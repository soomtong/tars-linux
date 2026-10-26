# HC-M2 — `tars-install`의 판정과 문장을 `disk`로 내린다

Date: 2026-10-26
Design: `docs/specs/2026-10-25-tars-host-checks-design.md` 결정 1 · 2 · 6 · 8 ~ 12
Status: 초안 — HC-M1 루트 게이트가 도는 동안 썼다. 그 게이트는 22/22였고 결과로 바뀌는 자리는 없다. 사용자 확인 뒤 구현에 넘긴다.

## 누가 무엇을 하나

고치는 파일은 셋이다 — `init/src/disk.zig`(더한다) · `init/src/disk_test.zig`(더한다) · `init/src/install.zig`(뺀다). `build.zig`는
0줄이다 — `disk_test`는 이름 붙은 모듈 없이 서고, 새로 import할 `control.zig`도 `std` · `logline` · `services`만 부른다
(2026-10-26 확인). lead가 직접 넣는다(M0 · M1과 같다). Task마다 commit 하나다.

| Task | 무엇을 | 검사 |
|---|---|---|
| 1 | `disk`에 판정 · 문장 함수, `disk_test`에 검사 14 ~ 18. `install`은 그대로 | `zig build test` · (a) `>`만 |
| 2 | `install`이 그 함수를 부른다 | 빌드 · (a) 빈 diff · `--color-moved` · install 체인 |
| 3 | 호스트 `fmt` · `ast-check`, mutation 둘, 루트 게이트, 실측, 닫기 | 22/22 |

## 착수 전에 확정한 것

1. 검사 (a)는 M0의 명령에서 파일 집합만 바꾼다 — `F='init/src/install.zig init/src/disk.zig'`(design 결정 2(a)의 실행 파일 단위).
   `/tmp/hc-inst-fmt.sh`로 묶는다. 2026-10-26 기준선 57줄. Task 1 전에 다시 뽑는다.

   체인은 install 하나다(`make check CHAIN=install`). 그 체인이 이 milestone의 글자를 보는 자리: usage 마지막 줄(`LIST_END`, 149),
   `type YES to continue: ` · `not confirmed`(200 ~ 241), 목록 행 `internal +blank` · `internal +TARS installed`(192 · 312 · 352),
   `already has TARS. p1 will be updated…`(363). 안 잡히는 것 — `will be erased`의 줄 · `rest unallocated` · `the settings now on p2 are
   erased too` · `failed (exit N)` · `was killed (signal N)` · `removable`. 그것은 Task 1의 want가 유일한 그물이다(design 확인 7).

2. 여러 줄은 `sink: anytype`다(M0 plan 확정 3, M1과 같다). design 결정 6의 "한 버퍼에 이어 짓고 `writeAll` 한 번"은 M0에서 sink로 바뀌었다.
   `install`에 sink 둘을 둔다 — `Say`(줄마다 `say`)와 `Complain`(줄마다 `complain`, 접두사 `tars-install: `과 개행을 `complain`이
   붙인다). 둘 다 `say` · `complain`의 `disk.clip`(512바이트)을 그대로 지난다. 검사는 `control.Out`에 받는다 — `Complain`으로 갈 글자는
   접두사 · 개행 없이 보인다.

3. 순서의 함정. 시스템 콜 쪽이 지금 짧게 끊는 자리가 둘이다.

   - `stateOf` — 매체 경로와 같으면 `isInstalled`를 안 부른다. `isInstalled`는 p1을 붙여 본다 — 매체 디스크의 p1을 붙이게 되면
     동작이 바뀐다. 그래서 `stateOf`의 앞 둘(경로 비교 · `isInstalled`)은 `install`에 남고, 앞머리를 읽은 뒤의 셋(못 읽음 · TARS ISO ·
     `stateText`)만 `disk.headState`로 간다.
   - `p2HasSettings` — 지금은 새 설치 갈래에서 넷째 줄을 찍은 뒤에 읽는다. 문장 함수에 bool로 주려면 그 앞에 읽어야 한다. 갱신
     갈래에서는 안 읽도록 `!update and p2HasSettings(path)`로 짧게 끊는다. 표준 출력 사이에 끼던 p2 앞머리 읽기가 그 앞으로 오는
     것뿐이라 바이트는 같다(design 확인 10).

