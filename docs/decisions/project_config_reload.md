---
name: project_config_reload
description: tars-config reload가 init에 재부팅 없이 tars.conf와 services.d를 다시 읽게 하는 TC-M2 · M3(2026-10-07). 키를 넷으로 가른다(지금 · 다음에 뜰 때부터 · 화면을 다시 띄워야 · 안 한다), 조이고(firewall on) → 데몬 → 셸 · env → 푼다(firewall off), init이 실효 설정을 들고 칸은 늘 열셋이며 "설정이 껐다"(config_off)는 사람이 멈춘 것(hold)과 다르다, reload terminal이 화면을 새 argv로 다시 띄운다, 드러난 잠재 버그 kill(-pid)
metadata:
  type: project
---

Config Tool(TC, [[project_config_tool]])의 M2 · M3이다. design은 `docs/specs/2026-10-07-tars-config-reload-design.md`(결정 11 + 덧붙임),
plan은 `docs/plans/2026-10-07-tars-config-reload-tc-m2.md` · `-tc-m3.md`. PID 1을 고친 첫 두 일이라 plan의 "착수 전에 확정한 것"에 PID 1
패닉을 막는 근거 표(M2 열한 자리 · M3 일곱 자리)가 있다 — init은 ReleaseSafe이고 PID 1의 패닉은 커널 패닉이다. 순수한 쪽 `reload.zig`에는
`unreachable`과 `.?`가 없고 길이를 먼저 보며, 호스트 검사 `reload_test`가 전부 덮는다.

## 결정 — 다시 조사하지 말 것

- 동사 둘, 문은 `tars-config`다(결정 1). `init.sock`(CT의 SEQPACKET)에 `config`(실효값 열둘과 대기 키)와 `reload`를 더했고, 사람은
  `tars-config reload [terminal]`을 친다. 인자 없는 `tars-config`가 두 칸이 됐다 — 파일(다음 부팅)과 init이 지금 쓰는 값이 다르면 그 줄 밑에
  주석 한 줄(같은 줄 끝이 아니라 다음 줄 — 출력이 그대로 `tars.conf`여야 한다). SIGHUP · inotify · `/run` 파일은 버렸다.
- 키를 넷으로 가른다(결정 2). 지금 — `net` · `ntp` · `firewall`(데몬을 띄우고 멈추는 길이 DS · CT에 있고 nft는 상태가 없다). 다음에 뜰
  때부터 — `shell` · `shell_config` · `timezone`(콘솔 셸 · ssh 로그인 · 서비스가 받고 떠 있는 셸은 안 죽인다). 화면을 다시 띄워야 — 자판 넷 ·
  `esc_latin` · `clipboard` · `keyboard`(terminal의 argv라 대기로 적고 `reload terminal`을 기다린다). 화면 재시작은 묻지 않는 명시 동사다.
- 원자성과 순서(결정 3). init의 파서가 한 마디라도 하면 아무것도 안 바꾼다(`configLog`가 수를 센다). 실효값과 diff해 바뀐 키만 건드린다.
  순서는 조이고(firewall on) → 데몬 → 셸 · env → 푼다(firewall off) — FW 결정 5의 "규칙이 서기 전에 주소가 붙는 틈이 없다"를 reload에서도.
- 감독 루프를 막지 않는다(결정 4, [[feedback_boot_never_blocks]]). PID 1이 기다리는 것은 `tars.conf` 읽기와 nft 한 번뿐이고 둘 다 부팅이
  이미 기다리는 것이다. 데몬을 띄우고 멈추는 것은 목표(`config_off` · `hold`)만 바꾸고 루프의 다음 바퀴가 한다.
- init이 실효 설정을 든다(결정 5). `supervise()`에 `Live`(실효 Config · 화면이 받은 Config · argv 글자 버퍼 · env 블록)를 넘기고, 데몬
  셋(wpa_supplicant · dhcpcd · chronyd)의 자리를 늘 두어 칸이 열셋이다. `Child.config_off`("설정이 껐다")는 `hold`("사람이 이 부팅에서
  멈춤")와 다르다 — status에 안 보이고 `tars-service start`가 거절한다. 그래서 `tars-service status` 출력은 한 줄도 안 바뀌었다(DS-M2의
  service 검사 17이 그것을 지킨다 — mutation이 증명했다).
