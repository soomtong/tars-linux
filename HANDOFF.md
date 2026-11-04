# HANDOFF: Device Modifiers(DM-M0~M1) 끝남 · 커밋됨 — 다음 서브프로젝트는 사용자가 고른다

## 목표

진행 중인 서브프로젝트는 없다. DM(Device Modifiers)은 코드 · 체인 · 루트 게이트 · 문서 · 커밋까지 닫혔다. 소개 페이지는
`gh-pages`에 로컬 커밋만 했다(아래 "현재 브랜치"). 다음 일은 "다음 후보"에서 사용자가 고르고, 새 서브프로젝트는 design부터.

## 현재 브랜치

`main` — origin보다 앞서 있다(DM design · M0 · M1 커밋, push는 사용자가 한다). `gh-pages`도 DM 커밋이 로컬에만 있다 — push는
사용자에게 남겼다(사용자가 외출하며 마무리를 맡긴 세션, 2026-11-04).

## 완료된 작업 (2026-11-04, 사용자 외출 중 위임)

- [x] DM design(`65b6f30`) — 사용자가 결정 1~7을 추천안 그대로 승인
- [x] DM-M0(`056d010`) — `keyboard` 체인 판정 8 · 9 · 10, 고치기 전 코드에서 기대한 이유로 빨강. 커널 자동 반복이 결함을 가려
  첫 판에 8 · 9가 초록이었다 → `stop_repeat`(design 실측 1)
- [x] DM-M1 — `input.zig`(`mods` · `taps` 칸 배열, `anyMods`, `otherHolds`, `releaseDevice`, `Context.device`), `main.zig`(칸 번호를
  넘긴다, `MAX_KEYBOARDS` 별칭), `input_test` 검사 88, 체인 11/11, mutation 셋 잡힘, 루트 게이트 27/27(15분 20초)
- [x] 닫는 묶음 — design Status · 실측 1~5, KH design 결정 4 · 비목표 5 포인터, `carryover.md` KH 둘째 항목 `[x]`, `completed.md` 행,
  `project_device_modifiers.md` + `MEMORY.md`, 소개 페이지 `data.js`(gh-pages 로컬 커밋)

## 시도했으나 실패한 접근

- 판정 8 · 9를 Shift만 쥔 채 보는 것: 커널 자동 반복이 지워진 비트를 다시 켜서 고치기 전 코드에서도 초록이었다 → 쥔 장치의
  오른쪽 Ctrl을 눌렀다 떼 반복을 멈춘 뒤 본다.
- 새 판정에 `joined_screen_dump | grep -aq`: 루트 게이트 진입 검사가 0.5초 만에 막았다(GA-M0) → `grep -a … >/dev/null`.

## 남은 작업

- [ ] 사용자: `main`과 `gh-pages` push
- [ ] 다음 서브프로젝트 고르기(사용자) → design → plan

## 핵심 파일

- `docs/specs/2026-11-04-tars-device-modifiers-design.md` — DM 결정 · 실측(방금 닫은 것)
- `terminal/src/input.zig` — `MAX_KEYBOARDS` · `Mods` · `Taps`, `State.mods` · `taps`, `anyMods` · `markTapConsumed` · `otherHolds` ·
  `releaseDevice`, `Context.device`
- `keyboard/check.sh` — KH 판정 1~7b + DM 판정 8~10, `stop_repeat`
- `check.sh`의 `CHAINS` — 체인 27(DM은 체인을 안 더했다)

## 다음 에이전트에게

이 저장소의 규칙(CLAUDE.md): 큰 편집은 무엇이 어떤 모양으로 들어가는지 먼저 설명, 매 편집 뒤 `git diff --stat`과
`git diff | rg '^-'`로 지운 줄 확인, 명령은 Claude가 실행하고 결과를 줄 단위로 설명, 커밋은 사용자 승인 뒤.
init의 `zig build test`는 macOS에서 안 끝나니 컨테이너에서. 체인 하나 돌리기:
`docker run --rm --sysctl net.ipv4.ip_local_reserved_ports=45455-45599 -v "$PWD":/workspace -w /workspace tars-devcontainer ./device/check.sh`.
terminal 줄의 내용을 보는 체인 판정은 `$LOG`가 아니라 `tlog |`를 거친다(커널 printk가 줄을 자른다, `gate_lib.sh`).

