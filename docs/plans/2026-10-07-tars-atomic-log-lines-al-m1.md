# AL-M1 — init이 시리얼 줄을 write 한 번으로 낸다

Date: 2026-10-07
Design: `docs/specs/2026-10-07-tars-atomic-log-lines-design.md`(결정 3 · 5 · 6)
Status: plan을 썼다. 구현 전이다. 기준은 AL-M0이 들어간 트리다. plan을 쓰며 사본에서 돈 값은 "착수 전에 확정한 것"에, 구현과 루트 게이트의 값은 맨
아래 "AL-M1이 실측한 것"에 들어간다.

## 누가 무엇을 하나

AL-M0 plan과 같다. Task 0 ~ 5는 구현 서브에이전트가 main 작업 트리에서 직접 편집하고 돌린다. Task 6(루트 게이트 2회 · 실측 절 · commit)은 lead가 한다.
구현자는 commit하지 않고, 끝에 `git diff --stat` · `git diff | rg '^-'` · 각 Task의 명령 출력을 그대로 보고한다. 이 plan의 "확정한 것" 절과 "실측한
것" 절은 구현자가 고치지 않는다.

권하는 모델은 Sonnet이다. init의 치환 151곳은 perl 한 줄이고, 나머지 편집 열아홉은 `old_string` · `new_string`이며(주석 둘 · 셸 여섯), 각 Task 끝의 `cmp`가
사본과 바이트까지 같은지를 본다. 새 파일이 없다 — `init/src/logline.zig`는 AL-M0이 이미 뒀다.

Opus로 올리는 조건. 아래 하나라도 보이면 구현자는 고치지 말고 멈춰 보고하고, lead가 Opus로 원인을 찾는다.

1. 어느 체인의 로그에든 `Attempted to kill init` · `Kernel panic` · `panic:`이 있다 — 이 milestone은 PID 1의 모든 로그 줄을 바꾼다.
2. 어느 회차의 셈이든 `A=` · `B=` · `C=` 가운데 하나가 0이 아니다.
3. 사본에서 초록이었던 체인(확정 4의 표)이 단독으로 빨갛다.
4. init의 `zig build test`가 빨갛다.

이 plan의 코드는 저장소 밖 사본(`/tmp/run/al1/repo/`)에 먼저 넣어 돌렸고, 아래의 블록은 그 사본에서 기계로 뽑은 것이다(`/tmp/run/al1/render.py`).
기준은 AL-M0 commit의 파일(`/tmp/run/al1/base/`)이고 편집 뒤의 파일은 `/tmp/run/al1/new/`다. `init/src/config.zig` · `power.zig`의 편집 둘은 Task 1의
perl 치환 뒤가 기준이다(`/tmp/run/al1/stage2/`). 편집은 Edit 도구에 글자 그대로 넣고, 각 Task 끝에서 `cmp`한다. 다르면 편집이 빗나간 것이니 plan의
글자에 맞춰 고친다. plan의 글자와 `new/`가 서로 다르다고 보이면 고치지 말고 그 자리를 보고한다. 편집은 한 파일 안에서 E1부터 차례로 넣는다.

| 파일 | 무엇을 | 줄 |
|---|---|---|
| `init/src`의 열셋(`audio` · `clock` · `config` · `control` · `devices` · `firewall` · `login` · `main` · `net` · `power` · `services` · `storage` · `wifi`) | perl 치환 — `std.debug.print(` → `logline.print(` 151곳, 파일마다 import 한 줄 | +164 −151 |
| `init/src/config.zig` · `power.zig` | 편집 하나씩 — 옛 싱크 이름을 적은 주석 | +6 −4 |
| `gate_lib.sh` | 편집 다섯 — `cut_log_lines`가 C(2048에서 잘린 줄)도 센다, `joined_screen_dump`의 `tars-init: ` 꼬리 떼기를 지운다 | +20 −17 |
| `check.sh` | 편집 일곱 — 셈의 B · C가 FAIL, `LOGLINE_DIRS`에 `init/src`, `joined_screen_dump`의 고정 조각, 셈의 고정 조각 C | +37 −25 |
| `pointer` · `copy` · `render` · `pane`의 `check.sh` | 편집 다섯 — 로그의 NUL 검사가 파일을 한 번만 읽는다(확정 4의 거짓 빨강) | +20 −5 |

`git diff --stat`은 19 files, +247 −202이다. terminal · 커널 · Dockerfile · `make_initrd.sh`는 안 바뀐다. 새 체인 · 새 포트도 없다.

design의 `Status:` · `CLAUDE.md` · `MEMORY.md` · `docs/decisions/` · `docs/guides/` · `HANDOFF.md`는 구현자가 안 고친다.

명령 · 컨테이너 · lock · `sync; sleep 1`의 규칙은 AL-M0 plan의 "누가 무엇을 하나"와 같다. 구현자의 측정용 파일은 `/tmp/run/al1/impl/` 아래에 둔다.

## 이 milestone이 끝나면

- init(PID 1)과 같은 디렉터리의 `tars-config` · `tars-service` · `tars-install`이 시리얼 · 표준 에러에 내는 줄이 전부 `logline.print` — 한 줄이 write 한
  번이다. fmt는 한 글자도 안 바뀌므로 2048바이트 안의 줄은 바이트도 같다.
- 그래서 terminal과 init이 서로의 줄 가운데에 끼는 일(셈의 A · B)이 양쪽 다 구조적으로 사라진다. 루트 `check.sh`의 셈이 A · B · C 셋 다 FAIL로 본다.
  회차마다의 셈 줄이 이렇게 바뀐다.

```
CP-M2 run 1/2: cut log lines A=0 B=0 C=0 (/tmp/tars-gate.XXXXXX/CP-M2-1)
```

