# TARS Wired NIC — Design

접두사: WN

Status: 열렸다(2026-09-26). M0부터.

관련 문서: `2026-09-13-tars-guest-network-design.md`(NW. virtio-net과 dhcpcd를
들인 문서이고, 아래에서 "NW 결정 N" · "NW 실측 N"은 전부 그 문서의 것이다) ·
`2026-09-09-tars-real-machine-design.md`(RM. `.config`가 하나라고 정한 문서) ·
`2026-09-26-tars-time-discipline-design.md`(TD. `init`은 배관만 한다는 방향) ·
`docs/decisions/feedback_boot_never_blocks.md`.

## 한 줄 요약

노트북에 흔한 유선 NIC 다섯 계열의 드라이버를 커널에 켠다. 그중 QEMU가 흉내
낼 수 있는 둘(`e1000e` · `usb-net`)은 게이트가 매번 DHCP lease까지 본다.
인터페이스를 고르고 링크를 올리는 일은 `init`에서 빼서 dhcpcd에게 넘긴다.

## 왜 지금인가

NW 비목표 1이 "실머신 NIC"를 층 5로 남겼고 "사용자의 실제 노트북이 무엇을
달고 있는지 보고 정할 일"이라고 적었다. 실기는 아직 없다. 2026-09-26에
사용자가 후보 넷(패키지 매니저 · 실머신 NIC · IN이 미룬 것 · IPv6) 중에서
실머신 NIC를 골랐고, 실기 없이 할 수 있는 반쪽 — "노트북형 드라이버를 전부
켜고 QEMU로 되는 것만 부팅으로 판정한다" — 을 골랐다.

DI · DC가 USB 없이 내장 디스크로 뜨는 기계를 세웠고 TD가 그 기계의 시계를
네트워크에 묶었다. 지금 커널은 virtio-net 말고는 NIC를 하나도 모르므로, 실기에
올리는 날 네트워크를 쓰는 기능(NW · IN · TS · TD) 전부가 조용히 꺼진다.

## 착수 전에 읽거나 잰 것 — 부팅은 한 번도 안 했다

### 확인 1 — 지금 `.config`에서 켜진 NIC 드라이버는 `VIRTIO_NET` 하나다

`kernel/.config`에서 `E1000` · `E1000E` · `IGC` · `R8169` · `USB_RTL8152` ·
`USB_USBNET`이 전부 `is not set`이다. `NET_VENDOR_INTEL` · `NET_VENDOR_REALTEK`
메뉴는 켜져 있고, `FW_LOADER=y` · `USB_XHCI_HCD=y` · `USB_EHCI_HCD=y`도 이미
있다(RM이 켰다). 새로 켤 것은 드라이버 자신뿐이다.

### 확인 2 — 기존 체인의 격리는 "드라이버를 안 켠 것"에 얹혀 있다

NW 결정 3. QEMU는 옵션이 없으면 NIC를 하나 붙인다 — `pc` 머신은 `e1000`,
`q35` 머신(`machine` · `install` 체인)은 `e1000e`다. 지금은 드라이버가 없어서
게스트가 그것을 보고도 넘어간다. `net/check.sh` 검사 11이 로그에 `e1000` ·
`r8169` 등이 나오면 빨강을 내는 것으로 그 성질을 지킨다. 이번에 `e1000e`를
켜면 `q35` 체인 둘이 곧바로 NIC를 하나씩 갖는다.

### 확인 3 — QEMU를 띄우는 파일은 열다섯이고 공통 헬퍼가 없다

`rg -c qemu-system-x86_64 --glob '*.sh'` — 체인 스크립트 열셋에 열여덟 번,
그리고 `kernel/check-virtio-gpu.sh` · `devcontainer/sanity/check.sh`.

### 확인 4 — `init`이 인터페이스 이름을 상수로 박아 두었다

`init/src/net.zig`의 `IFACE = "eth0"` · `SYS_IFACE`. `init`이 `/sys/class/net/eth0`을
열어 보고, `SIOCGIFFLAGS` · `SIOCSIFFLAGS`로 `IFF_UP`을 세우고, `dhcpcd -o
ntp_servers eth0`으로 띄운다. 주석이 "실머신 NIC가 들어오는 날 이 상수가 디렉터리
순회로 바뀐다"고 적어 두었다. `net/check.sh`는 `net link eth0 is up` ·
`started dhcpcd on eth0` 두 줄과 `/sys/class/net/eth0`을 본다.

