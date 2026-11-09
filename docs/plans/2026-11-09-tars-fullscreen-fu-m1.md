# FU-M1 — 전체 화면: 패널이 보내는 CSI 10 ; Ps t와 fakesteak 조각

Date: 2026-11-09
Design: `docs/specs/2026-11-09-tars-fullscreen-design.md`(2판, 결정 4의 셋째 · 5 · 7)
Status: 끝났다(2026-11-09)

## 착수 전에 확정한 것

plan을 쓰며 읽은 것(HEAD `cbac844`).

1. 패널 출력은 `readPanes`(`terminal/src/main.zig:4551`)의 `pane.screen.feed(out)`(`:4610`) 한 자리로 lib-vt에 들어간다. 이 루프는
   `fd_panes`(이 바퀴에 지은 패널 포인터 목록)를 돌고 있다. 루프 안에서 `setFullscreen`을 부르면 `applyLayout`이 모든 패널의 셀 버퍼를
   다시 잡는다 — 패널 포인터 자체는 그대로지만, 루프 도중에 다른 패널의 크기를 바꾸는 순서를 따로 따지고 싶지 않다. 그래서 루프 안에서는
   원하는 상태만 접어 두고, 루프가 끝난 뒤 한 번 `setFullscreen`을 부른다.
2. lib-vt의 XTWINOPS(`terminal/ghostty-src/src/terminal/stream.zig:2441`)는 첫 매개변수 10을 `else` 갈래로 보내 `logUnsupportedOnce`만
   하고 버린다(design 확인 7 그대로). 우리 훑기가 바이트를 그대로 넘기므로 lib-vt의 동작은 안 바뀐다.
3. `Pane` 구조체(`main.zig:1501`)는 기본값 있는 필드를 이미 여럿 갖는다. 새 필드에 기본값(`.{}`)을 주면 `spawnPane`의 struct literal
   (`:1693`)을 안 고쳐도 된다.
4. 순수 모듈 + 호스트 검사의 선례는 FU-M0의 `geometry.zig` · `geometry_test`(`terminal/build.zig:464`). 같은 모양으로 `winops.zig` ·
   `winops_test`를 둔다.
5. 게이트: 체인 `fullscreen/check.sh` 부팅 B는 판정 6에서 여백 상태(155×47)로 돌아온 같은 셸을 갖고 있다. 새 부팅을 늘리지 않고 판정 6과
   판정 7 사이에 판정 하나를 끼운다(부팅 한 번 ≈ 1분을 아낀다). fish의 builtin `printf`는 `\e`를 알지만 `\033`이 sh와 같아 그쪽을 쓴다.
6. fakesteak 조각 둘: `devlayer/files/fakesteak/etc/tars/rc.d/fakesteak.sh`(bash · zsh가 source) · `etc/fish/conf.d/90-fakesteak.fish`.
   둘 다 `fakesteak -b` 한 줄을 부른다. BB-M1의 `out/bb-m1/probe.sh`는 게이트의 `clean()`이 `out/`을 지워 남아 있지 않다 — BB-M1 plan
   Task 4의 절차로 다시 쓴다.

## Task 1 — `terminal/src/winops.zig`(순수 상태 기계)

```zig
pub const Scanner = struct {
    state: enum { ground, esc, csi, skip } = .ground,
    params: [2]u16 = .{ 0, 0 },
    count: u8 = 0,      // 지금까지 본 매개변수 칸 수(';'마다 하나, 첫 칸 포함)
    overflow: bool = false,

    /// bytes를 훑고, 그 안의 `CSI 10 ; Ps t`들을 차례로 `state`에 적용한 결과를 돌려준다.
    pub fn feed(self: *Scanner, bytes: []const u8, on: bool) bool
};
```

- 상태: `ESC`(0x1b) → esc, esc에서 `[` → csi(매개변수 초기화), 그 밖이면 ground(다른 ESC 시퀀스). csi에서 숫자는 지금 칸에 누적(넘치면
  `overflow`), `;`는 다음 칸, `t`는 끝 — 칸이 정확히 둘이고 첫 칸이 10이며 넘침이 없으면 Ps(0 끄기 · 1 켜기 · 2 바꾸기)를 적용. 다른
  끝 바이트(0x40–0x7e)는 ground. 개인 표지 · 중간 바이트(0x20–0x2f, `<=>?`)나 셋째 칸이 오면 skip — 끝 바이트까지 무시하고 ground.
- VT의 규칙을 따르는 자리: csi · skip 안의 `ESC`는 새 시퀀스를 연다. CAN(0x18) · SUB(0x1a)는 시퀀스를 버리고 ground. 그 밖의 C0
  (줄바꿈 등)는 시퀀스 안에서도 상태를 안 바꾼다.
