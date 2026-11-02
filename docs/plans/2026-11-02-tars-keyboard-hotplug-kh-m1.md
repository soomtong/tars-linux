# KH-M1 — 키보드를 포인터의 길로 연다

> 구현 파일은 Claude(또는 서브에이전트)가 넣고, lead가 diff를 실제 파일과 대조한 뒤 게이트 · commit한다. 줄 번호는 2026-11-02
> `ebcd813` 기준이라 낡을 수 있다 — 고치기 전에 `rg`로 다시 찾는다.

Goal: design 결정 1 ~ 7 · 9를 넣는다. 끝나면 부팅 뒤에 꽂은 키보드가 글자를 치고, 키보드가 여럿 동시에 열리고, 빠진 키보드는
닫히며 수정키가 풀리고(실측 4의 바쁜 루프가 닫힌다), 키보드 없이도 terminal이 뜬다. 체인 `keyboard/check.sh`는 M2다.

Architecture: 순수한 층(`pointer.zig`의 판정, `input.zig`의 `releaseHeld` · `BTN_MISC` 거르기)에 단위 검사를 먼저 붙이고,
`main.zig`는 키보드 칸 · 하나로 합친 여는 길 · `fds` 자리 · 닫기 · 로그만 바꾼다. init과 `shared/screen_args`는 안 건드린다
(비목표 2).

## Task 1: 순수한 층

1. `pointer.zig`에 `pub fn looksLikeKeyboard(caps: *const Caps) bool` — `EV_KEY`가 있고 `KEY_ESC`(1)부터 `KEY_D`(32)까지 다
   있다(결정 2). init `devices.looksLikeKeyboard`와 기준이 같다는 것을 주석에 적고, 비트맵 순서가 다르다는 것(`bitSet` 주석)도.
   `pointer_test`에 넷: 실측 5의 AT 키보드 · 전원 버튼 · ImExPS/2 마우스의 `key` 마지막 워드를 바이트 배열로 옮긴 것, 그리고
   글자가 하나 빠진 키보드(`KEY_D` 없음)는 아니다.
2. `input.zig`의 `State`에 `pub fn releaseHeld(self: *State) void` — 수정키 여덟을 거짓으로, `caps_tap` · `lctrl_tap`을 `.{}`로,
   `dictate_tap.reset()`(결정 4). 사람 쪽(`hangul_on` · `hangul_buf` · `commit_*` · `caps_lock` · `mode`)은 안 건드린다는 것을
   주석에 적는다. `input_test`에 셋:
   - Shift 누름 → `releaseHeld` → `a`는 `a`다.
   - 왼쪽 Ctrl 누름 → `releaseHeld` → 왼쪽 Ctrl 뗌은 한/영을 안 바꾼다(`hangul_on` 그대로).
   - 한글을 켜고 자음 하나 → `releaseHeld` → `preedit()`가 그대로다(S4).
3. `readKeys`의 루프에서 `EV_KEY` 다음에 `if (ev.code >= c.BTN_MISC) continue;`(결정 2). 이것은 fd를 읽는 함수라 단위 검사가
   직접 못 본다. 대신 거른 자리가 `handleKey` 앞이라는 것을 주석에 적고, `BTN_LEFT`(272)를 `handleKey`에 넣으면 지금 무엇이
   되는지(`markTapConsumed` · `dictate_tap.reset`)를 검사 하나로 고정해 둔다 — 거르기가 왜 필요한지의 증거다.

판정: 컨테이너에서 `zig build test`(terminal), 호스트에서 `make quick`.

## Task 2: `main.zig` — 키보드 칸과 하나로 합친 여는 길

1. `KeyboardDev { fd, path, path_len }`와 `MAX_KEYBOARDS = 8`(결정 5). `App`의 `keyboard_fd`를
   `keyboard_devs: [MAX_KEYBOARDS]?KeyboardDev = @splat(null)`로 바꾼다.
2. `tryOpenPointer`를 `tryOpenInput(ptrs, kbds, name)`으로 바꾼다. 한 번 열어 `readCaps` · 이름을 읽은 뒤:
   - 포인터 판정은 지금 그대로다(`pointer>` 줄도 그대로 — 결정 6, `pointer/check.sh` 558행).
   - `looksLikeKeyboard`면 키보드 칸에 넣는다. 포인터이기도 하면 키보드 쪽은 `open`을 한 번 더 한다. `dup`은 안 된다 — dup한 fd는
     open file description 하나를 나눠 이벤트 큐 하나를 둘이 빼앗아 읽는다. 키보드만이면 처음 연 fd를 그대로 키보드 칸에 넘긴다.
   - 경로 비교로 두 번 열기를 막는 것은 칸마다다(위험 5). 키보드 칸에 이미 있는 경로면 키보드 쪽만 건너뛴다.
   - 키보드 fd에 `EVIOCSCLOCKID` `CLOCK_MONOTONIC`(결정 9). 실패면 `keyboard> clock {path} error=…`.
   - 줄: `terminal: keyboard> open {path} name={name}`, 칸이 차면 `keyboard> skip {path} full name={name}`(결정 6).
   - 키보드 fd도 `O_RDONLY | O_NONBLOCK | O_CLOEXEC`(결정 1).
