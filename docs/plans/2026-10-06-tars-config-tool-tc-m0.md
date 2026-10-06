# TC-M0 — `tars-config`가 `tars.conf`를 init이 읽을 모양으로 보이고 그 키의 줄 하나만 고친다

Date: 2026-10-06
Design: `docs/specs/2026-10-06-tars-config-tool-design.md`
Status: plan을 썼다. 구현 전이다. plan을 쓰며 사본에서 돈 값은 "착수 전에 확정한 것"에, 구현과 루트 게이트의 값은 맨 아래 "TC-M0이 실측한 것"에 들어간다.

## 누가 무엇을 하나

design 결정 11. Task 0 ~ 5는 구현 서브에이전트가 main 작업 트리에서 직접 편집하고 돌린다. Task 6(루트 게이트 2회 · 실측 절 ·
design 덧붙임 · commit)은 lead(Fable)가 한다. 구현자는 commit하지 않고, 끝에 `git diff --stat` · `git diff | rg '^-'` · 각 Task의
명령 출력을 그대로 보고한다. 이 plan의 "확정한 것" 절과 "실측한 것" 절은 구현자가 고치지 않는다.

권하는 모델은 Sonnet이다. 근거 셋.

- Zig 새 파일 셋(`config_edit.zig` 299줄 · `config_cli.zig` · `config_edit_test.zig`)은 구현자가 짓지 않는다. 사본에서 컴파일 · 호스트 검사 ·
  config 체인 · regression · mutation을 지난 파일을 `cp -p`한다. VD-M1(terminal의 Zig 수백 줄)도 같은 방식으로 Sonnet이 넣었고 plan
  코드를 고친 곳이 없었다.
- 고치는 파일 일곱의 편집도 글자 그대로다. `config.zig`의 로그 스물넷은 perl 한 줄(Task 1-1)이 바꾸고, 그 뒤의 편집 여섯과 다른 파일의
  편집 열여섯은 `old_string` · `new_string`이다. 판단이 남는 자리가 없다 — 각 Task 끝의 `cmp`가 사본과 바이트까지 같은지를 본다.
- Opus로 올릴 이유는 하나다. 루트 게이트에서 이 plan이 안 돌린 체인이 빨개져 Zig 쪽 원인을 찾아야 할 때(예: `config.zig`의 `log`가
  init의 어떤 로그를 바꿨는가). 그때는 lead가 정한다.

이 plan의 코드는 저장소 밖 사본(`/tmp/run/tc0/repo/`)에 먼저 넣어 돌렸고, 아래의 새 파일 본문과 `old_string` · `new_string`은 그
사본에서 기계로 뽑은 것이다(`/tmp/run/tc0/render.py`). 기준은 HEAD `4ed73a9`의 파일(`/tmp/run/tc0/base/`)이고, `config.zig`만은
perl 한 줄을 지난 파일(`/tmp/run/tc0/mid/`)이 기준이다. 편집 뒤의 파일은 `/tmp/run/tc0/new/`다. 새 파일은 `new/`에서 `cp -p`하고, 편집은
Edit 도구에 글자 그대로 넣고(또는 plan 본문에서 블록을 기계로 뽑아 넣고), 각 Task 끝에서 `new/`와 `cmp`한다. 다르면 편집이 빗나간
것이니 plan의 글자에 맞춰 고친다. plan의 글자와 `new/`가 서로 다르다고 보이면 고치지 말고 그 자리를 보고한다. 편집은 한 파일 안에서
E1부터 차례로 넣는다.

| 파일 | 무엇을 | 줄 |
|---|---|---|
| `init/src/config.zig` | perl 한 줄(로그 스물넷 → `log`) · 편집 여섯 — `log` 함수, seed 셋의 별칭 두 줄씩, `MAX_FILE`의 `pub`과 주석, gitconfig 주석 한 줄 | +50 −32 |
| `init/src/config_test.zig` | 편집 다섯 — `ALLOWED_ALIAS_NAMES`에서 두 이름, 주석 셋, `alias tars-` 건너뛰기 | +15 −14 |
| `init/build.zig` | 편집 셋 — `tars-config` exe, `config_edit_test`, test step 한 줄 | +30 |
| `kernel/make_initrd.sh` | 편집 하나 — `tars-service` 뒤에 `tars-config` | +5 |
| `tools/check.sh` | 편집 하나 — `WANT+=(usr/bin/tars-config)` | +6 |
| `config/check.sh` | 편집 다섯 — 1차의 키 배열 넷과 검사 다섯, 2차의 `OFF_KEYS`가 `tars-config set` | +88 −16 |
| `check.sh` | 편집 하나 — config 체인 설명 문단 | +5 |
| `init/src/config_edit.zig` | 새 파일 — 순수한 쪽 | +299 |
| `init/src/config_cli.zig` | 새 파일 — `tars-config`의 root | +492 |
| `init/src/config_edit_test.zig` | 새 파일 — 호스트 검사 | +268 |

`git diff --stat`은 7 files, +199 −62이고(새 파일 셋은 밖), `git add -N` 뒤에는 10 files다. 커널(`kernel/.config`)도 Dockerfile도 안 바뀐다 —
이미지를 다시 굽지 않는다. `kernel/guest_tools.sh`도 안 고친다 — `all 92 tools`가 그대로다. `.gitignore`도 그대로다(`init/zig-out/`이 이미 있다).

design의 `Status:` · `CLAUDE.md` · `MEMORY.md` · `docs/decisions/` · `docs/guides/` · `HANDOFF.md`는 구현자가 안 고친다.

모든 명령은 저장소 루트에서 친다. 서브에이전트의 Bash는 호출마다 작업 디렉터리가 돌아가므로 명령 앞에
`cd /Users/dp/Repository/tars-linux &&`를 붙인다. 빌드 · 체인은 언제나 컨테이너에서 한다. 구현자의 측정용 파일은
`/tmp/run/tc0/impl/` 아래에 둔다. `/tmp/run/tc0/` 바로 아래는 이 plan을 쓰며 만든 것이고 대조에 쓴다. 지우지 않는다.

Docker VM의 메모리가 4GB다. 컨테이너 둘을 겹쳐 돌리면 `zig build`가 `Killed`로 죽거나 VM이 재시작된다(lessons PD-6).
컨테이너는 언제나 하나씩 돌린다. 다른 에이전트가 같은 시간에 돌 수 있으므로 모든 `docker run`을 아래로 감싼다. 명령이 실패해도
lock은 꼭 푼다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run … ; rc=$?
rmdir /tmp/run/docker.lock
```

20분 넘게 기다리면 `docker ps`를 보고, 컨테이너가 하나도 없으면 lock이 낡은 것이니 `rmdir`하고 진행한다.

main 트리의 `kernel/build`가 반쯤 지어진 채일 수 있다(design 실측 7 — 멈춘 게이트의 흔적, `net/.socket.o.cmd`가 잘렸다). 그 상태면 어느
체인이든 첫 줄의 `kernel/build.sh`가 `unterminated call to function 'wildcard'`로 죽는다. Task 0의 3이 그것을 본다. 고치는 것은 lead가 정한다.

## 이 milestone이 끝나면

- 게스트에서 `tars-config`를 치면 `/config/tars.conf`가 열두 줄로 보인다. 파일이 정하지 않은 키는 앞에 `#`가 붙는다(design 결정 8).
- `tars-config set net=dhcp ntp=dhcp timezone=Asia/Seoul`이 그 셋의 줄만 바꾸고 "reboot to apply"라 말한다. init이 버릴 값은 init이 할 말을
  이유로 거절하고 아무것도 안 쓴다. `get` · `reset` · `check` · `help`가 있다.
- 새 설정 디스크의 seed rc에는 `alias tars-config` · `alias tars-rc`가 없다. 옛 디스크의 rc에는 남아 있고 `tars-config check`가 그 줄을 문제로
  알린다(design 결정 6).
- init은 그대로다. `config.zig`의 로그가 `log` 하나로 모였고 init에서는 바이트까지 같은 줄을 찍는다.
- 새 체인은 없다. config 체인 1차가 명령 다섯을 치고, 2차가 3차를 위해 줄을 더하는 것도 이 명령이다. `zig build test`에 `config_edit_test`가 는다.
- `reload`(M2)와 남의 문법 파일(M1)은 아직 없다.

출력(정본 — `config_cli.zig`가 찍는다. 체인이 이 글자를 본다). 표준 출력이다.

```
# /config/tars.conf on /dev/vda, as init reads it at boot
# a line starting with # is a default; the file does not set it
shell=fish
⋮ (열두 키)
clipboard=shared
# change: tars-config set KEY=VALUE, then reboot (kill -INT 1)

clipboard: shared -> pane
net: off (default) -> dhcp
shell: zsh (unchanged)
init reads /config/tars.conf only at boot; reboot to apply (kill -INT 1)

/config/tars.conf: init reads every line without a complaint
line 7: unknown shell 'fsh', falling back to fish
shell is on 2 lines (3, 7); the last one wins
timezone Asia/Seol: /usr/share/zoneinfo/Asia/Seol is not a zoneinfo file; init falls back to UTC
/config/zshrc line 16: alias tars-config hides this command in zsh; delete that line
2 problem(s)
```

보기의 그 밖의 주석 줄.

```
# /config/tars.conf on /dev/vda does not exist yet; init writes it at the next boot
# no config disk: init uses the defaults and nothing here outlives a power off
# init complains about 1 line(s) of this file; tars-config check lists them
# /usr/share/zoneinfo/Asia/Seol is not a zoneinfo file; init falls back to UTC
# tars.noconfig is on the kernel command line: this boot's shells read no rc
```

표준 에러(`tars-config: `로 시작한다).

```
tars-config: shell=fsh: init would say "unknown shell 'fsh', falling back to fish"     exit 1
tars-config: shell takes fish | bash | zsh
tars-config: nothing was written
tars-config: unknown key 'colour'; tars-config help lists the keys                    exit 1(set) · 64(get · reset)
tars-config: timezone=Asia/Seol: /usr/share/zoneinfo/Asia/Seol is not a zoneinfo file; init would fall back to UTC
tars-config: shell: a control character cannot go into a config line
tars-config: no config disk is mounted at /config; a change there would be gone at the next boot     exit 2
tars-config: /config/tars.conf would be longer than the 4096 bytes init reads; nothing was written   exit 1
tars-config: 'shell' has no '='; set takes KEY=VALUE                                    exit 64
```

## 착수 전에 확정한 것

2026-10-06에 이 plan을 쓰며 저장소 사본(`/tmp/run/tc0/repo/`, HEAD `4ed73a9`)과 이미지 `tars-devcontainer`(zig 0.16.0)로 쟀다. 측정 파일은
`/tmp/run/tc0/meas/`(체인 · 시리얼 · regression)와 `/tmp/run/tc0/mut/`(mutation)에 있다. 저장소의 작업 트리는 design과 이 plan 말고는
한 글자도 안 바뀌었다.

1. 로그를 root로(design 결정 3). `config.zig`의 `std.debug.print("tars-init: …\n", …)` 스물넷이 전부 같은 모양이라 perl 한 줄이 다
   바꾼다(남는 `std.debug.print`는 0, `log("` 스물넷). 바꾼 뒤의 init과 HEAD의 init이 `config_test`에서 찍는 `tars-init:` 줄 쉰여덟이
   정렬해 같다. init 바이너리는 3,840,056 → 3,843,696바이트로 같지 않다(줄 번호 · seed 글자가 디버그 정보에 든다).

2. 파일 가름(design 결정 2). `config_cli.zig`가 root이고 시스템 콜은 전부 여기다. `config_edit.zig`는 시스템 콜이 없다 — 키 목록(`KEYS`,
   `Config`의 필드에서), 값의 글자(`valueText`), 받는 값(`hint`), 줄 가르기(`classify` · `Lines` · `lastLine` · `lineNumbers`), 줄 바꾸기
   (`setLine`), 듣기(`heard` · `configLog` · `judge` · `setByFile`), `/proc/mounts`(`mountSource`), 옛 별칭(`staleAlias`). `config_edit_test`가
   그 전부를 호스트에서 본다. `tars-config`는 3,414,368바이트다.

3. `config_edit_test`(호스트, `zig build test`의 열셋째). 다섯 묶음이 각각 한 줄을 찍고 끝에 `PASS`.

   | 묶음 | 본다 |
   |---|---|
   | 1 | 키가 열둘이고, 키마다 기본값 · 다른 값(`OTHER`)을 `judge`가 받고 정규형이 같다. `hint`가 있다 |
   | 2 | 거절이 init의 말 그대로다(`unknown shell 'fsh', falling back to fish` 등 여섯), 모르는 키 · 제어 문자 · 너무 긺, 정규형(`010.000.2.2` → `10.0.2.2`, 빈 목록 → `none`) |
   | 3 | 줄 열일곱을 `parse`와 `classify`+`judge`에 함께 넣어 같은 답 |
   | 4 | `setLine`의 일곱 모양(빈 파일 · 끝 개행 없음 · 마지막 줄 · 사람의 줄 보존 · CRLF · 주석 속 키 · 넘침)과, `config.save`가 /tmp에 쓴 진짜 seed(2,408바이트)에서 키마다 "한 줄만 다르다 · parse가 새 값 · 나머지 기본값" |
   | 5 | `setByFile`, `mountSource`, `staleAlias`, 지금의 seed 셋에 `alias tars-config`가 없다 |

4. initrd. `make_initrd.sh`가 `tars-service` 뒤에 `/usr/bin/tars-config`(0755)를 싣는다. gzip -9로 962,335바이트이고 initrd가
   97,997,614 ~ 97,997,632바이트였다. `tools/check.sh`의 `WANT`에 literal 한 줄 — `all 92 tools`는 그대로다.

