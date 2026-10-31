---
name: project_github_actions
description: "GitHub Actions(GH-M0, 2026-10-30). checks.yml 하나에 host(quick_check.sh: shellcheck 0.11.0 · Zig fmt/ast-check/shared 검사/init 크로스 빌드)와 container(ubuntu-24.04-arm에서 Dockerfile 그대로 굽고 sanity · 게이트 prebuild의 두 줄 = init · terminal zig build test, GH-M1) — 게이트는 안 돌린다, 도구는 tarball + sha256, 주석을 '# shellcheck'로 시작하면 지시자, push는 main만, deps.files.ghostty.org가 끊겨 재시도 fetch step(zig build --help), step 사이 전역 Zig 캐시 공유, host 3분 · container 7분 30초(FR-M0 뒤 6분 51초). VS-M0(2026-10-31): 받는 자리 여섯에 sha256 대조, stb는 .tmp 경유"
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
- shellcheck warning 넷을 지웠다(지시자 둘 · `|| exit 1` · `for _`). note 46은 판정하지 않고 수만 찍는다(SN-M0이 0으로 만들고 판정에 넣었다, 아래).

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
- unifont(`ftp.gnu.org`)를 runner에서 "100초 남짓"으로 읽은 것은 틀렸다 — `Downloading` 줄에서 다음 `fetching` 줄까지의 간격에 cold
  build runner 컴파일이 섞였다. 다운로드 끝은 로그에 안 찍힌다. FR-M0이 폰트를 저장소에 넣어 빠진 몫은 43초였다(3분 28초 → 2분 45초).
  step 사이의 간격으로 한 몫을 재지 않는다 — 그 사이에 찍히지 않는 일이 있다.
- `gh workflow run`이 HTTP 500을 낼 때가 있다(GitHub 쪽). 20초 뒤 다시 부르면 된다.
- `quick_check.sh`의 init 빌드는 `--prefix out/quick/init`다. `init/zig-out`을 덮으면 initrd가 호스트 Mac의 zig로 만든 바이너리를
  싣는다(같은 버전이면 같겠지만 확인하지 않았다).

## SN-M0(2026-10-31) — shellcheck note 46 → 0, note도 판정

GH-M1의 다음 후보 가운데 사용자가 골랐다. design `docs/specs/2026-10-31-tars-shellcheck-notes-design.md`, plan
`docs/plans/2026-10-31-tars-shellcheck-notes-sn-m0.md`. `quick_check.sh`의 판정이 `-S warning` → `-S style`이고 수 세는 줄은 없다.
46건 가운데 18은 출력이 같은 정석 꼴로 고쳤고(따옴표 · `printf '%s\n'` · `\\)` · `read -r` · `[:upper:]`), 28은 그 줄 위에 지시자와
이유를 달았다(SC2329 19 · SC2012 5 · SC2016 3 · SC2059 1).

- 함정: shellcheck 0.11은 파일의 마지막 최상위 명령이 `exit`이면 trap 핸들러와 이름으로 넘긴 콜백을 SC2329("never invoked")로
  찍는다. 같은 `trap cleanup EXIT`이라도 끝이 `exit`가 아닌 체인은 조용하다. 최소 예제로 재현했다. 전역으로 끄지 않고 함수
  위에 `# shellcheck disable=SC2329 # trap cleanup EXIT이 부른다`(콜백은 `boot_once가 이름으로 부른다`)를 단다 — 진짜 죽은 함수는
  계속 보이게.
- 지시자 이유는 부르는 자리 · 이름이 오는 곳을 적는다. 적다가 두 개가 틀린 것을 찾았다(wav 이름의 출처 · 프레임을 짓는 함수).

## VS-M0(2026-10-31) — 받는 자리 여섯에 sha256

GH-M1의 다음 후보 가운데 사용자가 골랐다. design `docs/specs/2026-10-31-tars-vendor-sha256-design.md`, plan
`docs/plans/2026-10-31-tars-vendor-sha256-vs-m0.md`. HANDOFF가 적은 셋(ghostty tarball · stb 둘)에 커널 tarball · limine tarball ·
Dockerfile의 Zig aarch64 tarball을 더해 여섯 — 전부 `*_SHA256` 변수 하나(출처 주석)와 `echo "$SHA  파일" | sha256sum -c -` 한 줄.
`checks.yml`의 꼴 그대로다. 받는 자리는 `rg -n 'curl -sSL -o'`로 찾는다.

- 함정: 받는 파일이 곧 "이미 있으면 안 받는다"의 검사 대상이면(stb의 `-o "$DEST"`) `FAILED` 뒤 나쁜 파일이 남아 다음 실행이 조용히
  쓴다. `.tmp`로 받아 대조한 뒤 `mv` — mutation이 잡았다. tarball은 존재 검사가 푼 디렉터리에 걸려 그럴 일이 없다.
