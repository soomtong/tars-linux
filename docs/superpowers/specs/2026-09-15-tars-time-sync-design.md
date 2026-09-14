# TARS Time Sync — Design

접두사: TS

Status: 진행 중(2026-09-15). M0이 끝났고 실측 여덟이 아래에 있다. 위험 일곱 중
넷이 닫혔고 하나는 처방이 정해졌다. M1 착수 전.

관련 문서: `2026-09-13-tars-guest-network-design.md`(NW. 게스트에 주소가 붙는
것을 세운 문서이고, 아래에서 "NW 실측 N"이라고 부르는 것은 전부 그 문서의
것이다) · `2026-09-14-tars-inbound-network-design.md`(IN. `net/check.sh`를
검사 열여섯으로 키운 문서).

## 한 줄 요약

부팅할 때 SNTP로 한 번 묻고 시계를 그 값으로 뛴다. 그리고 그 시각을 사람이
읽을 수 있는 지역 시간으로 보여 준다. 네트워크가 꺼져 있거나 안 닿아도
부팅은 평소대로 끝난다.

## 왜 지금인가

NW가 게스트에 주소를 붙였고 IN이 받는 길까지 세웠다. 그래서 이 기계는 이제
바깥과 바이트를 주고받는다. 그런데 이 기계는 지금이 몇 시인지 모른다 —
정확히 말하면, 무엇을 가리키는지를 아무도 안 봤다.

이것이 단순한 편의 문제가 아닌 이유가 커널 설정에 있다. `CONFIG_RTC_CLASS`가
꺼져 있어서(확인 1) 게스트에 `/dev/rtc0`가 없다. 즉 시계를 읽을 장치도,
되쓸 장치도, `hwclock`이 붙을 자리도 없다. 시계에 관해 이 저장소가 가진
것은 `clock_gettime(.MONOTONIC)` 세 자리뿐이고(확인 2) 그것은 흐른 시간을
재는 것이지 지금이 몇 시인지를 아는 것이 아니다.

사용자가 2026-09-14에 후보 넷(패키지 매니저 · 실머신 NIC · NTP · 포트 열기)
중에서 IN을 고르고, IN이 닫힌 뒤 같은 목록에서 NTP를 골랐다. 그리고 범위를
"부팅에 한 번 맞춘다"로, 묻는 주체를 "우리 코드"로, option 42 간극을
"hook → 파일 → init"으로, 시간대를 "zoneinfo 파일을 싣는다"로 정했다.
아래 결정 1 · 2 · 4 · 8이 그 넷이다.

그리고 사용자가 이번 사이클에 제약 하나를 따로 못 박았다 — 네트워크가
비활성화되어 있거나 연결되어 있지 않을 때도 부팅이 정상적으로 이루어져야
한다. 이것은 부수 조건이 아니라 구조를 정하는 힘이다(결정 3).

## 착수 전에 읽거나 잰 것 — 부팅은 한 번도 안 했다

열이다. 여섯은 저장소 파일을 읽은 것이고 넷(확인 5 · 6 · 8과 8의 압축값)은
컨테이너에서 명령을 돌려 잰 것이다. 게스트를 한 번도 안 띄웠으므로 이 문서의
어느 것도 실측이 아니다. 실측은 TS-M0이 한다.

### 확인 1 — 커널에 RTC 장치 계층이 없다

`kernel/.config`가 이렇다.

```
2448:CONFIG_RTC_LIB=y
2449:CONFIG_RTC_MC146818_LIB=y
2450:# CONFIG_RTC_CLASS is not set
2480:# CONFIG_VIRTIO_RTC is not set
```

`RTC_CLASS`가 꺼져 있으므로 `/dev/rtc0`도 `/sys/class/rtc`도 안 생긴다.
`hwclock`을 넣어도 열 장치가 없다.

`RTC_MC146818_LIB=y`가 남아 있는 것이 중요하다. x86의 timekeeping 초기화는
이 라이브러리로 CMOS를 직접 읽는 경로를 가지고 있어서, 장치 계층이 없어도
부팅 시각에 벽시계가 한 번 채워질 수 있다. 채워지는지 아닌지, 채워진다면
QEMU가 주는 호스트 시각인지는 소스 읽기로 단정할 수 없다 — M0의 측정 2가
`date`를 직접 찍어서 본다.

⚠ 답이 나왔다(실측 4). 채워지고, QEMU가 주는 호스트 시각이다. 그래서 게이트
판정은 "NTP 전에는 시계가 틀리다"에 기댈 수 없다.

### 확인 2 — init에 벽시계 코드가 한 줄도 없다

`rg 'clock_|settimeofday|CLOCK_REALTIME'`이 잡는 것이 넷인데 전부
`clock_gettime(.MONOTONIC)`이다(`main.zig:296` · `power.zig:143` ·
`devices.zig:272`의 `nanosleep` · `devices_test.zig:99`). 흐른 시간을 재는
자리들이고 지금이 몇 시인지를 묻는 자리가 하나도 없다.

`init/src`에 파일이 열둘 있다. 테스트 파일과 짝을 이룬 것이 다섯
(`config` · `devices` · `environ` · `power` · `storage`)이고, 짝이 없는 것이
`main.zig`와 `net.zig` 둘이다. TS가 더하는 것은 `sntp.zig`와 그 짝
`sntp_test.zig`다 — 순수 함수를 갈라내는 결정 11·12가 그 짝을 가능하게 한다.

### 확인 3 — 자식을 띄우고 잊는 패턴이 이미 있다

`net.zig`의 `startDhcpcd()`가 `fork` → `execve` → 부모는 로그 한 줄만 찍고
돌아온다. 감독 목록에 안 넣는 근거가 NW-M0 실측 4다 — dhcpcd가 배경으로
내려가면서 PID 1에 재부모화되고 `reapAll()`이 그것을 거둔다.

TS의 SNTP 자식은 여기서 한 걸음 더 간다. `execve`를 안 하므로 자식이 우리
코드를 그대로 이어서 돈다. `fork` 뒤의 자식에서 소켓을 열고 답을 기다리고
시계를 뛰고 `exit`한다. 부모는 그 사이 아무것도 안 기다린다(결정 3).

### 확인 4 — 게스트에 NTP 클라이언트가 없고 `date`는 있다

`kernel/guest_tools.sh:76`이 `usr/bin/date:usr/bin/date`다. 층 1의 GNU
coreutils 36개 중 하나다. `chronyd` · `ntpdate` · `sntp` · `busybox`는 목록에
없고 sysroot에도 없다.

