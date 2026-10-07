---
name: project_config_tool
description: 게스트의 tars-config가 /config의 설정을 보고 · 고치고 · 적용하는 서브프로젝트 Config Tool(TC-M0 ~ M3, 2026-10-06 ~ 07). tars.conf는 줄 하나만 바꾸고 값은 init의 parse가 정한다(로그를 root의 configLog가 가로챈다), 남의 문법은 그 주인이 짓고 이 명령은 옮긴다, 이 명령의 파일을 가르는 것은 방화벽 하나, seed의 별칭 둘을 지웠다(옛 디스크는 알리기만). reload는 project_config_reload
metadata:
  type: project
---

Config Tool(TC)은 2026-10-06 사용자의 요청("tars-config 실행 파일을 만들어서 시스템 전체 세팅을 할 수 있게 … 쉘 스크립트가 아니라면
어떤 언어로")에서 열어 2026-10-07에 M3까지 닫았다. design은 `docs/specs/2026-10-06-tars-config-tool-design.md`(M0 · M1, 결정 17)와
`docs/specs/2026-10-07-tars-config-reload-design.md`(M2 · M3, 결정 11 — 기억은 [[project_config_reload]]), plan은
`docs/plans/2026-10-06-tars-config-tool-tc-m0.md` · `-tc-m1.md` · `2026-10-07-tars-config-reload-tc-m2.md` · `-tc-m3.md`이고 각 끝의
"실측한 것" 절이 값이다. 사용자 결정 셋 — seed의 별칭 `tars-config` · `tars-rc`는 지운다(cat과 다를 게 없다), 언어는 Zig, M1 · M2까지
끝까지("진정한 user experience 개선"). design · plan은 Opus planner 하나(`tc-design`)가 사본 넷(`/tmp/run/tc0` ~ `tc3`)에서 코드를 돌려
썼고, 구현은 Sonnet 구현자 하나(`tc-m0-impl`)가 글자 그대로 넣었다 — 네 milestone 모두 plan 코드를 고친 곳이 0이다.

## 자리 — Zig, init 아래의 셋째 실행 파일

`tars-install` · `tars-service`와 같은 길이다. `init/build.zig`의 `addExecutable`로 정적 바이너리(3.7MB)를 만들고 `make_initrd.sh`가
`/usr/bin`에 넣는다. 시스템 콜 쪽 `config_cli.zig` · `config_front.zig`와 순수한 쪽 `config_edit.zig` · `config_front_edit.zig`를 가르고,
순수한 쪽은 호스트 검사(`config_edit_test` · `config_front_edit_test`)가 덮는다. bash를 안 고른 이유는 `key=value` 파서가 셋째가
되고(config.zig · tars-dictate 뒤) init이 받는 값의 목록을 베껴야 해서다. 새 런타임은 [[feedback_scripting_runtimes]]가 막는다.

## 결정 — 다시 조사하지 말 것

- 값을 받을지는 init의 `config.parse`에 묻는다(TC 결정 3). `parse`는 실패를 돌려주지 않고 로그만 찍으므로, `config.zig`의 로그 24줄을
  `log()` 하나로 모으고 root가 `configLog`를 선언하면 그리로 간다(`@import("root")` · `@hasDecl`). init의 부팅 로그 바이트는 그대로다.
  가로채지 않으면 `set`이 틀린 값을 받는다 — mutation이 증명했다.
- `set`은 이기는 줄(마지막 줄) 하나만 바꾼다(결정 5). `save()`로 통째로 다시 쓰면 사람의 주석과 모르는 키가 사라진다. 없으면 끝에
  더하고, 정규형으로 쓰고, 하나라도 거절이면 아무것도 안 쓰고, 4096바이트를 넘으면 거절하고, 임시 파일에 쓴 뒤 `rename`한다.
- 키 목록과 값의 글자는 `Config`의 필드에서 컴파일 타임에 나온다(결정 4). 모르는 타입이면 `@compileError`.
- 별칭 둘은 seed에서 지우고 옛 디스크의 rc는 고치지 않는다(결정 6) — 깔린 rc는 사람의 것이다(SC 결정 7). `check`가 알리고 처방은
  running-tars의 "seed는 한 번만 깔린다" 절. config 체인 1차가 그 별칭으로 "fish가 rc를 읽었다"를 판정하고 있었고 그 판정은 `ls` 별칭이
  이어받았다.
- "언세팅"은 `reset`이다(줄을 지우지 않고 기본값을 적는다). `unset`은 "줄을 지운다"로 읽히므로 안 받고 `reset`을 가리키는 한 줄과 exit 64.
  `list`는 사용자의 지적("어떤 설정 정보를 쓸 수 있는지 알아야")으로 M0 수정 1에 들어왔다 — `help`가 같은 표를 찍고 있었지만 사람이
  처음 찾는 동사가 아니었다.
- 남의 문법은 다시 짓지 않는다(결정 10 · 13). 무선 덩어리는 `wpa_passphrase`(비밀번호는 표준 입력)가 짓고 `#` 줄을 버린다, ssh 키는
  `ssh-keygen -l -f -`가 읽어 보고 몸통으로 중복을 가른다, 방화벽은 우리 한 줄 `tcp dport N accept`를 쓰고 올리는 것은 `nft -f`다.
- 이 명령의 파일과 사람의 파일을 가르는 것은 방화벽 하나다(결정 14, `nftables.d/tars-config.nft`) — 줄을 지우는 동사(`deny`)를 가진
  표면이 그것뿐이다. 방화벽만 `firewall=on`이면 그 자리에서 `nft -f`를 돈다 — init이 든 상태가 없고 nft는 전부 올리거나 하나도 안
  올린다. "묻는다"는 동사가 없다 — 게이트가 묻는 명령을 못 치므로 `ssh on|off`처럼 동사로 만든다.
- 받아쓰기는 키 이름 여덟만 알고 값은 거르지 않는다(결정 15). 그 여덟이 `tars-dictate`의 `case`와 같은지는 호스트 검사가 그 bash 파일을
  읽어 본다.
- 게이트는 새 체인 없이 그 표면의 체인에 하나씩이고 판정은 "읽는 쪽이 이 명령이 쓴 것을 읽었다"다(결정 9 · 17) — config 1 · 2차,
  wifi(틀린 비밀번호를 고쳐 다시 붙는다), service(더한 키로 곧바로 로그인), firewall(닫힌 포트가 재부팅 없이 열린다), dictation(다음
  `tars-dictate`가 쓴 키를 싣고 간다).

## 남긴 것

실기에서 칠 것 — tty에서 echo를 끄고 묻는 길(`wifi` · `dictation key`), `--country`, `firewall deny`, `firewall=off`의 말. 게이트는 그
넷을 못 본다. 이월 숙제 둘은 [[project_config_reload]]에.

관련: [[project_config_reload]] · [[project_config_persistence]] · [[project_shell_config]] · [[project_service_control]] ·
[[feedback_network_default_stays_off]] · [[feedback_scripting_runtimes]]
