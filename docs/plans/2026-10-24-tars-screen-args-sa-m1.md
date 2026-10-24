# SA-M1 — argv를 짓는 함수와 읽는 함수도 `screen_args.zig`로 간다

Date: 2026-10-24
Design: `docs/specs/2026-10-24-tars-screen-args-design.md` 결정 7
Status: 초안(M0의 루트 게이트가 도는 동안 썼다 — 게이트 결과로 바뀌는 자리가 있으면 고친 뒤 구현에 넘긴다).

## 왜 M1이 따로인가

M0 뒤에도 "칸에 무엇을 넣는가"는 init의 두 자리(`main`의 `term_argv` 아홉 줄 · `doReloadTerminal`의 일곱 줄)와 terminal의
읽는 자리(`argAt` · `enumArg` 호출 여덟)에 흩어져 있다. 이름은 같지만 세 자리가 각자 칸을 채우고 읽는다 — 칸을 하나 더하면 세
자리를 다 고쳐야 하고, 한 자리를 빠뜨려도 컴파일은 통과한다(`Slot`에 이름을 더해도 그 칸을 안 채우면 null일 뿐이다).
M1은 그 셋을 한 함수 쌍으로 모은다 — `encode`가 `Args`에서 argv를 짓고 `decode`가 argv에서 `Args`를 되돌린다. 칸을 더하는
일은 `Args`에 필드 하나, `Slot`에 이름 하나, `encode` · `decode`에 한 줄씩이고, 왕복 검사가 "encode한 것을 decode하면 같다"를 본다.

## 누가 무엇을 하나

M0과 같이 lead가 직접 넣는다. 새 파일은 없다.

| 파일 | 무엇을 |
|---|---|
| `shared/screen_args.zig` | `Args` · `Argv` · `encode` · `decode` |
| `shared/screen_args_test.zig` | encode → decode 왕복, 빈 argv · 짧은 argv · 엉뚱한 enum 글자의 decode |
| `init/src/config.zig` | `Config.screenToggles() Toggles`(집합). 글자를 주는 `terminalToggles`는 로그와 검사가 쓰므로 남긴다 |
| `init/src/main.zig` | `term_argv` 아홉 줄 → `encode` 한 번. `doReloadTerminal` 일곱 줄 → `decode` · 필드 대입 · `encode`. `slot()`은 탈출로 하나에 남는다 |
| `terminal/src/main.zig` | `argAt` · `enumArg`를 지우고 `decode` 한 번. 읽는 자리 여덟이 `a.shell_path` 같은 필드가 된다 |

## 착수 전에 확정한 것

1. `Args`는 값을 타입으로 든다. 전환 키는 `Toggles`(집합)이고 글자가 아니다 — 글자는 `encode` 안에서만 생긴다.

   ```zig
   pub const Args = struct {
       shell_path: [*:0]const u8,
       shell_flag: [*:0]const u8,
       keyboard: Keyboard,
       device_path: [*:0]const u8,
       hangul: HangulLayout,
       latin: LatinLayout,
       toggles: Toggles,
       clipboard: ClipboardScope,
   };
   pub const Argv = [ARGC:null]?[*:0]const u8;
   /// `toggle_buf`는 호출자가 들고 argv가 살아 있는 동안 유지한다 — init에는 힙이 없다.
   pub fn encode(a: Args, toggle_buf: *[TOGGLE_ARG_MAX]u8) Argv;
   /// 없는 칸과 못 읽는 글자는 기본값이다.
   pub fn decode(argv: Argv) Args;
   ```

2. `encode`의 버퍼는 init이 이미 들고 있는 둘이다 — 부팅은 `main`의 `terminal_toggle_buf`, reload는 `Live.toggle`. `encode`가
   `a.toggles.arg(buf)`를 그 버퍼에 쓰고 그 포인터를 `Slot.toggles`에 넣는다. 지금과 수명이 같다.
3. `decode`는 `Argv`(optional 아홉 칸)를 받는다. terminal의 `init.minimal.args.vector`는 모양이 다르므로(길이가 가변인 슬라이스)
   `fn argvOf(args: anytype) Argv`가 앞 `ARGC`칸을 옮긴다 — 그 함수도 공유 파일에 둔다. init의 `doReloadTerminal`은
   `children[0].argv`를 그대로 `decode`에 준다.
4. `doReloadTerminal`은 `var a = decode(term.argv); a.shell_path = …; … ; term.argv = encode(a, &live.toggle);`다. 장치 경로는
   `decode`가 꺼낸 값이 그대로 다시 들어가므로 "설정이 아니라 안 건드린다"가 코드로 선다 — M0까지는 "그 칸을 대입하지 않는다"는
   부재로만 표현됐다.
