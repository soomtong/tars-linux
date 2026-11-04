# PS-M1 — 가속 곡선을 이동에 곱한다

> 구현 파일은 Claude(또는 서브에이전트)가 넣고, lead가 diff를 실제 파일과 대조한 뒤 체인 · commit한다. 줄 번호는 2026-11-04
> `d2244ce` 기준이라 낡을 수 있다 — 고치기 전에 `rg`로 다시 찾는다.

Goal: PS design 결정 3 · 4와 결정 8의 판정 바를 넣는다. M0이 장치 칸에 들어 둔 가속 단계(`PointerDev.accel`)를 실제 이동에 곱한다.
단계 0은 지금 동작과 비트 단위로 같아서 부팅 A · B의 이동 판정(`at x= y=`)이 그대로 초록이다.

Architecture: 곡선과 상태는 `pointer.zig`의 순수 구조체 하나(`Ballistics`), 시각은 `main.zig`의 `eventUs`, 적용 자리는
`drainPointer`의 부호 곱하기 바로 옆이다. 디코더 둘(`pointer.Mouse` · `touchpad.Touchpad`)은 안 바뀐다 — 터치패드의 패드 단위 →
픽셀 배율(`touchpad.scale`)을 지난 픽셀에 가속이 붙는다.

## 착수 전에 확인한 것 (2026-11-04, `d2244ce`)

1. `PointerDev.accel: pointer.Accel`(단계 값)을 `takePointer`가 `prefs.accelFor(kind)`로 채운다. 읽는 곳은 없다 — `open` 줄은 칸이
   아니라 `prefs.accelFor(kind).arg()`를 찍는다. 그래서 칸의 필드를 상태 기계로 바꿔도 `open` 줄은 안 바뀐다.
2. `drainPointer`의 `for (frames.slice()) |raw_frame|` 안에서 `ev`는 그 Frame을 낸 이벤트, 곧 `SYN_REPORT`다. `eventUs(ev)`가 그
   보고의 커널 시각(µs, `CLOCK_MONOTONIC`)이다. 버튼 전이가 이미 같은 값을 쓴다.
3. 터치패드 디코더는 `SYN_REPORT`마다 Frame을 낸다 — 손가락이 닿은 첫 보고(`fresh`)와 뗀 보고는 `dx = dy = 0`이다. 한 번의
   `tp-replay move`는 닿음(0) → 이동 n개 → 뗌(0)이다.
4. `tp-replay move DX DY`는 10단위씩 8ms 간격(`STEP_MS` · `MOVE_STEP`), 패드 가로 1000 = 화면 1280이라 한 걸음이 12.8픽셀이다.
   `touchpad.scale`이 나머지를 넘겨 `move 100 0`은 걸음 열 개, 합 128픽셀이다(부팅 B 검사 22, x 640 → 768).
5. 판정 바의 속도 셈(design 결정 8이 plan에 맡긴 것): 걸음 하나 12.8px / 8ms = 1.6 px/ms로 `V_LOW` 0.3을 넘는다. 단계 10에서
   t = (1.6 − 0.3) / 2.7 ≈ 0.48, 배율 ≈ 1 + 3 × 0.48 = 2.44. 첫 이동 보고는 앞선 이동이 없어 배율 1이므로(확정 3), 기대는
   12.8 + 9 × 12.8 × 2.44 ≈ 294픽셀, x ≈ 934다. TCG에서 `nanosleep`이 늦어 간격이 20ms가 되면 v = 0.64, 배율 ≈ 1.38, x ≈ 799다.
   간격이 100ms(`IDLE_US`)를 넘지 않는 한 768보다 크다. 그래서 판정은 정확한 값이 아니라 범위다(Task 4).
6. 부팅 C에서 판정 라 뒤 · 도구의 `quit` 앞은 터치패드가 열려 있고 포인터가 아직 안 움직였다(휠과 두 손가락은 자리를 안
   바꾼다 — 라가 그것을 본다). 바를 거기에 둔다. 판정 마의 `reload terminal`은 터치패드를 다시 열므로 마의 글자도 함께 바뀐다.
7. 부팅 C 디스크는 `printf 'shell=fish\nmouse_scroll=natural\ntouchpad_scroll=normal\n'`이다. 가 · 나 · 마의 글자 일곱 자리가
   `mouse_accel=0 touchpad_accel=0` · `accel=0`을 글자 그대로 본다(`rg -n 'accel' pointer/check.sh`의 2091~2237행).

## 확정 (design을 코드로 옮기며 정한 것)

