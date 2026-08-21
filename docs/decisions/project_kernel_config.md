---
name: project_kernel_config
description: "커널 설정 다루는 법 — build.sh가 .config를 복사한 뒤 olddefconfig를 돌리므로 적어 둔 것과 빌드하는 것이 다를 수 있고(HD-M1 이전에 60줄 넘게 달랐다) 그래서 .config는 olddefconfig 출력으로 되접어 고정점으로 유지한다; 되접기가 주석을 지우므로 설명은 기억 파일과 plan에 적는다; 프롬프트가 있는 항목만 '# CONFIG_X is not set'으로 누를 수 있고 프롬프트가 없거나 'if EXPERT'인 것은 우리가 무엇을 적든 되살아난다; 우리 설정이 이미 THERMAL·SUSPEND·EFI·PCC·NET을 끄고 있어서 ACPI의 default y 상당수가 저절로 막힌다; ACPI를 켜면 SERIAL_8250_PNP와 i8042가 PNP 열거로 바뀌고 PCI_MMCONFIG는 QEMU pc 기계에 MCFG가 없어 발동하지 않는다; ACPI가 커널 빌드에 더한 시간은 2.589초이고 루트 게이트는 그것을 15배로 치른다; CONFIG_PRINTK_TIME이 꺼져 있어 부팅 구간을 나눠 잴 수단이 없다"
metadata:
  node_type: memory
  type: project
---

2026-08-21 HD-M1에서 `kernel/.config`에 ACPI를 켜면서 확정한 것들이다. 켠
결과가 무엇을 뜻하는지는 [[project_power_management]]에 있고, 여기에는
**설정 파일 자체를 다루는 법**을 적는다.

## `.config`는 `olddefconfig`의 고정점으로 유지한다

`kernel/build.sh:21`이 `.config`를 `build/.config`로 복사한 뒤
`olddefconfig`를 돌린다. 즉 **저장소에 커밋된 파일과 커널이 실제로 빌드하는
설정은 같은 파일이 아니다.** HD-M1 전까지 아무도 그 둘을 대조하지 않았고,
실제로 60줄 넘게 달랐다. 차이는 세 갈래였다.

1. **환경에서 캐내는 값.** 커밋된 파일에 `CC_VERSION_TEXT`가 크로스 gcc가
   아닌 호스트 gcc로 적혀 있었고 `RUSTC_VERSION`이 rustc가 있던 기계의
   값이었다. `CROSS_COMPILE` 없이 만들어진 흔적이다
   ([[project_build_host_arch]]).
2. **안 적혔을 뿐 의미가 같은 줄.** 안 적힌 것과 `# CONFIG_X is not set`은
   kconfig에서 같은 뜻이다.
3. **빌드되는데 기록에 없던 것.** `SERIO_SERPORT`·`INPUT_VIVALDIFMAP`·
   `BUFFER_HEAD`·`SG_POOL`이 `y`였다. 하필 둘이 입력 계층이었다.

**규칙: 설정을 고쳤으면 빌드한 뒤 `cp kernel/build/.config kernel/.config`로
되접고, 다시 빌드해 `diff`가 비는지 확인한다.** 그러면 저장소의 파일만 읽어도
진실을 알 수 있고, 그 다음 커밋의 diff가 곧 "이번 변경이 커널에 들여온 것"의
완전한 목록이 된다. HD-M1은 이 되접기를 ACPI를 켜기 **전에** 따로 커밋해서,
ACPI 커밋에 정규화 잡음이 섞이지 않게 했다.

**따라오는 규칙: `.config`에 설명 주석을 쓰지 않는다.** `olddefconfig`가 파일을
다시 쓰면서 전부 지운다. 왜 그 값인지는 기억 파일과 plan에 적는다.

## 누를 수 있는 항목과 없는 항목이 갈린다

`# CONFIG_X is not set`으로 눌러 둘 수 있는 것은 **Kconfig에 프롬프트가 있는
항목뿐**이다. 프롬프트가 없으면 `olddefconfig`가 기본값으로 되돌린다.

- **프롬프트 없음:** `ACPI_LPIT`, `ACPI_HOTPLUG_IOAPIC`. `default y`라 무조건
  켜진다.
- **`if EXPERT`:** `X86_PM_TIMER`, `ACPI_REDUCED_HARDWARE_ONLY`. 우리 설정에
  `CONFIG_EXPERT`가 없어서 프롬프트가 숨겨지고, 결국 기본값이 그대로 간다.
  전자는 `y`가 되고 후자는 `n`이 되는데, 둘 다 우리가 원하는 방향이라
  문제가 아니었다.

## 우리 설정이 이미 막고 있는 것이 생각보다 많다

ACPI의 `default y` 목록이 길어 보였지만 상당수는 손댈 필요가 없었다.
`THERMAL`이 꺼져 있어서 `ACPI_FAN`·`ACPI_THERMAL`이, `SUSPEND`가 꺼져 있어서
`ACPI_SLEEP`이, `EFI`가 없어서 `ACPI_PRMT`·`ACPI_BGRT`가, `PCC`가 없어서
`ACPI_PCC`가 못 들어온다. **손으로 누른 것은 일곱 줄뿐이다** —
`ACPI_SPCR_TABLE`(콘솔 경로에 변수를 더하지 않으려고),
`ACPI_REV_OVERRIDE_POSSIBLE`, `ACPI_AC`, `ACPI_BATTERY`, `ACPI_PROCESSOR`,
`ACPI_TABLE_UPGRADE`(매 부팅 initrd를 뒤진다), `ACPI_DEBUG`.

