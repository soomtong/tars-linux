# TARS Loose Ends — Design

Date: 2026-10-27
Status: design — 사용자 검토 전

`docs/guides/carryover.md`(이월 숙제)에서 실기 없이 닫을 수 있는 것을 묶는다(사용자가 2026-10-27에 골랐다). HANDOFF "다음
후보"의 "작은 것은 `carryover.md`에" 항목이다.

## 한 줄 요약

이월 숙제 넷을 닫는다. 그중 코드가 바뀌는 것은 둘이다 — (1) 화면 쪽 copy mode가 키보드 밖의 이유로 닫힐 때 입력 모드
(`input.State.mode`)도 `.normal`로 되돌린다, (2) PTY의 창 크기에 픽셀(`ws_xpixel` · `ws_ypixel`)을 채운다. 나머지 둘은 문서만
바뀐다 — 이미 고쳐진 `ntp:` 주석 항목과 닫힌 `[x]` 셋을 `carryover.md`에서 지운다.

## 배경

LS-M0(2026-10-26)이 `lessons.md`에서 `carryover.md`를 떼어 낼 때 글은 옮기기만 했다. 그래서 닫힌 항목과 이미 고쳐진 항목이
열린 항목 사이에 섞여 있다. 이 문서 스스로의 규칙("낡은 항목은 고치거나 지운다")이 지켜지지 않은 상태다.

열린 항목 대부분은 실기나 실제 장치가 있어야 판단할 수 있다(터치패드 출발값 · 늦은 내장 카드 · LAN 접속 · 무선 실칩 등). 그런
항목은 이번 범위에 넣지 않는다. 남는 것이 아래 넷이다.

## 착수 전에 확인한 것

2026-10-27, HEAD `442c6c9`.

