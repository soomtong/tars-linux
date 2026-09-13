# SL-M1 — `shutdown()`이 시그널 목록을 돌고, 호스트 검사가 그 목록을 본다

Date: 2026-09-13
design: `docs/superpowers/specs/2026-09-13-tars-shutdown-latency-design.md`

SL-M0이 A2를 골랐다(실측 6). `kill(-1, .TERM)` 뒤에 `kill(-1, .HUP)`을
보낸다. 이 milestone은 그것을 `power.zig`에 넣고, 호스트에서 볼 수 있는
얇은 검사 둘을 `power_test.zig`에 더한다.

게이트는 이 milestone에서 아직 이 변화를 판정하지 않는다. `power` 체인이
여전히 통과하는 것만 본다 — 판정은 SL-M2다.

## 왜 목록인가 — 두 줄을 나란히 쓰지 않는 이유

가장 짧은 코드는 이것이다.

```zig
_ = linux.kill(-1, .TERM);
std.debug.print("tars-init: sent SIGTERM to every process\n", .{});
_ = linux.kill(-1, .HUP);
std.debug.print("tars-init: sent SIGHUP to every process\n", .{});
```

안 쓰는 이유는 호스트 검사다. 확인 6이 말하듯 호스트에서 `shutdown()`을
부를 수 없으므로(`kill(-1)`이 컨테이너를 죽이고 `reboot(2)`가 개발 기계를
끈다), 위 모양으로 쓰면 검사가 볼 수 있는 것이 하나도 없다. 보낼 시그널을
데이터로 빼내면 그 데이터만은 호스트에서 읽을 수 있다.

얻는 것이 크지 않다는 것을 design 결정 7이 이미 인정했다. 이 검사가 막는
것은 "누가 나중에 `.HUP`을 지우는 것" 하나뿐이다. 그래도 0은 아니고,
비용은 상수 하나와 `for` 한 줄이다.

로그 문구는 `@tagName`으로 만든다. `SIG{s}`에 `TERM`이 들어가면
`sent SIGTERM to every process`가 나오므로, 지금 체인 다섯 자리가 보는
글자가 한 글자도 안 바뀐다(확인 4). 새로 생기는 것은 `sent SIGHUP to
every process` 한 줄뿐이고 그것은 아무도 아직 안 본다.

## Task 1 — `power.zig`에 시그널 목록을 둔다

파일: `init/src/power.zig`

고치는 자리가 둘이다. 하나는 `GRACE_SECONDS` 선언 바로 위에 상수를
더하는 것이고, 하나는 `shutdown()` 안의 `kill(-1, .TERM)` 두 줄을 `for`로
바꾸는 것이다.

### Step 1 — 상수를 더한다

`const GRACE_SECONDS: isize = 3;` 선언의 바로 위에 넣는다. 그 자리를 고른
이유는 둘 다 종료 순서의 정책이고, 읽는 사람이 "무엇을 보내고 얼마나
기다리는가"를 한자리에서 보게 하기 위해서다.

```zig
/// 종료할 때 자식에게 보내는 시그널과 그 순서. `shutdown()`이 이 배열을
/// 순서대로 돈다.
///
/// SIGTERM 하나로는 안 되는 이유가 SL-M0의 실측 1~4에 있다. 대화형 zsh와
/// bash는 SIGTERM을 무시하므로 유예를 꽉 쓰고 SIGKILL에 죽었다 — 종료가
/// 2.9초였다. SIGHUP은 "네가 붙어 있던 터미널이 사라졌다"는 뜻이고 전원이
/// 꺼지는 자리에서 그것은 거짓이 아니라 사실이므로, 셋 다 그 자리에서
/// 죽는다(실측 4. 0.13초).
///
/// 화면 셸이 전부터 빨리 죽던 것이 바로 이 SIGHUP이었다 — `terminal`이
/// 먼저 죽으면서 PTY가 닫히면 커널이 안쪽 셸에게 보내 준다. 콘솔 셸은
/// `/dev/console`을 잡고 있어 닫힐 PTY가 없어서 그 통지를 못 받았다.
/// 이 배열은 커널이 한쪽에만 해 주던 일을 양쪽에 하는 것이다.
///
/// 순서가 계약이다. TERM이 먼저인 것은 그것이 정중한 요청이기 때문이고,
/// SIGTERM에만 정리 코드를 다는 프로그램이 나중에 생겨도 정상 경로를 타게
/// 하려는 것이다(design 결정 3). `power_test`가 이 순서를 본다.
///
/// fish는 이 배열의 첫 칸만으로 죽는다(실측 3). "대화형 셸은 SIGTERM을
/// 무시한다"가 셋 다에 해당하는 것은 아니다.
pub const TERMINATION_SIGNALS = [_]linux.SIG{ .TERM, .HUP };
```

