# BH-M0 — 게스트에서 재고, 컨테이너 값을 옮겨도 되는지 본다

Design: `docs/superpowers/specs/2026-09-12-tars-bash-history-durability-design.md`

착수 전 실측 여섯은 전부 `tars-devcontainer`(arm64, bash 5.2.37)에서 잰
값이다. 게스트는 같은 Debian trixie 스냅샷의 amd64 패키지를 쓰지만 조건이
하나 다르다 — `/etc`에 `passwd`와 `group`뿐이라 `SYS_BASHRC`가 없다. 컨테이너
측정은 그 조건을 손으로 흉내 냈고(`: > /etc/bash.bashrc`), 흉내가 맞았는지를
게스트에서 본다.

그리고 고치기 전의 값을 손에 쥔다. SD가 zsh에 대해 실측 14로 한 일이다 —
"고친 뒤에 남는다"만 재면 고치기 전에도 남았을 가능성이 안 갈린다.

## 이 milestone이 재는 것 셋

| | 재는 것 | 기대 | 어긋나면 |
|---|---|---|---|
| 실측 7 | 게스트 bash가 `/etc/bash.bashrc`를 SYS_BASHRC로 찾는가, 그리고 그 파일이 없는가 | 찾지만 없다 | design 실측 1·2를 고친다 |
| 실측 8 | `shell=bash` 게스트에서 전원 버튼이 콘솔 셸의 히스토리를 지우는가 | 콘솔 0 · 화면 0 | 콘솔이 남으면 이 서브프로젝트의 전제가 없다 |
| 실측 9 | 게스트 zoxide(amd64 0.9.7)가 `PROMPT_COMMAND`를 앞에 붙이는가 | design 실측 6과 같은 두 줄 | 결정 3의 순서 근거를 다시 쓴다 |

실측 8의 기대가 SD와 다르다. zsh는 화면 셸이 SIGHUP을 받아 우연히 남았는데
(SD 실측 14 — 콘솔 0, 화면 1), bash는 SIGHUP에서도 안 쓴다(SD 실측 7).
그래서 bash는 둘 다 0일 것으로 본다. 화면 셸이 1로 나오면 SD 실측 7이 게스트
조건에서 틀렸다는 뜻이므로 그쪽을 먼저 조사한다.

## Task 0: 하네스를 준비한다

Files: 호스트의 `/tmp/bh_guest.sh`(저장소에 안 넣는다)

SD-M0 Task 6의 스크립트를 그대로 쓴다. 고치는 것은 셋이다.

1. `shell=zsh`가 아니라 `shell=bash`를 쓴다.
2. 마커를 `bhconsolemarker`·`bhscreenmarker`로 바꾸고, 읽는 파일을
   `/config/bash_history`로 바꾼다.
3. 공백 키를 `spc`로 친다. SD-M0의 그 스크립트가 `space`로 한 회차를 버렸고,
   증상이 에러가 아니라 글자가 붙어 나오는 것이었다(HANDOFF 실측 6).

포트는 45492를 쓴다. 체인들이 45455~45471을 쓰고 SD-M0이 45491을 썼다.

- [x] Step 1: 스크립트를 쓴다

