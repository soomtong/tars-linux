# TARS Hardware Discovery HD-M1 Implementation Plan

> **이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md`):** 파일 작성과
> 명령 실행은 사용자가 직접 하고, Claude는 각 Step의 정확한 내용을 제시하고
> 결과를 해석한다. 다른 저장소용 SUB-SKILL 문구는 이 저장소에 적용하지 않는다.

**Goal:** 커널에 ACPI를 최소한으로 켜서, `reboot(POWER_OFF)`이 HALT로 강등되지
않고 **기계가 진짜로 꺼지게** 만든다. 지금 `power/check.sh`가 HALT에 멈춘
QEMU를 대신 죽여 주고 있는데, 그 손길이 사라지는 것이 이 milestone의 완료
증거다.

**Design doc:** `docs/superpowers/specs/2026-08-20-tars-hardware-discovery-design.md`
(결정 10과 결정 11의 HD-M1 항목이 이 milestone의 몫이다. 결정 4·7·8·9는
HD-M2가 가져간다. design은 이미 승인되어 있으므로 다시 논의하지 않는다.)

**Tech Stack:** Linux 6.18.42 Kconfig(`olddefconfig`), QEMU의 ACPI 고정 하드웨어
전원 경로, Docker(`tars-devcontainer`, arm64), bash 게이트 스크립트

---

## 이 milestone은 두 가지를 동시에 증명한다

**1. 기계가 스스로 꺼진다.** PM-M1이 여기서 멈췄다. `reboot(POWER_OFF)`을
불렀는데 커널이 `Power off not available: System halted instead`를 찍고
멈춰만 섰다(`kernel/reboot.c:321`). 전원을 실제로 끊어 줄 주체가 없었기
때문이다. ACPI가 그 주체다.

**2. HD-M0의 탐색기가 옳았다.** ACPI 전원 버튼 드라이버가 evdev 장치를 하나
더 등록하면서 키보드의 번호가 뒤로 밀린다. **번호가 밀렸는데도 TF·IP 체인이
통과하는 그 순간이 증명이다.** HD-M0은 이 증명을 만들 수 없었다 — 그때는
`event0`이 곧 키보드라서, 틀린 탐색기도 똑같이 통과했다.

둘째 증명에는 함정이 하나 있다. 증명이 **관측으로만 남으면 곧 사라진다.**
누군가 나중에 커널에서 ACPI를 다시 끄면 입력 장치가 다시 하나가 되고, TF
체인은 아무 불평 없이 통과한다. 그래서 Task 4에서 "ACPI가 입력 장치를 하나
더 등록했는가"를 게이트가 직접 요구하게 만든다. 게이트가 안 보는 것은
게이트가 통과시킨다(`project_gate_chain_composition`).

## 왜 이 순서인가

```
Task 1   ACPI 없는 커널 빌드 시간을 잰다            ← 기준선. 되돌릴 수 없다
  ↓      .config가 olddefconfig의 고정점인지도 함께 본다
Task 1.5 .config를 고정점으로 되접는다              ← ACPI와 섞이기 전에
  ↓      다음 커밋의 diff가 순수하게 ACPI 몫이 되도록
Task 2   .config를 고치고 olddefconfig의 결과를 읽는다
  ↓      무엇이 따라 들어왔는지 diff로 확정하고 고정점으로 되접는다
Task 3   부팅해서 장치가 밀리는 것을 눈으로 본다
  ↓      게이트 문구는 실제로 찍힌 것을 보고 확정한다
Task 4   게이트가 ACPI의 존재를 요구한다            ← 둘째 증명을 붙박는다
  ↓
Task 5   전원 게이트가 "스스로 꺼졌는가"를 요구한다  ← 완료선
  ↓
Task 6   루트 게이트 3/3 + 전체 시간 실측
  ↓
Task 7   문서
```

**Task 1이 맨 앞인 이유는 되돌릴 수 없는 측정이기 때문이다.** ACPI를 켠 뒤에는
"켜기 전에 얼마였는가"를 다시 잴 수 없다. `.config`를 되돌려 재는 방법이
있기는 하지만 그러려면 커널을 두 번 더 빌드해야 한다.

**Task 3이 Task 4·5보다 앞인 이유는 로그 문구 때문이다.** 게이트가 grep할
문자열은 실제로 찍힌 것을 보고 확정해야 한다. 코드에 적은 문구와 게이트가
찾는 문구가 어긋나는 사고가 이 저장소에 이미 있었다.

**Task 5가 Task 4보다 뒤인 이유는 위험의 크기다.** Task 4는 검사를 하나
더하는 일이고, Task 5는 통과 조건 자체를 바꾸는 일이다. 앞의 것이 통과한
상태에서 뒤의 것에 손댄다.

## 이번에 정하는 것 여섯 (design doc이 안 정한 자리)

**1. `kernel/.config`를 `olddefconfig`의 고정점으로 만든다.**

`kernel/build.sh:21`이 `.config`를 `build/.config`로 복사한 뒤
`olddefconfig`를 돌린다. 즉 우리가 손으로 적은 것과 커널이 실제로 빌드하는
것은 **다른 파일**이고, 지금까지 그 둘의 차이를 아무도 보지 않았다. ACPI처럼
`select`가 넷이나 딸린 옵션을 켜면 그 차이가 커진다.

그래서 이번에는 `olddefconfig`가 만든 `build/.config`를 `kernel/.config`로
되접는다. 그러고 나서 다시 빌드해 둘이 **같은지** 확인한다. 같아지면 저장소에
들어 있는 파일이 곧 커널이 빌드하는 설정이고, 다음 사람이 `.config`만 읽어도
진실을 알 수 있다.

**되접기는 ACPI를 켜기 전에 따로 한다**(Task 1.5). Task 1 Step 2의 실측으로
`.config`가 고정점이 아님이 확인됐고, 그 차이가 60줄이 넘는다. ACPI를 켠 뒤에
한꺼번에 되접으면 `kernel/.config`의 커밋 하나에 ACPI 변경과 정규화가 뒤섞여서,
나중에 "ACPI가 실제로 무엇을 들여왔나"를 git 히스토리로 답할 수 없게 된다.
정규화를 앞에 떼어 놓으면 다음 커밋의 diff가 순수하게 ACPI 몫이 된다.

**2. `.config`에는 설명 주석을 쓰지 않는다.**

`olddefconfig`가 파일을 통째로 다시 쓰면서 우리가 적은 주석을 지운다. 이유는
plan·design doc·기억 파일에 적고, `.config`에는 값만 남긴다. 1번의 되접기를
하는 순간 이 규칙은 선택이 아니라 강제가 된다.

**3. 명시적으로 끌 것과, 껐다고 적어도 안 꺼지는 것이 갈린다.**

`drivers/acpi/Kconfig`에서 `default y`인 항목 중 **프롬프트가 있는 것**만
`.config`에 `# CONFIG_X is not set`으로 눌러 둘 수 있다. 프롬프트가 없는
항목(`ACPI_LPIT:104`, `ACPI_HOTPLUG_IOAPIC:438`)은 우리가 무엇을 적든
`olddefconfig`가 `y`로 되돌린다. `X86_PM_TIMER`(`:609`)는 프롬프트가
`if EXPERT`인데 우리 설정에 `CONFIG_EXPERT`가 없어서 같은 처지다.

