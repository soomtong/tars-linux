# NW-M2 — 주소가 붙는다

Date: 2026-09-13
design: `docs/superpowers/specs/2026-09-13-tars-guest-network-design.md`
앞 milestone: `docs/superpowers/plans/2026-09-13-tars-guest-network-nw-m1.md`

M1이 세운 것은 "커널이 그 장치를 보고 드라이버를 붙였다" 하나다. 게스트에는
아직 주소가 없고 도구도 없다. M2가 그 위에 얹는 것이 이것이다 —
`tars.conf`에 `net=dhcp`를 적은 부팅에서 게스트가 주소를 받고,
`/etc/resolv.conf`가 생기고, 사람이 `ip addr`를 쳐서 볼 수 있다.

우리가 쓰는 코드는 여전히 적다. 링크를 UP으로 올리는 `ioctl` 한 조각과
`dhcpcd`를 띄우는 `fork`/`execve` 하나가 전부다(design 결정 1·6). 나머지는
전부 배선이다 — 설정 키 하나, 게스트 도구 여섯, initrd의 디렉터리 둘과
링크 하나와 hook 둘, Dockerfile의 패키지 목록.

## M2가 정하고 들어가는 것 여섯

M0과 M1이 아홉 자리에 숫자를 붙여 두었다(design 끝의 표 둘). 그중 여섯이
여기서 값으로 확정된다. 나머지 셋(`nc` 링크 · 새 디렉터리 · Dockerfile
목록)은 이미 답이 하나뿐이라 결정이 아니라 실행이다.

### 결정 A — 설정은 디스크로 주되 `debugfs`로 미리 굽는다

M1이 마지막에 알아챈 걸림돌이다. 지금 `net/check.sh`는 디스크를 하나도 안
물어서 게스트에 `/config/tars.conf`가 아예 없다(`init/src/main.zig:147`이 그
경로를 읽는다). design은 갈래 둘을 적고 M2에게 미뤘다 — 설정 디스크를 굽느냐,
커널 cmdline으로 주느냐.

그 갈림을 제3의 길이 없앤다. 컨테이너에 `debugfs`가 이미 있다(e2fsprogs.
`config/make_disk.sh`가 쓰는 `mkfs.ext2`와 같은 패키지다). 2026-09-13에
직접 확인했다.

```
$ debugfs -w -R "write /tmp/tars.conf tars.conf" t.img
debugfs 1.47.2 (1-Jan-2025)
Allocated inode: 12
$ debugfs -R "cat tars.conf" t.img
net=dhcp
```

마운트도 loop 장치도 특권도 필요 없다. 이미지 파일을 파일로 읽고 쓸 뿐이다.
그래서 `net/make_disk.sh`가 ext2를 굽고 그 안에 `net=dhcp` 한 줄짜리
`tars.conf`를 미리 넣는다.

이 길이 갈래 둘의 값을 둘 다 갖는다.

| 무엇 | cmdline | 디스크 + 타이핑 | 디스크 + `debugfs` |
|---|---|---|---|
| 부팅 수 | 하나 | 둘 | 하나 |
| 타이핑 | 없음 | 백 키 남짓 | 없음 |
| `tars.conf`의 키를 읽는가 | 아니다 | 그렇다 | 그렇다 |

마지막 줄이 design이 걱정한 자리다 — cmdline으로 가면 "설정 파일의 키인데
체인은 파일로 안 준다"가 되어 게이트가 증명하는 것과 사람이 쓰는 길이
갈린다. 그 갈림을 만들지 않는다.

라벨은 `tars-net`이다. `init/src/storage.zig`의 `LABEL_PREFIX`가 `tars-`라
(RM-M2가 그렇게 바꿨다) 접두사만 맞으면 잡히고, 게이트 디스크 넷이 이미
`tars-config`·`tars-input`·`tars-power`·`tars-hangul`이다.

### 결정 B — dhcpcd는 감독 밖에 둔다

design 결정 9의 갈래 A다. M0의 실측 4가 근거 전부를 댔다 — dhcpcd는 주소를
받으면 `forked to background`를 찍고 배경으로 내려가면서 PID 1에
재부모화되고(`tars-init: reaped orphan pid 119`), SIGTERM에 죽는다. 즉 감독
목록에 안 넣어도 이미 init의 자식이고 `reapAll()`이 그것을 센다.

감독 루프에 넣는 것(갈래 B)은 "죽으면 다시 띄운다"를 원할 때의 일이다. 그
값이 지금 없다 — 리스가 끊기는 상황을 이 게이트가 만들지 않고, dhcpcd 자신이
갱신 타이머를 갖고 있다. 그리고 넣으면 `Child` 배열이 셋이 되면서
`boot/check.sh`가 정확히 세고 있는 재시작 횟수 같은 것들에 새 변수가 는다.

### 결정 C — `/etc/resolv.conf`는 dhcpcd의 hook이 쓴다

M0의 실측 6이 갈래 둘을 적고 첫째가 낫다고 했다. 그대로 간다. 실기에서도
맞고, DHCP 옵션을 우리가 파싱하지 않아도 된다.

넣을 파일이 둘이다. 2026-09-13에 `.deb`를 풀어 경로를 확인했다.

```
usr/lib/dhcpcd/dhcpcd-run-hooks              8,205   #!/bin/sh
usr/lib/dhcpcd/dhcpcd-hooks/20-resolv.conf   6,164   (셔뱅 없음. run-hooks가 . 로 읽는다)
```

`30-hostname`·`50-timesyncd.conf`·`01-test`는 안 넣는다. `dhcpcd-run-hooks`가
그 디렉터리를 훑어 있는 것만 돌리므로 빼는 데 비용이 없다.

한 가지 주의가 있고 그것이 결정 F로 이어진다. `20-resolv.conf`는 POSIX 셸
스크립트이고 `sed`·`rm`·`cat`·`tail`·`head`·`mkdir`·`chmod`를 이름으로
부른다. 일곱 다 게스트에 이미 있지만 `PATH`가 있어야 이름이 손에 닿는다.
`resolvconf`도 열세 번 나오는데 그것은 `type resolvconf`로 있는지 물어보고
없으면 직접 쓰는 갈래다 — 우리 게스트에는 없으므로 직접 쓴다.

### 결정 D — 인터페이스 이름은 `eth0` 상수다

`/sys/class/net`을 훑어 `lo`가 아닌 첫 장치를 고르는 쪽이 일반적이지만, init에
libc도 힙도 없어서 디렉터리 순회는 `getdents64`를 직접 다루는 일이다
(`devices.zig`가 evdev에 대해 그것을 피하려고 `event0`부터 서른둘을 열어
보는 이유가 이것이다). 이름이 번호가 아니라서 그 수법도 못 쓴다.

지금 필요한 것은 이름 하나다. 커널에 켠 NIC 드라이버가 `CONFIG_VIRTIO_NET`
하나뿐이고(M1의 실측 13), 실머신 NIC는 design 비목표 1이다. 그래서 상수
`eth0`으로 두되, `ioctl`을 부르기 전에 `/sys/class/net/eth0`이 있는지 한 번
열어 본다 — 없으면 로그가 "장치가 없다"라고 말하고, 있는데 `ioctl`이 실패하면
로그가 그것과 다른 말을 한다. 두 실패가 갈리는 것이 이 한 줄의 값이다.

### 결정 E — `curl`을 넣는다

design 결정 10에서 사용자가 5.9MB를 알고 넣기로 정했다. M0의 실측 3이 그
값을 실측으로 바꿨다 — 새 라이브러리 20개에 10,927,904바이트이고, initrd 증가분
13MB의 86%가 이것 하나다.

게이트 판정에는 안 쓴다(실측 5가 답했다). 사람이 쓰는 도구로 넣는 것이고,
그래서 M2의 체인은 `curl`을 한 번도 안 친다.

### 결정 F — dhcpcd는 env 블록이 지어진 뒤에 띄운다

`main.zig`에서 `envp`는 `resolveShell`이 끝난 뒤에 지어진다(SM-M2가 그리로
내렸다. `HISTFILE`이 셸마다 다르기 때문이다). 그런데 dhcpcd의 hook이
`sed`·`rm`을 이름으로 부르므로 `PATH`가 필요하고, `PATH`는 그 블록에 있다
(`environ.PATH_ENTRY = /usr/bin:/bin`).

