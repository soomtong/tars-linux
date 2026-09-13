# SL-M2 — 게이트가 유예 만료를 실패로 판정한다

Date: 2026-09-13
design: `docs/superpowers/specs/2026-09-13-tars-shutdown-latency-design.md`

SL-M1이 `shutdown()`을 고쳤지만 게이트는 아직 아무 말도 안 한다. SIGHUP을
도로 빼도 체인 열하나가 전부 초록이다 — 유예 만료를 보는 자리가
`power/check.sh:232~238`의 `note:` 한 줄뿐이고 그것이 어느 쪽이든
통과시키기 때문이다(확인 5).

이 milestone은 그 자리를 판정으로 올린다.

## 무엇을 더하고 무엇을 안 더하나

양성 셋과 음성 둘을 더한다.

| 어디 | 무엇 | 왜 |
|---|---|---|
| `power` 부팅 1 | `sent SIGHUP to every process` | SIGHUP이 실제로 나갔다 |
| `power` 부팅 2 | 같은 줄 | 재시작 경로도 같은 순서를 탄다 |
| `device` | 같은 줄 | 전원 버튼 경로도 같다 |
| `power` 부팅 1 | `grace period expired`가 없다 | 유예를 안 썼다 |
| `power` 부팅 1 | `sent SIGKILL to what was left`가 없다 | 죽일 것이 안 남았다 |

음성 둘을 `device`에는 안 넣는다. 그 체인은 설정 디스크가 없어서 fish로
뜨고, fish는 SIGTERM만으로도 죽는다(실측 3). 그러니 거기 넣은 음성 검사는
SIGHUP을 도로 빼도 초록이다 — 아무것도 안 막으면서 막는 것처럼 보이는
검사이고, SP-M0이 "한 색만 세는 음성 검사"에서 배운 함정과 같은 모양이다.

음성 둘을 `power` 부팅 2에도 안 넣는다. 부팅 2의 로그(`$LOG_A`)에는 종료가
한 번뿐이고 부팅 1의 로그는 다른 파일(`$LOG`)에 있으므로 넣어도 되지만,
같은 성질을 두 번 보는 것이 되고 실패했을 때 어느 부팅인지 읽는 비용만
는다. 부팅 2에서 보는 것은 양성 한 줄로 충분하다.

음성 둘을 따로 두는 이유는 design 결정 5에 있다. `grace period expired`가
없는 것만 보면 `reapAll()`이 아예 안 불린 경우와 안 갈린다. `sent SIGKILL`이
없는 것을 함께 보면 그 경우가 갈린다.

## Task 1 — `power/check.sh` 부팅 1

파일: `power/check.sh`

### Step 1 — 실패 리포트의 marker 목록에 한 줄

`report_failure()` 안, 90줄의 `"tars-init: sent SIGTERM to every process" \`
바로 아래에 넣는다.

```bash
    "tars-init: sent SIGHUP to every process" \
```

이 목록은 판정이 아니라 실패했을 때 사람에게 보여 주는 것이다. 판정 목록과
따로 고쳐야 하는 것이 이 파일의 성질이다.

### Step 2 — 판정 목록에 한 줄

190줄의 같은 줄 아래에 같은 것을 넣는다.

```bash
  "tars-init: sent SIGHUP to every process" \
```

### Step 3 — `note:` 두 줄을 음성 검사 둘로 바꾼다

지금 232~238줄이 이렇다.

```bash
# 관측만 하는 줄. 셸이 SIGTERM을 무시하는 것이 정상이므로 이 줄이 나오는
# 것은 실패가 아니다. 어느 경로였는지 사람이 알 수 있게 남긴다.
if grep -q "tars-init: grace period expired" "$LOG"; then
  echo "note: the grace period expired and SIGKILL finished the job (this is the normal path)"
else
  echo "note: every child died from SIGTERM alone"
