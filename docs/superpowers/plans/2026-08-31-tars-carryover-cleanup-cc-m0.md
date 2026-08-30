# CC-M0 — 이월 숙제 셋을 실제로 없앤다

**Date:** 2026-08-31
**Design:** `docs/superpowers/specs/2026-08-31-tars-carryover-cleanup-design.md`
**Status:** 진행 중

## 이 milestone이 끝나면

- 커널 `.config`에서 `ACPI_EC`와 `PNP_DEBUG_MESSAGES`가 꺼져 있고, 그 상태로
  여덟 체인이 전부 부팅한다.
- `terminal/sanity/`가 없다. 그 도구만 쓰던 `vendor/libghostty-vt/`(98MB)도
  더는 만들어지지 않는다.
- `terminal/vendor/fonts/Hanme_8x4x4.ttf`가 디스크에서 없어졌다.
- `HANDOFF.md`의 이월 숙제에서 그 셋이 "끝난 숙제"로 옮겨지고, **`ACPI_EC`를
  실머신에서 되켠다**는 새 항목이 하나 생긴다.

**편집은 Claude Code가 한다**(design의 "협업 범위의 예외"). 매 편집 뒤
`git diff --stat`으로 더한 줄과 지운 줄을 따로 세고, 지우는 편집은
`git diff | grep '^-'`로 내용을 직접 읽는다.

---

## Task 1 — 커널 `.config`에서 두 항목을 끈다

**Files:** `kernel/.config`

### Step 1: `ACPI_EC` 두 줄

`kernel/.config:383-384`

지울 것:
```
CONFIG_ACPI_EC=y
# CONFIG_ACPI_EC_DEBUGFS is not set
```

넣을 것:
```
# CONFIG_ACPI_EC is not set
```

`ACPI_EC_DEBUGFS`가 함께 없어지는 이유는 그 항목이 `depends on ACPI_EC`라
**심볼 자체가 존재하지 않게 되기** 때문이다(design 위험 2). 남겨 두면
`olddefconfig`가 `build/.config`에서 조용히 지우고, 우리 `.config`만 낡은
줄을 갖게 된다.

### Step 2: `PNP_DEBUG_MESSAGES` 한 줄

`kernel/.config:904`

지울 것:
```
CONFIG_PNP_DEBUG_MESSAGES=y
```

넣을 것:
```
# CONFIG_PNP_DEBUG_MESSAGES is not set
```

`CONFIG_PNP=y`는 그대로 둔다 — `SERIAL_8250_PNP`와 i8042의 PS/2 열거가 그 위에
서 있다.

### Step 3: 빌드 전 bzImage 크기를 적어 둔다

Run:
```bash
ls -l kernel/build/arch/x86/boot/bzImage
```

이 값이 "끄기 전"이다. 판정이 아니라 기록이다.

### Step 4: 커널을 다시 빌드하고 검산 1을 본다

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd kernel && ./build.sh 2>&1 | tail -5
  echo "--- 눌린 값이 살아남았는가 ---"
  grep -E "CONFIG_ACPI_EC|CONFIG_PNP_DEBUG_MESSAGES" build/.config || echo "(두 심볼이 build/.config에 아예 없다)"
  ls -l build/arch/x86/boot/bzImage
'
```

Expected: `build/.config`에
`# CONFIG_ACPI_EC is not set`과 `# CONFIG_PNP_DEBUG_MESSAGES is not set`이
그대로 있다. **`CONFIG_ACPI_EC=y`가 다시 나타나면 거기서 멈춘다** — 그때는
`.config`가 아니라 Kconfig의 프롬프트 유무를 다시 봐야 한다.

`build.sh`가 `.config`의 sha256을 스탬프로 쓰므로 이번에는 반드시 진짜로
빌드한다(2~3분).

---

## Task 2 — 새 커널로 부팅해서 검산 2를 본다

**Files:** 없음(실행만)

### Step 1: ISO까지 다시 만들고 부팅한다

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  set -e
  (cd init && zig build)
  (cd terminal && ./prepare.sh)
  (cd kernel && ./make_initrd.sh)
  (cd boot && ./build.sh && ./make_iso.sh)
' 2>&1 | tail -3
bash out/probe/run_boot.sh
```

`out/probe/run_boot.sh`는 Task 2에서 만드는 짧은 러너다(아래 Step 2).

### Step 2: 러너를 만든다

`out/probe/run_boot.sh` (gitignore 아래라 커밋되지 않는다):
```bash
#!/usr/bin/env bash
# 부팅 한 번을 띄우고 ACPI 관련 줄만 뽑는다. 커널 .config를 고친 뒤
# "깨지지 않았다"를 눈으로 보기 위한 일회성 러너다.
set -euo pipefail
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  LOG=/tmp/boot.log
  qemu-system-x86_64 -cdrom out/tars.iso -serial file:"$LOG" \
    -display none -no-reboot &
  QPID=$!
  for _ in $(seq 1 180); do
    grep -q "Welcome to fish" "$LOG" && break
    kill -0 "$QPID" 2>/dev/null || break
    sleep 1
  done
  sleep 2
  kill "$QPID" 2>/dev/null || true
  wait "$QPID" 2>/dev/null || true
  cp "$LOG" /workspace/out/probe/boot_after.log
