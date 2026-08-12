# TARS Terminal Foundation — TF-M4 종료 게이트 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **단, 이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md` 참고):** 파일
> 작성과 명령 실행은 사용자가 직접 하고, Claude는 각 Step의 정확한 내용을
> 제시하고 결과를 해석한다. 위 SUB-SKILL 문구는 다른 저장소용 기본값이며 이
> 저장소에는 적용하지 않는다.

**Goal:** TF-M4를 완료한다 — 커널 빌드 → init 빌드 → terminal(Zig) 빌드 →
initrd 생성 → QEMU 부팅 → 화면 렌더링 → 키 주입 → 셸 실행 결과 확인까지의
전체 체인을 재현 가능한 단일 스크립트로 묶어 **3회 연속 성공**시켜 Terminal
Foundation 서브프로젝트의 종료 게이트를 통과한다.

**Architecture:** 세 갈래의 작업이 있다.

1. **kms 잔재 정리 + DF 체인 은퇴.** TF-M2에서 `kernel/make_initrd.sh`가
   `kms` 대신 `terminal`을 initrd에 넣도록 바뀌었고 `init/src/main.rs`도
   `/terminal`을 fork한다. 그 결과 `display/check.sh`의 "(10,10)이
   `#FF0000`인가" 검사는 **더 이상 통과할 수 없다**(빨강을 그리던 프로세스가
   부팅되지 않는다). 되살리려면 커널 cmdline으로 kms/terminal을 고르는 부팅
   모드 스위치를 새로 만들어야 하는데, DF가 검증하던 DRM/KMS present 경로는
   TF 체인이 매 회차 실제 픽셀을 띄우며 이미 검증한다 — 죽은 테스트를 위해
   부팅 경로에 분기를 넣지 않는다(YAGNI). DF 체인은 루트 게이트에서 빼고
   `display/check.sh`에는 은퇴 주석을 단다. 아무도 실행하지 않는 `kms`를
   매 회차 빌드하던 `boot/check.sh`의 줄도 없앤다. `kms/` 크레이트와
   `display/check.sh` 파일 자체는 참조 구현으로 남겨둔다.
2. **`terminal/check.sh` 견고화.** 3회 연속 통과를 요구하는 순간 (a) vendor
   트리 부재, (b) 고정 `sleep 30` 타이밍, (c) 스크린샷 잔여 파일이 전부
   실패 요인이 된다. vendor 사전 준비를 스크립트 안으로 넣고, 고정 대기를
   serial 로그 폴링(`terminal: screen>`)으로 바꾸고, 스크린샷을 `out/tf/`로
   옮겨 성공 시 지운다.
3. **루트 `check.sh`를 BF + TF 두 체인으로 재구성.** BF 체인을 남기는 이유는
   그것만이 limine ISO 부팅 경로를 검증하기 때문이다(TF는 `-kernel`/`-initrd`
   직접 부팅). `clean()`은 **빌드 산출물만** 지운다 —
   `terminal/ghostty-src`, `terminal/vendor`, `terminal/zig-pkg`는
   네트워크에서만 복구되는 vendor 트리/패키지 캐시라 절대 지우지 않는다.

**Tech Stack:** bash, Docker(`tars-devcontainer` 이미지), QEMU monitor
`screendump` + `sendkey`, ImageMagick `compare -metric AE`, Zig 0.16 빌드

---

## 사전 준비

이 plan의 모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서
실행한다. TF-M3까지 완료되어 `terminal/check.sh` 단독 실행이 PASS함이 확인된
상태여야 한다(최신 커밋 `9152173`, working tree 깨끗함).

