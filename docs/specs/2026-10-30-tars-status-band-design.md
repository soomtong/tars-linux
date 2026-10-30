# TARS Status Band — Design

Date: 2026-10-30
Status: 끝났다 — SB-M0(2026-10-30, 루트 게이트 22/22, 11분 14초(prebuild 364 + lanes 308초), verify 8109프레임 전부 `ok`). plan은 `docs/plans/2026-10-30-tars-status-band-sb-m0.md`. 기억은
`docs/decisions/project_status_band.md`. 키 하나의 그리기 0.92 → 0.42ms(overlay 0.22 → 0.001, present 0.36 → 0.27).

HANDOFF "다음 후보"의 "상태 줄 띠의 부분 갱신(상한 0.22ms)"을 집는다(사용자가 2026-10-30에 골랐다). Dirty Rows(DR-M0~M3,
`docs/specs/2026-10-28-tars-dirty-rows-design.md`)가 격자 안을 행 단위로 바꾸고 남겨 둔 격자 밖의 한 자리다 — DR design 결정 4의
"상태 줄은 매 프레임 그 줄만 다시 칠한다(한 줄이다)".

## 한 줄 요약

프레임마다 격자 아래 띠 전체(1280 × 28)를 지우고 상태 줄을 다시 쓰던 것을, 상태 줄의 내용이 지난 프레임과 다르거나 통째
프레임일 때만 하게 바꾼다. 그 밖의 프레임은 띠에 손대지 않고 clip에도 안 넣는다. 판정은 DR의 verify가 그대로 한다 — 그림자는
매 프레임 띠를 통째로 그리므로, 띠를 건너뛴 것이 틀리면 픽셀 비교가 격자 아래 행(`rows`번)으로 말한다.

## 배경 — 착수 전 조사 (2026-10-30, HEAD `30a3d9f`)

1. 띠는 `renderOverlay`(`terminal/src/main.zig`)가 매 프레임 지우고 쓴다 — `fb.fillRect(0, grid_bottom, fb.width, fb.height -
   grid_bottom, MARGIN_COLOR)` 뒤 `drawStatus`. 게이트의 1280 × 800에서 `rows`는 `(800 − 2 × 20) / 16 = 47`, `grid_bottom`은
   `20 + 47 × 16 = 772`, 띠는 28픽셀 행 × 1280 × 4바이트 = 143KB다. 1080p에서는 `rows` 65 · 띠 20픽셀 행 × 1920 × 4 = 153KB.
2. `App.render`는 그 뒤에 띠 전체를 clip으로 넘긴다(`clips.push(0, grid_bottom, fb.width, fb.height - grid_bottom)`, DR-M2 plan
   확정 7). virtio-gpu는 clip을 경계 상자 하나로 합치고 simpledrm은 clip마다 VRAM으로 복사한다(DR design 위험 5의 답) — 실기에서는
   키 하나마다 바뀐 행 몇 줄에 더해 143KB가 늘 간다.
3. DR-M3의 진단 판(`probe/split.pl`)에서 키 하나의 그리기 0.92ms 가운데 `overlay`가 0.22ms다(measurements 97). 그 시나리오((a),
   `echo` 네 글자)에는 프롬프트가 없으므로 0.22 전부가 띠 지우기 + 상태 줄 글자다. `present` 0.36에 띠 clip의 몫이 얼마인지는
   따로 안 쟀다.
4. 상태 줄의 내용은 셋이 정한다 — `Status.text`(`한`/`EN` · 한글 자판 · 영문 자판 · `CAPS` · `  W2` · `  COPY` · 받아쓰기 칸,
   `status.statusText`가 짓는다), `Status.caps`(글자가 아니라 `CAPS` 칸의 색), `Status.battery`(오른쪽 끝의 칸 — 글자 넉 자와
   색 갈래). `copy` · `workspace` · `dict`는 `text`에 이미 들어 있다(`drawStatus`가 꼬리를 세는 데만 따로 쓴다). `rows` · `cols`는
   부팅 중 안 바뀐다(`App.open`이 한 번 정한다). 바뀌는 때는 한/영 전환 · 자판 바꿈 · CapsLock · 워크스페이스 수나 번호 · copy
   mode 들고 남 · 받아쓰기 단계 · 배터리 읽기(60초 주기 또는 uevent)다 — 출력이 쏟아지는 동안의 프레임이나 키 하나의 프레임에서는
   거의 안 바뀐다.
