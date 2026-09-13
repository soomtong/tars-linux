# NW-M0 — 커널 NET을 켜기 전에 일곱을 잰다

Date: 2026-09-13
design: `docs/superpowers/specs/2026-09-13-tars-guest-network-design.md`

이 milestone은 추적되는 저장소 파일을 한 글자도 안 바꾼다(design 결정 8).
실험용 `.config`와 `guest_tools.sh` 사본을 `/tmp/nw/`에 만들어 `-v`로 읽기
전용 마운트한다.

## 왜 마운트로 하면 되돌리는 것을 잊을 수 없나

`kernel/build.sh`가 빌드 입력의 해시를 산출물 옆에 적어 둔다.

```bash
BUILD_INPUTS="$(cat .config build.sh | sha256sum | cut -d' ' -f1)"
```

마운트한 동안은 `.config`가 NET 켜진 것이라 해시가 달라서 다시 빌드하고,
마운트를 풀면 해시가 원래대로 돌아가서 또 다시 빌드한다. 사람이 기억해서
되돌리는 것이 아니라 구조가 스스로 돌아온다.

`kernel/build/`와 `kernel/initrd.cpio`는 `.gitignore`에 있다. 그래서 이
측정이 그 둘을 바꿔도 git이 보는 저장소는 안 바뀐다. 다만 측정이 끝난 뒤
`kernel/build/arch/x86/boot/bzImage`가 NET 켜진 커널로 남아 있다는 것은
알고 있어야 한다 — 다음 빌드가 해시 불일치로 다시 만들므로 안전하지만,
그 사이에 손으로 게스트를 띄우면 실험용 커널로 뜬다.

## 이 measurement가 쓰는 두 가지 경로

측정마다 게스트에 명령을 넣는 방법이 갈린다.

| 무엇 | 방법 | 왜 |
|---|---|---|
| 측정 2 | 기존 `device/check.sh`를 그대로 돌린다 | 이 측정의 질문이 "그 체인이 안 바뀌는가"이므로 체인을 손대면 안 된다 |
| 측정 5·6·4 | `-serial stdio`에 FIFO를 물린다 | 명령이 길고 정확해야 한다. `sendkey`로 치면 키 수백 번이고 오타가 조용히 섞인다 |

FIFO 경로는 CC-M0이 세운 것이다(실측 21). `exec 4<>`로 읽기·쓰기 겸용으로
열어야 안 막히고, `-monitor none`을 함께 줘야 QEMU가 stdio를 두 번 쓰려다
죽지 않는다. 그 부팅에서는 monitor가 없으므로 전원 버튼을 못 누르고, 끝낼
때는 QEMU를 `kill`한다.

게스트 기본 셸은 fish다(설정 디스크를 안 주므로). fish에서 `(...)`가 command
substitution이라 글로브를 괄호로 감싸면 안 된다.

## Task 0 — `/tmp/nw/`를 만든다

```bash
mkdir -p /tmp/nw
```

아래 Task들이 이 디렉터리에 파일을 만든다. `-v`로 없는 파일을 마운트하면
Docker가 호스트에 0바이트 파일을 만들어 버리므로, 마운트 전에 `ls -l`로 그
파일이 있는지 확인한다.

## Task 1 — 실험용 `.config`를 만든다

호스트가 macOS라 `sed`가 BSD판이다. 그래서 이 파일은 컨테이너 안에서
만든다 — 저장소 `.config`를 읽어 NET 관련 줄을 지우고 원하는 값을 덧붙인다.

- [ ] Step 1: 실험용 `.config`를 만든다

