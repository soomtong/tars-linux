# TARS Config Reload — Design

Date: 2026-10-07
Status: 끝났다(2026-10-07, TC-M2 · M3). plan `docs/plans/2026-10-07-tars-config-reload-tc-m2.md` · `-tc-m3.md`의 실측 절이 값이다. 루트 게이트가
드러낸 간헐 셋(set의 답 · init 로그의 화면 dump 자름 · 프로브 둘째 줄)은 전부 게이트 쪽이었고 M2 5b · M3 5b · 5c가 고쳤다. 남은 자르개(`std.debug.print`의
64바이트 버퍼)는 TC 밖의 후속이다. 기억은 `docs/decisions/project_config_reload.md`.

TC design(`docs/specs/2026-10-06-tars-config-tool-design.md`)의 M2 절이 "따로 design을 쓴다"고 남긴 것이다.

> TC-M2 — `reload`. init이 재부팅 없이 `tars.conf`를 다시 읽는다. `init.sock`(CT의 SEQPACKET, 동사 넷)에 동사 하나를 더하는 일이지만,
> 다시 읽어서 무엇이 바뀌는지는 키마다 다르다 — `net` · `ntp` · `firewall`은 init이 서비스를 띄우고 멈추는 길이 있고(DS), `keyboard` ·
> 자판 · `clipboard`는 terminal의 argv라 terminal을 다시 띄워야 하고, `shell`은 떠 있는 셸을 죽일지의 문제다. … "지금 이 부팅이 쓰는 값"을
> 묻는 동사(결정 7)도 같은 자리다.

사용자가 M1 · M2를 승인했다(2026-10-06 — "M2도 너무 유용하게 사용할 수 있는 아이템이네").

## 한 줄 요약

`tars-config set net=dhcp` 뒤에 `tars-config reload`를 치면 init이 `tars.conf`를 다시 읽고, 바뀐 키 가운데 지금 바꿀 수 있는 것을
바꾸고(dhcpcd · chronyd · wpa_supplicant를 띄우거나 멈추고, 방화벽을 올리거나 내리고, 다음에 뜨는 셸의 셸 · env를 바꾼다), 바꾸려면
화면을 다시 띄워야 하는 것(자판 · 클립보드 · 화면의 셸)은 "대기 중"으로 남겨 `tars-config reload terminal`을 기다린다. 인자 없는
`tars-config`는 "다음 부팅이 읽을 값" 옆에 "지금 쓰는 값"을 보인다.

```
TC-M2   init.sock에 동사 둘(config · reload). init이 실효 설정과 대기를 들고 있다. reload가 바꾸는 것 — 서비스 셋 · 방화벽 · 콘솔 셸과
        ssh 세션의 셸 · env · 시간대. 화면 쪽은 대기로만 표시. tars-config의 보기가 두 칸이 되고 reload 동사가 는다
        게이트: net 체인(꺼짐 → 켬 → 주소), firewall 체인(켬 → 끔 → 열림), config 체인(대기 · 거절 · 두 칸)
TC-M3   reload terminal — terminal을 새 argv로 다시 띄운다(패널 · 셸 · 클립보드가 사라진다). config 체인이 자판 하나를 바꿔 본다
```

## 왜 따로인가

TC-M0 · M1은 파일을 쓰는 명령이었고 init은 한 줄도 안 바뀌었다(M0의 `log` 한 자리를 빼면). reload는 PID 1의 감독 루프에 상태를 더하는
일이다. init의 버그는 기계를 멈춘다 — 커널은 PID 1이 죽으면 패닉한다. 그래서 무엇이 바뀌는지를 키마다 따로 정하고, 순수한 쪽(무엇을 할지)을
호스트 검사로 다 덮은 뒤에야 시스템 콜 쪽을 짓는다.

그리고 열두 키가 init 안에서 닿는 자리가 열두 가지가 아니라 다섯이다(아래 모델). 그 다섯 자리마다 "지금 바꿀 수 있는가"의 답이 다르다.

## 모델

init이 부팅에 `tars.conf`를 읽어 정하는 것은 다섯 자리에 흩어진다. reload는 그 다섯을 다시 정하는 일이다.

| 자리 | 무엇 | 짓는 곳(main.zig) | 지금 바꿀 수 있나 |
|---|---|---|---|
| 1. 감독 목록의 데몬 셋 | wpa_supplicant · dhcpcd · chronyd를 넣을지, chronyd의 설정 파일 `/run/tars/chrony.conf` | `wifi.wants` · `net.wantsDhcpcd` · `clock.prepare`, `children[2..]` | 바꿀 수 있다 — 감독 루프가 이미 서비스를 띄우고 멈춘다(CT · DS) |
| 2. 방화벽 | `nft -f /etc/tars/firewall.nft`(실패하면 base) | `firewall.up` | 켜기는 그 함수 그대로. 끄기는 길이 없다 — 새로 `nft flush ruleset` |
| 3. 셸의 argv | 콘솔 셸의 경로 · rc 플래그 · 탈출로, terminal argv의 1 · 2 | `resolveShell` · `configFlag` · `children[0..2]` | 콘솔 셸은 다음에 뜰 때부터. terminal은 다시 띄워야 |
| 4. env와 로그인 | env 블록(`TZ` · 셸별 `HISTFILE`), `/etc/passwd`의 root 셸, `/etc/ssh/sshd_config.d/tars-env.conf` | `withTarsEnv` · `login.apply` | 바꿀 수 있다 — 다음에 뜨는 자식 · 다음 ssh 로그인부터 |
| 5. terminal의 argv | 키보드 · 키보드 장치 · 한글 · 영문 · 전환 키(+`esc_latin`) · 클립보드 | `children[0].argv[3..8]` | 다시 띄워야 — terminal은 argv를 시작할 때 한 번 읽는다 |