한편 조사 3번이 걱정한 것 중 상당수는 **우리 설정이 이미 막고 있다.**
`ACPI_FAN`·`ACPI_THERMAL`은 `THERMAL`이 꺼져 있어서(`.config:1156`),
`ACPI_SLEEP`은 `SUSPEND`가 꺼져 있어서(`:374`), `ACPI_PRMT`·`ACPI_BGRT`는
`EFI`가 없어서, `ACPI_PCC`는 `PCC`가 없어서 따라오지 못한다. 그래서 손으로
누를 것은 일곱 줄뿐이다(Task 2 Step 1).

**4. `ACPI_EC`는 기본값(`y`)으로 둔다.**

Embedded Controller 드라이버다. QEMU의 pc/q35 기계에 EC가 있을 것 같지는
않지만, **우리는 QEMU의 DSDT를 읽어 본 적이 없다.** 만약 DSDT에 EC opregion이
들어 있는데 드라이버가 없으면 AML 실행이 부팅 중에 실패하고, 그 사실은 커널을
한 번 더 빌드하고 나서야 알게 된다. 이해하는 것은 끄고 이해하지 못하는 것은
남긴다 — 최소 구성보다 이 원칙이 앞선다. 나중에 DSDT를 실제로 읽어 보고
결정할 후보로 남긴다.

**5. `-no-reboot`은 그대로 두고, 음성 검사로 구별한다.**

`power/check.sh`의 부팅 1은 `-no-reboot`을 달고 뜬다. 이 옵션은 게스트가
리셋을 걸어도 QEMU를 **끝내 버린다.** 그래서 "QEMU가 사라졌다"가 이제
전원 차단과 리셋 둘 다로 성립할 수 있다.

옵션을 빼면 그 모호함이 없어지지만, 게이트가 회차당 세 번 도는 동안 예기치
못한 리셋 고리에 빠질 여지를 열게 된다. 대신 로그에 `Restarting system`이
**없어야 한다**는 음성 검사 한 줄로 둘을 가른다. 같은 구별을 훨씬 싸게 얻고,
실패했을 때 어느 쪽이었는지도 함께 알려 준다.

**6. 커널이 찍는 줄 셋을 게이트의 어휘로 쓴다.**

vendor된 커널 소스에서 확인한 문자열이다. 게이트가 grep할 것은 이 셋이다.

| 문자열 | 위치 | 의미 |
|---|---|---|
| `reboot: Power down` | `kernel/reboot.c:711` | 전원 차단 경로를 실제로 밟았다 |
| `Power off not available: System halted instead` | `kernel/reboot.c:321` | 강등됐다 (**없어야 한다**) |
| `ACPI: button: Power Button` | `drivers/acpi/button.c:9,658` | 전원 버튼 장치가 등록됐다 |

## 사전 준비

모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서 실행한다.
`main` 브랜치, working tree가 깨끗한 상태에서 시작한다.

**`docker run`/`docker build`에 `--platform`을 붙이지 않는다**
(`docs/decisions/project_build_host_arch.md`).

**이번 milestone에는 `/tmp` + `cp` 경로가 필요 없다.** 편집이 전부 짧다. 다만
`kernel/.config`는 Task 2 Step 5에서 **명령으로** 통째 교체한다(손으로 옮겨
적지 않는다).

**인라인으로 제시하는 블록은 "넣을 것"만 적는다.** 지울 것이 있는 편집은
`지울 것`과 `넣을 것`을 따로 표시했다.

**이미지 재빌드는 필요 없다.** 새 외부 의존이 없다.

**Task 1은 커널을 처음부터 빌드하므로 몇 분이 걸린다.** 그 시간을 재는 것이
Task 1의 목적이므로 중간에 끊지 않는다.

---

## Task 1: ACPI 없는 커널의 빌드 시간을 잰다

되돌릴 수 없는 측정이라 맨 앞에 둔다. 같은 명령으로 `.config`가
`olddefconfig`의 고정점인지도 함께 본다.

**Files:**
- (없음. 측정만 한다.)

