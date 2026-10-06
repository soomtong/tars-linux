# TC-M1 — `tars-config`가 무선 · ssh · 방화벽 · 받아쓰기의 파일에 사람이 처음 적는 줄을 써 준다

Date: 2026-10-07
Design: `docs/specs/2026-10-06-tars-config-tool-design.md`(결정 12 ~ 17)
Status: 끝났다(2026-10-07). 구현은 Sonnet 서브에이전트가 Task 0 ~ 4를 글자 그대로 넣었고(plan 코드를 고친 곳 0), 루트 게이트 21체인 2/2가 두 번 초록이다. 값은 맨 아래 "TC-M1이 실측한 것".

## 누가 무엇을 하나

design 결정 11. Task 0 ~ 4는 구현 서브에이전트가 main 작업 트리에서 직접 편집하고 돌린다. Task 5(루트 게이트 2회 · 실측 절 · design
덧붙임 · commit)는 lead(Fable)가 한다. 구현자는 commit하지 않고, 끝에 `git diff --stat` · `git diff | rg '^-'` · 각 Task의 명령 출력을
그대로 보고한다. 이 plan의 "확정한 것" 절과 "실측한 것" 절은 구현자가 고치지 않는다.

권하는 모델은 Sonnet이다. 근거 셋.

- Zig 새 파일 셋(`config_front.zig` 639줄 · `config_front_edit.zig` 241줄 · `config_front_edit_test.zig` 164줄)은 구현자가 짓지 않는다. 사본에서
  컴파일 · 호스트 검사 · 체인 다섯 · mutation을 지난 파일을 `cp -p`한다. M0(Zig 세 파일 1,000줄 남짓)도 Sonnet이 같은 방식으로 넣었고 plan
  코드를 고친 곳이 없었다.
- 고치는 파일 여덟의 편집 스물일곱은 `old_string` · `new_string`이다. `config_cli.zig`의 열넷 중 아홉은 낱말 `pub` 하나씩이다. 각 Task 끝의
  `cmp`가 사본과 바이트까지 같은지를 본다.
- Opus로 올릴 이유는 하나다. 루트 게이트에서 이 plan이 안 돌린 체인이 빨개져 원인을 찾아야 할 때. 이 milestone은 `init` 바이너리를 안
  바꾸고(`tars-config`만 바뀐다) 체인 넷의 게스트 쪽 스크립트를 바꾸므로, 빨개질 만한 것은 그 넷과 `config`이고 전부 여기서 돌렸다.

이 plan의 코드는 저장소 밖 사본(`/tmp/run/tc1/repo/`)에 먼저 넣어 돌렸고, 아래의 새 파일 본문과 `old_string` · `new_string`은 그 사본에서
기계로 뽑은 것이다(`/tmp/run/tc1/render.py`). 기준은 HEAD `8671f56`(TC-M0)의 파일(`/tmp/run/tc1/base/`)이고 편집 뒤의 파일은
`/tmp/run/tc1/new/`다. 새 파일은 `new/`에서 `cp -p`하고, 편집은 Edit 도구에 글자 그대로 넣고(또는 plan 본문에서 블록을 기계로 뽑아 넣고),
각 Task 끝에서 `new/`와 `cmp`한다. 다르면 편집이 빗나간 것이니 plan의 글자에 맞춰 고친다. plan의 글자와 `new/`가 서로 다르다고 보이면
고치지 말고 그 자리를 보고한다. 편집은 한 파일 안에서 E1부터 차례로 넣는다.

| 파일 | 무엇을 | 줄 |
|---|---|---|
| `init/src/config_front_edit.zig` | 새 파일 — 앞문 넷의 글자 쪽(포트 · 규칙 한 줄 · wpa 덩어리 · 키 몸통 · 받아쓰기 키 여덟) | +241 |
| `init/src/config_front.zig` | 새 파일 — 앞문 넷의 시스템 콜 쪽(동사 다섯 · 남의 도구 부르기 · 비밀 읽기 · `check` 다섯) | +639 |
| `init/src/config_front_edit_test.zig` | 새 파일 — 호스트 검사(묶음 넷) | +164 |
| `init/src/config_cli.zig` | 편집 열넷 — 도우미 열하나에 `pub`, `config_front` import, USAGE의 둘째 묶음, `list`의 끝 줄, `check`가 앞문을 부른다, `main`의 동사 다섯 | +33 −15 |
| `init/build.zig` | 편집 둘 — `config_front_edit_test` | +14 |
| `dictation/probe.sh` | 편집 하나 — s21 뒤에 갈래 s22(`tars-config dictation key` · `set` · 거절) | +10 |
| `dictation/check.sh` | 편집 셋 — 표식 둘, 검사 12의 요청 수 19 → 20, 검사 30 | +27 −4 |
| `service/check.sh` | 편집 하나 — 부팅 D 끝에 검사 27(`ssh-key` · `ssh`) | +34 |
| `firewall/check.sh` | 편집 하나 — 부팅 A 끝에 검사 18(`firewall allow 7072`) | +12 |
| `wifi/ap.sh` | 편집 둘 — 머리 주석, 부팅 B(`ap-only`)의 2b(`tars-config wifi`로 고치고 재시작) | +19 −1 |
| `wifi/check.sh` | 편집 셋 — 머리 주석, 검사 9의 음성을 고친 줄 앞으로, 검사 12 | +22 −2 |

`git diff --stat`은 8 files, +171 −22이고(새 파일 셋은 밖), `git add -N` 뒤에는 11 files다. 커널 · Dockerfile · `make_initrd.sh` ·
`guest_tools.sh`는 안 바뀐다 — 부르는 도구 셋(`wpa_passphrase` · `ssh-keygen` · `nft`)은 이미 게스트에 있다. `init` 바이너리도 안 바뀐다
(`config.zig`를 안 고친다). `check.sh`(루트)도 그대로다 — 새 체인이 없다.

design의 `Status:` · `CLAUDE.md` · `MEMORY.md` · `docs/decisions/` · `docs/guides/` · `HANDOFF.md`는 구현자가 안 고친다.

모든 명령은 저장소 루트에서 친다. 서브에이전트의 Bash는 호출마다 작업 디렉터리가 돌아가므로 명령 앞에
`cd /Users/dp/Repository/tars-linux &&`를 붙인다. 빌드 · 체인은 언제나 컨테이너에서 한다. 구현자의 측정용 파일은
`/tmp/run/tc1/impl/` 아래에 둔다. `/tmp/run/tc1/` 바로 아래는 이 plan을 쓰며 만든 것이고 대조에 쓴다. 지우지 않는다.

Docker VM의 메모리가 4GB다. 컨테이너는 언제나 하나씩 돌린다. 모든 `docker run`을 아래로 감싼다. 명령이 실패해도 lock은 꼭 푼다.
`run_in_background`로 돌리는 명령이 lock을 기다리게 두지 않는다 — 그 명령은 lock을 잡은 채 끝까지 돈다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run … ; rc=$?
rmdir /tmp/run/docker.lock
```

20분 넘게 기다리면 `docker ps`를 보고, 컨테이너가 하나도 없으면 lock이 낡은 것이니 `rmdir`하고 진행한다.

## 이 milestone이 끝나면

- `tars-config wifi 'SSID'`가 비밀번호를 echo 없이 묻고, `wpa_passphrase`가 지은 덩어리를 `/config/wpa_supplicant.conf`에 둔다 — 같은 SSID의
  덩어리가 있으면 그것을 바꾸고, 평문 `#psk` 줄은 버리고, 파일은 0600이다. `--country KR`이 `country=` 줄을 둔다. 파일이 있었으면
  `tars-service restart wpa_supplicant`, 처음이면 재부팅을 말한다.
- `tars-config ssh on|off`가 `services.d/sshd` 템플릿 링크를 걸고 지운다. `tars-config ssh-key add 'ssh-ed25519 …'`(또는 `< id.pub`)가
  `ssh-keygen`으로 읽어 본 키를 지문과 함께 `authorized_keys`(0700 · 0600)에 더한다. 같은 키는 두 번 안 넣는다.
- `tars-config firewall allow 22`(· `deny` · `5353/udp`)가 `nftables.d/tars-config.nft`에 한 줄을 넣고 빼며, `firewall=on`이면 그 자리에서
  `nft -f /etc/tars/firewall.nft`를 돈다. 사람이 쓴 다른 `.nft`는 안 건드린다.
- `tars-config dictation key`가 Groq 키를 echo 없이 묻고 `groq.key`(0600)에, `tars-config dictation set language=ko …`가 `dictation.conf`의
  그 키의 줄 하나를 쓴다. 이름 여덟 밖은 거절한다.
- 인자 없이 치면 그 표면의 지금 상태가 보인다. `tars-config check`가 그 파일들의 다섯 가지(design 결정 16)를 더 본다. `help`가 그 동사들을
  보이고 `list`의 끝에 한 줄이 그리로 가리킨다.

출력(정본 — `config_front.zig`가 찍는다. 체인이 이 글자를 본다). 표준 출력이다.

```
wifi: tars-wl replaced in /config/wpa_supplicant.conf
wifi: home added in /config/wpa_supplicant.conf (with country)
apply now: tars-service restart wpa_supplicant
init starts wpa_supplicant only when this file is there at boot; reboot (kill -INT 1)
net=off: wifi needs the network on — tars-config set net=dhcp

sshd: on — /config/services.d/sshd -> /etc/tars/services/sshd; init starts it at the next boot (kill -INT 1)
sshd: off from the next boot; to stop it now: tars-service stop sshd
sshd: already on
ssh-key: added 256 SHA256:… sv-bad (ED25519)
ssh-key: already there — 256 SHA256:… sv-bad (ED25519)
sshd reads /config/ssh/authorized_keys at every login — no restart
firewall=on: port 22 is open only if a file in /config/nftables.d says so; tars-config firewall allow 22

firewall: opened tcp dport 7072 accept
applied now: nft -f /etc/tars/firewall.nft
firewall=off: nothing is filtered now; the rule counts once firewall=on (tars-config set firewall=on, reboot)

dictation: wrote /config/groq.key (0600, 7 characters)
dictation: transcribe_url=http://10.0.2.100:8080/fail/s22
tars-dictate reads /config/dictation.conf at every run — no restart; it warns about a value it does not take
```

표준 에러(`tars-config: `로 시작한다).

```
tars-config: wpa_passphrase refused (exit 1): <wpa_passphrase의 말>                       exit 1
tars-config: ssh-keygen does not read this as a public key: (stdin) is not a public key file.   exit 1
tars-config: unknown dictation key 'colour'; the keys are in tars-dictate -h            exit 1
tars-config: nft -f /etc/tars/firewall.nft refused (exit 1); the rules that were up stay up   exit 1
tars-config: a port is 1 to 65535, optionally /tcp or /udp (tcp is the default)        exit 64
tars-config: nothing was written
```

## 착수 전에 확정한 것

2026-10-07에 이 plan을 쓰며 저장소 사본(`/tmp/run/tc1/repo/`, TC-M0의 열 파일이 든 트리 = HEAD `8671f56`)과 이미지 `tars-devcontainer`로 쟀다.
측정 파일은 `/tmp/run/tc1/meas/`(빌드 · 체인 로그)와 `/tmp/run/tc1/mut/`(mutation)에 있다. 저장소의 작업 트리는 design과 이 plan 말고는 한
글자도 안 바뀌었다. 사본의 컨테이너는 lead의 루트 게이트(TC-M0 2회차)가 lock을 푼 뒤에만 돌렸다.

1. 파일 가름(design 결정 13). `config_front.zig`가 시스템 콜 쪽이고 `config_cli.zig`의 도우미(`say` · `complain` · `failed` · `writeAll` ·
   `usage` · `Read` · `readFile` · `configDisk` · `parsed` · `CONF_PATH` · `READ_MAX` · `EXIT_*`)를 `pub`로 받아 쓴다. 두 파일이 서로 import한다
   (root가 `config_cli.zig`다). 남의 도구를 부르는 `run`은 `install.zig`의 `runTool`과 같은 모양(fork · execve · wait4)에 출력을 돌려주는 것
   하나가 다르다. 비밀을 읽는 `readSecret`은 표준 입력이 tty면 `tcgetattr` · `tcsetattr`로 ECHO를 끄고 한 줄, 아니면 끝까지 읽는다.
   `tars-config`는 3,414,368 → 3,667,792바이트다.

2. 컴파일에서 고친 것 둘 — 0.16의 `linux.W.TERMSIG`가 enum을 돌려줘 `@intFromEnum`이 든다. multiline 문자열 리터럴이 탭을 거부해서(M0의
   gitconfig와 같은 벽) 검사의 wpa 덩어리를 `"\t…\n" ++` 줄로 적었다.

3. `config_front_edit_test`(호스트, `zig build test`의 열넷째). 묶음 넷이 각각 한 줄을 찍고 끝에 `PASS`.

   | 묶음 | 본다 |
   |---|---|
   | 1 | 포트 넷을 받고 열하나를 거절, 규칙 한 줄 둘, 더하기 · 찾기(앞부분이 같은 포트는 안 걸린다) · 빼기(공백 · 끝 개행 없음), 규칙 수 |
   | 2 | wpa 덩어리 — 주석과 `#psk`를 버린다, 오류 문구 · 안 닫힌 덩어리는 null, 사람의 파일에서 같은 SSID 덩어리만 바꾸고 다른 망 · 주석 · `country`는 그대로, 주석 속 SSID는 안 걸리고 끝에 더한다, `country`는 맨 앞 · 바꾸기 · 덩어리 안은 안 본다 |
   | 3 | 키 몸통(`AAAA…`) — 옵션 뒤에서도 찾고, 설명이 달라도 같은 키다, 짧은 토막은 몸통이 아니다 |
   | 4 | API 키(공백 · 제어 문자 거절), 받아쓰기 키 여덟이 `kernel/dictation/tars-dictate`의 `case $key in`에서 읽은 이름과 같다 |

   묶음 4는 tars-dictate 파일을 런타임에 읽는다(`../kernel/dictation/tars-dictate` — `zig build test`가 `init/`에서 돈다. `@embedFile`은 모듈
   뿌리 밖을 못 읽는다).