### Step 2 — `shutdown()`이 그 배열을 돈다

지금 이 두 줄을

```zig
    _ = linux.kill(-1, .TERM);
    std.debug.print("tars-init: sent SIGTERM to every process\n", .{});
```

이렇게 바꾼다. 위에 붙어 있던 `-1`에 대한 주석은 그대로 둔다.

```zig
    for (TERMINATION_SIGNALS) |sig| {
        _ = linux.kill(-1, sig);
        // 문구를 @tagName으로 만드는 이유는 체인 다섯 자리가 지금 보는
        // 글자를 그대로 지키기 위해서다. TERM이 들어가면 이 줄은
        // "sent SIGTERM to every process"가 된다.
        std.debug.print("tars-init: sent SIG{s} to every process\n", .{@tagName(sig)});
    }
```

### Step 3 — `reapAll()` 위의 주석을 고친다

지금 `shutdown()` 안에 이 주석이 있다.

```zig
    // 대화형 셸은 SIGTERM을 무시한다(POSIX). 그래서 여기서 false가 나오는
    // 것이 정상이고, SIGKILL은 예외 처리가 아니라 정상 경로의 일부다.
```

이 문장이 이제 틀렸다. 실측 4가 셸 셋 모두 유예 안에 죽는다는 것을
보였으므로 `false`는 더 이상 정상이 아니다. 이렇게 바꾼다.

```zig
    // 여기서 false가 나오면 SIGHUP에도 안 죽는 자식이 있다는 뜻이다.
    // SL-M0 전에는 이것이 정상 경로였다 — 콘솔 셸이 SIGTERM을 무시하고
    // 유예를 꽉 썼다. 지금은 셸 셋이 전부 유예 안에 죽으므로(실측 4)
    // 이 분기는 우리가 모르는 자식이 생겼을 때의 안전망이다.
    // `power/check.sh`가 이 분기를 밟지 않는 것을 판정한다(SL-M2).
```

`GRACE_SECONDS` 선언 위의 주석도 한 문장을 더한다. 지금은 "자식에게 주는
유예. 감독 루프의 재시작 backoff가 1초이고 우리 자식은 터미널과 셸뿐이라
정리에 이보다 오래 걸릴 일이 없다"인데, 그 뒤에 붙인다.

```zig
/// 이 값은 상한이지 실제 대기가 아니다. 두 가지 때문이다 — 평시에는
/// 자식이 전부 그 전에 죽어서 `reapAll()`이 일찍 나오고(실측 4),
/// `monotonicSeconds()`가 초 단위로 자르기 때문에 끝까지 가더라도 실제
/// 대기는 2~3초 사이에서 흔들린다(실측 7).
```

### Step 4 — 빌드한다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer \
  bash -c 'zig build && zig build test'
