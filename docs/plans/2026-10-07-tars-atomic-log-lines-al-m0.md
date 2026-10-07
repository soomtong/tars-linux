# AL-M0 — terminal이 시리얼 줄을 write 한 번으로 낸다

Date: 2026-10-07
Design: `docs/specs/2026-10-07-tars-atomic-log-lines-design.md`(결정 1 ~ 7, HEAD `22061fc`)
Status: plan을 썼다. 구현 전이다. plan을 쓰며 사본에서 돈 값은 "착수 전에 확정한 것"에, 구현과 루트 게이트의 값은 맨 아래 "AL-M0이 실측한 것"에 들어간다.

## 누가 무엇을 하나

design 결정 7. Task 0 ~ 6은 구현 서브에이전트가 main 작업 트리에서 직접 편집하고 돌린다. Task 7(루트 게이트 2회 · 실측 절 · commit)은 lead(Fable)가
한다. 구현자는 commit하지 않고, 끝에 `git diff --stat` · `git diff | rg '^-'` · 각 Task의 명령 출력을 그대로 보고한다. 이 plan의 "확정한 것" 절과
"실측한 것" 절은 구현자가 고치지 않는다.

권하는 모델은 Sonnet이다. 손으로 옮기는 편집이 없다 — 새 파일 둘은 plan의 블록을 그대로 쓰고, terminal의 치환 98곳은 perl 한 줄이고, 나머지 편집
스물셋은 `old_string` · `new_string`이며, 각 Task 끝의 `cmp`가 사본과 바이트까지 같은지를 본다. 판단이 드는 자리가 없다.

Opus로 올리는 조건. 아래 하나라도 보이면 구현자는 고치지 말고 멈춰 보고하고, lead가 Opus로 원인을 찾는다.

1. 어느 회차의 셈이든 `A=`가 0이 아니다(Task 5 · 루트 게이트). AL-M0 뒤로는 생길 수 없는 줄이다 — 생겼으면 terminal이 아직 어딘가에서 한 줄을 write
   여럿으로 낸다.
2. `logline_test`의 열세 경우 가운데 하나라도 빨갛다.
3. 사본에서 초록이었던 체인(아래 확정 4 · 5의 표)이 단독으로 빨갛다.
4. 시리얼 로그에 `terminal: ` · `kms: `로 시작하는데 ` [cut]`으로 끝나는 줄이 있다 — 게이트가 내는 줄은 2048바이트를 안 넘어야 한다(확정 6).

이 plan의 코드는 저장소 밖 사본(`/tmp/run/al0/repo/`)에 먼저 넣어 돌렸고, 아래의 블록은 그 사본에서 기계로 뽑은 것이다(`/tmp/run/al0/render.py`).
기준은 HEAD `22061fc`의 파일(`/tmp/run/al0/base/`)이고 편집 뒤의 파일은 `/tmp/run/al0/new/`다. `terminal/src/main.zig`의 편집 넷만은 Task 2의 perl
치환 뒤가 기준이다(`/tmp/run/al0/stage2/`). 편집은 Edit 도구에 글자 그대로 넣고(또는 plan 본문에서 블록을 기계로 뽑아 넣고), 각 Task 끝에서 `new/`
(Task 2는 `stage2/`)와 `cmp`한다. 다르면 편집이 빗나간 것이니 plan의 글자에 맞춰 고친다. plan의 글자와 `new/`가 서로 다르다고 보이면 고치지 말고 그
자리를 보고한다. 편집은 한 파일 안에서 E1부터 차례로 넣는다.

| 파일 | 무엇을 | 줄 |
|---|---|---|
| `terminal/src/logline.zig` | 새 파일 — `MAX` · `CUT` · `Line` · `print`, write 한 번 | +113 |
| `terminal/src/logline_test.zig` | 새 파일 — 경우 열셋. fd 2를 SEQPACKET 소켓으로 바꿔 write 수까지 센다 | +241 |
| `init/src/logline.zig` | 새 파일 — 위의 것을 그대로 복사(init은 M1에서 쓴다. 진입 검사의 `cmp`가 지금부터 지킨다) | +113 |
| `terminal/build.zig` | 편집 둘 — `logline_test` 모듈과 `test` 스텝 | +15 |
| `terminal/src/main.zig` · `drm.zig` · `font.zig` · `vt.zig` | perl 치환 — `std.debug.print(` → `logline.print(` 98곳, 파일마다 import 한 줄 | +102 −98 |
| `terminal/src/main.zig` | 편집 넷 — `dumpScreen`이 `Line` 하나에 짓는다, `screenLineMax`, 버퍼 할당, 부르는 자리 | +20 −2 |
| `gate_lib.sh` | 편집 하나 — `cut_log_lines` | +38 |
| `check.sh` | 편집 셋 — 회차 디렉터리 · `count_cut_lines` · `run_chain`, 진입 검사 셋, PASS 줄 | +89 −2 |
| `audio` · `dictation` · `firewall` · `nic` · `service` · `wifi` · `pointer` · `install`의 `check.sh` | 편집 열셋 — 시리얼 로그를 안 지운다(audio는 부팅마다 새 로그, install은 로그를 `$WORK` 밖에) | +16 −14 |

`git diff --stat`은 18 files, +747 −116이다(새 파일 셋 포함). init의 코드 · 커널 · Dockerfile · `make_initrd.sh`는 안 바뀐다. 새 체인 · 새 포트도 없다.

design의 `Status:` · `CLAUDE.md` · `MEMORY.md` · `docs/decisions/` · `docs/guides/` · `HANDOFF.md`는 구현자가 안 고친다.

모든 명령은 저장소 루트에서 친다. 서브에이전트의 Bash는 호출마다 작업 디렉터리가 돌아가므로 명령 앞에 `cd /Users/dp/Repository/tars-linux &&`를
붙인다. 빌드 · 체인은 언제나 컨테이너에서 한다. 구현자의 측정용 파일은 `/tmp/run/al0/impl/` 아래에 둔다. `/tmp/run/al0/` 바로 아래는 이 plan을
쓰며 만든 것이고 대조에 쓴다. 지우지 않는다.

