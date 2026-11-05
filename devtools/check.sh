#!/usr/bin/env bash
# shellcheck disable=SC2016 # 이 파일 전체: as_tars '…'의 $(…) · $((…))는 게스트의 bash가 펼친다
set -euo pipefail

cd "$(dirname "$0")" || exit 1

# TP-M1: 서른한째 체인. 개발 도구 층(TP design 결정 8~13) — 묶음을 실은 ISO로 설치하고, 디스크로 다시 뜬 게스트가
# 망 없이 사용자로 C와 Java를 짓고 돌리는가. 체인은 모두 `-nic none`이다(오프라인이 목표).
# TP-M2: 묶음이 셋이다(base · lang-jvm · lang-native). 부팅 2가 C++ · zig · rust · cargo · go의 hello를 더 본다(plan 결정 G).
#
# 부팅 넷이 같은 NVMe 이미지를 잇달아 쓴다(plan 결정 G).
#   1  ISO(묶음 셋) + 빈 최소 NVMe   tars-install --yes — 계획의 layers 줄, 복사 줄, done
#   2  NVMe만                          overlay /usr from 3, 읽기 전용, /etc/gprofng.rc, 사용자로 gcc · make · g++ · zig ·
#                                      rustc · cargo · go run · go build · javac · java · jwebserver + curl, 화면 셸에서
#                                      java --version(monitor 45504). 끝에 root가
#                                      /home/.tars/layers/lang-jvm.sqfs를 4KiB의 0으로 바꾼다
#   3  NVMe만                          layer lang-jvm: mount failed, overlay /usr from 2, gcc · go는 돌고 java는 없다
#   4  ISO + 같은 NVMe                 갱신 — p3 줄이 layers <ver> -> <ver>, 옛 묶음 셋을 지우고 새로(깨진 것을 고친다)
#
# 망가뜨리기가 부팅 2에 있는 이유: 게스트에 mount 명령이 없다(TP-M1 확인한 것). ISO로 뜬 부팅은 p3를 안 붙이므로
# p3에 손댈 수 있는 것은 설치된 디스크로 뜬 부팅의 /home뿐이다.
#
# 모양은 mise/check.sh의 것이다 — 시리얼 FIFO로 root 콘솔 셸에 한 줄씩 넣고 그 출력을 로그에서 읽는다. "사용자로"는
# setpriv다. PATH는 init이 주는 값(TP 결정 20) 그대로 — /usr/local/bin의 java가 이름으로 서야 한다.
#
# 묶음은 이 체인이 굽지 못한다. 게이트는 개발 컨테이너 안이라 amd64 거두기(devlayer/harvest.sh)를 못 돌린다 —
# make gate · make check CHAIN=devtools가 먼저 make dev-layers를 부르고, 여기서는 그 tar 위에서 build.sh가 방금
# 지은 initrd와 다시 대조한다(겹친 경로 · NEEDED). 캐시면 굽기는 건너뛴다.

(cd ../kernel && ./build.sh)
(cd ../init && zig build)
(cd ../terminal && ./prepare.sh)
(cd ../kernel && ./make_initrd.sh)
(cd ../boot && ./build.sh)
../devlayer/build.sh base
../devlayer/build.sh lang-jvm
../devlayer/build.sh lang-native
(cd ../boot && ISO_LAYERS="base lang-jvm lang-native" ISO_OUT=../out/tars-dev.iso ./make_iso.sh)

source ../gate_lib.sh

ISO=../out/tars-dev.iso
OVMF_CODE="/usr/share/OVMF/OVMF_CODE_4M.fd"
if [ ! -f "$OVMF_CODE" ]; then
  echo "FAIL: ${OVMF_CODE} not found; is the devcontainer image current?" >&2
  exit 1
fi

LAYERS="base lang-jvm lang-native"
LAYER_BYTES=0
for b in $LAYERS; do LAYER_BYTES=$(( LAYER_BYTES + $(stat -c %s "../devlayer/build/${b}.sqfs") )); done
LAYER_MIB=$(( (LAYER_BYTES + 1048575) / 1048576 ))
echo "devtools: iso $(stat -c %s "$ISO") bytes, layers ${LAYER_BYTES} bytes (${LAYER_MIB} MiB)"

WORK="$(mktemp -d)"
DISK="${WORK}/target.img"
# tars-install의 최소 디스크(disk.MIN_DISK_BYTES = 16 GiB + 2 MiB).
truncate -s 16386M "$DISK"

