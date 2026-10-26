# 이월 숙제

`docs/guides/lessons.md`(허브)에서 2026-10-26에 떼어 냈다(LS-M0). 규칙 — 줄 번호를 적지 않는다, 낡은 항목은 고치거나
지운다, 서브프로젝트 하나에만 해당하는 것은 그 design에 — 은 허브의 것을 따른다.


BV(2026-10-20)가 남긴 것 — GF-M0(2026-10-24)이 닫았다.

- [x] 병렬 레인이 `kernel/initrd.cpio`를 동시에 다시 조립하는 경합(BV-M0 루트 게이트 1회차의 PM ENOENT · UT 1d(c)). 루트 게이트는
      prebuild 뒤 `TARS_PREBUILT_INITRD=1`을 두어 체인의 `make_initrd.sh`가 건너뛰고, 회차마다 inode를 대조한다. tools 1d는 `TMPDIR`
      아래 사본에 `INITRD_OUT`으로 만든다([[project_gate_flakes]]).

BS(2026-10-09)가 남긴 것.

- [x] `dictation` B4(`read -s got something`)의 10초 창 — GF-M1(2026-10-24)이 같은 검사의 앞 기다림과 같은 20초로 넓혔다. BS-M0
      루트 게이트 1회차에서 한 번 빨갰고 로그의 둘째 `got[]`는 `ret` 바로 다음 프레임에 있었다(글자가 프롬프트에 들어간 것이 아니다).
- [ ] 실기 노트북에서 볼 것 셋. 칸이 안 뜨면 `cat /sys/class/power_supply/*/type`으로 `Battery`가 있는지 본다(로그
      `terminal: battery> scan seen=… present=… pick=…`도 같은 것을 말한다). `capacity` 파일이 없는 배터리는 칸이 `  ?%`인 것이
      정상이다(ACPI의 `full_cap_broken`). 어댑터를 꽂았다 뺄 때 색이 곧바로 초록 · 회색으로 바뀌는지 본다 — 바뀌지 않으면 firmware가
      ACPI notify를 안 보내는 기계이고 60초 주기가 받는다.

VD(2026-10-06)가 남긴 것.

- [ ] `render` 검사 28(vim의 `R` 뒤 underline 커서)이 VD-M2의 루트 게이트 2회차에서 한 번 빨갰다(`vt=block`인 채 15초). 앞선 루트 게이트
      여섯(열두 회차)과 그 뒤의 재실행은 초록이었고 M2는 terminal · 커널 · initrd 내용을 안 바꿨다 — 간헐이다. 시리얼 로그가 `mktemp`라
      `R`이 vim에 닿았는지(`key>` 줄 · `-- REPLACE --`)를 못 봤다. GF-M1(2026-10-24)부터 모든 체인의 로그가 `out/gate-logs/`에
      남는다(루트 게이트는 `<시각>/TR-M2-<회차>/`) — 다음에 빨개지면 그 로그에서 `key>` 줄과 `-- REPLACE --`부터 본다. 판정은 안
      넓혔다(원인을 모른다).
- [ ] 정리의 상한 `cleanup_timeout`(기본 1.5초)이 실기의 첫 연결(DNS · TLS)을 덮는지는 게이트로 못 잰다. 실기에서 `cleanup timed out`이
      매번이면 값을 늘리거나 `cleanup = off`. 크면 연결을 붙잡아 두는 상주 프로세스(VD design 결정 1의 (d) · 위험 5)를 다시 연다.
- [ ] 비밀번호 판정(`ICANON && !ECHO`)이 못 보는 자리 — 자기 편집기로 가리는 프롬프트(fish의 `read -s`)에는 글자가 들어간다(Enter는 안
      붙는다). 겪으면 그 프로그램의 모양을 적는다.

AU(2026-10-06)가 남긴 것.

- [ ] 늦은 내장 카드(AU design 위험 14). M1의 일꾼은 `controlC0`이 서는 순간 있는 카드만 `alsactl init`한다. 카드가 여럿인 AMD
      노트북이나 SOF가 firmware를 늦게 올리는 Intel 노트북에서 늦은 카드가 꺼진 채 남으면 — 일꾼이 `/dev/snd`가 잠잠해질 때까지
      기다리거나 `follow`가 새 카드에 `alsactl -U init N`을 부른다. 실기에서 겪은 뒤 정한다.
