# TC-M2 — init이 재부팅 없이 `tars.conf`와 `services.d`를 다시 읽는다(`tars-config reload`)

Date: 2026-10-07
Design: `docs/specs/2026-10-07-tars-config-reload-design.md`(결정 1 ~ 11)
Status: 끝났다(2026-10-07). 구현은 Sonnet 서브에이전트가 Task 0 ~ 4와 5b를 글자 그대로 넣었고(plan 코드를 고친 곳 0), 루트 게이트 21체인 2/2가 두 번 초록이다. 그 앞의 루트 게이트 두 번이 net 검사 31에서 간헐로 빨갰고 그것이 Task 5b다. 값은 맨 아래 "TC-M2가 실측한 것".

## 누가 무엇을 하나

reload design 결정 10. Task 0 ~ 4는 구현 서브에이전트가 main 작업 트리에서 직접 편집하고 돌린다. Task 5(루트 게이트 2회 · 실측 절 ·
design 덧붙임 · commit)는 lead(Fable)가 한다. 구현자는 commit하지 않고, 끝에 `git diff --stat` · `git diff | rg '^-'` · 각 Task의 명령
출력을 그대로 보고한다. 이 plan의 "확정한 것" 절과 "실측한 것" 절은 구현자가 고치지 않는다.

권하는 모델은 Sonnet이다. 근거 둘.

- 코드는 구현자가 짓지 않는다. 새 파일 둘(`reload.zig` · `reload_test.zig`)은 사본에서 `cp -p`하고, 고치는 파일 열둘의 편집 마흔여섯은
  `old_string` · `new_string`이며, 각 Task 끝의 `cmp`가 사본과 바이트까지 같은지를 본다. M0 · M1이 같은 방식이었고 plan 코드를 고친 곳이 없었다.
- 사본에서 컴파일 · 호스트 검사 · 체인 아홉 · mutation 일곱을 지났다(확정 4 ~ 6).

Opus로 올리는 조건 — 이 milestone은 PID 1의 감독 루프를 고치는 첫 일이라 따로 적는다(확정 2). 아래 하나라도 보이면 구현자는 고치지 말고 멈춰
보고하고, lead가 Opus로 원인을 찾는다.

1. 어느 체인의 로그에든 `Attempted to kill init` · `Kernel panic` · `panic:`(Zig의 ReleaseSafe 패닉 문구)이 있다.
2. 루트 게이트에서 이 plan이 안 돌린 체인(확정 5의 아홉 밖 — tools · input · device · render · copy · hangul · machine · install · pane · pointer ·
   audio · dictation)이 빨갛고, 그 FAIL이 `started …` · `giving up` · `restarting` · `tars-service status`의 줄 · 서비스의 수에 걸린다 —
   감독 목록의 칸을 열셋으로 고정한 것(design 결정 5)의 그림자일 수 있다.
3. reload의 검사(config 1차 · net 31 · firewall 19 · service 28)가 두 판 중 한 판만 빨갛다 — 감독 루프의 순서(목표를 바꾼 뒤 다음 바퀴가
   띄운다) 쪽의 경합이다.

이 plan의 코드는 저장소 밖 사본(`/tmp/run/tc2/repo/`)에 먼저 넣어 돌렸고, 아래의 새 파일 본문과 `old_string` · `new_string`은 그 사본에서
기계로 뽑은 것이다(`/tmp/run/tc2/render.py`). 기준은 HEAD `5621281`(TC-M1 + reload design)의 파일(`/tmp/run/tc2/base/`)이고 편집 뒤의 파일은
`/tmp/run/tc2/new/`다. 새 파일은 `new/`에서 `cp -p`하고, 편집은 Edit 도구에 글자 그대로 넣고(또는 plan 본문에서 블록을 기계로 뽑아 넣고),
각 Task 끝에서 `new/`와 `cmp`한다. 다르면 편집이 빗나간 것이니 plan의 글자에 맞춰 고친다. plan의 글자와 `new/`가 서로 다르다고 보이면 고치지
말고 그 자리를 보고한다. 편집은 한 파일 안에서 E1부터 차례로 넣는다.

| 파일 | 무엇을 | 줄 |
|---|---|---|
| `init/src/reload.zig` | 새 파일 — reload가 무엇을 할지(키의 갈래 · diff · 대기 · 데몬의 step · 방화벽 · services.d의 판정 · 답의 글자). 시스템 콜 없음 | +267 |
| `init/src/reload_test.zig` | 새 파일 — 호스트 검사(묶음 여섯) | +131 |
| `init/src/main.zig` | 편집 열여섯 — `configLog`, `Child.config_off`, `answer`의 동사 둘 · `config_off` 건너뛰기, `Live` · `steer` · `placeService` · `rebuildShellAndEnv` · `doReload`, `supervise`가 `live`를 받는다, 칸 열셋 고정 | +307 −49 |
| `init/src/control.zig` | 편집 다섯 — 동사 둘, 이름 없는 둘, `wantsRunning`의 `config_off`, `apply` · `reached`의 새 동사 | +15 −5 |
| `init/src/control_test.zig` | 편집 넷 — 가짜의 `config_off`, 요청 넷, `config_off` 검사 | +14 −1 |
| `init/src/service_cli.zig` | 편집 하나 — `tars-service`는 새 동사를 안 받는다 | +2 |
| `init/src/firewall.zig` | 편집 하나 — `down`(`nft flush ruleset`) | +34 |
| `init/build.zig` | 편집 둘 — `reload_test` | +14 |
| `init/src/config_cli.zig` | 편집 여덟 — `control` import, USAGE의 `reload`, init에 묻기(`askInit` · `nowValue` · `screenLine` · `reloadInit`), 보기의 두 칸, `set`의 끝 줄, `main`의 `reload` | +61 −2 |
| `init/src/config_front.zig` | 편집 넷 — 무선 · `ssh on/off` · `ssh-key`의 끝 줄이 "재부팅"에서 `tars-config reload`로 | +4 −4 |
| `config/check.sh` | 편집 둘 — 키 배열 셋, 1차의 reload 검사 | +37 |
| `net/check.sh` | 편집 하나 — 검사 31 | +32 |
| `firewall/check.sh` | 편집 하나 — 검사 19 | +21 |
| `service/check.sh` | 편집 하나 — 검사 27의 끝 글자, 검사 28 | +22 −2 |

`git diff --stat`은 12 files, +563 −63이고(새 파일 둘은 밖), `git add -N` 뒤에는 14 files다. Task 5b(수정 1 — 루트 게이트 뒤) 뒤에는 `net/check.sh` +23 −2 · `firewall/check.sh` +5 · `config/check.sh` +6이 더해져
12 files, +597 −65다. 커널 · Dockerfile · `make_initrd.sh` ·
`guest_tools.sh` · 루트 `check.sh`는 안 바뀐다. 새 체인 · 새 포트가 없다.

design의 `Status:` · `CLAUDE.md` · `MEMORY.md` · `docs/decisions/` · `docs/guides/` · `HANDOFF.md`는 구현자가 안 고친다.

모든 명령은 저장소 루트에서 친다. 서브에이전트의 Bash는 호출마다 작업 디렉터리가 돌아가므로 명령 앞에
`cd /Users/dp/Repository/tars-linux &&`를 붙인다. 빌드 · 체인은 언제나 컨테이너에서 한다. 구현자의 측정용 파일은
`/tmp/run/tc2/impl/` 아래에 둔다. `/tmp/run/tc2/` 바로 아래는 이 plan을 쓰며 만든 것이고 대조에 쓴다. 지우지 않는다.

Docker VM의 메모리가 4GB다. 컨테이너는 언제나 하나씩 돌린다. 모든 `docker run`을 아래로 감싼다. 명령이 실패해도 lock은 꼭 푼다.
`run_in_background`로 돌리는 명령이 lock을 기다리게 두지 않는다 — 기다림은 앞에서 끝낸다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run … ; rc=$?
rmdir /tmp/run/docker.lock
```

## 이 milestone이 끝나면

- `tars-config set net=dhcp` 뒤에 `tars-config reload`를 치면 init이 `tars.conf`를 다시 읽고 dhcpcd를 띄운다. `net=off`면 멈춘다(주소가 빠진다).
  `ntp`면 chrony 설정을 다시 쓰고 chronyd를 띄우거나 다시 띄운다. `firewall=on`이면 규칙을 올리고 `off`면 `nft flush ruleset`이다.
- `shell` · `shell_config` · `timezone`은 다음에 뜨는 콘솔 셸 · ssh 로그인 · 서비스부터다(env 블록 · `/etc/passwd` · sshd의 SetEnv를 다시 짓는다).
- 자판 넷 · `esc_latin` · `clipboard` · `keyboard`는 init의 값만 바뀌고 화면은 다음 부팅까지 옛 값이다(TC-M3이 `reload terminal`을 더한다).
- `/config/services.d`를 다시 읽는다 — 새 이름은 뜨고, 사라진 이름은 멈추고, 있던 이름은 안 건드린다. `tars-config ssh on` · `reload`면 재부팅 없이
  sshd가 뜬다. `tars-config wifi`가 처음 만든 무선 파일도 reload가 띄운다.
- init의 파서가 한 마디라도 하는 파일이면 reload는 아무것도 안 바꾸고 그 말을 돌려준다.
- 인자 없는 `tars-config`가 파일과 init의 값이 다른 키 밑에 주석 한 줄, 화면이 대기 중이면 한 줄을 더 보인다.
- 부팅의 로그는 그대로다. `tars-service status`의 출력도 그대로다(설정이 끈 칸은 안 보인다).

출력(정본 — `reload.zig` · `main.zig`가 짓는다. 체인이 이 글자를 본다). `tars-config reload`가 init의 답을 그대로 찍는다.

```
keyboard: apple -> pc (the screen keeps the old value until the next boot)
net: dhcp -> off (now)
timezone: UTC -> Asia/Seoul (the next console shell, ssh login and service; the screen keeps the old value until the next boot)
firewall: up (nft -f /etc/tars/firewall.nft)
service dhcpcd: stops
service chronyd: restarts
service sshd: starts
service web: starts (new in /config/services.d)
service web: no free slot until the next boot (8 at most)
firewall: down (nft flush ruleset)
nothing changed
error: /config/tars.conf: unknown shell 'fsh', falling back to fish; nothing changed (tars-config check)
error: no config disk is mounted at /config; nothing to reload
```

`tars-config`(보기)에 더해지는 줄.

```
#   init uses net=off now; tars-config reload applies the line above
# the screen keeps keyboard=apple clipboard=shared until the next boot
# init did not answer at /run/tars/init.sock; only the file is shown
# change: tars-config set KEY=VALUE, then tars-config reload (or reboot)
```

init.sock의 `config` 답(열두 줄 + 대기가 있으면 한 줄).

```
shell=fish
keyboard=pc
⋮
clipboard=pane
screen keyboard=apple clipboard=shared
```

시리얼에 남는 줄(`tars-init:`).

```
tars-init: reload of /config/tars.conf
tars-init: reload refused, /config/tars.conf has 1 line(s) init would not take
tars-init: reload: service dhcpcd stop
tars-init: reload: service sshd start
tars-init: reload: service web joins the services
tars-init: reload: console shell /usr/bin/zsh, env TZ=Asia/Seoul
tars-init: firewall down (nft flush ruleset), inbound is open
tars-init: service dhcpcd stopped on request
```

## 착수 전에 확정한 것

2026-10-07에 이 plan을 쓰며 저장소 사본(`/tmp/run/tc2/repo/`, HEAD `5621281` — M1 파일 열하나가 `/tmp/run/tc1/new/`와 같은 것을 cmp로 봤다)과
이미지 `tars-devcontainer`로 쟀다. 측정 파일은 `/tmp/run/tc2/meas/`(체인 로그)와 `/tmp/run/tc2/mut/`(mutation)에 있다. 저장소의 작업 트리는 reload
design의 덧붙임과 이 plan 말고는 한 글자도 안 바뀌었다.

1. 자리(design 결정 5 · 8 · 11). 무엇을 할지는 `reload.zig`(순수)이고 `main.zig`는 실행한다. `main.zig`에 생기는 것 — 상태 `Live`(실효 `Config` ·
   화면의 `Config` · env 블록 두 벌 · TZ 글자 두 벌 · 서비스 칸 여덟의 글자), 칸 번호 상수(`SLOT_WIFI` 2 · `SLOT_DHCPCD` 3 · `SLOT_CHRONYD` 4 ·
   `SLOT_SERVICES` 5 · `SLOTS` 13), `steer`(칸 하나의 목표를 CT의 `control.apply`로), `placeService`, `rebuildShellAndEnv`(부팅의 그 함수들을
   같은 순서로 — `resolveShell` · `resolveTimezone` · `environ.withTarsEnv` · `login.apply`), `doReload`. 칸은 부팅부터 늘 열셋이고 원하지 않는
   칸은 `config_off`다 — 띄우는 순서(배열 순서)는 그 전과 같다. `configLog`가 부팅에 찍는 바이트는 그 전과 같다(`tars-init: ` + 글 + 개행).

2. PID 1의 패닉을 막는 근거. init은 ReleaseSafe다(`init/build.zig`) — 범위 밖 인덱스 · 정수 넘침 · `unreachable` · null인 옵셔널의 `.?` · 잘못된
   `@intCast`는 패닉이고, PID 1의 패닉은 커널 패닉(`Attempted to kill init`)이라 기계가 선다. reload의 코드가 그 다섯을 어디서 막는지다.

   | 자리 | 무엇이 패닉이 될 수 있었나 | 어떻게 막았나 | 누가 보나 |
   |---|---|---|---|
   | `control.apply` · `reached` | 새 동사에 `unreachable`(옛 `.status => unreachable`) | 새 동사 셋은 무해한 값을 돌려준다 — `answer`가 거기로 안 보내지만, 보내도 안 죽는다 | `control_test` |
   | `answer` | `req.name.?` | `orelse`로 `error: bad request` | 컴파일(`.?` 없음) |
   | `doReload`의 칸 인덱스 | `children[2..13)` | 머리에서 `children.len < SLOTS`면 `error:`로 돌아간다. 서비스 칸은 `SLOT_SERVICES + i`, `i < services.MAX` | 체인 넷 |
   | `serviceActions` | 칸 번호 · 이름 번호 · 담는 배열 | 칸 번호는 `slots`의 순회에서만 나오고, 이름 번호는 `names`의 순회에서만, 담는 것은 `out.len`을 넘으면 세기만 하고 `@min`으로 돌려준다. `taken`은 길이를 먼저 본다 | `reload_test` 묶음 6(한 칸짜리 배열에 둘) |
   | `doReload`의 `.add` | `entries[p.name]` | `p.name >= entries.len`이면 건너뛴다 | 컴파일 · 체인 |
   | 라벨에서 이름 꺼내기 | `label[prefix.len..]` | 길이를 먼저 본다(빈 칸의 라벨은 `""`) | 체인(service) |
   | `Keys`의 비트 | `1 << i` | `i`가 컴파일 타임이고 키가 열여섯을 넘으면 컴파일 에러 | 컴파일 |
   | 값의 글자 | `Toggles.arg` · `Ntp.arg`의 버퍼 | `VALUE_MAX` 64 ≥ 셋의 최대를 컴파일 타임에 본다 | 컴파일 |
   | 답의 글자 | 버퍼 2048바이트 | `control.Out` — 넘치면 멈추고 `full`을 세운다(`bufPrint`의 `catch`) | `reload_test` 묶음 4(10바이트 버퍼) |
   | `configLog`의 수와 첫 말 | `+=` 넘침, 160바이트 | `+|=`(포화), `std.Io.Writer.fixed`(넘치면 거기서 멈춘다) | 컴파일 |
   | ssh env의 배열 | `[3 + 4]` | 히스토리 env를 더할 때 길이를 본다(부팅의 같은 자리는 안 본다 — 그 차이를 일부러 두었다) | 컴파일 |

   호스트 검사가 덮는 것은 `reload.zig` 전부(갈래 · diff · 대기 · step · 방화벽 · services.d · 답의 글자)와 `control.zig`의 새 동사다. 못 덮는 것은
   `doReload`의 시스템 콜 쪽(nft · `services.discover` · `clock.prepare` · `login.apply` · env 블록) — 그 함수들은 전부 부팅이 이미 같은 입력의 꼴로
   부르는 것이고, 체인 넷이 reload로 한 번씩 더 부른다. 남는 위험은 그 함수들이 부팅에 한 번만 불릴 것을 전제한 자리다 — 사본에서 재어 본
   것은 `clock.prepare`(설정 파일을 다시 쓴다 — `TRUNC`)와 `login.apply`(두 파일을 다시 쓴다)이고 둘 다 같은 내용을 덮어쓴다.

3. `reload_test`(호스트, `zig build test`의 열다섯째). 묶음 여섯이 각각 한 줄을 찍고 끝에 `PASS`.

   | 묶음 | 본다 |
   |---|---|
   | 1 | 열두 키가 다 한 갈래에 든다(지금 셋 · 다음에 뜰 때부터 셋 · 화면 여섯) |
   | 2 | 키 하나를 바꾸면 그 비트 하나, 정규형이 같으면 안 바뀐 것(순서가 다른 전환 키 · `010.0.2.2`) |
   | 3 | 대기는 화면 쪽 키만 |
   | 4 | `config` 답의 글자 · `reload`의 키 줄 · 10바이트 버퍼가 멈춘다 |
   | 5 | 데몬 step의 일곱 갈래 · 방화벽 넷 |
   | 6 | services.d — 빈 칸에 새 이름 · 그대로 · 사라짐 · 되살림 · 거둬진 칸 다시 쓰기와 멈추는 중인 칸 안 쓰기 · 칸 없음 · 담는 배열이 작을 때 |

   `control_test`의 첫 줄이 `requests — six verbs, config and reload without a name, one name, nothing else`가 된다.

4. 체인 넷의 자리(design 결정 9의 덧붙임). 새 부팅 · 새 포트가 없다.

   | 체인 | 검사 | 판정 |
   |---|---|---|
   | `config` 1차(fish) | `list` 뒤 | `set keyboard=pc` · `reload` → `keyboard: apple -> pc (the screen keeps …)`, 화면 덤프에 `service dhcpcd`가 없다(net=off 부팅 · diff), 보기의 `# the screen keeps keyboard=apple clipboard=shared until the next boot`(TC-M0 검사가 바꾼 clipboard=pane도 대기다), `echo shell=fsh >> /config/tars.conf` · `reload` → `error: … unknown shell 'fsh' …; nothing changed` |
   | `net` 첫 부팅(dhcp) | 검사 31 | `set net=off` · `reload` → `service dhcpcd: stops` · `stopped on request` · `nw0`, `set net=dhcp` · `reload` → `service dhcpcd: starts` · 이 부팅의 둘째 lease · 둘째 `started service dhcpcd` |
   | `firewall` 부팅 A | 검사 19 | `set firewall=off` · `reload` → `firewall: down (nft flush ruleset)` · `fwn0`, `set firewall=on` · `reload` → `firewall: up (…)` · drop이 선다(`fwp…`) |
   | `service` 부팅 D | 검사 27의 끝 · 검사 28 | `ssh off`의 글자가 `sshd: off — tars-config reload stops it now`, `reload` → `service sshd: stops` · 새 로그인이 막힘(제어 연결은 산다), `ssh on` · `reload` → `service sshd: starts` · 새 로그인, sleeper · stubborn · flaky의 줄이 없음, 검사 23이 멈춘 stubborn이 `stopped` 그대로 |

   config 1차의 `keyboard=pc`가 화면에 안 닿는 것이 그 부팅의 나머지 타이핑을 지킨다 — 닿았다면 Alt · Meta가 맞바뀌어 뒤의 sendkey가 다른 글자가
   된다. 그 부팅의 `EDIT_KEYS`가 파일을 한 줄로 덮어쓰므로 2차로 넘어가는 것은 없다.

