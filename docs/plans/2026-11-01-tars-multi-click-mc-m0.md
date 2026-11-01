# MC-M0 — 클릭 간격과 단어 모양을 먼저 잰다

> 이 milestone은 커밋되는 코드를 한 줄도 안 고친다. 계측 패치(`terminal/src/main.zig` · `terminal/src/vt_test.zig` ·
> `pointer/check.sh`)는 작업 트리에서만 쓰고 Task 6에서 되돌린다. 저장소에 들어가는 것은 이 plan의 "실측한 것" 절과
> design의 "실측 (M0)" 절이다.

Goal: design이 기다리는 값 셋을 잰다 — (1) `EVIOCSCLOCKID`가 게스트에서 되는가, (2) 게이트가 HMP로 넣은 두 누름의 `ev.time` 차가
500ms에 얼마나 여유가 있는가(단독 · 루트 게이트 부하 아래), (3) `selectWordBetween`이 우리 `WORD_BOUNDARY`로 결정 4의 모양을
내는가. M1 · M2가 그 값을 그대로 옮겨 적기만 하면 되게 한다.

Architecture: 시각은 terminal에 임시 로그 한 줄을 넣어 본다 — 버튼 전이마다 그 이벤트의 `ev.time`과 그 순간의 두 시계
(`CLOCK_MONOTONIC` · `CLOCK_REALTIME`)를 찍는다. 넣는 쪽은 `pointer/check.sh` 부팅 A 끝에 임시 블록 하나. 단어 모양은 `vt_test`에
임시 검사를 넣어 컨테이너의 `zig build test`로 본다.

---

## 착수 전에 확정한 것

1. evdev의 기본 시계는 `CLOCK_REALTIME`이다. `evdev_open`이 클라이언트를 0으로 채워 할당하고(`kvzalloc`) `INPUT_CLK_REAL = 0`이다
   (`kernel/src/linux-6.18.42/drivers/input/evdev.c:49` · `include/linux/input.h:39`). design 조사 5가 맞다. 게스트에서 볼 것은
   ioctl의 성공뿐이다.
2. `EVIOCSCLOCKID`는 translate-c가 상수로 넘긴다 — `c_input.zig`의 `pub const EVIOCSCLOCKID = _IOW('E', 0xa0, c_int)`. `EVIOCGBIT`처럼
   함수로 감쌀 필요가 없다.

## 무엇을 재나

| 측정 | 무엇 | design의 자리 |
|---|---|---|
| 1 | `EVIOCSCLOCKID(CLOCK_MONOTONIC)`의 반환값, 그 뒤 `ev.time`이 `CLOCK_MONOTONIC` 지금 값과 몇 ms 차인가 | 결정 2 |
| 2 | 50ms 간격 네 명령(`1` · `0` · `1` · `0`)의 두 누름 차, 다섯 번 — 단독 | 결정 3 · 위험 1 |
| 3 | 같은 것을 루트 게이트(22 lanes) 부하 아래 | 위험 1 · 2 |
| 4 | `.word` 모양 여섯 경우의 문자열 | 결정 4 |

## Task 1: 단어 모양 — 호스트 프로브

`vt_test.zig` 끝에 임시 `test "MC-M0 probe"` 하나. `vt.Screen`에 글을 쓰고 라이브러리의 `selectWordBetween` · `selectWord`를
`WORD_BOUNDARY`로 직접 불러 design 결정 4의 식(앵커 쪽 단어 · 커서 쪽 단어 이어 붙이기)의 `selectionString`을 `std.debug.print`로
찍는다. `WORD_BOUNDARY`는 `Screen` 안의 private 상수라 프로브에 같은 배열을 복사해 둔다(되돌릴 것이라 괜찮다).

경우 여섯(문자열 `alpha beta-gamma (delta)  eps` 한 줄, 30열 화면에 긴 단어 하나를 더 써 soft wrap):

