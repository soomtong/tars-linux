# BB-M0 — `shell=bash` 부팅을 한 번 띄워서 잰다

design: `docs/superpowers/specs/2026-09-12-tars-bash-boot-design.md`

게이트에 9차를 세우기 전에, `shell=bash`로 뜬 게스트를 한 번 손으로 띄워서
일곱을 잰다. 이 순서를 지키는 이유는 BH가 하루에 세 번 걸린 함정이다 —
컨테이너에서 잰 셸 동작을 게스트 값으로 읽으면 에러 없이 틀린 값이 나온다
(`docs/decisions/project_measuring_shells.md`).

## 재는 방법 — 디스크를 미리 구워서 부팅 하나로 끝낸다

체인은 1차에서 사람이 `tars.conf`를 고치고 2차가 그것을 읽는 두 부팅으로
`shell`을 바꾼다. 측정에서는 그럴 필요가 없다. `mkfs.ext2`의 `-d`가 디렉터리
하나를 그대로 이미지에 담아 주므로, `shell=bash` 한 줄이 든 `tars.conf`를
미리 넣고 한 번만 부팅한다.

씨앗 rc는 이 부팅의 init이 깐다(`O_EXCL`). 그래서 읽히는 bashrc가
`rcSeed()`의 내용 그 자체이고, 사람이 손댄 줄이 한 줄도 없다.

디스크가 새것이라 얻는 것이 하나 더 있다. `/config/bash_history`와 zoxide DB가
비어 있으므로 design 확인 5·6의 함정이 이 측정에는 아예 없다 — 판정 글자를
만들 수 있는 것이 우리가 보려는 것 하나뿐이다.

monitor 포트는 45464를 쓴다. 쓰이는 번호가 45455~45463과 45471이라 겹치지
않고, 측정이 체인과 같은 시각에 돌아도 엉뚱한 게스트에 키를 보내지 않는다.

## Task 0 — 하네스를 호스트에서 만들고 컨테이너에 읽기 전용으로 물린다

heredoc으로 컨테이너 안에서 만들지 않는다. 중첩 따옴표에서 `$LOG` 같은 것이
호스트 bash에 먼저 먹힌다(SD-M0이 그 함정을 적어 두었다). 호스트에서 `Write`로
만들고 `-v`로 마운트한다.

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/bb_m0.sh:/tmp/bb_m0.sh:ro \
  -w /workspace tars-devcontainer bash /tmp/bb_m0.sh > /tmp/bb_m0.log 2>&1
```

## Task 1 — 하네스 전문

`/tmp/bb_m0.sh`. 빌드 넷 · 디스크 굽기 · 부팅 하나 · 타이핑 넷.

```bash
#!/usr/bin/env bash
set -uo pipefail

cd /workspace/config
source ../gate_lib.sh

MONITOR_PORT=45464
LOG="$(mktemp)"
echo "serial log: $LOG"

(cd ../kernel && ./build.sh) || { echo "FAIL: kernel build"; exit 1; }
(cd ../init && zig build) || { echo "FAIL: init build"; exit 1; }
(cd ../terminal && ./prepare.sh) || { echo "FAIL: terminal build"; exit 1; }
(cd ../kernel && ./make_initrd.sh) || { echo "FAIL: initrd build"; exit 1; }

# tars.conf를 미리 담은 디스크. make_disk.sh와 같은 값에 -d만 더한다.
rm -rf /tmp/bbseed && mkdir -p /tmp/bbseed
printf 'shell=bash\n' > /tmp/bbseed/tars.conf
mkdir -p ../out && rm -f ../out/config.img
truncate -s 16M ../out/config.img
mkfs.ext2 -F -q -m 0 -L tars-config -d /tmp/bbseed ../out/config.img

qemu-system-x86_64 \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -drive file=/workspace/out/config.img,if=virtio,format=raw \
  -display none \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

for _ in $(seq 1 120); do
  if grep -q "tars-init: started console shell" "$LOG"; then break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
for _ in $(seq 1 120); do
  if grep -q "terminal: screen>" "$LOG"; then break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done

for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then break; fi
  sleep 0.5
done

echo "=== 측정 5: bash 프롬프트가 화면에 어떤 글자로 나오는가 ==="
grep -a "terminal: screen>" "$LOG" | tail -2

