# LB-M0 — `lo`와 이름을 고치기 전에 일곱을 잰다

> 이 plan을 실행하는 사람에게: 이 milestone은 커밋되는 코드를 한 줄도 안
> 고친다. 만드는 것은 `/tmp/lb/` 아래의 하네스뿐이고, 저장소에 들어가는 것은
> design의 실측 절과 이 plan이다. 그래서 TDD 구조가 아니다 — WN-M0 plan과 같은
> 형식이다.

Goal: LB design의 위험 셋과 M0 목록(`lo` 상태 · 자동 주소 · `nc` 전후 · 지금의
`localhost` 실패 · curl의 자체 처리 · `libnss_myhostname`의 의존 · `::1`)을 부팅
둘로 답해서, M1 · M2가 코드를 쓸 때 남은 결정(주소를 붙이나 · 모듈이 무엇을
끌고 오나 · `::1`을 어떻게 다루나)을 없앤다.

Architecture: 게스트에서 돌 스크립트 `lbm0.sh`와 측정 도구 둘(`getent` · 
`libnss_myhostname.so.2`)을 ext2 설정 디스크(`-L tars-lb`)에 실어 `/config/`로
닿게 한다. 콘솔 셸에는 FIFO로 `bash /config/lbm0.sh <단계>` 한 줄씩 친다(WN-M0 ·
TD-M0과 같은 길). `lo`를 올리는 것도, 모듈과 파일을 제자리에 놓는 것도 전부
게스트 안에서 손으로 한다 — M1 · M2가 코드로 할 일을 먼저 손으로 해 보는 것이다.

Tech Stack: bash · QEMU 10.0.13(`pc` 기본 머신 · `virtio-net-pci`) · 게스트의
`ip` · `nc.traditional` · `curl` · sysroot의 `getent` · `apt-get download
libnss-myhostname:amd64` · 기존 빌드 스크립트 넷(`kernel/build.sh` · `init/zig
build` · `terminal/prepare.sh` · `kernel/make_initrd.sh`)

---

## 무엇을 재는가

| 측정 | 무엇 | design의 자리 | 어디서 |
|---|---|---|---|
| 1 | 부팅 직후 `lo`의 플래그 · 주소 | 왜 지금인가 | 부팅 A · B의 `before` |
| 2 | `lo`가 DOWN일 때 `nc 127.0.0.1`이 어떻게 실패하나 | 결정 6(mutation의 모양) | `before` |
| 3 | `ip link set lo up`만으로 `127.0.0.1/8`이 붙나, 그 뒤 `nc` 왕복 | 결정 2 · 위험 1 | `raise` · `after` |
| 4 | 파일이 없을 때 `localhost` · `app.localhost`가 어떻게 실패하나(`net=off` · `net=dhcp`) | 결정 5 | `names` 단계, 모듈 넣기 전 |
| 5 | 게스트 `curl`이 `localhost` · `app.localhost`를 resolver 없이 푸나 | 결정 5 | `names` |
| 6 | `libnss_myhostname`의 크기와 `NEEDED` | 위험 2 | Task 1 |
| 7 | 모듈과 파일 둘을 놓은 뒤 이름이 풀리나, `::1`이 섞이나, `nc`가 그 이름으로 붙나 | 결정 5 · 위험 3 | `nss` 단계 |

부팅 A는 `net=off`(설정 디스크에 `net=` 줄 없음, `-nic none`), 부팅 B는
`net=dhcp`(`virtio-net-pci` + SLIRP)다. B가 있는 이유는 측정 4 하나다 — 파일이
없으면 glibc가 `localhost`를 DNS로 묻는데, `net=off`에는 `resolv.conf`가 없고
`net=dhcp`에는 SLIRP의 `10.0.2.3`이 있어서 실패 모양이 다를 수 있다.

## Task 0 — `/tmp/lb/`를 만든다

- [ ] Step 1: 디렉터리를 비우고 만든다

```bash
rm -rf /tmp/lb && mkdir -p /tmp/lb/seed-A /tmp/lb/seed-B && ls -la /tmp/lb
```

기대: 빈 디렉터리 둘.

- [ ] Step 2: 작업 트리가 깨끗한지 본다

```bash
git status --short
```

기대: 아무것도 없다.

## Task 1 — 측정 도구를 sysroot와 apt에서 꺼낸다 (측정 6)

- [ ] Step 1: `libnss-myhostname:amd64`를 받아 풀고 크기와 의존을 본다