1. 이름: `pointer.Ballistics`. `pointer.Accel`은 M0에서 단계 값(설정의 글자)의 이름이 됐다. "pointer ballistics"는 속도에 따른
   배율을 가리키는 흔한 말이다(Windows의 이름). `PointerDev.accel` 필드는 `ballistics: pointer.Ballistics`로 바뀐다.
2. 모양:
   ```zig
   pub const Ballistics = struct {
       level: u4,              // 0..10
       last_us: ?i64 = null,   // 직전 이동 Frame의 시각
       rem_x: i64 = 0,         // 배율을 곱하고 남은 1/1000 픽셀
       rem_y: i64 = 0,
       pub fn init(a: Accel) Ballistics
       pub fn apply(self: *Ballistics, dx: i32, dy: i32, t_us: i64) [2]i32
   };
   ```
   상수 넷은 `pub const`로 같은 자리 — `ACCEL_V_LOW_MPX`(0.3 px/ms를 1000배, 300) · `ACCEL_V_HIGH_MPX`(3000) · `ACCEL_GAIN_MAX`(4) ·
   `ACCEL_IDLE_US`(100_000). 이름의 `MPX`는 "1/1000 픽셀 / ms"다.
3. "직전 이동"은 `dx`나 `dy`가 0이 아닌 Frame이다. 이동 없는 Frame(버튼 · 휠 · 터치패드의 닿음 · 뗌)은 `last_us`를 안 바꾸고 그대로
   지난다. 앞선 이동이 없거나(`null`) 간격이 `IDLE_US`보다 길거나 0 이하면(시계가 뒤로 가는 일은 없지만 나누기를 지킨다) 배율 1이고
   `last_us`만 갱신한다. 그래서 한 손짓의 첫 보고는 늘 1:1이다 — 천천히 시작하는 손은 한 픽셀도 안 튄다.
4. 셈은 1/1000 고정소수점이다.
   ```
   dist_m  = isqrt((dx² + dy²) × 10⁶)                 # 1/1000 픽셀
   v_m     = dist_m × 1000 / dt_us                    # 1/1000 픽셀 / ms
   t_m     = clamp((v_m − V_LOW) × 1000 / (V_HIGH − V_LOW), 0, 1000)
   gain_m  = 1000 + level × (GAIN_MAX − 1) × t_m / 10
   out     = (d × gain_m + rem) / 1000,  rem = 나머지   # 축마다, divTrunc
   ```
   `isqrt`는 `std.math.sqrt`(u64)다. dx · dy는 i32라 제곱의 합 × 10⁶이 u64를 넘을 수 있다 — `dx`·`dy`를 ±2¹⁵에서 자른 값으로
   속도만 잰다(곱하는 값은 자르지 않는다). 한 보고에 32768픽셀을 넘는 이동은 없다.
5. 단계 0은 `apply`가 첫 줄에서 `.{ dx, dy }`를 그대로 돌려준다(`last_us` · 나머지를 안 만진다). design 결정 3의 "비트 단위로
   같다"를 셈의 우연이 아니라 갈래로 지킨다.
6. 나머지는 축마다 넘긴다(`touchpad.scale`과 같은 이유). 배율 1인 보고도 나머지를 더하므로, 빠른 손짓 끝에 남은 1/1000 픽셀이 다음
   보고에서 나온다 — 가속을 끈 단계 0만 나머지가 없다.
7. 적용 자리는 `drainPointer`의 부호 곱하기 바로 아래 두 줄이다.
   ```zig
   frame.wheel *= dev.wheel_sign;
   const d = dev.ballistics.apply(frame.dx, frame.dy, eventUs(ev));
   frame.dx = d[0];
   frame.dy = d[1];
   ```
8. 부팅 C의 디스크는 `mouse_accel=0` · `touchpad_accel=10`이다. design 결정 8은 "둘 다 10"이라고 적었지만 M0 실측 3(두 칸이 같은
   값이면 "터치패드가 마우스의 값을 쓴다"를 못 잡는다)을 그대로 따른다 — 마우스의 가속은 체인이 안 보므로(design 결정 8 끝 단락)
   마우스는 0이 잃는 것이 없고, 터치패드만 10이면 mutation b(Task 6)를 바가 잡는다. 한 부팅에서 두 `open` 줄의 `accel=`이 다른 것도
   판정 나가 함께 본다. design 결정 8의 표와 본문을 이 값으로 고친다.

## Task 1: `pointer.zig` — `Ballistics`