5. config 체인(design 결정 9). 1차(fish)에 키 배열 넷과 검사 다섯, 2차(zsh)의 `OFF_KEYS`가 `tars-config set shell_config=off`다.

   | 자리 | 친다 | 판정 글자(화면의 행 머리) |
   |---|---|---|
   | 1차 | `tars-config` | `\| shell_config=on` — 파일이 정할 때만 `#` 없이 나온다 |
   | 1차 | `tars-config set shell=fsh` | `\| tars-config: nothing was written`과 `\| tars-config: shell=fsh: init would say "unknown shell 'fsh', falling back to fish"` |
   | 1차 | `tars-config set clipboard=pane` | `\| clipboard: shared -> pane` |
   | 1차 | `echo tc$(tars-config get clipboard)` | `\| tcpane` |
   | 1차 | `tars-config check` | `\| /config/tars\.conf: init reads every line without a complaint` |
   | 2차 | `tars-config set shell_config=off` 뒤 `cat /config/tars.conf` | `\| shell_config=off`(그대로) — set의 답은 `shell_config:`로 시작해서 안 겹친다 |
   | 3차 | (그대로) | `tars-init: config shell=zsh.*shell_config=off` — 이 명령이 쓴 값을 다음 부팅이 읽었다 |

   되읽기가 `get`의 출력 `pane`이 아니라 `tcpane`인 이유. 화면 줄이 " | "로 이어지므로 거절의 둘째 줄 `shell takes fish | bash | zsh`가
   `| bash` 같은 행 머리 모양을 만든다 — 판정 글자를 우리가 짓는다(BH-M2의 수법). 1차의 셸은 fish 4.0이고 `$(…)`를 받는다.
   1차에서 바꾼 `clipboard=pane`은 그 부팅의 `EDIT_KEYS`(`echo shell=zsh > /config/tars.conf`)가 덮어써서 2차로 안 넘어간다. 2차의 set은
   1차가 남긴 `shell=zsh` 한 줄 끝에 더하므로 파일이 echo 때와 바이트까지 같다 — 3 ~ 9차가 보는 것이 안 바뀐다.

   사본의 1차 화면(시리얼에서 복원).

   ```
   root@(none) ~# tars-config
   # /config/tars.conf on /dev/vda, as init reads it at boot
   # a line starting with # is a default; the file does not set it
   shell=fish
   keyboard=apple
   hangul_layout=shin_pcs
   latin_layout=qwerty
   hangul_toggle=hangul_key,shift_space,capslock_tap,lctrl_tap
   shell_config=on
   net=off
   ntp=off
   timezone=UTC
   firewall=off
   esc_latin=on
   clipboard=shared
   # change: tars-config set KEY=VALUE, then reboot (kill -INT 1)
   root@(none) ~# tars-config set shell=fsh
   tars-config: shell=fsh: init would say "unknown shell 'fsh', falling back to fish"
   tars-config: shell takes fish | bash | zsh
   tars-config: nothing was written
   root@(none) ~ [1]# tars-config set clipboard=pane
   clipboard: shared -> pane
   init reads /config/tars.conf only at boot; reboot to apply (kill -INT 1)
   root@(none) ~# echo tc$(tars-config get clipboard)
   tcpane
   root@(none) ~# tars-config check
   /config/tars.conf: init reads every line without a complaint
   ```

6. 시간. config 체인이 사본에서 init · terminal을 처음부터 짓는 판이 246초, 데운 판(mutation의 대조군 · 되돌림)이 169 · 182초다. 1차의 타이핑이 키 아흔 남짓 늘었다(글자당 0.3초 안팎).

7. mutation. 다섯 가지를 일곱 판으로 돌렸다(`/tmp/run/tc0/make_mut.py` · `run_mut.sh`, 로그는 `/tmp/run/tc0/mut/`). 앞 검사가 먼저 잡는
   것은 그 검사를 건너뛴 체인 사본을 함께 덮어 겨냥한 검사까지 보냈다.

   | mutation | 판 | 덮는 사본 | 잡은 자리 | `FAIL` 줄 | 시간 |
   |---|---|---|---|---|---|
   | (대조군) | `m0` | 없음 | — | 마지막 줄 `PASS` | 169초 |
   | 1 `tars-config`가 로그를 안 가로챈다(`configLog` 한 줄을 지운다) | `m1` | `cli_m1.zig` | 1차의 거절 | `FAIL(boot 1): 'tars-config set shell=fsh' was not refused` | 45초 |
   | 2 set이 `rename`을 안 한다(임시 파일만 쓴다) | `m2` | `cli_m2.zig` | 1차의 되읽기 | `FAIL(boot 1): 'tars-config get clipboard' did not read pane back from /config/tars.conf` | 50초 |
   | | `m2_noset` | + `check_noset.sh`(1차의 set · 되읽기를 뺀 체인) | 2차의 되읽기 | `FAIL(boot 2): 'tars-config set shell_config=off' did not land in /config/tars.conf` | 65초 |
   | 3 `setLine`이 늘 끝에 더한다 | `m3` | `edit_m3.zig` | `config_edit_test` 묶음 4(부팅 전) | `FAIL: setLine shell=fish on` … `FAIL: config_test failed` | 16초 |
   | 4 fish seed가 `alias tars-config`를 다시 깐다 | `m4` | `config_m4.zig` | `config_edit_test` 묶음 5와 `config_test`(부팅 전) | `FAIL: the fish seed line 15 aliases tars-config` · `FAIL: the fish seed defines an alias the list does not allow:` | 19초 |
   | (되돌림) | `back` | 없음 | — | 마지막 줄 `PASS` | 182초 |

   읽을 것 셋.
   - `m1`이 design 전제 정정 3의 증거다. 마지막 화면이 이랬다 — 거절의 말이 `tars-init:`으로 새고, `judge`는 아무 말도 못 들어 값을
     받았고, 기본값(fish)으로 읽힌 정규형을 쓰려다 같아서 "unchanged"라 했다. 다른 키(`net=on` 같은)였다면 파일에 기본값을 써 넣었을 것이다.

     ```
     root@(none) ~# tars-config set shell=fsh
     tars-init: unknown shell 'fsh', falling back to fish
     shell: fish (unchanged)
     ```
   - `m2_noset`은 2차의 되읽기가 이 명령이 쓴 것만으로 초록이 된다는 것을 보인다. 2차에 echo가 없으므로 그 줄은 set에서만 온다. 3차의
     `config shell=zsh.*shell_config=off`까지는 못 간다 — 2차가 먼저 멈춘다.
   - `m3` · `m4`는 부팅 전에 잡힌다. 체인의 `zig build test`(config 체인의 셋째 단계)가 `config_test failed`로 멈춘다 — 그 문구는 체인이 `zig build test`
     전체에 붙이는 이름이고, 위 `FAIL:` 줄이 어느 검사인지 말한다.

8. regression. initrd가 1MB 남짓 커지고 init이 다시 지어지므로 셋을 돌렸다. 셋 다 exit 0이다.

   | 체인 | 시간(사본) | 왜 |
   |---|---|---|
   | `tools` | 71초 | initrd의 `/usr/bin`에 하나. `the initrd carries the four bones and all 92 tools the list names` 그대로 |
   | `boot` | 26초 | limine이 BIOS로 initrd를 읽는다 |
   | `install` | 110초 | initrd가 바뀌면 부팅 7의 창이 움직인다(lessons PD-3). `init waited 1400ms`(VD-M0 때 1,700ms) |

   그 밖의 체인은 `tars-config`를 안 부르고, init의 바뀐 것은 로그가 가는 자리뿐이다(확정 1). 루트 게이트가 전부를 본다.

9. 낡은 산출물. 사본은 `init/zig-out` · `.zig-cache` 없이 시작했다. 구현자의 첫 빌드는 캐시 삭제를 같은 `docker run` 안에 둔다
   (`project_zig_out_staleness`). 커널은 안 바뀐다 — 스탬프가 맞으면 `skipping make`다.

## Task 0: 바꾸기 전의 기준값

1. 돌고 있는 게이트나 컨테이너가 없는지 본다.

   ```bash
   docker ps --format '{{.Names}} {{.Image}} {{.Status}}'
   ls -d /tmp/run/docker.lock 2>&1
   ```

   컨테이너가 있으면 끝나기를 기다린다(위 lock 절차). 남의 컨테이너를 죽이지 않는다.

2. 작업 트리를 본다.

   ```bash
   git status --short
   git log --oneline -3
   for f in init/src/config.zig init/src/config_test.zig init/build.zig kernel/make_initrd.sh tools/check.sh config/check.sh check.sh; do
     cmp $f /tmp/run/tc0/base/$f && echo "BASE $f"; done
   ls init/src/config_cli.zig init/src/config_edit.zig init/src/config_edit_test.zig 2>&1
   ```

   기대: 맨 위 commit이 `4ed73a9`이거나 그 위에 lead의 commit(design · 이 plan · HANDOFF)이 있다. `BASE` 일곱. 새 파일 셋은 `No such file`.
   하나라도 다르면 그 파일을 보고하고 멈춘다.

3. 커널 빌드가 성한지 본다(위 "누가 무엇을 하나"의 끝 문단).

   ```bash
   ls kernel/build/.tars-build-stamp kernel/build/arch/x86/boot/bzImage 2>&1
   ```

   둘 다 있으면 진행한다. 없으면 진행하지 말고 보고한다 — lead가 정한다.

## Task 1: `init/` — `config.zig` · `config_test.zig` · 새 파일 셋 · `build.zig`

design 결정 2 ~ 6 · 확정 1 ~ 3. `config.zig`는 perl 한 줄을 먼저 치고 편집 여섯을 넣는다.

### 1-1. `config.zig` — perl 한 줄

로그 스물넷의 `std.debug.print("tars-init: …\n", ` 를 `log("…", `로 바꾼다. 줄 안의 치환이고 인자는 그대로다.

```bash
perl -pi -e 's/std\.debug\.print\("tars-init: (.*?)\\n", /log("$1", /g' init/src/config.zig
cmp init/src/config.zig /tmp/run/tc0/mid/init/src/config.zig && echo MID-SAME
rg -c 'std\.debug\.print' init/src/config.zig; rg -c '\blog\("' init/src/config.zig
```

기대: `MID-SAME`, 첫 `rg`는 아무것도 안 찍고(0), 둘째는 `24`.

### 1-2. `config.zig` — 편집 여섯

E1이 `log` 함수, E2 ~ E4가 seed 셋(fish · bash · zsh)의 별칭 두 줄, E5가 `MAX_FILE`, E6이 gitconfig 주석 한 줄이다.

E1 — `old_string`(perl 뒤의 파일 9줄부터):

```zig
    return if (e == .SUCCESS) null else e;
```

`new_string`:

```zig
    return if (e == .SUCCESS) null else e;
}

/// 이 파일의 로그 한 줄이 가는 자리(TC design 결정 3). 줄마다 `std.debug.print`를
/// 부르던 것을 TC-M0이 여기 하나로 모았다.
///
/// init에서는 그 전과 바이트 하나 다르지 않다 — `tars-init: ` 접두사와 개행을
/// 붙여 표준 에러에 찍는다. 달라지는 것은 이 파일을 import하는 다른 실행
/// 파일이다. 그 root가 `configLog`를 선언하면 줄이 그리로 간다 — `tars-config`가
/// 사람이 적으려는 값을 `parse`에 넣고, init이 부팅에 그 값에 대해 무엇이라고
/// 말할지를 그 자리에서 듣는다(`config_edit.judge`). 그 말이 곧 거절의 이유다.
///
/// 고르는 것이 컴파일 타임이다. `std`가 `std_options`를 root에서 찾는 것과 같은
/// 수법이고, init과 `config_test`의 root에는 그 이름이 없으므로 둘의
/// 바이너리에는 가로채는 갈래가 아예 안 들어간다.
///
/// fmt는 접두사와 끝의 개행이 없는 글자다.
fn log(comptime fmt: []const u8, args: anytype) void {
    const root = @import("root");
    if (@hasDecl(root, "configLog")) return root.configLog(fmt, args);
    std.debug.print("tars-init: " ++ fmt ++ "\n", args);
```

E2 — `old_string`(perl 뒤의 파일 578줄부터):

```zig
            \\# 기계에서 치른다.
            \\alias tars-config='cat /config/tars.conf'
            \\alias tars-rc='cat /config/fish.config'
```

`new_string`:

```zig
            \\# 기계에서 치른다.
```

E3 — `old_string`(perl 뒤의 파일 624줄부터):

```zig
            \\# 기계에서 치른다.
            \\alias tars-config='cat /config/tars.conf'
            \\alias tars-rc='cat /config/bashrc'
```

`new_string`:

```zig
            \\# 기계에서 치른다.
```

E4 — `old_string`(perl 뒤의 파일 683줄부터):

```zig
            \\# 기계에서 치른다.
            \\alias tars-config='cat /config/tars.conf'
            \\alias tars-rc='cat /config/zshrc'
```

`new_string`:

```zig
            \\# 기계에서 치른다.
```

E5 — `old_string`(perl 뒤의 파일 974줄부터):

```zig
const MAX_FILE = 4096;
```

`new_string`:

```zig
///
/// pub인 이유는 `tars-config`다(TC-M0). 고친 결과가 이 수를 넘으면 쓰지
/// 않는다 — 넘는 꼬리는 init이 안 읽으므로, 쓰는 순간 사람이 적은 줄이
/// 조용히 무시되는 파일이 된다.
pub const MAX_FILE = 4096;
```

E6 — `old_string`(perl 뒤의 파일 1330줄부터):

```zig
///                       `tars-config`가 가리키는 파일 안에 두는 것이 목적이다
```

`new_string`:

```zig
///                       이 파일 안에 두는 것이 목적이다
```

### 1-3. `config_test.zig` — 편집 다섯

E1 — `old_string`(기준 파일 29줄부터):

```zig
/// `tars-config`·`tars-rc`는 SC-M1의 것이고, `ls`가 지금 유일한 셰도다
/// (design 결정 2 — 걸리는 자리 셋을 부팅으로 재서 통과시켰다).
const ALLOWED_ALIAS_NAMES = [_][]const u8{
    "tars-config", "tars-rc",
    "ls",          "ll",
    "la",          "lt",
```

`new_string`:

```zig
/// `ls`가 지금 유일한 셰도다(design 결정 2 — 걸리는 자리 셋을 부팅으로 재서
/// 통과시켰다).
///
/// SC-M1의 `tars-config`·`tars-rc`는 TC-M0이 지웠다(TC design 결정 6). 앞의
/// 것은 이제 `/usr/bin/tars-config`라는 실행 파일의 이름이고, 같은 이름의 별칭은
/// 대화형 셸에서 그 명령을 가린다 — 이 목록에 다시 넣으면 seed가 우리 명령을
/// 가리는 줄을 깐다. 뒤의 것은 사용자가 쓸모없다고 했다(2026-10-06).
const ALLOWED_ALIAS_NAMES = [_][]const u8{
    "ls", "ll",
    "la", "lt",
```

E2 — `old_string`(기준 파일 293줄부터):

```zig
    // alias가 하나도 없으면 1차 부팅의 `tars-config`가 무의미해진다.
    // 게이트는 그 alias가 있다는 것으로 "셸이 이 파일을 읽었다"를 판정한다.
```

`new_string`:

```zig
    // alias가 하나도 없으면 1차 부팅의 `ls -l /config`가 무의미해진다.
    // 게이트는 그 alias가 eza로 간다는 것으로 "셸이 이 파일을 읽었다"를
    // 판정한다(SC-M1에는 `tars-config` 별칭이 그 일을 했고 TC-M0이 지웠다).
```

