---
name: project_kernel_config
description: "커널 설정 다루는 법(HD-M1, CC-M0). build.sh가 olddefconfig를 돌리므로 .config는 그 출력으로 되접어 고정점으로 둔다 · 되접기가 주석을 지우니 설명은 기억 파일에 · 프롬프트가 없거나 'if EXPERT'인 항목은 눌러도 되살아난다 · 한 항목을 켜면 무관해 보이는 것들이 함께 움직인다 · 정규화와 의도한 변경은 다른 커밋 · 부팅은 1.5초라 게이트 시간의 근원이 아니다"
metadata:
  node_type: memory
  type: project
---

HD-M1(2026-08-21)이 `kernel/.config`에 ACPI를 켜며 세웠고 CC-M0이
`ACPI_EC`를 껐다. 빌드는 `kernel/build.sh`, 켠 결과가 무엇을 뜻하는지는
[[project_power_management]]에 있고 여기에는 설정 파일 자체를 다루는 법을
적는다. milestone별 경과와 게이트 시간은 2026-10-20에 지웠다(커밋 이력에 있다).

## `.config`는 `olddefconfig`의 고정점으로 유지한다

`kernel/build.sh:21`이 `.config`를 `build/.config`로 복사한 뒤
`olddefconfig`를 돌린다. 커밋된 파일과 실제로 빌드되는 설정은 같은 파일이
아니고, HD-M1 전까지 60줄 넘게 달랐다. 차이는 세 갈래였다 — 환경에서
캐내는 값(`CC_VERSION_TEXT`가 호스트 gcc, `RUSTC_VERSION`이 다른 기계의 값
— `CROSS_COMPILE` 없이 만든 흔적, [[project_build_host_arch]]), 안 적힌 것과
`# CONFIG_X is not set`처럼 뜻이 같은 줄, 빌드되는데 기록에 없던 것
(`SERIO_SERPORT` · `INPUT_VIVALDIFMAP` · `BUFFER_HEAD` · `SG_POOL`이 `y`).

규칙: 설정을 고쳤으면 빌드한 뒤 `cp kernel/build/.config kernel/.config`로
되접고, 다시 빌드해 `diff`가 비는지 확인한다. 그러면 저장소의 파일이 곧
진실이고 다음 커밋의 diff가 "이번 변경이 커널에 들여온 것"의 완전한 목록이
된다. 정규화(되접기)와 의도한 변경은 다른 커밋으로 나눈다 — HD-M1이 되접기를
ACPI보다 먼저 따로 커밋했다.

`.config`에 설명 주석을 쓰지 않는다. `olddefconfig`가 파일을 다시 쓰면서
전부 지운다. 왜 그 값인지는 기억 파일과 plan에 적는다.

## 누를 수 있는 항목과 없는 항목이 갈린다

`# CONFIG_X is not set`으로 누를 수 있는 것은 Kconfig에 프롬프트가 있는
항목뿐이다. 프롬프트가 없으면 `olddefconfig`가 기본값으로 되돌린다.

- 프롬프트 없음: `ACPI_LPIT`, `ACPI_HOTPLUG_IOAPIC`. `default y`라 무조건
  켜진다.
- `if EXPERT`: `X86_PM_TIMER`(`y`), `ACPI_REDUCED_HARDWARE_ONLY`(`n`).
  `CONFIG_EXPERT`가 없어 프롬프트가 숨고 기본값이 간다. 둘 다 원하는
  방향이다.

의존하는 심볼이 꺼지면 줄째 사라진다 — `ACPI_EC`를 끄자 `depends on
ACPI_EC`인 `ACPI_EC_DEBUGFS`가 없어져 눌러 두었던 `# CONFIG_ACPI_EC_DEBUGFS
is not set`도 뺐다.

## 우리 설정이 이미 막고 있는 것이 생각보다 많다

