# HANDOFF: Terminal Graphics(TG) M0이 끝났다 — 다음은 M1(`vt.zig`)

## 지금 어디인가

2026-10-03에 사용자가 후보 넷(터미널 그래픽 · USB 동글 층 B · IPv6 · 패키지 매니저) 중
터미널 그래픽을 골랐다. 자식이 kitty graphics로 보낸 이미지를 우리 렌더러가 그린다.
명령 해석과 저장은 ghostty vt가 이미 하고, 우리 몫은 셀 픽셀 크기 알리기 · placement를 화면
픽셀 사각형으로 바꾸기(`vt.zig`) · 그리기(`main.zig`)다.

design은 `docs/specs/2026-10-03-tars-terminal-graphics-design.md`(결정 7 · 위험 3 · 실측 1~5),
plan은 `docs/plans/2026-10-03-tars-terminal-graphics-tg-m0.md`다.

M0(제품 코드 0줄)이 잰 것:
- 저장은 된다. 한도는 320MB가 아니라 lib 기본 10MB라 결정 5를 "그대로 둔다"로 고쳤다.
- `width_px`가 0이면 이미지가 저장만 되고 안 놓인다. 커서 이동이 전송 순간에 정해지므로
  px는 `Screen.init`에서 채워야 한다(실측 2).
- 질의 답은 `\x1b_Gi=N;OK\x1b\` 모양으로 기존 `takeReplies` 길로 나간다. PNG는 `EINVAL`.
- 스크롤하면 viewport 기준 y가 음수로 나간다 — 잘라 그리거나 건너뛰어야 한다. 대체 화면은
  저장소가 따로다.

이 서브프로젝트는 superpowers 없이 진행하는 첫 번째다(`docs/decisions/feedback_superpowers_off.md`).
M0 plan · design은 plugin 없이 기존 형식대로 썼다. 빠진 것이 보이면 그 기억에 적는다.

## 바로 다음에 할 것 — TG-M1 plan을 쓰고 `vt.zig`를 고친다

design 결정 2 · 3: `Screen.init`이 셀 픽셀 크기(`CELL_W` · `ROW_HEIGHT`, 지금 `main.zig`에
있다)를 받아 `width_px` · `height_px`를 채우고, 화면에 보이는 placement를 "RGBA · 원본
사각형 · 목적지 픽셀 사각형 · 층(셋)"으로 내놓는 함수를 만든다. 모양은 ghostty
`renderer/image.zig`의 `kittyUpdate` · `prepKittyPlacement` 축소판이고 virtual placement는
뺀다. `vt_test`에 검사를 더한다.

⚠ 이어받는 사람이 볼 것:
- Docker는 OrbStack이다. 소켓이 없다고 나오면 `orb start`.
- 새로 받은 저장소면 이미지부터 굽는다(Dockerfile 층 12, WL). 첫 빌드가 linux-firmware
  662MB를 `kernel/src/firmware/`에 받고 `clean()`이 안 지운다.
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
| 서브프로젝트의 실제 상태 | `check.sh`의 `CHAINS` 배열(열일곱) |

새 세션은 `CLAUDE.md`와 `MEMORY.md`의 feedback 다섯, 그리고 이 파일의 위 절을
읽고 시작한다. 새 서브프로젝트가 닫히면 이 파일은 맨 위 절만 갈아 끼운다 — 옛
머리를 아래로 쌓지 않는다. 서브프로젝트를 넘어 유효한 것이 나오면
`docs/guides/lessons.md`에 더한다.