```

기대: 에러 없이 끝나고 `power_test`가 지금 있는 검사 여섯을 통과한다.
`Action`이나 `Keys`나 `Copy`를 안 건드렸으므로 `terminal` 쪽은 이번에
안 돌려도 되지만, `zig build`를 함께 돌리는 습관은 유지한다.

### Step 5 — 편집 크기를 확인한다

```bash
git diff --stat init/src/power.zig
git diff init/src/power.zig | grep '^-' | grep -v '^---'
```

지운 줄은 넷이어야 한다 — `kill`/`print` 두 줄과 틀린 주석 두 줄. 그
외의 줄이 지워졌으면 되돌린다.

## Task 2 — `power_test.zig`가 그 목록을 본다

파일: `init/src/power_test.zig`

지금 검사가 여섯이고(1~6) 마지막이 "시그널을 거치지 않고도 같은 자리에
요청이 선다"이다. 그 뒤, `main()`이 끝나기 전에 검사 둘을 더한다. 새
검사는 7과 8이 된다.

### Step 1 — 검사를 더한다

```zig
    // 7. 종료 시그널 목록에 SIGHUP이 있어야 한다.
    //
    //    호스트에서 shutdown()을 부를 수 없으므로(kill(-1)이 이 컨테이너를
    //    죽이고 reboot(2)가 개발 기계를 끈다) 이 검사가 보는 것은 데이터
    //    한 벌뿐이다. 막는 것은 하나다 — 누가 .HUP을 지우면 부팅 전에
    //    빨개진다. 진짜 판정은 power 체인에 있다(SL-M2).
    //
    //    목록을 그대로 비교하지 않고 성질만 보는 이유는 tautology를 피하려는
    //    것이다. 상수를 복사한 기대값은 상수와 함께 고쳐지므로 아무것도
    //    안 막는다.
    var hup_at: ?usize = null;
    var term_at: ?usize = null;
    for (power.TERMINATION_SIGNALS, 0..) |sig, i| {
        if (sig == .HUP) hup_at = i;
        if (sig == .TERM) term_at = i;
    }

    if (hup_at == null) {
        std.debug.print("FAIL: TERMINATION_SIGNALS has no SIGHUP; the console shell will sit out the grace period\n", .{});
        return error.NoHangupSignal;
    }
    if (term_at == null) {
        std.debug.print("FAIL: TERMINATION_SIGNALS has no SIGTERM\n", .{});
        return error.NoTermSignal;
    }

    // 8. SIGTERM이 SIGHUP보다 앞이어야 한다.
    //
    //    순서가 뒤집혀도 셸은 죽는다 — 그래서 이 검사가 없으면 아무도
    //    모르게 뒤집힌다. 앞이어야 하는 이유는 의미다(design 결정 3):
    //    정중한 요청을 먼저 보내고, SIGTERM에만 정리 코드를 단 프로그램이
    //    나중에 생겨도 그 코드가 돌게 둔다.
    if (term_at.? > hup_at.?) {
        std.debug.print("FAIL: SIGHUP comes before SIGTERM (term at {d}, hup at {d})\n", .{
            term_at.?, hup_at.?,
        });
        return error.SignalOrderReversed;
    }

    std.debug.print("power_test: the shutdown sends SIGTERM then SIGHUP\n", .{});
```

`power`는 이 파일 맨 위에서 이미 import되어 있다
(`const power = @import("power.zig");`). 새 import가 필요 없다.

### Step 2 — 검사가 통과하는지 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer \
  bash -c 'zig build test 2>&1 | tail -20'
```

기대: `power_test: the shutdown sends SIGTERM then SIGHUP` 한 줄이 나오고
종료 코드가 0이다.

### Step 3 — 되돌림으로 검사가 정말 무언가를 보는지 확인한다

검사가 통과하는 것만으로는 그 검사가 값을 한다는 증거가 안 된다.
반사실 둘을 `/tmp`에 만들어 마운트한다. 저장소 파일은 안 바꾼다.

반사실 A — `.HUP`을 뺀다. `/tmp/sl/power_no_hup.zig`는 Task 1을 끝낸
`power.zig`의 사본이고 그 한 줄만 다르다.

```zig
pub const TERMINATION_SIGNALS = [_]linux.SIG{.TERM};
```