**이번 milestone의 결정 사항(design doc의 "TF-M4 — 종료 게이트: 전체 체인을
스크립트로 묶어 3회 연속 검증"을 구체화):**

- 루트 게이트 체인 구성은 **BF + TF**. DF 체인은 은퇴(위 Architecture 1번).
- 3회 연속 실행 중 중간 실패 시 즉시 중단(fail-fast) — BF-M4/DF-M3와 동일.
- 새 기능은 만들지 않는다. 이번 milestone의 산출물은 전부 스크립트와 문서다.

---

### Task 1: kms 잔재 정리와 DF 체인 은퇴

**Files:**
- Modify: `boot/check.sh:8`
- Modify: `display/check.sh:1-4`

- [x] **Step 1: `boot/check.sh`에서 kms 빌드 줄 제거**

`boot/check.sh`의 6~11행이 지금 이렇다.

```bash
(cd ../kernel && ./build.sh)
(cd ../init && cargo build --release)
(cd ../kms && cargo build --release)
(cd ../kernel && ./make_initrd.sh)
./build.sh
./make_iso.sh
```

가운데 `kms` 줄을 지워 다섯 줄로 만든다.

```bash
(cd ../kernel && ./build.sh)
(cd ../init && cargo build --release)
(cd ../kernel && ./make_initrd.sh)
./build.sh
./make_iso.sh
```

이 줄은 DF-M3(2026-08-07)에서 `make_initrd.sh`가 `kms` 바이너리를 initrd에
복사하기 때문에 추가됐던 것이다. TF-M2에서 그 복사가 `terminal`로 바뀌었으므로
(`kernel/make_initrd.sh:23`), 지금은 **아무도 쓰지 않는 바이너리를 매 회차
Rust로 컴파일**하고 있을 뿐이다. `boot/check.sh`는 `set -euo pipefail`이라
빌드 실패 시 `-e`가 알아서 중단시킨다 — 나머지 줄의 스타일은 그대로 둔다.

- [x] **Step 2: `display/check.sh` 맨 위에 은퇴 주석 추가**

`display/check.sh`의 1~4행을 아래로 교체한다(`cd "$(dirname "$0")"` 다음 줄부터
기존 내용은 손대지 않는다).

```bash
#!/usr/bin/env bash
#
# [은퇴됨 — 2026-08-12, TF-M4]
#
# 이 스크립트는 부팅 후 화면 (10,10) 픽셀이 kms 바이너리가 칠한 빨강
# (#FF0000)인지 검사한다. TF-M2에서 kernel/make_initrd.sh가 initrd에 kms 대신
# terminal을 넣도록 바뀌었고 init/src/main.rs도 /terminal을 fork하므로,
# 부팅된 시스템에는 이제 kms가 존재하지 않는다 — 이 검사는 실행하면 반드시
# FAIL한다.
#
# 되살리려면 커널 cmdline으로 kms/terminal 중 무엇을 띄울지 고르는 부팅 모드
# 스위치가 필요한데, 이 스크립트가 검증하던 DRM/KMS present 경로는
# terminal/check.sh가 매 회차 실제로 픽셀을 띄우며 이미 검증한다. 그래서 루트
# check.sh의 체인 목록에서 빠졌다(TF-M4 plan Architecture 1번 참고).
#
# 파일과 kms/ 크레이트를 남겨두는 것은 Rust로 쓴 DRM 참조 구현으로서의
# 가치 때문이다. 실행하지 말 것.
set -uo pipefail

cd "$(dirname "$0")"
```

- [x] **Step 3: 변경 내용 확인**

Run:
```bash
git diff --stat && rg -n "kms" boot/check.sh display/check.sh terminal/check.sh check.sh
```

Expected: `boot/check.sh`와 `display/check.sh` 두 파일만 변경됨.
`rg` 결과에서 `boot/check.sh`에는 `kms`가 **한 줄도 안 나오고**,
`display/check.sh`에는 은퇴 주석 안의 언급만 나오며, `check.sh`(루트)에는
`clean()`의 `kms/target` 한 줄이 아직 남아 있다(Task 3에서 정리한다).

- [x] **Step 4: 커밋**

```bash
git add boot/check.sh display/check.sh
git commit -m "Retire the display gate and stop building the unused kms crate"
```

- [x] **Step 5: TF-M3가 남긴 스크린샷 정리**

Run:
```bash
ls -la tf-m3-*.ppm && rm -f tf-m3-*.ppm && git status --short
```

Expected: 3.1MB짜리 `tf-m3-after-*.ppm`, `tf-m3-before-*.ppm`,
`tf-m3-cat.ppm` 세 개가 지워진다. 전부 `.gitignore`의 `*.ppm`에 걸리는
추적되지 않는 파일이라 `git status`는 그대로 깨끗하다(커밋할 것 없음).
Task 2에서 스크린샷 출력 위치를 `out/tf/`로 옮기므로 앞으로는 루트에 쌓이지
않는다.

---

### Task 2: `terminal/check.sh`를 3회 반복에 견디도록 견고화

**Files:**
- Modify: `terminal/check.sh` (전체 교체)

- [x] **Step 1: `terminal/check.sh` 전체 교체**

아래 내용으로 파일 전체를 바꾼다. 기존 대비 달라지는 곳은 네 군데이며,
각각 주석으로 표시해 뒀다.

```bash
#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

REPO_ROOT="$(cd .. && pwd)"

# --- (변경 1) vendor 사전 준비 ----------------------------------------
# 세 스크립트는 모두 "산출물이 이미 있으면 아무것도 안 한다"라서 반복 실행에
# 안전하다. ghostty-src는 다운로드에 더해 lib-vt 빌드까지 하므로 트리가 없을
# 때만 부른다(있으면 건너뛴다 — 매 회차 다시 빌드하지 않기 위해).
if [ ! -d ghostty-src ]; then
  if ! ./vendor_libghostty_vt.sh; then
    echo "FAIL: vendoring ghostty source failed"
    exit 1
  fi
fi

if ! ./vendor_stb_truetype.sh; then
  echo "FAIL: vendoring stb_truetype.h failed"
  exit 1
fi

if ! ./vendor_fonts.sh; then
  echo "FAIL: vendoring the 8x4x4 font failed"
  exit 1
fi

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && cargo build --release); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! zig build; then
  echo "FAIL: terminal build failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

MONITOR_PORT=45455
LOG="$(mktemp)"
QEMU_PID=""

# --- (변경 2) 스크린샷을 out/tf/ 아래 고정 이름으로 ---------------------
# 예전에는 /workspace 아래 mktemp로 만들고 지우지 않아서 저장소 루트에
# 3MB짜리 파일이 계속 쌓였다. out/은 .gitignore 대상이고 루트 check.sh의
# clean()이 매 회차 지운다. QEMU monitor의 screendump는 QEMU 프로세스의
# 작업 디렉터리를 기준으로 삼으므로 절대 경로로 넘긴다.
SCREENS_DIR="${REPO_ROOT}/out/tf"
mkdir -p "$SCREENS_DIR"
BEFORE="${SCREENS_DIR}/before.ppm"
AFTER="${SCREENS_DIR}/after.ppm"
rm -f "$BEFORE" "$AFTER"

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

qemu-system-x86_64 \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

MONITOR_READY=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then
    MONITOR_READY=1
    break
  fi
  sleep 0.5
done

if [ "$MONITOR_READY" != "1" ]; then
  echo "FAIL: could not connect to QEMU monitor on port ${MONITOR_PORT}"
  cat "$LOG"
  exit 1
fi

# --- (변경 3) 고정 sleep 30 대신 로그 폴링 ------------------------------
# main.zig:56의 dumpScreen()은 PTY 출력을 렌더링할 때마다
# "terminal: screen> ..." 한 줄을 serial에 찍는다. 그 줄이 처음 나타났다는
# 것은 (a) DRM 열기, (b) 폰트 래스터라이즈, (c) evdev 열기, (d) fish spawn,
# (e) 첫 프롬프트 렌더링까지 전부 끝났다는 뜻이다 — 키를 넣어도 되는 시점의
# 정확한 신호다. 고정 대기는 빠른 머신에서 낭비이고 느린 머신에서 깨진다.
READY=0
for _ in $(seq 1 120); do
  if grep -q "terminal: screen>" "$LOG"; then
    READY=1
    break
  fi
  sleep 1
done

if [ "$READY" != "1" ]; then
  echo "FAIL: terminal did not render a prompt within 120s"
  echo "--- startup markers ---"
  for marker in \
    "terminal: grid " \
    "terminal: rasterized " \
    "terminal: opened /dev/input/event0" \
    "terminal: spawned child pid "; do
    if grep -q "$marker" "$LOG"; then
      echo "  ok      ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  tail -n 60 "$LOG"
  exit 1
fi

# 첫 렌더링 직후 present가 끝나도록 한 박자 준다.
sleep 1

# 1) 키를 넣기 전 화면
echo "screendump ${BEFORE}" >&3
sleep 1

# 2) "math 6 x 7" + Enter 를 한 글자씩 주입.
#    fish 내장 math가 42를 출력하므로, 화면에 42가 나타나면 셸이 실제로
#    명령을 "실행"한 것이다 — 단순 에코와 구분된다.
for k in m a t h spc 6 spc x spc 7 ret; do
  echo "sendkey $k" >&3
  sleep 0.3
done

# --- (변경 4) 결과도 고정 sleep 3 대신 폴링 -----------------------------
# 42가 로그에 찍힌 뒤에 after 스크린샷을 뜨면, 픽셀 차이 검사와 로그 검사가
# 같은 화면 상태를 본다.
for _ in $(seq 1 30); do
  if grep -q "terminal: screen>.*42" "$LOG"; then
    break
  fi
  sleep 1
done
sleep 1

# 3) 키를 넣은 뒤 화면
echo "screendump ${AFTER}" >&3
sleep 1

exec 3<&-
exec 3>&-

kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""

if [ ! -s "$BEFORE" ] || [ ! -s "$AFTER" ]; then
  echo "FAIL: screendump did not produce both files (kept in ${SCREENS_DIR})"
  tail -n 60 "$LOG"
  exit 1
fi

if command -v magick >/dev/null 2>&1; then
  IDENTIFY=(magick identify)
  COMPARE=(magick compare)
else
  IDENTIFY=(identify)
  COMPARE=(compare)
fi

DIMENSIONS=$("${IDENTIFY[@]}" -format "%wx%h" "$AFTER" 2>&1) || {
  echo "FAIL: ImageMagick could not read ${AFTER}: ${DIMENSIONS}"
  exit 1
}
echo "Captured screendumps: ${BEFORE} / ${AFTER} (${DIMENSIONS})"

# 렌더링 경로 검증: 키 주입 전후로 화면이 실제로 달라졌는가.
DIFF_PIXELS=$("${COMPARE[@]}" -metric AE "$BEFORE" "$AFTER" null: 2>&1) || true
DIFF_PIXELS="${DIFF_PIXELS%%[!0-9]*}"
echo "Pixels changed after typing: ${DIFF_PIXELS:-0}"

if [ -z "$DIFF_PIXELS" ] || [ "$DIFF_PIXELS" -lt 100 ]; then
  echo "FAIL: screen did not change after key injection (${DIFF_PIXELS:-0} pixels)"
  echo "      screenshots kept in ${SCREENS_DIR}"
  tail -n 60 "$LOG"
  exit 1
fi

# 파싱 경로 검증: 셸이 명령을 실행해 42를 내놓았는가.
if ! grep -q "terminal: screen>.*42" "$LOG"; then
  echo "FAIL: expected '42' in the parsed screen dump (shell did not run the command)"
  echo "      screenshots kept in ${SCREENS_DIR}"
  tail -n 60 "$LOG"
  exit 1
fi
echo "Found '42' in parsed screen dump"

# 성공했으면 스크린샷은 필요 없다. 실패했을 때만 남겨서 눈으로 볼 수 있게 한다.
rm -f "$BEFORE" "$AFTER"

echo "PASS"
exit 0
```

- [x] **Step 2: 실행 권한 확인**

Run:
```bash
ls -la terminal/check.sh
```

Expected: `-rwxr-xr-x` (TF-M2에서 이미 부여됨). 아니면 `chmod +x terminal/check.sh`.

- [x] **Step 3: 단독 실행해서 여전히 PASS인지 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash terminal/check.sh
```

Expected 출력 순서:
1. vendor 스크립트 세 개는 산출물이 이미 있으므로 아무 것도 출력하지 않고
   지나간다(`ghostty-src/`가 있으므로 첫 번째는 아예 호출되지 않는다).
2. 커널 빌드 로그 → init `cargo build` → `zig build` → `make_initrd.sh`.
3. `Captured screendumps: /workspace/out/tf/before.ppm /
   /workspace/out/tf/after.ppm (1280x800)`
4. `Pixels changed after typing: 533` 정도(TF-M3 실측치 533, 임계값 100).
   화면에 그려지는 글자 수가 같으므로 비슷한 값이어야 한다.
5. `Found '42' in parsed screen dump`
6. `PASS`, 종료 코드 0.

이번 Step은 clean 빌드가 아니어도 된다 — "고쳐 쓴 스크립트가 여전히 자기
완결적으로 PASS하는가"만 본다.

**FAIL이면 어디를 볼지:**
- `FAIL: terminal did not render a prompt within 120s` + `MISSING terminal:
  grid ` → DRM 열기 실패. `-device virtio-gpu-pci`가 붙었는지, 커널
  `.config`의 DRM 옵션이 그대로인지 확인한다.
- `MISSING terminal: opened /dev/input/event0` → evdev/i8042 회귀. 로그에서
  `serio: i8042 KBD port`와 `input: AT Translated ...` 두 줄을 찾아본다.
- `MISSING terminal: spawned child pid ` → `forkpty` 실패. `/dev/pts` 마운트
  (`init/src/main.rs:34-43`)를 의심한다.
- 마커는 전부 `ok`인데 프롬프트가 안 나온다 → fish가 프롬프트를 그리다 죽은
  것. `tail -n 60`에서 `fish: Unknown command:` 를 찾는다(TF-M3에서
  `uname`/`mkdir`을 initrd에 넣어 해결한 것과 같은 종류의 문제).

- [x] **Step 4: 커밋**

```bash
git add terminal/check.sh
git commit -m "Make the terminal gate poll for readiness and vendor its inputs"
```

---

### Task 3: 루트 `check.sh`를 BF + TF 두 체인 3회 검증으로 재구성

**Files:**
- Modify: `check.sh` (저장소 루트, 전체 교체)

- [x] **Step 1: `check.sh` 전체 교체**

```bash
#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# 매 회차 전에 지우는 것은 "빌드 산출물"뿐이다.
#
# 지우면 안 되는 것들(전부 .gitignore 대상이라 눈에 안 띈다):
#   terminal/ghostty-src  GitHub tarball로 받아온 vendor 소스 트리
#   terminal/vendor       stb_truetype.h + 8x4x4 폰트 + libghostty-vt 산출물
#   terminal/zig-pkg      Zig 0.16의 프로젝트 로컬 패키지 캐시
# 이 셋은 네트워크가 있어야만 복구되므로, clean 대상에 넣으면 매 회차 수백
# MB를 다시 받고 오프라인에서는 아예 복구가 불가능하다.
#
# kms/target은 목록에서 빠졌다 — TF-M2 이후 kms를 빌드하는 체인이 없다
# (2026-08-12, TF-M4).
clean() {
  rm -rf kernel/build init/target terminal/zig-out terminal/.zig-cache out
}

run_chain() {
  local name="$1"
  local script="$2"

  for i in 1 2 3; do
    echo "=== ${name} run ${i}/3 ==="
    clean
    if ! "$script"; then
      echo "${name} FAIL: run ${i}/3 failed"
      exit 1
    fi
    echo "=== ${name} run ${i}/3 PASSED ==="
  done

  echo "${name} PASS: 3/3 consecutive runs succeeded"
}

# BF 체인은 limine ISO 부팅 경로를, TF 체인은 부팅 이후의 전체 런타임
# (DRM 렌더링 + evdev 입력 + PTY 셸)을 검증한다. DF 체인(display/check.sh)은
# TF-M4에서 은퇴했다 — 이유는 그 파일 머리말 참고.
run_chain "BF-M4" ./boot/check.sh
run_chain "TF-M4" ./terminal/check.sh

echo "TARS check PASS: all chains 3/3 consecutive runs succeeded"
```

- [x] **Step 2: `clean()` 대상이 전부 gitignore되는지 확인**

Run:
```bash
git check-ignore -v kernel/build init/target terminal/zig-out terminal/.zig-cache out
```

Expected: 다섯 경로 모두 `.gitignore`의 몇 번째 줄에 걸리는지 출력된다(예:
`.gitignore:20:terminal/zig-out/\tterminal/zig-out`). 하나라도 출력이 없으면
`clean()`이 추적 중인 파일을 지울 위험이 있으므로 Step 1로 돌아가 대상 목록을
다시 확인한다.

- [x] **Step 3: 보존 대상이 clean 목록에 없음을 눈으로 재확인**

Run:
```bash
rg -n "ghostty-src|terminal/vendor|zig-pkg" check.sh
```

Expected: 세 이름이 **주석에만** 나타나고 `rm -rf` 줄에는 없다. `clean()`의
`rm -rf` 줄에 이 중 하나라도 들어가 있으면 즉시 고친다 — 3회 반복 중 첫
회차에서 vendor 트리가 날아가면 나머지 회차가 네트워크 없이는 복구되지
않는다.

- [x] **Step 4: 커밋**

```bash
git add check.sh
git commit -m "Rebuild the root gate around the boot and terminal chains"
```

---

### Task 4: 전체 게이트 3회 연속 실행

**Files:**
- Create: `terminal/prepare.sh` (Step 0 정정에서 추가)
- Modify: `boot/check.sh:8`, `terminal/check.sh:8-30` (같은 정정)

- [x] **Step 0(정정): `boot/check.sh`가 terminal을 빌드하도록 공용 준비
      스크립트 분리**

Step 1을 처음 실행했을 때 `BF-M4 run 1/3`에서 이렇게 실패했다.

```
cp: cannot stat '../terminal/zig-out/bin/terminal': No such file or directory
BF-M4 FAIL: run 1/3 failed
```

원인: `kernel/make_initrd.sh:23`이 `../terminal/zig-out/bin/terminal`을 무조건
복사하는데 `boot/check.sh`는 kernel과 init만 빌드한다. 게다가 Task 3에서
`clean()`에 `terminal/zig-out`을 넣었으므로 TF-M3 때 남아 있던 바이너리조차
없다. **DF-M3 Task 2 Step 3(정정)과 완전히 같은 종류의 회귀다** — 그때는
`make_initrd.sh`가 kms를 복사하기 시작했는데 `boot/check.sh`가 kms를 안
빌드해서 깨졌다. `make_initrd.sh`의 복사 목록이 바뀔 때마다
`boot/check.sh`가 뒤처지는 패턴이며, 루트 게이트가 BF 체인을 매번 돌리기
때문에 이번에도 즉시 잡혔다.

`zig build` 한 줄을 `boot/check.sh`에 넣는 것으로는 부족하다 — terminal
빌드는 vendor 트리를 전제하고 `make_initrd.sh:27`은 폰트 파일까지 복사한다.
그 준비 로직이 이미 `terminal/check.sh`에 있으므로, 복붙 대신 공용 스크립트로
뽑아 두 체인이 같이 부르게 했다.

Create `terminal/prepare.sh` (`chmod +x` 필요):

```bash
#!/usr/bin/env bash
#
# initrd에 들어갈 terminal 바이너리와 그 vendor 입력을 준비한다.
# kernel/make_initrd.sh가 ../terminal/zig-out/bin/terminal 과
# ../terminal/vendor/fonts/Hanme_8x4x4.ttf 를 무조건 복사하므로, initrd를
# 만드는 체인은 어느 것이든 이 준비를 먼저 거쳐야 한다 — boot/check.sh와
# terminal/check.sh 둘 다 이 스크립트를 부른다.
set -euo pipefail

cd "$(dirname "$0")"

# 세 vendor 스크립트는 산출물이 이미 있으면 아무것도 하지 않는다.
# ghostty-src는 다운로드에 더해 lib-vt 빌드까지 하므로 트리가 없을 때만 부른다.
if [ ! -d ghostty-src ]; then
  ./vendor_libghostty_vt.sh
fi
./vendor_stb_truetype.sh
./vendor_fonts.sh

zig build
```

`boot/check.sh`의 6~11행(Task 1에서 kms 줄을 뺀 자리에 대응하는 terminal 줄이
들어간다):

```bash
(cd ../kernel && ./build.sh)
(cd ../init && cargo build --release)
(cd ../terminal && ./prepare.sh)
(cd ../kernel && ./make_initrd.sh)
./build.sh
./make_iso.sh
```

`terminal/check.sh`는 Task 2에서 넣은 vendor 블록 세 개와 `zig build` 블록을
지우고 한 블록으로 대체한다(주석도 함께 갱신).

```bash
# vendor 준비 + terminal 빌드는 prepare.sh가 맡는다(boot/check.sh와 공유).
if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && cargo build --release); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! ./prepare.sh; then
  echo "FAIL: terminal build failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi
```

**`make_initrd.sh`가 직접 `prepare.sh`를 부르게 하지 않은 이유:** 그러면 어떤
체인도 다시는 뒤처지지 않지만, `make_initrd.sh`는 init·fish·폰트 중 아무것도
빌드하지 않는 순수 조립 스크립트다. terminal만 예외로 빌드하게 만들면 "init은
호출자가 빌드, terminal은 자기가 빌드"라는 비대칭이 생긴다. 재발 방지는 루트
게이트가 BF 체인을 매 회 돌리는 것과 `docs/decisions/
project_gate_chain_composition.md`로 처리한다.

커밋: `4c33a47` "Share terminal build preparation between the boot and
terminal gates"

- [x] **Step 1: 루트 `check.sh` 실행**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash check.sh
```

Expected: 아래 순서로 출력되고 종료 코드 0.

```
=== BF-M4 run 1/3 ===
... (커널 빌드 → init 빌드 → initrd → limine ISO → QEMU 15초)
Welcome to fish, the friendly interactive shell
PASS
=== BF-M4 run 1/3 PASSED ===
=== BF-M4 run 2/3 ===
...
BF-M4 PASS: 3/3 consecutive runs succeeded
=== TF-M4 run 1/3 ===
... (커널 빌드 → init → zig build → initrd → QEMU 부팅 → 키 주입)
Captured screendumps: /workspace/out/tf/before.ppm / /workspace/out/tf/after.ppm (1280x800)
Pixels changed after typing: 533
Found '42' in parsed screen dump
PASS
=== TF-M4 run 1/3 PASSED ===
...
TF-M4 PASS: 3/3 consecutive runs succeeded
TARS check PASS: all chains 3/3 consecutive runs succeeded
```

