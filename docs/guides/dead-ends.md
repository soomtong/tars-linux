# 시도했으나 안 되는 접근 (같은 벽에 다시 부딪치지 말 것)

`docs/guides/lessons.md`(허브)에서 2026-10-26에 떼어 냈다(LS-M0). 규칙 — 줄 번호를 적지 않는다, 낡은 항목은 고치거나
지운다, 서브프로젝트 하나에만 해당하는 것은 그 design에 — 은 허브의 것을 따른다.


- `sd '옛것' '새것' 파일 > 사본` 으로 사본 만들기(TS-M1) — `sd`는 파일
  인자를 받으면 in-place로 고친다. 그래서 이 줄은 사본을 만드는 것이 아니라
  저장소 파일을 고치고 빈 사본을 남긴다. mutation용 `/tmp` 사본을 만들 때는
  `cp`를 먼저 하고 사본에 대고 `sd`를 친다. `sed`의 감각으로 치면 걸린다.
- `zsh -f`를 "옵션만 없는 세션"으로 쓰기(SD-M0 실측 5) — `NO_RCS`가 히스토리
  저장을 통째로 끈다. `exit`에서도 SIGHUP에서도 파일을 안 만들고, `fc -W`를
  직접 치면 써진다. 그래서 `-f`는 대조군이 못 된다. 옵션 하나만 다르게 하려면
  rc를 읽은 세션에서 `unsetopt`를 친다.
- 컨테이너에서 잰 셸 동작을 게스트 값으로 그대로 읽기(BH) — 하루에 세 번
  걸렸다. 컨테이너에는 `/dev/fd`가 있고 게스트에는 없었으며(실측 13),
  `script`의 래퍼가 시그널을 가로챘고(실측 10), 비대화형 bash가
  `PROMPT_COMMAND`를 안 돌았다(실측 5). 셋 다 증상이 같다 — 에러가 없고, 값이
  나오고, 그 값이 틀렸다. 처방은 재기 전에 "재는 환경과 돌 환경이 무엇이
  다른가"를 먼저 적는 것이고, 모르겠으면 게스트에서 5분을 쓰는 것이다.
  `project_measuring_shells`에 사례 셋이 있다.
- 중첩 셸이 뜨자마자 타이핑하기(BH-M2) — rc를 읽는 동안 들어간 글자가 화면의
  에러 줄과 섞여 쪼개진다(`HIS` · `TF` · `HISTFI`를 실제로 봤다). 그 회차는
  통과했지만 운이었다. bash는 프롬프트가 `bash-5.2#`로 바뀌므로
  `wait_for_screen`으로 기다릴 수 있다. zsh는 프롬프트가 같아서 못 기다리고,
  그럴 때는 판정이 실패했을 때 조용하지 않은지를 대신 확인한다.
- mutation이 겨냥한 검사에 걸릴 것이라고 믿기(SL-M2) — 앞의 검사가 먼저
  죽인다. `.HUP`을 뺀 사본으로 음성 검사(`grace period expired`)를 겨냥했는데
  체인이 양성 검사(`missing shutdown log line: sent SIGHUP …`)에서 죽었다.
  판정 목록이 음성보다 앞에 있기 때문이다. 음성을 겨냥하려면 앞의 검사를
  통과시키는 mutation이 따로 필요하다 — 여기서는 "로그는 찍되 실제로는 안
  보내는" 사본이었다(`if (sig != .HUP) _ = linux.kill(-1, sig);`). 그 회차에서
  marker에 `found … sent SIGHUP …`이 찍힌 채로 음성이 잡았고, 그것이 검사
  둘이 서로 다른 것을 본다는 증명이다.
- 호스트 검사가 지키는 줄을 뺀 mutation을 마운트 하나로 보기(SD-M2) — seed에서
  `setopt` 줄을 빼면 `config_test.zig`의 역방향 검사가 부팅 전에 죽여서
  게이트가 그 줄을 보는 자리까지 못 간다. 그 loop 한 줄도 함께 눕힌 사본을
  둘째 마운트로 준다. M1이 값을 한다는 증거이기도 하다.