- [ ] **Step 1: 깨끗한 상태에서 커널을 빌드하며 시간을 잰다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'rm -rf kernel/build; time (cd kernel && ./build.sh) >/tmp/k.log 2>&1; tail -n 3 /tmp/k.log'
```

기대: 마지막에 `Kernel: arch/x86/boot/bzImage is ready` 같은 줄이 나오고, 그
뒤에 `real`/`user`/`sys` 세 줄이 나온다. **`real` 값을 적어 둘 것** — 이것이
기준선이다.

루트 게이트의 `clean()`이 매 회차 `kernel/build`를 지우므로(`check.sh:15`),
루트 게이트 한 번은 이 시간을 **15번** 치른다. 그래서 이 숫자가 중요하다.

- [ ] **Step 2: `.config`가 고정점인지 본다**

```bash
diff kernel/.config kernel/build/.config && echo "IDENTICAL"
```

기대: 둘 중 하나다. 어느 쪽이든 다음으로 넘어가지만, **결과를 알려 줄 것** —
Task 2의 diff를 읽는 방식이 여기서 갈린다.

- `IDENTICAL`이 찍히면 지금 `.config`는 이미 고정점이다. Task 2의 diff는
  순수하게 ACPI 때문에 생긴 차이가 된다.
- 차이가 나오면 지금도 "적어 둔 것"과 "빌드하는 것"이 다르다는 뜻이다. 그
  차이를 먼저 읽고, Task 2의 diff에서 그만큼을 빼서 해석한다.

이 Step은 커밋할 것을 만들지 않는다.

**실측 결과(2026-08-21):** `real 0m50.355s`(`user 4m44s`, `sys 1m28s`). 루트
게이트 한 번에서 커널 빌드가 차지하는 몫이 15 × 50.4초 ≒ **12분 36초**이고,
직전 실측 전체가 28분 16초였으므로 게이트 시간의 약 45%다. Step 2의 diff는
`IDENTICAL`이 아니었다 — 그래서 Task 1.5가 생겼다.

---

## Task 1.5: `.config`를 고정점으로 되접는다

Task 1 Step 2가 찾아낸 차이를 ACPI와 섞이기 전에 정리한다. 차이는 세 갈래였다.

**1. 환경에서 캐내는 값.** 커밋된 `.config`는 `CROSS_COMPILE` 없이 만들어진
흔적을 갖고 있었다 — `CC_VERSION_TEXT`가 크로스 gcc가 아닌 호스트 gcc이고,
`RUSTC_VERSION`이 rustc가 있던 기계의 값이며, 크로스 gcc가 지원하지 않는
`CC_HAS_MARCH_NATIVE`가 남아 있었다. kconfig가 매번 다시 캐내는 값이라 우리가
정할 수 있는 것이 아니다.

**2. 안 적혔을 뿐 의미가 같은 줄.** `# CONFIG_BLK_DEV_LOOP is not set` 같은
것 수십 줄이다. 안 적힌 것과 `is not set`은 kconfig에서 같은 뜻이다.

**3. 빌드되는데 기록에 없던 것.** `CONFIG_SERIO_SERPORT=y`,
`CONFIG_INPUT_VIVALDIFMAP=y`, `CONFIG_BUFFER_HEAD=y`, `CONFIG_SG_POOL=y`,
`CONFIG_ARCH_MIGHT_HAVE_PC_SERIO=y`. `olddefconfig`가 기본값으로 켠 것들이고,
**커널에는 들어가 있는데 저장소의 파일을 읽어서는 알 수 없었다.** 하필 둘이
입력 계층이다 — 입력 장치를 성질로 찾는 서브프로젝트를 하면서 입력 설정이
기록 밖에 있던 셈이다.

**Files:**
- Modify: `kernel/.config` (`olddefconfig` 출력으로 통째 교체)

- [ ] **Step 1: 되접는다**

```bash
cp kernel/build/.config kernel/.config
```

빌드 결과는 바뀌지 않는다. `kernel/build/.config`가 방금 커널을 만든 바로 그
설정이기 때문이다.