Docker VM의 메모리가 4GB다. 컨테이너는 언제나 하나씩 돌린다. 모든 `docker run`을 아래로 감싼다. 명령이 실패해도 lock은 꼭 푼다.
`run_in_background`로 돌리는 명령이 lock을 기다리게 두지 않는다 — 기다림은 앞에서 끝낸다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run … ; rc=$?
rmdir /tmp/run/docker.lock
```

macOS에서 파일을 고친 직후의 `docker run`이 고치기 전의 내용을 본 적이 이 plan을 쓰며 두 번 있었다(빌드가 옛 파일로 실패했다가 같은 명령을 다시
돌리면 통과했다). 편집 직후의 빌드 앞에는 `sync; sleep 1`을 둔다.

## 이 milestone이 끝나면

- terminal이 시리얼에 내는 줄(`terminal: …` · `kms: …` · `font: …` · dictation 자식의 전달 줄)이 전부 write 한 번이다. 화면 dump는 프레임마다 글자
  수만큼의 write에서 한 번이 된다.
- 그래서 terminal의 줄 가운데에 init의 줄이 끼는 일(셈의 A)이 구조적으로 사라진다. init의 줄 가운데에 terminal의 줄이 끼는 일(B)은 init이 아직
  `std.debug.print`라 남는다 — AL-M1이 없앤다.
- 루트 `check.sh`가 회차마다 로그 디렉터리를 하나 주고(`<TMPDIR>/tars-gate.XXXXXX/<체인>-<회차>/`), 회차가 끝나면 끼어든 줄을 센다. A가 하나라도
  있으면 그 회차가 FAIL이고, B는 수와 줄만 찍는다. 회차마다 이런 줄이 하나 는다.

```
CP-M2 run 1/2: cut log lines A=0 B=0 (/tmp/tars-gate.6iBHEK/CP-M2-1)
```

- 진입 검사가 셋 는다 — 셈이 실제 줄 넷을 맞게 가르는가, `terminal/src/logline.zig`와 `init/src/logline.zig`가 같은가, `terminal/src`의 게스트
  파일에 `std.debug.print`가 없는가.
- 마지막 PASS 줄이 로그 디렉터리를 말한다: `TARS check PASS: all chains 2/2 consecutive runs succeeded (logs in /tmp/tars-gate.XXXXXX)`.

## 착수 전에 확정한 것

2026-10-07에 이 plan을 쓰며 저장소 사본(`/tmp/run/al0/repo/`, HEAD `22061fc`의 추적 파일 전부를 rsync로 맞추고 `cmp`로 봤다)과 이미지
`tars-devcontainer`로 쟀다. 측정 파일은 `/tmp/run/al0/meas/`(체인 로그 · 셈)와 `/tmp/run/al0/mut/`(mutation)에 있다. 저장소의 작업 트리는 이
plan 말고는 한 글자도 안 바뀌었다.

1. 셈이 design의 수를 다시 낸다. 새 `cut_log_lines`를 TC-M3 루트 게이트의 로그 여섯 디렉터리에 그대로 돌리면 A 7 · 2 · 4 · 7 · 6 · 2, B 0 · 0 · 0 ·
   1 · 0 · 0 — design 실측 A의 표와 같다. B에서 빼는 init의 줄은 fmt를 글자 그대로 맞춘 정규식이라(`reload terminal: pid \d+, shell \S+ keyboard=…
   clipboard=\S+`) 그 줄 뒤에 terminal의 조각이 붙은 줄은 여전히 B다.

2. 바꾸기 전 · 뒤(같은 세션, 같은 체인 스크립트, 체인마다 회차 디렉터리).

   | 체인 | 전: rc · 시간 · A · B | 뒤: rc · 시간 · A · B |
   |---|---|---|
   | terminal | 0 · 34초 · 0 · 0 | 0 · 76초 · 0 · 0 |
   | render | 0 · 111초 · 0 · 0 | 0 · 109초 · 0 · 0 |
   | pointer | 0 · 90초 · 0 · 0 | 0 · 76초 · 0 · 0 |
   | pane | 0 · 52초 · 0 · 0 | 0 · 52초 · 0 · 0 |
   | config | 0 · 194초 · 1 · 0 | 0 · 193초 · 0 · 0 |

   "전"의 config A 하나는 `terminal: cursor> vt=block drawn=block row=20 col=42 cols=1 ink=0` 뒤에 `tars-init: audio: no sound card within 5000ms …`가
   붙은 줄이다 — 64바이트를 넘는 `cursor>` 줄이 둘로 나갔다. "뒤"의 terminal 76초는 첫 체인이라 terminal을 다시 짓는 시간이 들었다(소스가 바뀌었다).
   나머지는 ±15초 안이다. `render> first frame`(첫 프레임, dump 앞에서 잰다)은 전 55 ~ 59밀리초 · 뒤 62 ~ 64밀리초로 첫 부팅의 흔들림 안이다 — 이
   값은 dump를 안 담으므로 dump가 빨라진 것은 여기 안 보인다.

3. 화면 dump의 바이트가 같다 — 같은 부팅에서 견줬다. 측정용 사본(`/tmp/run/al0/measpatch/main.zig`, plan 코드 아님)의 `dumpScreen`이 같은 칸을 옛
   모양(`std.debug.print` 조각, 머리 `terminal: screen0> `)으로 먼저 찍고 새 모양(`Line`, `terminal: screen> `)을 이어 찍게 해서 체인 넷을 돌리고,
   `/tmp/run/al0/cmp_screen.pl`이 프레임마다 둘을 견줬다(옛 줄이 커널 · init의 줄에 잘렸으면 `joined_screen_dump`와 같은 규칙으로 잇는다).

   | 체인 | 같은 프레임 | 다른 프레임 |
   |---|---|---|
   | terminal | 40 | 0 |
   | render | 694 | 0 |
   | hangul | 168(그 가운데 한글 음절이 든 것 76) | 0 |
   | pane | 318 | 0 |

   덤으로 pane의 그 판에서 셈이 A 하나를 잡았다 — 옛 모양 `screen0>` 줄의 `… apply` 뒤에 `tars-init: reload terminal: pid 39 …`가 끼었다. 셈이 실제
   부팅의 실제 끼어듦을 잡는다는 것이 여기서도 보였다(새 모양 `screen>` 줄은 같은 프레임에서 온전했다).

4. 로그를 지우던 자리. design은 여덟 체인 열한 자리라 했는데 다시 세니 열넷이다 — `service`의 `rm -f "$B_LOG"`(부팅 B의 로그를 다른 이름으로 들고
   있었다)와, `audio`의 부팅 함수가 같은 파일을 `: > "$LOG"`로 비우고 다시 쓰던 것(부팅 넷 가운데 마지막 하나만 남았다)과, `install`의 로그 경로 두
   자리. 고친 뒤 여덟 체인을 한 번씩 돌렸다 — 전부 초록, A=0 B=0, 남은 로그 수가 부팅 수와 같다.

   | 체인 | rc · 시간 | 부팅 = 남은 로그 |
   |---|---|---|
   | audio | 0 · 45초 | 4 = 4(고치기 전 판은 4 부팅에 로그 1) |
   | dictation | 0 · 93초 | 2 = 2 |
   | firewall | 0 · 62초 | 2 = 2 |
   | nic | 0 · 34초 | 2 = 2 |
   | service | 0 · 74초 | 4 = 4 |
   | wifi | 0 · 124초 | 3 = 3 |
   | install | 0 · 109초 | 7 = 7 |
   | pointer | 0 · 76초(확정 2) | 2 = 2 |

5. 나머지 체인. 편집이 안 닿은 여덟을 한 번씩 돌렸다 — `TMPDIR`이 회차 디렉터리로 바뀌어도 서는지(design 위험 6).

   | 체인 | rc · 시간 | A · B | 부팅 = 남은 로그 |
   |---|---|---|---|
   | boot | 0 · 24초 | 0 · 0 | 1 = 1 |
   | copy | 0 · 172초 | 0 · 0 | 1 = 1 |
   | device | 0 · 17초 | 0 · 0 | 1 = 1 |
   | input | 0 · 42초 | 0 · 0 | 2 = 2 |
   | machine | 0 · 20초 | 0 · 0 | 1 = 1 |
   | net | 0 · 186초 | 0 · 0 | 5 = 5 |
   | power | 0 · 51초 | 0 · 0 | 3 = 3 |
   | tools | 0 · 63초 | 0 · 0 | 1 = 1 |

   확정 2 · 3 · 4와 합쳐 체인 스물하나가 전부 회차 디렉터리 아래에서 초록이었고, 바꾼 뒤의 A는 모두 0이다(hangul은 확정 3의 측정용 빌드로 돌았다).

6. 2048을 넘는 줄. 확정 2 · 3 · 4 · 5의 모든 로그에 ` [cut]`으로 끝나는 줄이 0이다. 게이트가 내는 줄 가운데 화면 dump 밖에서 가장 긴 것은
   design 실측 B대로 111바이트(terminal)다. 화면 dump는 `screenLineMax` 버퍼라 안 잘린다 — 155×47이면 29,345바이트이고 가장 긴 dump는 7,172바이트다.

7. 패닉 표(terminal 쪽. PID 1은 AL-M1이다). terminal의 게스트 빌드는 Debug라 안전 검사가 살아 있고, 패닉하면 terminal이 죽고 init이 다시 띄운다
   (빨리 죽음이 쌓이면 `giving up on terminal`) — 화면이 사라지는 일이다.

   | 자리 | 무엇이 패닉이 될 수 있었나 | 어떻게 막았나 | 누가 보나 |
   |---|---|---|---|
   | `Line.print`의 자르기 | `buf[0 .. buf.len - CUT.len]`의 뺄셈, `buf[e..][0..CUT.len]` | `Line.init`이 `buf.len <= CUT.len`이면 처음부터 넘친 줄로 둔다 — `print`가 그 앞에서 돌아간다. `e`는 `whole`이 `buf.len - CUT.len` 이하로 준다 | `logline_test` 경우 4 · 6 · 7 · 8 · 12 · 13 |
   | `Writer.fixed`의 에러 | `w.print`의 `error.WriteFailed` | `catch`가 받아 자르기로 간다. 밖으로 안 나간다 | 경우 4 · 11 |
   | `whole`의 UTF-8 | `utf8ByteSequenceLength`의 에러, 이어짐 바이트만 있는 꼬리 | `catch return b.len`, 이어짐 바이트는 셋까지만 거슬러 본다 | 경우 6 · 7 · 8 |
   | write의 에러 | EBADF · EIO · 0바이트 | 버린다. EINTR만 다시, 덜 쓰이면 나머지를 마저 | 경우 1 · 2 |
   | 화면 dump 버퍼 | `allocator.alloc` 실패 | `try` — `cell_buf`의 할당과 같은 자리 · 같은 처리(main이 에러로 끝나고 init이 다시 띄운다) | 체인 |
   | `screenLineMax` | `usize` 넘침 | `rows × (cols × 4 + 3)` — u16 둘의 곱이라 usize에서 안 넘친다 | 컴파일 |

8. mutation(Task 6이 다시 돈다).

   | 판 | 무엇을 되돌렸나 | 무엇이 잡나 | 결과 |
   |---|---|---|---|
   | e1 | `main.zig`의 `pointer>` 한 곳을 `std.debug.print`로 | 진입 검사 `require_no_debug_print` | FAIL, 1초 |
   | e2 | `init/src/logline.zig`의 `MAX`를 4096으로 | 진입 검사 `require_same_logline` | FAIL, 0초 |
   | e3 | 셈의 A를 `^terminal: tars-init: `로 좁힘 | 진입 검사 `require_cut_lines_found` | FAIL, 0초 |
   | e4 | 셈의 B에서 빼는 줄을 못 맞게 | 같은 검사(온전한 `reload terminal` 줄이 B로 잡힌다) | FAIL, 1초 |
   | t1 | `whole`을 "이어짐 바이트만 걷어 내는" 첫 원형으로 | `logline_test` 경우 7(글자가 자르는 자리에 정확히 맞으면 온전한 글자까지 뗀다) | FAIL |
   | t2 | 자른 뒤 `cut = true`를 안 둠 | `logline_test` 경우 13 | FAIL |
   | m2 | terminal이 시작할 때 `terminal: planted tars-init: …` 한 줄을 냄 | `run_chain`의 셈(terminal 체인은 초록) | `A=2`(terminal이 두 번 뜬다) → FAIL |
   | m1 | `dumpScreen`이 칸마다 `flush` — 바꾸기 전의 write 모양 | 셈이 실제 끼어듦을 만나면 | config 2회 · pane 2회 모두 A=0, 초록 |

   t2는 처음에 살아남았다 — 경우 11은 자른 뒤 버퍼가 꽉 차 있어 깃발이 없어도 다음 조각이 못 들어갔다. 자르기가 글자 앞으로 물러나 빈 자리가 남는
   경우 13을 더한 뒤 잡혔다.

   m1이 살아남은 것은 셈의 구멍이 아니라 끼어듦이 드물기 때문이다. 바꾸기 전의 TC-M3 루트 게이트는 한 판(체인 스물하나 × 2회)에 A가 2 ~ 7이었고,
   확정 2의 "전"은 다섯 체인에 하나였다 — 한 체인 한 회차로는 대개 안 나온다. 그래서 "셈이 진짜 끼어듦을 잡는다"는 실제 로그로 보였다(확정 1의
   스물여덟, 확정 2의 하나, 확정 3의 하나). "셈이 회차를 빨갛게 한다"는 m2가 매번 같게 보였다. 되돌린 치환이 런타임에 잡히는지는 운이고, 그래서
   그 자리를 런타임이 아니라 진입 검사(e1)가 지킨다.

## Task 0: 바꾸기 전의 기준값

```bash
cd /Users/dp/Repository/tars-linux && git log --oneline -1 && git status --short && \
  rg -c 'std\.debug\.print\(' terminal/src/main.zig terminal/src/drm.zig terminal/src/font.zig terminal/src/vt.zig && \
  rg -l 'std\.debug\.print\(' terminal/src -g '!*_test.zig' | sort
