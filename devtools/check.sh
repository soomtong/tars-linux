#!/usr/bin/env bash
# shellcheck disable=SC2016 # 이 파일 전체: as_tars '…'의 $(…) · $((…))는 게스트의 bash가 펼친다
set -euo pipefail

cd "$(dirname "$0")" || exit 1

# TP-M1: 서른한째 체인. 개발 도구 층(TP design 결정 8~13) — 묶음을 실은 ISO로 설치하고, 디스크로 다시 뜬 게스트가
# 망 없이 사용자로 C와 Java를 짓고 돌리는가. 체인은 모두 `-nic none`이다(오프라인이 목표).
# TP-M2: 묶음이 셋이다(base · lang-jvm · lang-native). 부팅 2가 C++ · zig · rust · cargo · go의 hello를 더 본다(plan 결정 G).
# TP-M4: base 보강(빌드 · 디버깅 · 원격 · man)의 hello와 쓰기 가능한 /usr/local(root가 전역으로 깐 셋이 재부팅 뒤에도 선다, plan 결정 F · H).
# TP-M3: 넷째 묶음 lang-script. 부팅 2가 python(+ venv) · ruby · lua · luau · cyber · node(+ npm) · bun · janet · php를 본다(plan 결정 F).
#
# 부팅 넷이 같은 NVMe 이미지를 잇달아 쓴다(plan 결정 G).
#   1  ISO(묶음 넷) + 빈 최소 NVMe   tars-install --yes — 계획의 layers 줄, 복사 줄, done
#   2  NVMe만                          overlay /usr from 4, 읽기 전용, /etc/gprofng.rc, 사용자로 gcc · make · g++ · zig ·
#                                      rustc · cargo · go run · go build · 스크립트 언어 아홉 · javac · java · jwebserver + curl, 화면 셸에서
#                                      java --version(monitor 45504). 끝에 root가
#                                      /home/.tars/layers/lang-jvm.sqfs를 4KiB의 0으로 바꾼다
#   3  NVMe만                          layer lang-jvm: mount failed, overlay /usr from 3, gcc · go · node는 돌고 java는 없다
#   4  ISO + 같은 NVMe                 갱신 — p3 줄이 layers <ver> -> <ver>, 옛 묶음 넷을 지우고 새로(깨진 것을 고친다)
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
../devlayer/build.sh lang-script
(cd ../boot && ISO_LAYERS="base lang-jvm lang-native lang-script" ISO_OUT=../out/tars-dev.iso ./make_iso.sh)

source ../gate_lib.sh

ISO=../out/tars-dev.iso
OVMF_CODE="/usr/share/OVMF/OVMF_CODE_4M.fd"
if [ ! -f "$OVMF_CODE" ]; then
  echo "FAIL: ${OVMF_CODE} not found; is the devcontainer image current?" >&2
  exit 1
fi

LAYERS="base lang-jvm lang-native lang-script"
LAYER_BYTES=0
for b in $LAYERS; do LAYER_BYTES=$(( LAYER_BYTES + $(stat -c %s "../devlayer/build/${b}.sqfs") )); done
LAYER_MIB=$(( (LAYER_BYTES + 1048575) / 1048576 ))
echo "devtools: iso $(stat -c %s "$ISO") bytes, layers ${LAYER_BYTES} bytes (${LAYER_MIB} MiB)"

WORK="$(mktemp -d)"
DISK="${WORK}/target.img"
# tars-install의 최소 디스크(disk.MIN_DISK_BYTES = 16 GiB + 2 MiB).
truncate -s 16386M "$DISK"

# -m은 mise와 같은 1024다. JVM이 그 위에서 서는지가 판정의 일부다.
# -cpu는 SandyBridge다(TP-M3, 사용자 결정 2026-11-06). 다른 체인의 qemu64는 x86-64 첫 세대라 SSSE3가 없다 — rv-ruby가
# require_internal의 palignr에서 Illegal instruction으로 죽었다. 개발 도구 층의 실제 바닥은 맥북 에어 2011(Sandy Bridge:
# SSSE3 · SSE4.2 · POPCNT · AVX, AVX2는 없다)이라 그 세대로 돈다. AVX2가 없으므로 bun은 여전히 baseline이어야 한다.
TP_CPU="${TP_CPU:-SandyBridge}"
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
echo "=== boot 1: the ISO with four layers and a blank minimum-size NVMe ==="
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
COPY_MS="$(last_num 'copied 4 layers \([0-9]+ MiB\) in [0-9]+ms')"
[ -n "$COPY_MS" ] || fail "tars-install did not say it copied 4 layers" "copied"
echo "B1: tars-install planned and copied ${LAYERS} (${LAYER_MIB} MiB in ${COPY_MS}ms) and wrote version ${VER}"
stop_guest