- 셸이 실행했어야 할 명령의 흔적이 없는 것으로 "잃었다"를 판정하기(SD-M0) —
  "애초에 안 쳐졌다"와 안 갈린다. 첫 회차가 그 상태였다. 먼저 그 명령이
  실행된 증거(입력 줄과 출력)를 로그에서 보고, 그 다음에 기록이 없는 것을
  판정한다.
- `sendkey lang1`로 한/영 키를 게스트에 보내기(HI-M0) — QEMU가 이름은
  받아들이는데(에러가 없다. `sendkey hangul`은 `invalid parameter`를 내므로
  `lang1`이 유효한 QKeyCode인 것은 확실하다) PS/2 스캔코드로 옮기는 자리에서
  조용히 버린다. 게스트에 `atkbd: Unknown key pressed` 경고조차 안 뜬다.
  `lang2`(한자)도 같다. 대조군 `a`(30)·`shift`(42)·`caps_lock`(58)은 전부
  도착한다. 안 해 본 우회는 `-device usb-kbd`다 — RM이 `USB_SUPPORT`를
  켜고 `machine/check.sh`가 `qemu-xhci` + `usb-kbd` + `i8042=off`로 이미
  부팅하므로 장애물은 사라졌고 시도만 안 해 봤다.
- 자판 표를 사람이 읽어서 기대값 적기(HI-M0) — plan을 쓰는 동안 두벌식
  표를 두 번 잘못 읽었다(`g`를 ㄱ으로 봐서 `ghk`를 "과"로 적었는데 `g`는
  ㅎ이라 "화"다). 컴파일도 통과하고 검사만 빨갛게 나오므로 원인이 코드인지
  기대값인지 안 갈린다. 처방은 `hangul.zig`의 `comptime` 앵커이고
  `input.zig`가 `keymap`에 같은 못을 박았다.
- 셸 heredoc으로 한글이 든 Zig 파일을 컨테이너에 넣기(HI-M0) — 중첩된
  따옴표를 거치면서 UTF-8이 깨져 `'ㄱ'`이 `invalid token`이 된다. Write
  도구로 호스트에 쓰고 `-v`로 마운트한다.
- QEMU에 넘길 FIFO를 `exec 4>`로 열기(CC-M0) — 쓰기 전용 `open(2)`이 읽는
  쪽을 기다리는데 그 읽는 쪽인 QEMU는 다음 줄에서야 시작한다. 증상이 에러가
  아니라 아무 말 없이 멈추는 것이다. `exec 4<>`로 연다.
- fish에 넣을 글로브를 괄호로 감싸기(CC-M0) — fish에서 `(...)`는 command
  substitution이라 글로브의 첫 경로가 명령으로 실행되고 implicit cd가 그
  디렉터리로 들어간다. 증상은 프롬프트의 경로가 바뀌는 것이다.
- `--platform linux/amd64`로 x86_64 도구를 돌리기(CC-M0) — 두 devcontainer
  이미지가 둘 다 arm64이고 컨테이너에 `qemu-x86_64`(user mode)가 없다.
  x86_64 라이브러리는 링크부터 안 된다(`ld.lld: ... is incompatible with
  elf64-littleaarch64`). 근거는 `project_build_host_arch`다.
- `cells()`가 격자 전체를 준다고 믿기(RC-M0) — `vt.zig`의 `cells()`가 글자도 없고
  배경도 기본인 셀을 뺀다. `ls` 뒤 화면이 7,285개가 아니라 911개다.
  화면 전체를 전제로 픽셀 수를 세면 여덟 배가 틀린다.
- 어떤 구간을 건너뛰는 것을 `continue`로 흉내 내고 "그 구간을 뺐다"고
  읽기(RC-M0) — 쓰기는 줄어도 루프는 그대로 돈다. 여백만 칠하는 what-if를
  그렇게 썼다가 "프레임버퍼 전체를 훑는 비용"을 쟀다. 재려는 것을 실제로
  안 하는 형태로 써야 한다(사각형 넷만 돌기).
