# SD-M0 Implementation Plan — 남은 여섯을 잰다

Design: `docs/superpowers/specs/2026-09-12-tars-shell-history-durability-design.md`
Date: 2026-09-12

## 이 milestone이 하는 일

코드를 한 줄도 안 고친다. 실측 9~14를 재서 design에 적는다.

design의 실측 1~8은 착수 전에 이미 쟀다(그 측정이 이 서브프로젝트의 전제를
뒤집었다). 남은 여섯은 *"그 줄을 저장소에 넣어도 되는가"*와 *"게이트가 그것을
어떻게 보는가"*에 답한다.

| | 무엇 | 무엇이 걸려 있나 |
|---|---|---|
| 실측 9 | 씨앗 줄이 부팅할 때 0바이트인가 | `expectQuietSeed` 허용 목록에 넣을 근거(SD-M1) |
| 실측 10 | `fc -W`가 다른 세션이 써 둔 줄을 지우는가 | 7차의 그 명령을 남길지 뺄지(SD-M2) |
| 실측 11 | `unsetopt` 음성 대조군이 성립하는가 | 결정 5의 검사 모양(SD-M2) |
| 실측 12 | 중첩 zsh가 화면에 무엇을 찍는가 | `wait_for_screen`이 볼 글자(SD-M2, 위험 2) |
| 실측 13 | 쓰기가 추가인가 재작성인가 | 16MiB 디스크에 얹어도 되는가 |
| 실측 14 | 실기 경로에서 두 셸의 운명 | design의 가장 중요한 표가 추론인가 실측인가 |

## 이 milestone을 지배하는 사실 셋

### 1. 대화형 셸이 아니면 재려는 것을 아예 안 한다

`INC_APPEND_HISTORY`는 명령이 한 줄로 받아들여지는 자리에서 작동한다.
`zsh -c`로는 그 자리를 안 지나간다. 그래서 모든 측정이 PTY 위의 대화형
셸이어야 하고, 하네스가 `script -qfc "zsh -i"` + fifo다.

예외가 실측 9 하나다. 그것이 재는 것은 *"rc를 읽을 때 무엇을 찍나"*이므로
`zsh -i -c 'true'`로 충분하고, 오히려 프롬프트가 안 찍혀서 세기 쉽다.

### 2. 신호를 누구에게 보내는지가 결과를 바꾼다

design 실측 3이 그 자리다. 셸에게 SIGTERM을 보내면 아무 일도 안 나고, 셸 위의
PTY 주인에게 보내면 셸이 히스토리를 쓴다. 이 plan의 어떤 측정에서든
`pgrep`으로 고른 PID가 무엇인지 먼저 확인하고 적는다 — SM 실측 34가 이 자리에서
틀렸다.

### 3. fifo는 `exec 4<>`로 연다

CC-M0의 규칙이다. 쓰기 전용(`exec 4>`)으로 열면 읽는 쪽을 기다리며 멈추고,
증상이 에러가 아니라 아무 말 없는 정지다.

## Task 0: 측정 컨테이너를 세운다

Files: 없음(측정만)

- [ ] Step 1: 컨테이너를 띄우고 셸 둘을 넣는다

이 세션에서 이미 한 번 했고 `tars-measure`라는 이름으로 떠 있다. 끊겼으면
다시 만든다.

```bash
docker rm -f tars-measure 2>/dev/null
docker run -d --name tars-measure tars-devcontainer sleep 7200
docker exec tars-measure bash -c 'apt-get update -qq && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq zsh fish >/dev/null 2>&1; \
  zsh --version; fish --version'
```

기대 출력:

```
zsh 5.9 (aarch64-unknown-linux-gnu)
fish, version 4.0.2
```

devcontainer에는 zsh도 fish도 없다(bash 5.2.37만 있다). 게스트의 amd64와 같은
Debian trixie 스냅샷에서 받으므로 버전이 같고, 히스토리의 성질은 아키텍처에
안 갈리는 자리다. 그래도 게스트에서 한 번 보는 것이 실측 14다.

