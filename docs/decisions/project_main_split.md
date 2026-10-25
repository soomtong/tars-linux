---
name: project_main_split
description: "terminal의 main(1,072줄)과 init의 main(406줄)을 struct 하나(App · Boot)와 단계 함수로 나눈 Main Split(MS-M0~M1, 2026-10-25). 동작 · 로그 0줄 변경. 바퀴를 넘어 사는 값은 필드, 한 바퀴 안의 값은 지역 · Pointers · Frame · App은 값으로 돌려주므로 자기 포인터 금지, Boot는 argv · env가 가리키므로 포인터로만 · 검사는 로그 서식 집합 diff -w와 '지운 줄 가운데 새 파일에 없는 것' comm · 1,000줄 이동은 줄 번호로 자르고 Task마다 commit · probe anchor 넷"
metadata:
  type: project
---

# Main Split (MS)

2026-10-24 프로젝트 점검이 남긴 넷 가운데 추천 1순위를 사용자가 골랐다(2026-10-25). 설계는
`docs/specs/2026-10-25-tars-main-split-design.md`, plan은 `docs/plans/2026-10-25-tars-main-split-ms-m{0,1}.md`.

## 무엇을 세웠나

terminal의 `main`은 `App` struct의 `open`(단계 다섯: `openScreen` · `openKeyboard` · `spawnFirst` · `openPointers` · `openBattery`) →
`tick`(단계 열: `arm` → poll → `readKeyboard`(`runScrolls` · `runCopies` · `runPanes` · `runDictates`) → `readPointers` → `pollBattery` →
`wirePointer` → `readPanes` → `readDictation` → `decideFrame` → `render` → `dumpFrame`) → `close`가 됐다. init의 `main`은 `mountEarly` →
`Boot` 하나 → `readConfig` · `probeDevices` · `buildEnv` · `startHelpers` · `placeChildren` → `supervise`다. 두 `main`이 "단계 호출의
순서표"가 되어 "키보드 뒤 · PTY 앞" 같은 순서 주석이 한 함수에 모였다. 동작 · 로그 글자 · 프레임 수 · argv · env는 0줄 바뀌었고 체인
스크립트는 안 고쳤다. 새 파일은 없다 — 한 파일 안의 이동이라야 `git diff --color-moved`가 옮긴 줄을 전부 짝지어 준다.

## 결정

- 필드가 되는 것은 바퀴를 넘어 사는 값이다. 한 바퀴 안의 값(`ws` · `focus` · `round` · `want`)은 지역 변수거나 작은 struct(`Pointers` ·
  `Frame`)로 단계 사이를 건넌다. `ws` · `focus`는 단계마다 `self.current`로 다시 구한다 — MS 전 코드가 `current`를 바꾸는 자리마다
  `ws`를 다시 대입하던 것과 같다.
- `App`은 `open`이 값으로 돌려준다. 그래서 자기 필드를 가리키는 포인터를 두지 않는다 — `fd_panes`는 바퀴마다 `arm`이 다시 짓고 그
  바퀴 안에서만 읽는다. `Boot`는 반대다 — 자식의 argv · env 블록이 그 안의 버퍼를 가리키므로 `main`의 스택에 놓고 `*Boot`로만 건넨다.
  init은 힙이 없어 버퍼 필드는 `= undefined`로 시작하고 단계가 채운다.
- `Frame`은 프롬프트 · 상태 줄의 글자 버퍼를 품는다. `prompt.text` · `status_line.text`가 그 안을 가리키므로 `tick`의 스택에 두고
  포인터로만 건넨다 — `render`가 채우고 `dumpFrame`이 읽는다.
- 수명 주석("`main()`의 스택에 살고 `supervise()`가 영영 반환하지 않으므로")은 여섯 자리에서 `Boot`의 문서 주석 하나로 모았다.
  "주석은 옮기되 지우지 않는다"의 유일한 예외다. init의 `toggle_buf` 주석 "이 배열이 argv로도 간다"는 SA-M1 뒤로 거짓이라 지웠다.

## 함정 · 검사법

- 로그 서식 문자열 집합의 전후 비교는 `diff -w`여야 한다 — `rg -o 'logline\.print\(\s*"[^"]*"' --multiline`이 여러 줄짜리 호출에서
  다음 줄의 앞 공백을 잡고, 함수로 들어가면 들여쓰기가 한 단 얕아진다.
- "지운 줄 가운데 새 파일에(들여쓰기 무시) 없는 것"을 뽑는 `comm`이 옮기기 검사의 기계판이다 — 그 목록이 선언 → 필드, `self.` 접두사,
  `//` → `///`, `break`/`continue` → 반환값, `var` → `const`만이면 순수 이동이다. 사람이 읽을 때는 `--color-moved=dimmed-zebra
  --color-moved-ws=allow-indentation-change`와 `--word-diff`.
- 300줄 넘는 `Edit`은 한 글자 어긋나기 쉽다(M0 Task 3에서 실패). 새 본문을 파일로 쓰고 `sed -n`으로 줄 번호를 잘라 이어 붙이는 쪽이
  믿을 만하다 — 다섯 번 다 첫 시도에 컴파일됐다.
- 1,000줄 이동은 Task마다 commit 하나다(M0 넷 · M1 둘). 한 commit의 진한 줄이 읽을 수 있는 양이어야 한다는 것이 이유다. Task마다
  컨테이너 빌드 · 로그 집합 · 체인 하나(terminal · hangul · pointer · config · boot)를 거쳤고 루트 게이트는 milestone마다 한 번.
- `probe/patch.pl`은 소스를 글자로 찍는 유일한 스크립트다. anchor가 넷이 됐다 — 세는 값과 시계는 `App`의 필드, 시계의 원점은
  `openBattery`, 덤프 시간은 `dumpFrame`의 시작 시각부터(`frame_start`는 `render`의 지역이라 안 보인다). `main.zig`를 글자로 보는
  나머지 다섯(`make_initrd.sh` · `gate_lib.sh` · `input/check.sh` · `config/check.sh`)은 주석의 줄 번호 인용이다.
- `for` 안의 `continue`는 함수로 함께 가므로 뜻이 그대로다. 바뀌는 것은 `break :main_loop`(→ `readPanes`의 `.quit` → `tick`의
  `return false`)와 바깥 `continue`(→ `decideFrame`의 `.skip` → `return true`) 둘뿐이다.
- 수치 — terminal `main.zig` 3,889 → 4,123줄(+234, 필드 문서 주석 · 함수 머리), `tick` 39줄 · `main` 10줄, 가장 긴 함수는
  `spawnFirst` 151(주석이 대부분) · `runCopies` 122. init `main.zig` 1,472 → 1,526줄(+54), `main` 27줄, `placeChildren` 163.