## 지금 상태 (2026-11-04)

- 마지막으로 닫은 것은 Device Modifiers(DM-M0~M1, `docs/specs/2026-11-04-tars-device-modifiers-design.md`, 기억은
  `docs/decisions/project_device_modifiers.md`). 수정키 여덟과 tap 둘을 키보드 칸마다 들고(읽기는 OR), 빠진 키보드는 그 칸만
  푼다. 겹친 tap 키의 누름은 소비로 시작한다. 사용자가 결정을 추천안 그대로 정하고 마무리까지 맡겼다.

- 그 전에 닫은 것은 Init Keyboard(IK-M0, `docs/specs/2026-11-03-tars-init-keyboard-design.md`, 기억은
  `docs/decisions/project_init_keyboard.md`). KH 뒤로 아무도 안 쓰던 PID 1의 키보드 고르기 · 3초 기다림 · terminal argv의
  장치 칸을 걷었다. 사용자가 정했다: `Slot.device`를 빼고 `ARGC` 9, 체인 넷은 terminal의 `keyboard> open`과 init 줄의 부재로 판정.
  - 섰다: 키보드 없는 부팅의 `Run /init` → `started terminal` 3.39초 → 0.06초. 루트 게이트 `RUNS=3` 81/81.
  - init의 `devices.zig`에 남은 것은 전원 버튼의 길뿐이다(`looksLikeKeyboard`는 그 판정이 쓴다).
- 그 전에 닫은 것은 Mise(MI-M0~M1, `docs/specs/2026-11-03-tars-mise-design.md`, 기억은 `docs/decisions/project_mise.md`).
  사용자가 정했다: initrd에 안 싣는다, 설치 길은 공식 `mise.run`만, 게이트 런타임은 `node@lts`, activate는 시스템 rc.
  - 섰다: `mise.run` → `mise use -g node@lts` → node 26이 기본 이미지에 도구 하나 안 더하고 돈다(gpg 검증은 mise 안에서).
    시스템 rc 셋이 `~/.local/bin/mise`가 있을 때만 `mise activate <셸>`을 불러, 재부팅 뒤 망 없이 화면 셸에서 `node`가 이름으로
    불린다. 셸 하나에 약 115ms(TCG).
  - 남긴 것은 `carryover.md`의 MI 절(512MB에서 `mise.run`이 tmpfs `/tmp` 때문에 굳는다).
- 그 전에 닫은 것은 Package Manager(PM-M0~M1, `docs/specs/2026-11-03-tars-package-manager-design.md`, 기억은
  `docs/decisions/project_package_manager.md`). 사용자가 정했다: Homebrew, 공식 `install.sh`를 사용자가 직접 친다, 게이트는
  실제 망으로 끝까지.
  - 섰다: 공식 `install.sh`(HEAD)가 `Installation successful!`까지 가고, `brew install hello`가 bottle 하나로 서며, 재부팅 뒤 망
    없이 뜬 화면 셸에서 `hello`가 이름만으로 불린다. M0는 usrmerge · 층 19 도구 · glibc 통째로 · `/etc/os-release` · init의
    `LANG=C.UTF-8`, M1은 시스템 rc 셋의 shellenv(결정 5)와 libstdc++의 이름(결정 10 — Homebrew가 파일 이름에서 버전을 읽어
    gcc 463MB를 붙였다).
  - 남긴 것은 `carryover.md`의 PM 절 — Landlock(커널에 없어 brew sandbox가 꺼진다), 그리고 TARS 자체 패키지 매니저는 나중에
    다시 논의한다(사용자 결정 2026-11-03, 당분간 Homebrew. 그날 정리한 후보 · 출처 · design 질문이 그 항목에 있다).
  - 접두사 PM은 2026-08-19의 Power Management와 겹친다 — `CHAINS`의 `PM-M1`은 `power/check.sh`, 이 체인은 `PM-M0` 그대로다.
  - 컨테이너 이미지가 M0에서 바뀌었다(Dockerfile 태그 `fb074c15a322`, `tar` · `gzip` · `libcurl3t64-gnutls` · ngtcp2 둘). 다른
    기계는 `docker rmi tars-devcontainer && make container`.