- `services.d`도 다시 읽는다(결정 11 — lead가 비목표를 받지 않고 재서 정하라고 했고 유한했다). 부팅의 `services.discover`를 한 번 더
  부르고 규칙 넷 — 있는 이름은 안 건드린다 · 사라진 이름은 멈춘다 · 다시 나타나면 되살린다 · 새 이름은 빈 칸에(멈추는 중인 칸은 안 준다,
  칸이 없으면 다음 부팅). 그래서 `tars-config ssh on` 뒤에도 `reload`면 된다.
- 바로잡은 전제 — init은 설정을 한 번 읽지만 그것으로 지은 것 넷(`/run/tars/chrony.conf` · `/etc/passwd`의 root 셸 · sshd `tars-env.conf` ·
  env 블록)을 남기고 reload가 그 넷을 다시 짓는다. `net=off`로 뜬 부팅에는 dhcpcd의 칸이 없었다(그래서 칸을 늘 둔다). 방화벽을 끄는
  길이 init에 없었다(`nft flush ruleset`이 새로). terminal argv의 값은 여덟(argv[0] 빼고), 4번은 키보드 장치 경로라 설정이 아니다.
- `reload terminal`(M3). 대기가 없으면 아무것도 안 보내고 "nothing pending". 있으면 `tars-config`가 "the screen restarts now — every pane,
  its shell and the clipboard go away"를 먼저 찍고 보낸다(그 명령이 대개 그 화면 안에서 돌아 답이 못 올 수 있다). init은 argv의 설정 칸
  일곱을 `live.cfg`로 바꾸고 탈출로(rc 플래그)를 부팅의 판정으로 다시 세운 뒤 CT의 `restart`와 같은 길(요청한 죽음은 빨리 죽음으로 안
  센다)로 SIGTERM을 보낸다. 콘솔 셸은 같은 동사로 안 다룬다 — M2가 그 칸의 경로 · argv를 이미 바꿔 두므로 `exit`하면 새 셸로 뜬다(게이트가
  `kill -9 $(pgrep -t ttyS0)`로 본다 — 콘솔 셸의 tty는 `console`이 아니라 `ttyS0`이다).
- 드러난 잠재 버그 — `kill(-pid)`. CT-M1 결정 4 규칙 3("SIGTERM을 무시하면 유예 뒤 SIGKILL을 그룹으로")이 `supervise`의 `overdue` 갈래에
  모든 자식에 대해 들어갔지만, 시한을 세우는 `control.apply`는 서비스에만 불려 비서비스에는 한 번도 닿지 않았다. `reload terminal`이
  terminal(setsid를 안 해 제 그룹이 없다)에 그 길을 쓰는 첫 자리였다 — `kill(-pid)`는 ESRCH로 아무도 안 죽인다. SIGTERM · SIGKILL 둘 다
  서비스만 그룹, 나머지는 pid로 고쳤고 mutation 두 판(SIGTERM만 되돌림 → 17초 늦게 초록, 둘 다 되돌림 → `sent SIGKILL to group 39`로
  빨감)이 둘이 서로를 받치는 것을 보였다.

## 게이트가 남긴 것

- M2 루트 게이트 처음 둘이 net 검사 31(`reload did not stop dhcpcd after net=off`)에서 빨갰고, 단독 넷과 `/tmp`를 묶은 루트 게이트 하나는
  초록이었다 — 간헐이다. 시리얼에 `reload of`만 있고 steer 줄이 없어 "set이 파일을 못 바꿨거나 늦었다"가 맞아 보이지만 결정적 근거가
  없다. Task 5b — `set`의 답(`| net: dhcp -> off`)을 화면에서 본 뒤에 reload를 치고(firewall 19 · config 1차도), 실패하면 마지막 화면 ·
  `cat /config/tars.conf` · `reload of` 뒤 init 줄을 찍는다. 그 뒤 4판 초록.
- 이월 숙제 둘 — chronyd의 reload(`ntp` 키)를 게이트가 안 본다(그 부팅에 ntp가 없다. ntp 부팅에 `set ntp=…` · `reload`를 얹으면 덮인다).
  간헐 31의 진짜 원인(다시 빨개지면 5b의 진단 세 덩어리로 가린다).
- 게이트가 못 보는 것 — tty에서 echo를 끄고 묻는 길, `--country`, `firewall deny`, 실기의 `reload terminal`(사용자가 친다).

관련: [[project_config_tool]] · [[project_daemon_supervision]] · [[project_service_control]] · [[project_boot_services]] ·
[[project_firewall]] · [[feedback_boot_never_blocks]] · [[project_shutdown_signals]]
