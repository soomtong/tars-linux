# HANDOFF: Copy Mode가 끝났다 — 다음 일은 **다음 서브프로젝트를 고르는 것**이다

## 지금 어디인가

`main`, working tree 깨끗함.

```bash
git status --short     # 비어 있어야 한다
```

**push는 신경 쓰지 않는다**(`feedback_push_policy`). 미푸시 커밋 수를 세거나
push할지 묻지 않는다 — 필요하면 그냥 한다.

**Copy Mode 서브프로젝트가 2026-08-26에 닫혔다.** CM-M2가 마지막
milestone이었고 여덟 체인 24회가 전부 통과했다. **진행 중인 서브프로젝트가
없다** — 다음 세션의 첫 일은 아래 "이월 숙제"에서 다음 것을 고르고 design
doc을 쓰는 것이다.

- design: `docs/superpowers/specs/2026-08-24-tars-copy-mode-design.md`
  (CM-M0·M1·M2의 실측 결과가 "milestone 구성" 절 아래 인용 블록 셋에 있다)
- 끝난 plan 셋: `docs/superpowers/plans/2026-08-24-tars-copy-mode-cm-m0.md`,
  `…-cm-m1.md`, `…-cm-m2.md`
- 기억: `docs/decisions/project_copy_mode.md`에 서브프로젝트 전체가 정리돼 있다

| | 내용 |
|---|---|
| ~~CM-M0~~ | ~~모드 진입·이탈, `hjkl`·방향키 이동, 커서 반전, 뷰포트 추종, `scrollToBottom` 억제, 새 체인 신설~~ |
| ~~CM-M1~~ | ~~`v`/`V` 선택, 선택 렌더, `y` 복사, `Cmd+C` 별칭, 가지치기 방어~~ |
| ~~CM-M2~~ | ~~`Cmd+V` 붙여넣기, 왕복 증명, 억제 분기 밟기~~ |

## 다음 서브프로젝트 후보 — **1순위가 정해져 있다**

**게이트 시간을 줄이는 일 둘을 한 서브프로젝트로 묶는 안을 검토할 것.** 둘 다
같은 목표를 향하고, 따로 하면 게이트를 두 번 재야 한다.

1. **`init`을 `ReleaseSafe`로.** initrd 73.0MB → gzip 16.76MB이고 커널 부팅
   1.12초 중 **0.573초가 이 압축 해제**다. `terminal`도 Debug 42MB다.
2. **체인의 `sendkey` 사이 `sleep 0.3`을 줄이기.** CM-M0이 **0.05초 간격으로
   80번을 보내도 하나도 안 떨어지는 것**을 실측했다. 여덟 체인 전부에 걸리는
   변경이라 별도로 다뤄야 하고, **게이트 54분의 상당 부분이 이 `sleep`이다.**