- 그보다 전에 닫은 것은 Home Partition(HP-M0~M2, `docs/specs/2026-11-02-tars-home-partition-design.md`,
  기억은 `docs/decisions/project_home_partition.md`).
  - 섰다: 새 설치가 p3 ext4 `tars-home`을 `/home`에 붙이고 계정 하나(기본 `tars` · `tars-linux`)를 만든다. 화면 셸은 uid 1000 ·
    groups `27,29`(sudo · audio)로 홈에서 뜬다. `/config`에 쓰는 길은 Debian `sudo`이고, 사용자가 그냥 치면 `try: sudo …`(77)를 듣는다.
    `sudo tars-config passwd`가 비밀번호를 바꾼다. 시리얼 셸 · ssh는 root, ISO 부팅은 root 셸(그 root도 sudo가 된다).
  - M2의 함정 셋이 기억에 갔다: `pam_unix` 1.7은 setuid 호출자에게 `unix_chkpwd`를 요구한다, 사용자 없는 부팅에도 `/etc/shadow`가
    있어야 한다, sudo timestamp가 남으면 파이프의 첫 줄이 명령에게 간다.
  - 컨테이너 이미지가 바뀌었다(Dockerfile 태그 `5ffbe7a00fb2`, `sudo` · `libpam-modules` · `libpam-modules-bin`). 다른 기계는
    `docker rmi tars-devcontainer && make container`.
  - 남긴 것은 `carryover.md`의 HP 절(hostname `(none)`, sudo timestamp 범위, 부팅 뒤 꽂은 사운드 노드, `ping`, 사용자 셸 히스토리).
- 그 전에 닫은 Bluetooth(BT-M0~M2)는 사용자가 외출하며 결정을 Claude에게 맡긴 세션이었다. 범위(클래식 + BLE HID, 오디오 제외)와 0.1.4
  시점만 사용자가 정했고 나머지 결정은 `docs/specs/2026-11-01-tars-bluetooth-design.md`의 추천안이다 — 뒤집을 것이 있으면 그 문서의
  결정 번호로. 컨테이너 이미지가 그때 바뀌었다(Dockerfile 태그 `ee4aa97122b5`). 다른 기계는 `docker rmi tars-devcontainer &&
  make container`.
- 0.1.4는 커널 7.4 longterm 뒤에 낸다(사용자 결정, 2026-11-01). 그때 담길 것은 KU(슬롯 · ESP · 6.18.60) + BT + KH + HP(새 배치는 `--wipe`로만, HP design 결정 10) + PM + MI + IK + DM. 절차는
  `docs/decisions/project_release.md`의 일곱 단계 — `VERSION` 커밋 → tag → `make iso`. ISO가 약 23MB 커진다(Intel BT firmware).
- 닫은 서브프로젝트의 경과 · 함정 · 숫자는 여기 두지 않는다 — 한 줄 요약은
  `docs/guides/completed.md`의 표, 결정과 함정은 `docs/decisions/`의 기억 파일, 값은 design의 실측 절이다. 최근 것부터:
  - Device Modifiers(DM-M0~M1, 11-04) — `docs/decisions/project_device_modifiers.md`
  - Init Keyboard(IK-M0, 11-03) — `docs/decisions/project_init_keyboard.md`
  - Mise(MI-M0~M1, 11-03) — `docs/decisions/project_mise.md`
  - Package Manager(PM-M0~M1, 11-03) — `docs/decisions/project_package_manager.md`
  - Home Partition(HP-M0~M2, 11-03) — `docs/decisions/project_home_partition.md`
  - Keyboard Hotplug(KH-M0~M2, 11-02) — `docs/decisions/project_keyboard_hotplug.md`
  - Bluetooth(BT-M0~M2, 11-02) — `project_bluetooth.md`
  - Kernel Upgrade(KU-M0~M1, 11-01) — `project_kernel_upgrade.md`
  - Extend Repeat(ER-M0, 11-01) — `project_extend_repeat.md`
  - Shift Extend(SE-M0~M1, 11-01) — `project_shift_extend.md`
  - Multi Click(MC-M0~M2, 11-01) — `project_multi_click.md`
  - Reserved Ports(RP-M0, 11-01) — `project_reserved_ports.md`
  - USB Dongles B(UB-M0~M2, 10-31) — `project_usb_dongles_b.md`. 같은 자리에서 IPv6를 결정으로 닫았다(`feedback_ipv4_only.md`)
  - Ghcr Image(GI) · Vendor Sha256(VS) · Shellcheck Notes(SN) · GitHub Actions(GH-M0~M1, 10-30~31) — `project_github_actions.md`
  - 그 전은 `docs/guides/completed.md`.
