# IN-M0 — 받는 길에 손대기 전에 여섯을 잰다

design: `docs/superpowers/specs/2026-09-14-tars-inbound-network-design.md`

Goal: 게스트가 포트를 여는 것에 대해 아직 모르는 여섯을 부팅 한 번으로 재고,
그 값으로 IN-M1과 IN-M2가 쓸 상한과 판정 모양을 정한다.

Architecture: 저장소 파일을 한 글자도 안 바꾼다. `/tmp/in/`의 하네스가
컨테이너 안에서 게스트를 한 번 띄우고, FIFO로 게스트에 명령을 넣으면서
동시에 컨테이너 쪽에서 `/dev/tcp`로 그 게스트에 붙는다. 게스트 쪽 관찰은
시리얼 로그로, 컨테이너 쪽 관찰은 하네스가 직접 찍는 `PROBE[...]` 줄로
남는다.

Tech Stack: QEMU SLIRP의 `hostfwd`, bash의 `/dev/tcp`, 게스트의
`nc.traditional`, 커널이 직접 만드는 `/proc/net/tcp`.

---

## 왜 부팅을 한 번만 하나

측정 여섯을 하나씩 재면 게스트를 여섯 번 띄워야 하고, 그때마다 커널이 뜨고
dhcpcd가 리스를 받는 데 드는 시간을 여섯 번 치른다. NW-M2 실측 1이 잰
값으로는 `started dhcpcd`와 실제 리스 사이에만 로그 3500줄이 있다.

그래서 순서를 짜서 한 부팅에 몬다. 순서에 제약이 하나 있는데, 측정 4(듣는
프로세스가 없을 때)가 반드시 측정 3(리스너를 띄운 뒤)보다 앞이어야 한다는
것이다. 리스너를 한 번 띄우면 그 뒤로는 "없는 상태"를 다시 만들 수 없다.

## 이 하네스가 NW-M0과 다른 자리 둘

하나, 설정 디스크를 굽는다. NW-M0 때는 `net=` 키가 없어서 게스트에서 손으로
`ip link set eth0 up`과 `dhcpcd eth0`을 쳤다. 지금은 `net/make_disk.sh`가
있고 `init/src/net.zig`가 그 키를 읽으므로, 디스크만 물리면 주소까지 init이
붙인다. 하네스가 게스트에 칠 명령이 그만큼 줄어든다.

둘, 컨테이너가 게스트에 건다. NW-M0의 하네스는 게스트에 명령을 넣고 로그를
읽기만 했다. 이번에는 하네스 자신이 `/dev/tcp`로 붙는 쪽이라, 게스트에
명령을 넣는 일과 붙는 일이 같은 스크립트 안에서 번갈아 일어난다.

## Task 0 — `/tmp/in/`을 만든다

- [x] Step 1: 호스트에 디렉터리를 만든다

```bash
mkdir -p /tmp/in
```

이 디렉터리를 컨테이너에 `-v /tmp/in:/tmp/in`으로 물린다. 로그가 `--rm`과
함께 사라지지 않게 하려는 것이고, NW-M0이 `/tmp/nw`에 같은 것을 했다.

- [x] Step 2: 만들어졌는지 확인한다

```bash
ls -ld /tmp/in
```

Expected: `drwxr-xr-x` 한 줄.

## Task 1 — 측정 6: 포트 번호를 고른다

design 결정 6이 "monitor 대역과 안 겹쳐야 하고 M0이 실제로 열어 보고
정한다"고 적었다. monitor가 45455~45464와 45471을 쓰므로 후보를 45465·45466
으로 둔다. 둘인 이유는 Task 2가 리스너를 둘 띄우기 때문이다(측정 3과 3b).

- [x] Step 1: 컨테이너 안에서 두 포트가 비어 있는지 확인한다

```bash
docker run --rm tars-devcontainer bash -c '
  for p in 45465 45466; do
    if exec 3<>"/dev/tcp/127.0.0.1/${p}" 2>/dev/null; then
      echo "PORT ${p} BUSY"
      exec 3<&-; exec 3>&-
    else
      echo "PORT ${p} free"
    fi
  done'
```

Expected: 두 줄 다 `free`.

`BUSY`가 나오면 그 번호를 45467·45468로 올려서 다시 돌리고, 고른 값을 Task
2의 `HOST_PORT_A`·`HOST_PORT_B`에 반영한다.