```bash
cd /Users/dp/Repository/tars-linux
docker run --rm -v "$PWD":/workspace -v /tmp/nw:/tmp/nw -w /workspace \
  tars-devcontainer bash -c '
cp kernel/.config /tmp/nw/config.net

# 지우는 정규식이 CONFIG_UNIX98_PTYS를 안 건드리는 것이 중요하다. 이름 뒤에
# "=..." 또는 " is not set"이 바로 와야 하므로 CONFIG_UNIX98_PTYS=y는
# CONFIG_UNIX 다음이 "98_PTYS=y"라 안 맞는다. CONFIG_NET도 같은 이유로
# CONFIG_NETDEVICES·CONFIG_NET_CORE를 안 지운다.
sed -i -E "/^(# )?CONFIG_(NET|INET|PACKET|UNIX|NETDEVICES|VIRTIO_NET|IPV6|NETFILTER)( is not set|=.*)\$/d" /tmp/nw/config.net

cat >> /tmp/nw/config.net <<"EOF"
CONFIG_NET=y
CONFIG_UNIX=y
CONFIG_INET=y
CONFIG_PACKET=y
CONFIG_NETDEVICES=y
CONFIG_VIRTIO_NET=y
# CONFIG_IPV6 is not set
# CONFIG_NETFILTER is not set
EOF
'
```

- [ ] Step 2: 지운 줄과 더한 줄을 확인한다

```bash
diff <(sort /Users/dp/Repository/tars-linux/kernel/.config) <(sort /tmp/nw/config.net)
```

기대: `<` 쪽에 `# CONFIG_NET is not set` 하나, `>` 쪽에 위에서 덧붙인 여덟
줄. `CONFIG_UNIX98_PTYS=y`가 `<` 쪽에 나오면 정규식이 과하게 지운 것이므로
Step 1을 고치고 다시 한다.

## Task 2 — 측정 1: NET을 켠 커널의 빌드 시간과 크기

커널 전체 빌드는 arm64 위에서 x86_64로 크로스 빌드하는 것이라 오래 걸린다.
얼마나 걸리는지가 이 측정의 답 중 하나다. Bash 도구의 10분 타임아웃을
넘을 수 있으므로 `run_in_background`로 돌린다.

- [ ] Step 1: 지금 커널의 크기를 먼저 적어 둔다 (baseline)

```bash
cd /Users/dp/Repository/tars-linux
ls -l kernel/build/arch/x86/boot/bzImage
```

이 값이 없으면(파일이 없으면) baseline을 먼저 만들어야 하므로 Step 2 전에
`kernel/build.sh`를 한 번 돌린다.

- [ ] Step 2: NET 커널을 빌드하고 시간을 잰다

```bash
cd /Users/dp/Repository/tars-linux
{ time docker run --rm \
    -v "$PWD":/workspace \
    -v /tmp/nw/config.net:/workspace/kernel/.config:ro \
    -w /workspace tars-devcontainer bash kernel/build.sh ; } \
  > /tmp/nw/m1.log 2> /tmp/nw/m1.time
```

기대: `skipping make`가 안 나온다(해시가 다르므로). `make olddefconfig`가
돌고 그 뒤 `bzImage` 빌드가 돈다.

- [ ] Step 3: 결과를 읽는다

```bash
tail -5 /tmp/nw/m1.time
ls -l /Users/dp/Repository/tars-linux/kernel/build/arch/x86/boot/bzImage
grep -E "^(CONFIG_NET|CONFIG_INET|CONFIG_PACKET|CONFIG_UNIX|CONFIG_VIRTIO_NET)=" \
  /Users/dp/Repository/tars-linux/kernel/build/.config
grep -E "^# CONFIG_(IPV6|NETFILTER) is not set" \
  /Users/dp/Repository/tars-linux/kernel/build/.config
```

마지막 둘이 중요하다. `olddefconfig`가 의존성을 채우면서 우리가 끈 것을
도로 켰을 수 있다 — `CONFIG_IPV6`는 기본값이 `y`라서 특히 그렇다. 켜져
있으면 실측에 그대로 적고, 끄는 것이 가능한지도 함께 적는다.

- [ ] Step 4: 실측 표에 적을 값

baseline `bzImage` 바이트, NET `bzImage` 바이트, 차이, 빌드에 걸린 시간,
`olddefconfig`가 우리 뜻을 존중했는지 여부.

## Task 3 — 측정 2: 기존 체인이 NET 커널에서 안 바뀌는지

design 결정 3이 "virtio-net만 켜면 QEMU 기본 `e1000`을 게스트가 못 보고
넘어가므로 기존 체인 열 개에 `-net none`을 더할 필요가 없다"고 적었다.
그것은 읽어서 안 것이고 이 Task가 실제로 확인한다.