키 열둘이 그 자리에 닿는 모양이다.

| 키 | 자리 | reload(TC-M2)가 하는 것 | 화면(TC-M3) |
|---|---|---|---|
| `net` | 1 | 꺼짐 → dhcp: dhcpcd를 목록에 넣고 띄운다(방화벽이 켜져야 하면 그 뒤에). 무선 파일이 있으면 wpa_supplicant도. dhcp → 꺼짐: 둘을 멈추고 목록에서 뺀다(dhcpcd는 SIGTERM에 주소를 지우고 간다) | — |
| `ntp` | 1 | chrony.conf를 다시 쓰고 chronyd를 넣거나 · 다시 띄우거나 · 뺀다. `net=off`면 아무것도 안 한다(부팅과 같은 판정) | — |
| `firewall` | 2 | 꺼짐 → 켬: `firewall.up`(부팅의 함수 그대로). 켬 → 꺼짐: `nft flush ruleset` | — |
| `timezone` | 4 | env 블록의 `TZ`와 sshd의 SetEnv를 다시 짓는다. 이 뒤에 뜨는 자식부터 | 떠 있는 패널의 셸은 그대로(대기) |
| `shell` | 3 · 4 | 콘솔 셸의 argv · `/etc/passwd` · env의 `HISTFILE` · SetEnv. 떠 있는 콘솔 셸은 안 죽인다 — 다음에 뜰 때부터 | 대기 |
| `shell_config` | 3 | 콘솔 셸의 rc 플래그와 탈출로. 다음에 뜰 때부터 | 대기 |
| `keyboard` · `hangul_layout` · `latin_layout` · `hangul_toggle` · `esc_latin` · `clipboard` | 5 | 바꾸지 않는다. 대기로 적는다 | `reload terminal`이 새 argv로 다시 띄운다 |

## 결정

### 결정 1 — 동사 둘: `config`와 `reload`. 사람의 문은 `tars-config`

`init.sock`의 동사 넷(status · stop · start · restart, CT 결정 3)에 둘을 더한다. 요청의 모양(`동사` 또는 `동사 이름`, 64바이트)은 그대로다.

| 동사 | 답 |
|---|---|
| `config` | init이 지금 쓰는 실효값 열둘(`key=value` 줄, cmdline의 `tars.noconfig` · `resolveShell` · `resolveTimezone`의 폴백 뒤의 값)과 대기 중인 키(`pending terminal: keyboard hangul_layout` 한 줄) |
| `reload` | 키마다 한 줄 — `net: off -> dhcp (starting dhcpcd)` · `keyboard: apple -> pc (pending terminal)` · `shell: unchanged`. 거절이면 `error: …` 한 줄 |
| `reload terminal`(TC-M3) | 대기가 있으면 terminal을 새 argv로 다시 띄운다. 없으면 `nothing pending` |

사람이 치는 것은 `tars-config reload [terminal]`이다. `tars-service`가 아니라 `tars-config`인 이유는 설정을 다루는 문이 하나여야 해서다 —
`tars-config`는 `set` 뒤에 reload할지를 알고(결정 7), 보기에서 두 칸을 함께 보인다. `tars-config`가 `control.zig`의 `dial` · `awaitReply`를
쓴다(`tars-service`와 같은 클라이언트 쪽).

인자 없는 `tars-config`의 보기는 이렇게 된다. 왼쪽이 다음 부팅이 읽을 값(파일), 오른쪽이 지금 쓰는 값이다. 같으면 오른쪽을 비운다.

```
# /config/tars.conf on /dev/vda — left: the file (the next boot), right: what init uses now
shell=fish
keyboard=pc                     # now apple — pending terminal (tars-config reload terminal)
net=dhcp                        # now off — tars-config reload
```

| 후보 | 왜 아닌가 |
|---|---|
| (a) init.sock의 동사 둘, 문은 `tars-config` | 고른 것 |
| (b) SIGHUP으로 reload | 이 저장소의 PID 1은 SIGTERM · SIGINT만 받고 그 둘이 전원이다(PM). 시그널은 답을 못 돌려준다 — 무엇이 바뀌고 무엇이 대기인지를 사람이 못 본다 |
| (c) init이 `tars.conf`를 inotify로 지켜보고 저절로 | 사람이 반쯤 고친 파일을 init이 읽는다. 그리고 terminal을 다시 띄우는 일은 사람이 정해야 한다 |
| (d) 지금 쓰는 값을 파일(`/run/tars/config`)로 남기기 | 쓰는 쪽이 PID 1 하나라 소켓으로 묻는 것이 같은 일을 하고, 파일은 낡을 수 있다(reload 뒤 다시 써야 한다) |

> TC-M2 plan이 정한 것(2026-10-07, 코드를 사본에서 돌린 뒤). 위 글과 다른 셋.
>
> 1. `config`의 답은 열두 줄 `key=value`(init이 지금 쓰는 값) 뒤에, 화면이 대기 중이면 `screen keyboard=apple clipboard=shared` 한 줄이다 —
>    `pending terminal: …`이 아니라 화면이 지금 쓰는 값을 싣는다(`tars-config`가 그 값을 보여야 해서다). `reload`의 답은 바뀐 키마다
>    `keyboard: apple -> pc (the screen keeps the old value until the next boot)`, 데몬 · 서비스마다 `service dhcpcd: stops`, 방화벽은
>    `firewall: down (nft flush ruleset)`, 바뀐 것이 없으면 `nothing changed`, 거절이면 `error: /config/tars.conf: <init의 말>; nothing changed
>    (tars-config check)`다.
> 2. 보기의 "지금 값"은 같은 줄 끝이 아니라 그 줄 밑의 주석 한 줄이다 — `#   init uses net=off now; tars-config reload applies the line above`.
>    같은 줄 끝에 적으면 출력이 더는 그대로 쓸 수 있는 `tars.conf`가 아니다(TC 결정 8 — `parse`는 줄 끝 주석을 모른다). 화면의 대기는
>    `# the screen keeps keyboard=apple clipboard=shared until the next boot` 한 줄이다(M3 전이라 "다음 부팅"이다).
> 3. 게이트의 자리는 결정 9의 덧붙임.