컨테이너를 새로 띄워서 보는 이유는 이 검사가 호스트(macOS)가 아니라
컨테이너의 포트 공간을 물어야 하기 때문이다. QEMU가 `hostfwd`로 여는 자리가
거기다.

- [x] Step 2: 결과를 적어 둔다

두 값을 이 plan의 Task 2 스크립트에 직접 반영한다. 값이 45465·45466 그대로
이면 고칠 것이 없다.

## Task 2 — 하네스 전문 (측정 1~5와 3b)

- [x] Step 1: `/tmp/in/guest.sh`를 Write 도구로 만든다

heredoc으로 만들지 않는다. 중첩 따옴표에서 `$`가 호스트 셸에 먼저 먹힌다
(SD-M0이 배운 것이고 NW-M0도 같은 주의를 적었다).

```bash
#!/usr/bin/env bash
# IN-M0 측정 1~5와 3b. 컨테이너 안에서 돈다.
#
# 게스트를 한 번 띄우고 FIFO로 명령을 넣으면서, 동시에 이 스크립트 자신이
# /dev/tcp로 그 게스트에 붙는다. 재는 것이 여섯이다.
#
#   측정 4  — 듣는 프로세스가 없을 때 컨테이너 쪽에서 무엇이 보이나
#   측정 2  — fish에서 리스너를 배경에 두면 프롬프트가 돌아오나
#   측정 5  — 리스너를 띄운 시점과 실제로 붙는 시점의 간격
#   측정 3  — 게스트가 보낸 글자를 컨테이너가 읽나
#   측정 1  — /proc/net/tcp에 LISTEN이 생기나
#   측정 3b — 컨테이너가 보낸 글자를 게스트가 받나 (design에 없다. 아래 주석)
#
# 측정 4가 측정 3보다 먼저여야 한다. 리스너를 한 번 띄우면 "없는 상태"를
# 다시 만들 수 없다.
#
# monitor를 안 쓴다. -serial stdio와 -monitor none이 짝이고, 그래서 전원
# 버튼을 못 누른다 — 끝낼 때는 QEMU를 kill한다(NW-M0과 같다).
set -uo pipefail
cd /workspace

# Task 1이 고른 값이다.
HOST_PORT_A=45465
HOST_PORT_B=45466
GUEST_PORT_A=8080
GUEST_PORT_B=8081

LOG=/tmp/in/guest.log
FIFO=/tmp/in/guest.fifo

rm -f "$LOG" "$FIFO"
mkfifo "$FIFO"

# ── 빌드 ──────────────────────────────────────────────────────────────
# net/check.sh와 같은 다섯에 make_disk.sh를 더한 것이다. 산출물이 최신이면
# 커널은 skipping make로 넘어간다(GL-M1).
(cd kernel && ./build.sh) || { echo "INM0: kernel build failed"; exit 1; }
(cd init && zig build) || { echo "INM0: init build failed"; exit 1; }
(cd terminal && ./prepare.sh) || { echo "INM0: terminal build failed"; exit 1; }
(cd kernel && ./make_initrd.sh) || { echo "INM0: initrd build failed"; exit 1; }
(cd net && ./make_disk.sh) || { echo "INM0: config disk build failed"; exit 1; }

# 읽기·쓰기 겸용으로 연다. 쓰기 전용으로 열면 읽는 쪽이 붙을 때까지 막힌다.
exec 4<>"$FIFO"

# hostfwd가 둘이다. 값 형식은 tcp:<호스트주소>:<호스트포트>-<게스트주소>:<게스트포트>
# 이고 쉼표가 안 들어가므로 -netdev의 쉼표 구분과 안 부딪친다(design 확인 7).
#
# 127.0.0.1에 묶는 것이 design 결정 6이다. 비워 두면 QEMU가 모든 인터페이스에
# 묶는데, 이 포트가 컨테이너 밖으로 샐 이유가 없다.
#
# 게스트 주소를 10.0.2.15로 박는 것은 SLIRP의 DHCP가 첫 클라이언트에게 늘
# 그 주소를 주기 때문이다(NW가 열한 검사로 확인한 값이다). 그 전제가 깨지면
# 아래 probe가 전부 실패하고, 그때 ip addr 출력이 로그에 있으므로 갈린다.
qemu-system-x86_64 \
  -m 512 \
  -kernel kernel/build/arch/x86/boot/bzImage \
  -initrd kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -display none \
  -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:${HOST_PORT_A}-10.0.2.15:${GUEST_PORT_A},hostfwd=tcp:127.0.0.1:${HOST_PORT_B}-10.0.2.15:${GUEST_PORT_B}" \
  -device virtio-net-pci,netdev=n0 \
  -drive file=out/net.img,if=virtio,format=raw \
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

# QEMU가 옵션에서 죽었으면 여기서 끝난다. hostfwd 포트가 이미 쓰이고
# 있으면 이 자리이고(design 위험 5), 증상이 부팅 자체가 안 되는 것이라
# 원인에서 가깝다.
sleep 2
if ! kill -0 "$QEMU_PID" 2>/dev/null; then
  echo "INM0: qemu died at startup — likely a hostfwd port conflict"
  cat "$LOG"
  exit 1
fi

# 콘솔 셸이 뜰 때까지 기다린다.
WAITED=0
while [ "$WAITED" -lt 120 ]; do
  if grep -aq "started console shell" "$LOG" 2>/dev/null; then break; fi
  sleep 1
  WAITED=$((WAITED + 1))
done
if [ "$WAITED" -ge 120 ]; then
  echo "INM0: console shell never started"
  tail -40 "$LOG"
  exit 1
fi
echo "INM0: console shell up after ${WAITED}s"

# 셸에 명령을 넣는다. 이 부팅의 셸은 fish다 — 설정 디스크에 net=dhcp 한
# 줄뿐이라 나머지 여섯 키가 기본값이다(design 확인 4).
say() {
  printf '%s\n' "$1" >&4
  sleep "${2:-2}"
}

# 컨테이너에서 게스트로 붙어 본다. 읽기만 한다.
#
# timeout으로 감싸는 이유가 design 결정 5의 셋째 근거다 — 받는 방향의 실패
# 모양을 아직 모른다. 나가는 방향에서는 SLIRP이 RST를 안 주고 그냥 버렸고
# (NW-M3 실측 1), 여기서 같은 일이 일어나면 이 함수가 영영 안 돌아온다.
#
# rc와 ms를 함께 찍는 것이 요점이다. "붙었는데 아무것도 안 왔다"와 "못
# 붙었다"와 "10초를 기다리다 잘렸다"가 셋 다 다른 값으로 남는다.
probe_read() {
  local label="$1" t0 t1 out rc
  t0=$(date +%s%N)
  out="$(timeout 10 bash -c "exec 3<>/dev/tcp/127.0.0.1/${HOST_PORT_A} && cat <&3" 2>&1)"
  rc=$?
  t1=$(date +%s%N)
  echo "PROBE[${label}] rc=${rc} ms=$(( (t1 - t0) / 1000000 )) out=[${out}]"
  return "$rc"
}

say 'echo ===INM0-START==='

# ── 주소가 붙기를 기다린다 ────────────────────────────────────────────
# init이 dhcpcd를 띄우는 것은 설정 디스크가 하지만, 리스가 오는 데 시간이
# 걸린다(NW-M2 실측 1). 프롬프트를 보자마자 재면 언제나 너무 이르다.
say 'echo ===WAITING-FOR-LEASE==='
sleep 12
say 'ip addr show eth0'
say 'ip route'
say 'echo ===LEASE-ABOVE==='

# ── 측정 1의 앞쪽: 아직 아무도 안 듣는다 ──────────────────────────────
# /proc/net/tcp는 커널이 직접 만들므로 게스트에 도구가 필요 없다. 포트가
# 16진수로 적히고 8080이 1F90, 8081이 1F91이다.
#
# 이 줄이 지금은 아무것도 안 찍어야 한다. 찍으면 우리가 모르는 무언가가
# 이미 듣고 있다는 뜻이고, 그러면 아래 측정 전체의 뜻이 흐려진다.
say 'grep -c 1F90 /proc/net/tcp'
say 'echo ===LISTEN-BEFORE-ABOVE==='

# ── 측정 4: 듣는 프로세스가 없을 때 ───────────────────────────────────
# design 결정 5의 셋째 근거를 닫는 자리다. hostfwd가 여는 포트는 QEMU가
# 실제로 listen하므로 connect 자체는 붙을 수 있고, 그 뒤 게스트 쪽에 받을
# 것이 없을 때 무엇이 일어나는지가 열려 있다.
#
# M2의 음성 검사가 무엇을 보고 판정할지가 이 한 줄의 출력에서 나온다.
echo "=== measurement 4: nobody is listening yet ==="
probe_read "no-listener" || true

# ── 측정 2: fish에서 리스너를 배경에 둔다 ─────────────────────────────
# 한 번 응답하고 끝나는 리스너다(design 결정 7). echo가 만든 글자를 nc가
# 연결에 흘려 넣고 닫는다.
#
# 2>&1 | ... 같은 것을 안 붙인다. 배경 프로세스의 출력이 같은 pty로 오므로
# nc가 무언가 찍으면 화면에 섞이고, 그것이 design 위험 2다. 지금은 그것을
# 막는 것이 아니라 보는 것이 목적이라 그대로 둔다.
#
# 바로 다음 줄의 echo가 측정 2의 판정이다. 이 글자가 화면에 나오면 셸이
# 프롬프트로 돌아온 것이고, 안 나오면 fish가 매달린 것이다.
echo "=== measurement 2·5: spawning the listener ==="
SPAWN_NS=$(date +%s%N)
say "echo inm0-listener-ok | nc -l -p ${GUEST_PORT_A} &" 0
say 'echo ===LISTENER-SPAWNED===' 0

# ── 측정 5: 언제부터 붙나 ─────────────────────────────────────────────
# design 위험 1의 크기를 재는 자리다. 타이핑이 끝난 시점과 bind가 끝난
# 시점 사이가 얼마인지 모르고, 그 값이 M1의 재시도 상한과 M2의 음성 대기
# 상한을 둘 다 정한다.
#
# 0.2초 간격으로 30번, 즉 최대 6초를 본다. 성공하면 그 연결이 리스너의
# 유일한 연결을 소비하므로 측정 3도 같은 자리에서 끝난다.
#
# 이 값을 M1으로 옮길 때 주의할 것이 하나 있다. 이 하네스는 FIFO로 명령
# 한 줄을 한 번에 밀어 넣지만 게이트는 type_keys로 키를 하나씩 보내고
# 키마다 로그가 자라기를 기다린다(GL-M2). 그래서 게이트에서는 명령이
# 실행되기 시작하는 시점 자체가 여기보다 늦다. 여기서 재는 간격은
# "명령을 보낸 때부터"가 아니라 "명령이 실행된 뒤 bind까지"로 읽어야
# 하고, 그 해석이 맞는지는 아래 LISTENER-SPAWNED 줄이 로그에 찍힌 시점과
# 대조해서 본다.
echo "=== measurement 5: how long until the listener accepts ==="
CONNECTED=0
for i in $(seq 1 30); do
  NOW_NS=$(date +%s%N)
  if probe_read "attempt-${i}"; then
    echo "INM0: connected on attempt ${i}, $(( (NOW_NS - SPAWN_NS) / 1000000 ))ms after the spawn line"
    CONNECTED=1
    break
  fi
  sleep 0.2
done
[ "$CONNECTED" = "1" ] || echo "INM0: never connected within 30 attempts"

# ── 측정 1의 뒤쪽: 리스너가 실제로 LISTEN이었나 ───────────────────────
# 위 연결이 성공했으면 리스너는 이미 죽었다. 그래서 이 숫자는 0이 맞다 —
# 여기서 확인하려는 것은 "LISTEN이 생겼다가 사라졌다"의 뒤쪽 절반이고,
# 앞쪽 절반은 아래 둘째 리스너가 살아 있는 동안 본다.
say 'echo ===AFTER-FIRST-CONNECT===' 2
say 'grep -c 1F90 /proc/net/tcp'
say 'echo ===LISTEN-AFTER-ABOVE==='

# ── 측정 3b: 반대 방향 ────────────────────────────────────────────────
# design의 측정 여섯에 없다. 여기서 함께 재는 이유는 부팅 하나를 아끼기
# 위해서이고, 이 값이 IN-M2의 검사 14가 어떤 모양이 될지를 정한다.
#
# 둘째 리스너는 받기만 한다. stdin이 없으므로 붙은 쪽에 아무것도 안 보내고,
# 받은 것을 파일로 떨어뜨린다.
echo "=== measurement 3b: the reverse direction ==="
say "nc -l -p ${GUEST_PORT_B} > /tmp/inm0-got.txt &" 0
say 'echo ===SECOND-LISTENER-SPAWNED===' 3

# 살아 있는 동안 LISTEN을 본다. 이것이 측정 1의 진짜 판정이다.
say 'grep -c 1F91 /proc/net/tcp'
say 'echo ===LISTEN-LIVE-ABOVE==='

# 컨테이너가 보낸다. 보내고 바로 닫아야 게스트 쪽 nc가 EOF를 보고 끝난다.
timeout 10 bash -c "exec 3<>/dev/tcp/127.0.0.1/${HOST_PORT_B} && printf 'inm0-reverse-ok\n' >&3 && exec 3>&-"
echo "PROBE[reverse] rc=$?"
sleep 3

say 'cat /tmp/inm0-got.txt'
say 'echo ===REVERSE-ABOVE==='

# ── 끝 ────────────────────────────────────────────────────────────────
say 'echo ===INM0-END==='
sleep 2
echo "INM0: done"
```