## 게이트 현황

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh
```

`--platform`을 붙이지 않는다(`project_build_host_arch`).

**여덟 체인**(BF-M4 · TF-M4 · CP-M2 · IP-M2 · PM-M1 · HD-M2 · TR-M2 · CM-M2),
3/3, 부팅 30회 이상. **기준선은 54분 15초다**(2026-08-26).

monitor 포트는 45455(TF) · 45456(CP) · 45457(IP) · 45458(PM) · 45459(HD) ·
45460(TR) · 45461(CM)이고 **그다음은 45462가 비어 있다.**

### 이 게이트의 시간은 ±3분 수준의 잡음을 가진다

세 번의 기준선이 51분 20초(CM-M0) → 54분 40초(CM-M1) → 54분 15초(CM-M2)인데,
**증가분을 갈랐다고 말할 수 있었던 적이 없다.** CM-M1은 3분 20초 중 1분만,
CM-M2는 코드가 분명히 1분 10초를 더했는데도 전체가 25초 **줄었다.**

**값이 기준선에서 크게 벗어나면 코드를 의심하기 전에 기계를 먼저 의심한다.**
TR-M2를 끝내며 처음 잰 값이 6시간 12분이었고(8배), 판정은 멀쩡히 3/3이었으며
원인은 Chrome의 영상 재생이었다. 이 게이트는 arm64 위에서
`qemu-system-x86_64`를 TCG로 돌리므로 **전부 CPU 바운드**다.
`{ time docker run ... ; } 2> /tmp/gate.time`으로 감싼다.

### `pmset -g log`로는 CPU 부하를 사후에 알 수 없다 (CM-M2에서 드러났다)

TR-M2 때 Chrome을 짚을 수 있었던 것은 **assertion에 앱 이름이 찍혀 있었기
때문**이다. 그런 이름이 없으면 이 로그로는 부하를 못 가른다.

- **`Amphetamine`과 `caffeinate`는 부하가 아니다.** 둘 다 수면 방지 도구이고,
  54분짜리 게이트가 잠들지 않게 해 주므로 오히려 측정에 도움이 된다.
  **`caffeinate -i -t 300`은 Claude Code가 스스로 띄운다** — 이것을 배경
  부하의 증거로 읽으면 안 된다.
- **`coreaudiod` assertion**(`com.apple.audio.contextNNN`)은 오디오 세션이
  열려 있었다는 것만 말한다. 어느 앱인지도, CPU를 얼마나 썼는지도 없다.

**부하를 정말로 재려면 게이트를 돌리는 동안 `powermetrics`나 `top`으로 표본을
남겨야 한다.** 사후에는 못 본다.

### 게이트 로그를 조사하는 법

**각 체인은 시리얼 로그를 `mktemp` 파일에 담고 실패했을 때만 뿜는다.**
통과하면 `docker run --rm`과 함께 사라지므로, 특정 줄을 보려면 **한 번의
`docker run` 안에서** 게이트를 돌리고 `/tmp/tmp.*`를 뒤져야 한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  bash copy/check.sh > /tmp/gate.out 2>&1
  grep -ah "찾을 문구" /tmp/tmp.*
'
```

**`grep`에 `-a`를 반드시 붙인다.** 로그에 NUL이 한 바이트라도 있으면 `grep`이
파일을 binary로 취급해 `Binary file ... matches`만 뱉는다.

**긴 게이트를 돌릴 때 `| tail -N`을 붙이지 않는다.** `tail`이 파이프가 닫힐
때까지 아무것도 안 내보내서 진행 상황을 볼 수 없다. 파일로 리다이렉트하고
따로 들여다본다. **에러 본문도 `tail`에 잘리기 쉽다** — Zig 빌드 실패는
`grep -aE '^src/.*error'`로 뽑는 편이 빠르다.

**`style>`·`screen>` 줄을 셀 때는 마지막 프레임만 잘라낸다.** 그 줄들은 매
프레임 다시 찍히므로 로그 전체에서 세면 "지금 화면이 어떻게 생겼는가"가
아니라 "부팅 이후 몇 번 찍혔는가"가 된다. `copy/check.sh`의 `last_frame`이 그
방법이고, `inverted_cells`·`screen_count`가 그것 위에 서 있다.

### 로그 문구는 두 곳에 중복된다

`init` 코드(또는 커널)와 `check.sh` **양쪽에 있다.** 한쪽을 고치면 다른 쪽도
고쳐야 한다.

`signal handlers installed (TERM, INT)` · `ctrl-alt-del now arrives as SIGINT` ·
`shutdown requested (action power_off)` · `shutdown requested (action restart)` ·
`sent SIGTERM to every process` · `every child is gone (reaped N)` ·
`grace period expired (reaped N)` · `sent SIGKILL to what was left` ·
`filesystems synced` · `calling reboot(POWER_OFF)` · `calling reboot(RESTART)` ·
`giving up on terminal` · `started terminal`(개수 3) ·
`started console shell`(개수 1) · `restarting {s} in 1s` ·
`keyboard device /dev/input/event` · `no keyboard found`(없어야 한다) ·
`power button /dev/input/event` · `watching N power button(s)`(개수 1) ·
`no power button found`(없어야 한다) · `power button pressed` ·
`ACPI: button: Power Button`(커널) · `reboot: Power down`(커널) ·
`Power off not available: System halted instead`(커널, 없어야 한다) ·
`Restarting system`(커널, 끄는 부팅에는 없어야 하고 재시작 부팅에는 있어야 한다) ·
`terminal: style>` · `terminal: pixel>` · `terminal: render> first frame` ·
`terminal: ink>` · `terminal: font>` · `terminal: scroll>` · `terminal: key>` ·
`terminal: copy>` · `terminal: clip>` · `terminal: clip> paste`