### 결정 2 — 키를 넷으로 가른다: 지금 · 다음에 뜰 때부터 · 화면을 다시 띄워야 · 안 한다

모델 표의 셋째 · 넷째 칸이 이 결정이다. 원칙은 하나다 — reload는 떠 있는 사람의 것(셸 세션 · 패널 · 클립보드)을 죽이지 않는다. 죽여야만
바뀌는 것은 대기로 적고 사람이 따로 명시한다.

| 갈래 | 키 | 근거 |
|---|---|---|
| 지금 | `net` · `ntp` · `firewall` | 데몬과 커널 규칙은 사람의 세션이 아니다. CT가 이미 "서비스는 멈추고 다시 띄워도 된다"를 세웠다 |
| 다음에 뜰 때부터 | `shell` · `shell_config` · `timezone`(콘솔 셸 · ssh 로그인 · 이 뒤에 뜨는 서비스) | 떠 있는 콘솔 셸을 죽이면 사람이 치던 것이 사라진다. 다음 ssh 로그인 · 다음 콘솔 셸이 새 값을 받는 것으로 충분하다 |
| 화면을 다시 띄워야 | 자판 넷 · `esc_latin` · `clipboard` · `keyboard`, 그리고 화면 패널의 `shell` · `shell_config` · `timezone` | terminal이 argv를 시작할 때 한 번 읽는다(terminal을 고쳐 다시 읽게 하는 것은 비목표 1). 다시 띄우면 패널 · 셸 · 클립보드 · copy mode가 전부 사라진다 |
| 안 한다 | 없음 | 열둘 다 어느 갈래에 든다 |

화면을 다시 띄우는 것은 `tars-config reload terminal`이라는 명시 동사다(TC-M3). 묻지 않는다 — 묻는 명령은 게이트가 못 치고(TC 결정 12), 이
명령은 화면 안의 셸에서 친다. 그 셸이 그 명령으로 죽는다는 것을 출력이 먼저 말한다(`terminal restarts now; every pane and the clipboard go
away`). `--yes` 같은 플래그를 안 두는 이유는 동사 자체가 그 뜻이기 때문이다.

| 후보 | 왜 아닌가 |
|---|---|
| (a) 넷으로 가르고 화면은 명시 동사 | 고른 것 |
| (b) reload가 terminal까지 다시 띄운다 | `net=dhcp` 하나를 켜려다 패널이 전부 닫힌다 |
| (c) 콘솔 셸도 다시 띄운다(새 셸 · 새 TZ) | 콘솔 셸은 사람이 시리얼에서 치는 세션이다. 화면처럼 명시 동사로 열 수 있지만 그 필요를 아직 못 봤다(비목표 4) |
| (d) terminal이 init.sock을 들어 argv 대신 설정을 다시 받는다 | terminal에 새 입력과 상태 전환(자판을 조합 중에 바꾸기)을 짓는 일이다. 그만한 값은 "자판을 바꾸고 화면을 다시 띄우지 않기"인데, 자판은 드물게 바꾼다 |

### 결정 3 — 원자성: init의 파서가 한 마디라도 하면 아무것도 안 바꾼다. 바뀐 키만 건드린다

reload는 `config.load`로 파일을 읽고, `parse`가 불평한 줄이 하나라도 있으면 거절한다(`error: line 7: unknown shell 'fsh', falling back to fish`).
부팅은 그런 파일도 받는다(틀린 줄은 기본값) — 부팅이 설정 하나로 막히면 안 되기 때문이다(CP). reload는 다르다. 사람이 그 자리에서 고칠 수
있고, 틀린 줄을 기본값으로 바꿔 적용하면 "고쳤는데 꺼졌다"가 된다.

불평을 세는 길은 TC-M0이 이미 깔았다 — `config.zig`의 `log`가 root의 `configLog`를 찾는다. `main.zig`가 `configLog`를 선언해 지금과 같은
바이트(`tars-init: ` + 글 + 개행)를 찍으면서 수를 센다. 부팅의 로그는 한 바이트도 안 바뀐다.

그다음 지금 쓰는 실효값(init이 들고 있는 `cfg`)과 새 값을 키마다 비교한다. 같은 키는 손대지 않는다 — `tars-config set clipboard=pane`
뒤의 reload가 dhcpcd를 다시 띄우지 않는다.

순서는 "조이는 것 먼저, 푸는 것 나중"이다. FW 결정 5의 불변식("규칙이 서기 전에 주소가 붙는 틈이 없다")을 reload에서도 지킨다.

```
1. firewall off -> on        nft -f (부팅의 firewall.up)          조인다 — 주소를 받기 전에
2. net / wifi / ntp          데몬을 넣고 · 다시 띄우고 · 뺀다       목표만 정하고 감독 루프가 한다
3. shell · shell_config      콘솔 셸 argv · passwd                 다음에 뜰 때부터
4. timezone · shell          env 블록 · SetEnv 다시 짓기            다음에 뜨는 자식부터
5. firewall on -> off        nft flush ruleset                    푼다 — 데몬을 멈춘 뒤에
6. 화면 키                    대기로 적는다
```

`firewall.up`이 실패하면(사람의 `.nft`가 틀렸다) 부팅과 같이 base 규칙으로 떨어진다 — 닫힌 쪽이다. 그때 2단계의 `net` 켜기는 그대로
간다(부팅도 그렇다). 답에 그 사실을 적는다.