그래서 네트워크를 올리는 자리가 `envp` 다음, `children` 배열 앞이다. 이
순서를 틀리면 증상이 조용하다 — 주소는 붙고 `/etc/resolv.conf`만 안 생긴다.

## 고칠 파일

| 파일 | 무엇 | 커밋 |
|---|---|---|
| `devcontainer/Dockerfile` | `apt-get download` 목록에 도구 넷과 라이브러리 스물 남짓 | 1 |
| `kernel/guest_tools.sh` | 도구 여섯(`dhcpcd`·`ip`·`curl`·`nc.traditional`·`pgrep`·`kill`) | 2 |
| `kernel/make_initrd.sh` | `nc` 링크 · `/var/lib/dhcpcd`와 `/run` · hook 둘 | 2 |
| `init/src/config.zig` | `Net` enum · `net` 키 · `save()`의 새 블록 | 3 |
| `init/src/config_test.zig` | `net` 파싱 검사 | 3 |
| `init/src/net.zig` | 새 파일. 링크를 올리고 dhcpcd를 띄운다 | 4 |
| `init/src/main.zig` | 배선 한 줄과 로그 | 4 |
| `net/make_disk.sh` | 새 파일. `tars-net` 라벨 + 미리 구운 `tars.conf` | 5 |
| `net/check.sh` | 디스크를 물리고 주소 판정 넷을 더한다 | 5 |
| design · `HANDOFF.md` | 실측과 현황 | 6 |

`check.sh`의 `CHAINS`는 이번에도 안 고친다. 그것은 M3다.

## Task 0 — baseline을 적어 두고 `/tmp/nw`를 다시 세운다

M0과 M1이 남긴 값과 대조할 자리가 여럿이라 먼저 적어 둔다.

- [ ] Step 1: 지금 initrd와 커널의 크기를 잰다

```bash
cd /Users/dp/Repository/tars-linux
mkdir -p /tmp/nw
ls -l kernel/initrd.cpio 2>/dev/null || echo "(initrd가 아직 없다 — 빌드가 처음부터 돈다)"
ls -l kernel/build/arch/x86/boot/bzImage 2>/dev/null || echo "(커널이 아직 없다)"
git status --short
```

기대: `git status`가 깨끗하다. `bzImage`가 있으면 4,486,144바이트다(M1의 값).

- [ ] Step 2: `debugfs`가 있는 것을 다시 확인한다

결정 A가 통째로 이것에 얹혀 있다. 이미지를 다시 굽기 전에 먼저 본다.

```bash
docker run --rm tars-devcontainer bash -c '
cd /tmp && truncate -s 16M t.img && mkfs.ext2 -F -q -m 0 -L tars-net t.img
printf "net=dhcp\n" > c.conf
debugfs -w -R "write /tmp/c.conf tars.conf" t.img 2>&1 | tail -1
debugfs -R "cat tars.conf" t.img 2>&1 | tail -1'
```

기대: `Allocated inode: 12`와 `net=dhcp`. 안 되면 결정 A를 버리고 design이
적은 갈래 둘 중 하나로 돌아간다(그때는 커널 cmdline 쪽이 싸다 — 그 대신
게이트가 증명하는 것이 `tars.conf`가 아니게 된다는 것을 design에 적는다).

## Task 1 — Dockerfile에 적을 패키지 이름을 실측으로 구한다

M0의 실측 10이 이 Task의 이유다. `apt-get download`는 의존을 안 따라오므로
목록이 언제나 명시적이어야 하는데(Dockerfile 59번 줄), 우리가 필요한 것은
apt의 의존 닫힘 78개가 아니라 `copy_lib_deps`가 실제로 찾는 SONAME 23개를
담은 패키지들이다. 그 둘은 다른 집합이다.

짐작으로 적지 않는다. 컨테이너 안에서 SONAME → `.deb` 대응을 직접 구한다.

- [ ] Step 1: 닫힘을 받아서 SONAME이 어느 `.deb`에 있는지 센다 (약 2분)

```bash
cd /Users/dp/Repository/tars-linux
docker run --rm -v /tmp/nw:/tmp/nw tars-devcontainer bash -c '
set -e
apt-get update -qq
mkdir -p /tmp/w && cd /tmp/w

# M0의 실측 10과 같은 방법. 도구 넷의 의존 닫힘을 구한다.
pkgs="$(apt-cache depends --recurse --no-recommends --no-suggests \
        --no-conflicts --no-breaks --no-replaces --no-enhances \
        dhcpcd-base curl iproute2 netcat-traditional procps \
        | grep "^\w" | sort -u)"
echo "$pkgs" | wc -l
for p in $pkgs; do apt-get download -qq "${p}:amd64" >/dev/null 2>&1 || true; done
ls *.deb | wc -l

# 각 .deb가 담은 .so를 훑어, 우리가 새로 필요로 하는 SONAME과 맞춘다.
for d in *.deb; do
  dpkg-deb -c "$d" | grep -oE "[^/]+\.so(\.[0-9]+)*$" | sed "s|^|${d%%_*} |"
done | sort -u > /tmp/nw/soname_to_pkg.txt
wc -l /tmp/nw/soname_to_pkg.txt
'
```

- [ ] Step 2: M0이 센 23개를 그 표에 넣어 패키지 이름을 뽑는다

```bash
cd /Users/dp/Repository/tars-linux
for so in libcurl.so.4 libnghttp2.so.14 libnghttp3.so.9 libidn2.so.0 \
          libunistring.so.5 librtmp.so.1 libpsl.so.5 libgnutls.so.30 \
          libp11-kit.so.0 libnettle.so.8 libhogweed.so.6 libgmp.so.10 \
          libtasn1.so.6 libffi.so.8 libldap.so.2 liblber.so.2 \
          libsasl2.so.2 libbrotlidec.so.1 libbrotlicommon.so.1 \
          libbpf.so.1 libelf.so.1 libmnl.so.0; do
  printf '%-24s %s\n' "$so" \
    "$(awk -v s="$so" '$2==s {print $1}' /tmp/nw/soname_to_pkg.txt | sort -u | tr '\n' ' ')"
done
```

기대: 스물둘 전부에 패키지 이름이 하나씩 붙는다. 빈칸이 나오면 그 SONAME이
닫힘 밖에 있는 것이므로 `apt-cache search`로 따로 찾는다.

`libssl.so.3`은 이 목록에 없다 — 이미 Dockerfile에 `libssl3t64`가 있다
(UT-M2가 libgit2 사슬로 데려왔다). `libz`·`libzstd`도 같다. M0의 스물
중에서 이미 있는 것을 뺀 수가 이 목록의 길이다.

- [ ] Step 3: 도구 쪽 패키지 이름도 확인한다

```bash
cd /Users/dp/Repository/tars-linux
docker run --rm tars-devcontainer bash -c '
apt-get update -qq
for p in dhcpcd-base curl iproute2 netcat-traditional procps; do
  printf "%-20s %s\n" "$p" "$(apt-cache policy "$p" | sed -n "s/ *Candidate: //p")"
done'
```

기대: 다섯 다 후보 버전이 나온다. `procps`는 이미 Dockerfile에 있다
(UT-M1이 `ps`·`top` 때문에 넣었다) — `pgrep`·`kill`이 같은 패키지에서 온다는
것이 실측 3b가 "공짜"라고 한 이유다.

## Task 2 — Dockerfile을 고치고 이미지를 다시 굽는다

design 위험 7이 이 Task다. 목록을 고치면 그 뒤 레이어가 전부 다시 돌고,
이미지 빌드에는 네트워크가 필요하다.

- [ ] Step 1: `apt-get download` 목록에 줄을 더한다

`devcontainer/Dockerfile`의 `dpkg --add-architecture amd64` 블록 안이다.
도구 넷(`procps`는 이미 있다)과 Task 1이 구한 라이브러리들을 더한다. 기존
줄들과 같은 모양으로 `:amd64`를 붙인다 — architecture: all인 패키지만
안 붙인다(`fish-common`·`zsh-common`·`ncurses-base`가 그 예다).

그 앞에 주석 블록을 더한다. 기존 주석들이 milestone마다 "무엇을 왜 더했나"를
적고 있으므로 같은 결로 쓴다. 담을 것 넷이다.

