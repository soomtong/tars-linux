---
name: project_time_discipline
description: "시계를 chronyd에게 넘긴 서브프로젝트(TD, 2026-09-26 M0·M1). TS의 우리 SNTP를 지우고 init은 배관만 한다 — fork · 서버 결정 · /run/tars/chrony.conf · execve chronyd -d -u root. 커널이 주파수를 기억하고(driftfile 없이 다시 띄운 chronyd가 앞 값에서 출발), 같은 server가 두 번이면 먼저 적힌 쪽이 이기며, chrony는 주소가 붙기 전의 실패한 요청을 iburst로 세지 않는다"
metadata:
  node_type: memory
  type: project
---

# 시계를 chronyd에게 (TD)

design은 `docs/superpowers/specs/2026-09-26-tars-time-discipline-design.md`.
사용자가 2026-09-26에 chrony를 고르고, 목적으로 "오래 켜 둔 기계의 drift"를,
접근으로 "우리 SNTP를 전면 교체"를 골랐다. TS 결정 2("묻는 주체는 우리 코드")의
첫째 근거가 "어려운 부분(drift)을 뺐으니 누가 해도 같다"였고, 목적이 그 어려운
부분이 되면서 근거가 먼저 무너졌다([[project_write_or_reuse]]의 기준으로도 DHCP와
같은 쪽).

무엇이 섰나(M1).

- `init/src/clock.zig` — `start(net, ntp, envp)`가 fork하고, 자식이 서버를 정하고
  (`ntp=dhcp`면 `/run/tars/ntp_servers`를 최대 30초), `renderConf`로 세 줄
  (`server … iburst` · `makestep 1 3` · `cmdport 0`)을 쓰고, `chronyd -d -u root -f
  /run/tars/chrony.conf`로 execve한다. pid가 그대로라 종료의 SIGTERM이 chronyd에 닿는다.
- `power.resetToDefault()`는 남았다 — execve 전의 파일 기다림 동안 자식은 부모의
  핸들러를 갖고 있다. design 결정 2가 "지운다"고 적었다가 M1 plan이 뒤집었다.
- 이미지에 chrony · libseccomp2 · libedit2 · libbsd0 · libmd0, initrd에 chronyd ·
  chronyc(+425,905바이트).
- `net/ntp_stub.pl`의 시계가 흐른다(`출발 + 경과 × (1 + ppm/10^6)`). 멈춘 시계를
  상대로 chrony는 엉뚱한 주파수를 배운다.

Why: 한 번 뛰는 것은 SNTP로 충분했지만 drift를 길들이는 것(slew · 주파수 추정 ·
driftfile)은 chrony의 20년이다.

How to apply:

- chronyd의 사실 넷(TD-M0 · M1 실측). 게이트나 코드가 이것에 기댄다.
  1. 커널이 주파수를 기억한다. chronyd가 죽어도 `adjtimex`로 넣은 값이 남아, 다음
     chronyd가 driftfile 없이도 `Initial frequency F ppm`에서 출발한다. driftfile의
     증거는 한 부팅 안이 아니라 부팅을 넘어서 `read from PATH` 줄로 본다.
  2. 같은 `server`가 두 번이면 먼저 적힌 것이 이기고 뒤는 `Could not add source`.
     그래서 `confdir`를 맨 앞에 둔다(M2).
  3. 주소가 붙기 전에 뜬 chronyd는 실패한 요청을 버스트로 세지 않는다 — 기본 경로를
     기다리는 코드를 넣었다가 반사실로 1초 차이를 보고 걷어 냈다.
  4. 커널에 seccomp · IPv6가 없다. `-F`를 안 주고 `cmdport 0`을 준다.
- 반사실을 돌리기 전에 `git diff`로 바뀐 줄을 먼저 찍는다. `sd -F`가 Zig의 `\\`와
  줄바꿈을 못 맞춰 편집 없이 `PASS`가 나온 판이 있었다. 그리고 `net` 체인은 부팅 전에
  `zig build test`를 돌리므로, 코드를 바꾸는 반사실은 호스트 검사가 먼저 잡는다 —
  게이트 판정을 보려면 검사의 기대값도 함께 바꾼다.
- 체인의 게스트 로그는 컨테이너 `/tmp`의 mktemp다. 읽으려면 `-v 호스트:/tmp`로 문다.

관련: [[project_guest_network]] · [[project_write_or_reuse]] · [[project_measuring_tool_cost]] ·
[[feedback_boot_never_blocks]] · [[project_shutdown_signals]]
