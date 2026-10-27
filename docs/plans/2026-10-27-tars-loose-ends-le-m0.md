# LE-M0 — 이월 숙제 넷

Date: 2026-10-27
Design: `docs/specs/2026-10-27-tars-loose-ends-design.md`
Status: 끝났다(2026-10-27). Task마다 commit 하나(`e19acb0` · `a029839` · `6241824`). copy 검사 23 · pane 검사 9a ·
`pty_size_test`가 섰고 mutation 셋(되돌림의 `forceMode` 빼기 → copy 23 · pane 9a 빨강, `ws_xpixel`에 `* 0` → `pty_size_test` 빨강)이
전부 잡혔다. 루트 게이트 22/22(9분 50초, prebuild 298 + lanes 291초).

구현 중에 바뀐 것 하나 — pane 9a의 reset 판정을 처음에 `tlog | sed … | grep -aq`로 썼다가 빨갰다. `-q`가 첫 매치에서 나가 `sed`가
SIGPIPE를 받고 `pipefail`이 그것을 실패로 돌려준다. 같은 파일의 다른 판정처럼 `>/dev/null`로 바꿨다(코드 쪽은 맞았다 — 로그의
`pane> closed leaf=1` 바로 다음 줄이 `input> mode reset from=copy`였다).

## 이 milestone이 끝나면

- `carryover.md`에 닫힌 항목이 없다. 이번에 닫는 넷(`[x]` 셋 · `ntp:` 주석 · PD 위험 5 · `ws_xpixel`)이 빠진다.
- 가지치기나 포커스 패널의 셸 종료로 화면 쪽 copy mode가 닫히면 입력 모드도 `.normal`로 돌아온다. 그때
  `terminal: input> mode reset from=copy|find` 한 줄이 찍힌다.
- `TIOCGWINSZ`의 답에 픽셀이 있다(`cols × 8`, `rows × 16`).
- copy 체인 검사 23, pane 체인 검사 9a의 닫는 방법 변경, `zig build test`에 `pty_size_test`. 루트 게이트 22/22.

## 착수 전에 확정한 것

1. 체인의 셸은 fish다. 백그라운드 작업 대신 포그라운드 `sleep 3; …`를 치고, sleep이 도는 동안 Cmd+Shift+C로 copy mode에
   들어간다. copy mode는 terminal 쪽 기능이라 셸이 바빠도 들어간다. design 결정 5의 "셸 문법" 걱정이 여기서 사라진다.
2. copy 체인 검사 23은 검사 22 뒤(`cat`을 `ctrl-c`로 끝낸 fish 프롬프트)에 붙는다. `sleep 3; seq 1 3000`을 치고, copy
   mode에 들어간 것을 `copy> enter` 줄 수로 기다린 뒤 `v`로 선택을 시작한다(`copy_anchor_y`가 서야 가지치기 감시가 돈다).
   `copy> pruned` · `input> mode reset from=copy`를 기다리고, `seq`가 끝나 화면에 `3000`이 나온 뒤 `echo LE_OK`를 친다.
   판정은 `key>` 줄이 늘었고 화면에 `LE_OK`가 나온 것이다. 고치기 전에는 `mode reset` 줄이 없어 빨갛고, 그 판정을 건너뛰어도
   `e`가 copy 표에 삼켜져 `LE_OK`가 안 나온다.
3. pane 체인은 새 검사를 더하지 않고 검사 9a의 닫는 방법을 바꾼다. 9a는 패널 둘(포커스 1 = 오른쪽)에서 하나를 더 닫고, 남은
   패널에 `echo whole $COLUMNS`를 쳐서 155를 받는다. 닫는 키 `Cmd+W`를 "`sleep 3; exit`를 치고 copy mode에 들어간다"로
   바꾸면 그 타이핑이 그대로 "입력 모드가 돌아왔다"의 증거가 된다. Cmd+W의 닫기는 검사 6이 본다. 9a에 판정을 하나 더한다 —
   `pane> closed leaf=1` 뒤에 `input> mode reset from=copy`가 있다. 9b의 `exit_lines` 셈(`EXITS_BEFORE + 2`)은 셸이 한 번 끝나는
   것이 같으므로 그대로다.
