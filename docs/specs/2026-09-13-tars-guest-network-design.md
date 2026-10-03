# TARS Guest Network — Design

Date: 2026-09-13
Status: 완료(2026-09-14) — M0~M3을 전부 끝냈다. 열두번째 체인이 게이트 안에 있다.

`tars.conf`에 `net=dhcp`를 적은 부팅에서 게스트가 주소를 받고 밖으로 나간다.
기본값은 꺼짐이고, 기존 부팅 아홉과 체인 열하나는 한 밀리초도 안 늘어난다.

## 한 줄 요약

커널에 `CONFIG_NET`을 켜고 virtio-net을 붙인 다음, 인터페이스를 올리는
`ioctl` 한 조각만 우리가 쓰고 주소를 받는 일은 `dhcpcd`에게 맡긴다. 게이트는
바깥 인터넷이 아니라 SLIRP 안에서 닫히는 연결로 판정한다.

## 왜 지금인가

셋이 겹쳤다.

하나. 이 문은 우리가 새로 여는 것이 아니라 앞선 서브프로젝트 둘이 명시적으로
닫아 둔 것이다. RM design의 비목표가 "네트워크. `CONFIG_NET is not set`이고
이 서브프로젝트가 건드리지 않는다"이고, UT design은 실측 6의 제목 자체가
"게스트에 네트워크가 없다"이며 그 사실 하나가 후보 셋을 떨어뜨렸다 —
`tealdeer`(페이지 캐시를 받아야 한다) · Homebrew(UT 비목표 1이 "네트워크와
git을 둘 다 요구하므로 비목표 1 뒤다"라고 적었다) · git의 네트워크 헬퍼
일곱(UT-M3이 그 트리를 통째로 뺐다).

둘. 최종 비전의 나머지 절반이 이 뒤에 있다. 최초 design
(`2026-08-01-tars-boot-foundation-design.md`)의 배경이 적은 최종 비전에
"Linux용 homebrew 스타일 패키지 관리자"와 "Claude Code/Codex 등 AI 코딩 도구
통합"이 들어 있다. 둘 다 네트워크가 전제이므로, 이것이 서지 않으면 그
방향으로 한 걸음도 못 간다.

셋. 얹을 자리가 준비돼 있다. CP가 만든 `tars.conf` 체계 위에 SC가
`shell_config`를 얹었고 SM·SD·BH가 그 위에 또 얹었다. `net=` 키는 그 자리에
그대로 들어간다. 그리고 UT가 게스트 도구를 목록 한 파일로 관리하게 만들어
두어서(`kernel/guest_tools.sh`), 도구를 더하는 일이 그 파일 한 곳을 고치는
일이 됐다.

## 착수 전에 읽어 둔 것 — 소스 확인이고 실측이 아니다

아래 열은 파일을 읽거나 컨테이너에 한 줄짜리 질의를 던져서 안 것이다.
실행으로 재야 하는 것은 NW-M0의 실측 절에 따로 적는다.

### 확인 1 — 커널에 네트워크가 통째로 없다

```
kernel/.config:779:  # CONFIG_NET is not set
```

밖으로 나가는 길이 없는 정도가 아니라 소켓 API 자체가 없다. `AF_UNIX`도
없으므로 같은 기계 안의 프로세스끼리 소켓으로 이야기하는 것도 지금은 안
된다. 이 한 줄이 이 서브프로젝트가 건드리는 첫 자리다.

### 확인 2 — 체인의 장치 결이 이미 둘로 갈려 있다

체인 열하나 중 어디에도 `-net`·`-nic`·`-netdev`가 없다. 커널이 받을 수
없으니 줄 이유가 없었다.

그리고 장치를 주는 방식이 둘로 갈린다. `boot`·`config`·`copy`·`device`·
`hangul`·`input`·`power`·`render`·`terminal`·`tools` 열 개는 virtio
일색이고(`-device virtio-gpu-pci`, `-drive ...,if=virtio`), `machine` 하나만
RM이 실머신을 흉내 내어 q35 + UEFI(OVMF) + xhci USB 키보드 + NVMe로 간다.
네트워킹도 이 갈림을 그대로 따라가면 된다 — 이번 사이클은 virtio 결에만
붙이고, 실머신 NIC는 `machine` 결의 일로 남긴다.

### 확인 3 — 우리 코드에 소켓이 한 번도 안 나온다

`init/src`와 `terminal/src`의 Zig 소스 전부에 `socket`·`AF_INET`·`AF_UNIX`·
`connect(` 중 어느 것도 없다. 게스트 도구 64개에도 네트워크 도구가 하나도
없다 — `ip`도 `ping`도 `curl`도 `dig`도 없다.

그래서 이 서브프로젝트는 기존 코드를 고치는 일이 아니라 없던 층을 새로
얹는 일이다. 깨질 것이 적다는 뜻이기도 하고, 반대로 기댈 선례가 없다는
뜻이기도 하다.

### 확인 4 — 컨테이너의 QEMU가 필요한 것을 다 갖고 있다

```
QEMU emulator version 10.0.11 (Debian 1:10.0.11+ds-0+deb13u1)
netdev 백엔드:  socket stream dgram hubport tap user l2tpv3 vde bridge ...
장치:           virtio-net-pci  e1000  e1000e  ...
```

`user`가 SLIRP다. 요즘 QEMU는 `libslirp`가 별도 패키지로 빠져 있어서 없는
빌드가 실제로 존재하는데, 이 이미지에는 있다. 이것이 없었으면 설계가
통째로 달라졌을 자리라 먼저 확인했다.

### 확인 5 — initrd에 라이브러리가 이미 72개 있고, dhcpcd는 그중 것만 쓴다

initrd를 풀어 세어 보니 `.so`가 72개다. 이 설계에 걸리는 것이 셋이다.

| 라이브러리 | 있나 | 이 일에 무슨 뜻인가 |
|---|---|---|
| `libcrypto.so.3` | 있다 | UT가 넣은 libgit2 사슬이 데려왔다. dhcpcd가 부르는 둘 중 하나다 |
| `libresolv.so.2` | 있다 | 다만 확인 6이 말하는 대로 이것은 DNS의 근거가 아니다 |
| `libssl.so.3` | 없다 | 처음에는 dhcpcd가 요구한다고 적었는데 틀렸다. 아래를 보라 |

⚠ 이 자리에 처음 적었던 것이 틀렸고 결정 10의 측정이 고쳤다. `dhcpcd-base`
패키지가 `libssl3t64`와 `libudev1`을 요구하는 것은 맞지만, 그것은 패키지
의존이지 바이너리 의존이 아니다. `dhcpcd` 바이너리가 실제로 부르는 것은
둘뿐이다.

```
usr/sbin/dhcpcd (388,416 바이트)
  libcrypto.so.3
  libc.so.6
```

둘 다 게스트에 이미 있다. `libssl`과 `libudev`는
`/usr/lib/x86_64-linux-gnu/dhcpcd/dev/udev.so` 플러그인이 부르는 것이고, 그
플러그인은 `dlopen`으로 열리는 선택적 모듈이라 우리가 안 넣으면 안 쓴다.
`copy_lib_deps`가 `DT_NEEDED`만 따라가므로 따라오지도 않는다.

그래서 결정 1이 고른 길의 비용이 예상보다 훨씬 싸다 — 388KB에 새 라이브러리
0개다.

라이브러리는 손으로 적는 것이 아니라 `make_initrd.sh`의 `copy_lib_deps`가
자동 수집한다(UT-M1이 그렇게 바꿨다). 수집 방법이 `ldd`가 아니라 `readelf`인
것이 중요하다 — `ldd`는 대상 바이너리를 실제 동적 로더에 태워서 답을 얻는
것이라 arm64 컨테이너에서 x86_64 바이너리에는 쓸 수 없다. `readelf`는 파일을
읽기만 하므로 아키텍처와 무관한 대신, `PT_INTERP`의 인터프리터와 `DT_NEEDED`의
재귀를 `copy_lib_deps`가 손으로 따라간다.

그래서 도구를 목록에 더하면 라이브러리는 따라온다 — 다만 몇 개가 따라오는지는
NW-M0이 재서 적는다.

도구를 더하기 전에 할 일이 하나 더 있다. `install_tool`은 sysroot에 파일이
없으면 그 자리에서 죽는다. `dhcpcd`가 sysroot에 들어가려면
`devcontainer/Dockerfile`의 `apt-get download` 목록에 `dhcpcd-base:amd64`가
있어야 하고, 그것은 이미지를 다시 굽는 일이다. 위험 7이 이 비용을 다룬다.

### 확인 6 — 이름을 푸는 길은 이미 게스트 안에 있다. 다만 근거가 libresolv가 아니다

처음에는 `libresolv.so.2`가 initrd에 있는 것을 보고 "리졸버가 이미 있으니
DNS는 공짜"라고 적었는데, 그 근거가 틀렸다. 요즘 glibc에서 `libresolv.so.2`는
껍데기에 가깝고, 이름을 푸는 실제 일은 NSS가 한다. 그리고 initrd에는
`libnss_dns.so.2`도 `/etc/nsswitch.conf`도 없다 — `/etc` 아래에 있는 것은
`passwd`와 `group` 둘뿐이다.

그래서 한 걸음 더 파 보니 결론은 그대로인데 이유가 달랐다.

```
GNU C Library (Debian GLIBC 2.41-12+deb13u4) ... version 2.41.
libc.so.6 안의 심볼:  _nss_dns_gethostbyname2_r
                      _nss_files_gethostbyname2_r  (외 셋)
```

glibc 2.34부터 `nss_files`와 `nss_dns`가 `libc.so.6` 안으로 들어갔고, 게스트의
glibc가 2.41이라 그 뒤다. 별도 모듈 파일을 initrd에 넣을 필요가 없다.

이것을 파 본 값이 있었다. 만약 게스트 glibc가 2.34 이전이었다면
`libnss_dns.so.2`를 손으로 넣어야 했을 텐데, 그 파일은 `copy_lib_deps`가
절대 못 잡는다. 확인 5가 적은 대로 그 함수는 `readelf`로 `DT_NEEDED`를
따라가는데, NSS 모듈은 `DT_NEEDED`에 안 적혀 있고 실행 중에 `dlopen`으로
열리기 때문이다.

이것이 가상의 걱정이 아닌 근거가 `make_initrd.sh` 안에 이미 있다. zsh가
정확히 같은 모양이라(zle·complete 같은 기능이 실행 중에 열리는 `.so`다) 그
파일이 zsh 모듈 트리를 따로 복사하고 그 모듈들에 `copy_lib_deps`를 한 번 더
돌린다. UT design이 경고한 실패 모양 그대로이고, 빌드가 아니라 게스트가 그
명령을 처음 칠 때 터지며, 증상이 "이름만 안 풀린다"라 조사하기 나쁘다.

남은 변수는 `/etc/nsswitch.conf`가 없을 때 glibc가 쓰는 내장 기본값이
`hosts: files dns`인가 하나이고, NW-M0의 측정 6이 그것을 확인한다.

### 확인 7 — 벤더 DHCP 클라이언트의 크기를 재 보았다

trixie amd64 기준이다.

| 패키지 | 설치 크기 | 비고 |
|---|---|---|
| `dhcpcd-base` | 495 KB | 바이너리 `usr/sbin/dhcpcd`가 388 KB. 의존이 `libc6` · `libssl3t64` · `libudev1` |
| `busybox` | 875 KB | `udhcpc`를 품고 있지만 도구 수백 개가 함께 온다 |
| `isc-dhcp-client` | 2,884 KB | 가장 크고, 상류에서 이미 EOL이다 |

`udhcpc`와 `dhcpcd5`는 독립 패키지로 없다. 그래서 실질적 후보가
`dhcpcd-base` 하나다.

### 확인 8 — QEMU는 옵션을 안 줘도 NIC를 하나 붙인다

x86 기본 머신은 `-nodefaults`가 없으면 기본 NIC를 붙이고 그것이 `e1000`이다.
커널에 `CONFIG_NET`이 켜지는 순간 이 장치가 모든 체인의 게스트에 나타날 수
있다는 뜻이라 미리 짚어 둔다. 결정 3이 이것을 다룬다.

### 확인 9 — SL이 방금 종료 경로를 고쳤고, 게이트가 그것을 판정한다

SL-M1이 `shutdown()`에 SIGHUP을 더했고 SL-M2가 `grace period expired`를 실패
판정으로 바꿨다. 그래서 이제 종료를 3초 붙잡는 프로세스가 새로 생기면
게이트가 조용히 느려지는 것이 아니라 빨간불이 된다.

`dhcpcd`는 감독 루프에 새로 들어오는 자식이므로 이 자리에 정면으로 걸린다.
NW-M0이 SIGTERM과 SIGHUP에 대한 dhcpcd의 반응을 재야 하는 이유가 이것이다.

### 확인 10 — 감독 루프는 지금 자식 둘을 본다

HD-M2가 만든 구조가 `terminal`과 콘솔 셸을 보고, 죽으면
`restarting {s} in 1s`로 되살린다. `dhcpcd`는 성질이 다른 자식이다 — 화면을
만드는 것도 사람을 상대하는 것도 아니고, 주소를 받고 나면 조용히 살아 있기만
한다. 되살리는 것이 맞는지도 따로 따져야 한다. 결정 9가 이 판단을 M2로
미루는 근거다.

## 결정

### 결정 1 — DHCP 클라이언트를 직접 짜지 않는다. dhcpcd를 쓴다

이것이 이 설계에서 제일 먼저 정해진 것이고, 사용자가 정했다.

착수 논의에서 처음 추천한 것은 직접 구현이었다. 근거는 배움이었다 — DHCP는
커널과 우리 코드의 경계가 유난히 선명한 프로토콜이고(커널은 패킷을 나르기만
하며 상태 기계는 전부 우리 것이다), 이 저장소가 배우려는 것이 바로 그
경계다. 사용자가 난이도와 효용과 품질 차이 셋을 되물었고, 재 보니 추천을
유지할 근거가 약했다.

난이도는 크기가 둘이다. SLIRP를 상대로 주소 하나 받는 최소 구현은 Zig로
250~350줄 정도이고 우리가 이미 짠 `config.zig`(931줄)보다 작다. 실제 기계에서
하루 종일 쓸 물건은 훨씬 크다 — 임대 갱신 타이머(T1 50% · T2 87.5%), 링크
상태 변화 감지(rtnetlink 구독), NAK 처리와 기한 만료 시 반납, RFC 2131의
지수 백오프와 지터, option 121(classless static route), RFC 5227의 중복 주소
검사. `dhcpcd` 바이너리가 388KB인 이유가 이 목록이다.

효용은 성질이 나쁘다. DHCP 클라이언트는 잘 만들어도 아무도 모르고 못 만들면
네트워크가 통째로 막힌다. 성공의 보상이 없고 실패의 비용이 전부인 영역이다.
이 저장소가 직접 짠 것들과 비교하면 차이가 분명하다 — 터미널과 한글 입력기는
품질 차이가 매일 눈에 보이고, 무엇보다 우리가 원하는 모양이 벤더 것과
다르다(macOS 키바인딩 의미론, 세벌식 자판). DHCP는 우리가 원하는 동작이
남들과 글자 그대로 같다.

품질 차이는 상당히 난다. dhcpcd는 20년 넘게 실제 네트워크의 모서리에
부딪히며 자란 코드다. 며칠에 짠 것은 SLIRP와 평범한 공유기에서는 돌지만
이상한 라우터·중복 주소·링크 플랩에서 조용히 실패하고, 그 실패가 "조금
느리다"가 아니라 "아예 안 된다"로 나타난다.

사용자의 결정은 이랬다. "커널 위에 리눅스 배포 환경을 구축하는 것이
목표이긴 해. 그래서 네트워크에 대해서 배우는 것도 좋은데 DHCPD는 20년 넘게
쌓아온 완성된 결과물이기 때문에 이걸 그냥 그대로 사용하는 게 좋을 것 같다.
네트워크는 따로 학습하겠다."

그래서 이 저장소의 원칙이 한 자리 다듬어졌다. "커널이 어디까지 하고
어디부터 우리 코드인가"는 여전히 이 프로젝트의 축이지만, 그것이 "전부 직접
짠다"를 뜻하지는 않는다. 직접 짜는 자리는 배울 값이 있거나 우리가 원하는
모양이 남의 것과 다른 자리다. 기억 파일 `project_write_or_reuse`에 본문을
적는다.

### 결정 2 — 커널은 필요한 것만 켠다. IPv6는 끈다

| 옵션 | 왜 필요한가 |
|---|---|
| `CONFIG_NET` | 네트워크 스택 전체의 뿌리 |
| `CONFIG_INET` | IPv4 |
| `CONFIG_PACKET` | `AF_PACKET`. dhcpcd가 주소를 받기 전에 패킷을 보내야 하는데 주소가 없으면 일반 소켓을 못 쓴다. 이더넷 프레임을 직접 만들어 보내는 통로가 이것이고, 없으면 dhcpcd가 아예 못 돈다 |
| `CONFIG_UNIX` | `AF_UNIX`. dhcpcd의 제어 소켓이 쓴다 |
| `CONFIG_NETDEVICES` | 네트워크 장치 계층 |
| `CONFIG_VIRTIO_NET` | 이번에 쓸 유일한 NIC 드라이버 |

IPv6는 끈다. dhcpcd는 IPv6도 하려 들지만 커널에 없으면 접고 IPv4만 한다.
이번 사이클의 목표 밖이고, 켜면 커널이 커지는 데다 SLIRP의 IPv6 동작이라는
변수가 하나 더 는다.

`netfilter`도 끈다. 방화벽을 켤 이유가 지금 없고, 켜면 게스트가 나가는 길에
우리가 이해 못 하는 규칙이 끼어들 자리가 생긴다.

늘어나는 커널 크기와 빌드 시간은 NW-M0이 잰다. 게이트 시간의 8할이 빌드라
(실측 16) 이 숫자가 게이트에 직접 영향을 준다.

### 결정 3 — virtio-net만 켜는 것이 기존 체인의 격리 수단이다

확인 8이 말한 대로 QEMU는 옵션을 안 줘도 `e1000`을 하나 붙인다. 그런데 우리는
`e1000` 드라이버를 안 켠다. 그래서 게스트가 그 PCI 장치를 보고도 쓸 드라이버가
없어 그냥 넘어간다.

이 성질 덕분에 기존 체인 열 개에 `-net none`을 일일이 더할 필요가 없다.
드라이버를 하나만 고르는 것으로 격리가 된다. 고칠 파일이 열 개 줄어드는
것이고, 더 중요하게는 "체인 하나를 고치는 것을 잊었다"는 실패 경로가 아예
없어진다.

다만 이것은 읽어서 안 것이고 재 본 것이 아니다. NW-M0이 커널에 NET을 켠
상태로 기존 체인 하나를 돌려서 부팅 로그가 정말 안 바뀌는지, 시간이 정말 안
느는지 확인한다. 만약 영향이 있으면 그때 `-net none`을 더하는 쪽으로 돌린다.

### 결정 4 — SLIRP를 쓴다. tap은 안 쓴다

```
-netdev user,id=n0 \
-device virtio-net-pci,netdev=n0 \
```

`user`는 QEMU가 사용자 공간에서 TCP/IP를 흉내 내는 방식이다. 커널 모듈도
`tap` 장치도 특권도 필요 없고, DHCP 서버까지 내장하고 있어서 서버 쪽을 따로
세울 필요가 없다.

`tap`을 안 쓰는 이유가 분명하다. `tap`은 `CAP_NET_ADMIN`이 필요해서
`docker run`에 특권을 더해야 한다. 이 저장소의 게이트는 지금 아무 특권 없이
도는데, 그 성질을 네트워크 하나 때문에 버리지 않는다.

SLIRP의 주소 규칙은 고정이다 — 게스트 10.0.2.15/24, 게이트웨이 10.0.2.2,
DNS 10.0.2.3. 이 값을 코드에 박지는 않는다(dhcpcd가 받아 온다). 다만 게이트
판정을 짤 때 10.0.2.2가 컨테이너 자신을 가리킨다는 사실을 쓴다 — 결정 7이다.

### 결정 5 — `tars.conf`에 `net=` 키. 기본값은 꺼짐

값은 `off`(기본)와 `dhcp` 둘이다.

기본값이 꺼짐인 것이 게이트를 지킨다. 지금 게이트가 부팅 수십 개를 돌고
29분이 걸리는데, 그 부팅이 전부 DHCP 응답을 기다리면 시간이 늘고 잡음도
는다. 기본값을 꺼짐으로 두고 네트워크 체인만 켜면 기존 부팅의 시간이 한
밀리초도 안 는다.

값 셋째(`static:...`)는 이번에 안 만든다. 만들 근거가 아직 없고, 쓸 자리가
생기면 그때 더한다.

### 결정 6 — 링크를 올리는 것만 우리 코드다

`init`이 하는 일은 둘이다. `net=dhcp`를 읽는 것과, 인터페이스를 UP으로
올리는 것(`ioctl(SIOCSIFFLAGS)`)이다. 그 뒤 `dhcpcd`를 띄우고 나면 주소를
받는 것도 라우트를 넣는 것도 `/etc/resolv.conf`를 쓰는 것도 전부 dhcpcd가
한다.

링크를 올리는 것까지 dhcpcd에게 맡길 수도 있다(dhcpcd가 인터페이스를 직접
UP 시킨다). 그래도 우리가 하는 이유는 순서를 우리가 쥐기 위해서다 —
인터페이스가 올라온 것을 확인한 뒤에 dhcpcd를 띄우면, 실패했을 때 어느
단계에서 실패했는지가 로그로 갈린다. 이 저장소가 매번 지불해 온 비용이고
그때마다 값을 했다.

### 결정 7 — 게이트 판정을 SLIRP 안에서 닫는다

이 설계에서 제일 조심할 자리다.

게이트가 "google.com에 붙었다"로 판정하면, 네트워크가 흔들리는 날마다 우리
코드가 멀쩡한데도 빨간불이 된다. 게이트는 같은 입력에 늘 같은 답을 내야
한다. 이 저장소는 이 원칙을 이미 여러 번 지불했다 — SL-M2가 시간이 아니라
로그 줄로 판정한 것도, GA가 `grep -q`의 SIGPIPE 일곱 자리를 고친 것도 같은
이유다.

그래서 판정을 SLIRP 경계 안에서 끝낸다. 방법을 정하려고 컨테이너에 무엇이
있는지 먼저 세어 보았더니 리스너로 쓸 것이 하나도 없었다 — `nc`도 `ncat`도
`socat`도 `python3`도 `busybox`도 없다. bash의 `/dev/tcp`는 클라이언트만 되고
듣지는 못한다.

그래서 리스너를 세우는 대신 QEMU에게 시킨다. SLIRP에 `guestfwd` 옵션이 있다.

```
-netdev user,id=n0,guestfwd=tcp:10.0.2.100:8080-cmd:cat /tmp/nw/payload.txt
```

게스트가 `10.0.2.100:8080`으로 TCP를 걸면 QEMU가 그 연결을 가로채서 지정한
명령을 실행하고 그 출력을 연결에 흘려 넣는다. 듣는 프로세스가 아예 없으므로
도구를 새로 들일 필요가 없고, 컨테이너 밖으로도 한 바이트도 안 나간다.

이 선택에는 덤이 하나 있다. 리스너를 따로 띄우는 방식은 그 프로세스를
언제 죽일지, 죽었는데 체인이 안 죽는 경우를 어떻게 다룰지가 따라붙는데,
`guestfwd`는 QEMU의 수명 안에 있어서 QEMU가 사라지면 함께 사라진다. 체인이
관리할 상태가 하나도 안 는다.

`guestfwd`가 이 QEMU 버전에서 실제로 도는지는 NW-M0의 측정 5가 확인한다.
안 되면 그때 Dockerfile에 `netcat-openbsd`를 더하는 쪽으로 돌린다 — 다만
그것은 위험 7이 말하는 이미지 재빌드 비용을 치르는 일이다.

`ping`으로 판정하지 않는다. SLIRP의 ICMP 지원이 제한적이고, 리눅스에서
비특권 ping은 `net.ipv4.ping_group_range` sysctl에 걸린다. 변수가 둘 느는데
얻는 것은 TCP 판정과 같다.

### 결정 8 — NW-M0은 저장소 파일을 한 글자도 안 바꾼다

SL-M0과 BB-M0과 BH-M0이 전부 이렇게 했고 매번 값을 했다. 측정 하네스는
`/tmp`에 두고 `-v`로 마운트한다. 저장소 파일이 한 번도 안 바뀌므로 되돌리는
것을 잊는 경로가 아예 없다.

커널 `.config`를 고쳐야 재는 항목이 여럿이라 이 결정이 특히 중요하다 —
`.config`는 `kernel/build.sh`가 sha256으로 해시하는 빌드 입력이고
(`build/.tars-build-stamp`), 되돌리는 것을 잊으면 그 뒤 모든 게이트가 다른
커널을 쓴다.

### 결정 9 — dhcpcd의 감독 방식은 M0에서 재고 M2에서 정한다

확인 10이 적은 대로 dhcpcd는 성질이 다른 자식이다. 갈래가 둘이다.

A. 감독 루프에 넣는다. `-B`로 포그라운드에 묶어 두면 기존 구조가 그대로
   잡는다. 죽으면 `restarting {s} in 1s`로 되살아난다.
B. 감독 밖에 둔다. 띄우고 잊는다. 죽어도 안 되살린다.

지금 고르지 않는 이유는 SIGTERM·SIGHUP에 대한 dhcpcd의 반응을 모르기
때문이다. 확인 9가 적은 대로 게이트가 이제 유예 만료를 실패로 판정하므로,
dhcpcd가 SIGHUP에서 안 죽는다면 A를 고르는 순간 게이트가 빨간불이 된다.
NW-M0의 측정이 이 선택을 정한다.

### 결정 10 — 게스트에 넣을 도구는 넷이다. socat은 뺀다

사용자가 `nc`와 `socat`을 검토하라고 해서 후보 전부를 같은 방법으로 쟀다.
`readelf`로 `DT_NEEDED`를 재귀로 따라가는 것이고, `copy_lib_deps`가 쓰는 것과
같은 방법이라야 답이 맞는다. 아래는 게스트에 이미 있는 라이브러리를 뺀
순증가분이다.

| 도구 | 바이너리 | 새로 들어오는 라이브러리 | 순증가 | 넣나 |
|---|---|---|---|---|
| `nc.traditional` | 35 KB | 없음 | 35 KB | 넣는다 |
| `dhcpcd` | 388 KB | 없음 | 388 KB | 넣는다 |
| `nc.openbsd` | 44 KB | libbsd 85 | 129 KB | 안 넣는다 |
| `socat` | 약 400 KB | libwrap 48 · libssl 1,102 | 약 1,550 KB | 안 넣는다 |
| `ip` | 722 KB | libbpf 424 · libelf 약 1,000 · libmnl 27 | 약 2,170 KB | 넣는다 |
| `curl` | 322 KB | libcurl 984 외 열둘 | 약 5,940 KB | 넣는다 |

`nc`는 traditional판을 쓴다. openbsd판보다 싼 이유가 분명하다 — traditional은
`libc.so.6` 하나만 부르고 openbsd는 `libbsd.so.0`을 더 부른다. 35KB에 새
라이브러리가 0이라 사실상 공짜이고, 네트워크가 안 될 때 "포트가 열렸나,
연결이 되나"를 가장 빨리 가르는 도구다.

`socat`은 뺀다. `nc`로 되는 일에 1.5MB를 더 쓰는 것이고, socat의 진짜 값인
양방향 릴레이와 프록시를 이번 층에서 쓸 자리가 없다. 다만 `curl`이 들어오면
`libssl`이 어차피 따라오므로 그때 socat의 추가 비용이 약 450KB로 줄어든다 —
쓸 자리가 생기면 그때가 싸게 넣을 시점이라는 것을 적어 둔다.

`ip`는 대안이 없어서 넣는다. `iproute2` 패키지가 3.7MB에 의존 열둘이라 처음에
비싸 보였는데, 그 대부분은 `tc`·`ss` 같은 다른 바이너리 몫이다. `ip` 하나는
여섯만 부르고 그중 `libselinux`·`libcap`·`libc`가 이미 있다.

`curl`은 5.9MB를 알고 넣기로 사용자가 정했다. 열둘 중 큰 것이 libunistring
1,997 · libssl 1,102 · libldap 401이고, LDAP과 RTMP와 brotli를 우리가 쓸 일은
없는데 `libcurl.so.4`가 전부 `DT_NEEDED`에 적어 두어서 따라온다. 근거는 UT가
libgit2 사슬 열여섯을 "네트워크가 없는 기계의 TLS·Kerberos·SSH 스택"이라며
감수했던 것과 이어진다 — 이제 네트워크가 생기므로 그 사슬이 비로소 값을
한다.

### 결정 11 — `/usr/bin/nc`는 링크를 따로 걸어야 한다

Debian에서 `/usr/bin/nc`는 alternatives가 만드는 심볼릭 링크이고, 실체는
`/usr/bin/nc.traditional`이다. alternatives 링크는 패키지의 postinst가
만드는 것이라 `dpkg -x`로 푼 sysroot에는 없다.

그래서 `make_initrd.sh`에 링크 한 줄이 필요하다.

```bash
ln -sf nc.traditional "$WORKDIR/usr/bin/nc"
```

이것은 새로운 종류의 문제가 아니다. UT-M3이 `pager`에서 글자 그대로 같은
것을 겪었고(`git log`가 `pager`라는 이름을 컴파일 타임에 박아 두는데 그
링크가 sysroot에 없어서 게스트에서 죽었다), `vi`와 `editor`도 같은 자리다.
다른 점은 이번 이름은 우리가 고르는 것이라는 점이다 — 사람이 `nc`라고 칠
것이므로 그 이름을 세운다.

## 비목표 — 이번에 명시적으로 뺄 것

1. 실머신 NIC. 유선(`e1000e`·`igc`)도 무선도 이번 범위 밖이다. 무선은
   firmware 파일과 `wpa_supplicant`가 새로 들어오는 훨씬 큰 일이고, 유선은
   사용자의 실제 노트북이 무엇을 달고 있는지 보고 정할 일이다.
2. IPv6. 결정 2가 근거를 적었다.
3. 방화벽과 `netfilter`.
4. 게스트가 서버 노릇을 하는 것. 이번엔 나가기만 한다. 포트를 여는 것은
   `-netdev user`에서 `hostfwd`가 따로 필요하고, 열 이유가 아직 없다.
5. 패키지 매니저. 이 사이클은 그 전제를 세울 뿐이다.
6. 시간 동기화(NTP). 네트워크가 서면 할 수 있게 되지만 별개의 일이다.
7. `static:` 설정 값. 결정 5가 근거를 적었다.

## Milestone 넷

### NW-M0 — 재기만 한다

재야 할 것이 일곱이다.

1. 커널에 결정 2의 옵션을 켰을 때 늘어나는 빌드 시간과 `bzImage` 크기.
2. 그 커널로 기존 체인 하나를 돌렸을 때 부팅 로그와 시간이 정말 안 바뀌는지
   (결정 3의 근거를 실제로 확인하는 자리다).
3. `dhcpcd-base`를 게스트 목록에 넣었을 때 `copy_lib_deps`가 끌어오는
   라이브러리의 실제 개수와 initrd 크기 증가분. `ip`와 `curl`도 함께 잰다.
4. SIGTERM과 SIGHUP에 대한 dhcpcd의 반응. 결정 9가 이 값으로 갈린다.
5. `guestfwd`가 이 QEMU 버전에서 도는지. 게스트가 `10.0.2.100:8080`에 붙어
   우리가 정한 글자를 받아 오는 것을 실제로 본다.
6. 이름이 풀리는지. 둘로 나뉜다. 하나는 dhcpcd가 `/etc/resolv.conf`를 쓰는
   경로다 — 기본 hook(`20-resolv.conf`)이 셸 스크립트인데 게스트의 환경에서
   도는지, 아니면 hook을 끄고 init이 직접 쓰는 편이 나은지. 다른 하나는
   확인 6이 남긴 변수다 — `/etc/nsswitch.conf`가 없는 지금 상태에서 glibc의
   내장 기본값이 `hosts: files dns`로 동작하는지. 후자가 아니면 그 파일
   한 줄을 initrd에 넣는 것이 M2의 일이 된다.
7. dhcpcd가 쓰기를 요구하는 디렉터리(`/var/db/dhcpcd` 계열)가 무엇이고
   initrd의 tmpfs 위에서 되는지.

끝났다의 기준: 실측 표가 이 문서에 붙는다. 저장소 파일은 안 고친다.

### NW-M1 — 커널이 NIC를 본다

커널 `.config`에 결정 2의 옵션을 넣고, 새 체인의 QEMU 줄에 결정 4의 두 줄을
더한다.

끝났다의 기준: 게스트 로그에 virtio-net이 잡히는 줄이 나온다. 주소는 아직
없고 밖으로도 못 나간다.

⚠ 위 끝 기준이 틀렸고 M1이 실행 중에 고쳤다. 이 커널은 virtio-net에 대해
부팅 로그에 한 줄도 안 찍는다 — M0의 게스트 안에서 `dmesg | grep -i virtio`가
아무것도 못 찾았고 호스트가 받은 직렬 로그에도 없다. 찍히는 것은
`NET: Registered PF_*` 넷뿐인데 그 넷은 NIC가 하나도 없어도 찍힌다(실측 2가
정확히 그 상태에서 같은 줄들을 봤다). 그래서 실제 판정은 `/sys/class/net`에
`eth0`이 있는지다 — sysfs는 커널이 드라이버를 붙이면서 직접 만드는 것이라
게스트에 도구가 하나도 없어도 되고 셸의 `ls` 하나로 읽힌다.

⚠ "새 체인"이 M3의 `net/check.sh`와 겹쳐 보이는 것도 M1이 갈랐다. M1이 그
파일을 만들되 `check.sh`의 `CHAINS` 배열에는 안 넣는다. M3가 그 배열에 한
줄을 더하고 판정을 주소와 바깥 연결까지 늘린다. 이렇게 가르면 체인이 자라는
동안 루트 게이트가 한 초도 안 늘어나서 위험 1을 M3까지 미룰 수 있다.

### NW-M2 — 주소가 붙는다

`config.zig`에 `net` 키, `main.zig`에 링크를 올리는 `ioctl`과 dhcpcd를 띄우는
자리. `guest_tools.sh`에 `dhcpcd`와 `ip`와 `curl`.

끝났다의 기준: `net=dhcp`로 뜬 게스트가 주소를 받고 `/etc/resolv.conf`가
생긴다. 사람이 손으로 `ip addr`를 쳐서 볼 수 있다.

⚠ 2026-09-13에 끝났다. 세 문장이 다 섰고, 설정을 어떻게 줄 것인가는
`debugfs`로 미리 구운 디스크가 답했다(실측 24). 그리고 이 milestone에서
`ioctl`보다 어려웠던 것은 순서였다 — 실측 20을 볼 것.

### NW-M3 — 게이트가 판정한다

열두번째 체인 `net/check.sh`. monitor 포트는 쓰던 대역에서 새 번호를 잡는다.
`check.sh`의 `CHAINS` 배열에 더한다.

끝났다의 기준: 루트 게이트가 열두 체인을 돌고 3/3이다.

⚠ 2026-09-14에 끝났다. 체인이 검사 열하나가 됐고 `CHAINS`의 열두번째다.
M3에서 새로 정한 것이 둘인데 둘 다 "게이트가 거짓을 말하지 않게 하는" 같은
종류다.

하나. 기본 경로를 따로 본다(검사 8). `guestfwd`의 상대 `10.0.2.100`이 게스트
주소 `10.0.2.15/24`와 같은 서브넷이라 그 연결은 기본 경로를 한 번도 안 밟는다
— 검사 9 하나로 "밖으로 나가는 길이 있다"까지 주장하면 그것이 거짓이다.

둘. 판정 글자는 명령줄의 에코와 겹치면 안 된다. `wait_for_screen`이 마지막
프레임이 아니라 로그 전체의 `screen>` 줄을 보므로 우리가 친 명령도 화면이다.
`pgrep -l dhcpcd`를 `dhcpcd`로 판정하면 그 프로세스가 죽어 있어도 초록이
된다. 본문은 `docs/decisions/project_gate_screen_echo.md`에 있다.

## 위험

### 위험 1 — 게이트가 길어진다

커널에 NET을 켜면 빌드가 길어지고, 게이트 시간의 8할이 빌드다(실측 16).
거기에 체인이 하나 늘고 그것을 세 번 돈다.

크기를 미리 말할 수 없어서 NW-M0의 측정 1과 2가 이것을 재는 자리다. 이
게이트의 잡음이 ±3분이라 그보다 작은 증가는 갈렸다고 말하지 않는다는
기준도 그대로 쓴다.

### 위험 2 — dhcpcd가 종료를 붙잡는다

확인 9와 결정 9가 다룬 위험이다. SL-M2가 방금 `grace period expired`를 실패
판정으로 바꿔 놓아서, 여기서 걸리면 증상이 "조금 느려짐"이 아니라 게이트
빨간불이다.

거꾸로 보면 이것이 SL이 남긴 안전장치가 제대로 도는지 보는 첫 시험이기도
하다.

### 위험 3 — initrd가 커진다

지금 크기를 직접 쟀다. 압축된 `kernel/initrd.cpio`가 35,015,430 바이트이고
푼 것이 90,286,592 바이트, 즉 86.1 MiB다. UT-M2가 QEMU 기본 메모리
128MiB에서 tmpfs가 차서 기계가 아예 안 켜지는 것을 겪어 `GUEST_MEM=512`를
넣었으니 지금 여유가 넉넉하지만, 그때 겪은 실패의 증상이 "느려짐"이 아니라
"안 켜짐"이었다는 것을 기억해 둔다.

결정 10이 도구별로 잰 순증가분을 더하면 약 8.5MB다(`curl` 5.9 · `ip` 2.2 ·
`dhcpcd` 0.4 · `nc` 0.04). 푼 크기의 9.9%이고 그 대부분이 `curl` 하나다.

다만 이 숫자는 `.deb`를 푼 자리에서 파일 크기를 더한 것이라 실제와 다를 수
있다. initrd는 gzip으로 묶이므로 압축이 얼마나 먹는지가 빠져 있고, 이미
있는 라이브러리를 두 번 세지 않았는지도 확인해야 한다. NW-M0의 측정 3이
initrd를 실제로 만들어서 before와 after를 잰다.

### 위험 4 — 기본 NIC가 기존 체인에 보인다

결정 3이 "안 보인다"를 전제로 서 있는데 그것은 읽어서 안 것이다. 틀리면
체인 열 개에 `-net none`을 더해야 하고, 그것은 고칠 자리가 열 개로 늘고
"하나를 잊었다"는 실패 경로가 생긴다는 뜻이다.

NW-M0의 측정 2가 착수 전에 이것을 가른다.

### 위험 5 — 게이트 판정이 바깥으로 샌다

결정 7이 막으려는 것이다. 짜다 보면 "그냥 `curl example.com` 한 줄이면
되는데"로 기우는 힘이 생기는데, 그렇게 되면 게이트가 우리 코드가 아니라
그날의 인터넷을 판정하게 된다. 리뷰에서 이 한 줄을 특히 본다.

### 위험 6 — 커널 `.config`를 되돌리는 것을 잊는다

결정 8이 막으려는 것이다. `.config`는 `kernel/build.sh`가 sha256으로 해시하는
빌드 입력이라, NW-M0에서 실험용으로 고쳐 놓고 되돌리는 것을 잊으면 그 뒤
모든 게이트가 다른 커널을 쓴다. 그리고 증상이 조용하다 — 게이트는 그냥
통과한다.

측정 하네스를 `/tmp`에 두고 `-v`로 마운트하는 방식이 이 위험을 구조적으로
없앤다. 사람이 기억해서 막는 것이 아니라 고칠 파일이 아예 저장소 밖에 있게
한다.

### 위험 7 — devcontainer 이미지를 다시 구워야 한다

`install_tool`은 sysroot에 파일이 없으면 그 자리에서 죽는다. 그래서
`dhcpcd`·`ip`·`curl`을 게스트에 넣으려면 `devcontainer/Dockerfile`의
`apt-get download` 목록을 고쳐야 하고, 그러면 그 뒤의 레이어가 전부 다시
돈다.

RM design의 위험 5가 같은 일을 겪고 적어 둔 것이 이 위험의 크기를 말해 준다.
이미지를 다시 굽는 데는 네트워크가 필요하고, apt 패키지의 버전이 그때와
달라질 수 있다. 다만 `ZIG_VERSION=0.16.0`처럼 못으로 박힌 것들은 안 바뀐다.

NW-M0은 이 비용을 안 치른다. 측정하는 컨테이너 안에서 `apt-get download`와
`dpkg -x`로 sysroot에 임시로 풀고, 그 컨테이너는 `--rm`으로 사라진다.
Dockerfile을 정식으로 고치는 것은 NW-M2의 일이다.

## NW-M0이 실행으로 증명한 것

2026-09-13에 쟀다. 저장소의 추적되는 파일은 한 글자도 안 고쳤다 — 실험용
`.config`와 `guest_tools.sh`를 `/tmp/nw/`에 두고 `-v`로 읽기 전용 마운트했다.
게스트는 `-serial stdio`에 FIFO를 물려 두 번 띄웠다.

### 실측 1 — NET을 켜도 커널은 844KB 커지고 빌드는 1분이다

| 무엇 | 값 |
|---|---|
| baseline `bzImage` | 3,642,368 바이트 |
| NET `bzImage` | 4,486,144 바이트 |
| 차이 | +843,776 바이트 (+23.2%) |
| NET을 켜는 재빌드 | 1분 04.79초 |
| NET을 되돌리는 재빌드 | 1분 01.99초 |

두 재빌드 시간이 거의 같은 것에 뜻이 있다. `.config`가 바뀌면 `build.sh`의
해시가 어긋나 `make`가 다시 도는데, 그때 다시 컴파일되는 것은 바뀐 옵션이
건드리는 파일들뿐이라 양방향의 비용이 대칭이다. 위험 1이 걱정한 "게이트가
길어진다"는 이 값으로는 안 보인다 — 게이트는 커널을 회차마다 다시 굽지 않고
입력이 같으면 건너뛰기 때문이다(GL-M1).

`olddefconfig`가 우리 뜻을 전부 존중했다. `kernel/build/.config`에서 확인한
것이 이것이다.

```
CONFIG_NET=y  CONFIG_PACKET=y  CONFIG_UNIX=y  CONFIG_INET=y  CONFIG_VIRTIO_NET=y
# CONFIG_IPV6 is not set
# CONFIG_NETFILTER is not set
```

`CONFIG_IPV6`는 기본값이 `y`라서 의존성을 채우다가 도로 켜질 것을 걱정했는데
안 켜졌다. 결정 2를 그대로 쓸 수 있다.

지우는 정규식도 의도대로 동작했다. `CONFIG_UNIX98_PTYS=y`는 살아남았다 —
이름 뒤에 `=` 또는 ` is not set`이 바로 와야 한다는 조건이 그것을 막는다.

### 실측 2 — 기존 체인은 NET 커널에서 아무것도 안 달라진다. 결정 3이 맞았다

| 무엇 | baseline | NET 커널 |
|---|---|---|
| `device` 체인 판정 | PASS | PASS |
| 걸린 시간(따뜻한 상태) | 11.800초 | 12.183초 |

0.383초 차이는 이 체인의 잡음 안이다. 갈렸다고 말하지 않는다.

중요한 것은 시간이 아니라 커널 로그다. 체인이 통과하는 것과 "커널이 그
장치를 조용히 무시했다"는 다른 말이라 로그를 직접 훑었고, `e1000` ·
`virtio_net` · `eth0` · `Ethernet` · `8139` · `ne2k` 어느 것도 한 줄도 없다.
`virtio`로 걸리는 두 줄은 전부 GPU다.

```
[drm] pci: virtio-gpu-pci detected at 0000:00:03.0
[drm] Initialized virtio_gpu 0.1.0 for 0000:00:03.0 on minor 0
```

대신 NET 스택 자체는 분명히 뜬다.

```
NET: Registered PF_NETLINK/PF_ROUTE protocol family
NET: Registered PF_INET protocol family
TCP established hash table entries: 4096 ...
NET: Registered PF_UNIX/PF_LOCAL protocol family
NET: Registered PF_PACKET protocol family
```

그러니까 결정 3의 전제가 실제로 성립한다 — 스택은 서지만 드라이버가 없어서
QEMU가 붙여 둔 기본 `e1000`이 게스트에 안 나타난다. 기존 체인 열 개에
`-net none`을 더할 필요가 없다.

### 실측 3 — 도구의 비용은 `curl` 하나가 86%다

initrd를 실제로 만들어 쟀다. 앞 넷이 결정 10이 고른 것이다.

| 무엇 | before | after (도구 넷) | 차이 |
|---|---|---|---|
| 압축 | 35,015,430 | 40,516,166 | +5,500,736 (+15.7%) |
| 푼 것 | 90,286,592 | 103,253,504 | +12,966,912 (+14.4%) |
| 라이브러리 수 | 72 | 95 | +23 |

도구별로 귀속하면 이렇다. 크기는 푼 것 기준이고, 라이브러리는 baseline
initrd에 없던 것만 센다.

| 도구 | 바이너리 | 새 라이브러리 | 그 크기 |
|---|---|---|---|
| `dhcpcd` | 388,416 | 0개 | 0 |
| `nc.traditional` | 35,032 | 0개 | 0 |
| `ip` | 721,912 | 3개 | 567,920 |
| `curl` | 321,880 | 20개 | 10,927,904 |

귀속의 합이 13,025,248이고 initrd의 실제 증가분이 13,029,376이다 — 4,128
바이트 차이는 cpio의 패딩이라 귀속이 전체와 맞는다.

`dhcpcd`가 0개인 것이 확인 5의 정정을 실행으로 뒷받침한다. 388KB에 새
라이브러리가 없다.

`curl`이 데려오는 스물은 이것이다.

```
libcurl.so.4      983,720     libgnutls.so.30 2,246,712    libssl.so.3    1,101,760
libnghttp2.so.14  199,152     libp11-kit.so.0 1,705,664    libldap.so.2     400,912
libnghttp3.so.9   173,392     libnettle.so.8    346,216    liblber.so.2      63,824
libidn2.so.0      202,872     libhogweed.so.6   305,144    libsasl2.so.2    109,232
libunistring.so.5 1,996,840   libgmp.so.10      566,080    libbrotlidec     51,376
librtmp.so.1      122,256     libtasn1.so.6      88,064    libbrotlicommon  141,496
libpsl.so.5        75,616     libffi.so.8        47,576
```

그래서 M2가 결정할 것이 하나 생겼다. `curl`을 빼면 initrd 증가분이
13MB에서 1.7MB로 줄고 라이브러리가 23개에서 3개로 준다. 다만 게이트 판정에
HTTP가 필요한지는 실측 5가 따로 답한다.

### 실측 3b — `pgrep`과 `kill`은 공짜다

측정 4가 시그널을 보내려면 이 둘이 필요해서 목록을 여섯으로 늘려 다시 쟀다.
둘 다 procps에서 오고, 게스트에 이미 `ps`가 있어서 `libproc2.so.0`이 이미
initrd에 있다.

| 무엇 | 도구 넷 | 도구 여섯 | 차이 |
|---|---|---|---|
| 압축 | 40,516,166 | 40,535,041 | +18,875 |
| 라이브러리 수 | 95 | 95 | 0 |

`pgrep`이 39,344 바이트, `kill`이 22,840 바이트이고 새 라이브러리가 0개다.
M3의 체인이 "dhcpcd가 살아 있나"를 물으려면 `pgrep`이 있는 편이 낫고, 값이
이 정도면 넣지 않을 이유가 없다.

### 실측 4 — dhcpcd는 SIGTERM에 죽고 SIGHUP에 안 죽는다

| 시그널 | 결과 | 주소 |
|---|---|---|
| SIGTERM | 죽는다 | — |
| SIGHUP | 안 죽는다 | `10.0.2.15/24` 그대로 |

SIGTERM을 보낸 직후 init이 이렇게 찍었다.

```
tars-init: reaped orphan pid 119
```

이 한 줄이 결정 9에 직접 걸린다. dhcpcd는 주소를 받고 나면 `forked to
background`를 찍고 배경으로 내려가는데, 그러면 부모가 죽으면서 PID 1에
재부모화된다. 즉 우리가 감독 목록에 안 넣어도 dhcpcd는 이미 init의 자식이고,
`reapAll()`이 그것을 센다.

그래서 위험 2("dhcpcd가 종료를 붙잡는다")가 해소된다. 종료 경로가 보내는
첫 시그널이 SIGTERM이고 dhcpcd가 거기서 죽으므로, SL-M1이 그 뒤에 더한
SIGHUP까지 갈 일이 없고 `grace period expired`도 안 난다. 결정 9는 A(감독
밖에 두고 재부모화에 맡긴다)로 기울어도 안전하다 — 다만 "죽으면 다시
띄운다"를 원한다면 그것은 별개의 이유로 감독 루프에 넣는 것이다.

### 실측 5 — `guestfwd`가 이 QEMU에서 돈다

`-netdev user,guestfwd=tcp:10.0.2.100:8080-cmd:cat /tmp/nw/payload.txt`로
띄우고 게스트에서 두 가지로 붙었다.

| 방법 | 결과 |
|---|---|
| bash의 `/dev/tcp` | `nwm0-payload-ok` 받음 |
| `nc.traditional -w 5` | `nwm0-payload-ok` 받음 |
| `curl http://10.0.2.100:8080/` | 아무것도 안 나옴 |

`curl`이 조용한 것은 실패가 아니라 예상된 일이다. `guestfwd`가 실행하는 것이
`cat`이라 HTTP 응답 형식이 아니고, `-s`가 그 불평을 삼켰다. 그러니까 실측 3이
남긴 질문 — 게이트 판정에 HTTP가 필요한가 — 의 답은 "필요 없다"다. 결정 7의
판정은 `curl` 없이 선다.

`nc.traditional`은 매달리지 않았다. 상대가 닫으면 바로 나오고 그 뒤의 명령이
정상으로 이어졌다. 다만 stdin을 상대에게 흘리는 성질이 있어 하네스에서는
맨 마지막에만 쳤다.

bash의 `/dev/tcp`가 도구를 하나도 안 쓰고 같은 답을 준다는 것도 값이다 —
M3의 체인이 `nc`조차 없이 판정할 수 있다.

### 실측 6 — 이름은 풀린다. 다만 `/etc/resolv.conf`를 아무도 안 쓴다

확인 6이 남긴 변수가 풀렸고, 대신 그 앞에 다른 구멍이 있었다.

| 언제 | `curl http://deb.debian.org/` |
|---|---|
| dhcpcd가 주소를 받은 직후 | `000` (못 푼다) |
| 손으로 `nameserver 10.0.2.3` 한 줄을 쓴 뒤 | `200 146.75.50.132` |

그러니까 `/etc/nsswitch.conf`가 없어도 glibc의 내장 기본값이 DNS를 본다.
확인 6이 "남은 변수"라고 적은 것이 이 한 줄로 닫혔고, `libnss_dns.so.2`도
`nsswitch.conf`도 initrd에 넣을 필요가 없다.

못 풀던 이유는 리졸버가 아니라 `/etc/resolv.conf`가 아예 없어서였다. 주소를
받은 뒤에도 `/etc`에는 `group`과 `passwd` 둘뿐이었다. dhcpcd가 그 파일을 쓰려고
hook을 부르는데 그 hook이 initrd에 없다.

```
eth0: executing: /usr/lib/dhcpcd/dhcpcd-run-hooks BOUND
script_run: /usr/lib/dhcpcd/dhcpcd-run-hooks: No such file or directory
```

`install_tool`이 바이너리 하나만 복사하기 때문이다. `dhcpcd-base` 패키지는
`dhcpcd-run-hooks`(8,205) · `20-resolv.conf`(6,164) · `30-hostname`(3,764) ·
`50-timesyncd.conf`(1,370) · `/etc/dhcpcd.conf`(1,274)를 함께 담고 있는데
우리 initrd에는 `/usr/sbin/dhcpcd` 하나만 들어간다.

M2의 선택지가 둘이다.

- hook을 넣는다. `dhcpcd-run-hooks`와 `20-resolv.conf` 둘이면 약 14KB다.
  둘 다 POSIX 셸 스크립트이고 게스트에 `/bin/sh`(bash 링크)가 있으니 돈다.
  `make_initrd.sh`가 zsh 모듈 트리에 이미 같은 일을 하고 있어 모양도 낯설지
  않다.
- init이 직접 쓴다. `net=dhcp`일 때 `/etc/resolv.conf`에 SLIRP의 고정
  주소를 한 줄 적는 것이라 코드가 몇 줄이다. 대신 SLIRP 밖(실기계)에서는
  틀린 값이 된다.

지금 아는 것으로는 첫째가 낫다. 실기계에서도 맞고, 우리가 DHCP 옵션을
파싱하지 않아도 된다.

### 실측 7 — dhcpcd는 `/var/lib`에 쓰고 `/run`은 자기가 만든다

| 경로 | 무엇 |
|---|---|
| `/var/lib/dhcpcd/eth0.lease` | 548 바이트. 리스를 여기 쓴다 |
| `/run/dhcpcd/` | dhcpcd가 직접 만들었다 |
| `/var/db/dhcpcd` | 안 쓴다. 10.x는 `/var/lib`다 |

하네스가 `mkdir -p /var/db/dhcpcd /var/lib/dhcpcd /run`을 먼저 쳤다. 그래서
"dhcpcd가 부모 디렉터리까지 만드는가"는 반만 답했다 — `/run`을 준 상태에서
`/run/dhcpcd`는 자기가 만들었다.

지금 initrd에는 `/var`도 `/run`도 아예 없다. 그러니 M2가 그 둘을
`make_initrd.sh`에 더해야 한다. UT-M0이 `/bin`·`/tmp`·`/etc` 셋을 더한 것과
같은 자리다.

설정 파일이 없는 것은 문제가 아니었다. `read_config: /etc/dhcpcd.conf: No such
file or directory`를 두 번 찍고 내장 기본값으로 그냥 진행해서 주소를 받았다.

`no such user dhcpcd` 한 줄도 나왔다. dhcpcd 10.x는 권한 분리(privsep)를
컴파일에 넣고 도는데 전용 계정이 없으면 그것을 접고 계속한다. 게스트의
`/etc/passwd`에 root만 있으니 앞으로도 이 줄은 계속 나온다 — 실패가 아니다.

### 실측 8 — `PATH`에 `/usr/sbin`이 없어서 이름으로는 못 부른다

첫 회차가 여기서 한 번 죽었다.

```
fish: Unknown command: dhcpcd
```

`environ.zig`의 `PATH_ENTRY`가 `/usr/bin:/bin`이고(UT-M0 결정 1), `dhcpcd`는
sysroot에서 `usr/sbin/dhcpcd`다. `install_tool`이 `src:dest` 쌍을 받으므로
M2가 고칠 자리는 둘 중 하나다.

- `guest_tools.sh`에 `usr/sbin/dhcpcd:usr/bin/dhcpcd`로 적는다. 그 파일의
  주석이 "도구는 전부 `/usr/bin`에"라고 이미 말하고 있으니 이쪽이 결이 맞다.
- `PATH`를 넓힌다. 값이 자식 전부에 퍼지므로 더 큰 변경이다.

첫째를 고른다. 실측을 마저 하려고 M0의 하네스는 절대 경로로 쳤다.

### 실측 9 — `ip`는 `usr/bin/ip`가 맞고 `nc`는 sysroot에 없다

`dpkg -x`로 푼 sysroot에서 직접 확인했다.

| 경로 | 있나 |
|---|---|
| `usr/sbin/dhcpcd` | 있다 |
| `usr/bin/ip` | 있다 |
| `sbin/ip` | 없다 |
| `usr/bin/curl` | 있다 |
| `usr/bin/nc.traditional` | 있다 |
| `usr/bin/nc` | 없다 |

결정 11이 읽어서 적은 것이 그대로 맞았다. `nc`는 alternatives가 만드는
링크라 `dpkg -x`에는 안 따라온다.

각 바이너리의 `DT_NEEDED`도 다시 확인했다.

```
dhcpcd          libcrypto.so.3  libc.so.6
curl            libcurl.so.4  libz.so.1  libc.so.6
ip              libselinux.so.1  libbpf.so.1  libelf.so.1  libmnl.so.0  libcap.so.2  libc.so.6
nc.traditional  libc.so.6
```

`curl`의 줄이 짧은 것에 속으면 안 된다. `copy_lib_deps`는 `.so`의
`DT_NEEDED`까지 재귀로 따라가므로(`make_initrd.sh`의 73번 줄이 자기를 다시
부른다) 실제로 들어오는 것은 실측 3이 센 스물이다.

### 실측 10 — `apt-get download`는 의존을 안 따라오므로 M2의 목록이 길다

측정하는 컨테이너에서 `apt-get download dhcpcd-base curl iproute2
netcat-traditional` 넷만 받아 풀었더니 `libcurl.so.4` · `libbpf.so.1` ·
`libelf.so.1` · `libmnl.so.0` 넷이 sysroot에 없었다. `make_initrd.sh`는 그
자리에서 죽는다.

`apt-cache depends --recurse`로 닫힘을 구하니 패키지가 78개였고 그중 71개가
받아졌다(나머지 일곱은 `debconf`·`adduser`처럼 받을 수 없거나 필요 없는
것들이다). 받은 deb의 합이 19,547,036 바이트다.

이것이 위험 7의 크기를 구체적으로 말해 준다. Dockerfile의 `apt-get download`
목록은 언제나 명시적이어야 하므로(그 파일의 59번 줄이 그렇게 적고 있다), M2는
도구 패키지 넷에 더해 라이브러리 패키지 스물 남짓을 손으로 적어야 한다.
`curl`을 빼기로 하면 그 목록이 넷으로 준다.

### M0이 M2에 넘기는 것

| 무엇 | 지금 아는 것 |
|---|---|
| `curl`을 넣나 | 비용이 새 라이브러리 20개에 11MB다. 게이트 판정에는 안 쓴다(실측 5) |
| `/etc/resolv.conf` | dhcpcd hook 둘(약 14KB)을 initrd에 넣는 쪽이 낫다(실측 6) |
| dhcpcd를 감독하나 | 안 해도 안전하다. 재부모화되고 SIGTERM에 죽는다(실측 4) |
| `dhcpcd`의 자리 | `usr/sbin/dhcpcd:usr/bin/dhcpcd`로 넣는다(실측 8) |
| `nc`라는 이름 | `make_initrd.sh`에 링크 한 줄(결정 11, 실측 9) |
| 새로 만들 디렉터리 | `/var/lib/dhcpcd`와 `/run`(실측 7) |
| Dockerfile | 도구 패키지 넷 + 라이브러리 패키지 스물 남짓(실측 10) |

## NW-M1이 실행으로 증명한 것

2026-09-13에 했다. M0과 달리 저장소 파일을 고쳤다 — `kernel/.config`와 새
파일 `net/check.sh` 둘이다.

### 실측 11 — 지금 `.config`는 이미 `olddefconfig`의 고정점이었다

`project_kernel_config`의 규칙 넷째가 "정규화와 의도한 변경을 다른 커밋으로
나눈다"라서 먼저 확인했다. 손대기 전의 `.config`로 한 번 빌드하고
`diff kernel/.config kernel/build/.config`를 걸었더니 비었다.

그래서 정규화 커밋이 따로 필요 없었고, NET 커밋의 diff가 곧 "이번 변경이
커널에 들여온 것"의 완전한 목록이 된다. 그 빌드는 1분 02.60초였고 산출된
`bzImage`가 3,642,368 바이트로 M0이 잰 baseline과 정확히 같았다.

### 실측 12 — 여덟 줄이 451줄이 됐다

최소 편집은 M0과 글자 그대로 같다 — 한 줄(`# CONFIG_NET is not set`)을
지우고 여덟 줄을 더한다. 그것을 빌드하고 `build/.config`를 되접었더니
최종 diff가 이렇다.

```
kernel/.config | 457 +++++++++++++++++++++++++++++++++++++++++++++-
1 file changed, 451 insertions(+), 6 deletions(-)
```

더한 451줄 중 `=y`가 122개, `is not set`이 293개다. 지운 6줄은 전부 설명이
되는 것들이다.

| 지운 줄 | 왜 |
|---|---|
| `# CONFIG_NET is not set` | 우리가 지운 것 |
| `# DRBD disabled because PROC_FS or INET not selected` 주석 블록(3줄) | INET이 켜져서 그 문구가 무의미해졌다. 대신 `# CONFIG_BLK_DEV_DRBD is not set`이 생겼다 |
| `# CONFIG_PPS is not set` | 자리가 옮겨진 것이 아니라 값이 뒤집혔다 — 아래를 보라 |

`CONFIG_PPS`가 `is not set`에서 `=y`가 됐다. `CONFIG_NET_PTP_CLASSIFY`가
켜지면서 PTP가 PPS를 select한다. 우리가 고른 적 없는 하위 시스템 하나가
NET을 켠 대가로 따라 들어온 것이고, 843,776 바이트 증가분의 일부다.

되접고 다시 빌드했을 때 두 번째 빌드는 17.674초였고 `diff`가 비었다 —
고정점에 도달했다. 최종 `bzImage`가 4,486,144 바이트로 M0의 값과 정확히
같다.

### 실측 13 — 결정 3의 격리가 설정 수준에서도 확인된다

M0의 실측 2는 부팅 로그로 확인했다. 이번에는 `olddefconfig`가 만든
`build/.config`를 직접 세어 같은 것을 설정 수준에서 확인했다.

```
CONFIG_NETDEVICES=y  CONFIG_NET_CORE=y  CONFIG_ETHERNET=y
CONFIG_NET_VENDOR_3COM=y ... CONFIG_NET_VENDOR_XILINX=y   (벤더 게이트 60여 개)
```

벤더 줄이 전부 `=y`인 것에 놀랄 필요가 없다. 그것들은 메뉴를 여는 게이트이지
드라이버가 아니다. 실제 드라이버 심볼을 하나씩 물어보면 이렇다.

```
# CONFIG_E1000 is not set     # CONFIG_E1000E is not set   # CONFIG_IGB is not set
# CONFIG_8139CP is not set    # CONFIG_8139TOO is not set  # CONFIG_R8169 is not set
# CONFIG_NE2K_PCI is not set  # CONFIG_PCNET32 is not set  # CONFIG_VMXNET3 is not set
# CONFIG_TUN is not set       # CONFIG_VETH is not set     # CONFIG_MACVLAN is not set
# CONFIG_BRIDGE is not set    # CONFIG_VLAN_8021Q is not set
```

`drivers/net` 아래에서 `=y`인 것은 `CONFIG_VIRTIO_NET` 하나다. 결정 3이
"드라이버를 하나만 고르는 것으로 격리가 된다"고 적은 것이 이 상태를 말한다.

`CONFIG_TUN`이 꺼진 것은 덤이 아니라 결정 4와 맞물린다 — tap을 쓰려면
그것이 필요하고, 안 켜져 있으므로 누군가 나중에 tap으로 바꾸려면 커널부터
고쳐야 한다. 그 마찰이 특권 없는 게이트를 지킨다.

### 실측 14 — 커널 로그로는 NIC를 판정할 수 없다

M1의 끝 기준을 바꾼 근거다. NIC를 물린 게스트를 띄워도 커널이 virtio-net에
대해 찍는 줄이 없다. M0의 게스트 안에서 `dmesg | grep -i -e virtio -e eth0
-e e1000`이 아무것도 못 찾았고, 호스트가 받은 직렬 로그를 다시 훑어도
네트워크 관련 커널 줄은 넷뿐이다.

```
NET: Registered PF_NETLINK/PF_ROUTE protocol family
NET: Registered PF_INET protocol family
NET: Registered PF_UNIX/PF_LOCAL protocol family
NET: Registered PF_PACKET protocol family
```

그 넷은 NIC가 하나도 없어도 찍힌다. 실측 2가 정확히 그 상태(스택은 서고
NIC는 없음)에서 같은 줄들을 봤다.

그래서 `net/check.sh`는 `/sys/class/net`을 본다. sysfs는 커널이 드라이버를
붙이면서 직접 만드는 것이라 게스트에 도구가 하나도 없어도 되고, 셸의 `ls`
하나로 읽힌다. `NET: Registered` 셋은 버리지 않고 보조 증거로 남겼다 —
그것이 없으면 `.config`가 안 먹은 것이라 실패의 원인이 달라진다.

### 실측 15 — 새 체인이 8.954초에 통과하고 반사실이 겨냥한 자리에서 죽는다

`net/check.sh`는 202줄이고 부팅 하나에 타이핑 스물다섯 키다. monitor 포트는
45464를 잡았다.

| 무엇 | 결과 |
|---|---|
| 단독 실행 | PASS, 8.954초 |
| 반사실(NIC 두 줄을 지운 사본) | 종료 코드 1, `FAIL: no eth0 under /sys/class/net` |

반사실이 값진 것은 어디서 죽었는가다. 검사 1(`NET: Registered` 셋)은
통과하고 검사 2에서만 죽었다 — 스택은 NIC와 무관하게 서기 때문이다. 그
둘이 갈리는 것이 이 검사 구조가 실제로 두 가지를 따로 본다는 증거다.

SD-M2와 BH-M2가 "반사실은 겨냥한 검사가 아니라 앞의 검사에 걸린다"를
배웠는데, 이번에는 겨냥한 자리에서 죽었다. 화면이 그것을 그대로 보여 준다.

```
terminal: screen> root@(none) ~# ls /sys/class/net | lo@ | root@(none) ~#
```

`lo`만 있고 `eth0`이 없다. 명령은 정상으로 돌았고 sysfs에 그 장치가 없었을
뿐이다.

반사실은 저장소 파일을 한 글자도 안 바꿨다. `/tmp` 사본을 `-v`로 덮어씌우는
방식이고, SD-M2가 세운 것을 그대로 썼다.

### 실측 16 — 열한 체인이 NET 커널에서 3/3이다

위험 4를 닫는 자리다. 이 milestone이 바꾼 커널은 열한 체인 전부가 부팅하는
커널이라 `device` 하나로는 대변이 안 된다.

| 무엇 | 값 |
|---|---|
| 판정 | 열한 체인 전부 3/3 |
| 걸린 시간 | 29분 49.15초 |
| 직전 기준선(SL-M2 뒤) | 29분 38.52초 |
| 차이 | +10.63초 |
| `skipping make` 횟수 | 32회 (`11 × 3 − 1`과 일치) |

+10.63초는 이 게이트의 잡음(±3분)의 20분의 1이라 갈렸다고 말하지 않는다.
위험 1이 걱정한 "커널에 NET을 켜면 게이트가 길어진다"는 이 숫자로는 안
보인다 — 실측 1이 예상한 대로다. 게이트는 커널을 회차마다 다시 굽지 않고
입력이 같으면 건너뛴다(GL-M1).

`skipping make`가 32인 것이 그 구조가 이번에도 제대로 돌았다는 증거다.
33이면 `clean()`이 지운 자리에서도 건너뛴 것이라 잘못이고, 31 이하면 무언가가
`.config`를 건드리고 있다는 뜻이다.

`net/check.sh`는 아직 `CHAINS` 밖이라 이 29분에 안 들어간다. 체인이 열둘이
되는 것은 M3이고, 그때 이 값이 8.954초 × 3만큼 늘어난다.

### M1이 M2에 넘기는 것

M0이 남긴 표(위의 "M0이 M2에 넘기는 것")가 그대로 유효하고, 여기에 둘을
더한다.

| 무엇 | 지금 아는 것 |
|---|---|
| 체인의 자리 | `net/check.sh`가 이미 있다. M2는 그 파일에 판정을 더하는 것이지 새로 만드는 것이 아니다 |
| QEMU 줄 | `-netdev user,id=n0`에 M3가 `guestfwd=` 옵션을 덧붙인다(결정 7). 지금은 그 자리가 비어 있다 |
| 설정 디스크 | 지금 이 체인은 디스크를 하나도 안 문다. `net=dhcp`를 읽히려면 M2가 줄 하나를 더해야 한다 |

마지막 줄을 M1이 체인을 다 만든 뒤에 알아챘고, 그것이 M2의 첫 걸림돌이 될
자리라 여기 따로 적는다. `net/check.sh`의 QEMU 줄에는 `-drive`가 없다. 그래서
게스트에 `/config/tars.conf`가 아예 없고(`main.zig:147`이 그 경로를 읽는다),
설정으로 `net=dhcp`를 켤 방법이 지금은 없다.

M1에는 그것이 문제가 아니었다. 링크를 올리는 것도 dhcpcd를 띄우는 것도 M1의
일이 아니고, 커널이 장치를 봤는지만 물었기 때문이다.

M2가 고를 길이 둘이다.

- `config/check.sh:1161`처럼 `-drive file="${REPO_ROOT}/out/config.img",
  if=virtio,format=raw` 한 줄을 더한다. 그러면 그 이미지를 굽는 일도 따라온다
  — `config` 체인이 이미 그 방법을 갖고 있다.
- 커널 cmdline으로 준다. `-append`에 값을 얹는 것이라 이미지가 필요 없는데,
  `tars.noconfig`처럼 이미 cmdline을 읽는 자리가 있는지 먼저 확인해야 한다.

값이 하나뿐이고 부팅 사이에 남을 이유도 없으므로 둘째가 더 가벼워 보인다.
다만 결정 5가 `net=`을 `tars.conf`의 키로 정했으므로, cmdline으로 가면
"설정 파일의 키인데 체인은 파일로 안 준다"가 되어 게이트가 증명하는 것과
사람이 쓰는 길이 갈린다. 그 갈림을 M2가 의식하고 정해야 한다.

⚠ M2가 정했다. 갈래 둘 중 하나가 아니라 제3의 길이고, 그 길이 갈림 자체를
없앴다 — 아래 실측 24를 볼 것. 요지는 `debugfs`가 마운트 없이 ext2 이미지에
파일을 쓸 수 있다는 것이고, 그래서 `net/make_disk.sh`가 `net=dhcp` 한 줄을
담은 디스크를 미리 굽는다. 부팅은 하나로 유지되고 타이핑도 없으며 게이트는
`tars.conf`의 키를 실제로 읽는다.

## NW-M2가 실행으로 증명한 것

### 실측 17 — Dockerfile이 스물넷 늘고 이미지는 42초에 다시 구워졌다

착수 전에 SONAME → `.deb` 대응을 컨테이너 안에서 직접 구했다. 짐작으로
적으면 `make_initrd.sh`가 빌드 때 SONAME을 찍고 죽는데, 그 실패는 싸지만
목록을 한 번에 못 맞추면 이미지를 여러 번 굽게 된다.

`apt-cache depends --recurse`로 구한 닫힘이 118개이고 그중 `.deb`로 실제
받아진 것이 74개다(나머지는 가상 패키지다). 그 74개가 담은 `.so` 470개에서
M0이 센 SONAME 스물둘을 찾으니 빈칸이 하나도 없었다.

| 무엇 | 값 |
|---|---|
| 더한 도구 패키지 | 넷 (`dhcpcd-base` · `iproute2` · `netcat-traditional` · `curl`) |
| 더한 라이브러리 패키지 | 스물 |
| 이미지 재빌드 | 42.169초 |
| sysroot 확인 | 여덟 파일 전부 있음(도구 여섯 + hook 둘) |

SONAME 스물둘이 패키지 스물인 것은 둘이 겹치기 때문이다 — `libldap2`가
`libldap.so.2`와 `liblber.so.2`를, `libbrotli1`이 `libbrotlidec.so.1`과
`libbrotlicommon.so.1`을 함께 담는다.

`procps`는 안 더했다. 이미 있었고(UT-M1이 `ps`·`top` 때문에 받았다) 층 5가
쓰는 `pgrep`·`kill`이 같은 패키지에서 온다 — 실측 3b가 "공짜"라고 한 것이
목록 수준에서도 참이었다.

위험 7이 걱정한 것보다 쌌다. 42초는 이 저장소의 다른 어떤 단계보다도 짧다.

### 실측 18 — initrd가 M0의 예상과 바이트 수준에서 맞았다

M0은 도구를 sysroot에 임시로 넣어 쟀고, M2는 그것을 정식 경로로 넣었다.
두 값이 갈리면 임시로 재는 방법이 못 믿을 것이 되므로 대조할 값이 있다.

| 무엇 | before | after | 증가 | M0의 예상(실측 3) |
|---|---|---|---|---|
| 압축 | 35,015,659 | 40,538,221 | +5,522,562 | +5.5MB |
| 푼 것 | — | 103,257,440 | +13MB | 103MB |
| 라이브러리 수 | 72 | 95 | +23 | 95개 |

셋 다 맞았다. 도구를 저울질하는 데 `dpkg -x` + `cp -an`으로 sysroot에 임시로
넣는 방법이 정식 경로와 같은 값을 준다는 뜻이고, 그것이 M0이 이미지를
안 굽고도 결정을 내릴 수 있었던 근거다.

`nc` 링크가 M0에 없던 하나다. `usr/bin/nc` → `nc.traditional`이고
`make_initrd.sh`의 한 줄이 만든다 — `pager`·`vi`·`editor`와 같은 자리다.

### 실측 19 — 우리 코드가 하는 일은 로그 두 줄이다

`net.zig`가 165줄이고 그중 주석이 100줄 남짓이다. 실제로 하는 일은 셋이다.

```
tars-init: net link eth0 is up
tars-init: started dhcpcd on eth0 (pid 34)
```

그 뒤는 전부 dhcpcd가 말한다.

```
eth0: soliciting a DHCP lease
eth0: offered 10.0.2.15 from 10.0.2.2
eth0: probing address 10.0.2.15/24
eth0: leased 10.0.2.15 for 86400 seconds
eth0: adding route to 10.0.2.0/24
eth0: adding default route via 10.0.2.2
tars-init: reaped orphan pid 34
```

마지막 줄이 결정 9의 갈래 A가 실제로 성립한다는 증거다. dhcpcd는 배경으로
내려가면서 PID 1에 재부모화되고, 감독 목록에 없는데도 init이 그것을 거둔다.

`net=off`인 부팅도 침묵하지 않는다.

```
tars-init: net=off, leaving the network alone
```

`config` 체인의 부팅 아홉이 전부 이 줄을 찍는다. 침묵은 "안 켰다"와
"켜려다 실패했다"를 못 가르고, 이 저장소가 그 값을 여러 번 지불했다.

### 실측 20 — `started dhcpcd`와 `soliciting` 사이에 간격이 있다

plan에 없던 것이고, 그것이 이 체인의 1회차를 죽였다.

init이 `started dhcpcd`를 찍은 것이 시리얼 로그의 256번째 줄이고 dhcpcd가
실제로 DHCP를 요청한 것(`soliciting a DHCP lease`)이 3745번째 줄이다. 그
사이 3500줄이 전부 터미널의 렌더 로그다. 즉 체인이 프롬프트를 보자마자
`ip`를 치면 언제나 너무 이르다.

1회차의 화면이 이렇게 생겼다.

```
terminal: screen> root@(none) ~# ls /sys/class/net | eth0@  lo@ | root@(none) ~# ip -4 addr show eth0 | root@(none) ~#
```

`ip`가 출력을 한 줄도 안 냈다. 이것이 진단을 흐린 자리다 — iproute2는
family 필터(`-4`)를 걸면 그 family의 주소가 없는 인터페이스를 링크 줄조차
안 찍고 통째로 생략한다. 에러도 아니고 빈 출력이라 "명령이 실패했다"와
"아직 주소가 없다"가 화면에서 구별되지 않았다.

라이브러리를 먼저 의심했지만 아니었다. `ip`의 `DT_NEEDED` 여섯
(`libselinux`·`libbpf`·`libelf`·`libmnl`·`libcap`·`libc`)이 전부 initrd에
있었다. 원인은 순서였고, 시리얼 로그의 줄 번호가 그것을 말했다.

그래서 검사를 하나 더 세웠다. 검사 5가 시리얼 로그에서 `eth0: leased`를
기다리고, 검사 6이 화면에서 같은 사실을 사람의 눈으로 다시 확인한다. 둘이
갈리는 것에 값이 있다 — 앞은 dhcpcd의 말이고 뒤는 커널이 실제로 그 주소를
인터페이스에 갖고 있는가다.

### 실측 21 — 체인이 여덟 검사에 17.082초다

| 무엇 | 결과 |
|---|---|
| 단독 실행 | PASS, 17.082초 |
| M1의 값 | 8.954초 |
| 차이 | +8.128초 |

늘어난 것이 셋이다 — 디스크 굽기 하나, 리스 대기(실측 20), 타이핑 마흔 키.
검사는 넷에서 여덟이 됐다.

`grace period expired`가 안 나왔다. 위험 2가 닫히는 자리이고, M0의 실측 4가
컨테이너 밖에서 쟀던 "dhcpcd는 SIGTERM에 죽는다"가 실제 부팅에서 확인됐다.
이 게스트에는 `Child` 배열 밖의 프로세스가 하나 있는데도 종료가 안 늘어졌다.

### 실측 22 — 반사실 둘이 각각 겨냥한 자리에서 죽었다

| 반사실 | 종료 코드 | 죽은 자리 |
|---|---|---|
| 디스크에 `net=off`를 적는다 | 1 | 검사 3의 둘째 — `the config disk did not turn the network on` |
| hook 둘을 안 넣는다 | 1 | 검사 7 — `the dhcpcd hook never wrote /etc/resolv.conf` |

첫째에서 검사 1·2(스택과 `eth0`)는 통과했다. 커널은 설정과 무관하기
때문이다. 마커 목록이 그 갈림을 그대로 보여 준다 — `loaded /config/tars.conf`는
found이고 `net link eth0 is up`과 `started dhcpcd on eth0`이 MISSING이다.
우리 코드가 설정을 실제로 본다는 뜻이다.

둘째에서 검사 6(주소)까지 전부 통과했다. hook이 없어도 주소는 붙는다는 M0의
실측 6이 게이트 안에서 재확인됐고, 그 둘이 갈리는 것이 이 반사실의 값 전부다.

SD-M2와 BH-M2가 "반사실은 겨냥한 검사가 아니라 앞의 검사에 걸린다"를
배웠는데, M1에 이어 M2에서도 겨냥한 자리에 걸렸다.

함정이 하나 있었다. `/tmp` 사본에 실행 권한이 없으면 체인이 `./make_disk.sh`
에서 죽고, 그 증상(`FAIL: config disk build failed`)이 우리가 보려던 것과
아무 관계가 없다. 사본을 만들면 `chmod +x`를 함께 친다 — SD-M2가 세운
마운트 방식에 붙는 셋째 주의다.

### 실측 23 — 기존 체인 둘이 그대로다

이 milestone은 커널을 안 고쳤지만 initrd를 13MB 키웠고, `main.zig`의 로그
줄을 넓혔고, 씨앗 `tars.conf`에 줄 넷을 더했다. 셋 다 다른 체인에 닿는다.

| 체인 | 결과 | 시간 | 직전 값 |
|---|---|---|---|
| `config` | PASS | 2분 10.01초 | 2분 06.87초 (BB-M2 뒤) |
| `tools` | PASS | 34.818초 | — |

`config`가 가장 예민한 자리다. 부팅 아홉에 화면 판정이 수십이고, 씨앗
`tars.conf`가 길어지면 1차 부팅의 판정이 화면 밖으로 밀린다 — SD-M2와
BH-M2가 정확히 그 자리를 두 번 밀었다. `net` 블록 넉 줄은 안 밀었다.

`tools`는 `guest_tools.sh`를 source해서 목록을 검사하므로 층 5의 여섯 줄이
자동으로 그 검사에 들어갔다. UT-M1이 그렇게 만든 값이 여기서 다시 나왔다 —
목록에 줄을 더하는 것 말고 한 것이 없는데 게이트가 그 여섯을 본다.

### 실측 24 — `debugfs`가 design의 갈림을 없앴다

M1이 M2에 넘긴 표의 마지막 줄이 갈래 둘을 적고 어느 쪽도 좋지 않다고 했다.
설정 디스크를 굽고 게스트에서 타이핑하면 부팅이 둘이 되고, 커널 cmdline으로
주면 `tars.conf`의 키인데 게이트가 그 파일을 한 번도 안 읽는다.

컨테이너에 `debugfs`가 이미 있다. `mkfs.ext2`와 같은 패키지(e2fsprogs)이고
`config/make_disk.sh`가 그것을 이미 쓰고 있었다.

```
$ debugfs -w -R "write /tmp/c.conf tars.conf" t.img
Allocated inode: 12
$ debugfs -R "cat tars.conf" t.img
net=dhcp
```

마운트도 loop 장치도 특권도 필요 없다. 이미지 파일을 파일로 읽고 쓸 뿐이다 —
그래서 이 게이트가 아무 특권 없이 도는 성질을 안 버린다(결정 4가 tap을
버린 것과 같은 기준이다).

| 무엇 | cmdline | 디스크 + 타이핑 | 디스크 + `debugfs` |
|---|---|---|---|
| 부팅 수 | 하나 | 둘 | 하나 |
| 타이핑 | 없음 | 백 키 남짓 | 없음 |
| `tars.conf`의 키를 읽는가 | 아니다 | 그렇다 | 그렇다 |

라벨은 `tars-net`이다. `storage.zig`의 `LABEL_PREFIX`가 `tars-`라 접두사만
맞으면 잡힌다(RM-M2가 그렇게 바꿨다).

### 실측 25 — initrd가 13MB 커졌는데 게이트는 그대로다

| 무엇 | 값 |
|---|---|
| 판정 | 열한 체인 전부 3/3 |
| 걸린 시간 | 29분 53.84초 |
| 직전 기준선(NW-M1 뒤) | 29분 49.15초 |
| 차이 | +4.69초 |
| `skipping make` 횟수 | 32회 (`11 × 3 − 1`과 일치) |

+4.69초는 이 게이트의 잡음(±3분)의 38분의 1이다. 위험 3이 걱정한 것 —
initrd가 커지면 `make_initrd.sh`의 gzip이 회차마다 길어지고 게스트의 tmpfs가
그만큼 찬다 — 는 이 숫자로 안 보인다.

`GUEST_MEM=512`에도 여유가 남았다. 푼 것이 90MB에서 103MB가 됐는데 열한 체인
어디에서도 UT-M2가 겪은 증상(`Kernel panic - System is deadlocked on memory`)이
안 나왔다. 그 실패의 증상이 "느려짐"이 아니라 "안 켜짐"이라는 것을 기억해
둘 것 — 다음에 initrd를 크게 키우는 사람이 볼 자리다.

`net/check.sh`는 여전히 `CHAINS` 밖이라 이 29분에 안 들어간다. 체인이 열둘이
되는 것은 M3이고, 그때 이 값이 17.082초 × 3만큼 늘어난다.

## NW-M3가 실행으로 증명한 것

### 실측 26 — 검사 셋이 1회차에 섰고 체인이 22.911초다

| 무엇 | 값 |
|---|---|
| 검사 8 (기본 경로) | `default via 10.0.2.2` |
| 검사 9 (TCP 연결) | `nwm3-outbound-ok` — QEMU가 흘려 넣은 글자 그대로 |
| 검사 10 (dhcpcd 생존) | `dhcpcd-alive=1` |
| 체인 단독 | 22.911초 (M3 전 같은 기계에서 19.441초) |

+3.470초가 타이핑 78키를 더한 값이다. 한 키에 0.3초를 쉬던 시절이라면
23초가 늘었을 텐데 `type_keys`가 로그가 자라는 것을 보고 다음 키로 넘어가서
(GL-M2) 실제로는 그 7분의 1이다. M2의 17.082초와 이번 19.441초의 차이는
증분 빌드 상태 차이이고 M3가 더한 것이 아니다.

`dhcpcd-alive`의 값이 1이었다. dhcpcd 10의 특권 분리 자식이 따로 안
잡힌다는 뜻인데, 그 수를 검사에 박지는 않았다(`[1-9]`로 본다) — 우리가 고른
값이 아니라 dhcpcd의 내부 사정이라 올리는 날 이유 없이 빨개진다.

### 실측 27 — 반사실이 겨냥한 검사에서 죽었고, 실패가 조용했다

`guestfwd`가 듣는 포트만 8080에서 18080으로 옮긴 사본을 `-v`로 덮어씌웠다.
게스트는 여전히 8080으로 건다.

```
the guest has a default route via 10.0.2.2
FAIL: the guest could not open a TCP connection through SLIRP
```

앞 검사 여덟이 전부 초록인 채로 검사 9에서만 죽었다. SL-M2의 반사실이
겨냥한 검사가 아니라 앞의 검사에 걸렸던 것과 반대이고, 이번에는 새로 넣은
검사가 겨냥한 자리를 정확히 본다는 뜻이다.

그리고 배운 것이 하나 더 있다. 연결이 안 될 때 `nc`가 아무 말도 안 한다 —
화면의 마지막이 빈 줄과 프롬프트뿐이다. SLIRP이 RST를 안 주고 그냥 버려서
`-w 5`의 타임아웃으로 끝나기 때문이다. 화면만 보면 "연결이 실패했다"와
"명령을 안 쳤다"가 구별되지 않는다. 그래서 이 검사의 판정 글자가 `nc`의
반응이 아니라 QEMU가 흘려 넣는 payload인 것이 맞다 — 그 글자는 연결이 실제로
열렸을 때만 화면에 생긴다.

검사 8과 10의 반사실은 안 했고 이유가 각각 있다. 검사 8을 겨냥하려면
SLIRP의 서브넷을 옮겨야 하는데(`-netdev user,net=10.0.3.0/24`) 그러면 게스트
주소도 함께 바뀌어 검사 5(`eth0: leased 10.0.2.15`)가 먼저 죽는다 — SL-M2
실측 3이 겪은 "겨냥한 검사가 아니라 앞의 검사에 걸린다"와 같은 모양이다.
검사 10을 겨냥하려면 게스트에서 dhcpcd를 죽여야 하는데, 그것은 검사를
바꾸는 것이 아니라 게스트를 바꾸는 것이라 반사실의 모양이 아니다.

### 실측 28 — 게이트가 열둘이 되고 30분 57.86초다

| 무엇 | 값 |
|---|---|
| 판정 | 열두 체인 전부 3/3 |
| 걸린 시간 | 30분 57.86초 |
| 직전 기준선(NW-M2 뒤, 열한 체인) | 29분 53.84초 |
| 차이 | +1분 04.02초 |
| `skipping make` 횟수 | 35회 (`12 × 3 − 1`과 일치) |

+1분 04.02초가 설명되는 값이다. 체인 단독이 22.911초이고 게이트가 그것을 세
번 도니 68.7초인데, 실제 증가분이 64.02초로 그 안에 든다. 이 게이트의 잡음이
±3분이라 이 정도 차이를 "정확히 맞았다"고 말할 수는 없고, 말할 수 있는 것은
"설명되지 않는 시간이 없다"까지다.

`skipping make`가 35회인 것이 커널을 회차마다 다시 굽지 않는다는 증거다
(GL-M1). 체인이 하나 늘면 이 수도 셋 는다 — 32에서 35가 됐다. 34였다면
clean이 지운 자리를 한 번 더 빌드한 것이고, 36이었다면 지운 자리에서도
건너뛴 것이라 둘 다 잘못이다.

이것으로 위험 1이 닫혔다. NET 커널(M1) · 13MB 큰 initrd(M2) · 체인 하나(M3)를
전부 더하고도 게이트가 29분 38.52초(SL-M2 뒤)에서 30분 57.86초가 됐다.
셋 중 시간을 실제로 더한 것은 체인 하나뿐이다.

### M2가 M3에 넘기는 것

| 무엇 | 지금 아는 것 |
|---|---|
| `CHAINS` 배열 | `net`을 더하면 체인이 열둘이 된다. 게이트가 17.082초 × 3만큼 는다 |
| `guestfwd` | 실측 5가 이 QEMU에서 돈다고 쟀다. `-netdev user,id=n0`에 옵션을 덧붙인다 |
| 판정 도구 | `nc`가 게스트에 있고 이름도 선다. bash의 `/dev/tcp`도 된다 |
| `curl` | 들어갔지만 체인이 한 번도 안 친다. M3도 안 쳐도 된다(실측 5) |
| 리스 대기 | 검사 5가 그 자리다. 바깥 연결을 거는 판정은 그 뒤에 온다 |
| dhcpcd 감시 | `pgrep`·`kill`이 게스트에 있다. "살아 있나"를 물을 수 있다 |
