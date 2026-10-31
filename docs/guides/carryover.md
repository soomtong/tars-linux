# 이월 숙제

`docs/guides/lessons.md`(허브)에서 2026-10-26에 떼어 냈다(LS-M0). 규칙 — 줄 번호를 적지 않는다, 낡은 항목은 고치거나
지운다, 서브프로젝트 하나에만 해당하는 것은 그 design에 — 은 허브의 것을 따른다.


BS(2026-10-09)가 남긴 것.

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
- [ ] `audio` 부팅 A의 `speaker-test` 간헐(UB-M2 루트 게이트 1회차, 2026-10-31, lane 17). 출력이 `0 - Front Left|Write error: -32,Broken
      pipe| 1 - Front Right`라 판정 줄 `[ 0 - Front Left| 1 - Front Right]`와 안 맞았다 — ALSA underrun(EPIPE)이 두 목소리 사이에
      끼었고 같은 부팅의 `aplay` 사각파(tone=47952 · doubled=0)와 그 뒤 두 채널 판정은 멀쩡했다. 단독 재실행 PASS, 2회차 루트
      게이트도 본다. 로그 `out/gate-logs/20261031-140338/AU-M3-1/`. 판정은 안 넓혔다 — 한 번 더 겪으면 `speaker-test` 줄에서
      `Write error` 토막을 빼고 보는 것(underrun은 소리가 끊긴 것이지 채널이 바뀐 것이 아니다)이 후보다.
- [ ] 체인이 `grep -a 'terminal: screen>' "$LOG" | tail -n 1`로 화면 줄을 직접 읽는 자리 67곳은 printk에 잘린 줄을 못 잇는다
      (`joined_screen_dump`는 `wait_for_screen`만 쓴다). 그 자리가 이상한 값으로 빨개지면 로그의 `screen>` 줄 안에 커널 시각 표식이 있는지
      먼저 본다.
- [ ] 실기에서 볼 것 — `running-tars.md`의 소리 절. SOF 노트북에서 `Firmware file:` · `Topology file:` 두 줄, IPC4 `-3ch` topology 없음
      (위험 12), 잭 입력 장치가 키보드 · 포인터 판정에 안 걸리는지(위험 2).

PD(2026-10-05)가 남긴 것.

- [ ] 터치패드 출발값 셋(180ms · 2% · 배율)을 실기에서 손으로 본다(PD design 위험 3). 고친 값은 `touchpad_test`에도.
- [ ] 누름과 첫 칸 이동 사이에 출력이 오면 선택이 한 줄 어긋날 수 있다(PD design 위험 2). 겪으면 tracked pin으로.
- [ ] 커널 코드 배치가 TCG의 initramfs 풀기 시간을 움직인다. 커널을 바꾼 뒤 `install` 부팅 7의 `init waited`가 500ms 아래로
      내려가면 그 신호다(지금 `delay_use=4`에 900ms). 아래 실측 76. 커널을 안 바꿔도 루트 게이트의 동시 부하만으로 창이 닫힌
      적이 있다(HC-M0 첫 회, 2026-10-26 — 풀기 5.5초, `sda2`가 `/init`보다 50ms 먼저). 단독 재실행이 PASS(1300ms)이고 initrd
      크기가 같으면 부하다. 한 번 더 겪으면 `delay_use`를 5로 올리는 것을 본다.

서브프로젝트 후보(패키지 매니저 · USB 동글 층 B)는 `HANDOFF.md`에 있다. IPv6는 후보가 아니다(`docs/decisions/feedback_ipv4_only.md`).
여기는 그보다 작은 것과, 닫아 두어서 다시 열려면 근거가 필요한 결정이다. 끝난
서브프로젝트는 `docs/guides/completed.md`의 완료 표가 목록이다.

미룬 것.

- [ ] 게이트 포트가 ephemeral 범위 안이다 — 컨테이너의 `ip_local_port_range`는 32768~60999이고 체인의 포트(45455~45495, VD의 TLS
      45492 · monitor 포트들)가 전부 그 안에 있다. 다른 lane이 나가는 연결(curl · nc · SLIRP hostfwd)의 출발 포트로 그 번호를
      받은 순간 그 체인의 `bind()`가 `Address already in use`로 진다. UB-M2 루트 게이트 2회차(2026-10-31)에서 VD-M0이
      `openssl s_server died at startup`으로 그렇게 빨갰다(다른 체인은 45492를 안 쓴다, 단독 재실행 PASS, 로그
      `out/gate-logs/20261031-141844/VD-M0-1/`). 고치는 법은 확인했다 — `docker run --sysctl
      net.ipv4.ip_local_reserved_ports=45455-45499`가 컨테이너 안에서 먹힌다(네임스페이스별 sysctl이라 권한이 더 필요
      없다). 넣을 자리는 Makefile `IN_CONTAINER`와 lessons "게이트를 돌리고 읽는 법"의 `docker run` 줄, CI `container` job은
      게이트를 안 돌리니 그대로. 작은 서브프로젝트(GF 꼴) 하나다.
- [ ] `git-delta`(SM 비목표 1) · `Ctrl+R`을 게이트가 치는 것(SM 비목표 2 — TUI라
      체인이 매달린다. 안 하는 쪽에 근거가 쌓여 있다).
