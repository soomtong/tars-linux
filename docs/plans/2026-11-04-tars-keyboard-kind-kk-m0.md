# KK-M0 — Apple 대역 키보드와 판정을 먼저 넣고, 지금 코드에서 빨간 것을 본다

> 구현 파일은 Claude(또는 서브에이전트)가 넣고, lead가 diff를 실제 파일과 대조한 뒤 체인 · commit한다. 줄 번호는 2026-11-04
> `424155d` 기준이라 낡을 수 있다 — 고치기 전에 `rg`로 다시 찾는다.

Goal: KK design 결정 7 · 8을 고치기 전 코드에 먼저 넣는다. (1) uinput으로 vendor 0x05ac 키보드를 만드는 게이트 전용 도구,
(2) `input` 체인의 부팅 셋과 새 판정 (가) · (나), (3) Cmd · Option을 치는 체인 다섯의 `keyboard=apple`. 지금 terminal · init
(`424155d`)에서 (가)가 기대한 이유로 빨갛고, (나)와 다섯 체인은 초록이어야 한다. terminal · init 코드는 0줄이다.

Architecture: 도구는 `pointer/replay/`(`tp-replay`)의 모양을 그대로 따른다 — libc 없는 Zig, 체인이 빌드해 설정 디스크에 싣고
게스트 셸에서 친다. 다른 점은 하나다. 도구가 친 키는 terminal을 거쳐 전경 프로세스에 가므로, 도구는 백그라운드(`&`)로 떠서 정해진
키를 스스로 치고 끝난다(stdin으로 명령을 안 받는다). 체인 수는 27 그대로다.

## 착수 전에 확인한 것 (2026-11-04)

- `input` 체인의 키보드는 PS/2다. `start_guest`에 `-machine`이 없어 기본 `pc` 기계의 i8042 AT 키보드가 붙는다
  (`AT Translated Set 2 keyboard`, bus 0x11 · vendor 0x0001). design 결정 7 (가)의 예시 줄(`vendor=0627`)은 `keyboard` 체인의
  QEMU `usb-kbd` 것이고, 이 체인에서 M1 뒤에 찍힐 줄은 `kind=pc bus=0011 vendor=0001`이다. 일반 노트북 내장 키보드와 같은 모양이라
  판정의 뜻은 그대로다.
- 지금 1차 부팅: 디스크 없음 → `tars-init: config shell=fish keyboard=apple` · `terminal: keyboard=apple (swap_alt_meta=false)`.
  판정 1~6을 fish에서, 판정 7에서 `/usr/bin/bash --norc`로 들어가 판정 8(Option+← → `aa Xbb`) · 9(Cmd+← → `cc dd`)를 본다.
  2차는 `make_disk.sh`의 `shell=bash keyboard=pc` 디스크로 판정 10 · 11을 본다.
- `tp-replay`(`pointer/replay/main.zig`): uinput 요청 번호는 손으로 만든 상수(`UI_DEV_SETUP` · `UI_DEV_CREATE` · `UI_SET_EVBIT` ·
  `UI_SET_KEYBIT`), `DevSetup`은 92바이트, `Event`는 24바이트를 comptime으로 붙박는다. 빌드는 `build.zig`(x86_64 · musl ·
  baseline · ReleaseSafe · single_threaded), 체인이 `zig build --prefix "${REPO_ROOT}/out/pd-replay" --cache-dir …`로 부른다.
- terminal이 키보드로 여는 기준은 `EV_KEY`와 `KEY_ESC`(1) ~ `KEY_D`(32)다(KH 결정 2). 도구가 칠 키(`e c h o m n` · 빈칸 ·
  `KEY_LEFTALT`(56) · `KEY_LEFT`(105) · `KEY_LEFTSHIFT`(42) · `KEY_X`(45) · `KEY_ENTER`(28))도 비트가 켜져야 간다. 1 ~ 127을 다 켠다.