4. 체인 넷의 자리(design 결정 17). 덧붙이는 검사의 번호는 각 체인의 마지막 번호 뒤다.

   | 체인 | 검사 | 사본 |
   |---|---|---|
   | `dictation` 부팅 A | 프로브 s22 · 검사 30 · 검사 12의 수 19 → 20 | 158초 |
   | `service` 부팅 D | 검사 27 | 74초 |
   | `firewall` 부팅 A | 검사 18(타이핑 31키) | 53초 |
   | `wifi` 부팅 B | 프로브 2b · 검사 9의 음성 범위 · 검사 12 | 121초 |

   - dictation. 키는 `printf 'tc1-key\n' | tars-config dictation key`(표준 입력이 파이프라 끝까지 읽는다), 설정은
     `tars-config dictation set "transcribe_url=${STUB}/fail/s22" max_seconds=1` — s21이 남긴 파일의 그 두 키 줄만 바뀐다. `/fail`(429)이라
     기록(`dictation.jsonl`)에 한 줄도 안 더한다 — 검사 13의 열여섯이 그대로다. stub의 `POST /fail/s22 auth=[Bearer tc1-key]`가 판정이다.
   - service. 부팅 D의 ssh 제어 연결 위로 친다. 검사 14가 거절된 것을 본 `bad` 키를 더하면 그 키로 곧바로 로그인된다 — sshd가 로그인마다
     `authorized_keys`를 읽는다. 키 아닌 줄(`ssh-ed25519 not-a-key tc1`)은 `ssh-keygen -l -f -`가 거절하고 그 말이 이유다. 끝의 `ssh off` · `on`은
     부팅 D의 마지막이라 그 뒤의 판정에 안 닿는다.
   - firewall. 검사 8 · 11이 닫혀 있음을 본 7072를 연다. 그 리스너(`nc -l`)는 검사 11이 본 대로 아직 아무와도 안 이어졌으므로 바이트가 오는 것이
     "그 한 줄이 섰다"다. 부팅 B는 다른 디스크라 영향이 없다.
   - wifi. 부팅 B의 디스크는 손대지 않는다(사람의 모양 그대로 `country=KR` + 평문 `psk="wrong-secret"`). 프로브가 `wpa_cli list_networks`의
     `TEMP-DISABLED`(틀린 키로 쉬는 중)를 본 뒤 `printf 'tars-secret\n' | tars-config wifi tars-wl`과 `tars-service restart wpa_supplicant`를 친다.
     검사 9의 음성(`CTRL-EVENT-CONNECTED` · `wlan0: leased`가 없다)은 `wifi-ap: tc [` 줄 앞의 로그로만 본다.

5. 시간. 체인 다섯을 한 컨테이너에서 차례로 돌린 것이 dictation 158 · service 74 · firewall 53 · wifi 121 · config 169초였다(데운 판). 루트
   게이트에서 늘어나는 것은 firewall의 타이핑 31키(10초 안팎)와 wifi 부팅 B의 재연결(20초 안팎)이다.

6. regression. `config` 체인을 돌렸다(169초, 초록) — `config_cli.zig`의 `list` 끝 줄 · `check`가 앞문을 부르는 것이 1차의 `list` · `check` 판정을
   안 흔든다. `tools`는 안 돌렸다 — initrd에 든 것의 목록이 그대로다(`tars-config`의 바이트만 바뀐다).

7. mutation. 다섯 가지를 여섯(되돌림 포함) 판으로 돌렸다(`/tmp/run/tc1/make_mut.py` · `run_mut.sh`, 로그는 `/tmp/run/tc1/mut/`).

   | mutation | 판 · 체인 | `mounted:` | 잡은 자리 | `FAIL` 줄 | 시간 |
   |---|---|---|---|---|---|
   | 1 무선: 같은 SSID의 덩어리를 못 찾는다(늘 끝에 더한다) | `m1` · wifi | `0beb185c f94c91fc` | 검사 12 | `FAIL: tars-config wifi did not replace the tars-wl block and point at a restart` | 104초 |
   | 2 ssh 키: `ssh-keygen`의 판정을 안 본다 | `m2` · service | `87cf8fe7 6ea5154e` | 검사 27 | `FAIL: a line that is not a key gave rc 0 (ssh-key: added (stdin) is not a public key file.` | 84초 |
   | 3 방화벽: 쓰기만 하고 `nft`를 안 돈다 | `m3` · firewall | `3f6bcd19 6ea5154e` | 검사 18 | `FAIL: tars-config firewall allow 7072 did not apply the rules` | 63초 |
   | 4 받아쓰기: `set`이 파일을 안 갈아 끼운다 | `m4` · dictation | `ac61ba33 6ea5154e` | 검사 29(검사 30보다 앞) | `FAIL: the cleanup stub got 11 request(s), want 10` | 66초 |
   | 5 받아쓰기 키 하나가 tars-dictate와 어긋난다(`cleanup_timeout` → `cleanup_wait`) | `m5` · service | `0beb185c ab033860` | `config_front_edit_test` 묶음 4(부팅 전) | `FAIL: tars-dictate knows 'cleanup_timeout', DICTATION_KEYS does not` · `FAIL: init host tests failed` | 15초 |
   | (되돌림) | `back` · firewall | `0beb185c 6ea5154e` | — | 마지막 줄 `FW chain PASS` | 62초 |

   읽을 것 셋.
   - `m2`는 가짜 키 줄을 그대로 썼다 — 그 줄은 몸통 모양(`AAAA…`)을 갖춘 가짜라 거절할 수 있는 것이 `ssh-keygen`뿐이다. 첫 판의 가짜(`not-a-key`)는 몸통이
     없어서 이 명령의 다른 갈래가 반쯤 받쳤고, 그래서 검사 27의 가짜를 지금 모양으로 바꿨다(service 체인 다시 74초 초록). 망가진 판이 지문 자리에 찍은
     `(stdin) is not a public key file.`이 `ssh-keygen`의 말이다.
   - `m4`는 검사 30보다 앞의 검사 29가 잡았다. `set`이 안 쓰이면 s22가 s21의 설정 그대로 돈다 — 전사 주소가 `/ok/s21`, 정리 주소가 `/chat/wait/s21`이라 정리
     stub이 하나를 더 받는다. 어느 쪽이든 "다음 tars-dictate가 이 명령이 쓴 것을 안 읽었다"다.
   - `m5`는 부팅 전에 잡힌다. service 체인이 `zig build test`를 부팅 앞에 돈다(dictation 체인은 안 돈다 — 그래서 이 판을 service에 얹었다).
     첫 판에서 `m1` · `m3`을 `if (false)` · `if (true)`로 짓다가 `m1`이 컴파일되지 않았다(쓰이지 않게 된 `want`) — 둘 다 런타임 조건으로 바꿔 다시 돌린
     것이 위 표다.

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
   for f in init/src/config_cli.zig init/build.zig dictation/probe.sh dictation/check.sh service/check.sh firewall/check.sh wifi/ap.sh wifi/check.sh; do
     cmp $f /tmp/run/tc1/base/$f && echo "BASE $f"; done
   ls init/src/config_front.zig init/src/config_front_edit.zig init/src/config_front_edit_test.zig 2>&1
   ls kernel/build/.tars-build-stamp kernel/build/arch/x86/boot/bzImage
   ```

   기대: `8671f56`(TC-M0)이 있고 그 위에 lead의 commit(HANDOFF · design · 이 plan)이 있을 수 있다. `BASE` 여덟. 새 파일 셋은 `No such file`.
   커널 스탬프와 bzImage가 있다. 하나라도 다르면 멈추고 보고한다.

## Task 1: `init/` — 새 파일 셋 · `config_cli.zig` · `build.zig`

design 결정 12 ~ 16 · 확정 1 ~ 3.

### 1-1. 새 파일 셋

```bash
for f in config_front_edit.zig config_front.zig config_front_edit_test.zig; do cp -p /tmp/run/tc1/new/init/src/$f init/src/$f; done
```

본문은 아래와 같다(읽기용 — 넣는 것은 위 `cp`다).

`init/src/config_front_edit.zig`:

```zig
//! TC-M1. `tars-config`의 앞문 넷(wifi · ssh · firewall · dictation)이 쓰는 글자의 일
//! (TC design 결정 12 ~ 15).
//!
//! 시스템 콜이 하나도 없다 — `config_front_edit_test.zig`가 호스트에서 전부 본다. 파일을
//! 열고 쓰고 남의 도구(`wpa_passphrase` · `ssh-keygen` · `nft`)를 부르는 것은
//! `config_front.zig`다. M0의 `config_edit.zig` ↔ `config_cli.zig`와 같은 가름이다.
//!
//! 여기서 남의 문법을 파싱하지 않는다(결정 10). 하는 일은 셋뿐이다 — 우리가 짓는 한 줄
//! (`tcp dport 22 accept`)을 짓고 찾는 것, 남의 도구가 낸 덩어리를 그대로 옮기는 것, 그
//! 덩어리를 같은 이름의 덩어리와 바꿔 끼울 자리를 찾는 것.
const std = @import("std");

// ── 방화벽 ────────────────────────────────────────────────────────────

pub const Proto = enum { tcp, udp };

pub const PortSpec = struct { port: u16, proto: Proto };

/// `22` · `5353/udp` · `8080/tcp`. 포트는 1 ~ 65535, 앞의 0은 안 받는다.
pub fn parsePort(text: []const u8) ?PortSpec {
    var it = std.mem.splitScalar(u8, text, '/');
    const num = it.next() orelse return null;
    const proto_text = it.next();
    if (it.next() != null) return null;
    if (num.len == 0 or num.len > 5 or num[0] == '0') return null;
    var v: u32 = 0;
    for (num) |c| {
        if (c < '0' or c > '9') return null;
        v = v * 10 + (c - '0');
    }
    if (v == 0 or v > 65535) return null;
    const proto: Proto = if (proto_text) |p| (std.meta.stringToEnum(Proto, p) orelse return null) else .tcp;
    return .{ .port = @intCast(v), .proto = proto };
}

/// 이 명령이 쓰는 nft 한 줄. 사람이 `nftables.d`에 손으로 적는 모양과 같다(FW design 결정 3) —
/// `firewall.nft`의 `chain input` 안으로 include된다.
pub fn ruleLine(buf: []u8, spec: PortSpec) []const u8 {
    return std.fmt.bufPrint(buf, "{s} dport {d} accept", .{ @tagName(spec.proto), spec.port }) catch unreachable;
}

/// text에 그 줄이 있는가(양 끝 공백을 떼고 글자 그대로).
pub fn hasLine(text: []const u8, line: []const u8) bool {
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw| if (std.mem.eql(u8, std.mem.trim(u8, raw, " \t\r"), line)) return true;
    return false;
}

/// 끝에 한 줄을 더한다. 끝에 개행이 없던 글자면 개행을 먼저. 넘치면 null.
pub fn appendLine(out: []u8, text: []const u8, line: []const u8) ?[]const u8 {
    const sep: []const u8 = if (text.len > 0 and text[text.len - 1] != '\n') "\n" else "";
    return std.fmt.bufPrint(out, "{s}{s}{s}\n", .{ text, sep, line }) catch null;
}

/// 그 줄(양 끝 공백을 뗀 글자가 같은 줄)을 전부 뺀다. 다른 줄은 바이트 하나 안 바뀐다.
pub fn removeLine(out: []u8, text: []const u8, line: []const u8) ?[]const u8 {
    var len: usize = 0;
    var start: usize = 0;
    while (start < text.len) {
        const end = std.mem.indexOfScalarPos(u8, text, start, '\n') orelse text.len;
        const next = if (end < text.len) end + 1 else end;
        if (!std.mem.eql(u8, std.mem.trim(u8, text[start..end], " \t\r"), line)) {
            const piece = text[start..next];
            if (len + piece.len > out.len) return null;
            @memcpy(out[len..][0..piece.len], piece);
            len += piece.len;
        }
        start = next;
    }
    return out[0..len];
}

/// 이 명령이 쓰는 nft 파일의 머리. 사람이 그 파일을 열었을 때 누가 쓰는지를 안다.
pub const RULES_HEADER =
    \\# Written by tars-config firewall allow|deny (TC design 결정 14). Your own rules go in
    \\# another file in this directory; this one is rewritten by that command.
    \\
;

// ── 무선 ──────────────────────────────────────────────────────────────

/// `wpa_passphrase`의 출력에서 `network={ … }` 덩어리만 남긴다(결정 12).
///
/// 버리는 것은 `#`로 시작하는 줄 — `# reading passphrase from stdin`과 평문 비밀번호
/// `#psk="…"`다. 남기는 것의 모양을 본다: 첫 줄이 `network={`, 마지막 줄이 `}`. 그 밖의
/// 모양이면 null — `wpa_passphrase`가 바뀐 것이고 그때는 쓰지 않는다.
pub fn networkBlock(out: []u8, output: []const u8) ?[]const u8 {
    var len: usize = 0;
    var first = true;
    var last: []const u8 = "";
    var it = std.mem.splitScalar(u8, output, '\n');
    while (it.next()) |raw| {
        const t = std.mem.trim(u8, raw, " \t\r");
        if (t.len == 0 or t[0] == '#') continue;
        if (first and !std.mem.eql(u8, t, "network={")) return null;
        first = false;
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (len + line.len + 1 > out.len) return null;
        @memcpy(out[len..][0..line.len], line);
        out[len + line.len] = '\n';
        len += line.len + 1;
        last = t;
    }
    if (first or !std.mem.eql(u8, last, "}")) return null;
    return out[0..len];
}

/// 덩어리의 `ssid=…` 줄(양 끝 공백을 뗀 글자). 같은 망의 옛 덩어리를 이 글자로 찾는다.
pub fn ssidLine(block: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, block, '\n');
    while (it.next()) |raw| {
        const t = std.mem.trim(u8, raw, " \t\r");
        if (std.mem.startsWith(u8, t, "ssid=")) return t;
    }
    return null;
}

pub const Placed = struct { text: []const u8, replaced: bool };