`device` 체인을 고른 이유가 셋이다. 267줄로 짧고, `-kernel`/`-initrd` 직접
부팅이라 ISO를 안 구우며, 전원 버튼을 밟아서 SL이 방금 고친 종료 경로까지
지나간다.

- [ ] Step 1: NET 커널로 `device` 체인을 돌린다

```bash
cd /Users/dp/Repository/tars-linux
{ time docker run --rm \
    -v "$PWD":/workspace \
    -v /tmp/nw/config.net:/workspace/kernel/.config:ro \
    -w /workspace tars-devcontainer bash device/check.sh ; } \
  > /tmp/nw/m2.log 2> /tmp/nw/m2.time
echo "exit=$?"
```

기대: 통과한다. 커널은 Task 2에서 이미 빌드했으므로 `skipping make`가 나와야
한다 — 안 나오면 마운트가 안 걸린 것이다.

- [ ] Step 2: 실패했으면 무엇이 달라졌는지 본다

```bash
tail -60 /tmp/nw/m2.log
```

체인이 실패하면 마지막 60줄을 스스로 뿜는다. 거기서 `e1000` 또는 `eth0`
같은 글자가 보이면 결정 3의 전제가 틀린 것이고, design을 고치고 기존 체인
열 개에 `-net none`을 더하는 쪽으로 방향을 돌린다.

- [ ] Step 3: 통과했어도 게스트가 NIC를 봤는지 따로 확인한다

체인이 통과하는 것과 "커널이 그 장치를 조용히 무시했다"는 다른 말이다.
로그를 직접 본다.

```bash
cd /Users/dp/Repository/tars-linux
docker run --rm \
  -v "$PWD":/workspace \
  -v /tmp/nw/config.net:/workspace/kernel/.config:ro \
  -w /workspace tars-devcontainer bash -c '
  bash device/check.sh > /tmp/m2b.out 2>&1
  echo "--- 네트워크 관련 커널 줄 ---"
  grep -aiE "e1000|virtio_net|eth[0-9]|Ethernet|8139|ne2k" /tmp/tmp.* || echo "(한 줄도 없다)"
'
```

`grep`에 `-a`를 붙인 이유는 로그에 NUL이 있으면 `grep`이 binary로 취급해
내용 대신 `Binary file ... matches`만 뱉기 때문이다.

기대: "(한 줄도 없다)". 만약 `e1000` 줄이 보이면 드라이버가 어딘가에서
켜진 것이므로 `kernel/build/.config`에서 `CONFIG_E1000`을 확인한다.

- [ ] Step 4: 실측 표에 적을 값

체인 통과 여부, 걸린 시간, 기존 값과의 차이, 커널 로그에 NIC 줄이 있는지.
`device` 체인 단독의 기존 시간 기준선이 없으면 마운트 없이 한 번 더 돌려서
같은 자리에서 비교한다.

## Task 4 — 측정 3·7: dhcpcd가 데려오는 것과 요구하는 것

Dockerfile을 고치지 않는다(design 위험 7). 측정하는 컨테이너 안에서
`apt-get download`와 `dpkg -x`로 sysroot에 임시로 풀고, 그 컨테이너는
`--rm`으로 사라진다.

- [ ] Step 1: 실험용 `guest_tools.sh`를 만든다

배열을 닫는 `)`는 이 파일에 하나뿐이고(225줄) 그것이 파일의 마지막 줄이다.
그래서 마지막 줄을 떼고 세 줄을 더한 뒤 다시 닫으면 된다.

```bash
cd /Users/dp/Repository/tars-linux
docker run --rm -v "$PWD":/workspace -v /tmp/nw:/tmp/nw -w /workspace \
  tars-devcontainer bash -c '
head -n -1 kernel/guest_tools.sh > /tmp/nw/guest_tools.sh
cat >> /tmp/nw/guest_tools.sh <<"EOF"

  # NW-M0 측정용. 저장소 파일이 아니라 /tmp 사본에만 있다.
  usr/sbin/dhcpcd:usr/sbin/dhcpcd
  usr/bin/ip:usr/bin/ip
  usr/bin/curl:usr/bin/curl
)
EOF
'
```

