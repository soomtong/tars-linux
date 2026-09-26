# WN-M0 — 드라이버를 켜기 전에 여섯을 잰다

> 이 plan을 실행하는 사람에게: 이 milestone은 커밋되는 코드를 한 줄도 안
> 고친다. `kernel/.config`는 측정하는 동안만 작업 트리에서 바뀌고 끝에 되돌린다.
> 만드는 것은 `/tmp/wn/` 아래의 하네스뿐이고, 저장소에 들어가는 것은 design의
> 실측 절과 이 plan이다. 그래서 TDD 구조가 아니다 — TD-M0 plan과 같은 형식이다.

Goal: WN design의 위험 넷과 "WN-M0(재기)"가 적은 미지수를 부팅 둘과 기존 체인
한 판으로 답해서, M1 · M2가 코드를 쓸 때 남은 결정(RNDIS를 켜나 · lint의 문구 ·
manager mode로 가나 되돌아가나)을 없앤다.

Architecture: 작업 트리의 `kernel/.config`에 `scripts/config`로 드라이버를 켜고
`kernel/build.sh`로 증분 빌드한다. 게스트에 실행할 스크립트는 ext2 설정 디스크
(`-L tars-wn`)에 실어 `/config/wnm0.sh`로 닿게 한다. 콘솔 셸에는 FIFO로 한 줄씩
치고(TD-M0과 같은 길), USB 장치를 꽂는 것은 QEMU monitor의 `device_add`다
(`net/check.sh`의 `/dev/tcp` 연결과 같은 길).

Tech Stack: bash · `scripts/config`(커널 소스) · QEMU 10.0.13(`q35` · `e1000e` ·
`qemu-xhci` · `usb-net`) · dhcpcd(sysroot, `libudev` 없이 링크됨) · 기존 빌드
스크립트 넷(`kernel/build.sh` · `init/zig build` · `terminal/prepare.sh` ·
`kernel/make_initrd.sh`)

---

## 무엇을 재는가

| 측정 | 무엇 | design의 자리 | 어디서 |
|---|---|---|---|
| 1 | 드라이버가 끌고 들어오는 심볼(`olddefconfig`의 결과) | 결정 1 | Task 2의 `config.diff` |
| 2 | bzImage 크기 · 증분 빌드 시간 | 위험 1 | Task 1 · 2 |
| 3 | `e1000e`가 붙는가 · 인터페이스 이름 · manager mode가 lease를 받는가 | 결정 2 · 4 | 부팅 A |
| 4 | `usb-net`이 CDC와 RNDIS 중 어디로 붙나 · 이름 · 부팅 뒤에 꽂은 장치를 udev 없는 dhcpcd가 잡는가 | 결정 1 · 4 · 위험 3 | 부팅 B |
| 5 | `-netdev`만 줘도 QEMU가 기본 NIC를 빼는가 | 위험 2 | 부팅 B의 꽂기 전 목록 |
| 6 | 드라이버가 켜진 커널에서 기존 `q35` 체인이 무엇을 겪나 | 결정 3 | Task 6 `machine/check.sh` 전후 |

부팅 둘 다 `init`의 지금 경로(`eth0` 상수와 ioctl)를 안 쓴다. 설정 디스크에
`net=` 줄이 없어서 `init`이 dhcpcd를 안 띄우고, 우리가 콘솔에서 `dhcpcd -b -o
ntp_servers`를 인터페이스 인자 없이 친다. M2가 지울 경로를 재 봐야 쓸 데가 없기
때문이다. `-b`는 셸이 돌아오게 하려는 것이다. M2의 `init`은 fork한 자식을
기다리지 않으므로 `-b` 없이도 같다 — M2가 그 차이를 다시 본다.

## Task 0 — `/tmp/wn/`을 만들고 기준값을 잰다

- [ ] Step 1: 디렉터리를 비우고 만든다

```bash
rm -rf /tmp/wn && mkdir -p /tmp/wn && ls -la /tmp/wn
```

기대: 비어 있다.

- [ ] Step 2: 작업 트리가 깨끗한지 본다

```bash
git status --short
```

기대: 아무것도 없다. `kernel/.config`가 이미 바뀌어 있으면 끝의 되돌리기가
남의 변경을 지운다.

- [ ] Step 3: 지금 커널의 bzImage 크기를 적는다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd kernel && ./build.sh && stat -c "WNM0-BASE bzImage=%s" build/arch/x86/boot/bzImage' \
  | tee /tmp/wn/base.log
