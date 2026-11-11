# TARS Container Environment — Design

접두사: CE

Date: 2026-11-11
Status: 닫힘(2026-11-12, CE-M0 루트 bind · CE-M1 커널과 cgroup2 · CE-M2 묶음 `container`와 docker 서비스, 루트 게이트 32/33 + pm 단독). 사용자 "1번으로 가자. 조사부터. 완성 작업까지 결정을 위임합니다"(2026-11-11). plan은 milestone마다
`docs/plans/2026-11-11-tars-container-environment-ce-m<N>.md`.

계기: TP-M12(2026-11-08)에서 `codex sandbox linux`가 `bwrap: Creating new namespace failed, likely because the kernel does not support
user namespaces.`로 멈췄다. 같은 날 사용자: "컨테이너 환경을 활성화하는 것을 고려해야 됩니다. 개발도구 중에 도커를 쓰는 경우가 종종 있죠."
user namespace 하나만 켜면 AI 도구의 샌드박스는 서도 Docker는 안 서므로 둘을 한 서브프로젝트로 묶기로 했다(`carryover.md`).
2026-11-11에 다음 서브프로젝트로 골랐다.

관련 문서: TP design(개발 도구 층 — 묶음 · 출처 · 서비스 템플릿), SV · CT · SS design(서비스 감독 · 멈춤), FW design(nftables 방화벽),
LT design(Landlock — 같은 날, 같은 커널 빌드), `docs/decisions/feedback_ipv4_only.md`.

## 한 줄 요약

AI 도구의 샌드박스(bubblewrap)와 Docker가 TARS에서 선다 — init이 루트를 `pivot_root`가 되는 모양으로 덮고, 커널이 namespace ·
cgroup v2 · seccomp · bridge · NAT을 갖고, 새 묶음 `container`가 Docker Engine · compose · buildx · bubblewrap · socat을 싣고,
`sudo tars-service enable docker` 한 줄로 dockerd가 서비스가 된다.

## 확인 (2026-11-11, HEAD `ee4a880`)

조사는 둘로 했다 — 바깥 사실(원본 파일을 받아 읽었다: moby 29.9.3 소스 · `contrib/check-config.sh` · Docker apt `Packages` ·
static tarball · runc · bubblewrap · Codex · sandbox-runtime · Homebrew 7.0.13 · Linux 6.18 Kconfig)과 우리 게스트에서의 실측.