- 최신 공개 버전 0.1.3(2026-11-01, tag `v0.1.3` = `055228d`). 0.1.3 뒤로 KU · BT · KH · HP가 쌓였고 아직 내지 않았다.
- 체인은 스물일곱이다(`check.sh`의 `CHAINS`, 마지막이 `MI-M0:./mise/check.sh`). KH 체인이 monitor 45495 · QMP 45496을 쓰고 HP
  체인은 포트를 안 쓴다(45497 · 45498을 HP 예약으로 적어 뒀다), 예약 범위 45455~45599(RP-M0). PM 체인은
  바깥 망(github.com · ghcr.io)에 기대는 첫 체인이다 — 빨개지면 `pm: external network unavailable` 줄이 있는지부터 본다(PM 위험 1).
  마지막 루트 게이트(DM-M1, 1회): 27/27, 15분 20초(prebuild 332초 · lanes 586초), cut log lines 전부 0. `RUNS=3`의
  마지막 값은 IK-M0의 81/81, 약 36분. PM 체인이 244초로 가장 길다. 바깥 망 체인은 PM · MI 둘이다(MI는 `mise: external network unavailable`). 부팅 3의 monitor는 PM 45499 · MI
  45500 — 새 체인은 45501부터.
  게이트를 돌리고 읽는 법 · 로그 위치(`out/gate-logs/`)는 `docs/guides/lessons.md`. 다음에 어느 체인이 빨개지면 그 회차 로그부터 본다.
  `clean()`이 `out/`을 지우므로 그 자리에는 마지막 회차만 남는다 — 회차 사이 비교가 필요하면 게이트 전에 옮겨 둔다.
- 테스트 흐름: 실기는 쓰지 않고 테스트마다 `tars-install <disk> --wipe`로 새로 깐다.

## 사용자가 확인할 것 (실기 또는 실제 장치가 있을 때)

- DM: 키보드 둘(노트북 내장 + USB/BT)로 — A의 Shift를 쥐고 A로 글자 하나를 친 뒤(커널 반복을 멈춘다, DM 실측 1) B의 Shift를
  눌렀다 떼고 B로 글자 → 대문자가 그대로인지. A의 Shift를 쥔 채 B를 뽑아도 A로 친 글자가 대문자인지. 두 키보드의 왼쪽 Ctrl을
  겹쳐 눌렀을 때 한/영이 안 바뀌는지.

- MI: 화면 셸에서 `curl https://mise.run | sh` → 새 패널에서 `mise use -g node@lts` → 또 새 패널에서 `node --version`. rc를 안
  고쳐도 되는지(시스템 rc), 실기에서 패널을 열 때 늦어진 것이 느껴지는지(TCG는 셸 하나에 약 115ms, 부팅 뒤 첫 패널은 mise를
  디스크에서 처음 읽는다), 프로젝트 디렉터리에 `mise.toml`을 두고 `cd`했을 때 버전이 바뀌는지. 다른 런타임(python · go)은 처음이다.