ACPI의 `default y` 상당수는 이미 막혀 있다. `THERMAL`이 꺼져 `ACPI_FAN` ·
`ACPI_THERMAL`이, `SUSPEND`가 꺼져 `ACPI_SLEEP`이, `EFI`가 없어 `ACPI_PRMT` ·
`ACPI_BGRT`가, `PCC`가 없어 `ACPI_PCC`가 못 들어온다. 손으로 누른 것은 일곱
줄 — `ACPI_SPCR_TABLE`(콘솔 경로에 변수를 더하지 않으려고),
`ACPI_REV_OVERRIDE_POSSIBLE`, `ACPI_AC`, `ACPI_BATTERY`, `ACPI_PROCESSOR`,
`ACPI_TABLE_UPGRADE`(매 부팅 initrd를 뒤진다), `ACPI_DEBUG`.

규율은 "이해하는 것은 끄고 이해하지 못하는 것은 남긴다"다. `ACPI_EC`는
HD-M1에서 기본값 `y`로 남겼다 — EC opregion이 있는데 드라이버가 없으면
AML이 부팅 중에 실패하고, 그것은 커널을 한 번 더 빌드해야 안다. CC-M0이
조건을 채우고 껐다: 게스트의 `/sys/bus/acpi/devices/*`에 EC의 HID
`PNP0C09`가 없고(fish가 `PNP0C09*`에 `No matches for wildcard`), 끄고 부팅한
로그에 `ACPI Error:`가 없다.

`PNP_DEBUG_MESSAGES`도 껐다. `pnp_dbg`(`base.h:179`)는 module parameter
`pnp_debug`(`drivers/pnp/core.c:220-223`)로 감싸여 있고 우리 cmdline은
`console=ttyS0` 하나라(`boot/limine.conf:7`) 켜진 적이 없다. 우리가 읽는
`i8042: PNP: ...` · `00:04: ttyS0 at I/O 0x3f8`은 보통 `pr_info`라 그대로
나온다. 둘을 끄고 bzImage가 2,946,048 → 2,933,760바이트가 됐지만 크기가
이유는 아니다 — "쓰지 않는 것은 안 켠다"다.

실머신으로 갈 때 `ACPI_EC`를 되켠다. 노트북 DSDT에는 대개 EC가 있고 배터리
· 뚜껑 · 밝기 키가 그 위에 있는데, 안 켰을 때의 증상이 "AML이 실패한다"라
원인까지 멀다. 다만 되켤 것은 그 한 줄이 아니다 — `EFI` · `USB_SUPPORT` ·
`BLK_DEV_NVME` · `PCI_MSI` · `DRM_I915`도 꺼져 있어 이 커널은 노트북에서 못
뜨고, 그것은 서브프로젝트 하나다([[project_target_hardware]]).

## 한 항목을 켜면 무관해 보이는 것들이 함께 움직인다

ACPI를 켰을 때 `select`로 딸려 온 `PNP` · `FIRMWARE_TABLE` 말고도 움직였다.

- `SERIAL_8250_PNP=y` — 시리얼 포트가 PNP/ACPI로 열거된다. 게이트 전체가
  `console=ttyS0` 위에 있어 가장 겁났던 변화지만, 콘솔은 그보다 앞선
  `printk: legacy console [ttyS0] enabled`에서 이미 켜지므로 위험하지 않다.
- `i8042`가 PNP로 바뀐다 — `i8042: PNP: PS/2 Controller
  [PNP0303:KBD,PNP0f13:MOU]`. 넘겨짚던 주소 대신 펌웨어가 알려 준 주소다.
- `PCI_MMCONFIG=y`인데 발동하지 않는다 — QEMU의 기본 `pc` 기계(PIIX4)에는
  MCFG가 없어 포트 0xCF8을 쓴다. `acpi PNP0A03:00: fail to add MMCONFIG
  information`은 에러가 아니라 정상 안내다.
- `EFI` · `HPET` 항목이 새로 나타난다(`depends on ACPI`). 둘 다 꺼진 채다.
- `DRM_XE` 항목이 사라진다 — `depends on X86_PLATFORM_DEVICES || !(X86 &&
  ACPI)`라 ACPI를 켜자 의존이 무너졌다. 반대 방향의 변화도 생긴다.