```

기대: `skipping make`와 `WNM0-BASE bzImage=<바이트>`. 스킵이 아니면 빌드가 최신이
아니었던 것이고 그 시간은 측정 2에 안 쓴다.

- [ ] Step 4: 기존 체인 하나의 기준 시간 (약 1~2분)

```bash
/usr/bin/time -p docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash machine/check.sh > /tmp/wn/machine-before.log 2>&1; echo "exit=$?"
tail -5 /tmp/wn/machine-before.log
```

기대: `exit=0`. `real` 초를 적는다. `machine`을 고르는 이유 — `q35`라서 QEMU가
기본으로 `e1000e`를 붙이는 체인이고(design 확인 2), 드라이버를 켜면 가장 먼저
달라지는 곳이다.

## Task 1 — 드라이버를 켜고 증분 빌드한다

- [ ] Step 1: `scripts/config`로 켠다

`scripts/config`는 커널 소스에 딸린 스크립트이고 `.config`의 한 줄을 바꾸는 것
외에는 아무것도 안 한다. 의존은 다음 Step의 `olddefconfig`가 푼다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/kernel tars-devcontainer \
  bash -c 'S=src/linux-6.18.42/scripts/config
    $S --file .config -e E1000E -e IGC -e R8169 -e USB_RTL8152 \
       -e USB_USBNET -e USB_NET_CDCETHER
    grep -E "^CONFIG_(E1000E|IGC|R8169|USB_RTL8152|USB_USBNET|USB_NET_CDCETHER)=" .config'
cp kernel/.config /tmp/wn/config.edited
```

기대: 여섯 줄이 전부 `=y`. RNDIS는 이번에 안 켠다 — 부팅 B가 CDC만으로 붙는지
보고, 안 붙을 때만 Task 5가 켠다.

- [ ] Step 2: 빌드하고 시간과 크기를 잰다 (수 분)

```bash
/usr/bin/time -p docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd kernel && ./build.sh > /tmp/build.out 2>&1; rc=$?; tail -3 /tmp/build.out
    stat -c "WNM0-NEW bzImage=%s" build/arch/x86/boot/bzImage; exit $rc' \
  2>&1 | tee /tmp/wn/build.log
```

기대: `WNM0-NEW bzImage=<바이트>`와 `real`. 적을 것 — 증분 빌드 초, 크기 차이
(바이트와 %).

## Task 2 — `olddefconfig`가 끌고 들어온 것을 본다 (측정 1)

- [ ] Step 1: 차이를 뽑는다

```bash
cp kernel/build/.config /tmp/wn/config.resolved
diff <(git show HEAD:kernel/.config | grep '^CONFIG_' | sort) \
     <(grep '^CONFIG_' /tmp/wn/config.resolved | sort) > /tmp/wn/config.diff
cat /tmp/wn/config.diff
```

기대: `>` 줄에 켠 여섯과 그것들이 `select`한 것(예: `MII` · `PHYLIB` ·
`REALTEK_PHY`, 정확한 목록이 측정값이다). `<` 줄이 있으면 무엇이 꺼졌는지 따로
적는다 — 드라이버를 켜서 무언가가 꺼지면 안 된다.

- [ ] Step 2: `kernel/.config`와 `build/.config`가 갈리는지 본다

```bash
diff <(grep '^CONFIG_' /tmp/wn/config.edited | sort) \
     <(grep '^CONFIG_' /tmp/wn/config.resolved | sort) | head -40
```

적을 것 — 갈린 줄. M1이 커밋할 `kernel/.config`를 편집한 것으로 할지 해소된
것으로 할지를 이 목록이 정한다(지금 저장소의 `.config`가 어느 쪽 관례인지
`git show HEAD:kernel/.config`와 `HEAD`로 빌드한 `build/.config`의 차이로 이미
알 수 있다면 그것을 따른다).

## Task 3 — 게스트 스크립트와 설정 디스크

- [ ] Step 1: `/tmp/wn/seed/wnm0.sh`를 쓴다