5. `dumpStatus`가 이미 같은 셋을 메모한다 — `App.last_status` · `last_status_len` · `last_status_caps` · `last_status_battery`.
   `status>` 줄 다섯을 내용이 바뀐 프레임에만 찍기 위해서다(IS-M1 · BS-M1). 그 줄을 읽는 체인은 여섯(hangul · battery · copy ·
   dictation · pointer · pane)이고, 대개 "마지막 `status>` 줄"을 본다.
6. verify의 그림자(`verifyFrame`)는 매 프레임 `renderBackdrop` → fresh `renderPane` → `renderOverlay`다 — 띠를 지우고 상태 줄을 쓰는
   것까지 통째 경로 그대로다. 픽셀 비교(`verify.compare`)는 fb 전체를 행마다 보고 격자 아래는 `rows`번 행으로 센다
   (`Grid.rowOf`). clip 판정(`verifyClips`)은 clip 밖의 픽셀이 바뀌었는지를 본다. 그래서 띠를 건너뛰는 실수(바뀌었는데 안 그림)는
   `mismatch rows=1 first=47`로, 그렸는데 clip에 안 넣는 실수는 `mismatch clip`으로 이미 잡힌다 — 새 판정 장치가 필요 없다.
7. 띠에 쓰는 것은 `renderOverlay`와 화살표뿐이다. `clearRows` · `renderRows` · `renderPane`은 패널 사각형(+ 오른쪽 한 칸) 안이고
   패널의 마지막 행은 `grid_bottom`에서 끝난다. 이미지는 패널 clip 안이다. 구분선은 격자 안이다. 화살표는 `render`의 처음에
   `sprite.restore`로 저장한 픽셀을 되돌리고 `presentFrame`에서 새로 저장하고 그린다(DR-M2 plan 확정 8) — 띠 위에 있던 화살표는
   되돌리기가 띠의 픽셀을 지난 프레임의 것으로 돌려놓는다.
8. 통째 프레임(`full`: 첫 프레임 · 워크스페이스 전환 · 트리 변경)은 `renderBackdrop`의 `fill(MARGIN_COLOR)`이 fb 전체를 지우므로
   띠도 비어 있다 — 그 프레임은 내용이 같아도 상태 줄을 다시 써야 한다.
9. `renderOverlay`는 실제 경로와 그림자가 함께 부른다. DR design은 `renderBackdrop` · `renderPane` · `renderOverlay`의 모양을 "통째
   경로의 정의"라 했다 — 그림자 쪽은 이 모양을 그대로 두어야 한다.
10. `probe/split.pl`의 anchor 하나가 `frame.prompt_ink = try renderOverlay(self.fb, &self.cache, frame.prompt, frame.status_line);`
    줄이다(`overlay` 구간의 끝). 이 줄이 바뀌면 anchor도 따라 바꾼다(DR-M3 Task 2가 같은 일을 했다).

## 효과가 없거나 이 서브프로젝트가 안 하는 것

- 처리량((b) `seq 1 200000`). 프레임 69개 × 0.22ms ≈ 15ms로 1,139ms의 잡음 안이다. 재긴 하되 읽지 않는다.
- 상태 줄이 바뀌는 프레임. 그 프레임은 지금과 같이 띠 전체를 지우고 다시 쓴다(결정 1) — 그 한 프레임의 0.22ms는 그대로다.
- 프롬프트(검색 · copy의 오버레이 줄). 격자의 마지막 행이라 `paintPane`이 이미 dirty 행으로 다룬다(DR-M2 plan 확정 7).
- 띠의 자리 · 높이 · 글자 · 색. 보이는 것은 한 픽셀도 안 바뀐다 — 여섯 체인의 `status>` 기준값이 그대로 서는 것이 그 판정이다.
- `present` 자체(커널 쪽 0.36ms)와 GPU 가속. 이 뒤의 일이다.
- 실기 절대값. simpledrm에서 143KB 복사가 빠지는 효과는 게이트로 못 재고 "사용자가 확인할 것"으로 넘긴다(DR과 같다).

