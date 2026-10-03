# SV-M0 — 서비스와 sshd를 넣기 전에 여섯을 잰다

> 이 plan을 실행하는 사람에게: 이 milestone은 커밋되는 코드를 한 줄도 안
> 고친다. 만드는 것은 `/tmp/sv/` 아래의 하네스뿐이고, 저장소에 들어가는 것은
> design의 실측 절과 이 plan이다. FW-M0과 달리 `kernel/.config`도 안 건드린다 —
> sshd가 요구하는 커널 기능(devpts · `/dev/ptmx` · TCP)은 이미 다 있다. TDD 구조가
> 아니다 — FW-M0 · LB-M0 plan과 같은 형식이다.

Goal: SV design의 M0 목록(sshd · ssh-keygen의 비용 · `/config`에서 스크립트가
직접 실행되는가 · `debugfs`가 실행 비트와 링크를 만드는가 · sshd가 게스트에서
요구하는 것 · StrictModes · 로그인 셸과 `TERM`)을 부팅 하나로 답해서, M1 · M2가
코드를 쓸 때 남은 결정을 없앤다.

Architecture: 패키지를 받아 풀고 재귀 `DT_NEEDED`를 따라가 비용을 잰다. 그
바이너리와 라이브러리, `sshd_config`, 게스트 스크립트 `svm0.sh`, 시험용 서비스
스크립트를 ext2 설정 디스크(`-L tars-sv`)에 실어 `/config/`로 닿게 한다. 콘솔
셸에는 FIFO로 `bash /config/svm0.sh <단계>`를 한 줄씩 친다. 게스트 안에서는 M2가
initrd에 둘 자리(`/usr/bin/sshd` · `/usr/lib/openssh/` · `/lib/x86_64-linux-gnu/`)에
손으로 복사한다 — initramfs의 루트는 쓸 수 있다. 바깥에서 붙는 쪽은 컨테이너에
그때 설치하는 `openssh-client`다.

Tech Stack: bash · `apt-get download openssh-server:amd64 openssh-client:amd64 …` ·
`readelf` · `mkfs.ext2 -d` · `debugfs` · QEMU(`virtio-net-pci` + SLIRP `hostfwd`) ·
컨테이너의 `ssh` · `ssh-keygen` · `ssh-keyscan` · 기존 빌드 스크립트 넷

---

## 무엇을 재는가

| 측정 | 무엇 | design의 자리 | 어디서 |
|---|---|---|---|
| 1 | sshd · `sshd-session`(· `sshd-auth`) · ssh-keygen의 바이트와 재귀 `DT_NEEDED`, 그중 initrd에 없는 것 | 결정 6 · 위험 1 | Task 1 |
| 2 | `debugfs`로 쓴 파일의 모드, `sif`로 실행 비트, `symlink` | 결정 7 | Task 2 · `exec` |
| 3 | `/config`의 mount 옵션, 거기 둔 스크립트가 shebang으로 직접 실행되나 · 링크를 따라가 실행되나 · 실행 비트 없는 것은 무엇으로 실패하나 | 결정 2 · 결정 4 | `exec` |
| 4 | sshd가 이 게스트에서 요구하는 것 — privsep 사용자 · `/run/sshd` · 그 밖(`sshd -t`의 에러를 단계마다) | 결정 6 | `need` |
| 5 | 키 로그인이 되나, 등록 안 된 키는 거절되나, `/config/ssh`가 그룹 쓰기면 StrictModes가 거절하나 | 결정 6 · 위험 2 | 하네스 `login` |
| 6 | ssh 세션의 `$0` · `$SHELL` · `PATH` · `TERM`, terminfo가 없는 `TERM`에서 `less`가 어떻게 되나 | 비목표 7 · 위험 3 | 하네스 `login` |

부팅은 하나다(`net=dhcp`, `virtio-net-pci` + SLIRP). 호스트 키 지문이 부팅을 넘는지는
재지 않는다 — 파일이 ext2에 남는 것은 CP 이래의 사실이고, M2의 부팅 C가 판정한다.