# ── 부팅 2: NVMe만 ─────────────────────────────────────────────────────
echo "=== boot 2: the NVMe, no network ==="
MONITOR="tcp:127.0.0.1:${MONITOR_PORT},server,nowait"
boot_guest 2
grep -aqF "tars-init: mounted ext4 at /home" "$LOG" || fail "/home is not mounted" "tars-init: home"
wait_log_re "tars-init: overlay /usr from 4 layers in [0-9]+ms" 5 || fail "init did not lay four layers over /usr" "tars-init: layer"
MOUNT_MS="$(last_num 'overlay /usr from 4 layers in [0-9]+ms')"
grep -aqE "tars-init: layer base: [0-9]+ files into /etc" "$LOG" || fail "init did not copy base's etc/ into /etc" "into /etc"
grep -aqF "is not a file or directory, skipped" "$LOG" && fail "init skipped something in a layer's etc/ (links are copied as links since TP-M4)" "skipped"
echo "B2: init mounted ${LAYERS} over /usr in ${MOUNT_MS}ms"

send "grep '^overlay /usr overlay ro' /proc/mounts | sed 's/^/tp-mnt=/'"
wait_log "tp-mnt=overlay /usr overlay ro" 10 || fail "/proc/mounts has no read-only overlay on /usr" "tp-mnt"
grep -aqF "lowerdir=/usr:/run/tars-layers/base/usr:/run/tars-layers/lang-jvm/usr:/run/tars-layers/lang-native/usr:/run/tars-layers/lang-script/usr" "$LOG" \
  || fail "the overlay's lowerdir is not /usr then base, lang-jvm, lang-native, lang-script" "tp-mnt"
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

# TP-M3 plan 결정 F의 스크립트 언어 아홉. 소스는 printf "%s\n" "줄" … — 인자 안의 %는 printf가 안 펴므로 안전하다.
# 피할 것은 $(게스트 bash가 펼친다)와 작은따옴표(as_tars의 겹)다: PHP는 변수 없이, JS는 템플릿 문자열 없이.
# 출력 줄은 시간 줄보다 먼저 나온다(같은 셸이 차례로 찍는다). 그래도 ms 줄을 먼저 기다린 뒤 결과를 본다.
# 상한은 처음 잰 숫자의 세 배다(60초 아래로는 안 내린다). 첫 판(SandyBridge · 1GiB): python 1.4초, venv 27.3초, ruby 1.4초,
# lua 0.04초, luau 0.4초, cyber 0.5초, node 1.4초 · npm 1.9초, bun 0.6초, janet 0.07초, php 0.3초.
as_tars 'cd ~/tp && printf "%s\n" "import sys, ssl, sqlite3" "db = sqlite3.connect(\":memory:\"); db.execute(\"create table t(x)\"); db.execute(\"insert into t values (41)\")" "print(\"tp-py-\" + sys.version.split()[0] + \"-\" + ssl.OPENSSL_VERSION.split()[1] + \"-\" + str(db.execute(\"select x + 1 from t\").fetchone()[0]))" > h.py && s=$(date +%s%N) && python3 h.py 2>&1 | sed "s/^/tp-py: /"; e=$(date +%s%N); echo "tp-ms-py=$(((e-s)/1000000))"'
wait_log_re "tp-ms-py=[0-9]+" 60 || fail "python3 did not finish in 60s" "tp-py"
grep -aqF "tp-py: tp-py-3.15.2-3.5.9-42" "$LOG" || fail "python3 did not print its version, OpenSSL 3.5.9 and the sqlite answer" "tp-py"
echo "B2: as tars, python3 ran with ssl and sqlite3 ($(ms_of py)ms)"

# venv는 ensurepip가 묶음 안의 pip wheel을 홈에 깐다 — 읽기 전용 /usr에서 패키지를 까는 길(plan 결정 E). 망 없이.
as_tars 'cd ~/tp && s=$(date +%s%N) && python3 -m venv ~/tp/v 2>&1 | sed "s/^/tp-venv: /"; e=$(date +%s%N); echo "tp-ms-venv=$(((e-s)/1000000))"; ~/tp/v/bin/python h.py | sed "s/^/tp-venv-ran=/"; ~/tp/v/bin/pip --version | sed "s/^/tp-venv-pip=/"'
wait_log_re "tp-ms-venv=[0-9]+" 90 || fail "python3 -m venv did not finish in 90s" "tp-venv"
wait_log "tp-venv-ran=tp-py-3.15.2" 30 || fail "the venv python did not run" "tp-venv"
wait_log "tp-venv-pip=pip " 60 || fail "the venv has no working pip" "tp-venv"
echo "B2: as tars, python3 -m venv made a venv with pip in the home, offline ($(ms_of venv)ms)"

as_tars 'cd ~/tp && printf "%s\n" "require \"openssl\"" "require \"json\"" "puts \"tp-rb-#{RUBY_VERSION}-\" + JSON.generate([OpenSSL::Digest::SHA256.hexdigest(\"tp\")[0, 8]])" > h.rb && s=$(date +%s%N) && ruby h.rb 2>&1 | sed "s/^/tp-rb: /"; e=$(date +%s%N); echo "tp-ms-rb=$(((e-s)/1000000))"'
wait_log_re "tp-ms-rb=[0-9]+" 60 || fail "ruby did not finish in 60s" "tp-rb"
grep -aqF 'tp-rb: tp-rb-4.0.9-["3abd8072"]' "$LOG" || fail "ruby did not print 4.0.9 and the openssl digest through json" "tp-rb"
echo "B2: as tars, ruby ran with openssl and json ($(ms_of rb)ms)"

