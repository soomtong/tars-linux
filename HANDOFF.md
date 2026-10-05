# HANDOFF: Pointer Devices(PD)가 M0~M4로 닫혔다 — 다음 서브프로젝트를 고른다

## 지금 어디인가

2026-10-05 사용자의 요청("마우스 장치 지원: 마우스 포인터 및 인터렉션(드래그 선택). 터치패드 역시 지원")으로 열어 같은 날
닫았다. 사용자는 결정권을 lead(Fable)에게 위임하고 자리를 비웠다. design은
`docs/specs/2026-10-05-tars-pointer-devices-design.md`(결정 11 · 위험 8 · 비목표 13 · 실측 15, `Status: 끝났다`), plan은
`-pd-m0.md` ~ `-pd-m3.md`이고 각 끝의 "실측한 것" 절이 값이다. 기억은 `docs/decisions/project_pointer_devices.md`.

사용자의 지시("계획 수립과 구현 방법 그리고 구현 작업에 목적에 맞는 모델을 사용하는 서브 에이전트를 할당")로 design과
plan 넷은 Opus 서브에이전트가, 구현은 M0 · M2 · M3을 Opus, M1(정해진 모양을 옮긴다)을 Sonnet 서브에이전트가 했다. Fable은
착수 전 실측 · 대조 · 루트 게이트 · commit · 결정을 맡았다. planner들이 plan 코드를 저장소 밖 사본에서 컴파일 · 체인 ·
mutation까지 돌린 뒤 `old_string` · `new_string`을 기계로 뽑아 넘기고(`anchors.py`), 구현자는 그것을 글자 그대로 넣었다 —
네 milestone 모두 plan 코드를 고친 곳이 없고 보고와 파일이 어긋난 자리도 없었다. 다음 milestone의 plan은 앞 milestone의
루트 게이트가 도는 동안 docker 금지 조건으로 미리 썼다.

| 커밋 | 무엇 |
|---|---|
| `0c2e6f5` | design |
| `8f8a030` | M0 — `pointer.zig`(`classify` · `Mouse` · `Pointer` · `ueventAddedNode`) · netlink uevent 핫플러그 · 장치 칸 여덟 · poll `pty_base` · `pointer>` 줄 · 열아홉번째 체인 `pointer/check.sh`(45488). 커널은 안 바뀌었다. 루트 게이트 19체인 3/3, 1시간 8분 39초 |
| `3b57b66` · `6f4dfb2` | 사용자의 결정 — 루트 게이트 반복 3 → 2(`feedback_gate_runs`), `check.sh`의 `RUNS=2` |
| `8dcf6f1` | M1 — 화살표(save-under, `ink` 118) · 보이는 조건 셋 · 휠 세 줄 · `layout.Tree.hit`. 구현 Sonnet. 19체인 3/3(마지막 3회), 1시간 8분 41초 |
| `e937b92` · `1ecb973` | M2 — `Gesture` · `copyEnterAt` · `copyPointTo` · `pointerMode` · 클릭 포커스 · 드래그 = copy mode · 뗌 = `copyYank` · clamp · 누른 채 휠(사용자 요청 1 끝). 19체인 2/2, 47분 46초. 그리고 `kernel/.config` 되접기(UW의 USB 무선 select 여덟) |
| `38bb649` | M3 — `touchpad.zig`(MT B · 탭 · 두 손가락 휠 · 물리 버튼) · 커널 심볼 41개(PS/2 · SMBus · I2C-HID · THC QuickI2C · uinput, +323,584바이트) · `pointer/replay/tp-replay`(uinput 가짜 패드) · 부팅 B(45489) 검사 19~25 · `install` 부팅 7 `delay_use=4`. 19체인 2/2, 49분 29초 |
| (이 커밋) | design Status · CLAUDE.md 표 · 기억 · MEMORY.md · HD/WP/CM/IP/TF 비목표에 한 줄 · running-tars.md · lessons(PD-1~7 · 이월 숙제 · 핵심 파일 · 포트) |