```bash
docker run --rm -v /tmp/lb:/tmp/lb tars-devcontainer bash -c '
  set -e
  cd /tmp/lb
  apt-get download libnss-myhostname:amd64
  dpkg -x libnss-myhostname_*_amd64.deb pkg
  find pkg -name "*.so*" -exec ls -la {} \;
  so=$(find pkg -name "libnss_myhostname.so.2" | head -1)
  echo "LBM0-SO $so"
  readelf -d "$so" | grep -E "NEEDED|SONAME"
  cp "$so" /tmp/lb/libnss_myhostname.so.2
  cp /usr/local/amd64-sysroot/usr/bin/getent /tmp/lb/getent
  readelf -d /tmp/lb/getent | grep NEEDED
  dpkg-deb -f libnss-myhostname_*_amd64.deb Version Depends'
ls -la /tmp/lb
```

기대: `.deb` 하나, `libnss_myhostname.so.2`와 `getent`가 `/tmp/lb`에 있다. 적을
것 — 패키지 버전, `.so`의 바이트, `NEEDED` 목록 전부, `Depends`. `NEEDED`에
`libc.so.6` 말고 무엇이 있으면 그것이 initrd에 이미 있는지 다음 Step에서 본다.

`apt-get download`가 목록 갱신 없이 실패하면(`Unable to locate package`) 명령
앞에 `apt-get update -qq &&`를 붙여 다시 한다. 컨테이너가 매번 새것이라 호스트에
남는 것은 없다.

- [ ] Step 2: `NEEDED`가 initrd에 있는지 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd kernel && ./build.sh >/dev/null && cd ../init && zig build >/dev/null &&
  cd ../terminal && ./prepare.sh >/dev/null && cd ../kernel && ./make_initrd.sh >/dev/null &&
  cpio -t < initrd.cpio 2>/dev/null | grep -E "x86_64-linux-gnu/lib(c|nss|resolv|cap)" | sort'
```

기대: `lib/x86_64-linux-gnu/libc.so.6`이 있다. Step 1의 `NEEDED` 중 이 목록에
없는 것을 적는다 — 그것이 M2가 initrd 목록에 더 적어야 할 것이다.

## Task 2 — 게스트 스크립트와 설정 디스크 둘

- [ ] Step 1: `/tmp/lb/lbm0.sh`를 쓴다

```bash
cat > /tmp/lb/lbm0.sh <<'EOF'
#!/bin/bash
# LB-M0. 게스트의 /config/lbm0.sh로 닿는다. 표지는 전부 "LBM0-<이름> ".
# 우리가 치는 줄은 "bash /config/lbm0.sh <단계>"뿐이라 그 에코에는 표지가 없다.
mark() { printf 'LBM0-%s %s\n' "$1" "$2"; }

# 게스트에 timeout도 install도 없다(첫 실행에서 rc=127로 배웠다). 명령을
# 배경에서 돌리고 $1초 뒤에 죽인다. 죽였으면 rc는 143이다.
tmo() {
  local t="$1"; shift
  "$@" & local p=$!
  # 감시자의 출력을 닫는다. 안 닫으면 그 안의 sleep이 $(...)의 파이프를 붙잡아
  # 명령이 끝나도 호출자가 $t초를 다 기다린다(두 번째 실행에서 배웠다).
  ( sleep "$t"; kill "$p" 2>/dev/null ) >/dev/null 2>&1 & local k=$!
  wait "$p"; local rc=$?
  kill "$k" 2>/dev/null; wait "$k" 2>/dev/null
  return "$rc"
}

lo_state() {
  mark LOFLAGS "$(cat /sys/class/net/lo/flags) oper=$(cat /sys/class/net/lo/operstate)"
  ip -o addr show dev lo | while read -r line; do mark LOADDR "$line"; done
  mark LOADDRN "$(ip -o addr show dev lo | wc -l)"
}

# nc 왕복 하나. $1 = 붙을 이름, $2 = 포트. 리스너는 127.0.0.1이 아니라 모든
# 주소에 묶는다 — 이름이 무엇으로 풀리든 loopback이면 받는다.
roundtrip() {
  local host="$1" port="$2" got err rc
  rm -f /tmp/lbm0.got
  nc -l -p "$port" > /tmp/lbm0.got 2>/dev/null &
  local lp=$!
  sleep 0.5
  err=$(echo "hello-$port" | tmo 5 nc -q 1 "$host" "$port" 2>&1); rc=$?
  sleep 0.5
  kill "$lp" 2>/dev/null; wait "$lp" 2>/dev/null
  got=$(cat /tmp/lbm0.got 2>/dev/null)
  mark NC "host=$host port=$port rc=$rc got=[$got] err=[$err]"
}