```

`22061fc`이고 작업 트리가 깨끗하고(이 plan 파일 하나만 `??`일 수 있다), 수가 `main.zig:90` · `drm.zig:6` · `font.zig:1` · `vt.zig:1`, 파일 목록이 그
넷이어야 한다. 다르면 멈추고 보고한다.

## Task 1: `logline.zig`와 그 검사

### 1-1. 새 파일 셋

`terminal/src/logline.zig`:

```zig
//! 시리얼 로그 한 줄을 write(2) 한 번으로 낸다(AL design 결정 1).
//!
//! init과 terminal은 같은 /dev/console(ttyS0)에 쓴다. 커널의 tty는 write 한 번
//! 동안 잠금(`atomic_write_lock`)을 쥐므로 그 안에는 남의 바이트가 못 끼어들고,
//! write와 write 사이에는 누구나 끼어든다. `std.debug.print`는 부를 때마다 64바이트
//! 버퍼로 잠그고 비우므로 긴 줄 하나가 write 여럿이 되고, 그 사이에 다른 프로세스의
//! 줄이 들어와 게이트가 읽는 줄을 자른다(TC-M3 루트 게이트). 여기서는 한 줄을 버퍼에
//! 다 지은 뒤에 한 번 쓴다.
//!
//! 이 파일은 `init/src/logline.zig`와 `terminal/src/logline.zig`에 바이트까지 같게
//! 둘 있다. 루트 `check.sh`의 진입 검사가 `cmp`로 지킨다 — 한쪽을 고치면 다른 쪽에
//! 그대로 복사한다. 시스템 콜을 `std.os.linux`로 직접 부르는 이유도 그것이다. init은
//! libc가 없고 terminal은 있지만, 둘 다 리눅스라 같은 줄이 두 빌드에 선다.
//!
//! 패닉 자리가 없어야 한다. init(AL-M1)은 ReleaseSafe의 PID 1이라 여기의 패닉이 커널
//! 패닉이다. 에러는 밖으로 안 내보내고, 런타임 값에 `assert` · `unreachable`을 안 쓰고,
//! 슬라이스 경계는 `logline_test.zig`가 경계값으로 덮는다.
const std = @import("std");
const linux = std.os.linux;

/// `print` 한 줄의 상한(바이트). 커널 tty가 긴 write를 끊는 단위와 같다
/// (drivers/tty/tty_io.c `iterate_tty_write`의 chunk = 2048). 그보다 긴 write는
/// 2048씩 끊기고, 끊는 자리에서 처리할 시그널이 걸려 있으면 거기서 돌아간다 —
/// 그러면 나머지를 쓰는 다음 write 앞에 남의 줄이 끼어든다. 2048 이하는 끊을
/// 자리가 없어 시그널과 무관하게 한 덩이다(init은 SIGTERM · SIGINT 처리기를 단다).
///
/// 화면 dump는 이보다 길다. 그 줄은 `Line`에 큰 버퍼를 따로 주고, terminal이 시그널
/// 처리기를 하나도 안 달기 때문에 끊기지 않는다(AL design 결정 2). terminal에
/// 처리기를 다는 날 그 문장이 거짓이 된다.
pub const MAX = 2048;

/// 버퍼를 넘친 줄의 꼬리. 잘린 줄도 늘 줄바꿈으로 끝나야 다음 줄의 머리를 안 먹는다.
pub const CUT = " [cut]\n";

/// 여러 조각으로 짓는 한 줄. 조각마다 `print`하고 끝에 `flush` 한 번이다.
/// `flush`를 안 부르면 아무것도 안 나간다.
pub const Line = struct {
    buf: []u8,
    end: usize = 0,
    cut: bool = false,

    /// `buf`가 `CUT`보다 크지 않으면 처음부터 넘친 줄로 다룬다(아무것도 안 낸다).
    /// 패닉 대신이다.
    pub fn init(buf: []u8) Line {
        return .{ .buf = buf, .cut = buf.len <= CUT.len };
    }

    /// `fmt`를 지금까지의 끝에 붙인다. 넘치면 글자 경계에서 자르고 `CUT`을 붙인 뒤,
    /// 그 뒤의 `print`는 아무것도 안 한다.
    pub fn print(self: *Line, comptime fmt: []const u8, args: anytype) void {
        if (self.cut) return;
        var w: std.Io.Writer = .fixed(self.buf);
        w.end = self.end;
        w.print(fmt, args) catch {
            // `Writer.fixed`는 버퍼를 끝까지 채운 뒤 실패한다. `CUT` 자리를 비우고
            // 그 앞에서 글자가 온전한 데까지만 남긴다.
            const e = whole(self.buf[0 .. self.buf.len - CUT.len]);
            @memcpy(self.buf[e..][0..CUT.len], CUT);
            self.end = e + CUT.len;
            self.cut = true;
            return;
        };
        self.end = w.end;
    }

    pub fn bytes(self: *const Line) []const u8 {
        return self.buf[0..self.end];
    }

    /// 지은 줄을 fd 2에 write 한 번으로 내고 비운다.
    pub fn flush(self: *Line) void {
        writeAll(self.bytes());
        self.end = 0;
        self.cut = self.buf.len <= CUT.len;
    }
};

/// `std.debug.print`와 같은 fmt를 받아 한 줄을 write 한 번으로 낸다. 버퍼는 스택의
/// `MAX`바이트다. 넘는 줄은 `CUT`으로 끝난다.
pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [MAX]u8 = undefined;
    var line = Line.init(&buf);
    line.print(fmt, args);
    line.flush();
}

/// 덜 쓰이면 나머지를 마저 쓰고, 시그널에 끊기면(EINTR) 다시 쓴다. 다른 에러는
/// 버린다 — 로그를 못 쓴 것 때문에 멈추면 안 된다.
fn writeAll(b: []const u8) void {
    var off: usize = 0;
    while (off < b.len) {
        const rc = linux.write(2, b[off..].ptr, b.len - off);
        switch (linux.errno(rc)) {
            .SUCCESS => {
                if (rc == 0) return;
                off += rc;
            },
            .INTR => continue,
            else => return,
        }
    }
}