- 구간 합이 `total`과 맞는 것으로 "제대로 쟀다"고 읽기(RC-M0) — 그 검산은
  "못 잰 구간이 없다"만 말한다. 잘못 잰 값도 합에는 정확히 들어간다.
- 시간을 재는 구간 안에 `std.debug.print`를 두기(RC-M0) — 시리얼 한 줄이
  0.6~8.8밀리초다. 재는 것이 코드가 아니라 콘솔이 된다.
- 같은 일을 하는 구간의 비용을 중앙값으로 비교하기(RC-M0) — 이 환경은
  잡음이 커서 같은 구간의 폭이 3~18배다. 고정된 일은 최소값으로 비교한다 —
  간섭이 가장 적었던 회차다. 중앙값으로 보면 여백 칠하기가 `fill`보다 픽셀당
  비싸 보이는데 최소값으로 보면 8.11 대 8.27로 같다.
- `terminal: key>` 줄로 붙여넣기를 감지하기 — 붙여넣기는 `pty.write`를 직접
  부르지 `keys.bytes`를 거치지 않는다. 거꾸로, `key>` 줄을 세는 것은 "모드
  안의 키가 PTY로 안 샜다"의 좋은 도구다.
- `terminal: key>` 줄 수로 "키가 몇 개 도착했나"를 세기(GL-M2) — `readKeys`가
  한 번의 `read()`에 여러 키를 실어 오면 `key> 3 byte(s)`처럼 한 줄이다.
  타이핑이 빨라지면 배칭이 늘어 줄 수가 오히려 준다. 세려면 바이트 합을
  본다: `grep -aoE 'key> [0-9]+ byte' … | awk '{s+=$2} END {print s}'`.
- 한 색만 세는 음성 검사를 그대로 두기(SP-M0) — 그 색이 안 쓰이게 되면
  아무것도 안 보는 검사가 된다. 안 고쳐도 초록이라 조용히 지나간다.
  `vt_test`의 검사 31과 게이트 검사 16의 음성 판정이 둘 다 그랬다.
- `vt.zig`에서 `ci`·`mi` 같은 짧은 이름을 새 capture에 쓰기(SP-M0) —
  `findSpans`의 안쪽 루프가 이미 `ci`를 쓰고 있다. 이름 충돌 확인을
  `vt_test`에만 걸면 안 된다. 그리고 처방은 이름을 바꾸는 것보다 capture를
  안 만드는 것이 낫다(`opt != null and opt.? == x`).
- 게이트 로그를 조사할 때 `grep`을 넓게 잡고 `head`로 자르기(SP-M0) —
  `scroll>`·`copy>` 줄이 프레임마다 쏟아져서 보려던 `find>` 줄에 닿기 전에
  잘린다. 찾을 줄로 `grep`을 좁힌다.
- 무엇을 볼지 모르는 조사에서 `grep`을 미리 좁히기(2026-08-30) — 위 항목의
  처방이 여기까지는 못 간다. 좁힌 `grep`도 "그 줄을 볼 생각을 했어야"
  맞는다 — 이번에 답을 준 `copy> enter row=0 col=0`은 애초에 찾을 목록에
  없던 줄이다. 로그를 통째로 `out/`(gitignore) 아래로 `gzip`해서 빼내고 여러
  각도로 본다.
- 모드를 나갔다 들어와 같은 검색을 다시 하면 같은 자리에 설 것이라고
  믿기(2026-08-30) — `copyExit`이 뷰포트를 안 되돌리고 `copyEnter`가 커서를
  `{0, 0}`에 두므로 커서가 직전 매치 위에 서고, `above_only`가 그것을
  건너뛴다. 한 칸 더 위에 선다.
- 게이트에 이미 있는 needle을 더 심기(SP-M0) — 검사 15와 17이
  `matches=4`를 판정에 쓰므로 `findme`를 하나 더 심으면 그 숫자가 깨진다.
  새 검사는 새 글자를 쓴다.
- `sendkey`로 대문자 치기 — 키 이름이 전부 소문자다. `shift-f`를 쓴다.
- "화면에 표적이 없다"로 "스크롤백으로 밀려났다"를 판정하기 — "애초에 안
  쳐졌다"와 안 갈린다. 실제로 쳐졌는지는 `find> type needle=…`로 따로 본다.
