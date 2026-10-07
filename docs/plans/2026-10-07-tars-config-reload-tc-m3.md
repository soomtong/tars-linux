# TC-M3 — `tars-config reload terminal`이 화면을 init이 지금 쓰는 값으로 다시 띄운다

Date: 2026-10-07
Design: `docs/specs/2026-10-07-tars-config-reload-design.md`(TC-M3 절과 그 덧붙임)
Status: 끝났다(2026-10-07). 구현은 Sonnet 서브에이전트가 Task 0 ~ 4와 5b · 5c를 글자 그대로 넣었고(plan 코드를 고친 곳 0), 루트 게이트 완주 통과가 둘(59:20 · 59:17)이며 그 사이의 빨감 셋은 전부 게이트 쪽의 간헐이었다. 값은 맨 아래 "TC-M3이 실측한 것".

## 누가 무엇을 하나

reload design 결정 10. Task 0 ~ 4는 구현 서브에이전트가 main 작업 트리에서 직접 편집하고 돌린다. Task 5(루트 게이트 2회 · 실측 절 · commit)는
lead(Fable)가 한다. 구현자는 commit하지 않고, 끝에 `git diff --stat` · `git diff | rg '^-'` · 각 Task의 명령 출력을 그대로 보고한다. 이 plan의
"확정한 것" 절과 "실측한 것" 절은 구현자가 고치지 않는다.

권하는 모델은 Sonnet이다. 새 파일이 없고, 고치는 파일 여덟의 편집 스물은 `old_string` · `new_string`이며, 각 Task 끝의 `cmp`가 사본과 바이트까지
같은지를 본다. M0 ~ M2가 같은 방식이었고 plan 코드를 고친 곳이 없었다.

Opus로 올리는 조건 — M2와 같은 셋에 하나를 더한다. 아래 하나라도 보이면 구현자는 고치지 말고 멈춰 보고하고, lead가 Opus로 원인을 찾는다.

1. 어느 체인의 로그에든 `Attempted to kill init` · `Kernel panic` · `panic:`이 있다.
2. 루트 게이트에서 이 plan이 안 돌린 체인이 `started terminal` · `giving up on terminal` · `restarting terminal` · `sent SIGKILL`의 줄에서 빨갛다 —
   SIGKILL 시한의 대상을 고친 것(확정 2)의 그림자일 수 있다.
3. config 1차의 TC-M3 검사 셋 · pane 검사 16이 두 판 중 한 판만 빨갛다.
4. config 1차에서 `reload terminal` 뒤의 Ctrl+R 검사가 빨갛다 — 그 검사는 처음 뜬 화면이 아니라 다시 뜬 화면에서 돈다(확정 5).

이 plan의 코드는 저장소 밖 사본(`/tmp/run/tc3/repo/`)에 먼저 넣어 돌렸고, 아래의 `old_string` · `new_string`은 그 사본에서 기계로 뽑은 것이다
(`/tmp/run/tc3/render.py`). 기준은 HEAD `a582ce1`(TC-M2 commit `eed8556` 위)의 파일(`/tmp/run/tc3/base/`)이고 편집 뒤의 파일은
`/tmp/run/tc3/new/`다. 편집은 Edit 도구에 글자 그대로 넣고(또는 plan 본문에서 블록을 기계로 뽑아 넣고), 각 Task 끝에서 `new/`와 `cmp`한다.
다르면 편집이 빗나간 것이니 plan의 글자에 맞춰 고친다. plan의 글자와 `new/`가 서로 다르다고 보이면 고치지 말고 그 자리를 보고한다. 편집은 한 파일
안에서 E1부터 차례로 넣는다.

| 파일 | 무엇을 | 줄 |
|---|---|---|
| `init/src/control.zig` | 편집 둘 — `reload`가 이름 `terminal` 하나를 받는다 | +4 −2 |
| `init/src/control_test.zig` | 편집 둘 — 요청 셋, 첫 줄의 글자 | +4 −3 |
| `init/src/reload.zig` | 편집 하나 — 꼬리 글자 둘(`until tars-config reload terminal`), `screenLines` | +15 −2 |
| `init/src/reload_test.zig` | 편집 하나 — 꼬리 글자, `screenLines` 두 경우 | +11 −2 |
| `init/src/main.zig` | 편집 셋 — `answer`가 `reload terminal`을 보낸다, `Live.toggle` · argv 자리 상수 · `doReloadTerminal`, SIGKILL 시한의 대상 | +70 −2 |
| `init/src/config_cli.zig` | 편집 여섯 — USAGE, `askInit`이 이름을 받는다, `reloadInit(terminal)`, 보기의 screen 줄, `main`의 `reload terminal` | +27 −10 |
| `config/check.sh` | 편집 넷 — 키 배열 넷, M2 문구 둘, 1차의 TC-M3 검사 셋(Ctrl+R 앞) | +101 −2 |
| `pane/check.sh` | 편집 하나 — 부팅 B의 검사 16 | +28 |

`git diff --stat`은 8 files, +260 −23이다. Task 5b(수정 1 — 루트 게이트 뒤) 뒤에는 `gate_lib.sh` +19 −1 · `check.sh` +28이 더해져 10 files, +307 −24다. Task 5c(수정 2) 뒤에는 `wifi/check.sh` +11 −2 · `config/check.sh` +8이 더해져 11 files, +326 −26이다. 새 파일 · 커널 · Dockerfile · `make_initrd.sh` · terminal의 코드는 안 바뀐다. 새 체인 · 새 포트도 없다.

design의 `Status:` · `CLAUDE.md` · `MEMORY.md` · `docs/decisions/` · `docs/guides/` · `HANDOFF.md`는 구현자가 안 고친다.

모든 명령은 저장소 루트에서 친다. 서브에이전트의 Bash는 호출마다 작업 디렉터리가 돌아가므로 명령 앞에 `cd /Users/dp/Repository/tars-linux &&`를
붙인다. 빌드 · 체인은 언제나 컨테이너에서 한다. 구현자의 측정용 파일은 `/tmp/run/tc3/impl/` 아래에 둔다. `/tmp/run/tc3/` 바로 아래는 이 plan을
쓰며 만든 것이고 대조에 쓴다. 지우지 않는다.

Docker VM의 메모리가 4GB다. 컨테이너는 언제나 하나씩 돌린다. 모든 `docker run`을 아래로 감싼다. 명령이 실패해도 lock은 꼭 푼다.
`run_in_background`로 돌리는 명령이 lock을 기다리게 두지 않는다 — 기다림은 앞에서 끝낸다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run … ; rc=$?
rmdir /tmp/run/docker.lock
```

## 이 milestone이 끝나면

- `tars-config set keyboard=pc` · `tars-config reload` 뒤에 `tars-config reload terminal`을 치면 init이 terminal을 그 값으로 다시 띄운다. 패널 · 그 셸 ·
  클립보드 · copy mode가 전부 사라지고 패널 하나 · 새 셸로 돌아온다. 대기가 빈다.
- 대기가 없으면 아무것도 안 한다 — 화면이 사라지지 않는다.
- `reload`의 키 줄과 인자 없는 `tars-config`의 화면 줄이 "until the next boot" 대신 "until tars-config reload terminal"을 말한다.
- 콘솔 셸은 이 동사가 안 건드린다. M2의 `reload`가 바꾼 셸로 콘솔 셸이 다음에 뜰 때 뜬다(게이트가 본다).

출력(정본).

```
$ tars-config reload terminal
the screen restarts now — every pane, its shell and the clipboard go away
keyboard: apple -> pc
clipboard: shared -> pane
terminal: restarts; every pane, its shell and the clipboard are gone

$ tars-config reload terminal
nothing pending; the screen already uses what init uses

