# TARS Gate Latency GL-M1 Implementation Plan

> **이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md`):** 구현 파일 편집은
> 사용자가 하고, 빌드·QEMU·게이트·조사성 명령은 Claude가 실행하며, Claude는 각
> Step의 정확한 내용을 제시하고 결과를 해석한다. 다른 저장소용 SUB-SKILL 문구는
> 이 저장소에 적용하지 않는다.

**Goal:** 증분 회차 29초에서 **약 18초를 걷어낸다.** `gzip -9`를 `-6`으로
낮추고, `init`을 `ReleaseSafe`로 만들고, 커널 빌드가 할 일 없을 때 make를 아예
부르지 않게 한다.

**Design doc:** `docs/superpowers/specs/2026-08-26-tars-gate-latency-design.md`
의 "GL-M1" 절. **design은 승인되어 있으므로 다시 논의하지 않는다.**

**Tech Stack:** bash 빌드 스크립트, `build.zig`. **게스트 코드도 커널 설정도
건드리지 않는다** — 바뀌는 것은 "무엇을 어떻게 빌드하는가"뿐이다.

**고치는 파일 셋:** `kernel/make_initrd.sh` · `init/build.zig` ·
`kernel/build.sh`. 체인 여덟과 `check.sh`는 한 줄도 안 건드린다.

---

## 착수 전에 이미 확정된 사실 — 다시 조사하지 않는다

### 증분 회차 29초의 내역 (2026-08-26 실측)

| 단계 | 시간 | 정체 |
|---|---|---|
| `kernel/build.sh` | 13초 | **make의 트리 스캔**(`olddefconfig` 1.3초 + "할 일 없음" 확인 9.3초) |
| `init`·`terminal`의 `zig build test` | 각 3초 | |
| `terminal/prepare.sh` | 1초 | |
| `kernel/make_initrd.sh` | 9초 | **전부 `gzip -9`**(8.7초). cpio로 묶는 것은 154ms다 |

### gzip 레벨의 값

| | 크기 | 시간 |
|---|---|---|
| `gzip -1` | 19,531,989 | 700ms |
| `gzip -6` | 17,060,239 | 2,020ms |
| `gzip -9`(현재) | 16,835,576 | 8,729ms |

**`-9`는 `-6`보다 224,663바이트(1.3%) 작아지자고 6.7초를 더 쓴다.** 크기가
부팅에 미치는 영향은 ZM-M1이 이미 쟀다 — initrd가 19% 커져도 BF 부팅 시간이
변하지 않았으므로 1.3%는 영향권 밖이다.

### `init`의 `ReleaseSafe`

- **11,745,656 → 3,331,160바이트**(72% 감소). `init`은 libc를 링크하지 않아
  fortify 제약이 없다(`project_zig_c_uapi_rule`).
- **`-6`과 조합하면 initrd 15,725,317바이트에 gzip 1,804ms다** — 지금(Debug +
  `-9`, 16,835,576바이트, 8,729ms)보다 **1.1MB 작으면서 6.9초 빠르다.**
- 대가는 `init` 컴파일이 9초 → 10.7초로 1.7초 느려지는 것뿐이다.

### `terminal`은 이 길로 못 간다 — 시도하지 말 것

`-Doptimize=ReleaseSafe`가 `drm.zig:3`의 `@cImport`를 `error: C import failed`로
깨뜨린다. glibc fortify 헤더가 최적화 모드에서 활성화되기 때문이고 TF-M4가
이미 겪었다. 우회(`@cDefine("_FORTIFY_SOURCE", "0")`)까지
`project_zig_c_uapi_rule`에 적혀 있지만, **검증 대상 바이너리의 컴파일 모드를
바꾸는 일이라 GL-M1 범위 밖이다.** 42.7MB는 그대로 간다.

### `cp .config`는 13초의 원인이 아니다

`cp`를 하든 안 하든 같았다(9,304ms 대 8,962ms). **한때 그렇게 적었다가
정정했다** — mtime이 make의 판단 근거인 것은 맞지만 `.config` 내용이 같으면
재빌드로 이어지지 않는다.

---

## Task 1: `gzip -9`를 `-6`으로 낮춘다

**Files:**
- Modify: `kernel/make_initrd.sh:199`

- [ ] **Step 1: 마지막 줄의 압축 레벨을 바꾸고 이유를 주석에 남긴다**

`kernel/make_initrd.sh`의 **마지막 줄**이 지금 이렇다.

**지울 것** (한 줄):

```bash
(cd "$WORKDIR" && find . | cpio -o -H newc) | gzip -9 > initrd.cpio
```

**넣을 것:**

```bash
# GL-M1: -9가 아니라 -6이다. 이 줄이 make_initrd.sh 9초의 거의 전부였고
# (cpio로 묶는 것은 154ms다), -9는 -6보다 224,663바이트(1.3%) 작아지자고
# 6.7초를 더 쓴다(16,835,576 대 17,060,239, 8,729ms 대 2,020ms). 루트 게이트는
# 그 6.7초를 24회 치른다.
#
# 크기를 늘려도 되는 근거는 실측이다 — ZM-M1에서 initrd가 11.8MB에서 14MB로
# 19% 늘었는데 BF 부팅 시간이 34/33/33초로 변하지 않았다
# (docs/decisions/project_gate_chain_composition.md). 1.3%는 그 영향권 밖이다.
# 53MB에서 부팅조차 못 했던 것은 선형적인 느려짐이 아니라 다른 종류의 벽이었다.
(cd "$WORKDIR" && find . | cpio -o -H newc) | gzip -6 > initrd.cpio
```

**바로 위의 긴 주석 블록(190~198줄)은 그대로 둔다** — 왜 압축하는지, 파일명을
왜 유지하는지가 거기 있고 이번 변경과 무관하다.

- [ ] **Step 2: 확인** (Claude가 실행)

```bash
bash -n kernel/make_initrd.sh && echo "syntax OK"
grep -n 'gzip -' kernel/make_initrd.sh
```

기대: `syntax OK`, `gzip -6`이 **한 자리**에만 있다.

---

## Task 2: `init`을 `ReleaseSafe`로 만든다

**Files:**
- Modify: `init/build.zig:15-22`

- [ ] **Step 1: `exe_mod`의 최적화 모드만 고정한다**

`init/build.zig:15`가 지금 이렇다.

**지울 것** (4줄 — `exe_mod` 선언의 앞부분):

```zig
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
```

**넣을 것:**

```zig
    // GL-M1: initrd에 들어가는 것은 이 exe 하나뿐이라 여기만 최적화 모드를
    // 고정한다. Debug 11,745,656 → ReleaseSafe 3,331,160바이트(72% 감소)이고,
    // 그만큼 gzip도 부팅 중 압축 해제도 빨라진다.
    //
    // init이 이 길로 갈 수 있는 이유는 libc를 링크하지 않기 때문이다 —
    // terminal을 Debug에 묶어 둔 fortify 제약(@cImport가 최적화 모드에서
    // 깨진다)이 여기에는 없다(docs/decisions/project_zig_c_uapi_rule.md).
    //
    // 게스트 안 에러 트레이스는 살아 있다. ReleaseSafe는 strip이 아니라
    // 심볼도 안전 검사도 유지한다 — strip을 안 쓰기로 한 이유는
    // docs/decisions/project_gate_chain_composition.md에 있다.
    //
    // 아래 세 test_mod는 위의 `optimize`를 그대로 쓴다. 호스트가 돌리는
    // 검사라 크기와 무관하고, 여기까지 최적화하면 `zig build test`만 느려진다.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