4. 함수(design 결정 8). 모두 `disk.zig`의 `pub`.

   | 함수 | 지금 자리 | 서명 |
   |---|---|---|
   | `sectorsToBytes` | `sizeBytes` 88 ~ 89 | `fn sectorsToBytes(text: []const u8) ?u64` — `parseInt` · `* 512`. 넘침은 지금처럼 검사하지 않는다(비목표 2) |
   | `STATE_MEDIUM` · `STATE_INSTALLED` | `install` 196 ~ 197 | 글자 그대로 `pub const` |
   | `State` · `stateWord` | `stateOf`의 돌려주는 글자 · `install`의 `eql` 둘 | `union(enum) { medium, installed, other: []const u8 }`, `fn stateWord(s: State) []const u8` |
   | `headState` | `stateOf` 208 ~ 212 | `fn headState(buf: []u8, seen: ?Seen) State` — null이면 `.other = "unreadable"` |
   | `listRow` | `list` 241 ~ 247 | `fn listRow(sink: anytype, path, size, model, removable: []const u8, state: []const u8) void` — `"1"`이면 `removable` |
   | `planLines` | `install` 512 ~ 527 | `fn planLines(sink: anytype, update: bool, path, size, model, state: []const u8, p2_settings: bool) void` |
   | `toolFailure` | `runTool` 330 ~ 336 | `fn toolFailure(sink: anytype, tool: []const u8, status: u32) bool` — 0으로 끝났으면 true(찍지 않는다) |
   | `usageLines` | `printUsage` 145 ~ 147 | `fn usageLines(sink: anytype) void` |

   `State`가 문자열 비교를 대신한다 — `install`의 `std.mem.eql(u8, state, STATE_MEDIUM)` 둘이 `switch`가 된다. 글자는 `stateWord`가
   `list`와 `will be erased. it now holds: {s}`에 준다(설치된 디스크의 `--wipe`가 `TARS installed`를 거기 찍는다 — 지금과 같다).

   `toolFailure`의 판정은 `audio.outcome(status)`의 모양이다(`linux.W.*`는 status를 읽는 순수 함수다). `usageLines`는 `USAGE`
   상수가 아니라 함수다 — 여러 줄 리터럴(`\\`)로 바꾸면 (a)의 정규식이 그 세 줄을 못 보고 diff가 `<` 셋을 낸다.

   안 내려가는 것 — `list`의 매체 줄 둘(조건 하나에 문장 하나, 하나는 `printable` · `formatSize`를 이미 부른다), `(no disks)`,
   진행 줄(`writing the partition table` · `formatting …` · `syncing` · `copying` · `  {s} {d} bytes`), `type YES to continue: `
   (개행 없는 질문, design 결정 8), `not confirmed` · `updated` · `done`, `complain`의 errno 줄들(시스템 콜의 결과).

5. 검사 14 ~ 18의 want는 Task 1에서 지금의 `install.zig`에서 베낀다(design 결정 9).

   | 검사 | 무엇을 | 베끼는 줄 |
   |---|---|---|
   | 14 크기 · 상태 | `sectorsToBytes`(`"2097152"` → 1 GiB, `""` · `"x"` → null), `headState` 넷(null · TARS ISO · 남의 ISO · blank), `stateWord` 셋 | 88 ~ 89 · 196 ~ 212 |
   | 15 목록 행 | `listRow` 둘 — internal blank, removable TARS installed(칸 폭이 체인의 `^  /dev/nvme0n1 +[0-9]+ GB .* internal +blank$`에 맞는다) | 241 ~ 247 |
   | 16 계획 | `planLines` 셋 — 갱신, 새 설치, 새 설치 + p2 설정 | 512 ~ 527 |
   | 17 도구 실패 | `toolFailure` 셋 — 0(true, 출력 없음), exit 1, SIGKILL. status는 `W` 매크로의 역(`code << 8` · `sig`)으로 짓는다 | 330 ~ 336 |
   | 18 usage | `usageLines` 세 줄, 마지막 줄이 install 체인의 `LIST_END`와 글자가 같다 | 145 ~ 147 · `install/check.sh` 149 |

6. mutation 둘(Task 3, design 결정 10).

   | mutation | 비틀 것 | 잡아야 할 검사 |
   |---|---|---|
   | m1 판정 | `headState`가 `isTarsMedium`을 안 본다(TARS ISO가 `foreign (iso9660 TARS)`) | 14 |
   | m2 문장 | `planLines`의 `"  rest unallocated\n"`를 `"  rest free\n"`로 | 16 |

## Task 1: `disk`에 더하고 검사 14 ~ 18

`install.zig`는 한 줄도 안 고친다. (1) 기준선을 다시 뽑는다(57줄). (2) `disk.zig`에 확정 4를 넣는다 — 판정은 `stateText` 곁, 문장은 끝의
새 절 "── 문장 ──". 주석도 함께 간다(`printUsage`의 "마지막 줄이 목록의 끝", `sizeBytes`의 "늘 512바이트 단위", `STATE_*`의 "한 곳에").
(3) `disk_test`에 검사 14 ~ 18.

검사 — `zig build test` PASS, (a) `>`만, `git diff --stat`의 지운 줄 0.
commit: `HC-M2: Add the installer's state, row, plan and failure sentences to disk`.

## Task 2: `install`이 부른다

`Say` · `Complain` sink를 더하고, `sizeBytes` · `stateOf` · `list` · `install`의 계획 · `runTool`의 끝 · `printUsage`를 부르는 자리로
바꾼다(확정 3의 순서). 지우는 편집이라 `git diff | rg '^-'`로 지운 줄을 읽는다. 검사 — 빌드, (a) 빈 diff, install 체인.
commit: `HC-M2: Route tars-install through the moved state and sentences`.

## Task 3: 호스트 검사 · mutation · 루트 게이트 · 닫기

M1 Task 3과 같고, 끝에 design "닫을 때"의 넷을 한다 — design `Status:` · `completed.md` 한 행, `project_host_checks.md` ·
`MEMORY.md` 한 줄, lessons "핵심 파일"의 세 줄, `HANDOFF.md`.

## HC-M2가 실측한 것

(Task 3 뒤에 채운다.)