- [ ] Step 2: 스크립트를 넣는 방법을 정해 둔다

호스트에서 `Write`로 `/tmp`에 쓰고 `docker cp`로 넣는다. 셸 heredoc으로
컨테이너에 스크립트를 만들지 않는다 — 중첩된 따옴표에서 `$HISTFILE` 같은
것이 호스트 bash에 먼저 먹힌다(이 세션에서 한 번 당했다: `HISTFILE: unbound
variable`).

```bash
docker cp /tmp/sd_quiet.sh tars-measure:/tmp/
docker exec tars-measure bash /tmp/sd_quiet.sh
```

## Task 1: 실측 9 — 씨앗 줄이 조용한가

Files: 없음(측정만). 호스트에 `/tmp/sd_quiet.sh`를 만든다.

- [ ] Step 1: 스크립트를 쓴다

```bash
#!/bin/bash
# 실측 9: rc의 한 줄이 기동할 때 무엇을 찍는가.
set -u
measure() { # tag rc_body
  local tag=$1 rc=$2
  local w=/tmp/q_$tag; rm -rf $w; mkdir -p $w
  printf '%s' "$rc" > $w/.zshrc
  env -i HOME=$w ZDOTDIR=$w TERM=xterm PATH=/usr/bin:/bin \
    HISTFILE=$w/H HISTSIZE=50 SAVEHIST=50 \
    zsh -i -c 'true' > $w/out 2> $w/err
  printf '%-8s stdout=%-4s stderr=%-4s\n' \
    "$tag" "$(wc -c < $w/out)" "$(wc -c < $w/err)"
  if [ -s $w/err ]; then sed 's/^/    stderr: /' $w/err; fi
  if [ -s $w/out ]; then sed 's/^/    stdout: /' $w/out; fi
}
measure empty  '# nothing
'
measure good   'setopt INC_APPEND_HISTORY
'
measure typo   'setopt INC_APPEND_HISTORYY
'
```

세 번째가 오타다. 그것을 함께 재는 이유는 SD-M1에서 이 줄을 두 벌로 두기
때문이다(결정 3) — 두 벌이 어긋났을 때 증상이 어떻게 생기는지 알아야 한다.

- [ ] Step 2: 돌린다

```bash
docker cp /tmp/sd_quiet.sh tars-measure:/tmp/ && \
  docker exec tars-measure bash /tmp/sd_quiet.sh
```

기대: `empty`와 `good`이 둘 다 `stdout=0 stderr=0`. `typo`는 stderr에 한 줄이
나올 것으로 본다(`setopt: no such option`).

- [ ] Step 3: 판정한다

`good`이 0바이트가 아니면 이 서브프로젝트의 처방이 씨앗에 들어갈 수 없다
(씨앗의 규칙이 *"아무것도 찍지 않는다"*이고 설정 디스크를 붙이는 다섯 체인이
화면 좌표로 판정한다). 그때는 design 결정 2를 다시 열어야 하므로 그 자리에서
멈추고 사용자에게 알린다.

`typo`의 출력 크기를 적어 둔다 — SD-M1의 두 벌 규율이 막는 것이 그 바이트다.

## Task 2: 실측 10 — `fc -W`가 다른 세션의 줄을 지우는가

Files: 없음(측정만). 호스트에 `/tmp/sd_fcw.sh`를 만든다.

- [ ] Step 1: 스크립트를 쓴다