### 결정 4 — 감독 루프를 막지 않는다

`feedback_boot_never_blocks`의 뜻을 reload에 옮기면 "reload가 PID 1을 세우지 않는다"다. reload 안에서 PID 1이 기다리는 것은 둘뿐이다.

| 기다리는 것 | 얼마나 | 왜 괜찮은가 |
|---|---|---|
| `tars.conf` 읽기 | 4096바이트 한 번 | 부팅과 같다. `/config`는 로컬 ext2 |
| `nft -f` · `nft flush ruleset` | nft 한 번(로컬 netlink) | 부팅이 이미 같은 것을 기다린다(`firewall.up`, FW design 확인 3). 네트워크를 안 쓴다 |

데몬을 띄우고 멈추는 것은 reload가 하지 않는다. reload는 목표(`config_off` · `hold`)만 바꾸고 답을 보내고, 실제 fork · kill · 거두기는
감독 루프의 다음 바퀴가 한다 — CT의 stop · start가 이미 그 모양이다(SIGTERM 뒤 3초 SIGKILL, `kill_at`). 그래서 reload의 답은 "starting
dhcpcd"처럼 시작했다는 것까지이고, 떴는지는 `tars-service status`가 본다.

| 후보 | 왜 아닌가 |
|---|---|
| (a) 위 둘만 기다리고 나머지는 루프에 맡긴다 | 고른 것 |
| (b) nft도 일꾼으로(fork하고 안 기다리고 거둘 때 결과를 읽는다, AU의 `audio.zig`처럼) | 순서(결정 3의 1 → 2)가 그 일꾼의 끝을 기다려야 해서 reload가 여러 바퀴에 걸친 상태 기계가 된다. 부팅이 같은 nft를 기다리므로 얻는 것이 없다 |
| (c) reload 전체를 자식 프로세스에서 | 감독 목록 · env · argv는 PID 1의 메모리다. 자식이 바꿀 수 없다 |

### 결정 5 — init이 실효 설정을 들고 있다. 데몬 셋의 자리는 늘 있다

지금 `main()`의 `cfg` · argv 버퍼 · env 버퍼는 `main()`의 스택에 살고 `supervise()`는 `children`과 `envp`만 받는다. reload는 셋 다 바꿔야
한다. `supervise()`에 상태 하나(`Live` — 실효 `Config`, 대기 키 집합, argv에 들어가는 글자 버퍼, env 블록 두 벌과 지금 쓰는 쪽)를 넘긴다.
env 블록이 두 벌인 이유는 reload가 새 블록을 다 지은 뒤에 포인터 하나로 갈아 끼우기 위해서다 — 짓는 도중에 fork하는 자식은 없지만(한
스레드), 짓다 실패하면 옛 블록이 그대로 남아야 한다.

데몬 셋(wpa_supplicant · dhcpcd · chronyd)의 자리를 부팅이 정하지 않는다. 지금은 `want_*`가 참일 때만 `children`에 넣고 그 길이의 slice를
`supervise()`에 넘긴다 — `net=off`로 뜬 기계에는 dhcpcd의 자리가 아예 없어서 reload가 넣을 곳이 없다. 셋의 자리를 늘 두고 `Child`에 칸
하나(`config_off: bool` — 설정이 끈 것)를 더한다.

| 칸 | 누가 세우나 | 뜻 |
|---|---|---|
| `hold`(CT) | `tars-service stop` · `restart` | 사람이 이 부팅에서 멈췄다. 다음 부팅은 모른다 |
| `config_off`(새) | 부팅 · reload | 설정이 이 데몬을 안 원한다. `wantsRunning`이 거짓이고 `status`에 안 나온다 · `start`가 `error: … is off in tars.conf`로 거절한다 |

`status`가 `config_off`인 자리를 안 보이는 것이 지금의 출력(서비스 체인 · running-tars.md의 표)을 한 줄도 안 바꾸는 길이다. `children`의
크기는 이미 `2 + RESERVED.len + MAX`(13)로 셋의 자리를 갖고 있다 — 바뀌는 것은 slice의 길이와 순서(셋이 언제나 2 ~ 4번)다.

### 결정 6 — 두 reload, 반쯤 적용된 상태

init.sock의 요청은 감독 루프가 한 번에 하나씩 받는다(`serveControl`). 그래서 init 안에서 reload 둘이 겹치는 일은 없다. 겹칠 수 있는 것은
"reload가 목표를 바꾼 뒤 그 목표에 아직 안 닿은 것"(dhcpcd가 SIGTERM을 받고 아직 안 죽었다)이고, 둘째 reload는 지금 목표에 대해 diff한다 —
CT의 `hold`가 이미 그렇게 겹친다(stop 중의 start).

반쯤 적용되는 자리는 결정 3의 순서에서 하나뿐이다 — 1단계의 nft가 base로 떨어지는 것. 그 밖의 단계는 메모리의 값을 바꾸는 것이라
실패가 없다(쓰는 파일 셋 — chrony.conf · passwd · tars-env.conf — 은 부팅의 함수 그대로이고 실패하면 로그 한 줄이고 진행한다. 부팅과 같다).
답의 줄마다 그 키의 결과가 있어서 사람은 무엇이 됐는지 안다.

### 결정 7 — `tars-config`가 무엇을 하나

| 명령 | 하는 것 |
|---|---|
| `tars-config` | 결정 1의 두 칸. init에 못 닿으면(소켓 없음) 왼쪽만 보이고 한 줄로 그 사실을 말한다 |
| `tars-config set …` | 지금처럼 파일만 쓴다. 마지막 줄이 "reboot to apply"에서 `tars-config reload`로 바뀐다(대기가 될 키면 `tars-config reload terminal`까지) |
| `tars-config reload` | init의 답을 그대로 찍는다. 종료 코드 0 · 1(거절) · 2(init에 못 닿음) |
| `tars-config reload terminal` | 대기가 있으면 출력이 먼저 "패널이 사라진다"를 말하고 요청한다(TC-M3) |

