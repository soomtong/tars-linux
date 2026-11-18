# SW-M3 — 폭 preset과 빈 공간의 제목

Date: 2026-11-19
Design: `docs/specs/2026-11-18-tars-strip-workspace-design.md`(확인 13~15, 결정 19~26)
Status: 끝났다(2026-11-19). 결과는 맨 아래. SW 서브프로젝트의 마지막 milestone. 브랜치 `app-layer-0-3`.

## 누가 무엇을 하나

구현은 Herdr 서브에이전트(`sw-impl`, Opus). lead는 plan · diff 대조 · 게이트 · commit. 서브에이전트는 commit하지 않는다.

고치는 파일:

- `terminal/src/layout.zig` · `layout_test.zig` — 폭 저장 · 풀기 · 쌓기 · viewport · 채우기 · `cycleWidth` · `peek`.
- `terminal/src/input.zig` · `input_test.zig` — `Cmd+R` chord.
- `terminal/src/main.zig` — `Cmd+R` 처리, 빈 공간의 제목 그리기, `strip>` 줄의 `peek=`, `3/7` 조건, `pane> width refused`.
- `pane/check.sh` — 16d · 16e의 `strip>` 정규식, 새 검사 16f · 9r.
- `docs/help/desk.md` — `Cmd+R`.

## 이 milestone이 끝나면

- `Cmd+R`이 포커스 column의 폭을 80셀 → 120셀 → 절반 → 전체 → 80셀로 돌린다. 셸은 새 폭으로 resize된다.
- 보이는 column 오른쪽에 빈 칸이 남고 그다음 column이 있으면, 빈 칸 첫 줄에 그 column의 전경 프로세스 이름(`fish`)이 흐리게 뜬다.
- 혼자인 column은 언제나 전체 폭이고 `Cmd+R`은 `pane> width refused`만 찍는다.
- 지금 게이트의 모양(폭을 안 바꾼 strip)은 한 글자도 안 바뀐다.

## 착수 전에 확정한 것

1. `Column`에 `width: Width = .half`(`enum { half, full, c80, c120 }`)를 더한다. 쓰지 않는 칸의 기본값도 `.half`라 `std.meta.eql`
   비교가 그대로 선다. `init`의 column도 `.half`다(혼자면 어차피 전체 — 결정 21).
2. 풀기(결정 19): `half` → `(cols-1)/2`, `full` → `cols`, `c80` → `min(80, cols)`, `c120` → `min(120, cols)`.
3. 배치(결정 21 · 22): column 하나면 전체. 정확히 둘이고 둘 다 `half`면 `share(cols, 2, k)`. 그 밖에는 `first`부터 왼쪽에서
   폭 + 구분선 1을 쌓아, `cols` 안에 드는 데까지 보인다. M2의 "셋 이상 모두 반 폭"은 이 규칙의 특수한 경우로 그대로 나온다
   (77 + 1 + 77 = 155, 짝수 격자는 끝 한 칸이 빈다).
4. `reveal`(결정 23): 왼쪽 밖이면 `first = c`, 오른쪽 밖이면 `c`가 보이는 가장 작은 `first`. 그다음 채우기(`first - 1`부터 지금
   보이는 끝까지가 함께 들면 `first -= 1`을 되풀이). `remove` 뒤에도 범위로 당긴 뒤 채운다. 돌려주는 값은 "`first`가 바뀌었나"
   그대로다.
5. 분할(결정 20): 혼자인 column에서 `.right`면 둘 다 `half`. 아니면 새 column이 포커스 column의 `width`를 물려받는다.
   `.right`의 크기 판정은 "새 column의 폭이 1칸 이상"이면 되므로 사실상 `cols ≥ 3`이다.
6. `cycleWidth(leaf) ?Width`: column이 하나면 null(거절). 아니면 `c80 → c120 → half → full → c80`로 바꾸고 새 값을 돌려준다.
   `main.zig`가 `reveal` · `applyLayout` · 다시 그리기를 한다. 거절이면 `pane> width refused`.