- 디스크 없는 부팅 셋(`copy` 하나 · `pane` A · `pointer` A)에 `/config`의 없음에 기대는 판정이 없다(`rg '/config|tars-init: config'`).
  `pane` A는 `clipboard=shared`로 끝나는 config 줄을 보는데, `keyboard=apple`만 적은 파일에서도 clipboard는 기본값 `shared`다.
- init은 라벨이 `tars-`로 시작하는 첫 디스크를 `/config`로 붙인다(RM). ext2 라벨은 16자까지다.
- `site/capture.sh`(소개 페이지 녹화)도 디스크 없이 Cmd를 친다. 호스트(macOS)에서 돌고 `mkfs.ext2`가 없을 수 있어 M0에서는 안
  건드린다 — 기본값을 바꾸는 M1에서 함께 본다.

## Task 1: Apple 대역 도구 `input/kk/`

`pointer/replay/`의 두 파일을 본으로 `input/kk/build.zig` · `input/kk/main.zig`를 만든다. 실행 파일 이름은 `kk-apple`.

- 장치: `BUS_USB`(0x03) · vendor 0x05ac · product 0x0250 · version 1, 이름 `TARS KK Keyboard`. 이름에 `Apple`을 안 넣는다 — 결정 2가
  이름을 안 보는 것을, 이름으로 고르는 잘못된 구현이 통과하지 못하게.
- 비트: `EV_KEY`, 키 1 ~ 127. `EV_REP`는 안 켠다(커널 자동 반복이 판정을 흔들지 않게 — DM 실측 1).
- 동작(인자 없음): 장치를 만들고 `kk-apple: ready`를 stderr로 한 줄, 1초 쉰다(terminal이 uevent로 열 시간, design 위험 2). 그다음
  키를 친다 — `e c h o` 빈칸 `m m` 빈칸 `n n`, Alt 누름 · ← 누름 · ← 뗌 · Alt 뗌, Shift 누름 · `x` · Shift 뗌, Enter. 키 하나는 누름
  · `SYN` · 10ms · 뗌 · `SYN` · 10ms다. 끝나면 0.5초 쉬고 장치를 없앤다.
- 친 뒤에는 아무것도 안 찍는다(`tp-replay`와 같은 이유 — 출력이 패널에 섞이면 화면 판정이 흔들린다).
- 머리 주석에 "제품 initrd에는 없다. input 체인이 빌드해 1차 부팅 디스크의 `kk/kk-apple`로 싣는다"와, 백그라운드로 띄우는 이유를
  적는다.

Apple 키보드로서의 뜻: 이 키보드가 `apple`로 읽히면 Alt+←는 Option+←(단어 이동)이라 줄이 `echo mm Xnn`, `pc`로 읽히면 Cmd+←(줄
처음)라 `Xecho mm nn` → `bash: Xecho: command not found`다.

## Task 2: `input/make_disk.sh`가 디스크 셋을 굽는다

인자로 종류를 받는다: `./make_disk.sh auto <kk-apple 경로>` · `./make_disk.sh pc` · `./make_disk.sh apple`. 이미지는
`../out/input-<종류>.img`, 라벨은 `tars-input-<종류>`(16자 안).

- `auto`: `tars.conf`에 `keyboard=` 줄이 없다 — 주석 한 줄(`# KK: keyboard= 줄이 없다 — 기본값이 고른다`)과 `shell=fish`(지금 1차와
  같은 셸). 그리고 `kk/kk-apple`(0755).
- `pc`: 지금 그대로(`shell=bash` · `keyboard=pc`).
- `apple`: `shell=bash` · `keyboard=apple`.

머리 주석을 "IP 체인 2차 부팅용"에서 "부팅 셋의 디스크"로 고친다. 지금의 주석(`-d`의 이유 · 매 회차 새로 굽는 이유)은 남긴다.

## Task 3: `input/check.sh`를 부팅 셋으로

머리 주석의 부팅 목록을 셋으로 고친다(KK design 결정 7). 마지막 줄 `PASS`는 그대로다.