## 결정

1. 단위는 띠 전체이고, 조건은 "내용이 바뀌었거나 통째 프레임"이다. HANDOFF는 "바뀐 칸만"이라 적었지만 칸 단위로 안 간다 —
   상태 줄이 바뀌는 프레임은 드물고(배경 4), 바뀐 프레임 하나의 비용이 0.22ms가 상한이며, 칸 단위는 `drawStatus`의 col 전진
   산수(폭 2 글자 · 꼬리 넷)를 비교 쪽에서 한 번 더 해야 한다 — 어긋나면 "글자가 겹쳐 보인다"로 나타나 원인에서 멀다(`drawStatus`
   주석). 바뀌지 않은 프레임에서 0.22를 0으로 만드는 것이 이득의 거의 전부다.
2. "같다"의 정의는 메모 하나다. `Status`의 `text` 바이트 · `caps` · `battery`(칸 전체, `std.meta.eql`)를 지난 프레임의 것과
   비교한다 — `copy` · `workspace` · `dict`는 `text` 안에 있고 `rows` · `cols`는 불변이다(배경 4). 이 메모는 `dumpStatus`의 메모
   넷(배경 5)과 같은 것이므로 하나로 합친다 — `render`가 비교하고 갱신하며 결과(`changed`)를 `Frame`에 남기고, `dumpStatus`는
   그 값이 참일 때 찍는다. 찍는 때는 지금과 같다 — 지금도 "지난번 찍은 것과 다를 때"이고, 지난번 찍은 것 = 지난번 바뀐 것이다.
   첫 프레임은 메모가 비어 있어 `changed`다. `sameBatteryCell`은 쓰는 곳이 없어지면 지운다 — BS-M1이 그 함수를 메모 전용으로 둔
   이유(mutation이 메모만 건드리게)는 이제 verify가 대신한다: 메모를 고친 mutation은 띠를 안 그려 `mismatch rows=1`로 따로 보인다.
3. 실제 경로는 `renderOverlay`를 부르지 않고 둘을 따로 부른다 — 프롬프트(`drawPrompt`, 있으면 매 프레임. 그 행은 `paintPane`이
   방금 지웠다)와 띠(`renderStatusBand`: 띠 지우기 + `drawStatus`, `full or changed`일 때만). `renderOverlay`는 둘을 차례로 부르는
   함수로 남아 그림자(`verifyFrame`)가 그대로 쓴다 — 통째 경로의 정의가 안 바뀐다(배경 9). `renderOverlay`에 bool을 더해 가르는
   길도 있지만, "통째 경로"가 분기를 품지 않는 쪽을 고른다.
4. clip은 띠를 그린 프레임에만 넣는다. `full`이면 `clips.all()`이라 더해도 무시된다 — 지금과 같다.
5. 판정은 verify다(배경 6). 새 호스트 검사는 없다 — 메모 비교는 세 필드의 `eql`이고 `status_test`(순수 문자열)는 0줄이다. mutation
   둘로 verify가 잡는 것을 본다: (a) 조건을 늘 거짓으로(띠를 영영 안 그림 — 첫 프레임은 `full`이라 그려진다) → 상태가 바뀌는
   체인(hangul의 한/영 · battery의 A3 · copy)에서 `mismatch rows=1 first=47`과 그 체인의 `status> … ink` 검사가 함께 빨강, (b) 그리되
   clip을 안 넣음 → `mismatch clip`. 체인이 호스트 테스트를 먼저 돌지만 이번 mutation은 호스트가 못 보므로 마운트로 건너뛸 단계가
   없다.
6. 측정은 같은 프로브다 — `probe/patch.pl` + `probe/split.pl`, 부팅 3회, 열두 프레임의 중앙값(DR-M3 결과 절의 읽는 법). `split.pl`의
   `overlay` anchor를 새 호출 둘의 뒤로 옮긴다. 기대는 (a)에서 `overlay` 0.22 → 0.01 안팎(프롬프트 없음 · 띠 건너뜀)이고,
   `present`는 virtio-gpu의 경계 상자가 작아져 조금 줄 수 있다 — 줄지 않아도 실패가 아니다(QEMU의 DIRTYFB는 clip 크기에 둔하다,
   DR-M2 결과). 숫자는 measurements 98로 남긴다.
