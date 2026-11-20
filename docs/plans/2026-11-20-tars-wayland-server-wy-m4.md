# WY-M4 — 클립보드

Date: 2026-11-20
Design: `docs/specs/2026-11-19-tars-wayland-server-design.md`(결정 32~37), 요구사항 R-WY-6 · R-WY-8
Status: 끝(2026-11-20). 브랜치 `app-layer-0-3`.

## 확인(조사 `wy-m4`, 세션 scratchpad `wy-m4/research.md` — HEAD `34c721d`, SDL 3.2.10 소스)

- 셸 클립보드(`clipboard.zig`)는 바이트 하나(`?[:0]const u8`)이고 한도 · 인코딩 검사가 없다. 쓰는 입구는 `Clips.yank`(copy mode `y`) ·
  `Clips.release`(포인터 뗌) 둘, 읽기는 `Clips.paste`(`Cmd+V`, bracketed) · 검색창. 로그 `clip> len=N text=…`. OSC 52는 없다.
- app pane의 `Cmd+C` · `Cmd+V`는 표에 없어 evdev 46 · 47 + super로 앱에 간다 — 셸의 `Clips`를 안 지난다.
- `wl_data_device_manager` 최소 판은 1, 판 2가 `wl_data_device.release`를 더하고 판 3은 DnD 액션뿐. SDL3는 `min(3, v)`로 bind.
- `selection`은 키보드 포커스를 받기 바로 전과 포커스 동안 새 selection이 생겼을 때 보낸다.
- SDL3의 받기 · 내기는 둘 다 동기이고 파이프를 14 ms만 기다린다. SDL은 텍스트를 mime 다섯으로 offer하고, serial 0으로 `set_selection`을
  보내는 길이 있다.
- terminal은 SIGPIPE를 건드리지 않는다 — 읽기 끝을 닫은 클라이언트에 쓰면 terminal이 죽는다. 자식을 띄우는 자리는 `pty.spawn` 하나.
- 서버는 epoll fd 하나를 `main.zig`의 poll에 싣는다 — 파이프 · 타이머는 `EventLoop.addFd` · `addTimer`로 칸을 더하지 않고 실을 수 있다.

## 누가 무엇을 하나

구현은 Herdr 서브에이전트 `wy-m4`(Opus — 조사도 같은 에이전트)에 두 단계로. lead는 plan · 대조 · 게이트 · commit.

- 단계 A — protocol 뼈대와 앱 → 셸. 할 일 1~3.
- 단계 B — 셸 → 앱 · SIGPIPE · 체인. 할 일 4~6.

## 착수 전에 확정한 것

1. `scanner.generate("wl_data_device_manager", 2)`, global 판 2. data device 목록(키보드처럼 클라이언트로 고름)과 `release`.
2. source: `offer` mime 목록, 소멸 리스너. `set_selection`: 받아들이는 조건(결정 36 — 순수 함수 `wl_logic`), 옛 source에 `cancelled`, mime 고르기
   (결정 34의 우선순위, 하나도 없으면 `wl> selection ignored mimes=N`), `pipe2(O_CLOEXEC|O_NONBLOCK)` → `send` → 쓰기 끝 닫기 → 읽기 끝 `addFd` +
   2초 `addTimer`. 1 MiB 넘으면 `wl> selection too-big`, 기한이면 `wl> selection timeout`. EOF면 서버 사본 · `Event.selection`.
   중간에 source가 사라져 EOF면 받은 만큼 쓴다. 진행 중 읽기는 하나 — 새 `set_selection`이 오면 옛 읽기를 버린다.
3. `set_selection(null)`: 그 클라이언트가 지금 source의 주인일 때만 받고 서버 사본은 지우지 않는다. `start_drag` → source에 `cancelled`(source가 있으면).
4. App: `Event.selection` → `clipboard=shared`면 `Clips.shared`에 App 할당자로 `[:0]` 사본 `set` + `dumpClip`(같은 `clip>` 줄). `pane`이면 셸에 안 넣는다.
5. 셸 → 서버: `Clips.yank` · `Clips.release` 뒤 `shared`면 `srv.setClipboard(bytes)`(서버가 복사). 서버 사본 · 세대가 바뀌고 옛 source에 `cancelled`,
   포커스 클라이언트에 새 offer + `selection`.
