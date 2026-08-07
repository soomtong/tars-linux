# TARS Display Foundation — DF-M3 종료 게이트 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **단, 이 저장소는 pairing 방식 고정(`CLAUDE.md`, HANDOFF.md 참고):** 파일
> 작성과 명령 실행은 사용자가 직접 하고, Claude는 각 Step의 정확한 내용을
> 제시하고 결과를 해석한다. 위 SUB-SKILL 문구는 다른 저장소용 기본값이며 이
> 저장소에는 적용하지 않는다.

**Goal:** DF-M3를 완료한다 — DF-M0~M2 전체 체인(kernel 빌드 → init 빌드 →
kms 빌드 → initrd 생성 → QEMU `-device virtio-gpu-pci` 부팅 → screendump →
지정 좌표 픽셀 색 검사)을 재현 가능한 단일 스크립트로 묶어 **3회 연속
성공**시켜 Display Foundation 서브프로젝트의 종료 게이트를 통과한다.

**Architecture:** 두 가지 변경이 필요하다.

1. `display/check.sh`는 현재 `kernel/build/arch/x86/boot/bzImage`와
   `kernel/initrd.cpio`가 이미 만들어져 있다고 가정한다(빌드 단계가 없다) —
   지금까지 DF-M0~M2 검증은 사용자가 수동으로 `kernel/build.sh`,
   `init`/`kms`의 `cargo build --release`, `kernel/make_initrd.sh`를 먼저
   실행한 뒤에 `display/check.sh`를 돌리는 방식이었다. `boot/check.sh`(BF
   쪽)는 이미 빌드 단계까지 스크립트 안에 포함해 자기 완결적이다 —
   `display/check.sh`도 같은 패턴으로 만들어야 "재현 가능한 단일
   스크립트"라는 DF-M3의 결과 조건을 만족한다. 빠진 빌드 단계는 `kernel`,
   `init`뿐 아니라 `kms`도 포함해야 한다(`kernel/make_initrd.sh`가
   `../kms/target/release/kms`를 initrd에 복사하기 때문 — 지금까지는 이
   빌드도 사용자가 수동으로 먼저 해뒀다).
2. 저장소 루트 `check.sh`(BF-M4 산출물)는 현재 `boot/check.sh`를 3회
   반복하는 것만 한다. 이번 세션에서 사용자와 논의해 **BF 체인과 DF 체인을
   모두 포함하도록 확장**하기로 했다 — DF-M1에서 `kernel/.config`를 바꿔
   PCI/DRM/virtio-gpu를 켰으므로, BF 체인(fish 배너 부팅)이 그 변경 이후에도
   여전히 통과하는지 함께 재검증하는 것이 의미 있다는 판단이다(회귀
   안전망). `run_chain()`이라는 공용 함수로 일반화해 두 체인을 각각 3회
   돌리고, 하나라도 실패하면 어느 체인의 몇 번째 회차인지 즉시 출력하고
   중단(fail-fast)한다. `clean()`에는 DF 체인이 쓰는 `kms/target/`도
   추가한다(기존엔 `kernel/build`, `init/target`, `out`만 지웠다). 이 확장
   때문에 커널 전체 재빌드가 기존 3회에서 6회(BF 3 + DF 3)로 늘어 실행
   시간이 그만큼 길어진다 — 의도된 트레이드오프다.

**Tech Stack:** bash, Docker(`tars-devcontainer` 이미지), QEMU monitor
`screendump` + ImageMagick(DF-M0~M2 산출물, 수정 없음)

---

## 사전 준비

이 plan의 모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서
실행한다. DF-M2까지 완료되어 `display/check.sh` 단독 실행(수동 사전 빌드
포함)이 PASS함이 확인된 상태여야 한다(HANDOFF.md 기준 최신 커밋
`aeae89c`).

**이번 세션 결정 사항(design doc에 이미 정의된 DF-M3 exit gate를 구체화):**
- 새 아키텍처 결정 없음 — design doc(`2026-08-07-tars-display-foundation-
  design.md`) DF-M3 절의 "재현 가능한 단일 스크립트 + 3회 연속 성공"을
  BF-M4와 동일한 clean-rebuild 패턴으로 구현한다.