7. 로그 · 덤프의 줄은 바뀌지 않는다. `status>` 다섯 줄은 결정 2대로 같은 프레임에 같은 내용으로 찍히고, `dumpStatus`가 띠의 픽셀을
   세는 것은 띠가 지난 프레임 그대로이므로 같은 값이다.

## Milestone

| | 무엇을 | 상태 |
|---|---|---|
| SB-M0 | 메모 하나(결정 2) · 실제 경로의 `renderStatusBand` 분리(결정 3) · clip(결정 4) · mutation 둘(결정 5) · 같은 프로브로 재측정(결정 6) · 루트 게이트 | 끝(2026-10-30) — (a) frame 0.92 → 0.42ms(−54%). overlay 0.22 → 0.001, present 0.36 → 0.27(띠 clip이 빠져 경계 상자가 작아졌다 — 결정 6이 "줄 수 있다"고만 한 자리), cells 0.07 · pane 0.16. mutation 둘 다 hangul의 Shift+Space 프레임에서 `mismatch rows=1 first=47` · `mismatch clip`. (a) 판은 체인도 빨개졌지만 자리는 CapsLock 홀드 검사였다(`text=`는 메모가 찍어 초록). 루트 게이트 22/22, 11분 14초(prebuild 364 + lanes 308초), verify 8109프레임 전부 `ok` |

하나로 끝낸다. 코드는 `main.zig` 안의 수십 줄이고 새 모듈 · 새 검사 · 새 로그 줄이 없다.

## 위험

1. 띠의 픽셀이 다른 길로 낡는 것. 지금은 매 프레임 지우기가 어떤 쓰기든 덮었지만, 이 뒤로 띠는 "마지막으로 그린 상태 줄"이
   그대로 남는 자리다. 격자 마지막 행의 글리프가 아래로 삐져나오면(DR design 결정 5의 전제 — `font_test`가 한글 11172자에 대해
   단언하지만 코드의 성질은 아니다) 그 픽셀이 띠에 남고, 그 행이 다시 칠해져도 띠 쪽은 안 지워진다. 그림자는 fresh라 그 픽셀이
   없으므로 verify가 `first=47`로 잡는다 — 그때는 띠를 지우는 조건에 "격자 마지막 행이 dirty"를 더하는 것이 답이다. 지금은 안
   더한다(근거가 없다).
2. 화살표와의 순서. `restore`가 띠 판정보다 앞이어야 한다(배경 7). 뒤로 가면 띠를 건너뛴 프레임에서 화살표 밑에 저장된 픽셀이
   낡는다. 지금 순서가 이미 맞고 바꾸지 않는다 — 바꾸면 verify가 잡는다.
3. 이득이 QEMU 숫자로 작다. 0.92 가운데 0.22이고 `present`는 안 줄 수 있다. 이 서브프로젝트의 본론은 실기의 simpledrm에서 키
   하나마다 143KB가 안 가는 것이며, 그것은 사용자가 본다(HANDOFF "사용자가 확인할 것"의 RS · DR 항목에 한 줄 더한다).
4. `dumpStatus`가 `Frame`의 `changed`를 보게 되면 `render` 없이 `dumpStatus`를 부르는 길이 생길 때 어긋난다. 지금 부르는 자리는
   `dumpFrame` 하나이고 `tick`이 `render` 바로 뒤에 부른다 — 다른 자리가 생기면 그때 본다.

## 비목표

1. 칸 단위 부분 갱신(결정 1). 다시 열 신호는 "상태 줄이 매 프레임 바뀌는 칸"이 생기는 것 — 예를 들어 시계 칸.
2. 띠를 격자 행처럼 `Pane`의 dirty 행 비교에 넣는 것. 띠는 패널이 아니고 셀 목록도 없다.
3. 프롬프트 줄의 부분 갱신(이미 행 단위다).
