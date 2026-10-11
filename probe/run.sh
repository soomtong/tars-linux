#!/usr/bin/env bash
# RS 프로브 러너 — 컨테이너 안에서 부팅 한 번을 돌린다(RS design 결정 1).
#
#   docker run --rm -v "$PWD":/workspace \
#     -v /tmp/rs-probe/main.zig:/workspace/terminal/src/main.zig:ro \
#     -w /workspace tars-devcontainer bash probe/run.sh <label> <회차>
#
# 로그는 out/probe-rs/<label>-run<회차>.log에 남는다. 집계는 probe/report.pl이다.
#
# 시나리오 둘.
#   (b) 처리량 — `seq 1 200000; echo DONE$status`. 명령줄에는 `DONE$status`가 보이고
#       출력에만 `DONE0`이 나오므로 끝 표식이 명령줄과 안 헷갈린다.
#   (a) 지연 — (b) 뒤 화면이 숫자로 찬 채 `echo` 네 글자를 친다(Enter 없음).
#       화면이 찬 프레임에서 키 하나의 비용이다.
#
# monitor 포트 45590은 체인의 범위(45455~, 새 체인은 45495부터) 밖이다. 게이트와
# 동시에 돌려도 안 겹치게 하려는 것이다.
set -uo pipefail
LABEL="${1:?label}"
RUN="${2:?run number}"
cd /workspace/terminal

# 커널은 스탬프로 건너뛴다. terminal은 main.zig가 마운트로 바뀌었으므로 다시 컴파일된다.
(cd ../kernel && ./build.sh)       || { echo "FAIL: kernel"; exit 1; }
(cd ../init && zig build)          || { echo "FAIL: init"; exit 1; }
./prepare.sh                       || { echo "FAIL: terminal"; exit 1; }
(cd ../kernel && ./make_initrd.sh) || { echo "FAIL: initrd"; exit 1; }

source ../gate_lib.sh

# 셸 프롬프트를 기다린다. `wait_for_screen`(곧 `joined_screen_dump`)은 줄머리의 `terminal: screen>`만
# 보는데, 부팅 직후 셸의 escape 바이트가 시리얼에서 그 줄 앞에 붙는 회차가 있다(RS-M2 3회차). 그 뒤 화면이
# 안 바뀌면 15초 뒤 실패하므로 여기서는 줄 중간의 `screen>`도 본다.
until_prompt() {
  local i
  for i in $(seq 1 150); do
    grep -aq "terminal: screen> .*~# " "$LOG" && return 0
    sleep 0.1
  done
  return 1
}
mkdir -p /workspace/out

PORT=45590
LOG="$(mktemp)"
qemu-system-x86_64 \
  -nic none \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!
trap 'exec 3>&- 2>/dev/null; kill "$QEMU_PID" 2>/dev/null; wait "$QEMU_PID" 2>/dev/null' EXIT

for _ in $(seq 1 120); do
  grep -aq "terminal: screen>" "$LOG" && break
  sleep 1
done
for _ in $(seq 1 20); do
  exec 3<>"/dev/tcp/127.0.0.1/${PORT}" && break
  sleep 0.5
done
until_prompt || { cp "$LOG" /workspace/out/probe-rs-failed.log; echo "FAIL: no shell prompt"; exit 1; }
sleep 1

# (b)
type_keys s e q spc 1 spc 2 0 0 0 0 0 semicolon spc e c h o spc \
  shift-d shift-o shift-n shift-e shift-4 s t a t u s ret
for _ in $(seq 1 1200); do
  joined_screen_dump | grep -aq 'DONE0' && break
  sleep 0.1
done
joined_screen_dump | grep -aq 'DONE0' || { cp "$LOG" /workspace/out/probe-rs-failed.log; echo "FAIL: seq never finished"; exit 1; }
sleep 2

# (a) 표식 줄을 로그에 덧붙이지 않는다 — QEMU가 같은 파일에 제 offset으로 쓰고 있어
# 덮일 수 있다. report.pl은 `DONE0` 프레임 뒤의 `key>` 뒤 프레임을 (a)로 센다.
type_keys e c h o
sleep 2

mkdir -p /workspace/out/probe-rs
cp "$LOG" "/workspace/out/probe-rs/${LABEL}-run${RUN}.log"
echo "probe lines: $(grep -ac 'terminal: probe>' "$LOG")"