```

**`.single_threaded = true`와 그 아래 주석은 그대로 둔다.**

- [ ] **Step 2: 확인** (Claude가 실행)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  (cd init && zig build) && echo "init: $(stat -c %s init/zig-out/bin/init) bytes"
  s=$(date +%s%N); (cd init && zig build test) >/dev/null 2>&1; e=$(date +%s%N)
  echo "zig build test: $(( (e-s)/1000000 ))ms"
'
```

기대: `init` 크기가 **3,331,160바이트 근처**(Debug 11,745,656이 아니어야 한다),
그리고 `zig build test`가 **3초 근처**(검사까지 최적화됐다면 더 느려진다).

---

## Task 3: 커널 빌드가 할 일 없을 때 make를 부르지 않는다

**Files:**
- Modify: `kernel/build.sh` (다운로드 블록과 `mkdir -p build` 사이)

- [ ] **Step 1: 스킵 판정을 넣는다**

`kernel/build.sh`에서 다운로드 블록(`if [ ! -d "$SRC_DIR" ]; then ... fi`)이
끝나는 `fi` **다음**, `mkdir -p build` **앞**에 넣는다.

**넣을 것:**

```bash
# GL-M1: make가 "할 일 없음"을 확인하는 데만 9.3초가 들고 olddefconfig가 1.3초를
# 더한다. 증분 회차 29초 중 13초가 그것이었고, 루트 게이트는 24회 치른다.
#
# 커널 소스는 tarball을 푼 뒤 불변이므로 이 빌드의 입력은 .config와 이 파일
# 둘뿐이다. 그래서 그 둘의 해시를 산출물 옆에 적어 두고 대조한다.
#
# **mtime으로 판정하지 않는다.** 처음에는 bzImage가 .config보다 새것인지 보는
# 방식이었는데, .config의 mtime만 새것이 되면(git checkout, 편집했다 되돌리기)
# make가 내용이 같다고 판단해 bzImage를 갱신하지 않으므로 판정이 "빌드 필요"에
# **고착되어 영영 스킵되지 않는다.** GL-M0이 신선도 검사에서 겪은 것과 같은
# 병이다(docs/decisions/project_gate_latency.md).
#
# build.sh 자신이 해시에 들어가는 것이 중요하다. KERNEL_VERSION이 이 파일 안에
# 있어서, 커널 버전을 올리면 SRC_DIR이 바뀌고 새 소스를 받는데 build/는 옛
# 산출물을 그대로 갖고 있다. 이 파일을 함께 보지 않으면 **버전을 올린 뒤에도
# 낡은 bzImage로 부팅한다.**
#
# clean()이 kernel/build를 통째로 지우므로 스탬프도 함께 사라진다 — 게이트
# 첫 회차는 언제나 진짜로 빌드한다.
BZIMAGE=build/arch/x86/boot/bzImage
STAMP=build/.tars-build-stamp
BUILD_INPUTS="$(cat .config build.sh | sha256sum | cut -d' ' -f1)"
if [ -f "$BZIMAGE" ] && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$BUILD_INPUTS" ]; then
  echo "kernel: bzImage matches .config and build.sh, skipping make"
  exit 0
fi
```