`date`가 이미 있다는 것이 판정에 중요하다 — 게스트에 새 도구를 안 넣고도
화면으로 시각을 읽을 수 있다.

### 확인 5 — QEMU가 DHCP option 42를 줄 손잡이가 없다 (컨테이너에서 잼)

```
$ qemu-system-x86_64 --version
QEMU emulator version 10.0.11 (Debian 1:10.0.11+ds-0+deb13u1)

$ qemu-system-x86_64 -netdev user,id=x,ntp=1.2.3.4 ...
qemu-system-x86_64: -netdev user,id=x,ntp=1.2.3.4: Invalid parameter 'ntp'
```

SLIRP의 내장 DHCP 서버는 넷마스크 · 라우터 · DNS · 리스 시간 · 도메인 이름
정도를 주고 option 42(NTP servers)는 목록에 없다. 파라미터로 넣을 길도 없다.

같은 명령으로 netdev 백엔드 목록을 봤다 — `socket` · `stream` · `dgram` ·
`hubport` · `tap` · `user` · `l2tpv3` · `vde` · `bridge` · `vhost-user` ·
`vhost-vdpa`. 즉 SLIRP를 걷어내고 게스트 NIC를 컨테이너 프로세스에 직결할
길은 있다. 그 길이 "가짜 LAN"이고 이번에 안 골랐다(결정 4의 갈린 쪽).

### 확인 6 — 컨테이너에 perl이 있다 (컨테이너에서 잼)

NW-M0이 "컨테이너에 리스너로 쓸 것이 하나도 없다"를 세면서 `nc` · `ncat` ·
`socat` · `python3` · `busybox`를 봤고 전부 없었다. 이번에 perl을 더 봤다.

```
perl       /usr/bin/perl
perl -MIO::Socket::INET -e 'print "ok\n"'   →  ok
```

