---
name: project_service_control
description: "떠 있는 서비스를 사람이 멈추고 띄우는 tars-service와 그 통로(PID 1의 SOCK_SEQPACKET 소켓 /run/tars/init.sock)를 세운 서브프로젝트(CT-M0~M2, 2026-09-27 종료). 시그널은 프로세스 그룹에, 요청한 죽음은 빨리 죽음으로 안 센다. 규칙은 control.zig에 anytype으로 두어 호스트 검사가 본다. 게이트는 service/check.sh의 부팅 D"
metadata:
  node_type: memory
  type: project
---

# Service Control (CT)

design은 `docs/superpowers/specs/2026-09-27-tars-service-control-design.md`(결정 8 · 실측
1~13). SV 비목표 4를 목표로 옮긴 것이다. 사용자가 후보 넷(패키지 매니저 · IPv6 · 서비스
제어 · dhcpcd/chronyd 감독) 중 이것을 골랐고, 동사 넷(`status` · `stop` · `start` ·
`restart`)과 통로(소켓)를 정했다.

무엇이 섰나.

- `init/src/control.zig` — 통로의 양 끝(`open` · `receive` · `reply` / `dial` ·
  `awaitReply`), 감독 규칙(`apply` · `reaped` · `overdue` · `wantsRunning` · `stateOf`),
  글자(`parseRequest` · `row` · `parseRow`). 규칙은 `Child`를 모르고 필드 이름으로만
  만진다(`anytype`) — `control_test.zig`가 가짜 구조체로 전부 본다.
- `main.zig` — listen fd가 버튼 fd 옆에서 `poll`된다. `Child`에 `hold` · `kill_at`.
- `init/src/service_cli.zig` — `/usr/bin/tars-service`. PID 1은 곧바로 답하고 기다림은
  클라이언트가 진다(8초). exit code 0 · 1 거절 · 2 통로 없음 · 3 시한 · 64 사용법.
- 체인 `service/check.sh`의 부팅 D — ssh `ControlMaster` 연결 하나 위로 친다. 그 연결은
  제 세션을 가진 `sshd-session`이 들고 있어 `stop sshd` 뒤에도 산다.

Why: SV가 서비스를 띄우고 감독하게 했지만 사람이 떠 있는 것을 다룰 길이 없었다. 죽이면
되살아나고, 포기된 것은 다음 부팅까지 그대로였다.

How to apply:

- 서비스에 시그널을 보낼 때는 그룹(`kill(-pid)`)이다. 서비스는 `setsid`로 제 그룹의
  리더라 그룹 번호가 곧 pid다. `exec` 없이 쓴 스크립트에 리더에게만 보내면 셸만 죽고
  일꾼은 PID 1의 고아로 남는다(실측 5, 반사실 CF3).
- 사람이 요청한 죽음은 빨리 죽음으로 세지 않는다. 세면 restart 셋에 포기된다(실측 6).
- `receive`는 `MSG_TRUNC`로 원래 길이를 받아 64를 넘은 요청을 가른다. 답은
  `MSG_NOSIGNAL`로 보낸다. listen fd는 `CLOEXEC`다 — 반사실 CF4가 서비스의 자식에게
  새는 것을 부팅 D의 검사 26이 잡는다.
- 요청이 `poll`을 깨우므로 SIGTERM에 곧 죽는 서비스는 12ms에 `stopped`다. M0은 거둠까지
  1초를 예상했다 — 거둠이 느린 것은 요청이 없을 때뿐이다.
- 감독 루프는 거두는 바퀴와 띄우는 바퀴가 다르다. 그 사이에 클라이언트가 `stopped`를 한
  번 볼 수 있다 — "멈춘 채로 있는가"는 시간을 두고 따로 봐야 한다(반사실 CF2가 검사 18을
  통과하고 19에서 죽었다).
- `zig build test`의 끝줄은 판정이 아니다. 검사가 병렬로 돌아 실패가 있어도 다른 검사의
  `PASS`가 끝에 온다. 종료 코드와 `error` · `FAIL`로 가른다.
- 체인에 `… | grep -q`를 쓰면 GA-M0의 진입 검사가 게이트를 시작하지 않는다. `grep …
  >/dev/null`로 쓴다(CT-M2가 첫 루트 게이트에서 걸렸다).
- 부수 발견: PID 1의 전원 버튼 fd에 `CLOEXEC`가 없어 콘솔 셸 · 서비스와 그 자식이
  물려받는다(실측 7). `docs/guides/lessons.md`의 이월 숙제에 있다.

관련: [[project_boot_services]] · [[project_init_supervisor]] ·
[[feedback_boot_never_blocks]] · [[project_gate_chain_composition]]
