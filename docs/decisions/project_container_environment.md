---
name: project_container_environment
description: "컨테이너 실행 환경(CE, 2026-11-12) — init이 루트를 자기 bind mount로 덮어 pivot_root가 되게 하고, 커널에 namespace · cgroup v2 · seccomp · bridge · NAT · inotify, 묶음 container(Docker 29.9 static · compose · buildx · bwrap · socat), `tars-service enable docker`. rootful · nftables 백엔드 · -p는 127.0.0.1 · 소켓은 사용자 그룹. 방화벽은 자기 표만 짓고 지운다. 함정 — initramfs 루트의 EINVAL, flush ruleset, 프로브를 QEMU 죽이기로 끝내면 /config가 깨진다"
metadata:
  node_type: memory
  type: project
---

CE(Container Environment, 2026-11-11~12)가 세웠다. design `docs/specs/2026-11-11-tars-container-environment-design.md`, plan `-ce-m0` · `-ce-m1` · `-ce-m2`.
사용자: "1번으로 가자. 조사부터. 완성 작업까지 결정을 위임합니다" — 결정은 모두 Claude가 정했고 design에 까닭을 적었다.

## 무엇이 섰나

- init(`mountEarly`의 맨 앞, `rebindRoot`): `/`를 `/run/.root`에 bind → chdir → `MS_MOVE`로 `/` 위에 → chroot. 루트 mount에 부모가 생겨
  `pivot_root`가 된다. 로그 `tars-init: root is a bind mount of the initramfs (pivot_root works)`. 그리고 `/sys/fs/cgroup`에 cgroup2.
- 커널: `USER_NS` · `PID_NS` · `UTS_NS` · `TIME_NS`, cgroup(cpu · io · memory · pids · freezer · device · BPF), `BPF_SYSCALL`(비특권은 막음),
  seccomp, `POSIX_MQUEUE`, `VETH` · `BRIDGE` · `NF_NAT` · nft의 nat · masq · redir · reject · fib, ext4 · tmpfs의 xattr · ACL, `INOTIFY_USER`.
  bzImage 11,486,208 → 12,190,720 B.
- 묶음 `container`(101MiB): Docker Engine 29.9.3(static tarball, `ctr`은 훅이 뺀다) · compose 5.7.1 · buildx 0.38.2 · bubblewrap 0.12.0 · socat.
- 서비스: `sudo tars-service enable docker`. 템플릿이 `/home/.tars/var/docker`(p3) · `/var/run -> /run` · `ip_forward=1` 뒤
  `dockerd --config-file … --group <uid 1000의 gid>`. `daemon.json`: nftables 백엔드 · `ip` 127.0.0.1 · `log-driver` local.
  사람의 설정은 `/config/docker.d/daemon.json`(통째로 대신한다). `# tars-stop: TERM 20`.
- 방화벽: `firewall.nft`와 `firewall=off` reload가 `flush ruleset` 대신 `table ip tars`만 다시 짓고 `nft destroy table ip tars`로 지운다.

## 정한 것과 까닭

- rootful dockerd — init이 root 서비스를 감독하는 모양과 맞고 `docker` · compose가 그대로다. rootless(Podman · rootless Docker)는
  systemd 사용자 세션(cgroup 위임 · 런타임 디렉터리 · 사용자별 데몬)을 전제로 한다.
- nftables 백엔드(29.0부터, 문서 표시는 experimental) — iptables 실행 파일과 xtables 커널 옵션을 안 들인다. 표는 `ip docker-bridges`.
- `-p`의 기본 주소 127.0.0.1 — Docker의 DNAT은 TARS 방화벽의 `input`을 안 지나 그냥 두면 `firewall=on`인 기계의 포트가 LAN에 열린다.
- 소켓 그룹은 사용자의 gid(`docker` 그룹 없음) — init의 계정 코드를 안 건드린다. 켜는 한 줄이 "이 사용자는 root와 같다"는 동의다.
- `DOCKER_RAMDISK`(no-pivot)를 안 쓴다 — bwrap을 못 고치고 격리가 약하다.

## 잰 것 (QEMU TCG SandyBridge · 2GiB)

dockerd가 API를 열기까지 약 6.5초. `docker import`(정적 caddy) 19초, 컨테이너의 첫 응답 3.6초. `tars-service stop docker` 1.9초,
poweroff는 서비스 여섯(서버 다섯 + docker)을 2.6초에. 재부팅 뒤 이미지가 남고 `--restart unless-stopped` 컨테이너가 다시 뜬다.
망이 있는 프로브: hello-world · alpine(DNS · HTTP · ping) · nginx `-p`(127.0.0.1에만) · `--memory 64m`(`memory.max` 67108864).
`codex sandbox -- id`(0.167.1)가 uid를 찍고 안에서 쓰기 · 망이 막힌다. 묶음 열하나를 실은 ISO는 2,144,514,048 B(2GiB까지 약 3MB).

## 함정 (다시 만나면)

1. initramfs 루트에서 `pivot_root`는 EINVAL이다 — 커널 옵션을 다 켜도 runc · bwrap이 멈춘다. `tars-init: root is a bind mount` 줄이 판정이다.
   6.18에는 커널 쪽 해결이 없다(7.0의 nullfs). 커널을 7.x로 올릴 때 `rebindRoot`가 여전히 필요한지 본다.
2. initrd 뒤에 cpio를 덧붙여 프로브를 넣을 때는 512바이트 경계에서 시작해야 한다(`invalid magic at start of compressed archive`).
3. 프로브를 QEMU 죽이기로 끝내면 `/config`(ext2)의 방금 쓴 링크가 깨진다(`ext2_lookup: deleted inode referenced`) — `poweroff`로 끝낸다.
4. 화면 dump(`screen>`)는 탭이 건너뛴 칸을 싣지 않는다 — `0\t2147483647`이 `02147483647`로 붙는다. 판정은 `[[:space:]]*`.
5. devtools 체인에서 8080 · 8081은 서버 묶음의 nginx · caddy가 쓴다 — 컨테이너 판정은 8090 · 8091.
6. `SMP`가 꺼져 `CPUSETS`가 없다(`docker info`의 `No cpuset support`). inotify도 CE 전에는 없었다 — 파일 감시 도구가 전부 안 됐다.

남긴 것은 `docs/guides/carryover.md`의 CE 절(SMP · 2GiB · `/config` ext2 · rootless · nftables 백엔드의 experimental 표시 · 실기).

관련: [[project_dev_layer]](묶음 · 서비스 템플릿) · [[project_service_stop]] · [[project_little_things]](Landlock — 같은 커널 빌드) · [[project_release]]
