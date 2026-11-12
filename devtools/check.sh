#!/usr/bin/env bash
# shellcheck disable=SC2016 # 이 파일 전체: as_tars '…'의 $(…) · $((…))는 게스트의 bash가 펼친다
set -euo pipefail

cd "$(dirname "$0")" || exit 1

# TP-M1: 서른한째 체인. 개발 도구 층(TP design 결정 8~13) — 묶음을 실은 ISO로 설치하고, 디스크로 다시 뜬 게스트가
# 망 없이 사용자로 C와 Java를 짓고 돌리는가. 체인은 모두 `-nic none`이다(오프라인이 목표).
# TP-M2: 묶음이 셋이다(base · lang-jvm · lang-native). 부팅 2가 C++ · zig · rust · cargo · go의 hello를 더 본다(plan 결정 G).
# TP-M4: base 보강(빌드 · 디버깅 · 원격 · man)의 hello와 쓰기 가능한 /usr/local(root가 전역으로 깐 셋이 재부팅 뒤에도 선다, plan 결정 F · H).
# TP-M3: 넷째 묶음 lang-script. 부팅 2가 python(+ venv) · ruby · lua · luau · cyber · node(+ npm) · bun · janet · php를 본다(plan 결정 F).
# TP-M5: 다섯째 묶음 util(cci · glc). 부팅 2가 kotlin · clojure(첫 실행 시드) · clj(rlwrap) · cci · glc · man clojure를 본다(plan 결정 F).
# TP-M6: 여섯째 묶음 lang-beam. 부팅 2가 erl · erlc · escript · elixir · iex · mix test 세 번 · gleam(시드와 manifest.toml) · erl -man을 본다(plan 결정 G).
# TP-M7: 일곱째 묶음 editor. 부팅 2가 ms(health) · nvim(treesitter, 고쳐 쓰기) · ttt(--exec) · man nvim을 본다(plan 결정 F). LD-M0: emacs는 없다.
# TP-M8: 여덟째 묶음 media(ffmpeg · ImageMagick · GraphicsMagick)와 util의 터미널 유틸리티(plan 결정 E · F).
# TP-M9: 아홉째 묶음 docs(dasht · w3m · Bash docset). 부팅 2가 rc 조각의 링크 · 찾기 · w3m -dump · man dasht · fish 조각을 본다(plan 할 일 6).
# TP-M10: 열째 묶음 server(postgresql · mysql · nginx · redis · caddy). 부팅 2가 다섯을 사용자로 띄워 응답을 받고 끈다(plan 할 일 7).
# TP-M11: 서버가 서비스가 된다. 부팅 2가 tars-service enable로 다섯을 켜고 쓰고 CA를 넣고, 부팅 3이 저절로 뜬 다섯과 남은 데이터 · 조각 · 신뢰를
#        보고 disable redis로 끈다(plan 할 일 4). -m은 2048로 올렸다(아래).
# CE-M2: 열하나째 묶음 container(Docker Engine · compose · buildx · bubblewrap · socat). 부팅 2가 사용자의 bwrap, tars-service enable docker,
#        sudo 없는 docker info, 망 없이 docker import로 만든 이미지의 컨테이너가 -p로 답하는 것, 방화벽과의 공존을 보고, 부팅 3이 저절로
#        뜬 dockerd와 남은 이미지 · 다시 뜬 컨테이너를 보고 disable docker로 끈다(CE design 결정 4~8).
#
# 부팅 넷이 같은 NVMe 이미지를 잇달아 쓴다(plan 결정 G).
#   1  ISO(묶음 열둘) + 빈 최소 NVMe   tars-install --yes — 계획의 layers 줄, 복사 줄, done
#   2  NVMe만                          overlay /usr from 12, 읽기 전용, /etc/gprofng.rc, 사용자로 gcc · make · g++ · zig ·
#                                      rustc · cargo · go run · go build · 스크립트 언어 아홉 · javac · java · jwebserver + curl, kotlinc ·
#                                      clojure · clj · cci · glc · man clojure, BEAM 셋, 편집기 셋(LD-M0이 emacs를 뺐다), fakesteak, 서버 다섯, 화면 셸에서
#                                      java --version(monitor 45504), bwrap · docker 서비스 · 컨테이너 둘 · firewall=on. 끝에 root가
#                                      /home/.tars/layers/lang-jvm.sqfs를 4KiB의 0으로 바꾼다
#   3  NVMe만                          layer lang-jvm: mount failed, overlay /usr from 11, gcc · go · node · cci · erl · nvim은 돌고 java는 없다,
#                                      dockerd가 저절로 뜨고 keep 컨테이너가 다시 답한다
#   4  ISO + 같은 NVMe                 갱신 — p3 줄이 layers <ver> -> <ver>, 옛 묶음 열둘을 지우고 새로(깨진 것을 고친다)
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
../devlayer/build.sh container
../devlayer/build.sh docs
../devlayer/build.sh editor
../devlayer/build.sh lang-beam
../devlayer/build.sh lang-jvm
../devlayer/build.sh lang-native
../devlayer/build.sh lang-script
../devlayer/build.sh media
../devlayer/build.sh server
../devlayer/build.sh util
(cd ../boot && ISO_LAYERS="base container docs editor lang-beam lang-jvm lang-native lang-script media server util fakesteak" ISO_OUT=../out/tars-dev.iso ./make_iso.sh)

source ../gate_lib.sh

ISO=../out/tars-dev.iso
OVMF_CODE="/usr/share/OVMF/OVMF_CODE_4M.fd"
if [ ! -f "$OVMF_CODE" ]; then
  echo "FAIL: ${OVMF_CODE} not found; is the devcontainer image current?" >&2
  exit 1
fi

# LD-M0: fakesteak이 열둘째다(이름 순 — tars-install의 계획 줄이 이름 순으로 찍는다).
LAYERS="base container docs editor fakesteak lang-beam lang-jvm lang-native lang-script media server util"
LAYER_BYTES=0
for b in $LAYERS; do LAYER_BYTES=$(( LAYER_BYTES + $(stat -c %s "../devlayer/build/${b}.sqfs") )); done
LAYER_MIB=$(( (LAYER_BYTES + 1048575) / 1048576 ))
echo "devtools: iso $(stat -c %s "$ISO") bytes, layers ${LAYER_BYTES} bytes (${LAYER_MIB} MiB)"

WORK="$(mktemp -d)"
DISK="${WORK}/target.img"
# tars-install의 최소 디스크(disk.MIN_DISK_BYTES = 16 GiB + 2 MiB).
truncate -s 16386M "$DISK"

# -m은 2048이다(TP-M11, 사용자 2026-11-08 — 서버 다섯이 함께 뜬다). 맥북 에어 2011의 바닥 2GB와 같다.
# TP-M10까지는 mise와 같은 1024였고 JVM이 그 위에서 서는지도 판정의 일부였다.
# -cpu는 SandyBridge다(TP-M3, 사용자 결정 2026-11-06). 다른 체인의 qemu64는 x86-64 첫 세대라 SSSE3가 없다 — rv-ruby가
# require_internal의 palignr에서 Illegal instruction으로 죽었다. 개발 도구 층의 실제 바닥은 맥북 에어 2011(Sandy Bridge:
# SSSE3 · SSE4.2 · POPCNT · AVX, AVX2는 없다)이라 그 세대로 돈다. AVX2가 없으므로 bun은 여전히 baseline이어야 한다.
TP_CPU="${TP_CPU:-SandyBridge}"
TP_MEM="${TP_MEM:-2048}"
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

