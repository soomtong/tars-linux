# VD-M1 — 오른쪽 Cmd 두 번이 `tars-dictate`를 띄우고, 상태 줄에 `REC`가 뜨고, 받은 글자가 그 패널에 들어간다

Date: 2026-10-06
Design: `docs/specs/2026-10-06-tars-voice-dictation-design.md`
Status: 끝났다(2026-10-06). plan을 쓰며 사본에서 돈 값은 "착수 전에 확정한 것"에, 구현과 루트 게이트의 값은 맨 아래 "VD-M1이 실측한 것"에 있다. 다음은 VD-M2(`-vd-m2.md`).

## 누가 무엇을 하나

design 결정 12. Task 0~6은 구현 서브에이전트가 main 작업 트리에서 직접 편집하고 돌린다. Task 7(루트 게이트 2회 · 실측 절 ·
design 덧붙임 · commit)은 lead(Fable)가 한다. 구현자는 commit하지 않고, 끝에 `git diff --stat` · `git diff | rg '^-'` · 각 Task의
명령 출력을 그대로 보고한다. 이 plan의 "확정한 것" 절과 "실측한 것" 절은 구현자가 고치지 않는다.

권하는 모델은 Sonnet이다. design이 M1에 남긴 "정할 것 여섯"(판정의 자리 · 자식 · 상태 줄 · 대상 패널 · Esc의 순서 · 게이트)은 이 plan이
사본에서 정했고(확정 1 ~ 6), terminal의 Zig 코드는 전부 사본에서 컴파일 · 호스트 검사 · 체인 · mutation을 지난 글자다. 구현자에게 남는
Zig 판단이 없다 — 새 파일 둘은 사본을 복사하고, 편집 64개는 plan 본문에서 기계로 뽑아 넣고, 빌드 · 체인 · regression ·
mutation을 정해진 순서로 돌린다. plan의 기대와 다른 값이 나오면 고치지 말고 보고한다. Opus로 올릴 이유는 하나다 — 루트 게이트에서 이
plan이 못 돌린 체인이 빨개지거나, 부팅 B가 사본과 다른 자리에서 흔들려 원인을 찾아야 할 때. 그때는 lead가 정한다.

이 plan의 코드는 저장소 밖 사본(`/tmp/run/vd1/repo/`, HEAD `11039e6`)에 먼저 넣어 빌드 · 호스트 검사 · 체인 · regression · mutation까지
돌렸고, 아래의 새 파일 본문과 `old_string` · `new_string`은 그 사본에서 기계로 뽑은 것이다(`/tmp/run/vd1/render_plan.py`). 기준은
HEAD의 파일(`/tmp/run/vd1/base/`)이고 편집 뒤의 파일은 `/tmp/run/vd1/new/`다. 구현자는 코드를 새로 짓지 않는다. 새 파일은 `new/`에서
`cp -p`하고, 편집은 plan 본문에서 블록을 기계로 뽑아 넣는다(Task 0의 `apply_plan.py` — EL · CB · AU · VD-M0의 구현자가 같은 방식으로
했다). 각 Task 끝에서 `new/`와 `cmp`해 같은지 본다. 다르면 편집이 빗나간 것이니 plan의 글자에 맞춰 고친다. plan의 글자와 `new/`가 서로
다르다고 보이면 고치지 말고 그 자리를 보고한다.

| 파일 | 무엇을 | 줄 |
|---|---|---|
| `terminal/src/dictation.zig` | 새 파일 — 받아쓰기의 순수한 층: 더블 탭 판정기 · 단계 · 종료 코드 · 비밀번호 판정 · 거르기 | +268 |
| `terminal/src/dictation_test.zig` | 새 파일 — 그 호스트 검사 열여섯(Voxio `DoubleTapDetectorTests` · `TriggerEventRouterTests`를 옮겼다) | +285 |
| `terminal/build.zig` | 편집 둘 — `dictation_test` 등록 | +15 |
| `terminal/src/status.zig` | 편집 여섯 — 꼬리 맨 끝의 받아쓰기 칸, `MAX_LEN` 46 → 56 | +49 −3 |
| `terminal/src/status_test.zig` | 편집 열하나 — 인자 하나와 검사 17 ~ 19 | +78 −8 |
| `terminal/src/input.zig` | 편집 열넷 — `Action.dictate` · 트리거 · Esc · `SYN_DROPPED` | +94 |
| `terminal/src/input_test.zig` | 편집 일곱 — 헬퍼 다섯의 새 갈래와 검사 75 ~ 83 | +250 |
| `terminal/src/main.zig` | 편집 열아홉 — 받아쓰기 절(자식 · 파이프 · 삽입), poll의 두 칸, 키 배선, 상태 줄 | +395 −6 |
| `dictation/check.sh` | 편집 다섯 — 호스트 검사 단계와 부팅 B(검사 14 ~ 23) | +366 −2 |

합해서 9 files, +1800 −19(새 파일 둘 553줄). 커널(`kernel/.config`) · `init/` · `kernel/dictation/tars-dictate` · `devcontainer/Dockerfile` · `kernel/make_initrd.sh` ·
루트 `check.sh`는 한 줄도 안 바뀐다 — 이미지를 다시 굽지 않고, 새 체인도 없다(루트 게이트는 M0와 같은 스물한 체인이다).
`.gitignore`도 그대로다 — 부팅 B의 디스크 `out/dictation-b.img`는 `out/` 아래이고 루트 `check.sh`의 `clean()`이 지운다.

design의 `Status:` · `CLAUDE.md` · `MEMORY.md` · `docs/decisions/` · `docs/guides/` · `HANDOFF.md`는 구현자가 안 고친다.

모든 명령은 저장소 루트에서 친다. 서브에이전트의 Bash는 호출마다 작업 디렉터리가 돌아가므로 명령 앞에
`cd /Users/dp/Repository/tars-linux &&`를 붙인다. 빌드 · 체인은 언제나 컨테이너에서 한다(호스트의 zig는 0.17, 컨테이너는 0.16.0).
구현자의 측정용 파일은 `/tmp/run/vd1/impl/` 아래에 둔다. `/tmp/run/vd1/` 바로 아래는 이 plan을 쓰며 만든 것이고 대조에 쓴다. 지우지 않는다.

