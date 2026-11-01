# MC-M2 — 시각을 잇고, 게이트가 더블 · 트리플을 본다

Goal: MC-M1의 순수 층에 커널 시각을 이어 게스트에서 더블 · 트리플클릭이 동작하게 하고, `pointer` 체인이 다섯 검사로 본다.
루트 게이트로 닫고 서브프로젝트를 끝낸다.

Architecture: `drainPointer`가 전이를 담을 때 그 이벤트의 `ev.time`(µs)을 함께 담는다(`PointerEdge.t_us`). 장치를 열 때
`EVIOCSCLOCKID(CLOCK_MONOTONIC)`를 부른다. `PointerWire.press`가 `Stamp.t_us`에 그 값을 넘기고, 횟수가 2 이상이면 `press` 줄 뒤에
`repeat` 줄 하나를 찍는다.

---

## 착수 전에 확정한 것

1. 게이트의 `button_down` · `button_up`은 로그 줄이 늘 때까지 0.1초 간격으로 기다린다(`wait_for_count`). 둘을 이어 부르면 두
   누름 사이에 그 기다림이 끼어 M0이 잰 100ms보다 길어지고, 부하 아래에서는 더 길다. 더블 · 트리플 검사는 `hmp` 명령을 기다림
   없이 이어 보내고(M0 측정 2 · 3의 모양 그대로), 판정은 마지막 명령 뒤에 줄 수로 한다.
2. 검사 16의 둘째가 끝난 자리는 왼쪽 패널(잎 0, 77열)이 포커스이고 뷰포트가 스크롤백에 올라가 있다. 명령을 치면 셸 출력이
   뷰포트를 바닥으로 되돌린다(PD 검사 11과 같은 성질).
3. `EVIOCSCLOCKID`가 성공하면 아무것도 안 찍는다. `pointer> open` 줄은 여러 검사가 글자 그대로 비교하므로 안 바꾼다. 실패할 때만
   `terminal: pointer> clock <경로> error=<errno>` 한 줄(design 결정 2).

## Task 1: `main.zig` — 시각과 `repeat` 줄

- `PointerEdge`에 `t_us: i64`. `drainPointer`의 전이 칸을 채우는 자리에서 `@as(i64, ev.time.tv_sec) * 1_000_000 + ev.time.tv_usec`
  (터치패드 `feed`에 넘기는 식과 같은 값 — 한 번 셈해 둘 다 쓴다).
- `tryOpenPointer`: 장치 칸을 채운 직후 `ioctl(fd, pointer.c.EVIOCSCLOCKID, &mono)`(`mono: c_int = CLOCK_MONOTONIC`, 확정 3).
- `PointerWire.edge` → `press(e.x, e.y, e.t_us)`, `press`가 `Stamp.t_us = t_us`.
- `press`: `gesture.press` 뒤 `gesture.clicks >= 2`면 `terminal: pointer> repeat n={clicks} dt={gap_us / 1000}`. 줄 순서는 `press` 줄
  → `repeat` 줄 → (의도가 찍는) `copy> enter`다.
- 주석: `press`의 "시각은 MC-M2가 잇는다" 줄을 지운다.

## Task 2: `pointer/check.sh` — 검사 33~37

자리는 검사 16의 둘째 뒤, `move_to 679 0` 앞. 준비: 왼쪽 패널에서 `echo mc-one mc-two:three`를 치고 출력 행(`screen_row
'mc-one mc-two:three'`)을 `ROW`로. `o`(3열 — m0 c1 -2 o3)의 픽셀은 `cell_x 3`, `cell_y ROW`. 도구 둘을 더한다.

```bash
repeat_count() { pointer_count 'repeat '; }
last_repeat() { tlog | grep -a 'terminal: pointer> repeat ' | tail -n 1 | tr -d '\r'; }
```

1. 검사 33 — 더블클릭은 단어를 복사한다. `hmp 1; hmp 0; hmp 1; hmp 0` 뒤 `release` 줄이 둘 늘 때까지. `repeat` 한 줄이 늘고 그
   줄이 `n=2`로 시작, `last_clip`이 `clip> len=6 text=mc-one`, 상태 줄 `COPY`가 꺼짐.
2. 검사 34 — 트리플클릭은 줄을 복사한다. `1 0 1 0 1 0`. `repeat`가 둘 늘고 마지막이 `n=3`, `last_clip`이
   `clip> len=19 text=mc-one mc-two:three`.
3. 검사 35 — 더블클릭 뒤 끌면 단어 단위로 늘어난다. `1 0 1`(누른 채) → `repeat` 한 줄 기다림 → `move_to (cell_x 10) PY`(`mc-two`의
   `t`, 10열) → `button_up`. `last_clip`이 `clip> len=13 text=mc-one mc-two`(끄는 칸의 단어가 통째로, `:`에서 끊긴다).
4. 검사 36 — 느린 두 클릭은 반복이 아니다. `1 0`, `sleep 0.8`, `1 0`. `release` 둘을 기다린 뒤 `repeat` 수가 그대로, `clip>` 수가
   그대로.
