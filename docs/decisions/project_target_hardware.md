# 대상 하드웨어에 노트북이 포함된다 (2026-08-31)

사용자가 2026-08-31에 정했다 — **TARS는 노트북 사용을 포함한다.** 그 전까지
저장소에 적혀 있던 것은 "실머신(Intel 하드웨어) USB 부팅"(boot foundation
design의 비목표 절)뿐이었고, 노트북이 대상인지는 어디에도 없었다.

**이 사실이 커널 `.config` 작업의 크기를 바꾼다.** CC-M0이 `ACPI_EC`를 끄면서
"실머신으로 갈 때 되켠다"를 이월 숙제로 남겼는데, 그것을 계기로 `.config`를
훑어 보니 **되켤 것이 한 줄이 아니었다.**

## 지금 커널은 노트북에서 못 뜬다

2026-08-31 기준 `kernel/.config`다.

| 항목 | 지금 | 노트북에서 뜻하는 것 |
|---|---|---|
| `EFI` | off | UEFI 펌웨어와 EFI 프레임버퍼 경로가 통째로 없다 |
| `USB_SUPPORT` | off | 내장 키보드가 USB면 입력이 없다. **USB 부팅도 못 한다** |
| `BLK_DEV_NVME` · AHCI | off | 내장 저장장치를 못 본다 |
| `PCI_MSI` | off | 요즘 장치는 대부분 MSI/MSI-X로 인터럽트를 받는다 |
| `DRM_I915` · `DRM_AMDGPU` · `DRM_SIMPLEDRM` | 전부 off | 픽셀을 낼 길이 `DRM_VIRTIO_GPU` 하나뿐이다 |
| `ACPI_EC` | **off (CC-M0)** | AML의 EmbeddedControl opregion을 다룰 핸들러가 없다 |
| `ACPI_BATTERY` · `ACPI_AC` | off | 배터리와 어댑터 상태가 없다 |
| `THERMAL` · `ACPI_PROCESSOR` · `SUSPEND` | 전부 off | 온도·주파수·절전이 없다 |
| `ACPI_BUTTON` | **on** | lid(덮개)와 sleep 버튼 경로가 이미 열려 있다 |

`ACPI_BUTTON`이 켜져 있는 것은 우연이 아니다 — HD design이 **"노트북 실
하드웨어로 가는 방향과 어긋난다"**를 근거로 그것을 골랐다. 방향은 그때 이미
정해져 있었고, 이번에 명시적으로 적혔을 뿐이다.

## `ACPI_EC`가 없으면 무엇이 어떻게 깨지는가

노트북의 DSDT에는 거의 예외 없이 EC(`PNP0C09`)가 있고, AML이
`OperationRegion(..., EmbeddedControl, ...)`으로 그 레지스터를 읽고 쓴다.
드라이버가 없으면 그 region을 다룰 핸들러가 없어서 **AML 실행이 그 자리에서
실패한다** — `ACPI Error: No handler for Region ... [EmbeddedControl]` 계열이
뜨고 배터리·어댑터·뚜껑·온도·밝기 키가 통째로 안 붙는다.

**부팅이 멈추지는 않는 경우가 많다는 것이 함정이다.** 증상이 "부팅은 되는데
배터리가 안 보인다"로 나타나서 원인이 커널 config라는 데까지 가는 길이 멀다.
EC는 ECDT 테이블로 아주 이른 시점에 잡히는 경로도 있는데 그것도 함께 없어진다.

## 게이트는 이것을 검증할 수 없다

**QEMU의 `pc` 기계에는 EC가 없다.** CC-M0이 게스트에게 직접 물어 확인했다 —
`/sys/bus/acpi/devices/`에 `PNP0C09`가 없다. 그래서 "노트북에서 EC가 필요하다"는
여덟 체인 중 어느 것으로도 확인할 수 없고, **QEMU에서 초록이라는 것이 이
방향에 대해 아무것도 말하지 않는다.**

`kernel/.config`에 `CONFIG_ACPI_CUSTOM_DSDT_FILE=""`이 있으므로 **실제 노트북의
DSDT를 덤프해서 게스트에 물리는 길이 있을 수 있다.** 확인해 본 적은 없으니
아이디어로만 적어 둔다 — 실기 없이 EC 경로를 밟아 볼 유일한 후보다.

## 그래서 이것은 서브프로젝트 하나다

"`ACPI_EC`를 되켠다"가 아니라 **"실머신용 `.config`를 만든다"**가 일의 이름이다.
`project_kernel_config`가 세운 규율("이해하는 것은 끄고 이해하지 못하는 것은
남긴다")을 그대로 쓰되, 이번에는 **켜는 방향으로** 같은 일을 한다 — 항목마다
왜 필요한지를 확인하고 켠다.

**두 `.config`를 나눌지 하나로 갈지가 그 서브프로젝트의 첫 결정이다.** 지금
게이트는 QEMU 위에 서 있고 `project_gate_latency`가 "게이트가 부팅하는
바이너리가 곧 제품이다"를 근거로 최적화 기본값을 정했다. **커널 config가 둘로
갈리면 그 문장이 커널에 대해서는 더 안 맞게 된다.**

관련: [[project_kernel_config]] · [[project_carryover_cleanup]] ·
[[project_device_discovery]] · [[project_gate_latency]]