# -cpu는 다른 체인과 같은 TCG 기본 qemu64, -m은 mise와 같은 1024다. JVM이 그 위에서 서는지가 판정의 일부다.
TP_CPU="${TP_CPU:-qemu64}"
TP_MEM="${TP_MEM:-1024}"
echo "devtools: qemu -cpu ${TP_CPU} -m ${TP_MEM}"

QEMU_PID=""
LOG=""
FIFO=""

# shellcheck disable=SC2329 # trap cleanup EXIT이 부른다
cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  exec 3>&- 2>/dev/null || true
  exec 4>&- 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

set +e

clean() {
  perl -pe 's/\e\][^\a\e]*(\a|\e\\)//g; s/\e\[[0-9;?>=]*[a-zA-Z]//g;
            s/\e[()][AB0]//g; s/\r/\n/g' "$LOG"
}

fail() {
  echo "FAIL: $1"
  shift
  echo "--- context ---"
  local pattern
  for pattern in "$@" "tars-init: layer" "tars-init: overlay" "tars-install:" "error" "not found"; do
    grep -aF -- "$pattern" "$LOG" | tail -5 || true
  done
  echo "--- serial log tail (cleaned) ---"
  clean | tail -60
  exit 1
}

MONITOR="none"
MONITOR_PORT=45504
boot_guest() {
  local name="$1"; shift
  LOG="$(mktemp -t "devtools-boot-${name}.XXXXXX")"
  FIFO="${WORK}/boot-${name}.fifo"
  local vars="${WORK}/vars-${name}.fd"
  cp /usr/share/OVMF/OVMF_VARS_4M.fd "$vars"
  rm -f "$FIFO"; mkfifo "$FIFO"
  exec 4<>"$FIFO"
  qemu-system-x86_64 \
    -machine q35,i8042=off \
    -cpu "$TP_CPU" \
    -m "$TP_MEM" \
    -nic none \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,unit=1,file="$vars" \
    -device qemu-xhci,id=xhci \
    -device usb-kbd,bus=xhci.0 \
    -drive file="$DISK",if=none,id=target,format=raw \
    -device nvme,drive=target,serial=tarstarget \
    "$@" \
    -serial stdio \
    -monitor "$MONITOR" \
    -display none \
    -no-reboot \
    < "$FIFO" > "$LOG" 2>&1 &
  QEMU_PID=$!

  local waited=0
  while [ "$waited" -lt 180 ]; do
    if grep -aq "tars-init: started console shell" "$LOG"; then break; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
    sleep 1; waited=$((waited + 1))
  done
  if ! grep -aq "tars-init: started console shell" "$LOG"; then
    fail "boot ${name}: the console shell never started (${waited}s)" "PANIC" "efi: EFI" "tars-init"
  fi
  echo "boot ${name}: console shell up after ${waited}s"
  sleep 3
}

stop_guest() {
  kill "$QEMU_PID" 2>/dev/null
  wait "$QEMU_PID" 2>/dev/null
  QEMU_PID=""
  exec 3>&- 2>/dev/null
  exec 4>&-
  rm -f "$FIFO"
}

send() { printf '%s\n' "$1" >&4; }

# 사용자 tars로 bash 한 줄. 인자는 작은따옴표를 안 담는다(mise/check.sh의 as_tars와 같은 규칙). PATH는 init의 값이다.
as_tars() {
  send "setpriv --reuid=1000 --regid=1000 --init-groups env -u XDG_DATA_HOME HOME=/home/tars USER=tars LOGNAME=tars PATH=/usr/local/bin:/usr/bin:/bin bash -c '$1'"
}

wait_log() {
  local want="$1" limit="${2:-30}"
  for _ in $(seq 1 "$((limit * 10))"); do
    if grep -aqF -- "$want" "$LOG"; then return 0; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then return 1; fi
    sleep 0.1
  done
  return 1
}

wait_log_re() {
  local want="$1" limit="${2:-30}"
  for _ in $(seq 1 "$((limit * 10))"); do
    if grep -aqE -- "$want" "$LOG"; then return 0; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then return 1; fi
    sleep 0.1
  done
  return 1
}

last_num() { grep -aoE -- "$1" "$LOG" | tail -1 | grep -oE '[0-9]+' | tail -1; }
ms_of() { last_num "tp-ms-$1=[0-9]+"; }

CHAIN_T0=$(date +%s)