- `matches`로 "빈 Enter가 지난 검색어를 되불렀다"를 판정하기(CS-M1) —
  되부른 것이 실패한 검색어이면 0이 나오고, "빈 Enter가 아무 일도 안 했다"도
  0이 나온다. 되부를 검색어가 매치를 갖는 것을 먼저 확보하거나(게이트의
  검사 17), `findMissed()`가 다시 needle을 주는 것으로 본다(`vt_test`의
  검사 35).
- `find> submit matches=0`으로 "화면에 못 찾았다고 쓰였다"를 판정하기 —
  그것은 검색의 결과이지 그린 것이 아니다. 오버레이는 `screen>`에도
  `style>`에도 안 나오므로 `find> overlay text=…`로 따로 본다.
- `ScreenSearch.matches()`가 준 슬라이스를 `select()` 뒤에도 쓰기 —
  `reloadActive()`가 원소를 전부 해제한다. `refreshMatches()`로 다시 뜬다.
- 그 슬라이스의 원소를 `deinit`하기 — 얕은 복사라 이중 해제다. 바깥
  슬라이스만 `free`한다.
- 매치를 반전으로 표시하기 — 선택 안에서 두 번 뒤집혀 상쇄된다.
- 매치마다 `pointFromPin`을 부르기 — 뷰포트 위의 pin에서 목록 끝까지 훑는다.
- struct의 필드 사이에 `const` 선언을 끼우기 — Zig가 막는다. 파일 스코프나
  필드 뒤로 옮긴다.
- `&screen.term.screens.active` — `active`가 이미 포인터라서 `**Screen`이
  되고 `does not support field access`로 막힌다. `&` 없이 쓴다.
- `Terminal.scrollViewport`로 특정 pin에 뷰포트 맞추기 — `ScrollViewport`에
  `.pin`이 없다. `screens.active.scroll(.{ .pin = p })`을 쓴다.
- `pointFromPin(.viewport, …)`의 null만 보고 "화면 안이다"로 판정하기 —
  위쪽 밖만 null이고 아래쪽 밖은 큰 y를 그냥 준다. `y >= rows`를 따로 본다.
- `vt.Screen`을 새로 만들고 곧바로 `copyMove`를 부르기 — `copyEnter`가
  `state.cursor.viewport`를 읽는데 `cells()` 전에는 null이다.
- 선택이 무효가 된 것을 `selection == null`로 감지하기 — 앵커의 screen
  좌표를 비교한다.
- tagged union을 `==`로 비교하기 — Zig가 막는다. `std.meta.eql`을 쓴다.
- `render` 밖에서 오버레이 그리기 — `render`가 `fb.present()`로 끝나므로
  그 안에서 present 앞에 그려야 한다.
- 게이트 stdout에서 시리얼 로그의 줄을 `grep`하기 — 그 줄은 stdout에 없고
  체인이 만든 `mktemp` 파일 안에 있다.
- NUL이 든 로그를 `-a` 없이 `grep`하기 — `Binary file ... matches`만 나온다.
- `grep -qP '\x00'`으로 NUL 검출 — GNU grep 3.11에서 매치되지 않는다. 그리고 파일을
  두 번 읽는 판정(`tr -d '\0' | wc -c`와 `wc -c`의 비교)은 QEMU가 아직 쓰는 중이면 두
  값이 어긋나 거짓 빨강이다 — 한 번 읽는 `[ "$(tr -cd '\0' < "$f" | wc -c)" -eq 0 ]`로
  센다(AL-M1이 pointer · copy · render · pane의 NUL 검사를 그렇게 고쳤다).
- 파이프라인 끝에 `grep -q`를 두기 — 첫 매치에서 빠져나가며 앞단에
  SIGPIPE를 일으키고 `pipefail`이 그것을 실패로 판정한다. 이제 루트 게이트의
  진입 검사가 막는다(GA-M1).