```bash
mkdir -p /tmp/wn/seed
cat > /tmp/wn/seed/wnm0.sh <<'EOF'
#!/bin/bash
# WN-M0. 게스트의 /config/wnm0.sh로 닿는다. 표지는 전부 "WNM0-<이름> up=".
# 우리가 치는 줄은 "bash /config/wnm0.sh list"뿐이라 그 에코에는 표지가 없다.
up() { read -r u _ < /proc/uptime; printf '%s' "$u"; }
mark() { printf 'WNM0-%s up=%s %s\n' "$1" "$(up)" "$2"; }

case "$1" in
list)
  for f in /sys/class/net/*; do
    n=${f##*/}
    d=$(readlink "$f/device/driver" 2>/dev/null)
    mark IF "$n drv=${d##*/} state=$(cat "$f/operstate")"
  done
  for p in /sys/bus/pci/devices/*; do
    d=$(readlink "$p/driver" 2>/dev/null)
    mark PCI "${p##*/} $(cat "$p/vendor"):$(cat "$p/device") class=$(cat "$p/class") drv=${d##*/}"
  done
  ip -4 -o addr show | while read -r _ ifc _ addr _; do
    mark ADDR "$ifc=$addr"
  done
  mark LISTED "done"
  ;;
manager)
  dhcpcd -b -o ntp_servers
  mark MANAGER "rc=$?"
  ;;
*)
  mark USAGE "unknown phase"
  ;;
esac
EOF
chmod 755 /tmp/wn/seed/wnm0.sh
printf '# WN-M0. net= 줄이 없어서 init이 dhcpcd를 안 띄운다.\nhangul_layout=sebeol_3p3\n' \
  > /tmp/wn/seed/tars.conf
```

`hangul_layout`을 심는 이유는 `machine/check.sh`와 같다 — 기본값과 다르면서
아무 판정도 안 흔드는 키라서, 부팅 로그의 `config` 줄로 이 디스크가 실제로
읽혔는지 확인할 수 있다.

- [ ] Step 2: 디스크를 굽는다

```bash
docker run --rm -v /tmp/wn:/tmp/wn tars-devcontainer bash -c '
  dd if=/dev/zero of=/tmp/wn/cfg.img bs=1M count=8 status=none
  mkfs.ext2 -F -q -m 0 -L tars-wn -d /tmp/wn/seed /tmp/wn/cfg.img
  debugfs -R "ls -l /" /tmp/wn/cfg.img'
```

기대: `tars.conf`와 `wnm0.sh`가 보인다.

## Task 4 — 하네스를 쓴다

- [ ] Step 1: `/tmp/wn/boot.sh`를 쓴다

인자 하나(`A` 또는 `B`)로 부팅 하나를 한다.

```bash
cat > /tmp/wn/boot.sh <<'EOF'
#!/usr/bin/env bash
# WN-M0. 컨테이너 안에서 돈다. $1 = A(e1000e) | B(usb-net 꽂기)
set -uo pipefail
cd /workspace
BOOT="$1"
LOG=/tmp/wn/guest-$BOOT.log
FIFO=/tmp/wn/guest-$BOOT.fifo
MON=45480
rm -f "$LOG" "$FIFO"; mkfifo "$FIFO"

(cd kernel && ./build.sh)       || { echo "WNM0: kernel build failed"; exit 1; }
(cd init && zig build)          || { echo "WNM0: init build failed"; exit 1; }
(cd terminal && ./prepare.sh)   || { echo "WNM0: terminal build failed"; exit 1; }
(cd kernel && ./make_initrd.sh) || { echo "WNM0: initrd build failed"; exit 1; }

case "$BOOT" in
A) NIC=(-netdev user,id=n0 -device e1000e,netdev=n0) ;;
B) NIC=(-netdev user,id=n1 -device qemu-xhci,id=xhci) ;;
esac

exec 4<>"$FIFO"
qemu-system-x86_64 \
  -machine q35 \
  -m 512 \
  -kernel kernel/build/arch/x86/boot/bzImage \
  -initrd kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none -device virtio-gpu-pci -display none \
  "${NIC[@]}" \
  -drive file=/tmp/wn/cfg.img,if=virtio,format=raw \
  -serial stdio \
  -monitor tcp:127.0.0.1:${MON},server,nowait \
  -no-reboot \
  < "$FIFO" > "$LOG" 2>&1 &
QEMU=$!
cleanup() { kill "$QEMU" 2>/dev/null; wait 2>/dev/null; exec 4>&-; rm -f "$FIFO"; }
trap cleanup EXIT

W=0
until grep -aq "started console shell" "$LOG" 2>/dev/null; do
  sleep 1; W=$((W + 1))
  [ "$W" -ge 120 ] && { echo "WNM0: console shell never started"; tail -40 "$LOG"; exit 1; }
done
echo "WNM0: console shell up after ${W}s"
sleep 2

run() {  # 콘솔에 한 줄을 치고 LISTED/MANAGER 표지를 기다린다
  local phase="$1" want="$2" n
  n=$(grep -ac "WNM0-$want up=" "$LOG")
  printf 'bash /config/wnm0.sh %s\n' "$phase" >&4
  for _ in $(seq 1 30); do
    [ "$(grep -ac "WNM0-$want up=" "$LOG")" -gt "$n" ] && return 0
    sleep 1
  done
  echo "WNM0: $phase never answered"
}

wait_lease() {
  local t0=$SECONDS
  until grep -aqE "leased [0-9.]+ for" "$LOG"; do
    sleep 1
    [ $((SECONDS - t0)) -ge 40 ] && { echo "WNM0: no lease in 40s"; return 1; }
  done
  echo "WNM0: lease after $((SECONDS - t0))s"
}

run list LISTED
run manager MANAGER

if [ "$BOOT" = B ]; then
  sleep 3
  exec 3<>"/dev/tcp/127.0.0.1/${MON}" || { echo "WNM0: no monitor"; exit 1; }
  printf 'device_add usb-net,netdev=n1,bus=xhci.0,id=u1\n' >&3
  echo "WNM0: plugged usb-net at up=$(grep -aoE 'WNM0-MANAGER up=[0-9.]+' "$LOG" | tail -1)"
  sleep 1; exec 3>&-
fi

wait_lease
sleep 3
run list LISTED
echo "=== done ==="
EOF
chmod +x /tmp/wn/boot.sh
```