- [ ] Step 2: 끼운 자리가 맞는지 눈으로 본다

```bash
tail -8 /tmp/nw/guest_tools.sh
echo "--- 닫는 괄호가 하나여야 한다 ---"
grep -c '^)' /tmp/nw/guest_tools.sh
echo "--- 줄 수가 원본 + 5 여야 한다 ---"
wc -l /Users/dp/Repository/tars-linux/kernel/guest_tools.sh /tmp/nw/guest_tools.sh
```

기대: 세 줄이 `GUEST_TOOLS=(` 배열 안, 닫는 `)` 바로 앞에 있다. 닫는 괄호가
둘이면 `head -n -1`이 마지막 줄을 안 뗀 것이고, 그러면 배열 밖에 붙어서
`install_tool`이 그 줄을 아예 안 본다.

`ip`의 sysroot 경로가 `usr/bin/ip`가 맞는지도 Step 3이 확인한다. Debian의
iproute2는 `/usr/bin/ip`이지만 `/sbin/ip`인 판도 있다.

- [ ] Step 3: sysroot에 패키지를 임시로 풀고 의존을 센다

```bash
cd /Users/dp/Repository/tars-linux
docker run --rm -v "$PWD":/workspace -v /tmp/nw:/tmp/nw -w /workspace \
  tars-devcontainer bash -c '
set -e
apt-get update -qq
mkdir -p /tmp/debs && cd /tmp/debs
apt-get download dhcpcd-base:amd64 iproute2:amd64 curl:amd64 \
  libssl3t64:amd64 libudev1:amd64 2>&1 | tail -3
for d in /tmp/debs/*.deb; do dpkg -x "$d" "$AMD64_SYSROOT"; done

echo "=== 실제 경로 확인 ==="
for p in usr/sbin/dhcpcd usr/bin/ip sbin/ip usr/bin/curl; do
  printf "%-20s " "$p"
  [ -f "$AMD64_SYSROOT/$p" ] && echo "있다" || echo "없다"
done

echo "=== 각 바이너리가 직접 부르는 것 (DT_NEEDED) ==="
for p in usr/sbin/dhcpcd usr/bin/curl; do
  [ -f "$AMD64_SYSROOT/$p" ] || continue
  echo "--- $p ---"
  readelf -d "$AMD64_SYSROOT/$p" | sed -n "s/.*(NEEDED).*\[\(.*\)\]/\1/p"
done
'
```

`readelf`를 쓰는 이유는 `copy_lib_deps`가 쓰는 것과 같은 도구여야 답이
같기 때문이다. `ldd`는 arm64 컨테이너에서 x86_64 바이너리에 못 쓴다.

`ip`가 `sbin/ip`에 있으면 Step 1의 줄을 그 경로로 고친다.

- [ ] Step 4: initrd를 실제로 만들어 늘어난 크기와 라이브러리 수를 센다