5. 체인과 시간. 아홉을 한 컨테이너에서 차례로 돌렸다. 감독 목록의 칸을 바꿨으므로 init을 띄우는 체인 가운데 감독 · 서비스 · 데몬을 보는 것을
   함께 돌렸다.

   | 체인 | 시간(사본) | 왜 |
   |---|---|---|
   | `config` | 243초 | reload 검사 · 처음부터 짓는 판 |
   | `firewall` | 62초 | 검사 19 |
   | `service` | 77초 | 검사 28 · `status`의 줄이 그대로인가(검사 17) · 거절 다섯(검사 25) |
   | `net` | 185초 | 검사 31 · dhcpcd · chronyd의 칸 |
   | `boot` | 25초 | terminal이 셋 죽고 포기되는 수(칸을 고정해도 그대로인가) |
   | `wifi` | 120초 | wpa_supplicant의 칸(부팅 C의 음성 — 끈 칸이 안 뜬다) |
   | `power` | 50초 | 끄는 길이 칸 열셋을 지난다 |
   | `nic` | 33초 | dhcpcd의 칸과 핫플러그 |
   | `terminal` | 25초 | 고아 거두기 · 재시작의 줄 |

   루트 게이트에서 늘어나는 것은 타이핑이다 — config 1차 백열 키 · net 백서른 키 · firewall 백여든 키(글자당 0.3초 안팎, 합해서 2분 남짓 × 2회).

6. mutation. 여섯 가지를 일곱(되돌림 포함) 판으로 돌렸다(`/tmp/run/tc2/make_mut.py` · `run_mut.sh`, 로그는 `/tmp/run/tc2/mut/`).

   | mutation | 판 · 체인 | `mounted:` | 잡은 자리 | `FAIL` 줄 | 시간 |
   |---|---|---|---|---|---|
   | 1 설정이 끈 칸도 띄운다(`wantsRunning`이 `config_off`를 안 본다) | `m1` · wifi | `fe7df3b6 d64f1a5a b3fea774` | 부팅 C의 음성(검사 10) | `FAIL: found 'started service wpa_supplicant' in a boot with no file and no radios` | 136초 |
   | 2 init의 파서가 불평해도 reload한다 | `m2` · config | `9721d969 2ee2197a b3fea774` | 1차의 거절 | `FAIL(boot 1): reload did not refuse a file with a line init would not take` | 65초 |
   | 3 `firewall=off`로 바꿔도 규칙을 안 내린다 | `m3` · firewall | `9721d969 9fd616a3 b3fea774` | 검사 19 | `FAIL: reload did not take the firewall down` | 69초 |
   | 4 services.d를 견주지 않는다(칸 없이 견준다) | `m4` · service | `9721d969 d79c91b5 b3fea774` | 검사 28 | `FAIL: reload did not stop the unlinked sshd (service flaky: no free slot until the next boot (8 at most)` | 84초 |
   | 5 멈추는 중인 칸도 빈 칸으로 본다 | `m5` · service | `9721d969 d64f1a5a 5390ba9e` | `reload_test` 묶음 6(부팅 전) | `FAIL: reuse a reaped slot, not a dying one: action 0 is .{ .add = .{ .slot = 0, .name = 0 } }, want .{ .add = .{ .slot = 1, .name = 0 } }` | 16초 |
   | 6 `status`가 설정이 끈 칸도 보인다 | `m6` · service | `9721d969 da47dc37 b3fea774` | 검사 17(DS-M2의 것) | `FAIL: status lists chronyd although this disk leaves ntp off (got: [terminal        running   pid 40   up 8s` | 79초 |
   | (되돌림) | `back` · firewall | `9721d969 d64f1a5a b3fea774` | — | 마지막 줄 `FW chain PASS` | 76초 |

   읽을 것 셋.
   - `m1`은 칸을 열셋으로 고정한 것(design 결정 5)의 가장 큰 위험이다 — 판정 하나가 틀리면 `net=off` 부팅마다 데몬 셋이 뜬다. wifi 체인 부팅 C의
     음성이 그것을 잡는다. 이 milestone 전에는 그 판정이 없었다(원하지 않는 데몬은 목록에 아예 없었다).
   - `m4`는 service 체인의 셋째 판정이 아니라 첫 reload에서 잡혔다 — 칸 없이 견주면 이미 있던 넷이 "새 이름"이 되어 `no free slot`을 말하고
     sshd를 안 멈춘다. 답에 그 줄이 그대로 실려 FAIL에 보인다.
   - `m6`은 이 milestone이 더한 검사가 아니라 DS-M2의 검사 17이 잡았다 — `status`에 `config_off`인 칸(chronyd)이 보이면 그 검사의 음성에 걸린다.
     그래서 `status`의 줄이 TC-M2 전과 같다는 것이 이미 게이트에 묶여 있다.

## Task 0: 바꾸기 전의 기준값

1. 돌고 있는 게이트나 컨테이너가 없는지 본다.

   ```bash
   docker ps --format '{{.Names}} {{.Image}} {{.Status}}'
   ls -d /tmp/run/docker.lock 2>&1
   ```

2. 작업 트리를 본다.

   ```bash
   git status --short
   git log --oneline -3
   for f in init/src/control.zig init/src/control_test.zig init/src/service_cli.zig init/src/firewall.zig init/src/main.zig init/build.zig \
     init/src/config_cli.zig init/src/config_front.zig config/check.sh net/check.sh firewall/check.sh service/check.sh; do
     cmp $f /tmp/run/tc2/base/$f && echo "BASE $f"; done
   ls init/src/reload.zig init/src/reload_test.zig 2>&1
   ls kernel/build/.tars-build-stamp kernel/build/arch/x86/boot/bzImage
   ```

   기대: `5621281`이 있고 그 위에 lead의 commit(이 plan · design 덧붙임)이 있을 수 있다. `BASE` 열둘. 새 파일 둘은 `No such file`. 커널 스탬프와
   bzImage가 있다. 하나라도 다르면 멈추고 보고한다.

## Task 1: `init/` — 새 파일 둘과 편집

design 결정 1 ~ 8 · 11 · 확정 1 ~ 3. 편집은 아래 순서로 넣는다 — `control.zig`가 먼저인 것은 `main.zig`의 `config_off`를 그 규칙이 읽기 때문이다
(순서와 상관없이 마지막에 한 번 짓는다).

### 1-1. 새 파일 둘

```bash
for f in reload.zig reload_test.zig; do cp -p /tmp/run/tc2/new/init/src/$f init/src/$f; done
```

본문은 아래와 같다(읽기용 — 넣는 것은 위 `cp`다).

`init/src/reload.zig`:

```zig
//! TC-M2. `reload`가 무엇을 할지를 정하는 쪽(reload design 결정 8).
//!
//! 시스템 콜이 하나도 없다 — `reload_test.zig`가 호스트에서 전부 본다. 실행하는 것(nft ·
//! argv 포인터 · env 블록 갈아 끼우기 · 서비스의 목표)은 `main.zig`의 `reload`다.
//!
//! PID 1의 코드다. ReleaseSafe에서 범위 밖 인덱스 · 정수 넘침 · `unreachable` · `.?`의 null은
//! 패닉이고, PID 1의 패닉은 커널 패닉이다. 그래서 이 파일은 셋을 지킨다 — 인덱스는 언제나
//! 길이를 먼저 본 뒤에, 글자는 `control.Out`처럼 넘치면 멈추는 버퍼에, `unreachable`과
//! `.?`는 쓰지 않는다(plan 확정 2).
const std = @import("std");
const config = @import("config.zig");
const control = @import("control.zig");

// ── 키 ────────────────────────────────────────────────────────────────

/// 키 하나가 reload에서 가는 갈래(design 결정 2).
pub const Group = enum {
    /// 데몬 · 방화벽 — reload가 지금 바꾼다.
    now,
    /// 콘솔 셸 · ssh 로그인 · 뒤에 뜨는 자식부터. 화면의 패널은 대기다.
    next_spawn,
    /// terminal의 argv. 화면을 다시 띄워야 바뀐다 — 대기다.
    terminal,
};

/// 열두 키의 갈래. `Config`의 필드 이름으로 고른다 — 필드를 더하고 여기를 빠뜨리면
/// `groupOf`가 컴파일 에러를 낸다.
pub fn groupOf(comptime key: []const u8) Group {
    const now = [_][]const u8{ "net", "ntp", "firewall" };
    const next = [_][]const u8{ "shell", "shell_config", "timezone" };
    const term = [_][]const u8{ "keyboard", "hangul_layout", "latin_layout", "hangul_toggle", "esc_latin", "clipboard" };
    inline for (now) |k| if (comptime std.mem.eql(u8, k, key)) return .now;
    inline for (next) |k| if (comptime std.mem.eql(u8, k, key)) return .next_spawn;
    inline for (term) |k| if (comptime std.mem.eql(u8, k, key)) return .terminal;
    @compileError("reload.groupOf does not know the key " ++ key);
}

/// 화면이 쓰는 키 — terminal의 argv에 드는 것. `next_spawn`의 셋도 화면의 패널에는 argv
/// (1 · 2번 셸과 rc 플래그)와 env(`TZ`)로 들어가서 화면에서는 대기다.
pub fn onScreen(comptime key: []const u8) bool {
    return groupOf(key) != .now;
}

/// 두 값이 같은가. 필드 타입마다 비교가 다르다 — enum은 `==`, `Ntp` · `Timezone`은 `eql`,
/// `Toggles`는 칸 다섯.
fn same(comptime T: type, a: T, b: T) bool {
    if (T == config.Toggles) return std.meta.eql(a, b);
    if (T == config.Ntp or T == config.Timezone) return a.eql(b);
    if (@typeInfo(T) == .@"enum") return a == b;
    @compileError("reload.same cannot compare a " ++ @typeName(T));
}

/// 키의 집합. `Config`의 필드 순서대로 한 비트씩.
pub const Keys = struct {
    bits: u16 = 0,

    pub const count = @typeInfo(config.Config).@"struct".fields.len;

    comptime {
        if (count > 16) @compileError("reload.Keys holds 16 keys");
    }

    pub fn has(self: Keys, comptime key: []const u8) bool {
        return self.bits & bit(key) != 0;
    }

    pub fn empty(self: Keys) bool {
        return self.bits == 0;
    }

    fn bit(comptime key: []const u8) u16 {
        inline for (@typeInfo(config.Config).@"struct".fields, 0..) |f, i| {
            if (comptime std.mem.eql(u8, f.name, key)) return @as(u16, 1) << i;
        }
        @compileError("no key " ++ key);
    }
};

/// 바뀐 키.
pub fn changed(old: config.Config, new: config.Config) Keys {
    var k = Keys{};
    inline for (@typeInfo(config.Config).@"struct".fields, 0..) |f, i| {
        if (!same(f.type, @field(old, f.name), @field(new, f.name))) k.bits |= @as(u16, 1) << i;
    }
    return k;
}

/// 화면이 대기 중인 키 — init이 지금 쓰는 값(`live`)과 terminal이 뜰 때 받은 값(`screen`)이
/// 다른 화면 쪽 키.
pub fn pending(live: config.Config, screen: config.Config) Keys {
    var k = Keys{};
    inline for (@typeInfo(config.Config).@"struct".fields, 0..) |f, i| {
        if (comptime onScreen(f.name)) {
            if (!same(f.type, @field(live, f.name), @field(screen, f.name))) k.bits |= @as(u16, 1) << i;
        }
    }
    return k;
}

// ── 값의 글자 ─────────────────────────────────────────────────────────

pub const VALUE_MAX = 64;

comptime {
    if (VALUE_MAX < config.TZ_NAME_MAX or VALUE_MAX < config.TOGGLE_ARG_MAX or VALUE_MAX < config.NTP_ARG_MAX)
        @compileError("reload.VALUE_MAX is smaller than a value config.zig can hold");
}

/// 필드 하나의 글자. `config_edit.fieldText`와 같은 일이다 — init은 `config_edit`을 import하지
/// 않는다(그 파일은 `tars-config`의 것이고 듣기 전역을 든다).
fn text(comptime T: type, v: T, buf: *[VALUE_MAX]u8) []const u8 {
    if (T == config.Toggles) return v.arg(buf);
    if (T == config.Ntp) return v.arg(buf);
    if (T == config.Timezone) {
        const s = v.slice();
        @memcpy(buf[0..s.len], s);
        return buf[0..s.len];
    }
    if (@typeInfo(T) == .@"enum") return @tagName(v);
    @compileError("reload.text cannot print a " ++ @typeName(T));
}

// ── 답 ────────────────────────────────────────────────────────────────

/// 넘치면 멈추는 버퍼 — init.sock의 답과 같은 것을 쓴다. PID 1이 답을 짓다가 죽는 길을 두지
/// 않는다(`control.Out`의 주석).
pub const Out = control.Out;

/// `config` 동사의 답(design 결정 1). 열두 줄 `key=value`(init이 지금 쓰는 값), 그리고 화면이
/// 대기 중이면 `screen key=value …` 한 줄(terminal이 지금 쓰는 값).
pub fn configReply(out: *Out, live: config.Config, screen: config.Config) void {
    inline for (@typeInfo(config.Config).@"struct".fields) |f| {
        var buf: [VALUE_MAX]u8 = undefined;
        out.print("{s}={s}\n", .{ f.name, text(f.type, @field(live, f.name), &buf) });
    }
    const p = pending(live, screen);
    if (p.empty()) return;
    out.print("screen", .{});
    inline for (@typeInfo(config.Config).@"struct".fields, 0..) |f, i| {
        if (p.bits & (@as(u16, 1) << i) != 0) {
            var buf: [VALUE_MAX]u8 = undefined;
            out.print(" {s}={s}", .{ f.name, text(f.type, @field(screen, f.name), &buf) });
        }
    }
    out.print("\n", .{});
}

// ── 데몬 ──────────────────────────────────────────────────────────────

/// 데몬 하나에 할 일(design 결정 3의 2단계).
pub const Step = enum { keep, start, stop, restart };

/// was · now는 "설정이 이 데몬을 원하는가"(부팅의 `wifi.wants` · `net.wantsDhcpcd` ·
/// `clock.prepare`의 답). rewrote는 그 데몬이 읽는 설정 파일을 이번에 다시 썼는가(chronyd의
/// `/run/tars/chrony.conf`) — 켜진 채로 파일이 바뀌면 다시 띄워야 읽는다.
pub fn step(was: bool, now: bool, rewrote: bool) Step {
    if (!was and now) return .start;
    if (was and !now) return .stop;
    if (was and now and rewrote) return .restart;
    return .keep;
}

/// 방화벽에 할 일. 켜기는 조이는 것이라 데몬보다 먼저, 끄기는 푸는 것이라 데몬 뒤에
/// 한다(design 결정 3 — FW 결정 5의 "규칙이 서기 전에 주소가 붙는 틈이 없다").
pub const Fw = enum { keep, up, down };

pub fn firewallStep(old: config.Firewall, new: config.Firewall) Fw {
    if (old == new) return .keep;
    return if (new == .on) .up else .down;
}

// ── 서비스(services.d) ────────────────────────────────────────────────

/// 감독 목록의 서비스 칸 하나를 reload가 보는 모양.
pub const Slot = struct {
    /// 비었으면 한 번도 쓰인 적 없는 칸이다.
    name: []const u8,
    /// 설정(services.d)이 이 칸을 안 원한다 — 멈췄거나 멈추는 중이다.
    off: bool,
    /// 프로세스가 아직 있다(멈추는 중이면 참이다).
    alive: bool,
};

pub const SvcAction = union(enum) {
    /// 칸 i의 서비스가 services.d에서 사라졌다. 멈춘다.
    stop: usize,
    /// 칸 i의 서비스가 다시 나타났다. 되살린다.
    revive: usize,
    /// 새 이름(names의 n번째)을 칸 i에 넣고 띄운다.
    add: struct { slot: usize, name: usize },
    /// 새 이름(names의 n번째)을 넣을 칸이 없다. 다음 부팅을 기다린다.
    no_room: usize,
};

fn indexOf(names: []const []const u8, name: []const u8) ?usize {
    for (names, 0..) |n, i| if (std.mem.eql(u8, n, name)) return i;
    return null;
}

/// services.d를 다시 읽은 이름(정렬 · 여덟까지는 `services.discover`가 했다)과 지금의 칸을
/// 견줘 할 일을 out에 담는다. 담은 수를 돌려준다. 이미 있는 이름의 칸은 안 건드린다.
///
/// 빈 칸은 둘이다 — 한 번도 안 쓴 칸, 그리고 꺼졌고 프로세스가 이미 거둬진 칸(이번 목록에
/// 그 이름이 없을 때). 멈추는 중인 칸(꺼졌지만 아직 살아 있다)은 빈 칸이 아니다 — 거두기
/// 전에 칸을 넘기면 그 pid가 새 서비스의 것이 된다.
pub fn serviceActions(slots: []const Slot, names: []const []const u8, out: []SvcAction) usize {
    var n: usize = 0;
    // 사라진 것과 다시 나타난 것.
    for (slots, 0..) |s, i| {
        if (s.name.len == 0) continue;
        const listed = indexOf(names, s.name) != null;
        if (!s.off and !listed) {
            if (n < out.len) out[n] = .{ .stop = i };
            n += 1;
        } else if (s.off and listed) {
            if (n < out.len) out[n] = .{ .revive = i };
            n += 1;
        }
    }
    // 새 이름. 칸은 앞에서부터 찾고, 한 번 준 칸은 다시 안 준다.
    var taken: [32]bool = @splat(false);
    for (names, 0..) |name, ni| {
        var present = false;
        for (slots) |s| {
            if (s.name.len != 0 and std.mem.eql(u8, s.name, name)) present = true;
        }
        if (present) continue;
        var given: ?usize = null;
        for (slots, 0..) |s, i| {
            if (i >= taken.len or taken[i]) continue;
            const free = s.name.len == 0 or (s.off and !s.alive and indexOf(names, s.name) == null);
            if (!free) continue;
            given = i;
            taken[i] = true;
            break;
        }
        if (n < out.len) out[n] = if (given) |g| .{ .add = .{ .slot = g, .name = ni } } else .{ .no_room = ni };
        n += 1;
    }
    return @min(n, out.len);
}

// ── reload의 답 ───────────────────────────────────────────────────────

/// 키 한 줄의 꼬리. 지금 바뀌는 키는 main.zig가 데몬 · 방화벽의 줄을 따로 찍으므로 여기서는
/// 셋을 가른다.
pub fn note(comptime key: []const u8) []const u8 {
    return switch (comptime groupOf(key)) {
        .now => "now",
        .next_spawn => "the next console shell, ssh login and service; the screen keeps the old value until the next boot",
        .terminal => "the screen keeps the old value until the next boot",
    };
}

/// 바뀐 키마다 `key: old -> new (꼬리)` 한 줄.
pub fn keyLines(out: *Out, old: config.Config, new: config.Config) void {
    const k = changed(old, new);
    inline for (@typeInfo(config.Config).@"struct".fields, 0..) |f, i| {
        if (k.bits & (@as(u16, 1) << i) != 0) {
            var a: [VALUE_MAX]u8 = undefined;
            var b: [VALUE_MAX]u8 = undefined;
            out.print("{s}: {s} -> {s} ({s})\n", .{
                f.name, text(f.type, @field(old, f.name), &a), text(f.type, @field(new, f.name), &b), note(f.name),
            });
        }
    }
}
```

`init/src/reload_test.zig`:

```zig
//! TC-M2. `reload.zig`의 검사 — PID 1이 reload에서 무엇을 할지를 호스트에서 다 본다(reload design
//! 결정 8). config_test와 같은 모양이다 — 실패하면 `FAIL:` 줄을 찍고 0이 아닌 코드로 끝난다.
const std = @import("std");
const config = @import("config.zig");
const control = @import("control.zig");
const reload = @import("reload.zig");

fn fail(comptime fmt: []const u8, args: anytype) error{Failed} {
    std.debug.print("FAIL: " ++ fmt ++ "\n", args);
    return error.Failed;
}

fn expectText(got: []const u8, want: []const u8, what: []const u8) !void {
    if (!std.mem.eql(u8, got, want)) return fail("{s}:\n--- got ---\n{s}\n--- want ---\n{s}", .{ what, got, want });
}

/// 키마다 기본값이 아닌 값 하나. `config.parse`로 짓는다 — init이 읽는 그 길이다.
const OTHER = [_][]const u8{
    "shell=zsh",       "keyboard=pc",       "hangul_layout=dubeol", "latin_layout=dvorak",
    "hangul_toggle=shift_space", "shell_config=off", "net=dhcp", "ntp=10.0.2.2",
    "timezone=Asia/Seoul", "firewall=on", "esc_latin=off", "clipboard=pane",
};

const S = reload.Slot;

fn expectActions(slots: []const S, names: []const []const u8, want: []const reload.SvcAction, what: []const u8) !void {
    var out: [16]reload.SvcAction = undefined;
    const n = reload.serviceActions(slots, names, &out);
    if (n != want.len) return fail("{s}: {d} actions, want {d}", .{ what, n, want.len });
    for (out[0..n], want, 0..) |g, w, i| {
        if (!std.meta.eql(g, w)) return fail("{s}: action {d} is {any}, want {any}", .{ what, i, g, w });
    }
}

pub fn main() !void {
    // ── 1. 열두 키가 다 한 갈래에 든다 ──────────────────────────────────
    //
    // groupOf가 모르는 키는 컴파일 에러다 — 이 루프가 컴파일되면 열둘 다 들었다. 갈래의 수를 세서
    // design 결정 2의 표(지금 셋 · 다음에 뜰 때부터 셋 · 화면 여섯)와 견준다.
    var counts = [_]usize{ 0, 0, 0 };
    inline for (@typeInfo(config.Config).@"struct".fields) |f| counts[@intFromEnum(comptime reload.groupOf(f.name))] += 1;
    if (counts[0] != 3 or counts[1] != 3 or counts[2] != 6) return fail("groups now/next/terminal = {d}/{d}/{d}, want 3/3/6", .{ counts[0], counts[1], counts[2] });
    std.debug.print("reload_test: twelve keys in three groups — three now, three at the next spawn, six on the screen\n", .{});

    // ── 2. diff — 키 하나를 바꾸면 그 비트 하나 ────────────────────────
    const def = config.Config{};
    if (!reload.changed(def, def).empty()) return fail("default against default changed something", .{});
    for (OTHER, 0..) |line, i| {
        const c = config.parse(line);
        const k = reload.changed(def, c);
        if (k.bits != (@as(u16, 1) << @intCast(i))) return fail("{s}: changed bits {b}, want bit {d}", .{ line, k.bits, i });
    }
    // 정규형이 같으면 같은 값이다 — 순서가 다른 전환 키 목록 · 0으로 시작하는 주소.
    if (!reload.changed(config.parse("hangul_toggle=lctrl_tap,shift_space"), config.parse("hangul_toggle=shift_space,lctrl_tap")).empty())
        return fail("the same toggles in another order count as a change", .{});
    if (!reload.changed(config.parse("ntp=10.0.2.2"), config.parse("ntp=010.0.2.2")).empty())
        return fail("the same ntp address written with a leading zero counts as a change", .{});
    std.debug.print("reload_test: the diff flips one bit per changed key and none for the same value written another way\n", .{});

    // ── 3. 대기 — 화면 쪽 키만 ─────────────────────────────────────────
    const live = config.parse("keyboard=pc\nnet=dhcp\ntimezone=Asia/Seoul\n");
    const p = reload.pending(live, def);
    if (!p.has("keyboard") or !p.has("timezone") or p.has("net")) return fail("pending bits {b}", .{p.bits});

    // ── 4. 답의 글자 ────────────────────────────────────────────────────
    var buf: [control.REPLY_MAX]u8 = undefined;
    var out = reload.Out{ .buf = &buf };
    reload.configReply(&out, live, def);
    try expectText(out.bytes(),
        "shell=fish\nkeyboard=pc\nhangul_layout=shin_pcs\nlatin_layout=qwerty\n" ++
        "hangul_toggle=hangul_key,shift_space,capslock_tap,lctrl_tap\nshell_config=on\nnet=dhcp\nntp=off\n" ++
        "timezone=Asia/Seoul\nfirewall=off\nesc_latin=on\nclipboard=shared\n" ++
        "screen keyboard=apple timezone=UTC\n", "configReply");
    var kb: [1024]u8 = undefined;
    var ko = reload.Out{ .buf = &kb };
    reload.keyLines(&ko, def, live);
    try expectText(ko.bytes(),
        "keyboard: apple -> pc (the screen keeps the old value until the next boot)\n" ++
        "net: off -> dhcp (now)\n" ++
        "timezone: UTC -> Asia/Seoul (the next console shell, ssh login and service; the screen keeps the old value until the next boot)\n",
        "keyLines");
    // 넘치면 멈춘다 — PID 1이 답을 짓다가 죽지 않는다.
    var tiny: [10]u8 = undefined;
    var to = reload.Out{ .buf = &tiny };
    reload.configReply(&to, live, def);
    if (!to.full or to.len > tiny.len) return fail("a 10-byte reply buffer did not stop cleanly", .{});
    std.debug.print("reload_test: config answers twelve key=value lines and the screen's line; a full buffer stops, it does not panic\n", .{});

    // ── 5. 데몬 · 방화벽 ────────────────────────────────────────────────
    const table = [_]struct { bool, bool, bool, reload.Step }{
        .{ false, false, false, .keep }, .{ false, true, false, .start }, .{ false, true, true, .start },
        .{ true, false, false, .stop },  .{ true, false, true, .stop },   .{ true, true, false, .keep },
        .{ true, true, true, .restart },
    };
    for (table) |t| if (reload.step(t[0], t[1], t[2]) != t[3]) return fail("step({}, {}, {})", .{ t[0], t[1], t[2] });
    if (reload.firewallStep(.off, .on) != .up or reload.firewallStep(.on, .off) != .down or
        reload.firewallStep(.on, .on) != .keep or reload.firewallStep(.off, .off) != .keep) return fail("firewallStep", .{});
    std.debug.print("reload_test: a daemon starts, stops, restarts on a rewritten config or is left alone; the firewall goes up or down\n", .{});

    // ── 6. services.d ───────────────────────────────────────────────────
    const empty = S{ .name = "", .off = true, .alive = false };
    // 새 이름 둘이 앞의 빈 칸 둘에.
    try expectActions(&[_]S{ empty, empty, empty }, &[_][]const u8{ "a", "sshd" }, &[_]reload.SvcAction{
        .{ .add = .{ .slot = 0, .name = 0 } }, .{ .add = .{ .slot = 1, .name = 1 } },
    }, "two new names");
    // 이미 있는 것은 안 건드린다.
    try expectActions(&[_]S{ .{ .name = "a", .off = false, .alive = true }, empty }, &[_][]const u8{"a"}, &[_]reload.SvcAction{}, "nothing changed");
    // 사라진 것은 멈춘다. 멈춘 사람의 것(hold)은 칸의 off가 아니라 상관없다.
    try expectActions(&[_]S{ .{ .name = "a", .off = false, .alive = true }, .{ .name = "sshd", .off = false, .alive = true } }, &[_][]const u8{"a"}, &[_]reload.SvcAction{
        .{ .stop = 1 },
    }, "a name gone");
    // 다시 나타난 것은 되살린다 — 새 칸이 아니라 그 칸이다.
    try expectActions(&[_]S{ .{ .name = "a", .off = false, .alive = true }, .{ .name = "sshd", .off = true, .alive = false }, empty }, &[_][]const u8{ "a", "sshd" }, &[_]reload.SvcAction{
        .{ .revive = 1 },
    }, "a name back");
    // 꺼졌고 거둬진 칸은 다른 새 이름에게 간다. 멈추는 중(alive)인 칸은 안 준다.
    try expectActions(&[_]S{ .{ .name = "old", .off = true, .alive = true }, .{ .name = "gone", .off = true, .alive = false } }, &[_][]const u8{"new"}, &[_]reload.SvcAction{
        .{ .add = .{ .slot = 1, .name = 0 } },
    }, "reuse a reaped slot, not a dying one");
    // 칸이 없으면 다음 부팅.
    try expectActions(&[_]S{ .{ .name = "a", .off = false, .alive = true } }, &[_][]const u8{ "a", "b" }, &[_]reload.SvcAction{
        .{ .no_room = 1 },
    }, "no room");
    // out보다 많으면 out만큼 — 셈이 넘치지 않는다.
    var small: [1]reload.SvcAction = undefined;
    const m = reload.serviceActions(&[_]S{ empty, empty }, &[_][]const u8{ "a", "b" }, &small);
    if (m != 1) return fail("serviceActions into a one-slot array gave {d}", .{m});
    std.debug.print("reload_test: services.d — new names take free slots, gone names stop, returning names revive, a dying slot is not reused\n", .{});

    std.debug.print("PASS\n", .{});
}
```

