# TARS Loopback — Design

접두사: LB

Status: M0 끝났다(2026-09-26) — 실측 1~9. M1 착수 전.

관련 문서: `2026-09-26-tars-wired-nic-design.md`(WN. "덤 — `lo`는 `state=down`이다"가
이 서브프로젝트의 출발점이다) · `2026-09-13-tars-guest-network-design.md`(NW) ·
`2026-09-26-tars-time-discipline-design.md`(TD. `init`은 배관만 한다는 방향) ·
`docs/decisions/feedback_boot_never_blocks.md`.

## 한 줄 요약

게스트가 뜨면 `net` 설정과 무관하게 `lo`가 UP이고, `localhost`와
`아무거나.localhost`가 `127.0.0.1`로 풀린다. `lo`는 `init`이 ioctl 하나로 올리고,
이름은 파일 둘(`/etc/hosts` · `/etc/nsswitch.conf`)과 NSS 모듈 하나
(`libnss_myhostname`)가 푼다.

## 왜 지금인가

WN-M0이 두 부팅 모두에서 `lo drv= state=down`을 봤다. 커널은 `lo`를 만들기만
하고 올리지 않는다. dhcpcd는 `lo`를 안 만지고, WN-M2가 `init`에서 링크를 올리는
코드를 지웠으므로 지금 게스트에서 `lo`를 올리는 주체가 아무도 없다. 그래서
게스트 안에서 `127.0.0.1`로 붙는 일이 전부 실패할 것으로 본다(M0이 확인한다).

2026-09-26에 사용자가 후보(패키지 매니저 · IN 이월 · IPv6 · `lo`) 중에서 이것을
골랐고, 이름 풀이를 범위에 더했다 — "caddy 같은 웹 서버를 쓸 때
`some-domain.localhost`가 풀리면 편하다". IN이 미룬 "부팅 때 뜨는 서비스"의
바닥이기도 하다.

## 착수 전에 읽거나 잰 것 — 부팅은 한 번도 안 했다

### 확인 1 — 보통 리눅스에서 `lo`는 PID 1이나 init 스크립트가 올린다

systemd는 PID 1 안에서 직접 올린다(`src/core/loopback-setup.c`, netlink).
busybox 계열은 init 스크립트의 `ifconfig lo up`이다. 커널이 스스로 올리는 경로는
없다.

### 확인 2 — 링크를 ioctl로 올리는 코드가 이 저장소에 한 번 있었다

`1acf9f6`("Raise the link ourselves and hand the address to dhcpcd")이
`init/src/net.zig`에 `SIOCGIFFLAGS` · `SIOCSIFFLAGS`로 `eth0`의 `IFF_UP`을 세우는
코드를 넣었고, `d144bfd`(WN-M2)가 그 일을 dhcpcd에 넘기며 지웠다. 모양은 그
커밋에서 다시 읽을 수 있다.

### 확인 3 — 게스트 libc는 glibc 2.41이고 이름 풀이 파일이 하나도 없다

sysroot는 Debian 13(trixie)이고 `libc.so.6`이 `GLIBC 2.41-12+deb13u4`다. 2.34부터
`files` · `dns` 백엔드가 `libc.so.6` 안에 있다. sysroot에 `/etc/hosts`도
`/etc/nsswitch.conf`도 없고, `libnss_myhostname.so.2`도 없다(있는 것은
`compat` · `dns` · `files` · `hesiod`).

### 확인 4 — glibc는 `*.localhost`를 스스로 안 푼다

RFC 6761이 `.localhost` 아래 이름을 loopback으로 돌리라고 권하지만 glibc에는 그
규칙이 없다. 보통 배포판에서는 systemd의 NSS 모듈 `myhostname`이 그 일을 한다.
`/etc/hosts`는 와일드카드가 없다.

### 확인 5 — 게스트에 `ip` · `nc` · `curl`이 이미 있다

`kernel/guest_tools.sh`의 UT 층. M0 실측과 M3 판정에 새 도구가 필요 없다. 게스트에
Go로 된 클라이언트는 없다.

### 확인 6 — sysroot는 `apt-get download ...:amd64`로 채운다

`devcontainer/Dockerfile`의 목록에 한 줄을 더하면 sysroot에 들어온다. 다만
`libnss_myhostname`은 glibc가 실행 중에 `dlopen`하는 것이라 `make_initrd.sh`의
의존 추적(ELF `NEEDED`)에 안 잡힌다 — 목록에 이름을 직접 적어야 한다.

## 결정

### 결정 1 — `lo`는 늘 올린다