- [ ] **Step 2: 파일 맨 끝에 스탬프를 남긴다**

`make ... bzImage` 줄 **다음**에 붙인다.

**넣을 것:**

```bash

# 빌드가 성공한 뒤에만 적는다. 중간에 죽으면 스탬프가 없어 다음 실행이 다시
# 빌드한다 — set -e가 그것을 보장한다.
echo "$BUILD_INPUTS" > "$STAMP"
```

- [ ] **Step 3: 확인** (Claude가 실행)

```bash
bash -n kernel/build.sh && echo "syntax OK"
grep -n 'BZIMAGE\|STAMP\|BUILD_INPUTS\|mkdir -p build\|bzImage$' kernel/build.sh
tail -3 kernel/build.sh
```

기대: `syntax OK`, 판정이 `mkdir -p build`보다 **앞**, 스탬프 기록이
`make ... bzImage`보다 **뒤**에 있다.

---

## Task 4: 스킵 판정을 일곱 가지로 깨뜨려 확인한다

**이 Task를 건너뛰면 "언제나 스킵하는" 코드와 구분되지 않는다.** 그리고
**mtime과 내용을 가르는 경우가 반드시 들어가야 한다** — 최초 설계(mtime 비교)가
바로 그 자리에서 실패했다.

**Files:**
- 없음 (조사성 실행만)

- [ ] **Step 1: 일곱 경우를 돌린다** (Claude가 실행)

**약 3분 걸린다**(재빌드가 네 번 일어난다).

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  t() { local s=$(date +%s%N); (cd kernel && ./build.sh) 2>&1 | tail -1; local e=$(date +%s%N); echo "   → $(( (e-s)/1000000 ))ms"; }
  echo "=== (0) build.sh를 고쳤으므로 빌드 ==="; t
  echo "=== (a) 그냥 한 번 더 → 스킵 ==="; t
  echo "=== (b) .config touch (내용 동일) → 스킵해야 한다 ==="; touch kernel/.config; t
  echo "=== (c) build.sh touch (내용 동일) → 스킵해야 한다 ==="; touch kernel/build.sh; t
  echo "=== (d) .config 내용 변경 → 빌드 ==="
  cp kernel/.config /tmp/config.bak
  printf "# probe\n" >> kernel/.config
  t
  echo "=== (e) .config 복원 → 빌드(내용이 또 달라졌다) ==="
  cp /tmp/config.bak kernel/.config; t
  echo "=== (f) 한 번 더 → 스킵 ==="; t
  echo "=== (g) bzImage 삭제 → 빌드 ==="; rm -f kernel/build/arch/x86/boot/bzImage; t