/// conf에서 `ssid` 줄이 같은 첫 `network={ … }` 덩어리를 block으로 바꾼다. 없으면 끝에 더한다.
///
/// 덩어리의 경계는 줄 둘이다 — 양 끝 공백을 뗀 글자가 `network={`인 줄과 그 뒤 처음 나오는
/// `}`인 줄. `wpa_passphrase`가 내는 모양이고 running-tars.md가 사람에게 시킨 모양이다. 그
/// 밖의 모양(한 줄에 쓴 덩어리 등)은 못 찾고, 그때는 더한다 — 지우는 쪽으로 틀리지 않는다.
pub fn placeNetwork(out: []u8, conf: []const u8, block: []const u8) ?Placed {
    const want = ssidLine(block) orelse return null;
    var start: usize = 0;
    var block_start: ?usize = null;
    var matched = false;
    while (start < conf.len) {
        const end = std.mem.indexOfScalarPos(u8, conf, start, '\n') orelse conf.len;
        const next = if (end < conf.len) end + 1 else end;
        const t = std.mem.trim(u8, conf[start..end], " \t\r");
        if (block_start == null) {
            if (std.mem.eql(u8, t, "network={")) {
                block_start = start;
                matched = false;
            }
        } else if (std.mem.eql(u8, t, "}")) {
            if (matched) {
                const text = std.fmt.bufPrint(out, "{s}{s}{s}", .{ conf[0..block_start.?], block, conf[next..] }) catch return null;
                return .{ .text = text, .replaced = true };
            }
            block_start = null;
        } else if (std.mem.eql(u8, t, want)) {
            matched = true;
        }
        start = next;
    }
    const sep: []const u8 = if (conf.len > 0 and conf[conf.len - 1] != '\n') "\n" else "";
    const text = std.fmt.bufPrint(out, "{s}{s}{s}", .{ conf, sep, block }) catch return null;
    return .{ .text = text, .replaced = false };
}

/// 나라 코드. 대문자 둘(`KR`)만 받는다 — 규제 도메인의 이름이 그 모양이다.
pub fn countryOk(cc: []const u8) bool {
    return cc.len == 2 and std.ascii.isUpper(cc[0]) and std.ascii.isUpper(cc[1]);
}

/// 맨 앞의 `country=` 줄을 바꾸거나, 없으면 맨 앞에 더한다. `network={` 안은 안 본다.
pub fn setCountry(out: []u8, conf: []const u8, cc: []const u8) ?[]const u8 {
    var start: usize = 0;
    var depth: usize = 0;
    while (start < conf.len) {
        const end = std.mem.indexOfScalarPos(u8, conf, start, '\n') orelse conf.len;
        const next = if (end < conf.len) end + 1 else end;
        const t = std.mem.trim(u8, conf[start..end], " \t\r");
        if (std.mem.eql(u8, t, "network={")) depth += 1;
        if (depth > 0 and std.mem.eql(u8, t, "}")) depth -= 1;
        if (depth == 0 and std.mem.startsWith(u8, t, "country=")) {
            return std.fmt.bufPrint(out, "{s}country={s}{s}", .{ conf[0..start], cc, conf[end..] }) catch null;
        }
        start = next;
    }
    return std.fmt.bufPrint(out, "country={s}\n{s}", .{ cc, conf }) catch null;
}

// ── ssh ───────────────────────────────────────────────────────────────

/// 공개 키 한 줄의 몸통(base64). 키 줄은 `[옵션] 형식 몸통 [설명]`이고 몸통은 늘 `AAAA`로
/// 시작한다(길이 4바이트 + 형식 이름의 base64). 같은 키를 두 번 더하지 않는 데 쓴다.
pub fn keyBody(line: []const u8) ?[]const u8 {
    var it = std.mem.tokenizeAny(u8, line, " \t\r");
    while (it.next()) |tok| if (std.mem.startsWith(u8, tok, "AAAA") and tok.len >= 16) return tok;
    return null;
}

/// authorized_keys의 줄 가운데 몸통이 같은 것이 있는가.
pub fn hasKey(keys: []const u8, body: []const u8) bool {
    var it = std.mem.splitScalar(u8, keys, '\n');
    while (it.next()) |raw| {
        const t = std.mem.trim(u8, raw, " \t\r");
        if (t.len == 0 or t[0] == '#') continue;
        if (keyBody(t)) |b| if (std.mem.eql(u8, b, body)) return true;
    }
    return false;
}

/// 빈 줄 · 주석을 뺀 줄의 수. authorized_keys의 키 수와 이 명령의 nft 파일의 규칙 수를 센다.
pub fn keyCount(keys: []const u8) usize {
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, keys, '\n');
    while (it.next()) |raw| {
        const t = std.mem.trim(u8, raw, " \t\r");
        if (t.len != 0 and t[0] != '#') n += 1;
    }
    return n;
}

// ── 받아쓰기 ──────────────────────────────────────────────────────────

/// `/config/dictation.conf`의 키 여덟(VD design 결정 3). 그 파일의 파서는
/// `kernel/dictation/tars-dictate`(bash)이고 이 목록은 그 `case`의 이름과 같아야 한다 —
/// 이 명령은 이름만 알고 값은 거르지 않는다(결정 15). 이름이 어긋나면 `set`이 쓴 줄을
/// tars-dictate가 "unknown key"로 버린다. `config_front_edit_test`가 그 파일에서 이름을
/// 읽어 이 목록과 견준다.
pub const DICTATION_KEYS = [_][]const u8{
    "transcribe_url", "transcribe_model", "language",        "max_seconds",
    "cleanup",        "cleanup_url",      "cleanup_model",   "cleanup_timeout",
};

pub fn isDictationKey(key: []const u8) bool {
    for (DICTATION_KEYS) |k| if (std.mem.eql(u8, k, key)) return true;
    return false;
}

/// API 키 한 줄. 앞뒤 공백 · 개행을 뗀다. 비었거나 그 안에 공백 · 제어 문자가 있으면 null —
/// 그 글자는 키가 아니고, 개행 하나면 파일이 두 줄이 된다. 글자의 종류를 더 좁히는 것은
/// tars-dictate의 몫이다(결정 15).
pub fn apiKey(text: []const u8) ?[]const u8 {
    const t = std.mem.trim(u8, text, " \t\r\n");
    if (t.len == 0) return null;
    for (t) |b| if (b <= 0x20 or b == 0x7f) return null;
    return t;
}

/// `KEY=VALUE`의 값에 제어 문자가 있는가(개행 하나면 줄이 둘이 된다).
pub fn hasControl(text: []const u8) bool {
    for (text) |b| if (b < 0x20 or b == 0x7f) return true;
    return false;
}
```

`init/src/config_front.zig`:

```zig
//! TC-M1. `tars-config`의 앞문 넷 — 남의 문법 파일에 사람이 처음 적는 한 줄을 이 명령이
//! 써 준다(TC design 결정 12 ~ 16).
//!
//!   wifi SSID [--country CC]   /config/wpa_supplicant.conf — wpa_passphrase가 짓는 덩어리
//!   ssh [on|off]               /config/services.d/sshd — 템플릿으로 가는 링크
//!   ssh-key add [KEY] | list   /config/ssh/authorized_keys — ssh-keygen이 읽어 본 한 줄
//!   firewall [allow|deny P]    /config/nftables.d/tars-config.nft — 이 명령만 쓰는 파일
//!   dictation [key|set …]      /config/groq.key · /config/dictation.conf
//!
//! 남의 문법은 다시 짓지 않는다(결정 10). 덩어리를 짓는 것은 `wpa_passphrase`, 키를 읽는
//! 것은 `ssh-keygen`, 규칙을 올리는 것은 `nft`다 — 이 파일은 그 도구를 부르고, 낸 것을
//! 제자리에 두고, 다음에 무엇을 하면 되는지 말한다. 글자를 다루는 것은 전부
//! `config_front_edit.zig`(호스트 검사가 본다)이고, 여기는 시스템 콜 쪽이다.
const std = @import("std");
const linux = std.os.linux;
const config = @import("config.zig");
const cli = @import("config_cli.zig");
const fe = @import("config_front_edit.zig");

const say = cli.say;
const complain = cli.complain;
const failed = cli.failed;

const WPA_PATH: [:0]const u8 = "/config/wpa_supplicant.conf";
const WPA_TEMP: [:0]const u8 = "/config/.wpa_supplicant.conf.new";
const SERVICES_DIR: [:0]const u8 = "/config/services.d";
const SSHD_LINK: [:0]const u8 = "/config/services.d/sshd";
/// SV design 결정 6의 템플릿. 사람이 `ln -s`로 거는 그 대상이다.
const SSHD_TEMPLATE: [:0]const u8 = "/etc/tars/services/sshd";
const SSH_DIR: [:0]const u8 = "/config/ssh";
const KEYS_PATH: [:0]const u8 = "/config/ssh/authorized_keys";
const KEYS_TEMP: [:0]const u8 = "/config/ssh/.authorized_keys.new";
const NFT_DIR: [:0]const u8 = "/config/nftables.d";
/// 이 명령만 쓰는 nft 파일(결정 14). 사람의 파일과 갈라 둔다 — 지우는 동사(`deny`)가 사람의
/// 줄을 건드릴 길이 없다.
const NFT_PATH: [:0]const u8 = "/config/nftables.d/tars-config.nft";
const NFT_TEMP: [:0]const u8 = "/config/nftables.d/.tars-config.nft.new";
const KEY_PATH: [:0]const u8 = "/config/groq.key";
const KEY_TEMP: [:0]const u8 = "/config/.groq.key.new";
const DICT_PATH: [:0]const u8 = "/config/dictation.conf";
const DICT_TEMP: [:0]const u8 = "/config/.dictation.conf.new";

/// 부르는 도구. 경로는 `kernel/guest_tools.sh`가 싣는 자리이고 `firewall.zig`의 NFT_PATH와 같다.
const WPA_PASSPHRASE: [:0]const u8 = "/usr/bin/wpa_passphrase";
const SSH_KEYGEN: [:0]const u8 = "/usr/bin/ssh-keygen";
const NFT: [:0]const u8 = "/usr/bin/nft";
const FIREWALL_RULES: [:0]const u8 = "/etc/tars/firewall.nft";

const ENVP = [_:null]?[*:0]const u8{"PATH=/usr/bin:/bin"};

const BUF = 16384;

// ── 바탕 ──────────────────────────────────────────────────────────────

fn needDisk() bool {
    var mounts: [8192]u8 = undefined;
    if (cli.configDisk(&mounts) != null) return true;
    complain("no config disk is mounted at /config; a change there would be gone at the next boot", .{});
    return false;
}

/// 지금의 tars.conf를 init과 같은 길로 읽는다. 다음 걸음을 말할 때(`net=off`면 무선이 안
/// 뜬다 등) 쓴다.
fn tarsConf() config.Config {
    var buf: [cli.READ_MAX]u8 = undefined;
    return switch (cli.readFile(cli.CONF_PATH, &buf)) {
        .bytes => |b| cli.parsed(b),
        else => .{},
    };
}

fn readOr(path: [*:0]const u8, buf: []u8) ?[]const u8 {
    return switch (cli.readFile(path, buf)) {
        .bytes => |b| b,
        .missing => "",
        .failed => |e| {
            complain("cannot read {s} (errno {d})", .{ std.mem.span(path), @intFromEnum(e) });
            return null;
        },
    };
}

/// temp에 쓰고 path로 갈아 끼운다(결정 5와 같은 까닭). mode는 새 파일의 것이다.
fn replace(path: [:0]const u8, temp: [:0]const u8, text: []const u8, mode: linux.mode_t) bool {
    const rc = linux.open(temp.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, mode);
    if (failed(rc)) |e| {
        complain("cannot create {s} (errno {d})", .{ temp, @intFromEnum(e) });
        return false;
    }
    const fd: i32 = @intCast(rc);
    // umask가 mode를 깎을 수 있다. 비밀(0600)은 깎이는 쪽이라 괜찮지만 0644가 0600이 되면
    // 사람이 놀란다 — 적은 그대로 맞춘다.
    _ = linux.fchmod(fd, mode);
    const ok = cli.writeAll(fd, text);
    _ = linux.close(fd);
    if (!ok) {
        complain("cannot write {s}", .{temp});
        return false;
    }
    if (failed(linux.rename(temp.ptr, path.ptr))) |e| {
        complain("cannot rename {s} to {s} (errno {d})", .{ temp, path, @intFromEnum(e) });
        return false;
    }
    return true;
}

fn ensureDir(path: [:0]const u8, mode: linux.mode_t) bool {
    if (failed(linux.mkdir(path.ptr, mode))) |e| {
        if (e == .EXIST) return true;
        complain("cannot make {s} (errno {d})", .{ path, @intFromEnum(e) });
        return false;
    }
    _ = linux.chmod(path.ptr, mode);
    return true;
}

const Ran = struct { code: u8, out: []const u8 };

/// argv를 fork · execve로 돌린다. input을 표준 입력으로 주고 표준 출력 · 에러를 함께 받는다
/// (out에 들어가는 만큼). `install.zig`의 `runTool`과 같은 모양이고 다른 것은 출력을 돌려준다는
/// 것 하나다. 시그널로 죽었으면 128 + 번호.
fn run(argv: [*:null]const ?[*:0]const u8, input: []const u8, out: []u8) ?Ran {
    var in_fds: [2]i32 = undefined;
    var out_fds: [2]i32 = undefined;
    if (failed(linux.pipe2(&in_fds, .{ .CLOEXEC = true }))) |_| return null;
    if (failed(linux.pipe2(&out_fds, .{ .CLOEXEC = true }))) |_| return null;
    const pid = linux.fork();
    if (failed(pid)) |_| return null;
    if (pid == 0) {
        _ = linux.dup2(in_fds[0], 0);
        _ = linux.dup2(out_fds[1], 1);
        _ = linux.dup2(out_fds[1], 2);
        _ = linux.execve(argv[0].?, argv, &ENVP);
        linux.exit(127);
    }
    _ = linux.close(in_fds[0]);
    _ = linux.close(out_fds[1]);
    // 입력은 비밀번호 · 키 한 줄이라 파이프 버퍼 안에 든다. 자식이 읽기 전에 다 써도 안 막힌다.
    _ = cli.writeAll(in_fds[1], input);
    _ = linux.close(in_fds[1]);
    var len: usize = 0;
    while (true) {
        var sink: [512]u8 = undefined;
        const dst: []u8 = if (len < out.len) out[len..] else &sink;
        const n = linux.read(out_fds[0], dst.ptr, dst.len);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            break;
        }
        if (n == 0) break;
        if (len < out.len) len += n;
    }
    _ = linux.close(out_fds[0]);
    var status: u32 = 0;
    while (failed(linux.wait4(@intCast(pid), &status, 0, null))) |e| {
        if (e != .INTR) return null;
    }
    const code: u8 = if (linux.W.IFEXITED(status)) linux.W.EXITSTATUS(status) else 128 +| @as(u8, @truncate(@intFromEnum(linux.W.TERMSIG(status))));
    return .{ .code = code, .out = out[0..len] };
}

