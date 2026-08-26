# TARS Gate Latency GL-M0 Implementation Plan

> **이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md`):** 구현 파일 편집은
> 사용자가 하고, 빌드·QEMU·게이트·조사성 명령은 Claude가 실행하며, Claude는 각
> Step의 정확한 내용을 제시하고 결과를 해석한다. 다른 저장소용 SUB-SKILL 문구는
> 이 저장소에 적용하지 않는다.

**Goal:** `clean()`을 매 회차에서 게이트 시작 1회로 옮겨 **빌드 24회를 1회 +
증분 23회로 바꾸고**, 그 대가로 열리는 "빌드 스텝을 빠뜨린 체인이 남의
산출물로 통과하는" 구멍을 게이트 진입 지점의 정적 검사로 닫는다.

**Design doc:** `docs/superpowers/specs/2026-08-26-tars-gate-latency-design.md`
(결정 1~4 전부가 이 milestone의 몫이다. **design은 승인되어 있으므로 다시
논의하지 않는다.**)

**Tech Stack:** bash 게이트 스크립트. **Zig도 커널도 게스트 코드도 건드리지
않는다** — 이 milestone은 게이트 자신만 고친다.

**고치는 파일은 `check.sh` 하나다.** 체인 여덟 개와 `kernel/make_initrd.sh`는
한 줄도 건드리지 않는다.

---

## 착수 전에 이미 확정된 사실 — 다시 조사하지 않는다

### 2026-08-26에 실측한 것

1. **회차당 빌드가 113초 이상, 증분은 29초다.** 단계별 값은 design doc의
   표에 있다. `run_chain`이 24회차를 돌리므로 빌드만 약 45분이고, 게이트
   기준선 54분 15초의 8할이 넘는다.
2. **Zig는 `touch`를 무시한다.** 소스를 touch만 하고 `zig build`를 돌리면
   산출물 mtime이 갱신되지 않는다. **그래서 신선도를 mtime으로 판정하는
   최초 설계가 폐기됐다.**
3. **make는 mtime을 따른다.** `kernel/.config`를 touch하면 bzImage를 다시
   만든다. `kernel/build.sh`가 매번 `cp .config build/.config`를 하므로
   증분 회차에도 13초가 남는다 — **GL-M1의 몫이고 이번에는 건드리지 않는다.**
4. **네 패턴이 여덟 체인 전부에서 매치된다.** 아래 Task 1의 `BUILD_STEPS`가
   그 네 패턴이고, 이 plan을 쓰면서 여덟 스크립트에 직접 돌려 확인했다.
   **Task 2가 그것을 검사로 다시 증명한다.**
5. **`input/check.sh:88`은 호출이 아니라 `echo` 문자열이다.**
   `echo "       kernel/make_initrd.sh needs to copy the file)"` — 패턴에
   `./`를 넣으면 이 줄에 안 걸린다.

### 이 plan을 쓰면서 `check.sh`에서 확인한 것

- **`set -uo pipefail`이지 `-e`가 아니다.** 실패를 자동으로 전파하지 않으므로
  새로 넣는 검사도 **명시적으로 `exit 1`을 해야 한다.**
- **체인 이름과 스크립트 경로가 `run_chain` 호출 8줄에만 있다.** 진입 검사가
  같은 목록을 훑어야 하는데, 목록을 새로 적으면 **경로가 두 곳에 중복된다.**
  design doc 위험 2가 지적한 병을 새로 만드는 셈이므로, Task 1은 목록을
  배열 하나로 모으고 검사와 실행이 그것을 함께 쓴다.
- **`clean()` 위의 주석 8줄과 체인 목록 위의 주석 67줄은 그대로 둔다.**
  전자는 지우면 안 되는 셋을, 후자는 체인마다의 부팅 횟수와 사연을 적어 둔
  것이라 이번 변경과 무관하다.

---

## Task 1: `check.sh`를 고친다

**Files:**
- Modify: `check.sh:14-33`(함수 구역), `check.sh:102-109`(체인 호출)

- [ ] **Step 1: `run_chain`에서 `clean` 호출을 뺀다**

`check.sh:22-30`이 지금 이렇다.

**지울 것** (24번 줄 하나):

```bash
    clean