5. 검사 37 — 끌어 복사한 직후의 클릭은 반복이 아니다. `move_to (cell_x 0) PY` → `button_down` → `move_to (cell_x 4) PY` → `button_up`(복사 하나) → 곧바로
   `hmp 1; hmp 0`. `repeat` 수가 그대로, 새 `clip>` 줄은 끌기의 것 하나뿐(`text=mc-on`).

모든 검사는 실패 문구에 마지막 `repeat` · `clip>` 줄을 붙인다.

## Task 3: 판정

1. `make quick`, 컨테이너 `zig build test`.
2. `pointer` 체인 단독(약 3분 20초).
3. mutation 셋(되돌린다, 각각 `pointer` 체인 단독): (1) `repeats`가 늘 false → 검사 33 빨강. (2) `unitKind`의 `.word => .char` →
   검사 33의 `clip>` 글자 다름. (3) `motion`의 `dragging` 갈래에서 `breakRun()`을 지우고 `pressed` 갈래에서도 지움 → 검사 37 빨강.
   pointer_test가 (3)을 먼저 잡으면 체인은 호스트 테스트에서 멈춘다 — 그때는 그 결과를 적고, 게스트 검사가 이것을 보는지는
   체인의 `zig build test` 줄을 임시로 건너뛰어 본다(DR-M3에서 쓴 방법).
4. 루트 게이트 한 번(`feedback_gate_runs` — 반복은 1). 약 10분 반.

## Task 4: 닫기

- design: Status 줄 "끝났다", "실측 (M0)" 뒤에 M2 결과 요약 한 줄.
- PD design 비목표 2에 "MC(2026-11-01)가 더블 · 트리플을 열었다, Shift 클릭은 MC 비목표 1" 한 줄.
- `docs/guides/completed.md` 표 끝에 한 행.
- `docs/decisions/project_multi_click.md` + `MEMORY.md` 한 줄. `project_pointer_devices.md`의 "열지 않은 것"에서 더블클릭을 뺀다.
- `HANDOFF.md`: 지금 상태 · "다음 후보"의 PD 비목표 줄 · "사용자가 확인할 것"에 실기 더블클릭 · 터치패드 더블탭.
- 소개 페이지(`gh-pages`의 `data.js`)는 `site/README.md` 순서대로 — 사용자에게 보이는 기능이므로 넣는다.
- 커밋 `MC-M2: wire event times, gate double and triple clicks, close MC`.

## 결과 (2026-11-01)

lead가 직접 구현했다. `terminal/src/main.zig` +33 −7(`PointerEdge.t_us` · `eventUs` · `EVIOCSCLOCKID` · `press`의 시각과 `repeat`
줄), `pointer/check.sh` +131(검사 33~37과 도구 셋). `std.posix.CLOCK.MONOTONIC`이 그대로 컴파일된다.

판정.

1. `make quick` PASS. 첫 판은 `[ … ] && [[ … ]] || report_failure` 셋이 SC2015 note 꼴이라 `if`로 바꿨다(뜻도 모호했다).
2. `pointer` 체인 단독 254초 PASS. `repeat n=2 dt=104`, 트리플 `n=3 dt=111`, `clip>`이 `mc-one` · `mc-one mc-two:three` ·
   `mc-one mc-two` · (느린 두 클릭 없음) · `mc-on`. `pointer> clock … error` 줄 없음(ioctl 성공).
3. mutation 셋, 각각 `pointer` 체인 단독. (1) `repeats`가 늘 false — 호스트 테스트를 건너뛰고 — 검사 33 `the double click put
   nothing on the clipboard`. (2) `unitKind`의 `.word => .char` — 검사 33 `copied 'clip> len=1 text=o'`. (3) 끌기의 `breakRun` 둘을
   지움 — 첫 판은 초록이었다(아래). 검사 37을 고친 뒤 `a click right after a drag copy printed a repeat line (… repeat n=2 dt=222 …
   text=mc-one)`.
4. 루트 게이트 22/22, 11분 33초(prebuild 357 + lanes 332초), verify 8152줄. pointer는 lane 16, `dt` 109 · 114ms.

바로잡은 것. 검사 37의 첫 판은 `button_down` → `move_to` → 뗌으로 끌고 끌기 끝(32픽셀 오른쪽)에서 클릭했다. 그 헬퍼들은 로그 줄을
0.1초씩 기다리므로 두 누름의 차가 500ms를 넘고, 클릭 자리도 첫 누름에서 8픽셀 밖이다 — 시간과 거리가 먼저 연속을 끊어 "끌기가
끊는다"를 못 봤고, 그 조건을 지운 mutation 3이 초록으로 지나갔다. 여섯 명령(누름 → 32픽셀 오른쪽 → 뗌 → 32픽셀 되돌림 → 누름 →
뗌)을 기다림 없이 보내 두 누름이 약 200ms · 같은 픽셀이 되게 고쳤다. 한 회차에 다 들어와도 `round.edges` 루프가 전이마다 그 자리로
먼저 움직이므로 뗌 앞에서 끌기가 생긴다.

중간의 소동. 첫 체인 판은 호스트 디스크가 가득 차(ENOSPC) `ld.lld`가 terminal을 못 써서 빨갰고, 그 바람에 OrbStack이 내려가
다음 판은 1초 만에 `docker.sock` 없음으로 끝났다. 사용자가 공간을 비운 뒤 `orb start`. 우리 코드와 무관하다.