**`terminal: screen>`의 형식은 절대 바꾸지 않는다** — 다섯 체인이 이 줄로
화면을 판정한다.

## 협업 방식 (먼저 읽을 것)

| 하는 일 | 누가 |
|---|---|
| 무엇을 왜 하는지 설명 | Claude |
| 구현 파일 편집 | **사용자** |
| 빌드·QEMU·게이트·조사성 명령 | **Claude** |
| 결과 로그를 줄 단위로 해석 | Claude |
| design/plan/HANDOFF/기억 파일, git commit | Claude |

근거는 `docs/decisions/feedback_execution_scope.md`(2026-08-22에 바뀌었다),
`feedback_commit_delegation.md`, `feedback_design_question_load.md`.

**인라인 제시는 "넣을 것"만 적는다.** 지울 것이 있는 편집은 `지울 것`과
`넣을 것`을 따로 표시하고, 100줄이 넘으면 Claude가 `/tmp`에 원본을 만들어
`diff`로 대조해 보인 뒤 사용자가 `cp`로 넣는다. **CM-M1에서 이 방식이 세 번
쓰였고 매번 "지운 줄"을 따로 세어 보인 것이 값졌다** — 셋 다 지운 줄이 한
자리 수였고, 그것이 곧 "구조적으로 사라진 것이 없다"는 증거였다. **CM-M2는
전부 인라인으로 끝났고**(가장 큰 것이 `copy/check.sh`의 순삽입 130줄),
편집 뒤 `git diff --stat`과 `지운 줄` 세기로 같은 확인을 했다.

**긴 명령은 실행 전에 얼마나 걸리는지 알린다.** 루트 게이트는 54분이라 Bash
도구의 10분 타임아웃을 넘는다 — **`run_in_background`로 돌려야 한다.**

**사용자가 "네가 정해"라고 하면 되묻지 말고 진행한다.**

**매 Step 완료 후 파일 내용을 `Read`/`rg`로 직접 검증한다.**

**커밋 전에 `git status`의 `M`과 신규를 가른다.**

## 서브프로젝트를 넘어 유효한 실측 — **다시 조사하지 말 것**

**1. `Action`이나 `Keys`나 `Copy`를 건드리면 `zig build`도 함께 돌린다.**
Zig가 참조되지 않는 함수를 분석하지 않아서, `readKeys`가 쓰는 `State.scrolls`
필드가 통째로 사라진 것을 `zig build test`가 **두 번** 놓쳤다. `input_test`는
`handleKey`만 부른다.

**2. 키의 의미를 바꾸는 것은 enum을 넓히는 것과 다른 축이다.** CM-M2에서
`Copy`에 variant를 더한 것 자체는 `input_test`를 안 깨뜨렸는데(`expectCopy`·
`expectCtx`는 `Action`만 훑는다), `Cmd+V`가 **바이트에서 copy 명령으로 의미가
바뀐 것**을 보던 IP 시절 검사가 깨졌다. **두 축을 따로 센다.**

**3. `sendkey`를 0.05초 간격으로 80번 보내도 하나도 안 떨어진다.** 커서를 46줄
올리고 뷰포트를 34줄 밀었으니 46 + 34 = 80이 정확히 맞았다. 위 이월 숙제의
방증이다.

