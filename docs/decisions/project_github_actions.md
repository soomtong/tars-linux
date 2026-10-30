---
name: project_github_actions
description: "GitHub Actions(GH-M0, 2026-10-30). checks.yml 하나에 host(quick_check.sh: shellcheck 0.11.0 · Zig fmt/ast-check/shared 검사/init 크로스 빌드)와 container(ubuntu-24.04-arm에서 Dockerfile 그대로 굽고 sanity · 게이트 prebuild의 두 줄 = init · terminal zig build test, GH-M1) — 게이트는 안 돌린다, 도구는 tarball + sha256, 주석을 '# shellcheck'로 시작하면 지시자, push는 main만, deps.files.ghostty.org가 끊겨 재시도 fetch step(zig build --help), step 사이 전역 Zig 캐시 공유, host 3분 · container 7분 30초"
metadata:
  type: project
---

# GitHub Actions (GH)

2026-10-24 프로젝트 점검이 남긴 (5)를 사용자가 골랐다(2026-10-30). design은
`docs/specs/2026-10-30-tars-github-actions-design.md`, plan은 `docs/plans/2026-10-30-tars-github-actions-gh-m0.md`.
BF design(2026-08-01)의 비목표 "GitHub Actions 재도입은 … 별도로 판단"이 이것으로 닫혔다.

## 무엇을 세웠나

- `quick_check.sh`(루트) — 게이트가 아닌 1분짜리 검사. shellcheck(`git ls-files '*.sh'` + 게스트 스크립트 둘, `-x -P SCRIPTDIR
  -S warning`) · `zig fmt --check` · `ast-check` · `shared/screen_args_test.zig` · init 크로스 빌드(`out/quick/`). `make quick`과
  CI가 같은 파일을 부른다. lessons "범용 명령"의 손으로 치던 Zig 세 줄이 여기로 왔다.
- `.github/workflows/checks.yml` — job 둘 병렬. `host`(ubuntu-24.04)는 shellcheck 0.11.0 · Zig 0.17.0을 release tarball로 받아
  sha256을 대조하고 `quick_check.sh`. `container`(ubuntu-24.04-arm)는 `devcontainer/Dockerfile`을 0줄 고치지 않고 굽고 안에서
  `devcontainer/sanity/check.sh`(BF-M0) · `cd init && zig build`. 트리거는 `push`(`main`만) · `pull_request` · `workflow_dispatch`.
- README 배지 한 줄. 초록은 "서식 · 문법 · 셸 규칙 · 컨테이너가 구워진다"이지 부팅이 아니다 — 게이트는 로컬 `make gate`.
- shellcheck warning 넷을 지웠다(지시자 둘 · `|| exit 1` · `for _`). note 46은 판정하지 않고 수만 찍는다.

commit은 design `e7343cc` · `2eb20a9`, plan `5ce369f`, Task 1 `e7d7faf`, Task 2 `2259b14`, Task 4 · 닫기.

## GH-M1(2026-10-30) — 컨테이너 안 `zig build test`

M0의 M1 후보 가운데 사용자가 골랐다. plan `docs/plans/2026-10-30-tars-github-actions-gh-m1.md`, design의 "GH-M1" 절(결정 8~13).

- `container`가 `check.sh` `prebuild()`의 두 줄 — `cd init && zig build && zig build test` · `cd terminal && ./prepare.sh && zig build
  test` — 을 글자 그대로 돌린다(step 이름 `init build and test` · `terminal prepare and test`). init · terminal 검사 열일곱씩이 push마다
  arm64 Linux에서 돈다. 전에는 게이트를 돌 때만 돌았다.
- 그 사이에 `terminal fetch (retry)` — `vendor_libghostty_vt.sh` 뒤 `zig build --help`를 세 번까지. `deps.files.ghostty.org`가
  runner에서 연결을 끊었다(첫 네 회차 중 둘, zlib에서 `ConnectionResetByPeer`). 받은 것은 `terminal/zig-pkg`에 남아 다음 step이 안
  받는다.
- 세 step의 `docker run`에 `-v /tmp/zig-global:/root/.cache/zig`. `--rm`이 버리던 전역 캐시를 step 사이에 잇는다.
- 숫자: `container` 8분 10초(검사만) → 10분 51초(재시도 step) → 7분 30초(캐시 공유). 로컬 비교 288 → 180초. mutation 둘
  (`version_test` · `layout_test`의 기대값)이 각자의 step에서 `FAIL:` 줄로 잡혔다.

## 결정과 그 이유