- [x] Step 2: 파일이 만들어졌는지 확인한다

```bash
wc -l /tmp/in/guest.sh && grep -c "PROBE\[" /tmp/in/guest.sh
```

Expected: 줄 수가 나오고 `grep -c`가 2다. `PROBE[`를 적은 자리가 둘뿐이기
때문이다 — `probe_read` 함수 안의 한 줄과 반대 방향의 한 줄. 측정 4와 측정
5의 루프는 그 함수를 부르는 것이라 따로 안 적혀 있다.

## Task 3 — 하네스를 돌린다

- [x] Step 1: 컨테이너에서 실행한다

빌드가 최신이면 3~4분, 커널을 다시 구워야 하면 5분쯤 걸린다.

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/in:/tmp/in \
  -w /workspace tars-devcontainer bash /tmp/in/guest.sh > /tmp/in/run.log 2>&1
echo "exit=$?"
```

Expected: `exit=0`. 0이 아니면 `/tmp/in/run.log`의 마지막 40줄에 이유가 있다.

- [x] Step 2: 하네스가 찍은 줄만 먼저 본다

```bash
grep -E "^INM0:|^PROBE\[|^=== measurement" /tmp/in/run.log
```

Expected: `console shell up after Ns` 한 줄, `PROBE[no-listener]` 한 줄,
`PROBE[attempt-N]` 여럿, `connected on attempt N` 또는 `never connected`,
`PROBE[reverse] rc=0`, `done`.

## Task 4 — 게스트 로그를 구간별로 읽는다

- [x] Step 1: ANSI를 걷어낸다

시리얼 로그에 터미널이 그리는 escape sequence가 섞여 있어서 그대로는 못
읽는다. NW-M0이 쓴 것과 같은 한 줄이다.

```bash
perl -pe 's/\e\][^\a\e]*(\a|\e\\)//g; s/\e\[[0-9;?>=]*[a-zA-Z]//g;
          s/\e[()][AB0]//g; s/\r/\n/g' /tmp/in/guest.log > /tmp/in/guest.clean