- C는 `logline.zig`의 상한 2048에서 잘려 ` [cut]`으로 끝난 줄이다. init은 SIGTERM · SIGINT 처리기를 달고(SA_RESTART 없이) 커널 tty는 2048보다 긴
  write를 끊는 자리에서 처리할 시그널을 보면 돌아가므로, 2048은 "write 한 번 = 끼어들 수 없음"이 시그널과 무관하게 참인 상한이다. 게이트가 내는 줄은
  그만큼 길지 않으므로(가장 긴 init의 줄 247바이트) 잘린 줄이 보이면 그 회차가 빨갛다. 정적으로는 못 지킨다 — `{s}`에 들어가는 글자(설정 값 · 경로)의
  길이는 런타임에 정해진다.
- `joined_screen_dump`가 화면 줄 꼬리의 `tars-init: …`를 더는 떼지 않는다. 커널 printk 조각 떼기와, 이을 차례에 오는 온전한 `tars-init: ` 줄 건너뛰기는
  남는다(design 결정 5).
- 진입 검사 `require_no_debug_print`가 `init/src`도 본다. `require_screen_dump_joins`의 고정 조각이 바뀌고(init이 자른 모양 둘이 빠지고, 커널이 자른 뒤
  init의 온전한 줄이 오는 모양과 화면 글자로 `tars-init: `가 끝에 오는 모양이 든다), `require_cut_lines_found`에 C 조각이 하나 는다.

## 착수 전에 확정한 것

2026-10-07에 이 plan을 쓰며 저장소 사본과 이미지 `tars-devcontainer`로 쟀다. 기준(`/tmp/run/al1/base/`)은 AL-M0 plan의 `new/`와 같은 파일이다 —
`check.sh` · `gate_lib.sh` · `init/src/logline.zig`가 `/tmp/run/al0/new/`와 `cmp`로 같고, HEAD `7909558`의 파일과도 같다. 측정 파일은 `/tmp/run/al1/meas/`와 `/tmp/run/al1/mut/`에
있다.

1. 치환의 수. `rg -c 'std\.debug\.print\('`(괄호까지)로 세면 init은 열세 파일 151곳이다. design 표의 153은 괄호 없이 세어 `config.zig` · `power.zig`의 doc
   주석 한 줄씩이 들어간 수다. 줄바꿈 없는 fmt는 `config.zig`의 `log`와 `main.zig`의 `configLog` 둘뿐이고 둘 다 `"tars-init: " ++ fmt ++ "\n"` — 컴파일
   타임에 붙는 한 fmt라 조각이 아니다(design 결정 2). 그래서 init에는 `Line`이 필요 없고 치환만으로 끝난다.

2. import 자리. `control.zig` · `login.zig` · `services.zig`는 첫 줄이 `//!`라 AL-M0의 perl(`\A` 고정)이 import를 못 넣는다. 첫 `const std = …;` 줄 뒤에
   넣도록 바꿨다(Task 1). 넣은 뒤 열세 파일 모두 `import=1`.

3. 호스트. init의 `zig build`(exe 넷 — init · tars-config · tars-install · tars-service)와 `zig build test`가 초록이다. `logline.zig`는 같은 디렉터리의
   상대 import라 `build.zig`가 한 줄도 안 바뀐다 — `config_test` · `audio_test`처럼 치환된 파일을 import하는 시험 모듈도 그대로 선다. 진입 검사 전체가
   `entry rc=0`.

4. 체인. 사본을 HEAD `7909558`(AL-M0 commit `7996b1b` 위)에 맞추고(`base/`와 `cmp`로 같다) 바꾼 뒤 체인 스물하나를 회차 디렉터리 아래에서 한 번씩
   돌렸다(`/tmp/run/al1/meas/new/`).

   | 체인 | rc · 시간 | 체인 | rc · 시간 | 체인 | rc · 시간 |
   |---|---|---|---|---|---|
   | boot | 0 · 41초 | copy | 0 · 178초 | device | 0 · 17초 |
   | input | 0 · 41초 | machine | 0 · 20초 | net | 0 · 188초 |
   | power | 0 · 52초 | tools | 0 · 63초 | terminal | 0 · 25초 |
   | render | 0 · 109초 | pointer | 1 · 76초 → 0 · 76초(두 번) | pane | 0 · 52초 |
   | config | 0 · 195초 | hangul | 0 · 81초 | audio | 0 · 45초 |
   | dictation | 0 · 94초 | firewall | 0 · 63초 | nic | 0 · 36초 |
   | service | 0 · 77초 | wifi | 0 · 123초 | install | 0 · 108초 |

   스물하나 모두 셈이 `A=0 B=0 C=0`이고 ` [cut]` 줄은 0이다. 이 판에서 가장 긴 `tars-init: ` 줄은 227바이트다.

   pointer의 1은 AL과 무관한 게이트의 거짓 빨강이었다 — `the boot B serial log contains NUL bytes`인데 로그 둘에 NUL이 0바이트였다. 그 검사는
   `tr -d '\0' < "$LOG" | wc -c`와 `wc -c < "$LOG"`를 견주어 파일을 두 번 읽고, 그때 QEMU가 아직 돌며 terminal이 `style>` · `pixel>`을 쓰는 중이라 두
   읽기 사이에 로그가 자랐다(실패 출력의 꼬리가 바로 그 줄들이었다). 같은 모양이 pointer 둘 · copy · render · pane에 있어 Task 3-3이 한 번 읽기로
   고친다. 고친 뒤 pointer 두 번 · copy · render · pane 한 번씩 초록이다(`meas/new2` · `new3`). 왜 이 판에서 처음 드러났는지는 모른다 — AL-M0의 루트
   게이트 84회차는 초록이었다. 확률의 일이고, 고친 모양은 경합 자체를 없앤다.

   init 줄의 바이트. 같은 세션에서 바꾸기 전(`meas/base/`) · 뒤에 같은 체인 넷을 돌려, `tars-init: ` 줄의 숫자를 `N`으로 바꾼 모양을 견줬다
   (`/tmp/run/al1/cmp_init.py`). pid · 시각 · 횟수만 다를 수 있고 글자는 같아야 한다.

   | 체인 | 전: 줄 · 모양 | 뒤: 줄 · 모양 | 같은 모양 |
   |---|---|---|---|
   | boot | 34 · 30 | 34 · 30 | 30 |
   | power | 142 · 50 | 142 · 50 | 50 |
   | service | 244 · 86 | 246 · 86 | 86 |
   | config | 332 · 63 | 332 · 63 | 63 |

   한쪽에만 있는 모양은 0이다(service의 줄 둘 차이는 `reaped orphan` 같은 횟수다).

   init 바이너리. ReleaseSafe의 `init`이 4,072,600 → 4,425,856바이트(+353,256, +8.7%)다. fmt마다 `logline.print`가 따로 펼쳐지는데 그 몸이 `Writer.fixed` ·
   자르기 · write 고리까지라 `std.debug.print`의 펼침보다 크다. initrd에 실리는 것은 이 exe 하나이고, 체인 시간에 보이는 차이는 없다(확정 4의 표와
   AL-M0의 시간). `tars-config` · `tars-install` · `tars-service`는 바이트 수가 그대로다 — 앞의 것은 `configLog`로 가로채고, 뒤의 둘은 치환된 줄을
   부르지 않는다.

