---
name: project_daemon_supervision
description: dhcpcd와 chronyd가 감독 목록 안이다 — -B로 pid를 지키고, chronyd의 서버는 sourcedir로 나중에 온다(DS-M0~M2, 2026-09-27 종료)
metadata:
  type: project
---

dhcpcd와 chronyd는 `init`이 스스로 `children`에 넣는 `Kind.service`다(DS 때 2 · 3번 칸,
TC-M2가 wifi 칸을 앞에 끼워 지금은 `SLOT_DHCPCD = 3` · `SLOT_CHRONYD = 4`, `main.zig`).
label은 `service dhcpcd` · `service chronyd`이고 `services.d`의 같은 이름은 건너뛴다.

- dhcpcd는 `-B`다. manager mode는 lease 전에 배경으로 가서 PID 1이 쥔 pid가 곧 죽는다 —
  `-B`를 빼면 어떻게 조용히 초록인지는 measurements 61. `-B`여도 나중에 꽂힌 동글을 같은
  pid로 잡는다(DS-M0 실측 7).
- `-j /dev/console`은 남겼다. `-B`에서는 줄이 두 벌이 되지만 `[pid]` 줄머리가 체인의 판정
  근거다.
- chronyd 앞의 30초 기다림을 지웠다. `ntp=dhcp`면 설정이 `sourcedir
  /run/tars/chrony.sources`이고 hook이 `dhcp.sources`를 쓴 뒤 `chronyc -h
  /run/chrony/chronyd.sock reload sources || true`. chronyd는 뜰 때도 그 디렉터리를 읽는다.
- 그룹 SIGTERM은 돌고 있던 dhcpcd hook도 죽인다. 다음 lease가 다시 쓴다.
- 게이트의 SLIRP는 option 42를 안 주므로 hook의 reload 경로는 게이트 안에서 안 돈다 —
  증거는 DS-M0 실측 5 하나다.

Why: 두 데몬이 목록 밖이면 죽어도 안 뜨고, 사람이 `tars-service`로 못 다룬다(SV 비목표 5).

How to apply: 감독 목록에 넣을 데몬은 갈라지지 않게 띄운다. execve 앞에 우리 코드를
두지 않는다 — 기다림이 필요하면 데몬의 기능(sourcedir 같은)으로 옮긴다. 판정은 "살아
있다"가 아니라 "쥔 pid가 곧 그 데몬인가"로 한다. [[project_boot_services]] ·
[[project_service_control]] · [[project_time_discipline]]