```bash
#!/bin/bash
# 실측 10: INC_APPEND_HISTORY가 켜진 기계에서 `fc -W`가 무엇을 하나.
# 7차 부팅의 마지막 명령이 이것이고, 8차가 그 결과를 읽는다.
set -u
w=/tmp/fcw; rm -rf $w; mkdir -p $w
printf 'setopt INC_APPEND_HISTORY\n' > $w/.zshrc
mkfifo $w/inA $w/inB
exec 4<>$w/inA
exec 5<>$w/inB
start() { # fifo out
  env -i HOME=$w ZDOTDIR=$w TERM=xterm PATH=/usr/bin:/bin \
    HISTFILE=$w/H HISTSIZE=50 SAVEHIST=50 \
    script -qfc "zsh -i" /dev/null <"$1" >"$2" 2>&1 &
  echo $!
}
show() { printf '%-30s ' "$1"; if [ -f $w/H ]; then printf '[%s]\n' "$(tr '\n' '/' < $w/H)"; else printf 'NO FILE\n'; fi; }

pidA=$(start $w/inA $w/outA); sleep 1.5
printf 'echo a_one\n' >&4; sleep 1
show "A typed a_one"

pidB=$(start $w/inB $w/outB); sleep 1.5
printf 'echo b_one\n' >&5; sleep 1
show "B typed b_one"

printf 'fc -W\n' >&4; sleep 1
show "A ran fc -W"
printf 'verdict: b_one survived fc -W? %s\n' "$(grep -c '^echo b_one$' $w/H)"

printf 'exit\n' >&5; printf 'exit\n' >&4
wait $pidA 2>/dev/null; wait $pidB 2>/dev/null
show "both exited"
```

- [ ] Step 2: 돌린다

```bash
docker cp /tmp/sd_fcw.sh tars-measure:/tmp/ && \
  docker exec tars-measure bash /tmp/sd_fcw.sh
```

예상은 `b_one survived fc -W? 0`이다. `fc -W`는 메모리의 목록으로 파일을 다시
쓰고, A의 목록에는 B가 친 것이 없다. 예상이 맞든 틀리든 그것이 SD-M2의 모양을
정한다.

- [ ] Step 3: 두 갈래의 처방을 적어 둔다

| 결과 | SD-M2가 할 일 |
|---|---|
| `0`(지운다) | 7차에서 `fc -W`를 뺀다. 옵션이 켜지면 그 명령이 필요 없다 — 칠 때 이미 써지므로 8차가 읽을 것이 거기 있다. 빼면 SM-M2의 우회가 없어진다 |
| `1`(안 지운다) | 7차를 그대로 두고, 음성·양성 판정을 `fc -W` 앞에 둔다 |

어느 쪽이든 8차의 판정 글자(`the history list carries a command only the
seventh boot typed`)는 안 건드린다.

## Task 3: 실측 11 — 음성 대조군이 성립하는가

Files: 없음(측정만). 호스트에 `/tmp/sd_neg.sh`를 만든다.

중첩을 게이트와 같은 모양으로 만든다 — 세션 A 안에서 `zsh`를 쳐서 자식
세션을 띄운다. 둘 다 rc를 읽으므로 production과 같고, 다른 것은 `unsetopt`
한 줄뿐이다(결정 5).

- [ ] Step 1: 스크립트를 쓴다