/// 비밀 하나를 읽는다 — 비밀번호 · API 키. 표준 입력이 tty면 prompt를 찍고 echo를 끈 채
/// 한 줄을, 아니면(파이프 · 파일) 끝까지 읽는다. 끝의 개행은 뗀다. 명령줄 인자로 받지 않는
/// 이유는 `/proc/<pid>/cmdline`과 셸 히스토리다(VD design 결정 4와 같다).
fn readSecret(prompt: []const u8, buf: []u8) ?[]const u8 {
    var old: linux.termios = undefined;
    const tty = failed(linux.tcgetattr(0, &old)) == null;
    if (tty) {
        _ = cli.writeAll(2, prompt);
        var quiet = old;
        quiet.lflag.ECHO = false;
        _ = linux.tcsetattr(0, .FLUSH, &quiet);
    }
    var len: usize = 0;
    while (len < buf.len) {
        const n = linux.read(0, buf[len..].ptr, buf.len - len);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            break;
        }
        if (n == 0) break;
        len += n;
        if (tty and buf[len - 1] == '\n') break;
    }
    if (tty) {
        _ = linux.tcsetattr(0, .FLUSH, &old);
        _ = cli.writeAll(2, "\n");
    }
    if (len == buf.len) return null;
    return std.mem.trimEnd(u8, buf[0..len], "\r\n");
}

// ── wifi ──────────────────────────────────────────────────────────────

/// `tars-config wifi SSID [--country CC]` (결정 12).
pub fn wifi(args: []const [*:0]const u8) u8 {
    if (args.len == 0) return wifiStatus();
    const ssid = std.mem.span(args[0]);
    var country: ?[]const u8 = null;
    if (args.len == 3 and std.mem.eql(u8, std.mem.span(args[1]), "--country")) {
        country = std.mem.span(args[2]);
        if (!fe.countryOk(country.?)) {
            complain("--country takes two capital letters, like KR", .{});
            return cli.EXIT_USAGE;
        }
    } else if (args.len != 1) return cli.usage();
    if (ssid.len == 0 or ssid.len > 32 or fe.hasControl(ssid)) {
        complain("an SSID is 1 to 32 bytes without control characters", .{});
        return cli.EXIT_USAGE;
    }
    if (!needDisk()) return cli.EXIT_IO;

    var pass_buf: [256]u8 = undefined;
    var prompt_buf: [96]u8 = undefined;
    const prompt = std.fmt.bufPrint(&prompt_buf, "passphrase for {s}: ", .{ssid}) catch "passphrase: ";
    const pass = readSecret(prompt, &pass_buf) orelse {
        complain("the passphrase is too long", .{});
        return cli.EXIT_REFUSED;
    };
    // wpa_passphrase가 표준 입력에서 읽는다 — 인자로 주면 ps에 보인다.
    var line_buf: [258]u8 = undefined;
    const line = std.fmt.bufPrint(&line_buf, "{s}\n", .{pass}) catch unreachable;
    var ssid_z: [33:0]u8 = @splat(0);
    @memcpy(ssid_z[0..ssid.len], ssid);
    const argv = [_:null]?[*:0]const u8{ WPA_PASSPHRASE, &ssid_z };
    var out: [2048]u8 = undefined;
    const ran = run(&argv, line, &out) orelse {
        complain("could not run {s}", .{WPA_PASSPHRASE});
        return cli.EXIT_IO;
    };
    if (ran.code != 0) {
        complain("wpa_passphrase refused (exit {d}): {s}", .{ ran.code, std.mem.trim(u8, ran.out, " \n") });
        complain("nothing was written", .{});
        return cli.EXIT_REFUSED;
    }
    var block_buf: [1024]u8 = undefined;
    const block = fe.networkBlock(&block_buf, ran.out) orelse {
        complain("wpa_passphrase printed something that is not one network block; nothing was written", .{});
        return cli.EXIT_IO;
    };

    var conf_buf: [BUF]u8 = undefined;
    const conf = readOr(WPA_PATH, &conf_buf) orelse return cli.EXIT_IO;
    const existed = conf.len > 0 or fileExists(WPA_PATH);
    var placed_buf: [BUF]u8 = undefined;
    const placed = fe.placeNetwork(&placed_buf, conf, block) orelse {
        complain("{s} would grow past {d} bytes", .{ WPA_PATH, BUF });
        return cli.EXIT_REFUSED;
    };
    var text = placed.text;
    var cc_buf: [BUF]u8 = undefined;
    if (country) |cc| text = fe.setCountry(&cc_buf, text, cc) orelse {
        complain("{s} would grow past {d} bytes", .{ WPA_PATH, BUF });
        return cli.EXIT_REFUSED;
    };
    // 해시된 psk가 든다 — 그 망에 붙는 데는 그것으로 충분하므로 비밀이다.
    if (!replace(WPA_PATH, WPA_TEMP, text, 0o600)) return cli.EXIT_IO;

    say("wifi: {s} {s} in {s}{s}\n", .{
        ssid,
        if (placed.replaced) "replaced" else "added",
        WPA_PATH,
        if (country != null) " (with country)" else "",
    });
    const c = tarsConf();
    if (c.net == .off) say("net=off: wifi needs the network on — tars-config set net=dhcp\n", .{});
    if (existed) {
        say("apply now: tars-service restart wpa_supplicant\n", .{});
    } else {
        say("init starts wpa_supplicant only when this file is there at boot; reboot (kill -INT 1)\n", .{});
    }
    return cli.EXIT_OK;
}

fn wifiStatus() u8 {
    var conf_buf: [BUF]u8 = undefined;
    const conf = readOr(WPA_PATH, &conf_buf) orelse return cli.EXIT_IO;
    if (conf.len == 0) {
        say("no {s}: wifi is off. tars-config wifi SSID adds a network\n", .{WPA_PATH});
        return cli.EXIT_OK;
    }
    // 망의 이름만 보인다. psk 줄은 안 찍는다.
    var it = std.mem.splitScalar(u8, conf, '\n');
    while (it.next()) |raw| {
        const t = std.mem.trim(u8, raw, " \t\r");
        if (std.mem.startsWith(u8, t, "ssid=") or std.mem.startsWith(u8, t, "country=")) say("{s}\n", .{t});
    }
    return cli.EXIT_OK;
}

fn fileExists(path: [:0]const u8) bool {
    return failed(linux.access(path.ptr, linux.F_OK)) == null;
}

// ── ssh ───────────────────────────────────────────────────────────────

/// 링크가 템플릿을 가리키는가. 사람이 다른 sshd 스크립트를 그 이름으로 두었으면 거짓이다.
fn sshdLinked() enum { none, template, other } {
    var buf: [256]u8 = undefined;
    const rc = linux.readlink(SSHD_LINK.ptr, &buf, buf.len);
    if (failed(rc)) |e| return if (e == .NOENT) .none else .other;
    return if (std.mem.eql(u8, buf[0..rc], SSHD_TEMPLATE)) .template else .other;
}

/// `tars-config ssh [on|off]` (결정 13).
pub fn ssh(args: []const [*:0]const u8) u8 {
    if (args.len > 1) return cli.usage();
    if (args.len == 0) {
        var keys_buf: [BUF]u8 = undefined;
        const keys = readOr(KEYS_PATH, &keys_buf) orelse return cli.EXIT_IO;
        say("sshd: {s}\n", .{switch (sshdLinked()) {
            .template => "on (/config/services.d/sshd -> /etc/tars/services/sshd)",
            .other => "/config/services.d/sshd is yours, not the template",
            .none => "off",
        }});
        say("keys: {d} in {s}\n", .{ fe.keyCount(keys), KEYS_PATH });
        sayFirewall22();
        return cli.EXIT_OK;
    }
    const verb = std.mem.span(args[0]);
    if (!needDisk()) return cli.EXIT_IO;
    if (std.mem.eql(u8, verb, "on")) {
        switch (sshdLinked()) {
            .template => say("sshd: already on\n", .{}),
            .other => {
                complain("{s} is there and is not a link to {s}; leaving it", .{ SSHD_LINK, SSHD_TEMPLATE });
                return cli.EXIT_REFUSED;
            },
            .none => {
                if (!ensureDir(SERVICES_DIR, 0o755)) return cli.EXIT_IO;
                if (failed(linux.symlink(SSHD_TEMPLATE.ptr, SSHD_LINK.ptr))) |e| {
                    complain("cannot link {s} (errno {d})", .{ SSHD_LINK, @intFromEnum(e) });
                    return cli.EXIT_IO;
                }
                say("sshd: on — {s} -> {s}; init starts it at the next boot (kill -INT 1)\n", .{ SSHD_LINK, SSHD_TEMPLATE });
            },
        }
        var keys_buf: [BUF]u8 = undefined;
        const keys = readOr(KEYS_PATH, &keys_buf) orelse return cli.EXIT_IO;
        if (fe.keyCount(keys) == 0) say("no key yet: tars-config ssh-key add 'ssh-ed25519 AAAA… you@host'\n", .{});
        sayFirewall22();
        return cli.EXIT_OK;
    }
    if (std.mem.eql(u8, verb, "off")) {
        switch (sshdLinked()) {
            .none => say("sshd: already off\n", .{}),
            .other => {
                complain("{s} is not a link to {s}; leaving it", .{ SSHD_LINK, SSHD_TEMPLATE });
                return cli.EXIT_REFUSED;
            },
            .template => {
                if (failed(linux.unlink(SSHD_LINK.ptr))) |e| {
                    complain("cannot remove {s} (errno {d})", .{ SSHD_LINK, @intFromEnum(e) });
                    return cli.EXIT_IO;
                }
                say("sshd: off from the next boot; to stop it now: tars-service stop sshd\n", .{});
            },
        }
        return cli.EXIT_OK;
    }
    return cli.usage();
}

/// firewall=on이면 22를 이 명령이 열었는지 말한다. 사람의 nft 파일은 안 읽는다(결정 10) —
/// 열려 있을 수도 있다고만 말한다.
fn sayFirewall22() void {
    if (tarsConf().firewall != .on) return;
    var buf: [BUF]u8 = undefined;
    const text = readOr(NFT_PATH, &buf) orelse return;
    if (fe.hasLine(text, "tcp dport 22 accept")) {
        say("firewall=on: tars-config opened port 22\n", .{});
    } else {
        say("firewall=on: port 22 is open only if a file in {s} says so; tars-config firewall allow 22\n", .{NFT_DIR});
    }
}

/// `tars-config ssh-key add [KEY] | list` (결정 13).
pub fn sshKey(args: []const [*:0]const u8) u8 {
    if (args.len == 0) return cli.usage();
    const verb = std.mem.span(args[0]);
    if (std.mem.eql(u8, verb, "list")) {
        if (args.len != 1) return cli.usage();
        if (!fileExists(KEYS_PATH)) {
            say("no {s}\n", .{KEYS_PATH});
            return cli.EXIT_OK;
        }
        const argv = [_:null]?[*:0]const u8{ SSH_KEYGEN, "-l", "-f", KEYS_PATH };
        var out: [BUF]u8 = undefined;
        const ran = run(&argv, "", &out) orelse return cli.EXIT_IO;
        _ = cli.writeAll(1, ran.out);
        return if (ran.code == 0) cli.EXIT_OK else cli.EXIT_REFUSED;
    }
    if (!std.mem.eql(u8, verb, "add") or args.len > 2) return cli.usage();
    if (!needDisk()) return cli.EXIT_IO;

    // 키 한 줄 — 인자 하나(따옴표로 싼 줄)이거나 표준 입력(`< id_ed25519.pub`).
    var in_buf: [8192]u8 = undefined;
    const raw: []const u8 = if (args.len == 2) std.mem.span(args[1]) else (readSecret("public key: ", &in_buf) orelse {
        complain("the key is too long", .{});
        return cli.EXIT_REFUSED;
    });
    const line = std.mem.trim(u8, raw, " \t\r\n");
    if (line.len == 0 or std.mem.indexOfScalar(u8, line, '\n') != null or fe.hasControl(line)) {
        complain("give one public key line, like 'ssh-ed25519 AAAA… you@host'", .{});
        return cli.EXIT_USAGE;
    }
    // 키인지는 ssh-keygen이 정한다. 지문이 사람에게 보여 줄 것이기도 하다.
    const argv = [_:null]?[*:0]const u8{ SSH_KEYGEN, "-l", "-f", "-" };
    var out: [1024]u8 = undefined;
    var with_nl: [8200]u8 = undefined;
    const input = std.fmt.bufPrint(&with_nl, "{s}\n", .{line}) catch return cli.EXIT_REFUSED;
    const ran = run(&argv, input, &out) orelse {
        complain("could not run {s}", .{SSH_KEYGEN});
        return cli.EXIT_IO;
    };
    const fp = std.mem.trim(u8, ran.out, " \n");
    if (ran.code != 0) {
        complain("ssh-keygen does not read this as a public key: {s}", .{fp});
        complain("nothing was written", .{});
        return cli.EXIT_REFUSED;
    }
    const body = fe.keyBody(line) orelse {
        complain("ssh-keygen read it, but the key has no AAAA… body this command can compare; nothing was written", .{});
        return cli.EXIT_REFUSED;
    };

    var keys_buf: [BUF]u8 = undefined;
    const keys = readOr(KEYS_PATH, &keys_buf) orelse return cli.EXIT_IO;
    if (fe.hasKey(keys, body)) {
        say("ssh-key: already there — {s}\n", .{fp});
    } else {
        var new_buf: [BUF + 8200]u8 = undefined;
        const text = fe.appendLine(&new_buf, keys, line) orelse return cli.EXIT_REFUSED;
        if (!ensureDir(SSH_DIR, 0o700)) return cli.EXIT_IO;
        if (!replace(KEYS_PATH, KEYS_TEMP, text, 0o600)) return cli.EXIT_IO;
        say("ssh-key: added {s}\n", .{fp});
        say("sshd reads {s} at every login — no restart\n", .{KEYS_PATH});
    }
    if (sshdLinked() == .none) say("sshd is off: tars-config ssh on, then reboot\n", .{});
    sayFirewall22();
    return cli.EXIT_OK;
}

// ── firewall ──────────────────────────────────────────────────────────