- [ ] **Step 2: 고정점이 됐는지 확인한다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'rm -rf kernel/build && ./kernel/build.sh >/dev/null 2>&1 && diff kernel/.config kernel/build/.config && echo IDENTICAL'
```

기대: `IDENTICAL` 한 줄. 아무것도 안 찍히면 빌드가 실패했거나 두 번째
회차에서도 값이 바뀐 것이다 — 후자라면 우리가 모르는 의존 관계가 있다는
뜻이므로 멈춘다.

**실측 결과(2026-08-21):** `IDENTICAL`.

- [ ] **Step 3: 커밋**

```bash
git add kernel/.config
git commit -m "Record the settings the kernel is actually built with"
```

---

## Task 2: ACPI를 켜고 무엇이 따라 들어오는지 확정한다

**Files:**
- Modify: `kernel/.config:371` (Task 1.5의 되접기로 줄 번호가 377에서 371로
  밀렸다. `CONFIG_ARCH_SUPPORTS_ACPI=y` 바로 **다음** 줄이다.)

- [ ] **Step 1: `.config`를 고친다**

`kernel/.config:371`의 다음 **한 줄을 지운다.**

```
# CONFIG_ACPI is not set
```

그 자리에 아래 **아홉 줄을 넣는다.**

```
CONFIG_ACPI=y
CONFIG_ACPI_BUTTON=y
# CONFIG_ACPI_SPCR_TABLE is not set
# CONFIG_ACPI_REV_OVERRIDE_POSSIBLE is not set
# CONFIG_ACPI_AC is not set
# CONFIG_ACPI_BATTERY is not set
# CONFIG_ACPI_PROCESSOR is not set
# CONFIG_ACPI_TABLE_UPGRADE is not set
# CONFIG_ACPI_DEBUG is not set
```

각 줄의 이유는 이렇다.

- **`CONFIG_ACPI=y`** — 이 milestone 자체다. `select PNP`·`NLS`·`CRC32`·
  `FIRMWARE_TABLE`이 따라온다(`drivers/acpi/Kconfig:12-15`). `NLS`와 `CRC32`는
  이미 `y`라 실제로 새로 들어오는 것은 `PNP`와 `FIRMWARE_TABLE` 둘이다.
- **`CONFIG_ACPI_BUTTON=y`** — 전원 버튼 드라이버. `default y`라 안 적어도
  켜지지만(조사 2번), 이 milestone이 사려는 물건이므로 명시한다. 기본값이
  바뀌어도 우리 의도가 남는다.
- **`ACPI_SPCR_TABLE`** — 펌웨어가 지정한 시리얼 콘솔로 커널 콘솔을
  돌린다. 우리는 `-append "console=ttyS0"`으로 콘솔을 직접 정하고 있고,
  게이트 전체가 그 시리얼 로그 위에 서 있다. 콘솔 경로에 변수를 더할 이유가
  없다.
- **`ACPI_REV_OVERRIDE_POSSIBLE`** — 특정 Dell 노트북용 DMI quirk다.
- **`ACPI_AC`·`ACPI_BATTERY`** — 어댑터와 배터리. QEMU에 없고, 실 하드웨어로
  갈 때 그때 켠다.
- **`ACPI_PROCESSOR`** — C-state/P-state 처리. `CONFIG_CPU_IDLE`과
  `CONFIG_CPU_FREQ`가 이미 꺼져 있어서(`.config:382`, `:388`) 받아 줄 곳이
  없다.
- **`ACPI_TABLE_UPGRADE`** — 부팅 때 **initrd 앞부분을 뒤져서** ACPI 테이블
  덮어쓰기를 찾는다. 우리는 initrd를 쓰므로 이 코드가 매 부팅 실제로 돈다.
  쓰지 않을 기능에 부팅 경로를 내주지 않는다.
- **`ACPI_DEBUG`** — AML 디버그 출력. help가 커널이 50K쯤 커진다고 적어 둔다.

**주석을 함께 적지 않는다**(이번에 정하는 것 2번). Step 5의 되접기에서
`olddefconfig`가 전부 지운다.

- [ ] **Step 2: 들어갔는지 확인한다**

```bash
rg -n "^CONFIG_ACPI|^# CONFIG_ACPI" kernel/.config
```

기대: 방금 넣은 아홉 줄이 366~384 구간(`Power management and ACPI options`
절) 안에 나온다. 다른 곳에 중복으로 들어가지 않았는지도 이 출력으로 함께 본다.

- [ ] **Step 3: 빌드하며 시간을 다시 잰다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'rm -rf kernel/build; time (cd kernel && ./build.sh) >/tmp/k.log 2>&1; tail -n 3 /tmp/k.log'
```

기대: 빌드 성공, 그리고 `real` 값이 Task 1보다 크다. **두 숫자의 차이가 이
milestone의 첫째 실측치다.** 루트 게이트에 미치는 영향은 그 차이의 15배다.

- [ ] **Step 4: `olddefconfig`가 무엇을 더했는지 읽는다**

```bash
diff kernel/.config kernel/build/.config
```

기대: `>` 쪽에 ACPI 관련 항목이 잔뜩 나온다. **Task 1.5로 `.config`가
고정점이 됐으므로 이 diff에는 ACPI 때문에 생긴 차이만 나와야 한다** — 그것이
정규화를 앞에 떼어 놓은 이유다. ACPI와 무관한 항목이 섞여 나오면 그 자체가
새로운 사실이므로 멈추고 해석한다. **출력을 그대로 알려 줄 것.** Claude가
다음 셋을 확인한다.

1. `CONFIG_ACPI_BUTTON=y`가 살아 있는가 (조사 2번의 예측)
2. `CONFIG_PM`이 함께 켜졌는가 (design 결정 10이 확인하라고 한 자리)
3. 우리가 껐다고 적은 일곱 줄이 되살아나지 않았는가

`ACPI_LPIT`·`ACPI_HOTPLUG_IOAPIC`·`X86_PM_TIMER`가 `y`로 나오는 것은
예상된 결과다(이번에 정하는 것 3번) — 프롬프트가 없어서 우리가 누를 수 없다.

- [ ] **Step 5: `.config`를 고정점으로 되접는다**

```bash
cp kernel/build/.config kernel/.config
git diff --stat kernel/.config
```

기대: `kernel/.config`가 한 파일 바뀐 것으로 나온다. 줄 수 변화는 Step 4의
diff 크기와 맞아야 한다. Task 1.5를 먼저 했으므로 이 커밋의 diff는 곧
**ACPI가 커널에 들여온 것의 목록**이 된다.

- [ ] **Step 6: 정말 고정점이 됐는지 확인한다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'rm -rf kernel/build; cd kernel && ./build.sh >/dev/null 2>&1; cd ..; diff kernel/.config kernel/build/.config && echo IDENTICAL'
```

기대: `IDENTICAL`. 이 줄이 나오면 저장소에 들어 있는 설정과 커널이 빌드하는
설정이 같아진 것이고, 앞으로는 `.config`만 읽어도 진실을 알 수 있다.

`IDENTICAL`이 안 나오면 멈추고 diff를 알려 줄 것 — `olddefconfig`가 두 번째
회차에서도 값을 바꾼다면 그것은 우리가 모르는 의존 관계가 있다는 뜻이다.

- [ ] **Step 7: 커밋**

```bash
git add kernel/.config
git commit -m "Turn ACPI on with everything we do not need turned off"
```

---

## Task 3: 부팅해서 장치가 밀리는 것을 본다

여기서 처음으로 게스트를 띄운다. 게이트는 아직 안 고친다 — 무엇을 요구할지
정하려면 실제로 무엇이 찍히는지 먼저 봐야 한다.

**Files:**
- (없음. 관측만 한다. 로그는 `out/` 아래에 남는데 `.gitignore` 대상이다.)

- [ ] **Step 1: TF 체인을 먼저 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash terminal/check.sh
```