E3 — `old_string`(기준 파일 299줄부터):

```zig
    // seed는 자기 파일의 이름을 자기 안에 적는다. 그 이름이 틀리면 사용자가
    // `tars-rc`를 쳤을 때 없는 파일을 cat한다 — 문서가 아니라 실행되는
    // 문장이라 틀린 것이 드러난다.
```

`new_string`:

```zig
    // seed는 자기 파일의 이름을 자기 안에 적는다(머리 주석의 "실체는 …").
    // 그 이름이 틀리면 파일을 연 사람이 엉뚱한 자리를 고친다. SC-M1에는
    // `tars-rc` 별칭이 그 이름을 실행했는데 TC-M0이 지웠고, 이제 주석만 남았다.
```

E4 — `old_string`(기준 파일 409줄부터):

```zig
/// 허용할지 정하고 여기를 고친다.
///
/// `alias tars-*`는 안 견준다. 셋 다 자기 파일 이름을 가리키므로 다른 것이
/// 정상이다(`/config/fish.config` · `/config/bashrc` · `/config/zshrc`).
```

`new_string`:

```zig
/// 허용할지 정하고 여기를 고친다.
```

E5 — `old_string`(기준 파일 423줄부터):

```zig
            if (!std.mem.startsWith(u8, line, "alias ")) continue;
            if (std.mem.startsWith(u8, line, "alias tars-")) continue;
```

`new_string`:

```zig
            if (!std.mem.startsWith(u8, line, "alias ")) continue;
```

### 1-4. 새 파일 셋

`/tmp/run/tc0/new/`에서 복사한다.

```bash
for f in config_edit.zig config_cli.zig config_edit_test.zig; do cp -p /tmp/run/tc0/new/init/src/$f init/src/$f; done
```

본문은 아래와 같다(읽기용 — 넣는 것은 위 `cp`다).

`init/src/config_edit.zig`:

```zig
//! TC-M0. `tars-config`의 순수한 쪽(TC design 결정 4).
//!
//! 시스템 콜이 하나도 없다 — `config_edit_test.zig`가 호스트에서 전부 본다. 파일을
//! 열고 쓰는 것과 마운트 표 · zoneinfo · rc 파일을 읽는 것은 `config_cli.zig`다.
//! `service_cli.zig`(시스템 콜)와 `control.zig`(글자)를 가른 선과 같다.
//!
//! 값이 맞는지는 여기서 정하지 않는다. `config.parse`에 한 줄을 주고 그 함수가
//! 무슨 말을 하는지 듣는다(`judge`). init이 부팅에 쓰는 바로 그 함수라서, 이
//! 명령이 받은 값을 init이 거절하는 일이 구조로 없다(결정 3).
const std = @import("std");
const config = @import("config.zig");

/// 값 하나의 글자를 담는 버퍼의 크기. 가장 긴 값이 `timezone`(64)이다.
pub const VALUE_MAX = 64;

comptime {
    if (VALUE_MAX < config.TZ_NAME_MAX or VALUE_MAX < config.TOGGLE_ARG_MAX or
        VALUE_MAX < config.NTP_ARG_MAX)
        @compileError("VALUE_MAX is smaller than a value config.zig can hold");
}

/// `key=value` 한 줄을 지을 버퍼의 크기. 키는 가장 긴 것이 `hangul_layout`
/// 열세 글자이고, 사람이 준 값은 `judge`가 이 안에 들어갈 때만 받는다.
pub const LINE_MAX = 256;

// ── 키 ────────────────────────────────────────────────────────────────

/// 키 이름. `Config`의 필드 이름이 곧 키다 — `parse`가 그 이름으로 가른다.
///
/// 둘이 같다는 것은 컴파일러가 아니라 `config_edit_test`가 본다. 모든 필드
/// 이름을 기본값과 함께 `parse`에 넣어 "모르는 키"가 하나도 안 나오는지를 잰다.
/// 필드를 하나 더하고 `parse`의 갈래를 빠뜨리면 거기서 멈춘다.
pub const KEYS = blk: {
    const fields = @typeInfo(config.Config).@"struct".fields;
    var names: [fields.len][]const u8 = undefined;
    for (fields, 0..) |f, i| names[i] = f.name;
    const out = names;
    break :blk out;
};

pub fn isKey(key: []const u8) bool {
    for (KEYS) |k| if (std.mem.eql(u8, k, key)) return true;
    return false;
}

/// 그 키의 값을 설정 파일에 적는 글자로. 모르는 키면 null.
///
/// 필드의 타입마다 글자로 바꾸는 법이 config.zig에 이미 있다(`@tagName` ·
/// `Toggles.arg` · `Ntp.arg` · `Timezone.slice`). 여기는 그것을 고르기만 한다.
/// 모르는 타입의 필드가 생기면 `fieldText`가 컴파일 에러를 낸다 — 새 키를
/// 더한 사람이 이 명령을 잊을 수가 없다.
pub fn valueText(c: *const config.Config, key: []const u8, buf: *[VALUE_MAX]u8) ?[]const u8 {
    inline for (@typeInfo(config.Config).@"struct".fields) |f| {
        if (std.mem.eql(u8, key, f.name)) return fieldText(f.type, @field(c, f.name), buf);
    }
    return null;
}

fn fieldText(comptime T: type, v: T, buf: *[VALUE_MAX]u8) []const u8 {
    if (T == config.Toggles) return v.arg(buf);
    if (T == config.Ntp) return v.arg(buf);
    if (T == config.Timezone) {
        const s = v.slice();
        @memcpy(buf[0..s.len], s);
        return buf[0..s.len];
    }
    if (@typeInfo(T) == .@"enum") return @tagName(v);
    @compileError("tars-config cannot print a " ++ @typeName(T) ++ "; teach config_edit.fieldText");
}

/// 그 키에 적을 수 있는 것. `help`와 거절의 둘째 줄이 쓴다. 모르는 키면 null.
///
/// enum은 이름을 컴파일 타임에 모으므로 config.zig에 이름을 하나 더하면 여기도
/// 따라온다. enum이 아닌 셋만 글로 적는다.
pub fn hint(key: []const u8) ?[]const u8 {
    inline for (@typeInfo(config.Config).@"struct".fields) |f| {
        if (std.mem.eql(u8, key, f.name)) return comptime hintFor(f.type);
    }
    return null;
}

fn hintFor(comptime T: type) []const u8 {
    if (T == config.Toggles)
        return "a comma list of " ++ join(config.ToggleKey, ", ") ++ "; empty turns them all off";
    if (T == config.Ntp) return "off | dhcp | <IPv4 address>";
    if (T == config.Timezone) return "UTC | <a name under /usr/share/zoneinfo, e.g. Asia/Seoul>";
    if (@typeInfo(T) == .@"enum") return join(T, " | ");
    @compileError("tars-config has no hint for a " ++ @typeName(T) ++ "; teach config_edit.hintFor");
}

fn join(comptime E: type, comptime sep: []const u8) []const u8 {
    comptime {
        var s: []const u8 = "";
        for (@typeInfo(E).@"enum".fields, 0..) |f, i| s = s ++ (if (i == 0) "" else sep) ++ f.name;
        return s;
    }
}

// ── 줄 ────────────────────────────────────────────────────────────────

pub const Pair = struct { key: []const u8, value: []const u8 };

/// 한 줄의 종류. `config.parse`와 같은 규칙으로 가른다 — 양 끝의 " \t\r"를
/// 떼고, 비었거나 `#`로 시작하면 건너뛰고, 첫 `=`에서 나눠 양쪽의 " \t"를 뗀다.
/// 규칙이 두 벌인 것은 `parse`가 줄의 자리(바이트 위치)를 돌려주지 않기
/// 때문이다. 두 벌이 같은지는 `config_edit_test`가 같은 줄을 둘에 넣어 본다.
pub const Line = union(enum) {
    skip,
    no_equals,
    pair: Pair,
};

pub fn classify(raw: []const u8) Line {
    const line = std.mem.trim(u8, raw, " \t\r");
    if (line.len == 0 or line[0] == '#') return .skip;
    const eq = std.mem.indexOfScalar(u8, line, '=') orelse return .no_equals;
    return .{ .pair = .{
        .key = std.mem.trim(u8, line[0..eq], " \t"),
        .value = std.mem.trim(u8, line[eq + 1 ..], " \t"),
    } };
}

/// 파일의 줄 하나. `end`는 `\n` 앞이고 `number`는 1부터 센다.
pub const Span = struct { start: usize, end: usize, number: usize };

/// 줄을 하나씩 돌려준다. 끝에 개행이 없는 마지막 줄도 줄이다.
pub const Lines = struct {
    text: []const u8,
    pos: usize = 0,
    number: usize = 0,
    done: bool = false,

    pub fn next(self: *Lines) ?Span {
        if (self.done) return null;
        const end = std.mem.indexOfScalarPos(u8, self.text, self.pos, '\n') orelse blk: {
            self.done = true;
            if (self.pos == self.text.len) return null;
            break :blk self.text.len;
        };
        self.number += 1;
        const span = Span{ .start = self.pos, .end = end, .number = self.number };
        self.pos = end + 1;
        return span;
    }
};

/// key를 적은 마지막 줄. `parse`에서 이기는 줄이 이것이다("마지막 줄이 이긴다").
pub fn lastLine(text: []const u8, key: []const u8) ?Span {
    var found: ?Span = null;
    var it = Lines{ .text = text };
    while (it.next()) |span| switch (classify(text[span.start..span.end])) {
        .pair => |p| if (std.mem.eql(u8, p.key, key)) {
            found = span;
        },
        else => {},
    };
    return found;
}

/// key를 적은 줄의 번호들. `check`가 같은 키가 두 번 이상 적힌 자리를 알린다.
/// out보다 많으면 out만큼만 담고 전체 수를 돌려준다.
pub fn lineNumbers(text: []const u8, key: []const u8, out: []usize) usize {
    var n: usize = 0;
    var it = Lines{ .text = text };
    while (it.next()) |span| switch (classify(text[span.start..span.end])) {
        .pair => |p| if (std.mem.eql(u8, p.key, key)) {
            if (n < out.len) out[n] = span.number;
            n += 1;
        },
        else => {},
    };
    return n;
}

/// text에서 key의 줄 하나만 `key=value`로 바꾼 글자를 out에 짓는다(결정 5).
///
/// 바꾸는 것은 이기는 줄(마지막 줄) 하나다. 그 줄의 앞뒤 — 사람이 적은 주석,
/// 모르는 키, 같은 키의 앞선 줄 — 는 바이트 하나 안 건드린다. 그 키의 줄이
/// 없으면 끝에 더한다. 끝에 개행이 없던 파일이면 개행을 먼저 넣는다.
///
/// 넘치면 null이다. 호출자는 그 결과가 `config.MAX_FILE`을 넘는지도 본다.
pub fn setLine(out: []u8, text: []const u8, key: []const u8, value: []const u8) ?[]const u8 {
    if (lastLine(text, key)) |s| {
        return std.fmt.bufPrint(out, "{s}{s}={s}{s}", .{
            text[0..s.start], key, value, text[s.end..],
        }) catch null;
    }
    const sep: []const u8 = if (text.len > 0 and text[text.len - 1] != '\n') "\n" else "";
    return std.fmt.bufPrint(out, "{s}{s}{s}={s}\n", .{ text, sep, key, value }) catch null;
}

// ── 듣기 ──────────────────────────────────────────────────────────────

/// `config.parse`가 한 말. 첫 줄만 담고 수를 센다.
pub const Heard = struct {
    count: usize = 0,
    len: usize = 0,
    buf: [LINE_MAX + 64]u8 = undefined,

    pub fn first(self: *const Heard) []const u8 {
        return self.buf[0..self.len];
    }
};

/// 이 명령은 스레드가 하나라 전역 하나로 된다. 듣기 전에 `.{}`로 비운다.
pub var heard: Heard = .{};

/// config.zig의 `log`가 root에서 찾는 이름. root(`config_cli.zig` ·
/// `config_edit_test.zig`)가 `pub const configLog = config_edit.configLog;`로 건다.
pub fn configLog(comptime fmt: []const u8, args: anytype) void {
    heard.count += 1;
    if (heard.count > 1) return;
    var w: std.Io.Writer = .fixed(&heard.buf);
    w.print(fmt, args) catch {};
    heard.len = w.end;
}

/// 사람이 준 `key=value` 하나에 대한 답.
pub const Verdict = union(enum) {
    /// init이 아무 말 없이 받는다. 그 한 줄만 읽은 `Config`다 — 이 키의 값을
    /// 정규형으로 되돌릴 때(`valueText`) 쓴다.
    ok: config.Config,
    unknown_key,
    /// 제어 문자. 개행 하나면 한 번의 `set`이 줄을 둘 쓴다.
    control_byte,
    too_long,
    /// init이 부팅에 이 말을 하고 그 값을 버린다. 글자는 `heard`를 가리키므로
    /// 다음 `judge` 전에 쓴다.
    refused: []const u8,
};

/// key=value를 init의 파서에 한 줄로 넣어 본다(결정 3).
///
/// 판정은 "parse가 말을 했는가" 하나다. 키마다 값을 따로 검사하는 표를 여기
/// 두지 않는다 — 그런 표는 config.zig와 두 벌이 되고, 둘이 갈라지는 날 이
/// 명령은 init이 버릴 값을 써 준다.
pub fn judge(line_buf: *[LINE_MAX]u8, key: []const u8, value: []const u8) Verdict {
    for (key) |b| if (b < 0x20 or b == 0x7f) return .control_byte;
    for (value) |b| if (b < 0x20 or b == 0x7f) return .control_byte;
    if (!isKey(key)) return .unknown_key;
    const line = std.fmt.bufPrint(line_buf, "{s}={s}", .{ key, value }) catch return .too_long;
    heard = .{};
    const c = config.parse(line);
    if (heard.count != 0) return .{ .refused = heard.first() };
    return .{ .ok = c };
}

/// 그 키를 파일의 어느 줄이 정하는가. 정하는 줄이 없으면(줄이 없거나 있는
/// 줄을 init이 전부 버리면) 기본값이고 `show`가 그 줄 앞에 `#`를 붙인다.
///
/// `lastLine`만 보면 틀린다. 마지막 줄의 값이 틀리면 `parse`는 그 줄을 버리고
/// 앞 줄의 값에 머문다 — 줄마다 `judge`로 듣는다.
pub fn setByFile(line_buf: *[LINE_MAX]u8, text: []const u8, key: []const u8) bool {
    var it = Lines{ .text = text };
    while (it.next()) |span| switch (classify(text[span.start..span.end])) {
        .pair => |p| if (std.mem.eql(u8, p.key, key)) {
            if (judge(line_buf, p.key, p.value) == .ok) return true;
        },
        else => {},
    };
    return false;
}

