# CE-M2 — 묶음 `container`, docker 서비스, 판정, 안내

Date: 2026-11-11
Design: `docs/specs/2026-11-11-tars-container-environment-design.md`(결정 4~8)
Status: 끝났다(2026-11-12). 결정은 사용자 위임(2026-11-11).

## 착수 전에 확정한 것

1. 묶음의 자리 규칙(TP design 결정 2, `devlayer/build.sh`): upstream은 `/usr/local/lib/<도구>-<판>/`에 풀고 `/usr/local/bin`에 링크한다.
   압축 확장자가 아닌 URL은 실행 파일 하나로 `bin/<도구>`에 놓인다(compose · buildx). `devlayer/files/<묶음>/usr/local/lib/<이름>/`은
   그 이름의 도구 디렉터리가 있어야 통과하므로(판을 올리고 디렉터리 이름을 안 고친 것을 잡는 검사) CLI 플러그인 링크는
   `/usr/local/libexec/docker/cli-plugins/`에 둔다 — docker가 찾는 네 자리 가운데 하나다.
2. sha256: Docker의 static tarball은 벤더가 낸 체크섬이 없다. 두 번 받아(조사 에이전트와 lead, 서로 다른 때) 같은 값
   `3fb5d1f1…c973`이었다. compose · buildx는 릴리스의 체크섬 파일과 같았다.
3. 크기: tarball 86MB(풀면 236MB — dockerd 103 · docker 44 · containerd 39 · ctr 23 · runc 14 · shim 8 · proxy 3 · init 1),
   compose 34MB, buildx 68MB. 묶음 통째로는 풀면 333MiB · zstd15 109MiB, `ctr`을 빼면 311MiB · 101MiB(106,598,400 B). ISO의 남은
   자리는 약 105MiB였다 — `ctr`을 뺀다(훅 `devlayer/hooks/docker-static.sh`, tarball의 목록이 아는 여덟과 다르면 멈춘다).
4. trixie의 bubblewrap 0.12.0-1~deb13u1 · socat 1.8.0.3-1+deb13u1. 의존은 libcap2 · libselinux1 · libssl3t64 · libwrap0 —
   verify가 initrd와 겹치는 스물하나를 지웠다.
5. 서비스 템플릿은 server 묶음의 `common.sh`에 기대지 않는다 — `container`만 깐 기계에서도 서야 한다.
6. `/var/run`은 initrd에 없다. docker CLI의 기본 소켓이 `/var/run/docker.sock`이라 템플릿이 `/var/run -> /run`을 만든다.

## 프로브 (2026-11-11 · 12, QEMU TCG `-cpu SandyBridge -m 2048`, 묶음을 실은 ISO로 가상 NVMe에 설치한 뒤)

스크립트는 세션의 scratchpad(`ce/probe.sh` — devtools 체인의 부팅 도우미를 줄인 것)에 있었다. 저장소에는 결과만 남긴다.

