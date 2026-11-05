# HANDOFF: 맥북 지원(MB · HS · DB · BW) 닫힘 · DB-M1(파티션 지정) 닫힘 · 0.1.4 배포됨 — 다음은 맥 실기 확인

## 목표

사용자 요청(2026-11-04 밤): MacBook Air 11" 2011 · MacBook Pro 15" 2013(Retina)에 설치, 설치기가 macOS 옆을 고르는 듀얼 부팅, 그 뒤 패치
버전 배포. 사용자가 잠들며 남은 결정을 전부 Claude에게 맡겼고, 끝까지 갔다. 다음은 실기에서 아래 "사용자가 확인할 것"의 맨 앞 절.

## 현재 브랜치

`main` = origin/main(push됨), tag `v0.1.4` = `da909bb` push됨. `gh-pages`도 push됨(worktree `../tars-linux-pages`).
작업용 worktree `../tars-linux-hs` · `../tars-linux-db`와 브랜치 `hs` · `db`는 합친 뒤 지웠다.

## 완료된 작업 (2026-11-04~05)

- [x] MB-M0 — `MOUSE_BCM5974` · `ACPI_SBS`, machine 체인의 커널 장치 표 검사와 bcm5974 등록 줄. pointer 체인 금지 목록에서 bcm5974를 뺐다
  (PD 비목표 10의 한 갈래). 되접기 정규화는 따로 커밋(HP 때 빠진 ext4 줄 여섯). lead 직접.
- [x] HS-M0 — 논리 그림자 + 늘리는 present(`terminal/src/scale.zig`), `display_scale=auto|1|2|3`(`ARGC` 14), 체인 `hidpi`(monitor 45502). 서브에이전트.
- [x] DB-M0 — `tars-install <disk> --beside`, TARS 파티션을 GPT 이름으로, 포맷 전 대조 둘, init 후보 126, 체인 `dualboot`(포트 없음),
  `docs/guides/running-tars.md`의 macOS 절. 서브에이전트.
- [x] BW-M0(2026-11-05, 사용자 요청) — MacBookAir4,1 내장 BCM43224를 `brcmsmac`으로, firmware 둘. Pro의 BCM4331 · BCM4360은 못 연다
  (BW 비목표). 루트 게이트 29/29, 16분 48초.
- [x] 루트 게이트 29/29, 16분 30초(prebuild 포함, lanes 667초), 잘린 줄 0(`667240c`).
- [x] 0.1.4 — `VERSION` 커밋 · tag · `make iso` · smoke(`TARS 0.1.4`) · release(ISO 136,466,432 B, sha256 `11add999…01ce`) · 내려받아 `OK` ·
  `data.js` releases와 timeline 셋. 기록은 `docs/decisions/project_release.md`.
- [x] 맥 디스크의 빈 자리 검토(2026-11-05, 사용자 요청) — `diskutil apfs resizeContainer`는 크기만 주면 빈 자리를 남긴다. 포맷되는 것은
  triple을 붙이거나 디스크 유틸리티의 "파티션"을 쓴 경우이고, `diskutil eraseVolume free free <id>`로 되돌린다(`running-tars.md` macOS 절
  2번).
- [x] DB-M1(2026-11-05, 사용자 "continue") — `tars-install /dev/sda3`이 디스크 유틸리티가 만든 FAT · exFAT 파티션(또는 빈 파티션)과
  앞뒤의 빈 구간에 TARS 셋을 놓는다. EFI · APFS · HFS+ · Recovery · NTFS는 YES 전에 거절. 목록이 GPT 디스크 밑에 파티션 줄을 단다.
  `dualboot` 체인에 GUI 맥과 부팅 5. lead 직접. 첫 판 빨강은 체인의 대기(둘째 설치의 `done.`) — plan "결과" 절. 루트 게이트 29/29,
  16분 57초, 잘린 줄 0(`f9e2c44`).
- [x] 닫는 묶음 — design 셋 `Status:`, `completed.md` 세 행, 기억 셋(`project_macbook_hardware` · `project_hidpi_scale` · `project_dual_boot`) + `MEMORY.md`.

## Claude가 맡아 정한 것 (뒤집을 것이 있으면 design의 결정 번호로)