`net=off`도 포함이다. loopback은 기계 밖으로 나가는 길이 아니라 기계 안의 길이라
"네트워크를 켜지 않는다"와 다른 층이다. `net=off`의 로그 `leaving the network
alone`은 그대로 둔다 — 그 문장이 말하는 네트워크는 바깥이다.

### 결정 2 — `init`이 ioctl로 직접 올린다

`net.zig`에 `pub fn loopbackUp() void`를 둔다. `AF_INET` · `SOCK_DGRAM` 소켓 하나를
열고, `SIOCGIFFLAGS`로 `lo`의 플래그를 읽고, `IFF_UP`을 더해 `SIOCSIFFLAGS`로 쓰고
닫는다. 주소는 안 붙인다 — 커널이 `lo`가 UP이 될 때 `127.0.0.1/8`을 스스로
붙인다고 보고, M0이 그것을 확인한다. 틀리면 이 결정을 다시 연다.

대안은 둘이었다. `ip link set lo up`을 fork/exec하는 것은 TD · WN의 "어려운 일은
도구가"와 결이 같지만 플래그 하나는 어려운 일이 아니다 — 프로세스 하나와 `ip`
(라이브러리 셋)에 대한 의존을 들일 값이 없다. netlink는 systemd가 쓰는 길이지만
메시지를 짜야 해서 길어지고 얻는 것이 없다.

### 결정 3 — 자리는 `main()`의 이른 곳, 설정을 읽기 전이다

결정 1(설정과 무관하다)을 코드 구조가 보장하게 한다. 설정 디스크가 없거나 깨진
부팅에서도 `lo`가 선다. 정확한 줄은 M1 plan이 정한다.

### 결정 4 — 실패해도 부팅을 막지 않고, 조용하지도 않다

성공하면 `tars-init: lo up`, 실패하면 `tars-init: cannot raise lo (errno N)`을
찍고 계속 간다. `feedback_boot_never_blocks.md`와 `net.bringUp`의 태도 그대로다.

### 결정 5 — 이름은 파일 둘과 NSS 모듈 하나가 푼다. `init` 코드는 0줄이다

- `/etc/hosts` — `127.0.0.1 localhost`. NSS를 안 거치는 resolver(정적 Go 등)도 이
  파일은 읽으므로 `localhost` 자체는 그쪽에서도 풀린다.
- `/etc/nsswitch.conf` — `hosts: files myhostname dns`. 파일 → `*.localhost` →
  DNS 순서다.
- `libnss_myhostname.so.2` — Dockerfile이 `libnss-myhostname:amd64`를 받고,
  initrd 목록에 이름을 직접 적는다(확인 6).

두 파일은 저장소에 두고 `make_initrd.sh`가 넣는다. dhcpcd hook(`30-tars-ntp`)과
같은 자리다 — 우리가 쓴 파일이라 원본이 저장소에만 있다. 게스트의 `/`는 tmpfs라
사용자가 부팅 중에 `/etc/hosts`에 줄을 더할 수는 있지만 부팅을 넘지는 않는다.

대안은 둘이었다. 로컬 DNS stub(dnsmasq 류)은 정적 Go까지 덮지만 상주 데몬이 늘고,
dhcpcd hook이 쓰는 `/etc/resolv.conf`와 자리를 다퉈야 한다. `tars.conf`에 이름을
나열해 `init`이 `/etc/hosts`를 쓰는 것은 가장 넓게 통하지만 와일드카드가 아니다.

### 결정 6 — 판정은 기존 체인 둘에 더한다. 새 체인은 없다

`tools` 체인(기본 설정이라 `net=off`, 이미 타이핑한다)과 `net` 체인(`net=dhcp`)에서
`127.0.0.1` · `localhost` · `app.localhost` 셋으로 `nc` 왕복을 본다. 반사실은
둘이다 — `loopbackUp()` 호출을 뺐을 때와 `nsswitch.conf`에서 `myhostname`을 뺐을 때
각각 해당 검사가 빨갛게 되는 것. 판정의 구체적 모양(화면 글자인지 파일인지)은
M3 plan이 정한다.

## Milestone

- LB-M0 — 실측. 코드 0줄. 지금 `lo`의 상태, 손으로 올렸을 때 `127.0.0.1/8`이
  저절로 붙는지, 올리기 전후의 `nc 127.0.0.1`, 지금 `localhost`가 어떻게 실패하는지
  (`net=off` · `net=dhcp` 둘 다), 게스트 `curl`이 `foo.localhost`를 스스로
  처리하는지, `libnss-myhostname:amd64`의 의존 라이브러리, `myhostname`이 `::1`을
  함께 답할 때 IPv6 없는 커널에서 어떻게 보이는지.