1. 앵커 = 커서 = `beta`의 `e` → 기대 `beta-gamma`(`-`는 경계가 아니다).
2. 앵커 `alpha`의 `l`, 커서 `beta`의 `t` → `alpha beta-gamma`.
3. 앵커 `beta`의 `t`, 커서 `alpha`의 `l`(왼쪽으로 넘어감) → `alpha beta-gamma`.
4. 앵커 = 커서 = `delta` 뒤 공백 두 칸의 첫 칸 → 공백 둘(또는 `)`를 포함하는가 — 경계 문자 덩어리의 실제 모양을 본다).
5. 앵커 = 커서 = 줄 끝의 쓰이지 않은 칸 → null.
6. soft wrap으로 두 줄에 걸친 단어의 아랫줄 글자 → 단어 전체.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c './prepare.sh >/dev/null && zig build test 2>&1' | rg 'MC-M0|probe'
```

## Task 2: 계측 패치

`terminal/src/main.zig` 두 자리.

- `tryOpenPointer`에서 장치 칸을 채운 직후 `ioctl(fd, pointer.c.EVIOCSCLOCKID, &mono)`(`mono: c_int = CLOCK_MONOTONIC`)를 부르고
  `terminal: pointer> mc0 clock rc=<반환값> errno=<이름>` 한 줄.
- `drainPointer`의 전이 칸을 채우는 자리에서 `terminal: pointer> mc0 edge down=<0|1> t_us=<ev.time> mono_us=<지금> real_us=<지금>`
  한 줄. 왼쪽 버튼만.

`pointer/check.sh` 부팅 A의 마지막 검사 뒤(QEMU를 끄기 전)에 임시 블록 하나. 포인터를 글자가 있는 칸에 두고, 다섯 번 되풀이한다:

```bash
for k in 1 2 3 4 5; do
  hmp "mouse_button 1"; hmp "mouse_button 0"; hmp "mouse_button 1"; hmp "mouse_button 0"
  sleep 1
