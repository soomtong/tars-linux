# PM-M0 — `install.sh`가 TARS에서 `brew --version`까지 가게 한다

> 구현 파일은 Claude(또는 서브에이전트)가 넣고, lead가 diff를 실제 파일과 대조한 뒤 게이트 · commit한다. 줄 번호는 2026-11-03
> `34192c0` 기준이라 낡을 수 있다 — 고치기 전에 `rg`로 다시 찾는다.

Goal: design 결정 2(usrmerge) · 결정 3(도구)을 넣고, 결정 6의 체인 스물여섯째 `pm/check.sh` 첫 판을 세운다. 끝나면 설치된
디스크로 뜬 TARS에서 사용자 `tars`가 공식 `install.sh`(HEAD)를 돌려 `Installation successful!`을 보고, `brew --version`과
`brew config`(portable-ruby를 받는다)가 답한다. 위험 2 · 3 · 4 · 5의 숫자가 design "실측 (M0)"에 남는다. bottle 설치와 shellenv는
M1이다.

Architecture: 바꾸는 층은 셋이다. 컨테이너의 amd64 sysroot(`devcontainer/Dockerfile`에 `.deb` 몇 개), initrd의 모양
(`kernel/make_initrd.sh`의 `/bin`), 게스트 도구 목록(`kernel/guest_tools.sh`). 우리 Zig 코드는 안 바뀐다. 체인은 `home/check.sh`의
모양(시리얼 FIFO · ISO로 `tars-install --yes` · NVMe로 다시 부팅 · `setpriv`로 사용자 한 줄)을 따르고, SLIRP NIC 하나를 더한다.

## 착수 전에 확인한 것 (2026-11-03, 컨테이너 이미지 `5cd6f526d99f`)

- sysroot에 이미 있다: `usr/bin/chgrp` · `install` · `mktemp`(coreutils), `usr/bin/ldd`(libc-bin, bash 스크립트 5,356바이트),
  `usr/lib/git-core/git-remote-http`(2,399,952바이트)와 `git-remote-https -> git-remote-http` 링크. 목록에만 없었다.
- sysroot에 없다: `usr/bin/tar` · `usr/bin/gzip`(패키지 `tar` · `gzip`), 그리고 `git-remote-http`의 `NEEDED`인
  `libcurl-gnutls.so.4`. 게스트의 `curl`은 OpenSSL 판(`libcurl4t64`)이고 git은 GnuTLS 판을 부른다. `libcurl3t64-gnutls`의
  `Depends`는 `libgnutls30t64` · `libnettle8t64` · `libngtcp2-16` · `libngtcp2-crypto-gnutls8`와 이미 있는 것들(brotli ·
  gssapi · idn2 · ldap · nghttp2/3 · psl · rtmp · ssh2 · zstd · zlib)이다. gnutls는 다시 hogweed · gmp · p11-kit · tasn1 ·
  unistring · ffi를 끌 수 있다.
- 기본 `net`은 `off`다(`init/src/config.zig`의 `net: Net = .off`). 설치 뒤 `tars-config set net=dhcp`를 쳐야 망이 선다.
- 게이트의 `GUEST_MEM`은 512다(`gate_lib.sh`). 위험 4가 이 값에 걸릴 수 있다.
- `install.sh`의 `NONINTERACTIVE=1` 길은 `sudo -n -l mkdir`만 본다 — 같은 tty에 timestamp가 있어야 한다. `${USER}`로 `chown`하므로
  `setpriv`로 사용자가 될 때 `USER` · `HOME`을 함께 준다. `/proc/1/cgroup`에 docker가 없으니 root 판정은 그대로 막는다.

## 무엇을 재나 (design "실측 (M0)"에 적는다)