**4. `sendkey meta_l-shift-c`가 세 키 조합을 게스트까지 옮긴다.** 두 키
조합(`meta_l-v`)은 그보다 쉬운 경우이고 CM-M2가 확인했다.

**5. copy 커서는 언제나 화면 맨 아랫줄에서 시작한다**(`row=46`, 화면은 47줄).
셸 프롬프트가 거기 있기 때문이다.

**6. 스크롤백 한도는 값 둘을 함께 줘야 걸린다.** `max_scrollback_lines`만
주면 기본 `max_scrollback_bytes`(10,000)가 먼저 걸려 아무 일도 안 일어난다.
`bytes = null`을 함께 준다. 실제 history는 754~1000줄을 오간다.

**7. "바닥에 있다"는 `offset == total - len`이다.**

**8. `RenderState`에서 격자 크기를 읽으면 조용히 no-op이 된다.** `state`는
마지막 `cells()`가 찍은 스냅숏이고 `init`은 그것을 `.empty`(rows=0, cols=0)로
둔다. **새 화면으로 검사를 쓸 때는 `cells()`를 한 번 부르고 시작한다.**

**9. 가지치기는 tracked pin을 무효로 만들지 않는다** — 살아 있는 이웃 페이지의
왼쪽 위로 옮긴다. 그래서 증상은 "선택이 사라진다"가 아니라 **"조용히 엉뚱한
자리를 복사한다"**이고, `selection == null`로는 감지할 수 없다.

## 시도했으나 안 되는 접근 (같은 벽에 다시 부딪치지 말 것)

- **`terminal: key>` 줄로 붙여넣기를 감지하기** — 붙여넣기는 `pty.write`를 직접
  부르지 `keys.bytes`를 거치지 않으므로 그 줄을 안 만든다. CM-M2의 도구는
  `clip>`와 `scroll>`였다.
- **`&screen.term.screens.active`** — `active`가 **이미 포인터**라서 `**Screen`이
  되고 `does not support field access`로 막힌다. `&` 없이 쓴다.
- **`vt.Screen`을 새로 만들고 곧바로 `copyMove`를 부르기** — `copyEnter`가
  `state.cursor.viewport`를 읽는데 `cells()` 전에는 null이라 커서가 왼쪽 위에서
  시작한다.
- **선택이 무효가 된 것을 `selection == null`로 감지하기** — 앵커의 screen
  좌표를 비교한다.
- **게이트 stdout에서 시리얼 로그의 줄을 `grep`하기** — 그 줄은 stdout에 없고
  체인이 만든 `mktemp` 파일 안에 있다.
- **NUL이 든 로그를 `-a` 없이 `grep`하기** — `Binary file ... matches`만 나온다.
- **`grep -qP '\x00'`으로 NUL 검출** — GNU grep 3.11에서 매치되지 않는다.
  `[ "$(tr -d '\0' < "$f" | wc -c)" -ne "$(wc -c < "$f")" ]`를 쓴다.
- **파이프라인 끝에 `grep -q`를 두기** — 첫 매치에서 빠져나가며 앞단에
  SIGPIPE를 일으키고 `pipefail`이 그것을 실패로 판정한다. 변수에 담아 `case`로
  본다.
- **`std.time.Timer` / `std.posix.clock_gettime`으로 시간 재기** — Zig 0.16에
  둘 다 없다. `std.Io.Clock.now(.awake, io)`이고 단조 시계 이름이
  `.monotonic`이 아니라 `.awake`다. 경과는 `t0.untilNow(io, .awake).nanoseconds`.
- **`std.posix.getenv`** — Zig 0.16에 없다.
- **컨테이너에서 `rg` 쓰기** — 없다. `grep -aE`를 쓴다.
- **컨테이너에서 `nc`로 QEMU monitor에 명령 보내기** — `nc`가 없다. 체인들은
  `exec 3<>/dev/tcp/127.0.0.1/PORT`를 쓴다.