- NW-M2가 도구 넷을 더한다는 것과 각각이 무엇인지
- `dhcpcd`가 새 라이브러리를 0개 데려온다는 것(M0 실측 3). 그리고 그 이유가
  `libssl3t64`·`libudev1`이 패키지 의존이지 바이너리 의존이 아니기 때문이라는 것
- `curl` 하나가 스물을 데려오고 그것이 이 목록이 길어진 이유 전부라는 것
- `ip`의 셋(`libbpf`·`libelf`·`libmnl`)

- [ ] Step 2: 무엇이 더해졌는지 읽는다

```bash
cd /Users/dp/Repository/tars-linux
git diff --stat devcontainer/Dockerfile
echo "=== 지운 줄 (하나도 없어야 한다) ==="
git diff devcontainer/Dockerfile | grep '^-' | grep -v '^---' || echo "(하나도 없다)"
echo "=== 더한 줄 ==="
git diff devcontainer/Dockerfile | grep '^+' | grep -v '^+++'
```

기대: 지운 줄이 하나도 없다. 이 Task는 목록을 넓히기만 한다.

- [ ] Step 3: 이미지를 다시 굽는다 (오래 걸린다. 배경으로 돌린다)

```bash
cd /Users/dp/Repository/tars-linux
{ time docker build -t tars-devcontainer devcontainer/ ; } \
  > /tmp/nw/m2_image.log 2> /tmp/nw/m2_image.time
```

- [ ] Step 4: sysroot에 여섯이 들어갔는지 본다

```bash
cd /Users/dp/Repository/tars-linux
tail -5 /tmp/nw/m2_image.time
docker run --rm tars-devcontainer bash -c '
for f in usr/sbin/dhcpcd usr/bin/curl usr/bin/ip usr/bin/nc.traditional \
         usr/bin/pgrep usr/bin/kill \
         usr/lib/dhcpcd/dhcpcd-run-hooks usr/lib/dhcpcd/dhcpcd-hooks/20-resolv.conf; do
  if [ -f "/usr/local/amd64-sysroot/$f" ]; then echo "  있다   $f"; else echo "  없다   $f"; fi
done'
```

기대: 여덟 다 "있다". 하나라도 없으면 그 파일을 담은 패키지가 목록에 없는
것이다 — `dhcpcd-base`가 hook 둘을 함께 담으므로 hook이 없으면 그 패키지가
안 받아진 것이다.

- [ ] Step 5: 커밋한다

```bash
cd /Users/dp/Repository/tars-linux
git add devcontainer/Dockerfile
git diff --cached --stat
git commit -m "Stock the sysroot with a DHCP client and the tools to see it work"
```

## Task 3 — 게스트에 도구 여섯과 파일 넷을 넣는다

- [ ] Step 1: `kernel/guest_tools.sh`에 층 5를 더한다

배열 맨 끝에 붙인다. 기존 층들과 같은 모양으로 주석을 먼저 쓴다.

```bash
  # ── 층 5 · 네트워크 4 ──────────────────────────────────────────────────
  # NW-M2. 이 여섯 줄이 게스트가 밖으로 나가는 데 필요한 전부다.
  #
  # dhcpcd의 자리가 왼쪽과 오른쪽이 다른 넷째 자리다(mawk→awk · fdfind→fd ·
  # vim.tiny→vi에 이어). 이유는 앞의 셋과 다르다 — 이름 충돌도 alternatives도
  # 아니고 PATH다. environ.zig의 PATH_ENTRY가 /usr/bin:/bin이라
  # /usr/sbin에 둔 것은 이름으로 안 불린다. M0의 첫 회차가 여기서 통째로
  # 죽었다(`fish: Unknown command: dhcpcd`).
  #
  # 새 라이브러리 수가 도구마다 크게 다르다(M0 실측 3. 푼 것 기준).
  #   dhcpcd          388,416   새 라이브러리 0개
  #   nc.traditional   35,032   0개
  #   ip              721,912   3개 (libbpf · libelf · libmnl)
  #   curl            321,880   20개, 10,927,904바이트
  # curl 하나가 이 층 비용의 86%다. 사용자가 그 값을 알고 넣기로 정했다
  # (design 결정 10) — 네트워크가 생겼으므로 UT가 감수한 libgit2 사슬 열여섯이
  # 비로소 값을 한다는 것이 근거다.
  #
  # nc는 traditional판이다. openbsd판은 libbsd를 더 부른다. 그리고 게스트에
  # `nc`라는 이름을 세우는 것은 여기가 아니라 make_initrd.sh의 링크 한 줄이다
  # (결정 11 — alternatives 링크는 dpkg -x로 푼 sysroot에 없다).
  usr/sbin/dhcpcd:usr/bin/dhcpcd
  usr/bin/ip:usr/bin/ip
  usr/bin/curl:usr/bin/curl
  usr/bin/nc.traditional:usr/bin/nc.traditional

  # pgrep·kill은 procps에서 오고 libproc2가 이미 initrd에 있다(ps가 데려왔다).
  # 둘이 62,184바이트에 새 라이브러리 0개다(M0 실측 3b). M3의 체인이
  # "dhcpcd가 살아 있나"를 물을 때 쓴다.
  usr/bin/pgrep:usr/bin/pgrep
  usr/bin/kill:usr/bin/kill
```

- [ ] Step 2: `kernel/make_initrd.sh`에 넷을 더한다

`ln -sf less "$WORKDIR/usr/bin/pager"` 근처, 링크를 거는 자리들 뒤에 붙인다.

```bash
# NW-M2 결정 11. Debian의 /usr/bin/nc는 alternatives가 만드는 링크이고 실체가
# nc.traditional이다. alternatives 링크는 패키지의 postinst가 만드는 것이라
# dpkg -x로 푼 sysroot에 없다 — pager·vi·editor와 글자 그대로 같은 자리다.
# 다른 점은 이 이름을 우리가 골랐다는 것이다: 사람이 `nc`라고 친다.
ln -sf nc.traditional "$WORKDIR/usr/bin/nc"

# NW-M2. dhcpcd가 쓰는 자리 둘(M0 실측 7). 리스는 /var/lib/dhcpcd/eth0.lease에
# 쓰고(10.x는 /var/db가 아니다), /run/dhcpcd는 /run만 있으면 자기가 만든다.
# 지금 initrd에는 /var도 /run도 아예 없다 — UT-M0이 /bin·/tmp·/etc 셋을
# 더한 것과 같은 자리다.
mkdir -p "$WORKDIR/var/lib/dhcpcd" "$WORKDIR/run"

# NW-M2 결정 C. dhcpcd는 주소를 받으면 hook을 부르고, 그 hook이
# /etc/resolv.conf를 쓴다. M0의 실측 6이 이것이 없을 때 무슨 일이 생기는지
# 봤다 —
#
#   eth0: executing: /usr/lib/dhcpcd/dhcpcd-run-hooks BOUND
#   script_run: /usr/lib/dhcpcd/dhcpcd-run-hooks: No such file or directory
#
# 주소는 붙는데 이름만 안 풀린다. install_tool이 바이너리 하나만 복사하기
# 때문이고, 증상이 조용해서 원인에서 멀다.
#
# 경로를 바꾸면 안 된다. dhcpcd가 이 자리를 컴파일 타임에 박아 두고 찾는다 —
# zsh 모듈 트리가 sysroot와 같은 경로를 유지해야 하는 것과 같은 이유다.
#
# 넷 중 둘만 넣는다. 30-hostname은 hostname을 부르고(게스트에 없다),
# 50-timesyncd.conf는 systemd가 있을 때의 것이며, 01-test는 이름대로다.
# dhcpcd-run-hooks가 그 디렉터리를 훑어 있는 것만 돌리므로 빼는 데 비용이 없다.
#
# 20-resolv.conf가 이름으로 부르는 것은 sed·rm·cat·tail·head·mkdir·chmod
# 일곱이고 전부 게스트에 있다. resolvconf도 열세 번 나오지만 그것은 있는지
# 물어보고 없으면 직접 쓰는 갈래다.
mkdir -p "$WORKDIR/usr/lib/dhcpcd/dhcpcd-hooks"
cp "$SYSROOT/usr/lib/dhcpcd/dhcpcd-run-hooks" "$WORKDIR/usr/lib/dhcpcd/"
cp "$SYSROOT/usr/lib/dhcpcd/dhcpcd-hooks/20-resolv.conf" \
   "$WORKDIR/usr/lib/dhcpcd/dhcpcd-hooks/"
chmod 0755 "$WORKDIR/usr/lib/dhcpcd/dhcpcd-run-hooks"
```