/// `tars-config firewall [allow|deny PORT[/udp]]` (결정 14).
pub fn firewall(args: []const [*:0]const u8) u8 {
    const c = tarsConf();
    var buf: [BUF]u8 = undefined;
    const text = readOr(NFT_PATH, &buf) orelse return cli.EXIT_IO;
    if (args.len == 0) {
        say("firewall={s}\n", .{@tagName(c.firewall)});
        var it = std.mem.splitScalar(u8, text, '\n');
        var n: usize = 0;
        while (it.next()) |raw| {
            const t = std.mem.trim(u8, raw, " \t\r");
            if (t.len == 0 or t[0] == '#') continue;
            say("{s}\n", .{t});
            n += 1;
        }
        if (n == 0) say("tars-config opened no port ({s} has no rule)\n", .{NFT_PATH});
        say("rules you wrote yourself live in other files under {s}; nft list ruleset shows what is up\n", .{NFT_DIR});
        return cli.EXIT_OK;
    }
    if (args.len != 2) return cli.usage();
    const verb = std.mem.span(args[0]);
    const allow = std.mem.eql(u8, verb, "allow");
    if (!allow and !std.mem.eql(u8, verb, "deny")) return cli.usage();
    const spec = fe.parsePort(std.mem.span(args[1])) orelse {
        complain("a port is 1 to 65535, optionally /tcp or /udp (tcp is the default)", .{});
        return cli.EXIT_USAGE;
    };
    if (!needDisk()) return cli.EXIT_IO;
    var rule_buf: [32]u8 = undefined;
    const rule = fe.ruleLine(&rule_buf, spec);

    var new_buf: [BUF + 64]u8 = undefined;
    const base = if (text.len == 0) fe.RULES_HEADER else text;
    const changed: ?[]const u8 = if (allow)
        (if (fe.hasLine(base, rule)) null else fe.appendLine(&new_buf, base, rule) orelse return cli.EXIT_REFUSED)
    else
        (if (!fe.hasLine(text, rule)) null else fe.removeLine(&new_buf, text, rule) orelse return cli.EXIT_REFUSED);
    if (changed) |t| {
        if (!ensureDir(NFT_DIR, 0o755)) return cli.EXIT_IO;
        if (!replace(NFT_PATH, NFT_TEMP, t, 0o644)) return cli.EXIT_IO;
        say("firewall: {s} {s}\n", .{ if (allow) "opened" else "closed", rule });
    } else {
        say("firewall: {s} was {s}\n", .{ rule, if (allow) "already open here" else "not opened by tars-config" });
        if (!allow) say("rules you wrote yourself live in other files under {s}; this command does not touch them\n", .{NFT_DIR});
        return cli.EXIT_OK;
    }

    if (c.firewall != .on) {
        say("firewall=off: nothing is filtered now; the rule counts once firewall=on (tars-config set firewall=on, reboot)\n", .{});
        return cli.EXIT_OK;
    }
    // 켜져 있으면 init이 부팅에 하는 그 명령을 지금 돈다(FW 결정 5). nft는 전부 올리거나 하나도
    // 안 올리므로, 실패하면 지금 선 규칙이 그대로다 — 그 이유는 nft가 말한다.
    const argv = [_:null]?[*:0]const u8{ NFT, "-f", FIREWALL_RULES };
    var out: [4096]u8 = undefined;
    const ran = run(&argv, "", &out) orelse {
        complain("could not run {s}", .{NFT});
        return cli.EXIT_IO;
    };
    if (ran.code == 0) {
        say("applied now: nft -f {s}\n", .{FIREWALL_RULES});
        return cli.EXIT_OK;
    }
    _ = cli.writeAll(2, ran.out);
    complain("nft -f {s} refused (exit {d}); the rules that were up stay up", .{ FIREWALL_RULES, ran.code });
    complain("the next boot would fall back to the base rules too — fix the file nft named above", .{});
    return cli.EXIT_REFUSED;
}

// ── dictation ─────────────────────────────────────────────────────────

/// `tars-config dictation [key [KEY] | set KEY=VALUE…]` (결정 15).
pub fn dictation(args: []const [*:0]const u8) u8 {
    if (args.len == 0) {
        say("key: {s}\n", .{if (fileExists(KEY_PATH)) "/config/groq.key is there (not shown)" else "none — tars-config dictation key"});
        var buf: [BUF]u8 = undefined;
        const text = readOr(DICT_PATH, &buf) orelse return cli.EXIT_IO;
        if (text.len == 0) say("no {s}: tars-dictate uses its defaults (tars-dictate -h)\n", .{DICT_PATH}) else _ = cli.writeAll(1, text);
        return cli.EXIT_OK;
    }
    const verb = std.mem.span(args[0]);
    if (std.mem.eql(u8, verb, "key")) {
        if (args.len > 2) return cli.usage();
        if (!needDisk()) return cli.EXIT_IO;
        var in_buf: [512]u8 = undefined;
        const raw: []const u8 = if (args.len == 2) std.mem.span(args[1]) else (readSecret("Groq API key: ", &in_buf) orelse {
            complain("the key is too long", .{});
            return cli.EXIT_REFUSED;
        });
        const key = fe.apiKey(raw) orelse {
            complain("an API key is one word without spaces or control characters; nothing was written", .{});
            return cli.EXIT_REFUSED;
        };
        var line_buf: [520]u8 = undefined;
        const line = std.fmt.bufPrint(&line_buf, "{s}\n", .{key}) catch return cli.EXIT_REFUSED;
        if (!replace(KEY_PATH, KEY_TEMP, line, 0o600)) return cli.EXIT_IO;
        say("dictation: wrote {s} (0600, {d} characters)\n", .{ KEY_PATH, key.len });
        say("tars-dictate reads it at every run — no restart\n", .{});
        if (tarsConf().net == .off) say("net=off: dictation needs the network — tars-config set net=dhcp\n", .{});
        return cli.EXIT_OK;
    }
    if (!std.mem.eql(u8, verb, "set") or args.len < 2) return cli.usage();
    if (!needDisk()) return cli.EXIT_IO;
    // 이름만 거른다. 값은 tars-dictate가 실행마다 읽고 틀리면 경고한다(결정 15).
    for (args[1..]) |a| {
        const arg = std.mem.span(a);
        const eq = std.mem.indexOfScalar(u8, arg, '=') orelse {
            complain("'{s}' has no '='; set takes KEY=VALUE", .{arg});
            return cli.EXIT_USAGE;
        };
        const key = std.mem.trim(u8, arg[0..eq], " \t");
        if (!fe.isDictationKey(key)) {
            complain("unknown dictation key '{s}'; the keys are in tars-dictate -h", .{key});
            complain("nothing was written", .{});
            return cli.EXIT_REFUSED;
        }
        if (fe.hasControl(arg)) {
            complain("{s}: a control character cannot go into a config line", .{key});
            return cli.EXIT_REFUSED;
        }
    }
    var buf: [BUF]u8 = undefined;
    var text = readOr(DICT_PATH, &buf) orelse return cli.EXIT_IO;
    var work: [2][BUF]u8 = undefined;
    // 같은 문법(`#` 주석 · 첫 `=` · 양쪽 공백)이라 tars.conf의 줄 바꾸기를 그대로 쓴다.
    const edit = @import("config_edit.zig");
    for (args[1..], 0..) |a, i| {
        const arg = std.mem.span(a);
        const eq = std.mem.indexOfScalar(u8, arg, '=').?;
        const key = std.mem.trim(u8, arg[0..eq], " \t");
        const value = std.mem.trim(u8, arg[eq + 1 ..], " \t");
        text = edit.setLine(&work[i % 2], text, key, value) orelse {
            complain("{s} would grow past {d} bytes", .{ DICT_PATH, BUF });
            return cli.EXIT_REFUSED;
        };
        say("dictation: {s}={s}\n", .{ key, value });
    }
    if (!replace(DICT_PATH, DICT_TEMP, text, 0o644)) return cli.EXIT_IO;
    say("tars-dictate reads {s} at every run — no restart; it warns about a value it does not take\n", .{DICT_PATH});
    return cli.EXIT_OK;
}

// ── check ─────────────────────────────────────────────────────────────

/// `tars-config check`가 앞문 넷의 파일에서 보는 것(결정 16). 문제의 수를 돌려준다.
/// 남의 문법은 안 읽는다 — 파일이 있는지 · 모드 · tars.conf와 맞는지만 본다.
pub fn check(c: config.Config) usize {
    var problems: usize = 0;
    if (fileExists(WPA_PATH) and c.net == .off) {
        say("{s} is there but net=off, so init does not start wpa_supplicant; tars-config set net=dhcp\n", .{WPA_PATH});
        problems += 1;
    }
    if (sshdLinked() == .template) {
        var buf: [BUF]u8 = undefined;
        const keys = readOr(KEYS_PATH, &buf) orelse "";
        if (fe.keyCount(keys) == 0) {
            say("sshd is on but {s} has no key, so nobody can log in; tars-config ssh-key add\n", .{KEYS_PATH});
            problems += 1;
        }
    }
    // 비밀 셋. 남이 쓸 수 있으면 sshd가 그 파일을 버리고(StrictModes), 읽을 수 있으면 비밀이 아니다.
    for ([_][:0]const u8{ KEYS_PATH, KEY_PATH, WPA_PATH }) |path| {
        var st: linux.Statx = undefined;
        if (failed(linux.statx(linux.AT.FDCWD, path.ptr, 0, .{ .MODE = true }, &st)) != null) continue;
        const mode = st.mode & 0o777;
        if (mode & 0o077 != 0) {
            say("{s} is mode {o}; others can read it — chmod 600 {s}\n", .{ path, mode, path });
            problems += 1;
        }
    }
    if (c.firewall == .off) {
        var buf: [BUF]u8 = undefined;
        const text = readOr(NFT_PATH, &buf) orelse "";
        if (fe.keyCount(text) > 0) {
            say("note: firewall=off, so the ports tars-config opened in {s} filter nothing yet\n", .{NFT_PATH});
        }
    }
    var dbuf: [BUF]u8 = undefined;
    const dict = readOr(DICT_PATH, &dbuf) orelse "";
    var it = std.mem.splitScalar(u8, dict, '\n');
    var number: usize = 0;
    while (it.next()) |raw| {
        number += 1;
        const t = std.mem.trim(u8, raw, " \t\r");
        if (t.len == 0 or t[0] == '#') continue;
        const eq = std.mem.indexOfScalar(u8, t, '=') orelse continue;
        const key = std.mem.trim(u8, t[0..eq], " \t");
        if (!fe.isDictationKey(key)) {
            say("{s} line {d}: tars-dictate does not know the key '{s}'\n", .{ DICT_PATH, number, key });
            problems += 1;
        }
    }
    return problems;
}
```

`init/src/config_front_edit_test.zig`:

```zig
//! TC-M1. `config_front_edit.zig`의 검사. config_edit_test와 같은 모양이다 — 호스트 아키텍처의
//! 실행 파일이고, 실패하면 `FAIL:` 줄을 찍고 0이 아닌 코드로 끝난다.
const std = @import("std");
const linux = std.os.linux;
const fe = @import("config_front_edit.zig");

/// tars-dictate의 자리. `zig build test`는 init/에서 돈다.
const DICTATE_PATH: [:0]const u8 = "../kernel/dictation/tars-dictate";

fn fail(comptime fmt: []const u8, args: anytype) error{Failed} {
    std.debug.print("FAIL: " ++ fmt ++ "\n", args);
    return error.Failed;
}

fn expectText(got: ?[]const u8, want: []const u8, what: []const u8) !void {
    const g = got orelse return fail("{s}: got null, want\n{s}", .{ what, want });
    if (!std.mem.eql(u8, g, want)) return fail("{s}:\n--- got ---\n{s}\n--- want ---\n{s}", .{ what, g, want });
}

fn readAll(path: [:0]const u8, buf: []u8) ![]const u8 {
    const rc = linux.open(path.ptr, .{ .ACCMODE = .RDONLY }, 0);
    if (linux.errno(rc) != .SUCCESS) return fail("cannot open {s}", .{path});
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var len: usize = 0;
    while (len < buf.len) {
        const n = linux.read(fd, buf[len..].ptr, buf.len - len);
        if (linux.errno(n) != .SUCCESS) return fail("cannot read {s}", .{path});
        if (n == 0) break;
        len += n;
    }
    return buf[0..len];
}

/// `wpa_passphrase tars-wl`에 `tars-secret`을 표준 입력으로 준 출력의 모양. 첫 줄은 표준 입력에서
/// 읽을 때만 나온다. psk는 PBKDF2-SHA1(4096회)의 값이다. 게스트의 진짜 출력이 같은 길을 지나는 것은
/// wifi 체인 검사 12가 본다.
const WPA_OUT =
    "# reading passphrase from stdin\n" ++
    "network={\n" ++
    "\tssid=\"tars-wl\"\n" ++
    "\t#psk=\"tars-secret\"\n" ++
    "\tpsk=3c51e611003bdbb9d4c5553147982976c6760ed39de1705f73d5c1c08f97c3ac\n" ++
    "}\n";
const WPA_BLOCK =
    "network={\n" ++
    "\tssid=\"tars-wl\"\n" ++
    "\tpsk=3c51e611003bdbb9d4c5553147982976c6760ed39de1705f73d5c1c08f97c3ac\n" ++
    "}\n";

/// 소문자와 밑줄만으로 된 낱말인가 — tars-dictate의 case 줄에서 키 이름을 고른다.
fn isName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |ch| if (!(ch >= 'a' and ch <= 'z') and ch != '_') return false;
    return true;
}