5. PID 1의 패닉 표. init은 ReleaseSafe이고 PID 1의 패닉은 커널 패닉이다. `logline.zig`는 AL-M0이 둔 그 파일 그대로다(진입 검사의 `cmp`) — 패닉 자리와
   그것을 덮는 `logline_test`의 경우는 AL-M0 plan 확정 7의 표와 같고, init에서 달라지는 것만 적는다.

   | 자리 | 무엇이 패닉 · 멈춤이 될 수 있었나 | 어떻게 막았나 | 누가 보나 |
   |---|---|---|---|
   | `Line.print`의 자르기 | `buf.len - CUT.len`의 뺄셈 · `buf[e..][0..CUT.len]` | `print`의 버퍼는 컴파일 타임 `[MAX]u8`이라 `CUT`보다 늘 크다. `whole`이 `e`를 `MAX - CUT.len` 이하로 준다 | `logline_test` 4 · 6 · 7 · 8 · 13 |
   | `Writer.fixed`의 에러 | `w.print`의 `error.WriteFailed` | `catch`가 받아 자르기로 간다. `print`의 반환형은 `void`다 | 경우 4 · 11 |
   | write의 EINTR | init의 처리기는 `SA_RESTART` 없이 단다(`power.zig` — 감독 루프의 `waitpid`를 깨우려고). 콘솔이 막힌 채 SIGTERM이 오면 write가 EINTR이나 덜 쓴 수로 돌아온다 | EINTR은 다시 쓰고, 덜 쓰이면 나머지를 마저 쓴다. 다른 에러(EBADF · EIO)는 버린다 — 로그를 못 쓴 것 때문에 PID 1이 멈추지 않는다 | 경우 1 · 2(fd 2를 소켓으로), 체인 power |
   | 스택 | 줄마다 스택에 2048바이트 | PID 1의 스택은 커널이 준 기본(8MB)이고 `print`는 재귀하지 않는다. fork한 자식이 execve 전에 찍는 줄(`execve … failed`)도 같다 | 체인 |
   | 처리기 안의 로그 | 처리기에서 `print`하면 감독 루프가 쓰던 줄 가운데에 끼어든다 | 처리기(`onSignal`)는 원자적 저장 하나뿐이다 — 바뀌지 않는다. 주석이 이유를 `logline.print`로 다시 적는다(Task 2) | 코드 읽기 |
   | `configLog`의 가로채기 | — | 그대로다. `config_heard`의 `Writer.fixed`도 그대로(TC-M2) | `config_test` · 체인 config |

6. 2048을 넘는 줄을 어디서 지키나. 정적으로는 못 지킨다 — `{s}`에 사람이 적은 설정 값(`MAX_FILE` 4096) · 경로가 들어간다. 그래서 런타임에 지킨다:
   `logline.print`가 2048에서 자르고 ` [cut]`을 붙이고, 셈의 C가 그 줄을 세어 회차를 빨갛게 한다. 지금 게이트가 내는 init의 줄은 가장 긴 것이
   247바이트(design 실측 B)라 C는 0이어야 한다.

7. mutation. Task 5의 명령을 그대로 사본에서 돌렸다(`OUT=/tmp/run/al1/dry`). e1 · e5 · e6 · j1은 진입 검사가 0 ~ 1초에 FAIL로 잡았다. b1은 boot 체인이
   PASS인데 셈이 `B=1`로 그 회차를 FAIL로, c1은 `C=1`로 FAIL로 만들었다 — c1의 잘린 줄은 2047바이트 + 줄바꿈 = 2048이고 `xxxxxx [cut]`으로 끝난다.
   `clean`은 `entry rc=0` · `A=0 B=0 C=0` · `one rc=0`.

8. Task 4의 명령도 그대로 돌렸다(`/tmp/run/al1/dry`) — 여섯 다 `A=0 B=0 C=0` · `one rc=0`, `panic lines: 0`. 약 12분.

## Task 0: 바꾸기 전의 기준값

```bash
cd /Users/dp/Repository/tars-linux && git log --oneline -1 && git status --short && \
  cmp init/src/logline.zig terminal/src/logline.zig && \
  rg -c 'std\.debug\.print\(' init/src -g '!*_test.zig' | sort
```

HEAD가 `7909558`(AL-M0 commit `7996b1b` 위의 HANDOFF) 또는 그 위에 이 plan만 더한 commit이고, 작업 트리가 깨끗하고(이 plan 파일 하나만 `??`일 수 있다), 두 `logline.zig`가 같고, 수가 아래와 같아야 한다. 다르면 멈추고
보고한다.

```
init/src/audio.zig:23
init/src/clock.zig:11
init/src/config.zig:1
init/src/control.zig:2
init/src/devices.zig:7
init/src/firewall.zig:14
init/src/login.zig:2
init/src/main.zig:55
init/src/net.zig:7
init/src/power.zig:13
init/src/services.zig:11
init/src/storage.zig:1
init/src/wifi.zig:4
```

## Task 1: 치환 151곳

AL-M0의 perl과 한 군데가 다르다 — import를 넣는 자리. `control.zig` · `login.zig` · `services.zig`는 첫 줄이 `//!` 문서 주석이라 파일 맨 앞(`\A`)이
아니라 첫 `const std = @import("std");` 줄 뒤(`^…$`, `/m`, 첫 하나만)에 넣는다.