wc -l /tmp/in/guest.clean
```

- [x] Step 2: 구간을 하나씩 읽는다

```bash
sed -n '/===LEASE-ABOVE===/,/===LISTEN-BEFORE-ABOVE===/p' /tmp/in/guest.clean
sed -n '/===LISTENER-SPAWNED===/,/===LISTEN-AFTER-ABOVE===/p' /tmp/in/guest.clean
sed -n '/===SECOND-LISTENER-SPAWNED===/,/===REVERSE-ABOVE===/p' /tmp/in/guest.clean
```

각 구간에서 볼 것.

- 첫째 — `10.0.2.15/24`가 붙었나, 기본 경로가 있나. 없으면 아래 전부가
  무의미하므로 여기서 멈추고 원인부터 본다.
- 둘째 — `===LISTENER-SPAWNED===`가 화면에 나왔나(측정 2), 첫 `grep -c 1F90`이
  0이었나(측정 1의 앞쪽), 배경 리스너가 화면에 무언가 찍었나(위험 2).
- 셋째 — 살아 있는 리스너에 대해 `grep -c 1F91`이 1 이상이었나(측정 1),
  `/tmp/inm0-got.txt`에 `inm0-reverse-ok`가 있나(측정 3b).

- [x] Step 3: init이 한 일을 확인한다

```bash
grep -a "tars-init:" /tmp/in/guest.log | head -20
```

Expected: `net link eth0 is up`과 `started dhcpcd on eth0`이 있다. 없으면
설정 디스크가 안 붙은 것이고, 그러면 `make_disk.sh`가 만든
`out/net.img`부터 본다.

## Task 5 — 실측을 design에 적는다

- [x] Step 1: design에 `## IN-M0이 실행으로 증명한 것` 절을 더한다