- 빈 칸은 0이다(xterm과 같다): `CSI 10;t`는 끄기. 첫 칸이 비거나(`CSI ;1t`) 칸이 하나뿐(`CSI 10 t`)이면 무시 — design 결정 4의 "다른
  매개변수 수".
- 8비트 CSI(0x9b)는 보지 않는다 — UTF-8에서 그 바이트는 여러 바이트 글자의 일부다.
- 상태는 `feed` 호출 사이에 남는다 — read 경계에서 잘린 시퀀스를 이어 읽는다(design 결정 5).

## Task 2 — terminal에 잇기

- `Pane`에 `winops: winops.Scanner = .{}`.
- `readPanes`: 루프 앞에서 `var want = self.fullscreen`, `feed` 바로 앞(또는 뒤 — 바이트를 바꾸지 않으므로 같다)에서
  `want = pane.winops.feed(out, want)`. 루프가 끝난 뒤(`.quit`으로 나가지 않았을 때) `if (want != self.fullscreen) try self.setFullscreen(want)`.
  한 바퀴에 켜고 끄기가 함께 오면 접힌 결과만 남는다 — 화면이 두 번 다시 배치되지 않는다. 로그도 실제로 바뀐 한 번만 찍힌다.
- 루프 중간의 `break`(워크스페이스가 사라짐)도 루프 끝으로 오므로 그때까지 접힌 요청은 적용된다.
- 로그 줄은 FU-M0의 `fullscreen>` 그대로다. 누가 바꿨는지(단축키 · 시퀀스)는 줄에 넣지 않는다 — 게이트는 앞뒤 사건으로 구분한다.

## Task 3 — 단위 검사 `terminal/src/winops_test.zig`(`zig build test`)

- `\x1b[10;1t` 켜기, `\x1b[10;0t` 끄기, `\x1b[10;2t` 두 번 → 원래대로, `\x1b[10;t` 끄기.
- 무시(design 위험 3): `\x1b[10t`, `\x1b[1;10t`, `\x1b[10;1q`, `\x1b[10;1;0t`, `\x1b[?10;1t`, `\x1b[10;3t`, `\x1b[;1t`, `\x1b[99999;1t`.
- 잘림: `\x1b[10;1t`를 모든 자리에서 둘로 나눠 두 번 `feed` → 켜짐. 한 바이트씩 → 켜짐.
- 끼어듦: `\x1b[10\x1b[10;1t` → 켜짐(ESC가 새로 연다), `\x1b[10;\x181t` → 무시(CAN), `\x1b[10;\n1t` → 켜짐(C0는 안 끊는다).
- 한 덩이에 여럿: `\x1b[10;1tabc\x1b[10;0t` → 꺼짐, 그 사이 글자는 영향 없음.

## Task 4 — 게이트(체인 `fullscreen/check.sh`, 부팅 B의 판정 6과 7 사이)

판정 6.5 → 번호를 다시 매겨 판정 7, 지금의 7은 8.

- `printf '\033[10;1t'` → `wait_for_log 'terminal: fullscreen> on grid 160x50 origin 0,0'`(이 부팅의 둘째 on 줄 — 앞선 줄 수를 세어 늘었는지 본다).
- `printf '\033[10t'; printf '\033[1;10t'` 뒤 `echo w2-$LINES-$COLUMNS` → `w2-50-160`이고 `fullscreen>` 줄 수가 그대로(무시된 시퀀스가 아무것도 안 바꿨다).
- `printf '\033[10;2t'` → `fullscreen> off grid 155x47 origin 20,20` 줄이 하나 늘고 `ask_size` → `47 155`.
- 판정 8(`tars-config set` · `reload terminal`)은 여백 상태에서 시작해야 하므로 이 순서가 맞다.
- `check.sh`의 `CHAINS` 항목을 `"FU-M1:./fullscreen/check.sh"`로, PASS 줄에 시퀀스 한 마디.
- 판정: 체인 단독 2회, 그다음 루트 게이트.

## Task 5 — fakesteak 조각 둘(design 결정 7)

- 두 조각의 `fakesteak -b` 앞에 `printf '\033[10;1t'`, 뒤에 `printf '\033[10;0t'`. Ctrl+C는 전경 프로세스 그룹(fakesteak)에 가고 셸은
  다음 줄로 가므로 뒤 `printf`가 돈다. 주석에 FU-M1과 이유(상태 줄은 셸로 돌아온 사람을 위한 것) 한 줄.
- 조각은 납품 묶음의 파일이라 manifest · 묶음 빌드만 다시 돈다. 게이트 체인은 없다(BB design: 게이트는 smoke만).

