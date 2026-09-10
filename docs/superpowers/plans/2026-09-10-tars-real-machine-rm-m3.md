# RM-M3 Implementation Plan — 게이트가 못 보는 것들

> **실행 방식은 `CLAUDE.md`를 따른다.** 설명 먼저 → 파일 편집 → 명령 실행은
> Claude Code가 → 결과를 상세히 설명. 승인 뒤의 `git commit`도 Claude Code가
> 만든다. 체크박스는 진행 추적용이다.
>
> **이 milestone도 편집을 Claude Code가 한다** — RM-M0~M2의 예외와 같다.
> **RM의 마지막 milestone이고, 끝나면 다시 기본 규칙(사용자가 편집)이다.**

**Goal:** 노트북에만 있는 ACPI 장치 다섯을 켜고, **QEMU에서 아무것도 안
깨졌음**을 확인한다. 그리고 이 ISO를 실기에 꽂는 법을 `README.md`에 적는다.

**Architecture:** `kernel/.config` 다섯 줄과 `README.md` 한 절. **코드는 한
줄도 안 고친다.**

**Tech Stack:** `kernel/.config` · `README.md` · 컨테이너 안의 게이트

---

## 이 milestone이 다른 넷과 다른 점

**판정이 "된다"가 아니라 "안 깨졌다"이다.** RM-M0~M2는 전부 게이트가 새로
보는 줄을 만들었다 — `efi: EFI v` · `USB Keyboard` · `config storage
/dev/nvme0n1`. 이번에 켜는 다섯은 **QEMU에 대상이 없다.**

| 항목 | 노트북에서 무엇 | QEMU에 있나 |
|---|---|---|
| `ACPI_EC` | 임베디드 컨트롤러. **DSDT가 거의 항상 참조한다** | **없다**(`PNP0C09`가 없다) |
| `ACPI_AC` | 어댑터가 꽂혔는가 | 없다 |
| `ACPI_BATTERY` | 배터리 잔량 | 없다 |
| `ACPI_PROCESSOR` | C-state·P-state·`_PSS`/`_CST` | **재 본다**(아래 Task 0) |
| `THERMAL` | 온도 존과 트립 포인트 | **재 본다** |

**`ACPI_EC`가 이 다섯 중 가장 무겁다.** 노트북의 DSDT는 배터리·뚜껑·밝기 키를
전부 EC 위에 올려 둔다. 커널에 EC 드라이버가 없으면 그 AML이 **그 자리에서
실패하고**, 증상은 "배터리가 안 보인다" 하나가 아니라 **그 아래 매달린 것이
통째로 안 붙는 것**이다. `project_target_hardware`가 이 서브프로젝트를 처음
지목할 때 이름으로 삼았던 항목이다.

**"켜 봤다"와 "된다"가 안 갈린다는 것을 명시적으로 적는다.** 결정 3이
`DRM_I915`를 안 켠 근거가 정확히 이것이었다("게이트가 볼 수 없다"). 그런데
여기서는 켠다 — **차이는 비용이다.** i915·amdgpu는 커널에서 가장 큰 드라이버
둘이고, 이 다섯은 합쳐도 작다. Task 1이 그 크기를 재서 이 문장을 사실로
만든다.

---

## Task 0 — QEMU가 이 다섯 중 무엇을 보여 주는지 **재 본다**

**추측하지 않는다.** design의 표는 "`ACPI_AC`·`ACPI_BATTERY`·`THERMAL`은 못
본다"고 적었는데, 그 표는 **착수 전에 쓴 것**이고 `ACPI_PROCESSOR`는 아예 안
적혀 있다. **조사가 design의 문장을 절반 뒤집은 적이 이 서브프로젝트에서 이미
한 번 있다**(`ovmf` 하나로 못 보는 것이 열에서 셋으로 줄었다).