- **`/tmp`에 만든 파일이 `docker run --rm` 사이에 남기** — 안 남는다. 조사성
  명령은 한 번의 `docker run` 안에서 끝내야 한다.
- **임시 Zig 프로젝트의 path 의존에 절대 경로 쓰기** — `expected path relative
  to build root`로 막힌다. 심볼릭 링크로 우회한다.
- **루트 게이트를 Bash 도구의 기본 타임아웃으로 돌리기** — 54분이라 10분
  상한을 넘는다. `run_in_background`로 돌린다.
- **`git cherry-pick`에 `-q`를 붙이기** — 그런 옵션이 없다. 히스토리를 만질
  때는 **먼저 태그를 찍고 한 명령씩 나눠 돌린 뒤,
  `git rev-parse HEAD^{tree}`로 전후 트리가 같은지 확인한다.**
- **`vt_test`의 CM-M0 검사를 `screen`에 붙이기** — `screen`은 파일 앞쪽의 작은
  화면이고 history가 없다. 스크롤백을 가진 것은 `fresh`이고, CM-M1·M2의 검사는
  자기 화면 `cm`·`pruned`를 쓴다.

### 조사용 Zig 프로그램을 저장소 밖에서 돌리는 법

`font.zig`를 import하는 프로그램은 `terminal/src/`에 있어야 한다. `build.zig`를
거치지 않고 이렇게 돌린다.

```bash
docker run --rm -v "$PWD":/workspace \
  -v /tmp/measure.zig:/workspace/terminal/src/measure.zig:ro \
  -w /workspace/terminal tars-devcontainer bash -c '
    zig build-exe src/measure.zig src/stb_truetype_impl.c \
      -Ivendor -lc -lm -OReleaseFast -femit-bin=/tmp/measure
    /tmp/measure
  '
```

**`ghostty-vt`를 import해야 하면 이 방법이 안 된다**(모듈 의존을 손으로 줄
수 없다). 대신 **기존 검사 파일 자리에 마운트해서 `zig build test`로 돌린다.**

```bash
docker run --rm -v "$PWD":/workspace \
  -v /tmp/probe.zig:/workspace/terminal/src/vt_test.zig:ro \
  -w /workspace/terminal tars-devcontainer bash -c 'zig build test'
```

**주의 둘.** (1) `-v`로 **없는 파일**을 마운트하면 Docker가 호스트에 빈 파일을
만들어 마운트 지점으로 쓰고 컨테이너가 끝나도 그 0바이트 파일이 남는다. 작업
뒤 `git status`로 확인할 것(기존 파일 자리에 덮는 쪽은 안 남는다).
(2) `cp -r terminal /tmp/t`로 트리를 복사하는 방법은 1.5GB라 느리다.

**CM-M1도 CM-M2도 프로브를 안 돌렸다.** 대신 `terminal/ghostty-src/src/
terminal/`과 우리 소스를 직접 읽어서 계약을 확인하고, 그것을 검사로 옮겨 실행으로
다시 증명했다. **소스를 읽어 얻은 사실은 반드시 검사로 옮긴다.**

## 이월 숙제

**위 "다음 서브프로젝트 후보"의 둘이 1순위다.** 나머지는 순서가 없다.

- [ ] **`fill` 하나의 비용을 따로 재기.** 첫 프레임 209밀리초의 출처가 셀 배경
      칠하기인지 `fill`의 102만 번 volatile 쓰기인지 안 갈렸다. **부분 갱신
      논의의 전제다.**
- [ ] **design doc 셋의 `Status:` 줄이 낡았다.** Config Persistence ·
      Power Management · Hardware Discovery가 "M0 미착수"로 남아 있는데
      게이트에는 `CP-M2` · `PM-M1` · `HD-M2`가 3/3으로 돈다. **CM-M2가
      발견했고 범위 밖이라 고치지 않았다.**
