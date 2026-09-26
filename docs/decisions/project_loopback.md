---
name: project_loopback
description: "게스트의 lo를 init이 ioctl 하나로 올리고, localhost · *.localhost를 /etc/hosts · nsswitch.conf · libnss_myhostname이 푸는 서브프로젝트(LB-M0~M3, 2026-09-26 종료). 새 체인 없이 tools(net=off) · net(net=dhcp) 체인이 이름 셋으로 게스트 안 TCP 왕복을 본다"
metadata:
  node_type: memory
  type: project
---

# Loopback (LB)

design은 `docs/superpowers/specs/2026-09-26-tars-loopback-design.md`. WN-M0이 덤으로
본 `lo state=down`에서 시작했고, 사용자가 이름 풀이를 범위에 더했다 — "caddy 같은 웹
서버를 쓸 때 `some-domain.localhost`가 풀리면 편하다".

무엇이 섰나.

- `init/src/net.zig`의 `loopbackUp()` — `SIOCGIFFLAGS` → `IFF_UP` → `SIOCSIFFLAGS`.
  `main()`이 설정을 읽기 전에 부른다. 커널이 `127.0.0.1/8`을 스스로 붙인다.
- `kernel/make_initrd.sh` — `/etc/hosts`(`127.0.0.1 localhost`) ·
  `/etc/nsswitch.conf`(`hosts: files myhostname dns`) heredoc과
  `libnss_myhostname.so.2`(Dockerfile 층 9). `init` 코드 0줄.
- `gate_lib.sh`의 `type_loopback_roundtrips` — `tools` 검사 20 · 21, `net` 검사 29 · 30.

Why: 커널은 `lo`를 만들기만 하고 안 올린다. WN-M2가 링크를 올리는 코드를 dhcpcd에
넘긴 뒤 `lo`를 올리는 주체가 아무도 없었다(dhcpcd는 `lo`를 안 만진다). 파일이 없던
때 `localhost`는 `net=dhcp`에서 SLIRP 너머 호스트 DNS가 답해 줄 때만 풀렸다.

How to apply:

- 게스트 `curl`(8.14)은 `localhost` · `*.localhost`를 resolver 없이 스스로 푼다. 이름
  풀이의 증거로 쓰지 말고 NSS를 거치는 `nc`나 `getent`를 쓴다.
- `lo`가 DOWN일 때 `127.0.0.1`의 실패 모양이 `net`에 따라 다르다 — `net=off`는
  `Network is unreachable`, `net=dhcp`는 기본 경로 때문에 문구 없이 `rc=1`. 판정은
  문구가 아니라 "받은 글자가 없다"로 한다.
- 게이트는 `/etc/hosts`의 `localhost` 줄을 따로 못 지킨다 — `myhostname`도 `localhost`에
  답한다. 그 줄은 NSS를 안 거치는 resolver(정적 Go · musl)를 위한 것이고 게스트에 그런
  클라이언트가 없다. 그 클라이언트가 `*.localhost`를 필요로 하는 날 로컬 DNS stub을
  다시 본다(design 비목표 1).
- 판정의 재료를 판정 대상과 같은 파일로 두지 말 것 — `/etc/hosts`를 흘려 보내던 첫
  판에서 그 파일을 비우자 게이트가 "loopback을 못 건넜다"고 거짓말했다.
- 게스트에 `timeout` · `install`이 없다. bash로 짠 타임아웃의 감시자는 출력을 닫아야
  `$(...)`가 안 매달린다.