as_tars 'cd ~/tp && printf "%s\n" "print(\"tp-lua-\" .. _VERSION)" > h.lua && s=$(date +%s%N) && lua h.lua 2>&1 | sed "s/^/tp-lua: /"; e=$(date +%s%N); echo "tp-ms-lua=$(((e-s)/1000000))"'
wait_log_re "tp-ms-lua=[0-9]+" 60 || fail "lua did not finish in 60s" "tp-lua"
grep -aqF "tp-lua: tp-lua-Lua 5.4" "$LOG" || fail "lua did not print Lua 5.4" "tp-lua"
echo "B2: as tars, lua ran ($(ms_of lua)ms)"

as_tars 'cd ~/tp && printf "%s\n" "local function add(a: number, b: number): number return a + b end" "print(\"tp-luau-\" .. add(40, 2))" > h.luau && s=$(date +%s%N) && luau h.luau 2>&1 | sed "s/^/tp-luau: /"; luau-analyze h.luau 2>&1 | sed "s/^/tp-luau-analyze: /"; echo "tp-luau-analyze-rc=${PIPESTATUS[0]}"; e=$(date +%s%N); echo "tp-ms-luau=$(((e-s)/1000000))"'
wait_log_re "tp-ms-luau=[0-9]+" 60 || fail "luau did not finish in 60s" "tp-luau"
grep -aqF "tp-luau: tp-luau-42" "$LOG" || fail "luau did not run a typed function" "tp-luau"
grep -aqF "tp-luau-analyze-rc=0" "$LOG" || fail "luau-analyze did not pass the typed hello" "tp-luau"
echo "B2: as tars, luau ran a typed function and luau-analyze passed it ($(ms_of luau)ms)"

as_tars 'cd ~/tp && printf "%s\n" "use math" "" "fn add(a, b int) -> int:" "    return a + b" "" "n := add(40, 2)" "print(\"tp-cyber-%{n}-%{math.sqrt(16.0)}\")" > h.cy && s=$(date +%s%N) && cyber h.cy 2>&1 | sed "s/^/tp-cy: /"; e=$(date +%s%N); echo "tp-ms-cyber=$(((e-s)/1000000))"'
wait_log_re "tp-ms-cyber=[0-9]+" 60 || fail "cyber did not finish in 60s" "tp-cy"
grep -aqF "tp-cy: tp-cyber-42-4" "$LOG" || fail "cyber did not run (it reads src/ beside its real path)" "tp-cy"
echo "B2: as tars, cyber ran with use math ($(ms_of cyber)ms)"

as_tars 'cd ~/tp && printf "%s\n" "console.log(\"tp-node-\" + process.version + \"-\" + require(\"crypto\").createHash(\"sha256\").update(\"tp\").digest(\"hex\").slice(0, 8))" > h.js && s=$(date +%s%N) && node h.js 2>&1 | sed "s/^/tp-node: /"; e=$(date +%s%N); echo "tp-ms-node=$(((e-s)/1000000))"; s=$(date +%s%N); npm --version 2>&1 | sed "s/^/tp-npm=/"; e=$(date +%s%N); echo "tp-ms-npm=$(((e-s)/1000000))"'
wait_log_re "tp-ms-npm=[0-9]+" 60 || fail "node and npm did not finish in 60s" "tp-node" "tp-npm"
grep -aqF "tp-node: tp-node-v26.13.0-3abd8072" "$LOG" || fail "node did not print v26.13.0 and the crypto digest" "tp-node"
grep -aqF "tp-npm=11.20.0" "$LOG" || fail "npm --version did not print 11.20.0" "tp-npm"
echo "B2: as tars, node ran with crypto ($(ms_of node)ms) and npm answered ($(ms_of npm)ms)"

as_tars 'cd ~/tp && printf "%s\n" "function add(a: number, b: number): number { return a + b }" "console.log(\"tp-bun-\" + Bun.version + \"-\" + add(40, 2))" > h.ts && s=$(date +%s%N) && bun h.ts 2>&1 | sed "s/^/tp-bun: /"; e=$(date +%s%N); echo "tp-ms-bun=$(((e-s)/1000000))"'
wait_log_re "tp-ms-bun=[0-9]+" 60 || fail "bun did not finish in 60s" "tp-bun"
grep -aqF "tp-bun: tp-bun-1.4.4-42" "$LOG" || fail "bun did not run TypeScript (the baseline build needs no AVX2)" "tp-bun"
echo "B2: as tars, bun ran TypeScript ($(ms_of bun)ms)"

as_tars 'cd ~/tp && printf "%s\n" "(print \"tp-janet-\" janet/version)" > h.janet && s=$(date +%s%N) && janet h.janet 2>&1 | sed "s/^/tp-janet: /"; e=$(date +%s%N); echo "tp-ms-janet=$(((e-s)/1000000))"'
wait_log_re "tp-ms-janet=[0-9]+" 60 || fail "janet did not finish in 60s" "tp-janet"
grep -aqF "tp-janet: tp-janet-1.42.1" "$LOG" || fail "janet did not print 1.42.1" "tp-janet"
echo "B2: as tars, janet ran ($(ms_of janet)ms)"

