# TARS Build Version — Design

Date: 2026-10-20
Status: 끝났다(2026-10-20, BV-M0). plan은 `docs/plans/2026-10-20-tars-build-version-bv-m0.md`. 구현 중 design과 달라진 자리는
결정 2의 dirty 물음 하나다 — `git diff --quiet HEAD`가 컨테이너에서 `.git/index`를 써서 `git status --porcelain`으로 바꿨다(위험 2).
루트 게이트는 1회차 20/22(병렬 initrd 경합, `docs/guides/lessons.md` "이월 숙제" BV), 2회차 22/22. 기억은
`docs/decisions/project_build_version.md`.

HANDOFF "다음 후보"의 TODO에서 시작한다(2026-10-20 사용자가 골랐다).

> `tars-config`에 버전 표시 — 시스템 안에 버전이 없어 받은 사람이 자기 ISO가 몇 버전인지 알 길이 없다.

## 한 줄 요약

저장소 뿌리의 `VERSION` 한 줄이 버전의 원천이고, 빌드가 git으로 "이 트리가 그 태그 그대로인가"를 물어 아니면 커밋을 붙인다.
그 글자가 `tars-config version`과 부팅 로그의 첫 줄에 같이 나온다.

```
$ tars-config version
TARS 0.1.0                  ← HEAD가 v0.1.0이고 추적 파일에 고친 데가 없다(릴리즈 ISO)
TARS 0.1.0+cf1a41a          ← 그 뒤 커밋에서 빌드했다
TARS 0.1.0+cf1a41a-dirty    ← 커밋 안 한 편집이 있는 트리에서 빌드했다

tars-init: starting as PID 1 (TARS 0.1.0+cf1a41a)
```

## 배경

0.1.0(2026-10-11)은 GitHub release의 ISO 파일 이름과 sha256으로만 버전을 말한다(`docs/decisions/project_release.md`
"재사용할 사실"). 받은 사람이 ISO를 USB에 굽거나 `tars-install`로 디스크에 깔고 나면 파일 이름은 사라진다. 그 뒤에는
시스템 안 어디에도 "나는 몇 버전이다"가 없다. 다음 버전을 내기 전에 이 자리를 채운다 — 0.2.0을 받은 사람과 0.1.0을 쓰는
사람이 서로 다른 것을 쓰고 있다고 말할 수 있어야 한다.

`uname -r`은 커널 버전(`6.18.42`)이라 TARS의 버전이 아니다. 우리가 짓는 것은 init · tars-config · terminal · initrd 구성이고,
그 묶음에 번호를 매기는 것은 release 절차가 한다.

## 착수 전에 확인한 것

2026-10-20, HEAD `cf1a41a`.

1. 동사 분기 — `init/src/config_cli.zig`의 `main`이 `std.mem.eql` 사슬로 가른다. `help` · `-h` · `--help`가 이미 한 갈래다.
2. `tars-config`는 `init/build.zig`의 독립 exe(`config_cli_mod`)이고 PID 1(`exe_mod`)과 같은 타깃 · `ReleaseSafe`다.
3. 부팅 로그 첫 줄은 `init/src/main.zig`의 `main` 첫 문장 `tars-init: starting as PID 1`이다. 이 글자를 보는 곳은 셋이고
   모두 부분 일치다 — `power/check.sh`(awk · grep, 두 번째 부팅을 찾는다), `tools/check.sh`(실패 메시지의 인용),
   release 절차 3단계의 smoke. 줄 끝에 글자를 붙여도 셋 다 그대로 맞는다.
4. 컨테이너(`tars-devcontainer`)에 `/usr/bin/git`이 있고, 저장소가 `/workspace`로 붙으니 `.git`도 보인다. root로 돌지만
   `git rev-parse --short HEAD`가 거절 없이 `cf1a41a`를 냈다. `v0.1.0^{commit}`은 `0a6d4bc`다.