lookup() {  # getent ahosts는 getaddrinfo(AF_UNSPEC) — curl과 같은 호출이다
  local out rc                  # /config가 noexec일 수 있어 tmpfs로 옮겨 돈다
  [ -x /tmp/getent ] || { cp /config/getent /tmp/getent; chmod 755 /tmp/getent; }
  out=$(tmo 10 /tmp/getent ahosts "$1" 2>&1); rc=$?
  mark GETENT "name=$1 rc=$rc out=[$(echo "$out" | tr '\n' ';')]"
}

curl_try() {  # 리스너 없이 붙어 보기만 한다 — 실패 문구가 어디서 멈췄는지 말한다
  local out
  out=$(curl -sv -m 3 "http://$1:9/" 2>&1 | grep -E '^\*' | head -4 | tr '\n' ';')
  mark CURL "name=$1 out=[$out]"
}

case "$1" in
before)
  lo_state
  roundtrip 127.0.0.1 7001
  mark RESOLV "$(cat /etc/resolv.conf 2>&1 | tr '\n' ';')"
  mark ETC "$(ls /etc | tr '\n' ' ')"
  mark DONE before
  ;;
raise)
  ip link set lo up; mark RAISE "rc=$?"
  sleep 1
  lo_state
  mark DONE raise
  ;;
after)
  roundtrip 127.0.0.1 7002
  roundtrip 127.1.2.3 7003
  mark DONE after
  ;;
names)
  # 포트는 이름과 회차마다 다르다 — 앞 연결의 흔적이 다음 리스너를 막지 않게.
  p=$((7100 + $(date +%s) % 50 * 2))
  for n in localhost app.localhost; do lookup "$n"; roundtrip "$n" "$p"; curl_try "$n"; p=$((p + 1)); done
  mark VERSION "$(curl --version | head -1)"
  mark DONE names
  ;;
nss)
  cp /config/libnss_myhostname.so.2 /lib/x86_64-linux-gnu/ ; mark CPSO "rc=$?"
  printf '127.0.0.1 localhost\n' > /etc/hosts
  printf 'hosts: files myhostname dns\n' > /etc/nsswitch.conf
  p=7005
  for n in localhost app.localhost a.b.localhost localhost.localdomain; do
    lookup "$n"; roundtrip "$n" "$p"; p=$((p + 1))
  done
  mark DONE nss
  ;;
*)
  mark USAGE "unknown phase"
  ;;
esac
EOF
chmod 755 /tmp/lb/lbm0.sh
```

`roundtrip`의 판정은 `got=[hello-<포트>]`다. `err`가 연결 실패 문구(측정 2)다.
`127.1.2.3`은 `lo`가 `/8` 전체를 받는지 본다 — 커널이 `127.0.0.1/8`을 붙이면 그
대역의 아무 주소나 로컬이다.

`nss` 단계가 `localhost.localdomain`을 더 보는 것은 `myhostname`이 그 이름도
loopback으로 답한다고 알고 있어서다. 답하면 design에 한 줄 적고, 안 답해도
아무 결정이 안 바뀐다.

- [ ] Step 2: 디스크 둘을 굽는다

```bash
for B in A B; do
  cp /tmp/lb/lbm0.sh /tmp/lb/getent /tmp/lb/libnss_myhostname.so.2 /tmp/lb/seed-$B/
done
printf '# LB-M0 A. net= 줄이 없어서 net=off다.\nhangul_layout=sebeol_3p3\n' > /tmp/lb/seed-A/tars.conf
printf '# LB-M0 B.\nhangul_layout=sebeol_3p3\nnet=dhcp\n' > /tmp/lb/seed-B/tars.conf
docker run --rm -v /tmp/lb:/tmp/lb tars-devcontainer bash -c '
  for B in A B; do
    dd if=/dev/zero of=/tmp/lb/cfg-$B.img bs=1M count=16 status=none
    mkfs.ext2 -F -q -m 0 -L tars-lb -d /tmp/lb/seed-$B /tmp/lb/cfg-$B.img
    debugfs -R "ls -l /" /tmp/lb/cfg-$B.img 2>/dev/null
  done'