실측 1~6(그리고 3b)을 각각 `### 실측 N — <한 줄 결론>` 꼴로 적는다. 각
실측에 넣을 것이 셋이다 — 무엇을 쟀나, 값이 얼마였나, 그 값이 M1·M2의
무엇을 정하나.

- [x] Step 2: plan이 실제 실행과 갈린 자리를 이 문서 끝에 적는다

NW-M0이 다섯 갈렸고 그 목록이 다음 세션에 값졌다. 갈린 것이 없으면 "갈린
자리가 없다"고 한 줄 적는다.

- [x] Step 3: 위험 1과 위험 4의 상태를 갱신한다

측정 5의 값이 위험 1의 크기를 정하고, 측정 1이 위험 4를 닫거나 연다.
design의 그 두 절에 `⚠` 정정이나 확인 결과를 단다.

- [x] Step 4: 커밋한다

저장소 파일 중 바뀌는 것은 design과 이 plan 둘뿐이다. 실제로 그런지 먼저
본다.

```bash
git status --short
```

Expected: `M docs/superpowers/specs/2026-09-14-tars-inbound-network-design.md`
와 `?? docs/superpowers/plans/2026-09-14-tars-inbound-network-in-m0.md`
둘뿐이다. `out/net.img`나 빌드 산출물이 보이면 `.gitignore`를 확인한다 —
컨테이너가 만든 것이라 나와서는 안 된다.