```bash
docker run --rm -v "$PWD":/workspace \
  -v /tmp/sl/power_no_hup.zig:/workspace/init/src/power.zig:ro \
  -w /workspace/init tars-devcontainer bash -c 'zig build test 2>&1 | tail -10'
```

기대: `FAIL: TERMINATION_SIGNALS has no SIGHUP …`이 나오고 종료 코드가
0이 아니다.

반사실 B — 순서를 뒤집는다. `/tmp/sl/power_wrong_order.zig`는 그 한 줄이
이렇다.

```zig
pub const TERMINATION_SIGNALS = [_]linux.SIG{ .HUP, .TERM };
```

```bash
docker run --rm -v "$PWD":/workspace \
  -v /tmp/sl/power_wrong_order.zig:/workspace/init/src/power.zig:ro \
  -w /workspace/init tars-devcontainer bash -c 'zig build test 2>&1 | tail -10'
```

기대: `FAIL: SIGHUP comes before SIGTERM (term at 1, hup at 0)`이 나온다.

반사실을 돌린 뒤 `.zig-cache`가 반사실의 산출물을 들고 있을 수 있다.
실측 30이 그 함정이다 — 다음 명령 전에 컨테이너 안에서 지운다(호스트에서
지우면 바로 뒤의 `zig build`가 `error: FileNotFound`로 죽는다).

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf init/.zig-cache init/zig-out; cd init && zig build && zig build test'
```

## Task 3 — `power` 체인이 여전히 통과하는지 본다

이 milestone은 아직 판정을 안 바꾼다. 그러니 체인은 지금과 똑같이
통과해야 하고, 통과하면서 로그에 새 줄이 하나 늘어 있어야 한다.

약 3분이다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash power/check.sh 2>&1 | tail -30
```

기대 셋.

1. `boot 1/2 PASS` · `boot 2/2 PASS`가 나온다.
2. `note: every child died from SIGTERM alone`이 나온다. 지금까지는
   `note: the grace period expired and SIGKILL finished the job (this is
   the normal path)`이 나오던 자리다 — 이 한 줄이 바뀌는 것이 이
   milestone이 게이트에서 보이는 유일한 흔적이다.
3. 실패하지 않는다. 실패하면 `report_failure`의 marker 목록이 어느 줄이
   없어졌는지 알려 준다.

`note:`의 문구가 이제 정확하지 않다는 것에 주의한다 — SIGTERM이 아니라
SIGHUP이 죽인 것이다. 그 문구를 고치는 것은 SL-M2의 일이다. 여기서는
안 고친다. 검사 둘을 한 milestone에 넣으면 하나가 실패했을 때 원인이
안 갈리기 때문이다.

## Task 4 — 커밋

```bash
git status --short
git diff --stat
git add init/src/power.zig init/src/power_test.zig \
        docs/superpowers/plans/2026-09-13-tars-shutdown-latency-sl-m1.md
git commit -m "Send SIGHUP after SIGTERM so the console shell stops waiting"
```

design의 `Status:` 줄도 함께 고친다.

## 실패했을 때 어디를 보는가

- `linux.SIG`로 배열을 못 만들면 그 타입이 enum이 아닐 수 있다.
  `onSignal(sig: linux.SIG)`가 그 타입을 쓰고 있으므로 타입 자체는 있고,
  막히면 `@import("std").os.linux`의 정의를 직접 읽는다.
- `sig == .HUP` 비교가 막히면 `linux.SIG`가 tagged union일 때다. 그때는
  `std.meta.eql`을 쓴다 — tagged union을 `==`로 비교하는 것은 Zig가
  막는다(HANDOFF의 "시도했으나 안 되는 접근").
- `power` 체인이 `terminal never rendered a prompt`로 죽으면 그것은 이
  변경과 무관한 빌드 실패다. `zig build`를 따로 돌려 본다.
- `note:`가 여전히 grace period 쪽이면 SIGHUP이 안 나간 것이다. 로그에
  `sent SIGHUP to every process` 줄이 있는지 먼저 본다.