```bash
cd /Users/dp/Repository/tars-linux && files=$(rg -l 'std\.debug\.print\(' init/src -g '!*_test.zig' | sort | tr '\n' ' ') && echo "$files" && \
perl -0pi -e 's/^const std = \@import\("std"\);\n/$&const logline = \@import("logline.zig");\n/m; s/\bstd\.debug\.print\(/logline.print(/g' $files && \
for f in $files; do echo "$f logline=$(rg -c 'logline\.print\(' $f) import=$(rg -c '^const logline = @import\("logline.zig"\);$' $f)"; done && \
rg -n 'std\.debug\.print' init/src -g '!*_test.zig'; \
for f in $files; do cmp "$f" "/tmp/run/al1/stage2/$f" || exit 1; done && echo same
```

(구현자의 셸이 zsh면 `$files`가 안 쪼개진다. `bash -c '…'`로 감싸거나 `${=files}`를 쓴다.)

`logline=`의 수가 Task 0의 수와 같고 `import=1`이 열셋이고, 남은 `std.debug.print`가 주석 넷(`logline.zig` 5행 · 78행, `config.zig`의 doc 주석 한 줄,
`power.zig`의 doc 주석 한 줄)뿐이고, 마지막이 `same`이어야 한다.

지운 줄이 치환된 줄뿐인지.

```bash
cd /Users/dp/Repository/tars-linux && git diff init/src | rg '^-[^-]' | rg -vc 'std\.debug\.print\('; git diff init/src | rg '^-[^-]' | rg -c 'std\.debug\.print\('
```

빈 출력(또는 `0`)과 `151`이어야 한다.

## Task 2: 주석 둘

`config.zig`의 `log` doc 주석과 `power.zig`의 `onSignal` doc 주석이 옛 싱크의 이름을 말한다. 코드는 안 바뀐다 — `log`의 가로채기(`root.configLog`)는
그대로이고, 가로채는 쪽이 없을 때의 싱크와 init 쪽 가로채기(`main.zig`의 `configLog`)의 첫 줄은 Task 1의 치환이 이미 `logline.print`로 바꿨다.

`init/src/config.zig`:

E1 — `old_string`(기준 파일 17줄부터):

```zig
/// 붙여 표준 에러에 찍는다. 달라지는 것은 이 파일을 import하는 다른 실행
```

`new_string`:

```zig
/// 붙여 표준 에러에 찍는다. AL-M1부터는 그 한 줄이 `logline.print`로 write 한 번에
/// 나간다(AL design 결정 3) — 글자는 같고 terminal의 줄과 섞이지 않는다. 달라지는 것은 이 파일을 import하는 다른 실행
```

`init/src/power.zig`:

E1 — `old_string`(기준 파일 24줄부터):

```zig
/// 시그널 핸들러 안에서는 재진입 안전하지 않은 것을 부를 수 없다. 우리 로그
/// 함수(std.debug.print)가 바로 그런 것이므로, 핸들러는 정수 하나를 남기고
/// 즉시 돌아온다. 로그는 깨어난 감독 루프가 찍는다.
```

`new_string`:

```zig
/// 시그널 핸들러 안에서는 재진입 안전하지 않은 것을 부를 수 없다. 옛 로그
/// 함수(std.debug.print)가 바로 그런 것이었고, 지금의 `logline.print`도 핸들러에서
/// 부르면 감독 루프가 쓰던 줄 한가운데에 핸들러의 줄이 끼어든다(AL design). 그래서
/// 핸들러는 정수 하나를 남기고 즉시 돌아온다. 로그는 깨어난 감독 루프가 찍는다.
```

```bash
cd /Users/dp/Repository/tars-linux && for f in $(cd /tmp/run/al1/new && rg -l 'logline' init/src -g '!*_test.zig'); do cmp "$f" "/tmp/run/al1/new/$f" || exit 1; done && echo same && \
sync && sleep 1 && \
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer bash -c '
  zig build > /tmp/b.log 2>&1; echo build rc=$?; zig build test > /tmp/t.log 2>&1; echo test rc=$?; grep -E "FAIL|error:" /tmp/b.log /tmp/t.log; ls -l zig-out/bin'; rc=$?
rmdir /tmp/run/docker.lock
```

`build rc=0` · `test rc=0`이어야 한다(Opus 조건 4).

## Task 3: 게이트 — 셈 · 이어 붙이기 · 진입 검사

### 3-1. `gate_lib.sh` — 편집 다섯

E1 ~ E3은 `joined_screen_dump`의 주석 · 꼬리 떼기, E4 · E5는 `cut_log_lines`의 C다.

E1 — `old_string`(기준 파일 126줄부터):

```bash
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
```

`new_string`:

```bash
# init의 줄도 같은 UART에 쓴다. TC-M3 Task 5b 때는 init의 줄이 terminal의 줄 한가운데
# 끼어 같은 모양으로 잘랐고(config 7차의 `whence -w fzf` 뒤에 `tars-init: audio: …`),
# 그래서 꼬리의 `tars-init: ` 조각도 떼고 이었다. AL에서 terminal(M0)과 init(M1)이 한
# 줄을 write 한 번으로 내게 되어 그 자름은 생길 수 없고, 꼬리 떼기를 지웠다 — 남아
# 있으면 화면 글자로 `tars-init: `가 보이는 dump(사람이 시리얼 로그를 grep한 화면)의
# 꼬리를 진짜 글자인데도 떼어 냈다(AL design 결정 5). 그 자름이 돌아오면 이 함수가
# 아니라 check.sh의 셈(cut_log_lines의 A)이 그 회차를 빨갛게 한다.
#
# 이을 차례에 오는 온전한 `tars-init: ` 줄은 커널 줄처럼 건너뛴다. 이것은 남는다 —
# 커널이 화면 줄을 자르고 뒤 조각이 오기 전에 init이 온전한 한 줄을 쓸 수 있다.
```

E2 — `old_string`(기준 파일 149줄부터):

