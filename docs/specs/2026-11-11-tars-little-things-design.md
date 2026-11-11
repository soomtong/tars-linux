# TARS Little Things — Design

접두사: LT

Date: 2026-11-11
Status: 닫힘(2026-11-12, LT-M0 — 다섯 전부, 루트 게이트 32/33 + pm 단독). 사용자가 다섯을 골랐고 "완성 작업까지 결정을 위임합니다"(2026-11-11). plan은 `docs/plans/2026-11-11-tars-little-things-lt-m0.md`.

계기: `docs/guides/carryover.md`에 실기 진단 때마다 아쉬웠던 작은 것이 쌓여 있었다. 2026-11-11에 다음 후보를 추리며 다섯을 한 묶음으로
보였고 사용자가 그대로 골랐다. 컨테이너 실행 환경(CE)과 같은 날 시작하고 0.2.1에 함께 실린다.

관련 문서: HP design(sudo · 사용자), PM design(Homebrew — Landlock 경고), `docs/guides/initrd-criteria.md`(ping은 기준 B),
`docs/decisions/feedback_ipv4_only.md`.

## 한 줄 요약

기계에 이름이 생기고(`hostname=`), 사용자가 `ping`을 치고, 기종 이름을 `/sys/class/dmi/id`에서 읽고, Homebrew가 Landlock 샌드박스를
쓰고, `sudo`가 패널마다 다시 묻지 않는다.

## 확인 (2026-11-11, HEAD `2814b47`)

1. `ping`이 initrd에 없다. Debian `iputils-ping`은 sysroot에도 없다(Dockerfile). 넣어도 사용자(uid 1000)는 커널 기본
   `net.ipv4.ping_group_range = 1 0`(아무 그룹도 아님)에 막힌다 — ICMP datagram 소켓을 못 연다. trixie의 `ping`은 setuid가 아니라
   file capability(`cap_net_raw`)로 깔리는데 initrd(cpio)는 xattr을 안 싣는다.
2. hostname은 커널 기본 `(none)`이다. init은 `sethostname`을 부르지 않는다. `/etc/hosts`는 `localhost` 한 이름(`make_initrd.sh`),
   `/etc/hostname`은 없다. 보이는 자리: 프롬프트, git 신원(`<이름>@(none)`), server 묶음 자체 서명 인증서의 CN(`common.sh`가
   `/proc/sys/kernel/hostname`을 읽고 비면 `tars` — `(none)`은 비지 않아 그대로 CN이 된다).
3. `CONFIG_DMI=y`인데 `CONFIG_DMIID`가 꺼져 `/sys/class/dmi/id/`가 없다. 실기에서 기종을 가릴 길이 `dmesg`의 `DMI:` 줄뿐이었다
   (맥북 프로 2013 Wi-Fi 조사).
4. `CONFIG_SECURITY`가 꺼져 Landlock이 없다. `brew install`마다 `Sandbox unavailable … without sandboxing!`(PM M1 실측 4).
5. sudo의 timestamp는 기본값(tty 단위, 15분)이다. 화면의 패널은 pty가 다 달라 패널마다 비밀번호를 다시 묻는다.

## 결정

### 결정 1 — `ping`은 initrd에, 권한은 `ping_group_range`

`iputils-ping`을 sysroot에 풀고 `usr/bin/ping`을 initrd에 넣는다(initrd 기준 B — 설치 전 · 묶음 없는 부팅에서 망 연결을 본다. curl은
ICMP를 못 한다). init이 부팅에 `net.ipv4.ping_group_range`를 `0 2147483647`로 쓴다(Debian의 기본과 같다) — setuid도 capability도 없이
모든 사용자가 ICMP echo를 보낸다. 쓰지 못해도 부팅은 간다(로그 한 줄).

### 결정 2 — `hostname=` 키, 기본값 `tars`

`tars.conf`의 스물둘째 키. 값은 DNS label 하나다 — 영문 소문자 · 숫자 · `-`, 1~63자, `-`로 시작하거나 끝나지 않는다(대문자는
거절한다 — 받아서 소문자로 바꾸지 않는다). 틀리면 한 줄 로그 뒤 기본값. init이 부팅에 `sethostname`을 부르고 `/etc/hostname`과
`/etc/hosts`의 `127.0.1.1 <이름>` 줄을 쓴다(Debian의 모양 — sudo · git · 서버가 이름을 풀 때 DNS로 나가지 않는다).
갈래는 `now`다 — `tars-config reload`가 `sethostname`과 두 파일을 곧바로 고친다. terminal의 argv에 안 들어 화면 대기(`reload terminal`)와
상관이 없고, 새 패널은 새 이름을 본다. 이미 떠 있는 셸의 프롬프트만 그대로다(fish는 시작할 때 이름을 읽는다).
기본값이 생기면서 게이트 체인이 보는 프롬프트가 `root@(none) ~#`에서 `root@tars ~#`로 두 칸 짧아진다 — 그 글자와 칸 수를 보는 판정을 함께 고친다.
기본값을 두는 까닭: `(none)`이 좋은 기계는 없다. 기계마다 다른 이름을 자동으로 짓지 않는다 — DMI serial이나 MAC에서 이름을 만들면
그 값이 프롬프트와 DHCP 요청에 실려 나간다.
sudoers의 `!fqdn`은 그대로 둔다(이름이 풀리게 됐어도 해가 없다).

### 결정 3 — `CONFIG_DMIID=y`

커널 옵션 하나. `/sys/class/dmi/id/{sys_vendor,product_name,product_version,board_name,bios_version,…}`가 생긴다. serial · uuid는
커널이 root 0400으로 둔다. init도 terminal도 읽지 않는다 — 사람과 진단 스크립트의 것이다.

### 결정 4 — Landlock을 켠다

`CONFIG_SECURITY=y` · `CONFIG_SECURITYFS=y` · `CONFIG_SECURITY_LANDLOCK=y`, `CONFIG_LSM`에 `landlock`. 다른 LSM(SELinux · AppArmor ·
Smack · TOMOYO · Yama · LoadPin · Lockdown · IMA)은 켜지 않는다 — 정책 파일과 도구가 없는 기계에 켤 까닭이 없다. Landlock은 프로세스가
스스로 자기 권한을 줄이는 장치라 정책도 root도 필요 없다. 부팅 로그의 `landlock: Up and running.`이 판정 줄이다.
이 옵션은 CE(컨테이너 실행 환경)의 AI 샌드박스도 쓴다 — 커널을 다시 굽는 일은 한 번이다.

### 결정 5 — `Defaults timestamp_type=global`

sudoers 한 줄. 한 번 확인하면 15분 동안 그 사용자의 모든 패널 · ssh 세션에서 다시 묻지 않는다. 한 사람이 쓰는 기계에서 tty 단위
격리가 막는 것(다른 tty에 앉은 다른 사람)이 없다. timeout 15분은 그대로다.

## milestone

- LT-M0: 다섯 전부. 커널 옵션(결정 3 · 4)은 lead가, 나머지는 서브에이전트가.

## 비목표

1. hostname을 DHCP로 받기 · DHCP 요청에 싣기(dhcpcd의 `hostname` 옵션) — 지금 설정 그대로 둔다.
2. mDNS(`<이름>.local`).
3. `ping -6` · `traceroute` · `mtr`. IPv4만 지원한다(`feedback_ipv4_only`).
4. Landlock 말고 다른 LSM.