as_tars 'cd ~/tp && printf "%s\n" "<?php echo \"tp-php-\" . PHP_VERSION . \"-\" . json_encode([1, 2]) . \"-\" . var_export(ctype_digit(\"42\"), true) . PHP_EOL;" > h.php && s=$(date +%s%N) && php h.php 2>&1 | sed "s/^/tp-php: /"; e=$(date +%s%N); echo "tp-ms-php=$(((e-s)/1000000))"'
wait_log_re "tp-ms-php=[0-9]+" 60 || fail "php did not finish in 60s" "tp-php"
grep -aqF "tp-php: tp-php-8.4.27-[1,2]-true" "$LOG" || fail "php did not print 8.4.27, json and ctype (conf.d links into /etc)" "tp-php"
echo "B2: as tars, php ran with json ($(ms_of php)ms)"
SCRIPT_NUMBERS="python $(ms_of py)ms, venv $(ms_of venv)ms, ruby $(ms_of rb)ms, lua $(ms_of lua)ms, luau $(ms_of luau)ms, cyber $(ms_of cyber)ms, node $(ms_of node)ms, npm $(ms_of npm)ms, bun $(ms_of bun)ms, janet $(ms_of janet)ms, php $(ms_of php)ms"

# rc는 bash -i가 아니라 . /etc/bash.bashrc로 읽는다 — 보려는 것은 rc의 내용이고, 대화형 셸이 콘솔 tty를 만질 일을 만들지 않는다.
# 표시 글자는 명령 줄에 그대로 나오면 안 된다 — 콘솔이 명령을 되비추므로 wait_log가 출력 전에 맞는다(TP-M4 체인 둘째 판의 거짓
# 통과). 그래서 printf "tp-m4-%s\n" xxd-ok 꼴이나 sed 접두로 짓는다.
# ── TP-M4: base 보강(plan 결정 F) — 빌드 · 디버깅 · 원격 · 오프라인 man. 망 없이, 사용자로. ────────────────────────
# 소스는 printf "%s\n" "줄" … 한 겹(TP-M3과 같다). C 문자열의 \n은 %s가 안 펴므로 그대로 C의 이스케이프가 된다.
# 상한은 처음 잰 숫자의 세 배다(60초 아래로는 안 내린다). 첫 판(SandyBridge · 1GiB): cmake+ninja 2.5초, autotools 13.7초, perl 0.6초,
# gdb 3.6초, valgrind 4.4초, gpg 0.6초, root의 전역 설치 셋 24.3초.
as_tars 'mkdir -p ~/tp/m4 && cd ~/tp/m4 && printf "%s\n" "#include <stdio.h>" "#include <stdlib.h>" "void boom(int *p) { *p = 1; }" "int main(int c, char **v) { (void)v; if (c > 1) boom(0); char *m = malloc(64); m[0] = 0; printf(\"tp-m4c\n\"); return m[0]; }" > h.c && printf "%s\n" "cmake_minimum_required(VERSION 3.20)" "project(tp C)" "add_executable(hc h.c)" > CMakeLists.txt && s=$(date +%s%N) && cmake -S . -B b -G Ninja > cm.log 2>&1; ninja -C b 2>&1 | sed "s/^/tp-m4-ninja: /"; e=$(date +%s%N); echo "tp-ms-cmake=$(((e-s)/1000000))"; ./b/hc | sed "s/^/tp-m4-cmake=/"'
wait_log_re "tp-ms-cmake=[0-9]+" 60 || fail "cmake and ninja did not finish in 60s" "tp-m4-ninja"
wait_log "tp-m4-cmake=tp-m4c" 30 || fail "cmake -G Ninja and ninja did not build a running program" "tp-m4-ninja"
echo "B2: as tars, cmake -G Ninja and ninja built and ran a C program ($(ms_of cmake)ms)"

as_tars 'mkdir -p ~/tp/m4/at && cd ~/tp/m4/at && printf "%s\n" "AC_INIT([tpa],[1.0])" "AM_INIT_AUTOMAKE([foreign subdir-objects])" "AC_PROG_CC" "AC_CONFIG_FILES([Makefile])" "AC_OUTPUT" > configure.ac && printf "%s\n" "bin_PROGRAMS = tpa" "tpa_SOURCES = h.c" > Makefile.am && cp ../h.c . && s=$(date +%s%N) && { autoreconf -i && ./configure && make; } > at.log 2>&1; echo "tp-m4-at-rc=$?"; e=$(date +%s%N); echo "tp-ms-autotools=$(((e-s)/1000000))"; ./tpa | sed "s/^/tp-m4-at=/"; tail -3 at.log | sed "s/^/tp-m4-atlog: /"'
wait_log_re "tp-ms-autotools=[0-9]+" 60 || fail "autoreconf, configure and make did not finish in 60s" "tp-m4-at"
wait_log "tp-m4-at=tp-m4c" 30 || fail "autoreconf -i, ./configure and make did not build a running program" "tp-m4-at"
echo "B2: as tars, autoreconf -i, ./configure and make built and ran a program ($(ms_of autotools)ms)"

