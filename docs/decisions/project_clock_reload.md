---
name: project_clock_reload
description: "reload가 ntp 키로 chronyd를 바꾸는 세 길(restart · stop · start)을 net 부팅 A의 검사 32가 본다 — Clock Reload(CR-M0, 2026-10-28). 코드 0줄, `rewrote` 배선을 mutation으로 확인"
metadata:
  type: project
---

# Clock Reload (CR)

`carryover.md`의 "chronyd의 reload(`ntp` 키)를 게이트가 안 본다"를 사용자가 골랐다(2026-10-27). 설계는
`docs/specs/2026-10-27-tars-clock-reload-design.md`, plan은 `docs/plans/2026-10-28-tars-clock-reload-cr-m0.md`.

## 무엇을 세웠나

- `doReload`의 ntp 갈래는 `clock.prepare`(설정 파일을 다시 쓴다)의 답을 `reload.step`의 `now`와 `rewrote` 둘에 넘긴다. 두 함수는
  호스트 검사가 있지만 그 배선은 게이트가 안 지났다 — 검사 31의 부팅(`out/net.img`)에 ntp가 없어 chronyd 칸이 처음부터 꺼져 있다.
- net 부팅 A(ntp=10.0.2.2, stub이 답한다)의 검사 30 뒤에 검사 32. `tars-config set ntp=dhcp` → reload(restart, 설정에
  `sourcedir`, 새 pid) · `ntp=off` → reload(stop) · `ntp=10.0.2.2` → reload(start, `Selected source` 하나 더). 끝이 처음과 같다.
- mutation: `rewrote`에 `false`를 넣으면 차례 a에서 `reload did not restart chronyd after ntp=dhcp`로 빨갛다. 그때 진단은 set의 답과
  reload의 `ntp: 10.0.2.2 -> dhcp (now)`가 있고 `service chronyd: restarts`만 없다 — chronyd가 옛 서버로 살아 있는 상태다.
- 곁에서: `power.resetToDefault`와 `firewall.zig`의 주석이 "clock.zig의 자식이 서버 파일을 기다린다"는 옛 사실을 말했다. 지금 그런
  자식은 `audio.zig`의 일꾼(카드를 최대 5초 기다림) 하나다.

commit은 design `8b0fd44` · plan `79f43ed` · Task 1 `771ddd3` · 닫기. 루트 게이트 22/22(9분 47초, prebuild 289 + lanes 296초). 검사 32로 net 체인이 181 → 196초가 됐고 여전히 가장 긴 체인이라 lanes가 291 → 296초.

## 함정

- 부팅 A의 시리얼에는 검사 30(`tars-service restart chronyd`)이 이미 `restarting service chronyd on request`를 남긴다. reload의
  restart를 그 줄로 기다리면 곧바로 통과한다 — `tars-init: reload: service chronyd restart`(steer의 줄)와 `started service chronyd`
  줄 수로 가른다.
- SLIRP의 리스에는 option 42가 없다. reload 뒤 `ntp=dhcp`의 chronyd는 서버 없이 사는 것이 정상이다.

관련: [[project_time_discipline]] · [[project_daemon_supervision]] · [[project_config_tool]]