- "15 2013"은 두 세대(MacBookPro10,1 · 11,2/11,3) 다 대상(MB 결정 1). `HID_APPLE`은 끈 채 — Fn 조합(PageUp 등)이 없다(MB 위험 3).
- 무선(Broadcom) · 밝기 · 키보드 백라이트 · 절전은 범위 밖(MB 비목표).
- Retina는 present에서 정수배로 늘리기, auto는 논리 1280×800 이상의 가장 큰 정수(HS 결정 1 · 3).
- 듀얼 부팅은 빈 공간에만 깐다. APFS 줄이기는 macOS의 `diskutil`(DB 비목표 1). 기본 부팅은 macOS, 매번 Option 키(DB 결정 11).
- 0.1.4를 커널 7.4 전에 냈다 — 11-01 결정을 이번 요청이 대신한 것으로 읽었다.

## 시도했으나 실패한 접근

- 없음. 첫 판 실수 셋은 기억에: machine 체인의 `grep -x`(별칭 줄 꼬리), pointer 체인의 bcm5974 금지(다른 체인의 음성 검사),
  컨테이너 여럿이 같은 `.zig-cache`로 terminal을 동시에 빌드하면 깨진다(`project_hidpi_scale` 4).

## 남은 작업

- [ ] 사용자: 맥 두 대에서 실기 확인(아래 첫 절)
- [ ] 다음 서브프로젝트 고르기(아래 "다음 후보")

## 다음 에이전트에게

이 저장소의 규칙(CLAUDE.md): 큰 편집은 먼저 설명, 매 편집 뒤 `git diff --stat` · `git diff | rg '^-'`, 명령은 Claude가 실행, 커밋은
사용자 승인 뒤. init의 `zig build test`와 terminal 빌드는 컨테이너에서(macOS에 Linux 헤더가 없다, 컨테이너에는 `rg`가 없다 —
`grep`). 체인 하나 돌리기: `docker run --rm --sysctl net.ipv4.ip_local_reserved_ports=45455-45599 -v "$PWD":/workspace -w /workspace
tars-devcontainer ./pointer/check.sh`. 체인을 동시에 돌릴 때는 한 컨테이너 안에서(같은 트리의 `.zig-cache` 경합). 커널 심볼을 켜기 전에
`rg -n '<SYMBOL>' */check.sh`로 음성 검사를 찾는다. 새 체인의 monitor 포트는 45503부터(45502는 HS).

## 지금 상태 (2026-11-05)

- 마지막으로 닫은 것은 MB · HS · DB(같은 요청 하나, design `docs/specs/2026-11-04-tars-{macbook-hardware,hidpi-scale,dual-boot}-design.md`).
  최신 공개 버전 0.1.4(2026-11-05, tag `v0.1.4` = `da909bb`). 맥 실기 확인까지 같은 번호로 거듭 낸다(`feedback_release_iteration`).
- 체인은 스물아홉이다(`check.sh`의 `CHAINS`, 끝이 `HS-M0:./hidpi/check.sh` · `DB-M0:./dualboot/check.sh`). 마지막 루트 게이트 29/29, 16분 57초(`f9e2c44`, DB-M1).
  바깥 망 체인은 PM · MI 둘이다. 게이트를 돌리고 읽는 법 · 로그 위치(`out/gate-logs/`)는 `docs/guides/lessons.md`.
- 닫은 서브프로젝트의 경과 · 함정 · 숫자는 여기 두지 않는다 — 한 줄 요약은 `docs/guides/completed.md`의 표, 결정과 함정은
  `docs/decisions/`의 기억 파일이다. 최근 것부터 MB · HS · DB(11-05) → PS · KK · DM(11-04) → IK · MI · PM · HP(11-03) → KH · BT(11-02) → KU(11-01).
- 테스트 흐름: 실기는 쓰지 않고 테스트마다 `tars-install <disk> --wipe`로 새로 깐다.

## 사용자가 확인할 것 (실기 또는 실제 장치가 있을 때)