```

**결과** — `run_chain`의 `for` 루프가 이렇게 남는다:

```bash
  for i in 1 2 3; do
    echo "=== ${name} run ${i}/3 ==="
    if ! "$script"; then
      echo "${name} FAIL: run ${i}/3 failed"
      exit 1
    fi
    echo "=== ${name} run ${i}/3 PASSED ==="
  done
```

- [ ] **Step 2: `clean()` 정의 바로 아래에 빌드 스텝 검사를 넣는다**

`clean()`의 닫는 `}`(16번 줄)와 `run_chain() {`(18번 줄) **사이**에 넣는다.

**넣을 것:**

```bash
# GL-M0: 체인이 자기가 부팅할 것을 스스로 빌드하는지 확인한다.
#
# clean()이 매 회차 지우던 시절에는 이 검사가 필요 없었다 — 빌드 스텝을
# 빠뜨린 체인은 `cp: cannot stat ...`으로 즉시 죽었다. 실제로 그 죽음이 사고
# 둘을 잡았다(DF-M3의 kms, TF-M4의 terminal 바이너리). clean을 게이트 시작
# 1회로 옮기면 그 체인은 대신 **남이 만들어 둔 산출물로 조용히 통과한다.**
#
# 그래서 부팅 전에 스크립트를 읽어서 판정한다. 산출물이 신선한지는 보지
# 않는다 — Zig는 내용 해시로 판단해서 touch를 무시하므로 mtime 비교는 내용이
# 같고 mtime만 새것인 상황(git checkout, 편집했다 되돌리기)에서 거짓 실패한다.
# 빌드를 부르기만 하면 반영은 Zig와 make가 보장한다. **부르는지만 본다.**
#
# 패턴에 './'가 들어 있는 것은 실행과 언급을 가르기 위함이다
# (input/check.sh:88의 echo 문자열이 실제 예다). 주석 줄을 걸러내는 것은
# 호출을 지우는 대신 #으로 막아 두는 손버릇을 잡기 위함이다.
#
# **빌드 스텝이 새로 생기면 이 목록도 함께 고쳐야 한다.**
BUILD_STEPS=(
  'cd ../kernel && ./build.sh)'
  'cd ../init && zig build)'
  './prepare.sh'
  './make_initrd.sh'
)

require_build_steps() {
  local script="$1"
  local step body missing=0

  body="$(grep -vE '^[[:space:]]*#' "$script")"

  for step in "${BUILD_STEPS[@]}"; do
    case "$body" in
      *"$step"*) ;;
      *)
        echo "check FAIL: ${script} never calls '${step}'" >&2
        missing=1
        ;;
    esac
  done

  return "$missing"
}
```

**`grep`의 결과를 `case`로 보는 것에 이유가 있다.** 파이프라인 끝에 `grep -q`를
두면 첫 매치에서 빠져나가며 앞단에 SIGPIPE를 일으키고 `pipefail`이 그것을
실패로 판정한다(`HANDOFF.md`). 변수에 담아 `case`로 본다.

- [ ] **Step 3: 체인 호출 8줄을 배열 + 진입 검사 + 실행 루프로 바꾼다**

`check.sh:102-109`가 지금 이렇다.

**지울 것** (8줄):

```bash
run_chain "BF-M4" ./boot/check.sh
run_chain "TF-M4" ./terminal/check.sh
run_chain "CP-M2" ./config/check.sh
run_chain "IP-M2" ./input/check.sh
run_chain "PM-M1" ./power/check.sh
run_chain "HD-M2" ./device/check.sh
run_chain "TR-M2" ./render/check.sh
run_chain "CM-M2" ./copy/check.sh
```

**넣을 것** (같은 자리, 바로 위의 긴 주석 블록은 그대로 둔다):

```bash
# 이름과 경로를 한 곳에 모은다. 진입 검사와 실행이 같은 목록을 쓰므로,
# 체인을 더하거나 뺄 때 고칠 자리가 하나다.
CHAINS=(
  "BF-M4:./boot/check.sh"
  "TF-M4:./terminal/check.sh"
  "CP-M2:./config/check.sh"
  "IP-M2:./input/check.sh"
  "PM-M1:./power/check.sh"
  "HD-M2:./device/check.sh"
  "TR-M2:./render/check.sh"
  "CM-M2:./copy/check.sh"
)