- [ ] firmware가 게스트 RAM에 늘 있다. 무선 77 + 소리 42 = 119개, 원본 약 14MB가 더 늘어 512MB 게스트의 `MemAvailable`이 약 183MB다
      (AU design 위험 16). 다음에 firmware를 더하는 일은 이것을 함께 본다 — 초기 ramfs에서 빼서 늦게 붙이는 길이 있는지.
- [ ] `audio` 검사 5의 사각파 하한 40,000은 부하 아래 최소 47,425에서 정했다(AU design 실측 17). 루트 게이트가 `tone`으로 빨개지면
      dmix xrun이 더 커진 것이다 — `doubled` · `zero`를 먼저 본다.
- [ ] 체인이 `grep -a 'terminal: screen>' "$LOG" | tail -n 1`로 화면 줄을 직접 읽는 자리 67곳은 printk에 잘린 줄을 못 잇는다
      (`joined_screen_dump`는 `wait_for_screen`만 쓴다). 그 자리가 이상한 값으로 빨개지면 로그의 `screen>` 줄 안에 커널 시각 표식이 있는지
      먼저 본다.
- [ ] 실기에서 볼 것 — `running-tars.md`의 소리 절. SOF 노트북에서 `Firmware file:` · `Topology file:` 두 줄, IPC4 `-3ch` topology 없음
      (위험 12), 잭 입력 장치가 키보드 · 포인터 판정에 안 걸리는지(위험 2).

PD(2026-10-05)가 남긴 것.

- [x] 마우스 보고 — PD-M4가 같은 날 했다(design 결정 12). 자식이 마우스 모드를 켰으면 ghostty의 `encodeMouse`로 보고하고 우리
      선택은 Shift 끌기, 대체 화면의 휠은 모드 1007로 화살표 키. 남은 것은 design 비목표 14~18(1004 포커스 보고 · XTSHIFTESCAPE ·
      OSC 52 · 가로 휠과 포인터 모양 · 보고 끄기 설정).
- [ ] 터치패드 출발값 셋(180ms · 2% · 배율)을 실기에서 손으로 본다(PD design 위험 3). 고친 값은 `touchpad_test`에도.
- [ ] 누름과 첫 칸 이동 사이에 출력이 오면 선택이 한 줄 어긋날 수 있다(PD design 위험 2). 겪으면 tracked pin으로.
- [ ] 가지치기가 copy mode를 닫을 때 `input.State.mode`가 `.copy`에 남는다(PD design 위험 5, PD 전부터 있던 자리).
- [ ] 커널 코드 배치가 TCG의 initramfs 풀기 시간을 움직인다. 커널을 바꾼 뒤 `install` 부팅 7의 `init waited`가 500ms 아래로
      내려가면 그 신호다(지금 `delay_use=4`에 900ms). 아래 실측 76. 커널을 안 바꿔도 루트 게이트의 동시 부하만으로 창이 닫힌
      적이 있다(HC-M0 첫 회, 2026-10-26 — 풀기 5.5초, `sda2`가 `/init`보다 50ms 먼저). 단독 재실행이 PASS(1300ms)이고 initrd
      크기가 같으면 부하다. 한 번 더 겪으면 `delay_use`를 5로 올리는 것을 본다.

서브프로젝트 후보(패키지 매니저 · IPv6)는 `HANDOFF.md`에 있다.
여기는 그보다 작은 것과, 닫아 두어서 다시 열려면 근거가 필요한 결정이다. 끝난
서브프로젝트는 `docs/guides/completed.md`의 완료 표가 목록이다.

미룬 것.

- [ ] `git-delta`(SM 비목표 1) · `Ctrl+R`을 게이트가 치는 것(SM 비목표 2 — TUI라
      체인이 매달린다. 안 하는 쪽에 근거가 쌓여 있다).