Docker VM의 메모리가 4GB다. 컨테이너 둘을 겹쳐 돌리면 `zig build`가 `Killed`로 죽거나 VM이 재시작된다(lessons PD-6).
컨테이너는 언제나 하나씩 돌린다. 다른 에이전트가 같은 시간에 돌 수 있으므로 모든 `docker run`을 아래로 감싼다. 명령이 실패해도
lock은 꼭 푼다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run … ; rc=$?
rmdir /tmp/run/docker.lock
```

20분 넘게 기다리면 `docker ps`를 보고, 컨테이너가 하나도 없으면 lock이 낡은 것이니 `rmdir`하고 진행한다.

## 이 milestone이 끝나면

- 오른쪽 Cmd(PC 자판 `keyboard=pc`는 오른쪽 Alt)를 300ms 안에 두 번 누르면 terminal이 `/usr/bin/tars-dictate`를 띄우고, 상태 줄 맨 끝에
  붉은 `REC`가 뜬다. 다시 두 번 누르면 녹음이 끝나고(`WAIT`) 받아 적은 글자가 두 번을 처음 누른 그 패널의 커서 자리에 들어간다 —
  bracketed paste라 셸은 Enter 전에는 안 돈다. 클립보드는 안 만진다.
- 녹음 중의 Esc는 취소다. 그 Esc는 셸 · vim에 안 간다. 전사 중의 Esc는 평소대로 프로그램에 간다.
- `max_seconds`에서 스스로 멈춘 녹음도 같은 길로 글자를 넣고, 그 뒤의 두 번은 새 시작이다.
- 비밀번호 프롬프트(`sudo` · `ssh` · `read -s` — 줄 단위로 읽으며 안 보여 주는 것)에서는 마이크를 안 열고, 말하는 사이에 그런 프롬프트가
  뜨면 글자를 안 넣는다. 둘 다 상태 줄이 `PASSWORD`라고 말한다. 글자는 `/config/dictation.jsonl`에 남아 있다.
- 실패는 상태 줄이 한 낱말로 말하고(`NO KEY` · `NO MIC` · `FAILED` · `NO PANE`) 다음 키에 사라진다. 무음 · 취소는 조용히 끝난다.
- 정리 단계(LLM)는 아직 없다(VD-M2).

로그 줄(정본 — terminal이 시리얼에 찍는다. `dictation/check.sh`가 이 글자를 본다). 받아 적은 글자는 어느 줄에도 없다.

```
terminal: dictate> start pid=231 ws=1 leaf=0
terminal: dictate> phase recording
terminal: dictate> stop pid=231
terminal: dictate> phase transcribing                    자식이 상한에서 스스로 멈췄을 때(둘째 더블 탭이면 stop 줄이 이 일을 한다)
terminal: dictate> cancel pid=231                        녹음 중의 Esc
terminal: dictate> ignored phase=transcribing            starting · transcribing · cancelling의 더블 탭
terminal: dictate> exit code=0                           exit signal=N(시그널로 죽었다)
terminal: dictate> insert len=28 bracketed=1 ws=1 leaf=0
terminal: dictate> refused password at=start ws=1 leaf=0
terminal: dictate> refused password at=insert ws=1 leaf=0
terminal: dictate> no pane shell=233
terminal: dictate> notice password                       no_mic · no_key · failed · password · no_pane
terminal: dictate> nothing left to insert                거른 뒤 빈 글자
terminal: dictate> text over 65536 bytes, not inserted
terminal: dictate> spawn failed at fork error=AGAIN
terminal: status> dict ink=118                           상태 줄이 바뀔 때마다 `copy ink=` 줄 뒤에
```

자식의 표준 에러는 받은 그대로 다시 찍는다 — `tars-dictate: recording; Ctrl+C stops (at most 300s)` 같은 줄이고 정본은 M0 plan이다.
그 중 둘(`tars-dictate: recording; ` · `tars-dictate: recording stopped `)은 이제 terminal과의 계약이다(`dictation.phaseAfter`).

상태 줄의 꼬리(`terminal: status> text=`).

```
EN  신세벌 PCS  쿼티  CAPS  REC
EN  신세벌 PCS  쿼티  CAPS  W2  COPY  WAIT
EN  신세벌 PCS  쿼티  CAPS  PASSWORD
```

## 착수 전에 확정한 것

2026-10-06에 이 plan을 쓰며 Voxio(`/Users/dp/Repository/Voxio`, 1.0.1)의 `Sources/VoxioCore/DoubleTapDetector.swift` ·
`TriggerEventRouter.swift` · `DictationPipeline.swift` · `OverlayPresentation.swift`와 그 검사, `docs/ARCHITECTURE.md` D6 · D8 · D11a · 3절,
그리고 저장소의 코드와 vendored ghostty(`ghostty-src/src/termio/Exec.zig`)를 읽어 정했고, 저장소 사본(`/tmp/run/vd1/repo/`, HEAD
`11039e6` — VD-M0 commit)으로 쟀다. 측정 파일은 `/tmp/run/vd1/meas/`(체인 · 시리얼 · regression 로그)와 `/tmp/run/vd1/mut/`(mutation)에
있다. 저장소의 작업 트리는 이 plan 말고는 한 글자도 안 바뀌었다.

1. 트리거 판정과 그 자리(design 결정 10, "정할 것" 1 · 5).

   판정기는 순수 모듈 `dictation.zig`의 `DoubleTap`이다. Voxio `DoubleTapDetector`의 toggle 모드를 옮겼고 규칙은 그대로다 — 누름 → 뗌 →
   누름이 첫 누름부터 300ms 안(닫힌 구간)이면 둘째 누름에서 발동한다. 창을 넘긴 둘째 누름은 새 판정의 첫 누름이다. 시각은 `ev.time`
   (커널이 찍은 마이크로초)이고 거꾸로 가면 창 밖이다.

   Voxio와 갈린 자리가 하나다. 판정기가 "녹음 중"을 안 든다. Voxio는 판정기가 `recording`을 들고 키 없이 끝나는 길마다 `syncToIdle`을
   불러야 했다(D6 함정 3, V17). 여기서는 판정기가 "두 번 눌렸다"만 말하고, 그것이 시작인지 끝인지는 `dictation.onTap`이 자식의 단계로
   정한다. 자식이 스스로 끝나면 단계가 null로 돌아가므로 맞출 것이 남지 않는다.

   | Voxio의 함정(design 결정 10의 표) | 코드 | 검사 |
   |---|---|---|
   | 1. 같은 누름이 다시 온다 | 트리거 갈래가 `value == 1`만 넣는다. 자동 반복(2)은 안 넣는다 | `input_test` 76 |
   | 2. 놓친 뗌 | `readKeys`가 `EV_SYN`/`SYN_DROPPED`에서 `dictate_tap.reset()` | `input_test` 83 |
   | 3. 키 없이 끝나는 길 | 단계를 자식이 옮기고 자식의 끝이 지운다(확정 2) | `dictation_test` 10 · 체인 검사 21 |

   그 밖의 Voxio 규칙. 다른 키의 누름이 끼면 판정을 버린다(`handleKey`의 0.6번 단계 — 수정키의 누름도, 뗌은 아니다). 다른 수정키가 눌린
   누름은 발동도 시작도 안 한다(Shift · Ctrl · Alt · 왼쪽 Cmd. 왼쪽 Cmd는 Voxio의 `siblingBit`). 대문자 잠금은 수정키가 아니다.

   `handleKey`의 자리. 트리거 키 자신은 0번 단계의 수정키 `switch`(`KEY_RIGHTMETA` 갈래)다 — 맞바꿈 뒤라 `keyboard=pc`는 오른쪽 Alt가
   트리거다. 그래서 normal · copy · find 어느 모드에서도, 한글 조합 중에도 같은 두 번이 받아쓰기다. 수정키라 바이트가 안 나가고, 한글
   조합을 확정시키지도 않는다(넣을 때 확정한다 — 확정 4). Esc는 1.3번 단계다(확정 3).

   `tars.conf`에 켜고 끄는 키를 안 둔다. 오른쪽 Cmd를 두 번 누르는 일이 지금 아무 뜻도 없고(`chord()`의 Meta 표는 다른 키와의 조합뿐이다),
   design 결정 3의 표가 `trigger.key` · `mode` · `doubleTapWindowMs`를 상수로 보냈다. 저장소의 체인 중 `meta_r` · `alt_r`을 보내는 것은
   없다(`rg`).

   QEMU 쪽. `sendkey meta_r`가 게스트에서 `KEY_RIGHTMETA`(126)다. 둘을 잇달아 보내면 둘째 누름이 첫 누름 뒤 159 ~ 163ms에 왔다(확정 9).

2. 자식(design 결정 1 · 6, "정할 것" 2).

   `main.zig`의 받아쓰기 절이 한다. terminal은 이미 libc를 링크한다(`forkpty` · `stb`) — 그래서 `project_zig_c_uapi_rule`의 "시스템 콜만이면
   libc 없이 `std.os.linux`"는 이 바이너리에 해당하지 않고, 같은 파일이 이미 쓰는 `std.c`(`read` · `close` · `bind` · `open`)로 부른다.
   하나만 `std.os.linux`다 — `close_range`(glibc 2.34의 것이지만 `std.c`에 선언이 없다).

   | 무엇 | 값 |
   |---|---|
   | 띄우기 | `pipe2(O_CLOEXEC)` 둘(표준 출력 · 표준 에러) → `fork` → 자식: `setpgid(0,0)` · `dup2` 둘 · 표준 입력 `/dev/null` · `close_range(3, …)` · `execve("/usr/bin/tars-dictate", ["tars-dictate"], environ)` · 실패하면 `_exit(127)`. 부모: `setpgid(pid, pid)` · 쓰는 쪽 둘을 닫는다 |
   | 환경 · 디렉터리 | terminal의 것 그대로(`PATH=/usr/bin:/bin` · `TERM` · `LANG`, 있으면 `GROQ_API_KEY`). `tars-dictate`는 절대 경로만 쓴다 |
   | poll | 두 칸을 PTY 뒤에 둔다(`pty_end`, `pty_end + 1`). 자식이 없으면 -1이고 poll이 건너뛴다 |
   | 표준 출력 | 한 번에 한 read씩 64KB 버퍼에 모은다. 넘치면 넣지 않고 `FAILED`(글자는 기록에 있다) |
   | 표준 에러 | 줄로 나눠 받은 그대로 시리얼에 다시 찍고, `phaseAfter`로 단계를 옮긴다 |
   | 끝 | 두 파이프가 다 EOF면 `waitpid`(막을 수 있지만 짧다 — `pty.close`와 같은 판단) → 종료 코드 → `outcome` |
   | 하나만 | 자식이 있으면 더블 탭은 시작이 아니다(`onTap`) |
   | terminal이 끝날 때 | 자식의 그룹에 SIGTERM(`defer`). 거두는 것은 init이다 |

   단계는 넷이다 — `starting`(띄움) → `recording`(자식이 `tars-dictate: recording; …`을 찍음) → `transcribing`(둘째 더블 탭이 SIGINT를
   보냄, 또는 자식이 `tars-dictate: recording stopped …`을 찍음) · `cancelling`(Esc가 SIGTERM을 보냄). null로는 두 파이프의 EOF만 돌린다.

   `starting`의 더블 탭을 무시하는 이유. M0의 `tars-dictate`는 `arecord`가 돌기 전에 받은 SIGINT를 `stopped=1`로 기억만 하고 그 뒤에
   `arecord`를 상한(300초)까지 돌린다(`on_int` — 그때 `phase`는 이미 `recording`이다). 띄운 직후의 둘째 더블 탭이 그 틈에 떨어지면 사람은
   끝냈는데 마이크가 5분 열려 있다. "recording" 줄을 본 뒤에만 끝낸다. 전사 중의 더블 탭도 무시한다 — 그때의 SIGINT는 `tars-dictate`에게
   취소(130)라서, 다 말하고 한 번 더 두드린 손이 받아 적힌 것을 버리게 된다.

   표준 에러를 파이프로 받는 이유(design이 열어 둔 것). 셋이다 — 상한에서 스스로 멈춘 녹음을 terminal이 알 길이 그 줄뿐이고(terminal은
   시간을 안 센다 — `max_seconds`는 `dictation.conf`에 있고 바뀐다), 그것을 모르면 전사 중의 Esc를 가로채고 `REC`를 계속 보인다. 그리고
   시리얼에 다시 찍으므로 게이트가 M0의 정본 줄을 그대로 본다.

3. 시그널과 Esc(design 결정 6 · 11, "정할 것" 3 · 5).

   | 키 | 단계 | 한 일 | 그 뒤 |
   |---|---|---|---|
   | 더블 탭 | 없음 | 띄운다(비밀번호면 안 띄우고 `PASSWORD`) | `starting` |
   | 더블 탭 | `recording` | 그룹에 SIGINT | `transcribing` |
   | 더블 탭 | `starting` · `transcribing` · `cancelling` | 무시(`ignored` 줄) | 그대로 |
   | 수정키 없는 Esc | `starting` · `recording` | 그룹에 SIGTERM. PTY로 안 간다 | `cancelling` |
   | Esc | 그 밖 | VD 전과 같다 | — |

   Esc는 `handleKey`의 1.3번 단계 — `Cmd+V`(1.35) · find · copy 표 · 한글 층보다 앞이다. 녹음 중의 Esc는 받아쓰기의 것이라 copy mode가
   그대로 남고, 조합 중이던 글자도 그대로이고, EL의 `esc_latin`도 안 돈다(`input_test` 82). `input.zig`는 자식을 모르므로 `main.zig`가
   `Context.dictating`(= `escCancels(phase)`)으로 넘긴다 — DECCKM과 같은 길이다. 수정키가 있는 Esc는 평소의 길이다(EL과 같은 선).
   전사 중의 Esc를 안 가져가는 것은 Voxio `isCapturing`과 같다 — 취소도 안 되면서 vim의 Esc만 사라지게 하지 않는다.

   terminal은 녹음 시간을 안 센다. 상한은 `tars-dictate`의 `max_seconds`가 지키고, 그렇게 멈추면 위의 줄로 안다.

4. 삽입(design 결정 11, "정할 것" 4).

   대상은 두 번을 누른 순간의 포커스 패널이다(Voxio D8 1번) — 그 패널 셸의 pid로 든다. 패널 포인터나 master fd로 안 드는 이유는 코드의
   주석에 있다(워크스페이스가 닫히면 배열이 당겨지고, 닫힌 fd 번호는 곧바로 다시 쓰인다). 포커스를 옮겨도, 워크스페이스를 바꿔도 그 패널에
   간다. 그 패널이 닫혔으면 넣지 않고 `NO PANE`이다.

   넣는 순서. 패널이 있는가 → 비밀번호 프롬프트인가 → `dictation.sanitize`로 거르고 남은 것이 있는가 → 그 패널이 포커스이고 한글을 조합
   중이면 그 글자를 먼저 확정해 보낸다(`Cmd+V`와 같은 순서) → `pasteParts`(모드 2004면 bracketed paste). 클립보드는 안 만진다.

   비밀번호 판정 — lead의 결정을 좁혔다. `ECHO`가 꺼졌는가가 아니라 `ICANON`이 켜지고 `ECHO`가 꺼졌는가다. 셸의 줄 편집기(readline ·
   zle · fish)와 vim은 `ECHO`와 `ICANON`을 함께 끈다 — `ECHO`만 보면 모든 셸 프롬프트가 비밀번호다(확정 9가 fish 프롬프트에서 쟀다:
   `icanon=false echo=false`). vendored ghostty가 같은 판정을 쓴다(`termio/Exec.zig`의 `mode.canonical and !mode.echo`). master에 `tcgetattr`를 하면
   커널이 slave의 termios를 준다(`tty_mode_ioctl`이 master면 `tty->link`). 보는 때는 둘이다 — 시작할 때(그러면 마이크를 안 연다, Voxio V10)와
   넣을 때(말하는 사이에 `sudo`가 뜰 수 있다). 이 판정이 못 보는 것은 자기 편집기로 가리는 프로그램이다(fish의 `read -s`) — design 위험 2에
   덧붙인다.

   거르기(design 결정 11이 열어 둔 "방어 한 겹") — 한다. 규칙은 `tars-dictate`의 `printable | strip`과 같고(C0는 탭 · 개행만 남기고, DEL ·
   C1을 지우고, 앞뒤 공백 · 탭 · 개행을 뗀다) `dictation_test` 16의 마지막 줄이 M0 체인 s8의 기대값과 글자까지 같다. 이 자리가 돌이킬 수
   없는 유일한 자리라서다. 체인은 이 거르기를 못 본다(M0가 이미 걸러 보낸다) — 호스트 검사가 본다.

5. 상태 줄(design 결정 11, "정할 것" 3).

   꼬리의 맨 끝에 칸 하나다 — `… CAPS[  W2][  COPY][  REC]`. 맨 끝인 것은 이 칸만 글자마다 길이가 다르기 때문이다(앞 칸들의 자리를 안
   흔든다). 받아쓰기를 안 쓰는 화면은 한 글자도 안 바뀐다(`COPY`와 같은 규칙) — 그래서 `hangul` · `copy` · `pane` · `pointer` 체인의
   `text=` 기준값이 그대로 선다.

   | 칸 | 언제 | 사라질 때 |
   |---|---|---|
   | `REC` | `starting` · `recording` | 단계가 바뀔 때 |
   | `WAIT` | `transcribing` | 자식이 끝날 때 |
   | (없음) | `cancelling` · exit 0(넣었다 — 글자가 증거다) · 2 · 130 · 143 | — |
   | `NO MIC` · `NO KEY` · `FAILED` | exit 1 · 3 · 그 밖(4 · 64 · 127 · 시그널 · 64KB 넘음) | 다음 키 |
   | `PASSWORD` · `NO PANE` | 시작 · 넣기를 거절했다 | 다음 키 |

   "다음 키"는 무언가를 한 키다 — 바이트 · 스크롤 · copy · 패널 · 받아쓰기 명령이 나왔거나 다시 그렸다. 수정키만 누르고 뗀 배치는 안 센다.
   세면 더블 탭의 마지막 뗌이 방금 뜬 `PASSWORD`를 곧바로 지운다. 시간으로 지우지 않는다(PD가 비목표로 둔 자리).

   글자는 영어 대문자다(`CAPS` · `COPY`와 같은 줄). 색은 전용 `STATUS_DICT` = `0xF07070`이고 `dumpStatus`가 `status> dict ink=`로 센다
   (CI의 `copy ink`와 같은 짝). `MAX_LEN`은 이름 표에서 comptime에 세므로 46 → 56이 저절로 됐다(가장 긴 `PASSWORD` + `GAP`). `status_test`의
   검사 10이 그 수를 정확히 본다.

6. 게이트(design 결정 9, "정할 것" 6) — 새 체인 없이 `dictation/check.sh`에 부팅 B.

   부팅 A(M0)는 그대로다. 부팅 B는 같은 QEMU 줄(q35 · HDA 마이크 · SLIRP의 stub)에 monitor 45493을 더하고, 설정 디스크
   `out/dictation-b.img`(라벨 `tars-dictate`)에 `tars.conf`(`net=dhcp`) · `groq.key`(`vd1-test-key`) · `dictation.conf`(`/ok/b`)와 사람이 칠
   것을 줄인 스크립트 셋(`vd-pw` · `vd-cap` · `vd-nokey`)을 담는다. 셸은 기본값 fish다. stub의 로그는 부팅 B만의 것(`stub_b.log`)이다.
   부팅 A 앞에 `zig build test`(terminal의 호스트 검사)를 더했다.

   더블 탭은 `sendkey meta_r` 둘을 잇달아 보내는 것이다. `type_keys`를 안 쓴다 — 수정키 하나는 로그를 한 줄도 안 만들어 `type_keys`가 키마다
   0.3초를 기다리고, 그러면 둘째 누름이 창 밖이다. 화면은 마지막 프레임만 본다(`last_screen`) — `wait_for_screen`은 로그의 모든 프레임을
   훑으므로 지운 줄이나 다른 패널의 지난 프레임에 걸린다.

   | 검사 | 본다 | 사본의 값 |
   |---|---|---|
   | 14 | 한 번 탭 · 0.6초 떨어진 두 탭은 아무것도 안 한다(`dictate>` 줄 0) | 초록 |
   | 15 | B1 — 두 번 → `start` · `phase recording` · `REC` · `dict ink>0` → 1.5초 → 두 번 → `stop` · `WAIT` · `recording stopped by SIGINT` · `exit code=0` · `insert len=28 bracketed=1 ws=1 leaf=0` · 프롬프트 줄에 `안녕하세요 vd0-dictated`, 실행 안 됨, 칸이 사라지고 `dict ink=0`, 요청 1 | `insert len=28 bracketed=1 ws=1 leaf=0` |
   | 16 | B2 — 녹음 중의 Esc → `cancel` · `exit code=143`, `key>` 줄이 안 늘었다, 요청 그대로 | 초록 |
   | 17 | B3 — `vd-pw`의 `read -s`가 기다릴 때 두 번 → `refused password at=start` · `PASSWORD`, 시작 없음, Enter → `got[]` · 칸이 사라진다 | 초록 |
   | 18 | B4 — 프롬프트에서 시작하고 녹음 중에 `vd-pw`를 친 뒤 끝냄 → `refused password at=insert` · `PASSWORD`, `read`가 받은 것이 빈 문자열, 요청 2 | 초록 |
   | 19 | B5 — `Cmd+D`로 가른 leaf 1에서 시작, `Cmd+[`로 leaf 0에 와서 끝냄 → `insert … leaf=1`, leaf 0의 화면에 없고 `Cmd+]` 뒤 leaf 1의 프롬프트에 있다, 요청 3 | 초록 |
   | 20 | B6 — leaf 1에서 시작하고 `Cmd+W`로 닫은 뒤 끝냄 → `no pane` · `NO PANE`, 넣은 것 없음, 요청 4, 다음 키에 칸이 사라진다 | 초록 |
   | 21 | B7 — `vd-cap`(1초 상한) 뒤 두 번 → `phase transcribing`(자식의 줄) → 넣었다, 다시 두 번 → 새 시작 → 넣었다, `stop`/`ignored`가 안 늘었다, 요청 6 | 초록 |
   | 22 | B8 — `vd-nokey` 뒤 두 번 → `exit code=3` · `NO KEY`, `phase recording` 없음, 요청 그대로, 다음 키에 사라진다 | 초록 |
   | 23 | 부팅 B의 요청 여섯이 전부 키를 싣고 마이크의 상수다(`/ok/b` 넷 · `/ok/cap` 둘). `system_powerdown` 뒤 디스크의 `dictation.jsonl`이 여섯 줄 — 넣지 않은 B4 · B6도 남는다 | 6 |

   판정 글자는 위 "로그 줄"과 체인 파일의 `report_b` 문구가 정본이다.

7. 시간. 사본에서 `init` · `terminal`의 캐시를 지운 첫 판이 2분 39초(커널은 스탬프로 건너뛴다), 데운 판이 77 · 75초였다. M0의 데운 판
   33 ~ 35초에 부팅 B가 42초 남짓을 더한다 — 부팅에서 프롬프트 · 경로 · 믹서까지 약 15초, 받아쓰기 여덟 번과 그 사이의 타이핑이 나머지다.
   루트 게이트는 이 체인을 두 번 돌리므로 M0의 53분 28초에 1분 30초 남짓을 더한 것으로 본다.

8. mutation. 열 가지를 열한 판(대조군 하나 포함)으로 돌렸다(`/tmp/run/vd1/make_mut.py` · `run_mut.sh`, 로그는 `/tmp/run/vd1/mut/`).
   호스트 검사가 먼저 잡는 셋(1 · 5 · 7)은 호스트 검사를 건너뛴 체인 사본(`check_notest.sh`)을 함께 덮어 부팅 B의 겨냥한 검사까지 한 번 더
   보냈다(lessons "mutation이 겨냥한 검사에 걸릴 것이라고 믿기"). `FAIL` 줄은 로그의 첫 `^FAIL`이다 — 호스트 검사가 잡은 판은 그 검사의 줄이
   먼저 나오고 체인의 `FAIL: terminal host tests failed …`가 뒤따른다.

   | mutation | 판 | 덮는 사본 | 잡은 자리 | 첫 `FAIL` 줄 | 시간 |
   |---|---|---|---|---|---|
   | (대조군) | `m0` | 없음 | — | `VD check PASS` | 77초 |
   | 1 판정 창이 없다 | `m1` | `dictation_m1.zig` | `dictation_test` 3 · `input_test` 76 | `FAIL: second down at 301ms: fired=true, want false` | 41초 |
   | | `m1_gate` | + `check_notest.sh` | 검사 14 | `FAIL(boot B): a single tap or two taps 0.6s apart started something (terminal: dictate> start pid=98 ws=1 leaf=0)` | 50초 |
   | 2 `setpgid`가 없다 | `m2` | `main_m2.zig` | 검사 15(SIGINT가 그룹에 안 닿아 녹음이 상한까지 간다) | `FAIL(boot B): B1: nothing was inserted` | 118초 |
   | 3 넣을 때 비밀번호를 안 본다 | `m3` | `main_m3.zig` | 검사 18(로그에 `insert len=28 bracketed=0` — `read -s`에 들어갔다) | `FAIL(boot B): B4: the text was not refused at the password prompt` | 121초 |
   | 4 시작할 때 비밀번호를 안 본다 | `m4` | `main_m4.zig` | 검사 17 | `FAIL(boot B): B3: a double tap on a password prompt was not refused` | 107초 |
   | 5 Esc를 안 가로챈다 | `m5` | `input_m5.zig` | `input_test` 82 | `FAIL: code=1 value=1 t=0us -> dictate null, want .cancel` | 40초 |
   | | `m5_gate` | + `check_notest.sh` | 검사 16 | `FAIL(boot B): B2: Esc did not cancel` | 64초 |
   | 6 포커스에 넣는다 | `m6` | `main_m6.zig` | 검사 19 | `FAIL(boot B): B5: the text went to terminal: dictate> insert len=28 bracketed=1 ws=1 leaf=0` | 103초 |
   | 7 멈춤 줄을 안 읽는다 | `m7` | `dictation_m7.zig` | `dictation_test` 12 | `FAIL: phaseAfter(.recording, "tars-dictate: recording stopped by SIGINT after 1896ms") = .recording, want .transcribing` | 41초 |
   | | `m7_gate` | + `check_notest.sh` | 검사 21 | `FAIL(boot B): B7: the 1s limit did not move the phase (tars-dictate's line was not read)` | 83초 |

   읽을 것 둘.
   - `m2`가 design 결정 6의 증거다. 자식이 terminal의 그룹에 남으면 `kill(-pid)`가 `ESRCH`로 사라지고, `stop` 줄은 찍히는데 `arecord`는
     상한까지 녹음한다 — 사람에게는 "두 번 눌렀는데 안 멈춘다"이다.
   - `m3`의 로그가 design 위험 2가 실제로 무엇인지 보여 준다. `read -s`는 모드 2004를 안 켜므로 `bracketed=0`이고, 그 자리에 사람이 말한 것이
     그대로 들어갔다(검사 18의 `got[…]`이 비지 않았다).

   `sanitize`(확정 4)는 체인이 못 본다 — M0의 `tars-dictate`가 이미 걸러서 보낸다. `dictation_test` 16이 본다.

9. 실측. 체인을 측정판으로 두 번 돌렸다(`/tmp/run/vd1/meas/ov/` — 트리거 키의 evdev 시각과 `tcgetattr`의 두 비트를 찍는 줄을 사본에만
   넣었다. 로그는 `/tmp/run/vd1/meas/serial_b.log`).
   - `sendkey meta_r`가 게스트의 `KEY_RIGHTMETA`(126)다. hold를 안 적으면 누른 시간이 7 ~ 23ms, 둘을 잇달아 보낸 두 누름 사이가 19 ~ 22ms였다
     (판 열넷). `sendkey meta_r 80` 둘이면 누른 시간 78 ~ 83ms, 두 누름 사이 159 ~ 163ms다(판 열넷) — 체인은 이쪽을 쓴다. QEMU가 뗌을 지연과
     함께 입력 큐에 넣고 다음 sendkey가 그 뒤에 줄을 서기 때문이다. 늦은 두 탭(0.6초 · 0.8초 간격)은 603 ~ 1013ms였다.
   - termios. fish 프롬프트의 master에서 `icanon=false echo=false`(아홉 번, 패널 둘 다), `vd-pw`의 `read -s`가 기다릴 때
     `icanon=true echo=false`(두 번)였다. `ECHO`만으로 판정했다면 fish 프롬프트의 아홉 번이 전부 비밀번호였다.
   - 넣은 글자는 `insert len=28 bracketed=1`이다 — `안녕하세요 vd0-dictated`(15 + 1 + 12바이트), fish가 모드 2004를 켜 두었다.

10. regression. terminal의 키 경로 · 상태 줄 · poll이 바뀌므로 여섯을 사본에서 돌렸다. 여섯 다 exit 0이다.

    | 체인 | 시간(사본) | 왜 돌렸나 |
    |---|---|---|
    | `copy` | 215초 | Esc · `Cmd+V` · copy 표의 순서, 상태 줄의 `COPY` 꼬리(`copy ink`) |
    | `hangul` | 81초 | 한글 층과 EL의 Esc, 상태 줄의 `text=` · `caps ink` 기준값 |
    | `input` | 37초 | `handleKey`의 수정키 갈래(오른쪽 Cmd가 그 안이다) · `keyboard=pc` |
    | `pane` | 44초 | poll의 PTY 칸 경계(`pty_end`) · 워크스페이스 칸 · `status> text=` |
    | `terminal` | 23초 | poll 루프의 기본 · 되살리기 |
    | `pointer` | 74초 | poll의 장치 칸 · `key_state.modifiers()` · 상태 줄 |

    그 밖의 체인은 오른쪽 Cmd를 안 누르고(`meta_r` · `alt_r`을 보내는 체인이 없다) 상태 줄에 받아쓰기 칸이 안 뜬다. 루트 게이트가 전부를 본다.

11. 낡은 산출물 · 앵커. 이 milestone은 커널 · `init` · 이미지 · initrd의 내용을 안 바꾼다(initrd는 체인마다 새로 짓지만 terminal 바이너리만
    다르다). Task 4가 캐시 삭제를 같은 `docker run` 안에 둔다(`project_zig_out_staleness`). 편집 64개의 `old_string`이 HEAD `11039e6`의 파일에
    정확히 한 번씩 있고(`python3 /tmp/run/vd1/anchors.py pre "$PWD"` → `pre: 64 edits, 0 bad`), `new_string`이 사본에 정확히 한 번씩
    있다(`post: 64 edits, 0 bad`). 진입 검사 셋도 사본의 `dictation/check.sh`에서 `ENTRY-OK`였다. plan 본문에서 블록을 뽑아 기준 파일에 넣으면
    `new/`와 바이트까지 같다(`/tmp/run/vd1/verify_plan.py`).

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
   ```

   기대: 맨 위 commit이 `11039e6 VD-M0: …`이거나 그 위에 lead의 commit(이 plan · design)이 있다. `git status`에 lead가 고치는 중일 수 있는
   `HANDOFF.md` · design · 이 plan · `MEMORY.md` · `docs/decisions/`가 있을 수 있다. 그 밖의 소스 파일이 `M`이면 멈추고 보고한다.
   `terminal/src/dictation.zig`가 이미 있으면 멈추고 보고한다.

3. 편집의 앵커와 기준 파일을 본다(확정 11).

   ```bash
   python3 /tmp/run/vd1/anchors.py pre "$PWD"
   for f in terminal/build.zig terminal/src/status.zig terminal/src/status_test.zig terminal/src/input.zig \
     terminal/src/input_test.zig terminal/src/main.zig dictation/check.sh; do cmp $f /tmp/run/vd1/base/$f && echo "BASE $f"; done
   ```

   기대: `pre: 64 edits, 0 bad`와 `BASE` 일곱. 하나라도 다르면 그 파일을 보고하고 멈춘다 — 앵커를 다시 뽑아야 한다.

4. 편집을 넣는 도구. 이 plan 파일에서 `<파일> E<n>` 블록을 E1부터 차례로 찾아 `old_string`이 정확히 한 번 있는지 보고 바꾼다. 한
   파일에서 하나라도 어긋나면 그 파일을 한 글자도 안 쓰고 멈춘다. 각 Task가 아래처럼 부른다.

   ```bash
   python3 /tmp/run/vd1/apply_plan.py docs/plans/2026-10-06-tars-voice-dictation-vd-m1.md "$PWD" <파일>...
   ```

   `apply_plan.py`:

````python
"""VD-M1 plan 본문의 편집 블록을 저장소에 넣는다(구현자용).

사용: python3 apply_plan.py <plan 경로> <저장소 루트> <파일>...
파일마다 plan의 "<파일> E<n>" 블록을 E1부터 차례로 찾아, old_string이 정확히 한 번 있는지 보고 바꾼다.
하나라도 0번이거나 두 번 이상이면 그 파일을 한 글자도 안 쓰고 멈춘다.
"""
import os, re, sys
plan = open(sys.argv[1]).read()
root = sys.argv[2]
pat = re.compile(r"^(\S+) E(\d+) — `old_string`\(기준 파일 \d+줄부터\):\n\n```[a-z]*\n(.*?)\n```\n\n`new_string`:\n\n```[a-z]*\n(.*?)\n```\n", re.S | re.M)
blocks = {}
for path, num, old, new in pat.findall(plan):
    blocks.setdefault(path, []).append((int(num), old, new))
bad = 0
for f in sys.argv[3:]:
    p = os.path.join(root, f)
    s = open(p).read()
    for k, (num, old, new) in enumerate(blocks.get(f, []), 1):
        assert num == k, (f, num, k)
        n = s.count(old)
        if n != 1:
            print(f"{f} E{num}: old_string count={n}, file left as it was")
            bad += 1
            break
        s = s.replace(old, new)
    else:
        open(p, 'w').write(s)
        print(f"{f}: {len(blocks.get(f, []))} edit(s)")
        continue
sys.exit(1 if bad else 0)
````

## Task 1: `terminal/src/dictation.zig` · `dictation_test.zig`(새 파일) · `terminal/build.zig`

확정 1 ~ 5의 순수한 층. 이 Task가 끝나면 `zig build test`에 `dictation_test`가 더해져 돈다. 게스트 바이너리는 아직 이 파일을 안 쓴다.

### 1-1. 새 파일 둘

```bash
cp -p /tmp/run/vd1/new/terminal/src/dictation.zig /tmp/run/vd1/new/terminal/src/dictation_test.zig terminal/src/
```

본문은 아래와 같다(읽기용 — 넣는 것은 위의 `cp -p`다).

`terminal/src/dictation.zig`:

```zig
const std = @import("std");

// 받아쓰기의 순수한 층(VD-M1, VD design 결정 10 · 11). 시스템 콜도 `vt.zig`도
// 프레임버퍼도 안 본다 — 시각 · 단계 · 종료 코드를 받아 판단을 돌려주는 계산이라
// `dictation_test`가 호스트에서 전부 본다. fork · 파이프 · 시그널 · PTY 쓰기는
// `main.zig`의 받아쓰기 절에 있다(pointer.zig와 main.zig의 경계와 같다).
//
// 녹음 · 전사 · 기록은 게스트의 `tars-dictate`가 한다(VD-M0). 이 파일이 아는 그
// 프로그램의 계약은 셋이다 — 종료 코드(`outcome`), 표준 에러의 두 줄(`phaseAfter`),
// 표준 출력이 넣을 글자라는 것(`sanitize`).

/// 더블 탭의 창(Voxio D6의 `doubleTapWindowMs` 기본값, VD design 결정 10).
///
/// 첫 누름에서 둘째 누름까지를 잰다. 닫힌 구간이라 정확히 300ms는 발동한다
/// (Voxio `isWithinWindow`). `input.zig`의 `TAP_MAX_US`와 수가 같지만 재는 것이
/// 다르다 — 그쪽은 한 번 누른 길이이고 이쪽은 두 누름 사이다.
///
/// 설정으로 안 뺀다(design 결정 3의 표 — `trigger.doubleTapWindowMs`는 상수로 간다).
pub const WINDOW_US: u64 = 300_000;

/// 트리거 키의 더블 탭 판정기(Voxio `DoubleTapDetector`의 toggle 모드).
///
/// 녹음 중인지를 모른다 — Voxio와 갈리는 자리다(design 결정 10의 함정 3). Voxio는
/// 판정기가 `recording`을 들고 있다가 키 없이 끝나는 길마다 `syncToIdle`을 불러야
/// 했고, 하나를 빠뜨리면 다음 더블 탭이 "끝내라"로 읽혔다(V17). 여기서는 그 상태가
/// 아예 없다. 판정기는 "두 번 눌렸다"만 말하고, 그것이 시작인지 끝인지는
/// `onTap`이 자식의 단계로 정한다 — 자식이 스스로 끝나면 단계가 사라지므로 맞출
/// 것이 남지 않는다.
///
/// 자동 반복(value 2)은 부르는 쪽이 안 넣는다(함정 1). 커널 입력 코어는 상태가
/// 바뀔 때만 1을 보내므로 같은 누름이 두 번 오는 일은 2 말고는 없다.
pub const DoubleTap = struct {
    step: Step = .idle,
    /// 첫 누름의 시각. `step`이 `idle`이 아닐 때만 뜻이 있다.
    first_down_us: u64 = 0,

    const Step = enum {
        idle,
        /// 첫 누름을 봤고 뗌을 기다린다.
        first_down,
        /// 누름 → 뗌이 끝났고 둘째 누름을 기다린다.
        first_up,
    };

    /// 트리거 키의 누름. 더블 탭이 완성됐으면 참이다.
    ///
    /// `combined`는 다른 수정키가 눌려 있는가다. 그러면 이 누름은 조합의 일부이고
    /// 진행 중이던 판정도 버린다(Voxio `downWithForeignModifierIsNotFed`). 새 판정의
    /// 시작으로도 안 친다 — Shift를 잡은 채 누른 것을 첫 탭으로 세면, Shift를 놓고
    /// 한 번 더 누르는 것이 더블 탭이 된다.
    ///
    /// 창을 넘긴 둘째 누름은 버리지 않고 새 판정의 첫 누름으로 본다(Voxio
    /// `lateSecondTapBecomesNewSequence`). 시각이 거꾸로 가면 창 밖이다.
    pub fn down(self: *DoubleTap, time_us: u64, combined: bool) bool {
        if (combined) {
            self.step = .idle;
            return false;
        }
        if (self.step == .first_up and time_us >= self.first_down_us and
            time_us - self.first_down_us <= WINDOW_US)
        {
            self.step = .idle;
            return true;
        }
        self.step = .first_down;
        self.first_down_us = time_us;
        return false;
    }

    /// 트리거 키의 뗌. 첫 누름 뒤의 뗌만 판정을 앞으로 보낸다 — 그 밖의 뗌은
    /// 짝이 없다(terminal이 뜨기 전부터 눌려 있던 키의 뗌 등).
    pub fn up(self: *DoubleTap) void {
        if (self.step == .first_down) self.step = .first_up;
    }

    /// 진행 중인 판정을 버린다. 다른 키의 누름(조합의 신호, Voxio
    /// `otherKeyDownDiscardsPendingTap`)과 `SYN_DROPPED`(그 사이의 뗌을 잃었을 수
    /// 있다 — design 결정 10의 함정 2)가 부른다.
    pub fn reset(self: *DoubleTap) void {
        self.step = .idle;
    }
};

/// 자식(`tars-dictate`) 하나의 단계. 자식이 없으면 `?Phase`의 null이다.
///
/// 단계를 키 순서가 아니라 자식에게서 읽는 것이 design 결정 10의 함정 3이다.
/// `starting` → `recording`과 `recording` → `transcribing`은 자식의 표준 에러가
/// 옮기고(`phaseAfter`), null로 되돌리는 것은 자식의 끝(표준 출력 · 표준 에러의
/// EOF) 하나뿐이다.
pub const Phase = enum {
    /// 띄웠고 자식이 아직 "recording" 줄을 안 찍었다. 설정과 키를 읽는 중이다 —
    /// 키가 없으면 여기서 끝난다(exit 3).
    starting,
    /// 마이크가 열렸다(`tars-dictate: recording; …`).
    recording,
    /// 녹음이 끝나고 전사 중이다. 둘째 더블 탭이 SIGINT를 보냈거나 자식이
    /// `max_seconds`에서 스스로 멈췄다(`tars-dictate: recording stopped …`).
    transcribing,
    /// Esc가 SIGTERM을 보냈다. 끝나기를 기다린다.
    cancelling,
};

/// 더블 탭이 할 일.
pub const TapAction = enum {
    /// 자식이 없다 — 띄운다.
    start,
    /// 녹음 중이다 — 그룹에 SIGINT(녹음 끝, 전사로).
    stop,
    /// 그 밖 — 아무것도 안 한다.
    ignore,
};

/// 더블 탭의 뜻을 단계로 정한다(Voxio D6 — 시작과 끝이 같은 제스처).
///
/// `starting`의 더블 탭을 무시하는 이유. `tars-dictate`는 `arecord`가 돌기 전에
/// 받은 SIGINT를 "녹음을 끝내라"로 기억만 하고 그 뒤에 `arecord`를 상한(300초)까지
/// 돌린다(M0의 `on_int`). 띄운 직후 수십 ms 안의 둘째 더블 탭이 그 길을 밟으면
/// 사람은 녹음을 끝냈는데 마이크가 5분 열려 있다. "recording" 줄을 본 뒤에만
/// 끝낸다.
///
/// 전사 중의 더블 탭도 무시한다. 그때의 SIGINT는 `tars-dictate`에게 취소다(exit
/// 130) — 말을 다 하고 한 번 더 두드린 손이 받아 적힌 것을 버리게 하지 않는다.
pub fn onTap(phase: ?Phase) TapAction {
    const p = phase orelse return .start;
    return switch (p) {
        .recording => .stop,
        .starting, .transcribing, .cancelling => .ignore,
    };
}

/// 이 단계에서 Esc가 받아쓰기의 것인가(Voxio D11a — 마이크가 열려 있거나 열리는
/// 중일 때만). 참이면 Esc는 취소이고 PTY로 안 간다. 전사 중의 Esc는 뒤의 프로그램의
/// 것이다 — 거기서 먹으면 취소도 안 되면서 vim의 Esc만 사라진다(Voxio
/// `isCapturing`의 주석).
pub fn escCancels(phase: ?Phase) bool {
    const p = phase orelse return false;
    return switch (p) {
        .starting, .recording => true,
        .transcribing, .cancelling => false,
    };
}

/// 자식이 표준 에러에 찍은 한 줄로 단계를 옮긴다. 줄의 글자는 M0의 정본이다
/// (M0 plan "이 milestone이 끝나면"의 로그 줄) — 그쪽을 고치면 여기도 고친다.
///
/// 앞으로만 간다. `transcribing`에서 "recording" 줄을 다시 봐도 안 돌아가고,
/// `cancelling`은 어떤 줄로도 안 바뀐다.
pub fn phaseAfter(phase: Phase, line: []const u8) Phase {
    return switch (phase) {
        .starting => if (std.mem.startsWith(u8, line, "tars-dictate: recording; "))
            .recording
        else
            .starting,
        .recording => if (std.mem.startsWith(u8, line, "tars-dictate: recording stopped "))
            .transcribing
        else
            .recording,
        .transcribing, .cancelling => phase,
    };
}

/// 상태 줄 꼬리의 받아쓰기 칸이 무엇을 말하는가(design 결정 11). 글자는
/// `status.zig`의 `dictWord`가 정한다 — 이 파일은 글자를 모른다.
pub const Show = enum {
    /// 마이크가 열려 있거나 열리는 중이다(`starting` · `recording`).
    rec,
    /// 전사 중이다(`transcribing`).
    wait,
    /// 녹음을 못 했다(exit 1).
    no_mic,
    /// API 키가 없다(exit 3).
    no_key,
    /// 전사가 실패했다(exit 4 · 그 밖의 코드 · 시그널 · 글자가 너무 길다).
    failed,
    /// 비밀번호 프롬프트라 마이크를 안 열었거나 글자를 안 넣었다.
    password,
    /// 트리거를 누른 패널이 그사이 닫혔다. 글자는 기록에 있다.
    no_pane,
};

/// 단계가 보이는 모양. 취소 중에는 아무것도 안 보인다 — 사람이 Esc로 이미 끝낸
/// 것이다.
pub fn showOf(phase: Phase) ?Show {
    return switch (phase) {
        .starting, .recording => .rec,
        .transcribing => .wait,
        .cancelling => null,
    };
}

/// 자식이 끝난 뒤 할 일.
pub const Outcome = union(enum) {
    /// 모은 표준 출력을 대상 패널에 넣는다.
    insert,
    /// 아무것도 안 한다. 상태 줄도 비운다.
    quiet,
    /// 상태 줄에 알린다. 다음 키에 사라진다.
    notice: Show,
};

/// 종료 코드를 읽는다(design 결정 6의 표 — M0 `tars-dictate`의 머리 주석이 정본).
///
/// `code`가 null이면 자식이 시그널로 죽었다(`tars-dictate`는 INT · TERM을 trap하므로
/// 그 둘로는 이렇게 안 끝난다 — SIGKILL 등이다). 취소 중이었으면 무엇으로 끝났든
/// 조용하다 — 사람이 끝낸 것이다.
///
/// 2(무음 · 0바이트)와 130 · 143(취소)은 조용하다. 64(인자)와 127(`execve` 실패,
/// `main.zig`의 자식이 그 값으로 나간다)은 사람이 고칠 수 있는 설정 문제가 아니라서
/// 전사 실패와 같은 칸이다 — 자세한 것은 시리얼 로그의 `dictate> exit` 줄에 있다.
pub fn outcome(phase: Phase, code: ?u8) Outcome {
    if (phase == .cancelling) return .quiet;
    const c = code orelse return .{ .notice = .failed };
    return switch (c) {
        0 => .insert,
        2, 130, 143 => .quiet,
        1 => .{ .notice = .no_mic },
        3 => .{ .notice = .no_key },
        else => .{ .notice = .failed },
    };
}

/// 비밀번호 프롬프트인가(design 위험 2). ghostty와 같은 판정이다
/// (`termio/Exec.zig` — `mode.canonical and !mode.echo`).
///
/// `ECHO`만 보면 안 된다. 셸의 줄 편집기(readline · zle · fish)와 vim은 글자를 자기가
/// 그리므로 `ECHO`를 끄고 `ICANON`도 끈다 — `ECHO`만 보면 모든 셸 프롬프트가
/// 비밀번호다. `sudo` · `ssh` · `bash`의 `read -s`처럼 줄 단위로 읽으면서 안 보여 주는
/// 것만 `ICANON`이 켜지고 `ECHO`가 꺼진다.
///
/// 이 판정이 못 보는 것 — 자기 편집기로 가리는 프로그램(fish의 `read -s`가 그렇다,
/// 글자를 •로 그린다). 그런 프롬프트에는 글자가 들어간다(Enter는 안 붙는다).
pub fn isPasswordPrompt(canonical: bool, echo: bool) bool {
    return canonical and !echo;
}

/// 넣기 전에 한 번 더 거른다(design 결정 11 — "방어 한 겹"을 고른다).
///
/// 규칙은 `tars-dictate`의 `printable | strip`과 같다. 탭과 개행만 남기고 C0 · DEL ·
/// C1을 지운 뒤, 앞뒤의 공백 · 탭 · 개행을 뗀다. 두 번 거르는 이유는 이 자리가
/// 돌이킬 수 없는 유일한 자리이기 때문이다 — ESC 하나가 살면 `ESC[201~`로 bracketed
/// paste를 닫고 뒤를 명령으로 흘릴 수 있고(Voxio 94e0e64), 끝의 개행은 Enter다.
/// 표준 출력을 만든 쪽이 무엇이든(사람이 `/usr/bin/tars-dictate`를 바꿨든) 이 규칙은
/// terminal이 지킨다.
///
/// UTF-8을 풀지 않는다. C1(U+0080~U+009F)은 UTF-8로 `C2 80` ~ `C2 9F` 두 바이트이고,
/// 0x80~0x9F 홀로는 다른 글자의 꼬리 바이트라 지우면 안 된다(`한`의 꼬리가 0x9C다).
/// 그래서 `C2` 뒤의 그 범위만 짝으로 지운다.
///
/// 제자리에서 고치고 남은 조각을 돌려준다(시작이 `buf[0]`이 아닐 수 있다).
pub fn sanitize(buf: []u8) []const u8 {
    var w: usize = 0;
    var i: usize = 0;
    while (i < buf.len) {
        const b = buf[i];
        if (b == 0xC2 and i + 1 < buf.len and buf[i + 1] >= 0x80 and buf[i + 1] <= 0x9F) {
            i += 2;
            continue;
        }
        if ((b < 0x20 and b != '\t' and b != '\n') or b == 0x7F) {
            i += 1;
            continue;
        }
        buf[w] = b;
        w += 1;
        i += 1;
    }
    return std.mem.trim(u8, buf[0..w], " \t\n");
}
```

`terminal/src/dictation_test.zig`:

```zig
const std = @import("std");
const dictation = @import("dictation.zig");

// 받아쓰기의 순수한 층을 호스트에서 본다(VD-M1). 시각은 전부 손으로 넣는다 — 실제
// 시계를 쓰면 창의 경계를 못 본다(Voxio `DoubleTapDetectorTests`의 머리 주석).
//
// 판정기 검사(1~9)는 Voxio의 `DoubleTapDetectorTests` · `TriggerEventRouterTests`
// 중 toggle 모드의 것을 옮겼다. 키보드 경로에 붙어야 뜻이 서는 것(자동 반복 · 왼쪽
// Cmd · `keyboard=pc` · 수정키 · Esc · `SYN_DROPPED`)은 `input_test`의 검사 75~83에
// 있다. hold 모드와 `recoverFromDroppedEvents`의 hold 갈래는 옮기지 않았다(design
// 비목표 3).

/// 시각은 밀리초로 적고 마이크로초로 넣는다. Voxio의 검사와 숫자를 맞춰 읽기 위해서다.
fn ms(v: u64) u64 {
    return v * 1000;
}

fn expectFire(got: bool, want: bool, what: []const u8) !void {
    if (got == want) return;
    std.debug.print("FAIL: {s}: fired={}, want {}\n", .{ what, got, want });
    return error.WrongTap;
}

fn expectTap(phase: ?dictation.Phase, want: dictation.TapAction) !void {
    const got = dictation.onTap(phase);
    if (got == want) return;
    std.debug.print("FAIL: onTap({any}) = .{s}, want .{s}\n", .{ phase, @tagName(got), @tagName(want) });
    return error.WrongTapAction;
}

fn expectOutcome(phase: dictation.Phase, code: ?u8, want: dictation.Outcome) !void {
    const got = dictation.outcome(phase, code);
    if (std.meta.eql(got, want)) return;
    std.debug.print("FAIL: outcome(.{s}, {?d}) = {any}, want {any}\n", .{ @tagName(phase), code, got, want });
    return error.WrongOutcome;
}

fn expectClean(raw: []const u8, want: []const u8) !void {
    var buf: [256]u8 = undefined;
    @memcpy(buf[0..raw.len], raw);
    const got = dictation.sanitize(buf[0..raw.len]);
    if (std.mem.eql(u8, got, want)) return;
    std.debug.print("FAIL: sanitize({any}) = {any}, want {any}\n", .{ raw, got, want });
    return error.WrongSanitize;
}

pub fn main() !void {
    // ── 검사 1: 창 안의 누름 → 뗌 → 누름이 발동한다 ──────────────────────
    // Voxio `doubleTapWithinWindowStarts`. 발동하는 것은 둘째 누름이다 — 뗌을
    // 기다리지 않는다.
    {
        var t: dictation.DoubleTap = .{};
        try expectFire(t.down(ms(0), false), false, "first down");
        t.up();
        try expectFire(t.down(ms(200), false), true, "second down at 200ms");
    }
    std.debug.print("dictation_test: down-up-down within 300ms fires OK\n", .{});

    // ── 검사 2: 발동한 뒤의 다음 더블 탭도 발동한다 ───────────────────────
    // Voxio `doubleTapWhileRecordingStops`. 그쪽은 둘째가 `.stop`이었는데 여기는
    // 판정기가 녹음을 모르므로 그냥 발동이다 — 끝인지는 `onTap`이 단계로 정한다
    // (검사 10). 발동한 누름은 새 판정의 첫 누름이 아니다: 그 뒤 한 번 더 눌러도
    // 안 발동하고, 새로 두 번 눌러야 한다.
    {
        var t: dictation.DoubleTap = .{};
        _ = t.down(ms(0), false);
        t.up();
        _ = t.down(ms(200), false);
        t.up();
        try expectFire(t.down(ms(1000), false), false, "first down of the next sequence");
        t.up();
        try expectFire(t.down(ms(1200), false), true, "second down of the next sequence");
    }
    std.debug.print("dictation_test: the next double tap fires again OK\n", .{});

    // ── 검사 3: 창은 닫힌 구간이다 — 300ms는 발동, 301ms는 아니다 ─────────
    // Voxio `exactWindowBoundaryStarts`. 301을 더한 것은 경계의 다른 쪽이다 —
    // `<=`가 `<`로 바뀌거나 창이 넓어지면 둘 중 하나가 빨개진다.
    {
        var t: dictation.DoubleTap = .{};
        _ = t.down(ms(1000), false);
        t.up();
        try expectFire(t.down(ms(1300), false), true, "second down at exactly 300ms");
        var u: dictation.DoubleTap = .{};
        _ = u.down(ms(1000), false);
        u.up();
        try expectFire(u.down(ms(1301), false), false, "second down at 301ms");
    }
    std.debug.print("dictation_test: the window is closed at 300ms and open at 301ms OK\n", .{});

    // ── 검사 4: 늦은 둘째 누름은 새 판정의 첫 누름이다 ────────────────────
    // Voxio `lateSecondTapBecomesNewSequence`. 버리면 사람이 "한 번 늦었으니 두 번
    // 더"를 해야 한다.
    {
        var t: dictation.DoubleTap = .{};
        _ = t.down(ms(0), false);
        t.up();
        try expectFire(t.down(ms(500), false), false, "late second down");
        t.up();
        try expectFire(t.down(ms(700), false), true, "the late down's own second down");
    }
    std.debug.print("dictation_test: a late second down starts a new sequence OK\n", .{});

    // ── 검사 5: 한 번 탭은 아무것도 안 한다 · 뗌이 없으면 안 발동한다 ───────
    // Voxio `singleTapDoesNothing`. 뒤 절반 — 누른 채 다시 누름이 오는 것은
    // evdev에서 자동 반복뿐이고 그것은 안 들어오지만, 들어와도 뗌이 없었으니
    // 발동하면 안 된다.
    {
        var t: dictation.DoubleTap = .{};
        try expectFire(t.down(ms(0), false), false, "single down");
        t.up();
        var u: dictation.DoubleTap = .{};
        _ = u.down(ms(0), false);
        try expectFire(u.down(ms(100), false), false, "down without an up in between");
    }
    std.debug.print("dictation_test: a single tap and a down without an up do nothing OK\n", .{});

    // ── 검사 6: 다른 키가 끼면 판정을 버린다 ─────────────────────────────
    // Voxio `otherKeyDownDiscardsPendingTap`. `reset`을 부르는 것은 `input.zig`의
    // 0.6번 단계다(다른 키의 누름).
    {
        var t: dictation.DoubleTap = .{};
        _ = t.down(ms(0), false);
        t.up();
        t.reset();
        try expectFire(t.down(ms(200), false), false, "second down after another key");
    }
    std.debug.print("dictation_test: another key in between discards the sequence OK\n", .{});

    // ── 검사 7: 다른 수정키가 눌린 누름은 발동도 시작도 안 한다 ─────────────
    // Voxio `downWithForeignModifierIsNotFed`. 둘째 누름에 Shift가 있으면 안 발동하고,
    // 첫 누름에 Shift가 있었으면 그것은 첫 탭이 아니다 — Shift를 놓고 한 번 더 눌러도
    // 안 발동한다.
    {
        var t: dictation.DoubleTap = .{};
        _ = t.down(ms(0), false);
        t.up();
        try expectFire(t.down(ms(200), true), false, "second down with a modifier held");
        var u: dictation.DoubleTap = .{};
        _ = u.down(ms(0), true);
        u.up();
        try expectFire(u.down(ms(200), false), false, "second down after a combined first down");
    }
    std.debug.print("dictation_test: a down with another modifier held neither fires nor starts OK\n", .{});

    // ── 검사 8: 짝 없는 뗌은 판정을 안 움직인다 ─────────────────────────
    // Voxio `repeatedUpDeliveryDoesNotAdvanceSequence`. 두 번 온 뗌도, 누름 없이 온
    // 뗌(terminal이 뜨기 전부터 눌려 있던 키)도 첫 탭이 아니다.
    {
        var t: dictation.DoubleTap = .{};
        _ = t.down(ms(0), false);
        t.up();
        t.up();
        try expectFire(t.down(ms(200), false), true, "second down after a repeated up");
        var u: dictation.DoubleTap = .{};
        u.up();
        try expectFire(u.down(ms(100), false), false, "down after an unpaired up");
    }
    std.debug.print("dictation_test: unpaired ups do not advance the sequence OK\n", .{});

    // ── 검사 9: 시각이 거꾸로 가면 창 밖이다 ────────────────────────────
    // `ev.time`은 벽시계라 뒤로 뛸 수 있다(`input.zig`의 `Tap.up`과 같은 이유).
    // 뺄셈이 감싸 돌면 엄청 긴 간격이라 결과는 같지만 명시한다.
    {
        var t: dictation.DoubleTap = .{};
        _ = t.down(ms(1000), false);
        t.up();
        try expectFire(t.down(ms(900), false), false, "second down earlier than the first");
    }
    std.debug.print("dictation_test: a clock that runs backwards is outside the window OK\n", .{});

    // ── 검사 10: 더블 탭의 뜻은 자식의 단계가 정한다 ──────────────────────
    // design 결정 10의 함정 3. 자식이 없으면 시작, 녹음 중이면 끝, 그 밖은 무시다.
    // 키 없이 끝난 실행(max_seconds · 키 없음 · 실패) 뒤에는 단계가 null로 돌아가므로
    // 다음 더블 탭이 시작이다 — Voxio V17의 "트리거가 한 번 씹힌다"가 여기서는 생길
    // 자리가 없다.
    try expectTap(null, .start);
    try expectTap(.starting, .ignore);
    try expectTap(.recording, .stop);
    try expectTap(.transcribing, .ignore);
    try expectTap(.cancelling, .ignore);
    std.debug.print("dictation_test: no child starts, recording stops, the rest is ignored OK\n", .{});

    // ── 검사 11: Esc는 마이크가 열려 있거나 열리는 중일 때만 받아쓰기의 것이다 ──
    // Voxio D11a · `isCapturing`.
    {
        const cases = [_]struct { p: ?dictation.Phase, want: bool }{
            .{ .p = null, .want = false },
            .{ .p = .starting, .want = true },
            .{ .p = .recording, .want = true },
            .{ .p = .transcribing, .want = false },
            .{ .p = .cancelling, .want = false },
        };
        for (cases) |cs| {
            if (dictation.escCancels(cs.p) != cs.want) {
                std.debug.print("FAIL: escCancels({any}) != {}\n", .{ cs.p, cs.want });
                return error.WrongEsc;
            }
        }
    }
    std.debug.print("dictation_test: Esc cancels only while starting or recording OK\n", .{});

    // ── 검사 12: 자식의 두 줄이 단계를 옮긴다 · 앞으로만 간다 ─────────────
    // 줄의 글자는 M0 `tars-dictate`의 정본이다. 비슷한 다른 줄(전사 결과 · 취소)은
    // 단계를 안 바꾼다.
    {
        const P = dictation.Phase;
        const cases = [_]struct { from: P, line: []const u8, want: P }{
            .{ .from = .starting, .line = "tars-dictate: recording; Ctrl+C stops (at most 300s)", .want = .recording },
            .{ .from = .starting, .line = "tars-dictate: no API key; write it to /config/groq.key (or set GROQ_API_KEY)", .want = .starting },
            .{ .from = .recording, .line = "tars-dictate: recording stopped by SIGINT after 1896ms", .want = .transcribing },
            .{ .from = .recording, .line = "tars-dictate: recording stopped at the 1s limit", .want = .transcribing },
            .{ .from = .recording, .line = "tars-dictate: unknown key 'colour' in /config/dictation.conf", .want = .recording },
            .{ .from = .transcribing, .line = "tars-dictate: recording; Ctrl+C stops (at most 300s)", .want = .transcribing },
            .{ .from = .cancelling, .line = "tars-dictate: recording stopped by SIGINT after 10ms", .want = .cancelling },
            .{ .from = .starting, .line = "tars-dictate: recording stopped at the 1s limit", .want = .starting },
        };
        for (cases) |cs| {
            const got = dictation.phaseAfter(cs.from, cs.line);
            if (got != cs.want) {
                std.debug.print("FAIL: phaseAfter(.{s}, \"{s}\") = .{s}, want .{s}\n", .{
                    @tagName(cs.from), cs.line, @tagName(got), @tagName(cs.want),
                });
                return error.WrongPhase;
            }
        }
    }
    std.debug.print("dictation_test: the child's two lines move the phase forward only OK\n", .{});

    // ── 검사 13: 단계가 상태 줄에 보이는 모양 ───────────────────────────
    if (dictation.showOf(.starting) != .rec or dictation.showOf(.recording) != .rec or
        dictation.showOf(.transcribing) != .wait or dictation.showOf(.cancelling) != null)
    {
        std.debug.print("FAIL: showOf is not rec, rec, wait, null\n", .{});
        return error.WrongShow;
    }
    std.debug.print("dictation_test: starting and recording show rec, transcribing shows wait, cancelling shows nothing OK\n", .{});

    // ── 검사 14: 종료 코드의 표(design 결정 6) ────────────────────────────
    // 넣는 것은 0 하나다. 2 · 130 · 143은 조용하고, 1 · 3은 사람이 고칠 것을 말하고,
    // 나머지는 전부 실패다. 취소 중이었으면 무엇으로 끝났든 조용하다.
    try expectOutcome(.transcribing, 0, .insert);
    try expectOutcome(.recording, 0, .insert);
    try expectOutcome(.transcribing, 2, .quiet);
    try expectOutcome(.transcribing, 130, .quiet);
    try expectOutcome(.recording, 143, .quiet);
    try expectOutcome(.starting, 1, .{ .notice = .no_mic });
    try expectOutcome(.starting, 3, .{ .notice = .no_key });
    try expectOutcome(.transcribing, 4, .{ .notice = .failed });
    try expectOutcome(.starting, 64, .{ .notice = .failed });
    try expectOutcome(.starting, 127, .{ .notice = .failed });
    try expectOutcome(.recording, null, .{ .notice = .failed });
    try expectOutcome(.cancelling, 143, .quiet);
    try expectOutcome(.cancelling, 0, .quiet);
    try expectOutcome(.cancelling, null, .quiet);
    std.debug.print("dictation_test: exit 0 inserts, 2/130/143 are quiet, 1 and 3 say why, the rest failed OK\n", .{});

    // ── 검사 15: 비밀번호 프롬프트는 ICANON이 켜지고 ECHO가 꺼진 것이다 ────────
    // 셸의 줄 편집기는 ECHO와 ICANON을 함께 끈다 — 그것을 비밀번호로 읽으면 모든
    // 프롬프트에서 받아쓰기가 막힌다(design 위험 2를 ECHO만으로 고르면 그렇다).
    if (!dictation.isPasswordPrompt(true, false) or dictation.isPasswordPrompt(false, false) or
        dictation.isPasswordPrompt(true, true) or dictation.isPasswordPrompt(false, true))
    {
        std.debug.print("FAIL: isPasswordPrompt is not exactly canonical-without-echo\n", .{});
        return error.WrongPassword;
    }
    std.debug.print("dictation_test: only canonical input without echo is a password prompt OK\n", .{});

    // ── 검사 16: 넣기 전의 거르기 ───────────────────────────────────────
    // `tars-dictate`의 `printable | strip`과 같은 결과여야 한다. 마지막 줄의 기대값이
    // M0 체인 검사 9(s8)의 표준 출력과 글자까지 같다 — 같은 입력을 두 자리에서 걸러도
    // 결과가 하나라는 뜻이다.
    try expectClean("안녕하세요 vd0-dictated", "안녕하세요 vd0-dictated");
    try expectClean(" 앞뒤 공백\n", "앞뒤 공백");
    try expectClean("a\x1b[201~b", "a[201~b");
    try expectClean("a\rb\x7fc", "abc");
    try expectClean("a\tb\nc", "a\tb\nc");
    try expectClean("a\xc2\x85b\xc2\x9fc\xc2\xa0d", "abc\xc2\xa0d");
    try expectClean("한\x1b", "한");
    try expectClean("\x1b\x07\r", "");
    try expectClean("vd0-ctrl a\x1b[201~b\rc\td\ne\xc2\x85f\x1b", "vd0-ctrl a[201~bc\td\nef");
    std.debug.print("dictation_test: C0 but tab and newline, DEL and C1 go, multibyte tails stay, ends are trimmed OK\n", .{});

    std.debug.print("dictation_test: all checks passed\n", .{});
}
```

### 1-2. `terminal/build.zig` — 편집 둘

terminal/build.zig E1 — `old_string`(기준 파일 330줄부터):

```zig
    // `zig build test` = 호스트에서 도는 검사만 빌드해서 실행한다.
```

`new_string`:

```zig
    // dictation_test도 호스트에서 돈다(VD-M1). `clipboard_test`와 같은 자리다 —
    // 더블 탭 판정 · 단계 · 종료 코드 · 비밀번호 판정 · 거르기의 순수 계산이라
    // libc도 번역도 필요 없다. fork · 파이프는 `main.zig`에 있고 게이트가 본다.
    const dictation_test_mod = b.createModule(.{
        .root_source_file = b.path("src/dictation_test.zig"),
        .target = host_target,
        .optimize = optimize,
    });
    const dictation_test = b.addExecutable(.{
        .name = "dictation_test",
        .root_module = dictation_test_mod,
    });
    b.installArtifact(dictation_test);

    // `zig build test` = 호스트에서 도는 검사만 빌드해서 실행한다.
```

terminal/build.zig E2 — `old_string`(기준 파일 347줄부터):

```zig
    test_step.dependOn(&b.addRunArtifact(clipboard_test).step);
```

`new_string`:

```zig
    test_step.dependOn(&b.addRunArtifact(clipboard_test).step);
    test_step.dependOn(&b.addRunArtifact(dictation_test).step);
```


### 1-3. 넣고 확인

```bash
python3 /tmp/run/vd1/apply_plan.py docs/plans/2026-10-06-tars-voice-dictation-vd-m1.md "$PWD" terminal/build.zig
for f in terminal/build.zig terminal/src/dictation.zig terminal/src/dictation_test.zig; do cmp $f /tmp/run/vd1/new/$f && echo "SAME $f"; done
mkdir -p /tmp/run/vd1/impl
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer bash -c \
  'zig build test > /tmp/t.log 2>&1; echo "test exit=$?"; grep -a "dictation_test:" /tmp/t.log | tail -n 3' > /tmp/run/vd1/impl/task1.out 2>&1
rmdir /tmp/run/docker.lock
cat /tmp/run/vd1/impl/task1.out
```

기대: `terminal/build.zig: 2 edit(s)`, `SAME` 셋, `test exit=0`, 그리고 `dictation_test: all checks passed`.

## Task 2: `terminal/src/status.zig` · `status_test.zig`

확정 5. `statusText`가 인자 하나(`dict`)를 더 받는다. `main.zig`의 호출은 Task 4가 고친다 — 그 사이 게스트 바이너리(`zig build`)는 컴파일이
안 되고, 이 Task는 `zig build test`만 본다.

terminal/src/status.zig E1 — `old_string`(기준 파일 3줄부터):

```zig
const input = @import("input.zig");
```

`new_string`:

```zig
const input = @import("input.zig");
const dictation = @import("dictation.zig");
```

terminal/src/status.zig E2 — `old_string`(기준 파일 74줄부터):

```zig
/// 상태 줄이 쓸 수 있는 가장 긴 바이트 수.
```

`new_string`:

```zig
/// 받아쓰기 칸의 글자(VD-M1, design 결정 11). 꼬리의 맨 끝이고, 받아쓰기가 무엇을
/// 하고 있거나 방금 무엇으로 끝났을 때만 뜬다 — `COPY`와 같은 규칙이다. 받아쓰기를
/// 안 쓰는 화면은 한 글자도 안 바뀐다.
///
/// 영어 대문자인 것은 `CAPS` · `COPY`와 같은 줄에 서기 때문이다. 알림 다섯은 사람이
/// 고칠 것을 말한다 — `NO KEY`는 `/config/groq.key`, `NO MIC`는 장치, `PASSWORD`는
/// 비밀번호 프롬프트라 안 넣었다는 것, `NO PANE`은 말을 시작한 패널이 닫혔다는 것이다
/// (글자는 `/config/dictation.jsonl`에 있다). `FAILED`의 까닭은 시리얼의
/// `tars-dictate:` 줄에 있다.
///
/// `else`를 안 단다. `hangulName`과 같은 이유다 — `dictation.Show`에 여섯째 알림을
/// 더하는 사람이 글자를 빼먹으면 그 순간 컴파일 에러가 난다.
fn dictWord(s: dictation.Show) []const u8 {
    return switch (s) {
        .rec => "REC",
        .wait => "WAIT",
        .no_mic => "NO MIC",
        .no_key => "NO KEY",
        .failed => "FAILED",
        .password => "PASSWORD",
        .no_pane => "NO PANE",
    };
}

/// 받아쓰기 칸이 줄에 더하는 바이트. `GAP`을 포함한다. `main.zig`의 `drawStatus`가
/// 꼬리에서 이만큼 물러나 `COPY` · 워크스페이스 · `CAPS`의 자리를 센다 —
/// `COPY_TAIL`과 같은 이유로 길이를 저쪽에 다시 적지 않는다.
pub fn dictTailLen(s: dictation.Show) usize {
    return GAP.len + dictWord(s).len;
}

/// 상태 줄이 쓸 수 있는 가장 긴 바이트 수.
```

terminal/src/status.zig E3 — `old_string`(기준 파일 86줄부터):

```zig
/// 됐다. 버퍼를 손으로 늘린 자리는 셋 다 없다.
```

`new_string`:

```zig
/// 됐고, VD-M1에서 46이 56이 됐다(받아쓰기 칸의 가장 긴 글자 `PASSWORD`). 버퍼를
/// 손으로 늘린 자리는 넷 다 없다.
```

terminal/src/status.zig E4 — `old_string`(기준 파일 96줄부터):

```zig
    break :blk 3 + GAP.len + hl + GAP.len + ll + GAP.len + CAPS.len + WS_TAIL_LEN + COPY_TAIL.len;
```

`new_string`:

```zig
    var dl: usize = 0;
    for (std.enums.values(dictation.Show)) |s| {
        if (dictTailLen(s) > dl) dl = dictTailLen(s);
    }
    break :blk 3 + GAP.len + hl + GAP.len + ll + GAP.len + CAPS.len + WS_TAIL_LEN + COPY_TAIL.len + dl;
```

terminal/src/status.zig E5 — `old_string`(기준 파일 124줄부터):

```zig
/// `buf`는 최소 `MAX_LEN`바이트여야 한다.
pub fn statusText(state: *const input.State, copy: bool, workspace: ?u8, buf: []u8) []const u8 {
```

`new_string`:

```zig
/// `dict`는 받아쓰기 칸이다(VD-M1). null이면 칸이 없다. 무엇을 보일지(단계인지
/// 알림인지)는 부르는 쪽(`main.zig`)이 고른다 — 이 파일은 자식 프로세스를 모른다.
///
/// `buf`는 최소 `MAX_LEN`바이트여야 한다.
pub fn statusText(state: *const input.State, copy: bool, workspace: ?u8, dict: ?dictation.Show, buf: []u8) []const u8 {
```

terminal/src/status.zig E6 — `old_string`(기준 파일 149줄부터):

```zig
    if (copy) len += put(buf, len, COPY_TAIL);
```

`new_string`:

```zig
    if (copy) len += put(buf, len, COPY_TAIL);
    // 받아쓰기 칸이 맨 끝이다(VD-M1). 모드(`COPY`)보다도 뒤인 것은 이 칸만 글자의
    // 길이가 바뀌기 때문이다 — 맨 끝이면 그 길이가 앞 칸들의 자리를 안 흔든다.
    if (dict) |s| {
        len += put(buf, len, GAP);
        len += put(buf, len, dictWord(s));
    }
```


terminal/src/status_test.zig E1 — `old_string`(기준 파일 4줄부터):

```zig
const status = @import("status.zig");
```

`new_string`:

```zig
const status = @import("status.zig");
const dictation = @import("dictation.zig");
```

terminal/src/status_test.zig E2 — `old_string`(기준 파일 16줄부터):

```zig
    const got = status.statusText(&state, copy, null, &buf);
```

`new_string`:

```zig
    const got = status.statusText(&state, copy, null, null, &buf);
```

terminal/src/status_test.zig E3 — `old_string`(기준 파일 56줄부터):

```zig
        const line = status.statusText(&input.State{ .hangul_on = true }, false, null, &buf);
```

`new_string`:

```zig
        const line = status.statusText(&input.State{ .hangul_on = true }, false, null, null, &buf);
```

terminal/src/status_test.zig E4 — `old_string`(기준 파일 80줄부터):

```zig
    // `드보락`(9) + `CAPS`(4) + `W9`(2) + `COPY`(4) + 공백 열 = 46이다.
```

`new_string`:

```zig
    // `드보락`(9) + `CAPS`(4) + `W9`(2) + `COPY`(4) + `PASSWORD`(8) + 공백
    // 열둘 = 56이다.
```

terminal/src/status_test.zig E5 — `old_string`(기준 파일 90줄부터):

```zig
    // 검사는 42 ≠ 46으로 빨갰다.
```

`new_string`:

```zig
    // 검사는 42 ≠ 46으로 빨갰다.
    // VD-M1이 받아쓰기 칸으로 한 번 더 했다 — 가장 긴 글자 `PASSWORD`까지 붙은
    // 56이고, 이 호출에 칸을 넣기 전까지 46 ≠ 56으로 빨갰다.
```

terminal/src/status_test.zig E6 — `old_string`(기준 파일 97줄부터):

```zig
        }, true, 9, &buf);
```

`new_string`:

```zig
        }, true, 9, .password, &buf);