### 확인 5 — QEMU 10.0.13이 흉내 내는 것과 노트북에 달린 것이 반만 겹친다

`qemu-system-x86_64 -device help`(devcontainer)에서 네트워크 장치를 읽었다.

| 노트북에서 흔한 것 | 드라이버 | QEMU |
|---|---|---|
| Intel 내장 I219 계열 | `e1000e` | `e1000e`(82574L) — 같은 드라이버 |
| Intel 2.5G I225/I226 | `igc` | 없다 (`igb`는 82576이고 드라이버가 다르다) |
| Realtek RTL8111/8168 | `r8169` | 없다 |
| Realtek USB 동글 RTL8152/8153 | `r8152` | 없다 |
| USB 동글 · 폰 테더링(CDC) | `cdc_ether` · `rndis_host` | `usb-net` |

## 결정

### 결정 1 — 켤 드라이버는 다섯 계열이고 전부 `=y`다

`E1000E` · `IGC` · `R8169` · `USB_RTL8152` · `USB_USBNET` + `USB_NET_CDCETHER`.
QEMU의 `usb-net`이 RNDIS로 붙는다면 `USB_NET_RNDIS_HOST`도 켠다 — 어느 쪽인지는
M0이 잰다. 모듈은 안 쓴다(지금 커널에 모듈 로더 경로가 없고, 이것 때문에 세우지
않는다). `.config`는 RM 결정 1대로 하나다.

사용자가 골랐다(후보: 노트북형 전부 · QEMU로 재는 것만 · `e1000e` 하나).

### 결정 2 — 부팅으로 판정하는 것은 `e1000e`와 `usb-net` 둘이다

나머지 셋(`igc` · `r8169` · `r8152`)은 `.config`에 `=y`인 것까지만 본다. 켜 놓고도
QEMU에서는 "빌드됐다" 이상을 말할 수 없다는 것을 design이 먼저 인정한다. 실기
판정은 비목표다.

### 결정 3 — 격리를 명시한다. NW 결정 3을 대체한다

모든 QEMU 호출이 `-nic none`을 달거나 `-netdev`를 명시한다. `check.sh`의 진입
검사에 `require_explicit_nic`를 더해서, `CHAINS`의 스크립트 안에 둘 다 없는
`qemu-system-x86_64` 호출이 있으면 게이트가 돌기 전에 죽는다(GA가 세운
`require_no_early_exit_pipe`와 같은 자리 · 같은 모양).

`net/check.sh` 검사 11(드라이버 이름이 로그에 나오면 빨강)은 전제가 사라지므로
지운다. 그것이 지키던 성질 — "기존 체인이 조용히 NIC를 갖지 않는다" — 은 lint가
부팅 없이 지킨다.

사용자가 골랐다(후보: `-nic none` + lint · 격리를 포기하고 한 번 재기).

### 결정 4 — 인터페이스는 dhcpcd가 고른다 (manager mode)

`init`은 `dhcpcd -o ntp_servers`를 인터페이스 인자 없이 fork · `execve`한다.
dhcpcd가 `lo`가 아닌 인터페이스를 스스로 찾아 올리고, netlink로 나중에 생기는
장치(부팅 뒤에 꽂은 USB 동글)에도 붙는다. `net.zig`에서 `IFACE` · `SYS_IFACE` ·
`ifreq` · `SIOCGIFFLAGS` · `SIOCSIFFLAGS`와 링크를 올리는 함수가 빠진다.

TD 결정 1과 같은 방향이다 — 어려운 일은 그 일을 하는 도구가 하고 `init`은 배관만
한다. 게스트에 udev가 없으므로 dhcpcd가 udev 없이 핫플러그를 잡는지를 M0이 먼저
잰다. 못 잡으면 결정 4를 "`init`이 `/sys/class/net`을 순회해 넘긴다"로 되돌리고
핫플러그는 비목표로 옮긴다.

사용자가 골랐다(후보: dhcpcd manager mode · `init`이 첫 장치를 고른다 ·
`tars.conf`의 `net_iface=`).

### 결정 5 — 판정은 열네번째 체인 `nic/check.sh`다

