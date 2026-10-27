# CR-M0 — reload가 chronyd를 바꾸는 세 길

Date: 2026-10-28
Design: `docs/specs/2026-10-27-tars-clock-reload-design.md`
Status: 끝났다(2026-10-28). Task 1 `771ddd3`. 검사 32가 섰고 mutation(`rewrote`에 `false`)이 차례 a에서 잡혔다. 루트 게이트 22/22(9분 47초, prebuild 289 + lanes 296초, net 196초).

구현 중에 바뀐 것 둘 — 차례 a의 시리얼 대기를 `restarting service chronyd on request`에서 steer의 `reload: service chronyd restart`로
바꿨다(앞의 줄은 검사 30이 이미 남긴다). 주석 고침에 `firewall.zig`의 같은 옛 문장을 더했다(그런 자식은 지금 `audio.zig`의 일꾼).

## 이 milestone이 끝나면

- net 체인 부팅 A의 검사 30 뒤에 검사 32가 있다. `tars-config set ntp=dhcp|off|10.0.2.2`와 `tars-config reload`를 차례로 쳐서
  chronyd 칸의 restart · stop · start를 한 번씩 본다.
- `power.zig`의 `resetToDefault` 주석이 지금 구조(그런 자식은 `audio.zig`의 일꾼 하나)를 말한다.
- `carryover.md`에서 chronyd reload 항목이 빠진다. 루트 게이트 22/22.

## 착수 전에 확정한 것

1. 판정에 쓰는 줄(코드에서 확인, HEAD `8b0fd44`).
   - 화면: `ntp: <옛> -> <새>`(set의 답, `config_edit`), `service chronyd: restarts|stops|starts`(`steer`).
   - 시리얼: `tars-init: restarting service chronyd on request`(감독 루프가 restart를 거둘 때, `main.zig` 955행 근처),
     `tars-init: service chronyd stopped on request`(951행 근처), `tars-init: started service chronyd (pid N, …)`(458행 근처),
     `Selected source 10.0.2.2`(chronyd).
2. 화면 판정은 검사 31처럼 줄머리 `\| `를 붙여 그 줄의 처음에서 맞춘다. 친 명령의 에코(`tars-config set ntp=dhcp`)와 섞이지
   않는다.
3. 차례 a의 파일 판정은 `echo cr$(grep -c sourcedir /run/tars/chrony.conf)` → 화면 `cr1`. `clock.prepare`가 `steer`보다 먼저
   파일을 쓰므로 `restarts`를 본 뒤에 치면 된다. 키는 검사 19 · 31이 이미 쓰는 이름들이다(`shift-4 shift-9` · `minus` ·
   `slash` · `dot` · `shift-0`).
4. 차례 a의 pid 판정은 `started service chronyd (pid` 줄 수가 검사 32 시작 때보다 하나 는 것. 검사 30도 chronyd를 한 번 다시
   띄웠으므로 절대 수가 아니라 시작 때의 수와 비교한다.
5. 차례 c의 판정은 `Selected source 10.0.2.2` 줄 수가 차례 c 직전보다 는 것(검사 30과 같은 30초 창).
6. 진단은 `nw_reload_diag`를 그대로 부른다(design 결정 3). 그 함수의 `$LOG`는 부팅 A에서 `$LOGA`다.
7. 시리얼 대기는 부팅 A의 `wait_log`(90초)를 쓴다.

## Task 1: 검사 32와 주석

- `net/check.sh`: 검사 30 뒤, "부팅 A를 끈다" 앞에 검사 32. 머리 주석의 부팅 A 사슬에 한 줄.
- `init/src/power.zig`: `resetToDefault` 주석의 "지금 그런 자식은 `clock.zig`의 것 하나다 …" 문단을 지금 사실로 고친다.
- net 체인 단독으로 초록을 본다. mutation(`doReload`의 `rewrote` 자리에 `false`)으로 차례 a가 빨개지는지 보고 되돌린다.
- commit 하나.

## Task 2: 닫기

- 루트 게이트 22/22.
- `carryover.md`에서 항목을 지운다. design Status, 이 plan Status, `completed.md` 한 행, 기억 `project_clock_reload.md` ·
  `MEMORY.md` 한 줄, `HANDOFF.md`. 소개 페이지에는 안 넣는다(내부 작업).
- commit 하나.
