---
name: project_loose_ends
description: "이월 숙제 넷을 닫은 Loose Ends(LE-M0, 2026-10-27). 화면 쪽 copy mode가 가지치기 · 포커스 패널의 셸 종료로 닫히면 입력 모드도 normal(`input> mode reset`), `pointerMode` → `forceMode`, PTY winsize에 픽셀, carryover의 닫힌 항목 정리"
metadata:
  type: project
---

# Loose Ends (LE)

HANDOFF "다음 후보"의 `carryover.md`에서 실기 없이 닫을 수 있는 것을 사용자가 골랐다(2026-10-27). 설계는
`docs/specs/2026-10-27-tars-loose-ends-design.md`, plan은 `docs/plans/2026-10-27-tars-loose-ends-le-m0.md`.

## 무엇을 세웠나

- 입력 모드는 두 곳에 있다 — `input.State.mode`(App에 하나)와 `vt.Screen.copy_cursor`(패널마다). 키 밖의 이유로 화면 쪽만
  닫히는 자리가 둘이었다: 가지치기(PD design 위험 5)와 copy mode인 포커스 패널의 셸 종료(LE가 찾았다). 둘 다 `App.readPanes`
  안이고, 그 패널이 지금 워크스페이스의 포커스면 `App.resetInputMode`가 `terminal: input> mode reset from=copy|find`를 찍고
  `forceMode(.normal)`을 부른다.
- 다른 길로는 안 어긋난다 — copy mode 안에서는 copy 표가 `chord()`보다 앞이라 패널 · 워크스페이스 키가 안 닿고, 포인터는
  `.cancel`로 둘을 함께 닫는다. 세 번째 자리가 생기면 "키마다 두 모드를 대조"(design 결정 1의 (b))를 다시 본다.
- `pty.winsize(cols, rows, cell_w, cell_h)`가 `ws_xpixel` · `ws_ypixel`을 채운다(넘치면 0). `spawnPane` · `applyLayout`이
  `CELL_W` · `ROW_HEIGHT`를 넘긴다. 이미지 뷰어를 들일 때의 전제였다.
- `carryover.md`에서 닫힌 `[x]` 셋, 이미 `523c909`(2026-10-24)가 고친 `ntp:` 주석 항목, 이번에 닫은 둘을 지웠다.

commit은 design `724a7fd` · plan `32a0b10` · Task `e19acb0` · `a029839` · `6241824` · 닫기. 루트 게이트 22/22(9분 50초).

## 함정

- `pty_test`는 빌드만 되고 안 돈다(게스트용 fish를 exec). PTY를 호스트에서 보려면 `openpty` 쌍으로 — `pty_size_test`와
  호스트 target 번역 `c_pty_host`가 그 길이다.
- 체인은 `set -o pipefail`이다. `tlog | sed … | grep -q`는 `-q`가 일찍 나가 앞이 SIGPIPE를 받고 실패로 돌아온다 —
  `grep … >/dev/null`로 쓴다.
- 체인의 셸(fish)에는 `( … ) &`와 `$$`가 없다. "셸이 바쁜 동안 terminal 쪽 동작"은 포그라운드 `sleep 3; …` 중에 키를 치면
  된다(copy mode는 terminal 쪽이라 들어간다).
- 이름은 `forceMode`다. 지난 plan · design의 `pointerMode` 40곳은 기록이라 안 고쳤다.

관련: [[project_pointer_devices]] · [[project_copy_mode]] · [[project_workspace_panes]]