```bash
cd /Users/dp/Repository/tars-linux
docker run --rm \
  -v "$PWD":/workspace \
  -v /tmp/nw/guest_tools.sh:/workspace/kernel/guest_tools.sh:ro \
  -v /tmp/nw:/tmp/nw -w /workspace tars-devcontainer bash -c '
set -e
apt-get update -qq
mkdir -p /tmp/debs && cd /tmp/debs
apt-get download dhcpcd-base:amd64 iproute2:amd64 curl:amd64 \
  libssl3t64:amd64 libudev1:amd64 >/dev/null 2>&1
for d in /tmp/debs/*.deb; do dpkg -x "$d" "$AMD64_SYSROOT"; done
cd /workspace

echo "=== 기존 initrd ==="
printf "압축 %s  푼 것 %s  라이브러리 %s\n" \
  "$(stat -c %s kernel/initrd.cpio)" \
  "$(zcat kernel/initrd.cpio | wc -c)" \
  "$(zcat kernel/initrd.cpio | cpio -t 2>/dev/null | grep -cE "\.so")"
cp kernel/initrd.cpio /tmp/nw/initrd.before

echo "=== 도구 셋을 넣고 다시 만든다 ==="
bash kernel/make_initrd.sh

echo "=== 새 initrd ==="
printf "압축 %s  푼 것 %s  라이브러리 %s\n" \
  "$(stat -c %s kernel/initrd.cpio)" \
  "$(zcat kernel/initrd.cpio | wc -c)" \
  "$(zcat kernel/initrd.cpio | cpio -t 2>/dev/null | grep -cE "\.so")"
cp kernel/initrd.cpio /tmp/nw/initrd.after

echo "=== 새로 들어온 라이브러리 ==="
diff <(zcat /tmp/nw/initrd.before | cpio -t 2>/dev/null | grep -E "\.so" | sort) \
     <(zcat /tmp/nw/initrd.after  | cpio -t 2>/dev/null | grep -E "\.so" | sort) \
  || true

echo "=== dhcpcd가 들고 온 데이터 파일 (측정 7의 실마리) ==="
zcat kernel/initrd.cpio | cpio -t 2>/dev/null | grep -iE "dhcpcd" || echo "(바이너리 하나뿐)"
'
```

- [ ] Step 5: 실측 표에 적을 값

새로 들어온 라이브러리의 이름과 개수, 압축·푼 initrd 크기의 before/after,
`ip`와 `curl`의 실제 sysroot 경로.

design 확인 5가 예상한 것은 `libssl.so.3`과 `libudev.so.1` 둘이다. 실제가
다르면 그 차이를 실측에 적는다 — `curl`이 TLS·SSH·압축 사슬을 크게 끌고
올 가능성이 있고, 그러면 `curl`을 뺄지를 M2에서 다시 정해야 한다.

## Task 5 — 하네스 전문 (측정 4·5·6)

측정 셋을 부팅 한 번에 몰아서 잰다. 하나씩 재면 게스트를 세 번 띄워야 하고
그때마다 커널이 뜨는 데 드는 시간을 세 번 치른다.

- [ ] Step 1: `/tmp/nw/guest.sh`를 Write 도구로 만든다

heredoc으로 만들지 않는다 — 중첩 따옴표에서 `$`가 호스트 bash에 먼저 먹힌다
(SD-M0이 배운 것).