done
tlog | grep -a 'pointer> mc0' | tr -d '\r' > "$OUT_DIR/mc0.txt"   # 체인의 로그 자리에 맞춘다
```

`hmp`는 명령마다 50ms 잔다(조사 7). 블록은 판정하지 않는다 — 값을 남기기만 한다. 첫 누름의 `cancel`이 copy mode를 닫으므로
앞 검사의 상태와 섞이지 않는다.

## Task 3: 측정 1 · 2 — 단독

```bash
docker run --rm --sysctl net.ipv4.ip_local_reserved_ports=45455-45599 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer ./pointer/check.sh > <scratchpad>/mc0/pointer-alone.log 2>&1
```

`mc0 clock` 줄의 `rc=0`, edge 줄에서 (a) `mono_us − t_us`(이벤트에서 우리가 읽기까지), (b) 되풀이마다 두 누름 `t_us`의 차. 체인
자체는 초록이어야 한다 — 빨가면 계측이 무언가를 바꾼 것이다.

## Task 4: 측정 3 — 루트 게이트 부하 아래

루트 게이트를 한 번(약 10분 반, `run_in_background`). 끝나면 `out/gate-logs/<시각>/`의 pointer 로그에서 같은 두 값을 뽑는다. 22/22가
아니어도 pointer 체인의 값은 읽는다(다른 lane의 간헐은 이 측정과 무관). pointer가 빨가면 계측 탓인지 먼저 본다.

## Task 5: 기록

- 이 plan 끝에 "실측한 것" 절 — 측정 넷의 값과 해석. 두 누름 차의 최대가 500ms에 대해 얼마나 남는가, 그 결론(위험 1의 대책이
  필요한가).
- design에 "실측 (M0)" 절(배경 다음) — 결정이 바뀌는 자리가 있으면 그 결정에도 한 줄.
- Status 줄을 "MC-M0 끝(날짜), M1 착수 전"으로.

## Task 6: 되돌리고 커밋

```bash
git checkout -- terminal/src/main.zig terminal/src/vt_test.zig pointer/check.sh
git status --short   # plan · design 둘만 남아야 한다
git add docs/plans/2026-11-01-tars-multi-click-mc-m0.md docs/specs/2026-11-01-tars-multi-click-design.md
git commit -m "MC-M0: measure click intervals under the gate and the word selection shape"
```

## 실측한 것 (2026-11-01)

측정 1 — 시계. 게스트에서 `ioctl(fd, EVIOCSCLOCKID, &CLOCK_MONOTONIC)`가 `rc=0`이다(부팅 A · B, 단독 · 게이트 다). 그 뒤 전이 이벤트의
`ev.time`과 우리가 읽은 순간의 `CLOCK_MONOTONIC` 차("읽기 지연")가 0.05~0.23ms다 — 이벤트가 단조 시계로 찍힌다. `REALTIME`이었다면
차가 epoch(약 17.9억 초)였다. design 결정 2 그대로 간다.

측정 2 · 3 — 게이트의 두 누름 차. `hmp "mouse_button 1"` · `0` · `1` · `0`(명령마다 50ms 수면)을 다섯 번, 전이 순서는 늘 `1010`.

| | 두 누름 차 | 누름 → 뗌 | 읽기 지연 |
|---|---|---|---|
| 단독(`pointer/check.sh`, 3분 24초, 초록) | 96.8 · 117.5 · 117.6 · 110.6 · 111.2ms | 49.4~61.0ms | 0.05~0.22ms |
| 루트 게이트 부하(22/22, 10분 4초 = prebuild 303 + lanes 300초, pointer는 lane 16) | 103.1 · 113.4 · 119.5 · 104.9 · 119.7ms | 47.2~63.9ms | 0.09~0.23ms |

해석. 두 누름 차는 `hmp`의 수면 두 번(100ms)에 QEMU의 처리 몇 ms를 더한 값이고, 6 lanes가 함께 돌아도 안 늘었다(최대 119.7 대
117.6ms). 500ms까지 380ms가 남는다 — design 위험 1의 대책(명령 넷을 한 번에 쓰기)은 필요 없다. 검사는 기존 `hmp`를 그대로 쓴다.
트리플(누름 셋)도 둘째 → 셋째가 같은 간격이고 결정 3의 시각 조건은 "앞 누름과의 차"라 같은 여유다. 느린 두 클릭 검사(design
검사 4)의 `sleep 0.8`은 500ms에서 300ms 위다 — 두 누름 차가 수면보다 짧아질 수는 없으므로 거꾸로 새지 않는다.

측정 4 — 단어 모양(호스트, `vt_test` 임시 프로브, 문자열 `alpha beta-gamma (delta)  eps`, design 결정 4의 식).

| 경우 | 앵커 → 커서 | `selectionString` |
|---|---|---|
| 1 | `beta`의 e(같은 자리) | `beta-gamma` |
| 2 | `alpha`의 l → `beta`의 t | `alpha beta-gamma` |
| 3 | `beta`의 t → `alpha`의 l(앵커 왼쪽으로 넘어감) | `alpha beta-gamma` |
| 4 | `)` 뒤 공백 둘의 첫 칸 | `)` |
| 4b | `(` | ` (` |
| 5 | 줄 끝의 쓰이지 않은 칸 | null |
| 5b | `eps`의 p → 쓰이지 않은 칸 | `eps` |
| 6 | soft wrap된 `wrapword12`의 아랫줄 글자(10열 화면) | `wrapword12` |

해석. 식은 design대로 선다 — 2 · 3이 같은 문자열이라 뒤집혀도 앵커 단어가 남는다. 다른 것 하나: design은 "공백 위 더블클릭은
공백 덩어리"라 했는데, 라이브러리는 `WORD_BOUNDARY` 스무 개를 한 부류로 보므로 공백과 이웃한 괄호 · 따옴표가 한 덩어리다
(`)  `). 게다가 `selectionString`이 끝 공백을 잘라 4는 `)`, 4b는 ` (`다. ghostty와 같아 고치지 않는다. 5b — 빈 칸으로 끌어도
`selectWordBetween`이 앵커 쪽으로 거슬러 단어를 찾으므로 선택이 사라지지 않는다. 6 — soft wrap 단어는 통째다.

계측 패치 셋(`main.zig` +19 · `vt_test.zig` +43 · `pointer/check.sh` +10)은 되돌렸다.