- [ ] Step 3: initrd를 만들어 before/after를 잰다

```bash
cd /Users/dp/Repository/tars-linux
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd kernel && ./build.sh >/dev/null 2>&1
  cd ../init && zig build >/dev/null 2>&1
  cd ../terminal && ./prepare.sh >/dev/null 2>&1
  cd ../kernel && ./make_initrd.sh'
ls -l kernel/initrd.cpio
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf /tmp/x && mkdir -p /tmp/x && cd /tmp/x
  gzip -dc /workspace/kernel/initrd.cpio | cpio -idm --quiet
  echo "푼 것: $(du -sb . | cut -f1)"
  echo "라이브러리 수: $(find . -name "*.so*" | wc -l)"
  echo "=== 여섯이 들어갔나 ==="
  for f in usr/bin/dhcpcd usr/bin/ip usr/bin/curl usr/bin/nc.traditional \
           usr/bin/nc usr/bin/pgrep usr/bin/kill \
           usr/lib/dhcpcd/dhcpcd-run-hooks \
           usr/lib/dhcpcd/dhcpcd-hooks/20-resolv.conf; do
    if [ -e "$f" ]; then echo "  있다   $f"; else echo "  없다   $f"; fi
  done
  echo "=== 디렉터리 둘 ==="
  ls -ld var/lib/dhcpcd run'
```

기대: 압축 40.5MB 근처, 푼 것 103MB 근처, 라이브러리 95개(M0 실측 3의 값).
M0은 `nc`를 링크로 안 걸었으므로 이번에는 그 링크가 하나 더 있다.

`make_initrd.sh`가 SONAME을 찍고 죽으면 Task 2의 목록에 빠진 것이 있다 —
그 메시지가 이미 어느 패키지를 더하라고 말한다.

- [ ] Step 4: 커밋한다

```bash
cd /Users/dp/Repository/tars-linux
git add kernel/guest_tools.sh kernel/make_initrd.sh
git diff --cached --stat
git commit -m "Put a DHCP client and its hooks in the guest"
```

## Task 4 — `tars.conf`에 `net` 키를 만든다

design 결정 5다. 값은 `off`(기본)와 `dhcp` 둘이고, 기본값이 꺼짐인 것이
기존 부팅 아홉과 체인 열하나를 지킨다.

- [ ] Step 1: `init/src/config.zig`에 enum과 필드와 파싱을 더한다

`ShellConfig` 바로 아래에 enum을 둔다.

```zig
/// 이 기계가 네트워크를 켜는가(NW design 결정 5).
///
/// 기본값이 `off`인 것이 게이트를 지킨다. 부팅 수십 개가 전부 DHCP 응답을
/// 기다리면 시간이 늘고 잡음도 는다 — 기본값을 꺼짐으로 두고 네트워크 체인만
/// 켜면 기존 부팅의 시간이 한 밀리초도 안 는다.
///
/// `static:...` 같은 셋째 값은 안 만든다. 만들 근거가 아직 없고, 쓸 자리가
/// 생기면 그때 더한다.
pub const Net = enum {
    off,
    dhcp,
};
```

`Config`에 필드를 더한다. 위치는 `shell_config` 다음이다 — `save()`가 필드
순서대로 쓰므로 씨앗 파일에서도 맨 뒤가 되고, 그러면 `config/check.sh`가
화면에서 보는 `shell_config=on` 줄이 위로 안 밀린다.

```zig
    /// 기본값이 `off`인 유일한 키다. 다른 다섯은 "이 기계를 쓰는 사람이
    /// 쓰는 것"이 기본값인데(keyboard=apple · hangul_layout=shin_pcs),
    /// 이 키는 근거가 다르다 — 켜는 비용이 부팅마다 붙기 때문이다.
    net: Net = .off,
```

`parse()`에 분기를 더한다. `shell_config`와 글자 그대로 같은 모양이다.

```zig
        } else if (std.mem.eql(u8, key, "net")) {
            // shell·keyboard·자판 둘·shell_config와 완전히 같은 모양이다.
            c.net = std.meta.stringToEnum(Net, value) orelse {
                std.debug.print("tars-init: unknown net '{s}', falling back to {s}\n", .{
                    value, @tagName(c.net),
                });
                continue;
            };
```

`save()`의 형식 문자열 끝에 블록을 더한다.

```zig
        \\# net: off | dhcp
        \\#   dhcp면 init이 eth0을 UP으로 올리고 dhcpcd를 띄운다. 주소도
        \\#   라우트도 /etc/resolv.conf도 dhcpcd가 쓴다
        \\net={s}
```

인자 목록 끝에 `@tagName(c.net)`을 더한다.

- [ ] Step 2: `init/src/config_test.zig`를 넓힌다

`expect` 헬퍼가 필드를 하나씩 비교하므로 거기에 `net`을 더해야 한다
(`config_test.zig:57~87`). 빼먹으면 아래 검사들이 전부 통과하는데 아무것도
안 보는 상태가 된다 — SC-M0이 여섯째 필드에 대해 같은 자리에 주석을 남겼다.

그리고 `main()`에 검사 다섯을 더한다. `shell_config`의 것과 같은 모양이다.

```zig
    try expect("net=dhcp\n", .{ .net = .dhcp });
    try expect("net=off\n", .{});
    try expect("net=on\n", .{}); // enum에 없는 값
    try expect("net=\n", .{}); // 값 없음
    try expect("shell=zsh\nnet=dhcp\n", .{ .shell = .zsh, .net = .dhcp });
```

- [ ] Step 3: 호스트 검사를 돌린다

```bash
cd /Users/dp/Repository/tars-linux
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf init/.zig-cache init/zig-out; cd init && zig build && zig build test'
```

기대: 조용히 끝난다. 캐시 삭제를 컨테이너 안에서 하는 이유는 HANDOFF의
"⚠ 캐시는 컨테이너 안에서 지운다"에 있다.

- [ ] Step 4: 커밋한다

```bash
cd /Users/dp/Repository/tars-linux
git add init/src/config.zig init/src/config_test.zig
git diff --cached --stat
git commit -m "Let tars.conf ask for a network"
```

## Task 5 — 링크를 올리고 dhcpcd를 띄운다

우리가 이 서브프로젝트에서 쓰는 코드의 전부다. design 결정 6이 경계를
그었다 — init이 하는 일은 둘이고(설정을 읽는 것과 링크를 UP으로 올리는 것),
주소를 받는 것도 라우트를 넣는 것도 `/etc/resolv.conf`를 쓰는 것도 전부
dhcpcd가 한다.

링크를 올리는 것까지 dhcpcd에게 맡길 수도 있다. 그래도 우리가 하는 이유는
순서를 우리가 쥐기 위해서다 — 인터페이스가 올라온 것을 확인한 뒤에 dhcpcd를
띄우면, 실패했을 때 어느 단계에서 실패했는지가 로그로 갈린다.

- [ ] Step 1: `init/src/net.zig`를 만든다