5. 컨테이너의 zig는 0.16.0이다. build.zig에서 쓸 셋이 std에 있다 — `b.addOptions()`(Build.zig:766),
   `b.runAllowFail(argv, &code, .ignore)`(1862, 실패를 panic 대신 에러로 준다), `Io.Dir.readFileAlloc(dir, io, sub_path, gpa, limit)`
   (`b.build_root.handle`와 `b.graph.io`로 부른다).
6. 지금 release 절차는 `make iso`(2단계) 뒤에 tag(5단계)를 건다. 태그를 원천으로 삼으면 릴리즈 ISO가 태그 전의 트리를 본다.

## 목표

1. 설치된 시스템에서 `tars-config version`(또는 `--version` · `-V`)이 빌드에 박힌 버전을 한 줄로 찍는다.
2. 부팅 로그(시리얼)의 첫 줄에 같은 글자가 있다 — 화면을 못 보는 실기 진단에서도 버전이 남는다.
3. 릴리즈 ISO는 `TARS <ver>` 그대로이고, 그 밖의 빌드는 스스로 릴리즈가 아니라고 말한다.
4. 게이트가 두 출력이 같은 글자인지 본다.

## 결정

### 결정 1. 원천은 저장소 뿌리의 `VERSION` 한 줄이다

내용은 `0.1.0` 한 줄(끝 줄바꿈 하나)이다. 앞뒤 공백 · 줄바꿈은 build.zig가 벗긴다. 비었거나 64바이트를 넘으면 빌드를 멈춘다
— 버전 없는 이미지를 조용히 굽지 않는다.

사용자가 고른 길이다(2026-10-20, 세 갈래 중). 버린 둘:

- git 태그만(`git describe`): 손으로 올릴 것이 없지만 결정 4의 절차 순서를 강제하고, `.git`이 없는 곳(GitHub의 소스 archive)에서는
  아무것도 모른다.
- `VERSION`만: 가장 단순하지만 릴리즈와 릴리즈 사이의 모든 빌드가 `0.1.0`이라고 말한다. 게이트가 도는 개발 이미지가 릴리즈와
  같은 이름을 쓰면 실기 보고를 받았을 때 어느 트리였는지 가를 수 없다.

### 결정 2. 접미사는 build.zig가 git에 물어 붙인다

build.zig가 저장소 뿌리(`init/`의 부모)에서 git 셋을 부른다. 모두 `-c safe.directory=*`를 붙인다 — 지금 컨테이너에서는 없어도
되지만, 마운트한 사람과 git을 부르는 사람이 다른 환경에서 git이 "dubious ownership"으로 거절하면 접미사가 조용히 사라진다.

| 물음 | 명령 | 쓰는 곳 |
|---|---|---|
| HEAD | `git rev-parse --short=7 HEAD` | 접미사의 커밋 |
| 태그 | `git rev-parse --short=7 v<VERSION>^{commit}` | HEAD와 같은가 |
| 고친 데 | `git status --porcelain --untracked-files=no` | 출력이 있거나 물음이 실패하면 dirty |

글자는 이렇게 정한다.

| HEAD == 태그 | dirty | 결과 |
|---|---|---|
| 예 | 아니오 | `0.1.0` |
| 예 | 예 | `0.1.0+0a6d4bc-dirty` |
| 아니오(태그가 없음 포함) | 아니오 | `0.1.0+cf1a41a` |
| 아니오 | 예 | `0.1.0+cf1a41a-dirty` |

`+` 뒤는 semver의 build metadata 자리다 — 순서 비교에 안 끼는 꼬리표라는 뜻이 맞다. dirty는 추적 파일만 본다(`--untracked-files=no`).
`.gitignore`의 빌드 산출물 · firmware · `terminal/vendor/`가 매번 dirty를 만들면 안 되기 때문이다. 대신 `git add` 안 한 새 소스
파일은 dirty로 안 잡힌다 — 이 저장소의 새 파일은 같은 편집에서 `build.zig` 등록 같은 추적 파일 변경을 데려오므로 실제로는 잡힌다.