- 루트 `check.sh`는 BF+DF 두 체인을 모두 검증하도록 확장한다(위 Architecture
  절 2번 참고, 사용자와 합의).
- 3회 연속 실행 중 중간 실패 시 즉시 중단(fail-fast) — BF-M4와 동일한 해석.

---

### Task 1: `display/check.sh`를 자기 완결적으로 만들기 (kernel/init/kms 빌드 포함)

**Files:**
- Modify: `display/check.sh`

- [ ] **Step 1: `display/check.sh`에 빌드 단계 추가**

`display/check.sh` 전체를 아래 내용으로 교체한다(기존 `MONITOR_PORT=45454`
이후 로직은 그대로 유지하고, `cd "$(dirname "$0")"` 바로 다음에 빌드 단계
네 개만 새로 삽입한다):

```bash
#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && cargo build --release); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! (cd ../kms && cargo build --release); then
  echo "FAIL: kms build failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

MONITOR_PORT=45454
SCREENSHOT="$(mktemp /tmp/df-m0-XXXXXX.ppm)"
LOG="$(mktemp)"
QEMU_PID=""

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

# virtio-gpu가 기본 scanout을 초기화할 시간을 준다(경험적으로 선택한 값 —
# Step 3에서 FAIL이면 가장 먼저 늘려볼 값).
sleep 5
echo "screendump ${SCREENSHOT}" >&3
sleep 1
exec 3<&-
exec 3>&-

kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""

if [ ! -s "$SCREENSHOT" ]; then
  echo "FAIL: screendump did not produce a file at ${SCREENSHOT}"
  cat "$LOG"
  exit 1
fi

if command -v magick >/dev/null 2>&1; then
  IDENTIFY=(magick identify)
else
  IDENTIFY=(identify)
fi

DIMENSIONS=$("${IDENTIFY[@]}" -format "%wx%h" "$SCREENSHOT" 2>&1) || {
  echo "FAIL: ImageMagick could not read ${SCREENSHOT}: ${DIMENSIONS}"
  exit 1
}

echo "Captured screendump: ${SCREENSHOT} (${DIMENSIONS})"

if [[ ! "$DIMENSIONS" =~ ^[0-9]+x[0-9]+$ ]]; then
  echo "FAIL: unexpected ImageMagick output: ${DIMENSIONS}"
  exit 1
fi

if command -v magick >/dev/null 2>&1; then
  CONVERT=(magick)
else
  CONVERT=(convert)
fi

PIXEL=$("${CONVERT[@]}" "${SCREENSHOT}" -crop 1x1+10+10 +repage txt:- 2>&1) || {
  echo "FAIL: ImageMagick could not extract pixel at (10,10): ${PIXEL}"
  exit 1
}

echo "Pixel at (10,10): ${PIXEL}"

if echo "$PIXEL" | grep -qi '#FF0000'; then
  echo "PASS"
  exit 0
fi

echo "FAIL: expected red (#FF0000) at (10,10), got: ${PIXEL}"
exit 1
```

빌드 단계 네 개를 `if ! (...); then echo FAIL; exit 1; fi` 형태로 감싼
이유: 이 파일 전체가 `set -uo pipefail`이고 `set -e`가 없다(스크린샷/픽셀
검사 단계에서 `|| true`, trap 기반 정리를 쓰기 위해 의도적으로 뺀 것 —
DF-M0 때부터의 기존 설계). `set -e` 없이는 `./build.sh`가 실패해도 스크립트가
계속 진행해 버리므로, 나머지 코드와 동일하게 각 명령의 성공 여부를 명시적으로
검사하는 패턴을 그대로 따른다.

- [ ] **Step 2: 실행 권한 확인**

```bash
ls -la display/check.sh
```

Expected: 이미 `rwxr-xr-x` (DF-M0 때 부여됨) — 실행 권한이 없다면
`chmod +x display/check.sh`.