- 게이트를 Actions에서 돌리지 않는다. 커널 빌드 · firmware 662MB · TCG 부팅 22번을 4 vCPU 공용 runner에서 — 재지 않았고
  타이밍 판정(GF)이 흔들릴 것이다. CI의 자리는 게이트가 안 보던 검사(Zig fmt · shellcheck)와 "Dockerfile이 깨끗한 기계에서
  구워지는가"다.
- 도구는 runner에 있는 것이 아니라 저장소가 정한 버전을 tarball로 받는다. runner의 shellcheck는 0.9.0이고 호스트는 0.11.0 —
  SC2329(안 부르는 함수)는 0.10부터라 버전이 다르면 같은 파일에서 다른 답이 나온다. 제3자 action은 안 쓴다(무엇이 도는지
  파일에서 읽히게). Zig 버전은 Dockerfile의 `ENV ZIG_VERSION` 한 줄이 정본이고 `checks.yml`은 해시만 가진다.
- arm64 runner. Dockerfile이 `zig-aarch64`를 받으므로(ZM-M3) amd64에서는 안의 zig가 안 돈다. public 저장소라 `ubuntu-24.04-arm`이
  무료다.
- `push`는 `main`만(사용자 결정). 임시 브랜치는 `gh workflow run checks.yml --ref <브랜치>`로 돌린다 — mutation 둘을 그렇게 봤다.

## 숫자

첫 회차(run 41065218866): host 3분 9초 · container 3분 13초. `docker build`는 캐시 없이 46초(design이 "몇 분"이라 걱정한 것은
틀렸다 — runner의 네트워크가 빠르다). 시간의 대부분은 Zig 빌드다 — host의 init 크로스 빌드 약 2분 20초, 컨테이너 안 aarch64
빌드 2분 17초(둘 다 cold cache). 층 캐시는 필요 없다.

## 함정

- 주석 줄을 `# shellcheck`로 시작하면 shellcheck가 지시자로 읽고 SC1073 · SC1072(error)를 낸다. `quick_check.sh` 자신의 머리
  주석이 첫 판에 그렇게 빨갰다 — 도구 이름으로 문장을 시작하지 않는다.
- SC2034(안 쓰는 변수)는 한 변수에 한 번만 찍힌다. `wifi/ap.sh`의 `for i`는 넷이었는데 둘을 고치고 나서야 다음 자리가 보였다.
  `rg -n '\bi\b'`로 먼저 센다.
- `zig build test`(init의 호스트 검사)는 macOS 호스트에서 5분 넘게 안 끝난다(ZU 기억의 "init 검사는 멈춘다"와 같은 것). host
  job에 넣지 않았다 — 컨테이너 안이면 되고, GH-M1이 `container`에 넣었다.
- ghostty의 lazy 의존성을 미리 받는 명령은 `zig build --help`다. `--fetch`(needed)는 lazy를 안 받고(3개), `--fetch=all`은 ghostty가
  쓸 수 있는 것 전부(37개 534MB)다. `--help`는 build.zig를 configure까지 돌려 실제로 쓰는 8개(32MB)만 받는다.
- unifont(`ftp.gnu.org`)는 runner에서 매번 100초 남짓 걸린다(실패는 아니다). 지금 `container`의 가장 큰 바깥 몫이다.
- `gh workflow run`이 HTTP 500을 낼 때가 있다(GitHub 쪽). 20초 뒤 다시 부르면 된다.
- `quick_check.sh`의 init 빌드는 `--prefix out/quick/init`다. `init/zig-out`을 덮으면 initrd가 호스트 Mac의 zig로 만든 바이너리를
  싣는다(같은 버전이면 같겠지만 확인하지 않았다).

## 남긴 것(다음 후보)

shellcheck note 46(그중 SC2329 19, `config/check.sh`에 10)의 정리 · vendor 스크립트의 sha256(ghostty tarball · stb 둘은 대조가
없다, 게이트 입력이라 게이트가 따라온다) · unifont를 더 빠른 미러에서 · 구운 이미지를 ghcr.io에 올려 다음 사람이 굽지 않게 하는 것(README "준비"가 바뀌는 새 판단).

## 관련

[[project_zig_upgrade]] — Zig를 올릴 때 Dockerfile `ZIG_VERSION`과 `checks.yml` `ZIG_SHA256`을 함께. [[project_host_checks]] ·
[[project_lessons_split]] — 같은 점검의 (3) · (4). [[feedback_push_policy]] — push가 게이트인 설계가 이 위에 선다.