```bash
    next if $cur =~ s/\[ *\d+\.\d+\] [^\r\n]*\r?\n\z//;
    next if $cur =~ s/tars-init: [^\r\n]*\r?\n\z//;
```

`new_string`:

```bash
    next if $cur =~ s/\[ *\d+\.\d+\] [^\r\n]*\r?\n\z//;
```

E3 — `old_string`(기준 파일 238줄부터):

```bash
#   B <파일>: <줄>   init의 줄 가운데에 terminal의 줄이 들어 있다
```

`new_string`:

```bash
#   B <파일>: <줄>   init의 줄 가운데에 terminal의 줄이 들어 있다
#   C <파일>: <줄>   terminal · init의 줄이 `logline.zig`의 상한(2048바이트)을 넘어 잘렸다
#
# C를 세는 까닭(AL-M1). 2048은 커널 tty가 긴 write를 끊는 단위이고, init은 SIGTERM ·
# SIGINT 처리기를 단다 — 처리할 시그널이 걸린 채 2048을 넘는 write는 끊기는 자리에서
# 돌아가고 그 사이에 남의 줄이 낄 수 있다. 그래서 `logline.print`는 2048에서 자르고
# ` [cut]`을 붙인다. 게이트가 내는 줄은 그 상한에 한참 못 미쳐야 하고(가장 긴 init의 줄이
# 247바이트), 잘린 줄이 보이면 줄 하나가 판정이 볼 글자를 잃었다는 뜻이다. 화면 dump는
# 격자 크기 버퍼라 안 잘린다 — 잘렸다면 그것도 버그다.
```

E4 — `old_string`(기준 파일 249줄부터):

```bash
# 줄 머리가 `terminal: ` · `tars-init: `인 파일만 perl에 넘긴다. 회차 디렉터리에는
```

`new_string`:

```bash
# 줄 머리가 `terminal: ` · `tars-init: `인 파일만 perl에 넘긴다(C의 `kms: ` · `font: `
# 줄도 terminal이 쓰므로 그 파일에 함께 있다). 회차 디렉터리에는
```

E5 — `old_string`(기준 파일 258줄부터):

```bash
    if (/^terminal: .*tars-init: /) { print "A $ARGV: $_" }
```

`new_string`:

```bash
    if (/^(terminal|kms|font|tars-init): .* \[cut\]\r?\n?\z/) { print "C $ARGV: $_" }
    if (/^terminal: .*tars-init: /) { print "A $ARGV: $_" }
```

### 3-2. `check.sh` — 편집 일곱

E1 — `old_string`(기준 파일 153줄부터):

```bash
# 그 회차의 로그에서 남의 줄이 끼어든 줄을 센다(gate_lib.sh의 cut_log_lines). A(terminal의
# 줄 가운데의 init)는 AL-M0 뒤로 생길 수 없으므로 하나라도 있으면 그 회차가 FAIL이다.
# B(init의 줄 가운데의 terminal)는 init이 아직 한 줄을 write 여럿으로 내므로(AL-M1의 몫)
# 수만 찍는다. 체인이 빨개도 세어서 찍는다 — 빨간 까닭이 이 자름일 수 있다.
count_cut_lines() {
  local dir="$1" label="$2" cut a b
  cut="$(LOG=/dev/null bash -c 'source ./gate_lib.sh; cut_log_lines "$1"' _ "$dir")"
  a="$(grep -c '^A ' <<<"$cut")"
  b="$(grep -c '^B ' <<<"$cut")"
  echo "${label}: cut log lines A=${a} B=${b} (${dir})"
  if [ "$b" -ne 0 ]; then
    grep '^B ' <<<"$cut"
  fi
  if [ "$a" -ne 0 ]; then
    echo "${label} FAIL: ${a} terminal line(s) carry a tars-init line in the middle:"
    grep '^A ' <<<"$cut"
```

`new_string`:

```bash
# 그 회차의 로그에서 남의 줄이 끼어든 줄과 잘린 줄을 센다(gate_lib.sh의 cut_log_lines).
# terminal(AL-M0)과 init(AL-M1)이 한 줄을 write 한 번으로 내므로 A(terminal의 줄 가운데의
# init)도 B(init의 줄 가운데의 terminal)도 생길 수 없고, C(2048에서 잘린 줄)는 게이트의 줄이
# 그만큼 길지 않으므로 생기면 안 된다. 셋 가운데 하나라도 있으면 그 회차가 FAIL이다. 체인이
# 빨개도 세어서 찍는다 — 빨간 까닭이 이 자름일 수 있다.
count_cut_lines() {
  local dir="$1" label="$2" cut a b c
  cut="$(LOG=/dev/null bash -c 'source ./gate_lib.sh; cut_log_lines "$1"' _ "$dir")"
  a="$(grep -c '^A ' <<<"$cut")"
  b="$(grep -c '^B ' <<<"$cut")"
  c="$(grep -c '^C ' <<<"$cut")"
  echo "${label}: cut log lines A=${a} B=${b} C=${c} (${dir})"
  if [ "$a" -ne 0 ] || [ "$b" -ne 0 ] || [ "$c" -ne 0 ]; then
    echo "${label} FAIL: serial lines were cut (A: tars-init inside terminal, B: terminal inside tars-init, C: over 2048 bytes):"
    grep -E '^[ABC] ' <<<"$cut"
```

E2 — `old_string`(기준 파일 427줄부터):

```bash
# TC-M3 Task 5b. gate_lib.sh의 joined_screen_dump가 끼어든 줄을 잇는가. QEMU 없이 고정된
# 조각 넷으로 본다 — 안 잘린 dump, 커널 printk가 자른 dump, init의 줄이 자른 dump, init의
# 줄 둘(조각 + 온전한 한 줄)이 자른 dump가 전부 같은 한 줄이 되어야 한다. 이 함수가 잇지
# 못하면 그 화면의 마지막 dump를 기다리는 검사가 30초 뒤에 거짓으로 빨갛다(TC-M3 루트
# 게이트 2회차, config 7차). 게이트를 시작하기 전에 0.1초로 잡는다.
```