// ── 파일 밖의 글자 ────────────────────────────────────────────────────

/// `/proc/mounts`에서 mountpoint에 붙은 것의 원천(`/dev/vda`). 없으면 null.
/// 같은 자리에 여럿이 붙었으면 마지막 것이 보이는 것이다.
pub fn mountSource(mounts: []const u8, mountpoint: []const u8) ?[]const u8 {
    var found: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, mounts, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeScalar(u8, line, ' ');
        const source = fields.next() orelse continue;
        const target = fields.next() orelse continue;
        if (std.mem.eql(u8, target, mountpoint)) found = source;
    }
    return found;
}

/// 옛 seed가 rc에 남긴 `alias tars-config=…`의 줄 번호(결정 6). 없으면 null.
///
/// 그 별칭은 대화형 셸에서 `/usr/bin/tars-config`를 가린다 — 친 것이 이 명령이
/// 아니라 `cat /config/tars.conf`가 된다. seed는 "없으면 만든다"라서 TC 전에
/// 만든 디스크의 rc에는 그 줄이 그대로 있다. 이 명령은 그 줄을 지우지 않는다.
/// rc는 사람의 파일이다(SC design 결정 7). 알리기만 한다.
pub fn staleAlias(rc: []const u8) ?usize {
    const name = "alias tars-config";
    var it = Lines{ .text = rc };
    while (it.next()) |span| {
        const line = std.mem.trim(u8, rc[span.start..span.end], " \t\r");
        if (!std.mem.startsWith(u8, line, name)) continue;
        if (line.len == name.len) continue;
        switch (line[name.len]) {
            '=', ' ', '\t' => return span.number,
            else => {},
        }
    }
    return null;
}
```

`init/src/config_cli.zig`:

```zig
//! TC-M0. `tars-config` — `/config/tars.conf`를 보고 고치는 명령(TC design 결정 1).
//!
//! init이 부팅에 한 번 읽는 그 파일을 사람이 셸에서 다룬다. 인자 없이 치면 init이
//! 읽을 모양으로 보여 주고, `get` · `set` · `reset` · `check`가 있다. 값이 맞는지는
//! init과 같은 `config.parse`가 정하고(`config_edit.judge`), 쓰는 것은 그 키의 줄
//! 하나다. 고친 것은 다음 부팅부터다 — init은 이 파일을 다시 읽지 않는다(결정 7).
//!
//! 이 파일은 시스템 콜 쪽이다. 글자를 다루는 것은 전부 `config_edit.zig`이고 호스트
//! 검사가 본다. 표준 출력은 사람이 읽는 답이고, 거절과 실패는 `tars-config: `로
//! 시작하는 줄로 표준 에러에 간다.
const std = @import("std");
const linux = std.os.linux;
const config = @import("config.zig");
const edit = @import("config_edit.zig");

/// config.zig의 로그를 가로챈다(config.zig의 `log`). 이 한 줄이 없으면 `set`이 틀린
/// 값을 받을 때 `tars-init: unknown shell …`이 이 명령의 표준 에러에 그대로 찍히고,
/// 거절의 이유를 이 명령이 들을 수 없다.
pub const configLog = edit.configLog;

const CONF_PATH: [:0]const u8 = "/config/tars.conf";
/// 새 내용을 먼저 여기 쓰고 `rename`으로 갈아 끼운다(결정 5). 쓰다 끊겨도 init이
/// 읽는 파일은 옛것 그대로이거나 새것 그대로다. `/config`는 `MS_SYNCHRONOUS`라
/// write와 rename이 돌아온 때 이미 디스크에 있다.
const TEMP_PATH: [:0]const u8 = "/config/.tars.conf.new";
const MOUNTS_PATH: [:0]const u8 = "/proc/mounts";
const CONFIG_DIR = "/config";

const EXIT_OK: u8 = 0;
/// 값을 거절했다 · `check`가 문제를 찾았다.
const EXIT_REFUSED: u8 = 1;
/// 설정 디스크가 없다 · 파일을 못 읽거나 못 썼다.
const EXIT_IO: u8 = 2;
const EXIT_USAGE: u8 = 64;

/// 한 번의 `set` · `reset`이 받는 쌍의 상한.
const PAIRS_MAX = 16;
/// 파일을 읽는 버퍼. `config.MAX_FILE`의 두 배라 넘는 파일을 "넘는다"고 말할 수 있다.
const READ_MAX = 2 * config.MAX_FILE;

fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

fn writeAll(fd: i32, bytes: []const u8) bool {
    var off: usize = 0;
    while (off < bytes.len) {
        const n = linux.write(fd, bytes[off..].ptr, bytes.len - off);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            return false;
        }
        if (n == 0) return false;
        off += n;
    }
    return true;
}

fn say(comptime fmt: []const u8, args: anytype) void {
    var buf: [READ_MAX + 256]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, fmt, args) catch return;
    _ = writeAll(1, text);
}

fn complain(comptime fmt: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "tars-config: " ++ fmt ++ "\n", args) catch return;
    _ = writeAll(2, text);
}

const USAGE =
    \\usage: tars-config                     show /config/tars.conf as init reads it
    \\       tars-config get KEY             print one value
    \\       tars-config set KEY=VALUE...    change values; init reads them at the next boot
    \\       tars-config reset KEY...        put keys back to their defaults
    \\       tars-config check               list the lines init would complain about
    \\       tars-config help                keys and the values they take
    \\
;

fn usage() u8 {
    _ = writeAll(2, USAGE);
    return EXIT_USAGE;
}

fn help() u8 {
    _ = writeAll(1, USAGE);
    say("\nkeys (with their defaults):\n", .{});
    const defaults = config.Config{};
    for (edit.KEYS) |key| {
        var vbuf: [edit.VALUE_MAX]u8 = undefined;
        var pair_buf: [edit.LINE_MAX]u8 = undefined;
        const pair = std.fmt.bufPrint(&pair_buf, "{s}={s}", .{ key, edit.valueText(&defaults, key, &vbuf).? }) catch key;
        say("  {s:<26} {s}\n", .{ pair, edit.hint(key).? });
    }
    say("\ninit reads /config/tars.conf only at boot. To reboot: kill -INT 1\n", .{});
    return EXIT_OK;
}

// ── 읽기 ──────────────────────────────────────────────────────────────

const Read = union(enum) { missing, failed: linux.E, bytes: []const u8 };

fn readFile(path: [*:0]const u8, buf: []u8) Read {
    const rc = linux.open(path, .{ .ACCMODE = .RDONLY }, 0);
    if (failed(rc)) |e| return if (e == .NOENT) .missing else .{ .failed = e };
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var len: usize = 0;
    while (len < buf.len) {
        const n = linux.read(fd, buf[len..].ptr, buf.len - len);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            return .{ .failed = e };
        }
        if (n == 0) break;
        len += n;
    }
    return .{ .bytes = buf[0..len] };
}

/// `/config`에 붙은 장치. init이 설정 디스크를 찾았을 때만 있다 — 못 찾은 부팅의
/// `/config`는 initrd 안의 빈 디렉터리이고 init은 거기서 파일을 읽지도 않는다.
fn configDisk(buf: []u8) ?[]const u8 {
    return switch (readFile(MOUNTS_PATH, buf)) {
        .bytes => |b| edit.mountSource(b, CONFIG_DIR),
        else => null,
    };
}

/// 지금의 설정. init이 다음 부팅에 읽을 것과 같은 길로 읽는다.
const Current = struct {
    /// 설정 디스크의 장치. null이면 디스크가 없고 `text`는 비어 있다.
    disk: ?[]const u8,
    exists: bool,
    text: []const u8,
};

fn current(mounts_buf: []u8, text_buf: []u8) ?Current {
    const disk = configDisk(mounts_buf) orelse return .{ .disk = null, .exists = false, .text = "" };
    return switch (readFile(CONF_PATH, text_buf)) {
        .missing => .{ .disk = disk, .exists = false, .text = "" },
        .bytes => |b| .{ .disk = disk, .exists = true, .text = b },
        .failed => |e| {
            complain("cannot read {s} (errno {d})", .{ CONF_PATH, @intFromEnum(e) });
            return null;
        },
    };
}

/// init의 `load`가 하는 것과 같다 — 앞의 `MAX_FILE` 바이트만 `parse`에 준다.
fn parsed(text: []const u8) config.Config {
    return config.parse(text[0..@min(text.len, config.MAX_FILE)]);
}

/// main.zig의 `zoneinfoIsTzif`와 같은 판정이다(그 함수가 private이라 여기 둔다 —
/// 열 줄짜리 시스템 콜을 공용 모듈로 빼는 것보다 각자 갖는 편이 이 저장소의 선이다).
fn zoneinfoIsTzif(path: [:0]const u8) bool {
    const rc = linux.open(path.ptr, .{ .ACCMODE = .RDONLY }, 0);
    if (failed(rc)) |_| return false;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var head: [config.TZIF_MAGIC.len]u8 = undefined;
    const n = linux.read(fd, &head, head.len);
    if (failed(n)) |_| return false;
    return config.looksLikeTzif(head[0..n]);
}

/// init이 부팅에 받아 놓고 다른 길로 버리는 값. 지금은 `timezone` 하나다 —
/// `parse`는 모양만 보고, 파일이 정말 있는지는 main.zig의 `resolveTimezone`이 본다.
/// 버리면 null이 아니라 그 이유를 path_buf에 지어 돌려준다.
fn bootRefuses(c: *const config.Config, path_buf: *[config.ZONEINFO_PATH_MAX]u8) ?[:0]const u8 {
    if (c.timezone.eql(config.Timezone.UTC)) return null;
    const path = config.zoneinfoPath(path_buf, c.timezone);
    if (zoneinfoIsTzif(path)) return null;
    return path;
}

// ── show · get ────────────────────────────────────────────────────────

fn show() u8 {
    var mounts_buf: [8192]u8 = undefined;
    var text_buf: [READ_MAX]u8 = undefined;
    const cur = current(&mounts_buf, &text_buf) orelse return EXIT_IO;
    if (cur.disk) |disk| {
        if (cur.exists) {
            say("# {s} on {s}, as init reads it at boot\n", .{ CONF_PATH, disk });
        } else {
            say("# {s} on {s} does not exist yet; init writes it at the next boot\n", .{ CONF_PATH, disk });
        }
    } else {
        say("# no config disk: init uses the defaults and nothing here outlives a power off\n", .{});
    }
    say("# a line starting with # is a default; the file does not set it\n", .{});

    edit.heard = .{};
    const c = parsed(cur.text);
    const complaints = edit.heard.count;
    var line_buf: [edit.LINE_MAX]u8 = undefined;
    for (edit.KEYS) |key| {
        var vbuf: [edit.VALUE_MAX]u8 = undefined;
        const value = edit.valueText(&c, key, &vbuf).?;
        const mark = if (edit.setByFile(&line_buf, cur.text[0..@min(cur.text.len, config.MAX_FILE)], key)) "" else "#";
        say("{s}{s}={s}\n", .{ mark, key, value });
    }

    if (complaints > 0) say("# init complains about {d} line(s) of this file; tars-config check lists them\n", .{complaints});
    var path_buf: [config.ZONEINFO_PATH_MAX]u8 = undefined;
    if (bootRefuses(&c, &path_buf)) |path| say("# {s} is not a zoneinfo file; init falls back to UTC\n", .{path});
    edit.heard = .{};
    if (config.cmdlineNoConfig(config.CMDLINE_PATH))
        say("# {s} is on the kernel command line: this boot's shells read no rc\n", .{config.NO_CONFIG_TOKEN});
    if (cur.disk != null) say("# change: tars-config set KEY=VALUE, then reboot (kill -INT 1)\n", .{});
    return EXIT_OK;
}

fn get(key: []const u8) u8 {
    if (!edit.isKey(key)) return unknownKey(key);
    var mounts_buf: [8192]u8 = undefined;
    var text_buf: [READ_MAX]u8 = undefined;
    const cur = current(&mounts_buf, &text_buf) orelse return EXIT_IO;
    edit.heard = .{};
    const c = parsed(cur.text);
    var vbuf: [edit.VALUE_MAX]u8 = undefined;
    say("{s}\n", .{edit.valueText(&c, key, &vbuf).?});
    return EXIT_OK;
}

fn unknownKey(key: []const u8) u8 {
    complain("unknown key '{s}'; tars-config help lists the keys", .{key});
    return EXIT_USAGE;
}

// ── set · reset ───────────────────────────────────────────────────────