```

terminal/src/status_test.zig E7 — `old_string`(기준 파일 151줄부터):

```zig
        const line = status.statusText(&input.State{}, false, null, &buf);
```

`new_string`:

```zig
        const line = status.statusText(&input.State{}, false, null, null, &buf);
```

terminal/src/status_test.zig E8 — `old_string`(기준 파일 167줄부터):

```zig
        const got = status.statusText(&input.State{}, true, 2, &buf);
```

`new_string`:

```zig
        const got = status.statusText(&input.State{}, true, 2, null, &buf);
```

terminal/src/status_test.zig E9 — `old_string`(기준 파일 172줄부터):

```zig
        const plain = status.statusText(&input.State{}, false, 2, &buf);
```

`new_string`:

```zig
        const plain = status.statusText(&input.State{}, false, 2, null, &buf);
```

terminal/src/status_test.zig E10 — `old_string`(기준 파일 187줄부터):

```zig
        const line = status.statusText(&input.State{}, true, null, &buf);
```

`new_string`:

```zig
        const line = status.statusText(&input.State{}, true, null, null, &buf);
```

terminal/src/status_test.zig E11 — `old_string`(기준 파일 195줄부터):

```zig
    std.debug.print("status_test: all checks passed\n", .{});
```

`new_string`:

```zig
    // ── 검사 17: 받아쓰기 칸의 글자 일곱 (VD-M1) ───────────────────────
    //
    // 표를 옮겨 적는 자리라 하나씩 못 박는다(검사 3~6과 같은 이유). 앞 넷은 한
    // 바이트도 안 바뀌고 꼬리에 `GAP + 글자`가 붙는다.
    {
        const cases = [_]struct { s: dictation.Show, want: []const u8 }{
            .{ .s = .rec, .want = "EN  신세벌 PCS  쿼티  CAPS  REC" },
            .{ .s = .wait, .want = "EN  신세벌 PCS  쿼티  CAPS  WAIT" },
            .{ .s = .no_mic, .want = "EN  신세벌 PCS  쿼티  CAPS  NO MIC" },
            .{ .s = .no_key, .want = "EN  신세벌 PCS  쿼티  CAPS  NO KEY" },
            .{ .s = .failed, .want = "EN  신세벌 PCS  쿼티  CAPS  FAILED" },
            .{ .s = .password, .want = "EN  신세벌 PCS  쿼티  CAPS  PASSWORD" },
            .{ .s = .no_pane, .want = "EN  신세벌 PCS  쿼티  CAPS  NO PANE" },
        };
        for (cases) |cs| {
            var buf: [status.MAX_LEN]u8 = undefined;
            const got = status.statusText(&input.State{}, false, null, cs.s, &buf);
            if (!std.mem.eql(u8, got, cs.want)) {
                std.debug.print("FAIL: got \"{s}\", want \"{s}\"\n", .{ got, cs.want });
                return error.WrongDictWord;
            }
            if (got.len - status.dictTailLen(cs.s) != "EN  신세벌 PCS  쿼티  CAPS".len) {
                std.debug.print("FAIL: dictTailLen(.{s}) does not match the tail it wrote\n", .{@tagName(cs.s)});
                return error.WrongDictTailLen;
            }
        }
        if (std.enums.values(dictation.Show).len != cases.len) {
            std.debug.print("FAIL: dictation.Show has {d} value(s), but only {d} are checked above\n", .{
                std.enums.values(dictation.Show).len, cases.len,
            });
            return error.DictShowCountChanged;
        }
        std.debug.print("status_test: the seven dictation words OK\n", .{});
    }

    // ── 검사 18: 받아쓰기 칸은 꼬리의 맨 끝이다 (VD-M1) ──────────────────
    //
    // 워크스페이스 · `COPY`보다 뒤다. `drawStatus`가 꼬리에서 이 칸의 길이를 먼저
    // 물러나 `COPY`의 시작을 세므로, 순서가 뒤집히면 색이 칸째 밀린다.
    {
        var buf: [status.MAX_LEN]u8 = undefined;
        const want = "한  신세벌 PCS  쿼티  CAPS  W2  COPY  REC";
        const got = status.statusText(&input.State{ .hangul_on = true }, true, 2, .rec, &buf);
        if (!std.mem.eql(u8, got, want)) {
            std.debug.print("FAIL: got \"{s}\", want \"{s}\"\n", .{ got, want });
            return error.WrongDictOrder;
        }
        std.debug.print("status_test: \"{s}\" OK\n", .{got});
    }

    // ── 검사 19: 받아쓰기 칸이 없으면(null) 글자 일곱 어느 것도 없다 (VD-M1) ───
    //
    // 검사 14 · 16과 같은 이유다 — 켜지는 쪽(17)만 보면 "영영 붙어 있는" 코드도
    // 통과한다. `REC`만 보면 다른 여섯이 새는 것을 못 잡는다.
    {
        var buf: [status.MAX_LEN]u8 = undefined;
        const line = status.statusText(&input.State{}, true, 2, null, &buf);
        for ([_][]const u8{ "REC", "WAIT", "NO MIC", "NO KEY", "FAILED", "PASSWORD", "NO PANE" }) |w| {
            if (std.mem.indexOf(u8, line, w) != null) {
                std.debug.print("FAIL: \"{s}\" has {s} without a dictation\n", .{ line, w });
                return error.DictFieldLeaked;
            }
        }
        std.debug.print("status_test: no dictation field without a dictation OK\n", .{});
    }

    std.debug.print("status_test: all checks passed\n", .{});