`ACPI_EC`는 **일부러 기본값 `y`로 남겼다.** QEMU의 DSDT를 읽어 본 적이
없어서, EC opregion이 있는데 드라이버가 없으면 AML이 부팅 중에 실패하고 그
사실은 커널을 한 번 더 빌드하고 나서야 알게 되기 때문이다. 이해하는 것은 끄고
이해하지 못하는 것은 남긴다. 실제로는 `ACPI Error:`가 하나도 안 나왔으므로,
DSDT를 읽어 보고 끄는 것이 정리 후보로 남았다(`PNP_DEBUG_MESSAGES`도 같은
후보다).

## 한 항목을 켜면 무관해 보이는 것들이 함께 움직인다

ACPI 하나를 켰을 때 실제로 일어난 일이다. `select`로 딸려 온 `PNP`와
`FIRMWARE_TABLE`은 예상했지만 나머지는 아니었다.

- **`SERIAL_8250_PNP=y`** — 시리얼 포트가 PNP/ACPI로 열거된다. 게이트 전체가
  `console=ttyS0` 위에 서 있으므로 가장 겁났던 변화인데, 콘솔은 PNP 열거보다
  앞선 `printk: legacy console [ttyS0] enabled`에서 이미 켜지므로 위험하지
  않았다.
- **`i8042`가 PNP로 바뀐다** — `i8042: PNP: PS/2 Controller
  [PNP0303:KBD,PNP0f13:MOU]`. 넘겨짚어 찾던 것이 펌웨어가 알려 준 주소를 쓰게
  됐다.
- **`PCI_MMCONFIG=y`인데 발동하지 않는다** — QEMU의 기본 `pc` 기계는 PIIX4
  기반이라 MCFG 테이블 자체가 없다. 커널은 예전처럼 포트 0xCF8을 쓴다.
  `acpi PNP0A03:00: fail to add MMCONFIG information`은 에러처럼 보이지만
  **MCFG가 없는 기계에서 나오는 정상 안내**다.
- **`EFI`·`HPET` 항목이 새로 나타났다** — 둘 다 `depends on ACPI`라서 ACPI가
  꺼져 있을 때는 존재하지도 않았다. 둘 다 꺼진 채다.
- **`DRM_XE` 항목이 사라졌다** — `depends on X86_PLATFORM_DEVICES ||
  !(X86 && ACPI)`이다. ACPI가 꺼져 있을 때는 뒷절이 참이라 보였는데, 켜자
  의존이 무너져 항목째 없어졌다. **방향이 반대인 변화도 생긴다**는 예시다.
- **`ACPI: Failed to create genetlink family for ACPI event`** —
  `CONFIG_NET is not set`이라 generic netlink가 없다. ACPI 이벤트를 netlink로
  뿌리는 기능만 못 쓰고, 우리는 evdev로 읽으므로 상관없다.

## 빌드 시간은 15배로 곱해진다

루트 게이트의 `clean()`이 매 회차 `kernel/build`를 지우므로
(`check.sh:15`), 체인 다섯 × 3회 = **커널 빌드 15회**다. 설정 변경이 빌드에
더하는 시간은 그대로 15배가 된다.

ACPI의 실측치는 `50.355초 → 52.944초`, **+2.589초(+5.1%)**였다. 15배는 39초라
정책을 바꿀 이유가 되지 못했다. 루트 게이트 전체는 28분 16초에서 31분 30초로
늘었는데, **그 차이 3분 14초 중 39초만 설명된다.** 나머지는 가르지 못했다 —
부팅당 비용일 수도 있고 측정 편차일 수도 있으며, 기준선 자체가 다른 날 다른
부하에서 잰 값이다. 숫자의 내역을 모르는 채로 `clean()` 정책을 건드리지
않는다는 것이 그 미상을 남겨 둔 이유다.

**`CONFIG_PRINTK_TIME`이 꺼져 있어서**(`.config:1951`) 커널 로그에 타임스탬프가
없고, 그래서 부팅을 구간으로 나눠 잴 수단이 없다. 한 줄이면 앞으로 부팅 시간에
관한 질문에 답할 수 있게 되므로 켜는 것이 후보다.

**How to apply:** `kernel/.config`를 고칠 때는 (1) 프롬프트가 있는 항목인지
Kconfig에서 먼저 확인하고, (2) 빌드한 뒤 `diff kernel/.config
kernel/build/.config`로 `olddefconfig`가 무엇을 더했는지 읽고, (3)
`build/.config`를 되접은 뒤 다시 빌드해 `diff`가 비는지 확인하고, (4) 정규화와
의도한 변경을 **다른 커밋으로** 나누며, (5) 빌드 시간 증가분을 재서 15배가
견딜 만한지 본다. 설명은 `.config`가 아니라 기억 파일에 적는다.

관련: [[project_power_management]], [[project_build_host_arch]],
[[project_gate_chain_composition]], [[project_device_discovery]]