기대: `PASS`. **이 한 번이 HD-M0의 둘째 증명이다** — 입력 장치가 하나 더
생겼는데도 화면에 글자가 그려졌다면, 키보드를 번호가 아니라 성질로 찾은
것이 옳았다는 뜻이다.

여기서 실패하면 멈춘다. 특히 `init discovered the keyboard by capability`가
안 나오거나 `terminal: opened ...`이 전원 버튼을 가리키면 탐색기의 문제이므로
게이트를 고치기 전에 그것부터 해석한다.

- [ ] **Step 2: 로그를 남기는 부팅을 한 번 더 한다**

Step 1의 로그는 컨테이너 안의 `mktemp` 파일이라 `--rm`과 함께 사라진다.
관측용으로 한 번 더 띄우되 이번에는 로그를 저장소 안에 남긴다. Step 1이 이미
전부 빌드해 두었으므로 이 명령은 부팅만 한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  mkdir -p out
  timeout 15 qemu-system-x86_64 \
    -kernel kernel/build/arch/x86/boot/bzImage \
    -initrd kernel/initrd.cpio \
    -append "console=ttyS0" \
    -vga none -device virtio-gpu-pci -display none \
    -serial file:/workspace/out/hd-m1-observe.log \
    -monitor none -no-reboot
  true'
```

기대: 15초 뒤 조용히 끝난다. `timeout`이 QEMU를 끊는 것이 정상이다 — 이
부팅은 아무 일도 시키지 않고 로그만 받아 낸다.

- [ ] **Step 3: 무엇이 등록됐는지 읽는다**

```bash
rg -n "ACPI:|input:|keyboard device|terminal: opened" out/hd-m1-observe.log
```

기대: 아래 네 갈래가 보인다. **출력을 그대로 알려 줄 것.**

1. `ACPI: Core revision ...` — ACPI 코어가 살아났다.
2. `ACPI: button: Power Button [PWRF]` — 전원 버튼 장치가 등록됐다. 조사
   5번대로 `[PWRB]`가 하나 더 있을 수도 있다.
3. `input: Power Button as /devices/...` 와 `input: AT Translated Set 2
   keyboard as /devices/...` — 두 장치의 등록 **순서**가 여기서 보인다.
4. `tars-init: keyboard device /dev/input/eventN (AT Translated Set 2
   keyboard)` 와 `terminal: opened /dev/input/eventN` — 같은 N이어야 한다.

**예상은 전원 버튼이 `event0`, 키보드가 `event1`이다.** 예상대로면 HD-M0이
가짜 sysfs 트리로 흉내 낸 배치(`devices_test.zig:186`의 "picked event1 past a
power button at event0")가 실물로 재현된 것이다.

**번호가 안 밀렸다면 멈추고 알려 줄 것.** 그것은 ACPI 버튼이 키보드보다 늦게
등록됐다는 뜻이고, HANDOFF가 미리 적어 둔 대로 새로운 사실이다. 게이트를
고치기 전에 그 사실부터 해석한다.

- [ ] **Step 4: 재시작 경로가 살아 있는지 미리 본다**

```bash
rg -n "reboot|pm_power_off|Power down" out/hd-m1-observe.log | head -20
```

기대: 이 부팅은 종료를 시키지 않았으므로 `reboot:` 줄은 없을 수 있다. 이
Step의 목적은 ACPI가 부팅 경로에 남긴 흔적(위험 2번)을 눈으로 훑는 것이다.
`ACPI: Using IOAPIC for interrupt routing` 같은 줄이 새로 보이는 것이 정상이다.

**이 Task는 커밋할 것을 만들지 않는다.** `out/`은 `.gitignore` 대상이다.

---

## Task 4: 게이트가 ACPI의 존재를 요구한다

HD-M0의 둘째 증명이 관측으로만 남지 않게 붙박는다.

**Files:**
- Modify: `terminal/check.sh` (검사 하나 추가)
- Modify: `input/check.sh:125` (진단 문구에서 장치 번호 제거)

- [ ] **Step 1: TF 게이트에 검사를 넣는다**

`terminal/check.sh:295`의

```bash
echo "init discovered the keyboard by capability"
```

**다음**에 아래 블록을 넣는다.

```bash

# HD-M1: ACPI가 입력 장치를 하나 더 등록했는가.
#
# 이 검사가 없으면 바로 위의 탐색 검사는 "성질로 찾았다"와 "장치가 하나뿐이라
# 우연히 맞았다"를 구별하지 못한다. 전원 버튼이 evdev 장치 목록에 끼어든
# 상태에서 위쪽 화면 검사들이 통과하는 것이 HD-M0의 탐색기가 옳다는 증명이고,
# 이 줄은 그 전제가 사라지지 않았음을 확인한다. 커널에서 ACPI를 다시 끄면
# 여기가 먼저 실패하므로, 증명이 조용히 사라지지 않는다.
#
# 장치 번호를 요구하지 않는 이유는 탐색기를 만든 이유와 같다 — 번호는
# 하드웨어 사정에 따라 달라지는 값이다.
if ! grep -q "ACPI: button: Power Button" "$LOG"; then
  echo "FAIL: the kernel did not register an ACPI power button"
  grep -i "acpi" "$LOG" | tail -n 20
  exit 1