켠 커널로 `machine/check.sh`를 한 번 돌리고 로그에서 새로 나온 줄을 센다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash ./machine/check.sh 2>&1 | rg -i "acpi|thermal|processor|cpuidle|battery"
```

**무엇이 나오면 무엇을 아는가.**

| 나오는 줄 | 뜻 | 그러면 |
|---|---|---|
| `ACPI: \_PR_.CP00` 또는 `cpuidle` 관련 | `ACPI_PROCESSOR`가 QEMU의 Processor 객체에 붙었다 | **판정을 하나 더한다** |
| `thermal_sys` / `Registered thermal governor` | `THERMAL` 코어가 떴다 | **판정을 하나 더한다** |
| 아무것도 없음 | design의 표가 맞았다 | 판정을 안 더하고 **그 사실을 적는다** |

**판정을 더할 수 있으면 더한다.** "켜 봤다"를 하나라도 "된다"로 옮기는 것이
이 milestone에서 얻을 수 있는 가장 값진 것이다.

- [ ] Task 0 완료 — QEMU가 보여 주는 것이 무엇인지 실측했다

---

## Task 1 — `.config`에 다섯을 켠다

**넣을 것:** `kernel/.config`. 다섯 줄을 켜고 되접는다.

**층이 얕다.** 착수 전에 확인했다 — 다섯 다 이미 `# CONFIG_X is not set` 줄로
있으므로 `sd`로 바로 켤 수 있다. `CONFIG_ACPI=y`가 이미 켜져 있어서 상위 메뉴가
열려 있기 때문이다(RM-M1은 `USB_SUPPORT`부터 열어야 해서 라운드가 셋이었다).

```
CONFIG_ACPI=y                      ← 이미 켜져 있다
  CONFIG_ACPI_EC                   ← 385~415줄 사이에 전부 있다
  CONFIG_ACPI_AC
  CONFIG_ACPI_BATTERY
  CONFIG_ACPI_PROCESSOR
CONFIG_THERMAL                     ← 1451줄
```

**그래도 되접는다.** `ACPI_PROCESSOR`가 `CPU_FREQ`나 `ACPI_CPPC_LIB`를 끌고 올
수 있고, `THERMAL`은 governor 여럿을 딸고 온다. **무엇이 딸려 왔는지 세는
것이 이 Task의 절반이다** — RM-M1 실측 10이 그 규율을 세웠다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  ./kernel/build.sh >/dev/null 2>&1
  diff kernel/.config kernel/build/.config && echo "fixpoint OK"'
```

**잴 것 둘.** 결정 1(`.config`는 하나)의 대가를 이번에도 잰다. **게이트가 이것을
1배로 치른다**(실측 8).

- 커널 빌드 시간 (RM-M2 시점 기준선과 **같은 세션에서** 잰다 — IS-M0 실측 2)
- bzImage 크기 (RM-M2 시점 3,580,928바이트)

- [ ] Task 1 완료 — 고정점에 닿았고 딸려 온 것을 셌다

---

## Task 2 — 회귀가 없음을 확인한다

**이 milestone의 판정은 이것이다.** 새로 보는 줄이 없을 수도 있으므로(Task 0이
정한다) **게이트가 초록인 것 자체가 결과물**이다.

**무엇이 깨질 수 있는가 — 미리 적어 둔다.**

1. **`ACPI_PROCESSOR`가 cpuidle을 켜면 게스트가 idle에서 다르게 논다.**
   체인들이 `sleep`으로 타이밍을 맞추는 자리가 많으므로(FP-M1이 검사 20에서
   `sleep` 여덟을 더해 게이트가 41초 늘었다) 부팅이 느려지면 flaky가 된다.
2. **`THERMAL`이 없는 존을 찾아 경고를 찍으면 로그가 는다.** 체인들의 `grep`은
   부분 문자열이라 안 흔들리지만, `last_frame` 같은 헬퍼가 로그를 훑는다.
3. **`ACPI_EC`가 EC 없는 기계에서 무엇을 하는가.** 아무것도 안 하는 것이
   맞지만, 그것을 확인하는 것이 이 Task다.

**RM-M0 실측 6의 교훈이 여기 걸려 있다** — 커널 설정 하나가 다른 체인의
암묵적 전제를 깬 적이 이미 있다. **그때는 `SYSFB_SIMPLEFB`가 `card0`을
만들어서였고, 이번에 깨진다면 타이밍일 것이다.**

**게이트는 20분이 넘으므로 백그라운드로 돌린다.**

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } 2> /tmp/gate.time
```

기준선은 **20분 15.37초**(RM-M2 뒤, 실측 19)다.

- [ ] Task 2 완료 — 열 체인 3/3 초록

---