| 본 것 | 결과 |
|---|---|
| `sudo tars-service enable docker` | `API listen on /var/run/docker.sock`까지 약 6초. 첫 판에 섰다 |
| `docker info` | 29.9.3 · containerd 2.4.2 · runc 1.5.2 · Cgroup Driver cgroupfs · Cgroup Version 2 · Storage Driver overlayfs · seccomp · cgroupns · Firewall Backend nftables · Docker Root Dir `/home/.tars/var/docker`. 경고 둘: `No swap limit support`(swap 없음) · `No cpuset support`(SMP 없음) |
| 소켓 | `root:tars 660`(`--group 1000`) |
| 사용자의 `docker run --rm hello-world`(망 있음) | `Hello from Docker!` |
| `alpine`: 받기 · `wget http://example.com` · `ping 1.1.1.1` | 셋 다 됐다(컨테이너의 DNS · NAT · ICMP) |
| `nginx:alpine -d -p 8080:80 --memory 64m --pids-limit 50` | `127.0.0.1:8080`에만 듣는다(`lsoff`), HTTP 200, `memory.max` = 67108864, `docker stats` 2.8MiB / 64MiB |
| 망 없이: `docker import`(server 묶음의 정적 caddy) → `run -p 8080:80` → `curl` | `ce-ok` |
| 망 없이: `docker build`(BuildKit, `FROM` 로컬 이미지 + `COPY`) | `naming to docker.io/tars/built:latest … DONE` |
| 망 없이: `docker compose up -d`(`restart: unless-stopped`) | `compose-ok` |
| `poweroff` | `stopping 1 services first (up to 20s)` → `services stopped in 1861ms`(컨테이너 둘이 도는 중) |
| 다음 부팅 | dockerd가 저절로, 이미지 둘이 남고, compose의 컨테이너가 다시 `Up`, `curl` → `compose-ok` |
| `tars-service stop docker`(nginx 하나 도는 중) | 1,870ms, SIGKILL 없음 |
| 사용자의 `bwrap --ro-bind / / --unshare-all … id` | `uid=1000(tars)` |
| 사용자의 `bwrap … --proc /proc --unshare-user --unshare-pid --unshare-net …` | 안의 `/proc`에 프로세스 넷, 인터페이스 하나(`lo`) |
| `codex sandbox -- id`(0.167.1, 게스트에서 받았다) | `uid=1000(tars) …` — TP-M12의 `Creating new namespace failed`가 없다. 안에서 `/usr/local`에 쓰기는 `Read-only file system`, `curl`은 `http=000` |

프로브가 찾은 것 둘:
- inotify가 없었다. dockerd가 `couldn't initialize inotify: function not implemented`(CDI 감시)와 컨테이너마다
  `failed to watch oom events … failed to create inotify fd`를 찍었다. `CONFIG_INOTIFY_USER`가 꺼져 있었다 — Docker만이 아니라 파일
  감시를 쓰는 개발 도구 전부가 못 쓰던 것이다. 켰다(bzImage +16KiB), 줄이 사라졌다. CE-M1의 커널 옵션에 넣는다.
- 프로브를 QEMU 죽이기로 끝냈더니 다음 부팅에서 `/config/services.d/docker`가 `ext2_lookup: deleted inode referenced`로 안 읽혔다
  (`tars-init: service docker cannot be read (errno 5), skipped`). 호스트가 QEMU의 쓰기 캐시를 버린 것이다 — 프로브를 `poweroff`로
  끝내자 없어졌다. 실기의 전원 뽑기와 같은 종류라 `carryover.md`에 적는다(`/config`는 저널이 없는 ext2다).

남은 로그 줄(해가 없다고 본 것): `failed check for fsverity support`(ext4에 fsverity 없음), `failed to find iptables`(nftables
백엔드라 안 쓴다), `Could not load necessary modules for IPSEC rules`(swarm), `docker build` 뒤의 `healthcheck failed fatally …
connection error`(BuildKit 세션이 닫히는 줄).

## Task 1 — 묶음

`devlayer/manifest.toml`의 다섯 표(docker · docker-compose · docker-buildx · bubblewrap · socat), 훅 `docker-static.sh`,
`devlayer/files/container/`(서비스 템플릿 · `etc/docker/daemon.json` · 플러그인 링크 둘), `Makefile`의 `DEV_LAYERS`, `quick_check.sh`의
shellcheck 목록.

## Task 2 — 체인 devtools

묶음 열하나. 부팅 2: 사용자의 bwrap · socat, `tars-service enable docker`, 소켓 `root:tars 660`, `docker info`의 넷, compose ·
buildx, 망 없는 이미지(`docker import`)의 컨테이너가 `127.0.0.1:8080`에서 `ce-ok`, `memory.max`, `firewall=on` 뒤에도 표 둘이 함께
있고 응답이 온다, `--restart unless-stopped` 컨테이너 하나. 전원 끄기는 서비스 여섯을 먼저. 부팅 3: dockerd가 저절로, 이미지가
남고 그 컨테이너가 `Up`, `tars-service disable docker`.