'
echo "--- ACPI Error ---"
grep -c "ACPI Error\|ACPI BIOS Error" out/probe/boot_after.log || echo "0 (없다)"
echo "--- EC 흔적 ---"
grep -c "EC_CMD/EC_SC\|ACPI: EC" out/probe/boot_after.log || echo "0 (없다)"
echo "--- fish 배너 ---"
grep -c "Welcome to fish" out/probe/boot_after.log || echo "0 (도달 못 했다)"
```

Expected: `ACPI Error` 0, EC 흔적 0, fish 배너 1 이상.

---

## Task 3 — sanity 도구 둘을 지우기 전에 돌려 본다

**Files:** 없음(실행만)

### Step 1: `stb_truetype_check`를 컨테이너 native로 빌드해서 돌린다

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  set -e
  zig cc -I terminal/vendor -o /tmp/stb_check terminal/sanity/stb_truetype_main.c -lm
  cd terminal && /tmp/stb_check
'
```

Expected: 종료 코드 0. 이 도구는 `vendor/fonts/unifont.otf`를 상대 경로로 읽으므로
`cd terminal`이 필요하다. **결과가 이상하면 지우지 않고 멈춘다**(design 결정 4).

### Step 2: `libghostty_vt_check`는 빌드만 시도하고 왜 못 도는지 남긴다

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  uname -m
  file terminal/vendor/libghostty-vt/lib/libghostty-vt.so.0.1.0
  zig cc -I terminal/vendor/libghostty-vt/include \
    -L terminal/vendor/libghostty-vt/lib -lghostty-vt \
    -o /tmp/vt_check terminal/sanity/libghostty_vt_main.c 2>&1 | tail -5
  echo "exit=$?"
'
```

Expected: 컨테이너가 `aarch64`, 라이브러리가 `x86-64`. 링크가 되든 안 되든
**실행할 수 없다**는 것이 이 Step의 결론이고, 그 이유를 로그로 남기는 것이
목적이다.

---

## Task 4 — sanity 도구와 그 산출물 빌드를 없앤다

**Files:** `terminal/sanity/` (삭제) · `.gitignore` · `terminal/vendor_libghostty_vt.sh` · `check.sh`

### Step 1: 도구 넷을 지운다

Run:
```bash
rm -rf terminal/sanity
```

`.c` 둘은 git이 추적하고, 빌드 산출물 둘은 `.gitignore` 대상이다.

### Step 2: `.gitignore`에서 두 줄을 뺀다

`.gitignore:19-20`

지울 것:
```
terminal/sanity/libghostty_vt_check
terminal/sanity/stb_truetype_check
```

### Step 3: `vendor_libghostty_vt.sh`에서 라이브러리 빌드를 뺀다

`terminal/vendor_libghostty_vt.sh`

지울 것:
```bash
mkdir -p vendor
(cd "$SRC_DIR" && zig build -Demit-lib-vt -Dtarget=x86_64-linux-gnu \
    --prefix ../vendor/libghostty-vt)
```

넣을 것:
```bash
# CC-M0(2026-08-31): 여기에 있던 `zig build -Demit-lib-vt` 한 줄을 뺐다.
#
# 그 줄은 vendor/libghostty-vt/ 아래에 x86_64용 C 라이브러리 98MB를 만들었는데,
# **그것을 읽는 자리가 terminal/sanity/libghostty_vt_main.c 하나뿐이었고** 그
# 도구를 같은 milestone에서 지웠다. 우리 빌드가 쓰는 것은 이 라이브러리가
# 아니라 ghostty-src를 Zig 패키지로 잡은 쪽이다 — build.zig.zon의
# `.ghostty = .{ .path = "ghostty-src" }`와 build.zig의
# `ghostty_dep.module("ghostty-vt")`다.
#
# 그래서 이 스크립트가 하는 일은 이제 소스 트리를 받아 두는 것 하나다.
# 이름을 안 바꾼 이유는 부르는 자리가 둘이기 때문이다 — prepare.sh:14와
# check.sh의 BUILD_STEPS가 보는 ./prepare.sh.
```

### Step 4: `check.sh`의 clean() 주석에서 없어진 것을 뺀다

`check.sh:10`

지울 것:
```
#   terminal/vendor       stb_truetype.h + unifont + libghostty-vt 산출물
```

넣을 것:
```
#   terminal/vendor       stb_truetype.h + unifont
```

### Step 5: 지운 줄을 직접 읽는다 (검산 4)

Run:
```bash
git status --short
git diff --stat
git diff -- .gitignore terminal/vendor_libghostty_vt.sh check.sh | grep '^-' | grep -v '^---'
```

Expected: 지워진 줄이 위에 제시한 것과 정확히 같다.

---

## Task 5 — 검산 3: 빌드가 vendored 라이브러리를 안 쓴다

**Files:** 없음(실행만)

### Step 1: 산출물을 지우고 처음부터 빌드한다

Run:
```bash
rm -rf terminal/vendor/libghostty-vt
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  set -e
  cd terminal && ./prepare.sh && zig build test 2>&1 | tail -20
