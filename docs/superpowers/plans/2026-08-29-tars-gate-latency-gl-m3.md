# TARS Gate Latency GL-M3 Implementation Plan

> **협업 방식(이 저장소 규칙):** 구현 파일 편집은 **사용자**가 한다. 각 Step의
> "넣을 것"/"지울 것"을 그대로 넣으면 된다. 빌드·검사·QEMU·게이트 실행과
> git commit은 **Claude**가 한다.

**Goal:** `terminal`을 Debug에서 풀어 준다. TF-M4부터 네 서브프로젝트를 건너온
"이 바이너리는 Debug에 묶여 있다"는 제약을 없애고, 49.4MB를 10.6MB로 줄인다.

**Design doc:** `docs/superpowers/specs/2026-08-26-tars-gate-latency-design.md`의
"재개 (2026-08-28)" 절. 결정 9·10과 착수 전 실측 2·3이 내용을 이미 정해 두었다.

**Architecture:** `@cImport` 세 곳에서 fortify를 끄고, `build.zig`에 **게스트로
가는 것 전용 최적화 옵션**을 만들어 기본값을 `ReleaseSafe`로 둔다. 호스트 검사
모듈은 기존 `optimize`(기본 Debug)를 그대로 쓴다. **체인 스크립트는 한 줄도 안
바뀐다** — `terminal/prepare.sh:20`이 옵션 없이 `zig build`를 부르므로 여섯
체인 전부에 기본값이 저절로 흘러간다.

**Tech Stack:** Zig 0.16, glibc 헤더, QEMU

---

## 이 milestone은 게이트 시간 안건이 아니다

**이것을 먼저 적어 두는 이유는 판정 기준이 달라지기 때문이다.** 착수 전 측정이
버는 것과 잃는 것이 거의 같다는 것을 이미 보였다.

| | 버는 것 | 잃는 것 |
|---|---|---|
| `make_initrd.sh` | 회차당 0.97초 × 24회차 = **23초** | — |
| clean 빌드 1회차 | — | 47.6 → 70.9초 = **23초** |

**그러므로 "게이트 시간이 안 줄었다"는 실패가 아니라 예측대로다.** 크게 늘었다면
그것이 실패다. 이 milestone이 얻는 것은 셋이다.

1. **initrd가 16,199,658 → 10,988,958바이트가 된다**(−32.2%).
2. **게스트에서 도는 코드가 최적화된다.** `searchAll()`의 60~70밀리초와 첫
   프레임 209밀리초를 만드는 코드가 전부 ReleaseSafe가 된다. **이것이 사람이
   실제로 겪는 것이다.**
3. **제약 자체가 없어진다.** 앞으로 `terminal`에 무엇을 더할 때 "Debug라서
   느리다"를 감수할 이유가 사라진다.

## 착수 전에 이미 확정된 사실 — 다시 조사하지 않는다

전부 2026-08-28에 실행으로 확인했다. `HANDOFF.md`의 "GL-M3이 착수 전에 이미
확정한 것"과 같은 내용이다.

**1. fortify 벽은 셋이다.** `drm.zig:3`(`fcntl.h`) · `main.zig:8`(`poll.h`) ·
`pty.zig:3`(`pty.h`). `input.zig`의 `linux/input.h`(커널 UAPI)와 `font.zig`의
`stb_truetype.h`는 무관하다. **`drm.zig`만 고치면 에러가 6개에서 1개로 줄 뿐이고,
남는 하나는 `C import failed`가 아니라 `expected type 'c_int', found 'bool'`이라
같은 원인으로 보이지 않는다.**

**2. 셋에 `@cDefine`을 넣으면 빌드되고 `zig build test`도 PASS다.**

**3. `ghostty_dep`까지 박는 것이 공짜다.** `exe_mod`만 박으면 11,218,920바이트에
clean 빌드 71.0초, 둘 다 박으면 **10,577,200바이트에 70.9초**다.

**4. 증분 빌드는 안 느려진다.** 3.17초 대 3.18초다. 게이트 24회차 중 23회차가
증분이므로 이것이 "게이트 시간이 본전"의 근거다.

## 이번에 정하는 것 셋 (design doc이 안 정한 자리)