```zig
const std = @import("std");
const linux = std.os.linux;
const config = @import("config.zig");

/// config.zig·main.zig와 같은 세 줄짜리 헬퍼다. 넷째 자리라 슬슬 sys.zig로
/// 모을 때가 됐지만, 이 milestone에서 하지 않는다 — 파일 넷을 한꺼번에
/// 건드리는 변경과 새 층을 세우는 변경을 같은 커밋에 섞지 않는다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// 이 기계가 쓰는 인터페이스 이름(design 결정 D).
///
/// 상수인 이유는 init에 libc도 힙도 없기 때문이다. `/sys/class/net`을 훑어
/// `lo`가 아닌 첫 장치를 고르려면 `getdents64`를 직접 다뤄야 하는데,
/// `devices.zig`가 evdev에 대해 그것을 피하려고 event0부터 서른둘을 열어
/// 보고 있다. 그쪽은 이름이 번호라서 그 수법이 섰고 여기는 안 선다.
///
/// 지금 필요한 이름이 하나뿐인 근거는 커널에 있다 — 켠 NIC 드라이버가
/// CONFIG_VIRTIO_NET 하나다(M1 실측 13). 실머신 NIC는 design 비목표 1이고,
/// 그것이 들어오는 날 이 상수가 디렉터리 순회로 바뀐다.
pub const IFACE: []const u8 = "eth0";

/// 장치가 있는지 먼저 묻는 자리. sysfs는 커널이 드라이버를 붙이면서 직접
/// 만든다(M1 실측 14) — 이 경로가 없으면 드라이버가 안 붙은 것이고,
/// 있는데 ioctl이 실패하면 다른 실패다. 두 실패가 로그에서 갈리는 것이
/// 이 한 번의 open이 하는 일 전부다.
const SYS_IFACE: [:0]const u8 = "/sys/class/net/eth0";

/// include/uapi/linux/sockios.h. 이름이 아니라 숫자로 적는 이유는 Zig의
/// linux 바인딩에 이 상수가 없기 때문이고, 커널 ABI라 안 바뀐다.
const SIOCGIFFLAGS: u32 = 0x8913;
const SIOCSIFFLAGS: u32 = 0x8914;

/// include/uapi/linux/if.h. IFF_UP 하나만 세운다 — IFF_RUNNING은 커널이
/// 링크 상태를 보고 자기가 세우는 것이라 우리가 쓰면 거짓말이 된다.
const IFF_UP: u16 = 0x1;

/// include/uapi/linux/if.h의 struct ifreq.
///
/// 이름 16바이트 뒤에 오는 것은 union이고 그중 가장 큰 것이 struct
/// sockaddr(16바이트)이다. 그래서 전체가 32바이트다. flags는 그 union의
/// 첫 2바이트를 빌려 쓰는 것이고, 나머지 14바이트는 커널이 안 보지만
/// 구조체 크기가 맞아야 한다.
const ifreq = extern struct {
    name: [16]u8,
    flags: u16,
    _pad: [14]u8,
};

/// dhcpcd가 사는 자리. guest_tools.sh가 usr/sbin/dhcpcd를 여기로 넣는다 —
/// PATH가 /usr/bin:/bin이라 /usr/sbin은 이름으로 안 닿는다(M0 실측 8).
/// 그 파일의 오른쪽과 이 상수가 어긋나면 증상이 execve 실패 하나뿐이다.
const DHCPCD_PATH: [:0]const u8 = "/usr/bin/dhcpcd";

/// `/sys/class/net/eth0`이 있는가.
fn ifacePresent() bool {
    const rc = linux.open(SYS_IFACE.ptr, .{ .ACCMODE = .RDONLY, .DIRECTORY = true }, 0);
    if (failed(rc) != null) return false;
    _ = linux.close(@intCast(rc));
    return true;
}

/// 링크를 UP으로 올린다. 성공하면 true.
///
/// 읽고-고쳐-쓰는 이유는 flags가 비트 묶음이기 때문이다. SIOCSIFFLAGS는
/// 통째로 덮어쓰므로 IFF_UP만 담아 보내면 커널이 세워 둔 다른 비트를
/// 지우게 된다.
fn linkUp() bool {
    // 주소를 다루는 ioctl이라 소켓이 필요하다. 어느 소켓이든 되지만
    // AF_INET/SOCK_DGRAM이 관습이고, 이 커널에 INET이 있다(결정 2).
    const srv = linux.socket(linux.AF.INET, linux.SOCK.DGRAM, 0);
    if (failed(srv)) |e| {
        std.debug.print("tars-init: cannot open a socket to bring {s} up (errno {d})\n", .{
            IFACE, @intFromEnum(e),
        });
        return false;
    }
    const fd: i32 = @intCast(srv);
    defer _ = linux.close(fd);

    var req = ifreq{ .name = [_]u8{0} ** 16, .flags = 0, ._pad = [_]u8{0} ** 14 };
    @memcpy(req.name[0..IFACE.len], IFACE);

    if (failed(linux.ioctl(fd, SIOCGIFFLAGS, @intFromPtr(&req)))) |e| {
        std.debug.print("tars-init: cannot read the flags of {s} (errno {d})\n", .{
            IFACE, @intFromEnum(e),
        });
        return false;
    }
    if (req.flags & IFF_UP != 0) {
        std.debug.print("tars-init: {s} was already up\n", .{IFACE});
        return true;
    }

    req.flags |= IFF_UP;
    if (failed(linux.ioctl(fd, SIOCSIFFLAGS, @intFromPtr(&req)))) |e| {
        std.debug.print("tars-init: cannot bring {s} up (errno {d})\n", .{
            IFACE, @intFromEnum(e),
        });
        return false;
    }
    // net/check.sh가 이 줄을 grep한다.
    std.debug.print("tars-init: net link {s} is up\n", .{IFACE});
    return true;
}

/// dhcpcd를 띄운다. 감독 목록에 안 넣는다(design 결정 9의 갈래 A).
///
/// 근거가 M0의 실측 4다. dhcpcd는 주소를 받으면 `forked to background`를
/// 찍고 배경으로 내려가는데, 그러면 부모가 죽으면서 PID 1에 재부모화된다
/// (`tars-init: reaped orphan pid 119`). 즉 감독 목록에 없어도 이미 init의
/// 자식이고 `reapAll()`이 그것을 센다. 그리고 SIGTERM에 죽으므로 SL-M2가
/// 세운 `grace period expired` 판정에 안 걸린다.
///
/// envp를 받는 것이 중요하다(결정 F). dhcpcd가 주소를 받으면 hook을 부르고
/// 그 hook이 sed·rm·cat을 이름으로 부른다 — PATH가 없으면 주소는 붙는데
/// /etc/resolv.conf만 안 생긴다. 그래서 이 함수는 main()에서 env 블록이
/// 지어진 뒤에 불려야 한다.
fn startDhcpcd(envp: [*:null]const ?[*:0]const u8) void {
    const pid = linux.fork();
    if (failed(pid)) |e| {
        std.debug.print("tars-init: cannot fork for dhcpcd (errno {d})\n", .{
            @intFromEnum(e),
        });
        return;
    }
    if (pid == 0) {
        const argv = [_:null]?[*:0]const u8{ DHCPCD_PATH.ptr, "eth0", null };
        _ = linux.execve(DHCPCD_PATH.ptr, &argv, envp);
        // 여기 닿았다는 것은 execve가 실패했다는 뜻이다.
        std.debug.print("tars-init: cannot exec {s}\n", .{DHCPCD_PATH});
        linux.exit(127);
    }
    // net/check.sh가 이 줄을 grep한다.
    std.debug.print("tars-init: started dhcpcd on {s} (pid {d})\n", .{ IFACE, pid });
}

/// 설정이 실제 동작이 되는 자리. `main()`이 부르는 것은 이 함수 하나다.
///
/// `off`일 때 아무 말도 안 하지 않는다. 침묵은 "안 켰다"와 "켜려다 실패했다"를
/// 못 가르고, 이 저장소가 그 값을 여러 번 지불했다.
pub fn bringUp(want: config.Net, envp: [*:null]const ?[*:0]const u8) void {
    if (want == .off) {
        std.debug.print("tars-init: net=off, leaving the network alone\n", .{});
        return;
    }
    if (!ifacePresent()) {
        std.debug.print("tars-init: net=dhcp but there is no {s} under /sys/class/net\n", .{
            IFACE,
        });
        return;
    }
    if (!linkUp()) return;
    startDhcpcd(envp);
}
```

- [ ] Step 2: `init/src/main.zig`를 배선한다

`const net = @import("net.zig");`를 import 목록에 더하고, 호출 한 줄을
`envp` 블록의 로그 뒤, `shell_flag` 앞에 둔다.

```zig
    // NW-M2. envp 다음인 것이 이 한 줄의 유일한 제약이다(design 결정 F) —
    // dhcpcd의 hook이 sed·rm을 이름으로 부르므로 PATH가 필요하고, 그 값은
    // 방금 지은 블록에 있다. 순서를 틀리면 증상이 조용하다: 주소는 붙고
    // /etc/resolv.conf만 안 생긴다.
    //
    // 실패해도 부팅을 안 막는다. 네트워크가 없는 기계는 이 저장소가 지금까지
    // 돌려 온 상태 그 자체이고, 못 켠 이유는 로그에 있다.
    net.bringUp(cfg.net, envp);
```