포트 하나. 컨테이너 `127.0.0.1:45422` → 게스트 `10.0.2.15:22`.

## Task 0 — `/tmp/sv/`를 만든다

- [ ] Step 1: 디렉터리를 비우고 만든다

```bash
rm -rf /tmp/sv && mkdir -p /tmp/sv/seed/sv/lib /tmp/sv/seed/sv/bin /tmp/sv/seed/svc /tmp/sv/seed/ssh && ls -la /tmp/sv
```

- [ ] Step 2: 작업 트리를 본다

```bash
git status --short
```

기대: 이 plan 한 줄만 있다.

## Task 1 — 패키지를 꺼내고 비용을 잰다 (측정 1)

- [ ] Step 1: 닫힘을 구하고 받아 푼다

`project_measuring_tool_cost`의 절차 1 · 2다. 스테이징(`/tmp/sv/stage`)에 풀고
sysroot는 안 건드린다 — `readelf`로 따라갈 때 스테이징을 먼저, sysroot를 다음에 본다.

```bash
docker run --rm -v /tmp/sv:/tmp/sv tars-devcontainer bash -c '
  set -e
  cd /tmp/sv
  apt-get update -qq >/dev/null 2>&1 || true
  pk=$(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts \
        --no-breaks --no-replaces --no-enhances --no-pre-depends \
        openssh-server:amd64 openssh-client:amd64 \
        | grep "^[a-z0-9]" | sed "s/:amd64$//" | sort -u)
  echo "$pk" > closure.txt; wc -l closure.txt
  mkdir -p debs stage
  # 한 번에 받으면 Architecture: all인 것(runit-helper · ucf 등)이 `:amd64` 후보가
  # 없어 목록 전체가 멈춘다(실행 중 발견). 하나씩 받고 실패하면 접미사 없이 받는다.
  (cd debs && for p in $(cat ../closure.txt); do
     apt-get download "$p:amd64" >/dev/null 2>&1 || apt-get download "$p" >/dev/null 2>&1 || echo "FAIL $p"
   done)
  ls debs | wc -l
  for d in debs/*.deb; do dpkg -x "$d" stage; done
  dpkg-deb -f debs/openssh-server_*.deb Version
  find stage -name "sshd*" -o -name "ssh-keygen" | sort'
```

기대: `openssh-server`의 버전(Debian 13이면 10.0 계열)과 `usr/sbin/sshd` ·
`usr/lib/openssh/sshd-session` · (10.0이면) `usr/lib/openssh/sshd-auth` ·
`usr/bin/ssh-keygen`. 적을 것 — 버전, 실행 파일 목록. `sshd-session` · `sshd-auth`의
경로는 sshd에 컴파일되어 박혀 있으므로 M2의 initrd가 그 경로를 그대로 따라야 한다.

- [ ] Step 2: 재귀 `NEEDED`를 따라가며 바이너리와 라이브러리를 시드에 모은다

```bash
docker run --rm -v /tmp/sv:/tmp/sv tars-devcontainer bash -c '
  set -e
  cd /tmp/sv
  SYS=/usr/local/amd64-sysroot
  bins="stage/usr/sbin/sshd stage/usr/bin/ssh-keygen"
  for b in stage/usr/lib/openssh/sshd-session stage/usr/lib/openssh/sshd-auth; do
    [ -e "$b" ] && bins="$bins $b"
  done
  for b in $bins; do
    echo "SVM0-BIN $(basename $b) $(stat -Lc %s $b)"; cp -L "$b" seed/sv/bin/
  done
  todo="$bins"; seen=""
  while [ -n "$todo" ]; do
    f=${todo%% *}; todo=${todo#"$f"}; todo=${todo# }
    for n in $(readelf -d "$f" | sed -n "s/.*Shared library: \[\(.*\)\]/\1/p"); do
      case "$n" in ld-linux*) continue ;; esac
      case " $seen " in *" $n "*) continue ;; esac
      seen="$seen $n"
      p=$(find stage -name "$n" | head -1)
      [ -z "$p" ] && p=$(find $SYS/lib $SYS/usr/lib -name "$n" 2>/dev/null | head -1)
      [ -z "$p" ] && { echo "SVM0-NEED $n MISSING"; continue; }
      echo "SVM0-NEED $n $(stat -Lc %s "$p") by=$(basename $f)"
      todo="$todo $(readlink -f "$p")"
      cp -L "$p" seed/sv/lib/"$n"
    done
  done' | tee /tmp/sv/need.txt
ls -la /tmp/sv/seed/sv/bin /tmp/sv/seed/sv/lib
```