```bash
#!/usr/bin/env bash
# BH-M0 실측 7·8·9 — 게스트에서 한 번에 잰다.
#
# 마커에 밑줄을 안 쓴다. `_`는 QEMU의 키 이름이 아니라 `shift-minus`이고,
# `sendkey`의 키 이름은 전부 소문자다.
set -uo pipefail
REPO=/workspace
PORT=45492
OUT=/tmp/bhm0
rm -rf $OUT; mkdir -p $OUT

say() { printf '\n=== %s\n' "$1"; }

say "build"
(cd $REPO/kernel && ./build.sh) >/dev/null || exit 1
(cd $REPO/init && zig build) || exit 1
(cd $REPO/terminal && ./prepare.sh) >/dev/null || exit 1
(cd $REPO/kernel && ./make_initrd.sh) >/dev/null || exit 1
bash $REPO/config/make_disk.sh

# boot <n> <marker> — 콘솔 fifo로 글자를 넣을 수 있는 부팅 하나.
#   fd 8 = 콘솔 셸에 넣는 fifo, fd 3 = QEMU monitor
boot() {
  local n=$1 marker=$2
  local log=$OUT/boot$n.log fifo=$OUT/in$n
  mkfifo $fifo
  exec 8<>$fifo
  ( qemu-system-x86_64 -m 512 \
      -kernel $REPO/kernel/build/arch/x86/boot/bzImage \
      -initrd $REPO/kernel/initrd.cpio \
      -append "console=ttyS0" \
      -vga none -device virtio-gpu-pci \
      -drive file=$REPO/out/config.img,if=virtio,format=raw \
      -display none \
      -serial stdio \
      -monitor tcp:127.0.0.1:${PORT},server,nowait \
      -no-reboot <&8 > $log 2>&1 ) &
  QEMU_PID=$!
  local i
  for i in $(seq 1 120); do
    grep -aq "$marker" $log && return 0
    kill -0 $QEMU_PID 2>/dev/null || return 1
    sleep 1
  done
  return 1
}

mon() { # monitor 한 줄
  exec 3<>/dev/tcp/127.0.0.1/${PORT}
  printf '%s\n' "$1" >&3
  sleep 0.3
  exec 3>&-
}

say "boot 1 — make the machine bash"
boot 1 "started console shell" || { echo "FAIL: boot 1 never started a shell"; exit 1; }
printf 'echo shell=bash > /config/tars.conf\n' >&8
sleep 2
printf 'cat /config/tars.conf\n' >&8
sleep 2
grep -a "shell=bash" $OUT/boot1.log | tail -2
kill $QEMU_PID 2>/dev/null; wait $QEMU_PID 2>/dev/null; exec 8>&-

say "boot 2 — measure 7 and 9, type into both shells, then press the power button"
boot 2 "started console shell" || { echo "FAIL: boot 2 never started a shell"; exit 1; }
grep -a "tars-init: config shell=bash" $OUT/boot2.log || echo "WARN: not bash?"

# ── 실측 7 — /etc에 무엇이 있고, bash가 그 경로를 정말로 읽는가 ──────
printf 'ls -a /etc\n' >&8
sleep 2
printf 'echo BHSYSRC=$(test -e /etc/bash.bashrc && echo yes || echo no)\n' >&8
sleep 2
# 있으면 읽는가. 파일을 만들어 두고 중첩 bash를 띄운다. /etc는 tmpfs라
# 이 부팅에서만 산다 — 다음 부팅에 안 따라간다.
printf 'echo "echo BHSYSRCWASREAD" > /etc/bash.bashrc\n' >&8
sleep 1
printf 'bash -c true; bash -i -c true\n' >&8
sleep 3

# ── 실측 9 — 게스트 zoxide가 PROMPT_COMMAND를 어떻게 쓰는가 ──────────
printf 'zoxide --version\n' >&8
sleep 2
printf 'zoxide init bash | grep -n PROMPT_COMMAND\n' >&8
sleep 3

# ── 실측 8 — 두 셸에 각각 친다 ──────────────────────────────────────
printf 'echo bhconsolemarker\n' >&8
sleep 2
for k in e c h o spc b h s c r e e n m a r k e r ret; do
  mon "sendkey $k"
done
sleep 2

# 전원 버튼. ACPI → PID 1의 종료 경로(SIGTERM → 3초 → SIGKILL)
mon "system_powerdown"
for i in $(seq 1 30); do
  kill -0 $QEMU_PID 2>/dev/null || break
  sleep 1
done
grep -aE "sent SIGTERM|grace period expired|sent SIGKILL|calling reboot" $OUT/boot2.log
kill $QEMU_PID 2>/dev/null; wait $QEMU_PID 2>/dev/null; exec 8>&-

say "boot 3 — read the history file back"
boot 3 "started console shell" || { echo "FAIL: boot 3 never started a shell"; exit 1; }
printf 'echo BHFILE=$(test -e /config/bash_history && echo yes || echo no)\n' >&8
sleep 2
printf 'cat /config/bash_history\n' >&8
sleep 3
printf 'echo BHCON=$(grep -c bhconsolemarker /config/bash_history)\n' >&8
sleep 2
printf 'echo BHSCR=$(grep -c bhscreenmarker /config/bash_history)\n' >&8
sleep 2
kill $QEMU_PID 2>/dev/null; wait $QEMU_PID 2>/dev/null; exec 8>&-

say "verdict"
grep -a "BHSYSRC\|BHSYSRCWASREAD\|BHFILE\|BHCON=\|BHSCR=" $OUT/boot2.log $OUT/boot3.log
```

- [x] Step 2: 돌린다

`Write`로 호스트의 `/tmp/bh_guest.sh`를 만든 뒤 마운트한다. 출력은 파일로
받는다 — 파이프를 거치면 종료 코드가 `tail`의 것이 되고 진행 상황도 안 보인다.

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/bh_guest.sh:/tmp/bh_guest.sh:ro \
  -w /workspace tars-devcontainer bash /tmp/bh_guest.sh > /tmp/bhm0.log 2>&1