7. `peek() ?u4`(결정 25): 보이는 끝 column 오른쪽에 빈 칸이 1칸 이상이고 그다음 column이 있으면, 그 column 맨 위 pane의 slot.
   빈 칸의 사각형은 `peekRect(whole) ?Rect`(첫 줄 한 줄, 빈 칸의 폭).
8. 제목 그리기: `main.zig`가 그 slot의 PTY master에 `TIOCGPGRP`를 묻고 `/proc/<pgid>/comm`을 읽는다(실패면 `?`). 그 프레임의
   배경을 칠하는 자리(통째 프레임의 `renderBackdrop` 뒤)에서 `peekRect`에 `STATUS_OFF` 색으로 그린다. 읽기는 `strip>` 줄의 값이
   바뀔 때와 통째 프레임에서만 한다 — 셸 출력 프레임마다 `/proc`을 읽지 않는다. 이름은 15바이트(`comm`의 길이)까지다.
9. `strip>` 줄: `… view=<a>-<b> peek=<이름|->`. pane 체인 16d · 16e의 정규식 넷은 끝 `$` 앞에 ` peek=-`을 붙인다.
10. `3/7` 칸(결정 26): `view`가 모든 column을 덮지 않을 때만. 16e의 기대(`3/3` · `4/4` …)는 그대로 맞는다.
11. `Cmd+R` chord: `input.zig`의 Cmd 표에 `.width_cycle`. copy mode 안에서는 `Cmd+D`와 같은 길(삼킨다)이다. `input_test`에
    한 줄.
12. pane 체인 16f(16e 뒤, 검사 6 앞). 시작은 `0 | (1 / 2)`, 포커스 2, 둘 다 `half`, `view=1-2`.
    - `Cmd+R` → `full`: `focus=2 rect=0,24 155x23`, `strip> … heights=1,2 view=2-2 peek=-`, 상태 꼬리 `  2/2`.
    - `Cmd+R` → `c80`: `rect=0,24 80x23`, `view=2-2`(채우기 없음 — 77 + 1 + 80 > 155), `peek=-`, 셸 2의 `$COLUMNS` 80.
    - `Cmd+Opt+←` → slot 0: `focus=0 rect=0,0 77x47`, `view=1-1 peek=fish`, `  1/2`. 빈 칸(78..154열) 첫 줄에 `STATUS_OFF`
      색 픽셀이 있다(`sep ink`처럼 셀 수 있으면 센다 — 방법은 구현이 고르고 결과에 적는다).
    - `Cmd+Opt+→` → slot 1(맨 위 줄 규칙): `rect=0,0 80x23`, `view=2-2 peek=-`.
    - `Cmd+R` → `c120`: `rect=0,0 120x23`.
    - `Cmd+R` → `half`: 둘 다 `half`라 `share` — 채우기로 `view=1-2`, `rect=78,0 77x23`, 상태 칸 없음.
    - `Cmd+Opt+↓` → slot 2: `rect=78,24 77x23`. 검사 6의 시작 모양이다.
    - 그 사이 `spawned` 줄 수가 그대로다.
13. pane 체인 9r(검사 9a 뒤, 패널 하나): `Cmd+R` → `pane> width refused` 한 줄, 마지막 `pane>` 줄이 그대로(`155x47`).
14. 도움말: `| Cmd+R | 지금 열(column)의 폭 — 80칸 · 120칸 · 절반 · 전체를 돈다 |`, 그리고 빈 칸의 이름 한 문장.

## `layout_test`