/// set과 reset이 함께 쓰는 길. pairs의 값은 사람이 준 글자다.
fn change(pairs: []const edit.Pair) u8 {
    var mounts_buf: [8192]u8 = undefined;
    if (configDisk(&mounts_buf) == null) {
        complain("no config disk is mounted at /config; a change there would be gone at the next boot", .{});
        complain("attach an ext2 disk labelled tars-* (docs/guides/running-tars.md)", .{});
        return EXIT_IO;
    }

    // 1. 전부 먼저 듣는다. 하나라도 거절이면 아무것도 안 쓴다.
    var canon_bufs: [PAIRS_MAX][edit.VALUE_MAX]u8 = undefined;
    var canon: [PAIRS_MAX][]const u8 = undefined;
    var line_buf: [edit.LINE_MAX]u8 = undefined;
    var refused = false;
    for (pairs, 0..) |p, i| {
        switch (edit.judge(&line_buf, p.key, p.value)) {
            .ok => |c| {
                canon[i] = edit.valueText(&c, p.key, &canon_bufs[i]).?;
                var path_buf: [config.ZONEINFO_PATH_MAX]u8 = undefined;
                if (bootRefuses(&c, &path_buf)) |path| {
                    complain("{s}={s}: {s} is not a zoneinfo file; init would fall back to UTC", .{ p.key, p.value, path });
                    refused = true;
                }
            },
            .unknown_key => {
                complain("unknown key '{s}'; tars-config help lists the keys", .{p.key});
                refused = true;
            },
            .control_byte => {
                complain("{s}: a control character cannot go into a config line", .{p.key});
                refused = true;
            },
            .too_long => {
                complain("{s}: the value is too long", .{p.key});
                refused = true;
            },
            .refused => |said| {
                complain("{s}={s}: init would say \"{s}\"", .{ p.key, p.value, said });
                complain("{s} takes {s}", .{ p.key, edit.hint(p.key).? });
                refused = true;
            },
        }
    }
    if (refused) {
        complain("nothing was written", .{});
        return EXIT_REFUSED;
    }

    // 2. 지금의 파일. 없으면 init이 첫 부팅에 쓸 seed를 먼저 짓고 거기에 고친다 —
    //    한 줄짜리 파일을 만들면 사람이 seed의 주석을 영영 못 받는다.
    var text_buf: [READ_MAX]u8 = undefined;
    var text: []const u8 = switch (readFile(CONF_PATH, &text_buf)) {
        .bytes => |b| b,
        .failed => |e| {
            complain("cannot read {s} (errno {d})", .{ CONF_PATH, @intFromEnum(e) });
            return EXIT_IO;
        },
        .missing => seed: {
            edit.heard = .{};
            config.save(TEMP_PATH, .{}) catch {
                complain("cannot write {s}: {s}", .{ TEMP_PATH, edit.heard.first() });
                return EXIT_IO;
            };
            break :seed switch (readFile(TEMP_PATH, &text_buf)) {
                .bytes => |b| b,
                else => {
                    complain("cannot read back {s}", .{TEMP_PATH});
                    return EXIT_IO;
                },
            };
        },
    };
    if (text.len > config.MAX_FILE) {
        complain("{s} is longer than the {d} bytes init reads; shorten it first", .{ CONF_PATH, config.MAX_FILE });
        return EXIT_REFUSED;
    }
    const before = text;

    // 3. 쌍마다 그 키의 줄 하나를 바꾼다. 버퍼 둘을 번갈아 쓴다.
    var work: [2][READ_MAX]u8 = undefined;
    var olds: [PAIRS_MAX][edit.VALUE_MAX]u8 = undefined;
    var old_text: [PAIRS_MAX][]const u8 = undefined;
    var old_default: [PAIRS_MAX]bool = undefined;
    for (pairs, 0..) |p, i| {
        edit.heard = .{};
        const was = parsed(text);
        old_text[i] = edit.valueText(&was, p.key, &olds[i]).?;
        old_default[i] = !edit.setByFile(&line_buf, text, p.key);
        text = edit.setLine(&work[i % 2], text, p.key, canon[i]) orelse {
            complain("{s} would grow past {d} bytes", .{ CONF_PATH, READ_MAX });
            return EXIT_REFUSED;
        };
    }
    if (text.len > config.MAX_FILE) {
        complain("{s} would be longer than the {d} bytes init reads; nothing was written", .{ CONF_PATH, config.MAX_FILE });
        return EXIT_REFUSED;
    }

    // 4. 쓴다. 같으면 안 쓴다.
    if (!std.mem.eql(u8, text, before) or !fileExists(CONF_PATH)) {
        if (!writeFile(TEMP_PATH, text)) return EXIT_IO;
        if (failed(linux.rename(TEMP_PATH, CONF_PATH))) |e| {
            complain("cannot rename {s} to {s} (errno {d})", .{ TEMP_PATH, CONF_PATH, @intFromEnum(e) });
            return EXIT_IO;
        }
    }
    for (pairs, 0..) |p, i| {
        if (std.mem.eql(u8, old_text[i], canon[i])) {
            say("{s}: {s} (unchanged)\n", .{ p.key, canon[i] });
        } else {
            say("{s}: {s}{s} -> {s}\n", .{ p.key, old_text[i], if (old_default[i]) " (default)" else "", canon[i] });
        }
    }
    say("init reads {s} only at boot; reboot to apply (kill -INT 1)\n", .{CONF_PATH});
    return EXIT_OK;
}

fn fileExists(path: [:0]const u8) bool {
    return failed(linux.access(path.ptr, linux.F_OK)) == null;
}