`IO::Socket::INET`이 되므로 UDP 소켓을 열고 답하는 스무 줄짜리 SNTP stub
서버를 게이트 안에 세울 수 있다. NW-M0의 결론("리스너가 없으니 `guestfwd`로
판정한다")은 TCP 이야기였고, `guestfwd`는 UDP를 안 받으므로 TS에는 못 쓴다.
perl이 그 자리를 메운다(결정 6).

### 확인 7 — dhcpcd hook을 더하는 비용이 파일 하나다

`kernel/make_initrd.sh:225-229`가 이렇다.

```
mkdir -p "$WORKDIR/usr/lib/dhcpcd/dhcpcd-hooks"
cp "$SYSROOT/usr/lib/dhcpcd/dhcpcd-run-hooks" "$WORKDIR/usr/lib/dhcpcd/"
cp "$SYSROOT/usr/lib/dhcpcd/dhcpcd-hooks/20-resolv.conf" \
   "$WORKDIR/usr/lib/dhcpcd/dhcpcd-hooks/"
chmod 0755 "$WORKDIR/usr/lib/dhcpcd/dhcpcd-run-hooks"
```

`dhcpcd-run-hooks`가 그 디렉터리를 훑어 있는 것만 돌린다. 그래서 파일을 하나
더 놓으면 dhcpcd가 그것을 부른다. 그리고 `20-resolv.conf`가 하는 일이
`$new_domain_name_servers`를 받아 `/etc/resolv.conf`를 쓰는 것인데, option
42는 정확히 같은 자리에서 `$new_ntp_servers`로 온다. 즉 TS가 쓸 hook은 이미
게이트에서 매번 도는 계약을 그대로 한 번 더 쓰는 것이다.

### 확인 8 — sysroot에 zoneinfo가 없고, 전체를 실어도 171KB다 (컨테이너에서 잼)

```
/usr/local/amd64-sysroot/usr/share/zoneinfo   →  없음
/usr/share/zoneinfo (컨테이너 자신)           →  2.1M, 파일 443 · 링크 51
  cpio -H newc | gzip -9                      →  174,898 바이트
Asia/Seoul                                    →  617 바이트
```

initrd가 cpio+gzip이므로 실제 증가분이 약 171KB다. TZif 파일은 대부분이 0이라
잘 눌린다. 비교하면 `dhcpcd` 바이너리 하나가 388,416바이트였다(NW-M0) — 세상의
모든 시간대가 그 절반이 안 된다.

그래서 "몇 개만 고른다"의 임의성을 감수할 이유가 없다. 전체를 싣는다(결정 8).

sysroot에 없으므로 `devcontainer/Dockerfile`에 `tzdata`를 더하고 이미지를 다시
구워야 한다(위험 6). tzdata는 `Architecture: all`이라 컨테이너 자신의
`/usr/share/zoneinfo`를 복사해도 바이트까지 같지만, 그러면 게스트 파일의
출처가 둘이 된다 — sysroot 하나로 유지한다(결정 10).

### 확인 9 — tars.conf의 키 일곱이 전부 enum 화이트리스트다

`init/src/config.zig`의 `Config`에 `shell` · `keyboard` · `hangul_layout` ·
`latin_layout` · `hangul_toggle` · `shell_config` · `net`이 있고, 값을 읽는
자리가 전부 `std.meta.stringToEnum`이다. `hangul_toggle`만 모양이 다른데
그것도 이름 넷의 조합이지 자유 문자열이 아니다.

TS가 더하는 `ntp`가 이 저장소의 첫 자유 문자열 값이 된다(`<IPv4>`). 그래서
파서가 필요하고, 그 파서는 힙 없이 도는 순수 함수여야 한다(결정 5).
`timezone`도 자유 문자열이지만 그쪽은 값을 해석하지 않고 그대로 넘긴다
(결정 8).

### 확인 10 — `net=off`가 기본값이 꺼짐인 유일한 키다

`config.zig:632`의 주석이 그 근거를 적어 뒀다 — 다른 키들은 "이 기계를 쓰는
사람이 쓰는 것"이 기본값인데(`keyboard=apple` · `hangul_layout=shin_pcs`)
네트워크만 켜는 것이 부작용을 가지기 때문이다.

`ntp`도 같은 이유로 기본이 `off`다. `net=off`인 기계에서 `ntp`가 켜져 있으면
그 자식이 매 부팅마다 헛되이 태어나 실패하고 죽는다.

`timezone`은 갈린다. 기본값이 `UTC`인데 그것은 "꺼짐"이 아니라 "지금과 같은
동작"이다 — zoneinfo가 없는 지금 게스트가 이미 UTC를 찍고 있고, 기본값을
`UTC`로 두면 이 키를 안 적은 기계의 동작이 한 글자도 안 바뀐다.

## 결정

### 결정 1 — 부팅에 한 번 뛴다. 시계를 길들이지 않는다

사용자가 골랐다. 하는 일은 SNTP 질의 한 번과 `clock_settime` 한 번이다.

NTP의 어려운 부분은 시각을 묻는 것이 아니라 시계를 길들이는 것이다 — drift
추정 · slew · PLL/FLL 루프 · 서버 여럿의 교차 검증 · leap second. chrony의
값이 전부 거기 있고, 이 결정이 그것을 통째로 뺀다. 남는 것은 48바이트를
보내고 48바이트를 받아 그중 8바이트를 읽는 일이다.

다시 열릴 조건: TARS가 drift가 보일 만큼 오래 켜져 있게 되는 것. 그날
들어오는 것이 chrony이고, 그때 이 결정이 근거가 아니라 걸림돌이 된다.

### 결정 2 — 묻는 주체는 우리 코드다 (Zig SNTP)

사용자가 근거를 듣고 골랐다. 근거 셋이다.

첫째, 결정 1이 어려운 부분을 뺐으므로 남은 일에서는 chrony도 우리도 같은
코드를 쓴다. 둘째, 기성 도구를 쓰면 게이트에서 비용이 바로 나온다 — chrony는
기본적으로 큰 점프를 거부해서 `makestep` 설정 파일과 `/var/lib/chrony`와
전용 사용자를 initrd에 세워야 하고, 상주하므로 감독 목록 · 종료 시그널 ·
SL-M2가 세운 `grace period expired` 판정에 전부 얽힌다. 결정 1이 좁힌 범위를
도구가 도로 넓힌다. 셋째, 실패를 읽을 수 있다 — 우리 코드가 실패하면
`tars-init:` 한 줄이 어느 단계에서 멈췄는지 말하고 게이트가 그 줄을 grep한다.

initrd 비용이 0이다. 새 바이너리 0개 · 새 라이브러리 0개다.

### 결정 3 — 부팅을 절대 안 막는다. SNTP는 fork한 자식이 한다

사용자가 못 박은 제약이다. 갈래가 넷이고 전부 로그 한 줄을 남긴다.

| 상황 | 하는 일 |
|---|---|
| `ntp=off` | 로그 한 줄. 소켓도 fork도 없다 |
| `net=off`인데 `ntp`가 켜짐 | 로그 한 줄. 주소가 붙을 리 없으므로 시도 안 한다 |
| `eth0`이 없음 | `net.zig`가 이미 그 자리에서 멈춘다. TS도 같은 판단을 쓴다 |
| 서버가 안 답함 | 자식이 타임아웃을 다 쓰고 로그 한 줄 남기고 죽는다 |

마지막 줄이 이 결정의 핵심이다. `recvfrom`이 블록하면 부팅이 그 자리에 선다.
그래서 소켓에 `SO_RCVTIMEO`를 걸고, 그 위에 다시 fork로 감싼다 — 타임아웃
계산이 틀려도 부모가 안 기다리므로 셸이 뜨는 시각은 안 변한다.

자식을 감독 목록에 안 넣는 근거는 NW-M0 실측 4와 같다. PID 1의 `reapAll()`이
거두고, SIGTERM에 죽으므로 SL-M2의 유예 판정에 안 걸린다.

게이트가 이것을 음성으로 증명한다 — 부팅 B가 안 닿는 주소를 주고도 셸이
제때 뜨는지 본다(결정 7).

### 결정 4 — option 42 간극을 hook → 파일 → init으로 자른다

실기계에서 맞는 모양은 분명히 DHCP option 42다. 공유기가 알려 주는 것을 쓰는
것이 사람이 주소를 손으로 적는 것보다 옳다. 그런데 확인 5가 보인 대로 게이트의
SLIRP는 그것을 영영 안 준다. 증명 못 하는 기능을 넣는 것이 이 저장소가 가장
피하는 일이므로 그 간극을 어떻게 메우는지가 이 사이클의 가장 큰 설계 결정이다.

경로를 넷으로 자른다.

```
dhcpcd ──(option 42)──> hook 30-tars-ntp ──> /run/tars/ntp_servers ──> SNTP 자식
        [dhcpcd의 계약]      [우리 sh 3줄]          [파일]            [우리 Zig]
```

자른 자리마다 증명되는 곳이 다르고, 셋은 게이트 안에서 완전히 닫힌다.

1. 파일 → init. `net/check.sh`가 그 파일을 미리 심은 initrd로 부팅을 하나
   띄운다. init에게는 우리가 심은 파일과 dhcpcd가 쓴 파일이 구별되지 않는다.
   그래서 SLIRP가 option 42를 못 줘도 이 경로 전체가 게이트에서 초록이 된다.
2. hook → 파일. 호스트 검사가 `new_ntp_servers='1.2.3.4 5.6.7.8' sh 30-tars-ntp`로
   그 3줄을 직접 돌려 파일이 생기고 첫 주소가 들어 있는지 본다. 게스트도
   QEMU도 필요 없다.
3. dhcpcd → hook. 이것만 우리가 안 만든 부분이고 미증명으로 남는다. 근거는
   `20-resolv.conf`가 `$new_domain_name_servers`로 지금 게이트에서 매번 도는
   것과 글자 그대로 같은 계약이라는 것이다.

갈린 쪽은 "가짜 LAN"이었다 — `-netdev dgram`으로 게스트 NIC를 컨테이너의
perl에 직결하고 그 perl이 raw Ethernet frame 수준에서 ARP · DHCP(option 42
포함) · SNTP를 전부 말하게 하는 것. 증명력은 최고지만 perl 250~350줄에
IP/UDP 체크섬과 DHCP 상태 기계가 들어가고, SLIRP의 `hostfwd`/`guestfwd`를
잃어서 부팅을 따로 세워야 한다. 게이트에 새 부품이 생기고 그 부품 자체가
버그 원천이 된다. 사용자가 이 쪽을 안 골랐다.

다시 열릴 조건: 실기계에서 option 42가 안 오는 것으로 의심될 때. 그때는
가짜 LAN이 진단 도구로서 값을 한다.

### 결정 5 — 설정 키는 `ntp=off | dhcp | <IPv4 주소>`

`net=off | dhcp`와 대칭이다.

- `off` — 기본값. 아무것도 안 한다(확인 10).
- `dhcp` — `/run/tars/ntp_servers`를 읽는다. 실기계의 기본 길.
- `<IPv4>` — 그 주소에 묻는다. 명시가 이긴다.

한 키가 "켜고 끄는 것"과 "어디에 묻는지"를 함께 정하므로, "켰는데 어디에
물을지를 안 적은" 모순 상태가 구조적으로 없다.

이름이 아니라 주소 리터럴만 받는 이유는 `init`에 resolver가 없기 때문이다.
libc도 힙도 없으므로 `pool.ntp.org`를 풀려면 DNS 클라이언트를 직접 써야 하고,
그러면 이 사이클이 "시계 맞추기"에서 "DNS 구현하기"로 넘어간다. 게스트 셸
쪽 이름 풀이는 이미 된다(NW-M0 실측 5) — 안 되는 것은 `init` 안에서다.

값이 셋 중 어느 것도 아니면(예: 오타) 로그 한 줄을 찍고 `off`로 떨어진다.
다른 키 일곱이 전부 그 모양이다.

### 결정 6 — 게이트의 상대는 perl stub SNTP 서버다

`net/check.sh`가 컨테이너에서 perl 프로세스를 배경으로 띄우고, 그것이 UDP
123에서 고정된 시각을 답한다. 체인이 끝날 때 `trap`으로 죽인다.

답하는 시각은 CMOS로도 커널로도 나올 수 없는 값이어야 한다. 그래야 "시계가
우리 코드 때문에 움직였다"가 "원래 그 값이었다"와 갈린다. 실제 값은 M0이
정하고, 과거가 아니라 미래의 해로 둔다 — 과거로 뛰면 게이트가 만든 파일의
mtime이 뒤집혀서 다른 자리에서 이상한 일이 날 수 있다(위험 2).

게스트가 그 stub에 닿는 경로는 `10.0.2.2`(SLIRP의 게이트웨이이자 호스트)로
가는 UDP다. SLIRP가 그것을 컨테이너 쪽으로 넘겨 주는지가 이 사이클의 가장 큰
미지수이고 M0의 첫 측정이다(위험 1).

### 결정 7 — 판정은 부팅 둘이 나눠 가진다

`net/check.sh`에 부팅 둘이 는다. 하나에 다 담지 않는 이유는 둘이 서로 다른
것을 증명하기 때문이다.

부팅 A — 설정 디스크에 `net=dhcp` · `ntp=<stub 주소>`. 증명하는 것은
"SNTP가 돌고 시계가 뛴다".

- init 로그에 `tars-init: clock stepped to <…>` 줄이 있다
- 화면의 `date`가 stub이 정한 해를 찍는다

화면 판정은 에코 함정을 피해야 한다(`docs/decisions/project_gate_screen_echo.md`).
`date`를 그냥 치면 명령 에코가 화면에 남아서 `wait_for_screen`이 그것을
출력으로 오해할 수 있다. 그래서 출력에만 생기는 글자를 만든다 —
`echo tsyear=$(date -u +%Y)`.

`-u`를 붙이는 것이 중요하다. TS-M3이 시간대를 넣은 뒤에도 이 판정이 안
흔들려야 한다.

부팅 B — 설정 디스크에 `net=dhcp` · `ntp=dhcp`, 그리고
`/run/tars/ntp_servers`에 안 닿는 주소를 미리 심은 initrd. 증명하는 것이
둘이다.

- init이 그 파일을 읽었다 — 로그가 그 주소를 이름 대며 찍는다
- 안 닿는 서버가 부팅을 안 막는다 — 셸이 평소와 같은 자리에서 뜬다

심는 주소를 죽은 것으로 두는 것이 이 부팅의 값을 두 배로 만든다. 살아 있는
주소를 심으면 파일 경로만 증명되고, 죽은 주소를 심으면 결정 3의 음성까지
함께 증명된다.

호스트 검사는 셋이다 — `sntp.zig`의 순수 함수 단위 테스트, `config.zig`의
`ntp` 파싱 테스트, 그리고 hook 3줄을 직접 돌리는 검사(결정 4의 2번).

### 결정 8 — 시간대는 zoneinfo 전체를 싣고 `timezone=<IANA 이름>`으로 고른다

사용자가 골랐다. 확인 8이 근거를 숫자로 줬다 — 전체가 압축 171KB다.

갈린 쪽이 둘이었다. POSIX TZ 문자열(`timezone=KST-9`)은 파일이 0바이트지만
부호가 뒤집힌 규칙을 사람이 알아야 하고 서머타임 지역에서는 사람이 쓸 것이
못 된다. 이름 화이트리스트(`timezone=utc|seoul`)는 그 함정을 없애지만 새
도시를 넣으려면 다시 빌드해야 한다. zoneinfo를 실으면 둘 다 안 겪는다 —
세상의 모든 규칙과 과거 이력이 정확해지고, 다른 도구들도 같은 것을 본다.

값을 해석하지 않는다. `timezone=Asia/Seoul`을 받으면 `TZ=Asia/Seoul`을 env
블록에 넣고 끝이고, 그 이름이 무슨 뜻인지는 glibc가 안다. 다만 존재는
확인한다 — `/usr/share/zoneinfo/<값>`을 열어 보고 없으면 로그 한 줄을 찍고
`UTC`로 떨어진다. 그 확인이 없으면 오타의 증상이 "조용히 UTC"라서 원인에서
멀다.

이름에 `..`나 `/`로 시작하는 것이 오면 거른다. 위협 모델이 있어서가 아니라,
경로를 조립하는 코드가 검증 없이 값을 먹는 것을 이 저장소에 남기지 않기
위해서다.

### 결정 9 — 시간대는 `TZ` 환경변수로 전한다. `/etc/localtime`은 안 만든다

`init/src/environ.zig`가 이미 `PATH`와 `XDG_DATA_HOME`을 env 블록에 넣고
있고, 게스트의 모든 프로세스가 PID 1의 자식이라 그 블록을 물려받는다. 그래서
`TZ` 한 항목을 더하면 셸도 `date`도 같은 것을 본다.

`/etc/localtime` 심볼릭 링크를 함께 만들 수도 있지만 안 만든다. 길이 둘이면
어긋날 자리가 생기고, env 블록을 안 물려받는 프로세스가 지금 이 게스트에
하나도 없다.

`environ.zig`가 시스템 콜을 하나도 안 하는 파일이라는 것이 덤이다 —
`environ_test.zig`가 호스트에서 돌므로 새 항목이 블록에 제대로 들어가는지를
QEMU 없이 본다.

다시 열릴 조건: env 블록 밖에서 시작되는 프로세스가 생기는 것.

### 결정 10 — tzdata는 sysroot에서 온다

tzdata가 `Architecture: all`이라 컨테이너 자신의 `/usr/share/zoneinfo`를
복사해도 바이트까지 같다. 그래도 `devcontainer/Dockerfile`에 넣어 sysroot를
거치게 한다 — 게스트에 들어가는 파일의 출처가 하나여야 `make_initrd.sh`를
읽는 사람이 "이 파일은 어디서 왔나"를 한 자리에서 답할 수 있다.

비용은 이미지 재빌드 한 번이다(NW-M2 기준 약 42초, 위험 6).

### 결정 11 — NTP era를 코드와 테스트가 함께 못 박는다

NTP의 초는 1970이 아니라 1900부터 세고 32비트다. 그래서 둘이다.

- epoch 차이 `2208988800`을 뺀다.
- 2036-02-07 06:28:16 UTC에 그 32비트가 한 바퀴 돈다. RFC 4330이 정한 규칙은
  "최상위 비트가 0이면 era 1(2036년 이후)로 읽는다"이다.

이것을 주석으로만 적으면 10년 뒤에 조용히 1900년으로 뛴다. `parseReply`가
순수 함수이므로 테스트가 경계 양쪽을 직접 먹인다 — era 0의 마지막 초와 era
1의 첫 초.

### 결정 12 — 응답을 넷으로 검증한다

`parseReply`가 다음을 다 통과해야 시각을 돌려준다.

| 보는 것 | 안 보면 생기는 일 |
|---|---|
| Mode가 4(server)인가 | 우리가 보낸 것이 되돌아온 것을 시각으로 읽는다 |
| Stratum이 0이 아닌가 | Kiss-o'-Death 패킷의 쓰레기 값으로 시계를 뛴다 |
| Transmit timestamp가 0이 아닌가 | 1900년으로 뛴다 |
| Origin timestamp가 우리가 보낸 nonce와 같은가 | 아무 UDP 패킷이나 시계를 옮긴다 |

마지막 줄이 가장 중요하다. `recvfrom`이 소스 주소를 확인해도 UDP는 위조가
쉽고, nonce 대조가 그것을 막는 표준 방법이다. 보내는 패킷의 transmit
timestamp 자리에 우리가 만든 값을 넣고, 답의 origin timestamp가 그것과 같은지
본다.

nonce의 출처는 `clock_gettime(.MONOTONIC)`이다. 난수가 아니지만 부팅마다
다르고, 여기서 막으려는 것이 공격이 아니라 "엉뚱한 패킷"이다.

## 비목표

일곱이다. 각각 다시 열릴 조건을 함께 적는다.

1. 시계 길들이기(drift · slew · 재동기화 주기). 다시 열릴 조건: TARS가
   drift가 보일 만큼 오래 켜져 있게 되는 것.
2. 서버 여럿과 교차 검증. `/run/tars/ntp_servers`에 여럿이 와도 첫 것만
   쓴다. 다시 열릴 조건: 첫 서버가 자주 죽는 것을 실제로 겪는 것.
3. RTC에 되쓰기. `CONFIG_RTC_CLASS`가 꺼져 있어 장치가 없다(확인 1). 다시
   열릴 조건: 네트워크 없이 부팅해도 시각이 맞아야 하는 요구가 생기는 것.
4. DNS 이름으로 서버를 적는 것. 다시 열릴 조건: `init`에 resolver가 필요한
   다른 이유가 생기는 것.
5. 실기계에서 option 42가 실제로 오는 것의 증명. 게이트에 그 길이 없다
   (결정 4의 3번). 다시 열릴 조건: 실기계에서 시계가 안 맞는 것을 겪는 것.
6. 게스트가 NTP 서버 노릇을 하는 것. 이 저장소의 코드에는 아직 `bind`도
   `listen`도 없다(IN이 같은 문장을 남겼다). 다시 열릴 조건: 게스트가 무엇을
   서빙해야 하는지가 정해지는 것.
7. NTPv4의 나머지 — 인증 · 대칭 모드 · 브로드캐스트 · 왕복 지연 보정. 부팅에
   한 번 뛰는 데 필요하지 않다. 다시 열릴 조건: 비목표 1과 같다.

## 위험

### 위험 1 — SLIRP가 `10.0.2.2`로 가는 UDP를 컨테이너에 안 넘길 수 있다

TS-M0이 닫았다(실측 2). 넘긴다. 평문 7바이트도 SNTP 48바이트도 같은 길로
가고, 답도 돌아온다.

아래는 닫히기 전의 기록이다.

가장 크다. stub이 닿을 길이 없으면 결정 6과 7이 통째로 무너지고, 안 고른
"가짜 LAN"으로 되돌아가야 한다. 그러면 범위가 크게 늘어난다.

TS-M0의 첫 측정이 이것이고, 답이 아니오면 M1 전에 사용자에게 다시 묻는다.

완화책 후보: 포트를 123이 아닌 것으로 옮겨 보기(특권 포트 문제일 수 있다),
`hostfwd=udp:`로 반대 방향을 먼저 확인해 UDP 자체가 SLIRP를 지나는지 가르기.

### 위험 2 — 시계를 뛰면 다른 자리가 깨질 수 있다

TS-M0이 대부분 닫았다(실측 6). 5년을 뛰어도 셸 · dhcpcd · 주소 · 파일 쓰기가
전부 그대로였고, 점프 뒤로 커널도 init도 한 줄을 안 찍었다. dhcpcd의
`valid_lft`가 남아 있는 것이 특히 중요하다 — 리스 만료를 벽시계로 쟀다면
즉시 만료됐을 것이다.

⚠ 렌더 하나가 안 닫혔다(실측 7). M0의 하네스로는 "살아 있다"와 "할 일이
없다"가 같은 값이라 못 갈랐다. M1의 부팅 A가 본다 — 그 부팅은 화면에
타이핑을 하므로 판정이 서는 것 자체가 렌더가 살아 있다는 증거다.

아래는 닫히기 전의 기록이다.

게이트가 도는 중에 게스트의 벽시계가 몇 년을 뛴다. 영향 가능성이 있는 곳 셋.

- 파일 mtime. `/config`의 히스토리 파일과 zoxide DB가 미래 시각을 갖는다.
  미래로만 뛰게 하면(결정 6) "미래 파일" 경고를 내는 도구는 없으므로 안전할
  가능성이 높지만 안 쟀다.
- 셸 히스토리의 타임스탬프. zsh의 `EXTENDED_HISTORY`가 꺼져 있으면 안 쓴다.
- 터미널 렌더와 `nanosleep`. 전부 `MONOTONIC`이라 안 흔들린다(확인 2).

M0의 측정에 "뛴 뒤에 체인의 나머지가 그대로 도는가"를 넣는다.

### 위험 3 — dhcpcd가 option 42를 요청조차 안 할 수 있다

TS-M0이 처방을 정했다(실측 8). 요청하는지는 여전히 안 갈렸지만 가릴 필요가
없어졌다 — M2가 `net.zig`의 argv에 `-o ntp_servers`를 더한다. 그 옵션이 있는
것과, dhcpcd가 option 42를 `new_ntp_servers`라는 이름으로 다룬다는 것을
바이너리에서 확인했다.

아래는 정해지기 전의 기록이다.

dhcpcd의 요청 목록은 `/etc/dhcpcd.conf`와 컴파일 타임 기본값에서 오는데,
게스트에 `/etc/dhcpcd.conf`가 없다. `ntp_servers`가 기본 요청 목록에 없으면
hook에 `$new_ntp_servers`가 영영 안 온다.

이 위험은 결정 4의 구조 덕분에 게이트를 안 막는다 — 게이트가 증명하는 것은
"파일이 있으면 읽는다"이고 그것은 dhcpcd와 무관하다. 다만 실기계에서 `ntp=dhcp`가
안 도는 원인이 된다. M0이 그 기본 목록을 확인하고, 필요하면 처방이 둘이다 —
`dhcpcd`에 `-o ntp_servers`를 붙이거나 `/etc/dhcpcd.conf`를 initrd에 넣는 것.

### 위험 4 — 컨테이너에서 UDP 123을 못 열 수 있다

TS-M0이 닫았다(실측 1). 컨테이너가 `uid=0`이라 그대로 묶인다. 결정 5가 안
커진다 — 주소에 포트를 적는 문법이 필요 없다.

아래는 닫히기 전의 기록이다.

1024 미만이라 특권이 필요하다. 컨테이너가 root로 돌지만 확인은 안 했다.
못 열면 stub을 높은 포트로 옮겨야 하고, 그러면 `ntp=<IPv4>`에 포트를 적는
문법이 필요해진다(`ntp=10.0.2.2:12345`). 결정 5가 커진다. M0이 본다.

### 위험 5 — 부팅 둘이 게이트에 약 75초를 더한다

`net` 체인 단독이 지금 33.7초이고 부팅 하나가 대략 12~13초다. 부팅 둘이면
체인이 약 25초 늘고, 게이트가 체인을 세 번 도니 약 75초다. GL이 54분을
16분으로 줄인 저장소이므로 그냥 넘기지 않는다.

다만 게이트 잡음이 ±3분이라 이 크기는 게이트에서 안 갈린다. 체인 단독 시간을
M1 · M2가 각각 재서 기록한다.

### 위험 6 — 이미지 재빌드가 필요하다

sysroot에 tzdata가 없으므로 `devcontainer/Dockerfile`을 고쳐야 한다. RM
design 위험 5와 NW-M2가 같은 비용을 겪었고 약 42초다. M3에서 한 번 친다.

### 위험 7 — `clock_settime`이 이미 떠 있는 프로세스의 타이머를 흔든다

TS-M0이 닫았다(실측 6). 5년을 뛰어도 이미 떠 있던 셸과 dhcpcd가 둘 다
살아남았고 dhcpcd의 리스도 그대로였다. 완화책("되도록 일찍 띄운다")이
필요 없어졌다.

아래는 닫히기 전의 기록이다.

시계를 뛰는 시점에 이미 셸과 dhcpcd가 떠 있다. POSIX는 `CLOCK_REALTIME`
절대 타이머가 점프를 따라간다고 정하고 있고, 상대 타이머와 `MONOTONIC`은 안
흔들린다. 게스트에 절대 타이머를 쓰는 것이 무엇인지 안 셌다.

완화: SNTP 자식을 되도록 일찍 띄워서 뛰는 시점을 부팅 초반으로 당긴다.
그런데 `ntp=dhcp`는 dhcpcd의 리스를 기다려야 하므로 그럴 수 없다 — 그래서
M0이 "뛴 뒤에 체인의 나머지가 그대로 도는가"(위험 2)와 같은 측정으로 본다.

## TS-M0이 실행으로 증명한 것

여덟이다. plan이 잰다고 한 여섯에 더해, plan에 없던 것 둘(실측 3 · 7)이
나왔다. 하네스는 `/tmp/ts/stub.pl`과 `/tmp/ts/guest.sh`이고 전문이 plan의
Task 1 · 2에 글자 그대로 있다. 부팅 한 번을 포함해 전체가 1분 15초였다.

### 실측 1 — UDP 123이 열린다. 위험 4가 닫혔다

컨테이너가 root(`uid=0`)로 돌아서 특권 포트에 바로 묶인다. perl stub이 평문
왕복과 SNTP 왕복을 둘 다 해냈다.

```
TSM0: loopback text reply=[tsm0-pong]
TSM0: loopback sntp reply len=48 first=0x24
TSM0: transmit timestamp = 4139355967 ntp = 1930367167 unix
len=48 li_vn_mode=0x24 stratum=1 poll=4 precision=-6
refid=TSM0 origin=[NONCE123]
```

마지막 줄이 결정 12의 마지막 항목이 볼 자리다 — 요청의 40~47바이트에 넣은
`NONCE123`이 응답의 24~31바이트로 그대로 돌아왔다. M1의 `parseReply`가 이
자리를 자기 nonce와 대조한다.

그리고 이 self-test가 stub의 버그를 하나 잡았다. `pack('CCcC', 0x24, 1, 4, -6)`은
부호 있는 바이트를 셋째에 두어서 precision이 부호 없는 `C`로 갔고 perl이
`Character in 'C' format wrapped`를 찍었다. 결과 바이트는 두 보수라 우연히
같지만 템플릿은 `CCCc`가 맞다. `perl -c`는 문법만 보므로 이것을 못 잡는다 —
QEMU를 띄우기 전에 실제로 한 번 보내 본 값이 여기서 나왔다.

### 실측 2 — SLIRP가 나가는 UDP를 컨테이너에 넘긴다. 위험 1이 닫혔다

가장 크게 걸려 있던 것이 풀렸다. 게스트가 보낸 네 datagram이 전부 stub에
닿았고 답도 전부 게스트로 돌아왔다.

```
TSM0-STUB: recv 7 bytes from 127.0.0.1:57700 first=0x74      ← probe A (10.0.2.2)
TSM0-STUB: recv 48 bytes from 127.0.0.1:44486 first=0x23     ← probe B (10.0.2.2, SNTP)
TSM0-STUB: recv 7 bytes from 192.168.215.2:40197 first=0x74  ← probe C (컨테이너 IP)
TSM0-STUB: recv 8 bytes from 127.0.0.1:46235 first=0x74      ← probe A2 (점프 뒤)
```

소스 주소가 두 갈래인 것이 이 실측의 덤이다. `10.0.2.2`로 보낸 것은
`127.0.0.1`에서 오고 컨테이너 IP로 보낸 것은 그 IP에서 온다. 앞은 SLIRP이
"호스트"를 loopback으로 NAT한 것이고, 뒤는 SLIRP이 서브넷 밖이라 판단해
호스트 스택으로 내보낸 것이 돌아온 것이다. 결정 6이 `10.0.2.2`를 쓰므로
stub은 loopback에만 묶여도 되지만, 하네스는 `0.0.0.0`에 묶어 둘 다 받았다.

길이도 내용도 안 가린다 — 평문 7바이트와 SNTP 48바이트가 같은 길로 갔다.

### 실측 3 — bash의 `read`는 datagram을 잘라 먹는다 (plan에 없던 것)

probe A의 결과가 이것이었다.

```
TSM0-A rc=142 got=[t]
```

stub은 `tsm0-pong\n` 10바이트를 분명히 보냈는데 게스트가 받은 것이 `t` 한
글자다. 컨테이너에서 같은 bash로 재현해서 원인을 갈랐다.

```
read -r -t 3 line      →  rc=142 got=[t]
read -r -t 3 -N 10 x   →  rc=0   got=[tsm0-pong] len=10
head -c 10 <&3         →  got=[tsm0-pong]
```

`-N` 없는 `read`는 한 바이트씩 `read()`를 부른다. TCP에서는 그것이 맞지만
datagram 소켓에서는 한 번의 `read()`가 datagram 하나를 통째로 소비하고 요구한
길이 너머를 버린다. 그래서 첫 글자만 남고 나머지 9바이트가 사라지며, 다음
`read()`는 올 것이 없어 타임아웃해서 `rc=142`(128+SIGALRM)가 된다.

IN-M0 실측 1과 같은 자리의 함정이다 — 저쪽은 "`rc`로는 판정할 수 없다"였고
이쪽은 "`rc`도 받은 글자도 도구의 성질 때문에 거짓을 말한다"다. UDP를 셸로
읽는 사람은 `-N`이나 `head -c`를 쓴다.

probe B가 `rc=0`이었던 것이 이것으로 설명된다. 그쪽은 `-N 1`이라 요구한 만큼
정확히 받았다.

### 실측 4 — 게스트 시계는 이미 맞다. 커널이 CMOS를 읽는다

```
TSM0-CLOCK 2026-09-14T23:19:47Z unix=1789427987
```

같은 순간 호스트가 `2026-09-14T23:21:51Z`였다. 차이가 2분 04초이고 그것이
하네스가 돈 시간이다. 즉 게스트의 벽시계가 부팅 시점에 이미 호스트 시각이다.

확인 1이 남겨 둔 물음의 답이다. `CONFIG_RTC_CLASS`가 꺼져 있어도
`CONFIG_RTC_MC146818_LIB`로 x86 timekeeping이 CMOS를 읽고, QEMU가 그 CMOS를
호스트 시각으로 채운다.

이것이 게이트 판정에 직접 영향을 준다. "NTP 전에는 시계가 틀리다"에 기댈 수
없다 — 아무것도 안 해도 맞다. 그래서 stub이 답하는 시각이 현실과 뚜렷이
달라야 한다는 결정 6이 선택이 아니라 필수다.

실기계에서는 다를 수 있다. RTC 배터리가 죽었거나 없는 기계에서 무엇이 나오는지
이 실측은 말해 주지 않는다.

### 실측 5 — 게스트에서 벽시계를 뛸 수 있다

```
TSM0-AFTER 2031-03-04T05:06:11Z unix=1930367171
```

`date -u -s "2031-03-04 05:06:07"`이 성공했고 4초 뒤에 읽은 값이 그만큼
흘러 있다. 커널이 userspace의 벽시계 설정을 막지 않는다. M1의
`clock_settime(CLOCK_REALTIME)`이 같은 자리를 쓴다.

### 실측 6 — 시계를 5년 뛰어도 게스트가 그대로 돈다. 위험 2와 7이 닫혔다

점프 뒤에 넷을 봤고 넷 다 정상이었다.

```
TSM0-ALIVE=76                                          셸이 산다
TSM0-DHCPCD=1                                          dhcpcd가 산다
TSM0-MTIME 2031-03-04 05:06:20.059999483 +0000         파일 mtime이 따라간다
TSM0-ADDR= inet 10.0.2.15/24 ... valid_lft 86357sec    주소가 남아 있다
TSM0-A2 rc=142 got=[t]                                 UDP가 여전히 돈다
```

`TSM0-A2`의 `rc=142`는 실패가 아니라 실측 3의 성질이다 — 같은 회차의 stub
로그에 그 datagram과 응답이 남아 있다.

그리고 점프 뒤로 커널도 init도 한 줄을 안 찍었다. 시리얼 로그의 921행(점프를
친 자리)부터 끝까지 `tars-init:`도 커널 타임스탬프 줄도 하나도 없다. 위험 7이
걱정한 "이미 떠 있는 프로세스의 타이머"가 적어도 이 게스트에서는 아무 일도
안 일으킨다.

`valid_lft`가 남아 있는 것이 특히 중요하다. dhcpcd가 리스 만료를 벽시계로
쟀다면 5년 점프에 즉시 만료됐을 텐데 안 그랬다.

### 실측 7 — 렌더가 살아 있는지는 이 하네스로 못 갈랐다 (plan의 판정이 틀렸다)

plan은 "시리얼 로그의 `terminal: screen>` 줄 수가 점프 뒤에 자라면 렌더가
살아 있다"로 봤다. 그런데 관측이 이랬다.

```
TSM0: serial log has 3 screen lines
TSM0: five seconds later it has 3
```

안 자랐지만 그것이 렌더가 죽었다는 뜻이 아니다. TR-M2가 `needs_redraw`를
문지기로 두어서 화면에 아무 일도 없으면 프레임이 안 찍히고, 이 하네스는
콘솔 셸만 쓰므로 화면 셸에 아무 입력이 없다. 즉 "살아 있다"와 "할 일이
없다"가 이 지표에서 같은 값이다.

plan을 쓸 때 `gate_lib.sh`의 주석에 그 성질이 적혀 있는 것을 읽고도 판정에
반영하지 않았다. 갈라 보려면 monitor로 화면 셸에 키를 보내야 하는데 이
하네스는 `-monitor none`이다.

미해결로 남기고 M1의 부팅 A로 넘긴다. 그 부팅은 `net/check.sh` 안에 있어서
monitor가 있고 화면에 타이핑을 하므로, 시계가 뛴 뒤에 화면 판정이 서면 그
자체가 렌더가 살아 있다는 증거다.

### 실측 8 — dhcpcd는 option 42를 요청할 설정을 가졌지만 그 파일이 initrd에 없다

sysroot의 `/etc/dhcpcd.conf`에 그 줄이 있다.

```
option domain_name_servers, domain_name, domain_search
option classless_static_routes
option interface_mtu
option host_name
option ntp_servers
```

그런데 `kernel/make_initrd.sh`는 이 파일을 안 넣는다(`grep dhcpcd.conf`가
한 줄도 안 잡는다). 그래서 게스트의 dhcpcd는 컴파일 타임 기본 요청 목록만
쓰고, 거기에 `ntp_servers`가 있는지는 이 측정으로 안 갈렸다.

바이너리 자체는 option 42를 안다.

```
define 42 array ipaddress ntp_servers
```

이것은 디코딩 정의이고 요청 목록이 아니다. 즉 option 42가 오면 dhcpcd가
그것을 `new_ntp_servers`라는 이름으로 hook에 넘길 줄은 안다 — 결정 4의 3번이
기대는 계약이 실제로 그 이름이라는 것이 여기서 확인됐다.

처방을 정했다. M2가 `net.zig`의 argv에 `-o ntp_servers`를 더한다. 그 옵션이
있는 것을 확인했다.

```
[-O, --nooption option] [-o, --option option]
getopt: 146bc:de:f:gh:i:j:kl:m:no:pqr:s:t:u:v:wxy:z:...
```

`/etc/dhcpcd.conf`를 initrd에 넣는 길은 안 간다. 그 파일에는
`persistent` · `slaac private` · `require dhcp_server_identifier`처럼 NW가
한 번도 안 재 본 동작이 함께 들어 있어서, 시간을 맞추려다 네트워크의 다른
성질을 바꾸게 된다. 한 단어가 한 파일보다 작다.

## Milestone

넷이다. 각 plan은 그 milestone에 들어갈 때 새로 쓴다.

### TS-M0 — 잰다

부팅으로 답해야 하는 것들이다. 코드는 한 줄도 안 고친다.

1. SLIRP가 `10.0.2.2`로 가는 UDP를 컨테이너에 넘기는가(위험 1). 이것이
   아니오면 여기서 멈추고 사용자에게 묻는다.
2. 지금 게스트의 벽시계가 무엇을 가리키는가. `date`를 찍어서 본다. CMOS를
   읽는지, 읽는다면 QEMU가 주는 호스트 시각인지(확인 1).
3. perl stub SNTP 서버가 도는가. UDP 123을 열 수 있는가(위험 4).
4. dhcpcd가 option 42를 요청 목록에 넣는가(위험 3).
5. 게스트에서 시계를 손으로 뛴 뒤 체인의 나머지가 그대로 도는가(위험 2).
6. `clock_settime`이 게스트에서 실제로 성공하는가. 하네스에서 직접 부른다.

끝 기준: 여섯이 다 답해지고 design에 실측으로 적힌다. 위험 1의 답이 예다.

### TS-M1 — 우리 코드가 시계를 뛴다

- `init/src/sntp.zig` 새 파일. 순수 함수 넷과 fork한 자식 하나.
- `init/src/config.zig`에 `ntp` 키. `off | dhcp | <IPv4>`.
- `init/src/sntp_test.zig`와 `config_test.zig`에 단위 테스트.
- `net/check.sh`에 perl stub과 부팅 A.

끝 기준: 부팅 A가 초록이다. 반사실로 stub을 안 띄운 사본이 그 검사에서
죽는다. 호스트 검사가 era 경계 양쪽과 검증 넷을 본다.

### TS-M2 — DHCP가 알려 준 서버를 쓴다

- `kernel/make_initrd.sh`에 hook `30-tars-ntp`.
- `ntp=dhcp`일 때 `/run/tars/ntp_servers`를 제한 시간 안에서 기다린다.
- 호스트 검사가 hook 3줄을 직접 돌린다.
- `net/check.sh`에 부팅 B(파일을 심은 initrd · 죽은 주소).

끝 기준: 부팅 B가 초록이고, 그 부팅의 셸이 뜨는 시각이 다른 부팅과 같다.
반사실로 파일을 안 심은 사본이 그 검사에서 죽는다.

### TS-M3 — 사람이 읽는 시각이 된다

- `devcontainer/Dockerfile`에 tzdata. 이미지 재빌드.
- `kernel/make_initrd.sh`가 zoneinfo를 넣는다.
- `init/src/config.zig`에 `timezone` 키, `environ.zig`에 `TZ` 항목.
- `environ_test.zig`와 `config_test.zig`에 단위 테스트.
- 부팅 A에 검사 하나 — 같은 순간의 `date -u`와 `date`가 정해진 만큼 벌어진다.

끝 기준: 그 검사가 초록이고 initrd 증가분이 확인 8의 171KB와 맞는다.

## 이 사이클이 증명하게 될 문장

"부팅할 때 네트워크에서 시각을 받아 시계를 맞추고, 그 시각을 사람이 아는
시간대로 보여 준다. 그리고 그 길의 어느 조각이 없어도 부팅은 평소대로
끝난다."

그 이상이 아니다. 시계가 계속 맞는지는 아무도 안 세웠고, 실기계의 공유기가
NTP 서버를 알려 주는지도 게이트가 못 본다.