## Task 3 — `README.md`에 실기 절을 더한다

**넣을 것:** `README.md`의 "로컬(macOS)에서 화면 띄워 보기" **뒤에** 새 절
**"실기 노트북에 꽂아 보기"**.

**적을 것 다섯.**

1. **`out/tars.iso`를 그대로 USB에 쓴다.** 하이브리드 ISO라 변환이 필요 없다
   (결정 5). `dd`의 대상은 파티션(`/dev/disk4s1`)이 아니라 **디스크
   전체**(`/dev/disk4`)다 — 틀리면 조용히 안 뜬다.
2. **macOS에서 `diskutil list`로 번호를 확인하고 `diskutil unmountDisk`를
   먼저 한다.** 안 하면 `dd`가 `Resource busy`로 죽는다.
3. **Secure Boot를 꺼야 한다.** 우리 커널에 서명이 없고 shim도 없다. 펌웨어
   설정(보통 F2/Del)에서 끈다. **안 끄면 증상이 "부팅 항목이 아예 안 보인다"**라
   원인에서 멀다.
4. **설정을 남기려면 디스크에 `tars-`로 시작하는 ext2 라벨이 있어야 한다**
   (RM-M2 결정 10). 없으면 부팅은 되고 설정만 매번 사라진다.
5. **무엇을 기대하고 무엇을 기대하지 않는가.** 화면은 뜬다(simpledrm이 패널의
   네이티브 해상도를 쓴다). 안 되는 것: 밝기 조절 · 외부 모니터 · 절전 ·
   네트워크 · 터치패드. **`DRM_I915`를 안 켠 것이 그중 셋의 이유다**(결정 3).

**`dd` 명령을 적을 때 조심한다.** 이 문서를 읽는 사람이 디스크 번호를 틀리면
자기 기계의 디스크를 지운다. **`diskutil list`를 먼저 시키고, 번호를
`<N>`으로 두어 복사해 붙이면 안 되게 한다.**

**낡은 줄 하나를 함께 고친다.** `README.md:108`이 "여덟 체인 × 3회차, 약
16분"이라고 적어 뒀는데 지금은 **열 체인 3/3에 20분**이다. GL-M3 시점의
문장이고 그 뒤로 체인이 둘 늘었다.

- [ ] Task 3 완료

---

## Task 4 — RM을 닫는다

- design의 `Status:`를 **완료**로 고치고 실측 절을 더한다
  (`CLAUDE.md`의 규칙: "서브프로젝트를 끝내면 그 design doc의 `Status:` 줄을
  함께 고친다")
- `docs/decisions/project_real_machine.md`와 `MEMORY.md` 갱신
- **`CLAUDE.md`의 "진행 중" 줄을 완료 목록으로 옮기고, "RM이 끝나면 다시 기본
  규칙이다"를 실행한다** — 다음 서브프로젝트부터 파일 편집은 사용자가 한다
- `HANDOFF.md`를 다시 쓴다. **진행 중인 서브프로젝트가 없어지므로 "사용자가
  고를 자리"가 된다**

- [ ] Task 4 완료

---

## 위험

**위험 10. `ACPI_PROCESSOR`가 게이트를 flaky하게 만든다.** cpuidle이 붙으면
게스트가 idle에 드는 방식이 바뀐다. **3회차 반복이 잡는 것이 정확히 이런
종류다**(`check.sh`의 주석: "3회 반복이 잡는 것은 부팅과 게스트 입력의
flakiness이지 빌드 재현성이 아니다"). 한 회차라도 깨지면 그 항목만 되돌린다.

**위험 11. 켜 놓고 아무도 안 보는 코드가 는다.** 이것은 감수하는 위험이고
결정 3이 반대 방향으로 판단했던 자리다. **가르는 것은 크기이므로 Task 1이
그것을 잰다** — 크면 다시 본다.

**위험 12. README의 `dd`가 사람의 디스크를 지운다.** 처방은 Task 3에 적었다.

---

## 커밋 계획

| | 무엇 |
|---|---|
| 1 | plan (이 파일) |
| 2 | Task 1 — `.config` 다섯 |
| 3 | Task 3 — README 실기 절 |
| 4 | Task 2·4 뒤 — design Status·실측 · 기억 · `CLAUDE.md` · HANDOFF |