매 회차 `clean()` 뒤에 커널을 통째로 다시 컴파일하므로(총 6회) 아주 오래
걸린다 — 정상이다. `terminal/.zig-cache`도 매 회차 지워지므로 `zig build`가
ghostty-vt 모듈까지 다시 컴파일한다. **이때 네트워크는 필요 없어야 한다** —
받아온 패키지는 `terminal/zig-pkg`에 있고 그건 지우지 않기 때문이다. 만약
이 단계에서 zig가 다운로드를 시도하는 로그가 보이면, `zig-pkg`가 아닌 다른
경로를 패키지 캐시로 쓰고 있다는 뜻이므로 그 경로를 찾아 clean 대상에서
제외해야 한다.

**BF 체인이 실패하면(가장 가능성 높은 새 실패):** BF는 limine ISO를 기본 VGA로
부팅하므로 `/dev/dri/card0`가 없다. `init`이 fork한 `/terminal`은
`drm.open()`에서 실패하고 그 자식만 죽는다 — 부모 `init`은 그대로
`/usr/bin/fish`를 exec하므로 배너는 나와야 한다. 그런데도 배너가 없다면
로그에서 `tars-init: forked terminal` 다음 줄들을 보고, 죽은 자식이 콘솔을
어지럽혔는지 확인한다. (TF-M2 이후 `boot/check.sh`가 실행된 적이 없어서
이번이 첫 검증이다.)