준비: `init` 빌드 뒤에 도구를 빌드한다 — `(cd kk && zig build --prefix "${REPO_ROOT}/out/kk" --cache-dir "${REPO_ROOT}/out/kk/cache")`,
실패면 `FAIL: kk-apple build failed`. 디스크 셋을 부팅 앞에서 한 번에 굽는다. `LOG3`을 더한다.

### 1차 — 기본값(`auto` 디스크)

`start_guest "$LOG" -drive file="${REPO_ROOT}/out/input-auto.img",if=virtio,format=raw`. 판정 1 ~ 7은 그대로다(fish에서 1 ~ 6, 7에서
`bash --norc`).

지금의 판정 8 · 9를 3차로 옮기고, 그 자리에 둘을 넣는다. 출력 글자는 다른 판정(`aa Xbb` · `cc dd` · `gg hh` · `ii Xjj`)과 겹치지
않게 고른다.

판정 (가) — 기본값의 PS/2 키보드는 `pc`다. 지금 판정 10과 같은 모양이다.

```
type_keys k k spc l l
type_keys alt-left
type_keys e c h o spc
type_keys ret
```

`| kk ll`이면 초록. `kk: command not found`면 `report_failure "with the default keyboard setting the PS/2 keyboard's alt-left still
moved by a word; it was not read as a pc keyboard"`. 둘 다 30초 안에 없으면 따로 문구를 둔다.

판정 (나) — 기본값의 Apple 키보드는 `apple`이다.

```
type_keys slash c o n f i g slash k k slash k k minus a p p l e spc shift-7 ret
```

`wait_for_log 'terminal: keyboard> open /dev/input/event[0-9]+ .*name=TARS KK Keyboard'`(30초)로 열림을 먼저 본다. 안 열리면
`report_failure "terminal never opened the kk-apple keyboard"` — design 위험 2다. 그다음 화면: `| mm Xnn`이면 초록, `Xecho: command
not found`면 `report_failure "the Apple-vendor keyboard's alt-left went to the start of the line; it was read as a pc keyboard"`,
`| mm nXn`이면 맨 ←가 샌 것이다. 끝으로 `keyboard> close … `가 찍히는지(도구가 장치를 없앴다) 본다.

같은 부팅의 (가)와 (나)는 같은 물리 키(왼쪽 Alt + ←)가 키보드에 따라 반대 뜻이라는 증거다. design의 (다)(섞인 조합)는 이
milestone에 안 넣는다 — HMP `sendkey`는 키를 쥔 채 둘 수 없고, 도구가 바깥 키를 기다리는 모양은 위험 2를 키운다. 칸을 건너는 조합은
DM이 Shift로 이미 체인에서 보고, M1의 `input_test`가 Alt · Meta로 본다.

1차 끝의 로그 판정(지금 `diskless boot did not fall back`)을 셋으로 바꾼다.

- `tars-init: loaded /config/tars.conf`
- `tars-init: config shell=fish keyboard=auto`
- `terminal: keyboard=auto (swap_alt_meta=per keyboard)`

셋 다 M1의 값이다 — 지금 코드에서는 `keyboard=apple`이 찍힌다. 화면 판정 (가)가 먼저 빨개지므로 체인은 거기서 끝난다.

### 2차 — `keyboard=pc`

지금 그대로다. 디스크 경로만 `input-pc.img`로.

### 3차 — `keyboard=apple`

`input-apple.img`(`shell=bash`)로 띄운다. bash 프롬프트를 기다린 뒤(지금 판정 7의 `screen>.*bash-` 기다림과 같은 모양), 지금의 판정 8
· 9와 `key> 2 byte(s)` 판정을 그대로 옮긴다. 로그 판정 둘 — `tars-init: config shell=bash keyboard=apple` · `terminal:
keyboard=apple (swap_alt_meta=false)`. 3차의 판정은 지금 코드에서도 초록이어야 한다(값을 적었으므로 기본값과 상관없다).

번호. 지금의 1 ~ 11을 유지하고 새 것은 12(가) · 13(나)로 매긴다. 판정 8 · 9는 번호를 지키며 자리만 3차로 간다. 주석의 "1차 = 단어
이동 → 2차 = 줄 처음" 같은 대조 문장을 "3차(apple) ↔ 2차(pc)"로 고친다.