```bash
#!/bin/bash
# 실측 11: rc를 읽은 중첩 세션에서 옵션만 끄면 파일이 안 자라는가.
set -u
w=/tmp/neg; rm -rf $w; mkdir -p $w
printf 'setopt INC_APPEND_HISTORY\n' > $w/.zshrc
mkfifo $w/in
exec 4<>$w/in
env -i HOME=$w ZDOTDIR=$w TERM=xterm PATH=/usr/bin:/bin \
  HISTFILE=$w/H HISTSIZE=50 SAVEHIST=50 \
  script -qfc "zsh -i" /dev/null <$w/in >$w/out 2>&1 &
p=$!
sleep 1.5
size() { if [ -f $w/H ]; then wc -l < $w/H | tr -d ' '; else echo 0; fi; }
step() { printf '%-40s lines=%s\n' "$1" "$(size)"; }

printf 'echo outer_one\n' >&4; sleep 1; step "A typed outer_one"

# ── 음성 — 중첩 세션에서 옵션을 끈다 ────────────────────────────────
printf 'zsh\n' >&4; sleep 1.5; step "nested zsh started"
printf 'unsetopt INC_APPEND_HISTORY\n' >&4; sleep 1; step "nested unsetopt"
printf 'echo neg_one\n' >&4; sleep 1; step "nested typed neg_one (must NOT grow)"
printf 'grep -c neg_one %s\n' "$w/H" >&4; sleep 1
printf 'exit\n' >&4; sleep 1.5; step "nested exited (may grow here — see note)"

# ── 양성 — 중첩 세션이 rc의 옵션을 그대로 쓴다 ──────────────────────
printf 'zsh\n' >&4; sleep 1.5; step "second nested zsh started"
printf 'echo pos_one\n' >&4; sleep 1; step "nested typed pos_one (must grow)"
printf 'grep -c pos_one %s\n' "$w/H" >&4; sleep 1
printf 'exit\n' >&4; sleep 1.5
printf 'exit\n' >&4; wait $p 2>/dev/null

echo "--- file"
cat -n $w/H
echo "--- what the screen showed"
tr -d '\r' < $w/out
```

- [ ] Step 2: 돌린다

```bash
docker cp /tmp/sd_neg.sh tars-measure:/tmp/ && \
  docker exec tars-measure bash /tmp/sd_neg.sh
```

- [ ] Step 3: 판정한다

기대는 둘이다. `nested typed neg_one`에서 줄 수가 안 늘고, `nested typed
pos_one`에서 는다.

음성 세션이 나갈 때를 주의한다. 옵션을 끈 세션도 `exit`에서는 자기 목록을
append하므로(design 실측 3) 그때 `neg_one`이 파일에 들어온다. 그래서 판정
시점은 반드시 *"세션이 살아 있는 동안"*이고, 이것이 SD-M2의 검사가 지켜야 하는
순서다. 측정에서 그 순서가 정말 필요한지를 이 Step이 눈으로 확인한다.

## Task 4: 실측 12 — 중첩 zsh가 화면에 무엇을 찍는가

Files: 없음(측정만). Task 3의 `$w/out`을 쓴다.

- [ ] Step 1: Task 3이 찍은 화면에서 중첩 기동 부분만 본다

```bash
docker exec tars-measure bash -c "tr -d '\r' < /tmp/neg/out | sed -n '1,40p'"
```

- [ ] Step 2: 세 가지를 적는다

1. 중첩 zsh가 기동할 때 찍는 줄이 있는가(없어야 한다 — 씨앗 rc는 조용하다).
2. 프롬프트가 바뀌는가. 게스트의 프롬프트는 `root@(none) ~#` 모양이고,
   중첩 세션의 프롬프트가 그것과 같으면 게이트는 *"몇 번째 프롬프트인가"*를
   셀 수 없다.
3. `exit`으로 돌아왔을 때 화면에 무엇이 남는가.

- [ ] Step 3: SD-M2가 무엇으로 판정할지 고른다

2번이 *"같다"*로 나오면(그럴 것으로 본다) SD-M2의 판정은 프롬프트가 아니라
우리가 만든 글자여야 한다. 7차가 이미 쓰는 방식이다 — 파일을 `grep -c`한
숫자를 화면에 찍고 `wait_for_screen`이 그 숫자를 본다. 고른 글자를 이 Step에
적어 둔다(SM 실측 35가 `wc -l`의 출력 모양을 적어 둔 것과 같은 이유다).

## Task 5: 실측 13 — 쓰기가 추가인가 재작성인가

Files: 없음(측정만). 호스트에 `/tmp/sd_cost.sh`를 만든다.