as_tars 'cd ~/tp/m4 && printf "%s\n" "Name: tp" "Description: tp" "Version: 4.2" "Cflags: -I/tmp" > tp.pc && PKG_CONFIG_PATH=$HOME/tp/m4 pkg-config --modversion tp | sed "s/^/tp-m4-pc=/"; s=$(date +%s%N); perl -MData::Dumper -MJSON::PP -MDigest::SHA=sha256_hex -MTest::More -e "print JSON::PP->new->encode([substr(sha256_hex(q(tp)), 0, 8)])" 2>&1 | sed "s/^/tp-m4-perl=/"; echo; e=$(date +%s%N); echo "tp-ms-perl=$(((e-s)/1000000))"; perldoc -l strict | sed "s/^/tp-m4-perldoc=/"'
wait_log_re "tp-ms-perl=[0-9]+" 60 || fail "perl did not finish in 60s" "tp-m4-perl"
wait_log "tp-m4-pc=4.2" 10 || fail "pkg-config did not read a .pc from PKG_CONFIG_PATH" "tp-m4-pc"
grep -aqF 'tp-m4-perl=["3abd8072"]' "$LOG" || fail "perl did not run Data::Dumper, JSON::PP, Digest::SHA and Test::More" "tp-m4-perl"
wait_log "tp-m4-perldoc=/usr/share/perl/" 30 || fail "perldoc did not find strict" "tp-m4-perldoc"
echo "B2: as tars, pkg-config read a .pc, perl ran with four core modules ($(ms_of perl)ms) and perldoc answered"

# 디버거 셋. 일부러 죽는 프로그램(인자 하나면 boom(0))의 백트레이스, 시스템 콜 · 라이브러리 호출의 요약, 일부러 새는 malloc.
as_tars 'cd ~/tp/m4 && gcc -g -O0 -o hg h.c && s=$(date +%s%N) && gdb -q -batch -ex run -ex bt --args ./hg x 2>&1 | sed "s/^/tp-m4-gdb: /"; e=$(date +%s%N); echo "tp-ms-gdb=$(((e-s)/1000000))"; strace -c ./hg 2>&1 | tail -2 | sed "s/^/tp-m4-strace: /"; ltrace -c ./hg 2>&1 | tail -2 | sed "s/^/tp-m4-ltrace: /"; s=$(date +%s%N); valgrind -q --leak-check=full --errors-for-leak-kinds=definite --error-exitcode=9 ./hg > vg.log 2>&1; echo "tp-m4-vg-rc=$?"; e=$(date +%s%N); echo "tp-ms-valgrind=$(((e-s)/1000000))"'
wait_log_re "tp-ms-valgrind=[0-9]+" 60 || fail "gdb, strace, ltrace and valgrind did not finish in 60s" "tp-m4-gdb" "tp-m4-strace"
grep -aqE "tp-m4-gdb: #0 +(0x[0-9a-f]+ in )?boom" "$LOG" || fail "gdb did not show boom at the top of the backtrace" "tp-m4-gdb"
grep -aqE "tp-m4-strace: .*total" "$LOG" || fail "strace -c did not print its summary" "tp-m4-strace"
grep -aqE "tp-m4-ltrace: .*total" "$LOG" || fail "ltrace -c did not print its summary" "tp-m4-ltrace"
grep -aqF "tp-m4-vg-rc=9" "$LOG" || fail "valgrind did not report the definite leak with exit code 9" "tp-m4-vg"
echo "B2: as tars, gdb ($(ms_of gdb)ms) showed boom in the backtrace, strace and ltrace summed up, valgrind caught the leak ($(ms_of valgrind)ms)"

as_tars 'cd ~/tp/m4 && echo hello > z.txt && xz -k z.txt && zstd -q -k z.txt && zip -q z.zip z.txt && unzip -o -q z.zip -d zz && tar -cJf z.tar.xz z.txt && [ "$(xz -dc z.txt.xz)$(zstd -dcq z.txt.zst)$(cat zz/z.txt)$(tar -xOJf z.tar.xz)$(bzip2 -c z.txt | bzip2 -dc)" = hellohellohellohellohello ] && printf "tp-m4-%s\n" zip-ok; file -b hg | cut -c1-10 | sed "s/^/tp-m4-file=/"; printf "a\nb\n" > p1; printf "a\nc\n" > p2; diff -u p1 p2 > p.diff; patch -s p1 p.diff && cmp p1 p2 && printf "tp-m4-%s\n" patch-ok; xxd hg | xxd -r | cmp - hg && printf "tp-m4-%s\n" xxd-ok'
wait_log "tp-m4-xxd-ok" 120 || fail "xxd did not round-trip a binary" "tp-m4"
grep -aqF "tp-m4-zip-ok" "$LOG" || fail "xz, zstd, zip/unzip, tar -J and bzip2 did not all round-trip" "tp-m4"
grep -aqF "tp-m4-file=ELF 64-bit" "$LOG" || fail "file did not recognise an ELF" "tp-m4-file"
grep -aqF "tp-m4-patch-ok" "$LOG" || fail "patch did not apply a unified diff" "tp-m4"
echo "B2: as tars, xz, zstd, zip, unzip, tar -J and bzip2 round-tripped; file, patch and xxd work"

