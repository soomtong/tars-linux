---
name: project_status_band
description: "상태 줄 띠(격자 아래 1280 × 28)를 매 프레임 지우고 쓰던 것을 내용이 바뀐 프레임과 통째 프레임에만 하게 바꿨다 — Status Band(SB-M0, 2026-10-30). 메모 하나(StatusMemo)가 띠 다시 그리기와 status> 덤프를 함께 정하고, 판정은 DR의 verify 그대로. 키 하나의 그리기 0.92 → 0.42ms(overlay 0.22 → 0, present 0.36 → 0.27)"
metadata:
  type: project
---

# Status Band (SB)

HANDOFF "다음 후보"의 "상태 줄 띠의 부분 갱신(상한 0.22ms)"을 사용자가 골랐다(2026-10-30). Dirty Rows([[project_dirty_rows]])가 격자
안을 행 단위로 바꾸고 남긴 격자 밖의 한 자리다. design `docs/specs/2026-10-30-tars-status-band-design.md`, plan
`docs/plans/2026-10-30-tars-status-band-sb-m0.md`.

## 무엇을 세웠나

- 실제 경로(`App.render`)는 `renderOverlay`를 안 부르고 둘을 따로 한다 — 프롬프트는 `drawPrompt`(있으면 매 프레임, 그 행은
  `paintPane`이 방금 지웠다), 띠는 `paintBand(…, full or frame.status_changed, &clips)`. `renderOverlay`는 둘을 차례로 부르는 "통째
  경로의 정의"로 남아 그림자(`verifyFrame`)만 쓴다 — 분기를 안 품는다.
- "바뀌었다"는 `StatusMemo` 하나다 — `text` 바이트 · `caps`(색만 바뀌는 칸) · `battery`(칸 전체, `std.meta.eql`). `dumpStatus`가
  `status>` 줄을 찍는 조건도 같은 답(`Frame.status_changed`)이다 — 그전에는 `dumpStatus`가 메모 넷을 따로 들었다. `sameBatteryCell`은
  지웠다.
- 단위는 띠 전체다. 바뀐 칸만 그리지 않는다 — 바뀌는 프레임이 드물고(한/영 · CapsLock · 워크스페이스 · copy · 받아쓰기 · 배터리
  60초), 바뀐 프레임 하나의 비용이 0.22ms가 상한이라서다.
- 판정은 DR의 verify 그대로다. 그림자가 매 프레임 띠를 통째로 그리므로 띠를 잘못 건너뛰면 `mismatch rows=1 first=47`, clip을
  빼먹으면 `mismatch clip rows=1 first=47`. mutation 둘 다 hangul 체인의 Shift+Space 프레임에서 잡혔다 — (a)는 체인도 빨개졌지만 자리가
  CapsLock 홀드 검사(`on=0`)였고 검사 2의 `text=`는 메모가 찍어 초록이었다. (b)는 체인이 PASS다(픽셀은 맞다) — 루트 게이트의
  `check_verify_lines`가 빨갛게 만드는 자리.
- 숫자(같은 프로브, 부팅 3회 중앙값): 키 하나의 그리기 0.92 → 0.42ms(−54%, DR-M0의 2.45에서 −83%). `overlay` 0.22 → 0.001,
  `present` 0.36 → 0.27(띠 clip이 빠져 virtio-gpu의 경계 상자가 작아졌다 — 기대 밖의 몫). `seq`는 잡음 안. 남은 구간은 present 0.27 ·
  pane 0.16 · cells 0.07.

commit은 design `25e34ef` · plan `9c004ab` · Task 1 `7ab50e0` · 닫기. 루트 게이트 22/22, 11분 14초(prebuild 364 + lanes 308초), verify 8109프레임 전부 `ok`.

## 함정

- 띠는 이제 "마지막으로 그린 상태 줄"이 그대로 남는 자리다. 격자 마지막 행의 글리프가 아래로 삐져나오면 그 픽셀이 띠에 남고 그
  행을 다시 칠해도 안 지워진다 — verify가 `first=<rows>`로 잡는다. 그때는 띠를 지우는 조건에 "격자 마지막 행이 dirty"를 더한다.
- `sprite.restore`(화살표 되돌리기)가 띠 판정보다 앞이어야 한다. 뒤로 가면 띠를 건너뛴 프레임에서 화살표 밑에 저장된 픽셀이 낡는다.
- `dumpStatus`는 `render` 바로 뒤에서만 부른다(`dumpFrame`). 다른 자리에서 부르면 `status_changed`가 그 프레임의 값이 아니다.
- 통째 프레임(`full`)은 `renderBackdrop`이 띠도 지우므로 내용이 같아도 띠를 다시 써야 한다 — `paintBand`의 조건에 `full`이 있는 이유.

관련: [[project_dirty_rows]] · [[project_render_speed]] · [[project_input_status]] · [[project_battery_status]]
