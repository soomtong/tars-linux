# RF-M0 — 브랜치 리뷰 지적 고치기 (2026-11-22)

`/code-review high`(main..`app-layer-0-3`)가 낸 지적 아홉 가운데 여덟을 고친다. 아홉째(커밋 제목 길이)는 사용자가 고치지 않기로 했다
(2026-11-22). 새 기능은 없다 — 각 고침에 그 실패를 재현하는 host 검사를 하나씩 더하고, 끝에 루트 게이트 한 판.

## 맡기는 묶음 (Herdr 서브에이전트 둘, 같은 작업 트리 · 겹치지 않는 파일)

- `rf-tk` (toolkit): 1 · 8
- `rf-wl` (terminal): 2 · 3 · 4 · 5 · 6 · 7

## 고칠 것

1. `toolkit/src/kit/textfield.zig` `Model.replace` — 꼬리가 왼쪽으로 갈 때 `copyBackwards`가 아직 안 읽은 바이트를 덮는다(`"abcd"`, 캐럿 b 뒤
   Backspace → `"add"`). 왼쪽이면 `copyForwards`, 오른쪽이면 `copyBackwards`. 검사: 가운데 지우기 · 가운데 선택 바꾸기(짧게 · 길게).
2. `terminal/src/wl/server.zig` `apply` — sync 자식마다 재귀하는데 깊이 제한이 없다. `get_subsurface`가 부모 사슬이 이미 `TREE_DEPTH`면
   `bad_parent`로 거절한다(그리고 `apply`에도 깊이 상한을 둔다 — 두 겹).
3. `terminal/src/main.zig` `fullscreenRequest` · `leaveOwn`, `Server.setWorkspaceState` — 답 없는 길(갈 곳 없음 · strip 거절 · 상태 같음)에서
   지금 상태의 configure를 한 번 보낸다. carryover "CR-M2가 남긴 것"의 첫 줄을 닫는다.
4. `terminal/src/wl_logic.zig` `Positioner.complete` — anchor rect 0 × 0을 받아 놓고 완전성에서 거절한다. 완전성은 크기(`set_size`의 w · h > 0)와
   anchor rect가 설정되었는가로만 본다(vendored xdg-shell.xml에서 확인).
5. `terminal/src/wl/server.zig` `grabPress` — 안 보이는 창의 낡은 `last_fit`을 안쪽으로 센다. 이번 프레임에 그린 창만 센다.
6. `terminal/src/wl/server.zig` `xdg_popup.reposition` — 이미 닫은(`dismissed`) popup에 configure를 보낸다. 닫은 popup이면 보내지 않는다.
7. `terminal/src/main.zig` `startDictation` — fork한 자식이 SIGPIPE 무시를 물려받는다. execve 전에 `SIG_DFL`로 되돌리고 `pty.zig`의 주석을 고친다.
8. `toolkit/src/window/clip.zig` — 붙여넣기 MIME 고르는 순서가 서버(`wl_logic.PICK_ORDER`)와 다르다. 같은 순서를 따로 둔다.

## 끝나는 조건

- `make quick` 초록, 각 고침의 host 검사가 고치기 전 코드에서는 실패하고 고친 뒤 통과한다(서브에이전트가 보고).
- 루트 게이트 37/37.
- carryover의 해당 줄을 지운다.

## 결과

- 서브에이전트 `rf-tk`(Sonnet)가 1 · 8, `rf-wl`(Opus)이 2~7을 고쳤다. 둘 다 끝나고 pane 닫음.
- 더한 host 검사: toolkit `tk_test.zig`의 RF1 다섯 · RF8 둘, terminal `wl_logic_test.zig`의 다섯 묶음(positioner 0 × 0 · reposition · subsurface 깊이 ·
  fullscreen 답 · 그린 프레임), `pty_size_test.zig` 검사 4(execChild의 자식은 SIGPIPE 기본 처리). 고치기 전 동작에서 실패하는 것을 각 서브에이전트가 확인했다
  (toolkit의 선택 바꾸기 · Opt+Backspace 셋은 옛 코드에서도 통과 — 겹치는 바이트가 같은 값이라. 회귀 방지로 남김).
- 결정 셋:
  - 4: xml은 "non-zero anchor rectangle"이라 쓰지만 `set_anchor_rect`는 음수만 거절한다. 받은 값을 완전성에서 다시 거절하면 앞뒤가 어긋나므로
    "설정되었는가"(`anchor_set`)로 읽었다.
  - 5: 안 보이게 되는 자리(workspace 전환 · 스크롤 · 닫기)마다 `last_fit`을 지우는 대신 프레임 번호(`frame_no` · `painted_frame`)로 이번 프레임에 그린 창만 센다.
    grab popup이 있는 동안은 프레임이 늘 통째라 보이는 창은 모두 그려진다.
  - 6: 닫힌 popup의 reposition에는 `repositioned`도 보내지 않는다 — xml에서 그 이벤트는 configure 묶음의 일부다.
- 새 로그 줄 `wl> fullscreen id=N stays`(답만 하고 그대로).
- 루트 게이트 첫 판 36/37(`out/gate-logs/20261122-082618`): 빨간 것은 browser 체인 판정 3 — 첫 페이지가 60초 안에 열리지 않아 창 제목이 `Untitled - Chromium`에
  머물렀다(Chromium은 살아 있고 프로토콜 오류 없음, 그리기는 계속). 그 체인만 단독으로 다시 돌린 판은 판정 열셋 모두 통과(F11 왕복 포함) — 게이트 부하의 타이밍으로 본다.