### 1-2. `control.zig` — 편집 다섯

E1 — `old_string`(기준 파일 38줄부터):

```zig
pub const Verb = enum { status, stop, start, restart };
```

`new_string`:

```zig
/// TC-M2가 둘을 더했다 — `config`(init이 지금 쓰는 설정)와 `reload`(tars.conf를 다시 읽는다,
/// reload design 결정 1). 둘은 이름을 안 받는다. 사람의 문은 `tars-config`이고 `tars-service`는
/// 앞의 넷만 받는다(`service_cli.zig`).
pub const Verb = enum { status, stop, start, restart, config, reload };
```

E2 — `old_string`(기준 파일 64줄부터):

```zig
        if (!nameOk(n)) return null;
    } else if (verb != .status) return null;
```

`new_string`:

```zig
        if (verb == .config or verb == .reload) return null;
        if (!nameOk(n)) return null;
    } else if (verb != .status and verb != .config and verb != .reload) return null;
```

E3 — `old_string`(기준 파일 112줄부터):

```zig
pub fn wantsRunning(c: anytype) bool {
    return c.pid < 0 and !c.given_up and c.hold != .stop;
```

`new_string`:

```zig
///
/// TC-M2. `config_off`는 설정(tars.conf · services.d)이 이 칸을 안 원한다는 뜻이다. `hold`(사람이
/// 이 부팅에서 멈췄다)와 다른 칸인 이유는 reload design 결정 5 — 같은 칸이면
/// `tars-service start`가 설정이 끈 것을 되살린다.
pub fn wantsRunning(c: anytype) bool {
    return c.pid < 0 and !c.given_up and c.hold != .stop and !c.config_off;
```

E4 — `old_string`(기준 파일 135줄부터):

```zig
        .status => unreachable,
```

`new_string`:

```zig
        // 감독 루프의 `answer`가 이 셋을 여기로 안 보낸다. `unreachable`이 아닌 이유는 PID 1이라서다 —
        // ReleaseSafe의 `unreachable`은 패닉이고 PID 1의 패닉은 커널 패닉이다(TC-M2 plan 확정 2).
        .status, .config, .reload => return .{ .outcome = .already_running, .signal = false },
```

E5 — `old_string`(기준 파일 200줄부터):

```zig
        .status => true,
```

`new_string`:

```zig
        .status, .config, .reload => true,
```

### 1-3. `control_test.zig` — 편집 넷

E1 — `old_string`(기준 파일 25줄부터):

```zig
    kill_at: isize = 0,
```

`new_string`:

```zig
    kill_at: isize = 0,
    config_off: bool = false,
```

E2 — `old_string`(기준 파일 79줄부터):

```zig
    try expectParse("stop a b", null, null);
```

`new_string`:

```zig
    try expectParse("stop a b", null, null);
    // TC-M2. 둘은 이름 없이만 받는다 — `reload terminal`은 TC-M3의 자리다.
    try expectParse("config", .config, null);
    try expectParse("reload", .reload, null);
    try expectParse("reload terminal", null, null);
    try expectParse("config sshd", null, null);
```

E3 — `old_string`(기준 파일 88줄부터):

```zig
    std.debug.print("control_test: requests — four verbs, one name, nothing else\n", .{});
```

`new_string`:

```zig
    std.debug.print("control_test: requests — six verbs, config and reload without a name, one name, nothing else\n", .{});
```

E4 — `old_string`(기준 파일 123줄부터):

```zig
    if (control.wantsRunning(&c)) return fail("a stopped service wants to run", .{});
```

`new_string`:

```zig
    if (control.wantsRunning(&c)) return fail("a stopped service wants to run", .{});
    {
        // TC-M2. 설정이 끈 칸은 살아 있지 않아도 안 뜬다 — hold가 none이어도.
        var off = Fake{ .config_off = true };
        if (control.wantsRunning(&off)) return fail("a config_off slot wants to run", .{});
        off.config_off = false;
        if (!control.wantsRunning(&off)) return fail("a slot back on does not want to run", .{});
    }
```

### 1-4. `service_cli.zig` — 편집 하나

E1 — `old_string`(기준 파일 103줄부터):

```zig
    const verb = std.meta.stringToEnum(control.Verb, std.mem.span(argv[1])) orelse return usage();
```

`new_string`:

```zig
    const verb = std.meta.stringToEnum(control.Verb, std.mem.span(argv[1])) orelse return usage();
    // TC-M2의 둘(config · reload)은 tars-config의 동사다(reload design 결정 1).
    if (verb == .config or verb == .reload) return usage();
```

### 1-5. `firewall.zig` — 편집 하나

E1 — `old_string`(기준 파일 90줄부터):

```zig
    std.debug.print("tars-init: firewall NOT up, inbound is open\n", .{});
}
```

`new_string`:

```zig
    std.debug.print("tars-init: firewall NOT up, inbound is open\n", .{});
}

/// TC-M2. 규칙을 내린다 — `firewall=on`에서 `off`로 reload했을 때(reload design 결정 3의 5단계).
/// 부팅에는 이 길이 없다(`up(.off)`는 아무것도 안 올린다). `nft flush ruleset`은 init이 올린
/// 것 말고 사람이 손수 올린 규칙도 지운다 — `firewall=off`가 "거르지 않는다"는 뜻이라 맞는
/// 동작으로 본다(design 위험 3). 기다리는 것은 `up`과 같다(design 결정 4).
pub fn down(envp: [*:null]const ?[*:0]const u8) bool {
    const pid = linux.fork();
    if (failed(pid)) |e| {
        std.debug.print("tars-init: cannot fork for nft (errno {d})\n", .{@intFromEnum(e)});
        return false;
    }
    if (pid == 0) {
        const argv = [_:null]?[*:0]const u8{ NFT_PATH.ptr, "flush", "ruleset", null };
        _ = linux.execve(NFT_PATH.ptr, &argv, envp);
        std.debug.print("tars-init: cannot exec {s}\n", .{NFT_PATH});
        linux.exit(127);
    }
    var status: u32 = 0;
    while (true) {
        const rc = linux.wait4(@intCast(pid), &status, 0, null);
        if (failed(rc)) |e| {
            if (e == .INTR) continue;
            std.debug.print("tars-init: waiting for nft failed (errno {d})\n", .{@intFromEnum(e)});
            return false;
        }
        break;
    }
    if (linux.W.IFEXITED(status) and linux.W.EXITSTATUS(status) == 0) {
        std.debug.print("tars-init: firewall down (nft flush ruleset), inbound is open\n", .{});
        return true;
    }
    std.debug.print("tars-init: nft flush ruleset failed (status {d})\n", .{status});
    return false;
}
```

### 1-6. `main.zig` — 편집 열여섯

E1 import · E2 `configLog` · E3 `Child.config_off` · E4 `findService` · E5 ~ E8 `answer` · `serveControl` · E9 reload의 본체(`Live` ~ `doReload`) · E10 ~ E12
`supervise` · E13 `noconfig` · E14 `Live`를 짓는다 · E15 칸 열셋 · E16 `supervise`를 부른다.

E1 — `old_string`(기준 파일 15줄부터):

```zig
const audio = @import("audio.zig");
```

`new_string`:

```zig
const audio = @import("audio.zig");
const reload = @import("reload.zig");
```

E2 — `old_string`(기준 파일 22줄부터):

```zig
    return if (e == .SUCCESS) null else e;
```

`new_string`:

```zig
    return if (e == .SUCCESS) null else e;
}

/// TC-M2(reload design 결정 3). config.zig의 로그가 root의 이 이름으로 온다(`config.log`).
/// 찍는 바이트는 그 전과 같다 — `tars-init: ` + 글 + 개행. 더하는 것은 세는 것뿐이고, reload가
/// 그 수로 "init의 파서가 한 마디라도 했다"를 보고 파일을 거절한다. 부팅은 수를 안 본다.
var config_heard: struct { count: usize = 0, len: usize = 0, buf: [160]u8 = undefined } = .{};

pub fn configLog(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("tars-init: " ++ fmt ++ "\n", args);
    config_heard.count +|= 1;
    if (config_heard.count != 1) return;
    var w: std.Io.Writer = .fixed(&config_heard.buf);
    w.print(fmt, args) catch {};
    config_heard.len = w.end;
```

E3 — `old_string`(기준 파일 390줄부터):

```zig
    kill_at: isize = 0,
```

`new_string`:

```zig
    kill_at: isize = 0,
    /// TC-M2(reload design 결정 5). 설정(tars.conf · services.d)이 이 칸을 안 원한다. 데몬 셋과
    /// 서비스 여덟의 칸은 부팅부터 늘 있고, 원하지 않는 칸이 이것으로 꺼져 있다 — 안 뜨고,
    /// `status`에 안 나오고, `tars-service`가 이름으로 못 찾는다.
    config_off: bool = false,
```

E4 — `old_string`(기준 파일 449줄부터):

```zig
        if (c.kind != .service) continue;
```

`new_string`:

```zig
        if (c.kind != .service or c.config_off) continue;
```

E5 — `old_string`(기준 파일 458줄부터):

```zig
fn answer(children: []Child, req: control.Request, out: *control.Out) void {
    const now = monotonicSeconds();
    if (req.verb == .status) {
        for (children) |*c| {
```

`new_string`:

```zig
fn answer(children: []Child, live: *Live, req: control.Request, out: *control.Out) void {
    const now = monotonicSeconds();
    // TC-M2의 둘. 이름이 없다(control.parseRequest가 지켰다).
    if (req.verb == .config) {
        reload.configReply(out, live.cfg, live.screen);
        return;
    }
    if (req.verb == .reload) {
        doReload(children, live, out, now);
        return;
    }
    if (req.verb == .status) {
        for (children) |*c| {
            // 설정이 끈 칸은 없는 것처럼 — TC-M2 전의 status와 줄이 같다(reload design 결정 5).
            if (c.config_off) continue;
```

E6 — `old_string`(기준 파일 471줄부터):

```zig
    const name = req.name.?;
```

`new_string`:

```zig
    const name = req.name orelse {
        out.print(control.ERROR_PREFIX ++ "bad request\n", .{});
        return;
    };
```

E7 — `old_string`(기준 파일 486줄부터):

```zig
fn serveControl(children: []Child, lfd: i32) void {
```

`new_string`:

```zig
fn serveControl(children: []Child, live: *Live, lfd: i32) void {
```

E8 — `old_string`(기준 파일 503줄부터):

```zig
                answer(children, req, &out);
```

`new_string`:

```zig
                answer(children, live, req, &out);
```

E9 — `old_string`(기준 파일 511줄부터):

```zig
    control.reply(got.fd, out.bytes());
```

`new_string`:

```zig
    control.reply(got.fd, out.bytes());
}

// ── TC-M2. reload ─────────────────────────────────────────────────────

/// 감독 목록의 칸 번호. 0 · 1이 terminal과 콘솔 셸, 2 ~ 4가 데몬 셋, 그 뒤 여덟이 services.d다.
/// 칸은 부팅부터 늘 이 수만큼 있고 원하지 않는 칸은 `config_off`다(reload design 결정 5).
const SLOT_WIFI: usize = 2;
const SLOT_DHCPCD: usize = 3;
const SLOT_CHRONYD: usize = 4;
const SLOT_SERVICES: usize = 5;
const SLOTS: usize = SLOT_SERVICES + services.MAX;

/// init이 부팅에 정하고 reload가 다시 정하는 것(reload design 결정 5). `main()`의 스택에 살고
/// `supervise()`가 영영 반환하지 않으므로 프로세스 수명 내내 유효하다 — argv · env 포인터가
/// 이 안을 가리킨다.
const Live = struct {
    /// init이 지금 쓰는 설정. cmdline의 `tars.noconfig`를 덮은 뒤의 값이다.
    cfg: config.Config,
    /// terminal이 뜰 때 받은 값. 화면 쪽 키는 TC-M2에서 다음 부팅까지 이것이다.
    screen: config.Config,
    mounted: bool,
    noconfig: bool,
    /// 커널이 준 env. 블록을 다시 지을 때의 바탕이다.
    kernel_env: [*:null]const ?[*:0]const u8,
    /// env 블록 두 벌과 TZ 글자 두 벌. reload가 쓰지 않는 쪽에 새 블록을 다 지은 뒤 `envp`
    /// 하나를 바꾼다 — 짓다 멈춰도 옛 블록이 그대로다.
    env: [2]environ.Block = undefined,
    tz: [2][environ.TZ_ENTRY_MAX]u8 = undefined,
    which: u1 = 0,
    envp: [*:null]const ?[*:0]const u8,
    /// 서비스 칸 여덟의 글자(경로 · 라벨). 칸의 `path` · `label`이 이 안을 가리킨다.
    services: [services.MAX]services.Entry = undefined,
};

/// 칸 하나의 목표를 설정이 정한 대로 바꾼다. 실제 fork · kill · 거두기는 감독 루프가 한다 —
/// CT의 stop · start와 같은 길이다(reload design 결정 4).
fn steer(c: *Child, s: reload.Step, now: isize, out: *control.Out) void {
    const pid = c.pid;
    switch (s) {
        .keep => return,
        .start => {
            c.config_off = false;
            _ = control.apply(.start, c, now);
        },
        .stop => {
            c.config_off = true;
            const done = control.apply(.stop, c, now);
            if (done.signal) _ = linux.kill(-pid, .TERM);
        },
        .restart => {
            const done = control.apply(.restart, c, now);
            if (done.signal) _ = linux.kill(-pid, .TERM);
        },
    }
    out.print("{s}: {s}\n", .{ c.label, switch (s) {
        .keep => "",
        .start => "starts",
        .stop => "stops",
        .restart => "restarts",
    } });
    std.debug.print("tars-init: reload: {s} {s}\n", .{ c.label, @tagName(s) });
}

/// 서비스 칸 i에 새 서비스를 넣는다. 칸은 비었거나 꺼졌고 이미 거둬졌다(`reload.serviceActions`).
fn placeService(children: []Child, live: *Live, i: usize, e: *const services.Entry) void {
    if (i >= services.MAX or SLOT_SERVICES + i >= children.len) return;
    live.services[i] = e.*;
    const s = &live.services[i];
    children[SLOT_SERVICES + i] = .{
        .kind = .service,
        .label = s.label(),
        .path = s.path(),
        .argv = .{ s.path().ptr, null, null, null, null, null, null, null, null },
    };
}

/// 셸 · 시간대가 바뀌면 콘솔 셸의 argv · 로그인 셸 · env 블록 · sshd의 SetEnv를 다시 짓는다.
/// 부팅의 그 자리(`main()`)와 같은 함수들을 같은 순서로 부른다.
fn rebuildShellAndEnv(children: []Child, live: *Live, new: config.Config) void {
    const shell = resolveShell(new.shell);
    const console = &children[1];
    console.path = shell.path();
    console.argv[0] = shell.path().ptr;
    console.argv[CONSOLE_FLAG_SLOT] = switch (new.shell_config) {
        .on => null,
        .off => shell.noConfigFlag().ptr,
    };
    console.rescue = if (live.mounted and new.shell_config == .on)
        .{ .slot = CONSOLE_FLAG_SLOT, .flag = shell.noConfigFlag() }
    else
        null;

    const tz = resolveTimezone(new.timezone);
    const next: u1 = live.which ^ 1;
    const tz_entry = environ.tzEntry(&live.tz[next], tz.slice());
    live.envp = environ.withTarsEnv(live.kernel_env, &live.env[next], tz_entry, shell.histEntries());
    live.which = next;

    var ssh_env: [3 + 4][]const u8 = undefined;
    var n: usize = 0;
    for ([_][]const u8{ environ.PATH_ENTRY, environ.XDG_ENTRY, tz_entry }) |e| {
        ssh_env[n] = e;
        n += 1;
    }
    for (shell.histEntries()) |e| {
        if (n >= ssh_env.len) break;
        ssh_env[n] = e;
        n += 1;
    }
    login.apply(login.PASSWD_PATH, login.SSH_ENV_PATH, shell.path(), ssh_env[0..n]);
    std.debug.print("tars-init: reload: console shell {s}, env {s}\n", .{ shell.path(), tz_entry });
}

/// `reload` 동사(reload design 결정 3). 순서가 계약이다 — 조이고(방화벽 켜기), 데몬 · 서비스의
/// 목표를 바꾸고, 셸 · env를 다시 짓고, 푼다(방화벽 끄기). 기다리는 것은 파일 읽기와 nft뿐이다.
fn doReload(children: []Child, live: *Live, out: *control.Out, now: isize) void {
    if (children.len < SLOTS) {
        out.print(control.ERROR_PREFIX ++ "the supervisor has {d} slots, want {d}\n", .{ children.len, SLOTS });
        return;
    }
    if (!live.mounted) {
        out.print(control.ERROR_PREFIX ++ "no config disk is mounted at /config; nothing to reload\n", .{});
        return;
    }
    config_heard = .{};
    const loaded = config.load(CONFIG_PATH) orelse {
        out.print(control.ERROR_PREFIX ++ "no {s}; nothing changed\n", .{CONFIG_PATH});
        return;
    };
    if (config_heard.count != 0) {
        out.print(control.ERROR_PREFIX ++ "{s}: {s}", .{ CONFIG_PATH, config_heard.buf[0..config_heard.len] });
        if (config_heard.count > 1) out.print(" (and {d} more)", .{config_heard.count - 1});
        out.print("; nothing changed (tars-config check)\n", .{});
        std.debug.print("tars-init: reload refused, {s} has {d} line(s) init would not take\n", .{ CONFIG_PATH, config_heard.count });
        return;
    }
    var new = loaded;
    if (live.noconfig) new.shell_config = .off;
    const old = live.cfg;
    const keys = reload.changed(old, new);
    std.debug.print("tars-init: reload of {s}\n", .{CONFIG_PATH});
    const before = out.len;
    reload.keyLines(out, old, new);

    // 1. 조인다.
    const fw = reload.firewallStep(old.firewall, new.firewall);
    if (fw == .up) {
        firewall.up(.on, live.envp);
        out.print("firewall: up (nft -f /etc/tars/firewall.nft)\n", .{});
    }

    // 2. 데몬 셋. 셋의 판정은 부팅의 함수 그대로다. 무선은 키가 안 바뀌어도 다시 묻는다 —
    //    `tars-config wifi`가 처음 만든 파일을 reload가 띄운다.
    const want_wifi = wifi.wants(new.net, live.mounted, wifi.CONF_PATH);
    steer(&children[SLOT_WIFI], reload.step(!children[SLOT_WIFI].config_off, want_wifi, false), now, out);
    if (keys.has("net")) {
        const want_dhcpcd = net.wantsDhcpcd(new.net);
        steer(&children[SLOT_DHCPCD], reload.step(!children[SLOT_DHCPCD].config_off, want_dhcpcd, false), now, out);
    }
    if (keys.has("net") or keys.has("ntp")) {
        const want_chronyd = clock.prepare(new.net, new.ntp, live.mounted);
        steer(&children[SLOT_CHRONYD], reload.step(!children[SLOT_CHRONYD].config_off, want_chronyd, want_chronyd), now, out);
    }

    // 3. services.d를 다시 읽는다(design 결정 11). 이미 있는 이름은 안 건드린다.
    var list = services.List{};
    services.discover(services.DIR, &list);
    var slots: [services.MAX]reload.Slot = undefined;
    for (&slots, 0..) |*sl, i| {
        const c = &children[SLOT_SERVICES + i];
        const label = c.label;
        sl.* = .{
            .name = if (label.len > services.LABEL_PREFIX.len) label[services.LABEL_PREFIX.len..] else "",
            .off = c.config_off,
            .alive = c.pid >= 0,
        };
    }
    var names: [services.MAX][]const u8 = undefined;
    const entries = list.slice();
    for (entries, 0..) |*e, i| {
        const label = e.label();
        names[i] = if (label.len > services.LABEL_PREFIX.len) label[services.LABEL_PREFIX.len..] else "";
    }
    var actions: [2 * services.MAX]reload.SvcAction = undefined;
    const n = reload.serviceActions(&slots, names[0..entries.len], &actions);
    for (actions[0..n]) |a| switch (a) {
        .stop => |i| steer(&children[SLOT_SERVICES + i], .stop, now, out),
        .revive => |i| steer(&children[SLOT_SERVICES + i], .start, now, out),
        .add => |p| {
            if (p.name >= entries.len) continue;
            placeService(children, live, p.slot, &entries[p.name]);
            out.print("{s}: starts (new in {s})\n", .{ entries[p.name].label(), services.DIR });
            std.debug.print("tars-init: reload: {s} joins the services\n", .{entries[p.name].label()});
        },
        .no_room => |i| if (i < entries.len) {
            out.print("{s}: no free slot until the next boot ({d} at most)\n", .{ entries[i].label(), services.MAX });
        },
    };

    // 4 · 5. 셸과 env. 다음에 뜨는 콘솔 셸 · 서비스 · ssh 로그인부터다.
    if (keys.has("shell") or keys.has("shell_config") or keys.has("timezone")) rebuildShellAndEnv(children, live, new);

    // 6. 푼다.
    if (fw == .down) {
        if (firewall.down(live.envp)) {
            out.print("firewall: down (nft flush ruleset)\n", .{});
        } else {
            out.print("firewall: nft flush ruleset failed; the rules stay up\n", .{});
        }
    }

    live.cfg = new;
    if (out.len == before) out.print("nothing changed\n", .{});
```

E10 — `old_string`(기준 파일 533줄부터):

```zig
    control_fd: ?i32,
    envp: [*:null]const ?[*:0]const u8,
```

`new_string`:

```zig
    control_fd: ?i32,
    live: *Live,
```

E11 — `old_string`(기준 파일 563줄부터):

```zig
            if (control.wantsRunning(c)) start(c, envp);
```

`new_string`:

```zig
            // env는 reload가 갈아 끼울 수 있어서 바퀴마다 `live`에서 읽는다(TC-M2).
            if (control.wantsRunning(c)) start(c, live.envp);
```

E12 — `old_string`(기준 파일 736줄부터):

```zig
            if (p.revents & linux.POLL.IN != 0) serveControl(children, p.fd);
```

`new_string`:

```zig
            if (p.revents & linux.POLL.IN != 0) serveControl(children, live, p.fd);
```

E13 — `old_string`(기준 파일 790줄부터):

```zig
    if (config.cmdlineNoConfig(config.CMDLINE_PATH)) {
```

`new_string`:

```zig
    const noconfig = config.cmdlineNoConfig(config.CMDLINE_PATH);
    if (noconfig) {
```

E14 — `old_string`(기준 파일 1044줄부터):

```zig
    // SV-M1 · DS-M1. 앞 둘은 SV 전과 같고, 그 뒤에 init이 스스로 넣는 데몬 둘이
    // (DS design 결정 1), 그 뒤에 서비스가 이름순으로 붙는다. 크기는 컴파일
    // 타임에 정해진다(힙이 없다) — 쓰는 것은 앞에서 `n + len`까지다.
    var children: [2 + services.RESERVED.len + services.MAX]Child = undefined;
```

`new_string`:

```zig
    // TC-M2. init이 부팅에 정한 것을 reload가 다시 정할 수 있게 한 자리에 든다(reload design
    // 결정 5). 아래 서비스 칸의 글자가 이 안을 가리키므로 `children`보다 앞이다.
    var live = Live{
        .cfg = cfg,
        .screen = cfg,
        .mounted = storage_mounted,
        .noconfig = noconfig,
        .kernel_env = init.environ.block.slice.ptr,
        .envp = envp,
    };

    // SV-M1 · DS-M1 · TC-M2. 앞 둘은 SV 전과 같고, 그 뒤에 init이 스스로 넣는 데몬 셋이(DS design
    // 결정 1 · WL), 그 뒤에 서비스 여덟의 칸이 온다. TC-M2부터 칸은 늘 열셋이고 원하지 않는 칸은
    // `config_off`다 — reload가 dhcpcd를 켜거나 services.d에 새 이름을 넣을 자리가 늘 있다(reload
    // design 결정 5). 띄우는 순서(배열 순서)는 그 전과 같다.
    var children: [SLOTS]Child = undefined;
```

E15 — `old_string`(기준 파일 1084줄부터):

```zig
    var n: usize = 2;
    // DS-M1. 서비스와 같은 Kind라 CT의 규칙(그룹 시그널 · 요청한 죽음은 안 셈 ·
    // tars-service의 동사 넷)이 코드 없이 그대로 선다. 탈출로는 없다.
    // WL-M2. wpa_supplicant도 같은 자리의 셋째다.
    if (want_wifi) {
        children[n] = .{
            .kind = .service,
            .label = services.LABEL_PREFIX ++ services.WPA_SUPPLICANT,
            .path = wifi.WIFI_PATH,
            .argv = wifi.WIFI_ARGV,
        };
        n += 1;
    }
    if (want_dhcpcd) {
        children[n] = .{
            .kind = .service,
            .label = services.LABEL_PREFIX ++ services.DHCPCD,
            .path = net.DHCPCD_PATH,
            .argv = net.DHCPCD_ARGV,
        };
        n += 1;
    }
    if (want_chronyd) {
        children[n] = .{
            .kind = .service,
            .label = services.LABEL_PREFIX ++ services.CHRONYD,
            .path = clock.CHRONYD_PATH,
            .argv = clock.CHRONYD_ARGV,
        };
        n += 1;
    }
    for (service_list.slice(), 0..) |*s, i| {
        children[n + i] = .{
            .kind = .service,
            .label = s.label(),
            .path = s.path(),
            // 인자는 없다 — 서비스는 실행 파일 하나이고(결정 2), 준비할 것은
            // 스크립트가 한다. 탈출로도 없다(결정 3).
            .argv = .{ s.path().ptr, null, null, null, null, null, null, null, null },
        };
```

`new_string`:

```zig
    // DS-M1. 서비스와 같은 Kind라 CT의 규칙(그룹 시그널 · 요청한 죽음은 안 셈 ·
    // tars-service의 동사 넷)이 코드 없이 그대로 선다. 탈출로는 없다.
    // WL-M2. wpa_supplicant도 같은 자리의 셋째다.
    children[SLOT_WIFI] = .{
        .kind = .service,
        .label = services.LABEL_PREFIX ++ services.WPA_SUPPLICANT,
        .path = wifi.WIFI_PATH,
        .argv = wifi.WIFI_ARGV,
        .config_off = !want_wifi,
    };
    children[SLOT_DHCPCD] = .{
        .kind = .service,
        .label = services.LABEL_PREFIX ++ services.DHCPCD,
        .path = net.DHCPCD_PATH,
        .argv = net.DHCPCD_ARGV,
        .config_off = !want_dhcpcd,
    };
    children[SLOT_CHRONYD] = .{
        .kind = .service,
        .label = services.LABEL_PREFIX ++ services.CHRONYD,
        .path = clock.CHRONYD_PATH,
        .argv = clock.CHRONYD_ARGV,
        .config_off = !want_chronyd,
    };
    for (0..services.MAX) |i| {
        if (i < service_list.len) {
            // 인자는 없다 — 서비스는 실행 파일 하나이고(결정 2), 준비할 것은
            // 스크립트가 한다. 탈출로도 없다(결정 3).
            placeService(&children, &live, i, &service_list.entries[i]);
        } else {
            children[SLOT_SERVICES + i] = .{
                .kind = .service,
                .label = "",
                .path = "",
                .argv = .{ null, null, null, null, null, null, null, null, null },
                .config_off = true,
            };
        }
```