fi
```

이렇게 바꾼다.

```bash
# 음성 검사 5 — 유예가 만료되면 안 된다.
#
# SL-M1 전에는 이 줄이 나오는 것이 정상 경로였다. 콘솔 셸이 SIGTERM을
# 무시하고(POSIX) 3초를 버틴 뒤 SIGKILL에 죽었고, 그래서 모든 종료가
# 2.9초였다(SL-M0 실측 1). 지금은 shutdown()이 SIGHUP도 보내므로 셸 셋이
# 전부 그 자리에서 죽는다(실측 4. 0.13초).
#
# 이 줄이 다시 나오면 둘 중 하나다 — SIGHUP이 안 나갔거나, SIGHUP에도 안
# 죽는 자식이 새로 생겼거나. 어느 쪽이든 사람이 전원 버튼 앞에서 3초를
# 기다리게 된다.
if grep -q "tars-init: grace period expired" "$LOG"; then
  report_failure "the grace period expired; something outlived SIGTERM and SIGHUP"
fi

# 음성 검사 6 — 죽일 것이 남으면 안 된다.
#
# 위와 같은 말의 다른 쪽이다. 둘을 따로 보는 이유는 reapAll()이 아예 안
# 불린 경우를 가르기 위해서다(design 결정 5) — 그 경우에는 유예도 안
# 만료되고 SIGKILL도 안 나가지만, 그것은 "잘 끝났다"가 아니라 "종료 순서가
# 안 돌았다"이다.
if grep -q "tars-init: sent SIGKILL to what was left" "$LOG"; then
  report_failure "SIGKILL was needed; the shutdown did not end on its own"
fi

echo "note: every child died inside the grace period"
```

`grep -q`를 파일에 직접 거는 것은 안전하다. GA-M1의 진입 검사가 막는 것은
파이프 뒤의 `-q`이고(앞단이 SIGPIPE를 받는다), 여기에는 파이프가 없다.

## Task 2 — `power/check.sh` 부팅 2

### Step 1 — 실패 리포트의 marker 목록

`report_failure_a()` 안, 279줄의
`"tars-init: shutdown requested (action restart)" \` 아래에 넣는다.

```bash
    "tars-init: sent SIGHUP to every process" \
```

### Step 2 — 판정 목록

373줄 근처의 `"tars-init: sent SIGTERM to every process" \` 아래에 넣는다.

```bash
  "tars-init: sent SIGHUP to every process" \
```

이 목록에 붙은 `★` 주석이 "이 여섯 줄이 재부팅됐다와 우리를 거쳐
재부팅됐다를 가른다"고 적고 있다. 줄이 하나 늘었으므로 그 숫자도 일곱으로
고친다.

## Task 3 — `device/check.sh`

### Step 1 — 실패 리포트의 marker 목록

95줄의 `"tars-init: sent SIGTERM to every process" \` 아래.

```bash
    "tars-init: sent SIGHUP to every process" \
```

### Step 2 — 판정 목록

215줄의 같은 줄 아래.

```bash
  "tars-init: sent SIGHUP to every process" \
```

이 체인에 음성 검사를 안 넣는 이유는 위의 "무엇을 더하고 무엇을 안
더하나"에 있다. 주석으로도 그 자리에 남긴다 — 다음 사람이 "왜 여긴
없지"를 다시 조사하지 않도록.

판정 목록 바로 아래에 넣는다.

```bash
# power 체인에는 유예 만료를 보는 음성 검사가 둘 있는데 여기에는 없다.
# 이 체인은 설정 디스크 없이 떠서 셸이 fish이고, fish는 SIGTERM만으로도
# 죽는다(SL-M0 실측 3). 그래서 여기 넣은 음성 검사는 SIGHUP을 도로 빼도
# 초록이다 — 아무것도 안 막으면서 막는 것처럼 보이게 된다.
```

## Task 4 — HANDOFF의 로그 문구 목록

`HANDOFF.md`의 "로그 문구는 두 곳에 중복된다" 절에
`sent SIGTERM to every process`가 있다. 그 옆에 새 줄을 더한다.

```
`sent SIGTERM to every process` · `sent SIGHUP to every process`(SL-M1) ·
```

## Task 5 — 체인 둘을 돌린다

`power`가 약 3분, `device`가 약 2분이다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  bash power/check.sh 2>&1 | tail -20
  bash device/check.sh 2>&1 | tail -20'
```