- MB · HS · DB — 맥 두 대(이번 판의 본론, 게이트는 드라이버 등록까지만 봤다).
  - 준비: macOS에서 Time Machine 백업 → `diskutil list` → `diskutil apfs resizeContainer disk0s2 <크기>`(HFS+면 `diskutil resizeVolume`)로
    4GiB 넘는 빈 공간 → 0.1.4 ISO를 USB에 `dd`(`docs/guides/running-tars.md`의 macOS 절). 디스크 유틸리티의 "파티션"으로
    MS-DOS(FAT) · ExFAT 파티션을 만들어도 된다(DB-M1). APFS로 만들었다면 `diskutil eraseVolume free free disk0sN`으로 빈 자리로.
  - 전원을 켤 때 Option → "EFI Boot"로 USB가 보이는지(ISO의 EFI 파티션). 안 보이면 그것이 새 사실이다.
  - `tars-install` 목록에 내장 디스크가 `GPT: EFI, macOS (APFS); N GB free`로, 그 밑에 파티션 줄이 보이는지(FAT 파티션을 만들었으면
    `<- tars-install /dev/sda3 installs here`) → `tars-install /dev/sda --beside` 또는 `tars-install /dev/sda3` → 재부팅하며
    Option → TARS-BOOT가 "EFI Boot"로 보이는지(DB 위험 3 — Air 2011은 확인됨, 2026-11-05: `/dev/sda3` 지정 설치 → EFI Boot → TARS
    터미널). Pro 2013은 아직. macOS가 그대로 뜨는지도(Air는 사용자가 준비 중 macOS를 지워 볼 수 없다).
  - Air 2011 실기 결과(2026-11-05, 사용자): 트랙패드 · 속도 좋음, Cmd · Option과 Cmd+Option+화살표 패널 이동 정상, 소리 정상(speaker-test의
    핑크 노이즈 — MB 위험 1은 안 일어났다), 배터리 칸 정상. Bluetooth 어댑터가 `Controller … BlueZ 5.82 [default]`로 잡혔다(보정
    펌웨어 없이 — BT 위험 6은 안 일어났다). 내장 무선이 5GHz 망에 붙어 주소를 받고 `curl`이 바깥까지 간다(BW 위험 1 풀림). BT 장치 페어링은 아직.
    게스트에 `ping`이 없다 — 다음 판의 작은 숙제(`iputils-ping`). 실기가 드러낸 거친 곳 셋(`tars-config help`에서 bluetooth를 못
    찾음, `tars-config bluetooth=on`이 쓰는 법만 찍음, 꺼진 버스에서 `bluetoothctl`이 SIGABRT)은 고쳤다 — help의 "turning things on" 절,
    `missing_set`, `/usr/bin/bluetoothctl` 감싸개(bluetooth 체인 검사 8).
  - Pro 2013 실기(2026-11-05): Limine 메뉴가 GOP 화면에 보인다(KU의 이월 확인 하나가 풀렸다). Retina 2배가 잘 보이고(HS 결정 3),
    트랙패드 · 키보드 · 배터리 · Bluetooth 정상. 기종은 MacBookPro11,x(코덱 SSID `106b:5e00`, CS4208). 소리가 안 났던 원인은 init의
    오디오 일꾼이 카드 0만 기다린 것 — 카드 0(HDMI 쪽 HDA)이 i915 없이 안 서서 노드 권한 · 믹서가 그대로였다. 아무 카드나 기다리게 고쳤다
    (audio 체인 부팅 C가 `snd_hda_intel.index=1`로 보고, 되돌리면 빨개지는 것도 봤다). 실기 확인은 다음 0.1.4에서.
    내장 Wi-Fi(10,1 BCM4331 · 11,x BCM4360)는 사용자 결정으로 대기 — 조사는 `carryover.md`의 "맥 실기" 절.
  - 트랙패드: 한 손가락 이동 · 탭 · 두 손가락 스크롤, 로그 `pointer> open … kind=touchpad`. 손에 안 맞으면 `touchpad_accel`부터(MB 위험 2).
  - 키보드: `keyboard> open … kind=apple`, Cmd · Option 자리. Fn 조합이 없는 것이 거슬리는지(MB 위험 3).
  - 소리: `speaker-test`. Air4,1이 안 울리면 MB 위험 1(`snd_hda_intel.model=mba42`).
  - 배터리 칸이 뜨는지, 어느 길인지(`ls /sys/class/power_supply`).
  - Retina: 로그 `kms: scale 2 (2880x1800 -> 1440x900)`. 펌웨어가 낮은 모드를 주면 `scale 1`로 나온다(HS 위험 2). 출력이 쏟아질 때 늦지
    않은지, `sudo tars-config set display_scale=1` · `tars-config reload` · `tars-config reload terminal`로 1배와 비교.
  - 외장 USB 마우스 · 키보드를 함께.