PD가 남긴 가장 큰 사실은 커널이 아니라 게이트의 것이다. M0에서 `CONFIG_INOTIFY_USER=y`를 켰더니 `FSNOTIFY`가 따라 켜진
커널이 TCG에서 initramfs 풀기를 1.2초 늦춰 `install` 체인 부팅 7의 창(`usb-storage.delay_use=3`)을 닫았고 루트 게이트가 두 번
빨갰다 — inotify를 버리고 netlink uevent로 갔다. M3이 커널 심볼 41개를 켜며 같은 증상을 다시 겪고 진짜 원인을 찾았다:
드라이버가 아니라 코드 배치다(gzip `inflate_fast`가 페이지 경계를 넘으면 QEMU TCG가 번역 블록을 직접 잇지 못한다, `X86_INTEL_LPSS`
하나로 재현). 실기와 무관한 게이트 비용이고, 부팅 7의 `delay_use`를 4로 올려 여유를 900ms로 되돌렸다(lessons PD-3 · 이월 숙제).

열지 않은 것(design 비목표 13): 마우스 보고(SGR 1006 — 다음 서브프로젝트의 첫 후보, vim `mouse=a` · fzf · lazygit) · 더블클릭 ·
가장자리 자동 스크롤 · 절대 좌표 장치 · 뗀 뒤 반전 남기기 · 가속과 터치패드의 나머지 · `tars.conf` 항목(휠 방향 먼저) · 왼손잡이 ·
키보드 핫플러그 · Apple 트랙패드 · 패널 비율 드래그 · 시간 기반 숨김 · THC QuickSPI. 실기에서 볼 것 셋은 `running-tars.md`에
있다(`kind=` · 터치패드 출발값 셋 · 두 손가락 방향).

## PD-M4 — 마우스 보고(같은 날 덧붙인 milestone)