`set`이 reload를 스스로 하지 않는다. 사람이 여러 키를 고친 뒤 한 번 적용하는 것이 결정 3의 순서를 한 번에 태우는 길이고, 파일만 고치는 일
(다음 부팅을 위해)도 남아야 한다.

### 결정 8 — 순수한 쪽: `reload.zig`

PID 1의 코드라서 무엇을 할지를 정하는 것은 전부 시스템 콜이 없는 `init/src/reload.zig`에 두고 `reload_test`(호스트)가 본다 — 키 열둘의 diff,
갈래, 결정 3의 순서, 답의 글자, 대기 집합, `config` 동사의 답. `main.zig`는 그 계획을 받아 실행만 한다(nft · argv 포인터 · env 갈아 끼우기 ·
`config_off`). `control.zig`가 감독 규칙을 `anytype`으로 가짜 구조체에 대 보는 것과 같은 모양이다.

ReleaseSafe의 init에서 정수 넘침 · 범위 밖 인덱스는 패닉이고 PID 1의 패닉은 커널 패닉이다. 그래서 그 둘이 날 수 있는 셈(버퍼의 길이 · 슬롯
번호)은 `reload.zig`에 두고 호스트 검사가 경계값까지 본다.

### 결정 9 — 게이트는 체인 셋에 하나씩

| 체인 | 무엇 | 판정 |
|---|---|---|
| `net` | `net=off`로 뜬 부팅에서 `tars-config set net=dhcp ntp=…`과 `reload` | dhcpcd가 뜨고 lease, chronyd가 뜬다, `tars-service status`에 둘. 거꾸로 `net=off` · `reload` — 주소가 빠지고 둘이 `status`에서 사라진다 |
| `firewall` | `firewall=on`으로 뜬 부팅에서 `set firewall=off`와 `reload` | 닫혀 있던 포트로 바이트가 온다(`nft flush ruleset`). 그리고 다시 `on` — 닫힌다 |
| `config` | 1차(fish)에서 `set keyboard=pc` · `reload` · 보기 | 답이 `pending terminal`이고 보기의 오른쪽이 `now apple`. 틀린 줄을 심은 파일의 reload가 거절되고 아무것도 안 바뀐다. `set clipboard=pane`만의 reload가 dhcpcd를 안 건드린다(diff) |
| `config`(TC-M3) | `reload terminal` | 새 `started terminal` 줄과 terminal의 `hangul layout=… keyboard=pc` 줄 |

음성이 반을 차지하는 이유는 reload의 위험이 "안 바뀌어야 할 것이 바뀌는 것"이기 때문이다. 어느 체인이 어느 부팅에 얹을지와 포트는 plan이
정한다.

> TC-M2 plan이 정한 것. 새 부팅 · 새 포트는 없다 — 넷 다 이미 있는 부팅의 끝에 타이핑(또는 ssh)으로 붙는다.
>
> | 체인 | 자리 | 판정 |
> |---|---|---|
> | `net` | 첫 부팅(net=dhcp)의 끝, 검사 31 — 위 표의 반대 순서다. 그 부팅은 이미 dhcp라 `net=off` · reload를 먼저 치고 다시 `dhcp` · reload | `service dhcpcd: stops` · 주소가 빠짐(`nw0`) · `service dhcpcd: starts` · 이 부팅의 둘째 lease와 둘째 `started service dhcpcd`. chronyd는 이 부팅에 ntp가 없어 안 본다 |
> | `firewall` | 부팅 A의 끝, 검사 19 | 포트의 바이트가 아니라 규칙의 수다 — `nft list ruleset | wc -l`이 0(`fwn0`), 다시 켜면 drop이 선다(`fwp…`). 7072의 리스너는 검사 18이 이미 썼다 |
> | `config` | 1차의 `list` 뒤 | `keyboard: apple -> pc (the screen keeps …)` · dhcpcd를 안 건드림 · 보기의 `# the screen keeps keyboard=apple clipboard=shared …` · `shell=fsh`를 심은 파일의 reload가 `error: …; nothing changed` |
> | `service` | 부팅 D의 끝, 검사 28(결정 11) | `ssh off` · reload → `service sshd: stops` · 새 로그인 막힘, `ssh on` · reload → `service sshd: starts` · 새 로그인, 나머지 셋의 줄 없음 · 멈춘 stubborn은 그대로 |

### 결정 10 — 구현은 서브에이전트가, 검증 · 게이트 · commit은 lead가

TC 결정 11과 같다. 이 design의 milestone은 PID 1을 고치는 첫 일이라 plan은 Opus가 쓰고, 구현자 모델은 plan이 정한다 — 붙여 넣기만 하는
일이면 Sonnet, plan을 넘는 판단(감독 루프의 순서)이 남으면 Opus.

### 결정 11 — reload는 `services.d`도 다시 읽는다(lead 검토 뒤 올렸다)

lead가 비목표 2를 "비용을 재서 정하라"고 돌려보냈다(2026-10-07) — M1의 앞문 넷 가운데 `tars-config ssh on`만 재부팅이 남으면 사용자가
바란 경험과 어긋난다. 재 보니 유한하다. 새 상태도 새 상태 기계도 없다.