```bash
#!/usr/bin/env bash
# NW-M0 측정 4·5·6. 컨테이너 안에서 돈다.
#
# 게스트를 한 번 띄우고 FIFO로 명령을 넣는다. 재는 것이 셋이다.
#   측정 5 — guestfwd로 10.0.2.100:8080에 붙어 우리가 정한 글자를 받아 오나
#   측정 6 — /etc/resolv.conf가 생기나, 이름이 풀리나
#   측정 4 — dhcpcd가 SIGTERM과 SIGHUP에 어떻게 반응하나
#
# monitor를 안 쓴다. -serial stdio와 -monitor none이 짝이고, 그래서 전원
# 버튼을 못 누른다 — 끝낼 때는 QEMU를 kill한다.
set -uo pipefail
cd /workspace

LOG=/tmp/nw/guest.log
FIFO=/tmp/nw/guest.fifo
PAYLOAD=/tmp/nw/payload.txt

rm -f "$LOG" "$FIFO"
mkfifo "$FIFO"

# guestfwd가 실행할 명령이 읽을 파일. 이 글자가 게스트 화면에 나오면
# 게스트의 IP 스택이 QEMU까지 실제로 닿은 것이다.
echo "nwm0-payload-ok" > "$PAYLOAD"

# 읽기·쓰기 겸용으로 연다. 쓰기 전용으로 열면 읽는 쪽이 붙을 때까지 막힌다.
exec 4<>"$FIFO"

qemu-system-x86_64 \
  -m 512 \
  -kernel kernel/build/arch/x86/boot/bzImage \
  -initrd kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -display none \
  -netdev "user,id=n0,guestfwd=tcp:10.0.2.100:8080-cmd:cat ${PAYLOAD}" \
  -device virtio-net-pci,netdev=n0 \
  -serial stdio \
  -monitor none \
  -no-reboot \
  < "$FIFO" > "$LOG" 2>&1 &
QEMU_PID=$!

cleanup() {
  kill "$QEMU_PID" 2>/dev/null
  wait "$QEMU_PID" 2>/dev/null
  exec 4>&-
  rm -f "$FIFO"
}
trap cleanup EXIT

# 콘솔 셸이 뜰 때까지 기다린다. init이 찍는 줄이고 그 뒤에야 타이핑이 먹는다.
WAITED=0
while [ "$WAITED" -lt 120 ]; do
  if grep -aq "started console shell" "$LOG" 2>/dev/null; then break; fi
  sleep 1
  WAITED=$((WAITED + 1))
done
if [ "$WAITED" -ge 120 ]; then
  echo "NWM0: console shell never started"
  tail -40 "$LOG"
  exit 1
fi
echo "NWM0: console shell up after ${WAITED}s"

# 셸에 명령을 넣는다. 게스트 기본 셸은 fish다(설정 디스크를 안 줬다).
say() {
  printf '%s\n' "$1" >&4
  sleep "${2:-2}"
}

say 'echo ===NWM0-START==='

# ── 링크를 올린다 ──────────────────────────────────────────────────────
# init은 아직 net= 을 모른다(그것이 M2의 일이다). 여기서는 손으로 한다.
say 'ip link'
say 'ip link set eth0 up' 3
say 'ip link show eth0'

# ── dhcpcd를 띄운다 ────────────────────────────────────────────────────
# -b는 주소를 받기 전에 배경으로 내려간다. 여기서는 배경으로 보내되 로그를
# 보려고 -b 대신 & 를 쓴다. 게스트 셸이 fish라 & 가 그대로 먹는다.
say 'dhcpcd --version'
say 'dhcpcd -d eth0 &' 12
say 'echo ===AFTER-DHCPCD==='
say 'ip addr show eth0'
say 'ip route'

# ── 측정 6: 이름이 풀리나 ──────────────────────────────────────────────
say 'cat /etc/resolv.conf'
say 'ls -la /etc'
say 'echo ===RESOLV-ABOVE==='

# ── 측정 5: guestfwd로 QEMU에 붙는다 ──────────────────────────────────
# 이름이 아니라 주소로 건다. 이 검사는 DNS와 무관해야 한다.
say 'curl -s --max-time 10 http://10.0.2.100:8080/' 12
say 'echo ===GUESTFWD-ABOVE==='

# 이름으로도 한 번 — 이것이 측정 6의 진짜 판정이다. SLIRP의 DNS(10.0.2.3)가
# 바깥으로 포워딩하므로 이 한 줄만은 컨테이너 밖에 의존한다. M0에서만
# 쓰고 게이트에는 절대 안 넣는다(design 결정 7).
say 'curl -s -o /dev/null -w "%{http_code} %{remote_ip}" --max-time 15 http://deb.debian.org/' 20
say 'echo ===DNS-ABOVE==='

# ── 측정 4: 시그널에 어떻게 반응하나 ──────────────────────────────────
say 'ps' 3
say 'echo ===PS-ABOVE==='

# dhcpcd의 pid를 게스트가 직접 찾아 TERM을 보낸다. 게스트에 pgrep이 없을 수
# 있어 /proc을 직접 읽는 방법도 함께 시도한다.
say 'pgrep dhcpcd; or echo no-pgrep' 3
say 'kill -TERM (pgrep dhcpcd); or echo term-failed' 5
say 'echo ===AFTER-TERM==='
say 'pgrep dhcpcd; or echo dhcpcd-gone-after-term' 3

# 다시 띄우고 HUP을 보낸다.
say 'dhcpcd -d eth0 &' 12
say 'kill -HUP (pgrep dhcpcd); or echo hup-failed' 5
say 'echo ===AFTER-HUP==='
say 'pgrep dhcpcd; or echo dhcpcd-gone-after-hup' 3

# ── 측정 7: dhcpcd가 무엇을 어디에 썼나 ───────────────────────────────
say 'ls -la /var/db/dhcpcd 2>/dev/null; or echo no-var-db' 3
say 'find / -name "dhcpcd*" -not -path "/proc/*" -not -path "/sys/*" 2>/dev/null' 5
say 'echo ===NWM0-END==='

sleep 3
echo "NWM0: done, log at ${LOG}"
```