M0~M3을 닫은 직후 사용자의 결정("마우스 보고 기능은 지금 마일스톤에 이어서 M4 태스크로 진행하자. 같은 맥락이라 새로운
마일스톤으로 빼는 것이 합리적이지 않은 것 같아")으로 비목표 1을 결정 12 · PD-M4로 열어 같은 날 닫았다. design 절과 plan은
Opus planner가, 구현은 Opus가 했다.

| 커밋 | 무엇 |
|---|---|
| `1050b6f` | 다시 열기(design Status · HANDOFF) |
| `c29f3eb` | M4 — `pointer.Owner` · `Grab`(첫 누름이 주인) · `wheelRoute` · `Gesture.handOff` · `vt.mouseEncode`(ghostty `encodeMouse` 감싸개, 형식 다섯) · `wheelKeys`(모드 1007) · `input.State.modifiers` · `main.zig` 편집 열 · 게스트 vimrc `mouse=a ttymouse=sgr` · GE design 덧붙임 셋 · `pointer/check.sh` 검사 26~32(설정 디스크의 bash `read -N` 프로브 · vim 클릭) · 호스트 검사 OK 140 · 82 · 16 · 루트 게이트 19체인 2/2, 49분 56초 |
| (이 커밋) | 다시 닫기 — design Status · CLAUDE.md 표 `PD-M0~M4` · 기억 · MEMORY.md · lessons 이월 숙제 · HANDOFF |

규칙 하나로 가른다: 누른 패널의 자식이 모드 9 · 1000 · 1002 · 1003을 켰고 copy mode가 아니고 Shift가 없으면 자식의 것이다.
포커스가 아닌 패널이면 포커스를 먼저 옮기고 그 패널에 보고한다(tmux 순서). 휠은 copy mode면 무시 · Shift면 우리 스크롤 ·
자식이 원하면 버튼 4 · 5 · 대체 화면에 1007이면 화살표 키 세 번 · 그 밖은 우리 스크롤. 비목표로 남은 것은 design 14~18(1004
포커스 보고 · XTSHIFTESCAPE · OSC 52 · 가로 휠과 포인터 모양 · 보고 끄기 설정).

## 바로 다음에 할 것 — 새 서브프로젝트를 고른다

후보는 아래 PE 절의 "그 다음 후보"(ZU-M2는 ghostty의 Zig 0.17 전환 대기 · 패키지 매니저 · IPv6 · USB 동글 층 B · WP-M3 방향
포커스 · vim-runtime)와 PD의 비목표(더블클릭 단어 선택 · `tars.conf`의 휠 방향 · 포인터 가속)다. 작은 것은
`docs/guides/lessons.md`의 "이월 숙제"에 있다. 실기에서 볼 것 셋(`pointer> open`의 `kind=` · 터치패드 출발값 셋 · 두 손가락
방향)과 넷째(vim에서 클릭이 커서를 옮기나)는 `running-tars.md`에 있다.

### PD-M0~M3을 닫을 때의 "다음 후보"(M4 뒤에 유효)

후보는 마우스 보고(위), 그리고 아래 PE 절의 "그 다음 후보"(ZU-M2는 ghostty의 Zig 0.17 전환 대기 · 패키지 매니저 · IPv6 · USB
동글 층 B · WP-M3 방향 포커스 · vim-runtime)다. 작은 것은 `docs/guides/lessons.md`의 "이월 숙제"에 있다.

측정 파일(저장소 밖, 지워도 된다): `/tmp/run/mp0`(lead 실측) · `/tmp/run/pdm0` ~ `pdm3`(planner · 구현자 사본과 로그) ·
`/tmp/gate_pd0.log` ~ `gate_pd3.log`(루트 게이트 로그).

### 그 앞 — Paste Ergonomics(PE)가 M0~M2로 닫혔다


2026-10-04 GE를 닫은 직후 열어 같은 날 닫았다. GE가 남긴 둘(터미널의 bracketed paste · 사용자 vimrc
영속)에 루트 게이트를 흔들던 `service` 체인 경합 하나를 M0으로 묶었다. design은
`docs/specs/2026-10-04-tars-paste-ergonomics-design.md`(결정 9 · 위험 7 · 실측 10, `Status: 끝났다`),
plan은 `-pe-m0.md` · `-pe-m1.md` · `-pe-m2.md`이고 각 끝의 "실측한 것" 절이 값이다. 기억은
`docs/decisions/project_paste_ergonomics.md`.

사용자의 지시("계획 수립과 구현을 목적에 맞는 model을 선택하고 sub agents를 사용하여")로 design과
plan 셋은 Opus 서브에이전트가, 구현은 M0 · M2(이미 있는 모양을 옮긴다)를 Sonnet · M1(판단과 화면
판정을 새로 만든다)을 Opus 서브에이전트가 했고 Fable이 사실 조사 · 대조 · 루트 게이트 · commit을
맡았다. 이번에는 mutation도 구현자가 돌리고 Fable은 로그를 읽었다. 구현자는 전부 main 작업 트리에서
편집했다(루트 게이트와 겹치지 않게 순서를 두었다 — M2 planner만 M1의 게이트가 도는 동안 썼고, 그때
빌드 · QEMU · 저장소 편집을 금지했다).

planner들이 lead · design의 전제를 여럿 바로잡았다. 이것이 이 방식의 값이었다.
- M0: "부팅 C · D가 임대를 안 기다린다"가 아니라 셋 다 `boot_ssh`에서 기다리고 있었고, 원인은 dhcpcd가
  `leased`를 주소를 붙이기 전에 찍는 것이었다(lessons 실측 73). 이월 숙제의 진단이 틀렸던 것이다.
- M1: 꼬리 `ESC[201~`를 빠뜨리면 fish가 그 뒤의 키를 전부 삼킨다(mutation 3이 새 검사가 아니라 기존
  검사 11에서 잡혔다) · fish 4.0.2는 인자를 치는 중에 모드 2004를 끈다(design 위험 4에 덧붙였다) ·
  `cat` 아래의 에코와 출력 순서는 스케줄이 정한다(화면 모양 대신 개수로 판정).
- M2: `vim -e`가 `xterm-256color`에서 대체 화면에 찍어 출력이 사라진다(`-T dumb`, lessons 실측 74) ·
  `HOME=/`에서는 `~/.vimrc`가 아니라 `/.vimrc`로 찍힌다 · `seedOneFile`에 `O_TRUNC`가 없어 `.EXCL`만
  빼는 mutation은 잡히지 않는다(`.TRUNC`로 바꿨다). design 실측의 pyte가 대체 화면을 구현하지 않아
  첫째를 놓쳤다 — pyte로 잰 화면은 대체 화면에 대해 믿지 않는다.

| 커밋 | 무엇 |
|---|---|
| `d237fb2` | M0 — `service/check.sh`의 `boot_ssh`가 `leased` 뒤에 `eth0: adding default route via 10.0.2.2`를 30초까지 더 기다린다. 코드 0줄. 루트 게이트 대신 `service` 체인 5/5(1분 11~15초), 스무 로그 중 순서가 뒤바뀐 것 0 |
| `2c0443e` | M1 — `vt.Screen.pasteParts`(모드 2004를 보고 머리 · 본문 · 꼬리 셋) · `dumpPaste`가 `pty.write` 세 번, 로그 `clip> paste len=N bracketed=0\|1`(`len=`은 본문 그대로라 기존 판정 안 바뀜) · `vt_test` 93~96 · `copy/check.sh` 검사 21(fish 프롬프트에 두 줄 — Enter 전에 안 돌고 뒤에 둘 다 돈다) · 22(`cat` 아래 — 화면에 `[200~` 없음). mutation 넷 전부 빨감. 루트 게이트 18체인 3/3(1시간 7분 14초, M0의 기록도 됨) |
| (이 커밋) | M2 — initrd 링크 `/.vimrc -> config/vimrc` · `init`의 `VIMRC_SEED`(주석 21줄 843바이트) · `seedVimrc()` · `config_test`의 `expectVimrcSeed`(규칙 다섯) · `kernel/vim/vimrc` 주석 · `config/check.sh` 1차 셋(`vim -T dumb -e +scriptnames +qa` → `2: /.vimrc` · 에러 없음 · `>> /.vimrc` 되읽기) + 2차 하나(`+'set ts?'` → `tabstop=3`) · `tools/check.sh` `WANT`에 `.vimrc`. mutation 다섯 전부 빨감. 루트 게이트는 M2 plan 실측 7 |

열지 않은 것(design 비목표): 모드가 꺼진 갈래의 `\n` → `\r`과 제어 바이트 치환(`encodePaste`로 옮길
자리 — 클립보드가 화면 밖에서 오게 되면) · 감싸지 않는 여러 줄 붙여넣기를 막거나 묻는 것 · OSC 52 ·
`/.viminfo`를 `/config`로 · 큰 붙여넣기에서 `pty.write`가 멈추는 것(non-blocking 쓰기와 큐) · SLIRP의
SYN 재전송 시각 · vim의 계단을 게이트에서 보는 것 · fish의 확장 키 모드 · `tars.conf`로 bracketed
paste를 끄고 켜는 것.

### PE를 닫을 때 적어 둔 다음 후보(그대로 유효)

후보는 아래 "그 다음 후보" 절(ZU-M2는 ghostty의 Zig 0.17 전환 대기 · 패키지 매니저 · IPv6 · USB
동글 층 B)과 WP-M3(방향 포커스), GE가 남긴 `vim-runtime`(38MB — 문법 색 · filetype, syntax 파일 몇
개만 고르는 길과 함께)이다. 작은 것은 `docs/guides/lessons.md`의 "이월 숙제"에 있다 — PE-M0이
service 두 항목을 지워서 지금 그 목록에 체인 경합은 없다.

### 그 앞 — Guest Ergonomics(GE)가 M0 · M1로 닫혔다

2026-10-04 같은 날 PE 바로 앞에 닫았다. `which`(debianutils의 sh 스크립트, `copy_lib_deps`의 ELF magic
검사, M0 `a53f57b`)와 plugin · 런타임 없는 모던 시스템 vimrc(M1 `48431e7`). design은
`docs/specs/2026-10-04-tars-guest-ergonomics-design.md`, 기억은 `docs/decisions/project_guest_ergonomics.md`.
GE가 비워 둔 위험 2(autoindent 계단)와 비목표 2(사용자 vimrc) · 4(bracketed paste)를 PE가 채웠다.

### 그 앞 — Cursor Shape(CU)가 M0 · M1로 닫혔다

2026-10-04 같은 날 GE 바로 앞에 닫았다. 우리 렌더러가 DECSCUSR 모양 셋을 그리고(M0, `8d65077`),
게스트 vi를 `vim-tiny`(`-cursorshape`)에서 `vim.basic`으로 바꿔 시스템 vimrc 세 줄과 stub
`defaults.vim`을 initrd에 넣었다(M1, `9f97b4b`). 그 vimrc를 GE-M1이 넓혔다. design은
`docs/specs/2026-10-04-tars-cursor-shape-design.md`, 기억은 `docs/decisions/project_cursor_shape.md`.

### 그 앞 — Workspace Panes(WP)가 M0~M2로 닫혔다

2026-10-03 사용자의 요청으로 열어 2026-10-04에 닫았다 — "Cmd+1~9 workspace 전환, Cmd+D ·
Cmd+Shift+D pane split", 이어서 "Cmd+W로 닫기", "포커스 이동", "Cmd+T 새 탭". 모델은 iTerm2
그대로다: 워크스페이스가 탭(아홉까지), 각 워크스페이스는 패널을 이진 분할로 여덟까지, 패널
하나가 셸 하나(PTY · `vt.Screen` · 격자 안 사각형). design은
`docs/specs/2026-10-03-tars-workspace-panes-design.md`(`Status: 끝났다`), 기억은
`docs/decisions/project_workspace_panes.md`, plan은 `-wp-m0.md` · `-wp-m1.md` · `-wp-m2.md`이고
각 plan의 "실측한 것" 절이 값이다.

이 서브프로젝트는 설계를 Fable이, 구현을 Opus 서브에이전트가 했다(사용자의 지시). 서브에이전트는
commit하지 않고 diff · 로그만 보고했고, Fable이 파일 · 로그를 직접 대조한 뒤 commit했다. 세
milestone 모두 보고와 파일이 어긋난 자리는 없었다. 관찰: 서브에이전트가 mutation에서 plan의 구멍을
둘 찾아 검사를 스스로 더했다(`$COLUMNS` · `caps ink off=`) — 그것이 이 방식의 값이었다.

| 커밋 | 무엇 |
|---|---|
| `37798ad` | M0 — `layout.zig`(순수 트리) · `Pane` · `Workspace` · `spawnPane` · `paneOrigin`. 눈에 보이는 변화 0 |
| `ef0f0c3` | M1 — `Cmd+D` · `Cmd+Shift+D` · `Cmd+W`(SIGHUP, 닫힘은 EOF 경로 하나) · `Cmd+]` · `Cmd+[` · `Screen.resize` · `pty.resize` · 구분선 · `pane>` 줄 · 열여덟번째 체인 `pane/check.sh` |
| `778f5bb` | M2 — `Cmd+T` · `Cmd+1~9` · 상태 줄 `W2` 칸 · 워크스페이스 삭제 · 닫은 뒤 포커스를 형제로(`Tree.heir`). `pane/check.sh` 검사 열여섯 · 루트 게이트 18체인 3/3(1시간 4분 30초) |

열지 않은 것: WP-M3 방향 포커스(`Cmd+Option+화살표`, `Tree.neighbor` — design Milestone 절에
모양이 있다. 순환만으로 네 패널을 다니는 것이 불편해지면 연다) · 패널 간 클립보드 · 비율 조절.
사용자가 그대로 두기로 한 것: M1이 바꾼 `Cmd+Shift+←·→·Backspace`(Shift를 무시하던 것이 맨
키로 나간다).

### 그 앞 — Zig Upgrade(ZU)가 M1까지 왔다, M2는 ghostty의 Zig 0.17 전환을 기다린다

Zig 0.17.0이 나왔다(2026-10-03). 사용자의 다른 저장소(`_a-book/monorepo`, `3aad8cc`)는 같은 날
올렸지만 이 저장소는 ghostty가 막는다. `terminal`이 ghostty 소스를 패키지로 물고, ghostty의
`requireZig`가 major · minor 정확 일치를 요구한다. 업스트림 0.17 전환은 draft PR #14519 · 이슈
#14518에 있다(2026-10-02 개설, 0.16 때는 석 달 반 걸렸다).

사용자의 결정: 0.16에서 고쳐도 되는 것만 지금 고치고, ghostty가 0.17로 가면 그때 마무리한다.
design은 `docs/specs/2026-10-03-tars-zig-upgrade-design.md`(결정 5 · 위험 3 · 실측 1~5), plan은
`-zu-m0.md` · `-zu-m1.md`다.

| 커밋 | 무엇 |
|---|---|
| `a4953c0` | M0 — 배열 곱 `**` 25줄 → `@splat`(0.17이 문법을 없앴다) |
| `1a71c6c` | M1 — `@cImport` 다섯 → translate-c 패키지(ghostty가 0.16에서 쓰는 `80f8b6e` 판). fortify를 끄는 자리가 셋에서 `c_poll` stub 헤더의 `#undef` 하나로 줄었다 · 루트 게이트 17체인 3/3(1시간 1분 50초) |

0.17 컴파일러로 `ast-check`하면 `init` · `terminal/src` 오류가 0줄이다. 남은 것은 0.16에 없는 이름
(`@backingInt` · `std.lang`)과 버전 줄뿐이다.

### 그 사이 — Copy Indicator(CI)가 M0 하나로 닫혔다

2026-10-03 사용자의 요청 한 줄("copy mode에 있을 때 맨 아랫줄에 표시를")로 열고 같은 날
닫았다. copy mode에 있는 동안 상태 줄(IS) 꼬리에 다섯째 칸 `COPY`가 뜨고 Esc로 나가면
사라진다. 앞 넷은 안 움직이고, 색은 전용 `STATUS_COPY`라 `caps ink` 판정이 그대로 산다.
`status.zig`는 `vt.zig`를 모른 채 `copy: bool` 하나를 더 받는다.

design은 `docs/specs/2026-10-03-tars-copy-indicator-design.md`(결정 6 · 위험 3 · 실측 1~6),
plan은 `-ci-m0.md`, 기억은 `docs/decisions/project_copy_indicator.md`다. 새 체인은 없고
`copy/check.sh`가 검사 2a · 6a(글자와 픽셀을 짝으로)를 더했다. mutation(`st.copy` 무시)은
`text=`가 맞는데 `ink=0`으로 잡혔다 — 글자만 보는 판정이었으면 통과했을 고장이다.
루트 게이트 17체인 3/3 PASS, 약 1시간 2분(2026-10-03). 커밋 `362e36d`.

사용자가 요청에 적은 진입 키는 `Cmd+Shift+V`였지만 실제 진입 키는 `Cmd+Shift+C`다
(`Cmd+V`는 붙이기). 코드 기준으로 진행했다.

### 그 앞 — Terminal Graphics(TG)가 M3로 닫혔다

TG가 2026-10-03 하루에 M0~M3로 닫혔다(design `Status: 끝났다`). 자식이 kitty graphics로 보낸
이미지를 우리 렌더러가 그린다. 해석과 저장은 ghostty vt가 하고, 우리 몫은 셀 픽셀 크기 알리기 ·
placement를 픽셀 사각형으로 바꾸기(`vt.zig`) · 그리기(`image.zig`) · PNG 디코더(`png.zig`,
`stb_image`)다.

design은 `docs/specs/2026-10-03-tars-terminal-graphics-design.md`(결정 7 · 위험 3 · 실측 1~9),
plan은 `docs/plans/2026-10-03-tars-terminal-graphics-tg-m0.md` ~ `-tg-m3.md`, 기억은
`docs/decisions/project_terminal_graphics.md`다.

| 커밋 | 무엇 |
|---|---|
| `b90a7d0` | design · M0 실측(코드 0줄) |
| `4cda837` | M1 — `CellPx` · `Screen.images()` · `vt_test` 65~74 |
| `a8a68d0` | M2 — `image.zig` · `render()`의 층 셋 · `render` 체인 검사 15~18 |
| `cc934d9` | M3 — PNG(`stb_image`) · `vt_test` 75~77 · 검사 19 · mutation · 루트 게이트 · 문서 |

새 체인은 없다. 루트 게이트 17체인 3/3(1시간 1분 25초, `FAIL` 0줄, 2026-10-03). mutation(PNG
디코더 설치 줄 빼기)은 `vt_test` 75가 부팅 전에 잡았다.

superpowers 없이 연 첫 서브프로젝트였다. 관찰은 `docs/decisions/feedback_superpowers_off.md`
끝에 있다 — plugin이 막았을 누락은 못 봤다.

### 그 다음 후보 — 새 서브프로젝트를 고른다 (ZU-M2는 ghostty 대기)

WP-M3(방향 포커스)은 맨 위 절에 있다. 아래는 ZU-M2와 그 밖의 후보에 대한 메모다.

ZU-M2를 여는 신호는 ghostty main의 `build.zig.zon`이 `minimum_zig_version = "0.17.0"`이 되는 것이다
(`curl -sSL https://raw.githubusercontent.com/ghostty-org/ghostty/main/build.zig.zon | rg minimum_zig`).
태그 릴리즈는 기다리지 않는다 — SHA로 고정한다. M2가 할 것은 design의 Milestone 절에 있다:
`Dockerfile`의 `ZIG_VERSION` · `vendor_libghostty_vt.sh`의 `GHOSTTY_SHA` · zon의 `minimum_zig_version`과
translate-c URL · hash(codeberg `875969d`) · 0.17 `zig fmt`(원래 있던 fmt 차이 61줄이 섞인다, 실측 2) ·
`std.builtin` → `std.lang` · "0.16"을 적은 문서들. 첫 일은 ghostty `src/terminal`의 API 변화 읽기(위험 2).
호스트 macOS의 0.17은 `~/.local/zig/zig-aarch64-macos-0.17.0/zig`에 있다(빌드는 컨테이너가 한다).

2026-10-03 다시 봤을 때도 신호는 없었다 — ghostty main은 `"0.16.0"`, PR #14519는 draft에 CI 실패
(`test` · `test-lib-vt`). 그 사이 호스트 `PATH`의 첫 `zig`가 `/opt/homebrew/bin/zig` 0.17이 됐다.
호스트에서 `terminal` · `init`을 직접 `zig build`하면 깨질 수 있으니 빌드는 계속 컨테이너에서 한다.

TG를 닫은 뒤 이미지 뷰어를 다음으로 열려 했다가 2026-10-03에 사용자가 접었다. 재 보니 Debian
`chafa`(1.14.5)는 바이너리가 190KB인데 재귀 `DT_NEEDED`가 sysroot에 없는 `.so` 69개, 44.6MB를
끌고 온다 — `libSvtAv1Enc` 7.8MB · `librsvg-2` 6.1MB · `libaom` 5.5MB · `librav1e` 3.2MB(AVIF ·
SVG 로더 때문) · glib · cairo · X11 · harfbuzz. RAM 위 initrd에 늘 얹기에는 크다.

사용자의 결정: 뷰어는 기본 이미지에 넣지 않고, 필요한 사람이 패키지 관리자(brew)로 설치하게
남긴다. 그래서 이 일은 후보 "패키지 매니저"의 본론이 된다. brew 쪽에서 확인한 사실:
- Homebrew `install.sh`의 `check_run_command_as_root`가 root이면 `Don't run this as root!`로
  멈춘다. 예외는 컨테이너 표지(`/.dockerenv` · `/run/.containerenv` · cgroup 이름)뿐이다.
  게스트는 전부 root다 — termium이 막힌 자리와 같다. non-root 사용자가 먼저다.
- 설치물은 디스크의 prefix(`/home/linuxbrew/.linuxbrew`)에 놓여야 한다. DI의 설치 디스크 위다.

어느 뷰어든 `pty.zig`의 `ws_xpixel` · `ws_ypixel`(지금 0)은 우리가 채워야 한다 — 이월 숙제에 있다.

남은 후보 — 패키지 매니저(위의 brew · non-root · 디스크 prefix) · IPv6(방화벽 표를 `inet`으로,
FW design 위험 6) · USB 동글 층 B. 작은 것은 `docs/guides/lessons.md`의 "이월 숙제"에 있다.

⚠ 이어받는 사람이 볼 것:
- Docker는 OrbStack이다. 소켓이 없다고 나오면 `orb start`.
- 새로 받은 저장소면 이미지부터 굽는다(Dockerfile 층 12, WL). 첫 빌드가 linux-firmware
  662MB를 `kernel/src/firmware/`에 받고 `clean()`이 안 지운다. TG-M3부터 `prepare.sh`가
  `stb_image.h`도 받는다(`terminal/vendor/`, 커밋 안 함).
- initrd는 두 archive다. `gzip -dc initrd.cpio | cpio -it`에 firmware가 안 나온다(lessons 62).
- 실칩 무선은 PCIe도 USB도 한 번도 안 떴다 — 실기와 실제 동글이 생기면 그것이 새 사실이다.

## 어디를 보면 되는가

2026-09-27에 이 파일을 193KB에서 줄였다. 서브프로젝트마다 쌓이던 "그 앞" 절들
(SD부터 LB까지)은 지웠다 — 각 서브프로젝트의 경과는 그 design의 실측 절과
`docs/decisions/`의 기억에 있고, 지운 원문은 `git show 76c668e:HANDOFF.md`로 본다.

| 무엇 | 어디 |
|---|---|
| 협업 규칙 · 끝난 서브프로젝트 표 | `CLAUDE.md` |
| 세션을 넘는 기억(색인) | `MEMORY.md` → `docs/decisions/` |
| 게이트를 돌리고 읽는 법 · 범용 명령 · 다시 조사하지 말 실측 · 안 되는 접근 · 이월 숙제 · 핵심 파일 지도 | `docs/guides/lessons.md` |
| 사람이 TARS를 띄우는 법 | `docs/guides/running-tars.md` |
| 서브프로젝트의 실제 상태 | `check.sh`의 `CHAINS` 배열(열여덟) |

새 세션은 `CLAUDE.md`와 `MEMORY.md`의 feedback 다섯, 그리고 이 파일의 위 절을
읽고 시작한다. 새 서브프로젝트가 닫히면 이 파일은 맨 위 절만 갈아 끼운다 — 옛
머리를 아래로 쌓지 않는다. 서브프로젝트를 넘어 유효한 것이 나오면
`docs/guides/lessons.md`에 더한다.