keyboard: apple -> pc (the screen keeps the old value until tars-config reload terminal)
# the screen keeps keyboard=apple clipboard=shared until tars-config reload terminal
```

첫 줄은 `tars-config`가 init에 보내기 전에 찍는다. 이 명령은 대개 그 화면 안의 셸에서 돌고, init이 terminal을 내리면 이 프로세스도 SIGHUP으로 같이
간다 — init의 답(둘째 줄부터)은 못 볼 수 있다.

시리얼에 남는 줄.

```
tars-init: reload terminal: pid 39, shell /usr/bin/fish keyboard=pc hangul=shin_pcs latin=qwerty toggles=hangul_key,shift_space,capslock_tap,lctrl_tap,esc_latin clipboard=pane
tars-init: terminal killed (pid 39, signal 15, lived 61s)
tars-init: restarting terminal on request
tars-init: started terminal (pid 212, /terminal)
terminal: keyboard=pc (swap_alt_meta=true)
terminal: clipboard scope=pane
```

## 착수 전에 확정한 것

2026-10-07에 이 plan을 쓰며 저장소 사본(`/tmp/run/tc3/repo/`, HEAD `a582ce1` — M2의 열일곱 파일이 `/tmp/run/tc2/new/` · `new3/`과 같은 것을 cmp로
봤다)과 이미지 `tars-devcontainer`로 쟀다. 측정 파일은 `/tmp/run/tc3/meas/`(체인 로그)와 `/tmp/run/tc3/mut/` · `mut2/`(mutation)에 있다. 저장소의
작업 트리는 reload design의 M3 덧붙임과 이 plan 말고는 한 글자도 안 바뀌었다.

1. 자리와 순서(design M3 절의 덧붙임 1 · 3). `doReloadTerminal`(main.zig)이 한다 — 대기가 없으면 끝, 있으면 `reload.screenLines`로 대기 키를 찍고,
   terminal argv의 1 셸 · 2 rc 플래그 · 3 키보드 · 5 한글 · 6 영문 · 7 전환 키(+`esc_latin`) · 8 클립보드를 `live.cfg`로 바꾸고(4 키보드 장치 경로는
   설정이 아니라 그대로 — 부팅에 capability로 찾았다), 탈출로를 부팅의 판정으로 다시 세우고, `live.screen = live.cfg`(대기가 빈다), `control.apply(.restart)`로
   `hold = .restart`를 둔 뒤 SIGTERM이다. 감독 루프가 거둘 때 요청한 죽음이라 빨리 죽음으로 안 세고 다음 바퀴가 새 argv로 띄운다. 전환 키의 글자는
   `Live.toggle` 한 벌이다 — execve가 argv를 복사하므로 떠 있는 terminal은 그 버퍼를 안 본다. 파일은 다시 안 읽는다 — `reload`가 읽은 값을 화면에
   준다.

2. 드러난 잠재 버그 — SIGKILL 시한의 `kill(-pid)`. CT-M1의 design 결정 4 규칙 3은 "SIGTERM을 무시한 서비스에게 유예 뒤 SIGKILL을 프로세스 그룹으로"였다
   (CT-M0 실측 5 — 리더에게만 보내면 자식이 고아로 남는다). 그것이 `supervise`의 `control.overdue` 갈래에 `kill(-c.pid, .KILL)`로 들어갔는데 그 갈래는
   서비스만이 아니라 모든 자식(terminal · 콘솔 셸)을 돈다. 그 전에는 문제가 안 됐다 — 시한(`kill_at`)을 세우는 것은 `control.apply`의 stop · restart뿐이고
   그것을 부르는 자리는 `answer`의 `findService` 뒤 하나라 서비스에만 시한이 섰다. TC-M3의 `reload terminal`이 비서비스에 `apply(.restart)`를 부르는
   첫 자리다. terminal은 setsid를 안 하므로(`spawn`의 `.terminal => {}`) 제 그룹이 없고, `kill(-pid)`는 ESRCH로 아무도 안 죽인다. 그래서 둘을 고쳤다
   — `doReloadTerminal`의 SIGTERM은 pid로, 시한의 SIGKILL은 서비스만 그룹이고 나머지는 pid로. 사본의 mutation이 그 둘을 따로 · 함께 되돌렸다(확정 7의
   1 · 1b) — SIGTERM만 그룹으로 되돌리면 3초 뒤의 SIGKILL이 pid로 가서 terminal이 결국 다시 떠 체인이 초록이고(209초, 깨끗한 판보다 17초 늦다), 둘 다 되돌리면 terminal이 안
   죽어 config 1차가 빨갛다. 고친 둘이 서로를 받친다.

3. PID 1의 패닉을 막는 근거(M2 plan 확정 2의 표를 M3의 새 자리에 대해). init은 ReleaseSafe이고 PID 1의 패닉은 커널 패닉이다.

   | 자리 | 무엇이 패닉이 될 수 있었나 | 어떻게 막았나 | 누가 보나 |
   |---|---|---|---|
   | `doReloadTerminal`의 칸 | `children[0]` | 머리에서 `children.len < SLOTS`면 `error:`로 돌아간다(M2의 `doReload`와 같다) | 체인 |
   | terminal argv의 자리 | `argv[1..8]` | 자리 상수 여섯(`TERM_*_SLOT`)이 `[9:null]`의 범위 안이고 컴파일 타임 인덱스다 — 범위 밖이면 컴파일 에러 | 컴파일 |
   | 전환 키의 글자 | `terminalToggles(&live.toggle)` | 버퍼가 `TOGGLE_ARG_MAX`이고 config.zig의 comptime 검사가 그 크기를 이미 못 박았다 | 컴파일 |
   | 대기 키의 답 | `screenLines`의 비트 · 버퍼 | M2의 `keyLines`와 같은 모양 — 비트는 컴파일 타임, 글자는 `control.Out` | `reload_test` |
   | 요청의 이름 | `req.name` | `.?`를 안 쓰고 `if (req.name != null)`로 가른다. 이름이 `terminal`이 아니면 `parseRequest`가 이미 거절했다 | `control_test` |
   | `resolveShell` · `configFlag` · `noConfigFlag` | — | 부팅이 같은 입력의 꼴(`Shell` enum)로 부르는 함수 그대로 | 체인 |
   | SIGKILL 시한 | `kill`의 인자 | 정수 부호만 바뀐다(`-c.pid` · `c.pid`) — 패닉 자리가 없다. 다만 틀리면 자식이 안 죽는다(확정 2) | mutation 1b |

4. 호스트 검사. `reload_test` 묶음 4에 `screenLines` 둘(대기 둘이 `keyboard: apple -> pc` · `timezone: UTC -> Asia/Seoul`, 대기가 없으면 0바이트)과
   바뀐 꼬리 글자, `control_test`에 `reload terminal` 받음 · `reload sshd` 거절. `control_test`의 첫 줄이 `requests — six verbs, config without a name,
   reload alone or with terminal, one name, nothing else`가 된다.

5. 게이트(design M3 덧붙임 4 · 5).

   | 체인 | 자리 | 친다 | 판정 |
   |---|---|---|---|
   | `config` 1차(fish) | TC-M2 검사 뒤가 아니라 Ctrl+R 검사 앞 | `tars-config reload terminal` | 시리얼에 둘째 `terminal: keyboard=pc (swap_alt_meta=true)`(30초 안), `restarting terminal on request`, `clipboard scope=pane` 하나 · `started terminal` 둘, init의 argv 줄 |
   | | | 한 번 더 `tars-config reload terminal` | `\| nothing pending; the screen already uses what init uses` · `started terminal`이 여전히 둘 |
   | | | `tars-config set shell=bash` · `reload` · `kill -9 $(pgrep -t ttyS0)` · `tars-config set shell=zsh` | `reload: console shell /usr/bin/bash` · `started console shell (pid N, /usr/bin/bash)` · `\| shell: bash -> zsh` |
   | `pane` 부팅 B(패널 둘, clipboard=pane) | 검사 15 뒤 | `set clipboard=shared` · `reload` · `reload terminal` | `\| clipboard: pane -> shared (the screen keeps` · `clipboard scope=shared` · `restarting terminal on request` · 배치 `ws=1/1 panes=1` · `spawned child pid` 하나 더 |

   사본에서 정한 셋.
   - 자리. 처음에는 TC-M3 검사를 1차의 맨 끝(Ctrl+R 검사 뒤)에 두었다 — 화면이 다시 뜨면 칠 것이 없다고 봐서다. 그랬더니 `reload terminal`의 키가 닫히는
     fzf picker로 새어 init에 아무 요청도 안 갔다(`FAIL(boot 1): no terminal came up with keyboard=pc after reload terminal`, 시리얼에 `reload terminal` 줄
     없음) — Ctrl+R 검사의 주석이 이미 경고한 그 창이다. 그래서 Ctrl+R 검사 앞으로 옮겼다. 새 화면의 fish도 같은 히스토리(`/config/xdg`)를 읽으므로
     Ctrl+R 검사는 다시 뜬 화면에서 그대로 섰다.
   - 콘솔 셸의 tty. 콘솔 셸은 `/dev/console`을 열고 TIOCSCTTY하는데 커널은 그 밑의 실제 tty(ttyS0)를 제어 터미널로 준다. `pgrep -t console`은 아무것도
     못 찾아 `kill -9`가 쓰는 법만 찍었다 — `-t ttyS0`이 콘솔 셸이다. 게스트에 `pkill`은 없다.
   - 판정 글자의 폭. pane 부팅 B의 오른쪽 패널은 화면의 반(77열 남짓)이라 `reload`의 키 줄(89글자)이 접힐 자리다 — 패턴을 앞부분(`clipboard: pane -> shared (the
     screen keeps`)으로 줄여 두었다. 사본의 판은 그 패턴으로 초록이었다.

   1차의 `keyboard=pc`는 이제 화면에 닿는다 — TC-M3 검사 뒤의 타이핑(셋)은 Alt · Meta가 맞바뀐 화면에서 치는데, 치는 것이 글자 · Shift · Ctrl뿐이라 안
   닿는다. 1차가 끝나면 파일은 `shell=zsh` 한 줄이다(TC-M3 검사의 끝이 되돌린다) — 2차부터 그대로다.

6. 체인과 시간. 사본에서 돌렸다.

   | 체인 | 시간(사본) | 왜 |
   |---|---|---|
   | `config` | 192초(데운 판) | TC-M3 검사 셋 · Ctrl+R이 다시 뜬 화면에서 |
   | `pane` | 51초 | 검사 16 |
   | `service` | 75초 | SIGKILL 시한(검사 23 — stubborn의 SIGKILL은 그룹 그대로) |
   | `boot` | 24초 | terminal이 셋 죽고 포기되는 수 |
   | `terminal` | 25초 | terminal의 재시작 줄 |
   | `power` | 50초 | 끄는 길 |

   루트 게이트에서 늘어나는 것은 config 1차의 타이핑 약 백오십 키와 화면 재시작 한 번(M2 Task 5b 뒤 사본의 config 176초보다 16초), pane 부팅 B의 타이핑 약 일흔 키와 재시작 한 번이다.

7. mutation. 여섯 가지를 일곱 판으로 돌렸다(`/tmp/run/tc3/make_mut.py` · `run_mut.sh`, 로그는 `/tmp/run/tc3/mut/` · `mut2/`).

   | mutation | 판 | 잡은 자리 | 마지막 줄 · `FAIL` | 시간 |
   |---|---|---|---|---|
   | 1 `doReloadTerminal`의 SIGTERM을 그룹으로 | `m1` | 안 잡힌다(기대) — 3초 뒤의 SIGKILL이 pid로 가서 terminal이 다시 뜬다 | `last line: PASS` | 209초 |
   | 1b 위에 더해 SIGKILL 시한도 그룹으로(TC-M3 전의 모양) | `m1b` | 1차의 `reload terminal` | `FAIL(boot 1): no terminal came up with keyboard=pc after reload terminal` · 마지막 줄 `tars-init: terminal outlived SIGTERM by 3s, sent SIGKILL to group 39` | 92초 |
   | 2 새 argv에 키보드를 안 넣는다 | `m2` | 1차의 `reload terminal` | `FAIL(boot 1): no terminal came up with keyboard=pc after reload terminal` | 91초 |
   | 3 다시 띄운 뒤 대기를 안 비운다 | `m3` | 1차의 둘째 `reload terminal` | `FAIL(boot 1): a second reload terminal did not say nothing was pending` | 89초 |
   | 4 `screenLines`가 대기 아닌 키도 찍는다 | `m4` | `reload_test`(부팅 전) | `FAIL: screenLines:` · `FAIL: config_test failed` | 18초 |
   | 5 `reload`가 `terminal` 밖의 이름도 받는다 | `m5` | `control_test`(부팅 전) | `FAIL: parseRequest("reload sshd") accepted, want rejected` | 19초 |
   | (되돌림) | `back` · pane | — | `last line: CB-M0 check PASS` | 68초 |

   읽을 것 둘.
   - `m1`과 `m1b`가 확정 2의 증거다. `m1b`의 마지막 줄이 그 버그의 모양 그대로다 — `sent SIGKILL to group 39`라고 찍고 아무도 안 죽었다. `m1`이 초록인
     것은 고친 둘 중 하나(시한의 SIGKILL을 pid로)가 다른 하나를 받쳤기 때문이고, 대가는 화면이 3초 늦게 다시 뜬 것이다(209초 · 깨끗한 판 192초).
   - config 체인은 `zig build test`를 부팅 앞에 돌리므로 `m4` · `m5`가 20초 안에 잡힌다(그 문구 `config_test failed`는 체인이 `zig build test` 전체에 붙이는 이름이다).
   - 표의 판 가운데 `m2` · `m3` · `m4` · `m5`는 `main.zig`의 주석 한 단락을 다듬기 전의 사본에서 지었다(코드는 같다). `m1` · `m1b`와 되돌림은 다듬은 뒤의
     사본이다.

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
   for f in init/src/control.zig init/src/control_test.zig init/src/reload.zig init/src/reload_test.zig init/src/main.zig init/src/config_cli.zig \
     config/check.sh pane/check.sh; do cmp $f /tmp/run/tc3/base/$f && echo "BASE $f"; done
   ls kernel/build/.tars-build-stamp kernel/build/arch/x86/boot/bzImage
   ```

   기대: `a582ce1`이 있고 그 위에 lead의 commit(이 plan · design 덧붙임)이 있을 수 있다. `BASE` 여덟. 커널 스탬프와 bzImage가 있다. 하나라도 다르면
   멈추고 보고한다.

## Task 1: `init/`

확정 1 ~ 4.

### 1-1. `control.zig` — 편집 둘

E1 — `old_string`(기준 파일 39줄부터):

```zig
/// reload design 결정 1). 둘은 이름을 안 받는다. 사람의 문은 `tars-config`이고 `tars-service`는
```

`new_string`:

```zig
/// reload design 결정 1). `config`는 이름을 안 받고 `reload`는 `terminal` 하나만 받는다(TC-M3). 사람의 문은 `tars-config`이고 `tars-service`는
```

E2 — `old_string`(기준 파일 67줄부터):

```zig
        if (verb == .config or verb == .reload) return null;
```

`new_string`:

```zig
        if (verb == .config) return null;
        // TC-M3. reload가 받는 이름은 `terminal` 하나다(화면을 새 argv로 다시 띄운다).
        if (verb == .reload and !std.mem.eql(u8, n, "terminal")) return null;
```

### 1-2. `control_test.zig` — 편집 둘

E1 — `old_string`(기준 파일 81줄부터):

```zig
    // TC-M2. 둘은 이름 없이만 받는다 — `reload terminal`은 TC-M3의 자리다.
    try expectParse("config", .config, null);
    try expectParse("reload", .reload, null);
    try expectParse("reload terminal", null, null);
```

`new_string`:

```zig
    // TC-M2 · M3. `config`는 이름 없이, `reload`는 이름 없이 또는 `terminal`로만 받는다.
    try expectParse("config", .config, null);
    try expectParse("reload", .reload, null);
    try expectParse("reload terminal", .reload, "terminal");
    try expectParse("reload sshd", null, null);
```

E2 — `old_string`(기준 파일 94줄부터):

```zig
    std.debug.print("control_test: requests — six verbs, config and reload without a name, one name, nothing else\n", .{});
```

`new_string`:

```zig
    std.debug.print("control_test: requests — six verbs, config without a name, reload alone or with terminal, one name, nothing else\n", .{});
```

### 1-3. `reload.zig` — 편집 하나

E1 — `old_string`(기준 파일 250줄부터):

```zig
        .next_spawn => "the next console shell, ssh login and service; the screen keeps the old value until the next boot",
        .terminal => "the screen keeps the old value until the next boot",
    };
```

`new_string`:

```zig
        .next_spawn => "the next console shell, ssh login and service; the screen keeps the old value until tars-config reload terminal",
        .terminal => "the screen keeps the old value until tars-config reload terminal",
    };
}

/// TC-M3. `reload terminal`의 답 — 화면이 대기 중이던 키마다 `key: 화면의 값 -> init의 값` 한 줄.
/// 이 줄들이 끝나면 대기가 빈다(`main.zig`가 `screen`을 `cfg`로 맞춘다).
pub fn screenLines(out: *Out, screen: config.Config, live: config.Config) void {
    const p = pending(live, screen);
    inline for (@typeInfo(config.Config).@"struct".fields, 0..) |f, i| {
        if (p.bits & (@as(u16, 1) << i) != 0) {
            var a: [VALUE_MAX]u8 = undefined;
            var b: [VALUE_MAX]u8 = undefined;
            out.print("{s}: {s} -> {s}\n", .{ f.name, text(f.type, @field(screen, f.name), &a), text(f.type, @field(live, f.name), &b) });
        }
    }
```

### 1-4. `reload_test.zig` — 편집 하나

E1 — `old_string`(기준 파일 78줄부터):

```zig
        "keyboard: apple -> pc (the screen keeps the old value until the next boot)\n" ++
        "net: off -> dhcp (now)\n" ++
        "timezone: UTC -> Asia/Seoul (the next console shell, ssh login and service; the screen keeps the old value until the next boot)\n",
        "keyLines");
```

`new_string`:

```zig
        "keyboard: apple -> pc (the screen keeps the old value until tars-config reload terminal)\n" ++
        "net: off -> dhcp (now)\n" ++
        "timezone: UTC -> Asia/Seoul (the next console shell, ssh login and service; the screen keeps the old value until tars-config reload terminal)\n",
        "keyLines");
    // TC-M3. reload terminal의 답 — 화면 쪽 키만, 화면의 값에서 init의 값으로.
    var sb: [512]u8 = undefined;
    var so = reload.Out{ .buf = &sb };
    reload.screenLines(&so, def, live);
    try expectText(so.bytes(), "keyboard: apple -> pc\ntimezone: UTC -> Asia/Seoul\n", "screenLines");
    var none_buf: [64]u8 = undefined;
    var no = reload.Out{ .buf = &none_buf };
    reload.screenLines(&no, live, live);
    if (no.len != 0) return fail("screenLines printed something with nothing pending", .{});
```

### 1-5. `main.zig` — 편집 셋

E1 `answer` · E2 `Live.toggle` · argv 자리 상수 · `doReloadTerminal` · E3 SIGKILL 시한의 대상.

E1 — `old_string`(기준 파일 485줄부터):

```zig
        doReload(children, live, out, now);
```

`new_string`:

```zig
        // TC-M3. 이름이 있으면 `terminal`이다(control.parseRequest가 그 하나만 받는다).
        if (req.name != null) {
            doReloadTerminal(children, live, out, now);
        } else {
            doReload(children, live, out, now);
        }
```

E2 — `old_string`(기준 파일 576줄부터):

```zig
    services: [services.MAX]services.Entry = undefined,
};
```

`new_string`:

```zig
    services: [services.MAX]services.Entry = undefined,
    /// TC-M3. `reload terminal`이 짓는 전환 키 목록(terminal argv의 7번). 부팅의 것은 `main()`의
    /// `terminal_toggle_buf`에 있고, 한 번 다시 띄우면 argv가 이 칸을 가리킨다. 한 벌로 되는 이유 —
    /// execve가 argv를 자식에게 복사하므로 떠 있는 terminal은 이 버퍼를 안 본다.
    toggle: [config.TOGGLE_ARG_MAX]u8 = undefined,
};

/// terminal argv의 자리(`children[0].argv`). 부팅의 argv 리터럴과 짝이다 — 어긋나면 `reload terminal`이
/// 엉뚱한 자리를 덮는다. 4번(키보드 장치 경로)은 설정이 아니라 안 건드린다.
const TERM_SHELL_SLOT: usize = 1;
const TERM_KEYBOARD_SLOT: usize = 3;
const TERM_HANGUL_SLOT: usize = 5;
const TERM_LATIN_SLOT: usize = 6;
const TERM_TOGGLES_SLOT: usize = 7;
const TERM_CLIPBOARD_SLOT: usize = 8;

/// TC-M3. `reload terminal` — 화면을 init이 지금 쓰는 값으로 다시 띄운다(reload design의 M3 절).
///
/// 순서 — argv를 먼저 다 바꾸고 그다음 terminal에 SIGTERM을 보낸다. 감독 루프가 거둘 때 `hold = .restart`라
/// 빨리 죽음으로 안 세고(CT 결정 4 규칙 2) 다음 바퀴가 새 argv로 띄운다. 한 스레드라 순서를 뒤집어도 반쯤
/// 바뀐 argv로 뜨는 일은 없지만, "바꾸고 죽인다"가 읽기에 맞다.
///
/// SIGTERM은 그룹이 아니라 terminal에게다 — terminal은 setsid를 안 하므로 제 그룹이 없다(`spawn`). 패널의
/// 셸은 terminal이 죽어 PTY가 닫히면 SIGHUP을 받는다(SL).
///
/// 탈출로(rc 플래그)는 부팅의 판정(`storage_mounted and shell_config == on`)으로 다시 세운다. 부팅에서
/// 이미 한 번 썼어도 다시 선다 — 사람이 rc를 고치고 화면을 다시 띄운 것으로 본다.
fn doReloadTerminal(children: []Child, live: *Live, out: *control.Out, now: isize) void {
    if (children.len < SLOTS) {
        out.print(control.ERROR_PREFIX ++ "the supervisor has {d} slots, want {d}\n", .{ children.len, SLOTS });
        return;
    }
    if (reload.pending(live.cfg, live.screen).empty()) {
        out.print("nothing pending; the screen already uses what init uses\n", .{});
        return;
    }
    reload.screenLines(out, live.screen, live.cfg);
    const new = live.cfg;
    const shell = resolveShell(new.shell);
    const term = &children[0];
    term.argv[TERM_SHELL_SLOT] = shell.path().ptr;
    term.argv[TERMINAL_FLAG_SLOT] = shell.configFlag(new.shell_config).ptr;
    term.argv[TERM_KEYBOARD_SLOT] = new.keyboard.arg().ptr;
    term.argv[TERM_HANGUL_SLOT] = new.hangul_layout.arg().ptr;
    term.argv[TERM_LATIN_SLOT] = new.latin_layout.arg().ptr;
    term.argv[TERM_TOGGLES_SLOT] = new.terminalToggles(&live.toggle).ptr;
    term.argv[TERM_CLIPBOARD_SLOT] = new.clipboard.arg().ptr;
    term.rescue = if (live.mounted and new.shell_config == .on)
        .{ .slot = TERMINAL_FLAG_SLOT, .flag = shell.noConfigFlag() }
    else
        null;
    live.screen = new;

    const pid = term.pid;
    const done = control.apply(.restart, term, now);
    if (done.signal) _ = linux.kill(pid, .TERM);
    out.print("terminal: restarts; every pane, its shell and the clipboard are gone\n", .{});
    var toggle_buf: [config.TOGGLE_ARG_MAX]u8 = undefined;
    std.debug.print("tars-init: reload terminal: pid {d}, shell {s} keyboard={s} hangul={s} latin={s} toggles={s} clipboard={s}\n", .{
        pid,                     shell.path(),       @tagName(new.keyboard),       @tagName(new.hangul_layout),
        @tagName(new.latin_layout), new.terminalToggles(&toggle_buf), @tagName(new.clipboard),
    });
}
```

E3 — `old_string`(기준 파일 818줄부터):

```zig
                _ = linux.kill(-c.pid, .KILL);
```

`new_string`:

```zig
                // 서비스는 제 그룹을 가진다(setsid). terminal은 아니다 — TC-M3의 `reload terminal`이 이
                // 길로 오는 첫 비서비스다. 그룹에 보내면 ESRCH로 아무도 안 죽는다.
                _ = linux.kill(if (c.kind == .service) -c.pid else c.pid, .KILL);
```

### 1-6. `config_cli.zig` — 편집 여섯

E1 — `old_string`(기준 파일 81줄부터):

```zig
    \\       tars-config reload              init rereads tars.conf and services.d now (TC-M2)
```

`new_string`:

```zig
    \\       tars-config reload              init rereads tars.conf and services.d now (TC-M2)
    \\       tars-config reload terminal     restart the screen with what init uses; every pane goes away (TC-M3)
```

E2 — `old_string`(기준 파일 215줄부터):

```zig
fn askInit(verb: control.Verb, buf: []u8, ms: i32) ?[]const u8 {
    var req_buf: [16]u8 = undefined;
    const req = control.formatRequest(&req_buf, verb, null) orelse return null;
```

`new_string`:

```zig
fn askInit(verb: control.Verb, name: ?[]const u8, buf: []u8, ms: i32) ?[]const u8 {
    var req_buf: [32]u8 = undefined;
    const req = control.formatRequest(&req_buf, verb, name) orelse return null;
```

E3 — `old_string`(기준 파일 240줄부터):

```zig
/// `tars-config reload`(reload design 결정 7). init의 답을 그대로 찍는다.
fn reloadInit() u8 {
    var buf: [control.REPLY_MAX]u8 = undefined;
    const r = askInit(.reload, &buf, RELOAD_MS) orelse {
```

`new_string`:

```zig
/// `tars-config reload [terminal]`(reload design 결정 7 · M3 절). init의 답을 그대로 찍는다.
///
/// `terminal`이면 먼저 init에게 대기가 있는지 묻는다(`config`의 `screen` 줄). 없으면 아무것도 안 보내고
/// 그렇게 말한다. 있으면 화면이 사라진다는 것을 먼저 찍고 보낸다 — 이 명령은 대개 그 화면 안의 셸에서
/// 돌고, init이 terminal을 죽이면 이 프로세스도 SIGHUP으로 같이 간다. 답이 못 올 수 있어서 경고가 앞이다.
fn reloadInit(terminal: bool) u8 {
    var buf: [control.REPLY_MAX]u8 = undefined;
    if (terminal) {
        const now = askInit(.config, null, &buf, ASK_MS) orelse {
            complain("init did not answer at {s}", .{control.PATH});
            return EXIT_IO;
        };
        if (screenLine(now) == null) {
            say("nothing pending; the screen already uses what init uses\n", .{});
            return EXIT_OK;
        }
        say("the screen restarts now — every pane, its shell and the clipboard go away\n", .{});
    }
    const r = askInit(.reload, if (terminal) "terminal" else null, &buf, RELOAD_MS) orelse {
```

E4 — `old_string`(기준 파일 274줄부터):

```zig
    const now = askInit(.config, &now_buf, ASK_MS);
```

`new_string`:

```zig
    const now = askInit(.config, null, &now_buf, ASK_MS);
```

E5 — `old_string`(기준 파일 285줄부터):

```zig
        say("# the screen keeps{s} until the next boot\n", .{sl});
```

`new_string`:

```zig
        say("# the screen keeps{s} until tars-config reload terminal\n", .{sl});
```

E6 — `old_string`(기준 파일 553줄부터):

```zig
        if (rest.len != 0) return usage();
        return reloadInit();
```

`new_string`:

```zig
        if (rest.len == 0) return reloadInit(false);
        if (rest.len == 1 and std.mem.eql(u8, std.mem.span(rest[0]), "terminal")) return reloadInit(true);
        return usage();
```

### 1-7. 확인

```bash
for f in init/src/control.zig init/src/control_test.zig init/src/reload.zig init/src/reload_test.zig init/src/main.zig init/src/config_cli.zig; do
  cmp $f /tmp/run/tc3/new/$f && echo "SAME $f"; done
mkdir -p /tmp/run/tc3/impl
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer bash -c '
  rm -rf zig-out .zig-cache
  zig build; echo "build exit=$?"
  zig build test > /tmp/t.log 2>&1; echo "test exit=$?"
  grep -a "^reload_test:\|^control_test: requests\|^PASS" /tmp/t.log; grep -a "^FAIL" /tmp/t.log | head'
rmdir /tmp/run/docker.lock
```

기대: `SAME` 여섯, `build exit=0`, `test exit=0`, `reload_test:` 여섯 줄 · `control_test: requests — six verbs, config without a name, reload alone or with
terminal, one name, nothing else` · `PASS` 여섯, `FAIL` 없음.

## Task 2: 체인 둘

확정 5.

`config/check.sh`:

E1 — `old_string`(기준 파일 120줄부터):

```bash
TC_RELOAD_KEYS=(t a r s minus c o n f i g spc r e l o a d ret)
```

`new_string`:

```bash
TC_RELOAD_KEYS=(t a r s minus c o n f i g spc r e l o a d ret)
# tars-config reload terminal (TC-M3)
TC_RELOAD_TERM_KEYS=(t a r s minus c o n f i g spc r e l o a d spc t e r m i n a l ret)
# tars-config set shell=bash · kill -9 $(pgrep -t ttyS0) · tars-config set shell=zsh (TC-M3)
TC_SET_BASH_KEYS=(t a r s minus c o n f i g spc s e t spc s h e l l equal b a s h ret)
TC_KILL_CONSOLE_KEYS=(k i l l spc minus 9 spc shift-4 shift-9 p g r e p spc minus t spc
                      t t y shift-s 0 shift-0 ret)
TC_SET_ZSH_KEYS=(t a r s minus c o n f i g spc s e t spc s h e l l equal z s h ret)
```

E2 — `old_string`(기준 파일 571줄부터):

```bash
  if ! wait_for_screen '\| keyboard: apple -> pc \(the screen keeps the old value until the next boot\)'; then
```

`new_string`:

```bash
  if ! wait_for_screen '\| keyboard: apple -> pc \(the screen keeps the old value until tars-config reload terminal\)'; then
```

E3 — `old_string`(기준 파일 581줄부터):

```bash
  if ! wait_for_screen '\| # the screen keeps keyboard=apple clipboard=shared until the next boot'; then
```

`new_string`:

```bash
  if ! wait_for_screen '\| # the screen keeps keyboard=apple clipboard=shared until tars-config reload terminal'; then
```

E4 — `old_string`(기준 파일 693줄부터):

```bash
  echo "boot 1: appended a marker line to the seeded /config/zshrc"
```

`new_string`:

```bash
  echo "boot 1: appended a marker line to the seeded /config/zshrc"


  # ── TC-M3: reload terminal이 대기를 비운다 ───────────────────────────────
  #
  # 위 TC-M2 검사가 남긴 대기 둘(keyboard=pc · clipboard=pane)을 화면에 내린다. 아래 Ctrl+R 검사보다 앞이다 —
  # 그 검사는 이 훅의 마지막이어야 하고(picker를 닫은 직후의 키가 fzf로 샌다), 처음 이 자리를 그 뒤에 두었더니
  # `tars-config reload terminal`의 키가 닫히는 picker로 새어 아무 일도 안 일어났다(TC-M3 plan 확정 5). 새 화면의
  # fish도 같은 히스토리(/config/xdg)를 읽으므로 Ctrl+R 검사는 새 화면에서 그대로 선다. 판정은 시리얼이다.
  # terminal이 뜰 때마다 찍는 `terminal: keyboard=` · `clipboard scope=` 줄이 둘째로 나오고 그 값이 pc ·
  # pane이면 새 argv로 떴다. 그 사이에 `restarting terminal on request`가 있어야 빨리 죽음이 아니다.
  # 파일은 위 EDIT_KEYS가 이미 `shell=zsh` 한 줄로 덮었다 — reload terminal은 파일을 다시 안 읽고 init이
  # 지금 쓰는 값(위 reload가 읽은 것)을 화면에 준다. 그래서 셸은 그대로 fish다.
  type_keys "${TC_RELOAD_TERM_KEYS[@]}"
  local tries=0
  until grep -aq 'terminal: keyboard=pc (swap_alt_meta=true)' "$log"; do
    tries=$((tries + 1))
    if [ "$tries" -gt 60 ]; then
      echo "FAIL(boot 1): no terminal came up with keyboard=pc after reload terminal"
      grep -a 'tars-init: reload terminal\|restarting terminal\|started terminal\|terminal: keyboard=' "$log" | tail -6
      return 1
    fi
    sleep 0.5
  done
  if ! grep -aq 'tars-init: restarting terminal on request' "$log"; then
    echo "FAIL(boot 1): the terminal came back without init saying it restarted it on request"
    return 1
  fi
  if [ "$(grep -ac 'terminal: clipboard scope=pane' "$log")" != "1" ] || [ "$(grep -ac 'tars-init: started terminal' "$log")" != "2" ]; then
    echo "FAIL(boot 1): want one 'clipboard scope=pane' and two 'started terminal' lines after reload terminal"
    grep -a 'terminal: clipboard scope=\|tars-init: started terminal' "$log"
    return 1
  fi
  if ! grep -aq 'tars-init: reload terminal: pid [0-9]*, shell /usr/bin/fish keyboard=pc' "$log"; then
    echo "FAIL(boot 1): init did not log the argv it gave the new terminal"
    return 1
  fi
  echo "boot 1: reload terminal brought the screen up again with keyboard=pc and clipboard=pane"

  # 대기가 비었는가 — 한 번 더 치면 아무것도 안 보내고 그렇게 말한다(화면이 또 사라지면 안 된다).
  sleep 2
  type_keys "${TC_RELOAD_TERM_KEYS[@]}"
  if ! wait_for_screen '\| nothing pending; the screen already uses what init uses'; then
    echo "FAIL(boot 1): a second reload terminal did not say nothing was pending"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  if [ "$(grep -ac 'tars-init: started terminal' "$log")" != "2" ]; then
    echo "FAIL(boot 1): the second reload terminal restarted the screen again"
    return 1
  fi
  echo "boot 1: a second reload terminal found nothing pending and left the screen alone"

  # ── TC-M3: 콘솔 셸은 다음에 뜰 때 새 셸이다 ─────────────────────────────
  #
  # shell은 "다음에 뜰 때부터"의 키다(reload design 결정 2). reload가 콘솔 셸 칸의 argv를 bash로 바꾸고,
  # 사람이 그 셸을 끝내면 감독 루프가 그 칸의 새 argv로 띄운다. 이 체인은 콘솔에 칠 수 없으므로(시리얼이
  # 쓰기 전용 파일) 화면의 셸에서 콘솔 셸을 죽인다. 콘솔 셸은 /dev/console을 열고 TIOCSCTTY하는데 커널은 그
  # 밑의 실제 tty를 제어 터미널로 준다 — `pgrep -t console`은 아무것도 못 찾고 `-t ttyS0`이 콘솔 셸이다(TC-M3
  # plan 확정 5). 대화형 셸은 SIGTERM을 무시하므로 9다. 끝으로 파일을 shell=zsh로 되돌린다 — 2차가 그 한 줄을 읽는다.
  #
  # 새 화면의 셸 프롬프트를 기다리지 않는다. type_keys가 키마다 로그가 자라기를 기다리고, 새 terminal의
  # 첫 프레임은 위 keyboard=pc 줄보다 뒤다.
  type_keys "${TC_SET_BASH_KEYS[@]}"
  type_keys "${TC_RELOAD_KEYS[@]}"
  tries=0
  until grep -aq 'tars-init: reload: console shell /usr/bin/bash' "$log"; do
    tries=$((tries + 1))
    if [ "$tries" -gt 40 ]; then
      echo "FAIL(boot 1): reload with shell=bash did not set the console shell's next argv"
      grep -a 'tars-init: reload' "$log" | tail -4
      return 1
    fi
    sleep 0.5
  done
  type_keys "${TC_KILL_CONSOLE_KEYS[@]}"
  tries=0
  until grep -aqE 'tars-init: started console shell \(pid [0-9]+, /usr/bin/bash\)' "$log"; do
    tries=$((tries + 1))
    if [ "$tries" -gt 40 ]; then
      echo "FAIL(boot 1): the console shell did not come back as bash after it was killed"
      grep -a 'console shell' "$log" | tail -4
      return 1
    fi
    sleep 0.5
  done
  type_keys "${TC_SET_ZSH_KEYS[@]}"
  if ! wait_for_screen '\| shell: bash -> zsh'; then
    echo "FAIL(boot 1): could not put shell=zsh back for the second boot"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 1: after reload with shell=bash, the killed console shell came back as bash"
```

`pane/check.sh`:

E1 — `old_string`(기준 파일 782줄부터):

```bash
# NUL 바이트를 한 번의 읽기로 센다. 부팅 A의 검사처럼 크기를 두 번 재면
```

`new_string`:

```bash
# ── 검사 16: reload terminal은 화면을 새 값으로 다시 띄우고 패널은 하나로 돌아온다 (TC-M3) ──
#
# 사람이 clipboard를 shared로 되돌리고 reload한다 — 화면 쪽 키라 init의 값만 바뀌고 대기가 된다. 그다음
# reload terminal이면 init이 terminal을 새 argv로 다시 띄운다. 판정 셋 — 새 terminal이 scope=shared를 찍고,
# 배치가 패널 둘에서 `ws=1/1 panes=1`로 돌아오고, 부팅의 첫 셸만 찍는 `spawned child pid`가 하나 는다(새
# terminal의 첫 셸이다). 클립보드가 사라지는 것은 따로 안 본다 — terminal 프로세스의 메모리였다(CB).
echo "=== boot B: tars-config reload terminal ==="
SPAWNS_BEFORE="$(spawn_lines)"
type_keys t a r s minus c o n f i g spc s e t spc c l i p b o a r d equal s h a r e d ret
type_keys t a r s minus c o n f i g spc r e l o a d ret
wait_for_last_screen '\| clipboard: pane -> shared \(the screen keeps' ||
  report_failure "boot B: reload did not leave clipboard=shared waiting for the screen"
type_keys t a r s minus c o n f i g spc r e l o a d spc t e r m i n a l ret
RESTARTED=0
for _ in $(seq 1 60); do
  if grep -aqF 'terminal: clipboard scope=shared' "$LOG"; then RESTARTED=1; break; fi
  sleep 0.5
done
[ "$RESTARTED" = "1" ] || report_failure "boot B: no terminal came up with clipboard scope=shared after reload terminal"
grep -aqF 'tars-init: restarting terminal on request' "$LOG" ||
  report_failure "boot B: the terminal came back without init restarting it on request"
wait_for_pane 'ws=1/1 panes=1 focus=0 rect=0,0 ' ||
  report_failure "boot B: after reload terminal the layout is '$(last_pane_line)', want one pane"
for _ in $(seq 1 60); do [ "$(spawn_lines)" -gt "$SPAWNS_BEFORE" ] && break; sleep 0.5; done
[ "$(spawn_lines)" -eq $((SPAWNS_BEFORE + 1)) ] ||
  report_failure "boot B: spawned child pid ${SPAWNS_BEFORE} -> $(spawn_lines), want one more (the new terminal's first shell)"
echo "boot B: reload terminal brought the screen back with clipboard=shared and one pane"

# NUL 바이트를 한 번의 읽기로 센다. 부팅 A의 검사처럼 크기를 두 번 재면
```

```bash
for f in config/check.sh pane/check.sh; do cmp $f /tmp/run/tc3/new/$f && echo "SAME $f"; bash -n $f || echo "SYNTAX $f"; done
```

기대: `SAME` 둘, `SYNTAX` 없음.

## Task 3: 체인 여섯

확정 6. 한 컨테이너에서 차례로, 7분 남짓이다. `run_in_background`로 돌린다(lock은 앞에서 잡는다).

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -v /tmp/run/tc3/impl:/impl -w /workspace tars-devcontainer bash -c '
  for c in config pane service boot terminal power; do s=$(date +%s); bash $c/check.sh > /impl/chain_$c.log 2>&1
    echo "$c exit=$? $(( $(date +%s) - s ))s"; done' > /tmp/run/tc3/impl/chains.out 2>&1
rmdir /tmp/run/docker.lock
cat /tmp/run/tc3/impl/chains.out
rg -a '^boot 1: (reload|a second|after reload|one Ctrl)|^boot B: reload|^FAIL|Attempted to kill init|panic' /tmp/run/tc3/impl/chain_*.log
```

기대: 여섯 다 `exit=0`, 그리고 이 여섯 줄, `FAIL` · `panic` 없음.

```
chain_config.log: boot 1: reload left keyboard=pc waiting for the screen, showed both values, and refused a file with shell=fsh
chain_config.log: boot 1: reload terminal brought the screen up again with keyboard=pc and clipboard=pane
chain_config.log: boot 1: a second reload terminal found nothing pending and left the screen alone
chain_config.log: boot 1: after reload with shell=bash, the killed console shell came back as bash
chain_config.log: boot 1: one Ctrl+R opened the fzf picker (the terminal answered its query)
chain_pane.log: boot B: reload terminal brought the screen back with clipboard=shared and one pane
```

## Task 4: mutation

확정 7의 표다. 사본은 `/tmp/run/tc3/impl/mut/`에 만든다.

```bash
python3 /tmp/run/tc3/make_mut.py "$PWD" /tmp/run/tc3/impl/mut
M=/tmp/run/tc3/impl/mut
for p in main_m1.zig:init/src/main.zig main_m1b.zig:init/src/main.zig main_m2.zig:init/src/main.zig main_m3.zig:init/src/main.zig \
  reload_m4.zig:init/src/reload.zig control_m5.zig:init/src/control.zig; do echo "${p%%:*} $(diff ${p#*:} $M/${p%%:*} | rg -c '^[<>]')"; done
```

기대: `mutation copies: 6`, 그리고 `main_m1.zig 2` · `main_m1b.zig 4` · `main_m2.zig 1` · `main_m3.zig 1` · `reload_m4.zig 2` · `control_m5.zig 1`.

`make_mut.py`:

```python
"""TC-M3 plan Task 4의 mutation 사본을 만든다.

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


M = 'init/src/main.zig'
# mutation 1 — terminal의 SIGTERM을 그룹으로 보낸다(서비스의 모양). terminal은 제 그룹이 없어 아무도 안 죽는다
make(M, 'main_m1.zig', '    if (done.signal) _ = linux.kill(pid, .TERM);\n    out.print("terminal: restarts;',
     '    if (done.signal) _ = linux.kill(-pid, .TERM);\n    out.print("terminal: restarts;')
# mutation 1b — 위에 더해 SIGKILL 시한도 그룹으로(TC-M3 전의 모양). 1만으로는 3초 뒤의 SIGKILL이 pid로 가서 terminal이
# 결국 다시 뜬다 — 둘을 함께 되돌려야 terminal이 안 죽는다
s1 = open(os.path.join(out, 'main_m1.zig')).read()
old = '                _ = linux.kill(if (c.kind == .service) -c.pid else c.pid, .KILL);'
assert s1.count(old) == 1
open(os.path.join(out, 'main_m1b.zig'), 'w').write(s1.replace(old, '                _ = linux.kill(-c.pid, .KILL);'))
# mutation 2 — 새 argv에 키보드를 안 넣는다(옛 값으로 다시 뜬다)
make(M, 'main_m2.zig', '    term.argv[TERM_KEYBOARD_SLOT] = new.keyboard.arg().ptr;\n', '')
# mutation 3 — 다시 띄운 뒤 대기를 안 비운다
make(M, 'main_m3.zig', '    live.screen = new;\n\n    const pid = term.pid;', '\n    const pid = term.pid;')
# mutation 4 — reload terminal의 답이 대기가 아닌 키까지 찍는다
make('init/src/reload.zig', 'reload_m4.zig',
     '    const p = pending(live, screen);\n    inline for (@typeInfo(config.Config).@"struct".fields, 0..) |f, i| {\n        if (p.bits & (@as(u16, 1) << i) != 0) {\n            var a: [VALUE_MAX]u8 = undefined;',
     '    const p = Keys{ .bits = 0xffff };\n    inline for (@typeInfo(config.Config).@"struct".fields, 0..) |f, i| {\n        if (p.bits & (@as(u16, 1) << i) != 0) {\n            var a: [VALUE_MAX]u8 = undefined;')
# mutation 5 — reload가 terminal 밖의 이름도 받는다
make('init/src/control.zig', 'control_m5.zig',
     '        if (verb == .reload and !std.mem.eql(u8, n, "terminal")) return null;\n', '')
print('mutation copies:', len(os.listdir(out)))
```

`run_mut.sh` — M2의 것과 같다. 첫 줄 `mounted:`가 `control.zig` · `main.zig` · `reload.zig`의 md5 앞 여덟 자리이고 덮지 않은 판은 `2981abee ef319226 9cd72cbb`다.

```bash
#!/bin/bash
# TC-M3 plan Task 4의 mutation 한 판을 돈다.
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
R="$PWD"; I=tars-devcontainer; M=/tmp/run/tc3/impl/mut; X=/tmp/run/tc3/run_mut.sh
{ $X $R $I $M m1 config main_m1.zig:init/src/main.zig
  $X $R $I $M m1b config main_m1b.zig:init/src/main.zig
  $X $R $I $M m2 config main_m2.zig:init/src/main.zig
  $X $R $I $M m3 config main_m3.zig:init/src/main.zig
  $X $R $I $M m4 config reload_m4.zig:init/src/reload.zig
  $X $R $I $M m5 config control_m5.zig:init/src/control.zig
  $X $R $I $M back pane; } > $M/run.out 2>&1
cat $M/run.out
git status --short
```

기대는 확정 7의 표다 — `m1`은 초록(`last line: PASS`)이 기대값이다(확정 2). `back`은 `last line: CB-M0 check PASS`다. `git status`는 `M` 여덟이다.

보고 — `git diff --stat`(전체)과 `git diff | rg '^-'`(전체), Task 0 ~ 4의 출력 전부, plan과 다른 글자.

## Task 5: lead가 하는 것

1. 보고를 받아 diff를 직접 읽고, 여덟 파일을 `/tmp/run/tc3/new/`와 `cmp`한다.
2. 루트 게이트 2회, 스물한 체인 × 2다. `rg -c 'PASS: 2/2' /tmp/gate_tc3.log`가 21이어야 하고 `rg -c 'Attempted to kill init' /tmp/gate_tc3.log`가 0이어야 한다.
3. 빨갛면 "누가 무엇을 하나"의 Opus 조건을 본다.
4. 실측 절, design `Status:`, commit(여덟 파일과 이 plan, design이 바뀌었으면 함께).
5. TC를 닫는다 — 아래 "닫을 때 lead가 고칠 자리".

## Task 5b: 수정 1 — `joined_screen_dump`가 init의 끼어든 줄도 잇는다

2026-10-07, Task 0 ~ 4를 넣고 lead의 루트 게이트를 돌린 뒤에 더했다. 1회차는 21체인 2/2(59분 20초) 초록이었고 2회차가 config(CP-M2) run 2/2의 7차
부팅에서 `FAIL(boot 7): the fzf integration never defined its history widget`으로 빨갰다(`/tmp/gate_tc3_2.log`). TC-M3의 검사(1차 셋 · pane 16)는 두
회차 다 초록이다 — 이 milestone의 코드와 무관하다.

원인은 게스트 시리얼(`/tmp/run/tc3/gate_2/tmp.AD81GFh5bD` 1153행)에 있다 — `whence -w fzf-history-widget`의 출력이 찍힌 screen> 줄 한가운데에 init의
줄이 끼었다.

```
terminal: screen> … | (none)# whence -w fzftars-init: audio: no sound card within 5000ms, the mixer is left alone
-history-widget | fzf-history-widget: function | (none)#
```

init의 fd 2가 /dev/console이라 terminal의 줄과 같은 UART에 쓴다. `gate_lib.sh`의 `joined_screen_dump`는 커널 printk(`[ 7.35] …`)가 자른 줄은 이어
붙이지만(AU-M2) `tars-init: ` 줄은 몰랐다. 그 dump가 그 부팅의 마지막 screen> dump라(화면이 더 안 바뀌었다) 한 번의 자름이 곧 30초 뒤의 FAIL이었다.
2회차에만 난 것은 audio 일꾼의 5,000ms 줄과 그 타이핑의 시각이 겹친 우연이다. 같은 2회차의 config 1차 시리얼(`tmp.RLRCcx21eQ`)에서도 `tars-init: reload of
/config/tars.conf`가 `nothing pending …` 줄을 같은 모양으로 잘랐다 — 그쪽은 뒤의 dump가 이어져 판정이 살았다.

고치는 것 둘. `joined_screen_dump`가 꼬리의 `tars-init: ` 조각을 떼고 다음 조각을 이어 붙이고(커널 줄과 같은 모양), 이을 차례에 오는 온전한
`tars-init: ` 줄은 건너뛴다. 그리고 루트 `check.sh`의 진입 검사에 `require_screen_dump_joins`를 더한다 — QEMU 없이 고정된 조각 넷(안 잘린 dump ·
printk가 자른 것 · init이 자른 것 · init의 조각과 온전한 한 줄이 함께 자른 것)이 전부 같은 한 줄이 되는지 본다.

접두사를 `tars-init: ` 하나로 좁혔다. 꼬리를 떼는 정규식은 줄 머리가 아니라 줄 한가운데의 접두사를 찾으므로, `[a-z-]+: `처럼 넓히면 화면 글자
(`fzf-history-widget: function`)를 끼어든 줄로 보고 떼어 버린다. 커널 줄은 시각 표식이라는 화면에 없을 모양이 있어 넓어도 됐고, init의 줄은 우리가 정한
고정 접두사다. 같은 UART의 다른 쓰기(dhcpcd · sshd · chronyd · 서비스의 표준 출력)가 같은 자름을 일으키면 그 고정 접두사를 하나씩 더한다(주석에 적었다).
대가 — 화면에 `tars-init: `가 그대로 보이는 줄(사람이 시리얼 로그를 grep한 화면)은 그 자리부터 꼬리가 떨어진다. 지금 그런 화면을 판정하는 체인은 없다.

기준은 HEAD `3f8598d`의 파일(TC-M3은 이 둘을 안 건드렸다, `/tmp/run/tc3b/base/`)이고 편집 뒤는 `/tmp/run/tc3b/new/`다 — `gate_lib.sh` +19 −1,
`check.sh` +28.

### 5b-0. 기준을 본다

```bash
for f in gate_lib.sh check.sh; do cmp $f /tmp/run/tc3b/base/$f && echo "BASE $f"; done
```

### 5b-1. `gate_lib.sh` — 편집 둘

P1 — `old_string`(지금 파일 125줄부터):

```bash
joined_screen_dump() {
  perl -ne '
    if (defined $cur) {
      next if /^\[ *\d+\.\d+\] /;
```

`new_string`:

```bash
#
# init의 줄도 같은 UART에 쓴다(TC-M3 Task 5b). init의 fd 2가 /dev/console이라
# `tars-init: …` 한 줄이 terminal의 줄 한가운데 끼어 같은 모양으로 자른다 — TC-M3
# 루트 게이트 2회차의 config 7차가 `whence -w fzf` 뒤에 `tars-init: audio: no sound
# card within 5000ms …`가 끼어 `-history-widget | fzf-history-widget: function`이
# 머리 없는 다음 줄로 갔다. 그래서 꼬리의 `tars-init: ` 조각도 떼고 잇고, 이을
# 차례에 오는 온전한 `tars-init: ` 줄은 커널 줄처럼 건너뛴다.
#
# 접두사를 `tars-init: ` 하나로 좁힌 이유. 꼬리를 떼는 정규식은 줄 머리가 아니라
# 줄 한가운데의 접두사를 찾는다 — `[a-z-]+: `처럼 넓히면 화면 글자 자체
# (`fzf-history-widget: function`)를 끼어든 줄로 보고 떼어 버린다. 커널 줄은 시각
# 표식이라는 화면에 없을 모양이 있어서 넓어도 됐고, init의 줄은 우리가 정한 고정
# 접두사라 좁게 맞출 수 있다. 같은 UART에 쓰는 다른 것(dhcpcd · sshd · chronyd ·
# 서비스의 표준 출력)이 같은 자름을 일으키면 그 고정 접두사를 여기 하나씩 더한다 —
# 화면에 그 글자가 나올 수 있는지 먼저 보고. 거꾸로, 화면에 `tars-init: `가 그대로
# 보이는 줄(사람이 시리얼 로그를 grep한 화면)은 그 자리부터 꼬리가 떨어진다 — 지금
# 그런 화면을 판정하는 체인은 없다(check.sh의 require_screen_dump_joins가 모양을 본다).
joined_screen_dump() {
  perl -ne '
    if (defined $cur) {
      next if /^\[ *\d+\.\d+\] / || /^tars-init: /;
```

P2 — `old_string`(지금 파일 132줄부터):

```bash
    next if $cur =~ s/\[ *\d+\.\d+\] [^\r\n]*\r?\n\z//;
```

`new_string`:

```bash
    next if $cur =~ s/\[ *\d+\.\d+\] [^\r\n]*\r?\n\z//;
    next if $cur =~ s/tars-init: [^\r\n]*\r?\n\z//;
```

### 5b-2. `check.sh` — 편집 하나

P1 — `old_string`(지금 파일 394줄부터):

```bash
# 체인이 source하는 공용 파일과 이 파일 자신도 같은 규칙을 받는다. 자기를
```

`new_string`:

```bash
# TC-M3 Task 5b. gate_lib.sh의 joined_screen_dump가 끼어든 줄을 잇는가. QEMU 없이 고정된
# 조각 넷으로 본다 — 안 잘린 dump, 커널 printk가 자른 dump, init의 줄이 자른 dump, init의
# 줄 둘(조각 + 온전한 한 줄)이 자른 dump가 전부 같은 한 줄이 되어야 한다. 이 함수가 잇지
# 못하면 그 화면의 마지막 dump를 기다리는 검사가 30초 뒤에 거짓으로 빨갛다(TC-M3 루트
# 게이트 2회차, config 7차). 게이트를 시작하기 전에 0.1초로 잡는다.
require_screen_dump_joins() {
  local dir want got name
  dir="$(mktemp -d)"
  printf 'terminal: screen> a | (none)# whence -w fzf-history-widget | fzf-history-widget: function | (none)# \r\n' > "$dir/clean"
  printf 'terminal: screen> a | (none)# whence -w fzf[   7.359211] random: crng init done\r\n-history-widget | fzf-history-widget: function | (none)# \r\n' > "$dir/printk"
  printf 'terminal: screen> a | (none)# whence -w fzftars-init: audio: no sound card within 5000ms, the mixer is left alone\n-history-widget | fzf-history-widget: function | (none)# \r\n' > "$dir/init"
  printf 'terminal: screen> a | (none)# whence -w fzftars-init: audio: one\ntars-init: two\n-history-widget | fzf-history-widget: function | (none)# \r\n' > "$dir/init2"
  want="$(LOG="$dir/clean" bash -c 'source ./gate_lib.sh; joined_screen_dump')"
  for name in printk init init2; do
    got="$(LOG="$dir/$name" bash -c 'source ./gate_lib.sh; joined_screen_dump')"
    if [ "$got" != "$want" ]; then
      echo "check FAIL: gate_lib.sh joined_screen_dump does not rejoin a screen> line cut by ${name}:" >&2
      echo "  want [${want}]" >&2
      echo "  got  [${got}]" >&2
      rm -rf "$dir"
      return 1
    fi
  done
  rm -rf "$dir"
  return 0
}
require_screen_dump_joins || entry_failed=1

# 체인이 source하는 공용 파일과 이 파일 자신도 같은 규칙을 받는다. 자기를
```

### 5b-3. 확인

QEMU가 필요 없는 셋과 체인 둘이다.

```bash
for f in gate_lib.sh check.sh; do cmp $f /tmp/run/tc3b/new/$f && echo "SAME $f"; done
F=/tmp/run/tc3/gate_2/tmp.AD81GFh5bD
for v in /tmp/run/tc3b/base/gate_lib.sh ./gate_lib.sh; do
  echo "$v finds=$(LOG=$F bash -c "source $v; joined_screen_dump" | grep -acE '\| fzf-history-widget: function')"; done
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  bash -c "source <(sed -n \"/^require_screen_dump_joins()/,/^}/p\" check.sh); require_screen_dump_joins && echo SELFTEST-OK"
  bash -n check.sh && echo CHECK-SYNTAX-OK
  bash -c "source <(sed -n \"/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p\" check.sh); require_no_early_exit_pipe ./gate_lib.sh && require_no_early_exit_pipe ./check.sh && echo PIPE-OK"
  for c in boot pane; do s=$(date +%s); bash $c/check.sh > /tmp/$c.log 2>&1; echo "$c exit=$? $(( $(date +%s) - s ))s"; done'
rmdir /tmp/run/docker.lock
```

기대: `SAME` 둘, 옛 것 `finds=0` · 새 것 `finds=1`, `SELFTEST-OK` · `CHECK-SYNTAX-OK` · `PIPE-OK`, `boot exit=0` · `pane exit=0`. 사본에서 boot 25초 · pane
51초였다(pane은 `wait_for_screen` · `joined_screen_dump`를 가장 많이 쓰는 체인이다).

사본에서 더 본 둘(구현자는 안 돌린다).
- mutation — 옛 `gate_lib.sh`로 `require_screen_dump_joins`를 돌리면 printk 조각은 지나고 init 조각에서 멈춘다: `check FAIL: gate_lib.sh joined_screen_dump does not
  rejoin a screen> line cut by init:` · `got [… whence -w fzftars-init: audio: no sound card within 5000ms, the mixer is left alone]`.
- 2회차 게스트 로그 스물다섯에 옛 · 새 `joined_screen_dump`를 함께 돌려 출력을 견줬다. 다른 것은 둘뿐이고 둘 다 위의 끼어듦이다(`tmp.AD81GFh5bD`
  1153행 · `tmp.RLRCcx21eQ`의 `reload of`) — 나머지 스물셋의 출력은 바이트까지 같다. 넓게 떼어 버리는 자리가 없다는 뜻이다.

lessons의 AU-M2 절("커널 printk가 terminal의 화면 줄을 가운데서 자른다")에 lead가 덧붙일 두 문장:

> init의 줄도 같은 UART에 써서 같은 모양으로 자른다 — TC-M3 루트 게이트 2회차의 config 7차가 `whence -w fzf` 뒤에 끼어든 `tars-init: audio: …` 때문에
> 마지막 dump를 못 이어 빨갰고, `joined_screen_dump`가 이제 `tars-init: ` 조각도 떼고 잇는다(접두사는 일부러 그 하나로 좁다 — 넓히면 화면 글자를 뗀다).
> 루트 `check.sh`의 진입 검사 `require_screen_dump_joins`가 잘린 조각 넷을 QEMU 없이 0.1초에 보므로, 다른 쓰기(dhcpcd · sshd · 서비스)의 접두사를 더할 때 그
> 함수에 조각 하나를 함께 더한다.

보고는 Task 4의 보고와 같은 모양으로.

## Task 5c: 수정 2 — 프로브가 연달아 찍는 줄은 줄마다 기다린다

2026-10-07, Task 5b를 넣고 lead의 루트 게이트를 다시 돌린 뒤에 더했다. 2회차는 21체인 2/2(59분 11초) 초록이었고 1회차가 wifi(WL-M3) run 2/2의 검사 12
`FAIL: the file tars-config wrote is not one hashed block with the country kept and mode 600`으로 빨갰다(`/tmp/gate_tc3b_1.log` 19718행, 게스트 로그
`/tmp/run/tc3/gate3_1/`). fail이 찍은 마지막 줄이 `wifi-ap: tc [wifi: tars-wl replaced …|apply now: …|]`였고 그다음 줄 `wifi-ap: tc file [...]`은 아직
없었다. 검사 12는 `wait_for_log 'wifi-ap: tc \['`로 앞 줄을 기다린 뒤 다음 줄 `tc file [0 1 1 1 600]`을 기다림 없이 `grep`한다. 프로브(`wifi/ap.sh` 2b)는
`tc` 줄을 찍고 `grep -c` 넷과 `stat`으로 값 다섯을 재서 `tc file` 줄을 찍으므로 그 사이가 TCG에서 수백 ms이고, 체인이 그 창에 들어가면 빨갛다. TC-M1의
검사이고 그동안 열두 판에 처음 걸렸다(lead가 셌다).

같은 모양 — "앞 줄을 기다린 뒤 그다음 줄을 기다림 없이 본다" — 을 TC가 더한 검사 전부에서 찾았다.

| 검사 | 있나 | 왜 |
|---|---|---|
| wifi 12 | 있다 — 고친다 | 위 |
| config 1차 TC-M3 `reload terminal` | 있다 — 고친다 | `terminal: keyboard=pc` 줄을 기다린 뒤 `terminal: clipboard scope=pane`을 곧바로 센다. terminal은 시작할 때 keyboard · hangul · clipboard 줄을 차례로 찍는다(`terminal/src/main.zig`) — 아직 안 걸렸지만 같은 창이다 |
| config 1차 TC-M3 둘째 `reload terminal` · 콘솔 셸 | 없다 | 둘째는 `nothing pending`을 기다린 뒤 `started terminal`이 여전히 둘인지(없어야 하는 줄) 본다. 콘솔 셸은 줄마다 기다린다 |
| config 1차 TC-M0 · M2 | 없다 | 화면 판정이 전부 `wait_for_screen`이다. M2의 "dhcpcd를 안 건드렸다"는 같은 답(한 번의 write) 안의 줄이 없는 것을 본다 |
| net 31 | 없다 | 줄마다 기다린다(5b). 끝의 `started service dhcpcd` 둘은 lease보다 먼저 찍히는 줄이다 |
| firewall 18 · 19 | 없다 | 화면은 `wait_for_screen`, 포트는 `expect_tcp_bytes`가 다시 본다 |
| service 27 · 28 | 없다 | ssh 명령이 끝난 뒤의 출력을 본다(동기). 새 로그인은 다시 시도하며 기다린다 |
| dictation 30 | 없다 | 게스트가 꺼진 뒤(`kill -TERM 1`)의 로그와 stub 로그를 본다 |
| pane 16 | 없다 | `clipboard scope=shared`를 기다리고, 그보다 먼저 찍히는 `restarting terminal`을 본 뒤, 배치 · `spawned child pid`는 줄마다 기다린다 |
| wifi 9 | 없다 | 고친 줄(`tc [`)을 기다린 뒤 그 앞의 로그만 본다 |

고치는 모양. wifi 12는 그 줄의 머리(`wifi-ap: tc file [`)를 30초까지 기다리고 값은 그 뒤에 견준다 — 값까지 든 글자를 기다리면 틀린 값도 30초를 다 쓰고 "안
왔다"로 보인다. 틀린 값이면 FAIL에 그 줄을 붙인다. config의 clipboard 줄은 10초까지 기다린 뒤 지금처럼 센다(못 오면 그 셈이 빨갛다).

기준은 main 트리의 지금 파일이다 — `wifi/check.sh`는 HEAD `3f8598d`(TC-M3이 안 건드렸다, `/tmp/run/tc3c/base/wifi_check.sh`), `config/check.sh`는 Task 1 ~ 4를
넣은 것(= `/tmp/run/tc3/new/config/check.sh`, `/tmp/run/tc3c/base/config_check.sh`). 편집 뒤는 `/tmp/run/tc3c/new/`다 — `wifi/check.sh` +11 −2, `config/check.sh` +8.

### 5c-0. 기준을 본다

```bash
cmp wifi/check.sh /tmp/run/tc3c/base/wifi_check.sh && echo "BASE wifi/check.sh"
cmp config/check.sh /tmp/run/tc3c/base/config_check.sh && echo "BASE config/check.sh"
```

### 5c-1. `wifi/check.sh` — 편집 하나

P1 — `old_string`(지금 파일 297줄부터):

```bash
grep -aF 'wifi-ap: tc file [0 1 1 1 600]' "$LOG" >/dev/null \
  || report_failure "the file tars-config wrote is not one hashed block with the country kept and mode 600"
```

`new_string`:

```bash
#
# 이 줄은 위 `tc [` 줄과 따로 기다린다(TC-M3 Task 5c). 프로브가 `tc` 줄을 찍은 뒤 grep 넷과 stat으로
# 다섯 값을 재서 이 줄을 찍으므로 둘 사이가 TCG에서 수백 ms다 — 앞 줄만 기다리고 이 줄을 곧바로 grep하면
# 그 창에서 빨갛다(TC-M3 루트 게이트 1회차, 열두 판 만에 처음). 기다리는 것은 머리(`tc file [`)이고 값은
# 그 뒤에 견준다 — 값까지 든 글자를 기다리면 틀린 값도 30초를 다 쓰고 "안 왔다"로 보인다.
wait_for_log 'wifi-ap: tc file \[' 30 || report_failure "the probe never printed the tc file line"
TC_FILE="$(grep -a 'wifi-ap: tc file \[' "$LOG" | head -n 1 | tr -d '\r')"
case "$TC_FILE" in
  *'wifi-ap: tc file [0 1 1 1 600]'*) ;;
  *) report_failure "the file tars-config wrote is not one hashed block with the country kept and mode 600 (${TC_FILE})" ;;
esac
```

### 5c-2. `config/check.sh` — 편집 하나

P1 — `old_string`(지금 파일 728줄부터):

```bash
  if [ "$(grep -ac 'terminal: clipboard scope=pane' "$log")" != "1" ] || [ "$(grep -ac 'tars-init: started terminal' "$log")" != "2" ]; then
```

`new_string`:

```bash
  # terminal은 시작할 때 keyboard 줄 다음에 clipboard 줄을 찍는다(terminal/src/main.zig). 위에서 기다린 것은
  # 앞 줄이라 이 줄은 따로 기다린다 — 앞 줄을 기다리고 다음 줄을 곧바로 세면 그 사이가 경합이다(TC-M3 Task 5c).
  tries=0
  until grep -aq 'terminal: clipboard scope=pane' "$log"; do
    tries=$((tries + 1))
    if [ "$tries" -gt 20 ]; then break; fi
    sleep 0.5
  done
  if [ "$(grep -ac 'terminal: clipboard scope=pane' "$log")" != "1" ] || [ "$(grep -ac 'tars-init: started terminal' "$log")" != "2" ]; then
```

### 5c-3. 확인과 체인 둘

```bash
cmp wifi/check.sh /tmp/run/tc3c/new/wifi_check.sh && echo "SAME wifi/check.sh"
cmp config/check.sh /tmp/run/tc3c/new/config_check.sh && echo "SAME config/check.sh"
bash -n wifi/check.sh && bash -n config/check.sh && echo SYNTAX-OK
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -v /tmp/run/tc3/impl:/impl -w /workspace tars-devcontainer bash -c '
  for c in wifi config; do s=$(date +%s); bash $c/check.sh > /impl/p5c_$c.log 2>&1; echo "$c exit=$? $(( $(date +%s) - s ))s"; done'
rmdir /tmp/run/docker.lock
```

기대: `SAME` 둘, `SYNTAX-OK`, 둘 다 `exit=0`. 사본에서 wifi 122초 · config 191초였다.

lessons의 "게이트를 돌리고 읽는 법" 절에 lead가 넣을 한 문단:

> 프로브가 연달아 찍는 줄은 줄마다 기다린다. 앞 줄을 `wait_for_log` · `wait_for_screen`으로 기다리고 다음 줄을 곧바로 `grep`하면 그 사이가 경합이다 —
> 프로브가 두 줄 사이에 무엇을 재든(TC-M1 wifi 검사 12의 `grep -c` 넷과 `stat`) TCG에서는 수백 ms이고, 열두 판을 지난 검사가 루트 게이트에서 처음 빨갰다
> (TC-M3 Task 5c). 줄의 머리를 기다리고 값은 그 뒤에 견준다 — 값까지 든 글자를 기다리면 틀린 값이 "안 왔다"로 보인다. 프로세스 하나가 찍는 줄들(terminal의
> 시작 줄 셋)도 같다.

보고는 Task 4의 보고와 같은 모양으로.

## 닫을 때 lead가 고칠 자리(TC 전체, M3 기준)

TC design(`2026-10-06-tars-config-tool-design.md`)과 reload design(`2026-10-07-tars-config-reload-design.md`)의 "닫을 때" 절을 M3까지의 값으로 한 번에
모은 것이다.

1. 두 design의 `Status:` — TC는 M0 ~ M1과 M2 · M3이 reload design으로 갔다는 한 줄, reload design은 M2 · M3이 끝났다는 한 줄.
2. `CLAUDE.md` 완료 표에 한 줄(Config Tool, TC-M0 ~ M3). 예: "게스트의 `tars-config`가 설정을 보고 · 고치고 · 적용한다 — `tars.conf`의 줄 하나만
   바꾸고(값은 init의 `parse`가 정한다), 무선 · ssh · 방화벽 · 받아쓰기의 파일에 그 주인(wpa_passphrase · ssh-keygen · nft)이 지은 줄을 두고, `reload`가 init에
   재부팅 없이 tars.conf와 services.d를 다시 읽게 하고, `reload terminal`이 화면을 새 값으로 다시 띄운다. 새 체인 없이 config · net · firewall · service ·
   wifi · dictation · pane 체인이 본다".
3. `docs/guides/running-tars.md`에 새 절 "설정 — tars-config", 그리고 "재부팅"을 말하던 줄들. 새 절에 들어갈 동사 전부.

   | 동사 | 한 줄 |
   |---|---|
   | `tars-config` | `tars.conf`를 init이 읽을 모양으로(기본값은 `#`), init이 지금 쓰는 값과 다르면 그 줄 밑에 한 줄, 화면의 대기 |
   | `tars-config get KEY` | 값 하나 |
   | `tars-config set KEY=VALUE…` | 그 키의 줄 하나만. init이 버릴 값은 그 말로 거절 |
   | `tars-config reset KEY…` | 기본값을 적는다(줄을 안 지운다). "언세팅"이 이것이고 `unset`은 없다 |
   | `tars-config list` · `help` | 열두 키 · 기본값 · 받는 값 / 쓰는 법 전부 |
   | `tars-config check` | init이 불평할 줄 · 4096 · zoneinfo · rc의 옛 별칭 · 앞문 넷의 파일(모드 · net과의 짝 · 키 없음 · 모르는 받아쓰기 키) |
   | `tars-config wifi [SSID [--country CC]]` | 비밀번호를 echo 없이 묻고 같은 SSID의 덩어리를 바꾼다(0600, `#psk` 없음) |
   | `tars-config ssh [on\|off]` · `ssh-key add [KEY] \| list` | 템플릿 링크 · ssh-keygen이 읽어 본 키(0700 · 0600, 중복 없음) |
   | `tars-config firewall [allow\|deny PORT[/udp]]` | `nftables.d/tars-config.nft`, firewall=on이면 그 자리에서 nft -f |
   | `tars-config dictation [key [KEY] \| set KEY=VALUE…]` | `groq.key`(0600) · `dictation.conf`의 키 여덟 |
   | `tars-config reload` | tars.conf · services.d를 다시 읽는다 — net · ntp · firewall은 지금, 셸 · 시간대는 다음에 뜰 때부터, 화면 쪽은 대기 |
   | `tars-config reload terminal` | 화면을 지금 값으로 다시 띄운다(패널 · 클립보드가 사라진다) |

   "재부팅"을 말하던 줄 — "네트워크와 시계" 절의 `sd` 세 줄과 `kill -INT 1`(→ `tars-config set net=dhcp ntp=dhcp timezone=Asia/Seoul` · `tars-config reload`),
   "seed는 한 번만 깔린다" 절에 옛 별칭 처방(TC 결정 6), 무선 · ssh · 방화벽 · 받아쓰기 절의 손 명령(→ 앞문 동사), "부팅 때 뜨는 서비스" 절의 "고친 것은
   다음 부팅에"(→ `tars-config reload`).
4. 기억 둘과 `MEMORY.md` 두 줄.
   - `docs/decisions/project_config_tool.md` — 로그 가로채기(`configLog`, TC 결정 3), 이기는 줄 하나(결정 5), 옛 별칭(결정 6), 남의 문법은 주인이 짓는다(결정 10 · 13),
     이 명령의 파일을 가르는 것은 방화벽 하나(결정 14).
   - `docs/decisions/project_config_reload.md` — 키의 네 갈래(reload 결정 2), 조이고 푸는 순서(결정 3), `config_off`와 `hold`의 차이와 칸 열셋(결정 5), services.d
     다시 읽기(결정 11), 대기와 `reload terminal`, 드러난 `kill(-pid)`(M3 plan 확정 2).
5. `docs/guides/lessons.md`.
   - 핵심 파일(PID 1 쪽): `config_cli.zig` · `config_edit.zig` · `config_front.zig` · `config_front_edit.zig` · `reload.zig`, `config.zig` 항목에 `log`, `main.zig`
     항목에 `Live` · 칸 열셋(`SLOT_*`) · `doReload` · `doReloadTerminal`.
   - 실측(다시 조사하지 말 것): 0.16의 multiline 문자열은 탭을 거부한다 · `linux.W.TERMSIG`가 enum이다 · `@embedFile`은 모듈 뿌리 밖을 못 읽는다(런타임
     읽기) · sd 1.0은 줄 단위라 `\n`을 못 맞춘다 · 콘솔 셸의 tty는 `ttyS0`이다(`pgrep -t console`은 빈다) · fzf picker를 닫은 직후의 키는 샌다(그 뒤에
     화면을 바꾸는 명령을 치지 않는다) · 반쪽 패널에서 긴 줄은 접힌다.
   - 이월 숙제에서 지울 것: "seed 48줄이 화면을 넘는다 — config 1차의 25번째 줄"(1차가 `cat` 대신 `tars-config`를 본다).
   - 이월 숙제에 더할 둘: (a) chronyd의 reload를 게이트가 안 본다 — net 검사 31의 부팅에 ntp가 없다(M2 plan 확정 4). ntp 부팅(부팅 A)에 `set ntp=…` ·
     `reload`를 얹으면 덮인다. (b) net 검사 31의 간헐(M2 루트 게이트 두 판, 셋 중 둘)의 진짜 원인을 못 잡았다 — Task 5b가 set의 답을 기다리고 진단을
     찍게 했고 그 뒤 4판(2회 × 2) 초록이다. 다시 빨개지면 진단의 세 덩어리(마지막 화면 · `cat /config/tars.conf` · `reload of` 뒤 tars-init 줄)로 가린다.
6. `HANDOFF.md` — 사용자에게 알릴 것: 쓰던 디스크의 rc에는 `alias tars-config`가 남아 있다(처방은 TC design 결정 6), 실기에서 칠 것(`tars-config wifi …` ·
   `tars-config dictation key`의 tty 길 · `tars-config set net=dhcp` · `reload`).

## design과 다르게 적은 것

design 본문은 M3 절의 덧붙임(이 plan과 같은 날 같은 사람)으로 맞췄다. 구현 뒤에 lead가 고칠 것은 `Status:`와, 확정 6의 시간이 루트 게이트에서 다르면
실측 절이다.

## 이 milestone에서 안 하는 것

- 콘솔 셸을 다시 띄우는 동사(design 비목표 4). 콘솔 셸은 끝날 때 새 셸로 뜬다.
- terminal이 argv 대신 설정을 다시 받는 것(비목표 1) — 화면을 내리지 않고 자판을 바꾸기.
- running-tars.md · lessons · 기억(위 "닫을 때").

## TC-M3이 실측한 것

lead가 2026-10-07에 쟀다. 구현자(Sonnet)의 보고와 파일을 lead가 직접 대조했다 — 열한 파일 전부 사본(`/tmp/run/tc3/new/`, 5b는
`tc3b/new/`, 5c는 `tc3c/new/`)과 `cmp`가 같았고, 지운 줄은 plan이 말한 자리뿐이었다. 체인 로그에 `Attempted to kill init` · `Kernel panic`은 0건.

1. 구현자의 체인. `zig build test` 초록(`reload_test:` 다섯 줄 — M2와 같은 plan 문구 오타). config 192초 · pane 51 · service 76 · boot 24 ·
   terminal 25 · power 50초. mutation 일곱 판 전부 plan의 표와 같았다 — m1(SIGTERM만 그룹으로 되돌림)은 기대대로 초록(208초, 3초 뒤의
   SIGKILL이 pid로 가서 결국 다시 뜬다), m1b(둘 다 되돌림)는 `tars-init: terminal outlived SIGTERM by 3s, sent SIGKILL to group 39`로 빨감.
2. 루트 게이트 — 네 번 돌렸고 완주 통과가 둘이다. (a) 1회차 21체인 2/2 59분 20초, 2회차는 config 7차에서 `the fzf integration never defined
   its history widget` — init의 `tars-init: audio: no sound card within 5000ms` 줄이 화면 dump 줄을 잘라 출력이 머리 없는 조각으로 넘어갔다
   (게스트 로그 `/tmp/run/tc3/gate_2/tmp.AD81GFh5bD` 1153행). → Task 5b: `joined_screen_dump`가 `tars-init: ` 조각도 잇고 루트 `check.sh`에
   진입 검사 `require_screen_dump_joins`. (b) 1회차는 wifi run 2/2 검사 12 `the file tars-config wrote is not one hashed block …` — 프로브의
   둘째 줄(`tc file [`)을 기다림 없이 grep했고 실패 run의 마지막 로그 줄이 정확히 첫 줄이었다. 2회차 21체인 2/2 59분 11초. → Task 5c:
   줄마다 기다린다(wifi 12 · config 1차의 terminal 시작 줄 셋). (c) 1회차는 pointer run 1/2 — `terminal: pointer> at … ink=` 65바이트 자리에
   같은 audio 줄이 끼었다(`last at: '… ink=tars-init: audio: …'`). 2회차 21체인 2/2 59분 17초. (c)는 5b의 joiner 밖이다 — 원인이 Zig 0.16
   `std.debug.print`의 64바이트 내부 버퍼라(한 줄이 write 둘 이상으로 나간다) terminal · init 둘 다에 걸리고, 고치는 자리는 게이트가 아니라
   로그 줄을 write 한 번에 내는 것이다. TC 밖의 후속으로 열었다(HANDOFF).
   M3의 판정(config 1차 셋 · pane 16)은 네 번의 게이트 여덟 회차 전부에서 초록이었다.
3. 크기. `init` 4,072,600바이트(M2 4,028,376 — `doReloadTerminal` · `Live.toggle`이 44KB), `tars-config` 3,695,016, initrd 98,153,417.
4. 게이트가 본 M3 줄 — `reload terminal brought the screen up again with keyboard=pc and clipboard=pane` · `a second reload terminal found
   nothing pending and left the screen alone` · `after reload with shell=bash, the killed console shell came back as bash`, pane 검사 16.
5. 루트 게이트는 M2(58:19)보다 1분쯤 늘었다 — config 1차 150키 · pane 70키와 화면 재시작 둘.