**TF 체인이 1회차부터 실패하면:** Task 2 Step 3에서 단독 PASS를 확인했으므로,
clean 빌드에서만 생기는 문제다 — `zig build`가 `.zig-cache` 없이 실패하는지,
`make_initrd.sh`가 없는 산출물을 찾는지 로그 앞부분을 본다.

**TF 체인이 2~3회차에서만 실패하면:** 회차 간에 남는 상태가 원인이다.
`out/tf/`의 스크린샷은 매 회차 `rm -f`로 지우고 시작하므로 후보에서 빠진다 —
QEMU monitor 포트 45455가 이전 회차 프로세스에 잡혀 있는지(`FAIL: could not
connect to QEMU monitor`)를 먼저 의심한다.

- [x] **Step 2: 실행 후 작업 트리 상태 확인**

Run:
```bash
git status --short && ls out/ 2>/dev/null
```

Expected: 추적 파일에 변경이 없다(`kernel/initrd.cpio`는 이제 `.gitignore:6`에
있으므로 BF-M4/DF-M3 때와 달리 status에 나타나지 않는다). `out/`은 마지막
회차의 ISO 산출물이 들어 있고, `out/tf/`는 PASS했다면 비어 있다.

---

### Task 5: design doc·기억·HANDOFF 정리