4. 되돌림의 조건(design 결정 1). 가지치기: `ref.ws == self.current and ref.leaf == w.focus`. 셸 종료: 같은 조건을 `heir`로
   포커스를 옮기기 전에 보고, `key_state.mode != .normal`일 때만. 두 자리가 같은 일을 하므로 `App`에 메서드 하나
   (`resetInputMode`)를 두고 둘이 부른다. 메서드는 `mode`가 `.normal`이면 아무것도 안 하고, 아니면 로그를 찍고
   `forceMode(.normal)`을 부른다. "`.normal`이면 안 한다"를 두 자리 모두 이 메서드 안의 한 조건으로 둔다.
5. `forceMode`의 반환값(확정분 바이트)은 `.copy` · `.find`에서 늘 비어 있다(`input_test` 검사 64 · 65). `_ =`로 버린다.
6. 이름 바꾸기는 코드만이다 — `input.zig` 정의 하나, `main.zig` 다섯 자리(주석 하나 포함), `input_test.zig`의 호출 · 메시지 ·
   error 이름(`PointerMode*` → `ForceMode*`). `docs/`의 지난 plan · design 40곳은 기록이라 고치지 않는다.
7. `pty.zig`는 `vt.zig`를 import하지 않는다(무거운 ghostty-vt를 끌어온다). `spawn` · `resize`가 `cell_w: u32, cell_h: u32`
   두 인자를 받는다. `main.zig`의 `CELL_W` · `ROW_HEIGHT`가 `u32`다. 곱은 `u32`로 하고 `std.math.cast(u16, …) orelse 0`.
   구조체 조립은 순수 함수 `winsize(cols, rows, cell_w, cell_h) c.struct_winsize` 하나에 두고 `spawn` · `resize`가 부른다.
8. `pty_size_test`는 호스트 target으로 번역한 `c_pty_host`를 쓴다(`c_input_host`와 같은 길). `openpty`로 쌍을 만들고
   `pty.resize(master, 77, 47, 8, 16)` 뒤 slave에 `TIOCGWINSZ`를 걸어 `77 47 616 752`를 본다. 넘침 갈래(`cols = 9000`,
   `cell_w = 8` → 0)는 `winsize`를 직접 부른다. fish를 exec하지 않으므로 컨테이너 arm64로 돈다.

## Task 1: `carryover.md` 정리(문서만)

- 지운다: BV 머리말과 그 `[x]` 하나, BS의 `[x]`(dictation B4), PD의 `[x]`(마우스 보고), "미룬 것"의 `ntp:` 주석 항목.
- commit 하나.

## Task 2: 입력 모드 되돌림

- `input.zig`: `pointerMode` → `forceMode`. 문서 주석 첫 줄을 "키가 아닌 것이 모드를 바꾼다"로, 부르는 자리(포인터 ·
  받아쓰기 · 가지치기 · 셸 종료)를 적는다.
- `input_test.zig`: 확정 6.
- `main.zig`: 호출부 넷의 이름, `insertDictation` 주석, `App.resetInputMode`, `readPanes`의 두 자리.
- `copy/check.sh` 검사 23(확정 2), 머리 주석의 사슬에 한 줄.
- `pane/check.sh` 검사 9a(확정 3).
- `carryover.md`의 PD 위험 5 항목을 지운다.
- 확인: 컨테이너에서 `terminal` `zig build test`, `./copy/check.sh`, `./pane/check.sh`. commit 하나.

## Task 3: PTY 픽셀

- `pty.zig`: `winsize`, `spawn` · `resize`의 두 인자, `spawnFish`는 `0, 0`.
- `main.zig`: `spawnPane` · `applyLayout`이 `CELL_W, ROW_HEIGHT`를 넘긴다.
- `build.zig`: `c_pty_host`, `pty_size_test`, `test` 단계에 더한다.
- `pty_size_test.zig`: 확정 8.
- `carryover.md`의 `ws_xpixel` 항목, `HANDOFF.md`의 "이미지 뷰어 메모" 셋째 줄.
- 확인: `zig build test`. 그 뒤 루트 게이트(약 12분). commit 하나.