as_tars 'cd ~/tp/m4 && ssh -V 2>&1 | sed "s/^/tp-m4-ssh=/"; ssh-keygen -q -t ed25519 -N "" -f k && test -f k.pub && printf "tp-m4-%s\n" keygen-ok; mkdir -p r1/s && echo x > r1/s/f && rsync -a r1/ r2/ && cmp r1/s/f r2/s/f && printf "tp-m4-%s\n" rsync-ok; s=$(date +%s%N); gpg --batch --passphrase "" --quick-gen-key tp@tars > gpg.log 2>&1; gpg --list-keys tp@tars 2>/dev/null | grep -c tp@tars | sed "s/^/tp-m4-gpg=/"; e=$(date +%s%N); echo "tp-ms-gpg=$(((e-s)/1000000))"; gpgconf --kill gpg-agent'
wait_log_re "tp-ms-gpg=[0-9]+" 60 || fail "ssh, rsync and gpg did not finish in 60s" "tp-m4-ssh" "tp-m4-gpg"
grep -aqF "tp-m4-ssh=OpenSSH_10.0" "$LOG" || fail "ssh -V did not print OpenSSH_10.0" "tp-m4-ssh"
grep -aqF "tp-m4-keygen-ok" "$LOG" || fail "ssh-keygen did not make an ed25519 key" "tp-m4"
grep -aqF "tp-m4-rsync-ok" "$LOG" || fail "rsync -a did not copy a tree" "tp-m4"
grep -aqF "tp-m4-gpg=1" "$LOG" || fail "gpg did not make and list a key offline" "tp-m4-gpg"
echo "B2: as tars, ssh -V, ssh-keygen, rsync -a and gpg --quick-gen-key ($(ms_of gpg)ms) work offline"

as_tars 'cd ~/tp/m4 && MANPAGER=cat man 3 printf 2>&1 | grep -m1 -E "printf, +fprintf" | sed -E "s/^ *([a-z]+), +([a-z]+),.*/tp-m4-man3=\1-\2/"; MANPAGER=cat man 1 ssh 2>&1 | grep -m1 "OpenSSH remote login client" | sed "s/^ */tp-m4-man1=/"; printf "%s\n" "#!/bin/sh" "echo \$1" > bad.sh; shellcheck bad.sh 2>&1 | grep -o "SC2086" | head -1 | sed "s/^/tp-m4-sc=/"; ctags -x h.c | grep -o "^boom" | sed "s/^/tp-m4-ctags=/"; fish -c "string join : \$PATH" | sed "s/^/tp-m4-fishpath=/"; bash -c ". /etc/bash.bashrc; echo \$PATH" 2>/dev/null | sed "s/^/tp-m4-bashpath=/"'
wait_log_re "tp-m4-bashpath=/[a-z]" 120 || fail "man, shellcheck, ctags and the PATH probes did not finish in 120s" "tp-m4"
grep -aqF "tp-m4-man3=printf-fprintf" "$LOG" || fail "man 3 printf did not show the C library page (manpages-dev)" "tp-m4-man"
grep -aqF "tp-m4-man1=ssh" "$LOG" || fail "man 1 ssh did not show the page (man pages harvested)" "tp-m4-man"
grep -aqF "tp-m4-sc=SC2086" "$LOG" || fail "shellcheck did not flag the unquoted \$1" "tp-m4-sc"
grep -aqF "tp-m4-ctags=boom" "$LOG" || fail "ctags -x did not list boom" "tp-m4-ctags"
grep -aqE "tp-m4-fishpath=.*/home/tars/\.cargo/bin" "$LOG" || fail "fish has no ~/.cargo/bin on PATH (10-lang-native.fish)" "tp-m4-fishpath"
grep -aqE "tp-m4-bashpath=.*/home/tars/go/bin" "$LOG" || fail "bash with /etc/bash.bashrc has no ~/go/bin on PATH (/etc/tars/rc.d)" "tp-m4-bashpath"
echo "B2: as tars, man 3 printf and man 1 ssh read offline, shellcheck and ctags work, fish and /etc/bash.bashrc put ~/.cargo/bin and ~/go/bin on PATH"