- [ ] **Step 3: 단독 실행해서 여전히 PASS하는지 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash display/check.sh
```

Expected: kernel/init/kms 빌드 로그가 먼저 출력되고, 이어서 DF-M2 때와 같은
`Captured screendump: ... (640x480)`, `Pixel at (10,10): ... #FF0000 red`,
`PASS`가 출력된다. 종료 코드 0. `kernel/build/`, `init/target/`,
`kms/target/`이 이미 존재하는 상태(incremental build)에서 실행하므로 이번
Step은 clean 빌드가 아니어도 된다 — "스크립트가 자기 완결적으로 동작하는가"만
확인한다.

- [ ] **Step 4: 커밋**

```bash
git add display/check.sh
git commit -m "Make display/check.sh self-contained with kernel/init/kms build steps"
```

---

### Task 2: 루트 `check.sh`를 BF+DF 다중 체인 3회 검증으로 확장

**Files:**
- Modify: `check.sh` (저장소 루트)

- [ ] **Step 1: `check.sh` 전체 교체**

`check.sh`(저장소 루트):
```bash
#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

clean() {
  rm -rf kernel/build init/target kms/target out
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

run_chain "BF-M4" ./boot/check.sh
run_chain "DF-M3" ./display/check.sh

echo "TARS check PASS: all chains 3/3 consecutive runs succeeded"
```

`clean()`에 `kms/target`을 추가한 것 외에는 BF-M4 때 만든 구조를
`run_chain()` 함수로 일반화한 것뿐이다 — 로직 변경 없음. `run_chain`을 BF,
DF 순서로 두 번 호출하므로 BF 체인이 먼저 3회, 그다음 DF 체인이 3회
실행된다(교차 실행이 아니다 — 한 체인이 끝나야 다음 체인이 시작).

- [ ] **Step 2: `.gitignore` 대상에 `kms/target` 포함 확인**

Run:
```bash
git check-ignore -v kernel/build init/target kms/target out
```

Expected: 네 경로 모두 `.gitignore`의 어느 줄에 걸리는지 출력된다(예:
`.gitignore:9:kms/target\tkms/target`). 하나라도 출력이 없으면 `clean()`이
추적 파일을 지울 위험이 있으므로 Step 1로 돌아가 대상 목록을 다시 확인한다.

- [ ] **Step 3(정정): `boot/check.sh`에 `kms` 빌드 단계 추가**

Task 2 Step 3을 처음 실행했을 때 `BF-M4 run 1/3`에서
`cp: cannot stat '../kms/target/release/kms': No such file or directory`로
실패했다. 원인: DF-M2에서 `kernel/make_initrd.sh`가 무조건
`../kms/target/release/kms`를 initrd에 복사하도록 바뀌었는데,
`boot/check.sh`는 `kernel`과 `init`만 빌드하고 `kms`는 빌드하지 않는다.
DF-M2 이후 `boot/check.sh`가 `kms`가 추가된 상태로 재실행된 적이 없어서
지금까지 드러나지 않았던 회귀다 — 루트 `check.sh`가 BF 체인을 함께
검증하도록 확장하면서 처음 발견됐다.

`boot/check.sh`의 빌드 단계 세 줄을 아래처럼 네 줄로 바꾼다(`display/check.sh`에
Task 1에서 추가한 것과 동일한 `kms` 빌드 단계를 끼워 넣는다):

```bash
(cd ../kernel && ./build.sh)
(cd ../init && cargo build --release)
(cd ../kms && cargo build --release)
(cd ../kernel && ./make_initrd.sh)
./build.sh
./make_iso.sh
```

`boot/check.sh`는 `set -euo pipefail`(`-e` 포함)이므로 `display/check.sh`와
달리 `if ! (...); then ... fi`로 감쌀 필요가 없다 — 빌드 명령이 실패하면
`-e`가 스크립트를 바로 종료시킨다(기존 세 줄과 동일한 스타일 유지).

- [ ] **Step 4: 커밋**

```bash
git add boot/check.sh
git commit -m "Build kms crate in boot/check.sh before generating initrd"
```