5. 탈출로(`Rescue.slot`)는 그대로다. `c.argv[r.slot] = r.flag.ptr`는 terminal과 콘솔 셸을 같은 코드로 다루는 자리라 `Args`를
   모르는 편이 맞다. `TERMINAL_FLAG_SLOT = slot(.flag)`가 남는 이유다.
6. terminal의 로그 줄 셋(`keyboard=` · `hangul layout=` · `clipboard scope=`)은 `decode`가 돌려준 값을 `@tagName` · `arg`로 찍는다 —
   글자는 같다. 체인 스크립트는 안 고친다.
7. 검사 — `Args` 둘(기본값 전부 · 전부 다른 값)의 encode → decode가 같은가(포인터 칸은 글자로 비교), `decode(@splat(null))`이
   기본값인가, `Slot.hangul` 칸에 `"bogus"`를 넣으면 그 칸만 기본값이고 나머지는 사는가, `encode`가 0번 칸에 `/terminal`을 넣는가.

## Task 1: `screen_args.zig` · `screen_args_test.zig`

확정 1 · 3 · 7. `encode`는 `var v: Argv = @splat(null)`에서 시작해 `v[0] = "/terminal"`, 나머지는 `v[@backingInt(Slot.x)] = …`.
`decode`는 칸마다 `v[@backingInt(Slot.x)] orelse 기본값`, enum 칸은 `stringToEnum … orelse 기본값`, 전환 키는
`Toggles.parse(.argv, span, ignore_unknown)`.

## Task 2: init

`config.zig`에 `screenToggles`. `main.zig` — `term_argv` 블록을 `screen_args.encode(.{ … }, &terminal_toggle_buf)`로,
`doReloadTerminal`을 확정 4로. `TERMINAL_PATH` 상수는 공유 파일의 것(`encode`가 0번에 넣는 글자)과 같아야 한다 — 공유 파일로
옮기고 init은 별명으로 쓴다(`Child.path`가 그 글자다).

## Task 3: terminal

`main.zig` — `const a = screen_args.decode(screen_args.argvOf(args));`. `input_device`는 `a.device_path`, 나머지 일곱도 필드.
`argAt` · `enumArg` 삭제.

## Task 4: 검사와 게이트

M0과 같다 — 컨테이너에서 두 `zig build` · `zig build test`, 호스트 `zig fmt --check` · `ast-check`, 루트 게이트.

## SA-M1이 실측한 것

1. 루트 게이트 22/22(2026-10-24 23:52 시작, 약 10분 37초 — prebuild 약 335초 + lanes 약 302초). 요약 한 줄은 못 남겼다 — 로그를
   `out/sa-m1-gate.log`로 보냈는데 `check.sh`의 `clean()`이 게이트 시작에 `out/`을 지운다(lessons "범용 명령"이 `/tmp/gate.log`를
   쓰는 이유). 체인별 판정은 `out/gate-logs/20261024-145224/lane-*.out`의 `consecutive runs succeeded` 스물둘과 종료 코드 0으로
   확인했고, 초는 `prebuild.out` · `times.tsv`의 mtime에서 왔다. 가장 긴 체인은 CP-M2 187초 · TD-M2 180초 · CM-M2 164초.
2. 호스트 `zig fmt --check` · `ast-check` 통과, 컨테이너 init · terminal `zig build`와 두 `zig build test` PASS. `shared/`는 순수
   파일이라 `zig run shared/screen_args_test.zig`가 호스트 macOS Zig에서 그대로 돈다 — 컨테이너 전에 공유 파일 검사를 먼저 본다.
3. plan과 달라진 자리 — init의 `fn slot()`을 남기지 않고 공유 `Slot.index()`로 대신했다(같은 한 줄 변환이 두 파일에 있는 것이 SA가
   없애려는 중복이다). terminal의 `init.minimal.args.vector`는 `[]const [*:0]const u8`(0.17 `std.process.Args.Vector`)라
   `argvOf`가 `anytype` 없이 그 타입을 받는다. `Args`에 기본값을 두지 않았다(필드를 빠뜨리면 컴파일이 막혀야 한다).
   `default_toggles`(집합)를 `default_toggles_arg`(글자) 옆에 더했고 둘이 같은지를 검사 6이 본다.
4. 줄 수 — 공유 파일 +110, 검사 +118, init `main.zig` 88줄 바뀜(짓는 자리 둘이 `encode` 한 번과 `decode → 대입 → encode`),
   terminal `main.zig` -28줄(`argAt` · `enumArg`와 호출 여덟이 `decode` 한 줄과 필드 꺼내기 일곱으로). 로그 줄과 체인 스크립트는
   글자 하나 안 바뀌었다(design 결정 8) — 게이트가 그것을 봤다.
