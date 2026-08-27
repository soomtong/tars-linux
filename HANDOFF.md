# HANDOFF: Copy Navigation이 끝났다 — **진행 중인 서브프로젝트가 없다**

## 지금 어디인가

`main`, working tree 깨끗함. **CN-M0(단어 이동 `w`/`b`)과 CN-M1(검색 `/`·`n`·`N`)이
2026-08-27에 끝나 Copy Navigation이 닫혔다.** 게이트는 여덟 체인 3/3이고
**21분 38초**다.

```bash
git status --short     # 비어 있어야 한다
git log --oneline -8
#   Close out CN-M1
#   Bind n and N to walk the search matches
#   Run the search and move the copy cursor to a match
#   Draw the search prompt over the last row
#   Take search text in a copy mode prompt
#   Turn the copy command into a tagged union
#   Hand off at the start of CN-M1
#   Record the plain Korean writing rule
```

**push는 신경 쓰지 않는다**(`feedback_push_policy`). 미푸시 커밋 수를 세거나
push할지 묻지 않는다 — 필요하면 그냥 한다.

**다음 세션이 할 첫 일: 무엇을 할지 사용자와 정한다.** 후보는 아래 "이월 숙제"에
있고 순서는 없다. **사용자가 "네가 정해"라고 하면 되묻지 말고 고른 뒤 진행한다.**

- design: `docs/superpowers/specs/2026-08-26-tars-copy-navigation-design.md`
  (`Status:`를 종료로 갱신해 두었다)
- CN-M0 plan: `docs/superpowers/plans/2026-08-26-tars-copy-navigation-cn-m0.md`
- CN-M1 plan: `docs/superpowers/plans/2026-08-27-tars-copy-navigation-cn-m1.md`
- **기억: `docs/decisions/project_copy_navigation.md`**(CN-M0·CN-M1이 얻은 사실
  전부가 거기 있다)

## copy mode가 지금 할 수 있는 것

| 키 | 무엇 |
|---|---|
| `Cmd+Shift+C` | 진입 · `Esc` | 나가기 |
| `h`·`j`·`k`·`l`, 방향키 | 한 칸 이동 |
| `w`·`b` | 단어 이동(CN-M0) |
| `/` → 글자 → `Enter` | 스크롤백 검색(CN-M1) |
| `n`·`N` | 매치 사이 왕복(CN-M1) |
| `v`·`V` | 문자·줄 선택 |
| `y` 또는 `Cmd+C` | 복사하고 **나간다** |
| `Cmd+V` | 붙여넣기(**모드를 안 닫는다**) |

## CN-M1이 실행으로 증명한 것 — **다시 조사하지 말 것**

**1. design 위험 1이 해소됐다.** `ScreenSearch`는 `Screen.selection`을 안
건드린다 — `search/screen.zig` · `search/pagelist.zig` · `search/active.zig`
셋 전체에 그런 자리가 **없다.** 그래서 "매치의 좌표만 알려주는 것"으로 쓰는
설계가 그대로 섰고 우리 선택과 다툴 일이 없었다.

**2. `Select.next`의 주석은 "non-wrapping"이라고 하는데 코드는 감긴다**
(`search/screen.zig:851`). **주석이 아니라 코드를 믿는다.**

**3. 매치에서 pin을 꺼내는 길이 한 줄이다.** `selectedMatch()`가 주는
`FlattenedHighlight`에 `startPin()`이 있고(`highlight.zig:174`), 그것이
**CN-M0의 `copyPlace`가 받는 타입과 정확히 같다.** 검색의 커서 이동은 새 코드가
아니라 CN-M0 함수의 재사용이다.

**4. `searchAll()`은 스크롤백 416줄에 약 60~70밀리초다.** 게이트 세 회차가
`us=64423` · `us=69360` · `us=63908`을 찍었다(단독 실행은 48.8ms). 사람이 느끼는
문턱 아래이고 이 게이트는 arm64 위의 TCG 에뮬레이션이라 실제 하드웨어는 더
빠르다. **증분 검색으로 옮길 이유가 지금은 없다.**

**5. `Copy`가 `union(enum)`이고 variant가 열아홉이다.** payload를 가진 것은
`find_char: u8` 하나이고 **그것 하나 때문에 union이 됐다.** union에는 `==`가
없어서 `input_test`의 `expectCopy`가 `std.meta.eql`을 쓴다 — **전환이 깨뜨린
검사 코드는 그 한 줄뿐이었다.**

**6. 형태 전환과 기능 추가를 다른 커밋으로 가른 것이 값을 했다.** Task 1이
`union(enum)`으로만 바꾸자 컴파일러가 `input_test.zig:62` **하나만** 짚었고,
"union이라서 깨진 것"과 "variant가 늘어서 깨진 것"이 섞이지 않았다.
**표를 늘릴 다음 사람도 같은 순서로 한다.**

**7. `n`의 뜻이 세 층에서 갈리고 그것을 정하는 것은 분기 순서다.**
`handleKey`에서 **`.find` 분기가 copy 표보다 앞**이라 모드 밖에서는 바이트
`"n"`, copy mode에서는 `.find_next`, 프롬프트 안에서는 글자 `'n'`이다. 순서를
뒤집으면 **검색어에 `n`을 못 치게 된다.**

