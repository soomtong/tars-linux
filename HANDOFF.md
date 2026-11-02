# HANDOFF: Keyboard Hotplug 진행 중(2026-11-02) — KH-M0 끝, 다음은 KH-M1

## 지금 상태 (2026-11-02)

- 열린 서브프로젝트는 Keyboard Hotplug(KH)다. design `docs/specs/2026-11-02-tars-keyboard-hotplug-design.md`(결정 9 · 위험 7 ·
  여러 키보드 시나리오 검토 S1~S13), M0(실측 1~5) 끝. 다음은 `docs/plans/2026-11-02-tars-keyboard-hotplug-kh-m1.md` — 키보드를
  포인터의 길(처음 훑기 + uevent)로 terminal이 스스로 열고, `key_state` 하나를 같이 쓰고, 빠지면 `releaseHeld`. M0이 연 것: 부팅
  키보드를 빼면 지금 terminal이 CPU 하나를 다 쓴다(실측 4), QMP로 키보드를 골라 치려면 화면에 묶는다(measurements 101).
- 그 전에 닫은 것: Bluetooth. 2026-11-01 사용자가 외출하며 "이 세션에서 모든 작업을 완료, 모든 결정을 Claude에게 위임"했고, 그
  위임으로 Bluetooth(BT-M0~M2)를 design부터 닫기까지 한 세션에 했다. 범위(클래식 + BLE HID, 오디오 제외)와 0.1.4 시점(커널 7.4
  뒤)만 사용자가 정했고 나머지 결정은 `docs/specs/2026-11-01-tars-bluetooth-design.md`의 추천안이다 — 돌아와서 뒤집을 것이
  있으면 그 문서의 결정 번호로 말하면 된다.
  - 섰다: 커널 BT 스택 · USB/PCIe HCI · HIDP · uhid, firmware 157(initrd 93 → 117MB), Debian BlueZ 5.82 + dbus-daemon을 init이
    감독(감독 칸 2 · 3번), `tars.conf` 열셋째 키 `bluetooth=off|on`, 페어링은 `bluetoothctl`, 키는 `/config/bluetooth`. 체인 스물셋째
    `bluetooth/check.sh`가 가상 컨트롤러 둘의 페어링 · 재시작 · 끄기를 본다. 사용 설명은 `docs/guides/running-tars.md`의 "블루투스" 절.
  - 사용자가 알아야 할 틈 하나: BT 키보드는 아직 글자를 못 친다. terminal이 부팅 때 init이 고른 키보드 하나만 읽는다(BT design 확인 7 ·
    비목표 1). 마우스는 PD의 uevent 핫플러그로 끝까지 간다. 후속 후보 "Keyboard Hotplug"가 `carryover.md`의 BT 항목에 있다.
  - 컨테이너 이미지가 바뀌었다(Dockerfile 태그 `ee4aa97122b5`). 다른 기계는 `docker rmi tars-devcontainer && make container`.
    main에 push되면 CI가 같은 태그를 ghcr.io에 올린다.
- 0.1.4는 커널 7.4 longterm 뒤에 낸다(사용자 결정, 2026-11-01). 그때 담길 것은 KU(슬롯 · 1GiB ESP · 6.18.60) + BT. 절차는
  `docs/decisions/project_release.md`의 일곱 단계 — `VERSION` 커밋 → tag → `make iso`. ISO가 약 23MB 커진다(Intel BT firmware).