```


```bash
python3 /tmp/run/vd1/apply_plan.py docs/plans/2026-10-06-tars-voice-dictation-vd-m1.md "$PWD" terminal/src/status.zig terminal/src/status_test.zig
for f in terminal/src/status.zig terminal/src/status_test.zig; do cmp $f /tmp/run/vd1/new/$f && echo "SAME $f"; done
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer bash -c \
  'zig build test > /tmp/t.log 2>&1; echo "test exit=$?"; grep -a "status_test:" /tmp/t.log | tail -n 4; grep -a "MAX_LEN=" /tmp/t.log' > /tmp/run/vd1/impl/task2.out 2>&1
rmdir /tmp/run/docker.lock
cat /tmp/run/vd1/impl/task2.out
```

기대: `6 edit(s)` · `11 edit(s)`, `SAME` 둘, `test exit=0`, 끝 넷이 `the seven dictation words OK` ·
`"한  신세벌 PCS  쿼티  CAPS  W2  COPY  REC" OK` · `no dictation field without a dictation OK` · `all checks passed`다. 그 위 어딘가에
`longest line is exactly MAX_LEN=56 OK`가 있다.

## Task 3: `terminal/src/input.zig` · `input_test.zig`

확정 1 · 3. `Action`에 `dictate`가 생기므로 `input_test`의 헬퍼 다섯이 새 갈래를 받는다(그 `switch`에 `else`가 없어서 컴파일러가 요구한다).
게스트 바이너리는 Task 4까지 컴파일이 안 된다.

terminal/src/input.zig E1 — `old_string`(기준 파일 2줄부터):

```zig
const hangul = @import("hangul.zig");
```

`new_string`:

```zig
const hangul = @import("hangul.zig");
const dictation = @import("dictation.zig");
```

terminal/src/input.zig E2 — `old_string`(기준 파일 303줄부터):

```zig
    swap_alt_meta: bool = false,
```

`new_string`:

```zig
    swap_alt_meta: bool = false,

    /// 받아쓰기가 마이크를 열었거나 여는 중인가(VD-M1). 참이면 수정키 없는 Esc가
    /// 받아쓰기의 취소이고 PTY로 안 간다(VD design 결정 11, Voxio D11a).
    ///
    /// 자식 프로세스의 단계는 `main.zig`만 안다 — 이 파일은 fork도 파이프도 모른다.
    /// DECCKM처럼 `readKeys`를 부를 때의 값을 받는다(`dictation.escCancels`). 한 번의
    /// read 안에서 더블 탭과 Esc가 함께 와도 Esc는 그 앞의 단계로 읽힌다 — 띄운 직후
    /// 같은 read의 Esc는 PTY로 간다. 사람의 손으로는 생기지 않는 순서다.
    dictating: bool = false,
```

terminal/src/input.zig E3 — `old_string`(기준 파일 364줄부터):

```zig
    pane: Pane,
```

`new_string`:

```zig
    pane: Pane,
    /// 받아쓰기 명령(VD-M1). PTY로 보내지 않는다. 자식을 띄우고 시그널을 보내는
    /// 것은 `main.zig`다.
    dictate: Dictate,
};

/// 받아쓰기의 키 명령(VD design 결정 10 · 11). 둘이다.
///
/// `toggle`이 시작인지 끝인지를 여기서 안 가른다. 그것은 자식의 단계로 정해지고
/// (`dictation.onTap`), 단계는 `main.zig`가 든다 — 이 파일이 "녹음 중"을 들면
/// 자식이 스스로 끝났을 때 그 값을 맞출 길이 없다(design 결정 10의 함정 3).
pub const Dictate = enum {
    /// 오른쪽 Cmd 자리의 더블 탭.
    toggle,
    /// 녹음 중의 수정키 없는 Esc. `Context.dictating`이 참일 때만 나온다.
    cancel,
```

terminal/src/input.zig E4 — `old_string`(기준 파일 523줄부터):

```zig
    panes: []const Pane,
```

`new_string`:

```zig
    panes: []const Pane,
    /// 받아쓰기 명령도 같은 모양으로 순서대로 모은다(VD-M1).
    dictates: []const Dictate,
```

terminal/src/input.zig E5 — `old_string`(기준 파일 704줄부터):

```zig
    /// 한글을 치는 중인가(HI design 결정 5). `Mode`에 넣지 않는다 —
```

`new_string`:

```zig
    /// 한 번의 read에서 나온 받아쓰기 명령의 저장소(VD-M1). 같은 이유로 힙을
    /// 안 쓰고, 넘치면 버린다.
    dictates: [8]Dictate = undefined,

    /// 한글을 치는 중인가(HI design 결정 5). `Mode`에 넣지 않는다 —
```

terminal/src/input.zig E6 — `old_string`(기준 파일 767줄부터):

```zig
    lctrl_tap: Tap = .{},
```

`new_string`:

```zig
    lctrl_tap: Tap = .{},

    /// 오른쪽 Cmd 자리의 더블 탭(VD design 결정 10). `Tap`과 다른 판정이다 —
    /// 그쪽은 한 번 누른 길이를, 이쪽은 두 누름 사이를 잰다(`dictation.DoubleTap`).
    dictate_tap: dictation.DoubleTap = .{},
```

terminal/src/input.zig E7 — `old_string`(기준 파일 1302줄부터):

```zig
        if (value != 0) self.markTapConsumed(code);
```

`new_string`:

```zig
        if (value != 0) self.markTapConsumed(code);
        // 0.6번 단계 — 받아쓰기의 더블 탭(VD design 결정 10). 다른 키가 눌리면
        // 진행 중이던 판정을 버린다(Voxio D6 — 중간에 다른 키가 끼면 리셋). 다른
        // 수정키의 누름도 여기서 버린다: Shift를 잡은 채 한 번, 놓고 한 번이 더블
        // 탭이 되지 않게(Voxio `foreignModifierPressDiscardsPendingSequence`).
        // 뗌은 안 버린다 — 누르기 전부터 눌려 있던 키를 떼는 것은 조합이 아니다.
        if (value != 0 and code != c.KEY_RIGHTMETA) self.dictate_tap.reset();
```

terminal/src/input.zig E8 — `old_string`(기준 파일 1350줄부터):

```zig
                self.meta_right = value != 0;
```

`new_string`:

```zig
                self.meta_right = value != 0;
                // 받아쓰기의 트리거(VD design 결정 10). 맞바꿈 뒤의 코드라 Apple
                // 자판은 오른쪽 Cmd, `keyboard=pc`는 오른쪽 Alt다 — 둘 다 스페이스
                // 오른쪽의 Cmd 자리다.
                //
                // 자동 반복(2)은 안 넣는다(design 결정 10의 함정 1). 넣으면 길게 누른
                // 키가 스스로 더블 탭이 된다.
                //
                // 다른 수정키가 눌려 있으면 발동하지 않는다. 왼쪽 Cmd도 다른
                // 수정키다 — 양쪽 Cmd를 함께 잡은 것은 조합이다(Voxio
                // `siblingModifierCountsAsCombo`). CapsLock의 잠금은 수정키가
                // 아니다(Voxio `capsLockAndNumericPadAreNotCombos`).
                //
                // 발동은 둘째 누름에서다. Meta를 누른 채라 아래 1.35번 이후의 갈래는
                // 이 키에 안 닿는다 — 여기서 바로 돌려준다.
                if (value == 1) {
                    const combined = self.shifted() or self.ctrled() or self.alted() or self.meta_left;
                    if (self.dictate_tap.down(time_us, combined)) return .{ .dictate = .toggle };
                } else if (value == 0) {
                    self.dictate_tap.up();
                }
```

terminal/src/input.zig E9 — `old_string`(기준 파일 1392줄부터):

```zig
        if (value == 0) return nothing;
```

`new_string`:

```zig
        if (value == 0) return nothing;

        // 1.3번 단계 — 받아쓰기의 취소(VD design 결정 11). 모드 분기 셋과 한글
        // 층보다 앞이다.
        //
        // 녹음 중의 Esc는 받아쓰기의 것이다. 그 Esc가 뒤의 프로그램까지 가면 취소한
        // 손이 vim의 insert도 끝낸다(Voxio D11a — 탭이 키를 삼키는 유일한 예외). copy
        // mode · 검색 프롬프트 · 한글 조합 어느 것도 그 Esc를 못 본다: copy mode는 그대로
        // 남고, 조합 중이던 글자도 그대로이고, `esc_latin`도 안 돈다 — 사람은 받아쓰기를
        // 그만둔 것이지 입력을 고른 것이 아니다.
        //
        // 수정키 없는 Esc만이다. EL의 `esc_latin`과 같은 선이고, Shift+Esc 같은 조합은
        // 평소의 길로 간다.
        if (ctx.dictating and code == c.KEY_ESC and
            !self.shifted() and !self.ctrled() and !self.alted() and !self.metaed())
        {
            return .{ .dictate = .cancel };
        }
```

terminal/src/input.zig E10 — `old_string`(기준 파일 1643줄부터):

```zig
        .panes = self.panes[0..0],
```

`new_string`:

```zig
        .panes = self.panes[0..0],
        .dictates = self.dictates[0..0],
```

terminal/src/input.zig E11 — `old_string`(기준 파일 1651줄부터):

```zig
    var paned: usize = 0;
```

`new_string`:

```zig
    var paned: usize = 0;
    var dictated: usize = 0;
```

terminal/src/input.zig E12 — `old_string`(기준 파일 1656줄부터):

```zig
            @ptrCast(&raw[i * ev_size]);
```

`new_string`:

```zig
            @ptrCast(&raw[i * ev_size]);
        // 커널의 이벤트 버퍼가 넘쳤다(VD design 결정 10의 함정 2). 그 사이의 이벤트는
        // 사라졌고, 사라진 것이 트리거의 뗌이면 판정이 "첫 누름"에 멈춰 있다 —
        // 버린다(Voxio `recoverFromDroppedEvents`의 toggle 갈래). 수정키 비트가 눌린
        // 채로 남을 수 있는 오래된 구멍(design 실측 12)은 이 milestone의 것이 아니다.
        if (ev.@"type" == c.EV_SYN and ev.code == c.SYN_DROPPED) {
            self.dictate_tap.reset();
            continue;
        }
```

terminal/src/input.zig E13 — `old_string`(기준 파일 1731줄부터):

```zig
                paned += 1;
            },
```

`new_string`:

```zig
                paned += 1;
            },
            // 패널과 같은 모양이다(VD-M1).
            .dictate => |cmd| if (dictated < self.dictates.len) {
                self.dictates[dictated] = cmd;
                dictated += 1;
            },
```

terminal/src/input.zig E14 — `old_string`(기준 파일 1739줄부터):

```zig
        .panes = self.panes[0..paned],
```

`new_string`:

```zig
        .panes = self.panes[0..paned],
        .dictates = self.dictates[0..dictated],
```


terminal/src/input_test.zig E1 — `old_string`(기준 파일 92줄부터):

```zig
    }
}

/// copy 명령이 나오기를 기대한다. 바이트가 오면 실패다 — 그것이 정확히
```

`new_string`:

```zig
        .dictate => |cmd| {
            std.debug.print("FAIL: code={d} -> got dictate .{s}\n", .{ code, @tagName(cmd) });
            return error.UnexpectedDictate;
        },
    }
}

/// copy 명령이 나오기를 기대한다. 바이트가 오면 실패다 — 그것이 정확히
```

terminal/src/input_test.zig E2 — `old_string`(기준 파일 135줄부터):

```zig
    }
}

/// 패널 명령이 나오기를 기대한다(WP-M1). 바이트가 오면 실패다 — 그것이
```

`new_string`:

```zig
        .dictate => |cmd| {
            std.debug.print("FAIL: code={d} -> got dictate .{s}\n", .{ code, @tagName(cmd) });
            return error.UnexpectedDictate;
        },
    }
}

/// 패널 명령이 나오기를 기대한다(WP-M1). 바이트가 오면 실패다 — 그것이
```

terminal/src/input_test.zig E3 — `old_string`(기준 파일 166줄부터):

```zig
            std.debug.print("FAIL: code={d} -> got redraw, want pane .{s}\n", .{ code, @tagName(want) });
            return error.UnexpectedRedraw;
```

`new_string`:

```zig
            std.debug.print("FAIL: code={d} -> got redraw, want pane .{s}\n", .{ code, @tagName(want) });
            return error.UnexpectedRedraw;
        },
        .dictate => |cmd| {
            std.debug.print("FAIL: code={d} -> got dictate .{s}, want pane .{s}\n", .{ code, @tagName(cmd), @tagName(want) });
            return error.UnexpectedDictate;
```

terminal/src/input_test.zig E4 — `old_string`(기준 파일 214줄부터):

```zig
        },
    }
}

/// 한글 층이 이 키를 처리하기를 기대한다(HI-M1). 바이트가 오면 실패다 —
```

`new_string`:

```zig
        },
        .dictate => |cmd| {
            std.debug.print("FAIL: code={d} -> got dictate .{s}\n", .{ code, @tagName(cmd) });
            return error.UnexpectedDictate;
        },
    }
}

/// 한글 층이 이 키를 처리하기를 기대한다(HI-M1). 바이트가 오면 실패다 —
```

terminal/src/input_test.zig E5 — `old_string`(기준 파일 272줄부터):

```zig
    }
    try expectCommit(state, code, want_commit);
```

`new_string`:

```zig
        .dictate => |cmd| {
            std.debug.print("FAIL: code={d} -> got dictate .{s}, want hangul\n", .{ code, @tagName(cmd) });
            return error.UnexpectedDictate;
        },
    }
    try expectCommit(state, code, want_commit);
```

terminal/src/input_test.zig E6 — `old_string`(기준 파일 322줄부터):

```zig
    return ev;