## Task 4: 체인 다섯의 `keyboard=apple` (design 결정 8)

디스크가 있는 부팅은 `tars.conf`에 한 줄을 더하고, 그 자리의 주석에 "KK: QEMU 키보드를 Apple로 읽게 한다(Cmd · Option을 치는
체인)"를 단다.

| 체인 · 부팅 | 고칠 곳 |
|---|---|
| `pane` B | `printf 'shell=fish\nclipboard=pane\n'` |
| `pointer` B | `printf 'shell=fish\n'` |
| `dictation` A · B | `printf 'net=dhcp\n'` 둘 |
| `hangul` | `make_disk.sh`의 `tars.conf` 히어독 |

디스크가 없는 부팅 셋(`copy` · `pane` A · `pointer` A)은 `gate_lib.sh`에 도우미 하나를 두고 그것을 부른다.

```bash
# KK design 결정 8. `keyboard=apple` 한 줄짜리 설정 디스크를 굽는다. 기본값이 `auto`라 QEMU 키보드가 `pc`로
# 읽히므로, Cmd · Option을 치는 체인이 지금 뜻을 지키려고 문다. $1 = 이미지 경로, $2 = 라벨(`tars-`로 시작, 16자 안).
apple_disk() {
  local seed
  seed="$(mktemp -d)"
  printf 'keyboard=apple\n' > "$seed/tars.conf"
  rm -f "$1"
  truncate -s 16M "$1"
  mkfs.ext2 -F -q -m 0 -L "$2" -d "$seed" "$1"
  rm -rf "$seed"
}
```

각 부팅의 `qemu-system-x86_64`에 `-drive file=…,if=virtio,format=raw`를 더한다. 이미지는 `${REPO_ROOT}/out/<체인>-apple.img`, 라벨은
`tars-copy` · `tars-pane-a` · `tars-pd-a`. `copy` · `pane`에 `REPO_ROOT`가 없으면 `input`처럼 만든다. 각 부팅 뒤에 판정 하나를 더한다 —
`tars-init: config shell=.* keyboard=apple`(디스크가 붙고 값이 읽혔다). 이것이 없으면 디스크가 안 붙어도 지금 코드에서는 초록이라,
M1의 기본값 변경 전까지 이 Task가 섰는지를 아무것도 안 본다.

## Task 5: 정적 검사

`make quick`(shellcheck note까지 · fmt · ast-check · shared · init 빌드). `input/kk/main.zig`는 quick의 fmt · ast-check 대상인지 보고,
아니면 `zig fmt --check input/kk` · `zig ast-check input/kk/main.zig`를 따로 부른다. 도구는 호스트에서 `zig build`로 한 번 빌드해 본다.

`git diff --stat`과 `git diff | rg '^-'`로 지운 줄을 읽는다. 지워져야 하는 것은 `input/check.sh`의 1차 끝 로그 판정 · 옮긴 판정 8 · 9의
원래 자리 · 부팅 목록 주석, `make_disk.sh`의 고정 이미지 경로 · 머리 주석, 다섯 체인의 `tars.conf` 줄 원본, 디스크 없던 `qemu`
줄의 끝(`-no-reboot &` 앞)뿐이다.

## Task 6: 지금 코드에서 돌린다

### 6a — `input` 체인의 일회용 사본

체인을 그대로 돌리면 (가)에서 끝나 (나)를 못 본다. DM-M0과 같은 요령으로 `input/kk-m0-probe.sh`(같은 디렉터리 — `cd "$(dirname "$0")"`)
를 만들어 (가)와 1차 끝 로그 판정 셋의 `report_failure`만 `echo "RED: …"`로 바꾼다. 컨테이너에서 돌린다(약 2분).

```
docker run --rm --sysctl net.ipv4.ip_local_reserved_ports=45455-45599 -v "$PWD":/workspace -w /workspace tars-devcontainer ./input/kk-m0-probe.sh
```