| 측정 | 무엇 | design의 자리 |
|---|---|---|
| 1 | initrd 바이트(전 · 후), 새로 들어온 `.so`의 이름 · 개수 · 바이트. `git-remote-http` 사슬과 `tar` · `gzip`을 나눠 적는다 | 결정 3, 위험 3 |
| 2 | `install.sh` 전체 시간(TCG)과 그 가운데 `git fetch`의 몫(`==> Downloading and installing Homebrew...` 줄부터 다음 `==>`까지) | 위험 2 |
| 3 | `brew config` 첫 실행 시간(portable-ruby 받기 · 풀기) | 위험 2 |
| 4 | 설치 내내 5초마다 본 `MemAvailable`의 최솟값, OOM이 있었나(`dmesg`의 `Out of memory`) | 위험 4 |
| 5 | `du -sh /home/linuxbrew/.linuxbrew` · `~/.cache/Homebrew`, `df /home` | 위험 4의 디스크 쪽 |
| 6 | 로그에 hostname `(none)`이 나오는 자리가 있나 | 위험 5 |
| 7 | `install.sh` · `brew` 로그에 `file`이 없다는 줄이 있나(`file: command not found` · `No such file … file`) | 결정 3의 `file` 판정 |
| 8 | 체인 전체 시간과 루트 게이트 전체 시간의 변화 | 위험 2 |

## Task 0: 기준값

```
ls -l kernel/initrd.cpio                             # 측정 1의 "전"
gzip -dc kernel/initrd.cpio > /tmp/i.cpio; ls -l /tmp/i.cpio   # 첫 archive만 풀린다(measurements 62) — 그 크기를 적는다
```

컨테이너 안이다. initrd가 없으면 `make initrd`로 먼저 만든다.

## Task 1: Dockerfile — `tar` · `gzip` · GnuTLS 판 libcurl

`devcontainer/Dockerfile`의 amd64 `apt-get download` 목록에 더한다. 각 줄 위에 PM-M0 주석 한 줄(무엇이 부르나).

```
tar:amd64                      # install.sh · brew가 bottle과 portable-ruby(.tar.gz)를 푼다
gzip:amd64                     # tar -z가 PATH에서 부른다
libcurl3t64-gnutls:amd64       # git-remote-http의 NEEDED
libgnutls30t64:amd64
libnettle8t64:amd64
libngtcp2-16:amd64
libngtcp2-crypto-gnutls8:amd64
```

그 뒤 `make_initrd.sh`를 돌리면 `cannot resolve X (needed by …)`가 남은 사슬을 하나씩 알려 준다 — 나오는 대로 그 패키지를
더한다(hogweed · gmp · p11-kit · tasn1 · unistring · ffi 후보). 추측으로 미리 넣지 않는다. 끝나면 Dockerfile 태그(머리의 해시
주석)를 갱신하고, HANDOFF에 `docker rmi tars-devcontainer && make container`를 적는다.

## Task 2: `make_initrd.sh` — `/bin`을 `usr/bin`으로(결정 2)

- `mkdir -p`에서 `"$WORKDIR/bin"`을 빼고, 그 자리에 `ln -s usr/bin "$WORKDIR/bin"`.
- `ln -sf ../usr/bin/bash "$WORKDIR/bin/sh"` → `ln -sf bash "$WORKDIR/usr/bin/sh"`. 링크를 통해서도 `/bin/sh`는 그대로 bash다.
- UT-M0의 머리 주석(`/bin → sh 하나만 산다`)과 `/bin/sh` 문단을 새 모양으로 고친다 — "Debian과 같은 usrmerge. 이유는
  Homebrew `install.sh`의 `/bin/mkdir` 등 절대 경로(PM design 확인 1)".
- 다른 자리가 `$WORKDIR/bin/…`에 파일을 쓰는지 `rg 'WORKDIR/bin|WORKDIR}/bin'`으로 다시 본다(2026-11-03에는 `sh` 하나). 체인
  가운데 `/bin`이 디렉터리라고 가정한 검사가 있는지 `rg -n '/bin/' */check.sh | rg -v usr/bin`으로 본다.

## Task 3: `guest_tools.sh` — 목록에 더한다(결정 3)