- 그대로: 지금의 검사 1~23 전부(폭을 안 바꾼 strip은 M2와 같은 숫자다). 단언을 고쳐야 통과하면 멈추고 보고한다.
- 새 검사 24(풀기): 155 · 77 격자에서 넷의 셀 폭. 77에서 `c80` · `c120`이 77.
- 새 검사 25(쌓기와 viewport): 확정 12의 순서를 layout만으로 — 각 단계의 `view` · 포커스의 사각형 · `peek`.
- 새 검사 26(채우기): `[c80, c80, half]` 등에서 `reveal`의 끝 `first`가 "가장 적게 + 채우기"인지, 모든 단계에서 보이는 것의
  폭 합 + 구분선 ≤ `cols`.
- 새 검사 27(혼자 · 분할의 폭): 혼자면 `cycleWidth` null이고 전체, 혼자에서 `.right`면 둘 다 `half`, `c120` column에서 `.right`면
  새 column도 `c120`.

## 할 일

1. `layout.zig` · `layout_test.zig`, 호스트 `zig run`.
2. `input.zig` · `input_test.zig`.
3. `main.zig`.
4. `pane/check.sh`, 도움말.
5. lead: `make quick`, 체인 `pane` · `pointer` · `dictation` · `hangul`, 루트 게이트.

## 판정

- `layout_test` · `input_test` 통과. 체인 넷 PASS(16f · 9r 포함). 루트 게이트 34/34.

## 결과 (2026-11-19)

1. 구현은 Herdr 서브에이전트(`sw-impl`, Opus) 13분. lead가 `layout_test`의 지운 줄(호출에 `whole` 인자를 더한 것뿐, 단언 그대로)과
   `pty.foregroundName`을 대조했다. plan 밖의 것 셋을 받아들였다 — `visible` · `reveal` · `view` · `remove`가 `whole`을 받는다
   (폭이 섞이면 보이는 수가 격자 폭에 달렸다), `setFullscreen`이 워크스페이스마다 `reveal`한다(격자가 줄면 포커스가 밀린다),
   이름 픽셀은 새 줄 `peek> ink=`로 센다(체인이 `strip>` 줄을 `$`까지 견준다).
2. `Cmd+R`은 지금까지 표에 없어 셸에 `r`로 갔다 — 이제 chord로 삼킨다. 기대는 게이트가 없었다(루트 게이트).
3. 체인: `pane` 200초 · `pointer` 271초 · `dictation` 223초 · `hangul` 212초 PASS. 16f: `full`에 `view=2-2`, `c80`에 `rect=0,24 80x23
   sep ink=10240`(가로선 80칸 × 128), `←`로 `view=1-1 peek=fish, peek> ink=71`, `half`로 채우기 `view=1-2`. 9r: `pane> width refused`.
4. 첫 루트 게이트: 33/34(2,061초, `out/gate-logs/20261118-153808`). 빨강은 pane 체인(CB-M0)의 render verify — 체인 판정은 PASS였고
   `verify> mismatch rows=2 first=4,24`가 35줄. 원인: 부분 갱신(`paintPane` → `clearRows`)이 바뀐 줄의 pane 오른쪽 한 칸을
   `stripColor`의 "격자 끝이 아니면 구분선" 가정으로 칠했다. 80 · 120셀 column은 격자 끝에 안 닿는 마지막 column이라 그 칸이
   여백이다. 고침: `Strip.separatorRight(leaf, whole)`이 정하고 `paintPane`이 slot을 받는다. `layout_test` 검사 28이 91가지에서
   `separators()`와 견준다(옛 규칙이면 실패). pane 체인의 mismatch 34 → 0.
5. 놓친 절차: `make check`은 verify를 판정하지 않는다(`lessons.md` "범용 명령"에 이미 있다). 그리기를 바꾼 이 milestone은 체인 뒤
   `grep -rah 'terminal: verify>' out/gate-logs/<체인>`를 돌렸어야 했다 — 그랬으면 게이트 전에 잡았다.
6. 둘째 루트 게이트: 34/34 첫 판 PASS(2,047초, `out/gate-logs/20261118-162307`), 어느 체인에도 `verify> mismatch` 없음.