echo "=== 측정 6: bash에서 zoxide 훅이 걸리는가 ==="
type_keys c d spc slash u s r slash s h a r e slash dot dot slash b i n ret
type_keys c d spc slash ret
type_keys z spc b i n ret
type_keys p w d ret
if wait_for_screen '\| /usr/bin'; then
  echo "measure 6: OK — z bin landed on /usr/bin"
else
  echo "measure 6: NO — z did not move"
fi
grep -a "terminal: screen>" "$LOG" | tail -2

echo "=== 측정 8: production env로 히스토리가 명령마다 써지는가 ==="
type_keys b p r o d m a r k equal 1 ret
type_keys e c h o spc b p r o d shift-4 shift-9 \
          g r e p spc minus c x spc b p r o d m a r k equal 1 spc \
          slash c o n f i g slash b a s h shift-minus h i s t o r y shift-0 ret
if wait_for_screen 'bprod1'; then
  echo "measure 8: OK — the line was on disk while the session was alive"
else
  echo "measure 8: NO"
fi
grep -a "terminal: screen>" "$LOG" | tail -2

echo "=== 측정 7: fzf 통합이 정의하는 이름 (그리고 파이프 키) ==="
type_keys d e c l a r e spc minus shift-f spc shift-backslash spc g r e p spc f z f ret
sleep 3
grep -a "terminal: screen>" "$LOG" | tail -3

exec 3<&-
exec 3>&-
kill "$QEMU_PID" 2>/dev/null
wait "$QEMU_PID" 2>/dev/null

echo "=== 측정 1~4: init 로그 전문 ==="
grep -a 'tars-init:' "$LOG"
echo "=== 씨앗이 조용한가 — 의심스러운 줄 ==="
grep -anE 'No such file|command not found|rror|warning' "$LOG" | head -20
cp "$LOG" /workspace/out/bb_m0_serial.log
echo "serial log copied to out/bb_m0_serial.log"
```

## 재는 것 일곱 (design BB-M0과 같은 번호)

1. init이 `config shell=bash`를 찍고 폴백 로그(`is not executable`)가 없는가.
2. env 블록이 `HISTFILE=/config/bash_history` · `HISTSIZE=5000` 둘이고
   `SAVEHIST`가 없는가.
3. `started console shell`과 `started terminal`이 각각 하나이고 `times fast`와
   `giving up on`이 없는가.
4. 씨앗 bashrc가 화면과 로그에 아무것도 안 찍는가.
5. 최상위 bash의 프롬프트가 화면에 어떤 글자로 나오는가(9차의 대기에 쓴다).
6. `cd /usr/share/../bin` → `cd /` → `z bin` → `pwd`가 `/usr/bin`을 찍는가.
7. `declare -F | grep fzf`가 무엇을 찍는가. 겸해서 `shift-backslash`가
   게스트에 `|`로 닿는지도 본다 — 이 체인이 파이프를 타이핑한 적이 없다.

여덟째를 덤으로 잰다. production env(손으로 `HISTFILE`을 안 맞춘 상태)에서
히스토리가 명령마다 써지는가 — BH-M2의 중첩 판정이 env를 손으로 맞춘 자리이고,
9차가 그것을 안 하는 것이 design 결정 5다.

## 실패했을 때 어디를 보는가

부팅이 아예 안 뜨면 `out/bb_m0_serial.log`의 맨 끝을 본다. `-m 512`는
`gate_lib.sh`에서 오므로(`GUEST_MEM`) 그 자리는 의심하지 않아도 된다.

`mkfs.ext2 -d`가 없는 옵션이라고 나오면 e2fsprogs가 1.43보다 낮은 것이다.
그때는 측정을 두 부팅으로 바꾼다 — 1차에서 체인의 `EDIT_KEYS` 모양으로
`echo shell=bash > /config/tars.conf`를 치고 2차를 띄운다.

키가 게스트에 안 닿으면 `type_keys`가 아니라 `sendkey` 이름을 의심한다.
전부 소문자이고, 대문자는 `shift-<글자>`, `$`는 `shift-4`, `(`는 `shift-9`,
`)`는 `shift-0`, `_`는 `shift-minus`다.
