# PE-M1 — 자식이 모드 2004를 켰으면 붙여넣기를 감싼다

Date: 2026-10-04
Design: `docs/specs/2026-10-04-tars-paste-ergonomics-design.md`
Status: 끝났다(2026-10-04). 실측은 맨 아래 "PE-M1이 실측한 것" 절에 있다.

## 누가 무엇을 하나

design 결정 9. Task 0~6은 구현 서브에이전트(Opus)가 한다. Task 7(루트 게이트 · 실측 절 · commit)은
lead가 한다. 구현자는 commit하지 않고, 끝에 `git diff --stat` · `git diff | rg '^-'` · 각 Task의 명령
출력을 그대로 보고한다. 이 plan의 "실측한 것" 절은 구현자가 고치지 않는다.

구현자는 main 작업 트리에서 직접 편집한다(지금 루트 게이트가 돌고 있지 않다 — Task 0-1이 확인한다).

| 파일 | 무엇을 |
|---|---|
| `terminal/src/vt.zig` | 새 함수 `pasteParts`(`clipboard()` 바로 뒤), `findPaste` doc 주석의 세 줄 |
| `terminal/src/main.zig` | `dumpPaste`의 doc 주석 한 문단과 본문 두 줄 |
| `terminal/src/vt_test.zig` | 헬퍼 `peExpectParts`(`cuExpectMark` 바로 뒤), 검사 93~96(`PASS` 바로 앞) |
| `copy/check.sh` | 머리 주석 두 줄, 검사 21 · 22(검사 20 뒤, NUL 음성 검사 앞) |

고치는 자리는 심볼과 `rg` 패턴으로 적는다. 줄 번호는 2026-10-04 `d237fb2` 기준의 참고값이다.

모든 명령은 저장소 루트에서 친다. 서브에이전트의 Bash는 호출마다 작업 디렉터리가 돌아가므로
명령 앞에 `cd /Users/dp/Repository/tars-linux &&`를 붙인다. Zig 빌드는 언제나 컨테이너에서 한다 —
호스트 `PATH`의 zig는 0.17이고 컨테이너는 0.16.0이다(ghostty가 0.16을 요구한다). 측정용 파일은
`/tmp/run/pem1/` 아래에 둔다. `/tmp/run/pe1`이 아닌 이유는 그 이름을 PE-M0의 lead가 다섯 번 돌리기의
1회차 디렉터리로 이미 썼기 때문이다.

## 이 milestone이 끝나면

- 포커스 패널의 자식이 모드 2004를 켠 상태에서 `Cmd+V`를 누르면 `dumpPaste`가 `ESC[200~` · 본문 ·
  `ESC[201~`를 `pty.write` 세 번으로 쓴다. 모드가 꺼져 있으면 본문만 한 번 쓴다 — PE-M1 전과 같은
  바이트다.
- 로그 줄이 `terminal: clip> paste len=N bracketed=1`(또는 `=0`)이 된다. `len=`은 여전히 본문의
  길이라서 `copy/check.sh`의 기존 판정 셋(`clip> paste len=11`)은 고치지 않는다.
- 게스트의 zsh · bash · fish에서 여러 줄을 붙여도 Enter 전에는 실행되지 않는다. vim insert 모드에서
  붙여도 `autoindent` 계단이 없다. GE 위험 2의 우회(`:set paste`)가 필요 없어진다.
- `vt_test`가 검사 96까지, `copy` 체인이 검사 22까지 간다.
- 검색 프롬프트로 가는 갈래(`dumpFindPaste`)와 `.paste =>` 분기는 안 바뀐다(design 결정 6).

## 착수 전에 확정한 것

1번 · 2번 · 3번은 2026-10-04에 이 plan을 쓰며 잰 것이다. 방법은 design 실측 1 · 4와 같다 —
`tars-devcontainer` 이미지에 fish `4.0.2-1`(arm64, sysroot와 같은 판) · python3 · pyte를 깐 측정
컨테이너를 띄우고, python `pty.fork`로 47 × 100, `TERM=xterm-256color`, `LANG=C.UTF-8`, 빈 `HOME`으로
fish를 띄웠다. 화면은 fish의 출력을 pyte에 먹여 복원하고, 행을 ` | `로 이어 `terminal: screen>`와 같은
모양으로 찍었다(pyte가 잘못 읽는 `CSI = 5 u` · `CSI > 4 ; 1 m`은 먹이기 전에 걷어냈다). 측정
스크립트는 `/tmp/run/pem1/pe1_probe*.py`이고 측정 컨테이너는 지웠다.