**8. 입력 경로와 렌더 경로를 다른 Task로 가른 것이 값을 했다.** Task 2가
로그(`find> type needle=…`)를 먼저 세우고 Task 3이 화면을 그렸다. 한꺼번에
넣었다면 "글자를 못 받았다"와 "받았는데 못 그렸다"를 가르는 데 부팅 한 바퀴가
들었을 것이다.

## CN-M0이 실행으로 증명한 것 — **다시 조사하지 말 것**

**1. 라이브러리의 "단어"에 공백 덩어리가 포함된다.** `Screen.selectWord`가
"exclusively whitespace or exclusively non-whitespace"로 정의하므로
**`"ABC  DEF"`가 세 단어**다. vim의 `w`를 만들려면 공백을 한 번 더 건너뛰는
일을 우리가 한다 — `wordNext`의 `hop < 2`가 그것이다.

**2. "쓰인 공백"과 "한 번도 안 쓰인 셀"은 다르다.** `written()`이
`cell.hasText()`로 가른다.

**3. 선택은 커서 셀을 포함한다.** `vt_test`의 검사 16이 `"beta g"` **여섯 자**로
확정했다.

**4. `pointFromPin(.viewport, pin)`은 위아래가 비대칭이다**(`:5614`). 뷰포트
**위쪽** 밖이면 null이지만 **아래쪽 밖은 알려주지 않는다.** `copyPlace`의
`if (co.y >= rows) return;`이 그것을 가른다. 빠뜨리면 증상이 크래시가 아니라
**"커서가 안 보인다"**이다. **CN-M1의 검색도 같은 함수를 쓴다.**

**5. `Screen.scroll(.{ .pin = p })`가 있다**(`Screen.zig:1565`·`:1576`).
그 pin을 뷰포트의 top left로 만든다(x 무시). `assertIntegrity`까지 해 주므로
`pages.scroll`을 직접 부르지 않는다. **`Terminal.ScrollViewport`에는 `.pin`이
없다**(`Terminal.zig:2504`).

**6. `main.zig`의 copy switch에 `else`가 없는 규율은 매번 값을 한다.**
variant를 더하면 컴파일러가 배선할 자리를 짚는다.