```

`new_string`:

```zig
    return ev;
}

/// 시각이 있는 키 이벤트(VD-M1). 더블 탭은 시각으로 판정하므로 `keyEvent`의
/// 0초로는 `readKeys`를 지나는 검사를 못 쓴다. `eventMicros`가 읽는 두 칸이다.
fn keyEventAt(code: u16, value: i32, us: u64) input.c.struct_input_event {
    var ev = keyEvent(code, value);
    ev.time.tv_sec = @intCast(us / 1_000_000);
    ev.time.tv_usec = @intCast(us % 1_000_000);
    return ev;
}

/// 커널의 이벤트 버퍼가 넘쳤다는 표시(`EV_SYN` · `SYN_DROPPED`).
fn synDropped() input.c.struct_input_event {
    var ev = std.mem.zeroes(input.c.struct_input_event);
    ev.@"type" = input.c.EV_SYN;
    ev.code = input.c.SYN_DROPPED;
    return ev;
}

/// 키 하나가 받아쓰기 명령을 만들기를(또는 아무것도 안 만들기를) 기대한다(VD-M1).
///
/// `want`가 null이면 "받아쓰기의 것이 아니다"이고, 그때는 그 키의 평소 결과(바이트 ·
/// 다시 그리기)를 따지지 않는다 — 트리거 키는 수정키라 평소에 빈 바이트이고, Esc는
/// 0x1b다. 그 둘을 보는 것은 `expect`의 일이다.
fn expectDictate(
    state: *input.State,
    ctx: input.Context,
    code: u16,
    value: i32,
    time_us: u64,
    want: ?input.Dictate,
) !void {
    const got: ?input.Dictate = switch (state.handleKey(code, value, time_us, ctx)) {
        .dictate => |cmd| cmd,
        else => null,
    };
    if (got == want) return;
    std.debug.print("FAIL: code={d} value={d} t={d}us -> dictate {any}, want {any}\n", .{
        code, value, time_us, got, want,
    });
    return error.WrongDictate;
}

/// 트리거 키를 `down_ms`에 누르고 `up_ms`에 뗀다. 둘째 탭은 부르는 쪽이 따로 본다.
fn tap(state: *input.State, ctx: input.Context, code: u16, down_ms: u64, up_ms: u64) !void {
    try expectDictate(state, ctx, code, 1, down_ms * 1000, null);
    try expectDictate(state, ctx, code, 0, up_ms * 1000, null);
```

terminal/src/input_test.zig E7 — `old_string`(기준 파일 2018줄부터):

```zig
    std.debug.print("PASS\n", .{});
```

`new_string`:

```zig
    // ── VD-M1: 받아쓰기의 트리거와 Esc ──────────────────────────────────
    //
    // 판정기 자체(창 · 늦은 탭 · 거꾸로 가는 시각)는 `dictation_test`가 본다. 여기는
    // 그 판정기가 키보드 경로에 붙은 자리 — 어느 키가 트리거이고, 무엇이 판정을
    // 버리고, Esc가 언제 누구의 것인가(design 결정 10의 함정 셋 중 1 · 2).

    // 검사 75. 오른쪽 Cmd의 누름 → 뗌 → 누름이 300ms 안이면 `toggle`이다. 수정키라
    // 바이트는 하나도 안 나간다. 발동은 둘째 누름이고 그 뒤의 뗌은 아무것도 안 한다.
    {
        var vd_s: input.State = .{};
        try tap(&vd_s, .{}, K.KEY_RIGHTMETA, 0, 80);
        try expectDictate(&vd_s, .{}, K.KEY_RIGHTMETA, 1, 200_000, .toggle);
        try expectDictate(&vd_s, .{}, K.KEY_RIGHTMETA, 0, 260_000, null);
        try expectAt(&vd_s, K.KEY_A, 1, 300_000, "a");
    }
    std.debug.print("input_test: 오른쪽 Cmd 더블 탭이 toggle이다 OK\n", .{});

    // 검사 76. 자동 반복(value 2)은 판정에 안 들어간다(함정 1). 길게 누른 키가
    // 스스로 더블 탭이 되지 않고, 길게 누른 뒤 뗀 것은 첫 탭이다 — 창은 첫 누름부터
    // 재므로 그 뒤 300ms를 넘긴 누름은 새 판정의 시작이다.
    {
        var vd_s: input.State = .{};
        try expectDictate(&vd_s, .{}, K.KEY_RIGHTMETA, 1, 0, null);
        try expectDictate(&vd_s, .{}, K.KEY_RIGHTMETA, 2, 100_000, null);
        try expectDictate(&vd_s, .{}, K.KEY_RIGHTMETA, 2, 150_000, null);
        try expectDictate(&vd_s, .{}, K.KEY_RIGHTMETA, 0, 180_000, null);
        try expectDictate(&vd_s, .{}, K.KEY_RIGHTMETA, 1, 250_000, .toggle);
        var vd_r: input.State = .{};
        try expectDictate(&vd_r, .{}, K.KEY_RIGHTMETA, 1, 0, null);
        try expectDictate(&vd_r, .{}, K.KEY_RIGHTMETA, 2, 500_000, null);
        try expectDictate(&vd_r, .{}, K.KEY_RIGHTMETA, 0, 900_000, null);
        try expectDictate(&vd_r, .{}, K.KEY_RIGHTMETA, 1, 1_000_000, null);
    }
    std.debug.print("input_test: 자동 반복은 더블 탭을 안 만든다 OK\n", .{});

    // 검사 77. 왼쪽 Cmd는 트리거가 아니다(Voxio V2). 오른쪽 Alt도 Apple 자판에서는
    // 아니다.
    {
        var vd_s: input.State = .{};
        try tap(&vd_s, .{}, K.KEY_LEFTMETA, 0, 80);
        try expectDictate(&vd_s, .{}, K.KEY_LEFTMETA, 1, 200_000, null);
        try expectDictate(&vd_s, .{}, K.KEY_LEFTMETA, 0, 260_000, null);
        try tap(&vd_s, .{}, K.KEY_RIGHTALT, 1000, 1080);
        try expectDictate(&vd_s, .{}, K.KEY_RIGHTALT, 1, 1_200_000, null);
    }
    std.debug.print("input_test: 왼쪽 Cmd와 Apple 자판의 오른쪽 Alt는 트리거가 아니다 OK\n", .{});

    // 검사 78. `keyboard=pc`면 트리거가 오른쪽 Alt다(design 결정 10 — 맞바꿈 뒤의
    // 코드). PC 자판의 스페이스 오른쪽 첫 키가 그것이다. 맞바꿈이 오른쪽 Win(126)을
    // 오른쪽 Alt로 바꾸므로 그 키는 트리거가 아니다.
    {
        const vd_pc: input.Context = .{ .swap_alt_meta = true };
        var vd_s: input.State = .{};
        try tap(&vd_s, vd_pc, K.KEY_RIGHTALT, 0, 80);
        try expectDictate(&vd_s, vd_pc, K.KEY_RIGHTALT, 1, 200_000, .toggle);
        try expectDictate(&vd_s, vd_pc, K.KEY_RIGHTALT, 0, 260_000, null);
        try tap(&vd_s, vd_pc, K.KEY_RIGHTMETA, 1000, 1080);
        try expectDictate(&vd_s, vd_pc, K.KEY_RIGHTMETA, 1, 1_200_000, null);
    }
    std.debug.print("input_test: keyboard=pc의 트리거는 오른쪽 Alt다 OK\n", .{});

    // 검사 79. 다른 수정키가 눌려 있으면 발동하지 않는다(Voxio D6). Shift · Ctrl ·
    // 왼쪽 Cmd 셋을 하나씩 잡은 채 둘째 누름을 넣는다. 왼쪽 Cmd는 "같은 키의 반대쪽"
    // 이라 공통 비트로는 못 가린다(Voxio `siblingModifierCountsAsCombo`) — 여기서는
    // `meta_left`를 따로 본다.
    for ([_]u16{ K.KEY_LEFTSHIFT, K.KEY_RIGHTCTRL, K.KEY_LEFTMETA }) |vd_held| {
        var vd_s: input.State = .{};
        try tap(&vd_s, .{}, K.KEY_RIGHTMETA, 0, 80);
        try expect(&vd_s, vd_held, 1, "");
        try expectDictate(&vd_s, .{}, K.KEY_RIGHTMETA, 1, 200_000, null);
    }
    std.debug.print("input_test: 다른 수정키를 잡은 둘째 누름은 발동하지 않는다 OK\n", .{});

    // 검사 80. 다른 키의 누름이 끼면 판정을 버린다. 글자 키도, 수정키의 누름도 같다
    // (Voxio `otherKeyDownDiscardsPendingSequence` · `foreignModifierPressDiscardsPendingSequence`).
    // 수정키의 뗌은 안 버린다 — 첫 탭 전부터 잡고 있던 Shift를 놓는 것은 조합이
    // 아니다(Voxio `foreignModifierReleaseKeepsSequence`).
    {
        var vd_s: input.State = .{};
        try tap(&vd_s, .{}, K.KEY_RIGHTMETA, 0, 80);
        try expectAt(&vd_s, K.KEY_A, 1, 120_000, "a");
        try expectDictate(&vd_s, .{}, K.KEY_RIGHTMETA, 1, 200_000, null);
        var vd_m: input.State = .{};
        try tap(&vd_m, .{}, K.KEY_RIGHTMETA, 0, 80);
        try expectAt(&vd_m, K.KEY_LEFTSHIFT, 1, 100_000, "");
        try expectAt(&vd_m, K.KEY_LEFTSHIFT, 0, 120_000, "");
        try expectDictate(&vd_m, .{}, K.KEY_RIGHTMETA, 1, 200_000, null);
        var vd_r: input.State = .{ .shift_left = true };
        try expectAt(&vd_r, K.KEY_LEFTSHIFT, 0, 0, "");
        try tap(&vd_r, .{}, K.KEY_RIGHTMETA, 40, 100);
        try expectDictate(&vd_r, .{}, K.KEY_RIGHTMETA, 1, 200_000, .toggle);
    }
    std.debug.print("input_test: 다른 키의 누름은 판정을 버리고 수정키의 뗌은 안 버린다 OK\n", .{});

    // 검사 81. 대문자 잠금은 수정키가 아니다(Voxio `capsLockAndNumericPadAreNotCombos`).
    // 잠금을 켠 사람에게 트리거가 영영 안 듣는 일이 없어야 한다.
    {
        var vd_s: input.State = .{ .caps_lock = true };
        try tap(&vd_s, .{}, K.KEY_RIGHTMETA, 0, 80);
        try expectDictate(&vd_s, .{}, K.KEY_RIGHTMETA, 1, 200_000, .toggle);
    }
    std.debug.print("input_test: 대문자 잠금을 켜도 트리거가 듣는다 OK\n", .{});

    // 검사 82. Esc는 녹음 중(`Context.dictating`)에만 받아쓰기의 것이다(design 결정 11).
    // 그때는 PTY로 안 가고, copy mode · 한글 조합 · `esc_latin` 어느 것도 그 Esc를 못
    // 본다 — 모드가 그대로이고 조합 중인 글자도 그대로다. 녹음 중이 아니면 Esc는
    // VD 전과 같다. 수정키가 있는 Esc는 녹음 중에도 평소의 길이다.
    {
        const vd_rec: input.Context = .{ .dictating = true };
        var vd_s: input.State = .{};
        try expectDictate(&vd_s, vd_rec, K.KEY_ESC, 1, 0, .cancel);
        try expectDictate(&vd_s, vd_rec, K.KEY_ESC, 0, 50_000, null);
        try expectCtx(&vd_s, .{}, K.KEY_ESC, 1, "\x1b");
        try expect(&vd_s, K.KEY_LEFTSHIFT, 1, "");
        try expectCtx(&vd_s, vd_rec, K.KEY_ESC, 1, "\x1b");
        try expect(&vd_s, K.KEY_LEFTSHIFT, 0, "");

        var vd_cm: input.State = .{ .mode = .copy };
        try expectDictate(&vd_cm, vd_rec, K.KEY_ESC, 1, 0, .cancel);
        if (vd_cm.mode != .copy) {
            std.debug.print("FAIL: the dictation Esc left copy mode (mode=.{s})\n", .{@tagName(vd_cm.mode)});
            return error.DictateEscLeftCopy;
        }
        var vd_hg: input.State = .{ .hangul_layout = .dubeol, .hangul_on = true };
        try expectHangul(&vd_hg, K.KEY_R, "", 'ㄱ');
        try expectDictate(&vd_hg, vd_rec, K.KEY_ESC, 1, 0, .cancel);
        try expectCommit(&vd_hg, K.KEY_ESC, "");
        try expectPreedit(&vd_hg, K.KEY_ESC, 'ㄱ');
        if (!vd_hg.hangul_on) {
            std.debug.print("FAIL: the dictation Esc turned hangul off\n", .{});
            return error.DictateEscLatin;
        }
    }
    std.debug.print("input_test: 녹음 중의 Esc는 취소이고 아무것도 안 건드린다 OK\n", .{});

    // 검사 83. `readKeys`가 받아쓰기 명령을 모으고, `SYN_DROPPED`가 판정을 버린다
    // (함정 2). 사라진 이벤트 안에 다른 키의 누름이 있었을 수 있다 — 버리지 않으면
    // 사람이 그 사이에 친 글자가 있는데도 더블 탭이 된다. 대조군은 같은 이벤트에서
    // `SYN_DROPPED`만 뺀 것이다.
    {
        var vd_s: input.State = .{};
        const vd_evs = [_]input.c.struct_input_event{
            keyEventAt(K.KEY_RIGHTMETA, 1, 0),       keyEventAt(K.KEY_RIGHTMETA, 0, 80_000),
            keyEventAt(K.KEY_RIGHTMETA, 1, 200_000), keyEventAt(K.KEY_RIGHTMETA, 0, 260_000),
        };
        const vd_fds = try feedEvents(&vd_evs);
        defer _ = close(vd_fds[0]);
        var vd_out: [64]u8 = undefined;
        const vd_keys = input.readKeys(&vd_s, vd_fds[0], &vd_out, .{});
        if (vd_keys.dictates.len != 1 or vd_keys.dictates[0] != .toggle or vd_keys.bytes.len != 0) {
            std.debug.print("FAIL: a double tap through readKeys gave {d} dictate(vd_s), {d} byte(vd_s); want 1 toggle, 0\n", .{
                vd_keys.dictates.len, vd_keys.bytes.len,
            });
            return error.ReadKeysDictate;
        }
        var vd_d: input.State = .{};
        const vd_dropped = [_]input.c.struct_input_event{
            keyEventAt(K.KEY_RIGHTMETA, 1, 0), keyEventAt(K.KEY_RIGHTMETA, 0, 80_000),
            synDropped(),                      keyEventAt(K.KEY_RIGHTMETA, 1, 200_000),
        };
        const vd_dfds = try feedEvents(&vd_dropped);
        defer _ = close(vd_dfds[0]);
        const vd_dkeys = input.readKeys(&vd_d, vd_dfds[0], &vd_out, .{});
        if (vd_dkeys.dictates.len != 0) {
            std.debug.print("FAIL: SYN_DROPPED did not discard the pending double tap\n", .{});
            return error.SynDroppedKept;
        }
        var vd_e: input.State = .{};
        const vd_esc = [_]input.c.struct_input_event{
            keyEventAt(K.KEY_ESC, 1, 0), keyEventAt(K.KEY_ESC, 0, 50_000),
        };
        const vd_efds = try feedEvents(&vd_esc);
        defer _ = close(vd_efds[0]);
        const vd_ekeys = input.readKeys(&vd_e, vd_efds[0], &vd_out, .{ .dictating = true });
        if (vd_ekeys.dictates.len != 1 or vd_ekeys.dictates[0] != .cancel or vd_ekeys.bytes.len != 0) {
            std.debug.print("FAIL: Esc while dictating gave {d} dictate(vd_s), {d} byte(vd_s); want 1 cancel, 0\n", .{
                vd_ekeys.dictates.len, vd_ekeys.bytes.len,
            });
            return error.ReadKeysCancel;
        }
    }
    std.debug.print("input_test: readKeys가 받아쓰기 명령을 모으고 SYN_DROPPED가 판정을 버린다 OK\n", .{});

    std.debug.print("PASS\n", .{});
```


```bash
python3 /tmp/run/vd1/apply_plan.py docs/plans/2026-10-06-tars-voice-dictation-vd-m1.md "$PWD" terminal/src/input.zig terminal/src/input_test.zig
for f in terminal/src/input.zig terminal/src/input_test.zig; do cmp $f /tmp/run/vd1/new/$f && echo "SAME $f"; done
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer bash -c \
  'zig build test > /tmp/t.log 2>&1; echo "test exit=$?"; grep -a "input_test:" /tmp/t.log | tail -n 9' > /tmp/run/vd1/impl/task3.out 2>&1
rmdir /tmp/run/docker.lock
cat /tmp/run/vd1/impl/task3.out
```

기대: `14 edit(s)` · `7 edit(s)`, `SAME` 둘, `test exit=0`, 끝 아홉 줄이 검사 75 ~ 83의 `OK`(`오른쪽 Cmd 더블 탭이 toggle이다 OK`부터
`readKeys가 받아쓰기 명령을 모으고 SYN_DROPPED가 판정을 버린다 OK`까지).

## Task 4: `terminal/src/main.zig`

확정 2 · 3 · 4 · 5. 받아쓰기 절(`Dictation` · `startDictation` · `drainDictOut` · `drainDictErr` · `finishDictation` · `insertDictation`)이 포인터
절 바로 앞에 들어가고, `main()`의 poll · 키 · 렌더가 그것을 부른다.

terminal/src/main.zig E1 — `old_string`(기준 파일 2줄부터):

```zig
const clipboard = @import("clipboard.zig");
```

`new_string`:

```zig
const clipboard = @import("clipboard.zig");
const dictation = @import("dictation.zig");
```

terminal/src/main.zig E2 — `old_string`(기준 파일 76줄부터):

```zig
const STATUS_COPY: u32 = 0x00E0E8F0;
```

`new_string`:

```zig
const STATUS_COPY: u32 = 0x00E0E8F0;

/// 받아쓰기 칸의 색(VD-M1). `REC` · `WAIT`와 알림 다섯이 같은 색이다.
///
/// 전용 색인 이유는 `STATUS_COPY`와 같다(CI design 결정 3) — `dumpStatus`가 띠 전체에서
/// 이 색의 픽셀을 세어 `dict ink=`로 찍는데, 다른 칸이 같은 색을 쓰면 그 수가 이 칸만
/// 세지 않는다. 붉은 쪽인 것은 마이크가 열려 있다는 뜻이라서다. 여백 · 상태 줄 색
/// 넷 · 구분선 · 매치 색 둘 · 커서 · 화살표 어느 것과도 다르다.
const STATUS_DICT: u32 = 0x00F07070;
```

terminal/src/main.zig E3 — `old_string`(기준 파일 293줄부터):

```zig
    const copy_len = if (st.copy) status.COPY_TAIL.len else 0;
    const ws_len: usize = if (st.workspace != null) status.WS_TAIL_LEN else 0;
    if (st.text.len < status.CAPS.len + ws_len + copy_len) return;
    const copy_at = st.text.len - copy_len;
```

`new_string`:

```zig
    //
    // VD-M1부터 맨 끝에 받아쓰기 칸이 하나 더 있다 — `… CAPS[  W2][  COPY][  REC]`.
    // 같은 이유로 `st.dict`를 보고 그 길이부터 물러난다. 이 칸만 글자마다 길이가
    // 다르므로(`REC` · `PASSWORD`) 길이를 `status.dictTailLen`에서 받는다.
    const dict_len: usize = if (st.dict) |s| status.dictTailLen(s) else 0;
    const copy_len = if (st.copy) status.COPY_TAIL.len else 0;
    const ws_len: usize = if (st.workspace != null) status.WS_TAIL_LEN else 0;
    if (st.text.len < status.CAPS.len + ws_len + copy_len + dict_len) return;
    const dict_at = st.text.len - dict_len;
    const copy_at = dict_at - copy_len;
```

terminal/src/main.zig E4 — `old_string`(기준 파일 320줄부터):

```zig
    _ = try drawRun(fb, cache, st.text[copy_at..], y, STATUS_COPY, col, fb.width);
```

`new_string`:

```zig
    col = try drawRun(fb, cache, st.text[copy_at..dict_at], y, STATUS_COPY, col, fb.width);
    // 받아쓰기 칸(VD-M1). 받아쓰기가 없으면 빈 슬라이스다.
    _ = try drawRun(fb, cache, st.text[dict_at..], y, STATUS_DICT, col, fb.width);
```

terminal/src/main.zig E5 — `old_string`(기준 파일 572줄부터):

```zig
    workspace: ?u8,
```

`new_string`:

```zig
    workspace: ?u8,
    /// 받아쓰기 칸(VD-M1). 없으면 null이다. `workspace`와 같은 이유로 따로 나른다.
    dict: ?dictation.Show,
```

terminal/src/main.zig E6 — `old_string`(기준 파일 1115줄부터):

```zig
        std.debug.print("terminal: status> copy ink=0 (no room)\n", .{});
```

`new_string`:

```zig
        std.debug.print("terminal: status> copy ink=0 (no room)\n", .{});
        std.debug.print("terminal: status> dict ink=0 (no room)\n", .{});
```

terminal/src/main.zig E7 — `old_string`(기준 파일 1124줄부터):

```zig
    var copy: usize = 0;
```

`new_string`:

```zig
    var copy: usize = 0;
    var dict: usize = 0;
```

terminal/src/main.zig E8 — `old_string`(기준 파일 1133줄부터):

```zig
            if (px == STATUS_COPY) copy += 1;
```

`new_string`:

```zig
            if (px == STATUS_COPY) copy += 1;
            if (px == STATUS_DICT) dict += 1;
```

terminal/src/main.zig E9 — `old_string`(기준 파일 1145줄부터):

```zig
    std.debug.print("terminal: status> copy ink={d}\n", .{copy});
```

`new_string`:

```zig
    std.debug.print("terminal: status> copy ink={d}\n", .{copy});
    // 받아쓰기 칸의 픽셀(VD-M1). `copy ink`와 같은 짝이다 — 녹음 중에 `>0`, 끝난 뒤
    // `=0`을 dictation 체인이 본다. `text=`만 보면 칸을 안 그려도 초록이다.
    std.debug.print("terminal: status> dict ink={d}\n", .{dict});
```

terminal/src/main.zig E10 — `old_string`(기준 파일 1479줄부터):

```zig
        ink,
```

`new_string`:

```zig
        ink,
    });
}

// ── 받아쓰기(VD-M1) ───────────────────────────────────────────────────
//
// 게스트의 `tars-dictate`(VD-M0) 하나를 띄우고, 표준 출력과 표준 에러를 poll로 읽고,
// 끝나면 거둬서 트리거를 누른 패널에 넣는다(VD design 결정 1 · 11). 판단(더블 탭의
// 뜻 · 단계 · 종료 코드 · 비밀번호 · 거르기)은 전부 `dictation.zig`에 있고 여기는
// 시스템 콜과 로그만 다룬다 — 아래 포인터 절과 같은 경계다.
//
// 자식은 언제나 하나다. 둘째 더블 탭은 "하나 더"가 아니라 "끝내라"다
// (`dictation.onTap`). terminal이 녹음 시간을 안 센다 — 상한은 `tars-dictate`의
// `max_seconds`가 지키고, 그렇게 끝나면 자식이 표준 에러로 알린다.
//
// 로그 줄(`terminal: dictate> …`)의 문구가 이 파일과 `dictation/check.sh` 양쪽에 있다.
// 한쪽을 고치면 다른 쪽도 고쳐야 한다. 자식의 표준 에러는 받은 그대로 다시 찍는다 —
// 그 줄(`tars-dictate: …`)의 정본은 M0 plan이고, 받아 적은 글자는 거기 없다.

/// 띄울 프로그램(VD-M0, `make_initrd.sh`가 넣는다). PATH를 안 거친다.
const DICTATE_PATH = "/usr/bin/tars-dictate";

/// 표준 출력을 모으는 상한. `max_seconds`의 상한(600초)을 쉬지 않고 말해도 한글
/// 3,000자 남짓 · 9KB 안팎이다. 넘으면 넣지 않는다 — 잘린 UTF-8을 셸에 쓰지 않는다.
/// 글자는 `/config/dictation.jsonl`에 있다(M0가 표준 출력보다 먼저 쓴다).
const DICTATE_TEXT_MAX = 64 * 1024;

/// 표준 에러 한 줄의 상한. `tars-dictate`의 가장 긴 줄은 HTTP 본문 앞 200바이트를
/// 싣는 실패 줄이다. 넘치면 그 자리에서 끊어 한 줄로 친다.
const DICTATE_LINE_MAX = 512;