'
ls terminal/vendor/
```

Expected: `prepare.sh`가 통과하고 `zig build test`의 세 검사가 전부 초록이다.
`terminal/vendor/`에 `fonts`와 `stb_truetype.h`만 남고 `libghostty-vt`가 다시
생기지 않는다. **이것이 "빌드가 그것을 안 쓴다"의 증명이다.**

---

## Task 6 — 옛 폰트 파일을 지운다

**Files:** 없음(gitignore 아래)

Run:
```bash
ls -l terminal/vendor/fonts/
rm -f terminal/vendor/fonts/Hanme_8x4x4.ttf
ls -l terminal/vendor/fonts/
```

Expected: `unifont.otf` 하나만 남는다. `git status`는 아무것도 안 보여 준다 —
**이 항목의 증거는 커밋이 아니라 이 로그다**(design 결정 6).

---

## Task 7 — 기억을 고친다

**Files:** `docs/decisions/project_kernel_config.md`

### Step 1: `ACPI_EC` 문단을 답으로 바꾼다

지울 것:
```
`ACPI_EC`는 **일부러 기본값 `y`로 남겼다.** QEMU의 DSDT를 읽어 본 적이
없어서, EC opregion이 있는데 드라이버가 없으면 AML이 부팅 중에 실패하고 그
사실은 커널을 한 번 더 빌드하고 나서야 알게 되기 때문이다. 이해하는 것은 끄고
이해하지 못하는 것은 남긴다. 실제로는 `ACPI Error:`가 하나도 안 나왔으므로,
DSDT를 읽어 보고 끄는 것이 정리 후보로 남았다(`PNP_DEBUG_MESSAGES`도 같은
후보다).
```

넣을 것:
```
`ACPI_EC`는 HD-M1에서 **일부러 기본값 `y`로 남겼다.** QEMU의 DSDT를 읽어 본
적이 없어서, EC opregion이 있는데 드라이버가 없으면 AML이 부팅 중에 실패하고
그 사실은 커널을 한 번 더 빌드하고 나서야 알게 되기 때문이다. 이해하는 것은
끄고 이해하지 못하는 것은 남긴다.

**CC-M0(2026-08-31)이 그 조건을 채우고 껐다.** 게스트에게 직접 물었다 —
`-serial stdio`로 fish에 `echo /sys/bus/acpi/devices/*`를 넣어 받은 목록에
**Embedded Controller의 HID인 `PNP0C09`가 없다.** `PNP0C09*` 글로브에 fish가
`No matches for wildcard`로 답한 것이 그 증거다. EC 장치가 없으므로 그것을
가리키는 EmbeddedControl opregion을 실행할 AML도 없다.

`PNP_DEBUG_MESSAGES`도 함께 껐다. `drivers/pnp/core.c:220-223`이 `pnp_debug`를
module parameter로 두고 `base.h:179`가 `if (pnp_debug)`로 감싸는데, 우리
cmdline은 `console=ttyS0` 하나뿐이라(`boot/limine.conf:7`) 켜진 적이 없다.
**꺼서 없어지는 것은 실행되지 않는 `dev_printk` 호출뿐이다.**

**실머신으로 갈 때 `ACPI_EC`를 되켠다.** 실제 x86 노트북의 DSDT에는 대개 EC가
있고 배터리·뚜껑·밝기 키가 그 위에 있다. 되켜지 않았을 때의 증상이 "AML이
실패한다"라서 원인까지 가는 길이 멀다.
```

---

## Task 8 — 종료 게이트

Run (background, 약 16분):
```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh
```

Expected: 여덟 체인 3/3. 기준선은 16분 34.78초 · 16분 42.73초 · 16분 42.35초이고
**시간이 줄어들 것을 기대하지 않는다**(design 결정 7).

---

## Task 9 — 마무리

1. design doc의 "CC-M0이 실측한 것" 절을 채운다.
2. `HANDOFF.md`: 이월 숙제 셋을 "끝난 숙제"로 옮기고, **실머신에서 `ACPI_EC`를
   되켠다**를 새 항목으로 더한다. "지금 어디인가"와 게이트 현황을 갱신한다.
3. `docs/decisions/project_carryover_cleanup.md`를 만들고 `MEMORY.md`에 한 줄
   더한다.
4. `CLAUDE.md`의 완료 서브프로젝트 목록에 Carryover Cleanup을 더한다.
5. design doc의 `Status:` 줄을 완료로 고친다.
6. 커밋. **design과 plan을 코드보다 먼저 커밋한다.**