- [ ] Step 2: 파일이 만들어졌는지 확인한다

```bash
ls -l /tmp/nw/guest.sh
```

## Task 6 — 하네스를 돌리고 로그를 읽는다

- [ ] Step 1: 돌린다 (약 5분)

Task 4의 Step 4가 만든 initrd(도구 셋이 들어간 것)와 Task 2가 만든 커널(NET
켜진 것)이 이미 `kernel/` 아래에 있어야 한다. 둘 다 `.gitignore` 대상이라
저장소는 안 바뀐다.

```bash
cd /Users/dp/Repository/tars-linux
docker run --rm \
  -v "$PWD":/workspace \
  -v /tmp/nw:/tmp/nw \
  -v /tmp/nw/config.net:/workspace/kernel/.config:ro \
  -v /tmp/nw/guest_tools.sh:/workspace/kernel/guest_tools.sh:ro \
  -w /workspace tars-devcontainer bash /tmp/nw/guest.sh \
  > /tmp/nw/m456.log 2>&1
```

- [ ] Step 2: 각 구간을 읽는다

```bash
sed -n '/===NWM0-START===/,/===AFTER-DHCPCD===/p' /tmp/nw/guest.log
```

기대: `ip link`가 `eth0`를 보여 준다. 안 보이면 커널이 virtio-net을 못
잡은 것이고, 그때는 `grep -ai virtio /tmp/nw/guest.log`로 드라이버가 떴는지
본다.

```bash
sed -n '/===AFTER-DHCPCD===/,/===RESOLV-ABOVE===/p' /tmp/nw/guest.log
```

기대: `ip addr show eth0`에 `10.0.2.15/24`가 있고 `ip route`에 기본
경로가 `10.0.2.2`로 있다. `/etc/resolv.conf`에 `nameserver 10.0.2.3`이 있다.

resolv.conf가 없으면 dhcpcd의 hook이 안 돈 것이다. design 측정 6의 앞쪽
질문이 그것이고, 그러면 M2에서 hook을 끄고 init이 직접 쓰는 쪽으로 간다.

```bash
sed -n '/===RESOLV-ABOVE===/,/===GUESTFWD-ABOVE===/p' /tmp/nw/guest.log
```

기대: `nwm0-payload-ok`가 화면에 나온다. 이것이 측정 5의 답이다. 안 나오면
`guestfwd`가 이 QEMU 버전에서 안 되는 것이고, design 결정 7이 적어 둔
대로 `netcat-openbsd`를 Dockerfile에 더하는 쪽으로 돌린다.

```bash
sed -n '/===GUESTFWD-ABOVE===/,/===DNS-ABOVE===/p' /tmp/nw/guest.log
```

기대: `200` 같은 상태 코드와 주소 하나. 이것이 측정 6의 답이다 —
`/etc/nsswitch.conf`가 없는 상태에서 glibc의 내장 기본값으로 이름이
풀리는지를 본다. 안 되면 M2에서 그 파일 한 줄을 initrd에 넣는다.

```bash
sed -n '/===PS-ABOVE===/,/===NWM0-END===/p' /tmp/nw/guest.log
```

기대: TERM 뒤에 `dhcpcd-gone-after-term`, HUP 뒤에 `dhcpcd-gone-after-hup`.
둘 중 하나라도 안 죽으면 design 결정 9가 B(감독 밖에 둔다)로 기울고,
SL이 만든 유예와 어떻게 만나는지를 실측에 분명히 적는다.

- [ ] Step 3: 게스트 셸이 fish라서 생기는 문제를 확인한다

`kill -TERM (pgrep dhcpcd)`의 괄호가 fish의 command substitution이다. bash라면
`$(...)`여야 한다. 로그에 `Unknown command` 같은 것이 보이면 셸이 fish가
아닌 것이므로 문법을 바꿔 다시 돌린다.