- 무선: Air 2011은 내장(`tars-config wifi …`, 로그 `bcma` · `brcmsmac`, 안 되면 BW 위험 1). Pro 2013은 내장이 없다 — 유선 USB 어댑터나
  USB 무선 동글(UW · UB 계열). 내장 Bluetooth는 세 기종 다 `bluetooth=on` · `bluetoothctl`(보정 펌웨어 없이 돈다 — 안 되면 BT 위험 6).

- PS: 노트북 터치패드 + USB 마우스를 함께 쓰며 — 기본값에서 마우스 휠은 앞으로 = 위의 글, 두 손가락은 내용이 손가락을
  따라가는지. `sudo tars-config set mouse_scroll=natural` · `tars-config reload` · `tars-config reload terminal` 뒤 마우스만 뒤집히는지.
  로그 `pointer> open … kind= scroll= accel=`가 장치마다 맞는지 — 터치패드가 `kind=mouse`로 열리면 design 위험 1(`carryover.md`에).
  가속: `touchpad_accel=5` · `mouse_accel=5`로 — 천천히 칸 하나를 고르는 손이 그대로인지(배율 1), 빠르게 밀 때 화면 끝까지 한두 번에
  가는지, 10이 너무 세거나 1이 이미 거슬리는지. 맞지 않으면 값은 `pointer.ACCEL_V_LOW_MPX` · `ACCEL_V_HIGH_MPX` · `ACCEL_GAIN_MAX` ·
  `ACCEL_IDLE_US` 넷이다(design 위험 2). 손가락을 뗐다 다시 댄 첫 이동이 튀지 않는지(위험 3).

- KK: 일반 노트북 내장 키보드 + Apple 키보드(USB 또는 BT)를 함께 꽂고 — 두 키보드에서 Option+← · Cmd+←(PC 키보드는 Alt 자리가
  Cmd)가 각자 맞는지, 로그 `terminal: keyboard> open … kind= bus= vendor=`가 둘에 맞게 찍히는지(BT Magic Keyboard가 bus `0005` ·
  vendor `004c`인지). Mac 배열 서드파티 키보드가 있으면 그 vendor(design 위험 1 — `pc`로 읽히면 `carryover.md`의 KK 절). MacBook 내장
  (2015년 전)은 `kind=apple`이어야 한다.

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

- KH가 남긴 것(`carryover.md`의 KH 절)은 셋 다 닫혔다 — init 정리는 IK, 장치별 수정키는 DM, 키보드마다 종류는 KK. 남은 KH 항목은
  실기의 근거를 기다리는 자동 반복 · 칸 순서 · 두 노드 키보드다. KK가 남긴 것은 vendor가 배열을 말하지 않는 키보드(`carryover.md`의 KK 절).
- 커널 7.4 longterm 이동(12월 중순 예상, `carryover.md`의 KU 항목). 0.1.4는 그 전에 냈다 — 7.4는 0.1.5의 후보.
- BT 비목표에서 실기가 요구하면: Broadcom BT firmware(위험 6), `input.conf`의 `UserspaceHID` · `ClassicBondedOnly`, HID 배터리
  (`HID_BATTERY_STRENGTH`, BS design `scope` 행이 대비해 둔 자리). 오디오(A2DP)는 사용자가 뺐다 — 다시 열려면 코덱 + 오디오 서버.
- 렌더: 부분 갱신은 DR + SB로 닫았다. 남은 축은 GPU 가속뿐이다(키 하나 0.42ms 가운데 present 0.27이 커널 쪽, DR design "안 하는 것").
  실기 없이 할 수 있는 작은 것은 큰 kitty 이미지의 그리기 비용 하나(`carryover.md`).
- PS 비목표: 기본 속도(`*_speed`), 장치 이름별 설정, 스크롤 가속. SE 비목표: 키 입력이 남은 선택을 지우기(ghostty식) · 키보드 `y` 뒤에도 남기기.
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
