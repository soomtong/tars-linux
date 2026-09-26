# WN-M1 — 드라이버를 켜고, 기존 체인이 조용히 NIC를 갖지 않게 한다

Design: `docs/superpowers/specs/2026-09-26-tars-wired-nic-design.md`(결정 1 · 3, 실측 1 · 5 · 7)
Date: 2026-09-26

## 이 milestone이 하는 일

design 결정 1의 드라이버를 `kernel/.config`에 켜고, 결정 3의 격리를 세운다.

- `.config` — 드라이버 여섯을 켜고, `USB_USBNET`이 `default y`로 끌고 온 아홉 중
  옛 장치용 여섯을 끈다(아래 사실 1).
- QEMU 호출 열여섯 곳에 `-nic none`을 단다.
- `check.sh` 진입 검사에 `require_explicit_nic`를 더한다.
- `net/check.sh` 검사 11을 지운다.

`init`은 한 줄도 안 바꾼다. `eth0` 상수와 ioctl은 M2까지 그대로 둔다. virtio-net이
여전히 `eth0`이므로 `net` 체인의 판정도 그대로 선다.

## 이 milestone을 지배하는 사실 넷

### 1. 아홉 중 셋을 남기고 여섯을 끈다 — 사용자가 골랐다

2026-09-26에 사용자가 "요즘 동글만 남김"을 골랐다(후보: 아홉 다 남김 · 아홉 다 끔).

- 남긴다: `USB_NET_AX8817X`(ASIX USB2 동글) · `USB_NET_AX88179_178A`(USB3 동글) ·
  `USB_NET_CDC_NCM`(요즘 폰 테더링).
- 끈다: `USB_NET_NET1080`(Laplink 케이블) · `USB_NET_ZAURUS`(Sharp PDA) ·
  `USB_NET_CDC_SUBSET`. 셋째를 끄면 거기 딸린 `USB_NET_CDC_SUBSET_ENABLE` ·
  `USB_BELKIN` · `USB_ARMLINUX`도 사라진다(Kconfig의 `depends on USB_NET_CDC_SUBSET`).

plan을 쓰는 동안 `olddefconfig`만 따로 돌려 결과를 확인했다(`/tmp/wn/m1.resolved`,
빌드는 안 했다). HEAD 대비 `=y` 줄은 더해진 것이 스물둘이고 빠진 것이 영이다.
M0 실측 1의 스물여덟에서 여섯이 빠진 수다. `# ... is not set` 줄은 새 메뉴(PHY
드라이버 목록 · `USB_NET_*` 목록)가 열리면서 많이 생긴다. 이 줄들은 "안 켰다"는
기록일 뿐이라 판정에 쓰지 않는다.

### 2. QEMU 호출은 스물이고 그중 열여섯이 NIC 옵션을 안 준다

| 자리 | 호출 | 지금 |
|---|---|---|
| `net/check.sh` | 468 · 1026 · 1210 · 1348 | `-netdev` 있음 — 안 고친다 |
| `boot` · `terminal` · `config` · `input` · `device` · `render` · `copy` · `hangul` · `tools` | 한 곳씩 | 없음(`pc` → 기본 `e1000`) |
| `power/check.sh` | 114 · 325 | 없음(`pc`) |
| `machine/check.sh` | 95 | 없음(`q35` → 기본 `e1000e`) |
| `install/check.sh` | 101 · 461 | 없음(`q35`) |
| `kernel/check-virtio-gpu.sh` · `devcontainer/sanity/check.sh` | 한 곳씩 | 없음. `CHAINS` 밖 |