`MISSING`이 있으면 그 SONAME을 주는 패키지를 `closure.txt`가 놓친 것이다 —
`--no-pre-depends`를 빼거나 그 패키지를 Step 1의 목록에 더해 다시 한다.

- [ ] Step 3: initrd에 이미 있는 것을 빼고 무게를 잰다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd init && zig build >/dev/null && cd ../terminal && ./prepare.sh >/dev/null &&
  cd ../kernel && ./make_initrd.sh >/dev/null &&
  zcat initrd.cpio | cpio -it 2>/dev/null | sed -n "s|^lib/x86_64-linux-gnu/||p" | sort' > /tmp/sv/initrd-libs.txt
ls -la kernel/initrd.cpio
find /tmp/sv/seed/sv/lib -type f -exec basename {} \; | sort > /tmp/sv/need-libs.txt  # ls는 호스트에서 eza 별칭이라 색 코드가 섞인다
comm -13 /tmp/sv/initrd-libs.txt /tmp/sv/need-libs.txt > /tmp/sv/new-libs.txt
cat /tmp/sv/new-libs.txt
(cd /tmp/sv/seed/sv/lib && cat ../../../new-libs.txt | xargs stat -f '%z %N') | sort -n
(cd /tmp/sv/seed/sv/lib && cat ../../../new-libs.txt | xargs stat -f '%z') | paste -sd+ - | bc
```

적을 것 — 새 라이브러리의 이름과 바이트, 합, 바이너리 넷의 합, 그 둘이 지금
`initrd.cpio`의 몇 %인가. 어느 바이너리가 어느 새 라이브러리를 끌고 왔는가(`need.txt`의
`by=`) — 특히 `libgssapi_krb5` 계열이 있으면 그 몫을 따로 적는다(위험 1).

## Task 2 — `debugfs`가 만드는 것을 컨테이너에서 먼저 본다 (측정 2의 절반)

- [ ] Step 1: 빈 이미지에 셋을 써 본다

```bash
docker run --rm -v /tmp/sv:/tmp/sv tars-devcontainer bash -c '
  cd /tmp/sv
  printf "#!/bin/sh\necho hi\n" > probe.sh; chmod 644 probe.sh
  dd if=/dev/zero of=probe.img bs=1M count=4 status=none
  mkfs.ext2 -F -q -m 0 probe.img
  debugfs -w -R "write probe.sh plain" probe.img
  debugfs -w -R "write probe.sh execd" probe.img
  debugfs -w -R "sif execd mode 0100755" probe.img
  debugfs -w -R "symlink link /config/svc/execd" probe.img
  for n in plain execd link; do debugfs -R "stat $n" probe.img 2>/dev/null | head -3; done'