# ── TP-M4: 쓰기 가능한 /usr/local(plan 결정 E · H) ──────────────────────────────────────────
# 사용자가 망 없이 로컬 패키지 셋을 짓고, root(콘솔 fish)가 전역으로 깐다. 실행 파일은 /usr/local/bin에 서야 한다.
grep -aqF "tars-init: /usr/local writable (upper on /home/.tars/local)" "$LOG" || fail "init did not make /usr/local writable" "tars-init: /usr/local"
as_tars 'mkdir -p ~/tp/m4/pk/n ~/tp/m4/pk/g/exe ~/tp/m4/pk/w/tpw && cd ~/tp/m4/pk/n && printf "%s\n" "{\"name\":\"tpn\",\"version\":\"1.0.0\",\"bin\":{\"tpn\":\"cli.js\"}}" > package.json && printf "%s\n" "#!/usr/bin/env node" "console.log(\"tp-npm-ok\")" > cli.js && npm pack --silent --pack-destination .. > /dev/null 2>&1; cd ../g && printf "%s\n" "puts \"tp-gem-ok\"" > exe/tpg && chmod +x exe/tpg && printf "%s\n" "Gem::Specification.new do |s|" "  s.name = \"tpg\"; s.version = \"1.0\"; s.summary = \"tp\"; s.authors = [\"tp\"]" "  s.files = [\"exe/tpg\"]; s.bindir = \"exe\"; s.executables = [\"tpg\"]" "end" > tpg.gemspec && gem build -q tpg.gemspec -o ../tpg-1.0.gem > /dev/null 2>&1; cd ../w && printf "%s\n" "def main():" "    print(\"tp-pip-ok\")" > tpw/__init__.py && printf "%s\n" "import zipfile" "z = zipfile.ZipFile(\"../tpw-1.0-py3-none-any.whl\", \"w\")" "z.write(\"tpw/__init__.py\")" "z.writestr(\"tpw-1.0.dist-info/METADATA\", \"Metadata-Version: 2.1\nName: tpw\nVersion: 1.0\n\")" "z.writestr(\"tpw-1.0.dist-info/WHEEL\", \"Wheel-Version: 1.0\nGenerator: tp\nRoot-Is-Purelib: true\nTag: py3-none-any\n\")" "z.writestr(\"tpw-1.0.dist-info/entry_points.txt\", \"[console_scripts]\ntpw = tpw:main\n\")" "z.writestr(\"tpw-1.0.dist-info/RECORD\", \"\")" "z.close()" > mk.py && python3 mk.py; cd ~/tp/m4/pk && ls *.gem *.tgz *.whl | tr "\n" " " | sed "s/^/tp-m4-pk=/"; echo'
wait_log "tp-m4-pk=tpg-1.0.gem tpn-1.0.0.tgz tpw-1.0-py3-none-any.whl" 300 || fail "npm pack, gem build and the wheel did not all come out" "tp-m4-pk"
send "set -l s (date +%s%N); npm i -g --offline /home/tars/tp/m4/pk/tpn-1.0.0.tgz 2>&1 | sed 's/^/tp-m4-npmg: /'; gem install --local /home/tars/tp/m4/pk/tpg-1.0.gem 2>&1 | sed 's/^/tp-m4-gemg: /'; python3 -m pip install --no-index --root-user-action=ignore /home/tars/tp/m4/pk/tpw-1.0-py3-none-any.whl 2>&1 | sed 's/^/tp-m4-pipg: /'; set -l e (date +%s%N); echo tp-ms-globals=(math --scale 0 \"(\$e - \$s) / 1000000\")"
wait_log_re "tp-ms-globals=[0-9]+" 80 || fail "root's npm -g, gem install and pip install did not finish in 80s" "tp-m4-npmg" "tp-m4-gemg" "tp-m4-pipg"
as_tars 'for c in tpn tpg tpw; do command -v $c | sed "s/^/tp-m4-where=/"; $c | sed "s/^/tp-m4-ran=/"; done; touch /usr/local/tp-x 2>&1 | sed "s/^/tp-m4-ulocal=/"; touch /usr/bin/tp-x 2>&1 | sed "s/^/tp-m4-ubin=/"; python3 -c "import tpw; print(tpw.__file__)" | sed "s/^/tp-m4-purelib=/"'
wait_log_re "tp-m4-purelib=/[a-z]" 60 || fail "the global-install probes did not finish" "tp-m4-where"
for c in tpn tpg tpw; do grep -aqF "tp-m4-where=/usr/local/bin/${c}" "$LOG" || fail "${c} is not in /usr/local/bin" "tp-m4-where" "tp-m4-npmg" "tp-m4-gemg" "tp-m4-pipg"; done
for w in npm gem pip; do grep -aqF "tp-m4-ran=tp-${w}-ok" "$LOG" || fail "the ${w} package root installed globally did not run as tars" "tp-m4"; done
grep -aqF "tp-m4-ulocal=touch: cannot touch '/usr/local/tp-x': Permission denied" "$LOG" || fail "tars could write /usr/local (it is root's)" "tp-m4-ulocal"
grep -aqF "tp-m4-ubin=touch: cannot touch '/usr/bin/tp-x': Read-only file system" "$LOG" || fail "/usr/bin is no longer read-only" "tp-m4-ubin"
grep -aqF "tp-m4-purelib=/usr/local/lib/python3.15/site-packages/tpw/__init__.py" "$LOG" || fail "root's pip did not put the module in /usr/local/lib/python3.15 (sitecustomize.py)" "tp-m4-purelib"
echo "B2: root's npm i -g, gem install and pip install (offline, local files, $(ms_of globals)ms) put tpn, tpg and tpw in /usr/local/bin; tars runs them but cannot write /usr/local"
M4_NUMBERS="cmake+ninja $(ms_of cmake)ms, autotools $(ms_of autotools)ms, perl $(ms_of perl)ms, gdb $(ms_of gdb)ms, valgrind $(ms_of valgrind)ms, gpg $(ms_of gpg)ms, globals $(ms_of globals)ms"

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
NUMBERS="gcc $(ms_of gcc)ms, make $(ms_of make)ms, g++ $(ms_of cpp)ms, zig $(ms_of zig)ms, rustc $(ms_of rustc)ms, cargo $(ms_of cargo)ms, go run $(ms_of gorun)ms, go build $(ms_of gobuild)ms, ${SCRIPT_NUMBERS}, ${M4_NUMBERS}, javac $(ms_of javac)ms, java $(ms_of java)ms, jwebserver $(ms_of web)ms, MemAvailable ${MEM_KB:-?} kB"
# 부팅 3의 재료. 묶음이 loop로 열린 채 그 뒤 파일을 0으로 바꾼다 — java는 이미 끝났다. sync 뒤에 QEMU를 죽인다.
send "head -c 4096 /dev/zero > /home/.tars/layers/lang-jvm.sqfs; and sync; and printf 'tp-%s\n' broke-done"
wait_log "tp-broke-done" 30 || fail "root could not overwrite /home/.tars/layers/lang-jvm.sqfs"
stop_guest