`new_string`:

```bash
# TC-M3 Task 5b · AL-M1. gate_lib.sh의 joined_screen_dump가 커널이 자른 줄을 잇는가. QEMU
# 없이 고정된 조각으로 본다 — 안 잘린 dump, 커널 printk가 자른 dump, 커널이 자르고 뒤 조각
# 앞에 init의 온전한 줄이 온 dump가 전부 같은 한 줄이 되어야 한다. 이 함수가 잇지 못하면
# 그 화면의 마지막 dump를 기다리는 검사가 30초 뒤에 거짓으로 빨갛다(TC-M3 루트 게이트
# 2회차, config 7차). 그리고 화면 글자로 `tars-init: `가 끝에 보이는 dump는 그대로여야
# 한다 — AL-M1 전에는 init의 줄이 dump 가운데를 자를 수 있어서 그 꼬리를 떼어 냈고, 그
# 규칙이 진짜 화면 글자까지 떼었다. init의 줄이 write 한 번이 된 뒤로 그런 자름은 없다
# (AL design 결정 5). 게이트를 시작하기 전에 0.1초로 잡는다.
```

E3 — `old_string`(기준 파일 437줄부터):

```bash
  printf 'terminal: screen> a | (none)# whence -w fzftars-init: audio: no sound card within 5000ms, the mixer is left alone\n-history-widget | fzf-history-widget: function | (none)# \r\n' > "$dir/init"
  printf 'terminal: screen> a | (none)# whence -w fzftars-init: audio: one\ntars-init: two\n-history-widget | fzf-history-widget: function | (none)# \r\n' > "$dir/init2"
  want="$(LOG="$dir/clean" bash -c 'source ./gate_lib.sh; joined_screen_dump')"
  for name in printk init init2; do
```

`new_string`:

```bash
  printf 'terminal: screen> a | (none)# whence -w fzf[   7.359211] random: crng init done\r\ntars-init: audio: no sound card within 5000ms, the mixer is left alone\n-history-widget | fzf-history-widget: function | (none)# \r\n' > "$dir/printk_init"
  want="$(LOG="$dir/clean" bash -c 'source ./gate_lib.sh; joined_screen_dump')"
  for name in printk printk_init; do
```

E4 — `old_string`(기준 파일 449줄부터):

```bash
  done
  rm -rf "$dir"
```

`new_string`:

```bash
  done
  printf 'terminal: screen> (none)# grep audio /tmp/serial.log | tars-init: audio: no sound card\r\nterminal: style> 0,0 fg=8ABEB7 bg=102030\r\n' > "$dir/text"
  want="$(printf 'terminal: screen> (none)# grep audio /tmp/serial.log | tars-init: audio: no sound card\r')"
  got="$(LOG="$dir/text" bash -c 'source ./gate_lib.sh; joined_screen_dump')"
  rm -rf "$dir"
  if [ "$got" != "$want" ]; then
    echo "check FAIL: gate_lib.sh joined_screen_dump changes a screen> line whose text ends in tars-init:" >&2
    echo "  want [${want}]" >&2
    echo "  got  [${got}]" >&2
    return 1
  fi
```

E5 — `old_string`(기준 파일 458줄부터):

```bash
# `widget: function`이 든 온전한 `screen>` 줄(셈 밖). 못 잡으면 게이트가 회차마다
# "0"이라고 거짓말을 한다.
```

`new_string`:

```bash
# `widget: function`이 든 온전한 `screen>` 줄(셈 밖). AL-M1이 다섯째를 더했다 — 2048에서
# 잘려 ` [cut]`으로 끝나는 init의 줄(C). 못 잡으면 게이트가 회차마다 "0"이라고 거짓말을 한다.
```

E6 — `old_string`(기준 파일 467줄부터):

```bash
  got="$(LOG=/dev/null bash -c 'source ./gate_lib.sh; cut_log_lines "$1"' _ "$dir" | cut -d: -f1 | sort | tr '\n' ' ')"
  want="A ${dir}/a B ${dir}/b "
```

`new_string`:

```bash
  printf 'tars-init: config line without = ignored: xxxxxxxx [cut]\n' > "$dir/c"
  got="$(LOG=/dev/null bash -c 'source ./gate_lib.sh; cut_log_lines "$1"' _ "$dir" | cut -d: -f1 | sort | tr '\n' ' ')"
  want="A ${dir}/a B ${dir}/b C ${dir}/c "
```

E7 — `old_string`(기준 파일 495줄부터):

```bash
# 패턴에 걸린다. AL-M1이 init/src를 더한다.
LOGLINE_DIRS=(terminal/src)
```

`new_string`:

```bash
# 패턴에 걸린다. AL-M1이 init/src를 더했다 — `tars-config` · `tars-service` · `tars-install`도
# 같은 디렉터리라 함께 덮인다.
LOGLINE_DIRS=(terminal/src init/src)
```

### 3-3. 체인 넷 — NUL 검사가 로그를 한 번만 읽는다

design 밖의 편집이다. 이 plan의 사본 실측에서 pointer 체인이 `the boot B serial log contains NUL bytes`로 빨갰는데 로그에 NUL은 0바이트였다(확정 4).
그 검사는 로그를 두 번 읽어(NUL을 뺀 길이 · 전체 길이) 견주는데, 검사하는 때에 QEMU가 아직 돌고 terminal이 dump를 쓰는 중이라 두 읽기 사이에 로그가
자라면 NUL이 없어도 빨갛다. 같은 모양이 다섯 자리에 있다. NUL만 세는 한 번의 읽기(`tr -cd '\0' … | wc -c`가 0인가)로 바꾼다 — `pane/check.sh`의 다른 한
자리(부팅 B)가 이미 그 모양이다.

`pointer/check.sh`:

E1 — `old_string`(기준 파일 1102줄부터):

```bash
# ── 음성 검사: 로그에 NUL이 섞이지 않았다 ──────────────────────────────
if [ "$(tr -d '\0' < "$LOG" | wc -c)" -ne "$(wc -c < "$LOG")" ]; then
```

`new_string`:

```bash
# ── 음성 검사: 로그에 NUL이 섞이지 않았다 ──────────────────────────────
# NUL만 세어 한 번에 읽는다(AL-M1). 예전에는 파일을 두 번 읽어(NUL을 뺀 길이 · 전체 길이)
# 견줬는데, QEMU가 아직 돌며 terminal의 dump를 쓰는 동안이라 두 번 사이에 로그가 자라
# NUL이 없어도 거짓으로 빨갰다(AL-M1 사본의 pointer 부팅 B).
if [ "$(tr -cd '\0' < "$LOG" | wc -c)" -ne 0 ]; then
```

E2 — `old_string`(기준 파일 1646줄부터):

```bash
if [ "$(tr -d '\0' < "$LOG" | wc -c)" -ne "$(wc -c < "$LOG")" ]; then
  report_failure "the boot B serial log contains NUL bytes"
```

`new_string`:

```bash
# NUL만 세어 한 번에 읽는다(AL-M1). 예전에는 파일을 두 번 읽어(NUL을 뺀 길이 · 전체 길이)
# 견줬는데, QEMU가 아직 돌며 terminal의 dump를 쓰는 동안이라 두 번 사이에 로그가 자라
# NUL이 없어도 거짓으로 빨갰다(AL-M1 사본의 pointer 부팅 B).
if [ "$(tr -cd '\0' < "$LOG" | wc -c)" -ne 0 ]; then
  report_failure "the boot B serial log contains NUL bytes"
```

`copy/check.sh`:

E1 — `old_string`(기준 파일 1327줄부터):

```bash
if [ "$(tr -d '\0' < "$LOG" | wc -c)" -ne "$(wc -c < "$LOG")" ]; then
```

`new_string`:

```bash
# NUL만 세어 한 번에 읽는다(AL-M1). 예전에는 파일을 두 번 읽어(NUL을 뺀 길이 · 전체 길이)
# 견줬는데, QEMU가 아직 돌며 terminal의 dump를 쓰는 동안이라 두 번 사이에 로그가 자라
# NUL이 없어도 거짓으로 빨갰다(AL-M1 사본의 pointer 부팅 B).
if [ "$(tr -cd '\0' < "$LOG" | wc -c)" -ne 0 ]; then
```

`render/check.sh`:

E1 — `old_string`(기준 파일 942줄부터):

```bash
if [ "$(tr -d '\0' < "$LOG" | wc -c)" -ne "$(wc -c < "$LOG")" ]; then
```

`new_string`:

```bash
# NUL만 세어 한 번에 읽는다(AL-M1). 예전에는 파일을 두 번 읽어(NUL을 뺀 길이 · 전체 길이)
# 견줬는데, QEMU가 아직 돌며 terminal의 dump를 쓰는 동안이라 두 번 사이에 로그가 자라
# NUL이 없어도 거짓으로 빨갰다(AL-M1 사본의 pointer 부팅 B).
if [ "$(tr -cd '\0' < "$LOG" | wc -c)" -ne 0 ]; then
```

`pane/check.sh`:

E1 — `old_string`(기준 파일 658줄부터):

```bash
if [ "$(tr -d '\0' < "$LOG" | wc -c)" -ne "$(wc -c < "$LOG")" ]; then
```

`new_string`:

```bash
# NUL만 세어 한 번에 읽는다(AL-M1). 예전에는 파일을 두 번 읽어(NUL을 뺀 길이 · 전체 길이)
# 견줬는데, QEMU가 아직 돌며 terminal의 dump를 쓰는 동안이라 두 번 사이에 로그가 자라
# NUL이 없어도 거짓으로 빨갰다(AL-M1 사본의 pointer 부팅 B).
if [ "$(tr -cd '\0' < "$LOG" | wc -c)" -ne 0 ]; then
```

### 3-4. 확인

```bash
cd /Users/dp/Repository/tars-linux && for f in gate_lib.sh check.sh pointer/check.sh copy/check.sh render/check.sh pane/check.sh; do cmp "$f" "/tmp/run/al1/new/$f" || exit 1; bash -n "$f" || exit 1; done && echo same && \
sync && sleep 1 && \
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -v /tmp/run/al1/tools:/tools:ro -w /workspace tars-devcontainer bash /tools/entry.sh; rc=$?
rmdir /tmp/run/docker.lock
```

`entry rc=0`이고 그 앞에 아무 줄도 없어야 한다. `/tmp/run/al1/tools/`의 `entry.sh` · `one.sh`는 AL-M0 plan의 것과 같다.

## Task 4: 체인 — PID 1을 많이 말하는 여섯

init을 오래 · 많이 말하게 하는 체인 여섯을 루트 `run_chain` 그대로(`one.sh`) 한 회차씩 돈다 — boot(부팅과 감독), power(시그널로 끄고 되살리기 — 처리기가
도는 자리), service(`init.sock` · 서비스 감독), net(dhcpcd · chronyd 감독과 reload), config(설정 파서의 로그 · `configLog` · reload), firewall(nft 기다림).
첫 체인이 init · terminal · initrd를 짓는다. 이 명령 그대로 사본에서 약 12분이었다(확정 8).

```bash
cd /Users/dp/Repository/tars-linux && mkdir -p /tmp/run/al1/impl && \
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -v /tmp/run/al1/tools:/tools:ro -v /tmp/run/al1/impl:/impl -w /workspace tars-devcontainer bash -c '
  for c in BF-M4:./boot/check.sh PM-M1:./power/check.sh CT-M2:./service/check.sh TD-M2:./net/check.sh CP-M2:./config/check.sh FW-M2:./firewall/check.sh; do
    TMPDIR=/impl bash /tools/one.sh "$c" 1 > "/impl/${c%%:*}.out" 2>&1
    grep -aE "cut log lines|one rc=" "/impl/${c%%:*}.out"
  done
  echo "panic lines: $(grep -raE "Attempted to kill init|Kernel panic|panic:" /impl/tars-gate.* | wc -l)"'; rc=$?
rmdir /tmp/run/docker.lock
```

여섯이 다 `A=0 B=0 C=0`과 `one rc=0`이고 `panic lines: 0`이어야 한다.