```

기대: 두 디스크 모두 `tars.conf` · `lbm0.sh` · `getent` · `libnss_myhostname.so.2`가
보인다. `hangul_layout`은 WN-M0과 같은 이유로 심는다 — 부팅 로그의 `config` 줄로
디스크가 읽혔는지 확인한다.

## Task 3 — 하네스를 쓴다

- [ ] Step 1: `/tmp/lb/boot.sh`를 쓴다

```bash
cat > /tmp/lb/boot.sh <<'EOF'
#!/usr/bin/env bash
# LB-M0. 컨테이너 안에서 돈다. $1 = A(net=off) | B(net=dhcp)
set -uo pipefail
cd /workspace
BOOT="$1"
LOG=/tmp/lb/guest-$BOOT.log
FIFO=/tmp/lb/guest-$BOOT.fifo
rm -f "$LOG" "$FIFO"; mkfifo "$FIFO"

(cd kernel && ./build.sh)       || { echo "LBM0: kernel build failed"; exit 1; }
(cd init && zig build)          || { echo "LBM0: init build failed"; exit 1; }
(cd terminal && ./prepare.sh)   || { echo "LBM0: terminal build failed"; exit 1; }
(cd kernel && ./make_initrd.sh) || { echo "LBM0: initrd build failed"; exit 1; }

case "$BOOT" in
A) NIC=(-nic none) ;;
B) NIC=(-netdev user,id=n0 -device virtio-net-pci,netdev=n0) ;;
esac

exec 4<>"$FIFO"
qemu-system-x86_64 \
  -m 512 \
  -kernel kernel/build/arch/x86/boot/bzImage \
  -initrd kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none -device virtio-gpu-pci -display none \
  "${NIC[@]}" \
  -drive file=/tmp/lb/cfg-$BOOT.img,if=virtio,format=raw \
  -serial stdio \
  -no-reboot \
  < "$FIFO" > "$LOG" 2>&1 &
QEMU=$!
cleanup() { kill "$QEMU" 2>/dev/null; wait 2>/dev/null; exec 4>&-; rm -f "$FIFO"; }
trap cleanup EXIT

W=0
until grep -aq "started console shell" "$LOG" 2>/dev/null; do
  sleep 1; W=$((W + 1))
  [ "$W" -ge 120 ] && { echo "LBM0: console shell never started"; tail -40 "$LOG"; exit 1; }
done
echo "LBM0: console shell up after ${W}s"
sleep 2

run() {  # 한 단계를 치고 그 단계의 DONE 표지가 하나 늘기를 기다린다
  local phase="$1" n            # names를 두 번 치므로 "있나"가 아니라 "늘었나"다
  n=$(grep -ac "LBM0-DONE $phase" "$LOG")
  printf 'bash /config/lbm0.sh %s\n' "$phase" >&4
  for _ in $(seq 1 60); do
    [ "$(grep -ac "LBM0-DONE $phase" "$LOG")" -gt "$n" ] && return 0
    sleep 1
  done
  echo "LBM0: $phase never answered"
}

if [ "$BOOT" = B ]; then
  T0=$SECONDS
  until grep -aqE "leased [0-9.]+ for" "$LOG"; do
    sleep 1
    [ $((SECONDS - T0)) -ge 40 ] && { echo "LBM0: no lease in 40s"; break; }
  done
fi

run before
run names      # lo가 DOWN이고 파일도 모듈도 없을 때의 이름 (측정 4 · 5의 앞)
run raise
run after
run names      # lo는 UP이고 파일 · 모듈은 아직 없다
run nss
echo "=== done ==="
EOF
chmod +x /tmp/lb/boot.sh
```

`names`를 두 번 치는 이유 — 첫 번째는 "지금 게스트 그대로"의 실패이고, 두
번째는 `lo`만 올라간 상태의 실패다. 둘의 차이가 M1만 들어갔을 때 사용자가 보는
것이다. 로그에서 둘은 `LBM0-DONE names` 앞뒤의 순서로 갈린다.

## Task 4 — 부팅 둘을 돌린다 (각 약 1분)

- [ ] Step 1: 부팅 A (`net=off`)

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/lb:/tmp/lb -w /workspace \
  tars-devcontainer bash /tmp/lb/boot.sh A > /tmp/lb/run-A.log 2>&1; echo "exit=$?"
grep '^LBM0\|^===' /tmp/lb/run-A.log
grep -aoE "LBM0-[A-Z]+ .*" /tmp/lb/guest-A.log | tr -d '\r'
grep -aE "tars-init: (config|net)" /tmp/lb/guest-A.log
```

적을 것 — `before`의 `LOFLAGS`(16진수; `0x8`은 `IFF_LOOPBACK`만, `0x9`면 UP까지)와
`LOADDRN`, `NC`의 `err` 문구와 `rc`, 첫 `names`의 `GETENT` · `NC` · `CURL` 셋,
`RAISE` 뒤의 `LOADDR`(`inet 127.0.0.1/8`이 있나), `after`의 두 `NC`, 둘째 `names`,
`nss`의 `CPSO`와 네 이름의 `GETENT`(`::1`이 섞이나, 순서) · `NC`.