fn writeFile(path: [:0]const u8, text: []const u8) bool {
    const rc = linux.open(path.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    if (failed(rc)) |e| {
        complain("cannot create {s} (errno {d})", .{ path, @intFromEnum(e) });
        return false;
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    if (!writeAll(fd, text)) {
        complain("cannot write {s}", .{path});
        return false;
    }
    return true;
}

// ── check ─────────────────────────────────────────────────────────────

fn check() u8 {
    var mounts_buf: [8192]u8 = undefined;
    var text_buf: [READ_MAX]u8 = undefined;
    const cur = current(&mounts_buf, &text_buf) orelse return EXIT_IO;
    if (cur.disk == null) {
        say("no config disk: init uses the defaults and reads no file\n", .{});
        return EXIT_OK;
    }
    if (!cur.exists) {
        say("{s} does not exist yet; init writes it at the next boot\n", .{CONF_PATH});
        return EXIT_OK;
    }
    var problems: usize = 0;
    const text = cur.text;
    if (text.len > config.MAX_FILE) {
        say("{s} is {d} bytes or more; init reads only the first {d}\n", .{ CONF_PATH, text.len, config.MAX_FILE });
        problems += 1;
    }

    // 줄마다 init의 파서에 따로 넣는다. 줄 사이에 상태가 없는 파서라(마지막 줄이
    // 이긴다는 것뿐이다) 한 줄씩 들어도 init이 파일째로 읽을 때와 같은 말을 한다.
    var it = edit.Lines{ .text = text };
    while (it.next()) |span| {
        if (span.start >= config.MAX_FILE) break;
        const raw = text[span.start..span.end];
        if (edit.classify(raw) == .skip) continue;
        edit.heard = .{};
        _ = config.parse(raw);
        if (edit.heard.count == 0) continue;
        say("line {d}: {s}\n", .{ span.number, edit.heard.first() });
        problems += 1;
    }

    // 같은 키가 둘 이상이면 알린다. 틀린 것은 아니다 — 마지막 줄이 이긴다.
    for (edit.KEYS) |key| {
        var numbers: [8]usize = undefined;
        const n = edit.lineNumbers(text, key, &numbers);
        if (n < 2) continue;
        say("{s} is on {d} lines (", .{ key, n });
        for (numbers[0..@min(n, numbers.len)], 0..) |num, i| say("{s}{d}", .{ if (i == 0) "" else ", ", num });
        say("); the last one wins\n", .{});
    }

    edit.heard = .{};
    const c = parsed(text);
    var path_buf: [config.ZONEINFO_PATH_MAX]u8 = undefined;
    if (bootRefuses(&c, &path_buf)) |path| {
        say("timezone {s}: {s} is not a zoneinfo file; init falls back to UTC\n", .{ c.timezone.slice(), path });
        problems += 1;
    }

    // 옛 seed의 별칭(결정 6). 이 명령을 가리므로 문제로 센다. 지우지는 않는다.
    var rc_buf: [65536]u8 = undefined;
    for (std.enums.values(config.Shell)) |sh| {
        const rc = switch (readFile(sh.rcPath(), &rc_buf)) {
            .bytes => |b| b,
            else => continue,
        };
        const number = edit.staleAlias(rc) orelse continue;
        say("{s} line {d}: alias tars-config hides this command in {s}; delete that line\n", .{ sh.rcPath(), number, @tagName(sh) });
        problems += 1;
    }

    if (problems == 0) {
        say("{s}: init reads every line without a complaint\n", .{CONF_PATH});
        return EXIT_OK;
    }
    say("{d} problem(s)\n", .{problems});
    return EXIT_REFUSED;
}

// ── main ──────────────────────────────────────────────────────────────

pub fn main(init: std.process.Init.Minimal) u8 {
    const argv = init.args.vector;
    if (argv.len < 2) return show();
    const verb = std.mem.span(argv[1]);
    const rest = argv[2..];

    if (std.mem.eql(u8, verb, "help") or std.mem.eql(u8, verb, "-h") or std.mem.eql(u8, verb, "--help")) {
        if (rest.len != 0) return usage();
        return help();
    }
    if (std.mem.eql(u8, verb, "check")) {
        if (rest.len != 0) return usage();
        return check();
    }
    if (std.mem.eql(u8, verb, "get")) {
        if (rest.len != 1) return usage();
        return get(std.mem.trim(u8, std.mem.span(rest[0]), " \t"));
    }
    const is_set = std.mem.eql(u8, verb, "set");
    if (!is_set and !std.mem.eql(u8, verb, "reset")) return usage();
    if (rest.len == 0 or rest.len > PAIRS_MAX) return usage();

    var pairs: [PAIRS_MAX]edit.Pair = undefined;
    var default_bufs: [PAIRS_MAX][edit.VALUE_MAX]u8 = undefined;
    const defaults = config.Config{};
    for (rest, 0..) |arg_z, i| {
        const arg = std.mem.span(arg_z);
        if (is_set) {
            // 설정 파일의 한 줄과 같은 규칙으로 가른다 — 첫 `=`, 양쪽 공백.
            const eq = std.mem.indexOfScalar(u8, arg, '=') orelse {
                complain("'{s}' has no '='; set takes KEY=VALUE", .{arg});
                return EXIT_USAGE;
            };
            pairs[i] = .{
                .key = std.mem.trim(u8, arg[0..eq], " \t"),
                .value = std.mem.trim(u8, arg[eq + 1 ..], " \t"),
            };
        } else {
            const key = std.mem.trim(u8, arg, " \t");
            const value = edit.valueText(&defaults, key, &default_bufs[i]) orelse return unknownKey(key);
            pairs[i] = .{ .key = key, .value = value };
        }
    }
    return change(pairs[0..rest.len]);
}
```

`init/src/config_edit_test.zig`:

```zig
//! TC-M0. `config_edit.zig`의 검사. config_test와 같은 모양이다 — 호스트 아키텍처의
//! 실행 파일이고, 실패하면 `FAIL:` 줄을 찍고 0이 아닌 코드로 끝난다.
//!
//! 이 파일이 root라서 아래 `configLog`가 config.zig의 로그를 가로챈다. `judge`가
//! 듣는 것이 그 길이고, 그래서 여기서는 `tars-init:` 줄이 하나도 안 찍힌다.
const std = @import("std");
const linux = std.os.linux;
const config = @import("config.zig");
const edit = @import("config_edit.zig");

pub const configLog = edit.configLog;

/// `config.save`가 seed를 쓰는 자리. 게스트가 아니라 빌드 컨테이너의 /tmp다.
const SEED_PATH: [:0]const u8 = "/tmp/tars-config-edit-test.conf";

fn fail(comptime fmt: []const u8, args: anytype) error{Failed} {
    std.debug.print("FAIL: " ++ fmt ++ "\n", args);
    return error.Failed;
}

/// 기본값이 아닌 값 하나씩. 키를 하나 더하면 이 표가 먼저 멈춘다 — 모든 키를
/// 진짜 seed에 써 보는 검사(아래 4)가 그 키를 빠뜨리지 않게 하는 자리다.
const OTHER = [_]edit.Pair{
    .{ .key = "shell", .value = "zsh" },
    .{ .key = "keyboard", .value = "pc" },
    .{ .key = "hangul_layout", .value = "dubeol" },
    .{ .key = "latin_layout", .value = "dvorak" },
    .{ .key = "hangul_toggle", .value = "shift_space" },
    .{ .key = "shell_config", .value = "off" },
    .{ .key = "net", .value = "dhcp" },
    .{ .key = "ntp", .value = "10.0.2.2" },
    .{ .key = "timezone", .value = "Asia/Seoul" },
    .{ .key = "firewall", .value = "on" },
    .{ .key = "esc_latin", .value = "off" },
    .{ .key = "clipboard", .value = "pane" },
};

fn other(key: []const u8) ?[]const u8 {
    for (OTHER) |p| if (std.mem.eql(u8, p.key, key)) return p.value;
    return null;
}

fn valueOf(c: *const config.Config, key: []const u8, buf: *[edit.VALUE_MAX]u8) []const u8 {
    return edit.valueText(c, key, buf).?;
}

fn expectOk(key: []const u8, value: []const u8, want_canon: []const u8) !void {
    var line: [edit.LINE_MAX]u8 = undefined;
    switch (edit.judge(&line, key, value)) {
        .ok => |c| {
            var buf: [edit.VALUE_MAX]u8 = undefined;
            const got = valueOf(&c, key, &buf);
            if (!std.mem.eql(u8, got, want_canon))
                return fail("judge {s}=\"{s}\" wrote \"{s}\", want \"{s}\"", .{ key, value, got, want_canon });
        },
        else => |v| return fail("judge {s}=\"{s}\" gave {s}, want ok", .{ key, value, @tagName(v) }),
    }
}

fn expectRefused(key: []const u8, value: []const u8, want_said: []const u8) !void {
    var line: [edit.LINE_MAX]u8 = undefined;
    switch (edit.judge(&line, key, value)) {
        .refused => |said| if (!std.mem.eql(u8, said, want_said))
            return fail("judge {s}=\"{s}\" heard \"{s}\", want \"{s}\"", .{ key, value, said, want_said }),
        else => |v| return fail("judge {s}=\"{s}\" gave {s}, want refused", .{ key, value, @tagName(v) }),
    }
}

fn expectVerdict(key: []const u8, value: []const u8, want: std.meta.Tag(edit.Verdict)) !void {
    var line: [edit.LINE_MAX]u8 = undefined;
    const got = edit.judge(&line, key, value);
    if (got != want) return fail("judge {s}=\"{s}\" gave {s}, want {s}", .{ key, value, @tagName(got), @tagName(want) });
}

fn expectSet(text: []const u8, key: []const u8, value: []const u8, want: []const u8) !void {
    var out: [config.MAX_FILE * 2]u8 = undefined;
    const got = edit.setLine(&out, text, key, value) orelse return fail("setLine {s}={s} overflowed", .{ key, value });
    if (!std.mem.eql(u8, got, want))
        return fail("setLine {s}={s} on\n{s}\n--- gave ---\n{s}\n--- want ---\n{s}", .{ key, value, text, got, want });
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

/// a와 b가 정확히 한 줄만 다른가.
fn oneLineApart(a: []const u8, b: []const u8) bool {
    var ia = edit.Lines{ .text = a };
    var ib = edit.Lines{ .text = b };
    var diffs: usize = 0;
    while (true) {
        const sa = ia.next();
        const sb = ib.next();
        if (sa == null and sb == null) break;
        if (sa == null or sb == null) return false;
        if (!std.mem.eql(u8, a[sa.?.start..sa.?.end], b[sb.?.start..sb.?.end])) diffs += 1;
    }
    return diffs == 1;
}

pub fn main() !void {
    // ── 1. 키는 Config의 필드 이름이고, parse가 그 이름을 전부 안다 ─────
    //
    // 필드를 더하고 parse의 갈래를 빠뜨리면 여기서 "unknown config key"를 듣는다.
    // 기본값을 글자로 바꿨다가 되읽어 같은지도 본다 — valueText와 parse가 같은
    // 글자를 쓴다는 것이 `set`이 쓰는 줄을 init이 읽는다는 뜻이다.
    if (edit.KEYS.len != 12) return fail("{d} keys, want 12 (the seed has twelve)", .{edit.KEYS.len});
    const defaults = config.Config{};
    for (edit.KEYS) |key| {
        var buf: [edit.VALUE_MAX]u8 = undefined;
        try expectOk(key, valueOf(&defaults, key, &buf), valueOf(&defaults, key, &buf));
        const v = other(key) orelse return fail("OTHER has no row for {s}", .{key});
        try expectOk(key, v, v);
        if (edit.hint(key) == null) return fail("no hint for {s}", .{key});
    }
    if (OTHER.len != edit.KEYS.len) return fail("OTHER has {d} rows for {d} keys", .{ OTHER.len, edit.KEYS.len });
    if (edit.isKey("colour") or edit.hint("colour") != null) return fail("colour is a key", .{});
    if (!std.mem.eql(u8, edit.hint("shell").?, "fish | bash | zsh")) return fail("shell hint {s}", .{edit.hint("shell").?});
    std.debug.print("config_edit_test: twelve keys, each read back by parse as written\n", .{});

    // ── 2. judge — init이 하는 말이 곧 거절의 이유다 ───────────────────
    try expectRefused("shell", "fsh", "unknown shell 'fsh', falling back to fish");
    try expectRefused("net", "on", "unknown net 'on', falling back to off");
    try expectRefused("ntp", "pool.ntp.org", "unknown ntp 'pool.ntp.org', falling back to off");
    try expectRefused("timezone", "/etc/passwd", "unknown timezone '/etc/passwd', falling back to UTC");
    // 목록은 init이 이름 하나만 버리고 나머지를 받는다. set은 그 하나 때문에 통째로 거절한다.
    try expectRefused("hangul_toggle", "nosuch,shift_space", "unknown hangul_toggle 'nosuch', ignored");
    try expectRefused("shell", "", "unknown shell '', falling back to fish");
    try expectVerdict("colour", "red", .unknown_key);
    try expectVerdict("", "zsh", .unknown_key);
    // 개행 하나가 한 번의 set을 두 줄로 만든다.
    try expectVerdict("shell", "zsh\nnet=dhcp", .control_byte);
    try expectVerdict("shell", "zsh\r", .control_byte);
    try expectVerdict("timezone", "a" ** 300, .too_long);
    // 정규형으로 쓴다 — 적은 순서 · 공백 · 0으로 시작하는 주소가 init의 글자로 바뀐다.
    try expectOk("hangul_toggle", " lctrl_tap , shift_space ", "shift_space,lctrl_tap");
    try expectOk("hangul_toggle", "", "none");
    try expectOk("hangul_toggle", "none", "none");
    try expectOk("ntp", "010.000.2.2", "10.0.2.2");
    // 모양만 본다. 그 파일이 있는지는 config_cli의 bootRefuses가 게스트에서 본다.
    try expectOk("timezone", "Asia/Seol", "Asia/Seol");
    std.debug.print("config_edit_test: judge hears init's own words, refuses control bytes, writes the canonical form\n", .{});

    // ── 3. classify는 parse와 같은 규칙으로 가른다 ───────────────────────
    //
    // 줄마다 둘에 함께 넣는다. parse가 말없이 받는 줄은 classify가 건너뛰는 줄이거나
    // judge가 받는 쌍이어야 하고, 그 반대도 같다.
    const lines = [_][]const u8{
        "",               "   ",            "# shell=zsh",  "  # x",           "shell=zsh",
        "  shell = zsh  ", "\tshell\t=\tzsh", "shell=zsh\r",  "shell=zsh=extra", "no equals",
        "=zsh",           "shell=",         "colour=red",   "net = dhcp",      "hangul_toggle=",
        "ntp=1.2.3",      "timezone = Asia/Seoul",
    };
    for (lines) |raw| {
        edit.heard = .{};
        _ = config.parse(raw);
        const quiet = edit.heard.count == 0;
        var lbuf: [edit.LINE_MAX]u8 = undefined;
        const accepted = switch (edit.classify(raw)) {
            .skip => true,
            .no_equals => false,
            .pair => |p| edit.judge(&lbuf, p.key, p.value) == .ok,
        };
        if (quiet != accepted) return fail("\"{s}\": parse quiet={}, classify+judge accepted={}", .{ raw, quiet, accepted });
    }
    switch (edit.classify("  shell = zsh  \r")) {
        .pair => |p| if (!std.mem.eql(u8, p.key, "shell") or !std.mem.eql(u8, p.value, "zsh"))
            return fail("classify gave [{s}]=[{s}]", .{ p.key, p.value }),
        else => return fail("classify did not see a pair", .{}),
    }
    std.debug.print("config_edit_test: classify splits {d} lines the way parse does\n", .{lines.len});

    // ── 4. setLine — 그 키의 이기는 줄 하나만 바꾼다 ─────────────────────
    try expectSet("", "net", "dhcp", "net=dhcp\n");
    try expectSet("shell=zsh", "net", "dhcp", "shell=zsh\nnet=dhcp\n");
    try expectSet("shell=zsh\n", "net", "dhcp", "shell=zsh\nnet=dhcp\n");
    // 마지막 줄이 이기므로 그 줄을 바꾼다. 앞 줄은 그대로 둔다(check가 알린다).
    try expectSet("shell=zsh\nnet=off\nshell=bash\n", "shell", "fish", "shell=zsh\nnet=off\nshell=fish\n");
    // 사람의 주석 · 모르는 키 · 틀린 줄 · 끝에 개행 없음 — 바꾸는 줄 밖은 바이트 하나 안 바뀐다.
    try expectSet("# mine\ncolour=red\n  net = off  # old\nno equals\nkeyboard=pc",
        "net", "dhcp", "# mine\ncolour=red\nnet=dhcp\nno equals\nkeyboard=pc");
    // CRLF 줄은 그 줄만 LF가 된다(parse는 \r을 뗀다).
    try expectSet("shell=zsh\r\nnet=off\r\n", "net", "dhcp", "shell=zsh\r\nnet=dhcp\n");
    // 주석 안의 키는 줄이 아니다.
    try expectSet("#net=dhcp\n", "net", "off", "#net=dhcp\nnet=off\n");
    {
        var small: [8]u8 = undefined;
        if (edit.setLine(&small, "shell=zsh\n", "net", "dhcp") != null) return fail("setLine fit 19 bytes in 8", .{});
    }
    if (edit.lastLine("shell=zsh\nnet=off\nshell=bash", "shell").?.number != 3) return fail("lastLine number", .{});
    if (edit.lastLine("#shell=zsh\n", "shell") != null) return fail("lastLine found a comment", .{});
    {
        var nums: [4]usize = undefined;
        const n = edit.lineNumbers("shell=a\n\nshell=b\n# shell=c\nshell=d\n", "shell", &nums);
        if (n != 3 or nums[0] != 1 or nums[1] != 3 or nums[2] != 5) return fail("lineNumbers gave {d}", .{n});
    }

    // 진짜 seed — init이 첫 부팅에 쓰는 그 파일 — 에서 키마다 한 번씩. 바뀐 것이 그
    // 한 줄뿐이고, parse가 새 값을 읽고, 다른 열한 키는 기본값 그대로다.
    config.save(SEED_PATH, defaults) catch return fail("config.save {s}", .{SEED_PATH});
    var seed_buf: [config.MAX_FILE]u8 = undefined;
    const seed = try readAll(SEED_PATH, &seed_buf);
    _ = linux.unlink(SEED_PATH);
    if (seed.len < 500) return fail("the seed is only {d} bytes", .{seed.len});
    for (edit.KEYS) |key| {
        var out: [config.MAX_FILE * 2]u8 = undefined;
        const v = other(key).?;
        const got = edit.setLine(&out, seed, key, v).?;
        if (!oneLineApart(seed, got)) return fail("set {s} on the seed changed more or less than one line", .{key});
        if (got.len > config.MAX_FILE) return fail("set {s} grew the seed past MAX_FILE", .{key});
        edit.heard = .{};
        const c = config.parse(got);
        if (edit.heard.count != 0) return fail("parse complained after set {s}: {s}", .{ key, edit.heard.first() });
        for (edit.KEYS) |k| {
            var b1: [edit.VALUE_MAX]u8 = undefined;
            var b2: [edit.VALUE_MAX]u8 = undefined;
            const want = if (std.mem.eql(u8, k, key)) v else valueOf(&defaults, k, &b2);
            const now = valueOf(&c, k, &b1);
            if (!std.mem.eql(u8, now, want)) return fail("after set {s}: {s}={s}, want {s}", .{ key, k, now, want });
        }
        var lbuf: [edit.LINE_MAX]u8 = undefined;
        if (!edit.setByFile(&lbuf, seed, key)) return fail("the seed does not set {s}", .{key});
    }
    std.debug.print("config_edit_test: set on the real seed ({d} bytes) changes one line per key and parse reads it\n", .{seed.len});

    // ── 5. setByFile — 줄이 있어도 init이 버리면 기본값이다 ──────────────
    {
        var lbuf: [edit.LINE_MAX]u8 = undefined;
        if (edit.setByFile(&lbuf, "", "shell")) return fail("setByFile on an empty file", .{});
        if (edit.setByFile(&lbuf, "#shell=zsh\n", "shell")) return fail("setByFile on a comment", .{});
        if (edit.setByFile(&lbuf, "shell=fsh\n", "shell")) return fail("setByFile on a refused line", .{});
        if (!edit.setByFile(&lbuf, "shell=zsh\nshell=fsh\n", "shell")) return fail("setByFile missed the line parse keeps", .{});
    }

    // ── 6. 마운트 표와 옛 별칭 ────────────────────────────────────────────
    const mounts =
        \\rootfs / rootfs rw 0 0
        \\proc /proc proc rw,relatime 0 0
        \\/dev/vda /config ext2 rw,sync,nosuid,nodev,relatime 0 0
        \\
    ;
    if (!std.mem.eql(u8, edit.mountSource(mounts, "/config") orelse "", "/dev/vda")) return fail("mountSource /config", .{});
    if (edit.mountSource(mounts, "/conf") != null) return fail("mountSource matched a prefix", .{});
    if (edit.mountSource("rootfs / rootfs rw 0 0\n", "/config") != null) return fail("mountSource without /config", .{});

    if (edit.staleAlias("# x\nalias tars-config='cat /config/tars.conf'\n") != 2) return fail("staleAlias missed the old seed line", .{});
    if (edit.staleAlias("alias tars-config 'cat /config/tars.conf'\n") != 1) return fail("staleAlias missed the fish form", .{});
    if (edit.staleAlias("alias tars-configs='x'\n# alias tars-config='x'\nalias tars-rc='x'\n") != null)
        return fail("staleAlias matched something else", .{});
    // 지금의 seed 셋에는 그 줄이 없다 — 이 명령을 가리는 별칭을 우리가 다시 깔지 않는다.
    for (std.enums.values(config.Shell)) |sh| {
        if (edit.staleAlias(sh.rcSeed())) |n| return fail("the {s} seed line {d} aliases tars-config", .{ @tagName(sh), n });
    }
    std.debug.print("config_edit_test: /config's device is read from the mount table; no seed aliases tars-config\n", .{});

    std.debug.print("PASS\n", .{});
}
```

### 1-5. `build.zig` — 편집 셋

E1 — `old_string`(기준 파일 75줄부터):

```zig
    b.installArtifact(service_exe);
```

`new_string`:

```zig
    b.installArtifact(service_exe);

    // TC-M0: /config/tars.conf를 보고 고치는 명령. tars-service와 같은 까닭으로 따로 된
    // exe이고 같은 타깃 · 모드다. config.zig를 init과 함께 쓰는 것이 요점이다 — 값을
    // 받을지는 init이 부팅에 쓰는 그 parse가 정한다(TC design 결정 3).
    // make_initrd.sh가 zig-out/bin/tars-config를 usr/bin에 싣는다.
    const config_cli_mod = b.createModule(.{
        .root_source_file = b.path("src/config_cli.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
        .single_threaded = true,
    });
    const config_cli_exe = b.addExecutable(.{
        .name = "tars-config",
        .root_module = config_cli_mod,
    });
    b.installArtifact(config_cli_exe);
```

E2 — `old_string`(기준 파일 256줄부터):

```zig
    // installArtifact를 부르지 않는다. terminal/build.zig의 input_test는
```

`new_string`:

```zig
    // TC-M0: tars-config의 글자 쪽(줄 고르기 · 줄 바꾸기 · 값의 글자 · 듣기). config_test와
    // 같은 이유로 host_target이다 — config_edit.zig에는 시스템 콜이 없다.
    const config_edit_test_mod = b.createModule(.{
        .root_source_file = b.path("src/config_edit_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const config_edit_test = b.addExecutable(.{
        .name = "config_edit_test",
        .root_module = config_edit_test_mod,
    });

    // installArtifact를 부르지 않는다. terminal/build.zig의 input_test는
```

E3 — `old_string`(기준 파일 272줄부터):

```zig
    test_step.dependOn(&b.addRunArtifact(audio_test).step);
```

`new_string`:

```zig
    test_step.dependOn(&b.addRunArtifact(audio_test).step);
    test_step.dependOn(&b.addRunArtifact(config_edit_test).step);
```

### 1-6. 확인

```bash
for f in init/src/config.zig init/src/config_test.zig init/build.zig init/src/config_edit.zig init/src/config_cli.zig init/src/config_edit_test.zig; do
  cmp $f /tmp/run/tc0/new/$f && echo "SAME $f"; done
mkdir -p /tmp/run/tc0/impl
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer bash -c '
  rm -rf zig-out .zig-cache
  zig build; echo "build exit=$?"; ls -l zig-out/bin
  zig build test > /tmp/t.log 2>&1; echo "test exit=$?"
  grep -a "^config_edit_test:\|^PASS" /tmp/t.log; grep -a "^FAIL" /tmp/t.log | head'
rmdir /tmp/run/docker.lock
```

기대: `SAME` 여섯, `build exit=0`, `zig-out/bin`에 `init` · `tars-config`(3,414,368바이트 안팎) · `tars-install` · `tars-service`, `test exit=0`,
`config_edit_test:` 다섯 줄과 `PASS` 둘(config_test · config_edit_test), `FAIL` 없음.

## Task 2: `kernel/make_initrd.sh` · `tools/check.sh`

확정 4.

`kernel/make_initrd.sh`:

E1 — `old_string`(기준 파일 128줄부터):

```bash
chmod 0755 "$WORKDIR/usr/bin/tars-service"
```

`new_string`:

```bash
chmod 0755 "$WORKDIR/usr/bin/tars-service"

# TC-M0: /config/tars.conf를 보고 고치는 명령. tars-service와 같은 까닭으로 정적이고
# /usr/bin이다. 옛 seed rc의 alias tars-config가 이 이름을 가리던 자리다(TC design 결정 6).
cp ../init/zig-out/bin/tars-config "$WORKDIR/usr/bin/tars-config"
chmod 0755 "$WORKDIR/usr/bin/tars-config"
```

`tools/check.sh`:

E1 — `old_string`(기준 파일 202줄부터):

```bash
WANT+=(usr/bin/tars-install)
```

`new_string`:

```bash
WANT+=(usr/bin/tars-install)

# TC-M0: 설정 명령. tars-install과 같은 자리다 — 배열에 없고 make_initrd.sh가 손으로
# 넣는다. 빠지면 config 체인의 1차 부팅(그 이름을 친다)이 아니라 여기서 먼저 드러난다.
# 배열의 수(all N tools)는 안 바뀐다 — 그 수는 guest_tools.sh가 sysroot에서 고르는
# 바이너리의 수이고 우리 실행 파일은 거기 없다.
WANT+=(usr/bin/tars-config)
```

```bash
for f in kernel/make_initrd.sh tools/check.sh; do cmp $f /tmp/run/tc0/new/$f && echo "SAME $f"; done
bash -n kernel/make_initrd.sh && bash -n tools/check.sh && echo SYNTAX-OK
```

## Task 3: `config/check.sh` · `check.sh`

확정 5. `config/check.sh`의 E1이 키 배열 넷(1차)과 `ALIAS_KEYS`의 주석, E2가 `OFF_KEYS`, E3이 1차의 검사 다섯, E4 · E5가 2차의 주석과 글자다.

`config/check.sh`:

E1 — `old_string`(기준 파일 79줄부터):

```bash
# ── SC-M1 ───────────────────────────────────────────────────────────────
# tars-config — seed가 정의한 alias다. 이 한 명령이 셋을 동시에 본다:
#   1. /config/fish.config가 생겼다
#   2. fish가 그것을 읽었다(안 읽었으면 모르는 명령이다)
#   3. seed tars.conf가 실제로 shell_config=on을 담고 있다
# SC-M0의 게이트는 로그에서 기본값만 봤고 파일의 내용은 못 봤다.
ALIAS_KEYS=(t a r s minus c o n f i g ret)
```

`new_string`:

```bash
# ── SC-M1 · TC-M0 ───────────────────────────────────────────────────────
# tars-config — SC-M1에는 seed가 정의한 alias(cat /config/tars.conf)였고 TC-M0부터
# /usr/bin의 실행 파일이다. 인자 없이 치면 init이 읽을 모양으로 보여 준다. 이 한
# 명령이 지금 보는 것은 둘이다:
#   1. initrd에 그 명령이 있고 PATH로 닿는다
#   2. seed tars.conf가 실제로 shell_config=on을 담고 있다 — 파일이 정하지 않은
#      키는 줄 앞에 #가 붙으므로 행 머리의 shell_config=on은 파일에서만 온다
# SC-M1이 이 명령으로 보던 셋째("fish가 seed rc를 읽었다")는 바로 아래 ls -l의
# eza 판정이 이어받았다 — 그것도 seed의 alias가 있어야만 초록이다.
ALIAS_KEYS=(t a r s minus c o n f i g ret)
# tars-config set shell=fsh — init이 버릴 값이다. 이 명령은 init의 parse에 그
# 줄을 넣어 보고, parse가 한 말을 이유로 거절한다(TC design 결정 3). 판정 글자는
# 그 말이 `tars-config:`로 시작한다는 것이다 — 가로채기(configLog)가 빠지면 말이
# `tars-init:`로 새고 거절도 안 된다(TC-M0 plan mutation 2).
TC_REFUSE_KEYS=(t a r s minus c o n f i g spc s e t spc s h e l l equal f s h ret)
# tars-config set clipboard=pane — seed에 이미 있는 줄 하나를 바꾸는 길이다.
TC_SET_KEYS=(t a r s minus c o n f i g spc s e t spc
             c l i p b o a r d equal p a n e ret)
# echo tc$(tars-config get clipboard) — 쓴 값을 파일에서 되읽는다. get은 파일을
# init과 같은 길(parse)로 읽는다.
#
# 판정 글자를 우리가 만든다(BH-M2의 수법). `get`의 출력 pane만 보면 행 머리의
# `pane`이 다른 데서 올 수 있다 — 화면 줄은 " | "로 이어지므로 거절의 둘째 줄
# (`shell takes fish | bash | zsh`) 같은 글자가 그 모양을 만든다. 이 부팅의 셸은
# fish이고 fish 4.0은 $(…)를 받는다.
TC_READBACK_KEYS=(e c h o spc t c shift-4 shift-9 t a r s minus c o n f i g spc
                  g e t spc c l i p b o a r d shift-0 ret)
# tars-config check — 고친 파일을 init이 말없이 읽는가(거절한 shell=fsh가 파일에
# 들어갔으면 여기서 그 줄을 말한다), 그리고 새 seed rc에 이 명령을 가리는 alias가
# 없는가(TC design 결정 6).
#
# 줄 하나만 바꿨는지(더하지 않았는지)는 여기서 안 본다. 호스트의 config_edit_test가
# 진짜 seed에서 열두 키를 하나씩 바꿔 "한 줄만 다르다"를 본다.
TC_CHECK_KEYS=(t a r s minus c o n f i g spc c h e c k ret)
```

E2 — `old_string`(기준 파일 117줄부터):

```bash
# echo shell_config=off >> /config/tars.conf — 2차 부팅에서 친다.
# 밑줄은 shift-minus다(design 실측 14(f)에서 게스트에 닿는 것을 확인했다).
OFF_KEYS=(e c h o spc s h e l l shift-minus c o n f i g equal o f f spc
          shift-dot shift-dot spc slash c o n f i g slash t a r s dot c o n f ret)
```

`new_string`:

```bash
# tars-config set shell_config=off — 2차 부팅에서 친다. SC-M1부터 TC-M0 전까지는
# `echo shell_config=off >> /config/tars.conf`였다. 이 부팅의 파일은 1차가 덮어쓴
# `shell=zsh` 한 줄이라 set은 끝에 한 줄을 더하고, 파일은 echo가 만들던 것과
# 바이트까지 같다 — 3차부터의 부팅이 보는 것이 안 바뀐다. 3차의
# `config shell=zsh.*shell_config=off`가 "이 명령이 쓴 값을 다음 부팅이 읽었다"는
# 판정이 된다(TC design 결정 9).
# 밑줄은 shift-minus다(design 실측 14(f)에서 게스트에 닿는 것을 확인했다).
OFF_KEYS=(t a r s minus c o n f i g spc s e t spc
          s h e l l shift-minus c o n f i g equal o f f ret)
```

E3 — `old_string`(기준 파일 450줄부터):

```bash
    echo "  둘 중 하나다 — seed /config/fish.config가 안 생겼거나, 생겼는데"
    echo "  fish가 그것을 안 읽었다. 아래 마지막 화면에 'Unknown command'가"
    echo "  있으면 후자다."
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 1: the seeded fish.config defined tars-config, and it printed shell_config=on"
```

`new_string`:

```bash
    echo "  셋 중 하나다 — initrd에 /usr/bin/tars-config가 없거나(화면에"
    echo "  'Unknown command'), seed tars.conf에 그 줄이 없거나(화면에"
    echo "  '#shell_config=on'), 명령이 /config를 설정 디스크로 못 봤다."
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 1: tars-config showed the seeded config, and the file sets shell_config=on"

  # ── TC-M0: 거절 · 한 줄 바꾸기 · 되읽기 · check ────────────────────────
  #
  # 아래 EDIT_KEYS가 이 파일을 한 줄로 덮어쓰므로 여기서 바꾼 clipboard는 2차로
  # 안 넘어간다. 다음 부팅이 읽는 것은 2차의 OFF_KEYS가 본다.
  type_keys "${TC_REFUSE_KEYS[@]}"
  if ! wait_for_screen '\| tars-config: nothing was written'; then
    echo "FAIL(boot 1): 'tars-config set shell=fsh' was not refused"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  if ! wait_for_screen "\\| tars-config: shell=fsh: init would say \"unknown shell 'fsh', falling back to fish\""; then
    echo "FAIL(boot 1): the refusal did not quote init's own words under the tars-config: prefix"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 1: tars-config refused shell=fsh in init's own words and wrote nothing"

  type_keys "${TC_SET_KEYS[@]}"
  if ! wait_for_screen '\| clipboard: shared -> pane'; then
    echo "FAIL(boot 1): 'tars-config set clipboard=pane' did not report shared -> pane"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  type_keys "${TC_READBACK_KEYS[@]}"
  if ! wait_for_screen '\| tcpane'; then
    echo "FAIL(boot 1): 'tars-config get clipboard' did not read pane back from /config/tars.conf"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 1: set wrote clipboard=pane into the seed, and get read it back"

  type_keys "${TC_CHECK_KEYS[@]}"
  if ! wait_for_screen '\| /config/tars\.conf: init reads every line without a complaint'; then
    echo "FAIL(boot 1): 'tars-config check' found a problem in the seeded files"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 1: tars-config check found nothing init would complain about (the refused shell=fsh never landed), and no rc aliases tars-config"
```

E4 — `old_string`(기준 파일 602줄부터):

```bash
#      shell_config=off 한 줄을 더한다. 1차에서 사람이 친 shell=zsh는
```

`new_string`:

```bash
#      shell_config=off 한 줄을 더한다. TC-M0부터 그 줄을 쓰는 것은
#      `tars-config set`이다. 1차에서 사람이 친 shell=zsh는
```

E5 — `old_string`(기준 파일 668줄부터):

```bash
    echo "FAIL(boot 2): typed shell_config=off but /config/tars.conf never read it back"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 2: appended shell_config=off to the config for the third boot"
```

`new_string`:

```bash
    echo "FAIL(boot 2): 'tars-config set shell_config=off' did not land in /config/tars.conf"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 2: tars-config set shell_config=off for the third boot"
```

`check.sh`:

E1 — `old_string`(기준 파일 177줄부터):

```bash
# 설정을 고친다. 그래서 이 체인만 회차당 20초쯤 더 걸린다.
```

`new_string`:

```bash
# 설정을 고친다. 그래서 이 체인만 회차당 20초쯤 더 걸린다.
#
# TC-M0부터 그 타이핑에 tars-config가 든다. 1차가 그 명령으로 seed를 보고 · 틀린
# 값을 거절당하고 · 한 줄을 바꿔 되읽고 · check하며, 2차가 3차를 위해 tars.conf에
# 줄을 더하는 것도 echo가 아니라 그 명령이다 — 3차가 그 값을 읽는 것이 "이 명령이
# 쓴 것을 다음 부팅이 읽는다"는 판정이다.
```

```bash
for f in config/check.sh check.sh; do cmp $f /tmp/run/tc0/new/$f && echo "SAME $f"; done
bash -n config/check.sh && bash -n check.sh && echo SYNTAX-OK
bash -c 'source <(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic()/,/^}/p" check.sh)
  require_build_steps ./config/check.sh && require_no_early_exit_pipe ./config/check.sh &&
  require_explicit_nic ./config/check.sh && echo ENTRY-OK'
```

기대: `SAME` 둘, `SYNTAX-OK`, `ENTRY-OK`.

## Task 4: 체인 한 번과 regression

### 4-1. `config` 체인

4분 남짓이다. `run_in_background`로 돌리고 기다린다. 시리얼 로그를 꺼내 온다(lessons 범용 명령).

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -v /tmp/run/tc0/impl:/impl -w /workspace tars-devcontainer bash -c '
  s=$(date +%s); bash config/check.sh > /impl/config.log 2>&1; echo "exit=$? $(( $(date +%s) - s ))s"
  n=0; for f in /tmp/tmp.*; do if grep -a "tars-init" "$f" >/dev/null 2>&1; then n=$((n+1)); cp "$f" /impl/serial_$n.log; fi; done'
rmdir /tmp/run/docker.lock
rg -a '^boot 1: (tars-config|set|the seeded fish)|^boot 2: tars-config|^boot 3: shell_config=off|^FAIL' /tmp/run/tc0/impl/config.log
tail -n 1 /tmp/run/tc0/impl/config.log
```

기대: `exit=0`, 그리고 이 줄들.

```
boot 1: tars-config showed the seeded config, and the file sets shell_config=on
boot 1: tars-config refused shell=fsh in init's own words and wrote nothing
boot 1: set wrote clipboard=pane into the seed, and get read it back
boot 1: tars-config check found nothing init would complain about (the refused shell=fsh never landed), and no rc aliases tars-config
boot 2: tars-config set shell_config=off for the third boot
boot 3: shell_config=off kept both shells out of the rc that boot 2 ran
PASS
```

빨개지면 `FAIL(boot N)` 줄과 그 아래 마지막 화면을 그대로 보고한다.

### 4-2. regression — `tools` · `boot` · `install`

확정 8의 셋이다. 한 컨테이너에서 차례로, 약 3분 30초다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -v /tmp/run/tc0/impl:/impl -w /workspace tars-devcontainer bash -c '
  for c in tools boot install; do s=$(date +%s); bash $c/check.sh > /impl/reg_$c.log 2>&1
    echo "$c exit=$? $(( $(date +%s) - s ))s"; done; stat -c %s kernel/initrd.cpio' > /tmp/run/tc0/impl/reg.out 2>&1
rmdir /tmp/run/docker.lock
cat /tmp/run/tc0/impl/reg.out
rg -a 'init waited|tools the list names' /tmp/run/tc0/impl/reg_install.log /tmp/run/tc0/impl/reg_tools.log
```

기대: 셋 다 `exit=0`, `all 92 tools`, `init waited`가 1,000ms 이상(사본 1,400ms). 500ms 아래면 멈추고 보고한다.

## Task 5: mutation

확정 7의 표다. 사본은 `/tmp/run/tc0/impl/mut/`에 만든다. 만드는 스크립트와 도는 스크립트는 plan을 쓰며 쓴 것을 그대로 쓴다.

### 5-0. 사본을 만든다

```bash
python3 /tmp/run/tc0/make_mut.py "$PWD" /tmp/run/tc0/impl/mut
M=/tmp/run/tc0/impl/mut
for p in cli_m1.zig:init/src/config_cli.zig cli_m2.zig:init/src/config_cli.zig check_noset.sh:config/check.sh \
  edit_m3.zig:init/src/config_edit.zig config_m4.zig:init/src/config.zig; do
  echo "${p%%:*} $(diff ${p#*:} $M/${p%%:*} | rg -c '^[<>]')"; done
```

기대: `mutation copies: 5`, 그리고 `cli_m1.zig 1` · `cli_m2.zig 2` · `check_noset.sh 14` · `edit_m3.zig 2` · `config_m4.zig 1`. 다르면 돌리지
말고 보고한다.

`make_mut.py`:

```python
"""TC-M0 plan Task 5의 mutation 사본을 만든다.

사용: python3 make_mut.py <저장소 루트> <출력 디렉터리>
저장소 파일은 읽기만 한다. 사본마다 바꾼 자리가 정확히 한 군데인지 assert한다.
"""
import os
import sys

root, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)


def make(src, dst, old, new, base=None):
    s = open(base or os.path.join(root, src)).read()
    assert s.count(old) == 1, (dst, old[:60])
    path = os.path.join(out, dst)
    open(path, 'w').write(s.replace(old, new))
    os.chmod(path, 0o755 if src.endswith('.sh') else 0o644)


# mutation 1 — tars-config가 config.zig의 로그를 가로채지 않는다. parse가 거절해도
# 이 명령은 못 듣고(말은 tars-init:으로 표준 에러에 샌다) 틀린 값을 쓴다
make('init/src/config_cli.zig', 'cli_m1.zig',
     'pub const configLog = edit.configLog;\n', '')
# mutation 2 — set이 임시 파일만 쓰고 갈아 끼우지 않는다(쓰지 않는 set)
make('init/src/config_cli.zig', 'cli_m2.zig',
     'if (failed(linux.rename(TEMP_PATH, CONF_PATH))) |e| {',
     'if (@as(?linux.E, null)) |e| {')
# 그것을 1차의 되읽기가 먼저 잡으므로, 1차의 set · 되읽기를 뺀 체인 사본으로 2차까지 보낸다
s = open(os.path.join(root, 'config/check.sh')).read()
a = s.index('  type_keys "${TC_SET_KEYS[@]}"\n')
b = s.index('  type_keys "${TC_CHECK_KEYS[@]}"\n')
open(os.path.join(out, 'check_noset.sh'), 'w').write(s[:a] + s[b:])
os.chmod(os.path.join(out, 'check_noset.sh'), 0o755)
# mutation 3 — setLine이 줄을 바꾸지 않고 늘 끝에 더한다
make('init/src/config_edit.zig', 'edit_m3.zig',
     '    if (lastLine(text, key)) |s| {\n        return std.fmt.bufPrint(out,',
     '    if (@as(?Span, null)) |s| {\n        return std.fmt.bufPrint(out,')
# mutation 4 — fish seed가 옛 별칭을 다시 깐다
make('init/src/config.zig', 'config_m4.zig',
     "            \\\\# 기계에서 치른다.\n            \\\\#\n            \\\\# 아래 넷이 eza를 습관적인 이름으로 부른다. 이 기계는 도구 예순\n            \\\\# 다섯 개를 싣고 있는데 그중 대부분은 이름으로만 닿는다 — 그 하나를\n            \\\\# ls 자리에 앉힌다.\n            \\\\#\n            \\\\# ls가 여기서 유일한 셰도다. 설정 디스크를 붙이는 여섯 체인이 rc\n            \\\\# 켜진 셸에 명령을 넣으므로 별칭 하나가 게이트의 판정 글자를 바꿀\n            \\\\# 수 있다. ls가 돌아가는 자리 셋(/config/zshrc · /config/xdg/zoxide ·\n            \\\\# /sys/class/net)을 부팅으로 재서 eza가 같은 글자를 내는 것을\n            \\\\# 확인했다. 새 이름을 더할 때는 게이트가 치는 이름인지 먼저 볼 것.\n            \\\\#\n            \\\\# --icons는 안 붙인다 — eza의 아이콘은 유니코드 사설 영역이고 이\n            \\\\# 화면의 폰트에 그 글리프가 하나도 없다. 붙이면 빈 칸만 생긴다.\n            \\\\alias ls='eza'\n            \\\\alias ll='eza -l --group-directories-first'\n            \\\\alias la='eza -la --group-directories-first'\n            \\\\alias lt='eza --tree --level=2'\n            \\\\#\n            \\\\# 아래 둘이 이 기계가 기억하는 법이다.\n            \\\\#   zoxide  어느 디렉터리에 갔는지 — cd할 때마다 배우고 z <조각>으로 간다\n            \\\\#   fzf     무엇을 쳤는지 — Ctrl+R(히스토리) · Ctrl+T(파일) · Alt+C(디렉터리)\n            \\\\#\n            \\\\# type -q",
     "            \\\\# 기계에서 치른다.\n            \\\\alias tars-config='cat /config/tars.conf'\n            \\\\#\n            \\\\# 아래 넷이 eza를 습관적인 이름으로 부른다. 이 기계는 도구 예순\n            \\\\# 다섯 개를 싣고 있는데 그중 대부분은 이름으로만 닿는다 — 그 하나를\n            \\\\# ls 자리에 앉힌다.\n            \\\\#\n            \\\\# ls가 여기서 유일한 셰도다. 설정 디스크를 붙이는 여섯 체인이 rc\n            \\\\# 켜진 셸에 명령을 넣으므로 별칭 하나가 게이트의 판정 글자를 바꿀\n            \\\\# 수 있다. ls가 돌아가는 자리 셋(/config/zshrc · /config/xdg/zoxide ·\n            \\\\# /sys/class/net)을 부팅으로 재서 eza가 같은 글자를 내는 것을\n            \\\\# 확인했다. 새 이름을 더할 때는 게이트가 치는 이름인지 먼저 볼 것.\n            \\\\#\n            \\\\# --icons는 안 붙인다 — eza의 아이콘은 유니코드 사설 영역이고 이\n            \\\\# 화면의 폰트에 그 글리프가 하나도 없다. 붙이면 빈 칸만 생긴다.\n            \\\\alias ls='eza'\n            \\\\alias ll='eza -l --group-directories-first'\n            \\\\alias la='eza -la --group-directories-first'\n            \\\\alias lt='eza --tree --level=2'\n            \\\\#\n            \\\\# 아래 둘이 이 기계가 기억하는 법이다.\n            \\\\#   zoxide  어느 디렉터리에 갔는지 — cd할 때마다 배우고 z <조각>으로 간다\n            \\\\#   fzf     무엇을 쳤는지 — Ctrl+R(히스토리) · Ctrl+T(파일) · Alt+C(디렉터리)\n            \\\\#\n            \\\\# type -q")
print('mutation copies:', len(os.listdir(out)))
```

`run_mut.sh` — 사본을 저장소 경로 위에 읽기 전용으로 덮어 config 체인 한 판을 돈다. 덮은 Zig 파일은 내용이 다르므로 zig가 알아서 다시
짓는다. 판이 끝나면 `init/zig-out`에 망가진 바이너리가 남으므로 마지막 판(`back`)이 덮지 않고 한 번 더 돈다.

```bash
#!/bin/bash
# TC-M0 plan Task 5의 mutation 한 판을 돈다.
# 사용: run_mut.sh <저장소 루트> <이미지> <사본 디렉터리> <판 이름> <사본:저장소 경로>...
# 사본을 저장소 경로 위에 읽기 전용으로 덮어 config 체인을 한 번 돌리고, 로그를 <사본 디렉터리>/<판 이름>.log에 둔다.
# 첫 줄 mounted:의 다섯 자리는 차례로 "가로채기 · rename · 1차의 set · setLine의 바꾸기 · seed에 별칭 없음"의
# 수다. 덮지 않은 판은 11110이다(마지막은 옛 별칭 줄의 수라 0이 정상).
repo=$1; img=$2; mut=$3; name=$4; shift 4
mounts=""
for m in "$@"; do mounts="$mounts -v $mut/${m%%:*}:/workspace/${m#*:}:ro"; done
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
s=$(date +%s)
docker run --rm -v "$repo":/workspace $mounts -v "$mut":/mut -w /workspace "$img" bash -c "
  C=init/src/config_cli.zig
  echo \"mounted: \$(grep -c '^pub const configLog = edit.configLog;' \$C)\$(grep -c 'linux.rename(TEMP_PATH, CONF_PATH)' \$C)\$(grep -c '^  type_keys \"\\\${TC_SET_KEYS\\[@\\]}\"' config/check.sh)\$(grep -c '    if (lastLine(text, key)) |s| {' init/src/config_edit.zig)\$(grep -c \"alias tars-config='cat\" init/src/config.zig)\"
  bash config/check.sh > /mut/$name.log 2>&1; echo \"exit=\$?\""
rmdir /tmp/run/docker.lock
echo "== $name $(( $(date +%s) - s ))s"
grep -a '^FAIL' "$mut/$name.log" | head -2
echo "last line: $(tail -n 1 "$mut/$name.log")"
```

### 5-1. 체인 일곱 판

판마다 3분 안팎(`m1` · `m2` · `m2_noset`은 1분 안팎, `m3` · `m4`는 20초), 합해서 9분 남짓이다. `run_in_background`로 돌리고 기다린다.

```bash
R="$PWD"; I=tars-devcontainer; M=/tmp/run/tc0/impl/mut; X=/tmp/run/tc0/run_mut.sh
{ $X $R $I $M m0
  $X $R $I $M m1 cli_m1.zig:init/src/config_cli.zig
  $X $R $I $M m2 cli_m2.zig:init/src/config_cli.zig
  $X $R $I $M m2_noset cli_m2.zig:init/src/config_cli.zig check_noset.sh:config/check.sh
  $X $R $I $M m3 edit_m3.zig:init/src/config_edit.zig
  $X $R $I $M m4 config_m4.zig:init/src/config.zig
  $X $R $I $M back; } > $M/run.out 2>&1
cat $M/run.out
```

기대는 확정 7의 표에서 그 판의 `FAIL` 줄이고 `m0` · `back`은 `last line: PASS`다. `mounted:`는 `m0` · `back`이 `11110`, `m1`이 `01110`,
`m2`가 `10110`, `m2_noset`이 `10010`, `m3`이 `11100`, `m4`가 `11111`이다. 로그에 `Killed`가 보이고 `build failed`로 끝나면 mutation의 결과가
아니라 메모리다 — 다른 컨테이너가 없는지 보고 그 판만 다시 돈다. 예상과 다른 자리에서 죽거나 초록이면 그대로 적어 보고한다. 초록이면
먼저 덮기를 의심한다(`mounted:`).

### 5-2. 되돌림을 본다

mutation은 `-v`로 덮어 돌렸으므로 작업 트리의 파일은 그대로다. `back` 판이 `PASS`였으면 `init/zig-out`도 되돌아 있다.

```bash
git status --short
for f in init/src/config.zig init/src/config_cli.zig init/src/config_edit.zig config/check.sh; do cmp $f /tmp/run/tc0/new/$f && echo "SAME $f"; done
```

기대: `M` 일곱과 `??` 셋(`init/src/config_cli.zig` · `config_edit.zig` · `config_edit_test.zig`), lead의 문서가 commit 전이면 그것이 더 있다. `SAME`
넷. 다른 것이 보이면(특히 `-v`로 없는 파일을 덮어 Docker가 만든 0바이트 파일) 그 목록을 보고한다.

### 5-3. 보고

- `git diff --stat`(전체)과 `git diff | rg '^-'`(전체). 사본에서는 `7 files changed, 199 insertions(+), 62 deletions(-)`이었다. 지운 줄 예순둘은
  로그 스물넷의 옛 모양 · seed의 별칭 여섯 줄 · `config_test`의 목록과 주석 · config 체인의 옛 `OFF_KEYS` · 주석과 글자다.
- Task 0 ~ 3의 확인 출력(`BASE` · `MID-SAME` · `SAME` · `build exit` · `test exit` · `config_edit_test:` 다섯 줄 · `SYNTAX-OK` · `ENTRY-OK`).
- Task 4의 `exit=` · 시간 · 기대한 일곱 줄과 regression 셋의 줄 · `init waited` · `all 92 tools`.
- Task 5의 `diff` 수 다섯 · 판마다 `mounted:` · `exit=` · 시간 · `FAIL` 줄, 5-2의 출력.
- plan의 기대와 글자나 수가 다른 것이 있으면 그 줄을 그대로.

## Task 6: lead가 하는 것

1. 보고를 받아 diff를 직접 읽고, 열 파일을 `/tmp/run/tc0/new/`와 `cmp`한다. Task 4의 로그를 대조한다.
2. 루트 게이트 2회(`feedback_gate_runs`), 스물한 체인 × 2다. 판정은 `PASS: 2/2` × 21이다. `run_in_background`로 돌리고 `{ time …; }`로
   감싼다. 다른 컨테이너와 겹치지 않는다.

   ```bash
   { time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/gate_tc0.log 2>&1 ; echo "exit=$?" ; } 2> /tmp/gate_tc0.time
   ```

   완료 알림이 오면 `pgrep -f 'tars-devcontainer bash check.sh'`가 비었는지 먼저 보고 판정한다. `rg -c 'PASS: 2/2' /tmp/gate_tc0.log`가 21이어야 한다.
3. 실측 절 채우기, design `Status:`.
4. commit. 넣는 것은 열 파일과 이 plan이고 design이 바뀌었으면 함께 넣는다. `git add`는 경로를 하나씩 지정한다.
5. 사용자에게 알린다 — 쓰던 설정 디스크(`out/tars-config.img` · 실기의 p2)의 rc에는 `alias tars-config`가 남아 있다. 처방은 design 결정 6의 세 줄이다.
   running-tars.md의 새 절은 서브프로젝트를 닫을 때 쓴다(design "닫을 때").

## design과 다르게 적은 것

design 본문은 이 plan과 같은 날 같은 사람이 썼으므로 어긋난 자리가 없다. 구현 뒤에 lead가 고칠 것.

1. design `Status:`.
2. 검증 절의 표는 사본의 값이다. 루트 게이트의 값이 다르면 실측 절에 적는다.

## 이 milestone에서 안 하는 것

- 남의 문법 파일의 앞문 — wifi · ssh 키 · 방화벽 포트 · 받아쓰기(TC-M1).
- `reload`와 "지금 쓰는 값"(TC-M2).
- 옛 디스크의 rc를 고치는 것(design 결정 6). 알리기만 한다.
- running-tars.md · lessons · 기억(서브프로젝트를 닫을 때 lead가).
- `tools/check.sh`의 `WANT`에 `tars-service`가 없는 것(design 전제 정정 9). 이 milestone 밖이다.

## TC-M0이 실측한 것

(구현과 루트 게이트 뒤에 lead가 채운다.)