- `ACPI: Failed to create genetlink family for ACPI event` — `CONFIG_NET is
  not set`이라 generic netlink가 없다. 우리는 evdev로 읽으므로 상관없다.

## 빌드 시간은 15배로 곱해진다 — RM-M0(2026-09-09)에 1배가 됐다

HD-M1 때는 루트 게이트의 `clean()`이 매 회차 `kernel/build`를 지워 설정
변경의 빌드 비용(ACPI는 +2.589초)이 15배로 치러졌다. 지금은 GL-M0이
`clean()`을 게이트 시작 1회로 옮기고 GL-M1이 `.config`와 `build.sh`의 sha256
스탬프를 넣어 1배다(RM-M0 실측: 커널 빌드 1회, `skipping make` 29회).
교훈은 배수 자체보다 문서에 적은 배수가 게이트 시간과 같은 종류로 낡는다는
것이다 — 배수를 인용하기 전에 게이트 로그를 다시 센다.

## 부팅은 게이트 시간의 2%가 안 된다 (`PRINTK_TIME`으로 실측)

`CONFIG_PRINTK_TIME=y`로 커널 줄마다 시각을 붙여 갈랐다.

```
[    0.000000] Linux version 6.18.42
[    0.068969] printk: legacy console [ttyS0] enabled
[    0.507200] input: AT Translated Set 2 keyboard      ← 마지막 드라이버
        0.573초가 비어 있다 = initramfs 압축 해제
[    1.079865] Freeing initrd memory: 15144K
[    1.119354] Run /init as init process
```

커널이 `/init`에 넘기는 시각이 1.12초이고 그중 51%(0.573초)가 gzip 15.1MB를
67.7MB로 푸는 시간이다 — `init`을 `ReleaseSafe`로 줄이는 일이 부팅 시간
항목인 이유다. `started console shell` 다음 커널 줄이 `[ 1.455560] tsc:
Refined TSC clocksource calibration`이라 사용자 공간까지 1.46초 안에 끝난다.
그러므로 게이트 시간의 근원은 부팅이 아니라 커널 빌드와 게스트를 기다리는
`sleep` · 폴링 · 타이핑 지연이다.

`PRINTK_TIME`은 커널 줄에만 붙는다. `tars-init:` · `terminal:`은 fd 1로 직접
쓰므로 시각이 없다 — 우리 코드 내부 구간은 별도 수단이 필요하다. 게이트의
`grep`은 `^` 없는 부분 문자열 매치라 타임스탬프에 안 깨진다(커널 문구를 보는
`ACPI: button: Power Button` · `reboot: Power down` · `Restarting system` ·
`Power off not available`도 줄 중간을 본다).

커맨드라인 `printk.time=1`이나 `/sys/module/printk/parameters/time`으로도
된다(`printk_time`은 `#ifdef` 밖의 `0644` 파라미터, `printk.c:1345-1346`).
설정을 고른 이유는 커맨드라인 경로가 체인마다 `-append`를 고쳐야 하고 실
하드웨어로 갈 때 빠뜨릴 자리가 되기 때문이다. `PRINTK_TIME`은 잎 노드라
되접기가 필요 없었다.

How to apply: `kernel/.config`를 고칠 때는 (1) 프롬프트가 있는 항목인지
Kconfig에서 먼저 확인하고, (2) 빌드한 뒤 `diff kernel/.config
kernel/build/.config`로 `olddefconfig`가 무엇을 더했는지 읽고, (3)
`build/.config`를 되접은 뒤 다시 빌드해 `diff`가 비는지 확인하고, (4) 정규화와
의도한 변경을 다른 커밋으로 나누며, (5) 빌드 시간 증가분을 잰다. 설명은
`.config`가 아니라 기억 파일에 적는다.

관련: [[project_power_management]], [[project_build_host_arch]],
[[project_gate_chain_composition]], [[project_device_discovery]]