- [ ] 무선의 남은 것(WL 비목표). Intel BE201과 `sc-a0-fm-c0`(커널 6.18이 받는 번호의
      firmware가 linux-firmware-20260916에 없다 — 커널을 올릴 때 같이 본다) · 보드별 변형
      firmware(ath11k `nfa765` · ath12k `ncm865`) · WPA-Enterprise · 실칩 판정(실기가 생기면).
- [ ] USB 무선 동글의 나머지(UW 비목표 1). 층 A(rtw88 USB 일곱 · rtw89 둘 · MT7921U ·
      MT7925U)는 UW가 켰다(2026-09-28). 남은 것은 층 B와 `RTL8XXXU`다. 코드는 0줄이고
      게이트는 UW의 세 층(심볼 · modinfo alias · usbcore 등록 줄)을 그대로 늘리면 된다.
      층 B(MT7601U · MT76x0U · MT76x2U · rt2800usb ·
      ath9k_htc)는 커널 +348KB · firmware 약 0.4MB이고 `ATH9K_PCI`가 따라 켜진다.
      `RTL8XXXU`는 +82KB · 약 0.3MB인데 `NEW_LEDS`가 있어야 붙고, 그것이 `HID_APPLE` ·
      `INPUT_LEDS`를 끌고 온다 — 실제 Apple 키보드의 fn 키가 커널에서 바뀔 수 있어
      `keyboard=apple`과 부딪칠 수 있고, 게이트는 못 본다. 넣으려면 `HID_APPLE`을 먼저
      정한다. `mt7601u.bin` · `mt7662.bin` · `mt7662_rom_patch.bin`은 맨 위 이름이라
      `WHENCE`의 `Link:`로 실체를 찾고, `rtlwifi/rtl8723bu_bt.bin`은 이 릴리스에 없다.
- [ ] firmware 96MB가 게스트 RAM에 늘 있다(WL 위험 5). 게이트의 512MB에서 `MemAvailable`
      213MB. 체인이 메모리로 흔들리면 여기부터 본다.
- [ ] 실기에서 LAN의 다른 컴퓨터가 게스트 포트에 붙는 것. 게이트는 SLIRP 안에서만
      판정한다(IN 비목표 3 · FW 비목표 3).
- [ ] seed `tars.conf`의 `ntp:` 주석이 TD 전의 설명("부팅할 때 한 번만 묻고")으로 남아
      있다(EL-M0 planner가 찾았다). 고치면 seed의 글자가 바뀌어 `config` 체인을 함께 본다.
      (seed가 화면을 넘는 문제는 TC-M0부터 없다 — config 1차가 `cat` 대신 `tars-config`를 보고 그 출력은 15줄이다.)
- [ ] chronyd의 reload(`ntp` 키)를 게이트가 안 본다 — net 검사 31의 부팅에 ntp가 없다(TC-M2 plan 확정 4). 호스트 검사가 step 논리를 덮고
      `clock.prepare`는 부팅이 같은 꼴로 부른다. ntp 부팅(net 부팅 A)에 `set ntp=…` · `reload`를 얹으면 덮인다.
- [ ] net 검사 31의 간헐(TC-M2 루트 게이트 두 판, 셋 중 둘)의 진짜 원인. Task 5b가 set의 답을 기다리고 진단을 찍게 했고 그 뒤 4판 초록이다.
      다시 빨개지면 진단의 세 덩어리(마지막 화면 · `cat /config/tars.conf` · `reload of` 뒤 tars-init 줄)로 가린다 — 가설은 "set이 파일을 못
      바꿨거나 늦었다"(빨갰던 회차의 시리얼에 `reload of`만 있고 steer 줄이 없었다. 단독에서는 넷 중 영). GF-M1부터 그 회차의
      시리얼 로그가 `out/gate-logs/<시각>/TD-M2-<회차>/`에 남으니 진단 출력과 로그를 함께 본다.