### 결정 3. git을 못 쓰면 `VERSION` 그대로다

git이 없거나, `.git`이 없거나, HEAD를 못 읽으면(`runAllowFail`의 에러) 접미사 없이 `VERSION`만 쓴다. `.git` 없이 이 트리를
빌드하는 길은 사실상 GitHub의 태그 소스 archive 하나이고, 그것은 정의상 그 릴리즈다. 태그 물음만 실패하면(태그가 아직 없다)
"HEAD != 태그"로 친다.

### 결정 4. release 절차는 "VERSION 커밋 → tag → make iso" 순서가 된다

결정 2가 HEAD == 태그일 때만 맨 글자를 주므로, 태그가 `make iso`보다 먼저다. `project_release.md`의 일곱 단계를 이렇게 바꾼다.

1. `VERSION`을 새 번호로 고쳐 커밋한다(그 커밋에서 루트 게이트 PASS — 게이트 이미지는 `+<sha>`를 단다).
2. `git tag -a v<ver> <그 커밋>`. push는 6단계 전에.
3. `make iso`.
4. QEMU smoke에 한 줄 더 — `tars-init: starting as PID 1 (TARS <ver>)`가 꼬리표 없이 있는가.
5. 이후(해시 · push · `gh release create` · 내려받아 대조 · 소개 페이지)는 같다.

태그를 걸고 나서 smoke가 실패하면 `git tag -d`로 지우고 고친다 — push 전이라 바깥에 안 나갔다.

### 결정 5. 값은 build option 모듈 `build_info` 하나로 두 exe에 간다

build.zig가 `b.addOptions()`에 `version: []const u8` 하나를 넣고 `exe_mod`(init)과 `config_cli_mod`(tars-config)에
`build_info`라는 이름으로 붙인다. 두 출력이 한 값에서 나오므로 서로 다를 수 없다. tars-install · tars-service에는 안 붙인다
(비목표 2).

build.zig는 `zig build`마다 다시 돈다. 그래서 git도 매번 다시 묻고, 글자가 바뀌었을 때만 options 파일의 해시가 바뀌어 두 exe가
다시 컴파일된다. `make iso`가 낡은 버전을 실을 길은 없다 — initrd 조립은 매번 `zig-out/bin/`을 새로 복사한다.

### 결정 6. 글자를 짓는 함수는 `init/src/version.zig`의 순수 함수다

`fn format(buf, base, head, tag_matches, dirty) []const u8` 하나. build.zig가 `@import("src/version.zig")`로 부르고, 호스트 검사
`version_test`가 결정 2의 표 네 칸과 결정 1의 공백 벗기기를 본다. git을 부르는 부분은 build.zig에만 있다 — `clock.zig`가
시스템 콜을 함수 몇 개 아래에만 둔 것과 같은 선이다.

### 결정 7. 명령은 `version` · `--version` · `-V`이고 stdout에 `TARS <ver>` 한 줄이다

`help` 갈래와 같은 모양으로 `main`에 넣는다. 뒤에 인자가 있으면 `usage()`. 종료 코드 0. `USAGE`에 한 줄을 더하고, `help`의 첫 줄에도
`TARS <ver>`를 찍는다 — 도움말을 연 사람이 버전을 따로 묻지 않게.

머리 `TARS `를 붙이는 이유: 출력 한 줄만 붙여 보고할 때 무엇의 버전인지가 그 줄 안에 있어야 한다. 스크립트가 숫자만 원하면
`cut -d' ' -f2`.

### 결정 8. 부팅 로그는 첫 줄 끝에 붙인다

`tars-init: starting as PID 1 (TARS <ver>)`. 줄을 하나 더 만들지 않는 이유는 확인 3 — 이 줄을 보는 셋이 모두 부분 일치라
안 깨지고, 시리얼 로그의 맨 위에서 한 번에 읽힌다.