`net` 체인은 virtio 위에서 프로토콜(DHCP · 포트 · 시계)을 보고, `nic` 체인은
드라이버와 장치를 본다. 한 체인에 섞지 않는 이유는 `net` 체인이 이미 부팅
다섯이고, 여기서 보려는 것은 프로토콜과 무관하게 "장치가 붙어 주소를 받는다"
하나이기 때문이다.

- 부팅 없이: `.config`에 결정 1의 드라이버가 전부 `=y`다.
- 부팅 A: `-machine q35` + `-netdev user` + `-device e1000e`, `net=dhcp`.
  커널 로그에 `e1000e`가 붙고 dhcpcd가 lease를 받는다.
- 부팅 B: NIC 없이 뜬 뒤 monitor의 `device_add usb-net`으로 꽂는다(USB 컨트롤러는
  `qemu-xhci`). 부팅이 끝난 뒤 생긴 인터페이스에서 dhcpcd가 lease를 받는다.

`q35`를 쓰는 이유는 `machine` 체인과 같다 — 노트북에 가까운 칩셋이다.

### 결정 6 — 부팅을 절대 안 막는다

`feedback_boot_never_blocks` 그대로다. dhcpcd는 지금처럼 감독 목록 밖에서 fork되고
`init`은 기다리지 않는다. 인터페이스가 하나도 없는 기계(`net=dhcp`인데 NIC가
없는 경우)도 부팅은 평소대로 끝난다 — dhcpcd가 인터페이스를 기다리며 살아
있을 뿐이다.

## 비목표

1. Realtek firmware(`rtl_nic/*.fw`). `r8169` · `r8152`는 없으면 경고 한 줄을 찍고
   대부분의 칩에서 동작한다. QEMU로 효과를 잴 수 없다. 다시 열릴 조건 — 실기에서
   그 경고가 링크 문제로 이어지는 것을 본 날. 사용자가 골랐다.
2. 무선. firmware와 `wpa_supplicant`가 들어오는 훨씬 큰 일이다.
3. 실기 판정. 실기가 생기면 연다.
4. 인터페이스 이름 규칙(predictable names). 커널의 `ethN` · `usbN`을 그대로 쓴다.
5. 여러 NIC의 우선순위와 route metric. dhcpcd 기본값을 쓴다.
6. `igb` · `e1000` 등 노트북에 드문 것. QEMU로 잴 수 있어도 켜지 않는다.

## 위험

### 위험 1 — 커널이 커지고 게이트가 그것을 열네 번 치른다

드라이버 다섯의 크기와 빌드 시간, 부팅 시간을 M0이 잰다. RM 결정 1이 이 대가를
이미 받아들였지만 숫자는 남긴다.

### 위험 2 — `-netdev`를 줘도 QEMU가 기본 NIC를 붙이는가

`net` 체인은 `-netdev` + `-device virtio-net-pci`만 준다. QEMU가 이때 기본 NIC를
빼는지는 읽어서 안 것이 아니다 — M0이 잰다. 안 빼면 결정 3의 lint가 "`-netdev`면
통과"가 아니라 "`-nic none`이 반드시 있다"가 된다.

### 위험 3 — dhcpcd가 udev 없이 핫플러그를 못 잡는다

결정 4에 되돌아갈 길을 적어 두었다.

### 위험 4 — manager mode가 `net` 체인의 판정을 바꾼다

로그 줄(`net link eth0 is up` · `started dhcpcd on eth0`)이 사라지거나 바뀐다.
dhcpcd의 hook이 받는 `$interface`, TS · TD가 쓰는 `ntp_servers` 경로도 M2가 다시
확인한다.

## milestone

- WN-M0(재기). 드라이버를 켜고 잰다 — 어느 드라이버에 붙고 이름이 무엇인가 ·
  `usb-net`이 CDC인지 RNDIS인지 · udev 없는 manager mode가 핫플러그를 잡는가 ·
  커널 크기 · 빌드 · 부팅 시간 · `-netdev`일 때 기본 NIC가 빠지는가.
- WN-M1(격리). QEMU 호출 전부에 `-nic none`, `require_explicit_nic`, `net` 검사 11
  삭제. 드라이버가 켜진 커널로 기존 체인이 전부 초록.
- WN-M2(`init`). manager mode, `net.zig` 축소, `net` 체인의 로그 판정을 새 줄에
  맞춘다.
- WN-M3(체인). `nic/check.sh`와 `CHAINS`, 루트 게이트.

plan은 milestone마다 그 시점에 쓴다.