pub fn main() !void {
    // ── 1. 포트와 규칙 한 줄 ────────────────────────────────────────────
    const good = [_]struct { []const u8, u16, fe.Proto }{
        .{ "22", 22, .tcp }, .{ "65535", 65535, .tcp }, .{ "5353/udp", 5353, .udp }, .{ "8080/tcp", 8080, .tcp },
    };
    for (good) |g| {
        const s = fe.parsePort(g[0]) orelse return fail("parsePort {s} refused", .{g[0]});
        if (s.port != g[1] or s.proto != g[2]) return fail("parsePort {s}", .{g[0]});
    }
    for ([_][]const u8{ "", "0", "65536", "022", "22/sctp", "22/", "/udp", "2 2", "22/udp/x", "-1", "99999" }) |b| {
        if (fe.parsePort(b) != null) return fail("parsePort accepted '{s}'", .{b});
    }
    var rb: [32]u8 = undefined;
    try expectText(fe.ruleLine(&rb, .{ .port = 22, .proto = .tcp }), "tcp dport 22 accept", "ruleLine tcp");
    try expectText(fe.ruleLine(&rb, .{ .port = 5353, .proto = .udp }), "udp dport 5353 accept", "ruleLine udp");

    var out: [4096]u8 = undefined;
    const header = fe.RULES_HEADER;
    const one = fe.appendLine(&out, header, "tcp dport 22 accept").?;
    var two_buf: [4096]u8 = undefined;
    const two = fe.appendLine(&two_buf, one, "udp dport 5353 accept").?;
    if (!fe.hasLine(two, "tcp dport 22 accept") or !fe.hasLine(two, "udp dport 5353 accept")) return fail("hasLine missed a rule", .{});
    if (fe.hasLine(two, "tcp dport 2 accept")) return fail("hasLine matched a prefix", .{});
    var rm_buf: [4096]u8 = undefined;
    const back = fe.removeLine(&rm_buf, two, "udp dport 5353 accept").?;
    try expectText(back, one, "removeLine gives back the one-rule file");
    try expectText(fe.removeLine(&rm_buf, "a\n  tcp dport 22 accept  \nb", "tcp dport 22 accept"), "a\nb", "removeLine with spaces and no final newline");
    try expectText(fe.appendLine(&out, "x", "y"), "x\ny\n", "appendLine without a final newline");
    try expectText(fe.appendLine(&out, "", "y"), "y\n", "appendLine on nothing");
    if (fe.keyCount(header) != 0 or fe.keyCount(two) != 2) return fail("rule count", .{});
    std.debug.print("config_front_edit_test: ports, the one rule line, and adding · finding · removing it\n", .{});

    // ── 2. wpa_passphrase의 덩어리 ──────────────────────────────────────
    var blk: [1024]u8 = undefined;
    try expectText(fe.networkBlock(&blk, WPA_OUT), WPA_BLOCK, "networkBlock drops the comment and #psk");
    if (fe.networkBlock(&blk, "Passphrase must be 8..63 characters\n") != null) return fail("networkBlock took an error", .{});
    if (fe.networkBlock(&blk, "network={\n\tssid=\"x\"\n") != null) return fail("networkBlock took an unclosed block", .{});
    try expectText(fe.ssidLine(WPA_BLOCK), "ssid=\"tars-wl\"", "ssidLine");

    const human =
        "country=KR\n" ++
        "# my home\n" ++
        "network={\n" ++
        "\tssid=\"other\"\n" ++
        "\tpsk=\"x\"\n" ++
        "}\n" ++
        "network={\n" ++
        "\tssid=\"tars-wl\"\n" ++
        "\tpsk=\"wrong-secret\"\n" ++
        "\tpriority=3\n" ++
        "}\n";
    var pl: [4096]u8 = undefined;
    const placed = fe.placeNetwork(&pl, human, WPA_BLOCK).?;
    if (!placed.replaced) return fail("placeNetwork did not find the tars-wl block", .{});
    try expectText(placed.text, "country=KR\n# my home\nnetwork={\n\tssid=\"other\"\n\tpsk=\"x\"\n}\n" ++ WPA_BLOCK, "placeNetwork replaces only that block");
    const appended = fe.placeNetwork(&pl, "country=KR\n# ssid=\"tars-wl\" is not a block\n", WPA_BLOCK).?;
    if (appended.replaced) return fail("placeNetwork matched a comment", .{});
    try expectText(appended.text, "country=KR\n# ssid=\"tars-wl\" is not a block\n" ++ WPA_BLOCK, "placeNetwork appends");
    try expectText(fe.placeNetwork(&pl, "", WPA_BLOCK).?.text, WPA_BLOCK, "placeNetwork on a new file");
    try expectText(fe.placeNetwork(&pl, "ctrl_interface=x", WPA_BLOCK).?.text, "ctrl_interface=x\n" ++ WPA_BLOCK, "placeNetwork without a final newline");

    var cc: [4096]u8 = undefined;
    try expectText(fe.setCountry(&cc, WPA_BLOCK, "KR"), "country=KR\n" ++ WPA_BLOCK, "setCountry adds at the top");
    try expectText(fe.setCountry(&cc, human, "US"), "country=US" ++ human["country=KR".len..], "setCountry replaces");
    try expectText(fe.setCountry(&cc, "network={\n\tcountry=XX\n}\n", "KR"), "country=KR\nnetwork={\n\tcountry=XX\n}\n", "setCountry skips the inside of a block");
    for ([_][]const u8{ "KR", "US" }) |c| if (!fe.countryOk(c)) return fail("countryOk {s}", .{c});
    for ([_][]const u8{ "kr", "K", "KOR", "K1", "" }) |c| if (fe.countryOk(c)) return fail("countryOk took {s}", .{c});
    std.debug.print("config_front_edit_test: wpa_passphrase's block without #psk, put over the same SSID or appended, country at the top\n", .{});

    // ── 3. ssh 키 ──────────────────────────────────────────────────────
    const k1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOk1 tc1@host";
    const k1_body = "AAAAC3NzaC1lZDI1NTE5AAAAIOk1";
    try expectText(fe.keyBody(k1), k1_body, "keyBody");
    try expectText(fe.keyBody("no-pty,from=\"10.0.0.0/8\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOk1 x"), k1_body, "keyBody behind options");
    if (fe.keyBody("ssh-ed25519 AAAA") != null) return fail("keyBody took a stub", .{});
    const keys = "# mine\nssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOk1 other-comment\n\n";
    if (!fe.hasKey(keys, k1_body)) return fail("hasKey missed the same body under another comment", .{});
    if (fe.hasKey(keys, "AAAAC3NzaC1lZDI1NTE5AAAAIOk2")) return fail("hasKey matched another key", .{});
    if (fe.keyCount(keys) != 1 or fe.keyCount("") != 0) return fail("keyCount", .{});
    std.debug.print("config_front_edit_test: a key is the same key by its AAAA body, whatever the comment or options\n", .{});

    // ── 4. 받아쓰기 ────────────────────────────────────────────────────
    try expectText(fe.apiKey("  gsk_abc123\n"), "gsk_abc123", "apiKey trims");
    for ([_][]const u8{ "", " \n", "gsk abc", "gsk_\x1b[0m" }) |b| if (fe.apiKey(b) != null) return fail("apiKey took '{s}'", .{b});
    if (!fe.hasControl("a\nb") or fe.hasControl("https://x/y?z=1")) return fail("hasControl", .{});

    // 이름 여덟이 tars-dictate의 case와 같다. 그 파일의 `case $key in` ~ `esac`에서 `이름)` 줄을 모은다 —
    // 이름은 소문자와 밑줄뿐이라 안쪽 case의 `on|off)` · `*)`는 안 걸린다.
    var dbuf: [65536]u8 = undefined;
    const dictate = try readAll(DICTATE_PATH, &dbuf);
    const from = std.mem.indexOf(u8, dictate, "case $key in") orelse return fail("tars-dictate has no case $key in", .{});
    const to = std.mem.indexOfPos(u8, dictate, from, "\n    esac") orelse return fail("no esac after it", .{});
    var seen: usize = 0;
    var it = std.mem.splitScalar(u8, dictate[from..to], '\n');
    while (it.next()) |raw| {
        const t = std.mem.trim(u8, raw, " \t");
        const close = std.mem.indexOfScalar(u8, t, ')') orelse continue;
        const name = t[0..close];
        if (!isName(name)) continue;
        if (!fe.isDictationKey(name)) return fail("tars-dictate knows '{s}', DICTATION_KEYS does not", .{name});
        seen += 1;
    }
    if (seen != fe.DICTATION_KEYS.len) return fail("tars-dictate's case has {d} keys, DICTATION_KEYS {d}", .{ seen, fe.DICTATION_KEYS.len });
    std.debug.print("config_front_edit_test: the {d} dictation keys are tars-dictate's own, read from its case\n", .{seen});

    std.debug.print("PASS\n", .{});
}
```

### 1-2. `config_cli.zig` — 편집 열넷

E1이 import 한 줄, E2 ~ E7 · E10 ~ E12가 낱말 `pub`, E8이 USAGE의 둘째 묶음(과 `usage`의 `pub`), E9가 `list`의 끝 줄, E13이 `check`, E14가 `main`의 동사 다섯이다.

E1 — `old_string`(기준 파일 14줄부터):

```zig
const edit = @import("config_edit.zig");
```

`new_string`:

```zig
const edit = @import("config_edit.zig");
const front = @import("config_front.zig");
```

E2 — `old_string`(기준 파일 21줄부터):

```zig
const CONF_PATH: [:0]const u8 = "/config/tars.conf";
```

`new_string`:

```zig
pub const CONF_PATH: [:0]const u8 = "/config/tars.conf";
```

E3 — `old_string`(기준 파일 29줄부터):

```zig
const EXIT_OK: u8 = 0;
/// 값을 거절했다 · `check`가 문제를 찾았다.
const EXIT_REFUSED: u8 = 1;
/// 설정 디스크가 없다 · 파일을 못 읽거나 못 썼다.
const EXIT_IO: u8 = 2;
const EXIT_USAGE: u8 = 64;
```

`new_string`:

```zig
pub const EXIT_OK: u8 = 0;
/// 값을 거절했다 · `check`가 문제를 찾았다.
pub const EXIT_REFUSED: u8 = 1;
/// 설정 디스크가 없다 · 파일을 못 읽거나 못 썼다.
pub const EXIT_IO: u8 = 2;
pub const EXIT_USAGE: u8 = 64;
```

E4 — `old_string`(기준 파일 39줄부터):

```zig
const READ_MAX = 2 * config.MAX_FILE;