시간을 재지 않는다. 이 하네스는 키 사이에 `sleep`이 있어서 재는 것이 코드가
아니라 하네스가 된다(RC-M0이 `std.debug.print`로 같은 실수를 했다). 대신
의미가 있는 것을 본다 — 한 명령이 파일에 추가되는가 파일을 다시 쓰는가,
그리고 `SAVEHIST` 경계에서 무슨 일이 나는가.

- [ ] Step 1: 스크립트를 쓴다

```bash
#!/bin/bash
# 실측 13: 한 명령의 쓰기가 추가인가 재작성인가. 그리고 SAVEHIST 경계.
set -u
run() { # tag savehist prefill
  local tag=$1 savehist=$2 prefill=$3
  local w=/tmp/cost_$tag; rm -rf $w; mkdir -p $w
  printf 'setopt INC_APPEND_HISTORY\n' > $w/.zshrc
  seq 1 "$prefill" | sed 's/^/echo seeded_/' > $w/H
  mkfifo $w/in; exec 7<>$w/in
  env -i HOME=$w ZDOTDIR=$w TERM=xterm PATH=/usr/bin:/bin \
    HISTFILE=$w/H HISTSIZE=$savehist SAVEHIST=$savehist \
    script -qfc "zsh -i" /dev/null <$w/in >$w/out 2>&1 &
  local p=$!
  sleep 1.5
  printf '%s prefill=%s savehist=%s\n' "$tag" "$prefill" "$savehist"
  printf '  before  inode=%s lines=%s bytes=%s\n' \
    "$(stat -c %i $w/H)" "$(wc -l < $w/H | tr -d ' ')" "$(stat -c %s $w/H)"
  printf 'echo one_more\n' >&7; sleep 1.5
  printf '  after   inode=%s lines=%s bytes=%s\n' \
    "$(stat -c %i $w/H)" "$(wc -l < $w/H | tr -d ' ')" "$(stat -c %s $w/H)"
  printf '  tail: %s\n' "$(tail -1 $w/H)"
  printf 'exit\n' >&7; wait $p 2>/dev/null
  exec 7>&-
}
run below  5000 100
run at     50   50
run over   50   60
```

- [ ] Step 2: 돌린다

```bash
docker cp /tmp/sd_cost.sh tars-measure:/tmp/ && \
  docker exec tars-measure bash /tmp/sd_cost.sh
```

- [ ] Step 3: 세 줄로 판정한다

1. `below`에서 inode가 같고 줄이 하나 늘면 추가다 — 5,000줄 위에서도 한
   명령의 비용이 한 줄이라는 뜻이고, 16MiB ext2에 얹어도 된다.
2. `at`·`over`에서 inode가 바뀌면 zsh가 그 경계에서 파일을 다시 쓴다.
   그 비용은 `SAVEHIST`에 비례하므로 SM 결정 4의 5,000이 이 자리에서 값을 갖는다.
3. 줄 수가 `savehist`를 넘어 자라면 잘리는 시점이 쓰기가 아니라 다른 데
   있다는 뜻이다. 그때는 `/config`가 차는 경로가 생기므로 적어 둔다
   (design 비목표 9가 *"꽉 찼을 때의 정책은 안 만든다"*인데, 그 전제가
   *"상한이 실제로 걸린다"*다).

## Task 6: 실측 14 — 게스트에서 두 셸의 운명을 본다

Files: 없음(측정만). 호스트에 `/tmp/sd_guest.sh`를 만든다.

이 Task가 이 milestone에서 가장 비싸다(빌드 + 부팅 셋, 5분 안쪽으로 본다).
그리고 design의 가장 중요한 표(실측 4)를 추론에서 실측으로 옮기는 유일한
자리다.

컨테이너가 아니라 devcontainer에서 돌린다 — QEMU와 빌드 도구가 거기 있다.

- [ ] Step 1: 무엇을 보려는지 먼저 적는다