```bash
git add docs/superpowers/specs/2026-09-14-tars-inbound-network-design.md \
        docs/superpowers/plans/2026-09-14-tars-inbound-network-in-m0.md
git commit -m "Measure the inbound path before touching the chain"
```

## 끝 기준

여섯(과 3b)이 전부 값으로 적히고, design에 실측 절이 생기고, 저장소의 코드
파일이 한 글자도 안 바뀐 것. 게이트는 안 돌린다 — 돌릴 이유가 없다.

## 실제로 돌린 것이 이 plan과 갈린 자리

넷이다.

1. 부팅이 하나가 아니라 둘이었다. Task 2의 `probe_read`가 `rc`로 판정하는데
   그 판정이 틀렸다 — 듣는 프로세스가 없어도 `rc`가 0이다(실측 4). 그래서
   측정 5의 루프가 spawn 6밀리초 뒤의 빈 응답을 성공으로 세고 끝났고, 측정
   3이 아예 안 일어났다. 판정을 받은 바이트 수로 바꾼 `/tmp/in/guest2.sh`가
   2회차이고 그것이 측정 3·5를 줬다.

   이 갈림이 plan의 잘못이지만 피할 수 있었는지는 분명하지 않다. 측정 4가
   답하려던 질문이 정확히 "듣는 것이 없을 때 무엇이 보이나"였고, 그 답을
   모르는 상태에서 판정 기준을 고를 수밖에 없었다. 다음에 같은 모양을 만나면
   순서를 뒤집는 것이 처방이다 — 판정 기준을 정하는 측정을 먼저 단독으로
   돌리고, 그 값으로 나머지 하네스를 쓴다.

2. 1회차의 실패가 증거를 남겼다. 1회차에서 `grep -c 1F90`이 첫 연결 뒤에도
   1이었고 2회차에서는 0이었다. 그 차이가 "바이트를 받으면 리스너가 죽는다"를
   증명한다 — 실패한 회차를 안 버리고 읽은 것이 값을 만든 자리다.

3. 측정 5가 목적한 값 말고 다른 것을 찾았다. `bind`까지의 간격은 작았는데
   (4~104밀리초) 읽기가 10초 timeout을 다 썼다. design에 없던 위험 7이
   여기서 나왔고, IN-M1이 다룰 실제 걸림돌은 재시도 상한이 아니라 읽기의
   종료 조건이다.

4. Task 4 Step 2의 `sed` 구간 읽기가 숫자를 못 잡았다. fish의 에코 방식
   때문에 `grep -c`의 출력 숫자가 명령 에코와 여러 줄 떨어져 있어서,
   `grep -A2`로는 안 잡히고 `grep -B12 "===<표지>-ABOVE==="`로 거꾸로 봐야
   했다. 다음 milestone에서 같은 로그를 읽을 사람은 뒤에서 보는 쪽을 먼저
   쓴다.