3. `scanPointers` → `scanInputs`, `drainUevents`도 키보드 칸을 함께 넘긴다. `ENOBUFS`의 다시 훑기도 같다.
4. `closeKeyboard(kbds, slot, state)` — 줄 `keyboard> close {path}`, `close`, `state.releaseHeld()`, 칸 비우기.
5. `openKeyboard`를 `readArgs`로 바꾼다 — argv를 풀어 돌려주기만 하고 장치를 안 연다. `FATAL` 갈래와 `terminal: opened` 줄이
   사라진다(결정 6 · 7). `input.openDevice`는 쓰는 곳이 없어지면 지운다.
6. `openPointers`(준비 4)의 처음 훑기 뒤에 키보드 칸이 0이면 `terminal: keyboard> none` 한 줄(결정 7). 이름을 `openInputs`로.

## Task 3: `main.zig` — poll 자리와 읽기 · 닫기

1. `fds`의 자리를 `[0]` uevent · `[1..kbd_end]` 키보드 · `[kbd_end..pty_base]` 포인터 · `[pty_base..pty_end]` PTY · 받아쓰기 둘로
   바꾼다(결정 5). 크기는 `1 + MAX_KEYBOARDS + pointer.MAX_DEVICES + MAX_WORKSPACES * layout.MAX_LEAVES + 2`. `fd_kbds`를 더하고,
   `fds` 문서 주석의 자리 설명을 고친다. 숫자로 자리를 쓰는 곳(`fds[0]` · `fds[1]` · `fds[2..` · `nfds - 2`)을 전부 이름 있는 경계로
   바꾸고, 끝나면 `rg 'fds\[[0-9]'`에 `fds[0]`(uevent) 하나만 남는지 본다(위험 4).
2. `tick`의 `if (self.fds[0].revents & c.POLLIN != 0) try self.readKeyboard();`를 키보드 칸 순서의 루프로 바꾼다. `POLLERR` ·
   `POLLHUP`이면 읽지 않고 `closeKeyboard`. 아니고 `POLLIN`이면 `readKeyboard(fd)` — read가 `ENODEV`(또는 0)이면 닫는다. 그래서
   `input.readKeys`는 "장치가 사라졌다"를 돌려줘야 한다. `Keys`에 `gone: bool`을 더하거나 n ≤ 0과 `EAGAIN`을 가르는 결과를 둔다
   — 구현 때 더 작은 쪽을 고른다. `EAGAIN`은 빈 배치다(논블로킹이 됐으므로).
3. `readKeyboard`는 fd 하나를 받는다. 머리에서 포커스를 잡는 것은 그대로다 — 키보드마다 다시 잡으므로 앞 키보드가 바꾼
   워크스페이스를 뒤 키보드가 본다(결정 5).
4. 닫기는 uevent보다 먼저다(PD와 같은 이유 — 빠진 번호가 곧바로 다시 쓰인다). `readPointers`가 포인터 칸을 닫은 뒤 uevent를
   읽는 순서이므로, 키보드 루프가 그보다 앞인 지금 자리면 저절로 맞다. 그 사실을 주석 한 줄로 적는다.

## Task 4: 체인의 표지와 문서

- `terminal/check.sh`(113행) · `input/check.sh`(132행)의 진단 목록 `terminal: opened /dev/input/event` →
  `terminal: keyboard> open /dev/input/event`.
- `rg -n 'terminal: opened'`로 남은 자리가 없는지 본다(체인 · 문서 · 주석). `main.zig` 준비 순서의 문서 주석("로그의 순서")을
  고친다 — `opened`가 빠지고 `keyboard> open`이 `clipboard scope=` 뒤로 간다.
- `running-tars.md`의 블루투스 절 725 ~ 726행("키보드는 아직이다")을 고친다. 입력 장치 절에 "키보드는 부팅 뒤에 꽂아도, 여럿
  꽂아도 된다 · 한/영과 조합은 모든 키보드가 하나를 쓴다 · 장치마다 다른 `keyboard=`는 없다(비목표 1)" 세 줄.

## Task 5: 게이트와 커밋

1. `make quick` → 컨테이너 `zig build test`(terminal).
2. 루트 게이트(23체인, 약 10분 30초). 키보드 경로를 쓰는 체인이 전부라(`input` · `hangul` · `dictation` · `power` · `tools` …) 이
   milestone이 놓친 자리는 여기서 빨개진다. 바뀌는 로그는 `terminal: opened`가 빠진 것 하나뿐이어야 한다.
3. 손으로 하나: KH-M0의 부팅 C(scratchpad `kh/run.sh C`)를 다시 돌려 `device_del k0` 뒤 CPU 틱이 1초에 거의 안 느는지 —
   실측 4가 닫혔다는 첫 증거. 체인(M2 결정 8의 6)이 나중에 같은 것을 본다.
4. design에 M1 결과(바뀐 결정이 있으면), commit, M2 plan.

## 시간

코드 약 150 ~ 250줄(대부분 `main.zig`). 루트 게이트 약 11분.