| | 기대 | 근거 |
|---|---|---|
| 화면 셸에 친 명령 | 남는다 | `terminal`이 SIGTERM에 죽고 PTY가 닫혀 셸이 SIGHUP을 받는다 |
| 콘솔 셸에 친 명령 | 사라진다 | `/dev/console`은 닫히지 않아 SIGHUP이 없고, 셸은 SIGTERM을 무시한다 |

둘 중 하나라도 어긋나면 design 실측 4를 고친다. 특히 화면 셸이 *"사라진다"*로
나오면 이 서브프로젝트의 가치가 커지고(두 셸 다 잃는다), 콘솔 셸이
*"남는다"*로 나오면 왜 남는지를 찾아야 한다.

- [ ] Step 2: 스크립트를 쓴다

콘솔 셸에 글자를 넣는 것은 CC-M0의 방법이다 — `-serial stdio`에 fifo를 물리고
`exec 4<>`로 연다. monitor는 tcp로 따로 둔다(`-monitor none`이 필요한 것은
monitor를 stdio에 두려고 할 때다).

```bash
#!/usr/bin/env bash
# 실측 14: 전원 버튼 경로에서 두 셸의 히스토리가 각각 어떻게 되나.
#
# 마커에 밑줄을 안 쓴다. `_`는 QEMU의 키 이름이 아니라 `shift-minus`이고,
# `sendkey`의 키 이름은 전부 소문자다 — 없는 이름은 QEMU가 조용히 버린다.
set -uo pipefail
REPO=/workspace
PORT=45491
OUT=/tmp/sd14
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

say "boot 1 — make the machine zsh"
boot 1 "started console shell" || { echo "FAIL: boot 1 never started a shell"; exit 1; }
printf 'echo shell=zsh > /config/tars.conf\n' >&8
sleep 2
printf 'cat /config/tars.conf\n' >&8
sleep 2
grep -a "shell=zsh" $OUT/boot1.log | tail -2
kill $QEMU_PID 2>/dev/null; wait $QEMU_PID 2>/dev/null; exec 8>&-

say "boot 2 — type into both shells, then press the power button"
boot 2 "started console shell" || { echo "FAIL: boot 2 never started a shell"; exit 1; }
grep -a "tars-init: config shell=zsh" $OUT/boot2.log || echo "WARN: not zsh?"

# 콘솔 셸에 친다
printf 'echo sdconsolemarker\n' >&8
sleep 2

# 화면 셸에 친다 — monitor의 sendkey로 글자를 하나씩 보낸다
for k in e c h o space s d s c r e e n m a r k e r ret; do
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

say "boot 3 — read the file back"
boot 3 "started console shell" || { echo "FAIL: boot 3 never started a shell"; exit 1; }
printf 'cat /config/zsh_history\n' >&8
sleep 3
printf 'grep -c sdconsolemarker /config/zsh_history\n' >&8
sleep 2
printf 'grep -c sdscreenmarker /config/zsh_history\n' >&8
sleep 2
kill $QEMU_PID 2>/dev/null; wait $QEMU_PID 2>/dev/null; exec 8>&-

say "verdict"
grep -a "sdconsolemarker\|sdscreenmarker" $OUT/boot3.log | tail -20
```

- [ ] Step 3: 돌린다

`Write`로 호스트의 `/tmp/sd_guest.sh`를 만든 뒤 그 파일을 마운트한다
(`docker cp`가 아니다 — 이 Task는 `tars-measure`가 아니라 새 devcontainer에서
돈다). 출력을 `| tail`로 자르지 않고 파일로 받는다 — 파이프를 거치면 종료
코드가 `tail`의 것이 되고 진행 상황도 안 보인다.

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/sd_guest.sh:/tmp/sd_guest.sh:ro \
  -w /workspace tars-devcontainer bash /tmp/sd_guest.sh > /tmp/sd14.log 2>&1