# ── 부팅 3: NVMe만 — 깨진 묶음 하나 ────────────────────────────────────
echo "=== boot 3: the NVMe with lang-jvm broken ==="
MONITOR="none"
boot_guest 3
grep -aqE "tars-init: layer lang-jvm: mount failed \(errno [0-9]+\)" "$LOG" || fail "init did not name the broken layer" "tars-init: layer"
grep -aqE "tars-init: overlay /usr from 3 layers in [0-9]+ms" "$LOG" || fail "init did not lay base, lang-native and lang-script over /usr" "tars-init: overlay"
grep -aqF "tars-init: config shell=" "$LOG" || fail "the boot did not go on to the config line"
as_tars 'cd ~/tp && gcc -O2 -o h2 h.c -lm -lresolv && ./h2 | sed "s/^/tp-b3-c=/"; go run h.go | sed "s/^/tp-b3-go=/"; node h.js | sed "s/^/tp-b3-node=/"; command -v java || printf "tp-%s\n" no-java'
wait_log "tp-b3-c=tp-c-1.414-0" 180 || fail "gcc no longer works without lang-jvm" "tp-b3"
wait_log "tp-b3-go=tp-go-go1.27.3" 60 || fail "go no longer works without lang-jvm" "tp-b3"
wait_log "tp-b3-node=tp-node-v26.13.0-3abd8072" 60 || fail "node no longer works without lang-jvm" "tp-b3"
grep -aqF "tars-init: /usr/local writable (upper on /home/.tars/local)" "$LOG" || fail "boot 3 did not make /usr/local writable" "tars-init: /usr/local"
as_tars 'for c in tpn tpg tpw; do $c; done | sed "s/^/tp-b3-global=/"'
wait_log "tp-b3-global=tp-pip-ok" 60 || fail "what root installed in /usr/local did not survive the reboot" "tp-b3-global"
wait_log "tp-no-java" 10 || fail "java is still there with lang-jvm broken" "tp-b3"
echo "B3: a broken lang-jvm is named and skipped; base, lang-native and lang-script still run C, Go and node, what root put in /usr/local is still there, and the boot is otherwise the same"
stop_guest

# ── 부팅 4: ISO + 같은 NVMe — 갱신 ─────────────────────────────────────
echo "=== boot 4: the ISO again over the installed NVMe (update) ==="
boot_guest 4 -cdrom "$ISO"
send "tars-install /dev/nvme0n1 --yes"
wait_log "tars-install: updated. remove the boot medium and reboot." 600 || fail "the update did not say updated" "tars-install:"
grep -aqF "  p3 (tars-home) <- layers ${VER} -> ${VER} (${LAYER_MIB} MiB), your files are not touched" "$LOG" \
  || fail "the update plan does not say p3 gets the layers" "(tars-home)"
grep -aqF "  .tars/layers: 4 old layers removed" "$LOG" || fail "the update did not remove the four old layers first" ".tars/layers"
grep -aqF "  .tars/layers/lang-jvm.sqfs $(stat -c %s ../devlayer/build/lang-jvm.sqfs) bytes" "$LOG" \
  || fail "the update did not put lang-jvm.sqfs back byte for byte" ".tars/layers"
echo "B4: the update planned the layers on p3, removed the four old ones and put them back"
stop_guest

echo "devtools: numbers: layers ${LAYER_MIB} MiB, copy ${COPY_MS}ms, overlay ${MOUNT_MS}ms, ${NUMBERS}"
echo "devtools: chain $(( $(date +%s) - CHAIN_T0 ))s after the build"
echo "PASS"
exit 0