부팅 B에서 꽂기 전의 첫 `list`가 측정 5다. `-netdev`만 있고 `-device`가 없으므로,
QEMU가 기본 NIC를 붙였다면 `8086:10d3`(`e1000e`)가 PCI 목록에 있고 드라이버가
붙어 `ethN`이 이미 있다. 없으면 `-netdev`가 기본 NIC를 뺀다는 뜻이다.

## Task 5 — 부팅 둘을 돌린다 (각 약 1분)

- [ ] Step 1: 부팅 A

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/wn:/tmp/wn -w /workspace \
  tars-devcontainer bash /tmp/wn/boot.sh A > /tmp/wn/run-A.log 2>&1; echo "exit=$?"
cat /tmp/wn/run-A.log | grep '^WNM0\|^==='
grep -aE "WNM0-[A-Z]+ up=" /tmp/wn/guest-A.log
grep -aiE "e1000e|eth[0-9]|dhcpcd|leased|config " /tmp/wn/guest-A.log | grep -v "WNM0-" | head -40
```

적을 것 — `e1000e`의 probe 줄(드라이버 버전 · MAC · `eth0` 이름 짓기), 첫 `list`에서
`eth0 drv=e1000e`, dhcpcd가 인자 없이 무엇을 보고 무엇을 올렸나(로그 순서 그대로),
lease까지의 초, 끝 `list`의 `ADDR`.

- [ ] Step 2: 부팅 B

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/wn:/tmp/wn -w /workspace \
  tars-devcontainer bash /tmp/wn/boot.sh B > /tmp/wn/run-B.log 2>&1; echo "exit=$?"
cat /tmp/wn/run-B.log | grep '^WNM0\|^==='
grep -aE "WNM0-[A-Z]+ up=" /tmp/wn/guest-B.log
grep -aiE "usb|cdc|rndis|eth[0-9]|dhcpcd|leased" /tmp/wn/guest-B.log | grep -v "WNM0-" | head -60
```

적을 것 — 첫 `list`에 NIC가 있나(측정 5), 꽂은 뒤의 커널 줄(`new high-speed USB
device` · `cdc_ether` 또는 드라이버 없음 · 이름), dhcpcd가 새 인터페이스를 알아챈
줄과 시각, lease까지의 초.

- [ ] Step 3: (조건부) CDC로 안 붙었을 때만

부팅 B에서 USB 장치는 잡혔는데 네트워크 드라이버가 안 붙었으면(`list`에 새
인터페이스가 없다) `usb-net`이 RNDIS 설정만 내보인 것이다. 그때만 켜고 다시
돌린다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/kernel tars-devcontainer \
  bash -c 'src/linux-6.18.42/scripts/config --file .config -e USB_NET_RNDIS_HOST'
docker run --rm -v "$PWD":/workspace -v /tmp/wn:/tmp/wn -w /workspace \
  tars-devcontainer bash /tmp/wn/boot.sh B > /tmp/wn/run-B2.log 2>&1; echo "exit=$?"