### 결정 9. 게이트는 CP 체인의 부팅 1에서 본다

새 체인을 만들지 않는다. `config/check.sh`의 부팅 1이 이미 `tars-config`를 쳐 넣는 자리다(`set` · `get` · `check` · `list`).
거기에 `tars-config version`을 한 번 쳐 넣고 두 가지를 본다.

1. 화면 줄에 `| TARS <VERSION>(\+[0-9a-f]{7,}(-dirty)?)?`가 뜬다 — `<VERSION>`은 check.sh가 같은 `VERSION` 파일에서 읽는다.
2. 화면의 그 글자와 시리얼 로그 `starting as PID 1 (TARS …)`의 괄호 안 글자가 같다.

check.sh는 결정 2의 규칙을 셸로 다시 짓지 않는다. 빌드와 게이트 사이에 트리가 바뀌면(편집 중 게이트) 다시 지은 기대값이
틀리고, 규칙의 정확성은 `version_test`가 이미 본다. 게이트가 볼 것은 배관 — 원천이 두 출력에 같은 값으로 닿았는가 — 이다.

## Milestone

BV-M0 하나. 할 일:

1. `VERSION`(`0.1.0`).
2. `init/src/version.zig` · `version_test.zig`, `init/build.zig`의 options 모듈과 검사 등록.
3. `config_cli.zig`의 동사 · `USAGE` · `help`, `main.zig`의 첫 줄.
4. `config/check.sh` 부팅 1의 검사.
5. 루트 게이트(모든 체인이 init을 새로 실으므로 체인 하나로 끝내지 않는다).
6. `project_release.md`의 절차(결정 4)와 "시스템 안에는 버전이 없다" 줄.

## 위험

1. 게이트 이미지는 언제나 `-dirty`를 단다 — 편집 중에 게이트를 돌리기 때문이다. 정상이고, 결정 9의 정규식이 그것을 받는다.
2. git의 읽기 명령도 index를 새로 고치느라 `.git/index`를 쓸 수 있다. 컨테이너가 root로 쓰면 호스트에서 그 파일이 흔들린다.
   BV-M0 실측: 컨테이너의 git 2.47.3은 `git diff --quiet HEAD`마다 index를 다시 썼고 `--no-optional-locks`로도 안 멈췄다
   (주인은 OrbStack이 `dp`로 보여 바뀌지 않았다). `git --no-optional-locks status --porcelain`은 두 번 돌려도 안 썼다 —
   그래서 dirty 물음이 status다.
3. `--short=7`이 저장소가 커져 모호해지면 git이 더 길게 준다. 결정 9의 정규식은 `{7,}`로 둔다.

## 비목표

1. `/etc/os-release`. 리눅스의 표준 자리이고 `fastfetch` 같은 도구가 읽지만, 지금 그것을 읽는 우리 코드가 없다. 필요해지면
   initrd 조립이 같은 글자로 적는다 — `build_info`가 아니라 make_initrd.sh 쪽의 일이다.
2. tars-install · tars-service의 `--version`. 같은 initrd에 실리므로 tars-config 하나로 이미지를 말할 수 있다.
3. 상태 줄 · 화면 어딘가의 버전 표시.
4. 버전 번호를 언제 올리는지의 정책(semver 해석). 지금은 release 절차가 고른다.

## 닫을 때(lead의 몫)

- 이 design의 `Status:`, `docs/guides/completed.md`의 한 행, 소개 페이지 `data.js`(기준일 · 타임라인 · 기능 목록).
- `docs/decisions/project_release.md`(결정 4) · `MEMORY.md`의 그 줄, `HANDOFF.md`의 TODO 지우기.

## 관련

- `docs/decisions/project_release.md` — 0.1.0과 배포 절차.
- `docs/specs/2026-10-07-tars-config-reload-design.md` · TC 서브프로젝트 — `tars-config`의 동사들.