기대.

- 판정 1 ~ 7 초록.
- (가) `RED` — 화면은 `kk: command not found`, 로그에 `keyboard> open … name=AT Translated Set 2 keyboard`.
- (나) 초록 — `keyboard> open … name=TARS KK Keyboard`, 화면 `| mm Xnn`, 그 뒤 `close`. 지금 코드는 swap이 전역 거짓이라 어느
  키보드든 Option이다. 우연한 초록이고 M1의 mutation (a) · (b)가 이 판정의 값을 붙박는다.
- 로그 판정 셋 `RED` — `keyboard=apple`이 찍혔다.
- 2차 · 3차 초록.

사본을 지운다. 커밋에 안 들어간다.

갈래.

- (나)의 `open`이 안 찍히면 위험 2다. `kk-apple: ready`가 화면에 있는지, `/dev/uinput`이 있는지(1차 셸에서 `ls -l /dev/uinput`), terminal의
  `keyboard> skip` 줄이 있는지(비트가 모자라 키보드로 안 보였다) 순서로 본다.
- `open`은 찍혔는데 글자가 안 오거나 앞 글자가 빠지면 1초가 모자란 것이다. 2초로 늘리고 다시 본다.
- (가)가 지금 코드에서 초록이면 1차가 `pc`로 뜬 것이다 — 디스크의 `tars.conf`가 아니라 다른 것이 읽혔는지 로그의 `tars-init:
  config` 줄을 본다.

### 6b — 루트 게이트 한 판

Task 4가 다섯 체인의 부팅을 바꿨으므로 루트 게이트를 돈다(`RUNS=1`, 약 15분 — 실행 전에 알린다). 기대는 26/27이다. 빨강은 `input`
하나이고 이유가 6a의 (가)와 같아야 한다. 다섯 체인(`copy` · `pane` · `pointer` · `dictation` · `hangul`)이 초록이고 각자의 새 판정
(`keyboard=apple`이 읽혔다)도 초록이다. 디스크를 새로 문 부팅이 흔들리면(design 위험 4) 그 부팅만 B안(키 이름 바꾸기)으로 돌릴지
사용자와 정한다.

## Task 7: 문서

- KK design에 "실측 (M0)" 절. 실측 1 — `input` 체인의 키보드가 PS/2라는 것과 (가)에서 찍힐 id(design 결정 7의 예시 줄 정정). 실측 2 —
  6a의 결과(빨강 · 초록과 그 줄). 실측 3 — 6b의 결과와 `input` 체인의 늘어난 시간. (다)를 뺀 이유.
- design 결정 7의 (다)에 "M0에서 뺐다"를 단다. Status를 "KK-M0 끝남, 다음 KK-M1"로.
- `docs/guides/key-files.md`에 `input/kk/` 한 줄(`tp-replay` 줄 옆).
- HANDOFF: M0 끝, 그리고 "`input` 체인은 M1 커밋까지 판정 12(가)에서 빨강이 정상이다 — 이 사이 루트 게이트는 26/27이다".

## Task 8: 커밋

사용자 승인 뒤. add 대상: `input/kk/build.zig` · `input/kk/main.zig` · `input/check.sh` · `input/make_disk.sh` · `gate_lib.sh` ·
`copy/check.sh` · `pane/check.sh` · `pointer/check.sh` · `dictation/check.sh` · `hangul/make_disk.sh` · design · 이 plan ·
`key-files.md` · `HANDOFF.md`. `input/kk-m0-probe.sh`와 `input/kk/zig-out` · `.zig-cache`가 `git status`에 없는지 먼저 본다
(`.gitignore`가 `pointer/replay`의 것을 어떻게 막는지 보고 같게).

M0 커밋부터 M1 커밋까지 main의 `input` 체인이 빨갛다. 판정이 고칠 동작을 먼저 붙박는 것이 이 milestone의 뜻이다.

## 시간

도구 약 150줄, 셸 약 150줄 고침. 정적 검사 1분, 사본 한 판 약 2분, 루트 게이트 약 15분.