### 결정 1. 이유는 `drm.zig`에만 길게 적고 나머지 둘은 그 자리를 가리킨다

같은 `@cDefine` 줄이 세 파일에 들어간다. **셋에 같은 설명을 세 벌 두면 갱신이
어긋난다** — 이 저장소가 로그 문구에서 이미 겪고 있는 병이다. `drm.zig`가 첫
발견 자리이고 `project_zig_c_uapi_rule`이 지목해 온 파일이므로 거기에 적는다.

### 결정 2. 세 자리에 같은 표식을 남긴다

`@cImport`를 `b.addTranslateC`로 옮기면([[project_zig_c_uapi_rule]]이 적어 둔
0.16 권장 경로) 이 우회가 필요 없어질 수 있다. **그때 지울 자리를 찾을 수
있도록** 세 줄에 `GL-M3`을 똑같이 적는다. `rg 'GL-M3' terminal/src`로 셋이 한
번에 나오는 것이 이 표식의 값어치다.

### 결정 3. 에러 트레이스는 "심볼이 남았는가"까지만 확인한다

`init/build.zig`의 주석은 "게스트 안 에러 트레이스는 살아 있다"고 단언하는데,
**그것은 ReleaseSafe의 정의에서 온 말이지 실행으로 본 것이 아니다.** 그리고
`make_initrd.sh:84~89`가 이미 적어 두었듯 **Debug에서도 트레이스가 안 나왔다**
(2026-08-12 TF-M4 실측: strip 버전은 `???` 주소 두 줄, 심볼 버전은 트레이스
자체가 없었다).

**그러므로 "트레이스가 읽히는가"는 이 milestone이 확인할 대상이 아니다** —
Debug일 때도 안 읽혔으므로 비교 대상이 없다. 확인할 것은 **`.debug_info`
섹션이 남아 있는 것**뿐이고, 그것이 곧 "strip과 다르다"의 증명이다.

---

## Task 1: fortify를 세 자리에서 끈다

### Step 1: `drm.zig` (사용자가 편집)

`terminal/src/drm.zig:3~7`.

**지울 것:**

```zig
const c = @cImport({
    @cInclude("fcntl.h");
```

**넣을 것:**