fi
echo "the keyboard was found even though ACPI added another input device"
```

- [ ] **Step 2: IP 게이트의 진단 문구를 고친다**

`input/check.sh:125`의

```bash
    "terminal: opened /dev/input/event0" \
```

를 이것으로 바꾼다.

```bash
    "terminal: opened /dev/input/event" \
```

이 줄은 `report_failure` 안의 진단 목록이라 통과 조건이 아니다. 그래서
ACPI가 번호를 밀어도 IP 체인이 깨지지는 않았다. 다만 실패했을 때 있는
장치를 `MISSING`으로 찍어서 사람을 엉뚱한 곳으로 보낸다 — HD-M0이
`terminal/check.sh:109`에서 이미 같은 정리를 했다.

- [ ] **Step 3: 문법을 먼저 본다**

```bash
bash -n terminal/check.sh && bash -n input/check.sh && echo "SYNTAX OK"
```

기대: `SYNTAX OK`.

- [ ] **Step 4: 두 체인을 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'bash terminal/check.sh && bash input/check.sh'
```

기대: TF 쪽에
`the keyboard was found even though ACPI added another input device`가 찍히고
둘 다 `PASS`.

- [ ] **Step 5: 커밋**

```bash
git add terminal/check.sh input/check.sh
git commit -m "Prove discovery survives the extra input device ACPI adds"
```

---

## Task 5: 전원 게이트가 "스스로 꺼졌는가"를 요구한다

이 milestone의 완료선이다. 통과 조건 자체가 바뀌는 편집이라 앞의 것들이 전부
통과한 뒤에 한다.

**Files:**
- Modify: `power/check.sh` (머리말 주석, 진단 목록, 부팅 1의 대기 루프와 검사)

- [ ] **Step 1: 머리말 주석을 바꾼다**

`power/check.sh:17-20`의 아래 **네 줄을 지운다.**

```bash
# 마지막 칸을 게이트가 어떻게 보는가가 이 체인의 성격을 정한다. 우리 커널은
# ACPI가 꺼져 있어서(kernel/.config:377) reboot(POWER_OFF)이 HALT로 강등되고,
# 그때 커널이 찍는 줄이 아래 HALT_MARKER다. QEMU는 이 경우 스스로 끝나지
# 않으므로 -no-reboot을 그대로 두고 게이트가 죽인다.
```

그 자리에 아래 블록을 **넣는다.**

```bash
# 마지막 칸을 게이트가 어떻게 보는가가 이 체인의 성격을 정한다. HD-M1이
# 커널에 ACPI를 켜기 전에는 reboot(POWER_OFF)이 HALT로 강등돼서 QEMU가 스스로
# 끝나지 않았고, 이 게이트가 대신 죽여 줬다. 이제는 **QEMU가 스스로 사라지는
# 것**이 통과 조건이다 — 우리가 죽여 주던 그 손길이 없어진 것 자체가 전원이
# 진짜로 끊겼다는 증거다.
#
# -no-reboot은 그대로 둔다. 전원을 끄는 경로에는 영향이 없고, 루트 게이트가
# 이 체인을 회차당 세 번 돌리는 동안 예기치 못한 리셋 고리에 빠지는 것을
# 막아 준다. 다만 그 옵션 때문에 "QEMU가 사라졌다"가 리셋으로도 성립할 수
# 있으므로, 아래 음성 검사 4가 Restarting system이 없음을 요구해서 둘을 가른다.
```

- [ ] **Step 2: 진단 목록의 마지막 항목을 바꾼다**

같은 파일 `:88`의

```bash
    "Power off not available"; do
```

를 이것으로 바꾼다.

```bash
    "reboot: Power down"; do
```

`report_failure`의 이 목록은 "있어야 하는 것"을 훑는 자리다. 강등 메시지는
이제 있으면 안 되는 것이므로 목록에 두면 읽는 사람을 헷갈리게 한다. 대신
커널이 전원 차단 경로를 밟았을 때 찍는 줄(`kernel/reboot.c:711`)을 넣는다.

- [ ] **Step 3: 부팅 1의 대기 루프를 바꾼다**

같은 파일 `:164-174`의 아래 열한 줄을 **지운다.**

```bash
HALT_MARKER="Power off not available: System halted instead"
DONE=0
for _ in $(seq 1 30); do
  if grep -q "$HALT_MARKER" "$LOG"; then DONE=1; break; fi
  sleep 1
done

exec 3<&-
exec 3>&-

[ "$DONE" = "1" ] || report_failure "the guest never halted after kill -TERM 1"
```

그 자리에 아래 블록을 **넣는다.**

```bash
# 로그의 문자열이 아니라 **프로세스의 존재**를 본다. 이것이 HD-M1이 바꾼
# 통과 조건이다 — 게스트가 reboot(POWER_OFF)을 불렀고 커널이 그것을 ACPI로
# 실행했다면, QEMU는 우리가 아무것도 하지 않아도 사라진다.
GONE=0
for _ in $(seq 1 30); do
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then GONE=1; break; fi
  sleep 1
done

exec 3<&-
exec 3>&-

[ "$GONE" = "1" ] \
  || report_failure "the machine never switched itself off after kill -TERM 1"

# 여기서 거둬야 좀비가 남지 않고, EXIT trap의 cleanup이 이미 없는 PID를
# 건드리지 않는다. 아래 검사들은 QEMU가 끝난 뒤의 완성된 로그를 읽는다.
wait "$QEMU_PID" 2>/dev/null
QEMU_PID=""
```

`sleep 1`이 서른 번이라는 상한은 그대로 둔다. 종료 순서에 걸리는 시간은
여전히 유예 3초가 지배하므로 넉넉하다.

- [ ] **Step 4: 음성 검사 둘과 양성 검사 하나를 더한다**

같은 파일에서 음성 검사 2가 끝나는 자리, 즉