그리고 `config shell=` 로그 줄에 `net={s}`를 더한다. 줄을 새로 만들지 않는
이유는 HI-M2가 적어 둔 것과 같다 — 다른 체인들이 `tars-init: config shell=`로
grep하고 있어서 앞부분이 안 바뀌어야 한다. 맨 뒤에 붙이므로
`config/check.sh:1256`의 `config shell=fish.*shell_config=on`도 그대로 맞는다.

- [ ] Step 3: 빌드하고 호스트 검사를 돌린다

```bash
cd /Users/dp/Repository/tars-linux
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf init/.zig-cache init/zig-out; cd init && zig build && zig build test'
```

기대: 조용히 끝난다. `ifreq`의 크기가 틀리면 여기서는 안 잡히고 게스트에서
`ioctl`이 EINVAL을 내므로, 크기를 컴파일 타임에 못 박는 줄을 하나 넣는 것도
방법이다(`comptime std.debug.assert(@sizeOf(ifreq) == 32);`).

- [ ] Step 4: 커밋한다

```bash
cd /Users/dp/Repository/tars-linux
git add init/src/net.zig init/src/main.zig
git diff --cached --stat
git commit -m "Raise the link ourselves and hand the address to dhcpcd"
```

## Task 6 — 체인이 그것을 본다

M1이 만든 `net/check.sh`에 판정을 더한다. 새로 만드는 것이 아니다.

- [ ] Step 1: `net/make_disk.sh`를 만든다

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# NW-M2. config/make_disk.sh와 다른 점이 둘이다 — 라벨이 tars-net이고,
# 빈 디스크가 아니라 tars.conf를 미리 담아 굽는다.
#
# 미리 담는 방법이 debugfs다. 마운트도 loop 장치도 특권도 필요 없다 —
# 이미지 파일을 파일로 읽고 쓸 뿐이다. 그래서 이 게이트가 아무 특권 없이
# 도는 성질을 안 버린다(design 결정 4가 tap을 버린 것과 같은 기준이다).
#
# 이것이 design이 M2에 남긴 갈림을 없앤다. cmdline으로 주면 부팅 하나로
# 끝나지만 tars.conf의 키를 게이트가 한 번도 안 읽고, 게스트에서 타이핑으로
# 쓰면 tars.conf를 읽지만 부팅이 둘이 된다. 이쪽은 둘 다 갖는다.
#
# 라벨 접두사가 tars- 여야 한다. init/src/storage.zig의 LABEL_PREFIX가
# 그것이고(RM-M2), 정확히 하나로 박지 않은 이유가 게이트 디스크가 여럿이기
# 때문이다.
SIZE=16M
IMG=../out/net.img
CONF="$(mktemp)"
trap 'rm -f "$CONF"' EXIT

mkdir -p ../out
rm -f "$IMG"
truncate -s "$SIZE" "$IMG"
mkfs.ext2 -F -q -m 0 -L tars-net "$IMG"

# 한 줄만 적는다. 나머지 다섯 키는 기본값이고, 그래서 이 부팅의 셸이
# fish이며 체인의 화면 좌표가 다른 체인들과 같다.
#
# init이 이 파일을 읽으면 save()를 안 부른다 — load가 null이 아니기
# 때문이다. 즉 이 디스크의 tars.conf는 부팅 뒤에도 이 한 줄 그대로다.
printf 'net=dhcp\n' > "$CONF"
debugfs -w -R "write ${CONF} tars.conf" "$IMG" 2>&1 | grep -v '^debugfs' || true

echo "make_disk: created ${IMG} (${SIZE}, ext2, label tars-net, net=dhcp)"
```

- [ ] Step 2: `net/check.sh`를 고친다

다섯 자리다.

1. `cd "$(dirname "$0")"` 아래에 `REPO_ROOT="$(cd .. && pwd)"`를 더한다.
2. 빌드 블록 끝(`make_initrd.sh` 뒤)에 `./make_disk.sh` 호출을 더한다.
   `config/check.sh`와 같은 모양이다.
3. QEMU 줄에 `-drive file="${REPO_ROOT}/out/net.img",if=virtio,format=raw \`를
   더한다.
4. `fail()`의 marker 목록에 새 줄 셋을 더한다 —
   `tars-init: loaded /config/tars.conf` · `tars-init: net link eth0 is up` ·
   `tars-init: started dhcpcd on eth0`.
5. 검사 2와 3 사이에 새 검사 넷을 넣는다.

```bash
# ── 검사 3: 설정이 읽혔고 net=dhcp가 실효값인가 ───────────────────────
# 이 둘이 없으면 아래 판정이 무엇을 증명하는지가 흐려진다. 디스크가 안
# 붙었는데 주소가 붙는 경우는 없지만, 디스크가 안 붙어서 주소가 안 붙는
# 것과 코드가 틀려서 안 붙는 것은 다른 실패다.
if ! grep -a "tars-init: loaded /config/tars.conf" "$LOG" >/dev/null; then
  fail "the guest never read the config disk" "tars-init: mounted ext2" \
    "tars-init: created /config/tars.conf"
fi
if ! grep -aE "tars-init: config shell=.* net=dhcp" "$LOG" >/dev/null; then
  fail "the config disk did not turn the network on" "tars-init: config shell="
fi
echo "the guest read net=dhcp off the config disk"

# ── 검사 4: init이 한 일 둘 ───────────────────────────────────────────
# design 결정 6이 그은 경계가 이 두 줄이다. 우리 코드가 하는 일은 링크를
# 올리는 것과 dhcpcd를 띄우는 것이고, 그 뒤는 전부 dhcpcd다.
for marker in \
  "tars-init: net link eth0 is up" \
  "tars-init: started dhcpcd on eth0"; do
  if ! grep -a "$marker" "$LOG" >/dev/null; then
    fail "init did not do its half of the work: ${marker}" "tars-init: net"
  fi
done
echo "init raised the link and started dhcpcd"

# ── 검사 5: 주소가 붙었나 ─────────────────────────────────────────────
# SLIRP의 주소 규칙이 고정이라 값을 박을 수 있다 — 게스트 10.0.2.15/24,
# 게이트웨이 10.0.2.2, DNS 10.0.2.3(design 결정 4). 이 값을 우리 코드에는
# 안 박는다. dhcpcd가 받아 오는 것이고, 체인만 그것이 무엇인지 안다.
#
# 점을 이스케이프하는 이유는 wait_for_screen의 패턴이 ERE이기 때문이다.
echo "=== typing 'ip -4 addr show eth0' ==="
type_keys i p spc minus 4 spc a d d r spc s h o w spc e t h 0 ret

if ! wait_for_screen "10\.0\.2\.15"; then
  fail "dhcpcd never got an address from SLIRP" "terminal: screen>"
fi
echo "the guest holds 10.0.2.15"

# ── 검사 6: 이름을 풀 자리가 생겼나 ───────────────────────────────────
# M0의 실측 6이 이 검사의 이유다. 그때는 주소가 붙었는데 /etc/resolv.conf가
# 아예 없었다 — install_tool이 바이너리만 복사해서 dhcpcd의 hook이 initrd에
# 없었기 때문이다. 증상이 "이름만 안 풀린다"라 원인에서 멀고, 그래서 게이트가
# 직접 본다.
echo "=== typing 'cat /etc/resolv.conf' ==="
type_keys c a t spc slash e t c slash r e s o l v dot c o n f ret

if ! wait_for_screen "nameserver 10\.0\.2\.3"; then
  fail "the dhcpcd hook never wrote /etc/resolv.conf" "terminal: screen>"