| 무엇 | 이미 있는 것 | 더하는 것 |
|---|---|---|
| 다시 읽기 | `services.discover`(이름순 · 여덟까지 · 실행 비트 · 숨긴 이름) — 부팅의 그 함수 | 없다. reload가 한 번 더 부른다 |
| 칸 | 서비스 칸 여덟(`children[5..13)`, 결정 5가 늘 두기로 한 자리) | 없다 |
| 멈추기 · 되살리기 | CT의 `control.apply(.stop | .start)`와 결정 5의 `config_off` | 없다 |
| 칸의 글자 | 지금은 `main()`의 `service_list` | `Live.services`(여덟 칸 × 경로 128 + 라벨 40바이트) — 결정 5의 `Live`에 한 칸 |
| 판정 | — | `reload.serviceActions` — 칸 여덟과 새 이름(최대 여덟)을 견줘 `stop` · `revive` · `add` · `no_room` |

규칙은 넷이다. 이미 있는 이름의 칸은 안 건드린다(사람이 `tars-service stop`한 것은 멈춘 그대로). 사라진 이름은 `config_off`로 멈춘다.
다시 나타난 이름은 그 칸을 되살린다. 새 이름은 빈 칸에 넣는다 — 빈 칸은 한 번도 안 쓴 칸이거나, 꺼졌고 이미 거둬진 칸이다. 멈추는
중인 칸(꺼졌지만 살아 있다)은 빈 칸이 아니다 — 거두기 전에 넘기면 그 pid가 새 서비스의 것이 된다. 칸이 없으면(여덟이 다 차고
멈추는 중이 남았다) 그 이름은 다음 부팅이고 답이 그렇게 말한다.

그래서 `tars-config ssh on`(M1)의 끝 줄이 "reboot"이 아니라 `tars-config reload`를 가리킨다. 같은 까닭으로 M1의 `tars-config wifi`가 처음
만든 무선 파일도 reload가 띄운다 — 무선의 판정(`wifi.wants`)은 키가 안 바뀌어도 reload마다 다시 묻는다(파일이 있는지는 키가 아니다).
이미 떠 있는 wpa_supplicant의 재시작은 여전히 `tars-service restart wpa_supplicant`다(비목표 6).

## lead의 전제를 바로잡은 것

1. "init은 설정을 부팅에 한 번만 읽고 어디에도 안 남긴다" — 한 번 읽는 것은 맞다. 남기는 자리는 있다 — 시리얼의 `tars-init: config …` 한 줄,
   그리고 설정에서 지은 것 넷(`/run/tars/chrony.conf` · `/etc/passwd`의 root 셸 · `/etc/ssh/sshd_config.d/tars-env.conf` · env 블록). reload는
   `cfg`만 바꾸면 안 되고 이 넷을 다시 지어야 한다(모델의 자리 1 · 4). 실효값은 `main()`의 스택에 있다 — 소켓으로 물을 길이 없을 뿐이다.
2. "dhcpcd · chronyd는 Kind.service라 stop/start 길이 있다" — 부팅에 원했을 때만이다. `net=off`로 뜨면 `children`에 그 자리가 없고 `supervise()`가
   받는 slice의 길이가 고정이라 넣을 곳이 없다(결정 5). 그리고 `tars-service stop`의 `hold`는 "사람이 이 부팅에서 멈췄다"라서 "설정이 껐다"로
   쓰면 `tars-service start dhcpcd`가 꺼 둔 것을 되살린다 — 칸 하나(`config_off`)가 더 든다. chronyd는 설정 파일(`/run/tars/chrony.conf`, `ntp`의
   서버)을 다시 써야 하고, `net`이 바뀌면 wpa_supplicant(`wifi.wants`)도 함께 바뀐다.
3. "방화벽은 상태가 없어 nft -f 한 번이다" — 켜기는 맞다(`firewall.up`). 끄기는 init에 길이 없다 — `up(.off)`는 로그 한 줄로 돌아온다. 끄려면
   `nft flush ruleset`이 새로 든다. 그리고 nft는 PID 1이 기다린다(`wait4`) — 부팅이 받아들인 기다림이라 reload도 받는다(결정 4).
4. "terminal은 argv 아홉 자리로 값을 받고 재시작하면 패널이 다 사라진다" — 아홉은 argv[0](경로)까지 센 것이고 값은 여덟이다. 그 가운데 1 · 2가
   셸과 rc 플래그라 `shell` · `shell_config`도 화면에서는 terminal 키다(패널이 셸을 띄울 때 그 argv를 쓴다). 4번은 키보드 장치 경로로 설정이
   아니다(부팅에 capability로 찾는다). 패널이 사라지는 것은 맞다 — 패널의 셸은 terminal이 죽어 PTY가 닫히면 SIGHUP을 받는다(SL).
5. "셸은 env(TZ 등)를 exec 때 받는다" — 맞다. 하나를 더하면, 그 env 블록을 init이 부팅에 한 번 짓고(`environ.withTarsEnv`, `main()`의 스택)
   셸별 `HISTFILE`이 그 안에 있다 — `shell`이 바뀌면 `timezone`과 같이 블록을 다시 지어야 한다. ssh 세션의 env는 이 블록이 아니라 sshd의
   SetEnv 파일에서 온다(SV 결정 9).

## 검증

이 design의 수는 소스에서 센 것이다(착수 전에 실측한 것). 코드 실측 · 체인 시간 · mutation은 milestone의 plan이 TC-M1이 들어간 트리의 사본에서
잰다. plan이 볼 것 — 부팅의 로그가 한 바이트도 안 바뀐다(`config_test`의 `tars-init:` 줄 · 체인 전부), 데몬 셋의 자리를 늘 둔 뒤 `tars-service
status`의 출력이 그대로다(service 체인), reload 전후의 감독 루프가 1초 바퀴를 지킨다(`nft`의 시간).

## Milestone

### TC-M2 — init의 reload와 `config`, `tars-config`의 두 칸