'
```

기대: **(a)·(b)·(c)·(f)는 `skipping make`와 함께 10ms 미만**,
**(0)·(d)·(e)·(g)는 그 줄이 안 나오고 8초 이상** 걸린다.

- **(b)와 (c)가 이 검사의 핵심이다.** mtime 방식에서는 여기서 빌드가 일어났고,
  게다가 make가 내용이 같다고 bzImage를 안 갱신하는 바람에 **그 뒤로 영영
  스킵되지 않았다.** 둘이 스킵되지 않으면 내용 해시가 안 듣는 것이다.
- **(g)가 빠르면** 스탬프만 보고 산출물을 안 보는 것이다.
- **(d)가 빠르면** `.config` 변경을 놓치는 것이고, 게이트가 낡은 커널로
  부팅하게 된다.

- [ ] **Step 2: `.config`가 복원됐는지 확인한다** (Claude가 실행)

```bash
git status --short
tail -1 kernel/.config
```

기대: `kernel/.config`가 **`git status`에 없고**, 마지막 줄이
`# end of Kernel hacking`이다((d)가 붙인 `# probe`가 남아 있으면 안 된다).

- [ ] **Step 2: 저장소가 안 더러워졌는지 확인한다** (Claude가 실행)

```bash
git status --short
```

기대: **비어 있다.** `touch`는 mtime만 바꾸고 git은 내용으로 판단한다.

---

## Task 5: 증분 회차가 통과하는지 짧게 확인한다

GL-M0와 같은 이유로 `boot` 체인을 먼저 본다. **이번에는 initrd의 내용과 커널
빌드 경로가 둘 다 바뀌었으므로 짧은 확인의 값이 더 크다.**

**Files:**
- 없음 (조사성 실행만)

- [ ] **Step 1: clean 1회 뒤 boot 체인을 3연속으로 돌린다** (Claude가 실행)

**약 4~6분 걸린다.**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf kernel/build init/zig-out init/.zig-cache terminal/zig-out terminal/.zig-cache out
  for i in 1 2 3; do
    s=$(date +%s)
    if ./boot/check.sh > /tmp/boot_${i}.log 2>&1; then r=PASS; else r=FAIL; fi
    e=$(date +%s)
    echo "run ${i}/3: ${r} in $((e-s))s"
    [ "$r" = FAIL ] && tail -20 /tmp/boot_${i}.log
  done
  echo "initrd: $(stat -c %s kernel/initrd.cpio) bytes"
  echo "init:   $(stat -c %s init/zig-out/bin/init) bytes"
  true
'
```

기대: **세 회차 모두 `PASS`.** GL-M0 때는 131초 → 32초 → 31초였고, 이번에는
2·3회차가 **13초 근처**여야 한다(커널 13초와 gzip 6.7초가 빠진다). initrd는
**15.7MB 근처**, `init`은 **3.3MB 근처**다.

**부팅이 실패하면 가장 먼저 볼 것은 `ReleaseSafe` init이다.** 최적화가 PID 1의
동작을 바꿨다면 로그가 `tars-init:` 줄에서 끊긴다. `/tmp/boot_1.log`의
마지막 20줄이 그것을 보여준다.

---

## Task 6: 루트 게이트를 돌리고 새 기준선을 잰다

**Files:**
- 없음 (게이트 실행만)

- [ ] **Step 1: 게이트를 background로 돌린다** (Claude가 실행)

**예상 약 17분 30초이지만 24분까지 열어 둔다.** Bash 도구의 10분 상한을
넘으므로 `run_in_background`로 돌린다. `| tail -N`을 붙이지 않는다.

```bash
caffeinate -i -t 3600 &
CAF=$!
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
    bash check.sh > /tmp/gate.out 2>&1 ; } 2> /tmp/gate.time