- PM: 화면 셸에서 공식 안내 그대로 `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
  — 게이트는 `NONINTERACTIVE=1`이라 대화형 길(RETURN 누르기 · 비밀번호 묻기)은 처음이다. 실기에서 걸리는 시간(TCG 1GiB는
  140초). 끝의 "Next steps"가 rc에 eval을 넣으라고 하는데, 넣지 않고 새 패널을 열어도 `brew`가 되는지(시스템 rc, 결정 5),
  넣어도 PATH가 두 번 안 붙는지. 그다음 실제로 쓰고 싶은 formula 하나(`chafa` 등) — bottle이 없으면 소스 빌드라 안 된다(결정 4).

- HP: 화면 셸에서 `sudo tars-config set …`이 비밀번호를 한 번 묻고 그 패널에서 15분 동안 다시 안 묻는지, 다른 패널은 따로
  묻는지(timestamp가 tty 단위 — 거슬리면 `carryover.md`). `sudo tars-config passwd` 뒤 새 비밀번호, 사용자로 `tars-config set`을
  쳤을 때의 `try: sudo` 줄이 읽히는지.
- HP: 실제 키보드로 `tars-install`의 질문 셋 — 이름을 틀리게 쳤을 때 다시 묻는 말이 읽히는지, 비밀번호가 화면에 안 찍히는지(확인
  칸이 없어 오타가 그대로 들어간다 — 거슬리면 두 번 묻기). 설치 뒤 화면 셸에서 `id` · `echo $HOME` · `speaker-test`(소리), 명령
  몇 개를 친 뒤 재부팅하고 `history`가 남는지와 `ls ~/.local/share`(HP 실측 11), `bluetooth=on`인 기계에서 사용자의 `bluetoothctl`.

- KH: BT 키보드를 페어링 · 연결한 뒤 곧바로 글자가 쳐지는지(`keyboard> open … name=…`), 노트북 내장 키보드와 함께 쓸 때 한/영 ·
  조합이 이어지는지. `keyboard> open`이 같은 `name=`으로 둘 뜨고 글자가 두 번 나오면 KH 위험 6이다. 부팅 때 키보드가 하나도 없는
  기계(BT만)의 3초는 IK-M0이 걷었다 — 그런 기계에서 화면이 곧바로 뜨는지.
- BT: `tars-config set bluetooth=on` · `tars-config reload` 뒤 `bluetoothctl list`에 내장 어댑터가 뜨는지(안 뜨면 `dmesg | grep -i
  bluetooth` — firmware 이름이 안 보이면 그 이름을 `guest_firmware.sh`에). BLE 마우스를 `scan on` · `pair` · `trust` · `connect`한 뒤
  화살표가 움직이는지 — 게이트가 못 보는 uhid → evdev → terminal의 길이다(BT design 위험 4). 재부팅 뒤 마우스가 스스로 다시 붙는지
  (`/config/bluetooth`의 키). dbus-daemon의 소켓이 실기에서 몇 ms에 생기는지(`tars-bluetoothd: bus ready after Nms`, TCG는 2000).
  initrd가 23MB 커진 만큼 실기 부팅이 느려졌는지(QEMU는 +0.48초).
- RS · DR: 로그에 `kms: present by dirtyfb`가 찍히는지, `cat` · 빌드 로그처럼 출력이 쏟아질 때 화면이 매끄럽게 따라오는지,
  키 입력이 늦게 느껴지지 않는지. DR 뒤로 키 하나는 바뀐 행 몇 줄만 VRAM으로 가므로(simpledrm은 clip마다 복사) 체감이 달라야
  한다 — 달라지지 않았으면 그것이 새 사실이다. SB 뒤로는 상태 줄 띠(1280 × 28 = 143KB, 1080p에서 153KB)도 내용이 바뀐
  프레임에만 간다. TCG에서 키 하나의 그리기는 0.42ms다(SB-M0). 한/영 · CapsLock · 배터리가 바뀔 때 상태 줄이 그 프레임에
  바로 따라오는지도 본다(안 따라오면 `StatusMemo`의 비교가 그 칸을 못 보는 것).
- TC: `tars-config wifi …`와 `tars-config dictation key`의 tty 입력(echo 없이 묻는다), `tars-config set net=dhcp ntp=dhcp`,
  `tars-config reload`, `tars-config reload terminal`. 게이트가 못 보는 것은 tty 질문, `--country`, `firewall deny`,
  `firewall=off`의 말이다.
- AU: `cat /proc/asound/cards` · `aplay -l` · `arecord -l` · `speaker-test`, 헤드폰 잭 · USB 헤드셋. SOF 노트북이면
  `dmesg | grep -i sof`의 `Firmware file:` · `Topology file:`. 조용하면 `amixer -c N` · `snd_intel_dspcfg.dsp_driver=1`.
- BS: 노트북에서 상태 줄 오른쪽 끝에 칸이 뜨는지, 어댑터를 꽂았다 뺄 때 색이 곧바로 바뀌는지, 방전 중 잔량이 60초 안에
  따라오는지. 칸이 안 뜨면 `cat /sys/class/power_supply/*/type`과 로그 `terminal: battery> scan …` 줄(`carryover.md`의 BS 항목).
- MC: 실기 마우스로 더블클릭 · 트리플클릭이 손의 속도에 맞는지(500ms · 8픽셀), 터치패드의 두 번 탭이 더블이 되는지(탭 판정
  180ms 뒤 두 탭 끝의 차). 안 맞으면 값은 `pointer.MULTI_CLICK_US` · `MULTI_CLICK_PX` 둘이다(설정은 MC 비목표 3).
- SE: 끌어 뗀 뒤 반전이 남는 것이 거슬리는지(글자를 쳐도 남는다 — 거슬리면 SE 비목표 1, 키 경로에 `clearLinger` 한 줄), Shift
  클릭이 늘리는 끝이 손의 기대와 맞는지(가까운 끝). 자식이 마우스를 원하는 패널(vim)에서 Shift 끌기 뒤 Shift 클릭도 같다.
- KU: 실기에서 설치된 디스크로 뜰 때 메뉴 3초가 손에 맞는지(길면 `disk.MENU_TIMEOUT`), 갱신한 뒤 메뉴에서 아래 화살표로
  `(old)`를 골라 뜨는지. 실제 펌웨어에서 Limine 메뉴가 GOP 화면에 보이는지도 이때 처음 본다. 커널 6.18.60 자체의 실칩 동작(SOF ·
  무선 · 그래픽)도 처음이다 — 이상하면 old(6.18.42)를 고르는 것이 이 서브프로젝트의 목적이다. 0.1.3 이하로 깐 디스크는 `boot/version`이
  없어 첫 갱신에 old가 안 생긴다(`carryover.md`의 KU 항목).
- ER: Shift 더블 · 트리플클릭이 단어 · 줄로 느는지, Shift 클릭 바로 뒤(500ms · 8픽셀 안) Shift 없이 누른 클릭이 지우기가 아니라
  단어 늘리기가 되는 것이 거슬리는지(거슬리면 ER 비목표 1 — 둘째 누름의 Shift를 본다).
- WP-M3: `Cmd+Option+화살표`(`keyboard=pc`면 `Alt+Win+화살표`)로 패널 사이를 다닐 때 손에 맞는지, 동률의 "맨 위 · 맨
  왼쪽" 규칙이 어색하지 않은지. 어색하면 최근 포커스(tmux식)가 다른 후보였다.
- VD: `/config/groq.key`를 만들고 오른쪽 Cmd 두 번. 첫 연결 지연, `cleanup timed out`이 매번 나면 `cleanup_timeout`을
  늘리거나 끈다, SOF DMIC 앞부분이 0인지(VD design 위험 1).

## 다음 후보 (새 서브프로젝트는 design부터, 방향은 사용자가 고른다)

- KH가 남긴 것(`carryover.md`의 KH 절): 키보드마다 다른 `keyboard=`(DM이 칸 번호를 `Context.device`로 실어 자리를 만들었다 —
  `swap_alt_meta`를 칸마다 고르면 된다). init 정리는 IK-M0, 장치별 수정키는 DM이 닫았다.
- 커널 7.4 longterm 이동(12월 중순 예상, `carryover.md`의 KU 항목). 그 뒤 0.1.4(KU + BT).
- BT 비목표에서 실기가 요구하면: Broadcom BT firmware(위험 6), `input.conf`의 `UserspaceHID` · `ClassicBondedOnly`, HID 배터리
  (`HID_BATTERY_STRENGTH`, BS design `scope` 행이 대비해 둔 자리). 오디오(A2DP)는 사용자가 뺐다 — 다시 열려면 코덱 + 오디오 서버.
- 렌더: 부분 갱신은 DR + SB로 닫았다. 남은 축은 GPU 가속뿐이다(키 하나 0.42ms 가운데 present 0.27이 커널 쪽, DR design "안 하는 것").
  실기 없이 할 수 있는 작은 것은 큰 kitty 이미지의 그리기 비용 하나(`carryover.md`).
- PD 비목표: `tars.conf`의 휠 방향, 포인터 가속. SE 비목표: 키 입력이 남은 선택을 지우기(ghostty식) · 키보드 `y` 뒤에도 남기기.
- CB 범위 `workspace`(`docs/specs/2026-10-05-tars-clipboard-scope-design.md` 비목표 1).
- VD 비목표: 상주 프로세스로 연결 재사용(첫 연결 지연이 크면), 알림음, hold 모드.
- AU 비목표 10: SoundWire 코덱 노트북(`sof_sdw`), side-codec 스피커 앰프(실기가 요구하면).
- 패키지 매니저는 Homebrew로 닫았다(PM). 자체 매니저는 나중에 다시 논의(`carryover.md`의 PM 절). 이미지 뷰어는 Homebrew 위에서(`carryover.md`의 "이미지 뷰어 메모" — 기본 이미지에 뷰어를 넣지 않는다, 사용자 결정 2026-10-03). USB 동글은
  층 A(UW) · 층 B + rtl8xxxu(UB)로 끝났고 남은 것은 실제 동글이 근거를 줄 때.
- IPv6는 후보가 아니다 — IPv4만 지원한다(사용자 결정, 2026-10-31, `docs/decisions/feedback_ipv4_only.md`). 다시 여는 조건은 IPv6 망의 제품 탑재.
- vim 런타임 싣기는 2026-10-27에 착수 전 취소했다(`docs/decisions/user_editor_use.md`). 실측은 `docs/specs/2026-10-27-tars-vim-runtime-design.md`.
- 그보다 작은 것과 간헐은 `docs/guides/carryover.md`. 대부분 실기나 간헐의 다음 근거를 기다린다.

## 이어받는 사람이 볼 것

- Docker는 OrbStack이다(메모리 12GB). 소켓이 없다고 나오면 `orb start`. 호스트 디스크가 가득 차면(ENOSPC) 체인이 `ld.lld`에서
  죽고 OrbStack이 내려간다 — 비운 뒤 `orb start`(MC 중에 한 번).
- 부팅 없이 1분에 보는 검사는 `make quick`(`quick_check.sh`) — shellcheck(note까지) · Zig fmt · ast-check · shared · init 빌드. 호스트
  Zig는 `/opt/homebrew/bin/zig`(0.17). init의 `zig build test`는 macOS에서 안 끝난다 — 컨테이너에서 돌린다(BT-M1에서 다시 겪었다).
  push마다 CI(`checks.yml`)가 같은 것과 컨테이너 안 `zig build test`를 돌리고 README 배지가 그 결과다. 빨강이 `sha256sum` ·
  `curl`이면 우리 코드가 아니다 — `gh run rerun`.
- 새로 받은 저장소는 `make container`가 이미지를 ghcr.io에서 받는다(1.5GB, 없거나 오프라인이면 Dockerfile로 굽는다 — GI-M0).
  첫 빌드가 linux-firmware 662MB를 `kernel/src/firmware/`에 받고 `clean()`이 지우지 않는다. `terminal/prepare.sh`가
  `stb_image.h`도 받는다(`terminal/vendor/`, 커밋 안 함).
- `shared/`는 init과 terminal이 함께 컴파일하는 파일의 자리다. 순수해야 한다(libc · 로그 없음) — init이 libc를 안 링크한다.
  그 파일을 고치면 두 빌드가 다시 돈다(`zig build --summary all`로 보인다).
- initrd는 두 archive다. `gzip -dc initrd.cpio | cpio -it`에 firmware가 안 나온다(measurements 62). 그 파이프라인을 `if` 안에 두면
  pipefail이 gzip의 EPIPE를 거짓 빨강으로 올린다(BT-M2 체인의 첫 판) — 파일에 받고 따로 본다.
- 이 저장소의 셸 작업은 zsh다. `"$n:lib"`처럼 `$var` 뒤에 `:`가 오면 수식어로 읽혀 글자가 깨진다 — `${n}:lib`(BT-M0 실측 2).
- 실칩 무선 · 블루투스는 PCIe도 USB도 아직 한 번도 안 떴다. 실기와 실제 장치가 생기면 그것이 새 사실이다.
- 세션 문서(HANDOFF · MEMORY · `docs/guides` · `docs/decisions`)의 중복을 2026-11-01에 걷어냈다 — 사실 하나는 한 자리에 두고 나머지는
  포인터다. 닫은 서브프로젝트의 경과를 HANDOFF에 다시 쌓지 않는다. 문서 속 줄 번호 · 배열 길이는 낡으니 인용하기 전에 코드에서 다시 본다.