```
usr/bin/chgrp:usr/bin/chgrp
usr/bin/install:usr/bin/install
usr/bin/mktemp:usr/bin/mktemp
usr/bin/ldd:usr/bin/ldd
usr/bin/tar:usr/bin/tar
usr/bin/gzip:usr/bin/gzip
usr/lib/git-core/git-remote-http:usr/lib/git-core/git-remote-http
```

- `git-remote-https`는 vi처럼 링크 한 줄로 `make_initrd.sh`에 둔다(`ln -sf git-remote-http …/git-remote-https`) — 두 줄로 적으면
  2.4MB가 두 벌이 된다(UT-M3의 vi 문단과 같은 이유).
- `ldd`는 `#!/bin/bash` 스크립트다. `install_tool` → `copy_lib_deps`가 스크립트를 건너뛰는지(`make_initrd.sh`의 ELF 판정 주석)
  확인한다. `ldd`의 `RTLDLIST`가 가리키는 `/lib64/ld-linux-x86-64.so.2`가 initrd에 있는지 본다.
- `/usr/lib/git-core`를 안 싣는다는 주석(`CONFIG_NET is not set`)을 고친다 — "builtin은 트리 없이 돈다. 네트워크 헬퍼 가운데
  https 하나만 싣는다(PM-M0, Homebrew). ssh · 기타 헬퍼는 안 싣는다."
- `tools/check.sh`는 같은 배열을 source하므로 따로 고칠 것이 없다 — 다만 그 체인이 도구마다 `--version`을 치는지 보고, 친다면
  새 도구가 그 검사를 통과하는지 확인한다.

## Task 4: 체인 스물여섯째 `pm/check.sh`

`home/check.sh`를 복사해 시작하고 필요 없는 판정을 걷어낸다. 부팅 둘이다.

1. ISO + 빈 8GiB NVMe — `tars-install /dev/nvme0n1 --yes`(기본 계정 `tars` · `tars-linux`). 8GiB인 이유: `/home`이 약 7GiB가 되어
   Homebrew(측정 5)가 4GiB 최소 디스크의 `/home`(약 3GiB)에 들어가는지와 섞이지 않게 — 측정 5가 3GiB 안이면 M1에서 줄인다.
2. NVMe만, `-netdev user,id=n0 -device virtio-net-pci,netdev=n0`(`-nic none`을 이것으로 바꾼다).

사전 확인(QEMU 전, 컨테이너에서): `curl -fsS -o /dev/null --max-time 20 https://github.com`과 `https://ghcr.io`. 실패하면
`FAIL: pm: external network unavailable (<url>)`. 같은 자리에서 `install.sh`를 받아 sha256을 로그에 찍는다(`pm: install.sh
sha256 …`) — 게스트가 몇 분 뒤 받는 것과 같다고 가정한다.

부팅 2의 순서(시리얼 root 셸):

1. `tars-config set net=dhcp && tars-config reload`, 그리고 `ip -4 addr show`에 `10.0.2.15`가 뜰 때까지 기다린다.
2. 판정 P1 — `/bin`: `readlink /bin`이 `usr/bin`, `/bin/mkdir --version` · `/bin/chgrp --version`이 답하고 `/bin/sh -c 'echo $BASH_VERSION'`이
   비어 있지 않다.
3. 판정 P2 — 도구: `ldd --version | head -1`에 `2.41`, `tar --version` · `gzip --version` · `install --version` · `mktemp` 한 번,
   그리고 사용자로 `git ls-remote https://github.com/Homebrew/brew HEAD`가 해시 한 줄을 낸다(git의 https 헬퍼와 CA).