- 그 위험을 "로그가 파이프 버퍼(64KiB)보다 크면 터진다"로 읽기(GA-M0) —
  앞단 출력이 버퍼의 3분의 1일 때 이미 터진다. 앞단 `grep`이 약 4KB 블록으로
  나눠 쓰므로 임계는 버퍼가 아니라 그 블록이고, 읽는 쪽이 닫혔으면 버퍼가
  비어 있어도 쓰는 순간 SIGPIPE가 난다.
- 그 위험을 바이트 수 하나로 재기(GA-M0) — 변수가 셋이다(앞단 출력량 ·
  앞단이 입력을 훑는 시간 · 뒤단이 나가는 지점). 같은 2만 바이트가 한
  실험에서 80% 터지고 다른 실험에서 200/200 안전했다. "몇 바이트부터
  위험하다"로 고칠 자리를 고를 수 없다.
- 평시에 앞단 출력이 0줄인 것으로 그 검사가 안전하다고 읽기(GA-M0) —
  `config/check.sh`의 한 검사가 그 모양이었다. 앞단이 커지는 때가 바로 그 검사가
  빨개져야 하는 때라, 검사가 망가지는 조건과 검사가 필요한 조건이 같다.
  합성한 음성 상황으로만 보인다.
- `check.sh`의 사본을 `/tmp`에서 돌려 진입 검사만 보기(GA-M1) — 맨 위의
  `cd "$(dirname "$0")"`가 작업 디렉터리를 `/tmp`로 옮겨 체인 파일을 전부 못
  찾고, 증상이 lint의 거짓 양성과 똑같이 생긴다. 잘라낸 사본에서 그 줄을
  빼고 돌린다.
- 긴 빌드를 `| tail`로 감싸고 종료 코드 믿기 — 파이프의 종료 코드는 `tail`의
  것이다.
- `rg`에 `-r`을 "recursive"로 쓰기 — `-r`은 replace다. 재귀는 기본 동작이다.
- `rg`에 `-E`를 "extended regex"로 쓰기 — `-E`는 `--encoding`이다.
- Bash 도구에서 `cd`로 옮겨 다니기 — 작업 디렉터리가 호출 사이에 남는다.
  조사성 명령은 저장소 루트 기준 상대 경로를 그대로 쓴다.
- `std.time.Timer` / `std.posix.clock_gettime`으로 시간 재기 — Zig 0.16부터
  둘 다 없다(0.17도 같다). `std.Io.Clock.now(.awake, io)`이고 단조 시계 이름이
  `.monotonic`이 아니라 `.awake`다. 경과는 `t0.untilNow(io, .awake).nanoseconds`.
  `vt.Screen`이 `io`를 필드로 든 이유가 이것이다(CS-M0).
- `std.posix.getenv` — Zig 0.16부터 없다(0.17도 같다).
- 배열 반복 `"a" ** 32` — 0.17에는 없다. `binary operator '*' has whitespace on one side, but not the other`로
  막힌다. 검사의 긴 글자는 그대로 적는다(HC-M1).
- Zig의 multiline 문자열(`\\`)에 탭 넣기 — 거부한다. 탭이 든 글자는 `"\t"`로
  잇는다(TC).
- `linux.W.TERMSIG`를 숫자와 비교하기 — enum이다(TC).
- `@embedFile`로 모듈 뿌리 밖의 파일 읽기 — 못 읽는다. `kernel/dictation/tars-dictate`의
  키 여덟은 호스트 검사가 런타임에 읽는다(TC).
- `std.fmt.bufPrint`로 넘칠 수 있는 줄 만들기 — 넘쳤을 때 얼마나 썼는지를 안 돌려준다.
  `Writer.fixed`를 쓴다. 한글이 버퍼 끝에 정확히 맞으면 온전한 글자까지 떼던
  `logline.zig` 첫 원형의 버그는 경계값 검사(2048 · 2049 · 음절이 걸침 · 정확히
  맞음)가 잡는 자리다(AL).