**Files:**
- Modify: `docs/superpowers/specs/2026-08-08-tars-terminal-foundation-design.md:4`
- Create: `docs/decisions/project_gate_chain_composition.md`
- Modify: `MEMORY.md`
- Modify: `HANDOFF.md`

- [x] **Step 1: design doc Status 갱신**

`docs/superpowers/specs/2026-08-08-tars-terminal-foundation-design.md`의 4번째
줄을 아래로 바꾼다(현재 값은 `Design approved, awaiting TF-M0 plan`이라 TF-M0
이후 한 번도 갱신되지 않았다).

```markdown
**Status:** TF-M4 complete (2026-08-12); Terminal Foundation complete
```

- [x] **Step 2: 게이트 체인 구성 원칙을 기억으로 남기기**

Create `docs/decisions/project_gate_chain_composition.md`:

```markdown
---
name: project_gate_chain_composition
description: 루트 check.sh의 체인 구성 원칙 — 부팅 경로가 바뀌면 낡은 게이트는 되살리지 말고 은퇴시킨다; clean()은 빌드 산출물만 지운다.
metadata:
  type: project
---

2026-08-12 TF-M4에서 루트 `check.sh`를 BF + TF 두 체인으로 재구성했다.
DF 체인(`display/check.sh`)은 은퇴시켰다.

**왜 은퇴인가.** DF 게이트는 "화면 (10,10)이 kms가 칠한 빨강인가"를 본다.
TF-M2에서 `kernel/make_initrd.sh`가 initrd에 kms 대신 terminal을 넣고
`init/src/main.rs`가 `/terminal`을 fork하도록 바뀌면서, 부팅된 시스템에
kms가 존재하지 않게 됐다 — 되살리려면 커널 cmdline으로 무엇을 띄울지 고르는
부팅 모드 스위치를 새로 만들어야 한다. 반면 DF가 검증하던 DRM/KMS present
경로는 TF 체인이 매 회차 실제로 픽셀을 띄우며 이미 검증한다. **죽은 테스트를
살리려고 제품 코드(부팅 경로)에 분기를 넣지 않는다.**

**남긴 체인의 역할 분담.** BF는 limine ISO 부팅 경로를, TF는 부팅 이후의
런타임 전체(DRM 렌더링 + evdev 입력 + PTY 셸)를 본다. TF가 BF를 포함하지
못하는 유일한 지점이 부트로더다(TF는 `-kernel`/`-initrd` 직접 부팅).

**clean()이 지워도 되는 것.** 빌드 산출물만이다.
`terminal/ghostty-src`(tarball), `terminal/vendor`(폰트·헤더),
`terminal/zig-pkg`(Zig 0.16 프로젝트 로컬 패키지 캐시)는 전부 `.gitignore`
대상이라 눈에 안 띄지만 **네트워크에서만 복구된다** — clean 목록에 넣으면
3회 반복의 첫 회차가 나머지 두 회차를 오프라인에서 복구 불가능하게 만든다.

**How to apply:** 부팅 경로나 initrd 구성이 바뀌면 기존 게이트 스크립트가
조용히 무의미해졌는지 먼저 확인한다(TF-M2~M3 동안 아무도 `display/check.sh`와
`boot/check.sh`를 돌리지 않아 세 milestone 내내 드러나지 않았다). 새 게이트를
추가할 때는 clean 대상에 vendor 트리/패키지 캐시가 섞이지 않았는지 확인한다.

관련: [[project_zig_c_uapi_rule]], [[project_zig_rewrite_intent]]
```