6. offer: `data_offer` → `offer` × 4(`text/plain;charset=utf-8` · `text/plain` · `UTF8_STRING` · `TEXT`) → `selection`. 포커스가 바뀔 때마다 새 클라이언트의
   data device에 키보드 `enter` 앞에서. 클립보드가 비었으면 `selection(null)`. 옛 세대 offer의 `receive`는 fd만 닫는다.
7. `receive`: fd에 O_NONBLOCK, 요청 처리기 안에서 곧바로 쓰기, 다 쓰면 닫기, 남으면 writable `addFd`로 이어 쓰기(2초 기한). EPIPE는 조용히 닫는다.
   받은 fd는 서버가 닫는다(실측 3에서 소유를 확인).
8. SIGPIPE(결정 35): terminal 시작에 `SIG_IGN`, `pty.spawn`의 자식에서 exec 전 `SIG_DFL`.
9. 로그: `wl> selection from=<id> mime=<m>` · `wl> selection refused id=` · `wl> selection ignored mimes=` · `wl> selection too-big` · `wl> selection timeout` ·
   `wl> offer to=<id> len=N` · `wl> receive to=<id> mime=<m> len=N`.
10. `tars-wl-test`: `--copy TEXT`(C 키 누름에서 source · offer 넷 · `set_selection(그 serial)`, `send`면 쓰고 닫고 `wl-test> send mime= len=`, `cancelled`면
    `wl-test> cancelled`), `--paste`(selection offer를 기억, `wl-test> offer mimes=…`, V 키 누름에서 receive → EOF까지 → `wl-test> paste len=N text=…`,
    없으면 `wl-test> paste none`). 인자 칸을 늘린다. bind 판 2.

## 체인

wayland 부팅 1, 판정 22 뒤 · 9 앞(셸만 남은 자리):

23. 셸 → 앱. `echo wy23-clip` → copy mode(`Cmd+Shift+C` · `k` · `Shift+V` · `y`) → `clip> len=9 text=wy23-clip`. `tars-wl-test --follow-size --paste --copy
    wy24-app > /tmp/wl4.log &` → `wl> offer to=<id> len=9`. `Cmd+V` → `wl> receive to=<id> mime=text/plain;charset=utf-8 len=9`.
24. 앱 → 셸. `Cmd+C` → `wl> selection from=<id> mime=text/plain;charset=utf-8` → `clip> len=8 text=wy24-app`. `Cmd+Q`로 앱을 닫고(앱이 끝나도 붙는다)
    셸에서 `echo ` + `Cmd+V` + 엔터 → 화면에 `wy24-app` 한 줄. 클라이언트 로그 `paste len=9 text=wy23-clip` 1 · `send mime` 1(셸에서 grep → `c24-1-1`).

## 할 일

1. (A) 생성 · global · data device · source · `set_selection`(조건 · 고르기 · 파이프 · 한도) · `start_drag`. 순수 부분(mime 고르기 · 받아들이는 조건 ·
   한도)은 `wl_logic`에 호스트 검사.
2. (A) App의 `Event.selection` → `Clips.shared`.
3. (A) `tars-wl-test --copy`. 손으로(또는 저장소 밖 임시 스크립트) 판정 24의 앞 반을 한 번.
4. (B) `setClipboard` · offer · 포커스 앞 `selection` · `receive` 쓰기(이어 쓰기 포함).
5. (B) SIGPIPE, `tars-wl-test --paste`.
6. (B) 판정 23 · 24, 체인 머리 주석 · PASS 줄. 도움말 `docs/help/desk.md`에 "셸에서 복사한 것을 앱이 붙이고 앱에서 복사한 것을 셸이 붙인다,
   앱 안의 붙여넣기 키는 앱의 것(지금 Super+V)" 한 줄.
7. lead: 체인 · verify grep · 루트 게이트.

## 판정

- 호스트 검사, 체인 wayland · copy · pointer · display PASS(copy · pointer는 `clip>` 줄의 회귀), 루트 게이트 35/35, verify mismatch 0.

## plan에서 실측할 것