# ── 부팅 1: ISO + 빈 최소 NVMe ─────────────────────────────────────────
echo "=== boot 1: the ISO with three layers and a blank minimum-size NVMe ==="
boot_guest 1 -cdrom "$ISO"
VER="$(grep -aoE 'tars-init: starting as PID 1 \(TARS [^)]+\)' "$LOG" | head -1 | sed -E 's/.*TARS ([^)]+)\)/\1/')"
[ -n "$VER" ] || fail "the init banner has no version"
echo "devtools: the image is TARS ${VER}"
send "tars-install /dev/nvme0n1 --yes"
if ! wait_log "tars-install: done. remove the boot medium and reboot." 600; then
  fail "tars-install did not say done" "tars-install:" "failed"
fi
grep -aqF "  layers  ${LAYERS} (${LAYER_MIB} MiB) -> p3 /.tars/layers" "$LOG" \
  || fail "the plan has no layers line for ${LAYERS} (${LAYER_MIB} MiB)" "  layers"
for b in $LAYERS; do
  grep -aqF "  .tars/layers/${b}.sqfs $(stat -c %s "../devlayer/build/${b}.sqfs") bytes" "$LOG" \
    || fail "tars-install did not copy ${b}.sqfs byte for byte" ".tars/layers"
done
grep -aqF "  .tars/layers/version ${VER}" "$LOG" || fail "tars-install did not write the layers version ${VER}" ".tars/layers"
COPY_MS="$(last_num 'copied 3 layers \([0-9]+ MiB\) in [0-9]+ms')"
[ -n "$COPY_MS" ] || fail "tars-install did not say it copied 3 layers" "copied"
echo "B1: tars-install planned and copied ${LAYERS} (${LAYER_MIB} MiB in ${COPY_MS}ms) and wrote version ${VER}"
stop_guest

# ── 부팅 2: NVMe만 ─────────────────────────────────────────────────────
echo "=== boot 2: the NVMe, no network ==="
MONITOR="tcp:127.0.0.1:${MONITOR_PORT},server,nowait"
boot_guest 2
grep -aqF "tars-init: mounted ext4 at /home" "$LOG" || fail "/home is not mounted" "tars-init: home"
wait_log_re "tars-init: overlay /usr from 3 layers in [0-9]+ms" 5 || fail "init did not lay three layers over /usr" "tars-init: layer"
MOUNT_MS="$(last_num 'overlay /usr from 3 layers in [0-9]+ms')"
grep -aqF "tars-init: layer base: 1 files into /etc" "$LOG" || fail "init did not copy base's etc/ into /etc" "into /etc"
echo "B2: init mounted ${LAYERS} over /usr in ${MOUNT_MS}ms"

send "grep '^overlay /usr overlay ro' /proc/mounts | sed 's/^/tp-mnt=/'"
wait_log "tp-mnt=overlay /usr overlay ro" 10 || fail "/proc/mounts has no read-only overlay on /usr" "tp-mnt"
grep -aqF "lowerdir=/usr:/run/tars-layers/base/usr:/run/tars-layers/lang-jvm/usr:/run/tars-layers/lang-native/usr" "$LOG" \
  || fail "the overlay's lowerdir is not /usr then base, lang-jvm, lang-native" "tp-mnt"
send "touch /usr/tp-probe 2>&1 | sed 's/^/tp-ro=/'"
wait_log "Read-only file system" 10 || fail "root could write into /usr" "tp-ro"
send "test -f /etc/gprofng.rc; and printf 'tp-%s\n' etc-ok"
wait_log "tp-etc-ok" 10 || fail "/etc/gprofng.rc is not there" "gprofng"
echo "B2: /usr is a read-only overlay (initrd on top), root cannot write it, /etc/gprofng.rc came from base"

# C: 소스는 printf 한 겹으로 짓는다(initrd에 base64가 없다). 줄바꿈은 %c 10 — C 문자열에 백슬래시를 안 쓴다.
as_tars 'mkdir -p ~/tp/www && cd ~/tp && printf "#include <stdio.h>\n#include <math.h>\n#include <resolv.h>\nint main(int argc, char **argv) { (void)argv; printf(\"tp-c-%%.3f-%%d%%c\", sqrt(argc + 1.0), res_init(), 10); return 0; }\n" > h.c && s=$(date +%s%N) && gcc -O2 -o h h.c -lm -lresolv 2>&1 | sed "s/^/tp-gcc: /"; e=$(date +%s%N); echo "tp-ms-gcc=$(((e-s)/1000000))"; ./h'
wait_log "tp-c-1.414-0" 180 || fail "gcc hello.c with -lm -lresolv did not build and run" "tp-gcc" "tp-ms-gcc"
echo "B2: as tars, gcc built and ran a C program with -lm -lresolv ($(ms_of gcc)ms)"