## Task 5: mutation

판 일곱. 앞의 넷은 진입 검사가, 뒤의 둘은 `run_chain`의 셈이 잡고, 마지막 판(`clean`)이 덮지 않은 빌드로 돌아온다. mutation 파일은
`/tmp/run/al1/mut/<판>/`에 있고 `/tmp/run/al1/run_mut.sh`는 AL-M0의 것에서 경로 셋(`mut` · 기본 `repo` · `tools`)만 다르다.

| 판 | 무엇을 되돌렸나 | 무엇이 잡나 |
|---|---|---|
| e1 | `audio.zig`의 `no sound card within` 한 곳을 `std.debug.print`로(치환 하나 되돌림) | `require_no_debug_print` |
| e5 | 셈의 B를 `^tars-init: terminal: `로 좁힘 | `require_cut_lines_found` |
| e6 | 셈의 C 줄을 지움 | `require_cut_lines_found` |
| j1 | `joined_screen_dump`에 `tars-init: ` 꼬리 떼기를 되살림 | `require_screen_dump_joins`의 화면 글자 조각 |
| b1 | init이 부팅에 `tars-init: planted terminal: screen> …` 한 줄을 냄 | `run_chain`의 셈 B(boot 체인은 초록) |
| c1 | init이 부팅에 3000바이트짜리 줄 하나를 냄 | `run_chain`의 셈 C(줄이 2048에서 ` [cut]`으로 끝난다) |

```bash
cd /tmp/run/al1 && export REPO=/Users/dp/Repository/tars-linux OUT=/tmp/run/al1/impl && E='bash /tools/entry.sh' && \
./run_mut.sh e1 "$E" audio.zig:init/src/audio.zig && \
./run_mut.sh e5 "$E" gate_lib.sh:gate_lib.sh && \
./run_mut.sh e6 "$E" gate_lib.sh:gate_lib.sh && \
./run_mut.sh j1 "$E" gate_lib.sh:gate_lib.sh && \
./run_mut.sh b1 'bash /tools/one.sh "BF-M4:./boot/check.sh" 1' power.zig:init/src/power.zig && \
./run_mut.sh c1 'bash /tools/one.sh "BF-M4:./boot/check.sh" 1' power.zig:init/src/power.zig && \
./run_mut.sh clean 'bash /tools/entry.sh && bash /tools/one.sh "BF-M4:./boot/check.sh" 1'
```

e1 · e5 · e6 · j1이 `TARS check FAIL: the entry checks …`, b1이 `B=1` · `BF-M4 FAIL`, c1이 `C=1` · `BF-M4 FAIL`, `clean`이 `entry rc=0` · `A=0 B=0 C=0` ·
`one rc=0`이어야 한다.

## Task 6: lead가 하는 것

1. 루트 게이트 2회(약 60분). 회차마다 셈 줄이 `A=0 B=0 C=0`이어야 한다.
2. 실측 절을 채우고, 구현자의 diff를 읽고, commit한다.
3. 닫기 — design의 `Status:`, `CLAUDE.md`의 완료 표, `MEMORY.md` · `docs/decisions/`, `docs/guides/lessons.md`. 아래 "닫을 때 lead가 고칠 자리".

### 닫을 때 lead가 고칠 자리(AL 전체)

- design `docs/specs/2026-10-07-tars-atomic-log-lines-design.md`의 `Status:` — 끝났다(날짜, AL-M0 · M1), plan 둘의 실측 절이 값이라는 한 줄과 기억 파일.
- design 본문의 수 둘 — init 153곳(호출은 151), 로그를 지우던 자리 열하나(열넷, AL-M0 plan 확정 4). design은 착수 전의 값이니 고치지 않고 Status 줄에서
  plan을 가리키는 것으로 충분하다.
- `CLAUDE.md`의 완료 표에 한 행 — 무엇이 섰나: terminal과 init의 시리얼 줄이 write 한 번이고, 루트 `check.sh`가 회차마다 끼어든 줄(A · B)과 잘린
  줄(C)을 세어 FAIL로 본다. 로그의 주인은 회차 디렉터리이고 체인은 로그를 안 지운다.
- `docs/decisions/`에 한 파일(예: `project_atomic_log_lines.md`)과 `MEMORY.md` 한 줄 — `std.debug.print`는 호출마다 잠그고 비우므로 한 줄이 write
  여럿이다, tty는 write 한 번만 묶는다, 2048은 커널 chunk, 끼어듦은 드물어서 되돌린 치환은 런타임이 아니라 진입 검사가 지킨다(AL-M0 확정 8의 m1).
- `docs/guides/lessons.md` — "게이트를 돌리고 읽는 법"에 회차 디렉터리(`<TMPDIR>/tars-gate.XXXXXX/<체인>-<회차>/`)와 셈 줄 읽는 법, "다시 조사하지 말
  실측"에 위의 사슬.
- `HANDOFF.md`.

## design과 다르게 적은 것

1. init의 치환은 153곳이 아니라 151곳이다 — design의 표는 `rg -c 'std\.debug\.print'`로 셌고 그 수에 `config.zig` · `power.zig`의 doc 주석 한 줄씩이
   들어 있었다. 호출은 151이다.
2. 2048을 넘는 줄을 지키는 자리를 셈의 C로 정했다(design 결정 4의 A · B에 하나를 더함). lead의 요청 — init에 시그널 처리기가 있으니 2048 넘는 줄을
   지켜야 한다 — 을 런타임으로 받은 것이다.
3. 체인 넷의 NUL 검사(Task 3-3)는 design에 없다. 사본 실측이 드러낸 게이트의 거짓 빨강이라 같은 milestone에 넣었다.

## 이 milestone에서 안 하는 것

- 커널 printk와 콘솔 셸 프롬프트가 자르는 것(design 비목표 1 · 2).
- `tars-config` · `tars-service` · `tars-install`이 사람에게 쓰는 글(`writeAll`) — 치환은 `std.debug.print`만이다.

## AL-M1이 실측한 것

(구현과 루트 게이트 뒤에 lead가 채운다.)
