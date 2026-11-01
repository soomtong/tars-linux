---
name: project_target_hardware
description: TARS는 노트북 사용을 포함한다(사용자 결정, 2026-08-31). 그래서 커널 .config는 게이트용 최소가 아니라 실기용이고, 그 일을 Real Machine(RM, 2026-09-10)이 했다
metadata:
  type: project
---

# 대상 하드웨어에 노트북이 포함된다 (2026-08-31)

사용자가 2026-08-31에 정했다 — TARS는 노트북 사용을 포함한다. 그 전까지 저장소에 적혀 있던 것은 "실머신(Intel
하드웨어) USB 부팅"(boot foundation design의 비목표 절)뿐이었고, 노트북이 대상인지는 어디에도 없었다. HD design이
`ACPI_BUTTON`을 켠 근거("노트북 실 하드웨어로 가는 방향")는 그때 이미 그 방향을 전제하고 있었다.

이 결정이 바꾼 것은 커널 `.config` 작업의 크기다. CC-M0이 `ACPI_EC`를 끄면서 남긴 "실머신으로 갈 때 되켠다"를
계기로 훑어 보니 2026-08-31의 `.config`는 `EFI` · `USB_SUPPORT` · `BLK_DEV_NVME` · AHCI · `PCI_MSI` · `ACPI_EC` ·
`ACPI_AC` · `ACPI_BATTERY` · `THERMAL` · `ACPI_PROCESSOR` · `SUSPEND`가 전부 꺼져 있어 노트북에서 못 떴다. 그래서
일의 이름은 "`ACPI_EC`를 되켠다"가 아니라 "실머신용 `.config`를 만든다"가 됐고, Real Machine(RM-M0~M3,
2026-09-10, [[project_real_machine]])이 그것을 했다 — 켜진 것 · 게이트가 못 보는 셋(`ACPI_EC` · `ACPI_AC` · 실 GPU) ·
simpledrm으로 GPU 드라이버가 필요 없는 이유는 그 기억에 있다. 소리(AU)와 배터리(BS) · 무선(WL) · 포인터(PD)가
그 뒤에 얹힌 층이다.

## 남아 있는 아이디어

QEMU의 `pc` 기계에는 EC(`PNP0C09`)가 없어 `ACPI_EC` 경로는 어느 체인도 못 밟는다. `kernel/.config`에
`CONFIG_ACPI_CUSTOM_DSDT_FILE=""`이 있으므로 실제 노트북의 DSDT를 덤프해 게스트에 물리는 길이 있을 수 있다 —
확인해 본 적은 없다. 실기 없이 EC 경로를 밟아 볼 유일한 후보다.

관련: [[project_real_machine]] · [[project_kernel_config]] · [[project_audio_devices]] · [[project_device_discovery]]