/// 받아쓰기 하나의 상태. 자식이 없을 때도 `notice`는 남는다.
const Dictation = struct {
    pid: std.c.pid_t = 0,
    /// null이면 자식이 없다. "녹음 중인가"의 유일한 진실이다(design 결정 10의 함정 3).
    /// 앞으로는 자식의 표준 에러가 옮기고(`dictation.phaseAfter`), null로는 자식의
    /// 끝(두 파이프의 EOF) 하나만 되돌린다. 키가 하는 것은 SIGINT · SIGTERM을 보낸
    /// 사실을 적는 것뿐이다(`transcribing` · `cancelling`).
    phase: ?dictation.Phase = null,
    /// 표준 출력 · 표준 에러의 읽는 쪽. EOF에서 닫고 -1이 된다. poll은 음수 fd를
    /// 건너뛴다.
    out_fd: c_int = -1,
    err_fd: c_int = -1,
    /// 트리거를 누른 순간의 포커스 패널(Voxio D8 1번) — 그 패널 셸의 pid로 든다.
    ///
    /// 패널 포인터나 master fd로 들지 않는다. 워크스페이스가 닫히면 배열이 당겨져
    /// 포인터가 다른 패널을 가리키고(WP-M2 plan 확정 4), 닫힌 패널의 fd 번호는 다음
    /// `open`이 곧바로 다시 쓴다. pid는 커널이 `pid_max`를 한 바퀴 돌기 전에는 다시
    /// 안 준다.
    target: std.c.pid_t = 0,
    text: [DICTATE_TEXT_MAX]u8 = undefined,
    text_len: usize = 0,
    overflow: bool = false,
    line: [DICTATE_LINE_MAX]u8 = undefined,
    line_len: usize = 0,
    /// 끝난 실행이 남긴 알림. 다음 키에 사라진다 — copy mode의 "못 찾음"과 같은
    /// 규칙이고(CS design 결정 9), 시간으로 지우지 않는다(시간 기반 숨김은 PD가 비목표로
    /// 둔 자리다).
    notice: ?dictation.Show = null,

    /// 상태 줄의 받아쓰기 칸. 자식이 있으면 단계가, 없으면 알림이 보인다.
    fn show(self: *const Dictation) ?dictation.Show {
        if (self.phase) |p| return dictation.showOf(p);
        return self.notice;
    }

    fn setNotice(self: *Dictation, s: dictation.Show) void {
        self.notice = s;
        std.debug.print("terminal: dictate> notice {s}\n", .{@tagName(s)});
    }
};

/// 셸의 pid로 패널을 찾는다. 그사이 닫혔으면 null이다.
fn paneByShell(workspaces: *[MAX_WORKSPACES]?Workspace, pid: std.c.pid_t) ?PaneRef {
    for (workspaces, 0..) |*slot, wi| {
        const w = if (slot.*) |*w| w else continue;
        for (&w.panes, 0..) |*pane_slot, leaf| {
            const p = if (pane_slot.*) |*p| p else continue;
            if (p.session.child_pid == pid) return .{ .pane = p, .ws = wi, .leaf = @intCast(leaf) };
        }
    }
    return null;
}

/// 그 패널의 셸 쪽이 비밀번호를 받고 있는가(design 위험 2, `dictation.isPasswordPrompt`).
///
/// master에 `tcgetattr`를 하면 커널이 짝인 slave의 termios를 준다(`tty_mode_ioctl`이
/// master면 `tty->link`를 본다) — ghostty가 같은 자리에서 같은 호출을 한다. 읽기에
/// 실패하면 비밀번호가 아닌 쪽으로 간다. 살아 있는 master에서 실패할 길이 없고,
/// 실패를 막음으로 읽으면 사람이 이유를 모르는 채 받아쓰기가 안 된다.
fn passwordPrompt(master_fd: c_int) bool {
    var t: std.c.termios = undefined;
    if (std.c.tcgetattr(master_fd, &t) != 0) return false;
    return dictation.isPasswordPrompt(t.lflag.ICANON, t.lflag.ECHO);
}

/// 자식을 띄운다(design 결정 1). 실패하면 알림 `failed`이고 terminal은 산다.
///
/// 자식은 제 프로세스 그룹의 우두머리다(`setpgid(0, 0)`, design 결정 6). 시그널을 그룹에
/// 보내야 앞에서 도는 `arecord`가 직접 받는다 — 셸의 Ctrl+C와 같은 모양이다. 부모도
/// 같은 `setpgid`를 부른다. 자식이 그 줄에 닿기 전에 부모가 그룹에 보내면 `ESRCH`로
/// 사라지는 틈을 양쪽에서 닫는 교과서의 모양이다.
///
/// 표준 입력은 `/dev/null`이다. 표준 출력과 표준 에러는 파이프 둘이다 — 출력은 넣을
/// 글자이고(design 결정 6), 에러는 사람이 읽는 줄이자 단계의 재료다. 3번 위의 fd는
/// 전부 닫는다. terminal의 fd(DRM · 키보드 · PTY master)가 자식과 그 손자(`arecord` ·
/// `curl`)에게 새면, terminal이 끝나고 init이 되살린 새 terminal이 여는 DRM을 그 손자가
/// 쥐고 있을 수 있다.
///
/// 환경은 terminal의 것 그대로다(`PATH` · `TERM` · `LANG`, 있으면 `GROQ_API_KEY`).
/// 작업 디렉터리도 그대로다 — `tars-dictate`는 절대 경로만 쓴다.
fn startDictation(d: *Dictation, pane: *const Pane, ws: usize, leaf: u4) void {
    var out_pipe: [2]c_int = undefined;
    var err_pipe: [2]c_int = undefined;
    if (std.c.pipe2(&out_pipe, .{ .CLOEXEC = true }) != 0) return spawnFailed(d, "pipe2");
    if (std.c.pipe2(&err_pipe, .{ .CLOEXEC = true }) != 0) {
        _ = std.c.close(out_pipe[0]);
        _ = std.c.close(out_pipe[1]);
        return spawnFailed(d, "pipe2");
    }
    const pid = std.c.fork();
    if (pid < 0) {
        for ([_]c_int{ out_pipe[0], out_pipe[1], err_pipe[0], err_pipe[1] }) |fd| _ = std.c.close(fd);
        return spawnFailed(d, "fork");
    }
    if (pid == 0) {
        // 자식. `execve`까지 시스템 콜만 부른다 — fork한 프로세스가 안전하게 할 수 있는
        // 것이 그것뿐이다.
        _ = std.c.setpgid(0, 0);
        _ = std.c.dup2(out_pipe[1], 1);
        _ = std.c.dup2(err_pipe[1], 2);
        const devnull = std.c.open("/dev/null", .{ .ACCMODE = .RDONLY });
        if (devnull >= 0) _ = std.c.dup2(devnull, 0);
        _ = std.os.linux.close_range(3, std.math.maxInt(std.os.linux.fd_t), .{ .UNSHARE = false, .CLOEXEC = false });
        const argv = [_:null]?[*:0]const u8{"tars-dictate"};
        _ = std.c.execve(DICTATE_PATH, &argv, std.c.environ);
        std.c._exit(127);
    }
    _ = std.c.setpgid(pid, pid);
    _ = std.c.close(out_pipe[1]);
    _ = std.c.close(err_pipe[1]);
    d.pid = pid;
    d.phase = .starting;
    d.out_fd = out_pipe[0];
    d.err_fd = err_pipe[0];
    d.target = pane.session.child_pid;
    d.text_len = 0;
    d.overflow = false;
    d.line_len = 0;
    d.notice = null;
    std.debug.print("terminal: dictate> start pid={d} ws={d} leaf={d}\n", .{ pid, ws + 1, leaf });
}

fn spawnFailed(d: *Dictation, what: []const u8) void {
    std.debug.print("terminal: dictate> spawn failed at {s} error={s}\n", .{ what, @tagName(std.c.errno(-1)) });
    d.setNotice(.failed);
}

/// 자식의 프로세스 그룹에 시그널을 보낸다(design 결정 6).
fn signalDictation(d: *const Dictation, sig: std.c.SIG) void {
    _ = std.c.kill(-d.pid, sig);
}

/// 표준 출력에서 한 번 읽는다. poll이 읽을 것이 있다고 알린 뒤에만 부른다. EOF면 닫는다.
fn drainDictOut(d: *Dictation) void {
    var scratch: [4096]u8 = undefined;
    const room = d.text[d.text_len..];
    const dst = if (room.len > 0) room else scratch[0..];
    const n = std.c.read(d.out_fd, dst.ptr, dst.len);
    if (n <= 0) {
        _ = std.c.close(d.out_fd);
        d.out_fd = -1;
        return;
    }
    if (room.len > 0) d.text_len += @intCast(n) else d.overflow = true;
}

/// 표준 에러에서 한 번 읽어 줄로 나눈다. EOF면 남은 조각을 한 줄로 치고 닫는다.
fn drainDictErr(d: *Dictation) void {
    var buf: [1024]u8 = undefined;
    const n = std.c.read(d.err_fd, &buf, buf.len);
    if (n <= 0) {
        if (d.line_len > 0) dictLine(d);
        _ = std.c.close(d.err_fd);
        d.err_fd = -1;
        return;
    }
    for (buf[0..@intCast(n)]) |b| {
        if (b == '\n') {
            dictLine(d);
            continue;
        }
        if (d.line_len == d.line.len) dictLine(d);
        d.line[d.line_len] = b;
        d.line_len += 1;
    }
}

/// 자식의 한 줄. 받은 그대로 시리얼에 다시 찍고, 단계를 옮긴다.
fn dictLine(d: *Dictation) void {
    const line = d.line[0..d.line_len];
    d.line_len = 0;
    std.debug.print("{s}\n", .{line});
    const p = d.phase orelse return;
    const next = dictation.phaseAfter(p, line);
    if (next == p) return;
    d.phase = next;
    std.debug.print("terminal: dictate> phase {s}\n", .{@tagName(next)});
}

/// 두 파이프가 다 닫혔다 — 자식이 끝났다. 거두고 종료 코드대로 한다.
///
/// `waitpid`가 막을 수 있는데 짧다. 두 파이프의 EOF는 자식과 그 손자가 쥐던 쓰는 쪽이
/// 전부 닫혔다는 뜻이라 자식은 이미 끝났거나 끝나는 중이다(`pty.close`와 같은 판단).
fn finishDictation(
    d: *Dictation,
    workspaces: *[MAX_WORKSPACES]?Workspace,
    current: usize,
    key_state: *input.State,
) void {
    var status_word: c_int = 0;
    _ = std.c.waitpid(d.pid, &status_word, 0);
    const w: u32 = @bitCast(status_word);
    const code: ?u8 = if (std.c.W.IFEXITED(w)) std.c.W.EXITSTATUS(w) else null;
    if (code) |c_| {
        std.debug.print("terminal: dictate> exit code={d}\n", .{c_});
    } else {
        std.debug.print("terminal: dictate> exit signal={d}\n", .{std.c.W.TERMSIG(w)});
    }
    const phase = d.phase.?;
    d.phase = null;
    d.pid = 0;
    switch (dictation.outcome(phase, code)) {
        .quiet => {},
        .notice => |s| d.setNotice(s),
        .insert => {
            if (d.overflow) {
                std.debug.print("terminal: dictate> text over {d} bytes, not inserted\n", .{DICTATE_TEXT_MAX});
                return d.setNotice(.failed);
            }
            insertDictation(d, workspaces, current, key_state);
        },
    }
}

/// 받아 적은 글자를 트리거를 누른 패널에 넣는다(design 결정 11).
///
/// 순서가 판단이다. 패널이 남아 있는가 → 그 패널이 비밀번호를 받고 있는가 → 거르고
/// 남은 것이 있는가 → 넣는다. 앞의 둘에 걸리면 넣지 않고 알린다. 글자는 버려지지
/// 않는다 — `tars-dictate`가 이미 `/config/dictation.jsonl`에 남겼다(Voxio 불변식 1).
///
/// 넣는 길은 `Cmd+V`와 같다(`pasteParts`, PE design 결정 2). 자식이 모드 2004를 켰으면
/// bracketed paste라 Enter 전에는 안 돈다. 클립보드는 안 만진다(design 결정 11).
///
/// 그 패널이 포커스이고 한글을 조합 중이면 그 글자를 먼저 확정해 보낸다. 조합은 사람이
/// 넣기 전에 친 것이므로 셸에도 먼저 가야 한다 — `Cmd+V`가 1.35번 단계에서 하는 일과
/// 같다. `pointerMode(.normal)`은 normal에서 normal로 가며 확정만 한다.
fn insertDictation(
    d: *Dictation,
    workspaces: *[MAX_WORKSPACES]?Workspace,
    current: usize,
    key_state: *input.State,
) void {
    const ref = paneByShell(workspaces, d.target) orelse {
        std.debug.print("terminal: dictate> no pane shell={d}\n", .{d.target});
        return d.setNotice(.no_pane);
    };
    const fd = ref.pane.session.master_fd;
    if (passwordPrompt(fd)) {
        std.debug.print("terminal: dictate> refused password at=insert ws={d} leaf={d}\n", .{ ref.ws + 1, ref.leaf });
        return d.setNotice(.password);
    }
    const text = dictation.sanitize(d.text[0..d.text_len]);
    if (text.len == 0) {
        std.debug.print("terminal: dictate> nothing left to insert\n", .{});
        return;
    }
    const w = &workspaces[current].?;
    if (ref.ws == current and ref.leaf == w.focus and key_state.mode == .normal and key_state.preedit() != null) {
        pty.write(fd, key_state.pointerMode(.normal));
        ref.pane.screen.setPreedit(null);
    }
    const parts = ref.pane.screen.pasteParts(text);
    for (parts) |p| {
        if (p.len > 0) pty.write(fd, p);
    }
    std.debug.print("terminal: dictate> insert len={d} bracketed={d} ws={d} leaf={d}\n", .{
        text.len, @intFromBool(parts[0].len > 0), ref.ws + 1, ref.leaf,
```

terminal/src/main.zig E11 — `old_string`(기준 파일 2424줄부터):

```zig
    // 포인터 장치(PD-M0). 키보드와 달리 terminal이 스스로 찾고, 부팅 뒤에
```

`new_string`:

```zig
    // 받아쓰기(VD-M1). 자식이 없으면 `phase`가 null이다.
    var dict: Dictation = .{};
    // terminal이 끝나면(마지막 패널이 닫혔다) 자식도 끝낸다. 안 그러면 녹음이 상한까지
    // 돌고 그동안 마이크가 열려 있다. 거두지는 않는다 — 고아는 init이 거둔다.
    defer if (dict.phase != null) signalDictation(&dict, .TERM);

    // 포인터 장치(PD-M0). 키보드와 달리 terminal이 스스로 찾고, 부팅 뒤에
```

terminal/src/main.zig E12 — `old_string`(기준 파일 2486줄부터):

```zig
    var fds: [2 + pointer.MAX_DEVICES + MAX_WORKSPACES * layout.MAX_LEAVES]c.struct_pollfd = undefined;
```

`new_string`:

```zig
    //
    // 맨 뒤 두 칸이 받아쓰기의 표준 출력 · 표준 에러다(VD-M1). 자식이 없으면 -1이다.
    var fds: [2 + pointer.MAX_DEVICES + MAX_WORKSPACES * layout.MAX_LEAVES + 2]c.struct_pollfd = undefined;
```

terminal/src/main.zig E13 — `old_string`(기준 파일 2519줄부터):

```zig

        // -1 = 무한 대기. 이벤트가 없으면 CPU를 전혀 쓰지 않는다.
```

`new_string`:

```zig
        const pty_end = nfds;
        fds[nfds] = .{ .fd = dict.out_fd, .events = c.POLLIN, .revents = 0 };
        fds[nfds + 1] = .{ .fd = dict.err_fd, .events = c.POLLIN, .revents = 0 };
        nfds += 2;

        // -1 = 무한 대기. 이벤트가 없으면 CPU를 전혀 쓰지 않는다.
```

terminal/src/main.zig E14 — `old_string`(기준 파일 2545줄부터):

```zig
            };
            const keys = input.readKeys(&key_state, keyboard_fd, &key_buf, ctx);
```

`new_string`:

```zig
                // 받아쓰기가 Esc를 가져가는가(VD-M1). 이 바퀴의 단계로 읽는다.
                .dictating = dictation.escCancels(dict.phase),
            };
            const keys = input.readKeys(&key_state, keyboard_fd, &key_buf, ctx);
            // 받아쓰기의 알림은 다음 키에 사라진다(VD-M1). "키"는 무언가를 한 키다 —
            // 수정키를 누르고 떼기만 한 배치는 안 센다. 그렇지 않으면 더블 탭의 마지막
            // 뗌이 방금 뜬 `PASSWORD`를 바로 지운다.
            if (dict.notice != null and (keys.bytes.len > 0 or keys.scrolls.len > 0 or
                keys.copies.len > 0 or keys.panes.len > 0 or keys.dictates.len > 0 or keys.redraw))
            {
                dict.notice = null;
                needs_redraw = true;
            }
```

terminal/src/main.zig E15 — `old_string`(기준 파일 2775줄부터):

```zig
                needs_redraw = true;
            }
        }
```

`new_string`:

```zig
                needs_redraw = true;
            }
            // 받아쓰기 명령(VD-M1). 패널 명령 뒤다 — 같은 배치에서 포커스가 옮겨졌으면
            // 옮긴 뒤의 패널이 대상이다. 그래서 `focus` 변수가 아니라 `ws.focus`로 다시
            // 구한다(패널 명령이 `ws`는 고치고 `focus`는 안 고친다).
            //
            // 시작하기 전에 그 패널이 비밀번호를 받고 있는지 본다(design 위험 2). 그렇다면
            // 마이크를 안 연다 — Voxio가 비밀번호 칸에서 녹음을 안 시작한 것과 같다(V10).
            // 넣을 때 한 번 더 본다(`insertDictation`). 말하는 사이에 `sudo`가 뜰 수 있다.
            for (keys.dictates) |cmd| {
                switch (cmd) {
                    .toggle => switch (dictation.onTap(dict.phase)) {
                        .start => {
                            const tp = &ws.panes[ws.focus].?;
                            if (passwordPrompt(tp.session.master_fd)) {
                                std.debug.print("terminal: dictate> refused password at=start ws={d} leaf={d}\n", .{ current + 1, ws.focus });
                                dict.setNotice(.password);
                            } else {
                                startDictation(&dict, tp, current, ws.focus);
                            }
                        },
                        .stop => {
                            signalDictation(&dict, .INT);
                            dict.phase = .transcribing;
                            std.debug.print("terminal: dictate> stop pid={d}\n", .{dict.pid});
                        },
                        .ignore => std.debug.print("terminal: dictate> ignored phase={s}\n", .{
                            if (dict.phase) |p| @tagName(p) else "none",
                        }),
                    },
                    // 녹음 중의 Esc(design 결정 11). `ctx.dictating`이 참일 때만 오지만,
                    // 같은 배치의 앞 키가 단계를 바꿨을 수 있어 한 번 더 본다.
                    .cancel => if (dictation.escCancels(dict.phase)) {
                        signalDictation(&dict, .TERM);
                        dict.phase = .cancelling;
                        std.debug.print("terminal: dictate> cancel pid={d}\n", .{dict.pid});
                    },
                }
                needs_redraw = true;
            }
        }
