# BV-M0 — VERSION 한 줄이 tars-config와 부팅 로그에 닿는다

Date: 2026-10-20
Design: `docs/specs/2026-10-20-tars-build-version-design.md`
Status: 끝났다(2026-10-20). 값은 맨 아래 "BV-M0이 실측한 것".

## 누가 무엇을 하나

범위가 작아(새 파일 셋, 편집 넷) lead가 직접 넣는다. 서브에이전트는 안 쓴다. 매 편집 뒤 `git diff --stat`, 지우는 편집은
`git diff | rg '^-'`로 본다.

| 파일 | 무엇을 |
|---|---|
| `VERSION` | 새 파일 — `0.1.0` 한 줄 |
| `init/src/version.zig` | 새 파일 — `base` · `format` 순수 함수 둘(결정 1 · 2 · 6) |
| `init/src/version_test.zig` | 새 파일 — 그 호스트 검사 |
| `init/build.zig` | git 물음 · `build_info` options를 두 모듈에 · `version_test` 등록 |
| `init/src/config_cli.zig` | `version` · `--version` · `-V` 갈래, `USAGE` 한 줄, `help` 첫 줄 |
| `init/src/main.zig` | 첫 로그 줄 끝에 `(TARS <ver>)` |
| `config/check.sh` | 부팅 1 — `tars-config version`과 로그 줄 대조(결정 9) |

## 착수 전에 확정한 것

1. Zig 0.16 std에서 확인한 모양(컨테이너 `/usr/local/zig/lib/std`):
   `b.runAllowFail(argv, *u8, std.process.SpawnOptions.StdIo) RunError![]u8` — 종료 코드가 0이 아니면 `error.ExitCodeFailure`이고
   `out_code`에 코드를 남긴다. `Module.addOptions(name, *Step.Options)`. `Io.Limit.limited(n)`.
2. design 위험 2(`.git/index`)는 미리 막는다 — git 셋 모두에 `--no-optional-locks`를 붙인다. 구현 중 실측(Task 5): 컨테이너
   git 2.47.3의 `diff --quiet HEAD`는 그래도 index를 매번 다시 썼다. dirty 물음을 `status --porcelain --untracked-files=no`로
   바꿨고, 그것은 두 번 돌려도 index의 mtime이 그대로였다.
3. 태그와 HEAD는 둘 다 `--short=7`로 받아 비교한다. 같은 객체면 git이 고른 길이도 같다.
4. 게이트의 화면 대조는 `joined_screen_dump`(행을 ` | `로 잇는다)에서 `\| TARS [^ |]+`를 뽑는다. 친 명령 줄
   `tars-config version`에는 대문자 `TARS`가 없다.

## Task 1: `VERSION` · `init/src/version.zig` · `version_test.zig`

`version.zig`는 시스템 콜이 없다. `format`은 `head`가 null(git을 못 썼다)이면 `ver` 그대로, 태그와 같고 깨끗하면 그대로,
그 밖이면 `ver+head`에 dirty면 `-dirty`.

검사: 결정 2의 표 네 칸, 결정 3(head null — dirty여도 꼬리표 없음), `base`의 공백 벗기기 · 빈 것 · 65바이트 거절.

## Task 2: `init/build.zig`

파일 끝에 `fn buildVersion(b) []const u8`와 `fn git(b, root, args) ?[]const u8`를 둔다. `../VERSION`을 못 읽거나 `base`가
거절하면 `std.process.fatal`로 빌드를 멈춘다(결정 1). `build_info`를 `exe_mod` · `config_cli_mod`에 붙이고 `version_test`를
`test_step`에 더한다.

## Task 3: `config_cli.zig` · `main.zig`

- `main`의 `help` 갈래 바로 뒤에 `version` · `--version` · `-V`. 뒤에 인자가 있으면 `usage()`.
- `USAGE`에 `tars-config version   print the TARS version this image was built from` 한 줄(help 줄 앞).
- `help()` 맨 앞에 `TARS <ver>\n\n`.
- `main.zig` 첫 줄: `"tars-init: starting as PID 1 (TARS {s})\n"`.

## Task 4: `config/check.sh`

`list` 검사 뒤에 `TC_VERSION_KEYS=(t a r s minus c o n f i g spc v e r s i o n ret)`를 쳐 넣는다. 기대 정규식은
`\| TARS <VERSION의 점을 이스케이프>(\+[0-9a-f]{7,}(-dirty)?)?( \||$)`. 뜨면 화면에서 `TARS …`를 뽑아 로그의
`starting as PID 1 (TARS …)` 괄호 안과 같은지 본다.

## Task 5: 검사와 게이트

1. `make init`(컨테이너 `zig build`) — 컴파일, 그리고 `ls -l .git/index`.
2. 컨테이너 `cd init && zig build test` — `version_test`가 한 줄 요약을 찍는다.
3. 호스트에서 `strings init/zig-out/bin/tars-config | rg '^TARS|0\.1\.0'`로 박힌 글자를 본다.
4. CP 체인 하나(`./config/check.sh`) — 새 검사를 먼저 본다.
5. 루트 게이트(22체인, 약 10분). 모든 체인이 첫 로그 줄이 바뀐 init을 싣는다.

## 끝 조건

- `version_test` PASS, 루트 게이트 22체인 PASS.
- CP 체인 로그에 `boot 1: tars-config version printed TARS …, the same as init's first line`.
- 게이트 이미지의 버전이 `0.1.0+<HEAD>-dirty`(편집 중이므로).

## 닫을 때(lead의 몫)

design "닫을 때" 절 그대로.

## BV-M0이 실측한 것

| 항목 | 값 |
|---|---|
| diff | 추적 파일 넷 +98 −1(지운 줄은 `main.zig`의 옛 첫 로그 줄 하나), 새 파일 셋 80줄 |
| `version_test` | 다섯 갈래 PASS — `VERSION is trimmed, and only a clean tagged tree builds a bare version` |
| 박힌 글자 | `tars-config` · `init` 둘 다 `0.1.0+cf1a41a-dirty`(HEAD `cf1a41a`, 편집 중) |
| `.git/index` | `diff --quiet HEAD`는 `--no-optional-locks`여도 매번 mtime을 바꿨다. `status --porcelain`으로 바꾼 뒤 빌드 전후 같다 |
| git 비용 | `status` 0.05~0.15초, 캐시 적중 `zig build` 0.075~0.124초 |
| CP 체인 단독 | PASS. `boot 1: tars-config version printed TARS 0.1.0+cf1a41a-dirty, the same as init's first line` |
| 루트 게이트 1회차 | 20/22. PM-M1(QEMU가 `initrd.cpio`를 못 열었다) · UT-M3(검사 1d(c)가 다른 레인의 임시 파일을 셌다) — 병렬 initrd 경합, lessons "이월 숙제" BV |
| 루트 게이트 2회차 | 22/22 PASS. prebuild 285초 + 레인 328초 |
