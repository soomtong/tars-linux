---
name: project_wired_nic
description: "노트북형 유선 NIC를 켠 서브프로젝트(WN-M0~M3, 2026-09-26 종료). 드라이버 여섯 + USB 동글 셋을 =y로 켜고, 모든 QEMU 호출이 -nic none이나 -netdev를 명시하며(check.sh의 require_explicit_nic), init은 dhcpcd -j /dev/console -o ntp_servers를 인자 없이 띄우기만 한다 — 인터페이스를 고르고 올리는 것은 dhcpcd(manager mode)다. 열네번째 체인 nic/check.sh"
metadata:
  node_type: memory
  type: project
---

# 노트북형 유선 NIC (WN)

design은 `docs/superpowers/specs/2026-09-26-tars-wired-nic-design.md`(실측 1~18).
사용자가 2026-09-26에 후보 넷 중 "실머신 NIC"를 골랐다. 실기가 없어서 "노트북형
드라이버를 전부 켜고 QEMU로 되는 둘(`e1000e` · `usb-net`)만 부팅으로 판정한다"는
반쪽이다.

무엇이 섰나.

- `kernel/.config` — `E1000E` · `IGC` · `R8169` · `USB_RTL8152` · `USB_USBNET` ·
  `USB_NET_CDCETHER`와, `USB_USBNET`의 `default y` 아홉 중 사용자가 남긴 셋
  (`AX8817X` · `AX88179_178A` · `CDC_NCM`). `NET1080` · `ZAURUS` · `CDC_SUBSET`은
  명시적으로 끈다. Realtek firmware는 비목표.
- `check.sh`의 `require_explicit_nic` — `CHAINS`의 QEMU 호출마다 `-nic none`이나
  `-netdev`가 있어야 한다. 여러 줄 호출을 `awk`로 하나로 모은다. NW 결정 3("다른
  체인은 NIC가 없다")을 "드라이버를 안 켰다"는 우연에서 명시로 옮겼다.
- `init/src/net.zig` — 182줄 → 104줄. 인터페이스 이름 · sysfs 확인 · ioctl이 빠지고
  `dhcpcd -j /dev/console -o ntp_servers`를 fork · execve만 한다. `net=dhcp`인데
  NIC가 없어도 띄운다.
- `nic/check.sh` — 부팅 A(q35 + e1000e → `eth0: leased`)와 부팅 B(NIC 없이 떠서
  monitor `device_add usb-net` → 같은 pid의 dhcpcd가 `usb0: leased`).

Why: 실기에 올리는 날 virtio-net만 아는 커널이면 네트워크를 쓰는 기능(NW · IN ·
TS · TD) 전부가 조용히 꺼진다. 인터페이스를 고르는 것은 TD가 시계에 대해 한 것과
같은 방향이다 — 어려운 일은 그 일을 하는 도구가 하고 init은 배관만 한다.

How to apply:

- dhcpcd 10의 사실 넷(WN 실측). 코드와 게이트가 이것에 기댄다.
  1. 인터페이스 이름을 안 주면(manager mode) `-b` 없이도 lease 전에 배경으로 간다.
     그 뒤 로그는 syslog로 가는데 게스트에 syslog가 없다 — `-j /dev/console`을 빼면
     주소는 붙고 `leased` 줄만 사라진다.
  2. `-j`면 줄머리가 `Sep 26 11:07:33 [pid]: `이다. 배경으로 가기 전 세 줄만 두 번.
  3. 인터페이스가 하나도 없으면 `no valid interfaces found`를 찍고 30초 timeout을
     넘겨 살아서 기다린다. 나중에 생긴 장치를 udev 없이 잡는다.
  4. 링크를 스스로 올린다(`IFF_UP` ioctl이 필요 없다).
- 장치가 붙었는지는 드라이버 이름이 아니라 인터페이스 이름으로 센다. 드라이버가
  커널에 있으면 장치가 없어도 `e1000e: Intel(R) PRO/1000 …` 배너가 찍힌다.
- `usbnet: failed control transaction …` 세 줄은 게스트가 아니라 QEMU가 자기
  stderr에 찍는 것이다. `-serial stdio`로 재면 게스트 로그에 섞여 보인다.
- `-netdev`만 주고 NIC 장치를 안 주면 QEMU는 기본 NIC를 안 붙인다(pc는 `e1000`,
  q35는 `e1000e`를 붙이는 것이 기본이다).
- 새 체인이 QEMU를 띄우면 `-nic none`을 달거나 `-netdev`를 준다. 안 그러면 진입
  검사가 게이트를 세운다.

관련: [[project_guest_network]] · [[project_time_discipline]] ·
[[feedback_boot_never_blocks]] · [[project_real_machine]]