체인 안에서 고칠 곳은 열넷이다. `CHAINS` 밖의 둘도 design 결정 3("모든 QEMU
호출")대로 달지만 lint 대상은 아니다. lint는 게이트가 돌리는 것만 지킨다.

`-nic none`은 호출의 `qemu-system-x86_64 \` 바로 다음 줄(`-machine`이 있으면 그
다음 줄)에 둔다. 격리가 호출 머리에서 보이게 하려는 것이다.

`pc` 체인은 지금 켜는 드라이버로는 기본 NIC(`e1000`)를 못 잡는다. 그래도 단다.
그 성질은 "`E1000`을 안 켰다"는 우연에 기대고 있고, 결정 3이 없애려는 것이 바로
그런 우연이다.

### 3. lint는 여러 줄에 걸친 호출을 하나로 읽어야 한다

`require_no_early_exit_pipe`는 한 줄 안에서 끝나는 모양을 찾는다. QEMU 호출은
백슬래시로 열 줄 넘게 이어지고, `-nic none`은 첫 줄에 없다. 그래서 `awk`로
`qemu-system-x86_64`가 나온 줄부터 백슬래시로 끝나지 않는 줄까지를 한 호출로
모은다. 그 안에 `-nic none`도 `-netdev`도 없으면 호출이 시작된 줄 번호를 찍는다.

주석 줄(`^[[:space:]]*#`)은 건너뛴다. 줄 번호는 `awk`의 `NR`이라 원본과 같다.
GA-M1 사실 1이 겪은 번호 어긋남이 여기서는 구조적으로 안 생긴다.

`-netdev`를 통과로 치는 근거는 M0 실측 5다. `-netdev`만 줘도 기본 NIC가 안
붙는다.

### 4. 검사 11은 지우되 번호는 비워 둔다

검사 12~24가 서로를 번호로 부른다(예: "검사 12 · 13이 실패하면", "검사 24와 같은
사실"). 번호를 당기면 스무 곳 넘는 주석이 바뀌고, 그중 하나라도 놓치면 틀린
설명이 남는다. 그래서 검사 11 자리에 짧은 묘비 주석만 남긴다. "WN-M1이 지웠다,
그 성질은 `check.sh`의 `require_explicit_nic`가 부팅 없이 지킨다"는 내용이다.
파일 머리와 `check.sh`의 NW 설명 문단에서 검사 11 · "NIC가 아예 없다"를 말하는
문장도 함께 고친다.

## Task 1 — lint를 먼저 넣고, 지금 저장소가 빨간 것을 본다

TDD의 빨강 단계에 해당한다. 대상은 따로 심지 않고 지금 저장소 그대로다.
`-nic none`이 아직 없으므로 체인 안의 열넷이 전부 잡혀야 한다.

- [ ] Step 1: `check.sh`의 `require_no_early_exit_pipe` 아래에 함수를 넣는다

```bash
# WN-M1: QEMU 호출은 NIC를 명시해야 한다.
#
# QEMU는 NIC 옵션이 없으면 기본 NIC를 하나 붙인다 — pc는 e1000, q35는 e1000e다.
# WN이 e1000e를 켜기 전까지 기존 체인들은 "드라이버가 없어서 못 본다"는 우연에
# 기대어 NIC 없이 돌았다. 켠 뒤로 machine 체인은 모른 채 eth0을 갖고도
# 초록이었다(WN design 실측 7). 이 검사가 그 우연을 명시로 바꾼다.
#
# `-netdev`도 통과다. 그것만 줘도 기본 NIC가 안 붙는다(WN design 실측 5).
#
# 한 호출이 백슬래시로 여러 줄에 이어지므로 줄 단위 grep으로는 못 본다.
# qemu-system-x86_64가 나온 줄부터 백슬래시로 끝나지 않는 줄까지를 하나로 모은다.
# 찍는 번호는 호출이 시작된 줄이다.
require_explicit_nic() {
  local script="$1"
  local hits

  hits="$(awk '
    /^[[:space:]]*#/ { next }
    !open && /qemu-system-x86_64/ { open = 1; start = NR; call = "" }
    open {
      call = call " " $0
      if ($0 !~ /\\[[:space:]]*$/) {
        if (call !~ /-nic none/ && call !~ /-netdev/) print start
        open = 0
      }
    }
  ' "$script")"

  [ -z "$hits" ] && return 0

  echo "check FAIL: ${script} starts QEMU without saying which NIC it gets:" >&2
  echo "  line(s): $(echo $hits)" >&2
  echo "  QEMU adds a default NIC (e1000 on pc, e1000e on q35) when none is named." >&2
  echo "  add '-nic none', or '-netdev ...' if the chain wants a network (WN-M1)." >&2
  return 1
}
```

- [ ] Step 2: 진입 루프에 한 줄을 더한다

```bash
for entry in "${CHAINS[@]}"; do
  require_build_steps "${entry#*:}" || entry_failed=1
  require_no_early_exit_pipe "${entry#*:}" || entry_failed=1
  require_explicit_nic "${entry#*:}" || entry_failed=1
done
```

`gate_lib.sh`와 `check.sh`는 QEMU를 안 띄우므로 extra 루프에는 안 넣는다.

- [ ] Step 3: 진입 검사만 돌려 빨강을 본다 (몇 초)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  bash -n check.sh && echo "syntax OK"
  sed -n "/^clean$/q;p" check.sh | bash -s; echo "exit=$?"
' 2>&1 | grep -aE 'syntax|NIC|line\(s\)|exit='
```

기대: `syntax OK`가 나온다. 사실 2의 표에 있는 체인 스크립트 열두 개가 이름을
찍고, 줄 번호가 열넷(`power`와 `install`은 둘씩)이다. `net/check.sh`는 안 나온다.
마지막 줄은 `exit=1`이다.

잘라낸 사본을 파일로 두지 않고 `bash -s`로 넘기는 이유가 있다. `check.sh`는 맨 위에서
`cd "$(dirname "$0")"`를 하는데, 사본이 `/tmp`에 있으면 `/tmp`로 가서 모든 체인을
"없다"고 한다. 실행하면서 한 번 밟았다. stdin으로 넘기면 `$0`이 `bash`라 제자리다.

## Task 2 — `-nic none`을 단다

- [ ] Step 1: 체인 열넷과 `CHAINS` 밖의 둘에 한 줄씩 넣는다

사실 2의 자리대로 넣는다. 들여쓰기는 각 호출의 옆 줄에 맞춘다. `config` ·
`input` · `install`의 호출은 함수 안에 있어서 들여쓰기가 두 칸 더 깊다.

- [ ] Step 2: diff를 센다

```bash
git diff --stat
git diff | grep -E '^\+' | grep -v '^+++' | grep -vc -- '-nic none'
git diff | grep -E '^-' | grep -v '^---'
```

기대: 스크립트 열여섯 개에서 `-nic none` 줄이 열여섯 더해진다. `check.sh`에서
Task 1의 줄들이 더해진다(`-nic none`이 아닌 줄의 수 = 그 줄 수). 지운 줄은
`check.sh` 진입 루프의 `done` 앞뒤 외에는 없다.

- [ ] Step 3: 진입 검사가 초록이 된다

Task 1 Step 3과 같은 명령. 기대: NIC 문구가 하나도 없고 `exit=0`이다(`clean`
앞에서 잘랐으므로 끝까지 가면 0).

## Task 3 — 음성 확인 둘: 통과 경로와 주석 건너뛰기

Task 1이 "없으면 잡는다"를 실제 저장소로 봤다. 남은 것은 `-netdev`로 통과하는
길과 주석을 무시하는 길이다. 저장소 파일은 안 건드리고 `/tmp` 사본으로 본다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  sed -n "/^clean$/q;p" check.sh > /tmp/entry.sh
  run() { sed "s#\./boot/check.sh#/tmp/bait.sh#" /tmp/entry.sh > /tmp/e.sh
          bash -s < /tmp/e.sh >/tmp/o 2>&1; echo "$1 exit=$? $(grep -a "line(s)" /tmp/o)"; }

  cp boot/check.sh /tmp/bait.sh
  printf "qemu-system-x86_64 \\\\\n  -m 64 \\\\\n  -no-reboot\n" >> /tmp/bait.sh
  run "no-nic"

  cp boot/check.sh /tmp/bait.sh
  printf "qemu-system-x86_64 \\\\\n  -netdev user,id=n0 \\\\\n  -no-reboot\n" >> /tmp/bait.sh
  run "netdev"

  cp boot/check.sh /tmp/bait.sh
  printf "# qemu-system-x86_64 -m 64\n" >> /tmp/bait.sh
  run "comment"
'
```

기대: `no-nic exit=1`이고 끝에 덧붙인 줄의 번호를 찍는다. `netdev exit=0`,
`comment exit=0`이다.

## Task 4 — `.config`

- [ ] Step 1: 켜고 끈다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/kernel tars-devcontainer bash -c '
  S=src/linux-6.18.42/scripts/config
  $S --file .config -e E1000E -e IGC -e R8169 -e USB_RTL8152 \
     -e USB_USBNET -e USB_NET_CDCETHER \
     -d USB_NET_NET1080 -d USB_NET_ZAURUS -d USB_NET_CDC_SUBSET
  ./build.sh > /tmp/build.out 2>&1; rc=$?; tail -2 /tmp/build.out
  cp build/.config .config
  stat -c "bzImage=%s" build/arch/x86/boot/bzImage; exit $rc'
```

해소된 `build/.config`를 `kernel/.config`로 되돌려 쓴다. 저장소가 그 모양을
커밋해 왔다(M0 실측 1). 되돌려 쓰면 `.config`의 해시가 바뀌므로 다음 `build.sh`가
한 번 더 make를 돈다. 입력이 같으므로 할 일은 없다.

- [ ] Step 2: 사실 1과 같은지 본다

```bash
diff <(git show HEAD:kernel/.config | grep '^CONFIG_' | sort) \
     <(grep '^CONFIG_' kernel/.config | sort)
diff <(sort /tmp/wn/m1.resolved) <(sort kernel/.config) && echo "same as plan-time"
```

기대: 첫 diff는 `>`가 스물둘이고 `<`가 영이다. 둘째는 `same as plan-time`이다.
bzImage 크기는 M0의 4,871,168보다 조금 작아야 한다. 끈 여섯만큼 줄기 때문이다.

## Task 5 — `net` 검사 11을 지운다

- [ ] Step 1: 688~712행의 검사 블록을 묘비 주석으로 바꾼다(사실 4)
- [ ] Step 2: 파일 머리의 사슬 설명에 `e1000`이나 검사 11을 말하는 문장이 있으면
  고친다. `check.sh`의 NW 문단 둘째 단락("나머지 열하나는 NIC가 아예 없다 …
  검사 11이 그 음성을 매번 확인한다")도 새 사실로 고친다. 다른 체인은 이제
  `-nic none`으로 NIC가 없고, 그것을 `require_explicit_nic`가 지킨다.
- [ ] Step 3: 지운 줄을 읽는다

```bash
git diff net/check.sh check.sh | grep '^-' | grep -v '^---'
```

기대: 검사 11 블록과 고친 설명 문장만 지워졌다.

## Task 6 — 영향이 큰 체인 둘을 먼저 한 판씩 (약 3분)

루트 게이트 전에 싸게 확인한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash machine/check.sh > /tmp/wn/m1-machine.log 2>&1; echo "machine exit=$?"
grep -ac 'eth0' /tmp/wn/m1-machine.log
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash net/check.sh > /tmp/wn/m1-net.log 2>&1; echo "net exit=$?"
tail -3 /tmp/wn/m1-net.log
```

기대:
- `machine exit=0`이고 `eth0` 개수가 0이다. 이 체인은 시리얼 로그를 `cat`한다
  (`machine/check.sh:141`). M0 실측 7에서 보였던 `e1000e 0000:00:02.0 eth0: …` 줄이
  사라진 것이 `-nic none`의 효과다. 처음에는 `e1000e`를 0으로 적었는데 실행하니
  둘이 나왔다. 드라이버가 들어 있으면 장치가 없어도 부팅에 찍히는 등록 배너
  (`e1000e: Intel(R) PRO/1000 Network Driver` · `Copyright`)다. 그래서 장치에
  붙었다는 표지인 `eth0`으로 센다.
- `net exit=0`이다. 드라이버가 늘었어도 이 체인의 장치는 virtio-net 하나라
  이름이 여전히 `eth0`이다.

## Task 7 — 루트 게이트 3/3 (약 42분, 백그라운드)

커널 첫 빌드가 드라이버만큼 길어지고(M0 실측 2: 증분 18.8초) 부팅 수는 그대로다.
기준선은 TD-M2의 41분 08.74초다.

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } > /tmp/gate.log 2> /tmp/gate.time
grep -a 'PASS\|FAIL' /tmp/gate.log | tail -20; cat /tmp/gate.time
```

판정: 마지막 줄이 `TARS check PASS`이고 `FAIL`이 0줄이다.

## Task 8 — 문서와 커밋

- design: `Status:`를 "M1 끝났다"로 고치고, "WN-M1이 실행으로 증명한 것" 절에
  실측(lint가 잡은 열넷 · bzImage 크기 · `machine` 로그의 `e1000e` 0 · 게이트
  시간)을 적는다.
- `HANDOFF.md`: 바로 다음 할 것을 M2 plan으로 바꾼다.
- 커밋은 둘로 나눈다. 격리(lint · `-nic none` · 검사 11)와 `.config`다. 앞의
  것만으로도 게이트가 초록이어야 하므로 순서도 그렇게 둔다. Task 순서가 이미
  그렇다(Task 3까지는 드라이버 없이 진입 검사만 돈다).