## 게이트 현황

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh
```

`--platform`을 붙이지 않는다(`project_build_host_arch`).

**여덟 체인**(BF-M4 · TF-M4 · CP-M2 · IP-M2 · PM-M1 · HD-M2 · TR-M2 · CM-M2),
3/3, 부팅 30회 이상. **기준선은 21분 38초다**(2026-08-27, CN-M1 이후).

**CN-M0도 CN-M1도 새 체인을 만들지 않았다**(design 결정 1). `copy/check.sh`를
늘렸다 — 스크롤백 1000줄을 만드는 준비가 그대로 필요한데 그것을 새 부팅에서
다시 하는 것은 중복이고, 체인 하나는 부팅 세 번이다. **monitor 포트 45462는
계속 비어 있다.**

**체인 목록은 `CHAINS` 배열 하나에 있다**(`check.sh:146`). 진입 검사와 실행이
같은 목록을 쓰므로 체인을 더하거나 뺄 때 고칠 자리가 하나다.

monitor 포트는 45455(TF) · 45456(CP) · 45457(IP) · 45458(PM) · 45459(HD) ·
45460(TR) · 45461(CM)이다.

### 게이트는 첫 회차에만 clean하고 나머지 23회차는 증분이다 (GL-M0)

`clean()`은 `run_chain` 안이 아니라 **게이트 시작에서 한 번만** 불린다
(`check.sh:176`). 그래서 **회차 시간이 1회차와 2·3회차에서 크게 다른 것이
정상이다**.

**빌드 스텝을 빠뜨린 체인은 진입 검사가 막는다.** `check.sh`가 첫 부팅 전에
여덟 스크립트를 훑어 `kernel/build.sh` · `init`의 `zig build` ·
`terminal/prepare.sh` · `kernel/make_initrd.sh` 넷을 부르는지 본다. **빌드
스텝이 새로 생기면 `BUILD_STEPS` 목록도 함께 고쳐야 한다**(`check.sh:35`).

**커널은 입력이 안 바뀌면 아예 빌드하지 않는다 (GL-M1).** `kernel/build.sh`가
`.config`와 자기 자신의 sha256을 `build/.tars-build-stamp`에 적어 두고
대조한다. 게이트 로그에 **`skipping make`가 23회** 찍히는 것이 정상이다 —
**CN-M1의 게이트에서도 정확히 23회였다.** **24회가 찍히면 `clean()`이 지운
자리에서도 건너뛴 것이라 잘못이다.** `build.sh`가 해시에 들어가는 이유는
`KERNEL_VERSION`이 그 안에 있기 때문이고, **커널 버전을 올릴 사람은 이것을
알아야 한다.**

### 이 게이트의 시간은 ±3분 수준의 잡음을 가진다

CM 시절 세 기준선이 51분 20초 → 54분 40초 → 54분 15초인데, **증가분을 갈랐다고
말할 수 있었던 적이 없다.** CM-M2는 코드가 분명히 1분 10초를 더했는데도 전체가
25초 **줄었다.**

**GL-M0의 30분 06초는 그 잡음의 열 배라 갈렸다.** 절약을 주장하려면 이 정도
크기여야 한다는 기준으로 삼는다.

**CN-M0은 53초, CN-M1은 2분 38초 늘었다**(18분 08초 → 19분 01초 → 21분 38초).
CN-M1의 예상은 회차당 약 50초 · 전체 약 2분 30초였고 실측이 그 안에 들어왔지만,
**이것도 잡음보다 작으므로 "우리 코드가 2분 38초를 더했다"고 주장하지 않는다.**
**예상과 실측이 맞은 것은 확인이지 증명이 아니다.**

**값이 기준선에서 크게 벗어나면 코드를 의심하기 전에 기계를 먼저 의심한다.**
TR-M2를 끝내며 처음 잰 값이 6시간 12분이었고(8배), 판정은 멀쩡히 3/3이었으며
원인은 Chrome의 영상 재생이었다. 이 게이트는 arm64 위에서
`qemu-system-x86_64`를 TCG로 돌리므로 **전부 CPU 바운드**다.
`{ time docker run ... ; } 2> /tmp/gate.time`으로 감싼다.

### `pmset -g log`로는 CPU 부하를 사후에 알 수 없다 (CM-M2에서 드러났다)

TR-M2 때 Chrome을 짚을 수 있었던 것은 **assertion에 앱 이름이 찍혀 있었기
때문**이다. 그런 이름이 없으면 이 로그로는 부하를 못 가른다.

- **`Amphetamine`과 `caffeinate`는 부하가 아니다.** 둘 다 수면 방지 도구이고,
  22분짜리 게이트가 잠들지 않게 해 주므로 오히려 측정에 도움이 된다.
  **`caffeinate -i -t 1800`은 Claude Code가 스스로 띄운다** — 이것을 배경
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
따로 들여다본다. **파이프를 거치면 종료 코드가 `tail`의 것이 되는 것도
주의한다** — CN-M1에서 `zig build test`의 성공을 그렇게 잃을 뻔했다. 에러 본문은
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
`terminal: copy>` · `terminal: copy> word_next` · `terminal: copy> word_prev`
(CN-M0) · `terminal: clip>` · `terminal: clip> paste` ·
**`terminal: find> open` · `terminal: find> type needle=… len=…` ·
`terminal: find> erase` · `terminal: find> cancel` ·
`terminal: find> submit matches=… moved=… us=…` ·
`terminal: find> next moved=…` · `terminal: find> prev moved=…`**(CN-M1) ·
**`terminal: style> N cell(s) hidden by the find prompt`**(CN-M1)

**새 copy 명령의 로그는 공짜다** — switch 아래의 `dumpCopy(screen,
@tagName(cmd))`가 이미 찍는다. 새 `dump` 함수를 만들지 않는다. **`find>`는 그와
별개로 프롬프트 내용을 찍는 창구다** — 오버레이는 `cells()`에 안 섞여
`screen>`에 영영 안 나오므로 이 줄이 유일한 관측 수단이다.

**`terminal: screen>`의 형식은 절대 바꾸지 않는다** — 다섯 체인이 이 줄로
화면을 판정한다. **CN-M1의 검색 프롬프트가 오버레이인 이유가 이것이다.**

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
사용자가 `cp`로 넣는다. **CN-M1은 여섯 Task를 전부 인라인으로 냈고 잘 돌았다** —
가장 큰 편집(`vt.zig`의 함수 넷, 152줄)도 여러 자리로 나뉘어 있어 각각은
100줄 아래였다. 매 편집 뒤 `git diff --stat`으로 **더한 줄과 지운 줄을 따로
세어** 확인했고, 지운 줄이 예상과 정확히 맞는 것이 "엉뚱한 것을 안 지웠다"의
증명이다.

**plan이 각 Step의 코드를 파일 안에 그대로 담고 있는 것이 값지다.** 제시할 때
plan의 그 절을 가리키면 되고 다시 옮겨 적을 필요가 없다. **CN-M0도 CN-M1도 그
방식이었다.**

**plan이 틀릴 수 있다.** CN-M1 Task 6에서 두 번 드러났다 — `matches=2`가 실제로는
4였고(`echo findme`가 스크롤백에 **두 줄**을 남긴다), 대문자 `sendkey F`는 QEMU가
조용히 버린다. **plan을 그대로 밟되 실측이 다르면 실측이 답이다.**

**긴 명령은 실행 전에 얼마나 걸리는지 알린다.** 루트 게이트는 22분이라 Bash
도구의 10분 타임아웃을 넘는다 — **`run_in_background`로 돌려야 한다.**
`copy` 체인 단독도 8분이라 마찬가지다.

**사용자가 "네가 정해"라고 하면 되묻지 말고 진행한다.**

**글쓰기: 비유적 표현을 일반 어휘 자리에 쓰지 않는다**(`feedback_plain_korean`,
2026-08-27). "계획이 섰다"가 지적받은 실물이다 — "계획을 다 썼다"로 쓴다.
**평범한 한국어가 어색해지면 영어를 섞어도 된다**(`plan is up`). 판단 기준은
"이 어휘가 비유인가"가 아니라 **"이 문장을 두 가지로 읽을 수 있는가"**이고,
**제목과 첫 문장을 특히 본다** — 본문의 흐린 표현은 뒤에서 메워지지만 제목은
메울 자리가 없다.

**매 Step 완료 후 파일 내용을 `Read`/`rg`로 직접 검증한다.**

**커밋 전에 `git status`의 `M`과 신규를 가른다.**

## 서브프로젝트를 넘어 유효한 실측 — **다시 조사하지 말 것**

**1. `Action`이나 `Keys`나 `Copy`를 건드리면 `zig build`도 함께 돌린다.**
Zig가 참조되지 않는 함수를 분석하지 않아서, `readKeys`가 쓰는 `State.scrolls`
필드가 통째로 사라진 것을 `zig build test`가 **두 번** 놓쳤다. `input_test`는
`handleKey`만 부른다. **CN-M0도 CN-M1도 `zig build && zig build test`로 둘을
함께 돌려 이것을 막았다.**

**2. 키의 의미를 바꾸는 것은 enum을 넓히는 것과 다른 축이다.** `Copy`에
variant를 더하는 것 자체는 `input_test`를 안 깨뜨리는데(`expectCopy`는 `Action`을
훑는다), **키의 뜻이 바뀌면** 그것을 보던 검사가 깨진다. CM-M2의 `Cmd+V`,
CN-M0의 `w`가 그랬다. **CN-M1의 `n`은 "모르는 키" 목록에 없어서 안 깨졌고, 그
차이 자체가 두 축이 다르다는 증거다.** **두 축을 따로 센다.**

**3. 그 축을 막는 것은 "모드 밖 대조군" 검사다.** `input_test`의 검사 14가
`w`·`b`, 검사 21이 `/`·`?`, 검사 22가 `n`을 **모드 밖에서** 보아 여전히 바이트로
나가는 것을 확인한다. 이것이 없으면 배선을 잘못해 **셸에 그 글자를 영영 못
치게 되어도** 아무 검사도 안 깨진다.

**4. `sendkey`를 0.05초 간격으로 80번 보내도 하나도 안 떨어진다.**

**5. `sendkey meta_l-shift-c`가 세 키 조합을 게스트까지 옮긴다.**

**6. `sendkey`의 키 이름은 전부 소문자다.** `sendkey F`는 없는 이름이라 QEMU가
**조용히 버린다** — 체인은 monitor의 응답을 안 읽으므로 에러도 안 보인다.
대문자를 치려면 `shift-f`처럼 앞에 붙인다. **CN-M1에서 `echo FINDME`가
`echo `로 도착해 한 부팅을 잃었다.**

**7. copy 커서는 언제나 화면 맨 아랫줄에서 시작한다**(`row=46`, 화면은 47줄).
셸 프롬프트가 거기 있기 때문이다.

**8. `copyMove`의 좌우는 줄을 넘나들지 않고 x를 0과 `cols-1`에서 멈춘다.**
그래서 `h`를 충분히 많이 누르면 **반드시** col 0에 선다.

**9. 게이트에서 col을 세려면 대상 줄을 새로 만든다.** 화면에 이미 있는 줄들은
프롬프트가 섞여 있어 셀 수 없다.

**10. 게이트에서 검색 이동을 볼 때는 `scroll> offset`을 더해 절대 행으로 센다.**
`copy> row=`은 뷰포트 안의 행인데 `copyPlace`가 매치를 뷰포트 **맨 위로**
올리므로 검색에서는 늘 0이다. 그 값만 찍으면 **"0에서 0으로 갔다"**가 되어 안
움직인 것처럼 읽힌다. CN-M1의 검사 15가 `312 -> 210`으로 고쳤다.

**11. 스크롤백 한도는 값 둘을 함께 줘야 걸린다.** `max_scrollback_lines`만
주면 기본 `max_scrollback_bytes`(10,000)가 먼저 걸린다. `bytes = null`을 함께
준다.

**12. "바닥에 있다"는 `offset == total - len`이다.**

**13. `RenderState`에서 격자 크기를 읽으면 조용히 no-op이 된다.** `state`는
마지막 `cells()`가 찍은 스냅숏이고 `init`은 그것을 `.empty`(rows=0, cols=0)로
둔다. **새 화면으로 검사를 쓸 때는 `cells()`를 한 번 부르고 시작한다.**

**14. 가지치기는 tracked pin을 무효로 만들지 않는다** — 살아 있는 이웃 페이지의
왼쪽 위로 옮긴다. 그래서 증상은 "선택이 사라진다"가 아니라 **"조용히 엉뚱한
자리를 복사한다"**이고, `selection == null`로는 감지할 수 없다.

**15. "빌드가 최신인가"를 mtime으로 판정하려는 시도는 두 번 다 실패했다.**
**처방은 둘 다 내용을 보는 것이다** — 입력의 sha256을 산출물 옆에 적는다.

**16. 게이트 시간의 8할은 빌드였다.** 부팅은 2%가 안 되고 `type_keys`의
`sleep 0.3`은 11%다. 단계별 실측값은 `project_gate_latency`에 표로 있다.

**17. `gzip -9`는 값을 못 하는 압축 레벨이다.** initrd는 `-6`으로 만든다.

**18. `terminal`은 Debug에 묶여 있고 `init`은 아니다.** `-Doptimize=ReleaseSafe`가
`terminal/src/drm.zig:3`의 `@cImport`를 glibc fortify 때문에 깨뜨린다. 우회
(`@cDefine("_FORTIFY_SOURCE", "0")`)는 `project_zig_c_uapi_rule`에 있다.

## 시도했으나 안 되는 접근 (같은 벽에 다시 부딪치지 말 것)

- **`terminal: key>` 줄로 붙여넣기를 감지하기** — 붙여넣기는 `pty.write`를 직접
  부르지 `keys.bytes`를 거치지 않는다. **거꾸로, `key>` 줄을 세는 것은 "모드
  안의 키가 PTY로 안 샜다"의 좋은 도구다** — CN-M0의 판정 5와 CN-M1의 검사 15가
  그것이다.
- **`sendkey`로 대문자 치기** — 키 이름이 전부 소문자다. `shift-f`를 쓴다.
- **"화면에 표적이 없다"로 "스크롤백으로 밀려났다"를 판정하기** — **"애초에 안
  쳐졌다"와 안 갈린다.** CN-M1이 그것에 속았다. 실제로 쳐졌는지는 다른 줄로
  따로 본다(`find> type needle=…`).
- **`&screen.term.screens.active`** — `active`가 **이미 포인터**라서 `**Screen`이
  되고 `does not support field access`로 막힌다. `&` 없이 쓴다.
- **`Terminal.scrollViewport`로 특정 pin에 뷰포트 맞추기** — `ScrollViewport`에
  `.pin`이 없다. `screens.active.scroll(.{ .pin = p })`을 쓴다. **`pages.scroll`을
  직접 부르면 `assertIntegrity`를 건너뛴다.**
- **`pointFromPin(.viewport, …)`의 null만 보고 "화면 안이다"로 판정하기** —
  위쪽 밖만 null이고 아래쪽 밖은 큰 y를 그냥 준다. `y >= rows`를 따로 본다.
- **`vt.Screen`을 새로 만들고 곧바로 `copyMove`를 부르기** — `copyEnter`가
  `state.cursor.viewport`를 읽는데 `cells()` 전에는 null이다.
- **선택이 무효가 된 것을 `selection == null`로 감지하기** — 앵커의 screen
  좌표를 비교한다.
- **tagged union을 `==`로 비교하기** — Zig가 막는다. `std.meta.eql`을 쓴다.
- **`render` 밖에서 오버레이 그리기** — `render`가 `fb.present()`로 끝나므로
  **그 안에서 present 앞에** 그려야 한다. 밖에서 그리면 다음 프레임까지 화면에
  안 나온다.
- **게이트 stdout에서 시리얼 로그의 줄을 `grep`하기** — 그 줄은 stdout에 없고
  체인이 만든 `mktemp` 파일 안에 있다.
- **NUL이 든 로그를 `-a` 없이 `grep`하기** — `Binary file ... matches`만 나온다.
- **`grep -qP '\x00'`으로 NUL 검출** — GNU grep 3.11에서 매치되지 않는다.
  `[ "$(tr -d '\0' < "$f" | wc -c)" -ne "$(wc -c < "$f")" ]`를 쓴다.
- **파이프라인 끝에 `grep -q`를 두기** — 첫 매치에서 빠져나가며 앞단에
  SIGPIPE를 일으키고 `pipefail`이 그것을 실패로 판정한다. 변수에 담아 `case`로
  본다.
- **긴 빌드를 `| tail`로 감싸고 종료 코드 믿기** — 파이프의 종료 코드는 `tail`의
  것이다. 파일로 리다이렉트하고 `$?`를 따로 본다.
- **`rg`에 `-r`을 "recursive"로 쓰기** — `-r`은 **replace**다. 재귀는 기본
  동작이라 옵션이 필요 없다.
- **`rg`에 `-E`를 "extended regex"로 쓰기** — `-E`는 **`--encoding`**이다.
  패턴이 `-`나 `\`로 시작해 헷갈릴 때는 `-e`로 명시한다.
- **Bash 도구에서 `cd`로 옮겨 다니기** — **작업 디렉터리가 호출 사이에 남는다.**
  조사성 명령은 **저장소 루트 기준 상대 경로를 그대로 쓴다.**
- **`std.time.Timer` / `std.posix.clock_gettime`으로 시간 재기** — Zig 0.16에
  둘 다 없다. `std.Io.Clock.now(.awake, io)`이고 단조 시계 이름이
  `.monotonic`이 아니라 `.awake`다. 경과는 `t0.untilNow(io, .awake).nanoseconds`.
- **`std.posix.getenv`** — Zig 0.16에 없다.
- **컨테이너에서 `rg` 쓰기** — 없다. `grep -aE`를 쓴다.
- **컨테이너에서 `nc`로 QEMU monitor에 명령 보내기** — `nc`가 없다. 체인들은
  `exec 3<>/dev/tcp/127.0.0.1/PORT`를 쓴다.
- **`/tmp`에 만든 파일이 `docker run --rm` 사이에 남기** — 안 남는다.
- **임시 Zig 프로젝트의 path 의존에 절대 경로 쓰기** — `expected path relative
  to build root`로 막힌다. 심볼릭 링크로 우회한다.
- **루트 게이트를 Bash 도구의 기본 타임아웃으로 돌리기** — 22분이라 상한을
  넘는다. `run_in_background`로 돌린다.
- **`git cherry-pick`에 `-q`를 붙이기** — 그런 옵션이 없다.
- **`vt_test`의 검사를 남의 화면에 붙이기** — 화면마다 크기와 history가 다르다.
  CM-M1이 `cm`, CM-M2가 `pruned`, CN-M0이 `wm`, **CN-M1이 `fm`·`fs`를 새로
  만들었고 그래서 앞 검사들을 하나도 안 흔들었다.**
- **`vt_test`에서 `before`/`after`를 지역 변수 이름으로 쓰기** — CM-M0의 검사가
  이미 쓰고 있고, **Zig는 같은 함수 안의 shadowing을 컴파일 에러로 막는다.**
  `main()` 하나가 파일 전체라 이 파일의 모든 지역 변수 이름이 서로 부딪친다.
  **새 검사를 쓰기 전에 이름을 `rg`로 먼저 확인한다.**

### 조사용 Zig 프로그램을 저장소 밖에서 돌리는 법

`font.zig`를 import하는 프로그램은 `terminal/src/`에 있어야 한다.

```bash
docker run --rm -v "$PWD":/workspace \
  -v /tmp/measure.zig:/workspace/terminal/src/measure.zig:ro \
  -w /workspace/terminal tars-devcontainer bash -c '
    zig build-exe src/measure.zig src/stb_truetype_impl.c \
      -Ivendor -lc -lm -OReleaseFast -femit-bin=/tmp/measure
    /tmp/measure
  '