```

적을 것 — `plain`의 모드(원본 `644`를 따랐나), `execd`의 모드가 `0755`인가,
`link`가 `Type: symlink`이고 `Fast link dest`가 `/config/svc/execd`인가.
`sif`의 인자 모양이 틀려 에러가 나면 그 에러를 적고 `sif execd mode 0x81ed`로
다시 해 본다.

## Task 3 — 시드 · 게스트 스크립트 · 디스크

- [ ] Step 1: 시험용 서비스 스크립트 넷과 `sshd_config`를 쓴다

```bash
cat > /tmp/sv/seed/svc/hello <<'EOF'
#!/bin/sh
printf 'SVM0-%s %s\n' RAN "hello $0 $$"
EOF
chmod 755 /tmp/sv/seed/svc/hello
printf '#!/bin/sh\nprintf "SVM0-%%s %%s\\n" RAN "noexec"\n' > /tmp/sv/seed/svc/noexec
chmod 644 /tmp/sv/seed/svc/noexec
cat > /tmp/sv/sshd_config <<'EOF'
# SV-M0. design 결정 6 그대로.
HostKey /config/ssh/ssh_host_ed25519_key
AuthorizedKeysFile /config/ssh/authorized_keys
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
UsePAM no
EOF
cp /tmp/sv/sshd_config /tmp/sv/seed/sv/sshd_config
```

`printf 'SVM0-%s'`로 표지를 쪼개 쓰는 이유 — 스크립트 본문이 화면에 찍힐 일은 없지만,
`cat`으로 내용을 볼 때 표지가 판정에 섞이지 않게 한다(`project_gate_screen_echo`).

`noexec`는 `mkfs -d` 경로(모드 `644` 그대로), `execd` · `link`는 Task 4 Step 2에서
`debugfs` 경로로 넣는다 — 측정 2의 나머지 절반이 게스트에서 판정된다.

- [ ] Step 2: `/tmp/sv/seed/svm0.sh`를 쓴다

```bash
cat > /tmp/sv/seed/svm0.sh <<'EOF'
#!/bin/bash
# SV-M0. 게스트의 /config/svm0.sh로 닿는다. 표지는 전부 "SVM0-<이름> ".
# 우리가 치는 줄은 "bash /config/svm0.sh <단계>"뿐이라 그 에코에는 표지가 없다.
mark() { printf 'SVM0-%s %s\n' "$1" "$2"; }

case "$1" in
exec)
  # 측정 2 · 3. mount 옵션, 그리고 넷을 직접 실행한다(bash를 거치지 않는다).
  mark MOUNT "$(grep ' /config ' /proc/mounts)"
  for f in hello noexec execd link; do
    p=/config/svc/$f
    mark STAT "$f $(stat -c '%A %U:%G %F' "$p" 2>&1) -> $(readlink "$p")"
    out=$("$p" 2>&1); mark EXEC "$f rc=$? out=[$(echo "$out" | tr '\n' ';')]"
  done
  mark DONE exec
  ;;
