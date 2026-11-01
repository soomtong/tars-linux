---
name: project_guest_network
description: 게스트 네트워크 — tars.conf의 net=dhcp 한 줄로 게스트가 10.0.2.15를 받고 밖으로 TCP를 연다(NW-M0~M3, 2026-09-13~14). 기본값은 꺼짐. 주소 · 경로 · resolv.conf는 전부 dhcpcd가 쓴다. 게이트는 인터넷에 안 나가고 QEMU guestfwd가 상대 역할을 한다. 함정 — 커널 로그로 NIC를 판정할 수 없다 · ip -4는 주소가 없으면 침묵한다 · started dhcpcd와 실제 요청 사이에 간격이 있다 · 연결 실패가 조용하다
metadata:
  type: project
---

# 게스트 네트워크 — `net=dhcp` 한 줄과 그 경계

Guest Network(NW-M0~M3, 2026-09-13~14). `tars.conf`에 `net=dhcp`를 적은
부팅에서 게스트가 `10.0.2.15`를 받고 밖으로 TCP를 연다. 기본값은 꺼짐이고,
그 줄이 없는 부팅은 M0 이전과 한 바이트도 다르지 않다
([[feedback_network_default_stays_off]]).

## 우리 코드가 하는 일은 dhcpcd를 띄우는 것뿐이다

NW 때 `init/src/net.zig`는 링크를 UP으로 올리는 `ioctl` 하나와 dhcpcd를 띄우는
`fork`/`execve` 하나였고, 로그 두 줄(`net link eth0 is up` · `started dhcpcd on
eth0`)이 그 경계였다. 둘 다 그 뒤에 바뀌었다 — WN-M2가 링크 조작을 뺐다
(인터페이스를 고르고 올리는 것은 dhcpcd다. `init`이 링크를 만지면 `net` · `nic`
체인이 `net link` 줄로 잡는다), DS가 dhcpcd를 감독 목록에 넣었다(`-B`로 배경을
막아 PID 1이 쥔 pid가 곧 dhcpcd다 — [[project_daemon_supervision]]). 지금 모양은
`docs/guides/key-files.md`의 `net.zig` 항목이고 로그는 `tars-init: dhcpcd joins the
services, it picks the interface`(`net.zig`)와 `tars-init: started service dhcpcd
(pid N)`(`net/check.sh`가 본다)다.

주소도 기본 경로도 `/etc/resolv.conf`도 전부 dhcpcd가 쓴다. DHCP 상태 기계를
직접 짜지 않은 이유는 [[project_write_or_reuse]]에 있다 — 배울 값이 있거나
원하는 모양이 남의 것과 다른 자리에만 직접 쓴다. DHCP는 둘 다 아니었다.

## 게이트는 인터넷에 안 나간다

이것이 이 서브프로젝트에서 제일 많이 지불한 결정이다. 게이트는 같은 입력에
늘 같은 답을 내야 하는데, `google.com`으로 판정하면 회선이 흔들리는 날마다
코드가 멀쩡한데도 빨간불이 된다.

그래서 QEMU에게 상대 역할을 시킨다 — `-netdev user,…,guestfwd=tcp:10.0.2.100:8080-cmd:cat
<파일>`(measurements 41). 게스트가 그 주소에 붙으면 QEMU가 파일을 흘려 넣고, 듣는
프로세스가 없으니 체인이 관리할 상태가 안 늘며 컨테이너 밖으로 한 바이트도 안 나간다.

대신 그 연결이 증명하지 않는 것이 하나 있다. `10.0.2.100`은 게스트
`10.0.2.15/24`와 같은 서브넷이라 기본 경로를 안 밟는다 — 그래서 경로는
`ip -4 route show`로 따로 본다(`default via 10.0.2.2`). 둘을 더해도
"인터넷에 나간다"는 아니고, 그것은 이 게이트가 일부러 안 보는 것이다.

## 도구는 실제 의존으로 저울질한다

`dhcpcd-base` 패키지가 요구하는 것과 `dhcpcd` 바이너리의 `DT_NEEDED`가 다르다 —
measurements 40과 [[project_measuring_tool_cost]]. 그래서 dhcpcd의 비용이 388KB에 새
라이브러리 0개다. 같은 저울에서 `curl`이 13MB 중 86%였고 게이트 판정에는 필요
없다는 것도 실측으로 알았지만(`guestfwd`가 실행하는 것이 `cat`이라 HTTP가 아니다)
사용자가 값을 알고 넣기로 정했다 — 사람이 쓰는 물건이기 때문이다.

## 이 서브프로젝트가 남긴 함정 넷

1. 커널 로그로 NIC를 판정할 수 없다. 이 커널은 virtio-net에 대해 한 줄도 안
   찍고, 찍히는 `NET: Registered PF_*` 넷은 NIC가 없어도 찍힌다. 판정은
   `/sys/class/net`에 `eth0`이 있는지다 — sysfs는 커널이 직접 만든다.
2. `ip -4`는 주소가 없으면 빈 출력이다. family 필터를 걸면 그 family의 주소가
   없는 인터페이스를 링크 줄조차 안 찍는다 — 에러가 아니라 침묵이라 "명령이
   실패했다"와 "아직 주소가 없다"가 화면에서 안 갈린다.
3. `started dhcpcd`와 실제 DHCP 요청 사이에 간격이 있다. 시리얼 로그에서
   앞이 256번째 줄, 뒤가 3745번째 줄이었다. 프롬프트를 보자마자 치면 언제나
   너무 이르다 — 체인의 검사 5가 그 대기다. `leased` 줄 뒤에도 주소가 붙기까지
   틈이 있다는 것은 measurements 73.
4. 연결 실패가 조용하다. 상대가 없으면 `nc`가 아무 말도 안 하고 프롬프트로
   돌아온다(SLIRP이 RST를 안 준다). 그래서 판정 글자는 QEMU가 흘려 넣는
   payload여야 한다 — 그 글자는 연결이 열렸을 때만 생긴다.
   판정 글자를 고르는 일반 규칙은 [[project_gate_screen_echo]]에 있다.

## 실기의 NIC — 이 서브프로젝트 밖이었고 WN이 했다

RM 체인(노트북)의 NIC는 virtio-net이 아니다. 그 드라이버를 켜는 것은 이
서브프로젝트의 범위 밖이었고, WN(2026-09-26, `project_wired_nic`)이 노트북형
유선 드라이버를 켰다.

관련: [[project_kernel_config]] · [[project_seeding_a_config_disk]] ·
[[project_gate_chain_composition]] · [[project_shutdown_signals]] ·
[[project_daemon_supervision]] · [[project_wired_nic]]