```bash
if [ "$STARTED" != "1" ]; then
  report_failure "the supervisor restarted the console shell during shutdown (started ${STARTED} times)"
fi
```

**다음**에 아래 블록을 넣는다.

```bash

# 음성 검사 3 — POWER_OFF가 HALT로 강등되지 않았는가. 커널에서 ACPI가
# 빠지면 이 줄이 다시 나온다. 그때는 위의 GONE도 함께 실패하지만, 실패의
# **이유**를 알려 주는 것은 이 한 줄뿐이다.
if grep -q "Power off not available: System halted instead" "$LOG"; then
  report_failure "the kernel demoted POWER_OFF to a halt; is CONFIG_ACPI still on?"
fi

# 음성 검사 4 — 꺼진 것이지 리셋된 것이 아니어야 한다. -no-reboot이 붙어
# 있어서 게스트가 리셋을 걸어도 QEMU는 사라지고, 그러면 위의 GONE이 엉뚱한
# 이유로 참이 된다. 그 경로를 여기서 막는다.
if grep -q "Restarting system" "$LOG"; then
  report_failure "the guest reset the machine instead of powering it off"
fi

# 양성 검사 — 커널이 전원 차단 경로를 실제로 밟았다는 줄(kernel/reboot.c:711).
# QEMU가 사라졌다는 사실만으로는 커널이 어디까지 갔는지 알 수 없다.
grep -q "reboot: Power down" "$LOG" \
  || report_failure "the kernel never reported 'Power down'"
```

- [ ] **Step 5: 이제 필요 없어진 죽이기를 지운다**

같은 파일에서 부팅 1의 마지막, `echo "boot 1/2 PASS: ..."` **바로 위**에 있는
아래 세 줄을 **지운다**(Step 3에서 이미 거뒀다).

```bash
kill "$QEMU_PID" 2>/dev/null
wait "$QEMU_PID" 2>/dev/null
QEMU_PID=""
```

**이 세 줄이 사라지는 것이 HD-M1의 완료 증거다.** design 결정 11이
"HALT에 멈춘 QEMU를 죽이는 부분을 뺀다"고 적은 것이 바로 이 자리다.

주의: 파일 뒤쪽 부팅 2의 끝(`:390-392`)에도 똑같이 생긴 세 줄이 있다.
**그쪽은 그대로 둔다** — 부팅 2는 재시작 경로라서 게스트가 계속 살아 있고,
게이트가 죽여 주는 것이 정상이다.

- [ ] **Step 6: 문법과 편집 결과를 본다**

```bash
bash -n power/check.sh && echo "SYNTAX OK"
git diff --stat power/check.sh
rg -n "QEMU_PID=\"\"|GONE=|Power down|Restarting system" power/check.sh
```

기대: `SYNTAX OK`. 그리고 `QEMU_PID=""`가 세 곳(초기화, 부팅 1의 새 자리,
부팅 2의 끝)에 있고 넷이 아니어야 한다 — 넷이면 Step 5의 삭제가 안 된 것이다.

- [ ] **Step 7: PM 체인을 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash power/check.sh
```

기대:

```
boot 1/2 PASS: the guest shut itself down from a shell command
boot 2/2 PASS: ctrl-alt-delete went through PID 1 and the new config took effect
PM-M1 PASS: the guest can shut itself down and bring itself back up
```

**부팅 2가 통과하는 것이 실측할 것 3번이다.** 마지막의
`--- init log (boot 2) ---` 아래에 `tars-init: calling reboot(RESTART)`가 있고,
게이트가 `Restarting system`을 요구하는 검사(`:354`)를 통과했다는 뜻이므로
ACPI를 켠 뒤에도 재시작 경로가 살아 있다는 것이 여기서 확인된다.

실패하면 `report_failure`가 찍는 마커 목록과 마지막 60줄을 그대로 알려 줄 것.

- [ ] **Step 8: 커밋**

```bash
git add power/check.sh
git commit -m "Ask the power gate to prove the machine really lost power"
```

---

## Task 6: 루트 게이트 3/3

**Files:**
- (없음. 검증만 한다.)

- [ ] **Step 1: 다섯 체인을 전부 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'time bash check.sh'
```

기대: 마지막 줄이

```
TARS check PASS: all chains 3/3 consecutive runs succeeded
```

그리고 `real` 값이 나온다. **직전 실측은 2026-08-20의 28분 16초다.** 늘어난
시간이 Task 2 Step 3에서 잰 커널 빌드 증가분의 15배 언저리인지 확인한다.
그보다 훨씬 크면 커널 빌드 말고 다른 곳(부팅 시간 등)이 늘었다는 뜻이므로
멈추고 해석한다.

부팅 횟수는 24회 그대로다. HD-M1은 새 체인을 만들지 않는다(design 결정 11).

- [ ] **Step 2: 시간이 견딜 만한지 판단한다**

design 위험 1번이 "견디기 어려우면 그때 `clean()`에서 커널을 빼는 것을
**별도로** 논의한다"고 적어 두었다. 이제 숫자가 있으므로 그 논의를 할 수
있다. 다만 **이 milestone 안에서는 `check.sh`를 고치지 않는다** — 매 회차
깨끗이 빌드하는 것은 우연이 아니라 정책이고, 정책을 바꾸는 일은 그 자체로
따로 다룰 일이다. 판단 결과는 Task 7에서 `HANDOFF.md`에 적는다.

이 Task는 커밋할 것을 만들지 않는다.

---

## Task 7: 문서

**Files:**
- Modify: `docs/decisions/project_power_management.md`
- Modify: `MEMORY.md` (필요하면)
- Modify: `HANDOFF.md`

- [ ] **Step 1: 전원 관리 기억을 고친다**