- 확정 2 · 3 · 4 · 5 · 6. 머리 주석에 PS design 결정 3 · 4, 그리고 출발값 넷이 재지 않은 값이라는 것(design 위험 2).
- `Prefs`에 `ballisticsFor(kind) Ballistics` 하나를 둘지는 구현 때 본다 — `Ballistics.init(prefs.accelFor(kind))`면 충분하다.

## Task 2: `pointer_test` — 곡선 검사

각 행은 `Ballistics.init(.{ .level = L })`에 `apply`를 차례로 부른다. 시각은 µs.

| # | 무엇 | 기대 |
|---|---|---|
| 1 | 단계 0, (40, 0)을 8ms 간격 셋 | 셋 다 (40, 0) — 빨라도 그대로 |
| 2 | 단계 10, 첫 보고 (13, 0) | (13, 0) — 앞선 이동이 없다 |
| 3 | 단계 10, (2, 0) 둘 8ms 간격 | 둘째 (2, 0) — 0.25 px/ms < `V_LOW` |
| 4 | 단계 10, (40, 0) 둘 8ms 간격 | 둘째 (160, 0) — 5 px/ms > `V_HIGH`, 배율 4 |
| 5 | 단계 5, 같은 손 | 둘째 (100, 0) — 배율 2.5 |
| 6 | 단계 10, (13, 0) 둘 8ms 간격 | 둘째 (32, 0), `rem_x` 110 — v 1625, t 490, gain 2470 |
| 7 | 단계 10, (40, 0) 둘 사이 150ms | 둘째 (40, 0) — `IDLE_US`를 넘었다 |
| 8 | 단계 10, (−40, 0) 둘 8ms | 둘째 (−160, 0) — 부호가 대칭 |
| 9 | 단계 10, (0, 40) 둘 8ms | 둘째 (0, 160) — 세로도 같다 |
| 10 | 단계 10, (40, 0) → 50ms 뒤 (0, 0) → 8ms 뒤 (40, 0) | 셋째 (57, 0) — dt는 둘째가 아니라 첫째와의 58ms다(이동 없는 Frame이 `last_us`를 안 바꾼다). v 689, t 144, gain 1432 |
| 11 | 단계 10, (3, 4) 둘 2ms | 거리 5 → v 2500, t 814, gain 3442, 둘째 (10, 13) 나머지 326 · 768 — 빗변으로 잰다 |

셈이 손으로 맞는지 Task 2를 쓸 때 다시 확인하고, 틀리면 표가 아니라 셈을 믿고 이 plan을 고친다.

## Task 3: `main.zig` — 칸에 붙이기

- `PointerDev.accel: pointer.Accel` → `ballistics: pointer.Ballistics`, 주석에 PS design 결정 4(칸마다 하나 — 두 장치의 속도가 안 섞인다).
- `takePointer`: `.ballistics = pointer.Ballistics.init(prefs.accelFor(kind))`.
- `drainPointer`: 확정 7. 주석은 부호 곱하기의 주석에 "가속도 여기서(PS design 결정 4) — 휠은 안 곱한다"를 붙인다.
- `rg -n 'ballistics' terminal/src/main.zig`가 칸 · `takePointer` · `drainPointer` 셋에만 있는지 본다. `\.accel\b`가 남지 않았는지도.

## Task 4: 부팅 C — 판정 바

- 디스크: `printf 'shell=fish\nmouse_scroll=natural\ntouchpad_scroll=normal\ntouchpad_accel=10\n'`(확정 8 — `mouse_accel`은 기본 0).
- 글자 고치기(확인 7): 가의 config 줄 · prefs 줄은 `touchpad_accel=10`, 나의 터치패드 `open`은 `accel=10`(마우스는 `accel=0` 그대로),
  마의 prefs 줄 · reload terminal 줄 · 둘째 터치패드 `open`도 `touchpad_accel=10` · `accel=10`. 실패 글자도 같이. 부팅 C 머리 주석에 M1
  한 줄.