/// `b`에서 글자 가운데를 자르지 않는 가장 긴 앞부분의 길이. 마지막 글자의 머리
/// 바이트를 찾아, 그 글자가 다 들어와 있으면 `b.len`, 모자라면 머리 앞이다.
/// UTF-8이 아닌 바이트는 그대로 둔다.
fn whole(b: []const u8) usize {
    var p = b.len;
    while (p > 0 and b.len - p < 3 and b[p - 1] & 0xC0 == 0x80) p -= 1;
    if (p == 0) return b.len;
    const n = std.unicode.utf8ByteSequenceLength(b[p - 1]) catch return b.len;
    return if (p - 1 + n <= b.len) b.len else p - 1;
}
```

`terminal/src/logline_test.zig`:

```zig
//! `logline.zig`의 호스트 검사(AL-M0). init의 사본은 `cmp`로 같으므로 여기서 함께
//! 덮인다.
//!
//! 이 저장소의 다른 `*_test.zig`처럼 `main`이 경우를 하나씩 돌리고 `OK` 줄을 찍는다.
//!
//! 나가는 바이트와 write의 횟수를 함께 본다. fd 2를 잠깐 SOCK_SEQPACKET 소켓의 한쪽
//! 끝으로 바꿔 두면 write 한 번이 메시지 하나가 되므로, 받은 메시지의 수가 곧 write의
//! 수다 — "한 줄 = write 한 번"이 이 파일이 지키는 성질이다.
const std = @import("std");
const linux = std.os.linux;
const logline = @import("logline.zig");

const Caught = struct {
    writes: usize = 0,
    data: [64 * 1024]u8 = undefined,
    len: usize = 0,

    fn bytes(self: *const Caught) []const u8 {
        return self.data[0..self.len];
    }
};

/// `f(arg)` 동안 fd 2에 쓰인 것을 write 단위로 받는다.
fn catchWrites(out: *Caught, comptime f: anytype, arg: anytype) !void {
    var sv: [2]i32 = undefined;
    if (linux.errno(linux.socketpair(linux.AF.UNIX, linux.SOCK.SEQPACKET | linux.SOCK.CLOEXEC, 0, &sv)) != .SUCCESS)
        return error.SocketPair;
    defer _ = linux.close(sv[0]);
    const saved: i32 = @intCast(linux.dup(2));
    _ = linux.dup2(sv[1], 2);
    _ = linux.close(sv[1]);
    f(arg);
    _ = linux.dup2(saved, 2); // 소켓의 쓰는 끝이 닫혀 아래 read가 0으로 끝난다
    _ = linux.close(saved);
    out.* = .{};
    while (true) {
        const rc = linux.read(sv[0], out.data[out.len..].ptr, out.data.len - out.len);
        if (linux.errno(rc) != .SUCCESS) return error.Read;
        if (rc == 0) break;
        out.len += rc;
        out.writes += 1;
    }
}

fn filled(buf: []u8, ascii_len: usize, tail: []const u8) []const u8 {
    @memset(buf[0..ascii_len], 'a');
    @memcpy(buf[ascii_len..][0..tail.len], tail);
    return buf[0 .. ascii_len + tail.len];
}

fn printS(s: []const u8) void {
    logline.print("{s}", .{s});
}

fn case1() !void {
    var c: Caught = .{};
    try catchWrites(&c, struct {
        fn f(_: void) void {
            logline.print("terminal: pointer> at x={d} y={d} buttons={d} wheel={d} shown={d} ink={d}\n", .{ 1279, 799, 0, 0, 1, 1 });
        }
    }.f, {});
    try std.testing.expectEqual(@as(usize, 1), c.writes);
    try std.testing.expectEqualStrings("terminal: pointer> at x=1279 y=799 buttons=0 wheel=0 shown=1 ink=1\n", c.bytes());
}

fn case2() !void {
    var c: Caught = .{};
    try catchWrites(&c, printS, "");
    try std.testing.expectEqual(@as(usize, 0), c.writes);
    try catchWrites(&c, printS, "\n");
    try std.testing.expectEqual(@as(usize, 1), c.writes);
    try std.testing.expectEqualStrings("\n", c.bytes());
}

fn case3() !void {
    var src: [logline.MAX]u8 = undefined;
    const s = filled(&src, logline.MAX - 1, "\n");
    var c: Caught = .{};
    try catchWrites(&c, printS, s);
    try std.testing.expectEqual(@as(usize, 1), c.writes);
    try std.testing.expectEqualStrings(s, c.bytes());
}

fn case4() !void {
    var src: [logline.MAX + 1]u8 = undefined;
    const s = filled(&src, logline.MAX, "\n");
    var c: Caught = .{};
    try catchWrites(&c, printS, s);
    try std.testing.expectEqual(@as(usize, 1), c.writes);
    try std.testing.expectEqual(@as(usize, logline.MAX), c.len);
    try std.testing.expectEqualStrings(s[0 .. logline.MAX - logline.CUT.len], c.bytes()[0 .. logline.MAX - logline.CUT.len]);
    try std.testing.expect(std.mem.endsWith(u8, c.bytes(), logline.CUT));
}

fn case5() !void {
    var src: [logline.MAX]u8 = undefined;
    const s = filled(&src, logline.MAX - 3, "가");
    var c: Caught = .{};
    try catchWrites(&c, printS, s);
    try std.testing.expectEqualStrings(s, c.bytes());
}

fn case6() !void {
    // 자르는 자리(MAX - CUT.len)가 `가`(3바이트)의 둘째 바이트 뒤에 온다.
    const room = logline.MAX - logline.CUT.len;
    var src: [logline.MAX + 16]u8 = undefined;
    const s = filled(&src, room - 2, "가나다라마");
    var c: Caught = .{};
    try catchWrites(&c, printS, s);
    var want: [logline.MAX]u8 = undefined;
    const w = filled(&want, room - 2, logline.CUT);
    try std.testing.expectEqualStrings(w, c.bytes());
}

fn case7() !void {
    const room = logline.MAX - logline.CUT.len;
    var src: [logline.MAX + 16]u8 = undefined;
    const s = filled(&src, room - 3, "가나다라마");
    var c: Caught = .{};
    try catchWrites(&c, printS, s);
    var want: [logline.MAX]u8 = undefined;
    const w = filled(&want, room - 3, "가" ++ logline.CUT);
    try std.testing.expectEqualStrings(w, c.bytes());
}

fn case8() !void {
    const room = logline.MAX - logline.CUT.len;
    var src: [logline.MAX + 1]u8 = undefined;
    @memset(&src, 0x80);
    var c: Caught = .{};
    try catchWrites(&c, printS, &src);
    try std.testing.expectEqual(@as(usize, logline.MAX), c.len);
    try std.testing.expect(std.mem.allEqual(u8, c.bytes()[0..room], 0x80));
}

fn case9() !void {
    var c: Caught = .{};
    try catchWrites(&c, struct {
        fn f(_: void) void {
            var buf: [256]u8 = undefined;
            var l = logline.Line.init(&buf);
            l.print("terminal: screen> ", .{});
            l.print("{s}", .{"a"});
            l.print(" | ", .{});
            l.print("{s}", .{"가"});
            l.print("\n", .{});
            l.flush();
        }
    }.f, {});
    try std.testing.expectEqual(@as(usize, 1), c.writes);
    try std.testing.expectEqualStrings("terminal: screen> a | 가\n", c.bytes());
}

fn case10() !void {
    var c: Caught = .{};
    try catchWrites(&c, struct {
        fn f(_: void) void {
            var buf: [256]u8 = undefined;
            var l = logline.Line.init(&buf);
            l.print("terminal: screen> ", .{});
            l.print("{s}", .{"a"});
        }
    }.f, {});
    try std.testing.expectEqual(@as(usize, 0), c.writes);
}

fn case11() !void {
    var c: Caught = .{};
    try catchWrites(&c, struct {
        fn f(_: void) void {
            var buf: [10 + logline.CUT.len]u8 = undefined;
            var l = logline.Line.init(&buf);
            l.print("{s}", .{"0123456789ABCDEFGH"});
            l.print("{s}", .{"X"});
            l.flush();
            l.print("ok\n", .{});
            l.flush();
        }
    }.f, {});
    try std.testing.expectEqual(@as(usize, 2), c.writes);
    try std.testing.expectEqualStrings("0123456789 [cut]\nok\n", c.bytes());
}

fn case13() !void {
    // 자른 자리가 글자 앞으로 물러나면 버퍼 끝에 빈 자리가 남는다. 그 뒤의 조각이 표시 뒤에
    // 붙으면 줄이 `[cut]` 다음에 이어진다 — 넘친 뒤의 `print`는 아무것도 안 해야 한다.
    var c: Caught = .{};
    try catchWrites(&c, struct {
        fn f(_: void) void {
            var buf: [5 + logline.CUT.len]u8 = undefined;
            var l = logline.Line.init(&buf);
            l.print("{s}", .{"abc가나다라"});
            l.print("{s}", .{"X"});
            l.flush();
        }
    }.f, {});
    try std.testing.expectEqual(@as(usize, 1), c.writes);
    try std.testing.expectEqualStrings("abc [cut]\n", c.bytes());
}