- [x] **Step 3: `MEMORY.md` 색인에 한 줄 추가**

`MEMORY.md`의 "## 프로젝트 (project)" 절 맨 끝에 추가한다.

```markdown
- [Gate chain composition](docs/decisions/project_gate_chain_composition.md) — 루트 `check.sh`는 BF+TF 두 체인; 부팅 경로가 바뀌어 무의미해진 게이트는 되살리지 않고 은퇴, `clean()`은 vendor 트리를 건드리지 않는다
```

- [x] **Step 4: 커밋**

```bash
git add docs/superpowers/specs/2026-08-08-tars-terminal-foundation-design.md \
        docs/decisions/project_gate_chain_composition.md MEMORY.md
git commit -m "Mark Terminal Foundation complete and record gate chain rules"
```

- [x] **Step 5: 이 plan 파일에 실행 결과 반영**

각 Task의 체크박스를 채우고, 이 파일 말미에 "실제 실행에서 plan과 달라진 점"
절을 추가한다(TF-M2·TF-M3와 같은 형식). 특히 아래 세 가지는 예측이므로 실측치
또는 실제 동작으로 반드시 교체한다.

- BF 체인이 `/terminal` fork 실패를 안고도 통과하는가(Task 4 Step 1의 예측).
- `.zig-cache`를 지운 상태의 `zig build`가 네트워크 없이 되는가.
- TF 체인 3회의 실제 소요 시간과 `Pixels changed` 값의 회차별 편차.

- [x] **Step 6: `HANDOFF.md`를 다음 서브프로젝트 착수 전 상태로 갱신**

`handoff` 스킬로 현재 상태(Terminal Foundation 전체 완료, 다음 서브프로젝트
미정)를 반영해 새로 쓴다. 다음 후보로 `HANDOFF.md`의 "남은 작업"에 이미 적힌
두 가지 — 설정 영속화 + 부팅 셸 선택(`docs/decisions/
project_boot_shell_selection.md`), Rust → Zig 재작성(`docs/decisions/
project_zig_rewrite_intent.md`) — 를 남긴다.

- [x] **Step 7: 커밋**

```bash
git add HANDOFF.md docs/superpowers/plans/2026-08-12-tars-terminal-foundation-tf-m4.md
git commit -m "Update handoff after finishing Terminal Foundation"
```

---

## TF-M4 완료 확인

Task 4 Step 1이 `TARS check PASS: all chains 3/3 consecutive runs succeeded`로
끝나면 design doc 기준 TF-M4 exit gate(전체 체인 3회 연속 검증)를 만족하고,
Terminal Foundation 서브프로젝트(TF-M0~M4) 전체가 완료된다.

## 실제 실행에서 plan과 달라진 점

정정 네 건이 있었다. 전부 "TF-M2~M3 동안 BF/DF 체인을 아무도 돌리지 않아
쌓여 있던 빚"이 루트 게이트를 처음 돌리는 순간 한꺼번에 드러난 것이다.

### 1. `boot/check.sh`가 terminal을 빌드하지 않았다 (Task 4 Step 0)

`cp: cannot stat '../terminal/zig-out/bin/terminal'`. DF-M3에서 kms로 겪은
것과 완전히 같은 회귀다. `terminal/prepare.sh`로 vendor 준비 + `zig build`를
뽑아 두 체인이 공유하게 했다. 상세는 Task 4 Step 0 참고.

### 2. BF의 고정 `timeout 15`가 initrd 성장을 못 따라갔다