as_tars 'cd ~/tp && printf "hm: h.c\n\tcc -O2 -o hm h.c -lm -lresolv\n" > Makefile && s=$(date +%s%N) && make 2>&1 | sed "s/^/tp-make: /"; e=$(date +%s%N); echo "tp-ms-make=$(((e-s)/1000000))"; ./hm | sed "s/^/tp-make-ran=/"'
wait_log "tp-make-ran=tp-c-1.414-0" 180 || fail "make did not build the program" "tp-make"
echo "B2: as tars, make built the same program ($(ms_of make)ms)"

# TP-M2 결정 G의 hello 넷. 소스는 printf 한 겹 — 콘솔 fish가 작은따옴표 안을 그대로 bash에 넘기고, printf가 \n · \t를 편다.
# zig 소스의 문자열에는 \n을 둘 수 없어(printf가 먼저 편다) 줄바꿈 없이 찍고 echo로 끝낸다. 상한은 TP-M1의 규칙대로
# 처음 잰 숫자의 세 배다(60초 아래로는 안 내린다). 첫 판(qemu64 · 1GiB): g++ 5.3초, zig 53.3초(첫 빌드가 compiler_rt ·
# std를 짓는다), rustc 4.8초, cargo 1.5초, go run 94.2초(첫 빌드가 표준 라이브러리를 ~/.cache/go-build로), go build 1.5초.
as_tars 'cd ~/tp && printf "#include <iostream>\n#include <vector>\nint main() { std::vector<int> v{1, 2, 3}; int s = 0; for (int x : v) s += x; std::cout << \"tp-cpp-\" << s << std::endl; }\n" > h.cpp && s=$(date +%s%N) && g++ -O2 -o hcpp h.cpp 2>&1 | sed "s/^/tp-g++: /"; e=$(date +%s%N); echo "tp-ms-cpp=$(((e-s)/1000000))"; ./hcpp'
wait_log "tp-cpp-6" 60 || fail "g++ did not build and run a C++ program" "tp-g++" "tp-ms-cpp"
echo "B2: as tars, g++ built and ran a C++ program with iostream and vector ($(ms_of cpp)ms)"

as_tars 'cd ~/tp && printf "const std = @import(\"std\");\nconst builtin = @import(\"builtin\");\npub fn main() void {\n    std.debug.print(\"tp-zig-{s}\", .{builtin.zig_version_string});\n}\n" > h.zig && s=$(date +%s%N) && zig build-exe h.zig 2>&1 | sed "s/^/tp-zigc: /"; e=$(date +%s%N); echo "tp-ms-zig=$(((e-s)/1000000))"; ./h 2>&1; echo'
wait_log_re "tp-ms-zig=[0-9]+" 180 || fail "zig build-exe did not finish in 180s" "tp-zigc"
wait_log "tp-zig-0.17.1" 30 || fail "the zig program did not print 0.17.1" "tp-zigc"
echo "B2: as tars, zig built and ran a program that prints 0.17.1 ($(ms_of zig)ms)"

as_tars 'cd ~/tp && printf "fn main() { println!(\"tp-rust-{}\", 6 * 7); }\n" > h.rs && s=$(date +%s%N) && rustc -o hrs h.rs 2>&1 | sed "s/^/tp-rustc: /"; e=$(date +%s%N); echo "tp-ms-rustc=$(((e-s)/1000000))"; ./hrs'
wait_log "tp-rust-42" 60 || fail "rustc did not build and run a program (it links with base cc and rust-lld)" "tp-rustc" "tp-ms-rustc"
echo "B2: as tars, rustc built and ran a program ($(ms_of rustc)ms)"

as_tars 'cd ~/tp && cargo new --vcs none tpr 2>&1 | sed "s/^/tp-cargo: /"; cd tpr && s=$(date +%s%N) && cargo build --offline 2>&1 | sed "s/^/tp-cargo: /"; e=$(date +%s%N); echo "tp-ms-cargo=$(((e-s)/1000000))"; ./target/debug/tpr | sed "s/^/tp-cargo-ran=/"'
wait_log "tp-cargo-ran=Hello, world!" 60 || fail "cargo new and cargo build --offline did not make a running program" "tp-cargo"
echo "B2: as tars, cargo new and cargo build --offline made a running program ($(ms_of cargo)ms)"

