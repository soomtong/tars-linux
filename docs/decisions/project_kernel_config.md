---
name: project_kernel_config
description: "커널 설정 다루는 법 — build.sh가 .config를 복사한 뒤 olddefconfig를 돌리므로 적어 둔 것과 빌드하는 것이 다를 수 있고(HD-M1 이전에 60줄 넘게 달랐다) 그래서 .config는 olddefconfig 출력으로 되접어 고정점으로 유지한다; 되접기가 주석을 지우므로 설명은 기억 파일과 plan에 적는다; 프롬프트가 있는 항목만 '# CONFIG_X is not set'으로 누를 수 있고 프롬프트가 없거나 'if EXPERT'인 것은 우리가 무엇을 적든 되살아난다; 우리 설정이 이미 THERMAL·SUSPEND·EFI·PCC·NET을 끄고 있어서 ACPI의 default y 상당수가 저절로 막힌다; ACPI를 켜면 SERIAL_8250_PNP와 i8042가 PNP 열거로 바뀌고 PCI_MMCONFIG는 QEMU pc 기계에 MCFG가 없어 발동하지 않는다; ACPI가 커널 빌드에 더한 시간은 2.589초이고 루트 게이트는 그것을 15배로 치른다; 2026-08-22에 CONFIG_PRINTK_TIME을 켜서 부팅을 갈랐고 커널이 /init에 넘기는 시각이 1.12초(그중 51%가 initrd 압축 해제)이며 부팅 전체가 1.5초 안에 끝나므로 게이트 36분의 근원은 부팅이 아니라 커널 빌드 18회다"
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

`ACPI_EC`는 HD-M1에서 **일부러 기본값 `y`로 남겼다.** QEMU의 DSDT를 읽어 본
적이 없어서, EC opregion이 있는데 드라이버가 없으면 AML이 부팅 중에 실패하고
그 사실은 커널을 한 번 더 빌드하고 나서야 알게 되기 때문이다. 이해하는 것은
끄고 이해하지 못하는 것은 남긴다.

**CC-M0(2026-08-31)이 그 조건을 채우고 껐다.** 게스트에게 직접 물었다 —
`-serial stdio`로 fish에 `echo /sys/bus/acpi/devices/*`를 넣어 받은 목록에
**Embedded Controller의 HID인 `PNP0C09`가 없다.** `PNP0C09*` 글로브에 fish가
`No matches for wildcard`로 답한 것이 그 증거다. EC 장치가 없으므로 그것을
가리키는 EmbeddedControl opregion을 실행할 AML도 없고, 끄고 부팅한 로그에도
`ACPI Error:`가 한 줄도 없다.

**`ACPI_EC`를 끄면 `ACPI_EC_DEBUGFS` 줄이 함께 사라진다.** 그 항목이
`depends on ACPI_EC`라 심볼째 없어지고 `olddefconfig`가 줄을 지운다. 그래서
`.config`에서 눌러 두었던 `# CONFIG_ACPI_EC_DEBUGFS is not set`도 함께 뺐다.

`PNP_DEBUG_MESSAGES`도 함께 껐다. `drivers/pnp/core.c:220-223`이 `pnp_debug`를
module parameter로 두고 `base.h:179`의 `pnp_dbg`가 `if (pnp_debug)`로 감싸는데,
우리 cmdline은 `console=ttyS0` 하나뿐이라(`boot/limine.conf:7`) 켜진 적이 없다.
**끄고 부팅해도 `i8042: PNP: PS/2 Controller [PNP0303:KBD,PNP0f13:MOU]`와
`00:04: ttyS0 at I/O 0x3f8`은 그대로 나온다** — 그 줄들은 `pnp_dbg`가 아니라
보통 `pr_info`다. 우리가 실제로 읽던 PNP 정보는 한 줄도 안 없어졌다.

**둘을 끄고 bzImage가 2,946,048 → 2,933,760바이트가 됐다**(12,288바이트,
0.42%). 크기가 이유였던 적은 없다 — 이유는 "쓰지 않는 것은 안 켠다"다.

**실머신으로 갈 때 `ACPI_EC`를 되켠다.** 실제 x86 노트북의 DSDT에는 대개 EC가
있고 배터리·뚜껑·밝기 키가 그 위에 있다. 되켜지 않았을 때의 증상이 "AML이
실패한다"라서 원인까지 가는 길이 멀다.

**다만 되켤 것이 그 한 줄이 아니다.** 사용자가 2026-08-31에 "TARS는 노트북
사용을 포함한다"로 정했고, 그 기준으로 이 `.config`를 훑어 보니 `EFI`도
`USB_SUPPORT`도 `BLK_DEV_NVME`도 `PCI_MSI`도 `DRM_I915`도 전부 꺼져 있어
**지금 커널은 노트북에서 아예 못 뜬다.** 그래서 그것은 이 문서에 줄을 더하는
일이 아니라 서브프로젝트 하나이고, 목록과 근거는
[[project_target_hardware]]에 있다.

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