```zig
// GL-M3: glibc의 fortify를 끈다. 이 한 줄이 없으면 최적화 모드에서
// `@cImport` 전체가 `error: C import failed`로 죽는다 — Debug가 아닌 모드에서
// Zig가 `-D_FORTIFY_SOURCE`를 붙이면 `bits/fcntl2.h`가 활성화되고, 그 안의
// `__open_too_many_args()`처럼 `__attribute__((error))`가 달린 선언을
// translate-c가 번역하지 못한다. TF-M4가 2026-08-12에 겪고
// docs/decisions/project_zig_c_uapi_rule.md에 적어 둔 그대로다.
//
// **버퍼 검사를 잃어도 되는 이유는 대체물이 있기 때문이다.** ReleaseSafe는
// Zig 자신의 안전 검사(경계·오버플로·널)를 전부 켠 채로 두고, 여기서
// 가져오는 것은 open/ioctl/mmap 래퍼라 glibc의 fortify가 볼 버퍼가 애초에
// 우리 코드에 없다.
//
// **같은 줄이 main.zig와 pty.zig에도 있다.** 셋을 다 꺼야 빌드된다 —
// drm.zig만 고치면 에러가 6개에서 1개로 줄 뿐이고, 남는 하나는 모양이 달라서
// 같은 원인으로 보이지 않는다(main.zig의 `c.poll`이 `expected type 'c_int',
// found 'bool'`을 낸다). 이유를 여기에만 적는 것은 셋에 같은 설명을 두면
// 갱신이 어긋나기 때문이다.
//
// `@cImport`를 `b.addTranslateC`로 옮기게 되면 셋 다 필요 없어질 수 있다.
// 그때 찾을 수 있도록 세 자리에 `GL-M3`을 똑같이 적어 두었다.
const c = @cImport({
    @cDefine("_FORTIFY_SOURCE", "0"); // GL-M3
    @cInclude("fcntl.h");
```

### Step 2: `main.zig` (사용자가 편집)

`terminal/src/main.zig:8~10`.

**지울 것:**

```zig
const c = @cImport({
    @cInclude("poll.h");
});
```

**넣을 것:**

```zig
// fortify를 끄는 이유는 drm.zig의 @cImport 위에 적혀 있다. 이 파일이 걸리는
// 자리는 헤더가 아니라 `c.poll` 호출이다 — fortify가 켜지면 poll이 함수가
// 아니라 매크로가 되고, 그 번역이 c_int 자리에 bool을 놓는다.
const c = @cImport({
    @cDefine("_FORTIFY_SOURCE", "0"); // GL-M3
    @cInclude("poll.h");
});
```

### Step 3: `pty.zig` (사용자가 편집)

`terminal/src/pty.zig:3~7`.

**지울 것:**

```zig
const c = @cImport({
    @cInclude("pty.h");
```

**넣을 것:**

```zig
// fortify를 끄는 이유는 drm.zig의 @cImport 위에 적혀 있다.
const c = @cImport({
    @cDefine("_FORTIFY_SOURCE", "0"); // GL-M3
    @cInclude("pty.h");
```

### Step 4: Debug 상태에서 여전히 빌드되는지 본다 (Claude가 실행, 약 2분)

**최적화 모드를 바꾸기 전에 이 편집만으로 아무것도 안 깨지는 것을 먼저 본다.**
Task 1과 Task 2를 갈라 놓은 이유가 이것이다 — 뒤에서 깨지면 원인이 fortify인지
최적화인지 즉시 갈린다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer bash -c 'zig build && zig build test'
```

### Step 5: 커밋 (Claude가 실행)

---

## Task 2: 게스트로 가는 두 모듈의 기본값을 `ReleaseSafe`로 만든다

**design 결정 11대로 박지 않고 기본값이 있는 옵션으로 둔다.** 게이트가 부팅하는
바이너리가 곧 제품이므로 기본값은 배포되는 것과 같아야 하고, 개발자가 내려갈
문은 플래그 하나로 둔다. **축의 이름은 "개발이냐 배포냐"가 아니라 "게스트로
가느냐"다** — 호스트 검사는 언제나 Debug가 맞다.

### Step 1: 옵션을 만든다 (사용자가 편집)

`terminal/build.zig:10`의 `const optimize = b.standardOptimizeOption(.{});`
**바로 아래에 넣을 것:**

```zig

    // GL-M3: **게스트로 가는 것**의 최적화 모드. 위의 `optimize`와 갈라 놓은
    // 것이 이 milestone의 핵심 결정이다.
    //
    // 이 저장소에는 별도의 배포 경로가 없다 — prepare.sh가 만든 바이너리가
    // 그대로 initrd에 들어가고 게이트가 그것을 부팅한다. **게이트가 부팅하는
    // 바이너리가 곧 제품이다.** 그래서 "개발은 Debug, 배포는 Release"를 그대로
    // 옮기면 게이트가 배포되지 않는 것을 검사하게 된다
    // (docs/decisions/project_gate_chain_composition.md의 "게이트는 자기가 안
    // 보는 것을 통과시킨다"와 같은 병이다). **기본값이 배포되는 것과 같아야
    // 하는 이유가 이것이다.**
    //
    // 그래도 문은 둔다. 소스를 고친 뒤 `zig build`가 Debug 17.7초 대
    // ReleaseSafe 27.1초라 개발 한 바퀴에 9.4초가 붙기 때문이다. 다만 그
    // 문은 명시적으로 열어야 한다:
    //
    //   zig build -Dguest-optimize=Debug
    //
    // **이 문이 게이트를 흔들지 않는다.** clean()이 zig-out을 지우고 여덟
    // 체인이 각자 부르는 prepare.sh:20이 **옵션 없이** zig build를 부르므로,
    // 손으로 남긴 Debug 바이너리는 다음 게이트가 기본값으로 덮어쓴다.
    //
    // 위의 `optimize`는 이제 **호스트 검사 전용**이다. 그쪽은 게스트에 안
    // 가므로 크기와 무관하고, 최적화하면 `zig build test`만 느려진다
    // (소스를 고친 뒤 9.5초 대 25.8초). init/build.zig:29가 같은 선을 긋는다.
    const guest_optimize = b.option(
        std.builtin.OptimizeMode,
        "guest-optimize",
        "게스트로 가는 terminal 바이너리의 최적화 모드 (기본 ReleaseSafe)",
    ) orelse .ReleaseSafe;
```

### Step 2: 두 모듈이 그것을 쓰게 한다 (사용자가 편집)

`exe_mod`에서 **지울 것:**

```zig
        .optimize = optimize,
```

**넣을 것:**

```zig
        // GL-M3: Debug 49,373,160 → ReleaseSafe 10,577,200바이트(78.6% 감소).
        // initrd는 16,199,658 → 10,988,958바이트가 된다. 이 길이 열린 것은
        // fortify를 세 자리에서 껐기 때문이다(drm.zig · main.zig · pty.zig).
        .optimize = guest_optimize,
```

`ghostty_dep`에서 **지울 것:**

```zig
    const ghostty_dep = b.dependency("ghostty", .{
        .target = target,
        .optimize = optimize,
    });
```

**넣을 것:**

```zig
    // 이 의존도 게스트로 간다. 함께 옮기는 것이 공짜라는 것을 쟀다 —
    // exe_mod만 옮기면 11,218,920바이트에 clean 빌드 71.0초이고, 둘 다
    // 옮기면 10,577,200바이트에 70.9초다. **작아지면서 안 느려진다.**
    //
    // 그리고 이쪽이 성능의 본체다. searchAll()의 60~70밀리초를 쓰는 코드가
    // 여기 있다(CN-M1 실측). 아래 ghostty_host_dep은 호스트 검사용이라
    // `optimize`를 그대로 쓴다.
    const ghostty_dep = b.dependency("ghostty", .{
        .target = target,
        .optimize = guest_optimize,
    });
```

### Step 3: 기본값과 문을 둘 다 확인한다 (Claude가 실행, 약 4분)

**옵션이 있다는 것 자체가 새 검사 대상이다.** 기본값만 보면 문이 열리는지
모르고, 문만 보면 기본값이 맞는지 모른다.

```bash
zig build                          # 10,577,200 이어야 한다
zig build -Dguest-optimize=Debug   # 49,373,560 이어야 한다
zig build test                     # PASS, 그리고 이 값은 옵션과 무관해야 한다
zig build --help                   # guest-optimize가 설명과 함께 나와야 한다
```

**마지막에 옵션 없이 한 번 더 빌드해서 zig-out을 기본값으로 되돌린다** —
그러지 않으면 다음에 `make_initrd.sh`를 부르는 사람이 Debug 바이너리를 담는다.
(게이트는 `clean()` 덕분에 안전하지만 손으로 돌릴 때는 아니다.)

또 `readelf -S`로 `.debug_info`가 남아 있는 것을 본다(결정 3).

### Step 3: 커밋 (Claude가 실행)

---

## Task 3: `make_initrd.sh`의 낡은 주석을 고친다

### Step 1: 주석 (사용자가 편집)

`kernel/make_initrd.sh:84~89`.

**지울 것:**

```bash
# terminal은 Debug 빌드라 42MB이고 대부분이 디버그 심볼이다. strip하면
# initrd가 6.5MB까지 줄지만(부팅 25초 → 34초 차이), 심볼을 남긴다 —
# strip한 바이너리에서는 QEMU 안의 에러 트레이스가 원리적으로 복구
# 불가능해지기 때문이다. 단, 심볼이 있다고 트레이스가 바로 읽히지는
# 않았다(2026-08-12 TF-M4 실측: strip 버전은 `???` 주소 두 줄, 심볼 버전은
# 트레이스 자체가 없었다 — 원인 미규명). 크기는 아래 gzip으로 처리한다.
```

**넣을 것:**

```bash
# GL-M3(2026-08-29)에서 terminal이 ReleaseSafe가 됐다. 49,373,160 →
# 10,577,200바이트이고, 이 파일이 만드는 initrd는 16,199,658 →
# 10,988,958바이트다.
#
# **strip은 여전히 안 한다.** ReleaseSafe가 심볼을 지우지 않고도 78.6%를
# 줄이므로 strip을 검토할 이유가 없어졌다. 옛 주석은 "심볼을 남기는 이유는
# 에러 트레이스"라고 적고 바로 다음 문장에서 "단, 심볼이 있다고 트레이스가
# 바로 읽히지는 않았다"고 스스로를 부정하고 있었다 — 2026-08-12 TF-M4
# 실측에서 strip 버전은 `???` 주소 두 줄, 심볼 버전은 트레이스 자체가
# 없었다. **그 이유는 지금도 규명되지 않았고, Debug에서도 안 읽혔으므로
# ReleaseSafe에서 안 읽히는 것은 회귀가 아니다.**
```

### Step 2: initrd를 만들고 크기를 확인한다 (Claude가 실행, 약 1분)

기대값은 **10,988,958바이트**다.

### Step 3: 커밋 (Claude가 실행)

---

## Task 4: 루트 게이트로 판정한다

### Step 1: 게이트를 세 번 돌린다 (Claude가 실행, 약 60분)

`run_in_background`로 돌린다. **다른 무거운 명령을 동시에 돌리지 않는다** —
이 게이트는 전부 CPU 바운드다.

**볼 것 넷.**

1. **여덟 체인 3/3 통과, 세 번 모두.** 최적화 모드를 바꾸는 것은 **검증 대상
   바이너리 자체를 바꾸는 일**이고 TF-M4가 이 변경을 미룬 이유가 정확히
   이것이었다. **여덟 체인 전부가 그 바이너리를 딛고 서 있으므로 통과가 곧
   증명이다.**
2. **시간.** 기준선 19분 11초~16초에서 **크게 안 변하는 것**이 예측이다.
   줄면 좋고, **1분 넘게 늘면 착수 전 측정이 틀린 것이므로 어디가 늘었는지
   단계별로 다시 잰다.**
3. **`skipping make`가 정확히 23회.** GL-M1의 계약을 함께 본다.
4. **게스트 실행 시간.** 같은 `docker run` 안에서 체인 로그를 뒤져
   `find> submit us=`와 `render> first frame`을 앞뒤로 비교한다.

   ```bash
   grep -ahoE 'find> submit .* us=[0-9]+' /tmp/tmp.*
   grep -ah 'render> first frame' /tmp/tmp.*
   ```

   Debug에서 `us=`는 58,000~70,000이고 첫 프레임은 209밀리초다. **이 값이
   줄어드는 것이 "사람이 실제로 겪는 것이 나아졌다"의 증명이고, 게이트 시간이
   본전인 이 milestone에서 유일하게 좋아지는 숫자다.**

### Step 2: 문서와 기억을 갱신한다 (Claude가 작성)

- design doc의 GL-M3 절에 결과를 `>` 인용으로 적고, **`Status:`를 서브프로젝트
  종료로 갱신한다.**
- `docs/decisions/project_gate_latency.md`와
  `docs/decisions/project_zig_c_uapi_rule.md`를 갱신한다. **후자는 "벽이
  `drm.zig` 하나"라고 적어 둔 자리를 고쳐야 한다** — GL-M3이 그 문서를 직접
  부정한다.
- `HANDOFF.md`와 `CLAUDE.md`를 갱신한다.

### Step 3: 커밋 (Claude가 실행)

---

## 실패했을 때 어디를 보는가

**게이트가 깨지면 먼저 "빌드가 안 된다"와 "돌다가 다르게 동작한다"를 가른다.**

- **빌드가 안 되면** fortify가 남은 자리가 더 있는 것이다. 착수 전 측정은
  `input.zig`와 `font.zig`가 무관하다고 보았지만, 그것은 **지금 소스 기준**이다.
- **돌다가 다르면** 최적화가 정의되지 않은 동작을 다르게 다룬 것이다. Zig는
  Debug와 ReleaseSafe 모두 안전 검사를 켜므로 그 폭이 좁지만 **좁다는 것이지
  없다는 것이 아니다.** 이때는 `-Doptimize=Debug`로 되돌려 같은 체인이 통과하는
  것을 먼저 확인해 원인을 최적화로 좁힌다.
- **`zig build test`만 깨지면** 그것은 이 변경과 무관하다. 호스트 검사 모듈은
  `optimize`를 그대로 쓰므로 이 milestone이 건드리지 않는다.