E16 — `old_string`(기준 파일 1128줄부터):

```zig
    supervise(children[0 .. n + service_list.len], button_fds[0..button_count], control_fd, envp);
```

`new_string`:

```zig
    supervise(&children, button_fds[0..button_count], control_fd, &live);
```

### 1-7. `build.zig` — 편집 둘

E1 — `old_string`(기준 파일 298줄부터):

```zig
    // installArtifact를 부르지 않는다. terminal/build.zig의 input_test는
```

`new_string`:

```zig
    // TC-M2: reload가 무엇을 할지(diff · 갈래 · 순서 · services.d · 답의 글자). PID 1의 코드라 셈과
    // 경계를 여기서 다 본다(reload design 결정 8). config_test와 같은 이유로 host_target이다.
    const reload_test_mod = b.createModule(.{
        .root_source_file = b.path("src/reload_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const reload_test = b.addExecutable(.{
        .name = "reload_test",
        .root_module = reload_test_mod,
    });

    // installArtifact를 부르지 않는다. terminal/build.zig의 input_test는
```

E2 — `old_string`(기준 파일 316줄부터):

```zig
    test_step.dependOn(&b.addRunArtifact(config_front_edit_test).step);
```

`new_string`:

```zig
    test_step.dependOn(&b.addRunArtifact(config_front_edit_test).step);
    test_step.dependOn(&b.addRunArtifact(reload_test).step);
```

### 1-8. `config_cli.zig` — 편집 여덟

E1 — `old_string`(기준 파일 15줄부터):

```zig
const front = @import("config_front.zig");
```

`new_string`:

```zig
const front = @import("config_front.zig");
const control = @import("control.zig");
```

E2 — `old_string`(기준 파일 79줄부터):

```zig
    \\       tars-config list                every key with its default and the values it takes
```

`new_string`:

```zig
    \\       tars-config list                every key with its default and the values it takes
    \\       tars-config reload              init rereads tars.conf and services.d now (TC-M2)
```

E3 — `old_string`(기준 파일 205줄부터):

```zig
// ── show · get ────────────────────────────────────────────────────────
```

`new_string`:

```zig
// ── init에 묻기(TC-M2) ────────────────────────────────────────────────

/// `config`의 답을 기다리는 시간. `tars-service`와 같다.
const ASK_MS: i32 = 2000;
/// `reload`의 답. init이 nft 한 번과 services.d를 지나 답한다(reload design 결정 4).
const RELOAD_MS: i32 = 10000;

/// init.sock에 동사 하나를 보내고 답을 받는다. 못 닿거나 답이 없으면 null.
fn askInit(verb: control.Verb, buf: []u8, ms: i32) ?[]const u8 {
    var req_buf: [16]u8 = undefined;
    const req = control.formatRequest(&req_buf, verb, null) orelse return null;
    return switch (control.dial(control.PATH, req)) {
        .failed => null,
        .fd => |fd| control.awaitReply(fd, buf, ms),
    };
}

/// `config`의 답에서 그 키의 값.
fn nowValue(reply: []const u8, key: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, reply, '\n');
    while (it.next()) |line| {
        if (line.len > key.len and std.mem.startsWith(u8, line, key) and line[key.len] == '=') return line[key.len + 1 ..];
    }
    return null;
}

/// `config`의 답의 `screen …` 줄(화면이 대기 중인 키)의 꼬리. 없으면 null.
fn screenLine(reply: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, reply, '\n');
    while (it.next()) |line| if (std.mem.startsWith(u8, line, "screen ")) return line["screen".len..];
    return null;
}

/// `tars-config reload`(reload design 결정 7). init의 답을 그대로 찍는다.
fn reloadInit() u8 {
    var buf: [control.REPLY_MAX]u8 = undefined;
    const r = askInit(.reload, &buf, RELOAD_MS) orelse {
        complain("init did not answer at {s}", .{control.PATH});
        return EXIT_IO;
    };
    _ = writeAll(1, r);
    return if (std.mem.startsWith(u8, r, control.ERROR_PREFIX)) EXIT_REFUSED else EXIT_OK;
}

// ── show · get ────────────────────────────────────────────────────────
```

E4 — `old_string`(기준 파일 224줄부터):

```zig
    const complaints = edit.heard.count;
```

`new_string`:

```zig
    const complaints = edit.heard.count;
    // TC-M2. init이 지금 쓰는 값(reload design 결정 1). 파일과 다른 키는 그 줄 밑에 주석 한 줄로
    // 적는다 — 같은 줄 끝에 적으면 이 출력이 더는 그대로 쓸 수 있는 tars.conf가 아니다(TC 결정 8).
    var now_buf: [control.REPLY_MAX]u8 = undefined;
    const now = askInit(.config, &now_buf, ASK_MS);
```

E5 — `old_string`(기준 파일 230줄부터):

```zig
        say("{s}{s}={s}\n", .{ mark, key, value });
    }
```

`new_string`:

```zig
        say("{s}{s}={s}\n", .{ mark, key, value });
        if (now) |r| if (nowValue(r, key)) |v| if (!std.mem.eql(u8, v, value))
            say("#   init uses {s}={s} now; tars-config reload applies the line above\n", .{ key, v });
    }
    if (now) |r| if (screenLine(r)) |sl|
        say("# the screen keeps{s} until the next boot\n", .{sl});
    if (now == null and cur.disk != null) say("# init did not answer at {s}; only the file is shown\n", .{control.PATH});
```

E6 — `old_string`(기준 파일 239줄부터):

```zig
    if (cur.disk != null) say("# change: tars-config set KEY=VALUE, then reboot (kill -INT 1)\n", .{});
```

`new_string`:

```zig
    if (cur.disk != null) say("# change: tars-config set KEY=VALUE, then tars-config reload (or reboot)\n", .{});
```

E7 — `old_string`(기준 파일 375줄부터):

```zig
    say("init reads {s} only at boot; reboot to apply (kill -INT 1)\n", .{CONF_PATH});
```

`new_string`:

```zig
    say("apply it now: tars-config reload (the screen's keys wait for the next boot)\n", .{});
```

E8 — `old_string`(기준 파일 497줄부터):

```zig
    if (std.mem.eql(u8, verb, "check")) {
```

`new_string`:

```zig
    if (std.mem.eql(u8, verb, "reload")) {
        if (rest.len != 0) return usage();
        return reloadInit();
    }
    if (std.mem.eql(u8, verb, "check")) {
```

### 1-9. `config_front.zig` — 편집 넷

E1 — `old_string`(기준 파일 270줄부터):

```zig
        say("init starts wpa_supplicant only when this file is there at boot; reboot (kill -INT 1)\n", .{});
```

`new_string`:

```zig
        say("apply now: tars-config reload starts wpa_supplicant (or the next boot)\n", .{});
```

E2 — `old_string`(기준 파일 335줄부터):

```zig
                say("sshd: on — {s} -> {s}; init starts it at the next boot (kill -INT 1)\n", .{ SSHD_LINK, SSHD_TEMPLATE });
```

`new_string`:

```zig
                say("sshd: on — {s} -> {s}; tars-config reload starts it now (or the next boot)\n", .{ SSHD_LINK, SSHD_TEMPLATE });
```

E3 — `old_string`(기준 파일 356줄부터):

```zig
                say("sshd: off from the next boot; to stop it now: tars-service stop sshd\n", .{});
```

`new_string`:

```zig
                say("sshd: off — tars-config reload stops it now (or the next boot)\n", .{});
```

E4 — `old_string`(기준 파일 439줄부터):

```zig
    if (sshdLinked() == .none) say("sshd is off: tars-config ssh on, then reboot\n", .{});
```

`new_string`:

```zig
    if (sshdLinked() == .none) say("sshd is off: tars-config ssh on, then tars-config reload\n", .{});
```

### 1-10. 확인

```bash
for f in init/src/reload.zig init/src/reload_test.zig init/src/control.zig init/src/control_test.zig init/src/service_cli.zig init/src/firewall.zig \
  init/src/main.zig init/build.zig init/src/config_cli.zig init/src/config_front.zig; do cmp $f /tmp/run/tc2/new/$f && echo "SAME $f"; done
rg -n 'unreachable|\.\?' init/src/reload.zig
mkdir -p /tmp/run/tc2/impl
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer bash -c '
  rm -rf zig-out .zig-cache
  zig build; echo "build exit=$?"; ls -l zig-out/bin
  zig build test > /tmp/t.log 2>&1; echo "test exit=$?"
  grep -a "^reload_test:\|^control_test: requests\|^PASS" /tmp/t.log; grep -a "^FAIL" /tmp/t.log | head'
rmdir /tmp/run/docker.lock
```

기대: `SAME` 열, `rg`가 `reload.zig`에서 아무것도 못 찾는다(주석 속 낱말 둘 — `unreachable`과 `.?`를 쓰지 않는다는 머리 주석 — 만 나오면 그것이 다다),
`build exit=0`, `test exit=0`, `reload_test:` 여섯 줄 · `control_test: requests — six verbs, …` · `PASS` 여섯, `FAIL` 없음.

## Task 2: 체인 넷

확정 4.

`config/check.sh`:

E1 — `old_string`(기준 파일 117줄부터):

```bash
TC_LIST_KEYS=(t a r s minus c o n f i g spc l i s t ret)
```

`new_string`:

```bash
TC_LIST_KEYS=(t a r s minus c o n f i g spc l i s t ret)
# tars-config set keyboard=pc · tars-config reload · echo shell=fsh >> /config/tars.conf (TC-M2)
TC_SET_KB_KEYS=(t a r s minus c o n f i g spc s e t spc k e y b o a r d equal p c ret)
TC_RELOAD_KEYS=(t a r s minus c o n f i g spc r e l o a d ret)
TC_BAD_LINE_KEYS=(e c h o spc s h e l l equal f s h spc shift-dot shift-dot spc
                  slash c o n f i g slash t a r s dot c o n f ret)
```

E2 — `old_string`(기준 파일 550줄부터):

```bash
  echo "boot 1: tars-config list printed all ${#TC_LIST_WANT[@]} keys with their defaults and the values they take"
```

`new_string`:

```bash
  echo "boot 1: tars-config list printed all ${#TC_LIST_WANT[@]} keys with their defaults and the values they take"

  # ── TC-M2: reload의 대기 · 두 칸 · 거절 ─────────────────────────────────
  #
  # keyboard는 화면의 키다(위 TC-M0이 바꾼 clipboard=pane도 그렇다 — 둘 다 대기다). reload가 init의 값을 바꾸지만 화면(terminal)은 다음 부팅까지 apple이다 —
  # 그래서 이 부팅의 타이핑이 그대로 된다. 이 체인은 net=off라 reload가 dhcpcd를 건드리면 안 된다.
  # 끝으로 init이 거절할 줄을 심은 파일의 reload가 아무것도 안 바꾸는지 본다. 아래 EDIT_KEYS가 이
  # 파일을 한 줄로 덮어쓰므로 2차로 넘어가는 것은 없다.
  type_keys "${TC_SET_KB_KEYS[@]}"
  type_keys "${TC_RELOAD_KEYS[@]}"
  if ! wait_for_screen '\| keyboard: apple -> pc \(the screen keeps the old value until the next boot\)'; then
    echo "FAIL(boot 1): reload did not report keyboard as waiting for the screen"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  if joined_screen_dump | grep -aF 'service dhcpcd' >/dev/null; then
    echo "FAIL(boot 1): a reload that changed no network key touched dhcpcd"
    return 1
  fi
  type_keys "${ALIAS_KEYS[@]}"
  if ! wait_for_screen '\| # the screen keeps keyboard=apple clipboard=shared until the next boot'; then
    echo "FAIL(boot 1): tars-config did not show that the screen still uses keyboard=apple"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  type_keys "${TC_BAD_LINE_KEYS[@]}"
  type_keys "${TC_RELOAD_KEYS[@]}"
  if ! wait_for_screen "\\| error: /config/tars\\.conf: unknown shell 'fsh', falling back to fish; nothing changed"; then
    echo "FAIL(boot 1): reload did not refuse a file with a line init would not take"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 1: reload left keyboard=pc waiting for the screen, showed both values, and refused a file with shell=fsh"
```

`net/check.sh`:

E1 — `old_string`(기준 파일 984줄부터):

```bash
# ── 끈다 ──────────────────────────────────────────────────────────────
```

`new_string`:

```bash
# ── 검사 31: reload가 네트워크를 끄고 다시 켠다 (TC-M2) ────────────────────
# 사람이 `tars-config set net=off`와 `tars-config reload`를 친다. init이 tars.conf를 다시 읽고
# dhcpcd를 멈춘다 — SIGTERM을 받은 dhcpcd는 주소를 지우고 간다(DS). 다시 `net=dhcp`와 reload면 같은
# 부팅 안에서 dhcpcd가 새로 뜨고 lease를 받는다. 재부팅이 없다는 것은 `started service dhcpcd`가 이
# 로그에 둘이라는 것이다. 판정 글자 nw0은 우리가 짓는다(echo).
NW_LEASES_BEFORE="$(grep -ac 'eth0: leased 10\.0\.2\.15 ' "$LOG")"
echo "=== typing 'tars-config set net=off' and 'tars-config reload' ==="
type_keys t a r s minus c o n f i g spc s e t spc n e t equal o f f ret
type_keys t a r s minus c o n f i g spc r e l o a d ret
wait_for_screen '\| service dhcpcd: stops' \
  || fail "reload did not stop dhcpcd after net=off" "terminal: screen>" "tars-init: reload"
for _ in $(seq 1 40); do grep -a "tars-init: service dhcpcd stopped on request" "$LOG" >/dev/null && break; sleep 0.25; done
grep -a "tars-init: service dhcpcd stopped on request" "$LOG" >/dev/null \
  || fail "init never reaped the dhcpcd that reload stopped" "tars-init: reload" "dhcpcd"
type_keys e c h o spc n w shift-4 shift-9 i p spc minus 4 spc a d d r spc s h o w spc e t h 0 spc \
  shift-backslash spc g r e p spc minus c spc i n e t shift-0 ret
wait_for_screen '\| nw0' || fail "eth0 kept its address after reload turned the network off" "terminal: screen>"
echo "reload with net=off stopped dhcpcd and eth0 lost its address"
type_keys t a r s minus c o n f i g spc s e t spc n e t equal d h c p ret
type_keys t a r s minus c o n f i g spc r e l o a d ret
wait_for_screen '\| service dhcpcd: starts' \
  || fail "reload did not start dhcpcd after net=dhcp" "terminal: screen>" "tars-init: reload"
for _ in $(seq 1 60); do
  [ "$(grep -ac 'eth0: leased 10\.0\.2\.15 ' "$LOG")" -gt "$NW_LEASES_BEFORE" ] && break
  sleep 0.5
done
[ "$(grep -ac 'eth0: leased 10\.0\.2\.15 ' "$LOG")" -gt "$NW_LEASES_BEFORE" ] \
  || fail "the dhcpcd that reload started never leased" "tars-init: reload" "leased"
[ "$(grep -ac 'tars-init: started service dhcpcd (pid' "$LOG")" -ge 2 ] \
  || fail "dhcpcd was not started a second time in this boot" "tars-init: started service dhcpcd"
echo "reload with net=dhcp started dhcpcd again and it leased 10.0.2.15, without a reboot"

# ── 끈다 ──────────────────────────────────────────────────────────────
```