## Task 3 — 안내

`docs/help/devtools.md`의 "컨테이너" 절과 묶음 표 한 줄, `docs/guides/running-tars.md`.

## Task 4 — 게이트

`make quick` · 체인 devtools 단독 · 루트 게이트(LT · CE-M0 · M1과 함께).

## 결과

구현 `ec3ea14` · `3be23ba`(forward 체인). devtools 체인의 편집은 서브에이전트, 나머지는 lead. plan과 다른 자리:

1. 체인의 포트는 8090 · 8091이다 — 8080 · 8081은 그 체인에서 서버 묶음의 nginx · caddy가 쓴다(서브에이전트가 찾았다).
2. 방화벽을 고쳤다(plan에 없던 일, 서브에이전트가 체인을 쓰다 찾았다): `/etc/tars/firewall.nft` · `firewall-base.nft`의 첫 줄
   `flush ruleset`과 `firewall=off` reload의 `nft flush ruleset`이 dockerd의 표까지 지웠다 — 떠 있는 컨테이너의 망이 끊긴다. 표 하나만
   다시 짓고(`table ip tars` · `delete table ip tars` · 정의) `nft destroy table ip tars`로 지운다. firewall 체인 검사 19의 글자를 맞췄다.
3. forward 체인을 더했다(첫 커밋 뒤 자동 보안 검토가 짚었다): docker 템플릿이 `ip_forward=1`을 쓰면 `firewall=on`인 기계도 NIC 사이로
   패킷을 넘겼다. `table ip tars`에 `forward`(`policy drop` — 맺어진 연결 · `ct status dnat` · `iifname "docker0"` · `"br-*"`).
   망이 있는 프로브: 방화벽을 켠 채 기본 bridge와 `docker network create`의 bridge에서 밖으로 HTTP · ping, 밖 → `-p 0.0.0.0:8090`
   응답, 밖 → 루프백 전용 8091은 안 닿는다. 순서 셋(부팅 때 방화벽 먼저 · reload로 나중에 · dockerd 재시작) 모두 같았다.
   그 프로브의 첫 판에서 밖 → 8090이 한 번 시간 초과였다 — 망이 reload로 막 올라온 직후였고 다시 나지 않았다. 원인은 못 가렸다.
4. `ctr`을 뺐다(확인 3). 기본 판 ISO는 2,144,516,096 B — 2GiB까지 약 3MB.

devtools 체인(게이트 안, 701초): `dockerd opened its API (6865ms) on a root:tars 660 socket`, `docker import made tars/caddy offline
(18614ms) and its container answered on 127.0.0.1:8090 (4240ms) with a 64m cgroup limit`, `poweroff stopped the six services (docker
included) first in 2266ms`, 부팅 3 `dockerd came back on its own with the firewall up (both tables), tars/caddy is still there, keep is Up`.
단독 첫 판에 PASS였다(19분 8초).

게이트가 안 보는 것: 망이 있어야 하는 길 전부(`docker pull` · 컨테이너의 나가는 길 · 밖에서 들어오는 포트 — 프로브로만 봤다),
`codex` · `claude`의 샌드박스(codex는 프로브로 봤다).

루트 게이트(2026-11-12, `0e1b888`의 코드): 32/33 — 34분 51초(prebuild 344초 + lanes 1,614초), 잘린 줄 0, `out/gate-logs/20261111-162704`. 빨간 하나는 pm(PM-M0)의 화면 판정이 옛 프롬프트 `tars@(none) ~>`를 기다린 것(LT-M0이 놓친 자리)이고, 그 한 줄을 고친 뒤 pm 단독이 초록이었다. 커널 · init · initrd는 그 사이 바뀌지 않아 게이트를 통째로 다시 돌리지 않았다.