- `logline.zig`를 공용 모듈(`b.path("../…")`)로 하나만 두기 — 컨테이너 Zig에서 서기는
  하지만 그 파일을 import하는 호스트 검사 모듈 열다섯에 `addImport`가 필요하다. 사본
  둘 + 진입 검사의 cmp가 더 싸다(AL).
- 컨테이너에서 `rg` 쓰기 — 없다. `grep -aE`를 쓴다.
- 컨테이너에서 `nc`로 QEMU monitor에 명령 보내기 — `nc`가 없다. 체인들은
  `exec 3<>/dev/tcp/127.0.0.1/PORT`를 쓴다.
- `/tmp`에 만든 파일이 `docker run --rm` 사이에 남기 — 안 남는다.
- 임시 Zig 프로젝트의 path 의존에 절대 경로 쓰기 — `expected path relative
  to build root`로 막힌다. 심볼릭 링크로 우회한다.
- 루트 게이트를 Bash 도구의 기본 타임아웃으로 돌리기 — 46분이라 상한을
  넘는다. `run_in_background`로 돌린다.
- `git cherry-pick`에 `-q`를 붙이기 — 그런 옵션이 없다.
- `vt_test`의 검사를 남의 화면에 붙이기 — 화면마다 크기와 history가 다르다.
  CM-M1이 `cm`, CM-M2가 `pruned`, CN-M0이 `wm`, CN-M1이 `fm`·`fs`, CS-M0이 `hs`,
  CS-M1이 `ls`를 새로 만들었고 그래서 앞 검사들을 하나도 안 흔들었다.
  `hs`와 `ls`는 모양이 같다(20x5, 8·18번 줄이 표적) — 게으름이 아니라
  기대값(`matches=2`)을 옮겨 쓰기 위한 것이다.
- `vt_test`에서 지역 변수 이름을 겹쳐 쓰기 — `main()` 하나가 파일 전체라 이
  파일의 모든 지역 변수 이름이 서로 부딪치고, Zig는 shadowing을 컴파일
  에러로 막는다. CM-M0이 `before`/`after`를, CS-M0이 `painted`를 이미
  쓰고 있었다. 새 검사를 쓰기 전에 이름을 `rg`로 먼저 확인한다 — CS-M1은
  `ls`·`ls_i`·`lhit`~`lhit5`·`lmiss`·`lmiss2`를 미리 확인하고 썼고 한 번도 안
  부딪쳤다.


## 조사용 Zig 프로그램을 저장소 밖에서 돌리는 법

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

`ghostty-vt`를 import해야 하면 이 방법이 안 된다. 대신 기존 검사 파일
자리에 마운트해서 `zig build test`로 돌린다.

CS-M0이 쓴 더 나은 방법이 하나 있다. `vt.zig` 자체를 디버그 출력이 든
사본으로 갈아 끼우는 것이다 — 저장소 파일은 한 글자도 안 바뀌고, 라이브러리가
준 값을 그 자리에서 볼 수 있다. `matches()`의 `0xAA`를 이렇게 찾았다.

```bash
# 사본을 만들어 print를 끼운 뒤
docker run --rm -v "$PWD":/workspace \
  -v /tmp/vt_debug.zig:/workspace/terminal/src/vt.zig:ro \
  -w /workspace/terminal tars-devcontainer bash -c 'zig build test'
```

주의 둘. (1) `-v`로 없는 파일을 마운트하면 Docker가 호스트에 빈 파일을
만들어 마운트 지점으로 쓰고 컨테이너가 끝나도 그 0바이트 파일이 남는다.
(2) `cp -r terminal /tmp/t`로 트리를 복사하는 방법은 1.5GB라 느리다.

CM-M1도 CM-M2도 CN-M0도 CN-M1도 CS-M1도 프로브를 안 돌렸다. 대신
`terminal/ghostty-src/src/terminal/`과 우리 소스를 직접 읽어서 계약을 확인하고,
그것을 검사로 옮겨 실행으로 다시 증명했다. 소스를 읽어 얻은 사실은 반드시
검사로 옮긴다. CS-M0에서 그 규율이 값을 했다 — 소스가 말해 주지 않은
`matches()`의 수명이 실행에서만 드러났다.