기대 셋.

1. `boot 1/2 PASS` · `boot 2/2 PASS` · `PM-M1 PASS`
2. `note: every child died inside the grace period`
3. `HD-M2 PASS`(device 체인의 통과 문구)

## Task 6 — 반사실. 마운트가 둘 필요하다

SIGHUP을 빼면 `power_test`의 검사 7이 부팅 전에 죽인다. 그러면 게이트가
새 판정을 보는 자리까지 못 간다 — SD-M2가 같은 자리에서 배운 것이다.
그래서 사본을 둘 마운트한다.

사본 A는 `/tmp/sl/power_no_hup.zig`이고 SL-M1에서 이미 만들었다
(`TERMINATION_SIGNALS = [_]linux.SIG{.TERM};`).

사본 B는 `/tmp/sl/power_test_blind.zig`다. `init/src/power_test.zig`의
사본이고, 검사 7의 `return error.NoHangupSignal;`을 주석으로 눕힌다.

```zig
    if (hup_at == null) {
        std.debug.print("FAIL: TERMINATION_SIGNALS has no SIGHUP; the console shell will sit out the grace period\n", .{});
        // SL-M2 반사실 전용. 호스트 검사가 먼저 죽이면 게이트가 무엇을
        // 보는지 확인할 수 없다.
        // return error.NoHangupSignal;
    }
```

`term_at.? > hup_at.?`도 `hup_at`이 null이면 터지므로, 검사 8도 함께
눕힌다.

```zig
    if (hup_at != null and term_at.? > hup_at.?) {
```

```bash
docker run --rm -v "$PWD":/workspace \
  -v /tmp/sl/power_no_hup.zig:/workspace/init/src/power.zig:ro \
  -v /tmp/sl/power_test_blind.zig:/workspace/init/src/power_test.zig:ro \
  -w /workspace tars-devcontainer bash -c '
    rm -rf init/.zig-cache init/zig-out
    bash power/check.sh 2>&1 | tail -25'
```

기대: `FAIL: the grace period expired; something outlived SIGTERM and
SIGHUP`이 나오고 종료 코드가 0이 아니다. 그 앞에 marker 목록이 찍히는데
거기 `MISSING tars-init: sent SIGHUP to every process`가 함께 있어야 한다.

반사실 뒤에 캐시를 컨테이너 안에서 지운다(실측 30 · `project_zig_out_staleness`).

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf init/.zig-cache init/zig-out; cd init && zig build && zig build test'
```

## Task 7 — 루트 게이트

약 28분이라 Bash 도구의 타임아웃을 넘는다. `run_in_background`로 돌린다.

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } > /tmp/gate.log 2> /tmp/gate.time
```

기대: 3/3. 시간은 기준선(29분 24.06초)과 비교하되, 줄어든 값이 실측 11의
약 15초라면 잡음 안이므로 갈렸다고 말하지 않는다.

## Task 8 — 문서와 커밋

design의 `Status:`를 완료로 고치고, `HANDOFF.md`를 다시 쓰고,
`docs/decisions/`에 기억 파일을 하나 만들고 `MEMORY.md`에 한 줄 더한다.
`CLAUDE.md`의 완료 표에도 한 줄 더한다.

```bash
git add -A
git commit -m "Make the gate fail when the grace period expires"
```

## 실패했을 때 어디를 보는가

- 체인이 `MISSING tars-init: sent SIGHUP to every process`로 죽으면 initrd가
  옛 `init`을 담고 있을 수 있다. 캐시를 컨테이너 안에서 지우고 다시 빌드한다.
- 반사실이 새 판정이 아니라 `power_test`에서 죽으면 사본 B의 눕히기가
  덜 된 것이다. `zig build test`를 따로 돌려 어느 검사가 죽이는지 본다.
- `note:` 줄이 아예 안 나오면 그 앞의 음성 검사 둘 중 하나가 `report_failure`
  로 빠져나간 것이다. 그 함수는 `exit 1`로 끝난다.