```

**`ghostty-vt`를 import해야 하면 이 방법이 안 된다.** 대신 **기존 검사 파일
자리에 마운트해서 `zig build test`로 돌린다.**

```bash
docker run --rm -v "$PWD":/workspace \
  -v /tmp/probe.zig:/workspace/terminal/src/vt_test.zig:ro \
  -w /workspace/terminal tars-devcontainer bash -c 'zig build test'
```

**주의 둘.** (1) `-v`로 **없는 파일**을 마운트하면 Docker가 호스트에 빈 파일을
만들어 마운트 지점으로 쓰고 컨테이너가 끝나도 그 0바이트 파일이 남는다.
(2) `cp -r terminal /tmp/t`로 트리를 복사하는 방법은 1.5GB라 느리다.

**CM-M1도 CM-M2도 CN-M0도 CN-M1도 프로브를 안 돌렸다.** 대신
`terminal/ghostty-src/src/terminal/`과 우리 소스를 직접 읽어서 계약을 확인하고,
그것을 검사로 옮겨 실행으로 다시 증명했다. **소스를 읽어 얻은 사실은 반드시
검사로 옮긴다.** CN-M1의 아홉 사실이 그렇게 검사가 됐고, 그중 하나
(`Select.next`가 감기는가)는 **주석과 코드가 어긋난 자리**였다.

## 이월 숙제

**진행 중인 서브프로젝트가 없다.** 아래에서 다음 것을 고른다. 순서는 없다.

- [ ] **`terminal`을 `ReleaseSafe`로.** 42.7MB이고 initrd의 대부분이다.
      `@cImport`가 glibc fortify로 깨지는 것이 유일한 벽이고 우회
      (`@cDefine("_FORTIFY_SOURCE", "0")`)는 `project_zig_c_uapi_rule`에 있다.
      **검증 대상 바이너리의 컴파일 모드를 바꾸는 일이라 GL-M1이 범위 밖으로
      뒀다.** 게이트가 22분인 지금은 되재기가 싸다.
- [ ] **`sleep 0.3` 줄이기.** 약 6분짜리이고 실측 16이 근거지만, side effect
      우려로 GL 범위에서 뺐다. 다시 집을 때는 **타이핑 구간(셸이 줄을 편집하며
      프롬프트를 다시 그리는 자리)이 방향키 연타와 같은 여유를 갖는지**를 먼저
      확인한다. **CN-M0이 28키, CN-M1이 64키를 더했으므로 값이 계속 커지고
      있다** — 게이트 증가분 3분 31초의 대부분이 이것이다.
- [ ] **`fill` 하나의 비용을 따로 재기.** 첫 프레임 209밀리초의 출처가 셀 배경
      칠하기인지 `fill`의 102만 번 volatile 쓰기인지 안 갈렸다. **부분 갱신
      논의의 전제다.**
- [ ] **design doc 셋의 `Status:` 줄이 낡았다.** Config Persistence ·
      Power Management · Hardware Discovery가 "M0 미착수"로 남아 있는데
      게이트에는 `CP-M2` · `PM-M1` · `HD-M2`가 3/3으로 돈다. **CN design은 이
      빚을 새로 만들지 않았다** — CN-M0과 CN-M1을 닫으며 매번 갱신했다.
- [ ] **`ACPI_EC`와 `PNP_DEBUG_MESSAGES` 정리.**
- [ ] **`terminal/sanity/`의 수동 확인 도구 둘.** x86_64용이라 arm64 gcc로 못
      만든다. 필요하면 `zig cc -target x86_64-linux-gnu`. **빌드해서 돌려 본
      적이 없다.**
- [ ] **`terminal/vendor/fonts/Hanme_8x4x4.ttf`가 남아 있다.** `vendor/`가
      gitignore라 저장소에는 없다. 지워도 게이트는 안 흔들린다.
- [ ] **붙여넣기가 모드를 닫아야 하는가.** CM-M2가 "안 닫는다"로 정했다.
- [ ] **억제 분기를 진짜 상황으로 보기.** CM-M2의 검사 13이 밟는 것은
      붙여넣기 에코이고 **대역이다.** 진짜 이유인 백그라운드 출력으로 보려면
      copy mode 진입 전에 fish 백그라운드 잡을 띄워야 하는데 **타이핑 40여
      개와 회차당 15초**가 든다. 2026-08-26에 값을 저울질하고 안 하기로 골랐다.
- [ ] **`w`가 줄을 넘어 다음 줄의 첫 단어로 가야 하는가.** CN-M0이 "안 간다"로
      정했다 — 줄 사이 이동은 `j`/`k`가 하고, 다음 줄로 가려면 분기가 셋 는다.
      **CN-M1이 검색을 넣었으므로 줄 사이 이동의 주력이 `/`가 됐다** — 다시
      저울질할 값이 생겼고, 아마 여전히 "안 간다"가 맞다.
- [ ] **매치 하이라이트.** 화면의 모든 매치를 표시하는 것. `ViewportSearch`가
      그 용도로 있지만 `cells()`가 넘기는 색 결정에 손을 대야 한다.
      **CN-M1이 일부러 안 했다.**
- [ ] **검색 기록.** `/`를 다시 열었을 때 지난 needle을 되부르는 것. 지금은 빈
      검색어로 Enter를 눌러도 vim처럼 지난 검색어를 다시 쓰지 않는다.
- [ ] **`?`(아래로 검색).** design 결정 4가 뺐다 — "방향"이라는 상태가 하나 늘고
      `n`/`N`의 뜻이 그것에 따라 뒤집힌다.
- [ ] **매치를 못 찾았을 때 화면에 알리기.** 로그에는 `matches=0`이 남지만
      사람은 프롬프트가 닫히는 것 말고 아무 신호도 못 받는다. 상태줄이 없기
      때문이고, 그것을 만드는 것은 design 결정 7이 버린 안이다.

### 끝난 숙제 (지운 것을 다시 줍지 말 것)

- ~~copy mode의 단어 이동(`w`/`b`)~~ — **CN-M0이 2026-08-27에 끝냈다.**
- ~~copy mode의 검색(`/`)~~ — **CN-M1이 2026-08-27에 끝냈다.** `n`/`N`과
  프롬프트 오버레이까지 함께 들어갔다.
- ~~`clean()`에서 커널을 빼는 논의~~ — **GL-M0이 했다.** 이어서 GL-M1이
  `gzip -6`·`init`의 `ReleaseSafe`·커널 빌드 스킵으로 증분 회차를 더 깎았다.
- ~~`xterm-256color` terminfo를 initrd에 넣기~~ — TR-M2에서 했다.
- ~~게스트 안에서 Zig 에러 트레이스 읽기~~ — **이미 되고 있었다.**
- ~~`searchAll()`의 블로킹이 사람에게 느껴지는가~~ — **CN-M1이 쟀다. 60~70ms라
  안 느껴진다.** 증분 검색으로 옮길 이유가 지금은 없다.

## 핵심 파일

**줄 번호는 CN-M1 직후(2026-08-27) 기준이다.**

- `terminal/src/input.zig` — `handleKey`가 `Action`을 돌려주고 `readKeys`가
  `Keys`를 돌려준다.
  - `:28` `keymap` · `:160` `Action` · **`:184` `Copy` `union(enum)`(variant
    열아홉)** · `:195` `word_next` · `:197` `word_prev` · **`:218~231` 검색
    variant 일곱**(`find_open` · `find_char: u8` · `find_erase` ·
    `find_cancel` · `find_submit` · `find_next` · `find_prev`) ·
    `:235` `Keys` · `:243` `Keys.copies` · `:352` `State.copies` ·
    **`:359` `State.Mode`(`normal`·`copy`·`find`)** · `:458` `chord()` ·
    `:488` Meta 분기의 `KEY_V` · **`:585` find 분기(copy 표보다 **앞**이다 —
    이 순서가 `n`을 명령이 아니라 글자로 만든다)** · `:616` copy 표 시작 ·
    `:622~625` 방향키 넷 · `:630~631` 단어 이동 · **`:636` `/` ·
    `:648` `n`/`N`** · `:664` `KEY_V`의 세 갈래
- `terminal/src/vt.zig` — `Screen`. `cells()`가 색·inverse·선택·커서를 전부
  해소해 `CellGlyph`로 넘긴다.
  - `:55` `copy_cursor` · `:58` `copy_kind` · `:74` `copy_anchor_y` ·
    `:77` `copy_pruned` · `:83` `clip` · **`:96` `find_open` ·
    `:104` `find_buf`(128바이트) · `:118` `find`(`?search.Screen`)** ·
    `:194` `feed`(**가지치기 감시 + 대체 화면 감시**) · `:224` `anchorY` ·
    `:368` `copyExit`(**검색 상태도 여기서 버린다**) · **`:388` `findOpen` ·
    `:447` `findSubmit` · `:513` `findStep`(`/`의 첫 이동과 `n`/`N`이 함께
    쓰는 한 자리)** · `:577` `copyMove` · `:617` `WORD_BOUNDARY` ·
    `:662` `copyMoveWord` · `:734` `copyPlace`(뷰포트를 미는 두 갈래) ·
    `:797` `copyApply`(**모든 이동 수단이 통과하는 문**) · `:838` `copyYank` ·
    `:866` `clipboard`
- `terminal/src/main.zig` — `drawGlyph`·`render`·`dump*`, 그리고 `poll` 루프.
  **렌더는 루프 끝에 있고 `needs_redraw`가 문지기다.**
  - **`:91` `drawPrompt`(오버레이) · `:125` `render`(prompt 인자를 받는다) ·
    `:158` 오버레이를 그리는 자리(**present 바로 앞이다**) · `:165` `Prompt`** ·
    `:213` `dumpStyles`(**`overlaid_row`를 받아 덮인 줄을 건너뛴다**) ·
    `:346` `dumpCopy`(`@tagName`을 찍으므로 새 명령의 로그는 공짜다) ·
    **`:367` `dumpFind`** · `:387` `dumpClip` · `:411` `dumpPaste` ·
    `:594` copy 배선 switch(**`else`가 없다**) · `:706` `scrollToBottom` 억제 ·
    `:710` `copyTakePruned`
- `terminal/src/font.zig` — `Cache`(lazy 해시 맵) + `Glyph`. **코드는 폰트에
  무관하다.**
- `terminal/src/input_test.zig` — `:16` `expect` · `:59` `expectCopy`
  (**`:65`가 `std.meta.eql`을 쓰는 자리**) · `:497~` 검사 4의 "모르는 키"
  목록(**`n`이 빠졌고 `e`만 남았다**) · `:593~` CM-M2의 검사 11~13 ·
  `:637~` CN-M0의 검사 14~16 · **`:673~` CN-M1의 검사 17~23**
- `terminal/src/vt_test.zig` — `:356` `cm`(CM-M0·M1) · `:471` `pruned`(CM-M2) ·
  `:551` `wm`(CN-M0) · **`:664` `fm`(CN-M1의 프롬프트 검사 17~21) ·
  `:741` `fs`(CN-M1의 검색 검사 22~25)** · `:828` `PASS`. **새 검사는 자기
  화면을 새로 만든다.**
- `copy/check.sh` — 774줄. 검사 열다섯. `:108` `type_keys` · `:117` `key_lines` ·
  `:123` `copy_value` · `:134` `last_frame` · `:149` `scroll_field` ·
  `:161` `screen_count` · `:551~` CN-M0의 검사 14 ·
  **`:638~` CN-M1의 검사 15(스크롤백 검색)** · `:768` NUL 음성 검사.
- `check.sh` — `:35` `BUILD_STEPS` · `:42` `require_build_steps` · `:146`
  `CHAINS` 배열 · `:160` 진입 검사 · `:176` `clean` 호출 하나.
- `kernel/build.sh:53~58` — GL-M1의 스킵 판정. `:75`가 스탬프를 적는 자리다.
- `kernel/make_initrd.sh` 마지막 줄 — `gzip -6`. **`-9`로 되돌리지 말 것.**
- `init/build.zig:32` — `exe_mod`만 `.ReleaseSafe`다.
- `terminal/src/drm.zig:128`·`:138` — `setPixel`·`getPixel`. **범위 검사가
  없다.** 고치지 않고 호출부에서 막는다.
- `terminal/vendor_fonts.sh` — GNU ftp에서 unifont를 받고 sha256을 확인한다.

**기억.** `MEMORY.md`(색인) + `docs/decisions/`(본문). 새 세션은 협업 방식
feedback 셋과 **`feedback_plain_korean`(글쓰기 규칙 — 비유적 표현을 일반 어휘
자리에 쓰지 않는다. 평범한 한국어가 어색하면 영어를 섞는다)**,
**`project_copy_navigation`**, `project_copy_mode`,
`project_gate_latency`, `project_input_policy`, `project_terminal_rendering`,
`project_guest_environment`, `project_gate_chain_composition`,
`project_build_host_arch`, `project_kernel_config`, `project_zig_c_uapi_rule`을
먼저 읽을 것.

## IP-M2가 남긴 것 (그대로 이월)

- **`Ctrl+←`/`Shift+←`는 여전히 맨 `ESC [ D`로 샌다.** TUI 앱이 생기면 그때.
- **DECCKM(`ESC O` 분기)은 부팅 게이트가 영영 못 밟는다.** `input_test`가
  `Context.cursor_keys`를 주입해 대신 본다.
- **`keymap`에 comptime 앵커가 박혔다.** 표 중간에 줄을 끼우면 컴파일이 막힌다.
  `KEY_Z`도 그 앵커 중 하나다.

## TR-M2가 남긴 것 (그대로 이월)

- **`Terminal.ScrollViewport`의 이름이 `PageList.Scroll`과 다르다.**
  `.bottom`·`.delta`이지 `.active`·`.delta_row`가 아니다. **그리고 `.pin`이
  아예 없다** — CN-M0이 `copyPlace`에서 이것에 부딪혀 `Screen.scroll`로 갔다.
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