`firewall/check.sh`:

E1 — `old_string`(기준 파일 367줄부터):

```bash
echo "tars-config opened 7072 in its own file and nft put it up without a reboot"
```

`new_string`:

```bash
echo "tars-config opened 7072 in its own file and nft put it up without a reboot"

# ── 검사 19: reload가 방화벽을 내리고 다시 올린다 (TC-M2) ──────────────────
# `tars-config set firewall=off` · `reload`면 init이 `nft flush ruleset`을 돈다 — 부팅에는 없던
# 길이다(reload design 결정 3의 6단계). 규칙이 하나도 안 남는 것을 셈으로 본다(판정 글자 fwn0은
# echo가 짓는다). 다시 `on` · `reload`면 부팅의 `firewall.up`이 그대로 돌고 drop이 선다(fwp1).
echo "=== typing 'tars-config set firewall=off' and 'tars-config reload' ==="
type_keys t a r s minus c o n f i g spc s e t spc f i r e w a l l equal o f f ret
type_keys t a r s minus c o n f i g spc r e l o a d ret
wait_for_screen "firewall: down \\(nft flush ruleset\\)" \
  || fail "reload did not take the firewall down" "terminal: screen>" "tars-init: reload"
type_keys e c h o spc f w n shift-4 shift-9 n f t spc l i s t spc r u l e s e t spc \
  shift-backslash spc w c spc minus l shift-0 ret
wait_for_screen "fwn0" || fail "rules were still up after reload with firewall=off" "terminal: screen>"
type_keys t a r s minus c o n f i g spc s e t spc f i r e w a l l equal o n ret
type_keys t a r s minus c o n f i g spc r e l o a d ret
wait_for_screen "firewall: up \\(nft -f /etc/tars/firewall\\.nft\\)" \
  || fail "reload did not bring the firewall back up" "terminal: screen>" "tars-init: reload"
type_keys e c h o spc f w p shift-4 shift-9 n f t spc l i s t spc r u l e s e t spc \
  shift-backslash spc g r e p spc minus c spc d r o p shift-0 ret
wait_for_screen "fwp[1-9]" || fail "no drop policy after reload with firewall=on" "terminal: screen>"
echo "reload flushed the rules with firewall=off and put them back with firewall=on, without a reboot"
```

`service/check.sh`:

E1 — `old_string`(기준 파일 604줄부터):

```bash
grep -F 'sshd: off from the next boot' <<<"$OUT" >/dev/null || fail "ssh off did not say so (${OUT})"
[ -z "$(on_guest 'readlink /config/services.d/sshd')" ] || fail "ssh off left the services.d link"
tc ssh on
grep -F 'sshd: on' <<<"$OUT" >/dev/null || fail "ssh on did not say so (${OUT})"
[ "$(on_guest 'readlink /config/services.d/sshd')" = "/etc/tars/services/sshd" ] || fail "ssh on did not link the template"
echo "tars-config added a key sshd took at the next login, refused a duplicate and a non-key, and unlinked and relinked sshd"
```

`new_string`:

```bash
grep -F 'sshd: off — tars-config reload stops it now' <<<"$OUT" >/dev/null || fail "ssh off did not say so (${OUT})"
[ -z "$(on_guest 'readlink /config/services.d/sshd')" ] || fail "ssh off left the services.d link"
echo "tars-config added a key sshd took at the next login, refused a duplicate and a non-key, and unlinked sshd"

# ── 검사 28: reload가 services.d를 다시 읽는다 (TC-M2) ────────────────────
# 링크를 지운 뒤 reload하면 sshd가 멈추고 새 로그인이 막힌다 — 이 제어 연결은 제 세션을 가진
# sshd-session이 들고 있어 산다(검사 22와 같다). 다시 걸고 reload하면 재부팅 없이 sshd가 뜨고 새
# 로그인이 된다. 이미 있던 이름(sleeper · stubborn · flaky)은 안 건드린다 — 검사 23이 멈춘
# stubborn은 멈춘 그대로다.
tc reload
[ "$RC" = "0" ] || fail "tars-config reload gave rc ${RC} (${OUT})"
grep -Fx 'service sshd: stops' <<<"$OUT" >/dev/null || fail "reload did not stop the unlinked sshd (${OUT})"
for _ in $(seq 1 40); do fresh_ssh || break; sleep 0.25; done
fresh_ssh && fail "a fresh ssh login still worked after reload stopped sshd"
tc ssh on
grep -F 'sshd: on' <<<"$OUT" >/dev/null || fail "ssh on did not say so (${OUT})"
[ "$(on_guest 'readlink /config/services.d/sshd')" = "/etc/tars/services/sshd" ] || fail "ssh on did not link the template"
tc reload
grep -Fx 'service sshd: starts' <<<"$OUT" >/dev/null || fail "reload did not start the relinked sshd (${OUT})"
grep -E 'service (sleeper|stubborn|flaky)' <<<"$OUT" >/dev/null && fail "reload touched a service whose file did not change (${OUT})"
OK=0
for _ in $(seq 1 40); do if fresh_ssh; then OK=1; break; fi; sleep 0.25; done
[ "$OK" = "1" ] || fail "no fresh ssh login after reload restarted sshd" "sshd" "reload"
ts status stubborn
tail -1 <<<"$OUT" | grep -E '^service stubborn +stopped$' >/dev/null || fail "reload woke stubborn, which tars-service had stopped (${OUT})"
echo "reload stopped sshd when its link went and started it again when it came back, without a reboot, and left the other three alone"
```

```bash
for f in config/check.sh net/check.sh firewall/check.sh service/check.sh; do cmp $f /tmp/run/tc2/new/$f && echo "SAME $f"; bash -n $f || echo "SYNTAX $f"; done
```

기대: `SAME` 넷, `SYNTAX` 없음.

## Task 3: 체인 아홉

확정 5. 한 컨테이너에서 차례로, 15분 남짓이다. `run_in_background`로 돌린다(lock은 앞에서 잡는다).

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -v /tmp/run/tc2/impl:/impl -w /workspace tars-devcontainer bash -c '
  for c in config firewall service net boot wifi power nic terminal; do s=$(date +%s); bash $c/check.sh > /impl/chain_$c.log 2>&1
    echo "$c exit=$? $(( $(date +%s) - s ))s"; done' > /tmp/run/tc2/impl/chains.out 2>&1
rmdir /tmp/run/docker.lock
cat /tmp/run/tc2/impl/chains.out
rg -a '^boot 1: reload|^reload |^FAIL|Attempted to kill init|panic' /tmp/run/tc2/impl/chain_*.log
```

기대: 아홉 다 `exit=0`, 그리고 이 다섯(파일마다), `FAIL` · `panic` 없음.

```
chain_config.log: boot 1: reload left keyboard=pc waiting for the screen, showed both values, and refused a file with shell=fsh
chain_firewall.log: reload flushed the rules with firewall=off and put them back with firewall=on, without a reboot
chain_net.log: reload with net=off stopped dhcpcd and eth0 lost its address
chain_net.log: reload with net=dhcp started dhcpcd again and it leased 10.0.2.15, without a reboot
chain_service.log: reload stopped sshd when its link went and started it again when it came back, without a reboot, and left the other three alone
```

## Task 4: mutation

확정 6의 표다. 사본은 `/tmp/run/tc2/impl/mut/`에 만든다.

```bash
python3 /tmp/run/tc2/make_mut.py "$PWD" /tmp/run/tc2/impl/mut
M=/tmp/run/tc2/impl/mut
for p in control_m1.zig:init/src/control.zig main_m2.zig:init/src/main.zig main_m3.zig:init/src/main.zig main_m4.zig:init/src/main.zig \
  reload_m5.zig:init/src/reload.zig main_m6.zig:init/src/main.zig; do echo "${p%%:*} $(diff ${p#*:} $M/${p%%:*} | rg -c '^[<>]')"; done
```

기대: `mutation copies: 6`, 그리고 `main_m6.zig`만 `1`, 나머지 다섯은 `2`.

`make_mut.py`:

```python
"""TC-M2 plan Task 4의 mutation 사본을 만든다.

사용: python3 make_mut.py <저장소 루트> <출력 디렉터리>
저장소 파일은 읽기만 한다. 사본마다 바꾼 자리가 정확히 한 군데인지 assert한다.
"""
import os
import sys

root, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)


def make(src, dst, old, new):
    s = open(os.path.join(root, src)).read()
    assert s.count(old) == 1, (dst, old[:60])
    open(os.path.join(out, dst), 'w').write(s.replace(old, new))


C = 'init/src/control.zig'
M = 'init/src/main.zig'
R = 'init/src/reload.zig'
# mutation 1 — 설정이 끈 칸도 띄운다(wantsRunning이 config_off를 안 본다). net=off 부팅에 데몬이 뜬다
make(C, 'control_m1.zig', 'and c.hold != .stop and !c.config_off;', 'and c.hold != .stop and c.config_off == c.config_off;')
# mutation 2 — init의 파서가 불평해도 reload한다
make(M, 'main_m2.zig', '    if (config_heard.count != 0) {\n        out.print(control.ERROR_PREFIX ++ "{s}: {s}"',
     '    if (config_heard.count == 1000) {\n        out.print(control.ERROR_PREFIX ++ "{s}: {s}"')
# mutation 3 — firewall=off로 바꿔도 규칙을 안 내린다
make(M, 'main_m3.zig', '    if (fw == .down) {\n        if (firewall.down(live.envp)) {',
     '    if (fw == .keep and fw == .down) {\n        if (firewall.down(live.envp)) {')
# mutation 4 — services.d를 다시 읽지 않는다(목록이 빈 채로 견준다 — 새 이름이 없고 사라진 이름도 안 본다)
make(M, 'main_m4.zig', '    const n = reload.serviceActions(&slots, names[0..entries.len], &actions);',
     '    const n = reload.serviceActions(slots[0..0], names[0..entries.len], &actions);')
# mutation 5 — 멈추는 중인 칸도 빈 칸으로 본다(거두기 전에 pid를 넘긴다)
make(R, 'reload_m5.zig', 'const free = s.name.len == 0 or (s.off and !s.alive and indexOf(names, s.name) == null);',
     'const free = s.name.len == 0 or (s.off and indexOf(names, s.name) == null);')
# mutation 6 — status가 설정이 끈 칸도 보인다
make(M, 'main_m6.zig', '            if (c.config_off) continue;\n            if (req.name) |n| {',
     '            if (req.name) |n| {')
print('mutation copies:', len(os.listdir(out)))
```

`run_mut.sh` — 사본을 저장소 경로 위에 읽기 전용으로 덮어 그 체인 한 판을 돈다. 첫 줄 `mounted:`가 `control.zig` · `main.zig` · `reload.zig`의 md5
앞 여덟 자리다 — 덮지 않은 판은 `9721d969 d64f1a5a b3fea774`다.

```bash
#!/bin/bash
# TC-M2 plan Task 4의 mutation 한 판을 돈다.
# 사용: run_mut.sh <저장소 루트> <이미지> <사본 디렉터리> <판 이름> <체인> <사본:저장소 경로>...
# 사본을 저장소 경로 위에 읽기 전용으로 덮어 <체인>/check.sh를 한 번 돌리고, 로그를 <사본 디렉터리>/<판 이름>.log에 둔다.
# 덮은 Zig 파일은 내용이 다르므로 zig가 다시 짓는다. 판이 끝나면 init/zig-out에 망가진 바이너리가 남으니
# 마지막에 덮지 않은 판을 한 번 더 돈다.
repo=$1; img=$2; mut=$3; name=$4; chain=$5; shift 5
mounts=""
for m in "$@"; do mounts="$mounts -v $mut/${m%%:*}:/workspace/${m#*:}:ro"; done
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
s=$(date +%s)
docker run --rm -v "$repo":/workspace $mounts -w /workspace "$img" bash -c "
  echo \"mounted: \$(md5sum init/src/control.zig init/src/main.zig init/src/reload.zig | cut -c1-8 | tr '\n' ' ')\"
  bash $chain/check.sh > /tmp/m.log 2>&1; echo \"exit=\$?\"; cp /tmp/m.log /workspace/.mut_$name.log" 
rmdir /tmp/run/docker.lock
mv "$repo/.mut_$name.log" "$mut/$name.log"
echo "== $name ($chain) $(( $(date +%s) - s ))s"
grep -a '^FAIL' "$mut/$name.log" | head -2
echo "last line: $(tail -n 1 "$mut/$name.log")"
```

```bash
R="$PWD"; I=tars-devcontainer; M=/tmp/run/tc2/impl/mut; X=/tmp/run/tc2/run_mut.sh
{ $X $R $I $M m1 wifi control_m1.zig:init/src/control.zig
  $X $R $I $M m2 config main_m2.zig:init/src/main.zig
  $X $R $I $M m3 firewall main_m3.zig:init/src/main.zig
  $X $R $I $M m4 service main_m4.zig:init/src/main.zig
  $X $R $I $M m5 service reload_m5.zig:init/src/reload.zig
  $X $R $I $M m6 service main_m6.zig:init/src/main.zig
  $X $R $I $M back firewall; } > $M/run.out 2>&1