- LB-M1 — `lo`를 올린다. `loopbackUp()`과 `main()`의 한 줄.
- LB-M2 — 이름을 푼다. Dockerfile · 파일 둘 · initrd 목록.
- LB-M3 — 게이트. 결정 6.

## 비목표

- NSS를 안 쓰는 프로그램의 `*.localhost` 풀이(정적 Go · musl). 다시 여는 조건 —
  게스트에 Go 클라이언트가 생기고 그것이 이 이름을 필요로 할 때. 그때 로컬 DNS
  stub을 다시 본다. caddy가 서버로서 `foo.localhost` 요청을 받는 일은 이 한계와
  무관하다 — 이름을 푸는 쪽은 클라이언트다.
- IPv6 `::1`. 커널에 IPv6가 없다(TD-M0 실측 2).
- 게스트 hostname. `myhostname`이 풀어 줄 셋째 이름이지만 지금 hostname이 없다.
- `/etc/hosts`를 부팅을 넘어 남기는 일.
- `lo`가 아닌 인터페이스. WN 결정 4대로 dhcpcd의 일이다.

## 위험

### 위험 1 — 커널이 `lo`에 주소를 안 붙인다

그러면 결정 2가 주소까지 붙여야 하고 ioctl이 하나(`SIOCSIFADDR`) 는다. M0이 먼저
본다.

### 위험 2 — `libnss_myhostname`이 끌고 오는 라이브러리가 크다

systemd 소스에서 빌드된 모듈이라 의존이 무엇인지 모른다. M0이 `readelf`로 본다.
크면 결정 5를 다시 연다.

### 위험 3 — `myhostname`의 `::1` 답이 IPv6 없는 커널에서 연결을 늦춘다

`getaddrinfo`가 `::1`을 먼저 주면 클라이언트가 그쪽을 먼저 시도하고 실패한 뒤
`127.0.0.1`로 갈 수 있다. M0에서 `nc`와 `curl`로 본다.

## LB-M0이 실행으로 증명한 것

2026-09-26. plan은 `plans/2026-09-26-tars-loopback-lb-m0.md`. 부팅 A는 `net=off`
(`-nic none`), 부팅 B는 `net=dhcp`(`virtio-net-pci` + SLIRP)다. 두 부팅 모두 게스트
안에서 `lo`를 손으로 올리고, `/etc/hosts` · `/etc/nsswitch.conf` ·
`libnss_myhostname.so.2`를 손으로 놓았다 — M1 · M2가 코드로 할 일을 먼저 손으로 한
것이다.

### 실측 1 — 부팅 직후 `lo`는 `IFF_LOOPBACK`만 있고 주소가 없다

```
LBM0-LOFLAGS 0x8 oper=down
LBM0-LOADDRN 0
```

A · B 같다. `0x8`이 `IFF_LOOPBACK`이고 `0x1`(`IFF_UP`)이 없다. dhcpcd가 뜬 B에서도
같으므로 WN 덤의 관찰 그대로 — 아무도 `lo`를 안 올린다.

### 실측 2 — `lo`가 DOWN일 때 `127.0.0.1`의 실패 모양이 부팅마다 다르다

```
A  LBM0-NC host=127.0.0.1 port=7001 rc=1 got=[] err=[(UNKNOWN) [127.0.0.1] 7001 (?) : Network is unreachable]
B  LBM0-NC host=127.0.0.1 port=7001 rc=1 got=[] err=[]
```

A는 경로가 하나도 없어서 커널이 `connect`를 곧바로 `ENETUNREACH`로 돌려준다. B는
dhcpcd가 기본 경로를 깐 뒤라 `127.0.0.1`이 unreachable로 걸리지 않고, `nc`가 아무
말 없이 `rc=1`로 끝난다. 그래서 M3의 반사실은 에러 문구가 아니라 "받은 글자가
없다"(`got=[]`)로 판정한다.

### 실측 3 — `IFF_UP` 하나로 커널이 `127.0.0.1/8`을 붙인다

```
LBM0-RAISE rc=0
LBM0-LOFLAGS 0x9 oper=unknown
LBM0-LOADDR 1: lo    inet 127.0.0.1/8 scope host lo ...
LBM0-NC host=127.0.0.1 port=7002 rc=0 got=[hello-7002] err=[]
LBM0-NC host=127.1.2.3 port=7003 rc=0 got=[hello-7003] err=[]
```