- 대조는 받는 순간 한 번이다. 로컬 게이트는 트리가 있어 안 타고, CI `container`는 깨끗한 runner라 push마다 탄다 — 로그에 `OK` 넷.
- 컨테이너 안에 `rg`는 없다(runner와 같다). 컨테이너에서 돌릴 한 줄은 `grep`으로.
- 버전을 올릴 때 해시도 함께: Zig는 Dockerfile `ZIG_VERSION` · Dockerfile `ARG ZIG_SHA256`(aarch64) · `checks.yml` `ZIG_SHA256`(x86_64)
  셋([[project_zig_upgrade]]). ghostty는 `GHOSTTY_SHA`와 `GHOSTTY_SHA256` 둘 — GitHub archive가 바이트를 바꾸면(2023-01에 한 번)
  `FAILED`이고 재실행으로 안 풀린다. 새 tarball을 풀어 지난 트리와 `diff -rq` 0줄을 본 뒤 고친다.
- 숫자: 루트 게이트 22/22, 10분 1초(prebuild 301 + lanes 300초). CI host 2분 39초 · container 6분 54초.

## GI-M0(2026-10-31) — 이미지를 ghcr.io에서 받는다

GH-M1의 마지막 후보, 사용자가 골랐다. design `docs/specs/2026-10-31-tars-ghcr-image-design.md`, plan
`docs/plans/2026-10-31-tars-ghcr-image-gi-m0.md`. `ghcr.io/soomtong/tars-devcontainer:<Dockerfile sha256 앞 12자>` — 받는 ·
굽는 · 올리는 판단은 `devcontainer/image.sh` 하나(`tag|pull|build|push`), Makefile `container`와 CI `container` job이 `pull || build`,
CI는 `main` push에서 구웠을 때만 `docker login` 뒤 `push`. 로컬 태그 `tars-devcontainer`에 붙이므로 `docker run` 줄은 안 바뀌었다.

- 목표는 시간이 아니라 동일성이다. `docker build`는 runner에서 46~50초뿐이고, 얻은 것은 게이트 · CI · 새 저장소가 같은 digest를
  쓴다는 것(apt 층 824MB가 "구운 날"에 따라 달라지던 것이 멈췄다). CI `container` 8분 2초(built) → 6분 24초(pulled), 이미지 몫 78 → 25초.
- 태그가 커밋이 아니라 Dockerfile 해시인 이유: Dockerfile은 드물게 바뀌고, 태그 없음 = "이 Dockerfile로는 아직 안 구웠다"라 굽는
  조건이 따로 없다. 갱신(apt 보안 갱신 포함)은 Dockerfile 머리의 "이미지 세대" 날짜를 바꾸는 것 — 한 줄이라도 바뀌면 새 태그.
- 로컬은 Dockerfile을 자동으로 따라가지 않는다(`git pull` 한 번에 1.5GB가 사람 모르게 시작되지 않게). `docker rmi tars-devcontainer
  && make container`. Dockerfile을 바꾸는 commit 메시지에 새 태그를 적는다.
- 틀렸던 가정: "첫 push가 만드는 패키지는 비공개라 UI에서 한 번 Public으로". 공개 저장소에 `org.opencontainers.image.source`
  LABEL로 연결된 패키지를 그 저장소의 Actions가 올리면 처음부터 공개다 — 사람이 할 일이 없었다.
- 함정: ghcr은 없는 태그 · 비공개 · 권한 없음을 다 `denied`로 답한다 — `image> pull failed` 메시지가 세 경우를 다 말한다. 받은 이미지의
  ID는 구운 쪽과 같다(config digest) — 동일성 비교는 `docker image inspect --format '{{.Id}}'`로 된다. 같은 태그를 덮어쓰는 것을
  막는 장치는 없다(반쪽 장애에서 `pull` 실패 → `build` → `push`면 같은 Dockerfile의 다른 빌드가 덮는다 — 패키지 버전 페이지에 두
  digest가 남는다). 옛 태그는 Dockerfile을 고칠 때마다 1.5GB씩 쌓인다(공개라 무료, 지우는 것은 손으로).
- 숫자: 로컬 pull 42초, ID `0e214546893d` = CI. 루트 게이트 22/22, 10분 3초(prebuild 299 + lanes 301초), verify 8104줄 통과.

## 남긴 것(다음 후보)

없다 — GH-M1이 적은 넷(컨테이너 `zig build test` · shellcheck note · vendor sha256 · ghcr.io 이미지)을 M1 · SN · VS · GI가 다 닫았다.

## 관련

[[project_zig_upgrade]] — Zig를 올릴 때 Dockerfile `ZIG_VERSION`과 `checks.yml` `ZIG_SHA256`을 함께. [[project_host_checks]] ·
[[project_lessons_split]] — 같은 점검의 (3) · (4). [[feedback_push_policy]] — push가 게이트인 설계가 이 위에 선다.