```

빌드 때문에 5분 안쪽으로 본다. 커널은 입력이 안 바뀌었으면 `skipping make`로
지나간다(GL-M1).

- [x] Step 3: 안 돌면 가른다

| 증상 | 먼저 볼 것 |
|---|---|
| 아무 말 없이 멈춘다 | fifo를 `exec 8<>`로 열었는가(CC-M0) |
| 콘솔에 친 글자가 안 보인다 | boot 2의 셸이 bash인가. boot 1의 `grep`이 답한다 |
| `sendkey` 글자가 붙어 나온다 | 공백을 `spc`로 쳤는가 |
| monitor 연결이 거부된다 | 45492가 안 쓰이는 번호인가 |

두 번 고쳐도 안 되면 멈추고 사용자에게 알린다.

## Task 1: 실측 7을 판정한다

- [x] Step 1: `ls -a /etc`의 출력에 무엇이 있는지 센다

기대는 `.`·`..`·`passwd`·`group` 넷이다. 다른 것이 있으면
`kernel/make_initrd.sh`가 우리가 안 읽은 자리에서 무언가를 더 넣고 있다는
뜻이므로 그 자리를 찾는다.

- [x] Step 2: `BHSYSRC=no`인지 본다

`no`이면 게스트에 그 파일이 없다 — design 실측 1의 게스트 확인이다.

- [x] Step 3: `BHSYSRCWASREAD`가 한 번만 찍혔는지 본다

파일을 만든 뒤 비대화형(`bash -c true`)과 대화형(`bash -i -c true`) 둘을
띄운다. bash가 `SYS_BASHRC`를 읽는 것은 대화형일 때뿐이므로 한 번만 찍혀야
한다.

두 번 찍히면 이 게스트의 bash가 비대화형에서도 읽는다는 뜻이고, 그러면
design 실측 5의 대비("`bash -c`는 `PROMPT_COMMAND`를 실행하지 않는다")를
다시 잰다. 0번 찍히면 `SYS_BASHRC` 경로가 `/etc/bash.bashrc`가 아니므로
게스트 bash 바이너리에서 그 문자열을 찾는다.

## Task 2: 실측 8을 판정한다

- [x] Step 1: 전원 버튼이 진짜 종료 경로를 밟았는지 먼저 본다

`sent SIGTERM` · `grace period expired` · `sent SIGKILL` · `calling reboot`가
로그에 있어야 한다. 없으면 셸의 히스토리를 논하기 전에 종료가 안 일어난
것이다.

- [x] Step 2: 두 마커가 실제로 쳐졌는지 본다

`boot2.log`에서 `bhconsolemarker`와 `bhscreenmarker`의 에코를 찾는다.
"기록이 없다"를 "잃었다"로 읽으려면 먼저 "쳐졌다"가 있어야 한다 —
HANDOFF의 "시도했으나 안 되는 접근"이 이 순서를 못 박고 있고, SD-M0이 첫
회차를 그 상태로 버렸다.

화면 셸의 마커는 시리얼 로그가 아니라 `terminal: key>` 줄로 확인한다.
화면 셸의 출력은 프레임버퍼로 가지 시리얼로 안 온다.

- [x] Step 3: `BHFILE`·`BHCON`·`BHSCR`을 읽는다

기대는 셋이다. 셋 중 어느 것이 나오는지가 이 서브프로젝트의 크기를 정한다.

| `BHFILE` | `BHCON` | `BHSCR` | 뜻 |
|---|---|---|---|
| `no` | (없음) | (없음) | 파일이 아예 안 생긴다. 고칠 것이 가장 크다 |
| `yes` | 0 | 0 | 둘 다 잃는다. design의 예상이다 |
| `yes` | 0 | 1 | zsh와 같은 모양. SD 실측 7을 게스트에서 다시 잰다 |
| `yes` | 1 | — | 전제가 없다. 이 서브프로젝트를 닫는다 |

`BHFILE=no`가 나올 가능성이 실제로 있다. bash는 `exit`에서만 쓰는데
(SD 실측 7) 이 부팅에서 어느 셸도 `exit`을 안 했다. 그러면 SD-M2가
`pos1` 대신 `neg0`에서 죽은 것과 같은 모양이 된다 — 고친 것의 크기가
"늦게 쓴다"가 아니라 "파일이 없다"인 자리다.

## Task 3: 실측 9를 판정한다

- [x] Step 1: `zoxide --version`이 0.9.7인지 본다

컨테이너에 설치한 arm64와 같은 버전이어야 design 실측 6을 그대로 옮길 수
있다. 다르면 그 버전의 출력으로 실측 6을 다시 적는다.

- [x] Step 2: `grep -n PROMPT_COMMAND`의 출력이 design 실측 6과 같은지 본다

기대는 세 줄이고, 그중 대입은 하나다.

```
PROMPT_COMMAND="__zoxide_hook;${PROMPT_COMMAND#;}"
```

기존 값을 보존하는 형태인 것이 결정 3의 근거 전부다. 만약 게스트 버전이
`PROMPT_COMMAND="__zoxide_hook"`처럼 보존을 안 하면 순서를 어떻게 해도
한쪽이 죽으므로, 결정 3을 "우리 줄을 훅 뒤에 두고 zoxide를 우리가 감싼다"로
다시 쓴다.

## Task 4: 실측 셋을 design에 적고 커밋한다

- [x] Step 1: design에 "BH-M0이 실행으로 증명한 것" 절을 더한다

실측 7·8·9를 적는다. 값이 착수 전 실측과 어긋나면 어긋난 것을 적고, 그
어긋남이 어느 결정을 바꾸는지도 함께 적는다.

- [x] Step 2: `Status:` 줄을 고친다

"M0을 했다. M1이 다음이다"로 바꾼다.

- [x] Step 3: 커밋한다

측정 하네스는 저장소에 안 넣는다. 다시 필요하면 이 plan의 Task 0에 글자
그대로 있다.