cat $M/run.out
git status --short
```

기대는 확정 6의 표에서 그 판의 `FAIL` 줄이고 `back`은 `last line: FW chain PASS`다. `git status`는 `M` 열둘과 `??` 둘이다. 예상과 다른 자리에서 죽거나
초록이면 그대로 적어 보고한다.

보고 — `git diff --stat`(전체)과 `git diff | rg '^-'`(전체), Task 0 ~ 4의 출력 전부, plan과 다른 글자.

## Task 5: lead가 하는 것

1. 보고를 받아 diff를 직접 읽고, 열네 파일을 `/tmp/run/tc2/new/`와 `cmp`한다.
2. 루트 게이트 2회, 스물한 체인 × 2다. `rg -c 'PASS: 2/2' /tmp/gate_tc2.log`가 21이어야 하고 `rg -c 'Attempted to kill init' /tmp/gate_tc2.log`가 0이어야 한다.

   ```bash
   { time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/gate_tc2.log 2>&1 ; echo "exit=$?" ; } 2> /tmp/gate_tc2.time
   ```
3. 빨갛면 "누가 무엇을 하나"의 Opus 조건을 본다.
4. 실측 절, design `Status:`, commit(열네 파일과 이 plan, design이 바뀌었으면 함께).
5. 실기 — 사용자가 노트북에서 `tars-config set net=dhcp` · `tars-config reload`와 `tars-config ssh on` · `reload`를 친다. running-tars.md의 "재부팅"
   줄들은 서브프로젝트를 닫을 때 `tars-config reload`로 고친다.

## Task 5b: 수정 1 — set의 답을 본 뒤에 reload

2026-10-07, Task 0 ~ 5를 넣고 lead의 루트 게이트를 돌린 뒤에 더했다. 첫 루트 게이트 두 회차가 net 검사 31(`reload did not stop dhcpcd
after net=off`)에서 빨갰고, /tmp를 묶어 다시 돌린 게이트는 두 회차 다 초록이었다 — 루트 맥락에서 셋 중 둘, 단독에서 넷 중 영의
간헐이다. 빨간 두 판의 시리얼에는 `tars-init: reload of /config/tars.conf` 뒤에 tars-init 줄이 하나도 없었다. 건강한 판은 그 뒤에
`net=off, wifi stays off` · `net=off, leaving the network alone` · `reload: service dhcpcd stop`이 차례로 온다(lead가 /tmp/run/tc2/lead_gate의
시리얼로 봤다). 빨간 판은 reload가 파일을 다시 읽었는데 net이 아직 dhcp였던 것 — `tars-config set net=off`가 파일을 안 바꿨거나 늦었던
것(H1)이 가장 맞고, 결정적 근거는 못 잡았다(실패한 판의 게스트 로그가 없다).

그래서 둘을 한다. set의 답을 화면에서 본 뒤에 reload를 친다 — set이 끝났다는 증거를 기다리면 그 창이 닫힌다. 그리고 검사 31이 다시
빨개지면 한 판으로 가려지게 진단을 찍는다 — 그 시점의 마지막 화면, `cat /config/tars.conf`를 쳐서 되읽은 줄, 마지막 `reload of` 뒤의
tars-init 줄들. 같은 모양("set 뒤 곧바로 reload")이 있는 firewall 검사 19 · config 1차에도 기다림을 넣는다. service 검사 28은 ssh 명령이
하나씩 끝난 뒤에 다음을 보내므로 그 창이 없어 안 고친다.

기준은 Task 0 ~ 5를 넣은 지금의 main 트리 파일(= `/tmp/run/tc2/new/`)이고, 편집 뒤는 `/tmp/run/tc2/new3/`다. 세 파일만 바뀐다 —
`net/check.sh` +23 −2, `firewall/check.sh` +5, `config/check.sh` +6.

### 5b-0. 기준을 본다

```bash
for f in net/check.sh firewall/check.sh config/check.sh; do cmp $f /tmp/run/tc2/new/$f && echo "BASE $f"; done
```

기대: `BASE` 셋. 다르면 멈추고 보고한다.

### 5b-1. `net/check.sh` — 편집 둘

P1 — `old_string`(지금 파일 989줄부터):

```bash
NW_LEASES_BEFORE="$(grep -ac 'eth0: leased 10\.0\.2\.15 ' "$LOG")"
echo "=== typing 'tars-config set net=off' and 'tars-config reload' ==="
type_keys t a r s minus c o n f i g spc s e t spc n e t equal o f f ret
type_keys t a r s minus c o n f i g spc r e l o a d ret
wait_for_screen '\| service dhcpcd: stops' \
  || fail "reload did not stop dhcpcd after net=off" "terminal: screen>" "tars-init: reload"
```

`new_string`:

```bash
#
# set의 답을 화면에서 본 뒤에 reload를 친다(TC-M2 Task 5b). M2의 첫 루트 게이트에서 이 검사가 셋 중 둘
# 빨갰고 그때 시리얼에는 `reload of` 뒤에 아무 줄이 없었다 — init이 파일을 다시 읽었는데 net이 아직
# dhcp였다는 뜻이다(reload design 덧붙임의 H1). set이 끝났다는 증거를 기다리면 그 창이 닫히고, 다시
# 빨개지면 아래 진단이 "set이 안 됐다"와 "reload가 안 됐다"를 한 판으로 가른다.
NW_LEASES_BEFORE="$(grep -ac 'eth0: leased 10\.0\.2\.15 ' "$LOG")"
# 실패하면 마지막 화면과 tars.conf의 되읽기를 찍는다. fail이 끝내기 전에 부른다.
nw_reload_diag() {
  echo "--- last screen before the diagnosis ---"
  joined_screen_dump | tail -n 1 | sed 's/ | /\n/g' | tail -n 25
  type_keys c a t spc slash c o n f i g slash t a r s dot c o n f ret
  sleep 3
  echo "--- after cat /config/tars.conf ---"
  joined_screen_dump | tail -n 1 | sed 's/ | /\n/g' | tail -n 8
  echo "--- tars-init lines after the last 'reload of' ---"
  awk '/tars-init: reload of/ { n = NR } END { print n + 0 }' "$LOG" | {
    read -r from; [ "$from" -gt 0 ] && tail -n +"$from" "$LOG" | grep -a 'tars-init:' | head -n 8; true; }
}
echo "=== typing 'tars-config set net=off' and 'tars-config reload' ==="
type_keys t a r s minus c o n f i g spc s e t spc n e t equal o f f ret
wait_for_screen '\| net: dhcp -> off' \
  || { nw_reload_diag; fail "tars-config set net=off never answered 'net: dhcp -> off'" "terminal: screen>"; }
type_keys t a r s minus c o n f i g spc r e l o a d ret
wait_for_screen '\| service dhcpcd: stops' \
  || { nw_reload_diag; fail "reload did not stop dhcpcd after net=off" "terminal: screen>" "tars-init: reload"; }
```

P2 — `old_string`(지금 파일 1003줄부터):

```bash
type_keys t a r s minus c o n f i g spc r e l o a d ret
wait_for_screen '\| service dhcpcd: starts' \
  || fail "reload did not start dhcpcd after net=dhcp" "terminal: screen>" "tars-init: reload"
```

`new_string`:

```bash
wait_for_screen '\| net: off -> dhcp' \
  || { nw_reload_diag; fail "tars-config set net=dhcp never answered 'net: off -> dhcp'" "terminal: screen>"; }
type_keys t a r s minus c o n f i g spc r e l o a d ret
wait_for_screen '\| service dhcpcd: starts' \
  || { nw_reload_diag; fail "reload did not start dhcpcd after net=dhcp" "terminal: screen>" "tars-init: reload"; }
```

### 5b-2. `firewall/check.sh` — 편집 둘

P1 — `old_string`(지금 파일 374줄부터):

```bash
type_keys t a r s minus c o n f i g spc s e t spc f i r e w a l l equal o f f ret
```

`new_string`:

```bash
type_keys t a r s minus c o n f i g spc s e t spc f i r e w a l l equal o f f ret
# set의 답을 본 뒤에 reload를 친다(TC-M2 Task 5b — net 검사 31의 간헐과 같은 모양을 막는다).
wait_for_screen "\\| firewall: on -> off" \
  || fail "tars-config set firewall=off never answered 'firewall: on -> off'" "terminal: screen>"
```

P2 — `old_string`(지금 파일 381줄부터):

```bash
type_keys t a r s minus c o n f i g spc s e t spc f i r e w a l l equal o n ret
```

`new_string`:

```bash
type_keys t a r s minus c o n f i g spc s e t spc f i r e w a l l equal o n ret
wait_for_screen "\\| firewall: off -> on" \
  || fail "tars-config set firewall=on never answered 'firewall: off -> on'" "terminal: screen>"
```

### 5b-3. `config/check.sh` — 편집 하나

P1 — `old_string`(지금 파일 563줄부터):

```bash
  type_keys "${TC_SET_KB_KEYS[@]}"
```

`new_string`:

```bash
  type_keys "${TC_SET_KB_KEYS[@]}"
  # set의 답을 본 뒤에 reload를 친다(TC-M2 Task 5b — net 검사 31의 간헐과 같은 모양을 막는다).
  if ! wait_for_screen '\| keyboard: apple -> pc$|\| keyboard: apple -> pc \|'; then
    echo "FAIL(boot 1): tars-config set keyboard=pc never answered 'keyboard: apple -> pc'"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
```

### 5b-4. 확인과 체인 셋

```bash
for f in net/check.sh firewall/check.sh config/check.sh; do cmp $f /tmp/run/tc2/new3/$f && echo "SAME $f"; bash -n $f || echo "SYNTAX $f"; done
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -v /tmp/run/tc2/impl:/impl -w /workspace tars-devcontainer bash -c '
  for c in net firewall config; do s=$(date +%s); bash $c/check.sh > /impl/p5b_$c.log 2>&1; echo "$c exit=$? $(( $(date +%s) - s ))s"; done'
rmdir /tmp/run/docker.lock
```

기대: `SAME` 셋, `SYNTAX` 없음, 셋 다 `exit=0`. 사본에서 net 186 · firewall 62 · config 176초였다.

진단이 쓸 만한지는 사본에서 한 번 봤다 — net 체인 사본의 `net=off`를 `net=ofx`로 바꿔 돌리면(`/tmp/run/tc2/mut5b/net_typo.sh`) set이 거절되고
첫 기다림에서 빨개지며 아래가 찍힌다. "set이 안 됐다"가 화면 · 파일 두 자리에서 바로 읽힌다(거절의 둘째 줄 `net takes off | dhcp`가 화면 줄
이음 ` | `과 겹쳐 두 줄로 보이는 것은 진단의 겉모양일 뿐이다). 구현자는 이것을 돌리지 않는다.

```
--- last screen before the diagnosis ---
⋮
root@(none) ~# tars-config set net=ofx
tars-config: net=ofx: init would say "unknown net 'ofx', falling back to off"
tars-config: net takes off
dhcp
tars-config: nothing was written
root@(none) ~ [1]#
--- after cat /config/tars.conf ---
⋮
root@(none) ~ [1]# cat /config/tars.conf
net=dhcp
root@(none) ~#
--- tars-init lines after the last 'reload of' ---
FAIL: tars-config set net=off never answered 'net: dhcp -> off'
```

보고는 Task 4의 보고와 같은 모양으로 — `git diff --stat`, 위 출력, plan과 다른 글자.

## design과 다르게 적은 것

design 본문은 결정 1과 결정 9 밑의 덧붙임(이 plan과 같은 날 같은 사람)으로 맞췄다 — `config` 답의 모양, 보기의 다음 줄, 체인의 자리와 순서. 구현 뒤에
lead가 고칠 것은 `Status:`와, 확정 5의 시간이 루트 게이트에서 다르면 실측 절이다.

## 이 milestone에서 안 하는 것

- `reload terminal` — 화면을 새 argv로 다시 띄우기(TC-M3).
- 서비스 파일의 내용이 바뀐 것을 보고 다시 띄우기(design 비목표 2 — `tars-service restart`).
- 떠 있는 wpa_supplicant의 재시작(비목표 6), 콘솔 셸을 다시 띄우는 동사(비목표 4), cmdline 다시 읽기(비목표 3).
- running-tars.md · lessons · 기억(서브프로젝트를 닫을 때 lead가).

## TC-M2가 실측한 것

lead가 2026-10-07에 쟀다. 구현자(Sonnet)의 보고와 파일을 lead가 직접 대조했다 — 열네 파일 전부 사본(`/tmp/run/tc2/new/`, Task 5b 뒤 세 체인은
`new3/`)과 `cmp`가 같았고, 지운 63줄은 plan이 말한 자리뿐이었다. 체인 아홉의 로그에 `Attempted to kill init` · `Kernel panic`은 0건이고,
`reload.zig`의 `unreachable` · `.?`는 머리 주석에만 있다.

1. 구현자의 체인. `zig build test` 초록(`reload_test:` 다섯 줄 — plan은 여섯이라 적었는데 묶음 3(대기)이 따로 줄을 안 찍는다, plan 문구의 오타).
   config 178초 · firewall 61초 · service 74초 · net 189초, regression 다섯(boot 25 · wifi 123 · power 50 · nic 32 · terminal 24초). mutation 여섯 전부
   plan의 표와 같은 자리에서 잡혔다 — m1(`config_off` 무시)은 wifi 부팅 C의 음성 `found 'started service wpa_supplicant' in a boot with no file and
   no radios`, m6(status가 끈 칸도 보임)은 DS-M2의 service 검사 17.
2. 루트 게이트 — 처음 둘이 빨갰다. 둘 다 TD-M2(net) run 1/2의 검사 31 `FAIL: reload did not stop dhcpcd after net=off`(30:49 · 30:42에 멈춤).
   시리얼에는 `tars-init: reload of /config/tars.conf`만 있고 그 뒤 `reload: service dhcpcd stop`이 없었다. net 체인 단독은 네 번 다 초록(planner ·
   구현자 · lead 둘), 그리고 `/tmp`를 호스트에 묶고 다시 돌린 루트 게이트는 21체인 2/2 전부 초록이었다 — 결정적이 아니라 간헐이다. planner의 가설
   셋(H1 `set`이 파일을 못 바꿨거나 늦었다 · H2 dhcpcd 칸의 `config_off`가 참 · H3 init이 섰다) 중 H1이 맞아 보이지만 실패 시점의 게스트 로그가
   없어 결정적 근거는 없다. 그래서 Task 5b — `set`의 답(`| net: dhcp -> off`)을 화면에서 본 뒤에 reload를 치고, 실패하면 마지막 화면 ·
   `cat /config/tars.conf` 되읽기 · `reload of` 뒤의 init 줄을 찍는다(firewall 19 · config 1차도 같은 기다림). planner가 `net=ofx`로 틀린 판을 돌려
   그 진단이 "set이 안 됐다"를 한 판으로 보여 주는 것을 확인했다.
3. 5b 뒤의 루트 게이트 두 번 — 58분 19초 · 58분 24초, 둘 다 21체인 `PASS: 2/2`, 빨간 줄 0, 기다림이 2초를 넘겨 `the screen took about`을 찍은
   자리 0. M1 때(56:36 · 56:42)보다 1분 40초쯤 늘었다 — planner가 본 "회차당 2분 남짓"(타이핑 config 110 · net 130 · firewall 180키) 안이다.
4. 크기. `init` 4,028,376바이트(M1 3,843,696 — reload · `Live` · 칸 열셋이 184KB), `tars-config` 3,690,128, initrd 98,113,899바이트.
5. 게이트가 본 M2 줄 — net `reload with net=off stopped dhcpcd and eth0 lost its address` · `reload with net=dhcp started dhcpcd again and it leased
   10.0.2.15, without a reboot`, firewall 검사 19(off · reload → 규칙 0줄, on · reload → drop), service 검사 28(sshd 링크를 지우고 reload → 멈춤 ·
   새 로그인 막힘, 다시 걸고 reload → 재부팅 없이 로그인), config 1차 `reload left keyboard=pc waiting for the screen, showed both values, and refused
   a file with shell=fsh`.
6. 건강한 net 시리얼의 reload 순서(`/tmp/run/tc2/lead_gate/tmp.lNhV2kx2UH`): `reload of` → `net=off, wifi stays off` → `net=off, leaving the network
   alone` → `reload: service dhcpcd stop` → 400줄 뒤 `service dhcpcd stopped on request`. 다시 켤 때 `reload: service dhcpcd start` → `started service
   dhcpcd (pid 591)`.
7. 이월 숙제 — chronyd의 reload(`ntp` 키)는 게이트가 안 본다(그 부팅에 ntp가 없다). 호스트 검사가 step 논리를 덮고 `clock.prepare`는 부팅이 같은
   꼴로 부른다. 간헐 실패의 진짜 원인은 다음에 검사 31이 빨개질 때 진단이 가른다.