결정 1 ~ 9 · 11(화면 쪽은 대기 표시까지). 고칠 것 — `init/src/main.zig`(상태 `Live` · 데몬 셋의 자리 · `answer`의 동사 둘 · `configLog`),
`control.zig`(동사 둘 · `config_off`), 새 `reload.zig` · `reload_test.zig`, `firewall.zig`(`down` — `nft flush ruleset`), `config_cli.zig`
(보기의 두 칸 · `reload` 동사 · `set`의 끝 줄), 체인 셋. 정할 것 — `Live`의 버퍼 크기, `config` 답의 정확한 글자, 체인의 자리와 포트.

### TC-M3 — `reload terminal`

terminal을 새 argv로 다시 띄운다. terminal의 `Child`에 SIGTERM을 보내고(CT의 `hold = .restart`와 같은 길 — 요청한 죽음은 빨리 죽음으로 안 센다)
argv의 글자를 새 버퍼로 바꿔 두면 감독 루프가 다시 띄운다. 정할 것 — 콘솔 셸도 같은 동사로 다시 띄울지(비목표 4), terminal의 탈출로(rc 플래그)
상태를 새 argv에서 어떻게 잇는지. M2와 나눈 이유는 사람의 것을 죽이는 유일한 길이라서다 — M2만으로 `net` · `firewall` · `ntp`(이 기능을 원한
자리)가 다 된다.

> TC-M3 plan이 정한 것(2026-10-07, `docs/plans/2026-10-07-tars-config-reload-tc-m3.md`).
>
> 1. `reload terminal`은 대기가 없으면 아무것도 안 한다(`nothing pending; the screen already uses what init uses`). 있으면 대기 키를
>    `key: 화면의 값 -> init의 값`으로 찍고, terminal argv의 1 · 2 · 3 · 5 · 6 · 7 · 8을 init이 지금 쓰는 값으로 바꾼 뒤(4번 키보드 장치는
>    설정이 아니라 그대로), `control.apply(.restart)`로 hold를 세우고 SIGTERM을 보낸다. 대기가 빈다(`screen = cfg`). 파일은 다시 안 읽는다 —
>    `reload`가 읽은 것을 화면에 준다.
> 2. SIGTERM은 그룹이 아니라 terminal의 pid다. terminal은 setsid를 안 해서 제 그룹이 없다. CT-M1 결정 4 규칙 3의 SIGKILL 시한(`overdue`)이
>    `kill(-pid)`로 모든 자식을 돌던 것을 서비스만 그룹, 나머지는 pid로 고쳤다 — 그 전에는 비서비스에 시한이 선 적이 없어 드러나지 않았다
>    (plan 확정 2).
> 3. 탈출로는 부팅의 판정(`storage_mounted and shell_config == on`)으로 다시 선다. 이미 한 번 쓴 탈출로도 다시 선다.
> 4. 콘솔 셸은 같은 동사로 안 다룬다(비목표 4). M2의 reload가 콘솔 셸 칸의 argv를 이미 바꿔 두므로 그 셸이 끝나면 새 셸로 뜬다 — config
>    체인 1차가 `kill -9 $(pgrep -t ttyS0)`로 그것을 본다.
> 5. `tars-config reload terminal`은 먼저 `config`로 대기를 묻고, 있으면 "the screen restarts now — every pane, its shell and the clipboard go
>    away"를 먼저 찍고 보낸다. M2의 문구 둘(`reload` 키 줄의 꼬리 · 보기의 screen 줄)의 "until the next boot"가 "until tars-config reload
>    terminal"이 됐다.

## 위험

1. PID 1의 버그는 기계를 멈춘다. ReleaseSafe의 패닉이 커널 패닉이다. 처방은 결정 8 — 셈은 순수한 쪽에, 호스트 검사가 경계까지. 그리고 reload는
   사람이 칠 때만 돈다 — 부팅의 길은 지금과 같은 코드를 지난다(결정 3의 `configLog`가 부팅에 하는 일은 수를 세는 것뿐이다).
2. 데몬 셋의 자리를 늘 두는 것이 감독 루프의 첫 바퀴를 바꾼다. `config_off`인 자리는 `wantsRunning`이 거짓이라 안 뜬다 — 그 판정이 틀리면
   `net=off` 부팅에서 dhcpcd가 뜬다. 모든 체인이 그것을 본다(`net=off` 부팅이 대부분이다).
3. `nft flush ruleset`은 init이 올린 것 말고도 지운다 — 사람이 `nft`로 손수 올린 규칙. 이 기계에서 규칙을 올리는 것은 init과 사람(`nft -f`)이고
   `firewall=off`가 "거르지 않는다"는 뜻이라 맞는 동작으로 본다. 답에 적는다.
4. 대기가 오래 남는다. `keyboard=pc`를 reload하고 `reload terminal`을 안 치면 화면은 apple이고 파일은 pc다. 보기의 오른쪽이 그 상태를 늘 보인다.
   다음 부팅이 그 대기를 푼다.
5. `shell`이 바뀐 뒤의 콘솔 셸. 떠 있는 콘솔 셸은 옛 셸이고 히스토리도 옛 파일에 쓴다. 그 셸이 죽어 다시 뜰 때 새 셸 · 새 `HISTFILE`이다.
6. reload 뒤의 탈출로. `shell_config=on`으로 바꾸면 콘솔 셸의 탈출로(rc 없이 한 번 더)가 다시 서야 한다 — `rescue`를 부팅의 판정(`storage_mounted
   and shell_config == on`)으로 다시 정한다. 이미 한 번 쓴 탈출로를 되살릴지는 plan이 정한다.

## 비목표

1. terminal이 argv 대신 설정을 다시 받는 것(결정 2의 (d)).
2. (결정 11로 올렸다 — `services.d` 다시 읽기는 reload가 한다.) 남는 비목표는 서비스 파일의 내용이 바뀐 것을 보고 다시 띄우는 것이다 —
   이름이 같으면 안 건드린다. 그것은 `tars-service restart`다.