- [ ] **Step 5: 실행해서 BF+DF 모두 3회 연속 PASS 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash check.sh
```

Expected: `=== BF-M4 run 1/3 ===`부터 `=== BF-M4 run 3/3 PASSED ===`까지 세 번,
`BF-M4 PASS: 3/3 consecutive runs succeeded`가 나온 뒤, 이어서
`=== DF-M3 run 1/3 ===`부터 `=== DF-M3 run 3/3 PASSED ===`까지 세 번,
`DF-M3 PASS: 3/3 consecutive runs succeeded`가 나오고, 마지막 줄에
`TARS check PASS: all chains 3/3 consecutive runs succeeded`가 출력된다.
종료 코드 0. 매 회차마다 kernel 전체 재컴파일이 일어나므로(6회) 실행
시간이 `display/check.sh` 단독 실행보다 훨씬 길다 — 정상이다.

**만약 특정 체인/회차에서 FAIL이 나면:** `{체인명} FAIL: run N/3 failed`로
어느 체인, 몇 번째 회차인지 먼저 확인한다.
- BF 체인이 실패하면: DF-M1에서 바뀐 `kernel/.config`(PCI/DRM/virtio-gpu
  활성화)가 fish 배너 부팅 경로에 영향을 줬을 가능성을 의심한다 —
  `boot/check.sh`를 단독으로 돌려 재현되는지 먼저 좁힌다.
- DF 체인이 1회차부터 실패하면: `display/check.sh`(Task 1) 자체의 문제.
- DF 체인이 2~3회차에서만 실패하면: HANDOFF.md의 "정정 5번"(타이밍
  플레이키니스, screendump 전 `sleep 5`)이 재현된 것일 가능성이 크다 —
  `display/check.sh`의 `sleep 5`를 더 늘려본다.

- [ ] **Step 6: `git status`로 초기화 재현성 확인**

Run:
```bash
git status
```

Expected: `kernel/initrd.cpio`가 수정된 것으로 나타날 수 있다(BF-M4 때와
동일한 이유 — 빌드 산출물이지만 관례상 git에 커밋돼 있음). 그 외 추적
파일에 의도치 않은 변경이 없는지 확인한다.

- [ ] **Step 7: 커밋**

`kernel/initrd.cpio`가 변경되지 않았다면:
```bash
git add check.sh
git commit -m "Extend check.sh to verify BF and DF chains 3x each"
```

`kernel/initrd.cpio`도 변경됐다면 두 커밋으로 나눈다:
```bash
git add check.sh
git commit -m "Extend check.sh to verify BF and DF chains 3x each"
git add kernel/initrd.cpio
git commit -m "Refresh initrd.cpio from DF-M3 check.sh run"
```

---

### Task 3: design doc·HANDOFF.md 정리

**Files:**
- Modify: `docs/superpowers/specs/2026-08-07-tars-display-foundation-design.md`
- Modify: `HANDOFF.md`

- [ ] **Step 1: design doc Status 갱신**

`docs/superpowers/specs/2026-08-07-tars-display-foundation-design.md`의
2번째 줄:

```markdown
**Status:** DF-M3 complete (2026-08-07); Display Foundation complete
```

- [ ] **Step 2: 커밋**

```bash
git add docs/superpowers/specs/2026-08-07-tars-display-foundation-design.md
git commit -m "Mark Display Foundation complete after DF-M3"
```

- [ ] **Step 3: HANDOFF.md를 다음 서브프로젝트 착수 전 상태로 갱신**

`superpowers:handoff` 스킬로 현재 상태(Display Foundation 전체 완료, 다음
서브프로젝트 미정)를 반영해 새로 작성한다. 다음 서브프로젝트 후보는
`docs/superpowers/specs/2026-08-01-tars-boot-foundation-design.md`의 "배경"
절 최종 비전 목록(compositor, PTY/terminal, input policy, IME, 패키지
관리자, AI 도구 통합)을 참고해 사용자와 논의할 것을 남긴다.

- [ ] **Step 4: 커밋**

```bash
git add HANDOFF.md
git commit -m "Update HANDOFF.md after Display Foundation completion"
```

---

## DF-M3 완료 확인

Task 2의 Step 3이 `TARS check PASS: all chains 3/3 consecutive runs
succeeded`로 끝나면 design doc 기준 DF-M3 exit gate(스크립트 3회 연속
실행 성공)를 만족하고, Display Foundation 서브프로젝트(DF-M0~M3) 전체가
완료된다.