fn case12() !void {
    var c: Caught = .{};
    try catchWrites(&c, struct {
        fn f(_: void) void {
            var buf: [logline.CUT.len]u8 = undefined;
            var l = logline.Line.init(&buf);
            l.print("terminal: x\n", .{});
            l.flush();
            var none: [0]u8 = .{};
            var z = logline.Line.init(&none);
            z.print("y\n", .{});
            z.flush();
        }
    }.f, {});
    try std.testing.expectEqual(@as(usize, 0), c.writes);
}

pub fn main() !void {
    const cases = .{
        .{ "a line that fits leaves as the same bytes in one write", case1 },
        .{ "an empty format writes nothing, a bare newline writes one byte", case2 },
        .{ "MAX bytes exactly is not cut", case3 },
        .{ "MAX + 1 bytes is cut to MAX with the mark, still one write", case4 },
        .{ "a hangul syllable ending exactly at MAX is kept whole", case5 },
        .{ "a cut that would split a syllable backs off to the syllable's start", case6 },
        .{ "a syllable ending exactly at the cut point stays", case7 },
        .{ "bytes that are not UTF-8 are cut at the cut point", case8 },
        .{ "pieces of a Line leave in one write only at flush", case9 },
        .{ "a Line that is never flushed writes nothing", case10 },
        .{ "after a cut further pieces are dropped, and flush starts a fresh line", case11 },
        .{ "a buffer no larger than the mark writes nothing instead of panicking", case12 },
        .{ "pieces after a cut that backed off do not land after the mark", case13 },
    };
    inline for (cases) |c| {
        c[1]() catch |err| {
            std.debug.print("FAIL: {s}: {s}\n", .{ c[0], @errorName(err) });
            return err;
        };
        std.debug.print("logline_test: {s} OK\n", .{c[0]});
    }
}
```

`init/src/logline.zig`는 복사한다. 손으로 다시 치지 않는다.

```bash
cd /Users/dp/Repository/tars-linux && cp terminal/src/logline.zig init/src/logline.zig && \
  cmp terminal/src/logline.zig /tmp/run/al0/new/terminal/src/logline.zig && \
  cmp terminal/src/logline_test.zig /tmp/run/al0/new/terminal/src/logline_test.zig && \
  cmp init/src/logline.zig /tmp/run/al0/new/init/src/logline.zig && echo same
```

init은 이 파일을 아직 안 쓴다(아무도 import하지 않으니 빌드에 안 들어간다). 지금 두는 까닭은 진입 검사의 `cmp`가 AL-M0부터 서게 하려는 것이다 —
AL-M1이 init에서 쓰기 시작할 때 두 파일은 이미 한 번 게이트를 지난 같은 파일이다.

### 1-2. `terminal/build.zig` — 편집 둘

E1 — `old_string`(기준 파일 344줄부터):

```zig
    // `zig build test` = 호스트에서 도는 검사만 빌드해서 실행한다.
```

`new_string`:

```zig
    // logline_test도 호스트에서 돈다(AL-M0). 한 줄을 write 한 번으로 내는 helper라 fd 2를
    // 소켓으로 바꿔 write의 수까지 센다. libc도 번역도 필요 없다 — init의 사본은 바이트까지
    // 같으므로(루트 check.sh의 cmp) 이 검사가 함께 덮는다.
    const logline_test_mod = b.createModule(.{
        .root_source_file = b.path("src/logline_test.zig"),
        .target = host_target,
        .optimize = optimize,
    });
    const logline_test = b.addExecutable(.{
        .name = "logline_test",
        .root_module = logline_test_mod,
    });
    b.installArtifact(logline_test);

    // `zig build test` = 호스트에서 도는 검사만 빌드해서 실행한다.
```

E2 — `old_string`(기준 파일 362줄부터):

```zig
    test_step.dependOn(&b.addRunArtifact(dictation_test).step);
```

`new_string`:

```zig
    test_step.dependOn(&b.addRunArtifact(dictation_test).step);
    test_step.dependOn(&b.addRunArtifact(logline_test).step);
```

### 1-3. 확인

```bash
cd /Users/dp/Repository/tars-linux && cmp terminal/build.zig /tmp/run/al0/new/terminal/build.zig && sync && sleep 1 && \
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer bash -c '
  zig build test > /tmp/t.log 2>&1; rc=$?
  grep -c "logline_test: .* OK" /tmp/t.log; grep -E "FAIL|error:" /tmp/t.log; echo rc=$rc'; rc=$?