# 진입 검사는 **첫 부팅 전에** 여덟 개를 전부 훑는다. 하나라도 빠뜨렸으면
# 게이트를 시작하지 않는다 — 한 체인에서 멈추지 않고 끝까지 훑는 것은
# 고칠 자리를 한 번에 다 보여주기 위함이다.
entry_failed=0
for entry in "${CHAINS[@]}"; do
  require_build_steps "${entry#*:}" || entry_failed=1
done
if [ "$entry_failed" -ne 0 ]; then
  echo "TARS check FAIL: a chain would have run without building what it boots" >&2
  exit 1
fi

# GL-M0: clean은 여기서 한 번만 부른다. 예전에는 run_chain이 회차마다 불렀고
# 그것이 게이트 54분 중 약 45분을 만들었다(같은 산출물을 24번 빌드했다).
#
# 3회 반복이 잡는 것은 부팅과 게스트 입력의 flakiness이지 빌드 재현성이
# 아니다 — 같은 소스를 같은 컨테이너에서 다시 빌드하는 것이라 1회차가 통과한
# 것을 2·3회차가 실패시킬 경로가 사실상 없다. **반복의 목적을 부팅에 돌려주는
# 변경이지 반복을 줄이는 변경이 아니다.**
clean

for entry in "${CHAINS[@]}"; do
  run_chain "${entry%%:*}" "${entry#*:}"
done
```

- [ ] **Step 4: 편집 결과를 확인한다** (Claude가 실행)

```bash
bash -n check.sh && echo "syntax OK"
git diff --stat check.sh
echo "--- 지운 줄 ---"
git diff check.sh | grep -c '^-[^-]'
echo "--- clean 호출 자리 ---"
grep -n '^clean$\|^  clean$\|    clean' check.sh
```

기대: `syntax OK`, 지운 줄이 **9줄**(`run_chain` 안의 `clean` 1줄 + 체인 호출
8줄), `clean` 호출이 **최상위 한 자리**에만 남는다.

- [ ] **Step 5: 커밋** (Claude가 실행)

```bash
git add check.sh
git commit -m "Build once per gate instead of once per run"
```

---

## Task 2: 검사가 죽어야 할 때 죽는지 확인한다

**이 Task를 건너뛰면 아무 일도 하지 않는 코드를 넣은 것과 구분되지 않는다.**
IP-M2가 comptime 앵커를 일부러 깨뜨려 확인한 것과 같은 절차다.

**저장소 파일은 건드리지 않는다.** `check.sh`에서 검사 부분만 뽑아 정의하고,
`/tmp`에 만든 조작된 사본 셋에 돌린다.

**Files:**
- 없음 (조사성 실행만)

- [ ] **Step 1: 조작된 사본 셋에 검사를 돌린다** (Claude가 실행)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  set -uo pipefail
  # check.sh에서 BUILD_STEPS 배열과 require_build_steps 함수만 뽑아 온다.
  sed -n "/^BUILD_STEPS=(/,/^}/p" check.sh > /tmp/steps.sh
  echo "--- 뽑아 온 줄 수: $(wc -l < /tmp/steps.sh) ---"
  source /tmp/steps.sh

  # (a) 손대지 않은 사본 — 통과해야 한다
  cp copy/check.sh /tmp/a.sh

  # (b) make_initrd 호출을 지운 사본 — TF-M4 사고의 형태
  grep -v "make_initrd.sh)" copy/check.sh > /tmp/b.sh

  # (c) 호출을 지우고 같은 문자열을 주석으로 남긴 사본
  sed "s|^if ! (cd ../kernel \&\& ./make_initrd.sh); then|# (cd ../kernel \&\& ./make_initrd.sh)\nif false; then|" copy/check.sh > /tmp/c.sh

  # (d) 호출을 지우고 echo로 언급만 남긴 사본
  { grep -v "make_initrd.sh)" copy/check.sh; echo "echo \"see kernel/make_initrd.sh\""; } > /tmp/d.sh

  for f in /tmp/a.sh /tmp/b.sh /tmp/c.sh /tmp/d.sh; do
    if require_build_steps "$f" 2>/tmp/err; then
      echo "${f}: PASS"
    else
      echo "${f}: FAIL <- $(cat /tmp/err)"
    fi
  done
'
```