- [ ] **`ACPI_EC`와 `PNP_DEBUG_MESSAGES` 정리.**
- [ ] **`terminal/sanity/`의 수동 확인 도구 둘.** x86_64용이라 arm64 gcc로 못
      만든다. 필요하면 `zig cc -target x86_64-linux-gnu`. **빌드해서 돌려 본
      적이 없다.**
- [ ] **`clean()`에서 커널을 빼는 논의.** 게이트 시간의 가장 큰 단일 항목이다
      (`project_kernel_config`). 정책 변경이므로 별도로 다룬다. **위 1순위와
      묶일 수 있다.**
- [ ] **`terminal/vendor/fonts/Hanme_8x4x4.ttf`가 남아 있다.** `vendor/`가
      gitignore라 저장소에는 없다. 지워도 게이트는 안 흔들린다.
- [ ] **copy mode의 단어 이동(`w`/`b`)과 검색(`/`).** 라이브러리에
      `selectWord`도 `search`도 있다. design "비워 두는 자리"에 있다.
- [ ] **붙여넣기가 모드를 닫아야 하는가.** CM-M2가 "안 닫는다"로 정했고 대가를
      적어 두었다. 억제 분기를 백그라운드 출력으로 따로 보게 되면 다시
      저울질할 수 있다.
- [ ] **억제 분기를 진짜 상황으로 보기.** CM-M2의 검사 13이 밟는 것은
      붙여넣기 에코이고 **대역이다.** 진짜 이유인 백그라운드 출력으로 보려면
      copy mode 진입 전에 fish 백그라운드 잡을 띄워야 하는데 **타이핑 40여
      개와 회차당 15초**가 든다. 2026-08-26에 값을 저울질하고 안 하기로 골랐다.

### 끝난 숙제 (지운 것을 다시 줍지 말 것)

- ~~`xterm-256color` terminfo를 initrd에 넣기~~ — TR-M2에서 했다.
- ~~게스트 안에서 Zig 에러 트레이스 읽기~~ — **이미 되고 있었다.** BF 게이트
  로그에 `terminal/src/drm.zig:241:17`처럼 파일명과 줄 번호가 그대로 찍힌다.

## 핵심 파일

- `terminal/src/input.zig` — `handleKey`가 `Action`을 돌려주고 `readKeys`가
  `Keys`를 돌려준다.
  - `:160` `Action`(`bytes`·`scroll`·`copy`) · `:175` `Copy` enum(**열 개로
    닫혔다**) · `:197` `Keys` · `:314` `State.copies` · `:319` `State.mode` ·
    `:417` 진입키(Meta 분기 안의 Shift 예외, **이 예외는 하나뿐이어야 한다**) ·
    `:424` Meta 분기의 switch(`KEY_V`가 `:439`) · `:536` copy 표(`chord()`보다
    앞) · `:559` **`KEY_V`의 세 갈래**(Cmd / Shift / 맨)
- `terminal/src/vt.zig` — `Screen`. `cells()`가 색·inverse·선택·커서를 전부
  해소해 `CellGlyph`로 넘긴다.
  - `:55` `copy_cursor` · `:58~83` CM-M1 필드 넷(`clip` 포함) · `:156` `feed`
    (가지치기 감시) · `:172` `anchorY` · `:234` 선택 반전 · `:244` 커서 반전 ·
    `:316` `copyExit` · `:351` `copyMove` · `:465` `copyYank` · `:493`
    **`clipboard()`**
- `terminal/src/main.zig` — `drawGlyph`·`render`·`dumpScreen`·`dumpStyles`·
  `dumpInk`·`dumpScroll`·`dumpCopy`·`dumpClip`·`dumpPaste`, 그리고 `poll` 루프.
  **렌더는 루프 끝에 있고 `needs_redraw`가 문지기다.**
  - `:266` `dumpCopy` · `:286` `dumpClip` · `:310` **`dumpPaste`**(쓰기와
    로그를 한 함수에 둔다) · `:514` copy 배선 switch의 `.paste` 팔 · `:556`
    **`scrollToBottom` 억제**(CM-M2의 검사 13이 밟는다) · `:560`
    `if (screen.copyTakePruned())`