## 부팅은 게이트 시간의 2%가 안 된다 (2026-08-22 `PRINTK_TIME`으로 실측)

위의 "가르지 못했다"를 2026-08-22에 갈랐다. `CONFIG_PRINTK_TIME=y`를 켜서
커널 줄마다 타임스탬프를 붙이고 나니 경계가 보인다.

```
[    0.000000] Linux version 6.18.42
[    0.068969] printk: legacy console [ttyS0] enabled
[    0.507200] input: AT Translated Set 2 keyboard      ← 마지막 드라이버
        0.573초가 비어 있다 = initramfs 압축 해제
[    1.079865] Freeing initrd memory: 15144K
[    1.119354] Run /init as init process
```

**커널이 `/init`에 손을 넘기는 시각이 1.12초이고, 그중 51%(0.573초)가
initrd를 푸는 시간이다.** gzip 15.1MB를 67.7MB로 펼치는 비용이다 — 이월
숙제인 "`init`을 `ReleaseSafe`로"가 왜 부팅 시간 항목인지가 여기서 처음
숫자로 보인다. 루트 게이트 27회 부팅에서 이 값은 1.00~1.03초로 일정하다.

사용자 공간도 경계가 잡힌다. `started console shell` 다음에 찍힌 커널 줄이
`[ 1.455560] tsc: Refined TSC clocksource calibration`이므로, **PID 1이
마운트하고 설정을 읽고 장치를 찾고 `terminal`과 셸을 띄우기까지가 부팅 시작
1.46초 안에 끝난다.**

**그러므로 부팅은 게이트 시간의 근원이 아니다.** 27회를 전부 더해도 40초
남짓이고, 36분 34초의 2%가 안 된다. HD-M1이 "부팅당 비용일 수도 있다"고
남겨 둔 미상은 부팅 비용이 아니었다. 시간은 **커널 빌드 18회**(53초 × 18 ≈
16분)와 각 체인이 게스트를 기다리며 도는 `sleep`·폴링·타이핑 지연에 있다.
`clean()`에서 커널을 빼는 논의는 이제 근거가 확실해졌다.

**`PRINTK_TIME`은 커널 줄에만 붙는다.** `tars-init:`과 `terminal:`은
`printk`를 거치지 않고 fd 1로 직접 쓰므로 시각이 없다. 우리 코드 내부를
구간으로 재려면 별도의 수단이 필요하다.

**게이트는 안 깨졌다.** 여섯 체인의 `grep`이 전부 `^` 없는 부분 문자열
매치이고, 검사 문구의 대부분이 타임스탬프가 안 붙는 우리 쪽 줄이다. 커널
문구를 보는 넷(`ACPI: button: Power Button` · `reboot: Power down` ·
`Restarting system` · `Power off not available`)도 줄 중간을 본다. 켠 뒤
루트 게이트 6체인 3/3을 통과했다(37분 43초 — 직전 36분 34초와의 차이 1분
9초는 부하와 측정 편차라 가르지 못한다).

**설정을 안 켜고도 켤 수 있다.** `printk_time`은 `#ifdef` 밖에 선언된
모듈 파라미터이고 권한이 `0644`다(`printk.c:1345-1346`). 즉 커맨드라인의
`printk.time=1`이나 게스트의 `/sys/module/printk/parameters/time`으로도
된다. 그런데도 설정을 고른 이유는, 커맨드라인 경로가 체인 여섯의
`-append`를 전부 고쳐야 하고 실 하드웨어로 나갈 때 빠뜨릴 자리가 되기
때문이다. `PRINTK_TIME`은 잎 노드라 `olddefconfig`가 한 줄도 더하지 않았고
되접기가 필요 없었다.

**How to apply:** `kernel/.config`를 고칠 때는 (1) 프롬프트가 있는 항목인지
Kconfig에서 먼저 확인하고, (2) 빌드한 뒤 `diff kernel/.config
kernel/build/.config`로 `olddefconfig`가 무엇을 더했는지 읽고, (3)
`build/.config`를 되접은 뒤 다시 빌드해 `diff`가 비는지 확인하고, (4) 정규화와
의도한 변경을 **다른 커밋으로** 나누며, (5) 빌드 시간 증가분을 재서 15배가
견딜 만한지 본다. 설명은 `.config`가 아니라 기억 파일에 적는다.

관련: [[project_power_management]], [[project_build_host_arch]],
[[project_gate_chain_composition]], [[project_device_discovery]]