- [ ] 무선의 남은 것(WL 비목표). Intel BE201과 `sc-a0-fm-c0`(커널 6.18이 받는 번호의
      firmware가 linux-firmware-20260916에 없다 — 커널을 올릴 때 같이 본다) · 보드별 변형
      firmware(ath11k `nfa765` · ath12k `ncm865`) · WPA-Enterprise · 실칩 판정(실기가 생기면).
- [ ] USB 무선 동글의 나머지. 층 A는 UW(2026-09-28), 층 B 다섯과 `RTL8XXXU`는 UB(2026-10-31)가 켰다.
      남은 것은 드라이버 작성자가 안 본 장치 목록(`RT2800USB_UNKNOWN` · `RTL8XXXU_UNTESTED`)과
      다른 계열(`rtl8187` · `zd1211rw` · `carl9170` · `ar5523` · `p54usb` · brcmfmac USB)이다 — 실제
      동글이 그 목록에 있을 때 켠다(UB design 비목표 2 · 5). 켜는 법은 UB와 같다: 부모 메뉴까지
      `-k`로 켜고 해소본에서 `=y`를 센 뒤 `firmware=` 줄에서 이름을 센다.
- [ ] firmware 96MB가 게스트 RAM에 늘 있다(WL 위험 5). 게이트의 512MB에서 `MemAvailable`
      213MB. 체인이 메모리로 흔들리면 여기부터 본다.
- [ ] 실기에서 LAN의 다른 컴퓨터가 게스트 포트에 붙는 것. 게이트는 SLIRP 안에서만
      판정한다(IN 비목표 3 · FW 비목표 3).
- [ ] net 검사 31의 간헐(TC-M2 루트 게이트 두 판, 셋 중 둘)의 진짜 원인. Task 5b가 set의 답을 기다리고 진단을 찍게 했고 그 뒤 4판 초록이다.
      다시 빨개지면 진단의 세 덩어리(마지막 화면 · `cat /config/tars.conf` · `reload of` 뒤 tars-init 줄)로 가린다 — 가설은 "set이 파일을 못
      바꿨거나 늦었다"(빨갰던 회차의 시리얼에 `reload of`만 있고 steer 줄이 없었다. 단독에서는 넷 중 영). GF-M1부터 그 회차의
      시리얼 로그가 `out/gate-logs/<시각>/TD-M2-<회차>/`에 남으니 진단 출력과 로그를 함께 본다.
- [ ] firewall 검사 18의 간헐(DR-M1 루트 게이트 셋 중 하나, 2026-10-29). `tars-config firewall allow 7072` 뒤 호스트가 붙었는데
      빈 값이고 열 번의 `read -t 5`가 timeout 없이 곧바로 끝났다(회차 35초 — 통과한 회차는 58초). 7072의 리스너는 `nc -l -p 7072` 한
      번짜리다. 읽히는 모양은 검사 8이 막힌 포트에 붙었을 때 SLIRP이 버린 SYN을 재전송하다가 allow로 포트가 열린 순간 닿아 `nc`가 그
      묵은 연결을 받고 끝난 것(실측 73이 "언제 다시 보내는지는 재지 않았다"고 남긴 자리). 혼자 3/3은 초록이었다. 고치는 길은 검사
      18이 검사 8이 건드린 적 없는 포트를 열어 보거나, 7072의 리스너를 다시 듣는 꼴로 두는 것. 다음에 빨개지면 그 회차 로그의
      `fwm2-tcp-7072` 줄 뒤 `/proc/net/tcp`를 먼저 본다 — DR-M1 plan의 결과 절에 분석이 있다.

HI가 남긴 것 둘은 2026-09-13에 사용자가 뺐다. "한글 기호 확장은 당분간
마일스톤에서 제거한다. 팥알입력기의 나머지 trait도 당분간 고려 대상 아님."
다시 집게 되면 `docs/specs/2026-08-31-tars-hangul-input-design.md`
의 비목표 절이 그 둘을 그대로 갖고 있다. 그중 `ESC라틴` trait은 2026-10-05에
사용자가 다시 집어 EL-M0이 했다(`esc_latin=on|off`, [[project_escape_latin]]).

렌더 쪽 — 미룬 것이고 근거가 있다. 부분 갱신은 Dirty Rows(DR-M0~M2, 2026-10-30)가 했다([[project_dirty_rows]]).

- [ ] 큰 kitty 이미지의 그리기 비용. 화면 가득한 이미지가 게이트에서 프레임을 9.6 → 69.7ms로
      늘린다(TG 실측 7). `image.draw`가 픽셀마다 64비트 나눗셈 둘로 원본 좌표를 구하는 것이
      원인으로 보이고, 줄마다 열 대응표를 한 번 만들면 줄일 자리다. DR 뒤로 이미지가 있는 패널은 매
      프레임 통째로 그리므로(design 결정 3) 이미지가 떠 있는 동안은 부분 갱신의 이득도 없다 — 다시 집을
      신호는 실기에서 이미지가 뜬 채 화면이 느린 것이다.

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