Step 0을 고치고 다시 돌리니 `FAIL: expected fish banner not found`가 났는데,
`cat "$LOG"`가 출력한 serial 내용이 **0바이트**였다 — 커널이 한 줄도 실행되지
못했다는 뜻이다. `boot/check.sh`를 TF 게이트와 같은 폴링 방식으로 바꿨다
(최대 120초, 배너가 보이면 즉시 종료, 실제 대기 시간을 `Boot reached the
fish banner after ~Ns`로 출력). 커밋 `04c5c8d`.

### 3. `-Doptimize=ReleaseSafe`는 `@cImport`를 깨뜨린다 (계획에 없던 발견)

initrd를 줄이려고 최적화 모드를 올렸더니 `drm.zig:3`의 `@cImport`가
`error: C import failed`로 실패했다. Debug가 아닌 모드에서 Zig가 붙이는
`-D_FORTIFY_SOURCE` 때문에 glibc의 `bits/fcntl2.h`가 활성화되고, 그 안의
`__attribute__((error))` 선언(`__open_too_many_args`)을 translate-c가 번역하지
못한다. **`fcntl.h`를 `@cImport`하는 코드는 Debug에 묶인다**는 새 제약이며,
우회(`@cDefine("_FORTIFY_SOURCE", "0")`)는 종료 게이트 도중에 검증 대상
바이너리를 바꾸는 위험이 있어 쓰지 않았다.
(→ `docs/decisions/project_zig_c_uapi_rule.md`)

### 4. 진짜 원인은 initrd 크기, 해법은 gzip (strip은 거부)

BF가 부팅조차 못 한 이유는 initrd 53MB였다. 42MB짜리 Debug terminal이
TF-M2에서 들어갔고, BF는 limine이 **BIOS INT13h로 ISO9660에서** 그걸 읽는다
(TF는 QEMU가 `-initrd`로 메모리에 직접 올려서 무관했다).

측정한 세 조합:

| 구성 | initrd | BF 부팅 |
|---|---|---|
| 원본 | 53MB | 실패(120초 초과, serial 0바이트) |
| strip + gzip | 6.5MB | ~25초 |
| **gzip만(채택)** | **11.8MB** | **~34초** |

strip을 거부한 이유는 Zig 에러 트레이스가 바이너리 자체의 디버그 정보를
런타임에 읽어 만들기 때문이다 — strip하면 게스트 안에서 트레이스를 되살릴
방법이 원리적으로 없어진다. 5MB와 9초는 그 가능성을 영구히 포기할 값이
아니라고 판단했다. **단, 심볼이 있다고 트레이스가 바로 읽히지는 않았다** —
같은 크래시에서 strip 버전은 `???:?:?: 0x12716d8 in ???` 두 줄, 심볼 버전은
트레이스 자체가 없었다(원인 미규명, 남겨둔 숙제).

커밋 `4504a7f`(strip+gzip) → `136129c`(strip 제거). 이 변경으로 initrd가
바뀌었으므로 6.5MB 구성으로 통과했던 3/3은 근거로 쓰지 않고 **전체 게이트를
처음부터 다시 돌렸다.**

### 5. 통과한 게이트의 실제 수치

- **BF 체인:** 3/3 통과. `Boot reached the fish banner after ~25s`(strip 구성)
  / `~34s`(최종 구성). 예측대로 `/terminal` 자식은 `/dev/dri/card0`이 없어
  `error: OpenFailed`로 죽고, 부모 `init`은 그대로 fish 배너까지 간다 —
  BF 로그의 이 세 줄이 정상 동작의 증거다.
- **TF 체인:** 3/3 통과. `Pixels changed after typing:`이 **533~785**로
  회차마다 달랐다(임계값 100). TF-M3 단독 실행과 strip 구성에서는 533,
  최종 구성 마지막 회차는 785. initrd 압축과는 무관하고, before 스크린샷을
  뜨는 시점 문제로 보인다 — 폴링이 **첫** `terminal: screen>` 직후에 화면을
  뜨는데 fish가 프롬프트를 여러 조각으로 그리면 그때 프롬프트가 덜 그려져
  있고, 그만큼 after와의 차이가 커진다. 두 값 모두 임계값의 5배 이상이라
  게이트 판정에는 영향이 없다.
- **`terminal/check.sh: connect: Connection refused`** 두 줄은 QEMU가 monitor
  포트를 열기 전 첫 연결 시도다. 재시도 루프(20회 × 0.5초)가 처리한다.
- `.zig-cache`를 지운 상태의 `zig build`는 **네트워크 없이** 완주했다 —
  `terminal/zig-pkg`를 clean 대상에서 뺀 판단이 실측으로 확인됐다.

## 이번 범위에서 뺀 것 (YAGNI)

- **DF 게이트 되살리기.** 부팅 모드 스위치가 필요하고, 검증 가치는 TF 체인과
  겹친다(Architecture 1번).
- **`kms/` 크레이트 삭제.** 실행되지 않지만 Rust로 쓴 DRM 참조 구현으로서
  가치가 있고, 지우는 것은 되돌리기 어려운 변경이다. 은퇴 주석으로 충분하다.
- **회차 간 커널 빌드 캐시 재사용.** clean 재빌드가 곧 이 게이트의 목적이다.
  6회 커널 컴파일이 느린 것은 의도된 비용이다.
- **CI 연동.** 이 게이트는 사람이 손으로 돌리는 것을 전제로 한다.