- 판정 바: 라의 끝(`echo "normal touchpad: …"`) 뒤, 첫 `replay "quit"` 앞.
  ```
  BEFORE="$(last_at)"; BX = x, BY = y
  replay "move 100 0"
  wait_for_at "^terminal: pointer> at x=[0-9]+ y=${BY} " 로 이동이 도착할 때까지(at 줄 수가 는 것을 함께 본다)
  끝난 x를 AX로 읽고:
    AX - BX > 128          # 부팅 B 검사 22의 같은 손이 128이다(확인 4)
    AX - BX <= 512         # GAIN_MAX 4 × 128 — 배율 상한을 넘으면 셈이 틀렸다
    y는 BY 그대로
  ```
  "도착"을 가르는 법: 이동 하나는 at 줄을 여럿 낸다(보고마다). 손짓이 끝났는지는 도구가 뗀 뒤라 다음 명령(`quit`)과 겹치지 않게,
  at 줄의 x가 0.5초 동안 안 바뀔 때까지 기다린 뒤 읽는다(`wait_for_at`만으로는 첫 보고의 at에서 넘어간다). 구현 때 부팅 B 검사 22의
  기다림이 어떻게 끝을 아는지(정확한 x를 기다린다) 다시 보고, 같은 도우미가 있으면 쓴다.
- 로그 한 줄: `echo "accelerated: move 100 0 went $((AX - BX)) px (boot B: 128)"` — 실측 절에 그 값을 적는다.
- 끝 줄 `echo "PS-M1 check PASS"`를 `PS-M0 …` 뒤에 더한다.

## Task 5: 정적 검사 · 단위 검사 · 체인

1. `make quick`. `git diff --stat` · `git diff | rg '^-'` — 지워질 줄은 `PointerDev.accel` 두 줄(필드와 주석), `takePointer`의 `.accel =`
   한 줄, `drainPointer` 주석, 부팅 C의 `accel` 글자(확인 7)뿐이어야 한다.
2. 컨테이너에서 terminal `zig build test`(`pointer_test` · `touchpad_test`).
3. `pointer` 체인 하나. 부팅 A · B의 기존 이동 판정(검사 22의 768 · 464 등)이 그대로인 것이 단계 0의 증거다.

## Task 6: mutation 둘

한 번에 하나씩 넣고 `pointer` 체인만 돌린 뒤 되돌린다(`git diff`가 비는지 본다).

| | 망가뜨린 것 | 잡아야 할 판정 |
|---|---|---|
| a | `drainPointer`가 `ballistics.apply`를 안 부른다 | 바(이동 128 그대로) |
| b | `takePointer`가 종류를 안 보고 `prefs.mouse_accel`로 칸을 연다 | 바(마우스 0이라 터치패드가 1:1), 그리고 나의 `accel=` 글자는 안 바뀐다(줄은 `prefs`를 찍는다) — 바만 잡아야 맞다 |

단위 쪽 mutation은 따로 안 돌린다 — 곡선의 셈은 `pointer_test`의 기대값이 그 자체로 본다.

## Task 7: 루트 게이트

`RUNS=1`, 약 17분(실행 전에 알린다). 기대 27/27. `BT-M2`가 btvirt 간헐(`carryover.md`)로 빨가면 그 체인만 다시 돌려 초록을 확인한다.

## Task 8: 문서 · 닫기

PS는 M1로 끝난다. design 끝의 "닫을 때" 목록을 이 milestone에서 함께 한다.

- PS design: `Status:` "닫힘(2026-11-04)", 결정 8의 표 · 본문을 확정 8로, "실측 (M1)" 절(단위 검사 · 바의 픽셀 · mutation · 게이트).
- PD design 비목표 6 · 7에 "PS로 갔다(`2026-11-04-tars-pointer-settings-design.md`)" 한 줄씩.
- `docs/guides/completed.md` 표 끝 한 행.
- `docs/decisions/project_pointer_settings.md`와 `MEMORY.md` 한 줄 — 결정(종류별 넷 · 기본값 · 0~10), 함정(M0 실측 3: 같은 부호의 조합은
  "종류를 안 본다"를 못 잡는다, M0 실측 4: `screen_row`의 쓰는 중인 줄).
- `gh-pages`의 `data.js` — 기준일 · 타임라인 · 기능 목록(`site/README.md`의 순서).
- HANDOFF: PS 닫힘, 다음 후보.

## Task 9: 커밋

두 번으로 나눈다 — 구현(`terminal/src/{pointer,main}.zig` · `terminal/src/pointer_test.zig` · `pointer/check.sh` · 이 plan · PS design의
실측과 결정 8)과 닫기 문서. `gh-pages`는 그 브랜치에서 따로. `git status`에 산출물(`out/pd-settings.img`)이 없는지 먼저 본다.

## 시간

코드 약 60줄, 테스트 약 80줄, 셸 약 30줄. 단위 검사 2분, `pointer` 체인 약 4분 30초, mutation 둘 약 9분, 루트 게이트 약 17분.