`pgrep`이 게스트에 없으면 `no-pgrep`이 찍힌다. 그때는 `ps`의 출력에서 pid를
눈으로 읽어 `kill -TERM <pid>`를 직접 넣는 회차를 한 번 더 돈다.

## Task 7 — design에 실측 절을 붙이고 커밋한다

- [ ] Step 1: design에 실측 절을 더한다

`docs/superpowers/specs/2026-09-13-tars-guest-network-design.md`의 맨 끝에
`## NW-M0이 실행으로 증명한 것` 절을 만들고, 측정마다 `### 실측 N — <한 줄
결론>` 소제목으로 적는다. 숫자를 본문에 그대로 넣는다.

design의 전제를 고친 실측이 있으면 그 자리에 `⚠` 정정을 함께 단다 — SL-M0의
실측 3이 그렇게 했고, 그 표시가 다음 세션이 틀린 전제를 다시 안 쓰게 만든다.

- [ ] Step 2: 마운트가 다 풀렸는지 확인한다

```bash
cd /Users/dp/Repository/tars-linux
git status --short
grep -c "CONFIG_NET is not set" kernel/.config
```

기대: `git status`에 design 파일 하나만 `M`으로 나온다. `kernel/.config`의
`grep` 결과가 1이어야 한다 — 0이면 실험용 config가 저장소에 들어간 것이다.

`kernel/build/`와 `kernel/initrd.cpio`가 실험용으로 남아 있는 것은 정상이고
`.gitignore` 대상이라 `git status`에 안 나온다. 다음 빌드가 해시 불일치로
다시 만든다.

- [ ] Step 3: 실험 산출물을 지워 다음 사람이 안 헷갈리게 한다

```bash
cd /Users/dp/Repository/tars-linux
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf kernel/build kernel/initrd.cpio'
```

캐시 삭제를 컨테이너 안에서 하는 이유는 `project_zig_out_staleness`의
처방을 호스트(macOS)에서 치면 바로 뒤의 빌드가 `error: FileNotFound`로
죽기 때문이다(9회 중 2회).

- [ ] Step 4: 커밋한다

```bash
cd /Users/dp/Repository/tars-linux
git add docs/superpowers/specs/2026-09-13-tars-guest-network-design.md \
        docs/superpowers/plans/2026-09-13-tars-guest-network-nw-m0.md
git diff --cached --stat
git commit -m "Measure what happens when the kernel learns about networking"
```

## 실패했을 때 어디를 보는가

| 증상 | 먼저 볼 곳 |
|---|---|
| `skipping make`가 안 나온다 | `-v` 마운트 경로가 맞는지. `/tmp/nw/config.net`이 0바이트면 Docker가 없는 파일을 마운트하며 만든 것이다 |
| `make_initrd`가 `not found in sysroot`로 죽는다 | Task 4 Step 3이 찍은 실제 경로와 `guest_tools.sh`의 줄이 다르다. `ip`가 `sbin/ip`일 수 있다 |
| 게스트가 `eth0`를 못 본다 | `kernel/build/.config`에서 `CONFIG_VIRTIO_NET=y`를 확인한다. `olddefconfig`가 의존성 때문에 껐을 수 있다 |
| 콘솔 셸이 120초 안에 안 뜬다 | initrd가 커져서 tmpfs가 찬 것일 수 있다(UT-M2가 겪은 것). `-m 512`를 더 올려 본다 |
| FIFO에 쓴 명령이 안 먹는다 | `exec 4<>`로 열었는지. 쓰기 전용으로 열면 막힌다(실측 21) |
| 로그에 `Binary file matches`만 나온다 | `grep`에 `-a`를 빠뜨렸다 |

## 이 milestone이 안 하는 것

저장소의 추적되는 파일을 고치지 않는다. 커널 `.config`도 `guest_tools.sh`도
`Dockerfile`도 `init` 코드도 이번에는 그대로다. 그것들을 고치는 것은 M1과
M2의 일이고, 이 milestone은 그 둘이 무엇을 만나게 될지를 숫자로 만들어 두는
자리다.