tail -60 /tmp/sd14.log
```

빌드 때문에 5분 안쪽으로 본다. 커널은 입력이 안 바뀌었으면 `skipping make`로
지나간다(GL-M1).

- [ ] Step 4: 안 돌면 어디서 막혔는지 가른다

이 스크립트는 이 저장소에서 처음 쓰는 모양이라(`-serial stdio` + fifo를
`config` 쪽 부팅과 섞는다) 한 번에 안 돌 수 있다. 가르는 순서를 미리 적어 둔다.

| 증상 | 먼저 볼 것 |
|---|---|
| 아무 말 없이 멈춘다 | fifo를 `exec 8<>`로 열었는가(CC-M0). `<&8`이 QEMU보다 먼저 열려 있어야 한다 |
| 콘솔에 친 글자가 안 보인다 | 게스트 셸이 zsh인가. boot 1에서 fish였다면 `>` 리다이렉션 문법은 둘 다 같으니 괜찮다 |
| `sendkey`가 화면에 안 닿는다 | 키 이름이 전부 소문자인가. Enter는 `ret`이고 공백은 `space`다 |
| monitor 연결이 거부된다 | 포트 45491이 이 저장소에서 안 쓰이는 번호인가(체인들은 45455~45471을 쓴다) |

두 번 고쳐도 안 되면 멈추고 사용자에게 알린다 — design 실측 4는 추론으로
두고, SD-M2의 게이트 검사가 그 자리를 대신 본다고 적는다.

## Task 7: 실측을 design에 적고 커밋한다

Files:
- Modify: `docs/superpowers/specs/2026-09-12-tars-shell-history-durability-design.md`
- Modify: `HANDOFF.md`

- [ ] Step 1: design의 `## SD-M0이 남겨 둔 여섯` 절을 `## SD-M0이 실행으로 증명한 것`으로 바꾸고 실측 9~14를 각각 쓴다

표와 명령과 출력을 담는다. 숫자만 적지 않는다 — 어떤 명령이 그 숫자를
냈는지가 다음 사람에게 필요하다. 예상과 다른 값이 나온 자리는 예상도 함께
적는다(이 저장소의 실측 절은 전부 그 모양이다).

- [ ] Step 2: 틀린 것이 있으면 design의 결정을 그 자리에서 고친다

실측 10이 `fc -W`를 *"안 지운다"*로 답하면 위험 3의 처방이 바뀌고, 실측 14가
화면 셸도 잃는다고 답하면 실측 4의 표와 한 줄 요약이 바뀐다. 고친 자리마다
무엇이 바뀌었는지 Status 줄에 한 줄 남긴다.

- [ ] Step 3: `HANDOFF.md`를 고친다

"바로 다음에 할 것"을 SD-M1로 바꾸고, 이월 숙제에서 SM이 남긴 첫 항목(위험 3)을
지운다 — 그 항목의 전제가 틀렸다는 것이 이미 design에 있다. 대신 새 이월
숙제를 둘 더한다(bash의 히스토리 · 종료가 늘 3초 걸리는 것).

- [ ] Step 4: 커밋한다

```bash
git add docs/superpowers/specs/2026-09-12-tars-shell-history-durability-design.md \
        docs/superpowers/plans/2026-09-12-tars-shell-history-durability-sd-m0.md \
        HANDOFF.md
git commit -m "Measure what the history option costs and what the gate can see"
```

커밋 전에 `git status`로 `M`과 신규를 가른다. 측정만 하는 milestone이므로
`init/`·`config/`·`terminal/` 아래에 바뀐 파일이 하나도 없어야 한다 — 있으면
하네스가 저장소를 건드린 것이다.

## 이 milestone이 끝났다는 것

실측 9~14가 design에 있고, 그중 넷이 SD-M1·M2의 모양을 정한 것이 문서에
적혀 있다. 코드는 한 줄도 안 바뀌었다(`git diff --stat`이 md만 보여 준다).