# TP-M11. root로 bash 한 줄. 콘솔 셸은 fish라 bash 문법은 이 겹 안에 둔다. 인자의 규칙은 as_tars와 같다.
as_root() {
  send "bash -c '$1'"
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
echo "=== boot 1: the ISO with twelve layers and a blank minimum-size NVMe ==="
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
COPY_MS="$(last_num 'copied 12 layers \([0-9]+ MiB\) in [0-9]+ms')"
[ -n "$COPY_MS" ] || fail "tars-install did not say it copied 12 layers" "copied"
echo "B1: tars-install planned and copied ${LAYERS} (${LAYER_MIB} MiB in ${COPY_MS}ms) and wrote version ${VER}"
stop_guest

# ── 부팅 2: NVMe만 ─────────────────────────────────────────────────────
echo "=== boot 2: the NVMe, no network ==="
MONITOR="tcp:127.0.0.1:${MONITOR_PORT},server,nowait"
boot_guest 2
grep -aqF "tars-init: mounted ext4 at /home" "$LOG" || fail "/home is not mounted" "tars-init: home"
wait_log_re "tars-init: overlay /usr from 12 layers in [0-9]+ms" 5 || fail "init did not lay twelve layers over /usr" "tars-init: layer"
MOUNT_MS="$(last_num 'overlay /usr from 12 layers in [0-9]+ms')"
grep -aqE "tars-init: layer base: [0-9]+ files into /etc" "$LOG" || fail "init did not copy base's etc/ into /etc" "into /etc"
grep -aqF "is not a file or directory, skipped" "$LOG" && fail "init skipped something in a layer's etc/ (links are copied as links since TP-M4)" "skipped"
echo "B2: init mounted ${LAYERS} over /usr in ${MOUNT_MS}ms"

send "grep '^overlay /usr overlay ro' /proc/mounts | sed 's/^/tp-mnt=/'"
wait_log "tp-mnt=overlay /usr overlay ro" 10 || fail "/proc/mounts has no read-only overlay on /usr" "tp-mnt"
grep -aqF "lowerdir=/usr:/run/tars-layers/base/usr:/run/tars-layers/container/usr:/run/tars-layers/docs/usr:/run/tars-layers/editor/usr:/run/tars-layers/fakesteak/usr:/run/tars-layers/lang-beam/usr:/run/tars-layers/lang-jvm/usr:/run/tars-layers/lang-native/usr:/run/tars-layers/lang-script/usr:/run/tars-layers/media/usr:/run/tars-layers/server/usr:/run/tars-layers/util/usr" "$LOG" \
  || fail "the overlay's lowerdir is not /usr then base, container, docs, editor, fakesteak, lang-beam, lang-jvm, lang-native, lang-script, media, server, util" "tp-mnt"
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
grep -aqF "tp-cy: tp-cyber-42-4" "$LOG" || fail "cyber did not run (its std modules are built in since 0.4.7)" "tp-cy"
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

as_tars 'cd ~/tp/m4 && MANPAGER=cat man 3 printf 2>&1 | grep -m1 -E "printf, +fprintf" | sed -E "s/^ *([a-z]+), +([a-z]+),.*/tp-m4-man3=\1-\2/"; MANPAGER=cat man 1 ssh 2>&1 | grep -m1 "OpenSSH remote login client" | sed "s/^ */tp-m4-man1=/"; printf "%s\n" "#!/bin/sh" "echo \$1" > bad.sh; shellcheck bad.sh 2>&1 | grep -o "SC2086" | head -1 | sed "s/^/tp-m4-sc=/"; ctags -x h.c | grep -o "^boom" | sed "s/^/tp-m4-ctags=/"; mkdir -p ~/.local/bin; fish -c "string join : \$PATH" | sed "s/^/tp-m4-fishpath=/"; bash -c ". /etc/bash.bashrc; echo \$PATH" 2>/dev/null | sed "s/^/tp-m4-bashpath=/"'
wait_log_re "tp-m4-bashpath=/[a-z]" 120 || fail "man, shellcheck, ctags and the PATH probes did not finish in 120s" "tp-m4"
grep -aqF "tp-m4-man3=printf-fprintf" "$LOG" || fail "man 3 printf did not show the C library page (manpages-dev)" "tp-m4-man"
grep -aqF "tp-m4-man1=ssh" "$LOG" || fail "man 1 ssh did not show the page (man pages harvested)" "tp-m4-man"
grep -aqF "tp-m4-sc=SC2086" "$LOG" || fail "shellcheck did not flag the unquoted \$1" "tp-m4-sc"
grep -aqF "tp-m4-ctags=boom" "$LOG" || fail "ctags -x did not list boom" "tp-m4-ctags"
grep -aqE "tp-m4-fishpath=.*/home/tars/\.cargo/bin" "$LOG" || fail "fish has no ~/.cargo/bin on PATH (10-lang-native.fish)" "tp-m4-fishpath"
grep -aqE "tp-m4-bashpath=.*/home/tars/go/bin" "$LOG" || fail "bash with /etc/bash.bashrc has no ~/go/bin on PATH (/etc/tars/rc.d)" "tp-m4-bashpath"
# TP-M12: bun의 전역 bin(lang-script의 조각)과, 있을 때만 넣는 ~/.local/bin(시스템 rc — 위에서 만들었다). 공식 설치기가 두는 자리다.
grep -aqE "tp-m4-fishpath=.*/home/tars/\.bun/bin" "$LOG" || fail "fish has no ~/.bun/bin on PATH (10-lang-script.fish)" "tp-m4-fishpath"
grep -aqE "tp-m4-bashpath=.*/home/tars/\.bun/bin" "$LOG" || fail "bash with /etc/bash.bashrc has no ~/.bun/bin on PATH (/etc/tars/rc.d)" "tp-m4-bashpath"
grep -aqE "tp-m4-fishpath=/home/tars/\.local/bin:" "$LOG" || fail "fish does not put an existing ~/.local/bin first on PATH (user-bin.fish)" "tp-m4-fishpath"
grep -aqE "tp-m4-bashpath=/home/tars/\.local/bin:" "$LOG" || fail "bash with /etc/bash.bashrc does not put an existing ~/.local/bin first on PATH" "tp-m4-bashpath"
echo "B2: as tars, man 3 printf and man 1 ssh read offline, shellcheck and ctags work, fish and /etc/bash.bashrc put ~/.local/bin first and ~/.cargo/bin, ~/go/bin, ~/.bun/bin on PATH"

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

# TP-M5(plan 결정 F): kotlin · clojure는 망 없이, util의 둘, man clojure. 기다리는 글자는 계산된 값(42 · 판)이라 명령 줄에
# 그대로 없다 — 콘솔이 되비춘 명령에 맞지 않는다(TP-M4 plan 확인한 것 9).
as_tars 'cd ~/tp && printf "%s\n" "fun main() { println(\"tp-m5-kt=\" + (40 + 2) + \"-\" + KotlinVersion.CURRENT) }" > h.kt && s=$(date +%s%N) && kotlinc h.kt -include-runtime -d hk.jar 2>&1 | sed "s/^/tp-m5-kotlinc: /"; e=$(date +%s%N); echo "tp-ms-kotlinc=$(((e-s)/1000000))"; java -jar hk.jar 2>&1 | sed "s/^/tp-m5-ktrun: /"'
wait_log_re "tp-ms-kotlinc=[0-9]+" 180 || fail "kotlinc did not finish in 180s" "tp-m5-kotlinc"
wait_log "tp-m5-ktrun: tp-m5-kt=42-2.4.21" 60 || fail "the jar kotlinc built did not print 42 and the Kotlin version" "tp-m5-kotlinc" "tp-m5-ktrun"
echo "B2: as tars, kotlinc built a jar with the runtime and java ran it, offline ($(ms_of kotlinc)ms)"

# clojure의 첫 실행은 ~/.m2를 묶음의 시드로 채운다(plan 결정 D) — 그 전에 비어 있고, 뒤에 일곱 파일이 있다.
as_tars 'cd ~/tp && find ~/.m2 -type f 2>/dev/null | wc -l | sed "s/^/tp-m5-m2before=/"; s=$(date +%s%N); clojure -M -e "(require (quote clojure.spec.alpha)) (println (str \"tp-m5-clj=\" (+ 40 2) \"-\" (clojure-version)))" 2>&1 | sed "s/^/tp-m5-cljrun: /"; e=$(date +%s%N); echo "tp-ms-clojure=$(((e-s)/1000000))"; find ~/.m2 -type f | wc -l | sed "s/^/tp-m5-m2after=/"; echo "(+ 40 2)" | clj 2>&1 | sed "s/^/tp-m5-clj-repl: /"'
wait_log_re "tp-ms-clojure=[0-9]+" 100 || fail "clojure did not finish in 100s" "tp-m5-cljrun"
grep -aqF "tp-m5-m2before=0" "$LOG" || fail "the home's .m2 was not empty before the first clojure run" "tp-m5-m2before"
grep -aqF "tp-m5-cljrun: tp-m5-clj=42-1.12.6" "$LOG" || fail "clojure -M -e did not run offline (the seed in bin/clojure fills ~/.m2)" "tp-m5-cljrun" "UnknownHost"
wait_log "tp-m5-m2after=7" 30 || fail "the first clojure run did not leave the seven seeded files in ~/.m2" "tp-m5-m2after"
wait_log "tp-m5-clj-repl: user=> 42" 120 || fail "clj (through rlwrap) did not answer (+ 40 2)" "tp-m5-clj-repl"
echo "B2: as tars, clojure ran offline from the seeded ~/.m2 ($(ms_of clojure)ms) and clj answered through rlwrap"

as_tars 'cci --version 2>&1 | sed "s/^/tp-m5-cci: /"; glc --version 2>&1 | sed "s/^/tp-m5-glc: /"; MANPAGER=cat man clojure 2>&1 | grep -m1 "runners to launch" | sed "s/^ */tp-m5-man=/"'
wait_log "tp-m5-man=clj, clojure" 60 || fail "man clojure did not show the page (/usr/local/share/man)" "tp-m5-man"
grep -aqF "tp-m5-cci: cci 0.6.2" "$LOG" || fail "cci --version did not say 0.6.2" "tp-m5-cci"
grep -aqF "tp-m5-glc: glc 0.19.3" "$LOG" || fail "glc --version did not say 0.19.3" "tp-m5-glc"
echo "B2: as tars, util's cci and glc run and man clojure reads offline"
M5_NUMBERS="kotlinc $(ms_of kotlinc)ms, clojure $(ms_of clojure)ms"

# TP-M6(plan 결정 G): BEAM 셋. 작업 자리는 ~/tp/m6(앞 덩이의 h.* 파일과 섞이지 않게). 기다리는 글자는 계산된 값이다.
as_tars 'mkdir -p ~/tp/m6 && cd ~/tp/m6 && s=$(date +%s%N) && erl -noshell -eval "io:format(\"tp-m6-otp=~s-~s-~p~n\", [erlang:system_info(otp_release), erlang:system_info(emu_flavor), byte_size(crypto:hash(sha256, <<\"tp\">>))]), halt()." 2>&1 | sed "s/^/tp-m6-erl: /"; e=$(date +%s%N); echo "tp-ms-erl=$(((e-s)/1000000))"; printf "%s\n" "-module(h)." "-export([main/0])." "main() -> io:format(\"tp-m6-erlc=~p~n\", [lists:sum([40, 2])])." > h.erl && erlc h.erl 2>&1 | sed "s/^/tp-m6-erlc: /"; erl -noshell -s h main -s init stop; printf "%s\n" "#!/usr/bin/env escript" "main(_) -> io:format(\"tp-m6-escript=~p~n\", [ssl:start()])." > h.escript && escript h.escript'
wait_log_re "tp-ms-erl=[0-9]+" 60 || fail "erl did not finish in 60s" "tp-m6-erl"
grep -aqF "tp-m6-erl: tp-m6-otp=29-jit-32" "$LOG" || fail "erl did not run OTP 29 with the JIT and crypto" "tp-m6-erl"
wait_log "tp-m6-erlc=42" 60 || fail "erlc did not compile a module that runs" "tp-m6-erlc"
wait_log "tp-m6-escript=ok" 60 || fail "escript did not start ssl" "tp-m6-escript"
echo "B2: as tars, erl ran OTP 29 with the JIT and crypto ($(ms_of erl)ms), erlc built a module and escript started ssl"

as_tars 'cd ~/tp/m6 && s=$(date +%s%N) && elixir -e "IO.puts(\"tp-m6-ex=#{System.version()}-#{Enum.sum([40, 2])}\")" 2>&1 | sed "s/^/tp-m6-elixir: /"; e=$(date +%s%N); echo "tp-ms-elixir=$(((e-s)/1000000))"; echo "40 + 2" | iex 2>&1 | sed "s/^/tp-m6-iex: /"'
wait_log_re "tp-ms-elixir=[0-9]+" 60 || fail "elixir did not finish in 60s" "tp-m6-elixir"
grep -aqF "tp-m6-elixir: tp-m6-ex=1.20.5-42" "$LOG" || fail "elixir -e did not print 1.20.5 and 42" "tp-m6-elixir"
wait_log "tp-m6-iex: iex(1)> 42" 60 || fail "iex did not answer 40 + 2" "tp-m6-iex"
grep -aq "latin1" "$LOG" && fail "elixir warned about latin1 — LANG=C.UTF-8 did not reach it" "latin1"
echo "B2: as tars, elixir -e ($(ms_of elixir)ms) and iex ran without the latin1 warning"

# mix test 세 번(plan 위험 1): OrbStack의 qemu-user에서는 새 프로젝트의 첫 판이 JIT의 Illegal instruction으로 죽었다(확인한 것 4).
as_tars 'cd ~/tp/m6 && mix new tpx > /dev/null 2>&1; cd tpx && for i in 1 2 3; do s=$(date +%s%N); mix test 2>&1 | grep -E "passed|failure|Illegal|signal|rror" | sed "s/^/tp-m6-mix$i: /"; e=$(date +%s%N); echo "tp-ms-mix$i=$(((e-s)/1000000))"; done'
wait_log_re "tp-ms-mix3=[0-9]+" 90 || fail "mix new and three mix test runs did not finish in 90s" "tp-m6-mix"
for i in 1 2 3; do
  grep -aqF "tp-m6-mix${i}: Result: 2 passed" "$LOG" || fail "mix test run ${i} did not pass (plan risk 1: the BEAM JIT)" "tp-m6-mix" "Illegal" "invalid opcode"
done
grep -aqE "Illegal instruction|invalid opcode" "$LOG" && fail "something hit an illegal instruction (plan risk 1)" "Illegal" "invalid opcode"
echo "B2: as tars, mix new and mix test three times passed ($(ms_of mix1)ms with the first compile, then $(ms_of mix2)ms and $(ms_of mix3)ms)"

as_tars 'cd ~/tp/m6 && find ~/.cache/gleam -name "*.tar" 2>/dev/null | wc -l | sed "s/^/tp-m6-gcache0=/"; gleam new tpg > /dev/null 2>&1; cd tpg && test -f manifest.toml && printf "tp-m6-%s\n" manifest-ok; s=$(date +%s%N); gleam run 2>&1 | tail -1 | sed "s/^/tp-m6-grun: /"; e=$(date +%s%N); echo "tp-ms-gleam=$(((e-s)/1000000))"; gleam test 2>&1 | tail -1 | sed "s/^/tp-m6-gtest: /"; find ~/.cache/gleam -name "*.tar" | wc -l | sed "s/^/tp-m6-gcache1=/"'
wait_log_re "tp-m6-gcache1=[0-9]+" 90 || fail "gleam new, run and test did not finish in 90s" "tp-m6-grun" "tp-m6-gtest"
grep -aqF "tp-m6-gcache0=0" "$LOG" || fail "the gleam cache was not empty before the first gleam run" "tp-m6-gcache0"
grep -aqF "tp-m6-manifest-ok" "$LOG" || fail "the gleam launcher did not put manifest.toml into the new project" "tp-m6"
grep -aqF "tp-m6-grun: Hello from tpg!" "$LOG" || fail "gleam run did not run offline (seed and manifest.toml)" "tp-m6-grun" "repo.hex.pm"
grep -aqF "tp-m6-gtest: 1 passed, no failures" "$LOG" || fail "gleam test did not pass offline" "tp-m6-gtest"
grep -aqF "tp-m6-gcache1=2" "$LOG" || fail "the gleam launcher did not seed the two tarballs into the cache" "tp-m6-gcache1"
echo "B2: as tars, gleam new got manifest.toml, gleam run ($(ms_of gleam)ms) and gleam test passed offline from the seeded cache"

as_tars 'MANPAGER=cat erl -man lists 2>&1 | grep -m1 "List processing" | sed "s/^ */tp-m6-erlman=/"; MANPAGER=cat man mix 2>&1 | grep -m1 "project management" | sed "s/^ */tp-m6-mixman=/"'
wait_log "tp-m6-mixman=mix" 60 || fail "man mix did not show the page (man1=man)" "tp-m6-mixman"
grep -aqF "tp-m6-erlman=lists - List processing" "$LOG" || fail "erl -man lists did not read <ROOT>/man" "tp-m6-erlman"
echo "B2: as tars, erl -man lists and man mix read offline"
M6_NUMBERS="erl $(ms_of erl)ms, elixir $(ms_of elixir)ms, mix test $(ms_of mix1)/$(ms_of mix2)/$(ms_of mix3)ms, gleam run $(ms_of gleam)ms"

# TP-M7(plan 결정 F): 편집기 셋(LD-M0이 emacs를 뺐다). 상한은 60초 — 첫 판(SandyBridge · 1GiB): ms 0.2초, nvim 0.7초, ttt 0.8초. 작업 자리는 ~/tp/m7. 기다리는 글자는 계산된 값이다 — 명령 줄의 표시는 sed 접두나 format의 %s로 쪼갠다.
# ms: --health c의 parser · 쿼리 줄 가운데 초록(32m)인 수. ✓ 같은 비ASCII 글자는 콘솔로 보내지 않는다. runtime/이 없으면 0이다(plan 할 일 6(b)).
as_tars 'mkdir -p ~/tp/m7 && cd ~/tp/m7 && s=$(date +%s%N) && ms --version 2>&1 | sed "s/^/tp-m7-ms: /"; e=$(date +%s%N); echo "tp-ms-ms=$(((e-s)/1000000))"; ms --health c 2>&1 | grep -E "(parser|queries):" | grep -c 32m | sed "s/^/tp-m7-msok=/"; ls /usr/local/lib/mitos-0.1.3/runtime/grammars | wc -l | sed "s/^/tp-m7-msgram=/"'
wait_log_re "tp-ms-ms=[0-9]+" 60 || fail "ms --version did not finish in 60s" "tp-m7-ms"
grep -aqF "tp-m7-ms: mitos 0.1.3" "$LOG" || fail "ms --version did not print mitos 0.1.3" "tp-m7-ms"
wait_log "tp-m7-msok=7" 60 || fail "ms --health c did not find the C parser and its six queries in runtime/" "tp-m7-msok"
wait_log "tp-m7-msgram=301" 30 || fail "mitos runtime/grammars does not have 301 grammars" "tp-m7-msgram"
echo "B2: as tars, ms ran ($(ms_of ms)ms) and found its runtime beside the real file (C parser and six queries, 301 grammars)"

# nvim: C 파일에서 treesitter를 켜고 3번 줄을 고쳐 저장한다. Lua 문자열은 [[…]] — as_tars 안에 작은따옴표를 둘 수 없다.
# nvim의 written 메시지가 줄바꿈 없이 앞에 붙으므로 표시 앞에도 줄바꿈을 둔다.
as_tars 'cd ~/tp/m7 && printf "%s\n" "int main(void)" "{" "  return 0;" "}" > h7.c && s=$(date +%s%N) && nvim --headless h7.c -c "lua vim.treesitter.start(); local t = vim.treesitter.get_parser():parse()[1]:root():type(); vim.fn.setline(3, [[  return 42;]]); vim.cmd.write(); io.stdout:write(string.char(10), string.format([[tp-m7-%s=%s]], [[nvts]], t), string.char(10))" -c "qa!" 2>&1; e=$(date +%s%N); echo "tp-ms-nvim=$(((e-s)/1000000))"; grep -c "return 42" h7.c | sed "s/^/tp-m7-nvsaved=/"'
wait_log_re "tp-ms-nvim=[0-9]+" 60 || fail "nvim --headless did not finish in 60s" "tp-m7-nvts"
grep -aqF "tp-m7-nvts=translation_unit" "$LOG" || fail "nvim did not parse C with its bundled treesitter parser" "tp-m7-nvts"
wait_log "tp-m7-nvsaved=1" 30 || fail "nvim did not write the changed line" "tp-m7-nvsaved"
echo "B2: as tars, nvim parsed C with treesitter and wrote a changed line ($(ms_of nvim)ms)"

# LD-M0(LD design 결정 4): emacs-nox를 뺐다 — 명령이 없어야 한다. 표시 글자는 계산된 값이다(명령 줄의 되비침에 안 맞게).
as_tars 'command -v emacs | wc -l | sed "s/^/tp-m7-no%s=/;s/%s/emacs/"'
wait_log "tp-m7-noemacs=0" 60 || fail "emacs is still on the PATH (LD-M0 took emacs-nox out of editor)" "tp-m7-noemacs"
echo "B2: as tars, emacs is gone from editor"

# ttt: --exec(내장 시험 장치)로 Go 파일을 열어 글자가 뜨기를 기다리고 화면 글자를 남긴다. TUI는 SIGTERM으로 안 끝났다(plan 확인 5) — --exec만 쓴다.
as_tars 'cd ~/tp/m7 && printf "%s\n" "package main" "" "func main() {}" > h7.go && s=$(date +%s%N) && ttt --size 100x30 --exec "wait-for \"func main\" timeout=60000; screenshot $HOME/tp/m7/shot.txt; quit" h7.go < /dev/null 2>&1 | sed "s/^/tp-m7-ttt: /"; e=$(date +%s%N); echo "tp-ms-ttt=$(((e-s)/1000000))"; grep -c "1  package main" shot.txt | sed "s/^/tp-m7-tttshot=/"'
wait_log_re "tp-ms-ttt=[0-9]+" 60 || fail "ttt --exec did not finish in 60s" "tp-m7-ttt"
wait_log "tp-m7-tttshot=1" 30 || fail "ttt did not draw the Go file on its screen" "tp-m7-ttt" "tp-m7-tttshot"
echo "B2: as tars, ttt opened a Go file and drew it ($(ms_of ttt)ms)"

as_tars 'MANPAGER=cat man nvim 2>&1 | sed -n "/^NAME/{n;p;q}" | sed "s/^ */tp-m7-nvman=/"; command -v ctags | sed "s/^/tp-m7-ctags=/"'
wait_log "tp-m7-ctags=/usr/local/bin/ctags" 60 || fail "ctags is not base's universal-ctags (emacs-nox's alternative leaked)" "tp-m7-ctags"
grep -aqF "tp-m7-nvman=nvim" "$LOG" || fail "man nvim did not show the page (man1=share/man/man1)" "tp-m7-nvman"
echo "B2: as tars, man nvim read offline, and ctags is still universal-ctags"
M7_NUMBERS="ms $(ms_of ms)ms, nvim $(ms_of nvim)ms, ttt $(ms_of ttt)ms"

# TP-M8(plan 결정 F): util · media의 터미널 유틸리티. 상한은 60초 — 첫 판(SandyBridge · 1GiB): --version 60개 16.5초, 도구 2.9초,
# ffmpeg 5.4초, magick · gm 0.4초(세 배가 60초 아래). 작업 자리는 ~/tp/m8. 기다리는 글자는 chroot에서 잰 계산된 값이다(plan 확인한 것).
# F-1: 링크된 실행 파일 61개가(TP-M10 덧붙임의 mkcert 포함) 이름으로 서고 판 옵션이 0으로 끝나는 수. 판 옵션이 다른 다섯 — hugo는 하위 명령, ffmpeg · ffprobe는
# -version(--version은 판을 찍고도 0이 아니다), sqldiff는 --help뿐, flashfetch는 옵션 없이 돈다. 0이 아닌 것은 tp-m8-bad에 이름이 남는다.
# 목록은 매니페스트에서 계산하지 않는다 — 도구를 더하거나 빼면 여기도 고친다(plan 맡아 정한 것 5). rg는 initrd의 trixie 판을 이긴다(design 결정 20).
as_tars 'mkdir -p ~/tp/m8 && cd ~/tp/m8 && s=$(date +%s%N) && n=0 && bad="" && for t in cci glc bat duf eza fd fzf hyperfine jq rg sd asciinema ast-grep bed cidr difft dua dust fastfetch gitui glow task gping herdr hexyl hurl hurlfmt lazygit lazysql leaf mlr peco procs scc starship tspin tree-sitter uv uvx viddy wasmtime xh yazi ya sqlite3 sqlite3_analyzer sqlite3_rsync duckdb mkcert wget ipcalc vifm magick convert identify gm; do if $t --version >/dev/null 2>&1 </dev/null; then n=$((n+1)); else bad="$bad $t"; fi; done; hugo version >/dev/null 2>&1 && n=$((n+1)) || bad="$bad hugo"; for t in ffmpeg ffprobe; do $t -version >/dev/null 2>&1 && n=$((n+1)) || bad="$bad $t"; done; sqldiff --help >/dev/null 2>&1 && n=$((n+1)) || bad="$bad sqldiff"; timeout 60 flashfetch >/dev/null 2>&1 </dev/null && n=$((n+1)) || bad="$bad flashfetch"; e=$(date +%s%N); echo "tp-ms-m8ver=$(((e-s)/1000000))"; printf "tp-m8-%s=%s\n" ver $n; echo "tp-m8-bad:$bad"; command -v rg | sed "s/^/tp-m8-rgpath=/"; rg --version | head -1 | sed "s/^/tp-m8-rg=/"'
wait_log_re "tp-ms-m8ver=[0-9]+" 60 || fail "the util and media --version loop did not finish in 60s" "tp-m8-bad"
wait_log "tp-m8-ver=61" 10 || fail "not all 61 util and media commands ran by name" "tp-m8-bad" "tp-m8-ver"
wait_log "tp-m8-rgpath=/usr/local/bin/rg" 10 || fail "rg by name is not util's (/usr/local/bin before /usr/bin)" "tp-m8-rgpath"
wait_log "tp-m8-rg=ripgrep 15.2.0" 10 || fail "rg is not util's 15.2.0" "tp-m8-rg"
echo "B2: as tars, all 61 util and media commands run by name offline and util's rg wins over the initrd one"
# LD-M0(LD design 결정 5): 기본 판도 fakesteak 묶음을 싣는다 — 칠 수 있고, 첫 패널 자동 실행은 base가 얹힌 판에서 안 돈다(표시 파일이 안 생긴다).
as_tars 'command -v fakesteak | sed "s/^/tp-ld-fake%s=/;s/%s/path/"; test -e /tmp/.tars-autorun; echo "tp-ld-auto%s=$?" | sed "s/%s/run/"'
wait_log "tp-ld-fakepath=/usr/local/bin/fakesteak" 30 || fail "fakesteak is not on the PATH (the fakesteak bundle)" "tp-ld-fake"
wait_log "tp-ld-autorun=1" 10 || fail "the fakesteak autorun marker exists — the demo's rc piece ran with base mounted" "tp-ld-auto"
echo "B2: as tars, fakesteak is on the PATH and did not start by itself with base mounted"
# F-2: 일하는 도구. duckdb의 SQL은 printf의 \x27로 작은따옴표를 만든다(as_tars는 작은따옴표를 못 담는다). hurl의 libcurl은 initrd의 것이다.
as_tars 'cd ~/tp/m8 && s=$(date +%s%N) && printf "{\"a\":[1,2,3]}" | jq ".a|add" | sed "s/^/tp-m8-jq=/"; sqlite3 :memory: "select 6*7" | sed "s/^/tp-m8-sqlite=/"; printf "a,b\n1,x\n2,y\n" | mlr --icsv --ojsonl cat | head -1 | sed "s/^/tp-m8-mlr=/"; printf "fn main() {\n    let x = 1;\n}\n" > a.rs; printf "fn main() {\n    let x = 2;\n}\n" > b.rs; difft --color never --display inline a.rs b.rs | grep -c "x = " | sed "s/^/tp-m8-difft=/"; ast-grep run -p "let \$A = \$B" --lang rust a.rs --json=compact | jq -r ".[0].metaVariables.single.B.text" | sed "s/^/tp-m8-sg=/"; hyperfine -N -r 2 --style none --export-json h.json true >/dev/null 2>&1; jq ".results|length" h.json | sed "s/^/tp-m8-hf=/"; hurl --version | grep -o "libcurl/[0-9.]*" | sed "s/^/tp-m8-hurl=/"; printf "a,b\n1,x\n2,y\n3,z\n" > t.csv; printf "copy (select * from read_csv(\x27t.csv\x27)) to \x27t.parquet\x27;\ncopy (select * from \x27t.parquet\x27) to \x27t.json\x27;\nselect sum(a) from read_json(\x27t.json\x27);\n" > d.sql; duckdb -noheader -list < d.sql | sed "s/^/tp-m8-duck=/"; e=$(date +%s%N); echo "tp-ms-m8work=$(((e-s)/1000000))"'
wait_log_re "tp-ms-m8work=[0-9]+" 60 || fail "the util tool block did not finish in 60s" "tp-m8-"
wait_log "tp-m8-jq=6" 10 || fail "jq did not add 1, 2 and 3" "tp-m8-jq"
wait_log "tp-m8-sqlite=42" 10 || fail "sqlite3 did not compute 6*7" "tp-m8-sqlite"
wait_log 'tp-m8-mlr={"a": 1, "b": "x"}' 10 || fail "mlr did not turn the CSV into JSON" "tp-m8-mlr"
wait_log "tp-m8-difft=2" 10 || fail "difftastic did not show the changed line on both sides" "tp-m8-difft"
wait_log "tp-m8-sg=1" 10 || fail "ast-grep did not match let \$A = \$B in Rust" "tp-m8-sg"
wait_log "tp-m8-hf=1" 10 || fail "hyperfine did not export one result" "tp-m8-hf"
wait_log "tp-m8-hurl=libcurl/8.14.1" 10 || fail "hurl is not linked to the initrd's libcurl (libxml2 from util)" "tp-m8-hurl"
wait_log "tp-m8-duck=6" 10 || fail "duckdb did not round-trip CSV, Parquet and JSON" "tp-m8-duck"
echo "B2: as tars, jq, sqlite3, mlr, difft, ast-grep, hyperfine, hurl and duckdb work offline"
# F-3: media. ffmpeg가 libav*를 RUNPATH로 먼저 올린다 — needed-ignore.tsv의 exe-loaded가 기대는 길이다.
as_tars 'cd ~/tp/m8 && s=$(date +%s%N) && ffmpeg -hide_banner -loglevel error -y -f lavfi -i testsrc2=size=320x240:rate=25:duration=3 -c:v libx264 -pix_fmt yuv420p v.mp4 && ffprobe -v error -show_entries format=duration -of csv=p=0 v.mp4 | sed "s/^/tp-m8-ff=/"; e=$(date +%s%N); echo "tp-ms-ff=$(((e-s)/1000000))"; s=$(date +%s%N); magick -size 64x48 gradient:red-blue g.png && magick g.png -quality 80 g.jpg && magick identify -format "%wx%h %m\n" g.jpg | sed "s/^/tp-m8-im=/"; gm identify -format "%wx%h %m" g.jpg | sed "s/^/tp-m8-gm=/"; e=$(date +%s%N); echo "tp-ms-img=$(((e-s)/1000000))"'
wait_log_re "tp-ms-img=[0-9]+" 60 || fail "the media block did not finish in 60s" "tp-m8-"
wait_log "tp-m8-ff=3.000000" 10 || fail "ffmpeg did not make a 3-second H.264 file that ffprobe reads" "tp-m8-ff"
wait_log "tp-m8-im=64x48 JPEG" 10 || fail "ImageMagick did not make and read a JPEG" "tp-m8-im"
wait_log "tp-m8-gm=64x48 JPEG" 10 || fail "GraphicsMagick did not read the JPEG" "tp-m8-gm"
echo "B2: as tars, ffmpeg, ffprobe, magick and gm work offline"
# F-4: man. rg는 *.1, hurl · glow는 *.1.gz(plan 결정 D).
as_tars 'MANPAGER=cat man rg 2>&1 | grep -m1 -oE "rg +- recursively search" | sed "s/^/tp-m8-manrg=/"; MANPAGER=cat man hurl 2>&1 | grep -m1 -E "^ +hurl - " | sed "s/^ */tp-m8-manhurl=/"; MANPAGER=cat man glow 2>&1 | grep -m1 -E "^ +glow - " | sed "s/^ */tp-m8-manglow=/"'
wait_log "tp-m8-manglow=glow - Render markdown" 60 || fail "man glow did not show the page (man1= with .1.gz)" "tp-m8-man"
grep -aqF "tp-m8-manrg=rg  - recursively search" "$LOG" || fail "man rg did not show the page" "tp-m8-manrg"
grep -aqF "tp-m8-manhurl=hurl - run and test HTTP requests." "$LOG" || fail "man hurl did not show the page" "tp-m8-manhurl"
echo "B2: as tars, man rg, man hurl and man glow read offline"
M8_NUMBERS="61 --version $(ms_of m8ver)ms, tools $(ms_of m8work)ms, ffmpeg $(ms_of ff)ms, magick+gm $(ms_of img)ms"

# TP-M9(plan 할 일 6): docs. 비대화형 bash는 rc를 안 읽으므로 /etc/bash.bashrc를 직접 source한다 — 맨 앞의 rc.d 조각(결정 B)이 홈의 dasht
# docset 자리에 묶음의 Bash docset 링크를 둔다. 찾기(sqlite3 — util) → 결과의 file:// URL → w3m -dump(w3m은 initrd에 없다 — 스크립트의 의존이라
# verify의 NEEDED가 못 잡는다, 빨강 (b)). 그 뒤 링크를 지우고 fish의 conf.d 조각이 다시 두는지. 상한 60초 — 첫 판(SandyBridge · 1GiB)은 1,175ms.
as_tars 'mkdir -p ~/tp/m9 && cd ~/tp/m9 && s=$(date +%s%N) && . /etc/bash.bashrc >/dev/null 2>&1; dasht-docsets | sed "s/^/tp-m9-docsets=/"; readlink ~/.local/share/dasht/docsets/Bash.docset | sed "s/^/tp-m9-link=/"; dasht-query-line printf Bash > q.txt; sed -n "s/^name = /tp-m9-name=/p" q.txt | head -1; u=$(sed -n "s/^url = //p" q.txt | head -1); w3m -dump "$u" 2>&1 | grep -m1 -oE "Bash Builtin Commands" | sed "s/^/tp-m9-w3m=/"; MANPAGER=cat man dasht 2>&1 | grep -m1 -E "^ +dasht - " | sed "s/^ */tp-m9-man=/"; rm ~/.local/share/dasht/docsets/Bash.docset; fish -c "dasht-docsets" | sed "s/^/tp-m9-fish=/"; tars-docs | grep -cE "^ +[*] Bash " | sed "s/^/tp-m9-list=/"; tars-docs get -y Lua > g.log 2>&1; echo "tp-m9-get-rc=$?"; grep -c "failed: Lua" g.log | sed "s/^/tp-m9-getfail=/"; ls ~/.local/share/dasht/docsets | tr "\n" " " | sed "s/^/tp-m9-left=/"; echo; e=$(date +%s%N); echo "tp-ms-m9=$(((e-s)/1000000))"'
wait_log_re "tp-ms-m9=[0-9]+" 60 || fail "the docs block did not finish in 60s" "tp-m9-"
wait_log "tp-m9-link=/usr/local/lib/dasht-2.4.0/Bash.docset" 10 || fail "the rc piece did not link the bundle's Bash docset into the home docset directory" "tp-m9-"
grep -aqF "tp-m9-docsets=Bash" "$LOG" || fail "dasht-docsets does not list Bash" "tp-m9-"
grep -aqF "tp-m9-name=printf" "$LOG" || fail "dasht-query-line did not find printf in the Bash docset" "tp-m9-"
grep -aqF "tp-m9-w3m=Bash Builtin Commands" "$LOG" || fail "w3m -dump did not read the page dasht found" "tp-m9-"
grep -aqF "tp-m9-man=dasht - API documentation in your terminal" "$LOG" || fail "man dasht did not show the page" "tp-m9-"
grep -aqF "tp-m9-fish=Bash" "$LOG" || fail "fish's conf.d piece did not put the Bash docset link back" "tp-m9-"
# tars-docs(plan 결정 E): 목록이 묶음의 Bash를 받은 것(*)으로 보이고, 망이 없으면 받기가 이름을 대고 rc 1로 끝나며 아무것도 남기지 않는다.
grep -aqF "tp-m9-list=1" "$LOG" || fail "tars-docs does not list Bash as already here" "tp-m9-"
grep -aqF "tp-m9-get-rc=1" "$LOG" || fail "tars-docs get without a network did not end with rc 1" "tp-m9-"
grep -aqF "tp-m9-getfail=1" "$LOG" || fail "tars-docs get without a network did not name the docset it failed on" "tp-m9-"
grep -aqF "tp-m9-left=Bash.docset " "$LOG" || fail "tars-docs get without a network left something in the docset directory" "tp-m9-"
echo "B2: as tars, the rc pieces link the Bash docset, dasht finds printf, w3m reads the page, man dasht reads offline and tars-docs lists Bash and fails cleanly without a network"
M9_NUMBERS="docs $(ms_of m9)ms"

# TP-M10(plan 할 일 7): server. 다섯을 사용자로 하나씩 띄우고 응답을 받고 끈다 — 데이터는 모두 ~/tp/m10 아래(재부팅을 넘는 장치는 서비스
# milestone). rc 조각(결정 E)이 PGHOST=/tmp를, conf.d/tars.cnf가 mysql의 소켓 · secure-file-priv를 잡는다(빨강 (a)). mysqld · nginx · initdb 등은
# /usr/local/bin의 링크로 이름이 닿는다(결정 C, 빨강 (b) — /usr/sbin은 PATH에 없다). 기다리는 글자는 서버가 계산하거나 돌려준 값이다(판 · 42 ·
# PONG) — 명령 줄에 그대로 쓰지 않는다. nginx는 tars-help devtools의 모양 그대로(상대 경로 + -p). 상한 120초 — 첫 판(SandyBridge · 1GiB): postgres 6.6초, mysql 26.5초(초기화 포함), 나머지 3.8초.
as_tars 'mkdir -p ~/tp/m10 && cd ~/tp/m10 && . /etc/bash.bashrc >/dev/null 2>&1; echo "tp-m10-pghost=$PGHOST"; for c in initdb psql mysqld mysqladmin nginx redis-server caddy; do command -v $c; done | tr "\n" " " | sed "s/^/tp-m10-which=/"; echo; s=$(date +%s%N) && initdb -D ~/tp/m10/pg -A trust > pg-init.log 2>&1 && pg_ctl -D ~/tp/m10/pg -o "-k /tmp" -l pg.log -w start > /dev/null && psql -d postgres -Atc "show server_version" | sed "s/^/tp-m10-pg=/"; psql -d postgres -Atc "select 40+2" | sed "s/^/tp-m10-pgsel=/"; pg_ctl -D ~/tp/m10/pg -w stop > /dev/null; e=$(date +%s%N); echo "tp-ms-m10pg=$(((e-s)/1000000))"; s=$(date +%s%N) && mysqld --initialize-insecure --datadir=$HOME/tp/m10/my > my-init.log 2>&1; mysqld --datadir=$HOME/tp/m10/my > my.log 2>&1 & p=$!; for i in $(seq 240); do mysqladmin -uroot ping > /dev/null 2>&1 && break; sleep 0.5; done; mysql -uroot -N -e "select version()" | sed "s/^/tp-m10-my=/"; mysql -uroot -N -e "select 40+2" | sed "s/^/tp-m10-mysel=/"; mysqladmin -uroot shutdown; wait $p; echo "tp-m10-myrc=$?"; e=$(date +%s%N); echo "tp-ms-m10my=$(((e-s)/1000000))"; s=$(date +%s%N) && mkdir -p ng/logs ng/tmp && printf "%s\n" "pid nginx.pid;" "error_log logs/error.log;" "events {}" "http {" "  access_log logs/access.log;" "  client_body_temp_path tmp; proxy_temp_path tmp; fastcgi_temp_path tmp; uwsgi_temp_path tmp; scgi_temp_path tmp;" "  server { listen 8080; location / { return 200 \$nginx_version; } }" "}" > ng/nginx.conf && nginx -p $HOME/tp/m10/ng -e logs/error.log -c nginx.conf && curl -s 127.0.0.1:8080 | sed "s/^/tp-m10-ng=/"; echo; nginx -p $HOME/tp/m10/ng -e logs/error.log -c nginx.conf -s stop; redis-server --port 6379 --dir $HOME/tp/m10 --daemonize yes > /dev/null && for i in $(seq 40); do redis-cli ping > rd.txt 2>/dev/null && break; sleep 0.25; done; sed "s/^/tp-m10-rd=/" rd.txt; redis-cli info server | sed -n "s/^redis_version:/tp-m10-rdver=/p" | tr -d "\r"; redis-cli shutdown nosave; caddy respond --listen 127.0.0.1:8081 --body "caddy-$((6*7))" > caddy.log 2>&1 & c=$!; for i in $(seq 120); do curl -s 127.0.0.1:8081 > cd.txt 2>/dev/null && break; sleep 0.25; done; sed "s/^/tp-m10-cd=/" cd.txt; echo; kill $c; wait $c; for m in postgres mysqld nginx redis-server; do MANPAGER=cat man $m 2>/dev/null | grep -m1 -oE "^ +$m " | tr -d " "; done | tr "\n" " " | sed "s/^/tp-m10-man=/"; echo; e=$(date +%s%N); echo "tp-ms-m10rest=$(((e-s)/1000000))"'
wait_log_re "tp-ms-m10rest=[0-9]+" 120 || fail "the server block did not finish in 120s" "tp-m10-" "tp-ms-m10"
grep -aqF "tp-m10-pghost=/tmp" "$LOG" || fail "the rc piece did not set PGHOST=/tmp" "tp-m10-"
grep -aqF "tp-m10-which=/usr/local/bin/initdb /usr/local/bin/psql /usr/local/bin/mysqld /usr/bin/mysqladmin /usr/local/bin/nginx /usr/bin/redis-server /usr/local/bin/caddy " "$LOG" \
  || fail "a server command is not where the bundle puts it (psql must be 18's, mysqld and nginx through /usr/local/bin)" "tp-m10-which"
grep -aqF "tp-m10-pg=18.6" "$LOG" || fail "postgres 18.6 did not answer on the /tmp socket" "tp-m10-pg" "tp-ms-m10pg"
grep -aqF "tp-m10-pgsel=42" "$LOG" || fail "postgres did not compute 40+2" "tp-m10-pg"
grep -aqF "tp-m10-my=9.7.4" "$LOG" || fail "mysqld 9.7.4 did not answer (conf.d/tars.cnf: socket, secure-file-priv)" "tp-m10-my" "tp-ms-m10my"
grep -aqF "tp-m10-mysel=42" "$LOG" || fail "mysql did not compute 40+2" "tp-m10-my"
grep -aqF "tp-m10-myrc=0" "$LOG" || fail "mysqld did not shut down cleanly on mysqladmin shutdown" "tp-m10-my"
grep -aqF "tp-m10-ng=1.30.6" "$LOG" || fail "nginx 1.30.6 did not answer as the user on 8080" "tp-m10-ng"
grep -aqF "tp-m10-rd=PONG" "$LOG" || fail "redis did not answer ping" "tp-m10-rd"
grep -aqF "tp-m10-rdver=8.10.3" "$LOG" || fail "redis is not 8.10.3" "tp-m10-rd"
grep -aqF "tp-m10-cd=caddy-42" "$LOG" || fail "caddy respond did not answer" "tp-m10-cd"
grep -aqF "tp-m10-man=postgres mysqld nginx redis-server " "$LOG" || fail "a server man page did not read offline" "tp-m10-man"
echo "B2: as tars, postgres 18.6, mysql 9.7.4, nginx 1.30.6, redis 8.10.3 and caddy each start from the home, answer and stop offline, and their man pages read"
M10_NUMBERS="postgres $(ms_of m10pg)ms, mysql $(ms_of m10my)ms, nginx+redis+caddy+man $(ms_of m10rest)ms"
# TP-M10 덧붙임(사용자 요청 2026-11-08): mkcert가 망 없이 홈에 로컬 CA를 세우고 localhost 인증서를 발급한다. server의 openssl이 그 인증서를
# CA로 검증한다(OK는 openssl이 찍는다 — 명령 줄에 없다). 이름(SAN)에 127.0.0.1이 들었는지도 본다. 상한 60초.
as_tars 'mkdir -p ~/tp/m10/tls && cd ~/tp/m10/tls && s=$(date +%s%N) && mkcert localhost 127.0.0.1 > mk.log 2>&1; mkcert -CAROOT | sed "s/^/tp-m10-caroot=/"; openssl verify -CAfile "$(mkcert -CAROOT)/rootCA.pem" localhost+1.pem 2>&1 | sed "s/^/tp-m10-verify=/"; openssl x509 -in localhost+1.pem -noout -ext subjectAltName 2>&1 | grep -oE "IP Address:[0-9.]+" | sed "s/^/tp-m10-san=/"; e=$(date +%s%N); echo "tp-ms-m10tls=$(((e-s)/1000000))"'
wait_log_re "tp-ms-m10tls=[0-9]+" 60 || fail "the mkcert block did not finish in 60s" "tp-m10-"
grep -aqF "tp-m10-caroot=/home/tars/.local/share/mkcert" "$LOG" || fail "mkcert did not keep its CA in the home" "tp-m10-caroot"
grep -aqF "tp-m10-verify=localhost+1.pem: OK" "$LOG" || fail "openssl did not verify the mkcert certificate against its CA" "tp-m10-verify"
grep -aqF "tp-m10-san=IP Address:127.0.0.1" "$LOG" || fail "the mkcert certificate does not name 127.0.0.1" "tp-m10-san"
echo "B2: as tars, mkcert made a local CA in the home and a localhost certificate that openssl verifies, offline"
M10_NUMBERS="${M10_NUMBERS}, mkcert $(ms_of m10tls)ms"

# 끝 표시와 판정 글자는 printf로 쪼갠다 — 콘솔이 보낸 명령 줄을 로그에 되찍으므로 글자 그대로 쓰면 보내자마자 맞는다(TP-M11 첫 판).
# TP-M11(plan 할 일 4): 서버가 서비스가 된다. root가 tars-service enable로 다섯을 켜고(링크 + reload), 템플릿이 데이터를 /home/.tars/var에
# 두고 사용자 tars로 exec한다. 위 TP-M10 덩이는 다섯을 이미 껐다(같은 포트). 첫 시작은 initdb · mysqld --initialize를 돈다.
as_root 'for s in postgres mysql redis nginx caddy; do tars-service enable $s 2>&1 | sed "s/^/tp-m11-en: /"; done; ls /config/services.d | tr "\n" " " | sed "s/^/tp-m11-links=/"; echo; printf "tp-m11-%s\n" en-done'
wait_log "tp-m11-en-done" 120 || fail "tars-service enable did not finish for the five" "tp-m11-en"
for s in postgres mysql redis nginx caddy; do
  grep -aqE "tp-m11-en: ${s}: enabled, /config/services.d/${s} -> /etc/tars/services/${s}" "$LOG" || fail "enable ${s} did not make the link" "tp-m11-en"
  grep -aqE "tp-m11-en: service ${s}: starts \(new in /config/services.d\)" "$LOG" || fail "reload did not start ${s}" "tp-m11-en"
  grep -aqE "tp-m11-en: service ${s} +running +pid [0-9]+" "$LOG" || fail "enable ${s} did not wait for running" "tp-m11-en"
done
grep -aqF "tp-m11-links=caddy mysql nginx postgres redis " "$LOG" || fail "/config/services.d does not hold the five links" "tp-m11-links"
echo "B2: root ran tars-service enable for postgres, mysql, redis, nginx and caddy; each is a link in /config/services.d and init started it"
# SS-M1: 템플릿 머리의 `# tars-stop:` 줄을 init이 읽었다(enable의 reload가 services.discover를 부른다). nginx · caddy는 줄이 없어 로그도 없다.
for want in "postgres stops with SIGINT, grace 10s" "mysql stops with SIGTERM, grace 30s" "redis stops with SIGTERM, grace 10s"; do
  grep -aqF "tars-init: service ${want}" "$LOG" || fail "init did not read the tars-stop line: ${want}" "tars-stop" "stops with"
done
echo "B2: init read the tars-stop lines (postgres SIGINT 10s, mysql SIGTERM 30s, redis SIGTERM 10s)"
# 다섯이 답할 때까지(mysql의 첫 초기화가 가장 길다 — TP-M10 첫 판 26.5초). 프로세스의 uid는 /proc의 Uid 줄. 그리고 데이터 하나씩.
as_tars 'export PGHOST=/tmp; s=$(date +%s%N); for i in $(seq 480); do pg_isready -q && mysqladmin -uroot ping >/dev/null 2>&1 && redis-cli ping >/dev/null 2>&1 && curl -sf 127.0.0.1:8080 >/dev/null && curl -sf 127.0.0.1:8081 >/dev/null && break; sleep 0.5; done; e=$(date +%s%N); echo "tp-ms-m11up=$(((e-s)/1000000))"; for p in /proc/[0-9]*; do c=$(cat $p/comm 2>/dev/null); case $c in postgres|mysqld|redis-server|nginx|caddy) echo "$c:$(awk "/^Uid:/ {print \$2}" $p/status)";; esac; done | sort -u | tr "\n" " " | sed "s/^/tp-m11-uids=/"; echo; psql -d postgres -Atc "select current_user" | sed "s/^/tp-m11-pguser=/"; psql -d postgres -Atc "create table tp11(x int)" >/dev/null && psql -d postgres -Atc "insert into tp11 values (42)" | sed "s/^/tp-m11-pgw=/"; mysql -uroot -e "create database tp11; create table tp11.t(x int); insert into tp11.t values (42)" && printf "tp-m11-myw=%s\n" ok; redis-cli set tp11 42 | sed "s/^/tp-m11-rdw=/"; curl -s 127.0.0.1:8081 | sed "s/^/tp-m11-cd=/"; curl -s 127.0.0.1:8080 | grep -m1 -o "Welcome to nginx" | sed "s/^/tp-m11-ng=/"; stat -c "%U %a" /home/.tars/var/postgres /config/ssl/tars-selfsigned/key.pem /config/ssl/tars-selfsigned/cert.pem | tr "\n" " " | sed "s/^/tp-m11-own=/"; echo; readlink /var/lib/postgresql /var/lib/mysql /var/lib/redis | tr "\n" " " | sed "s/^/tp-m11-var=/"; echo; printf "tp-m11-%s\n" w-done'
wait_log "tp-m11-w-done" 300 || fail "the five services did not answer and take a write in 300s" "tp-m11-" "tp-ms-m11up"
grep -aqF "tp-m11-uids=caddy:1000 mysqld:1000 nginx:1000 postgres:1000 redis-server:1000 " "$LOG" || fail "a server does not run as uid 1000 (or one is missing)" "tp-m11-uids"
grep -aqF "tp-m11-pguser=tars" "$LOG" || fail "postgres did not take tars as its superuser (initdb by the template)" "tp-m11-pguser"
grep -aqF "tp-m11-pgw=INSERT 0 1" "$LOG" || fail "postgres did not take a row" "tp-m11-pg"
grep -aqF "tp-m11-myw=ok" "$LOG" || fail "mysql did not take a row as root without a password" "tp-m11-my"
grep -aqF "tp-m11-rdw=OK" "$LOG" || fail "redis did not take a key" "tp-m11-rd"
grep -aqF "tp-m11-cd=TARS caddy. Put your sites in /config/caddy.d/*.caddy" "$LOG" || fail "caddy's default site on 8081 did not answer" "tp-m11-cd"
grep -aqF "tp-m11-ng=Welcome to nginx" "$LOG" || fail "nginx's default site on 8080 did not answer" "tp-m11-ng"
grep -aqF "tp-m11-own=tars 755 root 640 root 644 " "$LOG" || fail "the data or the self-signed certificate has the wrong owner or mode" "tp-m11-own"
grep -aqF "tp-m11-var=/home/.tars/var/postgres /home/.tars/var/mysql /home/.tars/var/redis " "$LOG" || fail "/var/lib does not link to /home/.tars/var" "tp-m11-var"
echo "B2: as tars, the five answered as uid 1000 ($(ms_of m11up)ms, first start included), and postgres, mysql and redis each took a row or key under /home/.tars/var"

# SS-M1: psql 세션이 열린 채 postgres를 멈춘다. SIGTERM(smart shutdown)이면 세션을 기다리다 3초 뒤 SIGKILL이었다(SS-M0 결과 2) —
# 템플릿의 SIGINT로는 세션을 끊고 곧 끝난다. 끝나면 다시 띄운다(뒤의 판정 · 부팅 3이 데이터를 본다).
as_tars 'export PGHOST=/tmp; psql -d postgres -qc "select pg_sleep(60)" >/dev/null 2>&1 & sleep 1; ps -u 1000 -o comm= | grep -c "^psql$" | sed "s/^/tp-ss-psql=/"'
wait_log_re "tp-ss-psql=[0-9]+" 30 || fail "the psql session did not start" "tp-ss-psql"
as_root 's=$(date +%s%N); tars-service stop postgres 2>&1 | sed "s/^/tp-ss-stop: /"; e=$(date +%s%N); echo "tp-ms-ssstop=$(((e-s)/1000000))"; tars-service start postgres 2>&1 | sed "s/^/tp-ss-start: /"; printf "tp-ss-%s\n" done'
wait_log "tp-ss-done" 120 || fail "stopping and starting postgres with a session open did not finish" "tp-ss-"
grep -aqF "tp-ss-psql=1" "$LOG" || fail "no psql session was open while postgres stopped" "tp-ss-psql"
grep -aqE "tp-ss-stop: service postgres +stopped" "$LOG" || fail "tars-service stop postgres did not reach stopped" "tp-ss-stop"
grep -aqF "service postgres outlived" "$LOG" && fail "postgres outlived its stop signal with a session open" "outlived" "tp-ss-stop"
SS_STOP_MS="$(ms_of ssstop)"
[ -n "$SS_STOP_MS" ] && [ "$SS_STOP_MS" -lt 3000 ] || fail "stopping postgres with a session open took ${SS_STOP_MS:-?}ms (want under 3000)" "tp-ms-ssstop" "tp-ss-stop"
grep -aqE "tp-ss-start: service postgres +running" "$LOG" || fail "tars-service start postgres did not bring it back" "tp-ss-start"
echo "B2: with a psql session open, tars-service stop postgres sent SIGINT and stopped in ${SS_STOP_MS}ms without SIGKILL, and start brought it back"
# 사람의 조각(/config/nginx.d)과 신뢰. 조각은 8082와, 위 mkcert 덩이의 인증서로 8443 https. CA를 넣기 전 curl은 그 https를 못 믿어야 한다(60).
# 사람은 mkcert -install을 자기로 치고 mkcert가 sudo를 부른다 — 체인은 비밀번호를 못 치므로 root가 같은 CAROOT로 친다(같은 결과).
as_root 'printf "%s\n" "server { listen 127.0.0.1:8082; return 200 tp-m11-frag; }" "server { listen 127.0.0.1:8443 ssl; ssl_certificate /home/tars/tp/m10/tls/localhost+1.pem; ssl_certificate_key /home/tars/tp/m10/tls/localhost+1-key.pem; return 200 tp-m11-tls; }" > /config/nginx.d/tp.conf; tars-service restart nginx 2>&1 | sed "s/^/tp-m11-ngre: /"; for i in $(seq 40); do curl -sk https://localhost:8443 >/dev/null && break; sleep 0.25; done; curl -s https://localhost:8443 >/dev/null 2>&1; echo "tp-m11-before=$?"; env CAROOT=/home/tars/.local/share/mkcert mkcert -install 2>&1 | sed "s/^/tp-m11-mk: /"; ls /usr/local/share/ca-certificates | sed "s/^/tp-m11-ca: /"; update-ca-certificates 2>&1 | sed "s/^/tp-m11-uca: /"; curl -s 127.0.0.1:8082 | sed "s/^/tp-m11-frag=/"; echo; curl -s https://localhost:8443 | sed "s/^/tp-m11-https=/"; echo; printf "tp-m11-%s\n" c-done'
wait_log "tp-m11-c-done" 120 || fail "the nginx piece and the CA did not finish in 120s" "tp-m11-"
grep -aqE "tp-m11-ngre: service nginx +running +pid [0-9]+" "$LOG" || fail "tars-service restart nginx did not bring it back" "tp-m11-ngre"
grep -aqF "tp-m11-frag=tp-m11-frag" "$LOG" || fail "nginx did not read the piece in /config/nginx.d" "tp-m11-frag" "nginx"
grep -aqF "tp-m11-before=60" "$LOG" || fail "curl trusted the mkcert certificate before the CA was added (want 60)" "tp-m11-before"
# mkcert는 부른 명령의 출력을 삼킨다(성공이면 안 보인다). 그래서 mkcert 뒤에 한 번 더 손으로 — /etc의 묶음을 고치는 것은 이 명령뿐이라,
# 아래 https가 믿기면 mkcert가 이것을 불렀다는 뜻이다. 이 줄은 명령이 TARS의 것(원본 + .crt 하나)인지를 본다.
grep -aqF "tp-m11-uca: update-ca-certificates: 1 added from /usr/local/share/ca-certificates to /etc/ssl/certs/ca-certificates.crt" "$LOG" \
  || fail "update-ca-certificates is not TARS's, or it did not count the one mkcert CA" "tp-m11-uca" "tp-m11-mk"
grep -aqE "tp-m11-ca: mkcert_development_CA_[0-9]+\.crt" "$LOG" || fail "mkcert did not put its CA in /usr/local/share/ca-certificates" "tp-m11-ca" "tp-m11-mk"
grep -aqF "tp-m11-https=tp-m11-tls" "$LOG" || fail "curl did not trust https after mkcert -install" "tp-m11-https" "tp-m11-mk"
echo "B2: a piece in /config/nginx.d served 8082 and 8443 (https), curl refused that https until mkcert -install put its CA where update-ca-certificates reads"

# 화면 셸(plan 결정 H): terminal과 사용자 셸이 읽기 전용 /usr 위에서 뜨고, /usr/local/bin의 java가 이름으로 선다.
CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || fail "could not connect to the QEMU monitor on ${MONITOR_PORT}"
PROMPT_UP=0
for _ in 1 2 3 4; do
  if wait_for_screen 'tars@tars ~>'; then PROMPT_UP=1; break; fi
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
M11_UP_MS="$(ms_of m11up)"
NUMBERS="gcc $(ms_of gcc)ms, make $(ms_of make)ms, g++ $(ms_of cpp)ms, zig $(ms_of zig)ms, rustc $(ms_of rustc)ms, cargo $(ms_of cargo)ms, go run $(ms_of gorun)ms, go build $(ms_of gobuild)ms, ${SCRIPT_NUMBERS}, ${M4_NUMBERS}, ${M5_NUMBERS}, ${M6_NUMBERS}, ${M7_NUMBERS}, ${M8_NUMBERS}, ${M9_NUMBERS}, ${M10_NUMBERS}, javac $(ms_of javac)ms, java $(ms_of java)ms, jwebserver $(ms_of web)ms, MemAvailable ${MEM_KB:-?} kB"

# ── CE-M2: 컨테이너(CE design 결정 4~8) ─────────────────────────────────────────────
# 자리가 화면 셸 · 남은 메모리 뒤인 것은 그 둘의 뜻(JVM 서버 뒤)을 안 바꾸려는 것이고, poweroff 앞인 것은 dockerd도 끄기가 먼저
# 멈추는 서비스 가운데 하나여야 하기 때문이다. 포트는 8090 · 8091이다 — 8080 · 8081은 위 TP-M11의 nginx · caddy가 127.0.0.1에서
# 쥐고 있어 docker-proxy가 그 자리에 못 선다(부팅 3에서도 둘이 저절로 뜬다). 기다리는 글자는 계산된 값이나 sed 접두로 짓는다.
# (a) 사용자의 bwrap. --unshare-all이 user namespace를 열고 bwrap이 pivot_root를 돈다 — CE 결정 1(루트 덮기)과 결정 2(USER_NS)의 증거.
as_tars 'bwrap --ro-bind / / --unshare-all --die-with-parent id -u 2>&1 | sed "s/^/ce-bwrap=/"; command -v socat | sed "s/^/ce-socat=/"; printf "ce-%s\n" a-done'
wait_log "ce-a-done" 60 || fail "the bwrap probe did not finish in 60s" "ce-bwrap" "bwrap:"
grep -aqF "ce-bwrap=1000" "$LOG" || fail "bwrap --unshare-all did not run id as the user (user namespace or pivot_root)" "ce-bwrap" "bwrap:" "pivot_root"
grep -aqE "ce-socat=/[a-z]" "$LOG" || fail "socat is not on PATH" "ce-socat"
echo "B2: as tars, bwrap --unshare-all ran id in a new user namespace (pivot_root works) and socat is on PATH"

# (b) 서비스. enable은 running까지 기다린다 — dockerd가 API를 열 때까지는 더 걸린다(TCG). 소켓의 그룹은 uid 1000의 gid다(결정 7).
as_root 's=$(date +%s%N); tars-service enable docker 2>&1 | sed "s/^/ce-en: /"; for i in $(seq 240); do docker version >/dev/null 2>&1 && break; sleep 0.5; done; e=$(date +%s%N); echo "tp-ms-ceup=$(((e-s)/1000000))"; stat -c "%U:%G %a" /run/docker.sock | sed "s/^/ce-sock=/"; printf "ce-%s\n" en-done'
wait_log "ce-en-done" 180 || fail "tars-service enable docker did not finish in 180s" "ce-en" "dockerd" "level=error"
grep -aqF "ce-en: docker: enabled, /config/services.d/docker -> /etc/tars/services/docker" "$LOG" || fail "enable docker did not make the link" "ce-en"
grep -aqF "ce-en: service docker: starts (new in /config/services.d)" "$LOG" || fail "reload did not start docker" "ce-en"
grep -aqE "ce-en: service docker +running +pid [0-9]+" "$LOG" || fail "enable docker did not wait for running" "ce-en"
wait_log "tars-init: service docker stops with SIGTERM, grace 20s" 10 || fail "init did not read docker's tars-stop line" "tars-stop" "stops with"
wait_log "API listen on /var/run/docker.sock" 120 || fail "dockerd did not open its API in 120s" "dockerd" "level=error" "level=fatal" "failed to start daemon"
grep -aqF "ce-sock=root:tars 660" "$LOG" || fail "/run/docker.sock is not root:tars 660 (--group of uid 1000)" "ce-sock"
echo "B2: root ran tars-service enable docker; init read SIGTERM 20s, dockerd opened its API ($(ms_of ceup)ms) on a root:tars 660 socket"

# (c) 사용자가 sudo 없이. 플러그인 둘은 /usr/local/libexec/docker/cli-plugins에서 찾는다.
as_tars 'docker info 2>&1 | grep -E "Cgroup Version|Storage Driver|Firewall Backend|Docker Root Dir" | sed "s/^ */ce-info: /"; docker compose version 2>&1 | sed "s/^/ce-compose: /"; docker buildx version 2>&1 | sed "s/^/ce-buildx: /"; printf "ce-%s\n" c-done'
wait_log "ce-c-done" 60 || fail "docker info, compose and buildx did not finish in 60s" "ce-info" "ce-compose" "ce-buildx"
for want in "Cgroup Version: 2" "Storage Driver: overlayfs" "Firewall Backend: nftables" "Docker Root Dir: /home/.tars/var/docker"; do
  grep -aqF "ce-info: ${want}" "$LOG" || fail "docker info as tars does not say ${want}" "ce-info" "permission denied"
done
grep -aqE "ce-compose: .*v5\.7\.1" "$LOG" || fail "docker compose version did not answer 5.7.1 (cli-plugins)" "ce-compose"
grep -aqE "ce-buildx: .*v0\.38\.2" "$LOG" || fail "docker buildx version did not answer 0.38.2 (cli-plugins)" "ce-buildx"
echo "B2: as tars without sudo, docker info says cgroup v2, overlayfs, nftables and /home/.tars/var/docker; compose 5.7.1 and buildx 0.38.2 answer"

# (d) 망 없이 이미지 하나 — server의 caddy(정적 Go)를 import한다. 첫 답까지 다시 묻는다(TCG에서 ~6초를 쟀다). 64m 제한은
# runc가 만든 cgroup의 memory.max로 본다.
as_tars 'mkdir -p ~/tp/ce/r && cp -L /usr/local/bin/caddy ~/tp/ce/r/caddy && s=$(date +%s%N) && tar -C ~/tp/ce/r -c . | docker import - tars/caddy 2>&1 | sed "s/^/ce-import: /"; e=$(date +%s%N); echo "tp-ms-ceimport=$(((e-s)/1000000))"; s=$(date +%s%N); docker run -d --name ce --memory 64m -p 8090:80 tars/caddy /caddy respond --listen :80 --body ce-ok 2>&1 | sed "s/^/ce-run: /"; o=""; for i in $(seq 30); do o=$(curl -s -m 2 http://127.0.0.1:8090/) && [ -n "$o" ] && break; sleep 1; done; e=$(date +%s%N); echo "tp-ms-cerun=$(((e-s)/1000000))"; echo "ce-curl=$o"; docker port ce 2>&1 | sed "s/^/ce-port: /"; cat /sys/fs/cgroup/docker/$(docker inspect -f "{{.Id}}" ce)/memory.max 2>&1 | sed "s/^/ce-memmax=/"; printf "ce-%s\n" d-done'
wait_log "ce-d-done" 180 || fail "docker import, run and curl did not finish in 180s" "ce-import" "ce-run" "dockerd"
grep -aqE "ce-import: sha256:[0-9a-f]+" "$LOG" || fail "docker import did not make an image" "ce-import"
grep -aqF "ce-curl=ce-ok" "$LOG" || fail "the container did not answer on 127.0.0.1:8090 (-p, bridge, nftables)" "ce-run" "ce-curl" "level=error"
grep -aqF "ce-port: 80/tcp -> 127.0.0.1:8090" "$LOG" || fail "docker port ce is not 127.0.0.1:8090 (daemon.json ip)" "ce-port"
grep -aqF "ce-memmax=67108864" "$LOG" || fail "the container's cgroup has no 64m memory.max" "ce-memmax"
echo "B2: as tars, docker import made tars/caddy offline ($(ms_of ceimport)ms) and its container answered on 127.0.0.1:8090 ($(ms_of cerun)ms) with a 64m cgroup limit"

# (e) 방화벽과의 공존. set과 reload를 한 bash가 차례로 돈다 — set의 답이 찍힌 뒤에 reload가 간다(firewall 체인 검사 19와 같은 차례).
# TARS의 표(ip tars)와 Docker의 표(ip docker-bridges)가 함께 있어야 한다. firewall=on은 그대로 둔다 — 뒤의 판정은 모두 루프백과
# 유닉스 소켓이고(lo는 input이 받는다), 부팅 3이 방화벽을 먼저 세운 기계에서 dockerd가 뜨는지도 함께 본다.
as_root 'tars-config set firewall=on 2>&1 | sed "s/^/ce-fw-set: /"; tars-config reload 2>&1 | sed "s/^/ce-fw-reload: /"; nft list tables 2>&1 | sed "s/^/ce-fw-tables: /"; nft list chain ip tars forward 2>&1 | tr -s "\n\t" "  " | sed "s/^/ce-fw-forward: /"; echo; o=$(curl -s -m 5 http://127.0.0.1:8090/); echo "ce-fw-curl=$o"; printf "ce-%s\n" e-done'
wait_log "ce-e-done" 60 || fail "the firewall set, reload and probes did not finish in 60s" "ce-fw"
grep -aqE "ce-fw-set: firewall: off( \(default\))? -> on" "$LOG" || fail "tars-config set firewall=on did not answer off -> on" "ce-fw-set"
grep -aqF "ce-fw-reload: firewall: up (nft -f /etc/tars/firewall.nft)" "$LOG" || fail "reload did not bring the firewall up" "ce-fw-reload" "tars-init: reload"
grep -aqF "ce-fw-tables: table ip tars" "$LOG" || fail "nft has no table ip tars after reload" "ce-fw-tables"
grep -aqF "ce-fw-tables: table ip docker-bridges" "$LOG" \
  || fail "Docker's table ip docker-bridges is gone after the firewall came up (firewall.nft must only rebuild table ip tars)" "ce-fw-tables"
grep -aqF "ce-fw-curl=ce-ok" "$LOG" || fail "the container stopped answering on 127.0.0.1:8090 with the firewall on" "ce-fw-curl"
# dockerd가 ip_forward를 켠 기계에서 firewall=on은 넘기는 것도 닫는다(make_initrd.sh의 forward 체인) — 받는 것은 맺어진 연결,
# Docker가 DNAT한 포트, 컨테이너 bridge에서 나가는 것 셋이다. 망이 없는 체인이라 길 자체는 못 밟고(프로브가 밟았다 — CE-M2 plan)
# 체인의 모양을 본다. 이 체인이 없으면 Docker를 켠 기계가 NIC 사이의 라우터가 된다.
grep -aqE 'ce-fw-forward: .*hook forward priority filter; policy drop; ct state established,related accept ct status dnat accept iifname "docker0" accept iifname "br-\*" accept' "$LOG" \
  || fail "table ip tars has no forward chain with policy drop and the three accepts" "ce-fw-forward"
echo "B2: tars-config set firewall=on and reload put up table ip tars (input and forward closed) beside Docker's ip docker-bridges, and the container still answers"

# (f) 재부팅을 넘을 컨테이너. unless-stopped라 dockerd가 다시 뜨면 다시 선다(부팅 3). ce는 정책이 없어 Exited로 남는다.
as_tars 'docker run -d --name keep --restart unless-stopped -p 8091:80 tars/caddy /caddy respond --listen :80 --body keep-ok 2>&1 | sed "s/^/ce-keep: /"; o=""; for i in $(seq 30); do o=$(curl -s -m 2 http://127.0.0.1:8091/) && [ -n "$o" ] && break; sleep 1; done; echo "ce-keep-curl=$o"; printf "ce-%s\n" f-done'
wait_log "ce-f-done" 90 || fail "docker run keep did not finish in 90s" "ce-keep"
grep -aqF "ce-keep-curl=keep-ok" "$LOG" || fail "the keep container did not answer on 127.0.0.1:8091" "ce-keep"
echo "B2: as tars, a container with --restart unless-stopped answered on 127.0.0.1:8091"
CE_NUMBERS="dockerd up $(ms_of ceup)ms, import $(ms_of ceimport)ms, first answer $(ms_of cerun)ms"

# 부팅 3의 재료. 묶음이 loop로 열린 채 그 뒤 파일을 0으로 바꾼다 — java는 이미 끝났다.
send "head -c 4096 /dev/zero > /home/.tars/layers/lang-jvm.sqfs; and sync; and printf 'tp-%s\n' broke-done"
wait_log "tp-broke-done" 30 || fail "root could not overwrite /home/.tars/layers/lang-jvm.sqfs"
# SS-M1: 끝은 QEMU 죽이기가 아니라 poweroff다(TP-M11까지는 죽이기라 서버의 끄기를 한 번도 안 봤다). 서비스 다섯을 각자의
# 신호로 먼저 끄고 나머지를 끈다 — SIGKILL 없이. 부팅 3이 두 DB의 복구 없음을 본다.
# CE-M2: 서비스는 docker까지 여섯이다. dockerd는 SIGTERM에 컨테이너 둘을 먼저 멈추고(shutdown-timeout 15초) 20초 안에 끝나야 한다.
# 가장 긴 유예는 여전히 mysql의 30초다.
send "poweroff"
GONE=0
for _ in $(seq 1 1200); do
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then GONE=1; break; fi
  sleep 0.1
done
[ "$GONE" = 1 ] || fail "the guest did not switch itself off in 120s after poweroff" "tars-init: shutdown" "stopping" "outlived"
grep -aqF "tars-init: stopping 6 services first (up to 30s)" "$LOG" || fail "power off did not stop the six services first" "tars-init: stopping" "tars-init: shutdown"
grep -aqE "tars-init: services stopped in [0-9]+ms" "$LOG" || fail "the six services did not all stop on their signals" "outlived" "tars-init: services"
grep -aqF "service docker outlived" "$LOG" && fail "dockerd outlived SIGTERM and its 20s grace at power off" "outlived" "dockerd"
grep -aqF "outlived" "$LOG" && fail "a service outlived its stop signal at power off" "outlived"
grep -aqF "tars-init: grace period expired" "$LOG" && fail "something outlived SIGTERM and SIGHUP after the services" "grace period expired"
SS_OFF_MS="$(last_num 'tars-init: services stopped in [0-9]+ms')"
echo "B2: poweroff stopped the six services (docker included) first in ${SS_OFF_MS}ms, each on its own signal, and nothing needed SIGKILL"
wait "$QEMU_PID" 2>/dev/null
QEMU_PID=""
exec 3>&- 2>/dev/null
exec 4>&-
rm -f "$FIFO"

# ── 부팅 3: NVMe만 — 깨진 묶음 하나 ────────────────────────────────────
echo "=== boot 3: the NVMe with lang-jvm broken ==="
MONITOR="none"
boot_guest 3
grep -aqE "tars-init: layer lang-jvm: mount failed \(errno [0-9]+\)" "$LOG" || fail "init did not name the broken layer" "tars-init: layer"
grep -aqE "tars-init: overlay /usr from 11 layers in [0-9]+ms" "$LOG" || fail "init did not lay base, container, docs, editor, fakesteak, lang-beam, lang-native, lang-script, media, server and util over /usr" "tars-init: overlay"
grep -aqF "tars-init: config shell=" "$LOG" || fail "the boot did not go on to the config line"
as_tars 'cd ~/tp && gcc -O2 -o h2 h.c -lm -lresolv && ./h2 | sed "s/^/tp-b3-c=/"; go run h.go | sed "s/^/tp-b3-go=/"; node h.js | sed "s/^/tp-b3-node=/"; cci --version | sed "s/^/tp-b3-cci=/"; erl -noshell -eval "io:format(\"tp-b3-erl=~s~n\", [erlang:system_info(otp_release)]), halt()."; nvim --version | head -1 | sed "s/^/tp-b3-nvim=/"; rg --version | head -1 | sed "s/^/tp-b3-rg=/"; command -v java || printf "tp-%s\n" no-java'
wait_log "tp-b3-c=tp-c-1.414-0" 180 || fail "gcc no longer works without lang-jvm" "tp-b3"
wait_log "tp-b3-go=tp-go-go1.27.3" 60 || fail "go no longer works without lang-jvm" "tp-b3"
wait_log "tp-b3-node=tp-node-v26.13.0-3abd8072" 60 || fail "node no longer works without lang-jvm" "tp-b3"
wait_log "tp-b3-cci=cci 0.6.2" 30 || fail "util's cci no longer works without lang-jvm" "tp-b3"
wait_log "tp-b3-erl=29" 60 || fail "lang-beam's erl no longer works without lang-jvm" "tp-b3"
wait_log "tp-b3-nvim=NVIM v0.12.6" 30 || fail "editor's nvim no longer works without lang-jvm" "tp-b3"
wait_log "tp-b3-rg=ripgrep 15.2.0" 30 || fail "util's rg no longer works without lang-jvm" "tp-b3"
grep -aqF "tars-init: /usr/local writable (upper on /home/.tars/local)" "$LOG" || fail "boot 3 did not make /usr/local writable" "tars-init: /usr/local"
as_tars 'for c in tpn tpg tpw; do $c; done | sed "s/^/tp-b3-global=/"'
wait_log "tp-b3-global=tp-pip-ok" 60 || fail "what root installed in /usr/local did not survive the reboot" "tp-b3-global"
wait_log "tp-no-java" 10 || fail "java is still there with lang-jvm broken" "tp-b3"
echo "B3: a broken lang-jvm is named and skipped; base, container, docs, editor, lang-beam, lang-native, lang-script, media, server and util still run C, Go, node, cci, erl, nvim and rg, what root put in /usr/local is still there, and the boot is otherwise the same"
# TP-M11: 부팅 2가 켠 다섯이 저절로 뜨고, 부팅 2의 데이터 · 조각 · CA 신뢰가 남아 있다. 부팅 2는 QEMU를 죽여 끝났다(그 앞에 sync) —
# 전원이 끊긴 것과 같다. postgres · mysql의 복구는 판정하지 않고 숫자로 적는다(plan 위험 2).
grep -aqF "tars-init: trust: /usr/bin/update-ca-certificates added the certificates in /usr/local/share/ca-certificates" "$LOG" \
  || fail "init did not run update-ca-certificates for the CA in /usr/local" "tars-init: trust" "update-ca-certificates"
for s in postgres mysql redis nginx caddy; do
  grep -aqE "tars-init: started service ${s} \(pid [0-9]+" "$LOG" || fail "init did not start service ${s} at boot" "tars-init: started" "service ${s}"
done
grep -aqF "tars-init: giving up on service" "$LOG" && fail "init gave up on a service" "tars-init: giving up"
as_tars 'export PGHOST=/tmp; s=$(date +%s%N); for i in $(seq 480); do pg_isready -q && mysqladmin -uroot ping >/dev/null 2>&1 && redis-cli ping >/dev/null 2>&1 && curl -sf 127.0.0.1:8082 >/dev/null && break; sleep 0.5; done; e=$(date +%s%N); echo "tp-ms-m11b3up=$(((e-s)/1000000))"; psql -d postgres -Atc "select x from tp11" | sed "s/^/tp-m11-b3-pg=/"; mysql -uroot -N -e "select x from tp11.t" | sed "s/^/tp-m11-b3-my=/"; redis-cli get tp11 | sed "s/^/tp-m11-b3-rd=/"; curl -s 127.0.0.1:8082 | sed "s/^/tp-m11-b3-frag=/"; echo; curl -s https://localhost:8443 | sed "s/^/tp-m11-b3-https=/"; echo; grep MemAvailable /proc/meminfo | sed "s/^/tp-m11-mem /"; printf "tp-m11-%s\n" b3-done'
wait_log "tp-m11-b3-done" 300 || fail "the five services did not answer after the reboot in 300s" "tp-m11-b3" "tp-ms-m11b3up"
grep -aqF "tp-m11-b3-pg=42" "$LOG" || fail "postgres lost the row after the reboot" "tp-m11-b3-pg" "postgres"
grep -aqF "tp-m11-b3-my=42" "$LOG" || fail "mysql lost the row after the reboot" "tp-m11-b3-my" "mysqld"
grep -aqF "tp-m11-b3-rd=42" "$LOG" || fail "redis lost the key after the reboot" "tp-m11-b3-rd" "redis"
grep -aqF "tp-m11-b3-frag=tp-m11-frag" "$LOG" || fail "the piece in /config/nginx.d did not survive the reboot" "tp-m11-b3-frag"
grep -aqF "tp-m11-b3-https=tp-m11-tls" "$LOG" || fail "the CA added by mkcert -install is not trusted after the reboot" "tp-m11-b3-https" "tars-init: trust"
M11_MEM="$(last_num 'tp-m11-mem MemAvailable: +[0-9]+')"
PG_RECOVERY=no; grep -aqF "database system was not properly shut down; automatic recovery in progress" "$LOG" && PG_RECOVERY=yes
MY_RECOVERY=no; grep -aqE "\[InnoDB\] (Starting crash recovery|Database was not shutdown normally)" "$LOG" && MY_RECOVERY=yes
# SS-M1: 부팅 2가 poweroff로 끝났으므로 두 DB는 정상 종료였다 — 복구가 돌면 끄기가 서버를 제대로 끝내지 못한 것이다.
[ "$PG_RECOVERY" = no ] || fail "postgres ran crash recovery after a clean poweroff" "not properly shut down"
[ "$MY_RECOVERY" = no ] || fail "mysql ran crash recovery after a clean poweroff" "InnoDB"
echo "B3: the five came back on their own ($(ms_of m11b3up)ms), postgres, mysql and redis kept boot 2's data, the nginx piece and the CA trust survived (crash recovery: postgres ${PG_RECOVERY}, mysql ${MY_RECOVERY}, MemAvailable ${M11_MEM:-?} kB)"
as_root 'tars-service disable redis 2>&1 | sed "s/^/tp-m11-dis: /"; ls /config/services.d | tr "\n" " " | sed "s/^/tp-m11-links3=/"; echo; redis-cli ping >/dev/null 2>&1; echo "tp-m11-rdping=$?"; printf "tp-m11-%s\n" dis-done'
wait_log "tp-m11-dis-done" 60 || fail "tars-service disable redis did not finish" "tp-m11-dis"
grep -aqF "tp-m11-dis: redis: disabled, removed /config/services.d/redis" "$LOG" || fail "disable redis did not remove the link" "tp-m11-dis"
grep -aqF "tp-m11-dis: service redis: stops" "$LOG" || fail "reload did not stop redis" "tp-m11-dis"
grep -aqE "tp-m11-dis: service redis +stopped" "$LOG" || fail "disable redis did not wait for stopped" "tp-m11-dis"
grep -aqF "tp-m11-links3=caddy docker mysql nginx postgres " "$LOG" || fail "the other five links (docker included) are not as they were" "tp-m11-links3"
grep -aqF "tp-m11-rdping=1" "$LOG" || fail "redis still answers after disable" "tp-m11-rdping"
echo "B3: tars-service disable redis removed the link, init stopped it and the other five stay"
M11_NUMBERS="services up ${M11_UP_MS}ms, after the reboot $(ms_of m11b3up)ms, MemAvailable with six ${M11_MEM:-?} kB, recovery pg ${PG_RECOVERY} my ${MY_RECOVERY}"

# CE-M2: 부팅 2가 켠 docker가 저절로 뜬다 — 이번에는 방화벽(firewall=on)이 먼저 선 기계다. 이미지는 p3에 남고, unless-stopped인
# keep은 다시 서서 답하고, 정책이 없는 ce는 Exited로 남는다. 끝에 disable docker(redis와 같은 길).
grep -aqE "tars-init: started service docker \(pid [0-9]+" "$LOG" || fail "init did not start service docker at boot" "tars-init: started" "service docker"
wait_log "API listen on /var/run/docker.sock" 120 || fail "dockerd did not open its API after the reboot in 120s" "dockerd" "level=error" "level=fatal" "failed to start daemon"
as_tars 'o=""; for i in $(seq 60); do o=$(curl -s -m 2 http://127.0.0.1:8091/) && [ -n "$o" ] && break; sleep 1; done; echo "ce-b3-curl=$o"; docker images --format "{{.Repository}}" 2>&1 | sed "s/^/ce-b3-img=/"; docker ps -a --format "{{.Names}} {{.Status}}" 2>&1 | sed "s/^/ce-b3-ps: /"; printf "ce-%s\n" b3-done'
wait_log "ce-b3-done" 120 || fail "the docker probes after the reboot did not finish in 120s" "ce-b3" "dockerd"
# nft는 CAP_NET_ADMIN이 있어야 표를 읽는다 — root로.
as_root 'nft list tables 2>&1 | sed "s/^/ce-b3-tables: /"; printf "ce-%s\n" b3t-done'
wait_log "ce-b3t-done" 30 || fail "nft list tables did not finish" "ce-b3-tables"
grep -aqF "ce-b3-img=tars/caddy" "$LOG" || fail "the imported image did not survive the reboot (data-root on p3)" "ce-b3-img"
grep -aqE "ce-b3-ps: keep Up" "$LOG" || fail "the keep container (unless-stopped) is not up after the reboot" "ce-b3-ps"
grep -aqE "ce-b3-ps: ce Exited" "$LOG" || fail "the ce container (no restart policy) is not Exited after the reboot" "ce-b3-ps"
grep -aqF "ce-b3-curl=keep-ok" "$LOG" || fail "the keep container did not answer on 127.0.0.1:8091 after the reboot" "ce-b3-curl" "level=error"
grep -aqF "ce-b3-tables: table ip tars" "$LOG" || fail "firewall=on from boot 2 did not put up table ip tars at boot" "ce-b3-tables" "tars-init: firewall"
grep -aqF "ce-b3-tables: table ip docker-bridges" "$LOG" || fail "dockerd did not put up table ip docker-bridges after the boot's firewall" "ce-b3-tables"
echo "B3: dockerd came back on its own with the firewall up (both tables), tars/caddy is still there, keep is Up and answers, ce stayed Exited"
as_root 'tars-service disable docker 2>&1 | sed "s/^/ce-dis: /"; ls /config/services.d | tr "\n" " " | sed "s/^/ce-links=/"; echo; docker version >/dev/null 2>&1; echo "ce-dping=$?"; printf "ce-%s\n" dis-done'
wait_log "ce-dis-done" 60 || fail "tars-service disable docker did not finish in 60s" "ce-dis"
grep -aqF "ce-dis: docker: disabled, removed /config/services.d/docker" "$LOG" || fail "disable docker did not remove the link" "ce-dis"
grep -aqF "ce-dis: service docker: stops" "$LOG" || fail "reload did not stop docker" "ce-dis"
grep -aqE "ce-dis: service docker +stopped" "$LOG" || fail "disable docker did not wait for stopped" "ce-dis"
grep -aqF "service docker outlived" "$LOG" && fail "dockerd outlived SIGTERM and its 20s grace on disable" "outlived" "dockerd"
grep -aqF "ce-links=caddy mysql nginx postgres " "$LOG" || fail "the other four links are not as they were after disable docker" "ce-links"
grep -aqF "ce-dping=1" "$LOG" || fail "dockerd still answers after disable" "ce-dping"
echo "B3: tars-service disable docker removed the link, init stopped dockerd on SIGTERM and the other four stay"
stop_guest

# ── 부팅 4: ISO + 같은 NVMe — 갱신 ─────────────────────────────────────
echo "=== boot 4: the ISO again over the installed NVMe (update) ==="
boot_guest 4 -cdrom "$ISO"
send "tars-install /dev/nvme0n1 --yes"
wait_log "tars-install: updated. remove the boot medium and reboot." 600 || fail "the update did not say updated" "tars-install:"
grep -aqF "  p3 (tars-home) <- layers ${VER} -> ${VER} (${LAYER_MIB} MiB), your files are not touched" "$LOG" \
  || fail "the update plan does not say p3 gets the layers" "(tars-home)"
grep -aqF "  .tars/layers: 12 old layers removed" "$LOG" || fail "the update did not remove the twelve old layers first" ".tars/layers"
grep -aqF "  .tars/layers/lang-jvm.sqfs $(stat -c %s ../devlayer/build/lang-jvm.sqfs) bytes" "$LOG" \
  || fail "the update did not put lang-jvm.sqfs back byte for byte" ".tars/layers"
echo "B4: the update planned the layers on p3, removed the twelve old ones and put them back"
stop_guest

echo "devtools: numbers: layers ${LAYER_MIB} MiB, copy ${COPY_MS}ms, overlay ${MOUNT_MS}ms, ${NUMBERS}, ${M11_NUMBERS}, ${CE_NUMBERS}"
echo "devtools: chain $(( $(date +%s) - CHAIN_T0 ))s after the build"
echo "PASS"
exit 0