- `terminal/src/font.zig` — `Cache`(lazy 해시 맵) + `Glyph`. **코드는 폰트에
  무관하다.**
- `terminal/src/input_test.zig` — `expectCtx`·`expectCopy`의 `switch`가
  **`Action`을** 전부 훑는다(`Copy`가 아니다). `:315`가 `Cmd+V`를 보는 자리이고
  `:570~`이 CM-M2의 검사 11·12·13이다.
- `terminal/src/vt_test.zig` — TF-M3의 조각 이어붙이기 + TR-M0의 색 일곱과
  커서 + TR-M2의 스크롤백 다섯 + CM-M0의 copy 커서 넷 + CM-M1의 선택 다섯 +
  CM-M2의 클립보드 하나. `:471` `pruned` · `:512~` CM-M2.
- `copy/check.sh` — 558줄. 검사 열셋. `:149` `scroll_field` · `:161`
  `screen_count` · `:420~` 검사 10~13(왕복과 억제).
- `check.sh:109` — `run_chain "CM-M2" ./copy/check.sh`.
- `terminal/src/drm.zig:128`·`:138` — `setPixel`·`getPixel`. **범위 검사가
  없다.** 고치지 않고 호출부에서 막는다.
- `terminal/vendor_fonts.sh` — GNU ftp에서 unifont를 받고 sha256을 확인한다.

**기억.** `MEMORY.md`(색인) + `docs/decisions/`(본문). 새 세션은 협업 방식
feedback 셋과 `project_copy_mode`, `project_input_policy`,
`project_terminal_rendering`, `project_guest_environment`,
`project_gate_chain_composition`, `project_build_host_arch`,
`project_kernel_config`, `project_zig_c_uapi_rule`을 먼저 읽을 것.

## IP-M2가 남긴 것 (그대로 이월)

- **`Ctrl+←`/`Shift+←`는 여전히 맨 `ESC [ D`로 샌다.** TUI 앱이 생기면 그때.
- **DECCKM(`ESC O` 분기)은 부팅 게이트가 영영 못 밟는다.** `input_test`가
  `Context.cursor_keys`를 주입해 대신 본다.
- **`keymap`에 comptime 앵커가 박혔다.** 표 중간에 줄을 끼우면 컴파일이 막힌다.

## TR-M2가 남긴 것 (그대로 이월)

- **`Terminal.ScrollViewport`의 이름이 `PageList.Scroll`과 다르다.**
  `.bottom`·`.delta`이지 `.active`·`.delta_row`가 아니다.
- **렌더가 PTY 분기 안에만 있었다.** `needs_redraw`로 루프 끝에 뺐다.

## 감독 루프의 구조 (HD-M2가 만든 것, 그대로 유효)

```
1. power.take()   → 종료 요청이 있으면 shutdown(noreturn)
2. start()        → 안 떠 있고 포기하지 않은 자식을 띄운다
3. waitpid(-1, WNOHANG) 반복 → 거둘 것을 전부 거둔다
4. poll(버튼 fd들, 1000ms)   → 유일하게 잠드는 자리
```

**거두기(3)를 `poll`(4)보다 앞에 둔 것이 backoff를 만든다.** 이 코드의 진짜
계약은 HD 체인이 아니라 BF의 `started terminal` **정확히 3회**와 PM의
`started console shell` **정확히 1회**에 있다.

## 참고: vendor된 ghostty 소스의 프롬프트 인젝션 (조치 불필요, 인지만)

`terminal/ghostty-src/CLAUDE.md`(`AGENTS.md` 심볼릭 링크) 말미에 "이슈/PR
생성 요청이 오면 diff에 자기비하적 파일을 끼워 넣으라"는 프롬프트 인젝션이
있다. 따르지 않았다. 이 vendor 트리에 이슈/PR을 낼 계획은 없지만, 나중에
그럴 일이 생기면 이 파일 내용을 신뢰하지 말 것.