- [ ] Step 2: 부팅 B (`net=dhcp`)

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/lb:/tmp/lb -w /workspace \
  tars-devcontainer bash /tmp/lb/boot.sh B > /tmp/lb/run-B.log 2>&1; echo "exit=$?"
grep '^LBM0\|^===' /tmp/lb/run-B.log
grep -aoE "LBM0-[A-Z]+ .*" /tmp/lb/guest-B.log | tr -d '\r'
grep -aE "tars-init: (config|net|started dhcpcd)|leased" /tmp/lb/guest-B.log
```

적을 것 — A와 같은 목록. 특히 `RESOLV`가 무엇인지(`nameserver 10.0.2.3` 예상)와
첫 `names`의 `GETENT`가 A와 어떻게 다른지(DNS가 답했나, 얼마나 걸렸나). A와 같은
것은 "A와 같다"로 적는다.

## Task 5 — 읽는 법과 판단

- 측정 1에서 `LOFLAGS`가 `0x8`이고 `LOADDRN`이 0이다 → design의 전제대로다. `0x9`면
  누군가 이미 올리고 있다는 뜻이고, 이 서브프로젝트의 절반이 사라진다 — 사용자에게
  먼저 알린다.
- 측정 3에서 `RAISE` 뒤에 `inet 127.0.0.1/8`이 있고 `after`의 두 `NC`가 `got`을
  받았다 → 결정 2대로 M1은 `IFF_UP` 하나만 세운다. 주소가 없다 → 위험 1이다. M1이
  `SIOCSIFADDR`까지 하고, design 결정 2를 고친다.
- 측정 2의 `err` 문구가 M3 mutation의 기대값이 된다(아마 `Network is unreachable`).
- 측정 4 · 5 — `CURL`이 첫 `names`에서 이미 `Trying 127.0.0.1`이면 curl은 resolver를
  안 거친다. 그러면 M3의 이름 판정에 curl을 쓸 수 없고 `getent`나 `nc`를 써야 한다.
  `getent`를 게스트에 넣을지(도구 목록에 한 줄)가 그때 M3 plan의 결정이 된다.
- 측정 6 — `NEEDED`가 `libc.so.6` 하나면 M2는 `.so` 한 줄로 끝난다. 더 있으면 그것이
  initrd에 이미 있나(Task 1 Step 2)로 갈린다. 없는 것이 크면 design 위험 2대로 결정
  5를 다시 연다 — 사용자에게 먼저 알린다.
- 측정 7 — `app.localhost`의 `GETENT`에 `127.0.0.1`이 있고 `NC`가 `got`을 받았다 →
  결정 5대로 간다. `::1`이 먼저 나오면 `nc.traditional`은 IPv4 전용이라 영향이 없지만,
  `getaddrinfo(AF_UNSPEC)`을 쓰는 클라이언트가 `::1`에 먼저 붙으려다 실패하는 지연이
  위험 3이다. 지연이 보이면(M0에서는 `GETENT`의 순서와 `CURL`의 `Trying` 줄로 본다)
  M2 plan에서 `/etc/gai.conf`나 `nsswitch.conf`의 순서로 다룰지 정한다.

## Task 6 — design에 실측을 적고 커밋한다

- [ ] Step 1: design에 "LB-M0이 실행으로 증명한 것" 절을 더한다

`docs/specs/2026-09-26-tars-loopback-design.md`의 "위험" 절 뒤에, WN
design의 실측 절과 같은 모양으로 "실측 1 — …"부터 번호를 매겨 적는다. 로그 줄은
원문 그대로, 해석은 그 아래에 둔다. Task 5의 판단 결과도 적는다. `Status:` 줄을
"M0 끝났다"로 고친다.

- [ ] Step 2: 확인하고 커밋한다

```bash
git status --short
git diff --stat
git add docs/specs/2026-09-26-tars-loopback-design.md \
        docs/plans/2026-09-26-tars-loopback-lb-m0.md
git commit -m "Measure LB-M0: lo state, kernel-given address, and localhost lookups"
```

기대: 저장소의 코드 파일이 목록에 없다.

## 이 milestone이 끝난 자리

커밋은 plan과 design의 실측 절뿐이다. 커널 · `init` · initrd · 체인은 그대로다.
다음은 LB-M1의 plan이고, 그 plan은 이 실측을 입력으로 쓴다.