fn failed(rc: usize) ?linux.E {
```

`new_string`:

```zig
pub const READ_MAX = 2 * config.MAX_FILE;

pub fn failed(rc: usize) ?linux.E {
```

E5 — `old_string`(기준 파일 46줄부터):

```zig
fn writeAll(fd: i32, bytes: []const u8) bool {
```

`new_string`:

```zig
pub fn writeAll(fd: i32, bytes: []const u8) bool {
```

E6 — `old_string`(기준 파일 60줄부터):

```zig
fn say(comptime fmt: []const u8, args: anytype) void {
```

`new_string`:

```zig
pub fn say(comptime fmt: []const u8, args: anytype) void {
```

E7 — `old_string`(기준 파일 66줄부터):

```zig
fn complain(comptime fmt: []const u8, args: anytype) void {
```

`new_string`:

```zig
pub fn complain(comptime fmt: []const u8, args: anytype) void {
```

E8 — `old_string`(기준 파일 81줄부터):

```zig
;

fn usage() u8 {
```

`new_string`:

```zig
    \\other files under /config (TC-M1):
    \\       tars-config wifi [SSID [--country CC]]       add or replace a network; the passphrase is asked for
    \\       tars-config ssh [on|off]                     sshd at boot (the services.d link)
    \\       tars-config ssh-key add [KEY] | list         /config/ssh/authorized_keys
    \\       tars-config firewall [allow|deny PORT[/udp]] ports tars-config opens, applied now if firewall=on
    \\       tars-config dictation [key [KEY] | set KEY=VALUE...]   /config/groq.key and dictation.conf
    \\
;

pub fn usage() u8 {
```

E9 — `old_string`(기준 파일 99줄부터):

```zig
fn list() u8 {
    keyTable();
```

`new_string`:

```zig
fn list() u8 {
    keyTable();
    say("  (wifi · ssh · ssh-key · firewall · dictation write other files — tars-config help)\n", .{});
```

E10 — `old_string`(기준 파일 119줄부터):

```zig
const Read = union(enum) { missing, failed: linux.E, bytes: []const u8 };

fn readFile(path: [*:0]const u8, buf: []u8) Read {
```

`new_string`:

```zig
pub const Read = union(enum) { missing, failed: linux.E, bytes: []const u8 };

pub fn readFile(path: [*:0]const u8, buf: []u8) Read {
```

E11 — `old_string`(기준 파일 141줄부터):

```zig
fn configDisk(buf: []u8) ?[]const u8 {
```

`new_string`:

```zig
pub fn configDisk(buf: []u8) ?[]const u8 {
```

E12 — `old_string`(기준 파일 169줄부터):

```zig
fn parsed(text: []const u8) config.Config {
```

`new_string`:

```zig
pub fn parsed(text: []const u8) config.Config {
```

E13 — `old_string`(기준 파일 442줄부터):

```zig
    // 옛 seed의 별칭(결정 6). 이 명령을 가리므로 문제로 센다. 지우지는 않는다.
```

`new_string`:

```zig
    // 앞문 넷의 파일(TC-M1 결정 16). 남의 문법은 안 읽고 있는지 · 모드 · tars.conf와 맞는지만.
    problems += front.check(c);

    // 옛 seed의 별칭(결정 6). 이 명령을 가리므로 문제로 센다. 지우지는 않는다.
```

E14 — `old_string`(기준 파일 489줄부터):

```zig
    if (std.mem.eql(u8, verb, "get")) {
```

`new_string`:

```zig
    // 앞문 넷(TC-M1). 인자는 각자 가른다.
    if (std.mem.eql(u8, verb, "wifi")) return front.wifi(rest);
    if (std.mem.eql(u8, verb, "ssh")) return front.ssh(rest);
    if (std.mem.eql(u8, verb, "ssh-key")) return front.sshKey(rest);
    if (std.mem.eql(u8, verb, "firewall")) return front.firewall(rest);
    if (std.mem.eql(u8, verb, "dictation")) return front.dictation(rest);
    if (std.mem.eql(u8, verb, "get")) {
```

### 1-3. `build.zig` — 편집 둘

E1 — `old_string`(기준 파일 285줄부터):

```zig
    // installArtifact를 부르지 않는다. terminal/build.zig의 input_test는
```

`new_string`:

```zig
    // TC-M1: 앞문 넷의 글자 쪽(포트 · 규칙 한 줄 · wpa 덩어리 · 키 몸통 · 받아쓰기 키). config_edit_test와
    // 같은 이유로 host_target이다. tars-dictate의 case를 읽으므로 init/에서 돈다(zig build의 자리).
    const config_front_edit_test_mod = b.createModule(.{
        .root_source_file = b.path("src/config_front_edit_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const config_front_edit_test = b.addExecutable(.{
        .name = "config_front_edit_test",
        .root_module = config_front_edit_test_mod,
    });

    // installArtifact를 부르지 않는다. terminal/build.zig의 input_test는
```

E2 — `old_string`(기준 파일 302줄부터):

```zig
    test_step.dependOn(&b.addRunArtifact(config_edit_test).step);
```

`new_string`:

```zig
    test_step.dependOn(&b.addRunArtifact(config_edit_test).step);
    test_step.dependOn(&b.addRunArtifact(config_front_edit_test).step);
```

### 1-4. 확인

```bash
for f in init/src/config_front_edit.zig init/src/config_front.zig init/src/config_front_edit_test.zig init/src/config_cli.zig init/build.zig; do
  cmp $f /tmp/run/tc1/new/$f && echo "SAME $f"; done
mkdir -p /tmp/run/tc1/impl
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer bash -c '
  rm -rf zig-out .zig-cache
  zig build; echo "build exit=$?"; ls -l zig-out/bin
  zig build test > /tmp/t.log 2>&1; echo "test exit=$?"
  grep -a "^config_front_edit_test:\|^PASS" /tmp/t.log; grep -a "^FAIL" /tmp/t.log | head'
rmdir /tmp/run/docker.lock
```

기대: `SAME` 다섯, `build exit=0`, `tars-config`가 3,667,792바이트 안팎, `test exit=0`, `config_front_edit_test:` 네 줄과 `PASS` 넷, `FAIL` 없음.

## Task 2: 체인 넷의 게스트 쪽과 판정

확정 4.

`dictation/probe.sh`:

E1 — `old_string`(기준 파일 163줄부터):

```bash
sync
```

`new_string`:

```bash
# ── TC-M1 ─────────────────────────────────────────────────────────────
# 22. 사람이 printf와 편집기로 하던 일을 tars-config가 한다 — 키를 표준 입력으로, 설정 두 줄을
# set으로. tars-dictate는 실행마다 그 둘을 읽으므로 다음 실행이 곧 판정이다. /fail(429)로 보내서
# 기록에 한 줄도 안 더한다(검사 13의 열여섯이 그대로다). 모르는 키는 거절되고 파일이 안 바뀐다.
say "tc key [$(printf 'tc1-key\n' | tars-config dictation key 2>&1 | flat)] mode [$(stat -c %a /config/groq.key)]"
say "tc set [$(tars-config dictation set "transcribe_url=${STUB}/fail/s22" max_seconds=1 2>&1 | flat)]"
out="$(tars-config dictation set colour=blue 2>&1)"; rc=$?
say "tc refused exit ${rc} [$(printf '%s' "$out" | flat)] colour lines [$(grep -c colour /config/dictation.conf)]"
dictate s22 cap

sync
```

`dictation/check.sh`:

E1 — `old_string`(기준 파일 115줄부터):

```bash
    "dictate-probe: s21 exit" \
```

`new_string`:

```bash
    "dictate-probe: s21 exit" \
    "dictate-probe: tc key" \
    "dictate-probe: s22 exit" \
```

E2 — `old_string`(기준 파일 440줄부터):

```bash
# ── 검사 12: stub이 받은 전사 요청은 열아홉이고, 어느 WAV의 머리도 거짓말을 안 한다 ──
# 취소(s3)와 키 없음(s4)만 API에 안 간다 — M0의 여덟과 정리 갈래(s11 ~ s21)의 열하나다. 머리의
# 길이는 SIGINT로 멈춘 셋(s1 · s7 · s9)이 본다 — arecord가 고치지 못한 머리를 tars-dictate가 다시
# 쓴다(검사 3의 주석).
REQUESTS="$(grep -ac '^stub: POST ' "$STUBLOG")"
[ "$REQUESTS" -eq 19 ] || report_failure "the stub got ${REQUESTS} request(s), want 19 (s3 and s4 must not call it)"
```

`new_string`:

```bash
# ── 검사 30: tars-config가 쓴 키와 설정을 다음 tars-dictate가 읽는다 (TC-M1) ──
# 프로브가 키를 표준 입력으로(`printf … | tars-config dictation key`), 전사 주소와 상한을
# `tars-config dictation set`으로 고쳤다. s22의 요청이 그 주소(/fail/s22)로 그 키를 싣고 왔으면
# 둘 다 파일에 들어가 tars-dictate가 읽은 것이다. 키 파일은 0600이고, 모르는 키(colour)는
# 거절돼 파일에 한 줄도 안 남았다. tars-dictate가 이 갈래에서 exit 4(429)인 것은 /fail이 고른 답이다.
grep -aF 'dictate-probe: tc key [dictation: wrote /config/groq.key (0600, 7 characters)|' "$LOG" >/dev/null \
  || report_failure "tars-config dictation key did not write the key from stdin"
grep -aF '] mode [600]' "$LOG" >/dev/null || report_failure "the key file tars-config wrote is not mode 600"
grep -aF "dictate-probe: tc set [dictation: transcribe_url=http://10.0.2.100:8080/fail/s22|dictation: max_seconds=1|" "$LOG" >/dev/null \
  || report_failure "tars-config dictation set did not report the two lines it wrote"
grep -aF "dictate-probe: tc refused exit 1 [tars-config: unknown dictation key 'colour'" "$LOG" >/dev/null \
  || report_failure "tars-config dictation set did not refuse the unknown key colour"
grep -aF '] colour lines [0]' "$LOG" >/dev/null || report_failure "the refused key still landed in dictation.conf"
expect_run s22 4 '""' 'tars-dictate: transcription failed: HTTP 429'
S22="$(stub_line s22)"
[ -n "$S22" ] || report_failure "s22: the request did not reach the transcribe_url tars-config set"
[ "$(stub_field "$S22" auth)" = "[Bearer" ] || true
case "$S22" in *"auth=[Bearer tc1-key]"*) ;; *) report_failure "s22: the request did not carry the key tars-config wrote (${S22})" ;; esac
echo "tars-config wrote groq.key (0600) and two dictation.conf lines, refused an unknown key, and the next tars-dictate used both"

# ── 검사 12: stub이 받은 전사 요청은 스물이고, 어느 WAV의 머리도 거짓말을 안 한다 ──
# 취소(s3)와 키 없음(s4)만 API에 안 간다 — M0의 여덟과 정리 갈래(s11 ~ s21)의 열하나, 그리고
# TC-M1의 s22 하나다(검사 30). 머리의
# 길이는 SIGINT로 멈춘 셋(s1 · s7 · s9)이 본다 — arecord가 고치지 못한 머리를 tars-dictate가 다시
# 쓴다(검사 3의 주석).
REQUESTS="$(grep -ac '^stub: POST ' "$STUBLOG")"
[ "$REQUESTS" -eq 20 ] || report_failure "the stub got ${REQUESTS} request(s), want 20 (s3 and s4 must not call it)"
```

E3 — `old_string`(기준 파일 450줄부터):

```bash
echo "the stub got nineteen requests, and every WAV's header matched its length"
```

`new_string`:

```bash
echo "the stub got twenty requests, and every WAV's header matched its length"
```

`service/check.sh`:

E1 — `old_string`(기준 파일 576줄부터):

```bash
ssh -o ControlPath="$CTL" -O exit root@127.0.0.1 2>/dev/null || true
```

`new_string`:

```bash
# ── 검사 27: tars-config ssh-key · ssh (TC-M1) ────────────────────────────
# 사람이 `cat >> /config/ssh/authorized_keys`로 하던 일을 tars-config가 한다. sshd는 로그인마다
# 그 파일을 읽으므로 재시작 없이 다음 로그인이 판정이다 — 검사 14에서 거절된 bad 키를 더하면
# 그 키로 들어온다. 같은 키를 다시 더하면 안 더하고, 키가 아닌 줄은 ssh-keygen이 거절한다.
# 끝으로 ssh off · on이 템플릿 링크를 지웠다 되건다(다음 부팅에 반영되는 일이라 링크만 본다).
tc() {
  OUT="$(ssh "${SSHO[@]}" -o ControlPath="$CTL" root@127.0.0.1 "tars-config $*" 2>&1)"
  RC=$?
}
BAD_PUB="$(cat "$KEYS/bad.pub")"
tc ssh-key add "'${BAD_PUB}'"
[ "$RC" = "0" ] || fail "tars-config ssh-key add gave rc ${RC} (${OUT})"
grep -E '^ssh-key: added 256 SHA256:[A-Za-z0-9+/]+ sv-bad \(ED25519\)$' <<<"$OUT" >/dev/null \
  || fail "tars-config ssh-key add did not print the fingerprint ssh-keygen read (${OUT})"
ssh "${SSHO[@]}" -i "$KEYS/bad" -o ControlPath=none root@127.0.0.1 true >/dev/null 2>&1 \
  || fail "the key tars-config added did not log in"
[ "$(on_guest 'stat -c %a /config/ssh/authorized_keys')" = "600" ] || fail "authorized_keys is not 600 after tars-config wrote it"
tc ssh-key add "'${BAD_PUB}'"
grep -E '^ssh-key: already there' <<<"$OUT" >/dev/null || fail "adding the same key twice was not refused (${OUT})"
[ "$(on_guest 'grep -c sv-bad /config/ssh/authorized_keys')" = "1" ] || fail "the same key landed twice"
# 몸통 모양(AAAA…)은 갖춘 가짜다 — 그래서 이 줄을 거절할 수 있는 것은 ssh-keygen뿐이다.
tc ssh-key add "'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAnotakeyatall tc1'"
[ "$RC" = "1" ] || fail "a line that is not a key gave rc ${RC} (${OUT})"
grep -F 'tars-config: ssh-keygen does not read this as a public key' <<<"$OUT" >/dev/null \
  || fail "a line that is not a key was not refused in ssh-keygen's name (${OUT})"
tc ssh-key list
[ "$(grep -c 'ED25519' <<<"$OUT")" = "2" ] || fail "ssh-key list did not show the two keys (${OUT})"
tc ssh off
grep -F 'sshd: off from the next boot' <<<"$OUT" >/dev/null || fail "ssh off did not say so (${OUT})"
[ -z "$(on_guest 'readlink /config/services.d/sshd')" ] || fail "ssh off left the services.d link"
tc ssh on
grep -F 'sshd: on' <<<"$OUT" >/dev/null || fail "ssh on did not say so (${OUT})"
[ "$(on_guest 'readlink /config/services.d/sshd')" = "/etc/tars/services/sshd" ] || fail "ssh on did not link the template"
echo "tars-config added a key sshd took at the next login, refused a duplicate and a non-key, and unlinked and relinked sshd"

ssh -o ControlPath="$CTL" -O exit root@127.0.0.1 2>/dev/null || true
```

`firewall/check.sh`:

E1 — `old_string`(기준 파일 355줄부터):

```bash
echo "the listener on udp 7073 never saw a datagram"
```

`new_string`:

```bash
echo "the listener on udp 7073 never saw a datagram"

# ── 검사 18: tars-config firewall allow가 연 포트가 지금 열린다 (TC-M1) ──────
# 검사 8 · 11이 닫혀 있음을 본 7072를 사람이 tars-config로 연다. 그 명령은 이 명령만 쓰는
# nftables.d/tars-config.nft에 `tcp dport 7072 accept`를 더하고, firewall=on이라 init이 부팅에
# 하는 `nft -f /etc/tars/firewall.nft`를 그 자리에서 돈다(TC design 결정 14). 7072의 리스너는
# 검사 11이 본 대로 아직 아무와도 안 이어졌으므로, 지금 바이트가 오면 그 한 줄이 선 것이다.
echo "=== typing 'tars-config firewall allow 7072' ==="
type_keys t a r s minus c o n f i g spc f i r e w a l l spc a l l o w spc 7 0 7 2 ret
wait_for_screen "applied now: nft -f /etc/tars/firewall\.nft" \
  || fail "tars-config firewall allow 7072 did not apply the rules" "terminal: screen>"
expect_tcp_bytes "$TCP_SHUT_PORT" fwm2-tcp-7072-ok 7072
echo "tars-config opened 7072 in its own file and nft put it up without a reboot"
```

`wifi/ap.sh`:

E1 — `old_string`(기준 파일 14줄부터):

```bash
# 부팅 B는 /config/wl/mode가 ap-only라 AP만 세우고 멈춘다.
```

`new_string`:

```bash
# 부팅 B는 /config/wl/mode가 ap-only라 AP만 세운다. TC-M1부터 그 뒤에 사람이 할 일을 하나 더
# 한다 — 틀린 비밀번호로 연결이 안 서는 것을 본 뒤 tars-config wifi로 비밀번호를 고치고
# wpa_supplicant를 재시작한다(아래 2b).
```

E2 — `old_string`(기준 파일 57줄부터):

```bash
if [ "$mode" != full ]; then exec sleep 100000; fi
```

`new_string`:

```bash
# 2b. (부팅 B, TC-M1) 틀린 비밀번호를 tars-config로 고친다. wpa_supplicant가 그 망을 잠시 쉬는
# 것(TEMP-DISABLED)을 본 뒤에 고친다 — 체인은 이 줄 앞의 로그에서 "연결이 안 섰다"를 본다.
# 비밀번호는 표준 입력으로 준다(사람은 tty에서 echo 없이 친다). 파일에는 평문(#psk)이 안 남고
# 해시된 psk 한 줄과 0600이 남아야 한다. 그다음은 그 명령이 말한 대로 재시작이다.
if [ "$mode" = ap-only ]; then
  for i in $(seq 1 120); do
    wpa_cli -p /run/wpa_supplicant -i wlan0 list_networks 2>/dev/null | grep -q TEMP-DISABLED && break
    sleep 0.5
  done
  say "wrong key seen [$(wpa_cli -p /run/wpa_supplicant -i wlan0 list_networks 2>/dev/null | grep -o TEMP-DISABLED)]"
  say "tc [$(printf 'tars-secret\n' | tars-config wifi tars-wl 2>&1 | tr '\n' '|')]"
  f=/config/wpa_supplicant.conf
  say "tc file [$(grep -cF '#psk' $f) $(grep -cE '^[[:space:]]*psk=[0-9a-f]{64}$' $f) $(grep -cF 'ssid="tars-wl"' $f) $(grep -c '^country=KR$' $f) $(stat -c %a $f)]"
  say "restart: $(tars-service restart wpa_supplicant 2>&1 | tail -n 1)"
  exec sleep 100000
fi
if [ "$mode" != full ]; then exec sleep 100000; fi
```

`wifi/check.sh`:

E1 — `old_string`(기준 파일 16줄부터):

```bash
#   부팅 B  radios=2 · 틀린 비밀번호. 연결이 안 서고 부팅은 끝난다
```

`new_string`:

```bash
#   부팅 B  radios=2 · 틀린 비밀번호. 연결이 안 서고 부팅은 끝난다. 그 뒤에 프로브가
#           tars-config wifi로 비밀번호를 고치고 재시작하면 붙는다(TC-M1)
```

E2 — `old_string`(기준 파일 278줄부터):

```bash
for bad in 'CTRL-EVENT-CONNECTED' 'wlan0: leased'; do
  if grep -a "$bad" "$LOG" >/dev/null; then
```

`new_string`:

```bash
# TC-M1부터 이 부팅의 뒤쪽에서 프로브가 비밀번호를 고친다. "연결이 안 섰다"는 그 앞의 로그로만
# 본다 — 고친 줄(`wifi-ap: tc [`)이 찍히기 전까지다.
wait_for_log 'wifi-ap: tc \[' 90 || report_failure "the probe never ran tars-config wifi"
FIX_LINE="$(grep -an 'wifi-ap: tc \[' "$LOG" | head -n 1 | cut -d: -f1)"
for bad in 'CTRL-EVENT-CONNECTED' 'wlan0: leased'; do
  if head -n "$FIX_LINE" "$LOG" | grep -a "$bad" >/dev/null; then
```

E3 — `old_string`(기준 파일 283줄부터):

```bash
echo "a wrong passphrase is refused, no address, and the boot still ends at a prompt"
```

`new_string`:

```bash
echo "a wrong passphrase is refused, no address, and the boot still ends at a prompt"

# ── 검사 12: tars-config wifi가 고친 비밀번호로 붙는다 (TC-M1) ────────────
# 사람이 `wpa_passphrase … > /config/wpa_supplicant.conf`로 하던 일이다. 그 명령은 같은 SSID의
# 덩어리를 wpa_passphrase가 지은 것으로 바꾸고(평문 #psk 줄은 버린다), 파일이 이미 있었으니
# 재부팅이 아니라 재시작을 말한다. 프로브가 그 말대로 재시작하면 연결이 서고 주소가 온다.
grep -aF 'wifi-ap: tc [wifi: tars-wl replaced in /config/wpa_supplicant.conf|apply now: tars-service restart wpa_supplicant|]' "$LOG" >/dev/null \
  || report_failure "tars-config wifi did not replace the tars-wl block and point at a restart"
# 차례로 #psk 줄 0 · 64자리 psk 줄 1 · 그 SSID 1 · 사람의 country 줄 1 · 모드 600.
grep -aF 'wifi-ap: tc file [0 1 1 1 600]' "$LOG" >/dev/null \
  || report_failure "the file tars-config wrote is not one hashed block with the country kept and mode 600"
wait_for_log 'wlan0: CTRL-EVENT-CONNECTED - Connection to .* completed' 60 \
  || report_failure "wlan0 never connected after tars-config fixed the passphrase"
wait_for_log 'wlan0: leased 192\.168\.77\.[0-9]+ ' 60 \
  || report_failure "dhcpcd never leased an address after the fix"
echo "tars-config wifi replaced the wrong passphrase, and the restart it asked for brought wlan0 up with an address"
```

```bash
for f in dictation/probe.sh dictation/check.sh service/check.sh firewall/check.sh wifi/ap.sh wifi/check.sh; do
  cmp $f /tmp/run/tc1/new/$f && echo "SAME $f"; done
for f in dictation/probe.sh dictation/check.sh service/check.sh firewall/check.sh wifi/check.sh; do bash -n $f || echo "SYNTAX $f"; done
sh -n wifi/ap.sh || echo "SYNTAX wifi/ap.sh"
for c in dictation service firewall wifi; do
  bash -c 'source <(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic()/,/^}/p" check.sh)
    require_build_steps ./'$c'/check.sh && require_no_early_exit_pipe ./'$c'/check.sh &&
    require_explicit_nic ./'$c'/check.sh && echo "ENTRY-OK '$c'"'; done
```

기대: `SAME` 여섯, `SYNTAX` 없음, `ENTRY-OK` 넷.

## Task 3: 체인 다섯

확정 4 · 5 · 6. 한 컨테이너에서 차례로, 10분 남짓이다. `run_in_background`로 돌리고 기다린다(위의 lock 주의 — 기다림은 앞에서 끝낸다).

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -v /tmp/run/tc1/impl:/impl -w /workspace tars-devcontainer bash -c '
  for c in dictation service firewall wifi config; do s=$(date +%s); bash $c/check.sh > /impl/chain_$c.log 2>&1
    echo "$c exit=$? $(( $(date +%s) - s ))s"; done' > /tmp/run/tc1/impl/chains.out 2>&1
rmdir /tmp/run/docker.lock
cat /tmp/run/tc1/impl/chains.out
rg -a '^tars-config|^FAIL' /tmp/run/tc1/impl/chain_*.log
```

기대: 다섯 다 `exit=0`, 그리고 이 넷(파일마다 하나).

```
chain_dictation.log: tars-config wrote groq.key (0600) and two dictation.conf lines, refused an unknown key, and the next tars-dictate used both
chain_firewall.log: tars-config opened 7072 in its own file and nft put it up without a reboot
chain_service.log: tars-config added a key sshd took at the next login, refused a duplicate and a non-key, and unlinked and relinked sshd
chain_wifi.log: tars-config wifi replaced the wrong passphrase, and the restart it asked for brought wlan0 up with an address
```

빨개지면 `FAIL` 줄과 그 체인의 표식 · 마지막 줄들을 그대로 보고한다.

## Task 4: mutation

확정 7의 표다. 사본은 `/tmp/run/tc1/impl/mut/`에 만든다.

```bash
python3 /tmp/run/tc1/make_mut.py "$PWD" /tmp/run/tc1/impl/mut
M=/tmp/run/tc1/impl/mut
for p in fe_m1.zig:init/src/config_front_edit.zig fr_m2.zig:init/src/config_front.zig fr_m3.zig:init/src/config_front.zig \
  fr_m4.zig:init/src/config_front.zig fe_m5.zig:init/src/config_front_edit.zig; do
  echo "${p%%:*} $(diff ${p#*:} $M/${p%%:*} | rg -c '^[<>]')"; done
```

기대: `mutation copies: 5`와 다섯 다 `2`.

`make_mut.py`:

```python
"""TC-M1 plan Task 4의 mutation 사본을 만든다.

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


FE = 'init/src/config_front_edit.zig'
FR = 'init/src/config_front.zig'
# mutation 1 — 무선: 같은 SSID의 덩어리를 못 찾는다(늘 끝에 더한다). 틀린 덩어리가 앞에 남는다
make(FE, 'fe_m1.zig', '        } else if (std.mem.eql(u8, t, want)) {\n            matched = true;',
     '        } else if (std.mem.eql(u8, t, want) and t.len == 0) {\n            matched = true;')
# mutation 2 — ssh 키: ssh-keygen의 판정을 안 본다(키가 아닌 줄도 쓴다)
make(FR, 'fr_m2.zig', '    if (ran.code != 0) {\n        complain("ssh-keygen does not read this',
     '    if (false) {\n        complain("ssh-keygen does not read this')
# mutation 3 — 방화벽: 쓰기만 하고 nft를 안 돈다(재부팅을 기다린다)
make(FR, 'fr_m3.zig', '    if (c.firewall != .on) {\n        say("firewall=off: nothing',
     '    if (c.firewall == c.firewall) {\n        say("firewall=off: nothing')
# mutation 4 — 받아쓰기: set이 파일을 안 갈아 끼운다
make(FR, 'fr_m4.zig', '    if (!replace(DICT_PATH, DICT_TEMP, text, 0o644)) return cli.EXIT_IO;',
     '    _ = &text;')
# mutation 5 — 받아쓰기 키 이름 하나가 tars-dictate와 어긋난다
make(FE, 'fe_m5.zig', '"cleanup_timeout",\n', '"cleanup_wait",\n')
print('mutation copies:', len(os.listdir(out)))
```

`run_mut.sh` — 사본을 저장소 경로 위에 읽기 전용으로 덮어 그 체인 한 판을 돈다. 첫 줄 `mounted:`가 두 Zig 파일의 md5 앞 여덟 자리다 — 덮지
않은 판은 `0beb185c 6ea5154e`다.

```bash
#!/bin/bash
# TC-M1 plan Task 4의 mutation 한 판을 돈다.
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
  echo \"mounted: \$(md5sum init/src/config_front.zig init/src/config_front_edit.zig | cut -c1-8 | tr '\n' ' ')\"
  bash $chain/check.sh > /tmp/m.log 2>&1; echo \"exit=\$?\"; cp /tmp/m.log /workspace/.mut_$name.log" 
rmdir /tmp/run/docker.lock
mv "$repo/.mut_$name.log" "$mut/$name.log"
echo "== $name ($chain) $(( $(date +%s) - s ))s"
grep -a '^FAIL' "$mut/$name.log" | head -2
echo "last line: $(tail -n 1 "$mut/$name.log")"
```

```bash
R="$PWD"; I=tars-devcontainer; M=/tmp/run/tc1/impl/mut; X=/tmp/run/tc1/run_mut.sh
{ $X $R $I $M m1 wifi fe_m1.zig:init/src/config_front_edit.zig
  $X $R $I $M m2 service fr_m2.zig:init/src/config_front.zig
  $X $R $I $M m3 firewall fr_m3.zig:init/src/config_front.zig
  $X $R $I $M m4 dictation fr_m4.zig:init/src/config_front.zig
  $X $R $I $M m5 service fe_m5.zig:init/src/config_front_edit.zig
  $X $R $I $M back firewall; } > $M/run.out 2>&1
cat $M/run.out
git status --short
```

기대는 확정 7의 표에서 그 판의 `FAIL` 줄이고 `back`은 `last line: FW chain PASS`다(망가진 `tars-config`를 다시 짓는다). `git status`는 `M` 여덟과
`??` 셋이다. 예상과 다른 자리에서 죽거나 초록이면 그대로 적어 보고한다.

보고 — `git diff --stat`(전체)과 `git diff | rg '^-'`(전체), Task 0 ~ 4의 출력 전부, plan과 다른 글자.

## Task 5: lead가 하는 것

1. 보고를 받아 diff를 직접 읽고, 열한 파일을 `/tmp/run/tc1/new/`와 `cmp`한다.
2. 루트 게이트 2회, 스물한 체인 × 2다. `rg -c 'PASS: 2/2' /tmp/gate_tc1.log`가 21이어야 한다.

   ```bash
   { time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/gate_tc1.log 2>&1 ; echo "exit=$?" ; } 2> /tmp/gate_tc1.time
   ```
3. 실측 절 채우기, design `Status:`.
4. commit. 넣는 것은 열한 파일과 이 plan이고 design이 바뀌었으면 함께 넣는다.
5. 실기. 사용자가 노트북에서 칠 것 — `tars-config wifi '집 와이파이' --country KR`(tty에서 echo 없이 묻는 길은 게이트가 못 본다), `tars-config ssh on` ·
   `ssh-key add` · 재부팅, `tars-config dictation key`. running-tars.md의 무선 · ssh · 방화벽 · 받아쓰기 절은 서브프로젝트를 닫을 때 이 명령으로 고쳐 쓴다.

## design과 다르게 적은 것

design 본문(결정 12 ~ 17)은 이 plan과 같은 날 같은 사람이 썼으므로 어긋난 자리가 없다. 구현 뒤에 lead가 고칠 것 — `Status:`, 그리고 확정 5의
시간이 루트 게이트에서 다르면 실측 절에.

## 이 milestone에서 안 하는 것

- `reload`(M2). 무선의 재시작 · sshd 링크의 재부팅은 말하기만 한다(design 비목표 11).
- 지우기 — ssh 키 · 무선 망(비목표 9). 방화벽 `deny`는 이 명령이 연 줄만 닫는다.
- 열린 망 · WPA-EAP(비목표 10), IPv6 규칙(비목표 12).
- running-tars.md · lessons · 기억(서브프로젝트를 닫을 때 lead가).

## TC-M1이 실측한 것

lead가 2026-10-07에 쟀다. 구현자(Sonnet)의 보고와 파일을 lead가 직접 대조했다 — 열한 파일 전부 사본(`/tmp/run/tc1/new/`)과 `cmp`가
같았고, 지운 22줄은 plan이 말한 것뿐이었다(`config_cli.zig`의 도우미 열한 줄이 `pub`으로 · dictation 체인의 요청 수 19 판정 · wifi 체인의
옛 음성 한 줄 · 주석).

1. 구현자의 체인. `zig build test` 초록(`config_front_edit_test` 네 줄, 그중 하나가 "the 8 dictation keys are tars-dictate's own, read from
   its case"). dictation 94초(plan의 사본 값 158초 — 시간뿐) · service 73초 · firewall 51초 · wifi 122초 · config 172초. mutation 다섯 전부 plan의
   표와 같은 자리에서 잡혔다 — m4(받아쓰기 `set`이 안 씀)만 겨냥한 검사 30보다 앞의 검사 29가 먼저 잡았다(s22가 s21의 설정으로 돌아 정리 요청이
   11이 된다).
2. 루트 게이트 두 번 — 56분 36초 · 56분 42초, 둘 다 21체인 `PASS: 2/2`, 빨간 줄 0. M0 때(56:01 · 55:52)보다 40초쯤 늘었다 — planner가 본
   "회차당 30초 남짓"과 맞는다(체인 넷에 검사 하나씩).
3. 크기. `tars-config` 3,667,792바이트(M0 3,417,176 — 앞문 넷이 250KB), `init` 3,843,696(변함없음), initrd 98,067,012바이트.
4. 게이트가 본 M1 줄 — wifi 부팅 B `tars-config wifi replaced the wrong passphrase, and the restart it asked for brought wlan0 up with an address`,
   service 부팅 D의 검사 27(ssh-key add → 곧바로 로그인 · 600 · 중복 거절 · 가짜 키 거절 · list · ssh off/on), firewall 부팅 A의 검사 18(닫혀 있던
   7072가 `firewall allow 7072` 뒤 재부팅 없이 열린다), dictation 검사 30(다음 `tars-dictate`가 `dictation key` · `set`으로 쓴 키와 주소를 싣고 왔다).
5. M2가 바꿀 것. M1의 끝 줄 셋(`ssh on|off` · 처음 만든 무선 파일 · sshd가 꺼진 채 더한 키)이 지금은 재부팅 또는 재시작을 말한다. reload design
   결정 11(`services.d` 다시 읽기)이 들어가면 그 셋이 `tars-config reload`를 가리키게 된다 — M2 plan의 편집이다.