fi
echo "the hook wrote /etc/resolv.conf"
```

기존 검사 3(안 켠 드라이버가 안 보이는가)은 번호만 7로 밀린다. 맨 끝의
`grace period expired` 검사는 그대로 두되 주석을 고친다 — 이제 그 검사가
design 위험 2의 실제 시험이다. 이 부팅에는 dhcpcd가 있고, 그것이 SIGTERM에
안 죽으면 여기가 빨간불이 된다.

- [ ] Step 3: 문법과 진입 검사를 미리 본다

```bash
cd /Users/dp/Repository/tars-linux
chmod +x net/make_disk.sh
bash -n net/check.sh && bash -n net/make_disk.sh && echo "문법이 맞다"
echo "=== BUILD_STEPS 넷이 주석 아닌 줄에 있나 ==="
body="$(grep -vE '^[[:space:]]*#' net/check.sh)"
for step in 'cd ../kernel && ./build.sh)' 'cd ../init && zig build)' './prepare.sh' './make_initrd.sh'; do
  case "$body" in *"$step"*) echo "  있다   $step" ;; *) echo "  없다   $step" ;; esac
done
echo "=== 파이프 뒤의 grep -q (하나도 없어야 한다) ==="
grep -nE '\|[^|]*\b(grep|rg)\b[^|]*-[a-zA-Z]*q' net/check.sh net/make_disk.sh || echo "(하나도 없다)"
```

- [ ] Step 4: 체인을 단독으로 돌린다

```bash
cd /Users/dp/Repository/tars-linux
{ time docker run --rm -v "$PWD":/workspace -w /workspace \
    tars-devcontainer bash net/check.sh ; } \
  > /tmp/nw/m2_net.log 2> /tmp/nw/m2_net.time
echo "exit=$?"; tail -3 /tmp/nw/m2_net.time; tail -30 /tmp/nw/m2_net.log
```

기대: `PASS`. M1에서 8.954초였고 이번에는 디스크 굽기와 타이핑 마흔 키가
늘었으니 15초 안팎이다. 실패했으면 아래 "실패했을 때 어디를 보는가"를 본다.

- [ ] Step 5: 커밋한다

```bash
cd /Users/dp/Repository/tars-linux
git add net/check.sh net/make_disk.sh
git diff --cached --stat
git commit -m "Ask the guest what address it got"
```

## Task 7 — 반사실 둘

검사가 실제로 무엇에 걸려 있는지 확인한다. 저장소 파일은 한 글자도 안
바꾼다 — `/tmp` 사본을 `-v`로 덮어씌우는 SD-M2의 방법이다.

SD-M2와 BH-M2가 "반사실은 겨냥한 검사가 아니라 앞의 검사에 걸린다"를
배웠다. 어디서 죽는지를 매번 적는다.

- [ ] Step 1: `net=dhcp`를 `net=off`로 바꾼 디스크로 돌린다

우리 코드가 설정을 실제로 보는지 묻는 반사실이다.

```bash
cd /Users/dp/Repository/tars-linux
sed 's/net=dhcp/net=off/' net/make_disk.sh > /tmp/nw/make_disk_off.sh
docker run --rm -v "$PWD":/workspace \
  -v /tmp/nw/make_disk_off.sh:/workspace/net/make_disk.sh:ro \
  -w /workspace tars-devcontainer bash net/check.sh \
  > /tmp/nw/m2_counter_off.log 2>&1
echo "exit=$?"
grep -aE '^(FAIL|PASS|the |init )' /tmp/nw/m2_counter_off.log
```

기대: 종료 코드 1. 죽는 자리는 검사 3의 둘째
(`the config disk did not turn the network on`)다. 그 앞의 검사 1·2(스택과
`eth0`)는 통과해야 한다 — 커널은 설정과 무관하기 때문이다.

- [ ] Step 2: hook 둘을 안 넣는 `make_initrd.sh` 사본으로 돌린다

M0의 실측 6이 겪은 상태를 일부러 다시 만든다. 주소는 붙고 이름만 안 풀리는
자리이고, 검사 6이 겨냥한 것이 정확히 그것이다.

```bash
cd /Users/dp/Repository/tars-linux
sed '/dhcpcd-run-hooks/d; /20-resolv.conf/d; /dhcpcd-hooks/d' \
  kernel/make_initrd.sh > /tmp/nw/make_initrd_nohook.sh
echo "=== 지운 줄 수 (4여야 한다) ==="
diff <(wc -l < kernel/make_initrd.sh) <(wc -l < /tmp/nw/make_initrd_nohook.sh) || true
docker run --rm -v "$PWD":/workspace \
  -v /tmp/nw/make_initrd_nohook.sh:/workspace/kernel/make_initrd.sh:ro \
  -w /workspace tars-devcontainer bash net/check.sh \
  > /tmp/nw/m2_counter_hook.log 2>&1
echo "exit=$?"
grep -aE '^(FAIL|PASS|the |init )' /tmp/nw/m2_counter_hook.log
```

기대: 종료 코드 1이고 `FAIL: the dhcpcd hook never wrote /etc/resolv.conf`.
검사 5(주소)까지는 통과해야 한다 — hook이 없어도 주소는 붙는다는 것이 M0의
실측 6이 본 것이다. 그 둘이 갈리는 것이 이 반사실의 값 전부다.

검사 5에서 죽으면 hook이 주소 획득 자체에 관여한다는 뜻이므로, 그 사실을
design에 적고 결정 C를 다시 본다.

- [ ] Step 3: 저장소 파일이 안 바뀐 것을 확인한다

```bash
cd /Users/dp/Repository/tars-linux
git status --short
```

기대: 아무것도 안 나온다. 마운트는 컨테이너 안에서만 유효하다.

## Task 8 — 회귀. 기존 체인이 그대로인가

이 milestone은 커널을 안 고쳤지만 initrd를 13MB 키웠고, `main.zig`의 로그
줄을 넓혔고, 씨앗 `tars.conf`에 줄 셋을 더했다. 셋 다 다른 체인에 닿을 수
있는 변경이다.

- [ ] Step 1: `config` 체인을 단독으로 돌린다 (약 2분 07초)

가장 예민한 체인이다. 부팅 아홉에 화면 판정이 수십이고, 씨앗 `tars.conf`가
길어지면 1차 부팅의 `tars-config` 판정이 화면 밖으로 밀릴 수 있다 — SD-M2와
BH-M2가 정확히 그 자리를 두 번 밀었다.

```bash
cd /Users/dp/Repository/tars-linux
{ time docker run --rm -v "$PWD":/workspace -w /workspace \
    tars-devcontainer bash config/check.sh ; } \
  > /tmp/nw/m2_config.log 2> /tmp/nw/m2_config.time
echo "exit=$?"; tail -3 /tmp/nw/m2_config.time; tail -20 /tmp/nw/m2_config.log
```

기대: `PASS`. 시간이 2분 07초 근처다(BB-M2 뒤의 값이 2분 06.87초).

`shell_config=on`을 화면에서 못 찾아 죽으면 씨앗이 화면보다 길어진 것이다.
그때는 `save()`의 `net` 블록에서 주석 줄을 줄인다 — 키는 남기고 설명을
design으로 옮긴다.

- [ ] Step 2: `tools` 체인을 돌린다 (initrd 목록 검사가 있다)

```bash
cd /Users/dp/Repository/tars-linux
{ time docker run --rm -v "$PWD":/workspace -w /workspace \
    tars-devcontainer bash tools/check.sh ; } \
  > /tmp/nw/m2_tools.log 2> /tmp/nw/m2_tools.time
echo "exit=$?"; tail -3 /tmp/nw/m2_tools.time; tail -20 /tmp/nw/m2_tools.log
```

기대: `PASS`. 이 체인은 `guest_tools.sh`를 source해서 목록을 검사하므로,
층 5의 여섯 줄이 자동으로 그 검사에 들어간다 — UT-M1이 그렇게 만들었다.
여기서 죽으면 `install_tool`이 넣은 자리와 검사가 보는 자리가 갈린 것이다.

- [ ] Step 3: 루트 게이트를 돌린다 (약 30분. 배경으로)

```bash
cd /Users/dp/Repository/tars-linux
{ time docker run --rm -v "$PWD":/workspace -w /workspace \
    tars-devcontainer bash check.sh ; } \
  > /tmp/nw/m2_gate.log 2> /tmp/nw/m2_gate.time