`docs/decisions/project_power_management.md`가 지금 이렇게 적고 있다.

> 커널에 ACPI가 없어 `reboot(POWER_OFF)`이 HALT로 강등되고 QEMU가 스스로
> 안 끝난다; **ACPI를 켜려면 `terminal`의 `/dev/input/event0` 상수부터
> 고칠 것**

두 문장 다 이제 사실이 아니다. 내용은 Claude가 쓰고, 담을 것은 이렇다.

- ACPI가 켜졌고 `reboot(POWER_OFF)`이 강등되지 않는다는 것, 그 증거가
  `reboot: Power down`과 QEMU의 자연 종료라는 것
- 경고("상수부터 고칠 것")는 HD-M0이 이미 이행했으므로 **경고가 아니라
  완료된 사건**으로 다시 적는다
- `power/check.sh` 부팅 1의 통과 조건이 로그 문자열에서 프로세스의 존재로
  바뀌었다는 것과, `-no-reboot` 때문에 `Restarting system` 음성 검사가
  필요하다는 것
- `MEMORY.md`의 한 줄 요약도 함께 고친다

새로 만들 기억이 필요한지는 이 시점에 판단한다. ACPI 설정의 세부(무엇이
프롬프트가 있어서 끌 수 있고 무엇이 안 되는지, `.config`를 고정점으로
만들었다는 것)는 `project_kernel_config`처럼 별도 파일로 뺄 만한 분량이다.
그렇게 하면 `MEMORY.md`에 줄을 하나 더한다.

- [ ] **Step 2: HANDOFF 갱신**

담을 것.

- HD-M1이 끝났고 다음은 HD-M2(전원 버튼)라는 것, plan은 아직 없다는 것
- 실측한 숫자 셋: 커널 빌드 시간(전/후), 루트 게이트 전체 시간, 등록된
  입력 장치의 배치(어느 번호가 전원 버튼이고 어느 번호가 키보드인지)
- Task 6 Step 2의 판단 — `clean()`에서 커널을 빼는 논의가 필요한지
- HD-M2가 쓸 자리: monitor 포트 45459, `device/check.sh`, 부팅 27회
- **HANDOFF의 "`origin/main`보다 5개 앞서 있다 — push가 안 되어 있다"는
  문장을 지운다.** 2026-08-21 확인 결과 `origin/main`과 같다.
- 로그 문구 목록에 `reboot: Power down`과 `ACPI: button: Power Button`을
  더한다(두 곳에 중복되는 문구가 둘 늘었다)

- [ ] **Step 3: 커밋**

```bash
git add docs HANDOFF.md MEMORY.md
git commit -m "Hand off with a kernel that can switch itself off"
```

- [ ] **Step 4: push**

HD-M0까지는 push가 되어 있다. 이번 milestone의 커밋 다섯을 올린다.

```bash
git push origin main
```

---

## 위험과 대응

**1. 커널 빌드 시간이 15배로 곱해진다.** design 위험 1번이다. Task 1과 Task 2
Step 3이 그 숫자를 만들고, Task 6 Step 1이 전체에 미친 영향을 확인한다. 대응은
숫자를 본 뒤에 **별도로** 논의하는 것이고, 이 milestone 안에서 `check.sh`를
고치지 않는다.

**2. QEMU의 DSDT가 우리가 끈 드라이버를 필요로 할 수 있다.** 가장 그럴듯한
후보가 Embedded Controller라서 `ACPI_EC`만 기본값으로 남겼다(이번에 정하는
것 4번). 증상은 부팅 로그의 `ACPI Error:` 또는 `ACPI BIOS Error:` 줄이다.
Task 3 Step 3에서 `rg "ACPI:"`로 로그를 훑을 때 이런 줄이 보이면 멈추고
해석한다 — 우리가 끈 일곱 줄 중 무엇을 되살릴지는 그 에러 메시지가 말해 준다.

**3. 입력 장치의 번호가 예상과 다르게 밀릴 수 있다.** 전원 버튼이 `event1`이
되거나, 조사 5번대로 `Power Button`이 둘 등록될 수 있다. **어느 쪽이든
게이트는 통과해야 한다** — 그것이 탐색기를 만든 이유다. Task 3 Step 3이
실제 배치를 확인하고, 예상과 다르면 멈추고 해석한다.

**4. ACPI가 재시작 경로를 바꾼다.** design 위험 2번이다. 재부팅이 i8042 리셋
대신 ACPI 리셋 레지스터로 갈 수 있다. Task 5 Step 7의 부팅 2가 이것을 본다 —
`Restarting system`과 재부팅 뒤의 zsh까지 그대로 나와야 한다. 실패하면
`reboot=` 커널 파라미터로 리셋 방식을 고정하는 길이 있지만, 그 전에 로그를
먼저 읽는다.

**5. `power/check.sh`의 편집이 부팅 2를 건드릴 수 있다.** 부팅 1과 부팅 2의
끝에 똑같이 생긴 `kill`/`wait`/`QEMU_PID=""` 세 줄이 있다. Task 5 Step 5가
지우는 것은 **부팅 1의 것 하나뿐**이고, Step 6의 `rg`가 그것을 개수로
확인한다.

**6. `.config` 되접기가 의도하지 않은 변경을 함께 들여올 수 있다.** Task 1.5가
ACPI **전에** 되접기를 끝내는 이유가 이것이다. 그 덕분에 Task 2 Step 4의
diff에는 ACPI와 무관한 항목이 하나도 없어야 하고, 있다면 그것이 곧 새로운
사실이다. 되접기 자체가 빌드 결과를 바꾸지 않는다는 근거는 되접는 대상이
방금 그 커널을 만든 파일이라는 점이고, Task 1.5 Step 2의 `IDENTICAL`이 그것을
확인한다.