```

terminal/src/main.zig E16 — `old_string`(기준 파일 2855줄부터):

```zig
        for (fds[pty_base..nfds], fd_panes[0 .. nfds - pty_base]) |pfd, ref| {
```

`new_string`:

```zig
        for (fds[pty_base..pty_end], fd_panes[0 .. pty_end - pty_base]) |pfd, ref| {
```

terminal/src/main.zig E17 — `old_string`(기준 파일 2946줄부터):

```zig
            if (pane.screen.copyTakePruned()) dumpCopy(pane.screen, "pruned");
            needs_redraw = true;
```

`new_string`:

```zig
            if (pane.screen.copyTakePruned()) dumpCopy(pane.screen, "pruned");
            needs_redraw = true;
        }

        // 받아쓰기의 파이프 둘(VD-M1). PTY 뒤 · 렌더 앞이다 — 위 PTY 루프가 대상 패널을
        // 닫았으면 그것을 본 뒤에 넣을지 정한다. 두 파이프가 다 닫히면 자식이 끝난
        // 것이고, 거두고 넣는다.
        //
        // 다시 그리는 것은 상태 줄의 칸이 바뀌었을 때뿐이다. 표준 출력을 읽을 때마다
        // 그리면 `screen>` 덤프가 그만큼 는다. 넣은 글자는 셸이 되울리고, 그 출력이 다음
        // 바퀴의 PTY 루프에서 다시 그리게 한다.
        if (dict.phase != null) {
            const shown = dict.show();
            if (dict.out_fd >= 0 and fds[pty_end].revents != 0) drainDictOut(&dict);
            if (dict.err_fd >= 0 and fds[pty_end + 1].revents != 0) drainDictErr(&dict);
            if (dict.out_fd < 0 and dict.err_fd < 0) finishDictation(&dict, &workspaces, current, &key_state);
            if (!std.meta.eql(shown, dict.show())) needs_redraw = true;
```

terminal/src/main.zig E18 — `old_string`(기준 파일 3046줄부터):

```zig
            .text = status.statusText(&key_state, copy_active, ws_number, &status_buf),
```

`new_string`:

```zig
            .text = status.statusText(&key_state, copy_active, ws_number, dict.show(), &status_buf),
```

terminal/src/main.zig E19 — `old_string`(기준 파일 3052줄부터):

```zig
            .workspace = ws_number,
```

`new_string`:

```zig
            .workspace = ws_number,
            .dict = dict.show(),
```


```bash
python3 /tmp/run/vd1/apply_plan.py docs/plans/2026-10-06-tars-voice-dictation-vd-m1.md "$PWD" terminal/src/main.zig
cmp terminal/src/main.zig /tmp/run/vd1/new/terminal/src/main.zig && echo "SAME main.zig"
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer bash -c \
  'rm -rf .zig-cache zig-out; zig build > /tmp/b.log 2>&1; echo "build exit=$?"; grep -aE "error" /tmp/b.log | head -n 5
   zig build test > /tmp/t.log 2>&1; echo "test exit=$?"; ls -l zig-out/bin/terminal | cut -c1-10' > /tmp/run/vd1/impl/task4.out 2>&1
rmdir /tmp/run/docker.lock
cat /tmp/run/vd1/impl/task4.out
```

기대: `19 edit(s)`, `SAME main.zig`, `build exit=0`(에러 줄 없음), `test exit=0`, `-rwxr-xr-x`. 캐시를 지우는 것은 `project_zig_out_staleness` —
같은 `docker run` 안에서 지운다(lessons "캐시는 컨테이너 안에서 지운다").

## Task 5: `dictation/check.sh` · 체인 · regression

확정 6 · 7 · 9.

### 5-1. 편집

dictation/check.sh E1 — `old_string`(기준 파일 26줄부터):

```bash
# 이 체인이 못 보는 것 — 진짜 Groq의 답(사람이 키를 넣고 실기에서 본다, running-tars.md) ·
# 실기 마이크의 소리 · 터미널이 글자를 커서 자리에 넣는 것(VD-M1).

# $GUEST_MEM 하나 때문에 source한다. audio 체인처럼 타이핑을 안 한다.
```

`new_string`:

```bash
# 부팅 B(VD-M1)는 terminal이 하는 일을 본다 — 오른쪽 Cmd 두 번(monitor의 sendkey meta_r 둘)이
# tars-dictate를 띄우고, 상태 줄 꼬리에 REC가 뜨고, 다시 두 번이 녹음을 끝내고, 받은 글자가
# 그 패널의 셸 프롬프트에 들어간다(bracketed paste, Enter 없음). Esc 취소 · 비밀번호 프롬프트 ·
# 다른 패널 · 닫힌 패널 · 상한으로 스스로 멈춘 녹음 · 키 없음을 차례로 친다. 판정은 terminal의
# `dictate>` · `status>` 줄과 화면 줄, stub이 받은 요청, 끈 뒤의 dictation.jsonl이다.
#
# 이 체인이 못 보는 것 — 진짜 Groq의 답(사람이 키를 넣고 실기에서 본다, running-tars.md) ·
# 실기 마이크의 소리 · 실기 자판의 오른쪽 Cmd(PC 자판은 오른쪽 Alt — input_test 검사 78).

# 부팅 A는 $GUEST_MEM 하나 때문에, 부팅 B는 타이핑(type_keys · joined_screen_dump)
# 때문에 source한다.
```

dictation/check.sh E2 — `old_string`(기준 파일 34줄부터):

```bash
TLS_PORT=45492
```

`new_string`:

```bash
TLS_PORT=45492
# 부팅 B의 QEMU monitor(VD-M1). 45492가 TLS 상대라 그다음 번호다.
MONITOR_PORT_B=45493
```

dictation/check.sh E3 — `old_string`(기준 파일 51줄부터):

```bash
if ! (cd ../kernel && ./make_initrd.sh); then
```

`new_string`:

```bash
# 받아쓰기의 판정기 · 단계 · 종료 코드 · 비밀번호 · 거르기(dictation_test)와 트리거 ·
# Esc의 키 경로(input_test)는 여기서 먼저 걸러진다 — 부팅 둘을 쓰기 전에 잡을 수 있는
# 실패다.
if ! (cd ../terminal && zig build test); then
  echo "FAIL: terminal host tests failed (dictation_test, input_test or status_test)"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
```

dictation/check.sh E4 — `old_string`(기준 파일 63줄부터):

```bash
cleanup() {
```

`new_string`:

```bash
cleanup() {
  exec 3<&- 2>/dev/null
  exec 3>&- 2>/dev/null
```

dictation/check.sh E5 — `old_string`(기준 파일 375줄부터):

```bash
echo "VD check PASS"
```

`new_string`:

```bash
# ════════════════════════════════════════════════════════════════════════
# 부팅 B — terminal의 트리거 · 상태 · 삽입 (VD-M1)
# ════════════════════════════════════════════════════════════════════════
#
# 사람이 하는 일을 monitor로 한다. 셸은 기본값 fish다(프롬프트 `root@(none) ~#`).
#
# 더블 탭은 `sendkey meta_r 80` 둘을 잇달아 보내는 것이다. sendkey는 누르고 hold(80ms) 뒤에
# 떼고, QEMU는 그 뗌을 입력 큐에 지연과 함께 넣는다 — 둘째 sendkey의 누름은 그 뒤에 줄을
# 선다. 그래서 둘째 누름이 첫 누름 뒤 90ms 남짓에 온다(창 300ms 안, VD-M1 plan 확정 9가 evdev
# 시각으로 쟀다). hold를 적는 것은 사람의 손에 가깝게 하려는 것이다 — 안 적으면 누른 시간이
# 10ms 안팎이고 두 누름 사이가 20ms 남짓이었다. type_keys를 안 쓴다 — 수정키 하나는 로그를 한
# 줄도 안 만들어 type_keys가 키마다 0.3초를 기다리고, 그러면 둘째 누름이 창 밖이다.
#
# 화면은 마지막 프레임만 본다(`last_screen`). wait_for_screen은 로그의 모든 프레임을 훑으므로
# 지운 줄이나 다른 패널의 지난 프레임에 걸린다.
DISK_B=../out/dictation-b.img
STUBLOG_B="$WORK/stub_b.log"
rm -f "$LOG"
LOG="$(mktemp)"

mkdir -p "$WORK/seed_b"
printf 'net=dhcp\n' > "$WORK/seed_b/tars.conf"
printf 'vd1-test-key\n' > "$WORK/seed_b/groq.key"
printf '%s\n' '# written by the VD chain, boot B' 'transcribe_url = http://10.0.2.100:8080/ok/b' \
  > "$WORK/seed_b/dictation.conf"
# 사람이 셸에서 칠 것을 짧게 줄인 셋이다 — 타이핑 한 글자가 sendkey 하나라서다.
#   vd-pw     비밀번호 프롬프트. bash의 read -s는 줄 단위로 읽으며 안 보여 준다
#             (ICANON 켜짐 · ECHO 꺼짐). 받은 것을 대괄호 안에 되보여 준다
#   vd-cap    설정을 고친다 — 1초에서 스스로 멈추는 녹음(키 없이 끝나는 길)
#   vd-nokey  키 파일을 치운다
printf '%s\n' '#!/usr/bin/bash' "read -rsp 'pw> ' x" 'echo' 'echo "got[$x]"' > "$WORK/seed_b/vd-pw"
printf '%s\n' '#!/usr/bin/bash' \
  "printf '%s\\n' 'transcribe_url = http://10.0.2.100:8080/ok/cap' 'max_seconds = 1' > /config/dictation.conf" \
  > "$WORK/seed_b/vd-cap"
printf '%s\n' '#!/usr/bin/bash' 'mv /config/groq.key /config/groq.key.off' > "$WORK/seed_b/vd-nokey"
chmod 0755 "$WORK/seed_b/vd-pw" "$WORK/seed_b/vd-cap" "$WORK/seed_b/vd-nokey"
rm -f "$DISK_B"
truncate -s 16M "$DISK_B"
mkfs.ext2 -F -q -m 0 -L tars-dictate -d "$WORK/seed_b" "$DISK_B"

report_b() {
  echo "FAIL(boot B): $1"
  echo "--- dictation lines ---"
  grep -aE 'terminal: dictate>|tars-dictate:' "$LOG" | tr -d '\r' | tail -n 40
  echo "--- status lines ---"
  grep -aE 'terminal: status> (text=|dict ink)' "$LOG" | tr -d '\r' | tail -n 12
  echo "--- stub (boot B) ---"
  cat "$STUBLOG_B" 2>/dev/null
  echo "--- last screen ---"
  last_screen | tr -d '\r' | tr '|' '\n' | tail -n 15
  echo "--- last 30 lines ---"
  tail -n 30 "$LOG"
  exit 1
}

# 패턴에 맞는 줄의 수.
count_b() { grep -acE -- "$1" "$LOG" || true; }
# 그 수가 want가 될 때까지 0.1초 간격으로 기다린다. 상한은 초.
wait_count() {
  local pattern="$1" want="$2" secs="$3" i
  for i in $(seq 1 $((secs * 10))); do
    [ "$(count_b "$pattern")" -ge "$want" ] && return 0
    kill -0 "$QEMU_PID" 2>/dev/null || return 1
    sleep 0.1
  done
  return 1
}
# 상태 줄의 마지막 글자와 받아쓰기 칸의 마지막 픽셀 수.
last_status() { grep -a 'terminal: status> text=' "$LOG" | tail -n 1 | tr -d '\r' | sed -E 's/.*text=//'; }
last_dict_ink() { grep -a 'terminal: status> dict ink=' "$LOG" | tail -n 1 | tr -d '\r' | sed -E 's/.*ink=([0-9]+).*/\1/'; }
# 상태 줄이 패턴(ERE, 줄 끝까지)과 맞을 때까지 기다린다.
wait_status() {
  local pattern="$1" secs="$2" i
  for i in $(seq 1 $((secs * 10))); do
    grep -aE -- "$pattern" <<<"$(last_status)" >/dev/null && return 0
    sleep 0.1
  done
  return 1
}
# 받아쓰기 칸의 픽셀이 켜지거나(on, >0) 꺼질(off, =0) 때까지 기다린다. `dumpStatus`가
# `text=` 줄 뒤에 `dict ink=` 줄을 찍으므로, `text=`를 본 순간의 마지막 `dict ink`는 앞
# 프레임의 것일 수 있다.
wait_dict_ink() {
  local want="$1" i v
  for i in $(seq 1 50); do
    v="$(last_dict_ink)"
    if [ -n "$v" ]; then
      [ "$want" = on ] && [ "$v" -gt 0 ] && return 0
      [ "$want" = off ] && [ "$v" -eq 0 ] && return 0
    fi
    sleep 0.1
  done
  return 1
}
# 마지막 프레임의 화면 줄(포커스 패널).
last_screen() { joined_screen_dump | tail -n 1; }
wait_last_screen() {
  local pattern="$1" secs="$2" i
  for i in $(seq 1 $((secs * 10))); do
    grep -aE -- "$pattern" <<<"$(last_screen)" >/dev/null && return 0
    sleep 0.1
  done
  return 1
}
# 마지막 프레임에 그 글자가 몇 번 있는가.
last_screen_count() { last_screen | grep -oaF -- "$1" | wc -l; }
stub_b_count() { local n; n="$(grep -ac '^stub: POST ' "$STUBLOG_B" 2>/dev/null)"; echo "${n:-0}"; }
double_tap() {
  echo "sendkey meta_r 80" >&3
  echo "sendkey meta_r 80" >&3
  sleep 0.6
}
# 녹음이 시작됐다(n번째 start와 n번째 recording 줄).
expect_recording() {
  wait_count 'terminal: dictate> start pid=' "$1" 15 || report_b "$2: the double tap started no dictation (want start #$1)"
  wait_count 'terminal: dictate> phase recording' "$1" 15 || report_b "$2: tars-dictate never said it was recording"
}
PROMPT='root@\(none\) ~#'
TEXT='안녕하세요 vd0-dictated'

echo "=== boot B: the terminal triggers, shows and inserts (monitor ${MONITOR_PORT_B}) ==="
HOME="$WORK" qemu-system-x86_64 \
  -machine q35 \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -drive file="$DISK_B",if=virtio,format=raw \
  -netdev "user,id=n0,guestfwd=tcp:10.0.2.100:8080-cmd:perl $PWD/stub.pl $STUBLOG_B" \
  -device virtio-net-pci,netdev=n0 \
  -audiodev alsa,id=snd0,out.dev=tarstap,in.dev=tarsfeed,out.frequency=48000,in.frequency=48000,out.channels=2,in.channels=2,out.format=s16,in.format=s16,out.try-poll=off,in.try-poll=off \
  -device ich9-intel-hda \
  -device hda-micro,audiodev=snd0 \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT_B},server,nowait \
  -no-reboot &
QEMU_PID=$!

wait_for_log 'terminal: screen>' 120 || report_b "terminal never rendered"
wait_last_screen "$PROMPT" 30 || report_b "the fish prompt never showed up"
# 전사 API(stub)에 닿는 길과 켜진 마이크. 부팅 A의 프로브가 기다린 것과 같다.
wait_for_log 'eth0: adding default route via 10\.0\.2\.2' 60 || report_b "dhcpcd never added the default route"
wait_for_log 'tars-init: audio: alsactl init turned the mixer on' 60 || report_b "the boot never turned the mixer on"
CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT_B}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = 1 ] || report_b "could not connect to the QEMU monitor"
case "$(last_status)" in
  *"  REC"|*"  WAIT"|*"  NO "*|*"  FAILED"|*"  PASSWORD") report_b "the status line has a dictation field before any dictation ($(last_status))" ;;
esac

# ── 검사 14: 한 번 탭과 늦은 둘째 탭은 아무것도 안 한다 ─────────────────
# 판정 창의 바깥쪽이다(dictation_test 검사 3 · 4 · 5의 게스트 판). 0.6초 떨어진 두 탭은
# 첫 누름부터 700ms 남짓이다.
echo "sendkey meta_r 80" >&3
sleep 0.8
echo "sendkey meta_r 80" >&3
sleep 0.6
echo "sendkey meta_r 80" >&3
sleep 1
[ "$(count_b 'terminal: dictate>')" -eq 0 ] \
  || report_b "a single tap or two taps 0.6s apart started something ($(grep -a 'terminal: dictate>' "$LOG" | head -n 1))"
echo "a single tap and two taps 0.6s apart did nothing"

# ── 검사 15: 두 번 → REC → 두 번 → 글자가 프롬프트에 들어간다 ──────────────
# 둘째 더블 탭이 그룹에 SIGINT를 보내고(stop), 상태 줄은 그 자리에서 WAIT가 된다. 자식이
# 끝나면 받은 글자가 bracketed paste로 그 패널에 간다 — fish가 줄에 올려 두고 실행하지
# 않는다(Enter가 없다).
double_tap
expect_recording 1 "B1"
wait_status '  REC$' 10 || report_b "B1: the status line never showed REC ($(last_status))"
wait_dict_ink on || report_b "B1: REC is in the text but no pixel has the dictation color"
sleep 1.5
double_tap
wait_count 'terminal: dictate> stop pid=' 1 10 || report_b "B1: the second double tap did not stop the recording"
wait_count 'terminal: dictate> insert len=' 1 20 || report_b "B1: nothing was inserted"
grep -aF 'tars-dictate: recording stopped by SIGINT after' "$LOG" >/dev/null \
  || report_b "B1: tars-dictate did not stop on SIGINT (did the signal reach the process group?)"
grep -aE 'terminal: status> text=.*  WAIT' "$LOG" >/dev/null || report_b "B1: the status line never showed WAIT"
INSERT1="$(grep -a 'terminal: dictate> insert len=' "$LOG" | head -n 1 | tr -d '\r' | sed -E 's/.*dictate> //')"
[ "$INSERT1" = "insert len=28 bracketed=1 ws=1 leaf=0" ] || report_b "B1: the insert line is '${INSERT1}'"
grep -aF 'terminal: dictate> exit code=0' "$LOG" >/dev/null || report_b "B1: tars-dictate did not exit 0"
wait_last_screen "${PROMPT} ${TEXT}" 15 || report_b "B1: the text never showed up on the prompt line"
wait_status 'CAPS$' 10 || report_b "B1: the dictation field stayed after the insert ($(last_status))"
wait_dict_ink off || report_b "B1: dictation pixels remain after the insert"
case "$(last_screen)" in *"Unknown command"*) report_b "B1: fish ran the inserted text" ;; esac
[ "$(stub_b_count)" -eq 1 ] || report_b "B1: the stub got $(stub_b_count) request(s), want 1"
type_keys ctrl-u
echo "two double taps recorded, stopped with SIGINT, showed REC then WAIT, and put the text on the prompt without running it"

# ── 검사 16: 녹음 중의 Esc는 취소이고 PTY로 안 간다 ──────────────────────
# 그룹에 SIGTERM — API를 안 부르고(stub 그대로) 143으로 끝나 조용하다. `key>` 줄은 PTY로
# 바이트가 나갈 때만 찍히므로, 그 수가 그대로인 것이 "Esc가 셸에 안 갔다"이다.
double_tap
expect_recording 2 "B2"
KEYS_BEFORE="$(count_b 'terminal: key>')"
echo "sendkey esc" >&3
wait_count 'terminal: dictate> cancel pid=' 1 10 || report_b "B2: Esc did not cancel"
wait_count 'terminal: dictate> exit code=143' 1 10 || report_b "B2: tars-dictate did not exit 143 after Esc"
[ "$(count_b 'terminal: key>')" -eq "$KEYS_BEFORE" ] || report_b "B2: the cancelling Esc also went to the shell"
wait_status 'CAPS$' 10 || report_b "B2: the dictation field stayed after the cancel ($(last_status))"
[ "$(stub_b_count)" -eq 1 ] || report_b "B2: a cancelled recording reached the API"
echo "Esc while recording cancelled it with SIGTERM, never reached the shell, and called no API"

# ── 검사 17: 비밀번호 프롬프트에서는 마이크를 안 연다 ─────────────────────
# bash의 read -s가 기다리는 동안(ICANON 켜짐 · ECHO 꺼짐) 더블 탭은 시작이 아니라 알림이다.
type_keys slash c o n f i g slash v d minus p w ret
wait_last_screen 'pw> ' 10 || report_b "B3: the password prompt never showed up"
sleep 0.5
double_tap
wait_count 'terminal: dictate> refused password at=start ws=1 leaf=0' 1 10 \
  || report_b "B3: a double tap on a password prompt was not refused"
wait_status '  PASSWORD$' 10 || report_b "B3: the status line did not say PASSWORD ($(last_status))"
[ "$(count_b 'terminal: dictate> start pid=')" -eq 2 ] || report_b "B3: a dictation started on a password prompt"
type_keys ret
wait_last_screen 'got\[\]' 10 || report_b "B3: read -s did not end with an empty answer"
wait_status 'CAPS$' 10 || report_b "B3: PASSWORD stayed after the next key ($(last_status))"
echo "a double tap on a password prompt did not open the microphone, said PASSWORD, and the next key cleared it"

# ── 검사 18: 말하는 사이에 비밀번호 프롬프트가 뜨면 넣지 않는다 ─────────────
# 시작할 때는 프롬프트였다. 녹음 중에 vd-pw를 치고, 그 read -s가 기다리는 동안 끝낸다.
# 전사는 됐고(stub에 간다) 기록에도 남지만(검사 22) 그 프롬프트에는 한 글자도 안 간다 —
# read가 받은 것이 빈 문자열이다.
double_tap
expect_recording 3 "B4"
type_keys slash c o n f i g slash v d minus p w ret
for _ in $(seq 1 100); do [ "$(last_screen_count 'pw> ')" -ge 2 ] && break; sleep 0.1; done
[ "$(last_screen_count 'pw> ')" -ge 2 ] || report_b "B4: the second password prompt never showed up"
sleep 0.5
double_tap
wait_count 'terminal: dictate> stop pid=' 2 10 || report_b "B4: the double tap did not stop the recording"
wait_count 'terminal: dictate> refused password at=insert ws=1 leaf=0' 1 20 \
  || report_b "B4: the text was not refused at the password prompt"
wait_status '  PASSWORD$' 10 || report_b "B4: the status line did not say PASSWORD ($(last_status))"
type_keys ret
for _ in $(seq 1 100); do [ "$(last_screen_count 'got[]')" -ge 2 ] && break; sleep 0.1; done
[ "$(last_screen_count 'got[]')" -ge 2 ] || report_b "B4: read -s got something (the text went into the password prompt)"
[ "$(count_b 'terminal: dictate> insert len=')" -eq 1 ] || report_b "B4: an insert line appeared"
[ "$(stub_b_count)" -eq 2 ] || report_b "B4: the stub got $(stub_b_count) request(s), want 2"
echo "a password prompt that appeared while speaking got nothing, and the status line said PASSWORD"

# ── 검사 19: 글자는 트리거를 누른 패널에 간다 ───────────────────────────
# Voxio D8 1번. 오른쪽에 패널을 가르고(포커스가 새 패널) 거기서 시작한 뒤, 왼쪽으로 포커스를
# 옮겨서 끝낸다. 글자는 오른쪽 패널(leaf 1)에 가고, 왼쪽의 마지막 프레임에는 없다.
type_keys meta_l-d
wait_count 'terminal: pane> ws=1/1 panes=2 focus=1' 1 10 || report_b "B5: Cmd+D did not split"
sleep 1
wait_last_screen "$PROMPT" 15 || report_b "B5: the new pane's prompt never showed up"
double_tap
expect_recording 4 "B5"
grep -aF 'terminal: dictate> start pid=' "$LOG" | tail -n 1 | grep -aF 'ws=1 leaf=1' >/dev/null \
  || report_b "B5: the dictation did not start in leaf 1"
type_keys meta_l-bracket_left
wait_count 'terminal: pane> ws=1/1 panes=2 focus=0' 1 10 || report_b "B5: Cmd+[ did not move the focus"
double_tap
wait_count 'terminal: dictate> insert len=' 2 20 || report_b "B5: nothing was inserted"
grep -a 'terminal: dictate> insert len=' "$LOG" | tail -n 1 | grep -aF 'ws=1 leaf=1' >/dev/null \
  || report_b "B5: the text went to $(grep -a 'terminal: dictate> insert len=' "$LOG" | tail -n 1 | tr -d '\r')"
sleep 1
[ "$(last_screen_count "$TEXT")" -eq 0 ] || report_b "B5: the focused pane (leaf 0) shows the text"
type_keys meta_l-bracket_right
wait_last_screen "${PROMPT} ${TEXT}" 15 || report_b "B5: leaf 1 does not show the text on its prompt"
[ "$(stub_b_count)" -eq 3 ] || report_b "B5: the stub got $(stub_b_count) request(s), want 3"
echo "the text went to the pane where the double tap started, not to the pane that had the focus"

# ── 검사 20: 그 패널이 닫혔으면 넣지 않고 알린다 ─────────────────────────
# leaf 1에서 시작하고 Cmd+W로 닫는다. 자식은 제 그룹이라 셸의 SIGHUP을 안 받고 계속 녹음한다.
# 끝내면 전사는 되지만 넣을 곳이 없다 — NO PANE. 글자는 기록에 남는다(검사 22).
type_keys ctrl-u
double_tap
expect_recording 5 "B6"
type_keys meta_l-w
wait_count 'terminal: pane> closed leaf=1' 1 10 || report_b "B6: Cmd+W did not close leaf 1"
double_tap
wait_count 'terminal: dictate> stop pid=' 4 10 || report_b "B6: the double tap did not stop the recording"
wait_count 'terminal: dictate> no pane shell=' 1 20 || report_b "B6: the closed pane was not noticed"
wait_status '  NO PANE$' 10 || report_b "B6: the status line did not say NO PANE ($(last_status))"
[ "$(count_b 'terminal: dictate> insert len=')" -eq 2 ] || report_b "B6: something was inserted"
[ "$(last_screen_count "$TEXT")" -eq 0 ] || report_b "B6: the text landed in the remaining pane"
[ "$(stub_b_count)" -eq 4 ] || report_b "B6: the stub got $(stub_b_count) request(s), want 4"
type_keys ctrl-u
wait_status 'CAPS$' 10 || report_b "B6: NO PANE stayed after the next key ($(last_status))"
echo "a dictation whose pane closed was transcribed but not inserted anywhere, and said NO PANE"

# ── 검사 21: 키 없이 끝난 녹음 뒤의 더블 탭은 시작이다 ─────────────────────
# design 결정 10의 함정 3(Voxio V17). max_seconds=1이면 자식이 스스로 멈추고(`stopped at the
# 1s limit`) 그 줄이 단계를 transcribing으로 옮긴다. 그 뒤의 더블 탭은 "끝내라"가 아니라 새
# 시작이어야 한다 — 두 번째 실행도 스스로 멈추고 글자를 넣는다.
type_keys slash c o n f i g slash v d minus c a p ret
sleep 1
double_tap
expect_recording 6 "B7"
wait_count 'terminal: dictate> phase transcribing' 1 15 \
  || report_b "B7: the 1s limit did not move the phase (tars-dictate's line was not read)"
wait_count 'terminal: dictate> insert len=' 3 20 || report_b "B7: the self-stopped recording inserted nothing"
wait_last_screen "${PROMPT} ${TEXT}" 15 || report_b "B7: the text never showed up"
type_keys ctrl-u
double_tap
expect_recording 7 "B7 again"
wait_count 'terminal: dictate> insert len=' 4 20 || report_b "B7: the double tap after a keyless end did not start a new dictation"
[ "$(count_b 'terminal: dictate> (stop|ignored)')" -eq 4 ] || report_b "B7: a double tap after a keyless end was read as stop or ignored"
[ "$(count_b 'tars-dictate: recording stopped at the 1s limit')" -eq 2 ] || report_b "B7: the two runs did not stop at the limit"
wait_last_screen "${PROMPT} ${TEXT}" 15 || report_b "B7: the second text never showed up"
type_keys ctrl-u
[ "$(stub_b_count)" -eq 6 ] || report_b "B7: the stub got $(stub_b_count) request(s), want 6"
echo "a recording that stopped at its limit inserted its text, and the next double tap started again"

# ── 검사 22: 키가 없으면 마이크를 안 열고 NO KEY ──────────────────────────
type_keys slash c o n f i g slash v d minus n o k e y ret
sleep 1
double_tap
wait_count 'terminal: dictate> start pid=' 8 15 || report_b "B8: the double tap started no dictation"
wait_count 'terminal: dictate> exit code=3' 1 15 || report_b "B8: tars-dictate did not exit 3 without a key"
wait_status '  NO KEY$' 10 || report_b "B8: the status line did not say NO KEY ($(last_status))"
[ "$(count_b 'terminal: dictate> phase recording')" -eq 7 ] || report_b "B8: a run without a key reached the microphone"
[ "$(stub_b_count)" -eq 6 ] || report_b "B8: a run without a key reached the API"
type_keys ctrl-u
wait_status 'CAPS$' 10 || report_b "B8: NO KEY stayed after the next key ($(last_status))"
echo "without a key the dictation never recorded, said NO KEY, and the next key cleared it"

# ── 검사 23: stub이 받은 여섯과 기록 여섯 ──────────────────────────────────
# 요청은 B1 · B4 · B5 · B6 · B7 둘이다. 전부 마이크의 상수다 — terminal이 띄운 자식도 같은
# 마이크를 지났다. 기록도 여섯이다. 넣지 않은 둘(B4 비밀번호 · B6 닫힌 패널)도 남는다 —
# 전사가 된 순간부터 말한 것은 사라지지 않는다(Voxio 불변식 1).
while IFS= read -r req; do
  case "$req" in *'auth=[Bearer vd1-test-key]'*) ;; *) report_b "a boot B request lacks the key (${req})" ;; esac
  N="$(stub_field "$req" n)"
  [ "$(stub_field "$req" mode)" = "$FEED_VALUE" ] && [ "$(stub_field "$req" mode_count)" = "$N" ] \
    || report_b "a boot B recording is not the microphone's constant (${req})"
done < <(grep -a '^stub: POST ' "$STUBLOG_B")
[ "$(grep -acE '^stub: POST /ok/b ' "$STUBLOG_B")" -eq 4 ] && [ "$(grep -acE '^stub: POST /ok/cap ' "$STUBLOG_B")" -eq 2 ] \
  || report_b "the boot B requests are not four /ok/b and two /ok/cap"
echo "system_powerdown" >&3
wait_for_exit 60 || report_b "the guest did not power off after system_powerdown"
debugfs -R "dump dictation.jsonl $WORK/dictation_b.jsonl" "$DISK_B" >/dev/null 2>&1
HISTORY_B="$(grep -c '"raw":"안녕하세요 vd0-dictated"' "$WORK/dictation_b.jsonl" 2>/dev/null || true)"
[ "${HISTORY_B:-0}" -eq 6 ] && [ "$(wc -l < "$WORK/dictation_b.jsonl")" -eq 6 ] \
  || report_b "dictation.jsonl holds ${HISTORY_B:-0} of the six transcripts (the refused and the lost ones must stay)"