1. 루트가 initramfs다. `/proc/self/mountinfo`의 첫 줄이 `1 1 0:2 / / rw - rootfs rootfs rw` — 부모가 자기 자신인 mount다.
   `pivot_root(2)`는 이 루트에서 `EINVAL`이다(man page: "The rootfs (initial ramfs) cannot be pivot_root()ed"). 실측(정적 프로브,
   새 mount namespace 안에서 tmpfs로 `pivot_root`): `pivot_root FAILED: Invalid argument`. 같은 프로브가 먼저 루트를 자기 자신의
   bind mount로 덮으면(`mount --bind / D` → `chdir D` → `mount --move . /` → `chroot .`) `pivot_root OK`.
   runc(1.5.2)도 bubblewrap(0.13.1, issue #592 열려 있음)도 `pivot_root`를 쓴다 — 커널 옵션을 다 켜도 이 자리에서 둘 다 멈춘다.
   Docker에는 `DOCKER_RAMDISK`(runc `--no-pivot`, chroot로 대신한다)라는 우회가 있지만 격리가 약해지고 bwrap에는 그런 길이 없다.
   커널 쪽 해결(진짜 루트를 nullfs로)은 7.0에 들어갔다 — 6.18에는 없다.
2. 커널(`kernel/.config`)에서 꺼진 것: `USER_NS` · `PID_NS` · `UTS_NS` · `TIME_NS` · `CGROUPS` · `SECCOMP` · `BPF_SYSCALL` ·
   `POSIX_MQUEUE` · `VETH` · `BRIDGE` · `NF_NAT` · `IP_NF_IPTABLES`. 켜진 것: `NAMESPACES` · `IPC_NS` · `NET_NS` · `NF_TABLES` ·
   `NFT_CT` · `NF_CONNTRACK` · `OVERLAY_FS` · `KEYS`. `SMP`가 꺼져 있다(`NR_CPUS=1`) — `CPUSETS`는 SMP에 기대므로 켤 수 없다.
   `CONFIG_MODULES`가 없어 전부 내장이다 — dockerd는 기능이 이미 있으면 `modprobe`를 부르지 않는다(moby `modprobe_linux.go`).
3. Docker Engine의 요구(moby `check-config.sh`의 "Generally Necessary"와 29.9.3 소스):
   - namespace 다섯, cgroup(`CGROUP_SCHED` · `MEMCG` · `CGROUP_PIDS` 등), `VETH` · `BRIDGE` · `NF_NAT` · `POSIX_MQUEUE` · `KEYS`.
   - cgroup v2의 장치 제어는 eBPF다 — `CGROUP_BPF`(→ `BPF_SYSCALL`)가 사실상 필수다. cgroup v1은 29부터 deprecated.
   - 방화벽 백엔드가 둘이다. iptables(기본)는 6.18에서 `IP_NF_IPTABLES_LEGACY` 계열이나 `NFT_COMPAT` + xtables 매치와 `iptables` 실행
     파일을 끈다. nftables(`"firewall-backend": "nftables"`, 29.0부터, 문서의 표시는 아직 experimental)는 `nft` 실행 파일로 규칙을 넣고
     표는 `ip docker-bridges` 하나다(`inet`이 아니라 IPv6 없는 커널에서 선다). 쓰는 표현식은 nat · masquerade · fib · ct · dnat.
     nftables 백엔드는 `ip_forward`를 스스로 켜지 않는다 — 꺼져 있으면 시작이 실패한다.
   - systemd가 없으면 cgroup 드라이버는 저절로 cgroupfs다. cgroup2를 붙이는 것은 dockerd가 아니다. runc가 경로를 만들며 윗
     디렉터리의 `cgroup.subtree_control`을 스스로 쓴다 — 미리 위임할 것이 없고, 루트 cgroup은 "no internal processes" 규칙의 예외다.
   - 받는 자리 둘: static tarball(`download.docker.com/linux/static/stable/x86_64/docker-29.9.3.tgz`, 정적 실행 파일 여덟, 벤더가 낸
     체크섬 없음)과 apt 저장소(동적 dockerd — `libsystemd0` · `iptables`에 기댄다). compose(v5.7.1) · buildx(v0.38.2)는 GitHub 릴리스에
     실행 파일 하나씩과 체크섬 파일.
4. rootless 쪽(Podman · rootless Docker)은 `newuidmap` setuid · `/etc/subuid` · 사용자별 런타임 디렉터리 · systemd 사용자 세션의 cgroup
   위임을 전제로 한다. systemd가 없으면 자원 제한이 안 되고(Docker 문서: "cgroup is supported only when running with cgroup v2 and
   systemd"), 사용자별 데몬을 띄우고 거둘 주체가 없다. trixie의 Podman은 5.4.2(upstream 6.2.0).
5. AI 도구의 샌드박스: Codex(0.167)는 bwrap이 기본이고(PATH의 `bwrap`, 없으면 자기가 든 것) `--unshare-user` · `--unshare-pid` ·
   seccomp를 쓴다. Claude Code(sandbox-runtime)는 `bwrap`과 `socat`이 깔려 있어야 하고 seccomp는 선택이다. 둘 다 Landlock은 안 쓴다.
   Homebrew 7.0은 Landlock을 쓴다(LT design 결정 4가 켠다). trixie의 bubblewrap은 0.12.0, setuid bwrap은 Debian이 지원을 끊었다 —
   `USER_NS`가 길이다.
6. TARS의 방화벽(`/etc/tars/firewall.nft`)은 `table ip tars`의 `input` 체인 하나다(`policy drop`). forward 체인이 없어 컨테이너가
   밖으로 나가는 길을 막지 않는다. 반대로 Docker가 `-p`로 내는 포트는 prerouting의 DNAT을 타고 forward로 가므로 `input`을 안 지난다
   — `firewall=on`이어도 LAN에 열린다(Docker의 알려진 성질).
7. 서버 다섯의 선례(TP-M11): 묶음의 `etc/tars/services/<이름>` 템플릿, 데이터는 `/home/.tars/var/<이름>`(p3 ext4), `tars-service
   enable`이 `/config/services.d`에 링크한다. `/var` · `/etc` · `/run`은 RAM이다.
8. GitHub release의 파일 하나는 2GiB까지다. 0.2.0 ISO가 2,036,928,512 B라 남은 자리는 약 110MB다. Docker tarball은 86MB(풀면
   236MB)다.

## 결정

### 결정 1 — init이 부팅 첫머리에 루트를 자기 자신의 bind mount로 덮는다

`mountEarly`의 맨 앞, `/proc`을 붙이기 전이다. 순서는 확인 1의 넷 — 빈 디렉터리 `D`에 `/`를 bind, `chdir(D)`, `mount(".", "/", MS_MOVE)`,
`chroot(".")`, `chdir("/")`. 같은 ramfs를 한 번 더 붙이는 것이라 RAM을 더 쓰지 않고 파일은 하나도 옮기지 않는다. 그 뒤의 모든 mount와
자식은 새 루트 아래에 선다. 실패하면 한 줄을 남기고 옛 모양 그대로 부팅한다(부팅은 멈추지 않는다 — 컨테이너만 안 된다).
`DOCKER_RAMDISK`는 쓰지 않는다 — bwrap을 못 고치고 격리가 약하다. tmpfs로 통째 옮기는 switch_root는 RAM의 initrd를 한 번 복사한다.
커널의 firmware 읽기는 `init_task`의 루트(옛 rootfs)에서 `/lib/firmware`를 찾는데, 그 디렉터리는 같은 ramfs 안의 진짜 디렉터리라
그대로 보인다(initrd의 `/lib`는 링크가 아니다) — 무선 · 블루투스 체인이 판정한다.

### 결정 2 — 커널: namespace · cgroup v2 · seccomp · bridge · NAT을 내장한다

켠다: `USER_NS` · `PID_NS` · `UTS_NS` · `TIME_NS`, `CGROUPS` · `MEMCG` · `BLK_CGROUP` · `CGROUP_SCHED` · `FAIR_GROUP_SCHED` ·
`CFS_BANDWIDTH` · `CGROUP_PIDS` · `CGROUP_FREEZER` · `CGROUP_DEVICE` · `CGROUP_CPUACCT` · `CGROUP_BPF`, `BPF_SYSCALL` · `BPF_JIT` ·
`BPF_UNPRIV_DEFAULT_OFF`, `SECCOMP` · `SECCOMP_FILTER`, `POSIX_MQUEUE`, `VETH` · `BRIDGE`, `NF_NAT` · `NF_CT_NETLINK` · `NFT_NAT` ·
`NFT_MASQ` · `NFT_REDIR` · `NFT_REJECT` · `NFT_FIB_IPV4`, `EXT4_FS_POSIX_ACL` · `EXT4_FS_SECURITY` · `TMPFS_POSIX_ACL` · `TMPFS_XATTR`
(이미지 층이 xattr · ACL을 쓴다), `INOTIFY_USER`(CE-M2의 프로브가 찾았다 — dockerd가 OOM 이벤트를 inotify로 보고, 파일 감시를 쓰는 개발 도구
전부가 이것 없이는 `function not implemented`다).
켜지 않는다: iptables 계열 전부(결정 5), `BRIDGE_NETFILTER`(dockerd는 `icc=false`나 userland proxy를 끌 때만 찾는다), IPv6 · IPVS ·
VXLAN · MACVLAN(swarm · overlay 망), cgroup v1(`MEMCG_V1` 등), `TUN`(rootless 망 — 비목표 2), `CPUSETS`(SMP가 없다).
비특권 eBPF는 막아 둔다(`BPF_UNPRIV_DEFAULT_OFF`) — BPF는 runc의 장치 필터 때문에 켜는 것이지 사용자에게 여는 것이 아니다.
`USER_NS`의 대가: 비특권 사용자가 namespace 안에서 닿는 커널 코드가 는다. Debian · Fedora · Arch의 기본 커널이 같은 선택이고, 한
사람이 쓰는 개발 기계에서 샌드박스가 주는 이득(AI 도구가 돌리는 명령의 격리)이 더 크다. 끄는 길은 커널의
`user.max_user_namespaces=0`이다 — 설정 키는 두지 않는다.

### 결정 3 — init이 cgroup2를 붙인다

`mountEarly`에서 `/sys/fs/cgroup`에 `cgroup2`. init은 cgroup을 만들지도 프로세스를 옮기지도 않는다 — 모든 프로세스는 루트 cgroup에
남고, 그 아래의 경로(`/sys/fs/cgroup/docker/…`)는 runc가 만든다. 서비스마다 cgroup을 두는 일은 비목표 4다.

### 결정 4 — rootful Docker Engine, static tarball에서

dockerd는 root 데몬이고 init이 감독하는 서비스다 — TARS의 서비스 모양(root로 띄워 감독, 출력은 콘솔)과 그대로 맞는다. rootless
쪽을 고르지 않은 까닭은 확인 4다. 사람들이 기대하는 것도 `docker` · `docker compose` 그대로다.
출처는 static tarball이다(upstream, sha256은 우리가 받아 고정한다 — caddy · mkcert와 같은 길). apt 판은 `libsystemd0` · `iptables`를
끌어 묶음을 키우고 쓰지 않을 것을 싣는다. 정적 Go 실행 파일이라 CPU 수준(AVX2)의 걱정이 없다.
compose와 buildx는 GitHub 릴리스의 실행 파일 하나씩을 `docker`의 CLI 플러그인 자리에 링크한다.

### 결정 5 — Docker의 방화벽은 nftables 백엔드

`"firewall-backend": "nftables"`, `"ip6tables": false`. TARS의 방화벽이 nftables이고 `nft`가 initrd에 있다 — iptables 실행 파일도
xtables 커널 옵션도 들이지 않는다. Docker는 자기 표(`ip docker-bridges`)만 쓰고 TARS의 표(`ip tars`)를 건드리지 않는다. 문서의
experimental 표시는 받아들인다 — 게이트가 망 길(컨테이너 → 호스트의 포트)을 매번 판정하고, 깨지면 iptables-nft로 물러설 자리가
커널 옵션 몇 줄이다.
`net.ipv4.ip_forward=1`은 서비스 템플릿이 dockerd를 띄우기 직전에 쓴다 — Docker를 안 켠 기계는 forward가 꺼진 채다.
forward를 켠 기계는 NIC 사이로 패킷을 넘긴다. 그래서 `firewall=on`의 표(`ip tars`)에 `forward` 체인을 더한다 — `policy drop`,
받는 것은 맺어진 연결 · Docker가 DNAT한 포트(`ct status dnat`) · 컨테이너 bridge(`docker0` · `br-*`)에서 나가는 것 셋이다. nftables에서
한 base chain의 drop은 다른 표의 accept가 되돌리지 못하므로 컨테이너 쪽은 우리 체인이 받아야 한다. `firewall=off`인 기계는 이
체인이 없다 — 사람이 "거르지 않는다"를 고른 기계이고, 안내가 그 결과를 말한다. (첫 커밋 뒤의 자동 보안 검토가 짚어 더했다.)
같은 까닭으로 TARS의 방화벽은 자기 표만 다룬다 — `firewall.nft`의 `flush ruleset`과 `firewall=off` reload의 `nft flush ruleset`은
떠 있는 dockerd의 표를 지웠다. `table ip tars`만 다시 짓고 `nft destroy table ip tars`로 지운다(TC design 위험 3의 판단을 고친다).

### 결정 6 — `-p`의 기본 주소는 127.0.0.1

`daemon.json`의 `"ip": "127.0.0.1"`. 확인 6 — 그냥 두면 `docker run -p 8080:80`이 `firewall=on`인 기계의 포트를 LAN에 연다.
서버 묶음의 nginx · caddy가 127.0.0.1에 서는 것(TP-M11)과 같은 기본값이다. LAN에 내려면 사람이 `-p 0.0.0.0:8080:80`이라고 적는다 —
그때는 TARS의 방화벽이 아니라 그 한 줄이 문을 연 것이고, 안내에 그렇게 적는다.

### 결정 7 — 서비스 템플릿 하나, 데이터는 p3, 소켓은 TARS 사용자의 그룹

묶음의 `etc/tars/services/docker`. 서버 다섯과 같은 모양이다:
- 켜기: `sudo tars-service enable docker`. 기본은 꺼져 있다 — root 데몬과 forward를 켜는 일은 사람이 고른다.
- 데이터: `data-root` = `/home/.tars/var/docker`(p3 ext4 — overlay의 upper가 될 수 있는 진짜 파일시스템, 재부팅을 넘는다).
  `exec-root` · pid · 소켓은 `/run`(RAM).
- 소켓의 그룹은 TARS 사용자(uid 1000)의 gid다(`--group <gid>`). `docker` 그룹을 따로 만들지 않는다 — init의 계정 코드와 initrd의
  `/etc/group`을 안 건드리고, 사용자는 `sudo` 없이 `docker`를 친다. 이것은 그 사용자에게 root와 같은 힘을 주는 일이다(컨테이너에
  `/`를 붙일 수 있다) — 켜는 한 줄이 그 동의이고 안내가 그렇게 말한다. 사용자 없는 부팅(ISO)에서는 root 소유다.
- 설정: 묶음의 `/etc/docker/daemon.json`이 원본이고, 사람의 것은 `/config/docker.d/daemon.json`이 있으면 그 파일을 대신 쓴다
  (dockerd는 설정 파일 조각을 합치지 않는다 — 통째로 바꾼다).
- 로그 드라이버는 `local`(크기를 스스로 돌린다). dockerd 자신의 로그는 다른 서비스처럼 콘솔로 간다.
- 멈춤: `# tars-stop: TERM 20`(dockerd의 `shutdown-timeout` 15초 + 여유). SS의 전원 끄기가 서비스 먼저 끈다.

### 결정 8 — 묶음 `container`

Docker Engine 29.9.3 · compose 5.7.1 · buildx 0.38.2(upstream), bubblewrap · socat(debian). 기본 `DEV_LAYERS`와 기본 판 ISO에 든다 —
ISO의 2GiB 한도(확인 8) 때문에 tarball의 `ctr`(containerd의 진단용 CLI, 23MB)은 싣지 않는다 — 묶음은 101MiB다(CE-M2 plan 확인 3).
bwrap과 socat이 이 묶음인 까닭: 둘 다 AI 도구의 샌드박스가 부르는 것이고(확인 5), 그 도구들은 개발 도구 층이 있는 기계에서 쓴다.

## milestone

- CE-M0: 결정 1. init의 루트 덮기와 판정(루트 mount의 부모가 자기 자신이 아니다), 루트 게이트로 다른 체인이 그대로인지.
- CE-M1: 결정 2 · 3. 커널 옵션과 cgroup2, bzImage 크기 · 부팅 시간, 판정(컨트롤러 목록 · namespace 파일 · seccomp).
- CE-M2: 결정 4~8. 묶음 `container`, 서비스 템플릿, 체인 devtools의 판정(사용자의 bwrap, `docker import`로 만든 이미지의
  컨테이너가 `-p`로 응답한다, 재부팅 뒤 이미지가 남는다), 망이 있는 프로브(`docker pull` · `docker compose up`), 안내.

## 비목표

1. 이미지를 ISO에 싣기. 이미지는 망에서 받는다(`docker pull`). 게이트는 망이 없으므로 `docker import`로 이미지를 만들어 본다.
2. rootless Docker · Podman(`newuidmap` · subuid · `TUN`). 필요해지면 `USER_NS`는 이미 있다.
3. swarm · overlay 망 · IPv6 · macvlan.
4. 서비스마다의 cgroup(자원 제한 · 통째로 죽이기). 감독은 지금처럼 프로세스 그룹이다.
5. 컨테이너가 호스트의 포트에 붙는 길(`host.docker.internal` — `docker0`에서 들어오는 것은 TARS 방화벽의 `input`이 막는다).
   여는 법은 안내에 한 줄(`/config/nftables.d`).
6. Kubernetes(kind · k3s) — 더 많은 커널 옵션을 끈다. 요구가 생기면 그때.
7. SMP. 지금 커널은 CPU 하나만 쓴다 — 컨테이너와 별개의 큰 결정이라 `carryover.md`에 적는다.