grep -aiE "usb|cdc|rndis|eth[0-9]|dhcpcd|leased" /tmp/wn/guest-B.log | grep -v "WNM0-" | head -60
```

적을 것 — RNDIS가 필요했다는 사실과 그 커널 줄. design 결정 1의 "RNDIS는 M0이
정한다"가 이것으로 닫힌다.

## Task 6 — 기존 `q35` 체인이 무엇을 겪나 (측정 6, 약 1~2분)

- [ ] Step 1: 드라이버가 켜진 커널로 `machine` 체인을 돌린다

```bash
/usr/bin/time -p docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash machine/check.sh > /tmp/wn/machine-after.log 2>&1; echo "exit=$?"
tail -5 /tmp/wn/machine-after.log
```

- [ ] Step 2: 게스트 로그에서 NIC가 생겼는지 본다

`machine/check.sh`는 로그를 `mktemp`에 쓰고 끝에 지운다. 그래서 여기서는 체인의
결과(초록/빨강 · 시간)만 비교하고, 게스트 쪽 증거는 부팅 A가 이미 보인 것(`q35`에
`e1000e`가 오면 붙는다)으로 대신한다. 체인이 빨강이면 그 메시지를 그대로 적고
M1이 `-nic none`으로 무엇을 고치는지의 근거로 삼는다.

적을 것 — 전후의 `exit`, `real` 초 차이.

## Task 7 — `kernel/.config`를 되돌린다

- [ ] Step 1: 되돌리고 확인한다

```bash
git checkout kernel/.config
git status --short
```

기대: 아무것도 없다. `/tmp/wn/config.edited` · `config.resolved` · `config.diff`는
남긴다 — M1이 그중 하나를 커밋한다. 다음 빌드는 스탬프가 달라서 한 번 다시
빌드한다(`build.sh`의 `BUILD_INPUTS`). 그것은 정상이다.

## Task 8 — 읽는 법과 판단

측정마다 M1 · M2의 어느 결정이 갈리는지.

- 측정 3에서 manager mode가 `e1000e`에 lease를 받았고 측정 4에서 꽂은 뒤에도
  받았다 → design 결정 4대로 간다. M2가 `net.zig`의 ioctl을 지운다.
- 측정 4에서 꽂은 장치를 dhcpcd가 못 알아챘다 → design 결정 4의 되돌아갈 길이다.
  `init`이 `/sys/class/net`을 순회해 넘기고 핫플러그는 비목표로 옮긴다. 이 경우
  design을 고치고 사용자에게 먼저 알린다.
- 측정 5에서 기본 NIC가 빠졌다 → lint는 "`-nic none` 또는 `-netdev`가 있다"로 선다.
  안 빠졌다 → lint는 "`-nic none`이 반드시 있다"이고, `net` 체인에도 `-nic none`을
  더한다.
- 측정 6에서 `machine` 체인이 초록이고 시간이 거의 같다 → 격리는 성질이 아니라
  명시의 문제이고 M1은 그 명시만 한다. 빨강이다 → 그 실패 자체가 M1의 첫 증거다.

## Task 9 — design에 실측을 적고 커밋한다

- [ ] Step 1: design에 "WN-M0이 실행으로 증명한 것" 절을 더한다

`docs/superpowers/specs/2026-09-26-tars-wired-nic-design.md`의 끝(milestone 절
앞)에, TD design의 실측 절과 같은 모양으로 "실측 1 — …"부터 번호를 매겨
적는다. 숫자(바이트 · 초)와 로그 줄은 원문 그대로, 해석은 그 아래에 둔다.
Task 8의 판단 결과도 여기에 적는다. `Status:` 줄을 "M0 끝났다"로 고친다.

- [ ] Step 2: 확인하고 커밋한다

```bash
git status --short
git diff --stat
git add docs/superpowers/specs/2026-09-26-tars-wired-nic-design.md \
        docs/superpowers/plans/2026-09-26-tars-wired-nic-wn-m0.md
git commit -m "Measure WN-M0: which drivers bind, and whether dhcpcd sees a hotplug"
```

기대: `kernel/.config`가 목록에 없다.

## 이 milestone이 끝난 자리

커밋은 plan과 design의 실측 절뿐이다. 커널 · `init` · 체인은 그대로다. 다음은
WN-M1의 plan이고, 그 plan은 이 실측을 입력으로 쓴다.