HI가 남긴 것 둘은 2026-09-13에 사용자가 뺐다. "한글 기호 확장은 당분간
마일스톤에서 제거한다. 팥알입력기의 나머지 trait도 당분간 고려 대상 아님."
다시 집게 되면 `docs/specs/2026-08-31-tars-hangul-input-design.md`
의 비목표 절이 그 둘을 그대로 갖고 있다. 그중 `ESC라틴` trait은 2026-10-05에
사용자가 다시 집어 EL-M0이 했다(`esc_latin=on|off`, [[project_escape_latin]]).

렌더 쪽 — 미룬 것이고 근거가 있다.

- [ ] 부분 갱신(dirty 추적). Render Speed(RS-M0~M3, 2026-10-11)가 그 앞의 축 셋(칠하기 방식 · 프레임
      수 · 모드셋)을 먼저 줄였다 — 키 하나의 그리기 11.6 → 4.3ms, `seq 1 200000` 5.5 → 2.2초(남은 81%는
      VT 파서). 하느냐는 사용자가 다시 판단한다. 하게 되면 출발점은 "지난 프레임의 셀 격자와 이번
      `cells()`를 행 단위로 비교"이고 손상 사각형을 `present`(DIRTYFB)의 clip으로 넘긴다
      (`project_render_speed`). 게이트의 `style>` · `ink>` 덤프는 `cells()` 전체와 프레임버퍼를 되읽으므로
      덤프는 그대로 두고 잔상을 보는 검사를 새로 써야 한다.
- [ ] 큰 kitty 이미지의 그리기 비용. 화면 가득한 이미지가 게이트에서 프레임을 9.6 → 69.7ms로
      늘린다(TG 실측 7). `image.draw`가 픽셀마다 64비트 나눗셈 둘로 원본 좌표를 구하는 것이
      원인으로 보이고, 줄마다 열 대응표를 한 번 만들면 줄일 자리다. 다시 집을 신호는 위와 같다.
- [ ] `pty.zig`가 창 크기를 `ws_xpixel = 0` · `ws_ypixel = 0`으로 알린다. 이미지 뷰어(`chafa` ·
      `icat` 등)는 `TIOCGWINSZ`의 픽셀로 셀 크기를 셈하므로, 뷰어를 들일 때 `cols × CELL_W` ·
      `rows × ROW_HEIGHT`로 채운다. TG-M1이 라이브러리에 한 일(`width_px`)을 pty 쪽에도 하는
      것이다. 뷰어는 2026-10-03에 기본 이미지 대신 패키지 매니저로 넘겼다(Debian `chafa`가
      `.so` 69개 · 44.6MB를 끌고 온다).

닫아 둔 결정들 — 다시 열려면 근거가 필요하다.

- [ ] 붙여넣기가 모드를 닫아야 하는가. CM-M2가 "안 닫는다"로 정했다.
- [ ] `w`가 줄을 넘어 다음 줄의 첫 단어로 가야 하는가. CN-M0이 "안 간다"로 정했다.
- [ ] `?`(아래로 검색). CN design 결정 4가 뺐다.
- [ ] 검색 결과의 실시간 갱신. CS design 결정 7이 "안 한다"로 정했다.
- [ ] init이 직접 포트를 듣는 것. IN 비목표 5 — 다시 열릴 조건은 "게스트가
      무엇을 서빙해야 하는지가 정해지는 것".

## IP-M2가 남긴 것 (그대로 이월)

- `Ctrl+←`/`Shift+←`는 여전히 맨 `ESC [ D`로 샌다. TUI 앱이 생기면 그때.
- DECCKM(`ESC O` 분기)은 부팅 게이트가 영영 못 밟는다. `input_test`가
  `Context.cursor_keys`를 주입해 대신 본다.
- `keymap`에 comptime 앵커가 박혔다. 표 중간에 줄을 끼우면 컴파일이 막힌다.
  `KEY_Z`도 그 앵커 중 하나다.

## TR-M2가 남긴 것 (그대로 이월)

- `Terminal.ScrollViewport`의 이름이 `PageList.Scroll`과 다르다.
  `.bottom`·`.delta`이지 `.active`·`.delta_row`가 아니다. 그리고 `.pin`이
  아예 없다.
- 렌더가 PTY 분기 안에만 있었다. `needs_redraw`로 루프 끝에 뺐다.
