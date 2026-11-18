---
name: project_strip_workspace
description: App Layer 1단 Strip Workspace(SW-M0~M3, 2026-11-19, 브랜치 app-layer-0-3). 패널 이진 트리를 column strip으로 바꾸고 viewport · 폭 preset `Cmd+R` · 빈 칸의 다음 column 이름을 더했다. 함정 셋 — 짝수 격자의 자리 폭은 scroll에 resize를 부른다, 부분 갱신의 "오른쪽 한 칸" 색은 layout이 정해야 한다, make check는 verify 잔상을 판정하지 않는다
metadata:
  type: project
---

Strip Workspace(SW)는 App Layer(0.3)의 1단이다(로드맵 `docs/plans/2026-11-18-tars-app-layer-roadmap.md`). design
`docs/specs/2026-11-18-tars-strip-workspace-design.md`(확인 1~15, 결정 1~26), plan `docs/plans/2026-11-18-tars-strip-workspace-sw-m0.md`
· `-sw-m1.md` · `-sw-m2.md` · `docs/plans/2026-11-19-tars-strip-workspace-sw-m3.md`. 사용자는 결정 가~라를 추천안 그대로 받고
나머지를 위임했다("주요 결정은 너의 의견에 따를 테니까"). 구현은 전부 Herdr 서브에이전트(`sw-impl`, Opus)가 했다
([[feedback_herdr_subagents]]).

## 모양

- `layout.Strip`: column 목록(고정 배열 8), column은 slot 번호 목록과 폭(`half` · `full` · `c80` · `c120`), 그리고 보이는 첫
  column `first`. 쓰지 않는 칸은 늘 0 — `main.zig`가 지난 프레임과 `std.meta.eql`로 견준다. 바깥 면(메서드 이름)은 WP의 트리와 같다.
- 폭: column 하나면 전체, 둘이 다 `half`면 `share(cols, 2, k)`(155 → 77 | 77, 154 → 76 | 77), 그 밖은 왼쪽부터 쌓는다. 셋 이상의
  `half`는 모두 왼쪽 반 폭이다. column 안 높이는 고르게(셋이면 15 · 15 · 15), column당 3.
- viewport: `first`부터 드는 데까지(전부 보이거나 전부 안 보인다). `reveal`은 가장 적게 옮기고, 그다음 왼쪽이 함께 들면 채운다.
- 키: `Cmd+D` 혼자면 반 · 반, 아니면 폭을 물려받는다. `Cmd+R` 폭 순환(80 → 120 → 절반 → 전체), 혼자면 `pane> width refused`.
- 상태 줄 `2/3` 칸은 보이지 않는 column이 있을 때만. 빈 칸 첫 줄에 다음 column 맨 위 pane의 전경 프로세스 이름
  (`TIOCGPGRP` → `/proc/<pgid>/comm`, `pty.foregroundName`).
- 로그: `strip> cols= focus_col= heights= view=a-b peek=<이름|->`, `peek> ink=`. `pane>` 줄은 그대로다 — `pointer/check.sh`가 그
  줄을 글자 그대로 견준다.

## 함정 — 다시 조사하지 말 것

1. 짝수 격자에서 왼쪽 반은 76, 오른쪽 반은 77이다. 셋 이상에서 column이 자리의 폭을 쓰면 scroll로 자리를 옮길 때 셸이
   resize된다. 셋 이상은 모든 column이 왼쪽 반 폭이고 끝 한 칸이 빈다(design 결정 13, `layout_test` 검사 23).
2. 부분 갱신(`paintPane` → `clearRows`)은 바뀐 줄을 지울 때 pane 오른쪽 한 칸도 칠한다. 그 색을 "격자 끝이 아니면 구분선"으로
   고르면 격자 끝에 안 닿는 마지막 column(80 · 120셀)의 오른쪽 여백에 구분선 색이 남는다. `Strip.separatorRight`가 정한다
   (`layout_test` 검사 28이 `separators()`와 견준다).
3. `make check`은 render verify 잔상(`verify> mismatch`)을 판정하지 않는다 — 루트 게이트만 한다. 그리기를 바꾼 milestone은 체인 뒤
   `lessons.md` "범용 명령"의 `grep … 'terminal: verify>'`를 기본으로 돌린다. SW-M3은 이것을 건너뛰어 루트 게이트에서 처음 봤다.
4. column 정보를 `pane>` 줄에 끼우면 `pointer/check.sh:611`이 깨진다 — 새 줄로 낸다.
5. column마다 높이를 따로 나누면 옆 column의 구분선 줄에 시작 줄이 떨어질 수 있다(한도 3 안에서는 5~9줄 격자에서만). 그래서
   `neighbor`는 WP 트리처럼 칸을 건너뛰어 `hit`에 묻지 않고 목록으로 고른다(검사 18).

## 남은 것

- 끄는 선택 중에 키로 viewport가 옮기면 누른 pane이 화면 밖일 수 있다(`clampInto`가 의미 없는 위치를 쓴다). 게이트 밖.
- 제목의 원천은 전경 프로세스 이름뿐이다. OSC 0/2 제목은 받아 두는 자리가 없다 — WY의 app pane은 `xdg_toplevel.set_title`을 쓴다.
- 픽셀 폭(R-SW-2)은 WY-M0에서 `Rect` 옆에 더한다(design 결정 3).

관련: [[project_app_layer_vision]] · [[project_branch_lines]] · [[feedback_herdr_subagents]]