기대하는 출력:

```
/tmp/a.sh: PASS
/tmp/b.sh: FAIL <- check FAIL: /tmp/b.sh never calls './make_initrd.sh'
/tmp/c.sh: FAIL <- check FAIL: /tmp/c.sh never calls './make_initrd.sh'
/tmp/d.sh: FAIL <- check FAIL: /tmp/d.sh never calls './make_initrd.sh'
```

**(a)가 PASS해야 거짓 실패가 없다는 뜻이고, (b)·(c)·(d)가 FAIL해야 검사가
일을 한다는 뜻이다.** 특히 **(c)는 주석 거르기를, (d)는 `./` 접두사가 언급과
호출을 가르는 것을** 각각 증명한다. 넷 중 하나라도 어긋나면 Task 1로 돌아간다.

- [ ] **Step 2: 진입 검사가 게이트를 정말 막는지 확인한다** (Claude가 실행)

함수 단위가 아니라 `check.sh` 전체가 막히는 것을 본다. 체인 목록에 없는
경로를 하나 끼운 사본을 만들어 돌린다 — **부팅이 시작되지 않고 즉시 죽어야
한다.**

**`check.sh`는 첫 줄들에서 `cd "$(dirname "$0")"`를 한다.** 사본을 `/tmp`에
두고 그냥 돌리면 작업 디렉터리가 `/tmp`가 되어 체인 경로를 못 찾고, **의도한
것과 다른 이유로 죽는다.** 그래서 그 줄도 함께 바꿔 준다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  # 빌드를 하나도 안 부르는 가짜 체인을 목록에 끼운다.
  printf "#!/usr/bin/env bash\necho fake chain\n" > /tmp/fake_check.sh
  chmod +x /tmp/fake_check.sh
  sed -e "s|^cd \"\$(dirname \"\$0\")\"|cd /workspace|" \
      -e "s|^  \"BF-M4:./boot/check.sh\"|  \"XX-M0:/tmp/fake_check.sh\"\n  \"BF-M4:./boot/check.sh\"|" \
      check.sh > /tmp/check_broken.sh
  echo "--- cd 줄이 바뀌었는지 ---"
  grep -n "^cd " /tmp/check_broken.sh
  echo "--- 가짜 체인이 끼워졌는지 ---"
  grep -n "XX-M0" /tmp/check_broken.sh
  echo "--- 실행 ---"
  bash /tmp/check_broken.sh; echo "exit=$?"
'
```

기대: `check FAIL: /tmp/fake_check.sh never calls ...` 네 줄과
`TARS check FAIL: a chain would have run without building what it boots`,
그리고 `exit=1`. **`=== BF-M4 run 1/3 ===`이 한 줄도 나오면 안 된다** —
나오면 진입 검사가 실행보다 뒤에 있다는 뜻이다.

- [ ] **Step 3: 저장소가 안 더러워졌는지 확인한다** (Claude가 실행)

```bash
git status --short
```

기대: **비어 있다.** 조작은 전부 `/tmp` 안에서 했다. Docker가 없는 파일을
`-v`로 마운트하면 호스트에 0바이트 파일을 남기는 성질이 있으므로
(`HANDOFF.md`) 매번 확인한다.

---

## Task 3: 증분 회차가 통과하는지 짧게 확인한다

**54분(예상 22분)짜리 루트 게이트를 돌리기 전에, 이 변경의 핵심 가정 —
"clean 없이 두 번째·세 번째 회차를 돌려도 체인이 통과한다" — 을 체인 하나로
먼저 본다.** 실패한다면 루트 게이트에서 발견하는 것보다 훨씬 싸다.

`boot` 체인을 고른 이유는 셋이다. 커널·`init`·`terminal`·initrd·ISO를 **전부**
만드는 유일한 체인이고, 타이핑이 없어 잡음이 적으며, ISO 부팅이라 initrd가
낡으면 가장 먼저 티가 난다.

**Files:**
- 없음 (조사성 실행만)

- [ ] **Step 1: clean 1회 뒤 boot 체인을 3연속으로 돌린다** (Claude가 실행)

**약 5~7분 걸린다.**

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
'
```