as_tars 'mkdir -p ~/tp/gm && cd ~/tp && printf "package main\n\nimport (\n\t\"fmt\"\n\t\"runtime\"\n)\n\nfunc main() { fmt.Println(\"tp-go-\" + runtime.Version()) }\n" > h.go && s=$(date +%s%N) && go run h.go 2>&1 | sed "s/^/tp-gorun=/"; e=$(date +%s%N); echo "tp-ms-gorun=$(((e-s)/1000000))"; cp h.go gm/ && cd gm && go mod init tp 2>&1 | sed "s/^/tp-gomod: /"; s=$(date +%s%N) && go build 2>&1 | sed "s/^/tp-gobuild: /"; e=$(date +%s%N); echo "tp-ms-gobuild=$(((e-s)/1000000))"; ./tp | sed "s/^/tp-gobuilt=/"'
wait_log_re "tp-ms-gobuild=[0-9]+" 300 || fail "go run and go build did not finish in 300s" "tp-gorun" "tp-gobuild"
grep -aqF "tp-gorun=tp-go-go1.27.3" "$LOG" || fail "go run h.go did not print go1.27.3" "tp-gorun" "tp-go"
# 실행 결과는 ms 줄 뒤에 나온다 — 바로 grep하면 첫 판처럼 경쟁에 진다.
wait_log "tp-gobuilt=tp-go-go1.27.3" 30 || fail "go build in a module did not make a running program" "tp-gobuild" "tp-gomod"
echo "B2: as tars, go run ($(ms_of gorun)ms, the first build fills ~/.cache/go-build) and go build in a module ($(ms_of gobuild)ms)"

as_tars 'cd ~/tp && echo "public class Hello { public static void main(String[] a) { System.out.println(\"tp-java-\" + Runtime.version()); } }" > Hello.java && s=$(date +%s%N) && javac Hello.java 2>&1 | sed "s/^/tp-javac: /"; e=$(date +%s%N); echo "tp-ms-javac=$(((e-s)/1000000))"; s=$(date +%s%N); java Hello 2>&1 | sed "s/^/tp-run: /"; e=$(date +%s%N); echo "tp-ms-java=$(((e-s)/1000000))"'
wait_log_re "tp-ms-java=[0-9]+" 600 || fail "javac and java did not finish in 600s" "tp-javac" "tp-run"
grep -aqE "tp-run: tp-java-25\.0\.5\+8" "$LOG" || fail "java Hello did not print the JDK version" "tp-javac" "tp-run"
echo "B2: as tars, javac $(ms_of javac)ms and java Hello $(ms_of java)ms print 25.0.5+8"

as_tars 'cd ~/tp && echo tp-web-ok > www/index.html && s=$(date +%s%N); jwebserver -b 127.0.0.1 -p 8000 -d /home/tars/tp/www > jws.log 2>&1 & p=$!; for i in $(seq 1 300); do out=$(curl -fsS http://127.0.0.1:8000/index.html 2>/dev/null) && { e=$(date +%s%N); echo "tp-web=$out"; echo "tp-ms-web=$(((e-s)/1000000))"; break; }; sleep 1; done; kill $p; sed "s/^/tp-jws: /" jws.log'
wait_log_re "tp-ms-web=[0-9]+" 360 || fail "jwebserver never answered curl" "tp-jws" "tp-web"
grep -aqF "tp-web=tp-web-ok" "$LOG" || fail "curl did not get the file jwebserver serves" "tp-jws"
echo "B2: as tars, jwebserver served a file to curl on 127.0.0.1 ($(ms_of web)ms to the first answer)"

# 화면 셸(plan 결정 H): terminal과 사용자 셸이 읽기 전용 /usr 위에서 뜨고, /usr/local/bin의 java가 이름으로 선다.
CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || fail "could not connect to the QEMU monitor on ${MONITOR_PORT}"
PROMPT_UP=0
for _ in 1 2 3 4; do
  if wait_for_screen 'tars@\(none\) ~>'; then PROMPT_UP=1; break; fi
done
[ "$PROMPT_UP" = 1 ] || fail "the screen shell never drew the tars prompt" "terminal: screen>"
type_keys j a v a spc minus minus v e r s i o n ret
JAVA_UP=0
for _ in 1 2 3 4; do
  if wait_for_screen 'openjdk 25\.0\.5'; then JAVA_UP=1; break; fi
done
if [ "$JAVA_UP" != 1 ]; then
  joined_screen_dump | tail -3
  fail "typing java --version on the screen did not print openjdk 25.0.5" "Unknown command" "terminal: screen>"