4. 측정 4의 표본기를 뒤에 띄운다: `(while :; do awk '/MemAvailable/{print "pm-mem " $2}' /proc/meminfo; sleep 5; done) &`.
5. 판정 P3 — 사용자로 설치. 한 줄로 친다(같은 tty여야 timestamp가 이어진다):
   `setpriv --reuid=1000 --regid=1000 --init-groups env HOME=/home/tars USER=tars LOGNAME=tars HOMEBREW_NO_ANALYTICS=1 bash -c
   'printf "%s\n" tars-linux | sudo -S -k -v && curl -fsSL -o /tmp/pm-install.sh <URL> && NONINTERACTIVE=1 bash /tmp/pm-install.sh;
   echo "pm-install-rc-$?"'`
   `sudo -S -k -v`인 이유는 HP-M2의 함정이다(timestamp가 남아 있으면 파이프의 첫 줄이 명령에게 간다 — `-k`로 언제나 묻게 한다).
   `HOMEBREW_NO_ANALYTICS=1`은 게이트가 Homebrew 통계를 오염시키지 않게 하는 것이고, 사용자의 길과 다른 유일한 환경 변수다.
   기다림은 1800초로 시작하고 측정 2를 본 뒤 줄인다. 판정은 `pm-install-rc-0`과 `Installation successful!`.
6. 판정 P4 — `stat -c '%U' /home/linuxbrew/.linuxbrew`가 `tars`, 사용자로 `/home/linuxbrew/.linuxbrew/bin/brew --version`이
   `Homebrew [0-9]`. 그 줄을 로그에 남긴다(design 결정 6의 "저쪽이 바뀌었나"를 가르는 값).
7. 판정 P5 — 사용자로 `brew config`가 끝나고(시간은 측정 3), `HOMEBREW_PREFIX: /home/linuxbrew/.linuxbrew`와 `Homebrew Ruby:`
   줄에 `portable-ruby`가 있다.
8. 측정 4 · 5 · 6 · 7을 모아 찍는다(`dmesg | grep -c 'Out of memory'`, `du -sh` 둘, `df -h /home`).

`fail`이 넘기는 grep 꼬리에 `==>` · `Error:` · `Warning:` · `sudo:` · `curl:` · `git:`을 넣는다 — 빨개지면 Homebrew의 말이
그대로 보이게.

`GUEST_MEM` 512에서 OOM이 나면(측정 4), 이 체인만 `-m 1024`로 올리고 그 사실을 측정 4와 체인 머리 주석에 적는다. 다른 체인은
안 건드린다.

## Task 5: `check.sh`의 `CHAINS`

`"PM-M0:./pm/check.sh"`를 끝에 더한다. 체인이 루트 게이트에서 가장 긴 것이 되면(측정 8) `CHAINS`의 앞쪽으로 옮겨 lanes가 일찍
잡게 한다 — 배치 규칙은 lessons "게이트 운영"을 따른다. 포트는 안 쓴다(monitor · QMP 없음). 머리 주석에 "바깥 망에 기대는 첫
체인(PM design 확인 6 · 위험 1)"을 적는다.

## Task 6: 실측 · 문서 · 게이트 · 커밋

1. `make quick`(shellcheck가 새 체인을 본다).
2. `./pm/check.sh` 단독으로 초록을 본다. 빨강마다 막힌 자리를 design 결정 3의 기준으로 판정하고(넣는다 · 안 넣는다) design에
   적는다 — 그것이 이 milestone의 본래 일이다.
3. design "실측 (M0)" 절에 측정 1~8. 결정 3의 `file` 판정을 측정 7로 닫는다(M1에서 bottle 경로가 다시 본다).
4. 루트 게이트(`make gate`, 약 11분 + 이 체인). 26/26.
5. commit: `PM-M0: usrmerge /bin, tar gzip ldd git-remote-https, install.sh to brew --version`. HANDOFF의 체인 수 · 컨테이너
   태그를 고친다.

## 시간

Task 1의 컨테이너 재빌드가 5~10분, `make_initrd.sh`의 의존 고리 몇 바퀴, 체인 첫 판들이 TCG의 `install.sh` 시간(모름 — 측정 2)만큼씩
걸린다. 루트 게이트 1회.