echo "the stub got six recordings of the microphone, and dictation.jsonl kept all six, inserted or not"

echo "VD check PASS"
```


```bash
python3 /tmp/run/vd1/apply_plan.py docs/plans/2026-10-06-tars-voice-dictation-vd-m1.md "$PWD" dictation/check.sh
cmp dictation/check.sh /tmp/run/vd1/new/dictation/check.sh && echo "SAME check.sh"
bash -n dictation/check.sh && echo SYNTAX-OK
bash -c 'source <(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic()/,/^}/p" check.sh)
  require_build_steps ./dictation/check.sh && require_no_early_exit_pipe ./dictation/check.sh &&
  require_explicit_nic ./dictation/check.sh && echo ENTRY-OK'
python3 /tmp/run/vd1/anchors.py post "$PWD"
```

기대: `5 edit(s)`, `SAME check.sh`, `SYNTAX-OK`, `ENTRY-OK`, `post: 64 edits, 0 bad`.

### 5-2. `dictation` 체인 — 캐시를 지운 첫 판과 데운 판

한 컨테이너에서 셋을 잇달아 돈다. 약 5분이라 `run_in_background`로 돌리고 기다린다. 부팅 B의 시리얼 로그를 꺼내 둔다(lessons 범용 명령).

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -v /tmp/run/vd1/impl:/impl -w /workspace tars-devcontainer bash -c '
  rm -rf init/.zig-cache init/zig-out terminal/.zig-cache terminal/zig-out
  for r in cold warm1 warm2; do s=$(date +%s); bash dictation/check.sh > /impl/chain_$r.log 2>&1
    echo "$r exit=$? $(( $(date +%s) - s ))s"; done
  for f in /tmp/tmp.*; do [ -f "$f" ] && grep -a "terminal: dictate>" "$f" >/dev/null 2>&1 && cp "$f" /impl/serial_b.log; done' \
  > /tmp/run/vd1/impl/chain.out 2>&1
rmdir /tmp/run/docker.lock
cat /tmp/run/vd1/impl/chain.out
tail -n 12 /tmp/run/vd1/impl/chain_warm2.log
grep -a 'terminal: dictate>' /tmp/run/vd1/impl/serial_b.log | tr -d '\r'
```

기대: 셋 다 `exit=0`, 시간이 사본에서 2분 39초 · 77 · 75초 안팎. 끝 열두 줄이 아래와 같다.

```
=== boot B: the terminal triggers, shows and inserts (monitor 45493) ===
a single tap and two taps 0.6s apart did nothing
two double taps recorded, stopped with SIGINT, showed REC then WAIT, and put the text on the prompt without running it
Esc while recording cancelled it with SIGTERM, never reached the shell, and called no API
a double tap on a password prompt did not open the microphone, said PASSWORD, and the next key cleared it
a password prompt that appeared while speaking got nothing, and the status line said PASSWORD
the text went to the pane where the double tap started, not to the pane that had the focus
a dictation whose pane closed was transcribed but not inserted anywhere, and said NO PANE
a recording that stopped at its limit inserted its text, and the next double tap started again
without a key the dictation never recorded, said NO KEY, and the next key cleared it
the stub got six recordings of the microphone, and dictation.jsonl kept all six, inserted or not
VD check PASS
```

`dictate>` 줄은 `start` 여덟 · `phase recording` 일곱 · `stop` 넷 · `cancel` 하나 · `phase transcribing` 둘 · `insert` 넷 · `refused password` 둘 ·
`no pane` 하나 · `exit code=` 여덟(0이 여섯 · 143 하나 · 3 하나)이다. pid · `shell=`의 수는 판마다
다르다. 빨개지면 `report_b`가 찍는 줄들(받아쓰기 줄 · 상태 줄 · stub · 마지막 화면 · 마지막 30줄)을 그대로 보고한다.

### 5-3. regression — `copy` · `hangul` · `input` · `pane` · `terminal` · `pointer`

확정 9의 여섯이다. 한 컨테이너에서 차례로 돈다. 약 8분이라 `run_in_background`로 돌리고 기다린다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -v /tmp/run/vd1/impl:/impl -w /workspace tars-devcontainer bash -c '
  for c in copy hangul input pane terminal pointer; do s=$(date +%s); bash $c/check.sh > /impl/reg_$c.log 2>&1
    echo "$c exit=$? $(( $(date +%s) - s ))s"; done' > /tmp/run/vd1/impl/reg.out 2>&1
rmdir /tmp/run/docker.lock
cat /tmp/run/vd1/impl/reg.out
```

기대: 여섯 다 `exit=0`. 하나라도 빨개지면 그 로그의 `FAIL` 줄과 마지막 40줄을 보고한다 — 고치지 않는다.

## Task 6: mutation

확정 8의 표다. 사본은 `/tmp/run/vd1/impl/mut/`에 만든다. 만드는 스크립트와 도는 스크립트는 plan을 쓰며 쓴 것을 그대로 쓴다.

### 6-0. 사본을 만든다

```bash
python3 /tmp/run/vd1/make_mut.py "$PWD" /tmp/run/vd1/impl/mut
M=/tmp/run/vd1/impl/mut
for p in dictation_m1.zig:terminal/src/dictation.zig check_notest.sh:dictation/check.sh main_m2.zig:terminal/src/main.zig \
  main_m3.zig:terminal/src/main.zig main_m4.zig:terminal/src/main.zig input_m5.zig:terminal/src/input.zig \
  main_m6.zig:terminal/src/main.zig dictation_m7.zig:terminal/src/dictation.zig; do
  echo "${p%%:*} $(diff ${p#*:} $M/${p%%:*} | rg -c '^[<>]')"; done
```

기대: `mutation copies: 8`, 그리고 바뀐 줄 수가 여덟 다 `2`(`main_m2.zig`는 지운 줄 둘이라 `2`). 다르면 돌리지 말고 보고한다.

`make_mut.py`:

````python
"""VD-M1 plan Task 5의 mutation 사본을 만든다.

사용: python3 make_mut.py <저장소 루트> <출력 디렉터리>
저장소 파일은 읽기만 한다. 사본마다 바꾼 자리가 정확히 한 군데인지 assert한다.
"""
import os
import sys

root, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)


def make(src, dst, old, new, mode=0o644):
    s = open(os.path.join(root, src)).read()
    assert s.count(old) == 1, (dst, old[:70])
    path = os.path.join(out, dst)
    open(path, 'w').write(s.replace(old, new))
    os.chmod(path, mode)


# mutation 1 — 판정 창이 없다(얼마나 떨어진 두 탭이든 더블 탭이다)
make('terminal/src/dictation.zig', 'dictation_m1.zig',
     'time_us - self.first_down_us <= WINDOW_US)', 'time_us - self.first_down_us <= std.math.maxInt(u64))')
# 그것을 호스트 검사가 먼저 잡으므로, 호스트 검사를 건너뛴 체인 사본으로 부팅 B까지 보낸다
make('dictation/check.sh', 'check_notest.sh',
     'if ! (cd ../terminal && zig build test); then\n', 'if false; then\n', 0o755)
# mutation 2 — 자식이 제 프로세스 그룹을 안 만든다(그룹에 보낸 SIGINT가 아무에게도 안 간다)
s = open(os.path.join(root, 'terminal/src/main.zig')).read()
for old in ['        _ = std.c.setpgid(0, 0);\n', '    _ = std.c.setpgid(pid, pid);\n']:
    assert s.count(old) == 1, old
    s = s.replace(old, '')
open(os.path.join(out, 'main_m2.zig'), 'w').write(s)
# mutation 3 — 넣을 때 비밀번호 프롬프트를 안 본다
make('terminal/src/main.zig', 'main_m3.zig',
     '    if (passwordPrompt(fd)) {\n        std.debug.print("terminal: dictate> refused password at=insert',
     '    if (false) {\n        std.debug.print("terminal: dictate> refused password at=insert')
# mutation 4 — 시작할 때 비밀번호 프롬프트를 안 본다
make('terminal/src/main.zig', 'main_m4.zig',
     '                            if (passwordPrompt(tp.session.master_fd)) {',
     '                            if (false) {')
# mutation 5 — 녹음 중의 Esc를 가로채지 않는다(Esc가 셸로 가고 취소가 없다)
make('terminal/src/input.zig', 'input_m5.zig',
     '        if (ctx.dictating and code == c.KEY_ESC and\n',
     '        if (false and ctx.dictating and code == c.KEY_ESC and\n')
# mutation 6 — 트리거를 누른 패널이 아니라 지금 포커스에 넣는다
make('terminal/src/main.zig', 'main_m6.zig',
     '    const ref = paneByShell(workspaces, d.target) orelse {',
     '    const ref = paneByShell(workspaces, workspaces[current].?.panes[workspaces[current].?.focus].?.session.child_pid) orelse {')
# mutation 7 — 자식이 스스로 멈춘 줄을 안 읽는다(상한에서 멈춘 녹음이 끝날 때까지 "녹음 중"이다)
make('terminal/src/dictation.zig', 'dictation_m7.zig',
     '        .recording => if (std.mem.startsWith(u8, line, "tars-dictate: recording stopped "))',
     '        .recording => if (false)')
print('mutation copies:', len(os.listdir(out)))
````

`run_mut.sh` — 사본을 저장소 경로 위에 읽기 전용으로 덮어 체인 한 판을 돈다. Zig 파일을 덮은 판은 terminal이 다시 빌드된다(Zig는 내용
해시로 본다).

````bash
#!/bin/bash
# VD-M1 plan Task 5의 mutation 한 판을 돈다.
# 사용: run_mut.sh <저장소 루트> <이미지> <사본 디렉터리> <판 이름> <사본:저장소 경로>...
# 사본을 저장소 경로 위에 읽기 전용으로 덮어 dictation 체인을 한 번 돌리고, 로그를 <사본 디렉터리>/<판 이름>.log에 둔다.
# 첫 줄 mounted:의 여덟 자리는 차례로 "판정 창 · setpgid · 넣을 때의 비밀번호 · 시작할 때의 비밀번호 ·
# Esc 가로채기 · 대상 패널 · 멈춤 줄 · 호스트 검사"의 수다. 덮지 않은 판은 11111111이다.
repo=$1; img=$2; mut=$3; name=$4; shift 4
mounts=""
for m in "$@"; do mounts="$mounts -v $mut/${m%%:*}:/workspace/${m#*:}:ro"; done
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
s=$(date +%s)
docker run --rm -v "$repo":/workspace $mounts -v "$mut":/mut -w /workspace "$img" bash -c "
  D=terminal/src/dictation.zig; M=terminal/src/main.zig; I=terminal/src/input.zig
  echo \"mounted: \$(grep -c 'time_us - self.first_down_us <= WINDOW_US)' \$D)\$(grep -c '_ = std.c.setpgid(pid, pid);' \$M)\$(grep -c 'if (passwordPrompt(fd)) {' \$M)\$(grep -c 'if (passwordPrompt(tp.session.master_fd)) {' \$M)\$(grep -c 'if (ctx.dictating and code == c.KEY_ESC and' \$I)\$(grep -c 'paneByShell(workspaces, d.target) orelse' \$M)\$(grep -c '.recording => if (std.mem.startsWith' \$D)\$(grep -c 'if ! (cd ../terminal && zig build test); then' dictation/check.sh)\"
  bash dictation/check.sh > /mut/$name.log 2>&1; echo \"exit=\$?\""
rc=$?
rmdir /tmp/run/docker.lock
echo "== $name $(( $(date +%s) - s ))s"
grep -a '^FAIL\|^VD check PASS' "$mut/$name.log" | head -2
exit $rc
````

### 6-1. 체인 열한 판

판마다 1 ~ 3분, 합해서 14분 남짓이다. `run_in_background`로 돌리고 기다린다.

```bash
R="$PWD"; I=tars-devcontainer; M=/tmp/run/vd1/impl/mut; X=/tmp/run/vd1/run_mut.sh
{ $X $R $I $M m0
  $X $R $I $M m1 dictation_m1.zig:terminal/src/dictation.zig
  $X $R $I $M m1_gate dictation_m1.zig:terminal/src/dictation.zig check_notest.sh:dictation/check.sh
  $X $R $I $M m2 main_m2.zig:terminal/src/main.zig
  $X $R $I $M m3 main_m3.zig:terminal/src/main.zig
  $X $R $I $M m4 main_m4.zig:terminal/src/main.zig
  $X $R $I $M m5 input_m5.zig:terminal/src/input.zig
  $X $R $I $M m5_gate input_m5.zig:terminal/src/input.zig check_notest.sh:dictation/check.sh
  $X $R $I $M m6 main_m6.zig:terminal/src/main.zig
  $X $R $I $M m7 dictation_m7.zig:terminal/src/dictation.zig
  $X $R $I $M m7_gate dictation_m7.zig:terminal/src/dictation.zig check_notest.sh:dictation/check.sh; } > $M/run.out 2>&1
cat $M/run.out
```

기대는 확정 8의 표에서 그 판의 `FAIL` 줄이고 `m0`은 `VD check PASS`다. `mounted:`는 `m0`이 `11111111`, `m1`이 `01111111`, `m1_gate`가
`01111110`, `m2`가 `10111111`, `m3`이 `11011111`, `m4`가 `11101111`, `m5`가 `11110111`, `m5_gate`가 `11110110`, `m6`이 `11111011`, `m7`이
`11111101`, `m7_gate`가 `11111100`이다. 로그에 `Killed`가 보이면 mutation의 결과가 아니라 메모리다 — 다른 컨테이너가 없는지 보고 그 판만 다시
돈다. 예상과 다른 자리에서 죽거나 초록이면 그대로 적어 보고한다. 초록이면 먼저 덮기를 의심한다(`mounted:`).

### 6-2. 되돌림을 본다

mutation은 `-v`로 덮어 돌렸으므로 작업 트리의 파일은 그대로다. 체인을 한 번 더 돈다(데운 판이지만 terminal이 다시 빌드된다, 2분 안쪽).

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  bash dictation/check.sh > /tmp/d.log 2>&1; echo "exit=$?"; tail -n 1 /tmp/d.log'
rmdir /tmp/run/docker.lock
git status --short
```

기대: `exit=0` · `VD check PASS`. `git status`는 `M` 일곱(`dictation/check.sh` · `terminal/build.zig` · `terminal/src/` 아래 다섯)과 `??` 둘
(`terminal/src/dictation.zig` · `dictation_test.zig`)이고, lead의 문서가 commit 전이면 그것이 더 있다. 다른 것이 보이면(특히 `-v`로 없는
파일을 덮어 Docker가 만든 0바이트 파일) 그 목록을 보고한다.

### 6-3. 보고

- `git diff --stat`(전체)과 `git diff | rg '^-'`(전체). 사본에서는 `7 files changed, 1247 insertions(+), 19 deletions(-)`였다(새 파일 둘은 `git diff`에 안 나온다 — `git add -N`
  뒤에는 `9 files changed, 1800 insertions(+), 19 deletions(-)`).
- Task 0의 출력. Task 1 ~ 5의 확인 출력(`edit(s)` · `SAME` · `test exit` · `build exit` · `SYNTAX-OK` · `ENTRY-OK` · `anchors.py`).
- Task 5의 `exit=` · 시간 · 끝 열두 줄 · `dictate>` 줄들과 regression 여섯의 줄.
- Task 6의 `diff` 수 여덟 · 판마다 `mounted:` · `exit=` · 시간 · `FAIL` 줄, 6-2의 출력.
- plan의 기대와 글자나 수가 다른 것이 있으면 그 줄을 그대로.

## Task 7: lead가 하는 것

1. 보고를 받아 diff를 직접 읽고, 아홉 파일을 `/tmp/run/vd1/new/`와 `cmp`한다. Task 5의 로그를 대조한다.
2. 루트 게이트 2회(`feedback_gate_runs`), 스물한 체인 × 2다. 판정은 `PASS: 2/2` × 21과 `VD check PASS` 둘이다. M0의 53분 28초에 부팅 B가
   회차마다 약 45초를 더한다. `run_in_background`로 돌리고 `{ time …; }`로 감싼다. 다른 컨테이너와 겹치지 않는다.

   ```bash
   { time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/gate_vd1.log 2>&1 ; echo "exit=$?" ; } 2> /tmp/gate_vd1.time
   ```

   완료 알림이 오면 `pgrep -f 'tars-devcontainer bash check.sh'`가 비었는지 먼저 보고 판정한다. `rg -c 'PASS: 2/2' /tmp/gate_vd1.log`가 21,
   `rg -c 'VD check PASS' /tmp/gate_vd1.log`가 2여야 한다.
3. 실측 절 채우기, design에 덧붙이기(아래 절), design `Status:`(M1 끝, M2 plan 차례).
4. commit. 넣는 것은 아홉 파일과 이 plan이고 design이 바뀌었으면 함께 넣는다. `git add`는 경로를 하나씩 지정한다
   (`terminal/src/dictation.zig` · `terminal/src/dictation_test.zig`를 이름으로).
5. 실기. 사용자가 오른쪽 Cmd(또는 PC 자판의 오른쪽 Alt)를 두 번 눌러 보는 것은 M1 뒤에 바로 할 수 있다. 실기의 손으로 300ms가 맞는지와
   `REC`가 눈에 들어오는지를 거기서 본다(design 비목표 4 — 시작음을 다시 열 신호).

## design에 덧붙일 것

design 본문은 lead가 고친다. 이 plan이 design과 다르게 정했거나 design에 없던 것.

1. 위험 2(비밀번호 프롬프트)의 판정 — lead가 적은 "`tcgetattr`의 `ECHO`"를 "`ICANON`이 켜지고 `ECHO`가 꺼졌다"로 좁힌다(확정 4). 셸의
   줄 편집기는 `ECHO`와 `ICANON`을 함께 끄므로 `ECHO`만 보면 모든 셸 프롬프트에서 받아쓰기가 막힌다 — 사본의 fish 프롬프트가
   `icanon=false echo=false`였다(확정 9). ghostty와 같은 판정이다. 못 보는 것 하나를 위험 2에 덧붙인다 — 자기 편집기로 가리는 프롬프트
   (fish의 `read -s`)에는 글자가 들어간다(Enter는 안 붙는다). 보는 때는 시작과 넣기 둘이다.
2. 결정 6의 표 "M1의 terminal이 할 일(제안)" — 실제 값. 0 넣는다, 1 `NO MIC`, 2 · 130 · 143 조용, 3 `NO KEY`, 4 · 64 · 127(`execve` 실패) ·
   시그널 · 64KB 넘음 `FAILED`. 취소 중(`cancelling`)이었으면 무엇으로 끝났든 조용하다.
3. 결정 10의 함정 3 — "자식이 살아 있는가"에 한 겹을 더했다. 단계가 넷(`starting` · `recording` · `transcribing` · `cancelling`)이고, 앞의
   둘을 자식의 표준 에러 두 줄이 옮긴다(`tars-dictate: recording; ` · `tars-dictate: recording stopped `). 그래서 M0의 그 두 줄이 이제
   terminal과의 계약이다 — M0 plan의 로그 줄 정본에 "terminal이 읽는다"를 붙인다. 표준 에러는 파이프로 받아 시리얼에 그대로 다시 찍는다.
4. 결정 10 — 더블 탭이 시작인지 끝인지를 판정기가 아니라 단계가 정한다(`onTap`). `starting` · `transcribing`의 더블 탭은 무시한다. 근거는
   M0의 한 자리다(아래 5).
5. M0의 `tars-dictate`가 `arecord` 전에 받은 SIGINT는 "녹음을 끝내라"로 기억만 되고 그 뒤의 `arecord`가 상한(기본 300초)까지 돈다
   (`on_int`에서 `phase`가 이미 `recording`이다). 셸에서 친 사람의 Ctrl+C로도 같다(띄우자마자 누르면). M1은 그 구간의 더블 탭을 무시해
   피했다. 고치려면 `tars-dictate`가 `arecord`를 띄우기 직전에 `stopped`를 보고 녹음을 건너뛰면 된다 — M2에서 함께 볼 것으로 남긴다.
6. 결정 11 — 상태 줄의 글자(`REC` · `WAIT` · `NO MIC` · `NO KEY` · `FAILED` · `PASSWORD` · `NO PANE`)와 색(`0xF07070`), 알림은 다음 키에
   사라진다(수정키만 누르고 뗀 배치는 안 센다). terminal이 PTY 앞에서 한 번 더 거른다(방어 한 겹을 고른다).
7. 결정 11 — Esc의 자리. 녹음 중(`starting` · `recording`)의 수정키 없는 Esc는 `handleKey`의 1.3번 단계에서 copy mode · 검색 프롬프트 ·
   한글 층보다 먼저 받아쓰기의 것이 된다. 조합 중이던 글자와 `esc_latin`은 그대로다.
8. 결정 1 — terminal이 이미 libc를 링크하므로 자식 쪽 시스템 콜은 `std.c`로 부른다(`project_zig_c_uapi_rule`의 "libc 없이"는 `init`의
   길이다). `close_range` 하나만 `std.os.linux`다.
9. 실측에 덧붙인다(확정 9). QEMU의 `sendkey meta_r`가 게스트의 `KEY_RIGHTMETA`이고, hold를 안 적으면 누른 시간이 10ms 안팎 · 두 누름 사이가
   20ms 남짓이다. `sendkey meta_r 80` 둘이면 누른 시간 78 ~ 83ms · 두 누름 사이 159 ~ 163ms다. master의 `tcgetattr`가 slave의 termios를 준다.
10. lessons 포트 절 — `dictation`의 부팅 B가 monitor 45493을 쓴다. 새 체인은 45494부터.

## 이 milestone에서 안 하는 것

- 정리 단계(LLM) · `cleanup*` 키 · running-tars.md의 받아쓰기 절(VD-M2).
- 녹음 시작음 · 레벨 미터 · 오버레이 창(design 비목표 2 · 4). 상태 줄의 `REC`가 신호다.
- hold 모드 · 트리거 키 설정(design 비목표 3 · 결정 3의 표). 오른쪽 Cmd 자리 · 300ms는 상수다.
- 진짜 Groq. 게이트는 Groq를 절대 안 부른다. 실기에서 사용자가 본다.
- 수정키 비트가 `SYN_DROPPED` 뒤에 눌린 채 남는 오래된 구멍(design 실측 12). 이 milestone은 탭 판정만 비운다.
- `tars-dictate`가 `arecord` 전에 받은 SIGINT를 상한까지의 녹음으로 만드는 자리(확정 2). terminal은 그 구간의 더블 탭을 무시해 피한다.

## VD-M1이 실측한 것

구현은 Sonnet 서브에이전트가 2026-10-06에 main 작업 트리에서 했고, lead가 아홉 파일을 `/tmp/run/vd1/new/`와 `cmp`해 전부 같은
것을 봤다. plan의 기대와 글자나 수가 다른 것은 없었다. 로그는 `/tmp/run/vd1/impl/`(`chain_{cold,warm1,warm2}.log` · `reg_*.log` ·
`mut/` · `serial_b.log`), 루트 게이트는 `/tmp/gate_vd1.log`.

1. 편집과 검사. 편집 64개(`build.zig` 2 · `status.zig` 6 · `status_test.zig` 11 · `input.zig` 14 · `input_test.zig` 7 · `main.zig` 19 ·
   `dictation/check.sh` 5)와 새 파일 둘. `git diff --stat` 9 files +1800 −19, 지운 19줄은 plan의 자리뿐. `zig build test` exit 0 —
   `dictation_test` 16 전부 OK · `status_test` `MAX_LEN=56` · `input_test` 75 ~ 83 OK. `dictation` 체인 캐시를 지운 판 157초, 데운 판 72 · 76초,
   검사 14 ~ 23 전부 초록, 부팅 B의 `dictate>` 줄 수가 확정과 같다(`start` 8 · `phase recording` 7 · `stop` 4 · `cancel` 1 · `phase transcribing` 2 ·
   `insert` 4 · `refused password` 2 · `no pane` 1 · `exit code=` 8). regression 여섯 전부 exit 0(`copy` 176초 · `hangul` 81 · `input` 40 ·
   `pane` 44 · `terminal` 24 · `pointer` 74). mutation 열한 판이 확정 8의 표와 같은 자리 · 글자로 빨갰다.
2. plan과 다른 점 하나(판정 아님) — 체인이 시리얼 로그를 지워 5-2의 복사만으로는 `serial_b.log`가 안 남아, 구현자가 되돌림 판에서
   컨테이너 안에 복사 루프를 띄워 `dictate>` 줄을 따로 받았다.
3. 루트 게이트. 스물한 체인 × 2회, 54분 48초, `PASS: 2/2` 스물하나 · `VD check PASS` 둘 · `skipping make` 41. 두 회차 다 `dictation_test`
   16 · `status_test`의 받아쓰기 낱말 일곱 OK, `install` 부팅 7 `init waited` 1,700ms 둘. M0의 53분 28초에 1분 20초가 더해졌다(확정 7이 본
   1분 30초 남짓).