3. 커널 cmdline(`tars.noconfig`)의 다시 읽기. 부팅의 것이 이 부팅 내내 이긴다.
4. 콘솔 셸을 다시 띄우는 동사.
5. 설정 디스크가 늦게 붙은 경우의 reload(디스크 없이 뜬 부팅에서 디스크를 꽂고 reload). 그 부팅의 `/config`는 마운트가 아니라 tmpfs다 —
   reload는 "설정 디스크가 없다"로 거절한다.
6. 무선의 망을 더한 뒤 떠 있는 wpa_supplicant의 재시작을 reload가 대신 하는 것(파일이 처음 생긴 것은 결정 11대로 reload가 띄운다). TC-M1의 `tars-config wifi`가 말하는 `tars-service restart wpa_supplicant`가
   그대로다(`net`이 바뀌지 않는 한 reload는 wpa_supplicant를 안 건드린다).

## 착수 전에 실측한 것

소스(HEAD `5d58520` — TC-M0 + TC-M1 plan)와 앞 서브프로젝트의 기록으로 쟀다. 코드를 돌린 측정은 없다.

1. `main.zig`에 `cfg.`가 나오는 곳이 스물여덟이다(로그 한 줄의 인자 열둘과 주석 하나 포함). 닿는 자리를 묶으면 이렇다 — cmdline의 덮기, 로그 한 줄, `resolveShell` · `resolveTimezone`, env 블록,
   `login.apply`, `firewall.up`, `wantsDhcpcd` · `wifi.wants` · `clock.prepare`, `configFlag` · `console_flag` · `rescue_flag`, terminal argv의
   다섯(`keyboard` · `hangul` · `latin` · 전환 키 · `clipboard`). `supervise()`가 받는 것은 `children` · 버튼 fd · 제어 fd · `envp` 넷이고 `cfg`는 없다.
2. `children`의 크기는 `2 + services.RESERVED.len + services.MAX` = 2 + 3 + 8 = 13이다. `supervise()`가 받는 slice는 `children[0 .. n + service_list.len]`이고
   `n`은 2 + (wpa · dhcpcd · chronyd 중 원한 수)다.
3. `Child.argv`는 `[9:null]`이다. terminal은 0 경로 · 1 셸 · 2 rc 플래그 · 3 키보드 · 4 키보드 장치 · 5 한글 · 6 영문 · 7 전환 키(+`esc_latin`) ·
   8 클립보드. 콘솔 셸은 0 · 1만 쓴다. 글자는 `main()`의 스택 버퍼(`toggle_buf` · `terminal_toggle_buf` · `keyboard_path`)와 상수를 가리킨다.
4. env 블록은 `environ.Block` = `[16:null]`(MAX_ENTRIES 16) 하나이고 `main()`의 `env_buf`에 산다. TZ 항목은 `tz_buf`(80바이트)다.
5. `firewall.up(.off)`는 `firewall=off, inbound is open` 한 줄로 돌아온다 — 규칙을 내리는 코드가 저장소에 없다. `load`는 `fork` · `execve` ·
   `wait4`로 nft를 기다린다.
6. `control.Verb`는 `status · stop · start · restart`이고 요청은 64바이트(`REQUEST_MAX`), 답은 2048바이트(`REPLY_MAX`)다. 열두 키의 `key=value`가
   가장 길 때 300바이트 남짓이라 `config`의 답이 들어간다. `tars-service`는 답을 2초(`REPLY_WAIT_MS`) 기다린다.
7. 감독 루프는 한 바퀴에 `power.take` → `audio.follow` → 띄우기 → SIGKILL 시한 → 거두기 → `poll`(1초)이고 제어 요청은 poll이 깨운 뒤
   `serveControl`이 하나를 끝까지 처리한다(붙잡히는 상한 `WAIT_MS` 200ms + 처리).
8. dhcpcd는 SIGTERM에 주소를 지우고 간다(running-tars.md "서비스를 멈추고 다시 띄우기" — restart에 주소가 약 6초 빠진다).
9. terminal의 패널 셸은 terminal이 죽으면 PTY가 닫혀 SIGHUP을 받는다(`config.zig`의 `HIST_OPTIONS_ZSH` 주석 · SL design).

## 닫을 때(lead의 몫)

- 이 design의 `Status:`. TC design의 `Status:`와 M2 절에 이 design을 가리키는 한 줄.
- `CLAUDE.md` 완료 표 — TC를 닫을 때 한 줄로(M0 ~ M3).
- `docs/decisions/project_config_reload.md`와 `MEMORY.md` 한 줄 — 담을 것: 키의 네 갈래, `config_off`와 `hold`의 차이, 조이고 푸는 순서.
- lessons의 PID 1 쪽 핵심 파일에 `reload.zig`, `main.zig` 항목에 `Live`.
- running-tars.md — "네트워크와 시계" 절의 "재부팅" 줄들이 `tars-config reload`로.
- `HANDOFF.md`.

## 관련

- `docs/specs/2026-10-06-tars-config-tool-design.md` — 결정 7(다음 부팅부터) · M2 절 · 결정 14(방화벽만 그 자리에서 nft)
- `docs/specs/2026-09-27-tars-service-control-design.md` · `docs/decisions/project_service_control.md` — init.sock · `hold` · 요청한 죽음
- `docs/decisions/project_daemon_supervision.md` — dhcpcd · chronyd가 감독 목록에 든 것
- `docs/decisions/project_firewall.md` — 규칙이 주소보다 먼저(FW 결정 5)
- `docs/decisions/feedback_boot_never_blocks.md` — reload도 PID 1을 세우지 않는다(결정 4)
- `docs/decisions/project_shutdown_signals.md` · `project_shutdown_latency.md` — 패널 셸의 SIGHUP