fi
echo "B2: the screen shell (tars) came up over the read-only /usr and runs java by name"
# JVM 서버 뒤의 남은 메모리(design 위험 6). 게스트에 free가 없다.
send "grep MemAvailable /proc/meminfo | sed 's/^/tp-mem /'"
wait_log_re "tp-mem MemAvailable: +[0-9]+" 10
MEM_KB="$(last_num 'tp-mem MemAvailable: +[0-9]+')"
# ms_of는 지금의 LOG를 읽는다 — 부팅 2의 숫자를 여기서 받아 둔다.
NUMBERS="gcc $(ms_of gcc)ms, make $(ms_of make)ms, g++ $(ms_of cpp)ms, zig $(ms_of zig)ms, rustc $(ms_of rustc)ms, cargo $(ms_of cargo)ms, go run $(ms_of gorun)ms, go build $(ms_of gobuild)ms, javac $(ms_of javac)ms, java $(ms_of java)ms, jwebserver $(ms_of web)ms, MemAvailable ${MEM_KB:-?} kB"
# 부팅 3의 재료. 묶음이 loop로 열린 채 그 뒤 파일을 0으로 바꾼다 — java는 이미 끝났다. sync 뒤에 QEMU를 죽인다.
send "head -c 4096 /dev/zero > /home/.tars/layers/lang-jvm.sqfs; and sync; and printf 'tp-%s\n' broke-done"
wait_log "tp-broke-done" 30 || fail "root could not overwrite /home/.tars/layers/lang-jvm.sqfs"
stop_guest

# ── 부팅 3: NVMe만 — 깨진 묶음 하나 ────────────────────────────────────
echo "=== boot 3: the NVMe with lang-jvm broken ==="
MONITOR="none"
boot_guest 3
grep -aqE "tars-init: layer lang-jvm: mount failed \(errno [0-9]+\)" "$LOG" || fail "init did not name the broken layer" "tars-init: layer"
grep -aqE "tars-init: overlay /usr from 2 layers in [0-9]+ms" "$LOG" || fail "init did not lay base and lang-native over /usr" "tars-init: overlay"
grep -aqF "tars-init: config shell=" "$LOG" || fail "the boot did not go on to the config line"
as_tars 'cd ~/tp && gcc -O2 -o h2 h.c -lm -lresolv && ./h2 | sed "s/^/tp-b3-c=/"; go run h.go | sed "s/^/tp-b3-go=/"; command -v java || printf "tp-%s\n" no-java'
wait_log "tp-b3-c=tp-c-1.414-0" 180 || fail "gcc no longer works without lang-jvm" "tp-b3"
wait_log "tp-b3-go=tp-go-go1.27.3" 60 || fail "go no longer works without lang-jvm" "tp-b3"
wait_log "tp-no-java" 10 || fail "java is still there with lang-jvm broken" "tp-b3"
echo "B3: a broken lang-jvm is named and skipped; base and lang-native still build C and Go and the boot is otherwise the same"
stop_guest

# ── 부팅 4: ISO + 같은 NVMe — 갱신 ─────────────────────────────────────
echo "=== boot 4: the ISO again over the installed NVMe (update) ==="
boot_guest 4 -cdrom "$ISO"
send "tars-install /dev/nvme0n1 --yes"
wait_log "tars-install: updated. remove the boot medium and reboot." 600 || fail "the update did not say updated" "tars-install:"
grep -aqF "  p3 (tars-home) <- layers ${VER} -> ${VER} (${LAYER_MIB} MiB), your files are not touched" "$LOG" \
  || fail "the update plan does not say p3 gets the layers" "(tars-home)"
grep -aqF "  .tars/layers: 3 old layers removed" "$LOG" || fail "the update did not remove the three old layers first" ".tars/layers"
grep -aqF "  .tars/layers/lang-jvm.sqfs $(stat -c %s ../devlayer/build/lang-jvm.sqfs) bytes" "$LOG" \
  || fail "the update did not put lang-jvm.sqfs back byte for byte" ".tars/layers"
echo "B4: the update planned the layers on p3, removed the three old ones and put them back"
stop_guest

echo "devtools: numbers: layers ${LAYER_MIB} MiB, copy ${COPY_MS}ms, overlay ${MOUNT_MS}ms, ${NUMBERS}"
echo "devtools: chain $(( $(date +%s) - CHAIN_T0 ))s after the build"
echo "PASS"
exit 0