## Task 6 — QEMU probe 한 판(저장소 밖 `out/fu-m1/probe.sh`, BB-M1 Task 4의 방식)

`make iso ISO_LAYERS="fakesteak"`(트리 clean) → 빈 NVMe에 설치 → NVMe만으로 부팅:

- 로그에 `terminal: fullscreen> on grid 160x50 origin 0,0`(autorun이 켰다), screendump 한 장 — 여백 없이 비가 화면 끝까지.
- monitor `sendkey ctrl-c` → `fullscreen> off grid 155x47 origin 20,20`, screendump 한 장 — 프롬프트와 상태 줄이 돌아왔다.
- 새 패널을 열어도 `fullscreen>` 줄이 늘지 않는다(autorun은 한 번).

## 비목표

design의 비목표. 데모 릴리스를 다시 내는 것(사용자가 말하면 BB-M1 Task 5의 모양으로).

## 결과

lead 직접. 커밋 `d3ea489`(Task 1~5) · `dbb6151`(조각 고침). `zig build test`의 `winops_test: 120 checks, all passed`, 빨강 하나(칸 수 조건을 빼면
`ESC[10t`가 켜진 화면을 끈다 — 검사가 그 줄을 짚었다). FU 체인 단독 2회 PASS(3분 0초 · 3분 2초). 루트 게이트 32/32(`make gate` 36분 23초 — 개발 도구 묶음 굽기 포함, prebuild 378초 + lanes 1,660초, 잘린 줄 0, `out/gate-logs/20261109-112727`).

판정 7의 로그 순서: `fullscreen> on`(printf `10;1t`) → lib-vt의 `ignoring CSI t with unimplemented parameter: ESC [ {1, 10} t` →
`fullscreen> off`(printf `10;2t`). lib-vt의 경고는 첫 매개변수 값마다 한 번만 찍혀(`logUnsupportedOnce`) `ESC[10t`의 경고는 안 보인다 —
바이트를 그대로 넘겼으므로 lib-vt도 같은 시퀀스를 여전히 보고 버린다(design 결정 5).

plan과 다른 자리:

1. 조각의 세 줄(`printf` · `fakesteak -b` · `printf`)이 한 줄 `sh -c 'trap : INT; printf …; fakesteak -b; printf …'`이 됐다. probe 첫 판에서
   Ctrl+C 뒤 화면이 전체 화면에 갇혔다 — fakesteak은 raw 모드가 아니라 Ctrl+C를 SIGINT로 받고, 대화형 fish는 전경 job이 SIGINT로 죽으면
   블록의 남은 명령을 취소한다(bash · zsh도 같다). 안쪽 sh는 빈 처리기(`:`, 무시 `''`가 아니다 — 무시는 자식에게 물려져 Ctrl+C가 안 먹는다)로
   살아남아 끄기를 찍는다. Task 5의 "뒤 printf가 돈다"는 틀린 짐작이었다.
2. 끄기 뒤에 `ESC[H ESC[2J ESC[3J`(clear가 보내는 것)를 붙였다. 둘째 판에서 160열 → 155열로 줄 때 비 세 줄이 다시 접혀 프롬프트 위에 남았다.
   같은 read 덩이면 지우기가 크기 바꾸기보다 먼저(Task 2의 접기), 다른 덩이면 나중에 — 어느 쪽이든 깨끗하다. 사용자(2026-11-09): "clean up them all".
3. probe(`out/fu-m1/probe.sh`, 51초): 설치 `fakesteak.sqfs 323584 bytes`, NVMe 부팅 `grid 155x47` → autorun `fullscreen> on grid 160x50 origin 0,0`,
   `sendkey ctrl-c` → `fullscreen> off grid 155x47 origin 20,20` · fakesteak 0개, 새 패널(`alt-d`)에 다시 안 뜨고 on · off 1줄씩.
   화면 `rain.png`(여백 없는 비) · `prompt.png`(프롬프트 하나와 상태 줄) · `split.png`.
4. 루트 게이트 첫 판이 입구 검사에서 멈췄다(2분 30초, 체인 0). `check.sh`의 조기 종료 grep 검사(`\|[^|]*\b(grep|rg)\b[^|]*-[a-zA-Z]*q`)가
   `tlog | grep -acE … )" -eq 3`의 `-eq`를 `-q`로 읽었다 — 오탐이지만 셈을 변수로 먼저 받게 고쳤다(`6884678`). `make check CHAIN=`은 이 입구
   검사를 안 거친다 — 체인 스크립트를 고쳤으면 루트 게이트 전에 그 정규식을 한 번 대 본다.