A · B 같다. 위험 1은 일어나지 않았고, 결정 2대로 M1은 `IFF_UP`만 세운다. `/8`
전체가 로컬이라 `127.1.2.3`도 받는다. `oper=unknown`은 loopback에 carrier가 없어서
커널이 그렇게 두는 것이고 실패가 아니다.

### 실측 4 — 파일이 없으면 `localhost`는 호스트 DNS가 답할 때만 풀린다

```
A  LBM0-GETENT name=localhost rc=2 out=[;]
A  LBM0-NC host=localhost ... err=[localhost: forward host lookup failed: Host name lookup failure : Resource temporarily unavailable]
B  LBM0-GETENT name=localhost rc=0 out=[127.0.0.1       STREAM localhost;...]
B  LBM0-GETENT name=app.localhost rc=2 out=[;]
B  LBM0-NC host=app.localhost ... err=[app.localhost: forward host lookup failed: Unknown server error : Resource temporarily unavailable]
```

A에는 `/etc/resolv.conf`가 없어서 glibc가 물을 곳이 없다. B에서는 dhcpcd hook이 쓴
`nameserver 10.0.2.3`(SLIRP)으로 물었고, SLIRP이 넘긴 호스트 resolver가 `localhost`에
답했다. `app.localhost`에는 답하지 않았다. 즉 지금 `localhost`가 풀리는지는 "네트워크가
켜졌고 호스트 DNS가 답해 주는가"에 달려 있다 — 결정 5의 `/etc/hosts`가 그 의존을
끊는다.

### 실측 5 — 게스트 `curl`(8.14.1)은 `*.localhost`를 resolver 없이 푼다

```
LBM0-CURL name=app.localhost out=[* Host app.localhost:9 was resolved.;* IPv6: ::1;* IPv4: 127.0.0.1;*   Trying 127.0.0.1:9...;]
```

파일도 모듈도 없고 `lo`가 DOWN인 A의 첫 `names`에서 이미 이렇다. curl은 이름 풀이의
증거가 될 수 없다 — M3은 NSS를 거치는 `nc`로 판정한다. `getent`는 M0의 측정 도구로만
썼고 게스트 도구 목록에 넣을지는 M3 plan이 정한다.

### 실측 6 — `libnss_myhostname`은 174,288바이트이고 새로 끌고 오는 것이 없다

`libnss-myhostname 257.13-1~deb13u1`. `NEEDED`는 `libcap.so.2` · `libc.so.6` ·
`ld-linux-x86-64.so.2`이고, 셋 다 지금 initrd에 있다(`lib/x86_64-linux-gnu/libcap.so.2`
는 다른 도구가 이미 끌고 왔다). 위험 2는 일어나지 않았다 — M2가 initrd 목록에 적을
것은 `.so` 한 줄이다. 모듈은 `/lib/x86_64-linux-gnu/`에 놓았을 때 glibc가 찾았다.

### 실측 7 — 파일 둘과 모듈을 놓으면 `.localhost` 아래가 전부 `127.0.0.1`이다

```
LBM0-GETENT name=app.localhost rc=0 out=[127.0.0.1       STREAM localhost;127.0.0.1       DGRAM  ;127.0.0.1       RAW    ;]
LBM0-NC host=app.localhost port=7006 rc=0 got=[hello-7006] err=[]
LBM0-NC host=a.b.localhost port=7007 rc=0 got=[hello-7007] err=[]
LBM0-NC host=localhost.localdomain port=7008 rc=0 got=[hello-7008] err=[]
```

A · B 같다. A에는 DNS가 없으므로 `app.localhost`의 답은 `myhostname`에서 왔다.
`myhostname`은 정식 이름(canonical)을 `localhost`로 준다. `localhost.localdomain`도
답한다.

### 실측 8 — `::1`은 나오지 않는다

`getent ahosts`(`AF_UNSPEC`)의 답에 `::1`이 없다. 커널에 IPv6가 없으면 `myhostname`이
`::1`을 빼는 것으로 보인다. 위험 3은 NSS 쪽에서 일어나지 않는다. curl은 자기가
`::1`을 목록에 올리지만 `127.0.0.1`부터 시도한다(실측 5의 `Trying` 줄).

### 실측 9 — 하네스가 배운 것: 게스트에 `timeout` · `install`이 없다

첫 실행은 `NC` · `GETENT`가 전부 `rc=127`이었다. bash로 짠 타임아웃은 감시자
서브셸의 출력을 닫아야 한다 — 안 닫으면 그 안의 `sleep`이 `$(...)`의 파이프를 붙잡아
명령이 끝나도 타임아웃을 꽉 채운다. M3이 같은 것을 게이트에 쓸 때 그대로 적용된다.