rmdir /tmp/run/docker.lock
```

`13`과 `rc=0`이어야 한다. `FAIL`이 하나라도 있으면 Opus 조건 2다.

## Task 2: 치환 98곳

치환은 perl 한 줄이다. 파일마다 맨 첫 줄(`const std = @import("std");`) 뒤에 import 한 줄을 넣고, `std.debug.print(`를 전부 `logline.print(`로
바꾼다. fmt와 인자는 한 글자도 안 바뀐다 — 그래서 2048바이트 안의 줄은 나가는 바이트도 같다(design 위험 2).

```bash
cd /Users/dp/Repository/tars-linux && \
perl -0pi -e 's/\Aconst std = \@import\("std"\);\n/const std = \@import("std");\nconst logline = \@import("logline.zig");\n/; s/\bstd\.debug\.print\(/logline.print(/g' \
  terminal/src/main.zig terminal/src/drm.zig terminal/src/font.zig terminal/src/vt.zig && \
for f in main drm font vt; do echo "$f logline=$(rg -c 'logline\.print\(' terminal/src/$f.zig) import=$(rg -c '^const logline = @import\("logline.zig"\);$' terminal/src/$f.zig)"; done && \
rg -n 'std\.debug\.print' terminal/src -g '!*_test.zig'; \
cmp terminal/src/main.zig /tmp/run/al0/stage2/terminal/src/main.zig && \
for f in drm font vt; do cmp terminal/src/$f.zig /tmp/run/al0/new/terminal/src/$f.zig || exit 1; done && echo same
```

`main logline=90 import=1` · `drm 6 1` · `font 1 1` · `vt 1 1`이고, 남은 `std.debug.print`는 `terminal/src/logline.zig`의 주석 두 줄(5행 · 78행)뿐이고,
마지막이 `same`이어야 한다. `main.zig`만 `stage2/`와 견주는 까닭은 다음 Task가 그 위에 편집 넷을 더하기 때문이다.

`git diff --stat`으로 넷이 `+91 −90` · `+7 −6` · `+2 −1` · `+2 −1`인지 본다. 지우는 줄이 치환된 줄뿐인지는 아래로 본다 — 지운 줄 98개가 전부
`std.debug.print(`를 담아야 한다.

```bash
cd /Users/dp/Repository/tars-linux && git diff terminal/src | rg '^-[^-]' | rg -vc 'std\.debug\.print\('; git diff terminal/src | rg '^-[^-]' | rg -c 'std\.debug\.print\('
```

`0`과 `98`이어야 한다(첫 명령의 `0`은 `rg -c`가 맞는 줄이 없을 때 아무것도 안 찍을 수도 있다 — 빈 출력도 0이다).

## Task 3: `dumpScreen`이 한 줄을 한 번에 — `terminal/src/main.zig` 편집 넷

E1은 doc 주석 넷째 단락과 함수 머리, E2는 `dumpScreen`의 끝과 `screenLineMax`, E3은 `cell_buf` 옆의 버퍼 할당, E4는 부르는 자리다. 머리 · 칸 · ` | ` ·
`\n`의 순서와 글자는 그대로이고, 차이는 `logline.print` 넷이 `line.print` 넷이 되고 끝에 `line.flush()` 한 번이 붙는 것이다.

E1 — `old_string`(기준 파일 678줄부터):

```zig
fn dumpScreen(cells: []const vt.CellGlyph) void {
    logline.print("terminal: screen> ", .{});
    var last_row: u16 = 0;
    for (cells) |cell| {
        if (cell.row != last_row) {
            logline.print(" | ", .{});
```

`new_string`:

```zig
///
/// 줄 하나를 `buf`에 다 지은 뒤 write 한 번으로 낸다(AL design 결정 2). 예전에는
/// 머리 · 칸 하나 · ` | ` · 줄바꿈을 따로 찍어 화면 한 줄이 글자 수만큼의 write였고,
/// 그 사이에 init의 줄이 끼어 게이트가 읽는 줄을 잘랐다(TC-M3 루트 게이트).
/// `buf`는 `screenLineMax`만큼이라 이 줄은 잘리지 않는다.
fn dumpScreen(cells: []const vt.CellGlyph, buf: []u8) void {
    var line = logline.Line.init(buf);
    line.print("terminal: screen> ", .{});
    var last_row: u16 = 0;
    for (cells) |cell| {
        if (cell.row != last_row) {
            line.print(" | ", .{});
```

E2 — `old_string`(기준 파일 692줄부터):

```zig
        logline.print("{s}", .{utf8[0..len]});
    }
    logline.print("\n", .{});
```

`new_string`:

```zig
        line.print("{s}", .{utf8[0..len]});
    }
    line.print("\n", .{});
    line.flush();
}

/// `cols` × `rows` 격자의 화면 dump가 가질 수 있는 가장 긴 길이(바이트). 칸 하나의
/// 글자는 UTF-8로 많아야 4바이트이고(`CellGlyph.codepoint`는 u21), 줄이 바뀔
/// 때마다 ` | ` 3바이트, 앞에 머리, 끝에 줄바꿈이다. QEMU의 155×47이면 29,345다.
fn screenLineMax(cols: u16, rows: u16) usize {
    return @as(usize, rows) * (@as(usize, cols) * 4 + 3) + "terminal: screen> ".len + 1;
```

E3 — `old_string`(기준 파일 2706줄부터):

```zig
    defer allocator.free(cell_buf);
```

`new_string`:

```zig
    defer allocator.free(cell_buf);
    // 화면 dump 한 줄의 버퍼(AL-M0). `cell_buf`처럼 격자 전체 크기라 어느 패널에도
    // 충분하고, 격자가 큰 실기계에서는 그만큼 커진다.
    const screen_line_buf = try allocator.alloc(u8, screenLineMax(cols, rows));
    defer allocator.free(screen_line_buf);
```

E4 — `old_string`(기준 파일 3457줄부터):

```zig
        dumpScreen(cells);
```

`new_string`:

```zig
        dumpScreen(cells, screen_line_buf);
```

```bash
cd /Users/dp/Repository/tars-linux && cmp terminal/src/main.zig /tmp/run/al0/new/terminal/src/main.zig && echo same
```

## Task 4: 게이트 — 회차 디렉터리 · 셈 · 진입 검사 셋 · 로그를 남기는 체인

### 4-1. `gate_lib.sh` — 편집 하나

E1 — `old_string`(기준 파일 225줄부터):

```bash
    slash t m p slash l b minus a p p dot t x t ret
}
```

`new_string`:

```bash
    slash t m p slash l b minus a p p dot t x t ret
}

# AL-M0: 한 회차의 로그 디렉터리에서 남의 줄이 끼어든 줄을 찾는다(AL design 결정 4).
#
# terminal과 init은 같은 콘솔에 쓰고, 커널의 tty는 write 한 번 안에는 아무것도
# 못 끼어들게 하지만 write와 write 사이에는 누구나 끼어든다. 그래서 한 줄을 write
# 여럿으로 내던 시절에는 한쪽의 줄 가운데에 다른 쪽의 줄이 들어갔다(TC-M3 루트
# 게이트 여섯 디렉터리에서 회차마다 2 ~ 8줄). AL은 두 쪽 다 한 줄을 write 한 번으로
# 내게 바꾸고, 이 함수가 그것이 참인지를 회차마다 센다. 찾은 줄을 앞에 갈래를
# 붙여 찍는다.
#
#   A <파일>: <줄>   terminal의 줄 가운데에 init의 줄이 들어 있다
#   B <파일>: <줄>   init의 줄 가운데에 terminal의 줄이 들어 있다
#
# B에서 빼는 것은 init이 제 글로 `terminal: `을 쓰는 단 하나의 줄(`reload terminal:
# pid …`, init/src/main.zig)이다. 그 fmt를 글자 그대로 맞춰 빼므로, 그 줄 뒤에
# terminal의 조각이 붙은 줄은 여전히 B다. init의 fmt 가운데 `terminal: `을 담는 것이
# 늘면 B가 거짓으로 빨갛다 — 그때 여기에 하나 더한다.
#
# 커널 printk(`[  7.35] …`)와 콘솔 셸의 프롬프트가 자르는 것은 세지 않는다. 앞의
# 것은 tty 잠금 밖에서 쓰이고 뒤의 것은 남의 프로세스라 AL이 고칠 수 없다(AL design
# 비목표 1 · 2).
#
# 줄 머리가 `terminal: ` · `tars-init: `인 파일만 perl에 넘긴다. 회차 디렉터리에는
# 디스크 이미지 · WAV도 있고, 줄바꿈이 드문 큰 파일을 perl이 줄로 읽으면 한 줄이
# 수십 MB가 된다.
cut_log_lines() {
  local dir="$1" files
  files="$(grep -rlaE '^(terminal|tars-init): ' "$dir")" || return 0
  local IFS=$'\n'
  # shellcheck disable=SC2086
  perl -ne '
    if (/^terminal: .*tars-init: /) { print "A $ARGV: $_" }
    elsif (/^tars-init: .*terminal: / &&
           !/^tars-init: reload terminal: pid \d+, shell \S+ keyboard=\S+ hangul=\S+ latin=\S+ toggles=\S+ clipboard=\S+\r?\n?\z/) {
      print "B $ARGV: $_";
    }
  ' $files
}
```

### 4-2. `check.sh` — 편집 셋

E1은 `RUNS` 뒤의 회차 디렉터리 · `count_cut_lines`와 `run_chain`이다. 체인이 빨개도 셈은 돈다 — 빨간 까닭이 이 자름일 수 있다. E2는 진입 검사 셋
(`require_screen_dump_joins` 뒤), E3은 마지막 PASS 줄이다.

E1 — `old_string`(기준 파일 147줄부터):

```bash
run_chain() {
  local name="$1"
  local script="$2"

  for i in $(seq 1 "$RUNS"); do
    echo "=== ${name} run ${i}/${RUNS} ==="
    if ! "$script"; then
```

`new_string`:

```bash
# AL-M0: 회차마다 로그 디렉터리를 하나씩 준다(AL design 결정 4). 체인의 `mktemp`이 전부
# `TMPDIR`을 따르므로, 회차의 시리얼 로그가 `<GATE_LOGS>/<체인>-<회차>/` 아래에 모인다.
# 체인은 로그를 지우지 않는다 — 로그의 주인은 이 디렉터리다. 지우지도 않는다. 컨테이너는
# `--rm`이고, `-e TMPDIR=`로 bind-mount해 두면 체인별로 나뉜 채 호스트에 남는다.
GATE_LOGS="$(mktemp -d "${TMPDIR:-/tmp}/tars-gate.XXXXXX")"

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
    return 1
  fi
  return 0
}

run_chain() {
  local name="$1"
  local script="$2"
  local dir ok

  for i in $(seq 1 "$RUNS"); do
    echo "=== ${name} run ${i}/${RUNS} ==="
    dir="${GATE_LOGS}/${name}-${i}"
    mkdir -p "$dir"
    ok=1
    TMPDIR="$dir" "$script" || ok=0
    count_cut_lines "$dir" "${name} run ${i}/${RUNS}" || ok=0
    if [ "$ok" -ne 1 ]; then
```

E2 — `old_string`(기준 파일 422줄부터):

```bash
# 체인이 source하는 공용 파일과 이 파일 자신도 같은 규칙을 받는다. 자기를
```

`new_string`:

```bash
# AL-M0. 회차마다 끼어든 줄을 세는 cut_log_lines가 실제로 잡는가. QEMU 없이 TC-M3 루트
# 게이트 로그의 실제 줄 넷으로 본다 — init의 줄이 자른 `pointer>` 줄(A), terminal의 줄이
# 붙은 init의 줄(B), init이 제 글로 `terminal: `을 쓰는 온전한 줄(셈 밖), 화면 글자에
# `widget: function`이 든 온전한 `screen>` 줄(셈 밖). 못 잡으면 게이트가 회차마다
# "0"이라고 거짓말을 한다.
require_cut_lines_found() {
  local dir got want
  dir="$(mktemp -d)"
  printf 'terminal: pointer> at x=1279 y=799 buttons=0 wheel=0 shown=1 ink=tars-init: audio: no sound card within 5000ms, the mixer is left alone\n' > "$dir/a"
  printf 'tars-init: login shell /usr/bin/bash, ssh env in /etc/ssh/sshd_config.d/tars-env.confterminal: screen> root@(none) ~# \r\n' > "$dir/b"
  printf 'tars-init: reload terminal: pid 39, shell /usr/bin/fish keyboard=pc hangul=shin_pcs latin=qwerty toggles=hangul_key,shift_space,capslock_tap,lctrl_tap,esc_latin clipboard=pane\n' > "$dir/legit"
  printf 'terminal: screen> (none)# whence -w fzf-history-widget | fzf-history-widget: function | (none)# \r\n' > "$dir/clean"
  got="$(LOG=/dev/null bash -c 'source ./gate_lib.sh; cut_log_lines "$1"' _ "$dir" | cut -d: -f1 | sort | tr '\n' ' ')"
  want="A ${dir}/a B ${dir}/b "
  rm -rf "$dir"
  if [ "$got" != "$want" ]; then
    echo "check FAIL: gate_lib.sh cut_log_lines does not find the cut lines:" >&2
    echo "  want [${want}]" >&2
    echo "  got  [${got}]" >&2
    return 1
  fi
  return 0
}
require_cut_lines_found || entry_failed=1

# AL-M0. 시리얼에 쓰는 helper `logline.zig`는 terminal과 init에 바이트까지 같은 사본
# 둘이다(AL design 결정 1). 공용 모듈로 두지 않은 대신 여기서 어긋남을 막는다.
require_same_logline() {
  cmp terminal/src/logline.zig init/src/logline.zig >/dev/null && return 0
  echo "check FAIL: terminal/src/logline.zig and init/src/logline.zig differ:" >&2
  diff terminal/src/logline.zig init/src/logline.zig >&2
  echo "  they are one file in two places; copy the edited one over the other (AL design 1)." >&2
  return 1
}
require_same_logline || entry_failed=1

# AL-M0. 게스트에서 도는 파일은 `std.debug.print`를 안 쓴다(AL design 결정 3). 그 함수는
# 한 줄을 64바이트씩 write 여럿으로 내고, 그 사이에 남의 줄이 끼어든다 — 쓸 것은
# `logline.print`다. `*_test.zig`는 호스트에서만 돌아 대상이 아니다. 주석 줄도 뺀다
# (`logline.zig`가 그 이름을 설명에 쓴다). 별명(`const print = std.debug.print;`)도 이
# 패턴에 걸린다. AL-M1이 init/src를 더한다.
LOGLINE_DIRS=(terminal/src)
require_no_debug_print() {
  local hits
  hits="$(find "${LOGLINE_DIRS[@]}" -name '*.zig' ! -name '*_test.zig' -print0 \
    | xargs -0 grep -HnE 'std\.debug\.print' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//')" \
    || return 0
  echo "check FAIL: guest code writes serial lines with std.debug.print:" >&2
  echo "$hits" >&2
  echo "  use logline.print; std.debug.print splits a line into 64-byte writes (AL design 3)." >&2
  return 1
}
require_no_debug_print || entry_failed=1

# 체인이 source하는 공용 파일과 이 파일 자신도 같은 규칙을 받는다. 자기를
```

E3 — `old_string`(기준 파일 451줄부터):

```bash
echo "TARS check PASS: all chains ${RUNS}/${RUNS} consecutive runs succeeded"
```

`new_string`:

```bash
echo "TARS check PASS: all chains ${RUNS}/${RUNS} consecutive runs succeeded (logs in ${GATE_LOGS})"
```

### 4-3. 체인 여덟 — 로그를 안 지운다

`audio` · `dictation` · `firewall` · `nic` · `service` · `wifi` · `pointer` · `install` 순이다. cleanup의 `rm`에서 로그만 빼고(`$WORK` · `$SEED`는 그대로
지운다), 중간의 `rm -f "$LOG"`를 지우고, `audio`는 부팅마다 `mktemp`, `install`은 로그를 `$WORK` 밖의 `mktemp -t`로 옮긴다. `firewall` · `nic`의
cleanup은 `rm`이 통째로 빠져 주석 한 줄이 그 자리에 선다 — 함수 몸에 `if` 블록이 남으므로 bash 문법은 그대로다.

`audio/check.sh`:

E1 — `old_string`(기준 파일 85줄부터):

```bash
  rm -rf "$LOG" "$WORK"
```

`new_string`:

```bash
  # 시리얼 로그는 안 지운다 — 루트 check.sh가 회차 디렉터리에서 끼어든 줄을 센다(AL-M0).
  rm -rf "$WORK"
```

E2 — `old_string`(기준 파일 379줄부터):

```bash
  : > "$LOG"
```

`new_string`:

```bash
  # 부팅마다 새 로그다(AL-M0). 예전에는 같은 파일을 비우고 다시 써서 루트 check.sh가
  # 회차 디렉터리에서 셀 때 마지막 부팅 하나만 남았다.
  LOG="$(mktemp)"
```

`dictation/check.sh`:

E1 — `old_string`(기준 파일 98줄부터):

```bash
  rm -rf "$LOG" "$WORK"
```

`new_string`:

```bash
  # 시리얼 로그는 안 지운다 — 루트 check.sh가 회차 디렉터리에서 끼어든 줄을 센다(AL-M0).
  rm -rf "$WORK"
```

E2 — `old_string`(기준 파일 537줄부터):

```bash
STUBLOG_B="$WORK/stub_b.log"
rm -f "$LOG"
```

`new_string`:

```bash
STUBLOG_B="$WORK/stub_b.log"
```

`firewall/check.sh`:

E1 — `old_string`(기준 파일 70줄부터):

```bash
  rm -f "$LOG_A" "$LOG_B"
```

`new_string`:

```bash
  # 시리얼 로그는 안 지운다 — 루트 check.sh가 회차 디렉터리에서 끼어든 줄을 센다(AL-M0).
```

`nic/check.sh`:

E1 — `old_string`(기준 파일 69줄부터):

```bash
  rm -f "$LOG_A" "$LOG_B"
```

`new_string`:

```bash
  # 시리얼 로그는 안 지운다 — 루트 check.sh가 회차 디렉터리에서 끼어든 줄을 센다(AL-M0).
```

`service/check.sh`:

E1 — `old_string`(기준 파일 77줄부터):

```bash
  rm -f "$LOG"
```

`new_string`:

```bash
  # 시리얼 로그는 안 지운다 — 루트 check.sh가 회차 디렉터리에서 끼어든 줄을 센다(AL-M0).
```

E2 — `old_string`(기준 파일 347줄부터):

```bash
echo "=== boot B: sshd linked, firewall=on without ssh.nft ==="
rm -f "$LOG"   # 부팅 A의 로그. cleanup은 마지막 LOG 하나만 지운다
```

`new_string`:

```bash
echo "=== boot B: sshd linked, firewall=on without ssh.nft ==="
```

E3 — `old_string`(기준 파일 632줄부터):

```bash
stop_ssh
rm -f "$LOG"
rm -f "$B_LOG"
```

`new_string`:

```bash
stop_ssh
```

`wifi/check.sh`:

E1 — `old_string`(기준 파일 61줄부터):

```bash
  rm -rf "$LOG_A" "$LOG_B" "$LOG_C" "$SEED"
```

`new_string`:

```bash
  # 시리얼 로그는 안 지운다 — 루트 check.sh가 회차 디렉터리에서 끼어든 줄을 센다(AL-M0).
  rm -rf "$SEED"
```

`pointer/check.sh`:

E1 — `old_string`(기준 파일 1651줄부터):

```bash
grep -a 'terminal: pointer>' "$LOG" | tr -d '\r'
rm -f "$LOG_A" "$LOG"
```

`new_string`:

```bash
grep -a 'terminal: pointer>' "$LOG" | tr -d '\r'
```

`install/check.sh`:

E1 — `old_string`(기준 파일 94줄부터):

```bash
  local name="$1"; shift
  LOG="${WORK}/boot-${name}.log"
```

`new_string`:

```bash
  local name="$1"; shift
  # 로그는 `$WORK` 밖에 둔다. cleanup이 `$WORK`(디스크 이미지)를 통째로 지우는데 시리얼
  # 로그는 루트 check.sh가 회차 디렉터리에서 센다(AL-M0). `mktemp`은 `TMPDIR`을 따른다.
  LOG="$(mktemp -t "install-boot-${name}.XXXXXX")"
```

E2 — `old_string`(기준 파일 463줄부터):

```bash
  local name="$1" cmdline="$2"
  LOG="${WORK}/boot-${name}.log"
```

`new_string`:

```bash
  local name="$1" cmdline="$2"
  LOG="$(mktemp -t "install-boot-${name}.XXXXXX")"   # boot_guest와 같은 까닭(AL-M0)
```

### 4-4. 확인 — cmp · 문법 · 진입 검사

```bash
cd /Users/dp/Repository/tars-linux && for f in gate_lib.sh check.sh audio/check.sh dictation/check.sh firewall/check.sh nic/check.sh \
  service/check.sh wifi/check.sh pointer/check.sh install/check.sh; do cmp "$f" "/tmp/run/al0/new/$f" || exit 1; bash -n "$f" || exit 1; done && echo same
```

진입 검사만 돌리는 도구 둘이 `/tmp/run/al0/tools/`에 있다. 루트 `check.sh`를 `clean` 앞에서 자르거나(`entry.sh`), 체인 목록을 하나로 바꾸고 `clean`을
건너뛴다(`one.sh`). 둘 다 저장소 루트에 임시 파일 하나를 만들고 끝에 지운다.

`entry.sh`:

```bash
#!/bin/bash
# 루트 check.sh의 진입 검사만 돈다(clean 앞에서 자른다).
cd /workspace
sed '/^clean$/,$d' check.sh > .entry.sh
bash .entry.sh; rc=$?
rm -f .entry.sh
echo "entry rc=$rc"
exit $rc
```

`one.sh`:

```bash
#!/bin/bash
# 루트 check.sh를 체인 하나로 돈다(run_chain · 회차 디렉터리 · 셈은 그대로, clean은 건너뛴다).
# 사용: one.sh '<이름>:<스크립트>' [회차 수]
cd /workspace
runs=${2:-2}
sed -e 's/^clean$/: clean skipped in the AL-M0 copy/' \
    -e "s/^RUNS=2\$/RUNS=${runs}/" \
    -e "/^CHAINS=(/,/^)\$/c\\CHAINS=(\"$1\")" check.sh > .one.sh
bash .one.sh; rc=$?
rm -f .one.sh
echo "one rc=$rc"
exit $rc
```

```bash
cd /Users/dp/Repository/tars-linux && sync && sleep 1 && \
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -v /tmp/run/al0/tools:/tools:ro -w /workspace tars-devcontainer bash /tools/entry.sh; rc=$?
rmdir /tmp/run/docker.lock
```

`entry rc=0`이고 그 앞에 아무 줄도 없어야 한다. 사본에서 1초가 안 걸렸다.

## Task 5: 체인 — 화면 dump를 가장 많이 보는 다섯과 audio

루트 `check.sh`의 `run_chain`을 그대로 쓰는 `one.sh`로 체인마다 한 회차씩 돈다. 그래서 셈 줄이 회차마다 찍히고, A가 0이 아니면 그 자리에서 FAIL이다.
첫 체인이 terminal · init · initrd를 짓는다. 모두 합쳐 사본에서 약 12분이었다(이 명령 그대로 돌렸다 — 여섯 다 `A=0` · `one rc=0`, `cut marks: 0`, audio 로그 넷).

```bash
cd /Users/dp/Repository/tars-linux && mkdir -p /tmp/run/al0/impl && \
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -v /tmp/run/al0/tools:/tools:ro -v /tmp/run/al0/impl:/impl -w /workspace tars-devcontainer bash -c '
  for c in TF-M4:./terminal/check.sh TR-M2:./render/check.sh PD-M4:./pointer/check.sh CB-M0:./pane/check.sh CP-M2:./config/check.sh AU-M3:./audio/check.sh; do
    TMPDIR=/impl bash /tools/one.sh "$c" 1 > "/impl/${c%%:*}.out" 2>&1
    grep -aE "cut log lines|one rc=" "/impl/${c%%:*}.out"
  done
  echo "cut marks: $(grep -raE "^(terminal|kms|font): .* \[cut\]\r?$" /impl/tars-gate.* | wc -l)"'; rc=$?
rmdir /tmp/run/docker.lock
```

체인 여섯이 다 `A=0`과 `one rc=0`이어야 한다. B는 0이 아닐 수 있다(init의 줄 — AL-M1의 몫). `cut marks: 0`이어야 한다(Opus 조건 4). audio의 회차
디렉터리에는 로그가 넷이어야 한다.

```bash
cd /tmp/run/al0/impl && grep -rlaE '^(terminal|tars-init): ' tars-gate.*/AU-M3-1 | wc -l
```

## Task 6: mutation

판 여덟 가운데 결정적인 일곱(e1 ~ e4 · t1 · t2 · m2)을 다시 돈다. m1은 확정 8대로 운이라 다시 안 돈다. mutation 파일은 `/tmp/run/al0/mut/<판>/`에 있고,
`/tmp/run/al0/run_mut.sh`가 그 파일을 저장소 경로 위에 읽기 전용으로 덮어 한 판을 돈다. 판이 끝나면 `terminal/zig-out`에 망가진 바이너리가 남으므로
마지막 판(`clean`)이 덮지 않고 다시 짓는다.

`run_mut.sh`:

```bash
#!/bin/bash
# AL-M0 plan Task 6의 mutation 한 판. 사용: [REPO=…] [OUT=…] run_mut.sh <판> '<명령>' <mut 파일:저장소 경로>...
# mut/<판>/<mut 파일>을 저장소 경로 위에 읽기 전용으로 덮고 <명령>을 저장소 루트에서 돌린다.
# 저장소는 $REPO(없으면 plan을 쓴 사본), 출력은 $OUT/<판>.log(없으면 mut/<판>.log). 덮은 Zig 파일은 내용이 다르므로 zig가 다시 짓는다 — 판이 끝나면
# terminal/zig-out에 망가진 바이너리가 남으니 마지막에 덮지 않은 빌드를 한 번 더 돈다.
name=$1; cmd=$2; shift 2
mut=/tmp/run/al0/mut; repo=${REPO:-/tmp/run/al0/repo}; out=${OUT:-$mut}
mounts=""
for m in "$@"; do mounts="$mounts -v $mut/$name/${m%%:*}:/workspace/${m#*:}:ro"; done
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
s=$(date +%s)
docker run --rm -v "$repo":/workspace -v /tmp/run/al0/tools:/tools:ro $mounts -w /workspace tars-devcontainer bash -c "$cmd" > "$out/$name.log" 2>&1
echo "exit=$?" >> "$out/$name.log"
rmdir /tmp/run/docker.lock
echo "== $name $(( $(date +%s) - s ))s"
grep -aE 'FAIL|exit=|cut log lines|rc=' "$out/$name.log"
```

```bash
cd /tmp/run/al0 && export REPO=/Users/dp/Repository/tars-linux OUT=/tmp/run/al0/impl && E='bash /tools/entry.sh' && \
./run_mut.sh e1 "$E" main.zig:terminal/src/main.zig && \
./run_mut.sh e2 "$E" logline.zig:init/src/logline.zig && \
./run_mut.sh e3 "$E" gate_lib.sh:gate_lib.sh && \
./run_mut.sh e4 "$E" gate_lib.sh:gate_lib.sh && \
./run_mut.sh t1 'cd terminal && zig build test' logline.zig:terminal/src/logline.zig && \
./run_mut.sh t2 'cd terminal && zig build test' logline.zig:terminal/src/logline.zig && \
./run_mut.sh m2 'bash /tools/one.sh "TF-M4:./terminal/check.sh" 1' main.zig:terminal/src/main.zig && \
./run_mut.sh clean 'bash /tools/entry.sh && bash /tools/one.sh "TF-M4:./terminal/check.sh" 1'
```

구현자는 `REPO=/Users/dp/Repository/tars-linux`와 `OUT=/tmp/run/al0/impl`을 앞에 두고 돈다(위 명령의 첫 줄에 이미 있다). 없으면 plan을 쓴 사본과
그 로그를 덮어 쓴다.

e1 ~ e4가 `TARS check FAIL: the entry checks …`, t1 · t2가 `FAIL: …`와 `exit=1`, m2가 `TF-M4 run 1/1: cut log lines A=2` · `TF-M4 FAIL`, `clean`이
`entry rc=0` · `A=0` · `one rc=0`이어야 한다(확정 8의 표. 이 명령 그대로 사본에서 `OUT=/tmp/run/al0/dry`로 돌려 같았다).

## Task 7: lead가 하는 것

1. 루트 게이트 2회(약 60분). `docker run -e TMPDIR=/workspace/out/al0 …`처럼 회차 디렉터리를 호스트로 꺼내 두면 체인별로 나뉜 로그가 남는다.
2. 회차마다의 셈 줄을 모은다 — A는 전부 0이어야 하고, B의 수와 줄을 "실측한 것"에 적는다(AL-M1의 기준선이 된다).
3. 실측 절을 채우고, 구현자의 diff를 읽고, commit한다.

## design과 다르게 적은 것

1. `init/src/logline.zig`를 AL-M1이 아니라 AL-M0에 둔다 — lead가 M0의 진입 검사에 `cmp`를 넣으라 했고, 그러려면 두 파일이 다 있어야 한다. init은
   M1까지 그 파일을 안 쓴다.
2. 로그를 지우던 자리가 열하나가 아니라 열넷이다(확정 4). 그 가운데 audio는 "지우던" 것이 아니라 "같은 파일에 덮어 쓰던" 것이다.
3. design 검증 절의 "변이: `dumpScreen`을 칸마다 `flush`로 되돌린 사본에서 셈이 빨개지는가"는 네 회차 모두 초록이었다(확정 8의 m1). 셈이 회차를
   빨갛게 하는 것은 결정적인 m2로, 진짜 끼어듦을 잡는 것은 실제 로그로 보였다.

## 이 milestone에서 안 하는 것

- init의 `std.debug.print` 153곳과 `config.zig`의 `log` 싱크, 셈의 B를 FAIL로 올리는 것, `joined_screen_dump`의 꼬리 떼기를 지우는 것 — AL-M1.
- 커널 printk와 콘솔 셸 프롬프트가 자르는 것(design 비목표 1 · 2).

## AL-M0이 실측한 것

(구현과 루트 게이트 뒤에 lead가 채운다.)