1. design mutation 3의 미측정 — 머리와 본문만 쓰고 꼬리(`ESC[201~`)를 빠뜨리면. fish 4.0.2는 붙인
   글자를 하나도 그리지 않는다. 그 뒤에 보낸 Enter(`\r`), `echo AFTER\r`, ctrl-c(`\x03`)에도 출력이 0
   바이트였다(각 2~3초, 합계 11초). fish가 꼬리를 기다리며 그 뒤의 키를 전부 붙여넣기의 일부로 삼키는
   것이다. 그래서 design이 예상한 "검사 21의 6단계가 빨개진다"가 아니라, 그 앞인 4단계("붙인 둘째 줄이
   입력줄에 나타난다")에서 빨개진다. 붙여넣기 줄(`clip> paste len=21 bracketed=1`)은 우리 코드가 찍으므로
   그대로 나오고, 화면의 `echo PETWO` 수가 안 늘어서 15초를 다 쓴다. 기대 문구는 Task 4의
   `the pasted lines never showed up on the fish command line ('echo PETWO' stayed at N)`이다.

   감싸지 않은 붙여넣기(design mutation 1의 모양)도 같은 하네스로 다시 봤다. 첫 줄이 곧바로 실행되어
   `| PEONE |` 행이 생기고, 둘째 줄은 새 프롬프트의 입력줄에 남는다(`echo PETWO` 수가 2 → 3). 그래서
   mutation 1은 4단계를 지나 5단계에서 빨개진다 — design 그대로다.

2. 감싼 두 줄을 받은 fish의 화면. 검사 21의 흐름(ctrl-l · 명령을 쳐서 두 줄을 만든다 · 붙인다 ·
   Enter)을 그대로 돌렸다. 붙인 직후의 화면:

   ```
   screen> root@… /workspace# echo echo PEONE; echo echo PETWO | echo PEONE | echo PETWO | root@… /workspace# echo PEONE |                               echo PETWO
   ```

   fish는 입력줄을 두 행으로 그리고, 둘째 행을 첫 행의 명령 시작 열에 맞춘다. 맞추는 방법은 공백이
   아니라 커서 이동(`ESC[30C`, 컨테이너의 프롬프트 폭 30)이다 — 원본 바이트가
   `echo PEONE\r\n\x1b[K\x1b[30Cecho PETWO…`였다. 우리 `dumpScreen`은 글자 없는 셀(codepoint 0)을
   건너뛰므로 게스트의 `screen>`에서는 그 행이 `| echo PETWO |`로 나올 것이다(게스트에서는 Task 5가
   본다). 어느 쪽이든 마지막 프레임의 `echo PETWO` 수가 하나 는다(2 → 3). design 결정 5의 4단계는
   참이다. Enter 뒤에는 `… | PEONE | PETWO | root@… /workspace#`로 두 행이 연달아 생겼다(6단계도 참).

   덤으로 하나를 봤다. fish 4.0.2는 모드 2004를 프롬프트 내내 켜 두지 않는다. 출력에서 마지막으로 본
   `?2004h` / `?2004l`을 상태로 삼아 세 번 돌렸고, 세 번 다 같았다.

   | 그 순간 | 모드 |
   |---|---|
   | 빈 프롬프트(명령을 실행하고 돌아온 직후 · ctrl-l 뒤 · ctrl-c 뒤) | 켜짐 |
   | `echo`까지 쳤을 때 | 켜짐 |
   | `echo h`까지 쳤을 때(인자를 치기 시작했을 때) | 꺼짐(`ESC[?2004l`), 10초를 기다려도 꺼진 채다 |
   | 감싼 두 줄을 받은 직후 | 꺼짐(`l h l`) |
   | 그 상태에서 키를 하나 더 친 뒤, 또는 Enter 뒤 | 다시 켜짐 |

   원인은 안 팠다. 결과는 이렇다 — 사람이 fish 입력줄에 인자를 치던 중에 여러 줄을 붙이면 그 순간
   모드가 꺼져 있을 수 있고, 우리 터미널은 모드를 따르므로 감싸지 않는다. 그러면 첫 줄이 Enter 없이
   실행된다. ghostty 앱도 같은 값(`modes.get(.bracketed_paste)`)을 보므로 같은 일을 겪는다. 이 plan은
   이것을 고치지 않는다(design 결정 2의 규칙 그대로 둔다). 대신 Task 7에서 lead가 design 위험에 한 줄
   더할 것을 권한다. 게이트는 영향을 안 받는다 — 검사 21의 붙여넣기는 명령을 실행하고 돌아온 빈
   프롬프트에서 일어나고, 그 사이의 copy mode 키는 pty로 안 간다. 그 상태가 "켜짐"인 것을 위 세 번이
   봤다.

3. `cat` 아래에서 감싸지 않은 두 줄. fish는 `cat\r`을 받자 OSC 133;C 바로 뒤에 `ESC[?2004l`을
   보냈다(응답의 47바이트째). 그다음 감싸지 않은 21바이트를 한 번에 쓰면 원본 응답이 이랬다.

   ```
   b'echo PEONE\r\necho PETWOecho PEONE\r\n'
   ```

   tty가 21바이트를 받은 자리에서 한꺼번에 되울리고(`echo PEONE` · 개행 · `echo PETWO`), 그 뒤에
   `cat`이 첫 줄을 읽어 다시 쓴다. 그래서 `cat`의 출력이 둘째 줄의 에코 바로 뒤에 붙는다. 화면은
   `| echo PEONE | echo PETWOecho PEONE`이다. design 결정 5 검사 22의 3단계가 예상한
   `| echo PEONE | echo PEONE | echo PETWO`(에코 · 출력 · 둘째 줄의 에코)와 순서가 다르다. 에코와
   `cat`의 출력 사이의 순서는 커널의 스케줄이 정하므로, 이 plan은 화면의 모양에 기대지 않고
   `echo PEONE`의 개수가 둘 느는 것으로 판정한다(Task 4). `echo PETWOecho PEONE`에도 `echo PEONE`은
   하나이므로 두 순서 모두에서 +2다.

   ctrl-c로 `cat`을 끝내면 fish가 `^C`를 찍고 프롬프트를 `root@… /workspace [SIGINT]#`로 다시 그리며
   `ESC[?2004h`를 보낸다. 감싼 붙여넣기를 `cat`에 주면(mutation 2의 모양) 화면이
   `| ^[[200~echo PEONE | echo PETWO^[[201~echo PEONE`이었다 — design 실측 4대로 `[200~`가 화면에 찍히고,
   `echo PEONE`은 이때도 +2다(`cat`이 다시 쓴 `ESC[200~`는 터미널이 시퀀스로 먹는다). 그래서
   mutation 2를 잡는 것은 양성 판정이 아니라 음성 판정(`[200~`)이다.

4. `vt_test`. 마지막 검사는 92이고 그 뒤가 `std.debug.print("PASS\n", .{});`(2545줄)다. 화면은
   `vt.Screen.init(init.io, init.gpa, 20, 5, CELL)`로 만들고 `defer x.deinit();`을 붙인다. 바이트는
   `x.feed("…")`로 먹인다. `Screen`이 `Terminal`과 `Stream`을 수명 내내 들고 있어서 시퀀스를 두 번의
   `feed`로 나눠도 파서 상태가 남는다(`Screen`의 doc 주석). 실패는
   `std.debug.print("FAIL: …")` 뒤에 `return error.이름;`이고, 통과는
   `std.debug.print("vt_test: … OK\n", .{});`다. `main()` 하나가 파일 전체라 지역 변수 이름이 서로
   부딪친다(lessons) — 새 이름의 접두 `pe_`는 지금 파일에 0개다. 실행은 컨테이너에서
   `-w /workspace/terminal`로 `zig build test`이고(`build.zig`의 `test` 스텝이 `vt_test`를 포함한 일곱을
   돌린다) 따뜻한 캐시에서 3.6초, `.zig-cache`와 `zig-out`을 지운 뒤에는 45.6초였다. 출력은 일곱 검사
   파일의 줄이 섞여 나오고, `^PASS` 줄은 다섯이다(일곱 중 다섯이 끝에 `PASS`를 찍는다). Zig 0.16의 `{any}`는 `[]const u8`을
   `{ 27, 91, 50, 48, 48, 126 }`처럼 바이트 숫자로 찍는다(컨테이너에서 확인) — 새 헬퍼가 그것을 쓴다.

5. `copy/check.sh`. 헬퍼는 `type_keys`(`gate_lib.sh`, 키마다 로그가 자랄 때까지 최대 0.3초 기다린다) ·
   `wait_for_screen`(`gate_lib.sh`, 로그의 모든 `screen>` 줄에 ERE를 건다, 15초) · `screen_count`(마지막
   프레임의 `screen>`에서 고정 문자열의 개수, `grep -oaF`) · `copy_value`(마지막 `copy>` 줄의 값) ·
   `report_failure`다. 키 이름은 `meta_l-shift-c`(copy mode) · `k` · `j` · `shift-v` · `y` · `meta_l-v`
   (붙여넣기) · `ret` · `esc` · `ctrl-l`(fish가 화면을 지운다, `hangul/check.sh` 765줄) · `ctrl-c` ·
   `semicolon`(`tools/check.sh` 779줄)이다. 검사 20은 copy mode 안에서 `k`를 치고 끝난다(1136줄
   `echo "the next key cleared the match number"`). 그 뒤가 빈 줄과 NUL 음성 검사(1138줄)이고, 마지막
   줄이 `echo "CM-M2 check PASS"`다. 체인 시간은 2026-10-04 CU-M0 루트 게이트에서 2분 31초였다 —
   Task 0-4가 지금 값을 잰다.

6. 모드를 읽는 API. `ModeState.get(self: *const ModeState, mode: Mode) bool`(`modes.zig` 47줄)이고
   상태는 `Terminal.modes` 필드(`Terminal.zig` 83줄)다. `get`이 `*const`를 받으므로
   `pasteParts(self: *const Screen, …)`에서 `self.term.modes.get(.bracketed_paste)`가 그대로 된다.
   ghostty 앱도 같은 호출을 쓴다(`src/input/paste.zig` 11줄). RIS는 `stream.zig`의 `'c'` 갈래(2699줄)가
   `full_reset`을 부르고, `Terminal.fullReset`이 `self.modes.reset()`(4672줄)으로 모드를 끈다. 지금
   `terminal/src/`에는 `modes.get` · `bracketed_paste`가 한 자리도 없다.

7. 갈래 표지(`bracketed=`)를 보는 자리를 design에서 옮겼다. design 결정 5는 검사 21의 4단계와 검사
   22의 2단계에서 `bracketed=1` · `bracketed=0`을 보지만, 이 plan은 두 검사 모두 화면 판정이 다 끝난
   뒤 맨 끝에서 본다. 그 앞에서는 `clip> paste len=21 `(끝의 공백까지)로 붙여넣기가 도착했다는 것만
   본다. 이유는 mutation이다. 필드를 앞에서 보면 mutation 1(감싸지 않는다)과 mutation 2(언제나
   감싼다)가 둘 다 필드에서 먼저 잡혀서, 화면 판정이 그 고장을 실제로 잡는지를 아무도 확인하지 못한다.
   필드를 맨 끝에 두면 mutation 1은 검사 21의 화면(5단계)이, mutation 2는 검사 22의 화면(`[200~`)이,
   mutation 4(필드만 거짓)는 검사 22의 필드가 잡는다 — 판정 셋이 각각 한 번씩 실제로 빨개진다.

8. 기존 판정은 그대로 맞는다(design 결정 4의 표). 검사 11과 13의 붙여넣기는 이제 fish의 빈
   프롬프트에서 감싸서 간다. 한 줄짜리라 fish의 화면은 PE-M1 전과 같고(입력줄에 `echo PASTED`가
   생긴다), 두 검사가 보는 `clip> paste len=11`은 `clip> paste len=11 bracketed=1`의 접두다.
   `hangul/check.sh`는 `find>` 갈래만 탄다. 다른 체인에 `meta_l-v`가 없다.

9. mutation을 Zig 파일에 넣는 법. 저장소 파일은 안 고치고 사본을 `-v`로 그 파일 자리에 덮는다
   (lessons "조사용 Zig 프로그램을 저장소 밖에서 돌리는 법"의 `vt.zig` 사본과 같은 모양). 같은
   `docker run` 안에서 먼저 `terminal/.zig-cache`와 `terminal/zig-out`을 지운다 — 캐시가 소스보다 낡은
   채로 판정에 쓰이는 일이 이 저장소에서 일곱 번 있었고(`project_zig_out_staleness`), 지우는 것도
   컨테이너 안에서 해야 한다(호스트에서 지우면 9회 중 2회 `error: FileNotFound`). 덮인 사본이 실제로
   쓰였는지는 같은 `docker run` 안에서 `grep -c`로 mutation 글자를 세어 본다.

   mutation 1 · 2는 `vt.zig`를 바꾸므로 체인이 부팅 전에 돌리는 `zig build test`가 검사 94 · 93에서
   먼저 멈춘다(lessons 실측 52). 그것이 첫째 판정이고, 체인의 화면 판정은 `copy/check.sh`의 사본에서 그
   한 단계만 끈 채로 따로 본다. mutation 조건은 runtime 값(`text.len`)을 섞어 쓴다 — `if (true) return …;`
   처럼 comptime에 정해지는 조건은 뒤의 줄을 도달 불가로 만들어 컴파일 에러가 날 수 있다.

10. 이 plan의 코드 블록은 한 번 돌려 봤다. plan을 쓴 뒤 Task 1~4의 편집을 python으로 저장소 파일의
    사본(`/tmp/run/pem1/*_plan.*`)에 적용하고, 사본을 `-v`로 덮어 컨테이너에서 캐시를 지운 뒤
    `zig build`(게스트의 `terminal` 바이너리, `main.zig` 포함)와 `zig build test`를 돌렸다. 둘 다
    `exit=0`이었고 검사 93~96의 OK 넷이 나왔다. 사본과 원본의 차이는 vt.zig +28/−3 · main.zig +23/−6 ·
    vt_test.zig +59/−0 · copy/check.sh +186/−0이었고, `copy/check.sh` 사본은 `bash -n`과
    `require_no_early_exit_pipe`를 통과했다. 게스트 부팅(체인)은 안 돌렸다 — 그것은 Task 5의 일이다.

## Task 0: 바꾸기 전의 기준값

1. 돌고 있는 게이트가 없는지 본다. Task 4~6이 docker로 copy 체인을 돌리므로 겹치면 monitor 포트
   45461이 부딪친다.

   ```bash
   docker ps --format '{{.Names}} {{.Image}} {{.Status}}'
   pgrep -fl 'tars-devcontainer'
   ```

   둘 다 아무것도 안 나와야 한다. 나오면 멈추고 보고한다.

2. 작업 트리가 깨끗한지 본다.

   ```bash
   git status --short
   git log --oneline -1
   ```

   기대: `git status`는 0줄(이 plan 파일이 untracked로 보이는 것은 정상), 마지막 commit은
   `d237fb2 PE-M0: …` 또는 그 뒤의 것이다.

3. 고칠 자리가 그대로인지 본다.

   ```bash
   rg -n 'pub fn clipboard|셸 쪽 `dumpPaste`는|^fn dumpPaste|paste len=\{d\}|"PASS\\n"|the next key cleared the match number|Esc로 나오면 다시 나간다|pasteParts|bracketed=' \
     terminal/src/vt.zig terminal/src/main.zig terminal/src/vt_test.zig copy/check.sh
   rg -n '^fn cuExpectMark|^pub fn main' terminal/src/vt_test.zig
   ```

   기대(줄 번호는 참고):

   ```
   copy/check.sh:17:#   → Esc로 나오면 다시 나간다
   copy/check.sh:1136:echo "the next key cleared the match number"
   terminal/src/vt_test.zig:2545:    std.debug.print("PASS\n", .{});
   terminal/src/vt.zig:1225:    /// 뜬다"라 조용하다. 셸 쪽 `dumpPaste`는 개행이 곧 실행이 되는 것을
   terminal/src/vt.zig:1968:    pub fn clipboard(self: *const Screen) ?[]const u8 {
   terminal/src/main.zig:1186:fn dumpPaste(screen: *vt.Screen, master_fd: c_int) void {
   terminal/src/main.zig:1194:    std.debug.print("terminal: clip> paste len={d}\n", .{text.len});
   67:fn cuExpectMark(label: []const u8, got: ?vt.CursorMark, want: ?vt.CursorMark) !void {
   73:pub fn main(init: std.process.Init) !void {
   ```

   `pasteParts`와 `bracketed=`는 0줄이어야 한다.

4. `vt_test`와 `copy` 체인을 한 번씩 초록으로 본다. 체인은 약 2분 30초다. 시리얼 로그도 이 단계에서
   하나 받아 둔다 — Task 5에서 PE-M1 전후의 `clip> paste` 줄을 나란히 보기 위해서다.

   ```bash
   mkdir -p /tmp/run/pem1/base
   docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
     bash -c 'zig build test 2>&1 | grep -a -E "^vt_test: 뷰포트 밖|^PASS|FAIL|error:"'
   { time docker run --rm -v "$PWD":/workspace -v /tmp/run/pem1:/tmp/run/pem1 -w /workspace \
       tars-devcontainer bash -c '
     bash copy/check.sh > /tmp/run/pem1/base/chain.log 2>&1; echo "exit=$?"
     n=0; for f in /tmp/tmp.*; do
       if grep -a "tars-init" "$f" >/dev/null 2>&1; then n=$((n+1)); cp "$f" /tmp/run/pem1/base/serial_$n.log; fi
     done' ; } 2> /tmp/run/pem1/base/time
   tail -2 /tmp/run/pem1/base/chain.log; cat /tmp/run/pem1/base/time
   ls /tmp/run/pem1/base/
   ```

   기대: 첫 명령은 `vt_test: 뷰포트 밖의 셸 커서는 안 그린다 OK`와 `PASS` 다섯 줄(검사 파일 일곱 중
   다섯이 `PASS`를 찍는다 — 2026-10-04에 잰 기준값), `FAIL`과 `error:`는
   0줄. 체인은 `exit=0`, 마지막 줄 `CM-M2 check PASS`, 시리얼 로그 `serial_1.log` 하나. `time`의 `real`을
   보고에 적는다(Task 4의 새 시간과 비교한다).

## Task 1: `terminal/src/vt.zig`

### 1-1. `pasteParts`를 `clipboard()` 바로 뒤에 넣는다

`pub fn clipboard(self: *const Screen) ?[]const u8 {`(1968줄)의 함수 끝 `}` 뒤, 빈 줄 하나를 두고
`/// 뷰포트가 스크롤백의 어디에 있는지.` 앞에 넣는다. Edit 도구로 한다.

바꾸기 전:

```zig
    pub fn clipboard(self: *const Screen) ?[]const u8 {
        const text = self.clip orelse return null;
        return text;
    }

    /// 뷰포트가 스크롤백의 어디에 있는지.
```

바꾼 뒤:

```zig
    pub fn clipboard(self: *const Screen) ?[]const u8 {
        const text = self.clip orelse return null;
        return text;
    }

    /// 붙여넣기가 pty에 쓸 세 조각 — 머리 · 본문 · 꼬리(PE design 결정 2 · 4).
    ///
    /// 자식이 모드 2004(bracketed paste)를 켰으면 머리와 꼬리가 `ESC[200~` ·
    /// `ESC[201~`이고, 꺼져 있으면 둘 다 빈 조각이다. 본문은 언제나 `text`
    /// 그대로다 — 개행도 제어 바이트도 안 바꾼다. 라이브러리의 `encodePaste`를
    /// 안 쓰는 이유가 이것이다. 그 함수는 모드가 꺼진 갈래에서 `\n`을 `\r`로
    /// 바꾸고 제어 바이트를 공백으로 바꾼다(PE design 결정 2의 후보 표).
    ///
    /// 모드는 화면별이 아니라 `Terminal` 하나에 하나다(PE design 실측 2).
    /// 대체 화면에서 켜고 끈 것도 같은 값을 바꾸고, RIS가 끈다(`vt_test`
    /// 검사 95 · 96). 패널마다 `Screen`이 따로이므로 모드도 패널마다 따로다.
    ///
    /// `main.zig`가 `self.term.modes`를 직접 읽지 않게 하려고 함수로 낸다 —
    /// `clipboard`·`findNeedle`과 같은 규율이다(TR design 결정 1). 판단과
    /// 머리 · 꼬리의 글자가 여기 있어서 호스트의 `vt_test`가 실제로 나갈
    /// 바이트를 본다.
    ///
    /// 할당하지 않는다. 돌려주는 조각은 `text`와 정적 문자열을 가리킨다 —
    /// 클립보드에는 상한이 없어서, 이어 붙이려면 매번 본문 길이만큼 할당해야
    /// 한다(PE design 결정 3).
    pub fn pasteParts(self: *const Screen, text: []const u8) [3][]const u8 {
        if (!self.term.modes.get(.bracketed_paste)) return .{ "", text, "" };
        return .{ "\x1b[200~", text, "\x1b[201~" };
    }

    /// 뷰포트가 스크롤백의 어디에 있는지.
```

더한 줄은 25다(빈 줄 하나 · doc 주석 20 · 함수 4).

### 1-2. `findPaste` doc 주석의 세 줄

`findPaste`의 doc 주석(`rg -n '셸 쪽 `dumpPaste`는' terminal/src/vt.zig`, 1225줄)에서 세 줄을 바꾼다.
그 문장은 PE-M1 전의 사실(셸 쪽은 개행이 곧 실행이다)을 적고 있어서 이 milestone이 낡게 만든다.
앞의 두 줄과 뒤의 `///` 빈 줄은 그대로다.

바꾸기 전:

```zig
    /// 개행에서 자르는 것이 이 함수의 본체다. 화면 셀에는 개행이 없으므로
    /// 개행이 든 needle은 영영 안 맞는다 — 증상이 "붙여넣었는데 못 찾음이
    /// 뜬다"라 조용하다. 셸 쪽 `dumpPaste`는 개행이 곧 실행이 되는 것을
    /// 감수했지만(CM design 결정 9), 검색은 감수할 수 있는 종류가 아니다.
    /// 셸에서는 잘못 붙은 것이 화면에 보이고 검색에서는 안 보인다.
```

바꾼 뒤:

```zig
    /// 개행에서 자르는 것이 이 함수의 본체다. 화면 셀에는 개행이 없으므로
    /// 개행이 든 needle은 영영 안 맞는다 — 증상이 "붙여넣었는데 못 찾음이
    /// 뜬다"라 조용하다. 셸 쪽 `dumpPaste`는 자식이 모드 2004를 켰으면
    /// bracketed paste로 감싸서 개행을 자식에게 맡긴다(PE design 결정 2).
    /// 검색 프롬프트는 우리 것이라 감쌀 상대가 없어서 개행을 여기서 다룬다.
```

### 1-3. 확인

```bash
git diff --stat terminal/src/vt.zig
git diff terminal/src/vt.zig | rg '^-'
```

기대: `1 file changed, 28 insertions(+), 3 deletions(-)`. 둘째 명령은 `--- a/terminal/src/vt.zig`와
1-2의 "바꾸기 전" 마지막 세 줄(`뜬다"라 조용하다. 셸 쪽 …` · `감수했지만(CM design 결정 9), …` ·
`셸에서는 잘못 붙은 것이 …`)뿐이다. 다른 줄이 `-`로 나오면 편집이 다른 줄을 건드린 것이다 —
되돌리고 다시 한다.

## Task 2: `terminal/src/main.zig` — `dumpPaste`

`fn dumpPaste`(1186줄)의 doc 주석 한 문단과 본문 두 줄을 바꾼다. doc 주석의 첫 문단(`Cmd+V`가 …),
둘째 문단(쓰는 일과 찍는 일을 한 함수에 둔 이유), 마지막 문단(`clip>` 접두사), 그리고 클립보드가
비었을 때의 `orelse` 블록은 그대로다. Edit 도구로 두 번 한다.

### 2-1. doc 주석

바꾸기 전(넷째 문단 넉 줄):

```zig
/// bracketed paste로 감싸지 않는다(design 결정 9). 여러 줄을 붙이면 개행이
/// 곧 실행이 되는 것을 감수한다 — 셸이 그 모드를 받는지 확인한 적이 없고,
/// 확인 없이 넣으면 게이트가 못 보는 코드가 느는 것이
/// `project_gate_chain_composition`이 경고한 부채 그대로다.
```

바꾼 뒤(세 문단 열다섯 줄):

```zig
/// 자식이 모드 2004를 켰으면 bracketed paste로 감싼다(PE design 결정 2).
/// 감쌀지와 무엇으로 감쌀지는 `vt.zig`의 `pasteParts`가 정하고, 여기는 그
/// 세 조각을 차례로 쓰기만 한다. 게스트의 셸 셋(zsh · bash · fish)과 vim이
/// 전부 그 모드를 켜므로(PE design 실측 1), 여러 줄을 붙여도 Enter 전에는
/// 실행되지 않고 vim의 `autoindent`가 계단을 만들지 않는다. 모드가 꺼져
/// 있으면(`cat`처럼 모드를 모르는 프로그램) 머리와 꼬리가 비어서 본문만
/// 나간다 — PE-M1 전과 같은 바이트다.
///
/// 이어 붙여 한 번에 쓰지 않는다(PE design 결정 3). 클립보드에 상한이 없어서
/// 매번 할당이 들고, 한 번에 써도 자식이 한 번에 읽는다는 보장이 없다.
///
/// `len=`은 본문의 길이이고 `bracketed=`는 감쌌는지(1 또는 0)다. 머리와
/// 꼬리의 12바이트를 `len=`에 더하지 않는 것은 그 숫자가 계속 "클립보드에
/// 무엇이 들었나"를 말하게 하기 위해서다. 새 필드를 맨 뒤에 붙였으므로
/// `clip> paste len=11`을 접두로 보는 판정이 그대로 맞는다(PE design 결정 4).
```

### 2-2. 본문

바꾸기 전:

```zig
    pty.write(master_fd, text);
    std.debug.print("terminal: clip> paste len={d}\n", .{text.len});
}
```

바꾼 뒤:

```zig
    const parts = screen.pasteParts(text);
    for (parts) |p| {
        if (p.len > 0) pty.write(master_fd, p);
    }
    std.debug.print("terminal: clip> paste len={d} bracketed={d}\n", .{
        parts[1].len,
        @intFromBool(parts[0].len > 0),
    });
}
```

`screen`은 `*vt.Screen`이고 `pasteParts`는 `*const Screen`을 받으므로 그대로 넘어간다. design
결정 4의 코드 블록과 다른 점은 모양뿐이다 — `for` 본문을 중괄호로 감쌌고, 인자 목록을 한 줄에
하나씩 적었다. 쓰는 조각 · 로그의 글자 · 필드의 뜻은 design 그대로다. `pty.write`의 시그니처는
`pub fn write(fd: c_int, bytes: []const u8) void`(`pty.zig` 131줄)이고 안 바꾼다.

### 2-3. 확인

```bash
git diff --stat terminal/src/main.zig
git diff terminal/src/main.zig | rg '^-'
```

기대: `1 file changed, 23 insertions(+), 6 deletions(-)`. 둘째 명령은 `--- a/terminal/src/main.zig`와
2-1의 "바꾸기 전" 넉 줄, 2-2의 `pty.write(master_fd, text);` · `std.debug.print("terminal: clip> paste
len={d}\n", .{text.len});` 두 줄뿐이다.

## Task 3: `terminal/src/vt_test.zig` — 검사 93~96

### 3-1. 헬퍼 `peExpectParts`

`fn cuExpectMark`(67줄)의 함수 끝 `}`와 `pub fn main`(73줄) 사이에 넣는다. 결과가 `}` · 빈 줄 · 새
헬퍼 · 빈 줄 · `pub fn main`이 되게 한다.

```zig
/// `pasteParts`의 세 조각이 기대와 같은가(PE-M1). 조각마다 비교해서, 머리가
/// 틀렸는지 본문이 바뀌었는지를 실패 메시지가 바로 말하게 한다. 바이트를
/// 숫자로 찍는다(`{any}`) — 머리와 꼬리의 ESC가 터미널에 먹혀 사라지지 않게.
fn peExpectParts(label: []const u8, got: [3][]const u8, want: [3][]const u8) !void {
    for (got, want, 0..) |g, w, i| {
        if (std.mem.eql(u8, g, w)) continue;
        std.debug.print("FAIL: {s} — 조각 {d}\n  got  {any}\n  want {any}\n", .{ label, i, g, w });
        return error.PastePartsWrong;
    }
}
```

### 3-2. 검사 93~96

`main()`의 끝, `std.debug.print("vt_test: 뷰포트 밖의 셸 커서는 안 그린다 OK\n", .{});`(검사 92의 끝)와
빈 줄 뒤, `std.debug.print("PASS\n", .{});` 앞에 넣는다. 결과가 검사 92의 `OK` 줄 · 빈 줄 · 검사 93 …
검사 96의 `OK` 줄 · 빈 줄 · `PASS`가 되게 한다. 화면은 검사마다 새로 만든다(lessons — 남의 화면에
붙이면 크기와 history가 달라 깨진다).

```zig
    // 검사 93. 새 화면은 모드 2004가 꺼져 있다 — 머리와 꼬리가 비고 본문은
    // 그대로다(PE design 결정 2). 기본값이 꺼짐이라는 것은 ghostty의
    // `modes.zig` 표가 정하고, 이 검사가 그것을 우리 함수로 다시 본다.
    const pe_plain = [3][]const u8{ "", "ab", "" };
    const pe_wrapped = [3][]const u8{ "\x1b[200~", "ab", "\x1b[201~" };
    const pe_new = try vt.Screen.init(init.io, init.gpa, 20, 5, CELL);
    defer pe_new.deinit();
    try peExpectParts("검사 93 새 화면", pe_new.pasteParts("ab"), pe_plain);
    std.debug.print("vt_test: 새 화면의 붙여넣기는 감싸지 않는다 OK\n", .{});

    // 검사 94. `ESC[?2004h`를 먹이면 감싼다. 시퀀스를 `ESC[?20`과 `04h`로
    // 나눠 먹여도 같다 — 파서 상태가 `feed` 사이에 남는다(`Screen`의 doc
    // 주석). 셸의 출력이 pty read 경계에서 잘리는 것은 흔한 일이다. 반쪽만
    // 먹인 순간에는 아직 꺼져 있어야 한다.
    const pe_on = try vt.Screen.init(init.io, init.gpa, 20, 5, CELL);
    defer pe_on.deinit();
    pe_on.feed("\x1b[?2004h");
    try peExpectParts("검사 94 ESC[?2004h 뒤", pe_on.pasteParts("ab"), pe_wrapped);
    const pe_split = try vt.Screen.init(init.io, init.gpa, 20, 5, CELL);
    defer pe_split.deinit();
    pe_split.feed("\x1b[?20");
    try peExpectParts("검사 94 반쪽만 먹인 뒤", pe_split.pasteParts("ab"), pe_plain);
    pe_split.feed("04h");
    try peExpectParts("검사 94 나머지를 먹인 뒤", pe_split.pasteParts("ab"), pe_wrapped);
    std.debug.print("vt_test: 모드 2004가 켜지면 머리와 꼬리로 감싼다 OK\n", .{});

    // 검사 95. 모드는 화면별이 아니다(PE design 실측 2). 켠 채로 대체 화면에
    // 들어가도 켜져 있고, 대체 화면에서 끄고 나와도 꺼져 있다. 검사 91의 커서
    // 모양(화면마다 따로)과 반대다 — 두 성질을 같은 것으로 짐작하면 틀린다.
    const pe_alt = try vt.Screen.init(init.io, init.gpa, 20, 5, CELL);
    defer pe_alt.deinit();
    pe_alt.feed("\x1b[?2004h\x1b[?1049h");
    try peExpectParts("검사 95 켠 채로 대체 화면에 들어간 뒤", pe_alt.pasteParts("ab"), pe_wrapped);
    pe_alt.feed("\x1b[?2004l\x1b[?1049l");
    try peExpectParts("검사 95 대체 화면에서 끄고 나온 뒤", pe_alt.pasteParts("ab"), pe_plain);
    std.debug.print("vt_test: 모드 2004는 화면별이 아니다 OK\n", .{});

    // 검사 96. RIS(`ESC c`)가 모드를 끈다 — 모드를 켠 채 죽은 자식 뒤에
    // 사람이 `reset`을 치면 풀린다(PE design 위험 2). 그리고 본문의 개행은
    // 그대로다 — 감싸든 안 감싸든 `\n`을 `\r`로 바꾸지 않는다(결정 2).
    const pe_ris = try vt.Screen.init(init.io, init.gpa, 20, 5, CELL);
    defer pe_ris.deinit();
    pe_ris.feed("\x1b[?2004h");
    try peExpectParts("검사 96 RIS 전", pe_ris.pasteParts("a\nb"), .{ "\x1b[200~", "a\nb", "\x1b[201~" });
    pe_ris.feed("\x1bc");
    try peExpectParts("검사 96 RIS 뒤", pe_ris.pasteParts("a\nb"), .{ "", "a\nb", "" });
    std.debug.print("vt_test: RIS가 모드를 끄고, 본문의 개행은 그대로다 OK\n", .{});

```

(마지막의 빈 줄은 `PASS` 앞의 빈 줄이 된다.)

### 3-3. 확인과 실행

```bash
git diff --stat terminal/src/vt_test.zig
git diff terminal/src/vt_test.zig | rg '^-'
rg -n '\bpe_[a-z]+ =' terminal/src/vt_test.zig | wc -l
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test > /tmp/t.out 2>&1; echo "exit=$?"; grep -a -E "^vt_test: (뷰포트 밖|새 화면의 붙여넣기|모드 2004|RIS가)|FAIL|error:" /tmp/t.out; grep -ac "^PASS" /tmp/t.out'
```

기대.

- `--stat`은 `1 file changed, 59 insertions(+)`다 — 헬퍼 11(빈 줄 포함)과 검사 넷 48(마지막 빈 줄
  포함). 빈 줄의 자리 때문에 하나 다르면 그 수를 보고하고, 지운 줄이 0인지만 확인한다.
- 둘째 명령은 `--- a/terminal/src/vt_test.zig` 한 줄만.
- 셋째 명령은 `7`이다 — `const pe_… =` 꼴의 선언(`pe_plain` · `pe_wrapped` · `pe_new` · `pe_on` ·
  `pe_split` · `pe_alt` · `pe_ris`). 다른 수가 나오면 그 출력을 보고한다(이름이 부딪치면 컴파일이 먼저
  막는다).
- 넷째 명령은 `exit=0`, `vt_test: 뷰포트 밖의 셸 커서는 안 그린다 OK`, 새 OK 넷, `FAIL` · `error:` 0줄,
  마지막 수 `5`(Task 0-4의 기준값과 같은 `PASS` 줄 수).

  ```
  vt_test: 뷰포트 밖의 셸 커서는 안 그린다 OK
  vt_test: 새 화면의 붙여넣기는 감싸지 않는다 OK
  vt_test: 모드 2004가 켜지면 머리와 꼬리로 감싼다 OK
  vt_test: 모드 2004는 화면별이 아니다 OK
  vt_test: RIS가 모드를 끄고, 본문의 개행은 그대로다 OK
  ```

  `zig build test`가 `file contents changed during update`로 멈추면 편집 직후의 파일을 빌드가 읽은
  것이다(lessons 실측 60) — 다시 돌린다.

검사 95나 96이 빨가면 기대값을 고쳐서 맞추지 않는다. 그 실패 메시지(`FAIL: 검사 9x … — 조각 N`과
got · want 바이트)를 그대로 보고한다 — design 실측 2(모드가 화면별이 아니다, RIS가 끈다)가 틀렸다는
뜻이고, design의 판단을 lead가 다시 봐야 한다.

## Task 4: `copy/check.sh` — 검사 21 · 22

### 4-1. 머리 주석

맨 위 "이 게이트가 증명하는 사슬 전체" 목록의 마지막 줄(`rg -n 'Esc로 나오면 다시 나간다' copy/check.sh`,
17줄) 바로 뒤에 두 줄을 넣는다.

```bash
#   → Esc로 나오면 다시 나간다
#   → 자식이 모드 2004를 켰으면 붙인 글자를 ESC[200~ · ESC[201~로 감싸고,
#     꺼져 있으면 그대로 쓴다(PE-M1, 검사 21 · 22)
```

(첫 줄은 이미 있는 줄이다.)

### 4-2. 검사 21 · 22

검사 20의 마지막 줄 `echo "the next key cleared the match number"`(1136줄)와 빈 줄 뒤,
`# ── 음성 검사: 로그에 NUL이 섞이지 않았다` 앞에 아래를 그대로 넣는다. 결과가 검사 20의 `echo` ·
빈 줄 · 검사 21 … 검사 22의 마지막 `echo` · 빈 줄 · NUL 음성 검사가 되게 한다. 다른 줄은 안
고친다 — 끝의 `echo "CM-M2 check PASS"`도 그대로다(`check.sh`의 `CHAINS`가 이 체인을 `CM-M2`로 부른다).

```bash
# ── 검사 21: 모드 2004가 켜진 자식에게는 감싸서 붙인다 (PE-M1) ─────────
#
# fish는 프롬프트에서 `ESC[?2004h`를 보내고(PE design 실측 1), 우리 터미널은
# 그 모드가 켜져 있으면 클립보드를 `ESC[200~` · `ESC[201~`로 감싸 쓴다(PE
# design 결정 2). fish는 감싼 두 줄을 개행째 입력줄에 넣고 Enter를 기다린다.
# 감싸지 않으면 첫 줄의 개행을 Enter로 읽어 그 줄을 곧바로 실행한다.
#
# 판정은 화면이 한다(PE design 결정 5). `clip> paste`의 `bracketed=`는 우리
# 코드가 자기 판단을 찍은 것이라서, 그 필드는 화면 판정이 다 끝난 뒤 맨
# 끝에 본다. 앞에 두면 "감싸지 않았다"는 고장이 화면에 닿기 전에 필드에서
# 먼저 잡혀, 화면 판정이 실제로 그 고장을 잡는지를 mutation으로 볼 수 없다.
#
# 검사 20이 copy mode 안에서 끝났으므로 먼저 나간다. ctrl-l은 fish가 화면을
# 지우고 프롬프트를 맨 윗줄에 다시 그리게 한다 — 출력이 생기므로 뷰포트도
# 바닥으로 돌아온다(hangul 체인 검사 17이 같은 키를 쓴다).
type_keys esc
sleep 1
type_keys ctrl-l
sleep 1

# 붙여넣을 두 줄을 만든다. 검사 7과 같은 요령이다 — `echo echo PEONE`의
# 출력은 `echo PEONE`만 있는 줄이다. 판정 글자 `| PEONE |`는 친 줄과 안
# 겹친다(project_gate_screen_echo). 친 줄에서 PEONE 앞은 `| `가 아니라 `o `다.
echo "=== typing 'echo echo PEONE; echo echo PETWO' ==="
type_keys e c h o spc e c h o spc shift-p shift-e shift-o shift-n shift-e semicolon spc \
  e c h o spc e c h o spc shift-p shift-e shift-t shift-w shift-o ret
if ! wait_for_screen '\| echo PEONE \| echo PETWO \|'; then
  report_failure "the shell did not print the two lines 'echo PEONE' and 'echo PETWO'"
fi

# 두 줄을 잡는다. 커서는 셸 커서 자리(프롬프트 줄)에서 시작하므로 k 둘이
# `echo PEONE` 줄이다(검사 8과 같은 셈). V로 그 줄을, j로 다음 줄까지 잡는다.
echo "=== entering copy mode and yanking the two lines (k k V j y) ==="
type_keys meta_l-shift-c
sleep 2
PE_ROW_ENTER="$(copy_value row)"
type_keys k k
sleep 1
PE_ROW="$(copy_value row)"
if [ "$PE_ROW" -ne "$((PE_ROW_ENTER - 2))" ]; then
  report_failure "k k moved the copy cursor from row ${PE_ROW_ENTER} to ${PE_ROW} (expected $((PE_ROW_ENTER - 2)))"
fi
type_keys shift-v
sleep 1
type_keys j
sleep 1
type_keys y
sleep 2

# `echo PEONE` + 개행 + `echo PETWO`, 21바이트다. dumpClip이 text= 뒤에
# 개행째 찍으므로 둘째 줄은 다음 로그 줄로 넘어간다(FP design 결정 5의
# 실측). 그래서 첫 줄까지만 글자로 보고, 둘째 줄이 잡힌 것은 길이로 본다.
if ! grep -aq 'terminal: clip> len=21 text=echo PEONE' "$LOG"; then
  report_failure "y did not put the two lines (21 bytes) on the clipboard: $(grep -a 'terminal: clip> len=' "$LOG" | tail -n 1)"
fi
echo "the clipboard holds the two lines (21 bytes)"

# 대조군. 지금까지 `PEONE`만 있는 줄은 한 번도 없었다 — 검사 10과 같은
# "지금까지 한 번도"의 대조군이다. 이것이 없으면 아래 음성 판정이 원래부터
# 그랬던 화면을 보고, 양성 판정이 원래부터 있던 줄을 볼 수 있다.
if grep -aqF '| PEONE |' "$LOG"; then
  report_failure "a line containing only 'PEONE' was on the screen before the paste"
fi
echo "control: nothing has printed 'PEONE' on a line of its own yet"

# 붙인다. 먼저 `clip> paste len=21 `로 붙여넣기가 도착한 것만 본다(뒤의 공백은
# `len=210` 같은 값과 안 겹치게 하려는 것이다). 감쌌는지는 여기서 안 본다.
PE_ECHO_BEFORE="$(screen_count 'echo PETWO')"
echo "=== pasting the two lines at the fish prompt (Cmd+V) ==="
type_keys meta_l-v
PE_OK=0
for _ in $(seq 1 50); do
  if grep -aq 'terminal: clip> paste len=21 ' "$LOG"; then PE_OK=1; break; fi
  sleep 0.1
done
[ "$PE_OK" = "1" ] || report_failure "Cmd+V did not write the 21-byte clipboard (no 'clip> paste len=21' line)"

# 붙인 둘째 줄이 fish의 입력줄에 나타난다. fish는 감싼 두 줄을 입력줄 두 행으로
# 그리고 둘째 행을 커서 이동으로 첫 행의 명령 자리에 맞춘다 — 띄운 칸에는
# 글자가 없어 screen>에는 `| echo PETWO |`로 나온다(PE-M1 plan 확정 2). 그래서
# 마지막 프레임의 `echo PETWO`가 하나 는다. 절대값을 못 쓰는 이유는 검사 11과
# 같다 — 친 명령줄과 출력줄에 이미 둘이다.
#
# fish는 꼬리(`ESC[201~`)가 올 때까지 붙인 글자를 하나도 안 그리고, 그동안
# 오는 키(Enter · ctrl-c 포함)를 전부 붙여넣기의 일부로 삼킨다(plan 확정 1).
# 꼬리를 빠뜨리면 여기서 약 15초를 다 쓰고 빨개진다.
PE_ECHO_AFTER="$PE_ECHO_BEFORE"
for _ in $(seq 1 150); do
  PE_ECHO_AFTER="$(screen_count 'echo PETWO')"
  if [ "$PE_ECHO_AFTER" -gt "$PE_ECHO_BEFORE" ]; then break; fi
  sleep 0.1
done
if [ "$PE_ECHO_AFTER" -le "$PE_ECHO_BEFORE" ]; then
  report_failure "the pasted lines never showed up on the fish command line ('echo PETWO' stayed at ${PE_ECHO_BEFORE})"
fi
echo "the paste reached the fish command line (echo PETWO ${PE_ECHO_BEFORE} -> ${PE_ECHO_AFTER})"

# 판정(음성). 3초 뒤에도 `PEONE`만 있는 줄이 없다. 감싸지 않았다면 fish가
# 첫 줄의 개행을 Enter로 읽어 `PEONE`을 곧바로 찍는다(plan 확정 1의 mutation 1).
sleep 3
if grep -aqF '| PEONE |' "$LOG"; then
  report_failure "the first line ran before Enter: the paste at the fish prompt was not bracketed"
fi
echo "nothing ran before Enter"

# 판정(양성). Enter를 치면 두 줄이 함께 실행되어 `PEONE`만 있는 줄과 `PETWO`만
# 있는 줄이 연달아 생긴다. 위의 음성 판정만 있으면 "붙여넣기가 아예 안
# 갔다"도 통과하므로 이 판정이 짝이다.
echo "=== running the pasted lines (Enter) ==="
type_keys ret
if ! wait_for_screen '\| PEONE \| PETWO \|'; then
  report_failure "Enter did not run both pasted lines (no 'PEONE' row followed by a 'PETWO' row)"
fi
echo "Enter ran both pasted lines together"

# 갈래의 표지. 화면 판정이 다 끝난 뒤에 본다(이 검사의 머리 주석). 시리얼
# 로그의 줄 끝은 \r\n이라 \r를 지우고 꼬리를 맞춘다.
PE_LINE="$(grep -a 'terminal: clip> paste' "$LOG" | tail -n 1 | tr -d '\r')"
case "$PE_LINE" in
  *"terminal: clip> paste len=21 bracketed=1") ;;
  *) report_failure "the paste at the fish prompt was logged as '${PE_LINE}', expected 'clip> paste len=21 bracketed=1'" ;;
esac
echo "check 21: the paste at the fish prompt was bracketed (${PE_LINE##*clip> })"

# ── 검사 22: 모드가 꺼진 자식에게는 그대로 붙인다 (PE-M1) ───────────────
#
# fish는 `cat`을 띄우기 전에 `ESC[?2004l`을 보낸다(plan 확정 3). 그러면 우리는
# 감싸지 않고 PE-M1 전처럼 본문만 쓴다. `cat` 아래에서 감쌌다면 tty가 ESC를
# `^[`로 되울려(ECHOCTL) 화면에 `^[[200~`가 찍힌다(PE design 실측 4).
#
# 클립보드는 검사 21의 두 줄 그대로다. 화면을 지우는 것은 아래 셈을 짧은
# 화면에서 하려는 것이다.
type_keys ctrl-l
sleep 1
echo "=== typing 'cat' ==="
type_keys c a t ret
sleep 2
PE_CAT_BEFORE="$(screen_count 'echo PEONE')"
echo "=== pasting the two lines into cat (Cmd+V) ==="
type_keys meta_l-v
PE_OK=0
for _ in $(seq 1 50); do
  if [ "$(grep -ac 'terminal: clip> paste len=21 ' "$LOG" || true)" -ge 2 ]; then PE_OK=1; break; fi
  sleep 0.1
done
[ "$PE_OK" = "1" ] || report_failure "Cmd+V under cat did not write the clipboard (no second 'clip> paste len=21' line)"

# 판정(양성). `echo PEONE`이 마지막 프레임에 둘 는다 — tty의 에코 하나와,
# `cat`이 그 줄을 읽어 다시 쓴 것 하나다. 둘째 줄은 개행이 없으므로 에코만
# 되고 `cat`에게 안 간다.
#
# 화면의 모양은 셈하지 않는다. plan 확정 3에서는 tty가 21바이트를 한꺼번에
# 되울린 뒤에 `cat`의 출력이 와서 `| echo PEONE | echo PETWOecho PEONE`이었다.
# 에코와 `cat`의 출력 사이의 순서는 커널의 스케줄이 정하므로 그 모양에
# 기대지 않고 개수만 센다(`echo PETWOecho PEONE`에도 `echo PEONE`은 하나다).
PE_CAT_AFTER="$PE_CAT_BEFORE"
for _ in $(seq 1 150); do
  PE_CAT_AFTER="$(screen_count 'echo PEONE')"
  if [ "$PE_CAT_AFTER" -ge "$((PE_CAT_BEFORE + 2))" ]; then break; fi
  sleep 0.1
done
if [ "$PE_CAT_AFTER" -lt "$((PE_CAT_BEFORE + 2))" ]; then
  report_failure "cat did not echo and repeat the first pasted line ('echo PEONE' ${PE_CAT_BEFORE} -> ${PE_CAT_AFTER}, expected +2)"
fi

# 판정(음성). 화면 어디에도 `[200~`가 없었다. 이 체인의 어떤 키도 그 글자를
# 만들지 않으므로 마지막 프레임이 아니라 로그의 screen> 줄 전부를 본다.
if [ "$(grep -acF '[200~' <<<"$(grep -a 'terminal: screen>' "$LOG")" || true)" -ne 0 ]; then
  report_failure "the paste under cat was bracketed: '[200~' showed up on the screen"
fi
echo "cat got the two lines as they are (echo PEONE ${PE_CAT_BEFORE} -> ${PE_CAT_AFTER}, no [200~ on screen)"

# cat을 끝낸다. 둘째 줄은 cat의 줄 버퍼에 남은 채 버려진다.
type_keys ctrl-c
sleep 1

# 갈래의 표지. 검사 21과 같은 이유로 맨 끝에 본다.
PE_LINE="$(grep -a 'terminal: clip> paste' "$LOG" | tail -n 1 | tr -d '\r')"
case "$PE_LINE" in
  *"terminal: clip> paste len=21 bracketed=0") ;;
  *) report_failure "the paste under cat was logged as '${PE_LINE}', expected 'clip> paste len=21 bracketed=0'" ;;
esac
echo "check 22: the paste under cat went unwrapped (${PE_LINE##*clip> })"

```

(마지막의 빈 줄은 NUL 음성 검사 앞의 빈 줄이 된다.)

글자에 관해 셋을 짚는다.

- 판정 글자가 친 명령줄과 안 겹친다(`project_gate_screen_echo`). `| PEONE |` · `| PEONE | PETWO |`는 그
  글자만 있는 행이고, 친 줄에는 PEONE 앞에 `echo `가 붙는다. `[200~`는 이 체인의 어떤 키도 안 만든다.
  `| echo PEONE | echo PETWO |`(1단계의 기다림)는 붙인 뒤의 입력줄(`~# echo PEONE | echo PETWO |`)과도
  안 겹친다 — 그쪽은 `echo PEONE` 앞이 `| `가 아니라 `# `다. 그리고 그 기다림은 붙이기 전에 끝난다.
- fish의 자동 제안. `echo echo P`까지 치면 fish가 검사 7의 `echo echo PASTED`를 회색으로 제안할 수
  있다. 판정 글자에 `PASTED`가 없으므로 영향이 없다.
- 진입 검사. 새 줄의 파이프 뒤에는 `tail` · `tr`만 있고 `grep`/`rg`의 `-q`가 없다. 파일을 직접 읽는
  `grep -aq …  "$LOG"`와 here-string(`<<<`)은 lint 대상이 아니다. QEMU 호출은 안 늘었다.

### 4-3. 확인

```bash
git diff --stat copy/check.sh
git diff copy/check.sh | rg '^-'
bash -n copy/check.sh && echo SYNTAX-OK
bash -c 'source <(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic()/,/^}/p" check.sh)
  require_build_steps ./copy/check.sh && require_no_early_exit_pipe ./copy/check.sh &&
  require_explicit_nic ./copy/check.sh && echo ENTRY-OK'
```

기대: `1 file changed, 186 insertions(+)`(머리 주석 2와 검사 둘 184, 마지막 빈 줄 포함 — 빈 줄을
다르게 두었으면 하나 다를 수 있고, 그때는 수를 보고한다), 지운 줄 0(`rg '^-'`는 `--- a/copy/check.sh`
한 줄만), `SYNTAX-OK`, `ENTRY-OK`.

## Task 5: 체인 한 번과 게스트 실측

### 5-1. `copy` 체인 한 번(시리얼 로그를 함께 꺼낸다)

새 화면 판정을 넣었으므로 로그 꺼내기가 기본 절차다(lessons "범용 명령"). 약 3분이다(Task 0-4의
시간 + 검사 둘의 약 30초).

```bash
mkdir -p /tmp/run/pem1/after
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/pem1:/tmp/run/pem1 -w /workspace \
    tars-devcontainer bash -c '
  bash copy/check.sh > /tmp/run/pem1/after/chain.log 2>&1; echo "exit=$?"
  n=0; for f in /tmp/tmp.*; do
    if grep -a "tars-init" "$f" >/dev/null 2>&1; then n=$((n+1)); cp "$f" /tmp/run/pem1/after/serial_$n.log; fi
  done' ; } 2> /tmp/run/pem1/after/time
cat /tmp/run/pem1/after/time
rg -n 'PEONE|PETWO|fish prompt|cat|check 2[12]|^FAIL|CM-M2 check PASS|terminal host tests' /tmp/run/pem1/after/chain.log
```

기대(괄호 안의 수는 회차마다 다를 수 있다). 아래 줄들이 이 순서로 있어야 하고, `rg` 패턴의 `cat`이
다른 줄을 더 고를 수 있다:

```
=== typing 'echo echo PEONE; echo echo PETWO' ===
=== entering copy mode and yanking the two lines (k k V j y) ===
the clipboard holds the two lines (21 bytes)
control: nothing has printed 'PEONE' on a line of its own yet
=== pasting the two lines at the fish prompt (Cmd+V) ===
the paste reached the fish command line (echo PETWO 2 -> 3)
nothing ran before Enter
=== running the pasted lines (Enter) ===
Enter ran both pasted lines together
check 21: the paste at the fish prompt was bracketed (paste len=21 bracketed=1)
=== typing 'cat' ===
=== pasting the two lines into cat (Cmd+V) ===
cat got the two lines as they are (echo PEONE 0 -> 2, no [200~ on screen)
check 22: the paste under cat went unwrapped (paste len=21 bracketed=0)
CM-M2 check PASS
```

`exit=0`이 아니면 `FAIL:` 줄과 그 아래 덤프(`--- copy lines ---` · `--- last 40 lines ---`)를 그대로
보고한다. 기대값을 고쳐서 초록을 만들지 않는다 — 특히 `echo PETWO`의 증가(확정 2)와 `echo PEONE`의
+2(확정 3)는 컨테이너에서 잰 값이고 게스트에서는 처음이다. 빨가면 5-2의 명령으로 그 순간의 화면을
꺼내 보고한다. 시간(`real`)은 Task 0-4와 함께 보고한다.

### 5-2. 시리얼 로그에서 꺼낼 것

```bash
perl -pe 's/\e\][^\a\e]*(\a|\e\\)//g; s/\e\[[0-9;?>=]*[a-zA-Z]//g;
          s/\e[()][AB0]//g; s/\r/\n/g' /tmp/run/pem1/after/serial_1.log > /tmp/run/pem1/after/serial.clean
perl -pe 's/\e\][^\a\e]*(\a|\e\\)//g; s/\e\[[0-9;?>=]*[a-zA-Z]//g;
          s/\e[()][AB0]//g; s/\r/\n/g' /tmp/run/pem1/base/serial_1.log > /tmp/run/pem1/base/serial.clean
# (a) 붙여넣기 줄 — PE-M1 전과 후
grep -a 'terminal: clip> paste' /tmp/run/pem1/base/serial.clean
grep -a 'terminal: clip> paste' /tmp/run/pem1/after/serial.clean
# (b) 두 줄짜리 클립보드(dumpClip이 개행째 찍는 모양)
grep -a -A1 'terminal: clip> len=21' /tmp/run/pem1/after/serial.clean
# (c) 검사 21 · 22의 화면 — 두 붙여넣기 사이와 그 뒤에서 서로 다른 프레임만
bash -c '
f=/tmp/run/pem1/after/serial.clean
L1=$(grep -an "clip> paste len=21 bracketed=1" "$f" | head -1 | cut -d: -f1)
L2=$(grep -an "clip> paste len=21 bracketed=0" "$f" | head -1 | cut -d: -f1)
echo "check 21 paste at line $L1, check 22 paste at line $L2"
echo "== check 21: distinct frames between the two pastes"
sed -n "${L1},${L2}p" "$f" | grep -a "terminal: screen>" | uniq | sed -E "s/( \| ?)+\$//" | tail -n 6
echo "== check 22: distinct frames after the cat paste"
sed -n "${L2},\$p" "$f" | grep -a "terminal: screen>" | uniq | sed -E "s/( \| ?)+\$//" | tail -n 4'
```

기대.

- (a) PE-M1 전은 `terminal: clip> paste len=11` 둘(검사 11 · 13). 후는 `len=11 bracketed=1` 둘과
  `len=21 bracketed=1` · `len=21 bracketed=0`. 검사 11 · 13이 `bracketed=1`인 것은 fish의 빈 프롬프트에서
  붙였기 때문이다(확정 8).
- (b) `terminal: clip> len=21 text=echo PEONE` 다음 줄이 `echo PETWO`다.
- (c) 검사 21 쪽에 세 모양이 차례로 있어야 한다. 붙인 뒤 Enter 전의 프레임에서 마지막 두 행이
  `root@(none) ~# echo PEONE`과 `echo PETWO`이고(둘째 행 앞의 칸이 `screen>`에 안 찍혀 행 머리가
  `| echo PETWO`일 것이다 — 확정 2), Enter 뒤에 `| PEONE | PETWO | root@(none) ~#`가 온다. 검사 22 쪽은
  `root@(none) ~# cat` 아래에 `echo PEONE`과 `echo PETWOecho PEONE`(확정 3의 순서) 또는
  `echo PEONE` · `echo PEONE` · `echo PETWO`(다른 순서)이고, ctrl-c 뒤에 `^C`와
  `root@(none) ~ [SIGINT]#`가 올 것이다.

기대와 다른 모양(둘째 행 앞에 공백이 찍혀 있다, `cat` 쪽 순서가 다르다, `⏎` 같은 fish의 표시가
끼어 있다 등)은 판정과 무관해도 그대로 옮겨 보고한다 — lead가 실측 절에 적는다. `screen>` 줄이
시리얼에서 중간에 끊겨 있으면(GE-M1 실측 4에서 한 번 있었다) 그다음의 완전한 줄을 고른다.

## Task 6: mutation 넷

저장소 파일은 안 고치고 사본을 `-v`로 덮는다(확정 9). 사본은 `/tmp/run/pem1/`에 만든다. 넷 다
돌리기 전에 `diff`로 편집이 정확히 한 줄 들어갔는지 본다 — `sd -F`가 빗나가도 에러가 없다(lessons
실측 52). 한 줄이 아니면 돌리지 말고 보고한다.

각 체인 run은 캐시를 지운 뒤라 빌드에 1분 안팎이 더 든다(확정 4의 45.6초는 `terminal`만이다).
그래서 한 회가 약 4분이다. Bash 도구의 10분 상한 안이지만, 넘을 것 같으면 `run_in_background`로
돌리고 완료 알림을 기다린다.

### 6-0. 사본을 만든다

```bash
mkdir -p /tmp/run/pem1
cp terminal/src/vt.zig /tmp/run/pem1/vt_m1.zig
cp terminal/src/vt.zig /tmp/run/pem1/vt_m2.zig
cp terminal/src/main.zig /tmp/run/pem1/main_m3.zig
cp terminal/src/main.zig /tmp/run/pem1/main_m4.zig
cp copy/check.sh /tmp/run/pem1/copy_notest.sh
# mutation 1 — 모드와 무관하게 머리 · 꼬리를 비운다(본문이 있으면 언제나 안 감싼다)
sd -F '.get(.bracketed_paste)) return' '.get(.bracketed_paste) or text.len > 0) return' /tmp/run/pem1/vt_m1.zig
# mutation 2 — 언제나 감싼다(본문이 비지 않았으면)
sd -F '.get(.bracketed_paste)) return' '.get(.bracketed_paste) and text.len == 0) return' /tmp/run/pem1/vt_m2.zig
# mutation 3 — 머리와 본문만 쓰고 꼬리를 빠뜨린다
sd -F 'for (parts) |p| {' 'for (parts[0..2]) |p| {' /tmp/run/pem1/main_m3.zig
# mutation 4 — 로그의 bracketed=를 언제나 1로 찍는다
sd -F '@intFromBool(parts[0].len > 0)' '@as(u1, 1)' /tmp/run/pem1/main_m4.zig
# mutation 1 · 2의 체인 판정용 — 부팅 전의 terminal 호스트 검사 한 단계만 끈다
sd -F 'if ! (cd ../terminal && zig build test); then' 'if false; then' /tmp/run/pem1/copy_notest.sh
chmod +x /tmp/run/pem1/copy_notest.sh
for p in "vt.zig vt_m1.zig" "vt.zig vt_m2.zig" "main.zig main_m3.zig" "main.zig main_m4.zig"; do
  set -- $p; echo "== $2"; diff terminal/src/$1 /tmp/run/pem1/$2
done
echo "== copy_notest.sh"; diff copy/check.sh /tmp/run/pem1/copy_notest.sh
```

기대: 다섯 `diff`가 각각 한 줄의 차이(`<` 한 줄과 `>` 한 줄)다. mutation 1 · 2의 차이는
`pasteParts`의 첫 줄, 3은 `dumpPaste`의 `for`, 4는 `dumpPaste`의 `@intFromBool`, 마지막은 `copy/check.sh`의
`if ! (cd ../terminal && zig build test); then` 한 줄이다. 호스트 셸이 zsh라 `set -- $p`가 단어를 안
가를 수 있다 — 그러면 그 루프를 `bash -c '…'`로 감싸 친다(lessons 실측 69).

### 6-1. mutation 1 · 2 — 먼저 `vt_test`

```bash
for m in 1 2; do
  echo "== mutation $m"
  docker run --rm -v "$PWD":/workspace -v /tmp/run/pem1/vt_m$m.zig:/workspace/terminal/src/vt.zig:ro \
    -w /workspace/terminal tars-devcontainer bash -c '
    echo "mounted: $(grep -c "text.len [>=]" src/vt.zig)"
    rm -rf .zig-cache zig-out
    zig build test > /tmp/t.out 2>&1; echo "exit=$?"
    grep -a -E "^FAIL|^  (got|want)|error: PastePartsWrong" /tmp/t.out | head -6'
done
```

기대.

| mutation | 기대 |
|---|---|
| 1 | `mounted: 1`, `exit=1`, `FAIL: 검사 94 ESC[?2004h 뒤 — 조각 0`, `got  {  }`, `want { 27, 91, 50, 48, 48, 126 }`, `error: PastePartsWrong` |
| 2 | `mounted: 1`, `exit=1`, `FAIL: 검사 93 새 화면 — 조각 0`, `got  { 27, 91, 50, 48, 48, 126 }`, `want {  }`, `error: PastePartsWrong` |

`mounted:`가 0이면 사본이 안 덮인 것이다 — 멈추고 보고한다.

### 6-2. mutation 1 · 2 — 체인의 화면 판정

`vt_test`를 건너뛴 사본 체인으로 돌린다. 같은 `docker run` 안에서 캐시를 지운다.

```bash
for m in 1 2; do
  echo "== mutation $m"
  { time docker run --rm -v "$PWD":/workspace -v /tmp/run/pem1:/tmp/run/pem1 \
      -v /tmp/run/pem1/vt_m$m.zig:/workspace/terminal/src/vt.zig:ro \
      -v /tmp/run/pem1/copy_notest.sh:/workspace/copy/check.sh:ro \
      -w /workspace tars-devcontainer bash -c '
    echo "mounted: $(grep -c "text.len [>=]" terminal/src/vt.zig) $(grep -c "if false; then" copy/check.sh)"
    rm -rf terminal/.zig-cache terminal/zig-out
    bash copy/check.sh > /tmp/run/pem1/mut$m.log 2>&1; echo "exit=$?"' ; } 2>&1 | tail -5
  rg -n '^=== |^FAIL|nothing ran before Enter|check 21|cat got' /tmp/run/pem1/mut$m.log | tail -8
done
```

`/tmp/run/pem1`를 통째로 마운트하는 것은 체인 로그(`mut$m.log`)를 호스트로 가져오기 위해서다. 그
안의 사본 파일 둘은 각각 다시 파일 자리에 덮인다.

기대.

| mutation | 어디서 빨개지나 | `FAIL` 줄 |
|---|---|---|
| 1 | 검사 21의 음성 판정. 그 앞의 `the paste reached the fish command line`은 초록이다 — 감싸지 않으면 첫 줄이 실행되고 둘째 줄이 새 입력줄에 남아 `echo PETWO`가 는다(확정 1) | `FAIL: the first line ran before Enter: the paste at the fish prompt was not bracketed` |
| 2 | 검사 22의 음성 판정. 검사 21은 통과하고(`check 21: … bracketed=1`), 검사 22의 양성 판정도 통과한다(`echo PEONE`은 이때도 +2 — 확정 3) | `FAIL: the paste under cat was bracketed: '[200~' showed up on the screen` |

둘 다 `mounted: 1 1`이어야 한다.

### 6-3. mutation 3 · 4 — `main.zig`

`main.zig`는 `vt_test`에 안 들어가므로 체인의 `zig build test`가 초록으로 지나간다. 사본 체인이
필요 없다.

```bash
for m in 3 4; do
  echo "== mutation $m"
  { time docker run --rm -v "$PWD":/workspace -v /tmp/run/pem1:/tmp/run/pem1 \
      -v /tmp/run/pem1/main_m$m.zig:/workspace/terminal/src/main.zig:ro \
      -w /workspace tars-devcontainer bash -c '
    echo "mounted: $(grep -c -E "parts\[0\.\.2\]|@as\(u1, 1\)" terminal/src/main.zig)"
    rm -rf terminal/.zig-cache terminal/zig-out
    bash copy/check.sh > /tmp/run/pem1/mut$m.log 2>&1; echo "exit=$?"' ; } 2>&1 | tail -5
  rg -n '^=== |^FAIL|terminal host tests|the paste reached|check 21|cat got|check 22' /tmp/run/pem1/mut$m.log | tail -8
done
```

기대.

| mutation | 어디서 빨개지나 | `FAIL` 줄 |
|---|---|---|
| 3 | `vt_test`는 초록이다(배선의 실수라 호스트 검사가 못 본다). 검사 21에서 `clip> paste len=21 bracketed=1`은 찍히지만 fish가 꼬리를 기다리며 아무것도 안 그려서, 붙인 줄을 기다리는 판정이 약 15초를 다 쓴다(확정 1). design이 예상한 6단계가 아니라 그 앞이다 | `FAIL: the pasted lines never showed up on the fish command line ('echo PETWO' stayed at N)` |
| 4 | 화면 판정은 전부 초록이고 검사 22의 마지막 필드 판정에서 빨개진다 | `FAIL: the paste under cat was logged as 'terminal: clip> paste len=21 bracketed=1', expected 'clip> paste len=21 bracketed=0'` |

둘 다 `mounted: 1`이어야 한다. mutation이 예상과 다른 자리에서 죽거나 초록이면 그대로 적어 보고한다.
초록이면 먼저 바이너리를 의심한다(`project_zig_out_staleness` 일곱번째 — 캐시 삭제가 같은 `docker run`
안에 있었는지, `mounted:`가 1이었는지).

### 6-4. 되돌린다

mutation 체인은 저장소의 `terminal/zig-out`과 `kernel/initrd.cpio`(둘 다 gitignore 대상)에 망가진
판을 남긴다. 캐시를 컨테이너 안에서 지우고 호스트 검사를 한 번 더 돌려, 다음에 체인을 돌리는
사람이 낡은 산출물을 쓰지 않게 한다. 덮었던 사본 파일은 저장소 밖(`/tmp/run/pem1/`)이라 저장소에
안 남는다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf terminal/.zig-cache terminal/zig-out
  cd terminal && zig build test > /tmp/t.out 2>&1; echo "exit=$?"; grep -ac "^PASS" /tmp/t.out'
git status --short
```

기대: `exit=0`, `5`. `git status`는 `M` 넷(`copy/check.sh` · `terminal/src/main.zig` ·
`terminal/src/vt.zig` · `terminal/src/vt_test.zig`)과 이 plan(`??`)뿐이다. 다른 것이 보이면(특히 `-v`로
없는 파일을 덮어 Docker가 만든 0바이트 파일) 그 목록을 보고한다.

### 6-5. 보고

구현자는 여기까지 하고 lead에게 보고한다. 보고에 담을 것.

- `git diff --stat`(전체)과 `git diff | rg '^-'`(전체).
- Task 0의 출력 넷(`docker ps` · `git status` · `rg` · 기준 `vt_test`와 체인의 `exit=` · `real`).
- Task 1~4의 확인 출력(`--stat` · `rg '^-'` · `SYNTAX-OK` · `ENTRY-OK` · `vt_test`의 OK 줄).
- Task 5의 `exit=` · `real` · 5-1의 `rg` 출력 · 5-2의 (a)(b)(c) 출력.
- Task 6의 `diff` 다섯 · 넷의 `mounted:` · `exit=` · `real` · `FAIL` 줄, 6-4의 출력.
- plan의 기대와 글자나 수가 다른 것이 있으면 그 줄을 그대로.

## Task 7: lead가 하는 것

1. 보고를 받아 diff를 직접 읽고(`git diff`), Task 5의 로그를 `Read`로 대조한다.
2. 루트 게이트. 18체인 × 3, 약 1시간 5분이다(GE-M0 1시간 5분 52초). `terminal` 바이너리가 initrd의
   `/terminal`이므로 열여덟 체인이 전부 새 initrd로 부팅한다(design 검증 "셋 다"). Bash 도구의 10분
   상한을 넘으므로 `run_in_background`로 돌리고 `{ time …; }`로 감싼다.

   ```bash
   { time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/gate_pe1.log 2>&1 ; echo "exit=$?" ; } 2> /tmp/gate_pe1.time
   ```

   완료 알림이 오면 `pgrep -f 'tars-devcontainer bash check.sh'`가 비었는지 먼저 보고 판정한다.
   `rg -c 'PASS: 3/3' /tmp/gate_pe1.log`가 18이어야 하고, `copy`의 회차마다
   `check 21: the paste at the fish prompt was bracketed` · `check 22: the paste under cat went unwrapped`가
   한 번씩(합계 각 3) 있어야 한다.

   PE-M0은 루트 게이트를 안 돌리고 이 게이트에 맡겼다(PE-M0 plan 실측 6). 그래서 이 게이트에서
   `service`(CT-M2)가 3/3이면 그것이 PE-M0의 루트 게이트 기록도 된다 — 실측 절에 그렇게 적는다.
   `service`의 회차마다 부팅 B · C · D가 `boot_ssh`의 새 기다림을 지난다.
3. 실측 절 채우기. 구현자의 보고와 루트 게이트의 시간 · 결과를 아래 "PE-M1이 실측한 것"에 적는다.
   확정 2의 덤(fish 4.0.2가 인자를 칠 때와 두 줄을 받은 직후 모드 2004를 끈다)을 design 위험에 한 줄로
   더할지 정한다 — 이 plan은 더하기를 권한다. 위험 4가 "fish가 그 동작을 바꾸면"을 적고 있으므로 그
   옆이 자리다.
4. commit. 넣는 것은 `terminal/src/vt.zig` · `terminal/src/main.zig` · `terminal/src/vt_test.zig` ·
   `copy/check.sh` · 이 plan이다. design의 위험 줄을 더했으면 design도 함께 넣는다.
5. `docs/guides/lessons.md`의 `copy/check.sh` 항목("검사 스물")과 "로그 문구는 두 곳에 중복된다"의
   `terminal: clip> paste`는 design "닫을 때"에 있는 일이다 — 서브프로젝트를 닫을 때 하거나, 이
   commit에 함께 넣을지 lead가 정한다.

## design과 다르게 적은 것

1. mutation 3이 빨개지는 자리. design은 "검사 21의 6단계가 빨개질 것으로 본다"였다. 확정 1의 측정에서
   fish는 꼬리가 없으면 붙인 글자를 하나도 안 그리고 그 뒤의 키를 전부 삼켰다. 그래서 그 앞인
   "붙인 줄이 입력줄에 나타난다"(design의 4단계)가 15초를 다 쓰고 빨개진다.
2. 검사 22의 양성 판정. design은 화면에 `| echo PEONE | echo PEONE | echo PETWO`가 생기는 것을
   기대했다. 확정 3의 측정에서 순서는 `| echo PEONE | echo PETWOecho PEONE`이었다. 이 plan은 모양 대신
   마지막 프레임의 `echo PEONE`이 둘 느는 것으로 판정한다 — 두 순서 모두에서 참이다.
3. `bracketed=` 필드를 보는 자리. design은 검사 21의 4단계 · 검사 22의 2단계였고, 이 plan은 두 검사의
   맨 끝이다(확정 7). 그래서 mutation 2를 잡는 것은 design의 "검사 22의 3 · 4단계"가 아니라 4단계(음성
   판정) 하나이고, mutation 1 · 4가 잡히는 자리는 design과 같다.
4. 검사 21에 판정 하나를 더했다. `k k` 뒤에 copy 커서가 정확히 두 행 올라갔는지 본다(검사 8과 같은
   모양). 이것이 없으면 커서가 엉뚱한 줄에서 `V j y`를 해도 다음 판정(`clip> len=21 text=echo PEONE`)에
   가서야 드러나고, 그 메시지는 원인을 말하지 않는다.
5. 새 위험 하나(확정 2의 덤). fish 4.0.2는 프롬프트 내내 모드 2004를 켜 두지 않는다. design 결정 2의
   규칙은 그대로 두고, 위험 줄을 더할지는 lead에게 맡긴다(Task 7-3).

design의 전제가 코드와 어긋난 것은 없었다. `pasteParts(self: *const Screen, …)`는 `ModeState.get`이
`*const`를 받아서 그대로 된다(확정 6). `findPaste` doc 주석의 문장, `copy/check.sh`의 515 · 564 · 567줄,
검사 20이 마지막이라는 것, `vt_test`의 마지막이 92라는 것이 전부 design대로였다.

## 이 milestone에서 안 하는 것

- vim의 계단을 게이트에서 보는 것(design 비목표 7).
- 모드가 꺼진 갈래의 `\n` → `\r`과 제어 바이트 치환(design 비목표 1).
- fish가 모드를 끄는 순간에 붙인 여러 줄을 막는 것(확정 2의 덤). design 비목표 2(감싸지 않는 여러 줄
  붙여넣기를 막거나 묻는 것)와 같은 종류다.
- 큰 붙여넣기에서 `pty.write`가 멈추는 것(design 위험 3 · 비목표 5).
- `HANDOFF.md` · `CLAUDE.md` · `MEMORY.md` · design의 `Status:`(design "닫을 때").

## PE-M1이 실측한 것

2026-10-04. Task 0~6은 Opus 서브에이전트가 하고 보고했고, lead가 diff(`git diff`)와 체인 로그 ·
시리얼 로그를 직접 읽어 대조했다. Task 7은 lead가 했다.

1. Task 0의 기준값. 돌고 있는 docker 없음. 고칠 자리 아홉이 plan의 참고 줄 번호 그대로였고
   `pasteParts` · `bracketed=`는 0줄. 기준 `vt_test`는 `PASS` 다섯 줄. 기준 `copy` 체인은 `exit=0` ·
   `CM-M2 check PASS`에 3분 14.75초 — plan이 적은 CU-M0 때의 2분 31초보다 44초 길다(그 사이 TG · CU ·
   GE가 체인에 검사를 더했다).
2. Task 1~4의 diff. `vt.zig` +28/−3(지운 셋은 `findPaste` doc 주석의 기대한 세 줄) · `main.zig` +23/−6
   (doc 주석 넉 줄과 본문 두 줄) · `vt_test.zig` +59/−0(`pe_` 선언 일곱) · `copy/check.sh` +186/−0.
   `SYNTAX-OK` · `ENTRY-OK`. 구현자는 Edit 도구 대신 python 정확 치환(치환마다 `count == 1`을 확인)을
   썼다 — 결과 diff는 plan의 편집 전후와 글자까지 같았다.
3. `vt_test` 93~96. `exit=0`, 새 OK 넷이 plan의 글자 그대로, `PASS` 다섯 줄. 검사 95(모드가 화면별이
   아니다)와 96(RIS가 끈다 · 개행 보존)이 첫 실행에 초록이었다 — design 실측 2가 맞았다.
4. Task 5의 `copy` 체인. `exit=0` · `CM-M2 check PASS`에 3분 28.59초(기준보다 13.84초 — 검사 둘의 `sleep`과
   기다림). 검사 21은 `the paste reached the fish command line (echo PETWO 2 -> 3)` · `nothing ran before
   Enter` · `Enter ran both pasted lines together` · `check 21: … bracketed=1`, 검사 22는 `cat got the two
   lines as they are (echo PEONE 0 -> 2, no [200~ on screen)` · `check 22: … bracketed=0`. 시리얼 로그의
   붙여넣기 줄은 넷 — `len=11 bracketed=1` 둘(검사 11 · 13, fish의 빈 프롬프트) · `len=21 bracketed=1` ·
   `len=21 bracketed=0`. PE-M1 전의 기준 로그는 `len=11` 둘이었다.
   게스트의 화면 모양(확정 2 · 3을 게스트에서 처음 본 것). 붙인 뒤 Enter 전의 프레임은
   `root@(none) ~# echo PEONE | echo PETWO`로 둘째 행 앞의 칸이 `screen>`에 안 찍혔고(확정 2대로), Enter
   뒤에 `| PEONE | PETWO | root@(none) ~#`가 왔다. `cat` 쪽은 `root@(none) ~# cat | echo PEONE | echo
   PETWOecho PEONE`(확정 3의 순서)이고, ctrl-c 뒤에 `^C⏎`와 긴 공백, 그다음 프레임에
   `root@(none) ~ [SIGINT]#`가 왔다 — fish가 `^C` 뒤에 `⏎`를 찍는 것은 plan이 적지 않은 모양이다.
   plan 5-1의 `rg` 패턴은 기대 목록의 열다섯 줄 중 다섯(`entering copy mode` · `the clipboard holds` ·
   `nothing ran before Enter` · `running the pasted lines` · `Enter ran both`)을 고르지 못했다 — 글자가
   패턴에 없었다. 로그를 `sed -n`으로 직접 읽어 열다섯 줄이 기대 순서 그대로인 것을 봤다. plan 5-2
   (b)의 `-A1`은 빈 줄을 보였다 — perl이 `\r\n`을 빈 줄 하나로 만들어서다. `-A3`으로 `echo PETWO`가
   다음다음 줄에 있었다. (c)의 `tail -6`은 범위에 `cat` 타이핑 프레임이 들어 있어 붙여넣기 프레임을
   못 보였고 `head -12`로 봤다.
5. Task 6의 mutation 넷. 사본 `diff` 다섯이 전부 한 줄 차이. 캐시를 지운 체인 한 판은 3분 48초 ~ 3분 58초.

   | mutation | `vt_test` | 체인 | 기대와 |
   |---|---|---|---|
   | 1 안 감싼다 | `FAIL: 검사 94 ESC[?2004h 뒤 — 조각 0`, `got {  }` | (`vt_test` 건너뛴 사본) 검사 21의 `the paste reached …` 뒤 `FAIL: the first line ran before Enter: the paste at the fish prompt was not bracketed` | 같다 |
   | 2 언제나 감싼다 | `FAIL: 검사 93 새 화면 — 조각 0`, `got { 27, 91, 50, 48, 48, 126 }` | 검사 21 통과(`bracketed=1`) 뒤 `FAIL: the paste under cat was bracketed: '[200~' showed up on the screen` | 같다 |
   | 3 꼬리를 빠뜨린다 | 초록(배선의 실수라 못 본다) | 검사 11에서 `FAIL: the pasted text never showed up on screen ('echo PASTED' stayed at 2)`, 2분 06초 | 다르다 — 잡히는 자리가 검사 21의 4단계가 아니라 기존 검사 11이다. 확정 8대로 검사 11의 한 줄 붙여넣기도 fish 빈 프롬프트에서 감싸 가므로, 꼬리가 없으면 fish가 거기서 먼저 삼킨다. 새 판정이 아니라 기존 판정이 잡는다 |
   | 4 필드를 언제나 1로 | 초록 | 검사 22의 `cat got …` 뒤 `FAIL: the paste under cat was logged as 'terminal: clip> paste len=21 bracketed=1', expected 'clip> paste len=21 bracketed=0'` | 같다 |

   plan 6-2 · 6-3의 명령에 버그가 있었다. `bash -c '…mut$m.log…'`의 `$m`이 작은따옴표 안이라 컨테이너에서
   빈 값이 되어 두 run이 같은 `mut.log`에 썼다. 구현자가 `-e m=$m`을 더해 다시 돌렸고(m1 재실행), 6-3에
   같은 수정을 넣었다. 6-4 뒤 `zig build test`는 `exit=0` · `PASS` 다섯, 0바이트 파일은 생기지 않았다.
6. 루트 게이트. 18체인 × 3 전부 PASS, 1시간 7분 14.30초(GE-M0 1시간 5분 52초보다 1분 22초 길다 — `copy`
   체인이 검사 둘로 약 14초 길어진 것이 세 번), `FAIL` 0줄. `copy`(CM-M2)의 회차마다 `check 21: the paste
   at the fish prompt was bracketed`와 `check 22: the paste under cat went unwrapped`가 한 번씩(합계 각 3).
   `service`(CT-M2)가 3/3 — PE-M0은 루트 게이트를 안 돌리고 여기에 맡겼으므로(PE-M0 plan 실측 6) 이것이
   PE-M0의 루트 게이트 기록이다. 부팅 B · C · D 아홉 번이 `boot_ssh`의 새 기다림을 지났다.
7. Task 7-3의 판단. 확정 2의 덤(fish 4.0.2가 인자를 치는 중과 두 줄을 받은 직후에 모드 2004를 끈다)을
   design 위험 4에 한 단락으로 더했다. 결정 2의 규칙은 그대로다. lessons의 `clip> paste` 문구와
   `copy/check.sh` 항목(검사 스물둘)도 이 commit에 함께 넣었다.

## 닫을 때

PE-M1은 서브프로젝트를 닫지 않는다. 다음은 PE-M2 plan이다(design 결정 7 · 8, Sonnet 구현).