- 마지막으로 닫은 것은 Bluetooth(BT-M0~M2, 2026-11-02). 닫은 서브프로젝트의 경과 · 함정 · 숫자는 여기 두지 않는다 — 한 줄 요약은
  `docs/guides/completed.md`의 표, 결정과 함정은 `docs/decisions/`의 기억 파일, 값은 design의 실측 절이다. 최근 것부터:
  - Bluetooth(BT-M0~M2, 11-02) — `docs/decisions/project_bluetooth.md`
  - Kernel Upgrade(KU-M0~M1, 11-01) — `project_kernel_upgrade.md`
  - Extend Repeat(ER-M0, 11-01) — `project_extend_repeat.md`
  - Shift Extend(SE-M0~M1, 11-01) — `project_shift_extend.md`
  - Multi Click(MC-M0~M2, 11-01) — `project_multi_click.md`
  - Reserved Ports(RP-M0, 11-01) — `project_reserved_ports.md`
  - USB Dongles B(UB-M0~M2, 10-31) — `project_usb_dongles_b.md`. 같은 자리에서 IPv6를 결정으로 닫았다(`feedback_ipv4_only.md`)
  - Ghcr Image(GI) · Vendor Sha256(VS) · Shellcheck Notes(SN) · GitHub Actions(GH-M0~M1, 10-30~31) — `project_github_actions.md`
  - 그 전은 `docs/guides/completed.md`.
- 최신 공개 버전 0.1.3(2026-11-01, tag `v0.1.3` = `055228d`). 0.1.3 뒤로 KU와 BT가 쌓였고 아직 내지 않았다.
- 체인은 스물셋이다(`check.sh`의 `CHAINS`, 마지막이 `BT-M2:./bluetooth/check.sh`). BT 체인은 monitor 포트를 안 쓴다 — 새 체인의
  monitor 포트는 여전히 45495부터, 예약 범위 45455~45599(RP-M0). 마지막 루트 게이트(BT-M2): 23/23, 10분 25초(prebuild 약 310 + lanes 315초), verify 8208줄 전부 통과.
  게이트를 돌리고 읽는 법 · 로그 위치(`out/gate-logs/`)는 `docs/guides/lessons.md`. 다음에 어느 체인이 빨개지면 그 회차 로그부터 본다.
  `clean()`이 `out/`을 지우므로 그 자리에는 마지막 회차만 남는다 — 회차 사이 비교가 필요하면 게이트 전에 옮겨 둔다.
- 테스트 흐름: 실기는 쓰지 않고 테스트마다 `tars-install <disk> --wipe`로 새로 깐다.

## 사용자가 확인할 것 (실기 또는 실제 장치가 있을 때)

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

- Keyboard Hotplug — BT 키보드와 부팅 뒤 꽂은 USB 키보드가 글자를 치게. terminal의 키보드 하나(`keyboard_fd`)를 PD의 uevent 길로
  여러 개로(`carryover.md`의 BT 항목). BT가 끝났으니 이것이 없으면 BT 키보드의 값이 없다 — 첫 후보로 둔다.
- 커널 7.4 longterm 이동(12월 중순 예상, `carryover.md`의 KU 항목). 그 뒤 0.1.4(KU + BT).
- BT 비목표에서 실기가 요구하면: Broadcom BT firmware(위험 6), `input.conf`의 `UserspaceHID` · `ClassicBondedOnly`, HID 배터리
  (`HID_BATTERY_STRENGTH`, BS design `scope` 행이 대비해 둔 자리). 오디오(A2DP)는 사용자가 뺐다 — 다시 열려면 코덱 + 오디오 서버.
- 렌더: 부분 갱신은 DR + SB로 닫았다. 남은 축은 GPU 가속뿐이다(키 하나 0.42ms 가운데 present 0.27이 커널 쪽, DR design "안 하는 것").
  실기 없이 할 수 있는 작은 것은 큰 kitty 이미지의 그리기 비용 하나(`carryover.md`).
- PD 비목표: `tars.conf`의 휠 방향, 포인터 가속. SE 비목표: 키 입력이 남은 선택을 지우기(ghostty식) · 키보드 `y` 뒤에도 남기기.
- CB 범위 `workspace`(`docs/specs/2026-10-05-tars-clipboard-scope-design.md` 비목표 1).
- VD 비목표: 상주 프로세스로 연결 재사용(첫 연결 지연이 크면), 알림음, hold 모드.
- AU 비목표 10: SoundWire 코덱 노트북(`sof_sdw`), side-codec 스피커 앰프(실기가 요구하면).
- 패키지 매니저(`carryover.md`의 "이미지 뷰어 메모" — 기본 이미지에 뷰어를 넣지 않는다, 사용자 결정 2026-10-03). USB 동글은
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