기대: **세 회차 모두 `PASS`**, 1회차가 2분 안팎이고 **2·3회차가 그보다 뚜렷하게
짧다.** 2·3회차가 1회차만큼 걸리면 증분 빌드가 듣지 않는다는 뜻이므로,
루트 게이트로 넘어가지 말고 어느 단계가 다시 빌드하는지 design doc의 단계별
표와 대조해 찾는다.

- [ ] **Step 2: 결과를 해석해 기록한다**

세 회차의 시간을 적어 둔다. **Task 4의 전체 게이트 시간을 예측하는 근거가
되고, 예측이 빗나갔을 때 어디를 볼지 정해 준다.**

---

## Task 4: 루트 게이트 전체를 돌리고 새 기준선을 잰다

**Files:**
- 없음 (게이트 실행만)

- [ ] **Step 1: 게이트를 background로 돌린다** (Claude가 실행)

**예상 22분이지만 최대 54분까지 열어 둔다.** Bash 도구의 10분 상한을 넘으므로
`run_in_background`로 돌린다(`HANDOFF.md`). `| tail -N`을 붙이지 않는다 —
`tail`이 파이프가 닫힐 때까지 아무것도 안 내보내 진행 상황을 볼 수 없다.

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
    bash check.sh > /tmp/gate.out 2>&1 ; } 2> /tmp/gate.time