echo "=== 게이트 종료 ==="
cat /tmp/gate.time
kill $CAF 2>/dev/null || true
```

- [ ] **Step 2: 판정과 시간을 읽는다** (Claude가 실행)

```bash
cat /tmp/gate.time
grep -aE 'PASS: 3/3|FAIL' /tmp/gate.out
grep -ac 'skipping make' /tmp/gate.out
tail -3 /tmp/gate.out
```

기대: 여덟 줄의 `PASS: 3/3`, 마지막 줄 `TARS check PASS`, 그리고
**`skipping make`가 23회**(24회차 중 첫 회차만 실제로 빌드한다).

**`skipping make`가 24회면 첫 회차도 건너뛴 것이므로 잘못이다** — `clean()`이
`kernel/build`를 지우므로 첫 회차에는 bzImage가 없어야 한다.

- [ ] **Step 3: 실패했을 때** (Claude가 실행)

```bash
grep -aE '=== .* run [0-9]/3 ===|FAIL' /tmp/gate.out | head -40
```

**이번 변경은 실패 원인이 셋으로 갈린다.** (1) `ReleaseSafe` init이면 부팅
로그가 `tars-init:`에서 끊기고, (2) 스킵 판정이면 낡은 커널로 부팅해 커널
문구를 보는 체인(PM·HD)이 흔들리며, (3) gzip 레벨이면 BF만 느려진다.
**어느 체인이 깨졌는지가 곧 어느 변경이 원인인지를 가리킨다.**

---

## Task 7: 문서와 기억을 갱신하고 서브프로젝트를 닫는다

**GL-M1이 Gate Latency의 마지막 milestone이다.** 끝나면 진행 중인
서브프로젝트가 없어지므로 문서 작업이 GL-M0 때보다 한 겹 많다.

**Files:**
- Modify: `docs/superpowers/specs/2026-08-26-tars-gate-latency-design.md`(Status와 GL-M1 결과)
- Modify: `docs/decisions/project_gate_latency.md`
- Modify: `HANDOFF.md`
- Modify: `CLAUDE.md`(완료 목록과 "진행 중" 줄)

- [ ] **Step 1: design doc에 GL-M1 결과를 인용 블록으로 넣는다** (Claude가 작성)

GL-M0가 쓴 것과 같은 형식으로, 새 기준선·`skipping make` 횟수·initrd 크기·
Task 4의 네 경우를 적는다. `Status:` 줄은 **"GL-M0·M1 완료로 서브프로젝트가
끝났다"**로 바꾼다.

- [ ] **Step 2: 기억 파일을 갱신한다** (Claude가 작성)

`docs/decisions/project_gate_latency.md`에 더할 것은 셋이다.

1. **최종 기준선**(54분 15초 → 24분 09초 → GL-M1의 값)과 각 단계가 무엇을
   걷어냈는지.
2. **`gzip -9`가 값을 못 하는 압축 레벨이라는 것** — 1.3% 크기에 6.7초.
3. **커널 빌드 스킵 판정이 `build.sh` 자신도 비교한다는 것과 그 이유**
   (`KERNEL_VERSION`이 그 안에 있다). 이건 나중에 커널 버전을 올릴 사람이
   반드시 알아야 한다.

`description:` frontmatter도 함께 늘린다 — 그 줄이 회수 판단에 쓰인다.

- [ ] **Step 3: `HANDOFF.md`를 갱신한다** (Claude가 작성)

- 제목과 "지금 어디인가" — **서브프로젝트가 닫혔고 진행 중인 것이 없다**는 것.
- **게이트 현황의 기준선**을 새 값으로. `run_in_background`가 여전히 필요한지도
  다시 판단해 적는다(10분을 넘으면 필요하다).
- **"다음 일: GL-M1의 plan을 쓴다" 절을 지우고** 다음 후보 목록으로 바꾼다.
- **"서브프로젝트를 넘어 유효한 실측"에** gzip 레벨과 `terminal`이 Debug에
  묶여 있다는 것을 더한다.

- [ ] **Step 4: `CLAUDE.md`의 서브프로젝트 현황을 고친다** (Claude가 작성)

완료 목록에 **Gate Latency(GL-M0~M1)**를 더하고, "진행 중인 서브프로젝트는
Gate Latency다" 줄을 **"진행 중인 서브프로젝트가 없다"**로 되돌린다.

- [ ] **Step 5: 커밋** (Claude가 실행)

```bash
git status --short
git add docs/superpowers/specs/2026-08-26-tars-gate-latency-design.md \
        docs/decisions/project_gate_latency.md HANDOFF.md CLAUDE.md
git commit -m "Close out Gate Latency"
```

`git add` 전에 `M`과 신규를 가른다. 빌드 산출물이 섞이지 않았는지 확인한다.

---

## 이 milestone이 하지 않는 것

- **`terminal`을 `ReleaseSafe`로.** `@cImport`가 깨진다. 우회는 있지만 검증
  대상의 컴파일 모드를 바꾸는 일이라 따로 다룬다.
- **`gzip -1`.** `-6`보다 1.3초 더 빠르지만 initrd가 2.5MB 커진다. `-6`이
  크기와 시간 둘 다에서 합리적인 자리다.
- **`type_keys`의 `sleep 0.3`.** side effect 우려로 이월했다.
- **`zig build test`의 3초씩.** 검사를 안 돌리는 방향은 게이트의 목적에
  어긋난다.
- **`clean()`의 대상 목록과 `run_chain`의 3회.** GL-M0에서 정한 그대로 둔다.