1. `ntp:` 주석은 이미 고쳐져 있다. 항목이 말하는 TD 이전 문구("부팅할 때 한 번만 묻고")는 저장소의 코드 어디에도 없다. 고친
   commit은 `523c909`(2026-10-24, "update seed net/ntp comments")이다. 지금 문구("처음 세 번은 1초 넘게 틀리면 뛰고 그 뒤로는
   조금씩 당긴다")는 `init/src/clock.zig`가 쓰는 chrony 설정의 `makestep 1 3`과 맞는다. 이틀 뒤 LS-M0이 항목을 그대로 옮겼다.
2. `carryover.md`의 닫힌 `[x]`는 셋이다 — BV의 initrd 경합(GF-M0이 닫음), BS의 `dictation` B4 창(GF-M1), PD의 마우스
   보고(PD-M4). 셋 다 닫은 쪽의 기억(`project_gate_flakes` · `project_pointer_devices`)에 같은 내용이 있다.
3. 입력 모드는 두 곳에 있다(`input.State.pointerMode`의 문서 주석) — `input.State.mode`(키를 어떻게 해석하나, App에 하나)와
   `vt.Screen.copy_cursor`(그 화면이 모드인가, 패널마다). 키보드 경로는 둘을 같은 키에서 함께 바꾸고, 포인터 경로는
   `pointerMode`로 함께 바꾼다(PD design 결정 6).
4. 두 모드가 따로 움직이는 자리는 둘이다.
   - 가지치기. `vt.Screen.feed`가 선택의 앵커가 밀려난 것을 보거나, 검색 프롬프트 중에 대체 화면으로 갈아탄 것을 보면
     `copyExit`하고 `copy_pruned`를 세운다. `App.readPanes`는 `copyTakePruned()`로 그것을 받아 `copy> pruned` 로그만 찍는다.
     `input.State.mode`는 `.copy` 또는 `.find`에 남는다. PD design 위험 5가 적은 자리다.
   - 포커스 패널의 셸이 끝남. `readPanes`의 EOF 갈래가 패널을 닫고 `w.focus = w.tree.heir(..)`로 포커스를 형제에게 넘긴다.
     copy mode 중이었으면 `input.State.mode`는 `.copy`에 남고, 새 포커스 패널은 copy mode가 아니다. 이 자리는 carryover에
     없고 이번에 찾았다.
   - 둘 다 사람이 겪는 모양은 같다 — 다음에 친 글자가 copy 표(또는 검색 프롬프트)에 삼켜지고, `Esc`를 한 번 쳐야 셸에
     닿는다.
5. 다른 길로는 어긋나지 않는다. copy mode 안에서는 copy 표가 `chord()`보다 앞이라(`handleKey`의 1.5번 단계) 패널 명령과
   워크스페이스 전환 키가 닿지 않는다. 그래서 포커스가 아닌 패널이나 다른 워크스페이스의 패널이 copy mode인 채로 남는 일이
   없다. 포인터로 포커스를 옮기면 `.cancel`이 옛 포커스의 copy mode를 먼저 닫는다.
6. `pty.spawn`과 `pty.resize`는 `ws_xpixel = 0` · `ws_ypixel = 0`을 넘긴다. 같은 패널의 `vt.Screen`은 `CellPx{ CELL_W,
   ROW_HEIGHT }`를 받아 `width_px = cols × CELL_W`를 라이브러리에 준다(TG-M1). 그래서 `CSI 14t`의 답에는 픽셀이 있는데
   `TIOCGWINSZ`의 답에는 없다. 두 호출부는 `spawnPane`과 `applyLayout`이다.
7. `pty_test`는 빌드만 되고 실행되지 않는다. 게스트용 x86_64 fish를 exec하기 때문이다(`terminal/build.zig`의 `test` 단계
   주석). `zig build test`는 호스트 아키텍처로 돈다(컨테이너 arm64).
8. 실제 스크롤백 한도는 1,000줄이다(`vt.Screen.init`의 `max_scrollback_lines`). `seq 1 3000`이면 한 부팅 안에서 가지치기가
   난다 — `vt_test`의 "가지치기가 copy mode를 끊는다"가 같은 수로 본다.

## 결정

### 결정 1. 화면이 모드를 닫으면 입력 모드도 닫는다

`readPanes`의 두 자리에서, 그 패널이 지금 워크스페이스의 포커스였으면 `input.State`를 `.normal`로 둔다.

- 가지치기: `copyTakePruned()`가 참이고 `ref.ws == self.current`이며 `ref.leaf`가 그 워크스페이스의 포커스일 때.
- 셸 종료: 포커스를 `heir`로 옮기기 전에, 닫히는 잎이 지금 워크스페이스의 포커스이고 `key_state.mode != .normal`일 때.

`.normal`로 가는 함수는 이미 있다 — `pointerMode(.normal)`이다. `.copy` · `.find`에서 부르면 조합 중인 한글을 버리고(그 글자는
셸에 갈 글자가 아니다) 모드를 바꾼다. 돌려받는 바이트는 늘 비어 있다.

`.normal`인데 한글을 조합 중이었던 패널이 셸 종료로 닫히면 지금처럼 둔다. 조합은 형제 패널로 넘어간다. 이번 범위는 "모드가
어긋나는 것"이고, 그 경우는 모드가 어긋나지 않는다.

검토한 다른 길:
- (b) 키를 읽을 때마다 포커스 화면의 `copyActive()`와 `key_state.mode`를 대조해 맞춘다. 어긋나는 자리를 하나하나 찾지 않아도
  되지만, `input.zig`는 `vt.zig`를 모르고(IP design 결정 6) 대조를 `main.zig`의 키 경로에 넣어야 한다. 어긋남이 언제 생겼는지가
  로그에 안 남는다. 자리가 둘뿐이고 둘 다 이미 로그를 찍는 곳이라 (a)를 고른다.

### 결정 2. `pointerMode`의 이름을 `forceMode`로 바꾼다

부르는 쪽이 포인터만이 아니다. 받아쓰기(`insertDictation`)가 이미 부르고, 결정 1이 둘을 더한다. 이름이 "키가 아닌 것이 모드를
바꾼다"를 말하게 한다. 문서 주석의 "왜 이것이 필요한가"는 그대로 두고 부르는 자리 목록만 고친다. 호출부는 지금 넷이고 이름만
바뀐다.

### 결정 3. 로그

가지치기 자리는 이미 `copy> pruned`를 찍는다. 셸 종료 자리는 `pane> closed leaf=N`을 찍는다. 입력 모드를 되돌렸을 때만 둘
뒤에 `terminal: input> mode reset from=copy|find`를 한 줄 더 찍는다. 체인이 이 줄로 "되돌림이 일어났다"를 직접 본다.

### 결정 4. PTY의 창 크기에 픽셀을 채운다

`pty.spawn`과 `pty.resize`가 `vt.CellPx`를 하나 더 받아 `ws_xpixel = cols × cell.w`, `ws_ypixel = rows × cell.h`로 채운다.
`spawnPane`과 `applyLayout`이 `.{ .w = CELL_W, .h = ROW_HEIGHT }`를 넘긴다 — `vt.Screen.init`이 받는 값과 같은 출처다.
`spawnFish`(`pty_test`만 부른다)는 0을 넘긴다.

`pty.zig`가 `vt.zig`를 import하지 않게 `CellPx`를 쓰지 않고 `cell_w: u16, cell_h: u16` 두 인자로 받는 것도 가능하다. plan에서
import 관계를 보고 정한다.

곱이 `u16`을 넘는지 본다. 한 패널의 최대 크기는 화면 전체이고, 화면 폭이 65,535픽셀을 넘을 일은 없다. 그래도 곱셈은 `u32`로
하고 `std.math.cast`가 실패하면 0을 넘긴다(0은 "모른다"라는 뜻으로 지금과 같다).

### 결정 5. 검증

- 결정 1: copy 체인에 검사 하나. 셸에 "2초 뒤 `seq 1 3000`"을 백그라운드로 걸고 바로 copy mode에 들어가 `v`로 선택을
  시작한다. 로그에 `copy> pruned`와 `input> mode reset from=copy`가 나온 뒤 `echo LE_OK`를 치고 화면에 `LE_OK`가 나오는지 본다.
  고치기 전에는 `e`가 copy 표에 삼켜지므로 이 검사가 빨갛다.
- 결정 1의 셸 종료 자리: pane 체인에 검사 하나. 분할한 뒤 포커스 패널에 "2초 뒤 이 셸에 SIGHUP"을 백그라운드로 걸고 copy
  mode에 들어간다. `pane> closed`와 `input> mode reset from=copy` 뒤에 친 글자가 형제 패널의 셸에 닿는지 본다.
- 두 검사의 백그라운드 명령은 체인의 셸 문법을 따른다. fish에는 `( … ) &` 서브셸과 `$$`가 없다(`fish -c '…' &` ·
  `$fish_pid`). 어느 셸로 도는지는 plan에서 체인을 읽고 정한다.
- 결정 4: `zig build test`에 호스트 검사. `openpty`로 쌍을 만들고 `pty.resize`를 부른 뒤 `TIOCGWINSZ`로 되읽어 네 값을 본다.
  `pty_test`처럼 fish를 exec하지 않으므로 컨테이너의 arm64로 돈다. 게스트에서 `TIOCGWINSZ`의 픽셀을 읽을 도구가 없다(fish ·
  bash · zsh · `tq-probe.sh` 어느 것도 픽셀을 안 보인다) — 게스트 쪽은 `spawnPane` · `applyLayout`의 두 줄을 읽어서 확인한다.
- 루트 게이트 22/22.

### 결정 6. `carryover.md` 정리

- 지운다: 닫힌 `[x]` 셋, `ntp:` 주석 항목, 결정 1이 닫는 PD 위험 5 항목, 결정 4가 닫는 `ws_xpixel` 항목.
- BV 머리말은 그 아래 항목이 다 지워지므로 함께 지운다.
- 지운 항목은 이 design의 "착수 전에 확인한 것"과 git 히스토리에 남는다. 다른 곳으로 옮기지 않는다.
- HANDOFF의 "이미지 뷰어 메모" 셋째 줄(`ws_xpixel` · `ws_ypixel`을 우리가 채워야 한다)도 고친다.

## Milestone

하나다(LE-M0). Task 셋으로 나누고 Task마다 commit 하나를 둔다.

1. `carryover.md`에서 이미 닫힌 넷을 지운다(문서만).
2. 결정 1 · 2 · 3과 copy · pane 체인 검사.
3. 결정 4와 호스트 검사. 끝에 `carryover.md`에서 두 항목을 지운다.

루트 게이트는 Task 3 뒤에 한 번 돈다(약 12분).

## 위험

1. copy 체인 검사의 타이밍. `sleep 2` 안에 copy mode에 들어가 선택을 시작해야 한다. 늦으면 가지치기가 copy mode 전에 끝나고
   검사는 아무것도 못 본다 — 그 경우 로그에 `copy> pruned`가 없으니 "고쳐졌다"가 아니라 "검사가 못 밟았다"로 빨개진다.
   판정은 `pruned` 줄을 먼저 기다리고 그 뒤에 글자를 친다.
2. 게이트의 동시 부하에서 `seq 1 3000`이 길어질 수 있다. 출력은 copy mode 중에 아래로 안 내려가므로 화면을 흔들지 않는다
   (`scrollToBottom` 억제).
3. 픽셀을 채우면 그 값을 보는 프로그램이 다르게 동작할 수 있다. 지금 이미지에 있는 것 가운데 `TIOCGWINSZ`의 픽셀을 쓰는 것은
   찾지 못했다. 게이트의 render · image 체인이 그대로 초록이면 된다.

## 비목표

1. 실기가 있어야 판단할 수 있는 이월 숙제 전부.
2. `carryover.md`의 "닫아 둔 결정들"과 "IP-M2 · TR-M2가 남긴 것" 절의 정리. 그 절은 열린 숙제가 아니라 기록이다.
3. 이미지 뷰어를 들이는 것. 결정 4는 그 전제만 놓는다.
4. 결정 1의 (b) — 키마다 두 모드를 대조하는 것. 세 번째 자리가 생기면 다시 본다.