```

- [ ] Step 4: 결과를 읽는다

```bash
cd /Users/dp/Repository/tars-linux
tail -30 /tmp/nw/m2_gate.log
tail -5 /tmp/nw/m2_gate.time
echo "=== skipping make 횟수 (11 × 3 − 1 = 32 여야 한다) ==="
grep -ac "skipping make" /tmp/nw/m2_gate.log || true
```

기대: 열한 체인 3/3. 직전 기준선이 29분 49.15초이고 이 게이트의 잡음이
±3분이다. initrd가 13MB 커졌으므로 `make_initrd.sh`의 gzip이 회차마다 조금
길어지고 게스트의 tmpfs가 13MB 더 찬다 — 둘 다 크기를 미리 말할 수 없으니
여기서 잰다.

`GUEST_MEM=512`에 여유가 있는지도 이 값이 답한다. 푼 것이 90MB에서 103MB가
되므로 여유가 여전히 넉넉하지만, UT-M2가 겪은 실패의 증상이 "느려짐"이 아니라
"안 켜짐"이었다는 것을 기억해 둔다(`Kernel panic - System is deadlocked on
memory`).

## Task 9 — design과 HANDOFF를 갱신하고 커밋한다

- [ ] Step 1: design에 M2의 실측 절을 더한다

`## NW-M2가 실행으로 증명한 것`으로 절을 만들고 실측 17부터 번호를 잇는다.
담을 것이 여덟이다.

- Dockerfile에 실제로 더한 패키지 수와 이미지 재빌드 시간
- initrd의 before/after(압축·푼 것·라이브러리 수). M0의 예상(실측 3)과 맞았나
- 게스트가 받은 주소와 `/etc/resolv.conf`의 내용
- 반사실 둘이 각각 어느 검사에서 죽었나
- `net/check.sh` 단독 시간(M1의 8.954초와 비교)
- `config`·`tools` 체인 단독 시간
- 루트 게이트 시간과 판정, `skipping make` 횟수
- 결정 A가 design의 갈림을 어떻게 없앴는지

그리고 design의 "### NW-M2 — 주소가 붙는다" 절 아래에 결정 A를 `⚠`로 적는다.
M1이 "설정 디스크" 항목에 갈래 둘을 적고 미뤄 둔 자리에 답이 생겼다.

- [ ] Step 2: `HANDOFF.md`를 갱신한다

고칠 자리가 다섯이다.

- 제목과 "지금 어디인가"를 M2가 끝난 상태로
- "NW가 지금까지 한 일" 표에 커밋 여섯을 더한다
- "바로 다음에 할 것"을 M3 plan 쓰기로 바꾼다. M3가 하는 일은 `CHAINS`에
  `net`을 더하는 것과 `guestfwd`로 바깥 연결을 판정하는 것 둘이다
- "게이트 현황"에 이번 회차를 더한다
- "로그 문구는 두 곳에 중복된다" 목록에 새 줄 넷을 더한다 —
  `net=off, leaving the network alone` · `net link eth0 is up` ·
  `started dhcpcd on eth0` · `config shell=…  net=…`

- [ ] Step 3: 커밋한다

```bash
cd /Users/dp/Repository/tars-linux
git add docs/superpowers/specs/2026-09-13-tars-guest-network-design.md \
        docs/superpowers/plans/2026-09-13-tars-guest-network-nw-m2.md \
        HANDOFF.md
git diff --cached --stat
git commit -m "Hand off with an address on the guest and a chain that reads it"
```

## 실패했을 때 어디를 보는가

| 증상 | 먼저 볼 곳 |
|---|---|
| `make_initrd.sh`가 SONAME을 찍고 죽는다 | Task 1의 표. 그 SONAME을 담은 패키지가 Dockerfile 목록에 없다. 메시지가 이미 그렇게 말한다 |
| `install_tool: ... not found in sysroot` | 이미지를 다시 안 구웠거나 `.deb`의 경로가 우리가 적은 것과 다르다. `docker run --rm tars-devcontainer ls /usr/local/amd64-sysroot/usr/sbin`으로 직접 본다 |
| 게스트가 `tars.conf`를 못 읽는다 | `-drive`가 QEMU 줄에 있는지. 그 다음 라벨이 `tars-` 로 시작하는지(`storage.zig`의 `LABEL_PREFIX`) |
| `net=dhcp`인데 `net link ... is up`이 안 나온다 | `/sys/class/net/eth0`이 있는지(검사 2가 이미 봤다). 있으면 `ifreq`의 크기다 — 32바이트가 아니면 `ioctl`이 EINVAL이다 |
| `started dhcpcd`는 나오는데 주소가 안 붙는다 | 직렬 로그에서 dhcpcd 자신의 줄을 찾는다. `no such user dhcpcd`와 `read_config: /etc/dhcpcd.conf: No such file`는 실패가 아니다(M0 실측 7) |
| 주소는 붙는데 `/etc/resolv.conf`가 없다 | 둘 중 하나다. hook 둘이 initrd에 없거나(Task 3 Step 3이 확인한다), `envp`를 안 넘겨 hook이 `sed`를 못 찾았거나(결정 F) |
| `grace period expired`로 죽는다 | 이제 이 게스트에는 dhcpcd가 있다. design 위험 2의 자리이고, M0 실측 4가 "SIGTERM에 죽는다"고 했으니 그 전제가 깨진 것이다 — 그러면 결정 9를 다시 본다 |
| `config` 체인이 1차 부팅에서 죽는다 | 씨앗 `tars.conf`가 화면보다 길어졌다. `save()`의 `net` 주석을 줄인다 |
| 게이트가 크게 길어졌다 | 코드보다 기계를 먼저 의심한다(HANDOFF의 "이 게이트의 시간은 ±3분 수준의 잡음을 가진다") |

## 이 milestone이 안 하는 것

`check.sh`의 `CHAINS`를 안 고친다. `guestfwd`를 안 쓴다. 바깥으로 나가는
연결을 한 번도 안 건다. `curl`을 넣되 체인이 한 번도 안 친다.

그 넷이 전부 M3의 일이다. M3가 `CHAINS`에 한 줄을 더하고 판정을 SLIRP 안에서
닫는 연결까지 늘린다(design 결정 7). 그때 체인이 열둘이 되고 게이트가
체인 단독 시간의 세 배만큼 늘어난다.

IPv6도 netfilter도 실머신 NIC도 여전히 비목표다. 게스트가 서버 노릇을 하는
것(`hostfwd`)도, 시간 동기화도, 패키지 매니저도 마찬가지다.

## 실제로 돌린 것이 이 plan과 갈린 자리 넷

2026-09-13에 이 plan을 그대로 실행했고, 네 자리가 갈렸다. M0 plan이 세운
관행대로 적어 둔다 — 다음 사람이 이 문서를 글자 그대로 쓰면 밟을 자리다.

1. 검사 다섯이 아니라 여섯이다. plan의 검사 5(화면에서 주소 확인)가 그대로
   돌면 죽는다 — dhcpcd가 리스를 요청하기도 전에 치기 때문이다(실측 20).
   시리얼 로그에서 `eth0: leased`를 기다리는 검사를 그 앞에 새로 세웠고,
   화면 판정이 검사 6으로 밀렸다. 번호가 하나씩 밀려 마지막이 검사 8이다.
2. 반사실 사본에 `chmod +x`가 필요하다. plan의 Task 7 Step 1·2에 그 줄이
   없어서 1회차가 `FAIL: config disk build failed`로 죽었다 — 체인이
   `./make_disk.sh`로 부르는데 호스트에서 만든 파일이 644다.
3. `comptime` 블록에는 `///`를 못 붙인다. plan Step 3의 제안
   (`comptime std.debug.assert(@sizeOf(ifreq) == 32)`)을 넣되 주석을 `//`로
   쓴다. `///`로 쓰면 `documentation comments cannot be attached to comptime
   blocks`로 컴파일이 막힌다. 그리고 `assert`가 아니라 `@compileError`를
   쓰는 편이 메시지를 남긴다.
4. Task 7 Step 2의 `sed`가 지우는 줄이 넷이 아니라 아홉이다. 코드 다섯 줄과
   주석 넷인데, 주석이 지워지는 것은 반사실에 영향이 없다. 기대값만 고친다.

Task 2 Step 2의 "지운 줄이 하나도 없다"도 정확히는 한 줄이 바뀐다 —
`libselinux1:amd64) \`에서 닫는 괄호가 다음 줄로 옮겨간다. 목록 끝에 붙이는
구조상 불가피하고, 의도한 줄만 바뀐 것을 내용으로 확인했다.