1. libwayland가 `send` 이벤트의 fd를 dup하는가(보낸 뒤 서버가 쓰기 끝을 닫아도 되는가), 클라이언트가 닫으면 EOF가 오는가.
2. 판 2에서 `start_drag`에 `cancelled`가 무해한가.
3. zig-wayland가 만든 이름과 `receive`의 fd 소유(서버가 닫는가).
4. SIGPIPE: receive 직후 읽기 끝을 닫는 클라이언트로 terminal이 살아 있는지, 셸에서 `SigIgn`의 0x1000 비트가 꺼져 있는지.
5. `receive`가 같은 dispatch 안에서 쓰이는지(로그 순서).
6. wayland 체인 단독 시간(판정 23 · 24 전후).

## 결과

구현은 `wy-m4`(Herdr, Opus — 조사도 같은 에이전트), lead는 대조 · 게이트 · commit.

1. 단계 A `d07b7ea`: `wl_data_device_manager` 2, source · data device · `set_selection`(gate · `cancelled` · mime 고르기 · 파이프 · `addFd` + 2초 `addTimer`
   · 1 MiB), `Event.selection` → `Clips.shared` + `clip>` 줄, `tars-wl-test --copy`. 체인 단독 terminal · wayland · copy · pointer PASS, verify mismatch 0.
   임시 스크립트로 판정 24의 앞 반: `Cmd+C` → `wl> selection from=1 mime=text/plain;charset=utf-8` → `clip> len=8 text=wy24-app`, 앱을 닫은 뒤
   셸 `Cmd+V`로 `wy24-app`이 그려진다.
2. 실측: libwayland는 `send`의 fd를 marshal에서 복제한다 — 서버가 곧바로 쓰기 끝을 닫아도 클라이언트가 쓰고, 닫으면 EOF가 온다. 파이프 fd는 새지
   않는다(첫 받기에서 anon_inode +1 — libwayland 루프의 공용 timerfd로 본다). SDL 3.2.10에는 `start_drag` 호출이 없다 — 판 2의 `cancelled` 길은
   이번 클라이언트가 안 탄다(런타임 확인 안 함).
3. plan과 달라진 것: 파이프는 `pipe2(O_CLOEXEC)` 뒤 읽기 끝만 비블록(두 끝 다 비블록이면 클라이언트 쓰기 끝도 비블록이 되어 EAGAIN을 안 다루는
   클라이언트가 64 KiB 넘는 글을 자른다). 0바이트 받기는 버린다(`wl> selection empty` — 실패한 클라이언트가 셸 클립보드를 비우지 않게).
   gate가 거절한 source에는 `cancelled`. 로그 `wl> selection len=` · `empty` · `cleared` · `dropped` · `kept scope=pane`을 더했다.
4. 단계 B `ca9f431`: `setClipboard`(셸 복사 → 서버 사본 · 옛 source `cancelled` · 포커스 offer), `setFocus`가 키보드 `enter` 앞에 offer, 늦은 `get_data_device`에도
   offer, `receive`는 처리기 안에서 곧바로 쓰고(`first=K`) 남으면 writable로 이어 쓴다. SIGPIPE는 `main` 앞에서 무시, `pty.spawn` 자식에서 되돌림.
   `tars-wl-test --paste` · `--paste-drop`(plan에 없던 시험 깃발 — 읽기 끝을 먼저 닫아 EPIPE를 결정적으로). wayland 판정 23 · 24 · 25(25는 plan에
   없던 SIGPIPE 판정 — terminal이 EPIPE에 살고, 셸의 `seq 1000000 | head -n1`이 141). 도움말 한 줄. 체인 단독 wayland 395초(+22초) · copy · pointer ·
   display · pane · terminal PASS.
5. 실측 5: Cmd+V 다음 줄이 `wl> receive … len=9 first=9` — 같은 dispatch 안에서 다 썼다. 창이 열리면 `wl> column` 바로 다음이 `wl> offer`(enter 앞).
6. 루트 게이트 34/35(prebuild 347초 + lanes 1,562초, `out/gate-logs/20261120-041131`), verify mismatch 0. 빨강 하나는 BT-M2 `btvirt` 간헐(carryover
   일곱 번째 — 이번엔 general protection fault) — 체인 단독 초록(3분 25초).

남은 걱정은 `docs/guides/carryover.md`의 "WY-M2 ~ WY-M4가 남긴 것" 절로 옮겼다.