```

`--platform`을 붙이지 않는다(`project_build_host_arch`).

- [ ] **Step 2: 판정과 시간을 읽는다** (Claude가 실행)

```bash
cat /tmp/gate.time
grep -aE 'PASS: 3/3|FAIL' /tmp/gate.out
tail -3 /tmp/gate.out
```

기대: 여덟 줄의 `... PASS: 3/3 consecutive runs succeeded`와 마지막 줄
`TARS check PASS: all chains 3/3 consecutive runs succeeded`.

**시간이 예상만큼 안 줄어도 그 자체가 결과다.** 이 게이트는 ±3분의 잡음을
가지지만 32분짜리 절약은 잡음 밖이라 갈린다. 안 갈리면 증분 빌드가 예상대로
no-op이 아니라는 뜻이므로 단계별로 다시 잰다.

**값이 기준선에서 크게 벗어나면 코드를 의심하기 전에 기계를 먼저 의심한다.**
TR-M2를 끝내며 처음 잰 값이 6시간 12분이었고 원인은 Chrome의 영상 재생이었다
(`HANDOFF.md`). 다만 **사후에는 `pmset -g log`로 부하를 못 가른다** — 의심되면
다시 잰다.

- [ ] **Step 3: 실패했을 때** (Claude가 실행)

체인이 실패하면 어느 회차인지부터 본다.

```bash
grep -aE '=== .* run [0-9]/3 ===|FAIL' /tmp/gate.out | head -40
```

**2회차나 3회차에서만 실패하면 증분 빌드가 원인일 가능성이 높다** — 그 체인만
따로 Task 3의 방식으로 돌려 재현한다. 1회차에서 실패하면 clean 정책과 무관한
회귀이므로 변경을 되짚는다.

---

## Task 5: 문서와 기억을 갱신하고 닫는다

**Files:**
- Modify: `docs/superpowers/specs/2026-08-26-tars-gate-latency-design.md`(Status 줄)
- Create: `docs/decisions/project_gate_latency.md`
- Modify: `MEMORY.md`(색인 한 줄)
- Modify: `HANDOFF.md`

- [ ] **Step 1: design doc의 `Status:` 줄을 고친다** (Claude가 작성)

```markdown
**Status:** 설계 확정. **GL-M0 완료(2026-08-26)**, GL-M1 미착수
```

- [ ] **Step 2: 기억 파일을 만든다** (Claude가 작성)

`docs/decisions/project_gate_latency.md`에 담을 것은 넷이다. **실측값과 그것을
어떻게 얻었는지를 함께 적는다** — 숫자만 적으면 다음 사람이 다시 잰다.

1. 게이트 시간의 내역(빌드 45분 · 키 입력 5분 50초 · 부팅 1분 미만)과 그것을
   가른 방법(단계별 `date +%s`, `clean` 직후와 증분을 따로).
2. **Zig는 `touch`를 무시하고 make는 따른다** — mtime으로 신선도를 판정하려는
   시도를 다시 하지 않도록.
3. **clean을 1회로 줄이면 "빌드 스텝을 빠뜨린 체인"이 조용히 통과한다**는 것과
   그것을 정적 검사로 막았다는 것, 그리고 **필수 스텝 목록이 체인과 따로
   논다**는 남은 병.
4. **"clean 1회로 충분하다"는 판단이지 증명이 아니다**(design doc 위험 3).
   뒤집을 근거가 나오면 되돌릴 수 있게 남긴다.

- [ ] **Step 3: `MEMORY.md`에 색인 한 줄을 더한다** (Claude가 작성)

"프로젝트 (project)" 절 끝에 붙인다. **본문을 여기 쓰지 않는다.**

```markdown
- [Gate latency](docs/decisions/project_gate_latency.md) — 게이트 54분의 8할은 같은 산출물을 24번 빌드하는 비용이었다; clean을 1회로 옮기고 빌드 스텝 검사로 구멍을 막았다, Zig는 touch를 무시하고 make는 따른다
```

- [ ] **Step 4: `HANDOFF.md`를 갱신한다** (Claude가 작성)

고칠 자리가 여럿이다.

- 제목과 "지금 어디인가" — GL-M0가 끝났고 GL-M1이 다음이라는 것.
- **"게이트 현황"의 기준선 54분 15초** → Task 4의 실측값.
- **"루트 게이트는 54분이라 Bash 도구의 10분 타임아웃을 넘는다"** → 새 값으로.
  22분이어도 여전히 `run_in_background`가 필요하다.
- **이월 숙제에서 `clean()` 항목을 뺀다**(끝났다). `init`을 `ReleaseSafe`로와
  `sleep 0.3` 줄이기는 **남기되 판정을 함께 적는다** — 전자는 게이트 시간
  안건이 아니었고 GL-M1의 `make_initrd` 9초에서만 값이 있으며, 후자는
  side effect 우려로 미뤘다는 것.
- **"서브프로젝트를 넘어 유효한 실측"에 mtime 계약을 더한다.**

- [ ] **Step 5: 커밋** (Claude가 실행)

```bash
git status --short
git add docs/superpowers/specs/2026-08-26-tars-gate-latency-design.md \
        docs/decisions/project_gate_latency.md MEMORY.md HANDOFF.md
git commit -m "Close out GL-M0"
```

`git add` 전에 `M`과 신규를 가른다(`CLAUDE.md`). 이 저장소는 빌드 산출물이
계속 생기므로 add 대상을 항상 좁혀서 지정한다.

---

## 이 milestone이 하지 않는 것

- **`kernel/build.sh`의 13초.** 원인은 이미 확인됐지만 GL-M1의 몫이다.
- **`make_initrd.sh`의 9초.** 같은 이유로 GL-M1이다.
- **`type_keys`의 `sleep 0.3`.** side effect 우려로 이월했다.
- **`run_chain`의 3회를 줄이는 것.** 반복이 잡는 것은 부팅 flakiness이고 이
  변경은 그것을 건드리지 않는다.
- **`clean()`의 대상 목록.** 지우면 안 되는 넷에 대한 판단은 그대로 둔다.