need)
  # 측정 4. M2의 initrd 자리에 손으로 놓고, sshd -t를 한 단계씩 돌린다.
  cp /config/sv/bin/sshd /usr/bin/sshd
  cp /config/sv/bin/ssh-keygen /usr/bin/ssh-keygen
  mkdir -p /usr/lib/openssh
  for b in sshd-session sshd-auth; do
    [ -e /config/sv/bin/$b ] && cp /config/sv/bin/$b /usr/lib/openssh/$b
  done
  chmod 755 /usr/bin/sshd /usr/bin/ssh-keygen /usr/lib/openssh/* 2>/dev/null
  n=0
  for l in /config/sv/lib/*; do
    [ -e /lib/x86_64-linux-gnu/$(basename $l) ] || { cp $l /lib/x86_64-linux-gnu/; n=$((n + 1)); }
  done
  mark LIBS "copied $n"
  mkdir -p /etc/ssh; cp /config/sv/sshd_config /etc/ssh/sshd_config
  mark VERSION "$(/usr/bin/sshd -V 2>&1 | head -1)"

  t() { mark TEST "$1 rc=$(/usr/bin/sshd -t -f /etc/ssh/sshd_config >/tmp/t.out 2>&1; echo $?) err=[$(tr '\n' ';' </tmp/t.out)]"; }
  t bare
  if [ ! -e /config/ssh/ssh_host_ed25519_key ]; then
    /usr/bin/ssh-keygen -q -t ed25519 -N '' -f /config/ssh/ssh_host_ed25519_key
    mark KEYGEN "rc=$?"
  fi
  mark FPR "$(/usr/bin/ssh-keygen -l -f /config/ssh/ssh_host_ed25519_key.pub)"
  t key
  grep -q '^sshd:' /etc/passwd || echo 'sshd:x:100:65534::/run/sshd:/usr/sbin/nologin' >> /etc/passwd
  grep -q '^nogroup:' /etc/group || echo 'nogroup:x:65534:' >> /etc/group
  t user
  mkdir -p /run/sshd; chmod 755 /run/sshd
  t rundir

  /usr/bin/sshd -D -e -f /etc/ssh/sshd_config < /dev/null > /tmp/sshd.log 2>&1 &
  echo $! > /tmp/sshd.pid; disown -a
  sleep 1
  # 22 = 0x0016. 손으로 옮기지 않는다(FW 실측 10).
  mark LISTEN "$(grep -c ":$(printf '%04X' 22) 00000000:0000 0A" /proc/net/tcp) pid=$(cat /tmp/sshd.pid)"
  mark DONE need
  ;;
perm)
  # 측정 5의 StrictModes 쪽. /config/ssh를 그룹 쓰기로 연다.
  chmod 770 /config/ssh; mark PERM "$(stat -c '%a %U:%G' /config/ssh /config/ssh/authorized_keys | tr '\n' ';')"
  mark DONE perm
  ;;
unperm)
  chmod 700 /config/ssh; mark PERM "$(stat -c '%a %U:%G' /config/ssh | tr '\n' ';')"
  mark DONE unperm
  ;;
log)
  while IFS= read -r l; do mark SSHD "$l"; done < /tmp/sshd.log
  mark DONE log
  ;;
*)
  mark USAGE "unknown phase"
  ;;
esac
EOF
chmod 755 /tmp/sv/seed/svm0.sh
```

`need`가 `sshd -t`를 네 번 돌리는 이유 — 무엇이 없을 때 무슨 말로 죽는가가 M2의
가이드와 로그 판정의 재료다. `bare`는 호스트 키도 사용자도 `/run/sshd`도 없는
상태이고, 하나씩 채울 때마다 에러가 바뀌거나 사라진다. 순서는 sshd가 확인하는
순서와 다를 수 있으므로 `rc`가 0이 되는 단계만이 아니라 에러 문구 전부를 적는다.

- [ ] Step 3: 클라이언트 키와 디스크를 굽는다

소유자를 컨테이너 안에서 root로 맞춘다. macOS 바인드 마운트의 파일을 `mkfs -d`가
그대로 읽으면 uid가 무엇으로 찍힐지 모르고, 그것이 곧 StrictModes의 판정을
흔든다 — 그래서 시드를 컨테이너 안의 디렉터리로 복사해 `chown`한 뒤 굽는다.

```bash
printf '# SV-M0.\nhangul_layout=sebeol_3p3\nnet=dhcp\n' > /tmp/sv/seed/tars.conf
docker run --rm -v /tmp/sv:/tmp/sv tars-devcontainer bash -c '
  set -e
  apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq openssh-client >/dev/null 2>&1
  cd /tmp/sv
  ssh-keygen -q -t ed25519 -N "" -C svm0-good -f good
  ssh-keygen -q -t ed25519 -N "" -C svm0-bad -f bad
  rm -rf /root/seed; cp -a seed /root/seed
  cp good.pub /root/seed/ssh/authorized_keys
  chown -R 0:0 /root/seed
  chmod 700 /root/seed/ssh; chmod 600 /root/seed/ssh/authorized_keys
  dd if=/dev/zero of=cfg.img bs=1M count=64 status=none
  mkfs.ext2 -F -q -m 0 -L tars-sv -d /root/seed cfg.img
  printf "#!/bin/sh\nprintf \"SVM0-%%s %%s\\\\n\" RAN \"execd \$0\"\n" > execd.src
  debugfs -w -R "write execd.src svc/execd" cfg.img
  debugfs -w -R "sif svc/execd mode 0100755" cfg.img
  debugfs -w -R "symlink svc/link /config/svc/execd" cfg.img
  debugfs -R "ls -l /" cfg.img 2>/dev/null
  debugfs -R "ls -l /svc" cfg.img 2>/dev/null
  debugfs -R "ls -l /ssh" cfg.img 2>/dev/null'
```

기대: `/`에 `tars.conf` · `svm0.sh` · `sv` · `svc` · `ssh`, `/svc`에 `hello`(755) ·
`noexec`(644) · `execd` · `link`, `/ssh`에 `authorized_keys`(600, uid 0). 라이브러리
합이 크면 64MB로 모자랄 수 있다 — `mkfs`가 `Could not allocate block`을 내면 128로 올린다.

## Task 4 — 하네스를 쓴다

- [ ] Step 1: `/tmp/sv/boot.sh`를 쓴다

```bash
cat > /tmp/sv/boot.sh <<'EOF'
#!/usr/bin/env bash
# SV-M0. 컨테이너 안에서 돈다.
set -uo pipefail
cd /workspace
LOG=/tmp/sv/guest.log
FIFO=/tmp/sv/guest.fifo
rm -f "$LOG" "$FIFO"; mkfifo "$FIFO"

apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq openssh-client >/dev/null 2>&1 \
  || { echo "SVM0: cannot install openssh-client"; exit 1; }

(cd kernel && ./build.sh)       || { echo "SVM0: kernel build failed"; exit 1; }
(cd init && zig build)          || { echo "SVM0: init build failed"; exit 1; }
(cd terminal && ./prepare.sh)   || { echo "SVM0: terminal build failed"; exit 1; }
(cd kernel && ./make_initrd.sh) || { echo "SVM0: initrd build failed"; exit 1; }

exec 4<>"$FIFO"
qemu-system-x86_64 \
  -m 512 \
  -kernel kernel/build/arch/x86/boot/bzImage \
  -initrd kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none -device virtio-gpu-pci -display none \
  -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:45422-10.0.2.15:22" -device virtio-net-pci,netdev=n0 \
  -drive file=/tmp/sv/cfg.img,if=virtio,format=raw \
  -serial stdio \
  -no-reboot \
  < "$FIFO" > "$LOG" 2>&1 &
QEMU=$!
cleanup() { kill "$QEMU" 2>/dev/null; wait 2>/dev/null; exec 4>&-; rm -f "$FIFO"; }
trap cleanup EXIT

W=0
until grep -aq "started console shell" "$LOG" 2>/dev/null; do
  sleep 1; W=$((W + 1))
  [ "$W" -ge 120 ] && { echo "SVM0: console shell never started"; tail -40 "$LOG"; exit 1; }
done
echo "SVM0: console shell up after ${W}s"
T0=$SECONDS
until grep -aqE "leased [0-9.]+ for" "$LOG"; do
  sleep 1; [ $((SECONDS - T0)) -ge 40 ] && { echo "SVM0: no lease in 40s"; break; }
done
sleep 2

run() {  # 한 단계를 치고 그 단계의 DONE 표지가 하나 늘기를 기다린다
  local phase="$1" n
  n=$(grep -ac "SVM0-DONE $phase" "$LOG")
  printf 'bash /config/svm0.sh %s\n' "$phase" >&4
  for _ in $(seq 1 90); do
    [ "$(grep -ac "SVM0-DONE $phase" "$LOG")" -gt "$n" ] && return 0
    sleep 1
  done
  echo "SVM0: $phase never answered"
}

SSHO=(-p 45422 -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no
      -o UserKnownHostsFile=/tmp/sv/known_hosts -o IdentitiesOnly=yes)

login() {  # $1 = 이름, $2 = 키 파일, 나머지 = ssh에 더 줄 것. 원격 명령은 고정이다
  local tag="$1" key="$2"; shift 2
  local s out rc
  s=$(date +%s%N)
  out=$(ssh "${SSHO[@]}" -i "$key" "$@" root@127.0.0.1 \
    'printf "%s|%s|%s|%s|%s\n" "$0" "$SHELL" "$TERM" "$PATH" "$(id -u)"; ls /usr/share/terminfo/x' 2>&1)
  rc=$?
  echo "SVM0-LOGIN $tag rc=$rc ms=$(( ($(date +%s%N) - s) / 1000000 )) out=[$(echo "$out" | tr '\n' ';')]"
}

run exec
run need
ssh-keyscan -p 45422 -t ed25519 127.0.0.1 2>/dev/null | ssh-keygen -lf - | sed 's/^/SVM0-SCAN /'
login good /tmp/sv/good
login bad  /tmp/sv/bad
# 측정 6. terminfo가 있는 TERM과 없는 TERM에서 pty를 받고 less를 한 번 돌린다.
for term in xterm-256color xterm-ghostty; do
  # timeout: 첫 실행에서 xterm-ghostty 쪽이 돌아오지 않았다. 매달린 것도 측정이라
  # 잘라서 거기까지의 출력과 rc(124)를 남긴다.
  out=$(TERM=$term timeout 15 ssh "${SSHO[@]}" -i /tmp/sv/good -tt root@127.0.0.1 \
    'echo "$TERM"; echo x | less -FX; echo "rc=$?"' 2>&1 < /dev/null)
  echo "SVM0-PTYRC $term $?"
  echo "SVM0-PTY $term out=[$(echo "$out" | tr -d '\r' | tr '\n' ';')]"
done
run perm
login perm /tmp/sv/good
run unperm
login unperm /tmp/sv/good
run log
echo "=== done ==="
EOF
chmod +x /tmp/sv/boot.sh
```

`login`의 원격 명령에 표지가 없는 이유 — 그 출력은 게스트 화면이 아니라 컨테이너의
`ssh` stdout으로 오고, 하네스가 `SVM0-LOGIN` 줄로 감싸서 `run.log`에 적는다. 게스트
로그(`guest.log`)에는 sshd의 `-e` 출력이 콘솔로 오지 않는다(`/tmp/sshd.log`로 돌렸다)
— 그것은 `log` 단계가 표지를 붙여 화면에 낸다.

`perm` 뒤의 로그인이 거절되고 `unperm` 뒤의 로그인이 다시 되면 StrictModes가
`/config/ssh`의 그룹 쓰기를 본다는 뜻이다. `perm`에서도 되면 StrictModes는 이
자리를 안 본다 — 둘 다 M2의 가이드에 적을 사실이다.

## Task 5 — 부팅 하나를 돌린다 (빌드가 끝나 있으면 약 2분)

- [ ] Step 1: 돌린다

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/sv:/tmp/sv -w /workspace \
  tars-devcontainer bash /tmp/sv/boot.sh > /tmp/sv/run.log 2>&1; echo "exit=$?"
grep -E '^SVM0|^===' /tmp/sv/run.log
grep -aoE "SVM0-[A-Z]+ .*" /tmp/sv/guest.log | tr -d '\r'
grep -aE "tars-init: (config|started)|leased" /tmp/sv/guest.log | head -10
```

적을 것 — 측정별로.

- 2 · 3: `MOUNT`의 옵션(`noexec`가 없나), `STAT` 넷(모드 · 소유자 · 링크 대상),
  `EXEC` 넷의 `rc`와 `out`. `noexec`의 `rc`가 126이고 `Permission denied`인가 —
  M1의 사전 확인이 그 경우를 미리 잡는다는 것의 근거다.
- 4: `LIBS` · `VERSION` · `TEST` 넷(`bare` · `key` · `user` · `rundir`)의 rc와 에러 문구,
  `FPR`, `LISTEN`이 1인가.
- 5: `SCAN`의 지문이 `FPR`과 같은가. `LOGIN good`의 rc가 0, `bad`가 255이고
  `Permission denied (publickey)`인가. `perm` · `unperm`의 rc. `log`의 `SSHD` 줄 중
  `Authentication refused: bad ownership or modes` 같은 줄이 있나.
- 6: `LOGIN good`의 `out` — `$0` · `$SHELL` · `TERM` · `PATH` · uid. `PTY` 둘 — 없는
  `TERM`에서 `less`가 경고를 내나, `rc`가 무엇인가.

- [ ] Step 2: `TEST rundir`가 0이 아니면

에러 문구가 가리키는 것을 `need` 단계의 `t rundir` 앞에 더하고 Task 3 Step 3(디스크)부터
다시 한다. 더한 것은 M2가 initrd에 구울 목록이 된다 — 실측에 그대로 적는다.

## Task 6 — 읽는 법과 판단

- 측정 1 — 새 라이브러리의 합이 수 MB 안팎이면 M2가 그대로 넣는다. 훨씬 크면(예:
  Kerberos 계열이 대부분) design 위험 1대로 사용자에게 먼저 알린다. 대안은 그때
  고른다(예: 다른 빌드의 sshd). M1은 sshd와 무관하므로 이 판단이 M1을 막지 않는다.
- 측정 2 — `sif` · `symlink`가 되면 M1 체인의 부팅 A가 `debugfs`만으로 심는다.
  `mkfs -d`가 모드를 따르므로 둘 중 무엇을 쓸지는 M1 plan이 정한다.
- 측정 3 — `noexec`가 mount에 없고 `hello` · `execd` · `link`가 `rc=0`이면 결정 2가
  그대로 선다. `noexec`의 실패 모양이 M1 사전 확인의 로그 문구를 정한다.
- 측정 4 — `TEST`의 단계별 에러가 M2가 initrd에 구울 것(privsep 사용자 줄 ·
  `/run/sshd` · 그 밖)의 목록이다.
- 측정 5 — `good` 0 · `bad` 255면 결정 6이 선다. StrictModes의 결과가 가이드의 권한
  안내(`chmod 700 /config/ssh`)를 정한다.
- 측정 6 — `$0`이 bash이고 `TERM`이 클라이언트 것이면 비목표 7(로그인 셸이
  `tars.conf`를 안 따른다)이 그대로 남는다. 없는 `TERM`에서 `less`가 깨지면 M2
  가이드에 `TERM=xterm-256color ssh …`를 적을지, 무엇을 할지를 사용자와 정한다.

## Task 7 — design에 실측을 적고 커밋한다

- [ ] Step 1: design에 "SV-M0이 실행으로 증명한 것" 절을 더한다

`docs/specs/2026-09-27-tars-boot-services-design.md`의 "위험" 절 뒤에 FW
design의 실측 절과 같은 모양으로 "실측 1 — …"부터 번호를 매겨 적는다. 로그 줄은
원문 그대로, 해석은 그 아래에 둔다. Task 6의 판단과 M1이 넘겨받을 것도 적는다.
`Status:` 줄을 "M0 끝났다"로 고친다.

- [ ] Step 2: 확인하고 커밋한다

```bash
git status --short
git diff --stat
git add docs/specs/2026-09-27-tars-boot-services-design.md \
        docs/plans/2026-09-27-tars-boot-services-sv-m0.md
git commit -m "Measure SV-M0: sshd cost, exec from /config, and what sshd needs"
```

기대: 저장소의 코드 파일이 목록에 없다.

## 이 milestone이 끝난 자리

커밋은 plan과 design(실측 절)뿐이다. 커널 · `init` · initrd · 체인은 그대로다.
다음은 SV-M1의 plan이고, 그 plan은 이 실측을 입력으로 쓴다.
