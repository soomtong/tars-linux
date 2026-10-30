# GH-M0 — quick_check.sh와 checks.yml

Date: 2026-10-30
Design: `docs/specs/2026-10-30-tars-github-actions-design.md`
Status: 끝났다(2026-10-30)

## 착수 전에 확정한 것

design의 확인 1~9에 더해, plan을 쓰며 읽은 것.

1. shellcheck warning 네 자리의 모양과 처방(design 결정 4).
   - `audio/probe.sh:98` SC2010(`ls /sys/bus/pci/drivers | grep -E …`). 이 스크립트는 설정 디스크의 `services.d/probe`로 게스트에
     들어가 돈다(`#!/usr/bin/bash`). `/sys`의 드라이버 이름은 커널이 정한 것이라 공백 · 특수문자가 없고, `ls`의 정렬 순서를 체인이
     `say` 줄 그대로 읽는다 — `find`로 바꾸면 순서가 바뀔 수 있다. 지시자로 덮고 이유를 적는다.
   - `kernel/tq-probe.sh:27` SC3045(`#!/bin/sh`에서 `read -n`). 바로 위 주석이 이미 "이 게스트의 `/bin/sh`가 bash라서 되는 것"이라
     적었다(`make_initrd.sh`가 그렇게 건다). 지시자로 덮는다 — 고치면 의도(`sh`로 쓴 게스트 스크립트)가 바뀐다.
   - `probe/run.sh:21` SC2164(`cd /workspace/terminal`에 실패 처리 없음). 호스트의 프로브 하네스이고 `set -e`가 없다. `|| exit 1`을
     붙인다 — `cd`가 실패하면 그 아래 상대 경로 전부가 엉뚱한 곳을 가리키므로 멈추는 것이 맞다.
   - `wifi/ap.sh:89` SC2034(안 쓰는 `i`). 설정 디스크의 `services.d/ap`로 게스트에 들어가는 `#!/bin/sh`. 세는 변수를 안 읽는 `for`가
     둘(78 · 89행)이다 — 둘 다 `_`로 바꾼다. 동작은 같다.
2. 넷 가운데 게이트에 닿는 것은 `wifi/ap.sh`(wifi 체인) · `audio/probe.sh`(audio 체인) · `kernel/tq-probe.sh`(initrd → terminal
   체인)이다. 바뀌는 것이 주석 둘과 변수 이름이라 Task 1 뒤에는 wifi 체인만 돌리고, 나머지는 닫을 때의 루트 게이트가 본다.
3. shellcheck 0.11.0은 지시자 뒤의 `# 이유`를 받는다(`# shellcheck disable=SC2010 # …`를 호스트에서 돌려 exit 0).
4. `actions/checkout`의 최신은 v7(v7.0.1, 2026-07-20). 태그로 핀한다(`sha_pinning_required`는 꺼져 있다).
5. `.zig` 파일은 `init/src` · `terminal/src` · `shared` 바로 아래에만 있다(비재귀 80 = 재귀 80). `find`로 세어도 같다.
6. runner에는 `fd` · `rg` · `sd`가 없다. `quick_check.sh`는 `git` · `sed` · `find` · `xargs` · `grep`과 도구 둘만 쓴다.
7. Zig 0.17.0 x86_64-linux tarball sha256 `1cbe9df9f27e6b78d14ccbca43b6703a404ef79ef1c463de901d7f088d4e2026`, shellcheck
   `shellcheck-v0.11.0.linux.x86_64.tar.xz` sha256 `8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198`.
8. 사용자 결정(2026-10-30): `push` 트리거는 `main`만, README 배지는 넣는다. mutation은 `gh workflow run checks.yml --ref <브랜치>`.

## Task 1 — `quick_check.sh` · Makefile `quick` · warning 넷

새 파일 `quick_check.sh`(저장소 루트, 실행 권한).

```bash
#!/usr/bin/env bash
# quick_check.sh — 게이트가 아닌, 1분 안에 끝나는 검사(GH-M0 design 결정 3).
#
# 사람은 `make quick`으로, CI는 .github/workflows/checks.yml의 host job이 같은 파일을
# 돌린다. 명령을 두 벌 두지 않으려고 스크립트 하나에 모았다 — lessons "범용 명령"에
# 손으로 치던 Zig 세 줄이 여기로 왔다.
#
# 단계는 다섯이다. 셸 스크립트(shellcheck) · Zig 서식(fmt --check) · Zig 문법(ast-check) ·
# shared/의 순수 검사(zig run) · init의 크로스 빌드(zig build). 빌드 산출물은 out/quick/
# 아래에만 두어 init/zig-out(initrd가 싣는 원본)을 건드리지 않는다.
#
# 도구는 PATH의 shellcheck · zig다. 버전이 아래와 다르면 한 줄 찍고 계속 돈다 — 실패가
# 아니다. 호스트 Mac은 Homebrew가 올리는 대로 따라가고, CI와 답이 다르면 그 줄이 이유다.
# shellcheck 버전은 여기가 정본이고, Zig 버전은 devcontainer/Dockerfile의 ENV ZIG_VERSION이
# 정본이다(ZU가 올릴 때 고칠 자리 하나).
set -uo pipefail
cd "$(dirname "$0")" || exit 1

SHELLCHECK_VERSION=0.11.0
ZIG_VERSION="$(sed -n 's/^ENV ZIG_VERSION=\([0-9.]*\).*/\1/p' devcontainer/Dockerfile)"

failed=()
note() { printf 'quick_check: %s\n' "$*"; }

for tool in shellcheck zig; do
  command -v "$tool" >/dev/null 2>&1 || { note "$tool is not on PATH"; exit 2; }
done
have_sc="$(shellcheck --version | sed -n 's/^version: //p')"
have_zig="$(zig version)"
[ "$have_sc" = "$SHELLCHECK_VERSION" ] || note "shellcheck is $have_sc, this file expects $SHELLCHECK_VERSION"
[ "$have_zig" = "$ZIG_VERSION" ] || note "zig is $have_zig, Dockerfile says $ZIG_VERSION"

# 1. shellcheck. 대상은 추적 중인 *.sh 전부와, 확장자 없이 게스트에 들어가는 둘이다.
#    추적 파일 기준이라 terminal/vendor · ghostty-src · out/은 안 걸린다. -x -P SCRIPTDIR은
#    `source ../gate_lib.sh`를 스크립트 위치 기준으로 따라가게 한다(없으면 SC1091 28줄).
#    판정은 warning 이상(-S warning). note는 판정하지 않고 수만 찍는다 — 기준선 46(2026-10-30).
mapfile -t sh_files < <(git ls-files '*.sh')
sh_files+=(kernel/wifi/tars-wifi kernel/dictation/tars-dictate)
note "shellcheck ${#sh_files[@]} files"
if shellcheck -x -P SCRIPTDIR -S warning "${sh_files[@]}"; then
  :
else
  failed+=(shellcheck)
fi
notes="$(shellcheck -x -P SCRIPTDIR -S style -f gcc "${sh_files[@]}" 2>/dev/null | grep -c ': note:' || true)"
note "shellcheck notes: $notes"

# 2. Zig 서식. 디렉터리는 재귀다.
zig fmt --check init/build.zig terminal/build.zig init/src terminal/src shared || failed+=(zig-fmt)

# 3. Zig 문법. 컨테이너 컴파일러가 거부하지 않는 문법이 다시 들어오는 것을 여기서 본다(ZU).
ast_failed=0
while IFS= read -r f; do
  zig ast-check "$f" || { echo "ast-check FAIL $f"; ast_failed=1; }
done < <(find init/src terminal/src shared -name '*.zig' | sort)
[ "$ast_failed" = 0 ] || failed+=(zig-ast-check)

# 4. shared/의 순수 검사. libc · 시스템 콜이 없어 어느 호스트에서나 돈다(SA-M1).
zig run shared/screen_args_test.zig || failed+=(shared-test)

# 5. init의 크로스 빌드. build.zig가 target을 x86_64-linux로 고정하고 libc를 안 쓰므로
#    호스트가 무엇이든 같은 산출물 넷이 나온다. `zig build test`(호스트 검사)는 Linux
#    컨테이너의 몫이라 여기 없다(design 확인 5).
mkdir -p out/quick
(cd init && zig build --prefix ../out/quick/init --cache-dir ../out/quick/init-cache) || failed+=(init-build)

if [ "${#failed[@]}" = 0 ]; then
  note PASS
  exit 0
fi
note "FAIL: ${failed[*]}"
exit 1
```

Makefile — `.PHONY`에 `quick`, help에 "그 밖" 절 앞, 타깃은 `gate` 앞.

```make
	@echo "  make quick"
	@echo "      quick_check.sh — 게이트가 아닌 1분짜리 검사. 컨테이너 없이 호스트의 shellcheck · zig로"
	@echo "      shellcheck(51파일) · zig fmt --check · ast-check · shared 검사 · init 크로스 빌드. CI(.github/"
	@echo "      workflows/checks.yml)가 같은 파일을 돌린다. 산출물은 out/quick/ 아래"
```

```make
# 게이트가 아닌 1분짜리 검사. 컨테이너 없이 호스트의 shellcheck · zig로 돈다 — 부르는
# 쪽이 CI(.github/workflows/checks.yml의 host job)와 같다(GH-M0).
quick:
	@./quick_check.sh
```

warning 넷(확정 1). `audio/probe.sh` 98행 위에 지시자 한 줄, `kernel/tq-probe.sh` 27행 위에 지시자 한 줄, `probe/run.sh` 21행
`|| exit 1`, `wifi/ap.sh` 78 · 89행 `for i` → `for _`.

확인: `make quick`이 `quick_check: PASS`, `shellcheck notes: 46`. `git status`에 `out/`만(gitignore). `make check CHAIN=wifi`.
commit 하나.

## Task 2 — `.github/workflows/checks.yml` · README 배지

```yaml
# TARS의 CI — 게이트가 아니다. 초록은 "소스가 서식 · 문법 · 셸 규칙을 지키고 컨테이너가
# 구워진다"이지 "부팅한다"가 아니다. 부팅 판정은 로컬 게이트(make gate)다.
# design: docs/specs/2026-10-30-tars-github-actions-design.md
#
# job 둘은 병렬이다.
#   host       amd64 runner. shellcheck · Zig를 release tarball로 받아(sha256 대조) quick_check.sh를
#              돌린다 — 사람이 `make quick`으로 돌리는 그 파일이다.
#   container  arm64 runner. devcontainer/Dockerfile이 zig-aarch64를 받으므로(ZM-M3) amd64에서는
#              못 쓴다. 그대로 굽고, 안에서 BF-M0 sanity 부팅과 init의 zig build를 돌린다.
#
# 제3자 action은 쓰지 않는다 — 무엇이 도는지 이 파일에서 읽히게. actions/checkout만 태그로 핀한다.
# Zig 버전은 Dockerfile의 ENV ZIG_VERSION이 정본이고 여기서는 해시만 적는다(ZU가 올릴 때 함께).
name: checks

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

concurrency:
  group: checks-${{ github.ref }}
  cancel-in-progress: true

jobs:
  host:
    runs-on: ubuntu-24.04
    env:
      SHELLCHECK_VERSION: 0.11.0
      SHELLCHECK_SHA256: 8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198
      ZIG_SHA256: 1cbe9df9f27e6b78d14ccbca43b6703a404ef79ef1c463de901d7f088d4e2026
    steps:
      - uses: actions/checkout@v7

      # runner에 있는 shellcheck는 0.9.0이라 호스트(0.11.0)와 답이 다르다(SC2329는 0.10부터).
      - name: shellcheck
        run: |
          curl -sSL -o /tmp/shellcheck.tar.xz \
            "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.xz"
          echo "${SHELLCHECK_SHA256}  /tmp/shellcheck.tar.xz" | sha256sum -c -
          mkdir -p /opt/shellcheck
          tar -xJf /tmp/shellcheck.tar.xz -C /opt/shellcheck --strip-components=1
          echo /opt/shellcheck >> "$GITHUB_PATH"

      - name: zig
        run: |
          v="$(sed -n 's/^ENV ZIG_VERSION=\([0-9.]*\).*/\1/p' devcontainer/Dockerfile)"
          curl -sSL -o /tmp/zig.tar.xz "https://ziglang.org/download/${v}/zig-x86_64-linux-${v}.tar.xz"
          echo "${ZIG_SHA256}  /tmp/zig.tar.xz" | sha256sum -c -
          mkdir -p /opt/zig
          tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1
          echo /opt/zig >> "$GITHUB_PATH"

      - run: ./quick_check.sh

  container:
    runs-on: ubuntu-24.04-arm
    steps:
      - uses: actions/checkout@v7

      # Makefile의 container 타깃과 같은 줄. 층 캐시는 없다 — 먼저 캐시 없는 시간을 잰다(design 결정 5).
      - run: docker build -t tars-devcontainer devcontainer/

      # BF-M0의 sanity. 크로스 gcc → 32비트 ELF → qemu TCG 5초 → 시리얼 표식.
      - run: docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer devcontainer/sanity/check.sh

      # 이미지 안의 zig(aarch64)가 게스트 바이너리 넷을 만든다 — host job의 5단계와 짝.
      - run: docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c 'cd init && zig build'
```

README — 제목 바로 아래.

```markdown
[![checks](https://github.com/soomtong/tars-linux/actions/workflows/checks.yml/badge.svg)](https://github.com/soomtong/tars-linux/actions/workflows/checks.yml)
정적 검사와 컨테이너 빌드다(`make quick`과 같은 것) — 부팅 판정인 게이트는 로컬 `make gate`.
```

확인: commit → push → `gh run watch`. 두 job 초록, 각 시간과 로그의 버전 줄(`shellcheck notes: 46` · `zig is …` 없음)을 아래
결과 절에 적는다. 빨강이면 우리 코드(quick_check 단계 이름)인지 바깥(curl · apt)인지를 로그로 가른다.

## Task 3 — mutation 둘

임시 브랜치 `gh-m0-mut-a`: `probe/run.sh`의 `|| exit 1`을 뺀다(Task 1이 고친 것을 되돌린다 → warning 하나). push →
`gh workflow run checks.yml --ref gh-m0-mut-a` → `host` 빨강(`FAIL: shellcheck`). 브랜치 삭제(원격 · 로컬).

임시 브랜치 `gh-m0-mut-b`: `shared/screen_args.zig` 한 줄의 들여쓰기를 깨뜨린다. 같은 순서 → `host` 빨강(`FAIL: zig-fmt`).
`container`는 둘 다 초록이어야 한다(Dockerfile · init 소스는 그대로다 — (b)는 `shared/`를 바꾸므로 init 빌드가 돈다. 서식이
깨져도 컴파일은 되므로 초록이 맞다).

commit 없음(브랜치는 지운다). 결과는 아래 결과 절에.

## Task 4 — 문서 · 루트 게이트

- `docs/guides/lessons.md` "범용 명령"의 Zig 세 줄(440~445행) → `make quick` 한 줄과 "명령은 `quick_check.sh`에".
- `docs/guides/key-files.md` 게이트 절에 `quick_check.sh` · `.github/workflows/checks.yml` 한 줄씩.
- `docs/decisions/project_zig_upgrade.md` — "zig fmt는 고침과 따로 commit한다" 절의 "이 저장소에 fmt 게이트는 없고 만들지
  않았다"에 "GH-M0(2026-10-30)부터 `quick_check.sh`가 `fmt --check`를 CI에서 본다"를 더하고, 올리는 절차에 "Dockerfile의
  `ZIG_VERSION`과 `checks.yml`의 `ZIG_SHA256`을 함께"를 더한다.
- 루트 게이트 1회(약 10분, `/tmp/gate.log`).
- commit 하나. 닫기는 design "닫을 때" 목록대로 따로.

## 결과

### Task 1

- 첫 `make quick`이 `FAIL: shellcheck`로 빨갰다 — 둘. (1) `quick_check.sh` 자신의 머리 주석 한 줄이 `# shellcheck 버전은 …`으로
  시작해 shellcheck가 지시자로 읽고 SC1073 · SC1072(error)를 냈다. 주석을 "셸 검사기의 버전은"으로 바꾸고 그 사실을 주석에 적었다.
  (2) `wifi/ap.sh`의 `for i`가 둘이 아니라 넷이었다(32 · 64 · 78 · 89행) — shellcheck는 한 변수에 SC2034를 한 번만 찍어 둘을 고친 뒤에야
  다음이 보였다. 넷 다 `_`. 그 뒤 `quick_check: PASS`, `shellcheck 52 files`(49 `.sh` + 게스트 둘 + `quick_check.sh` 자신),
  `shellcheck notes: 46`, 호스트 23초(warm).
- `make check CHAIN=wifi` PASS(WL-M3 줄), verify에 `ok` 아닌 줄 0. ap.sh가 찍는 `wlan0 inet` · `wrong key seen` · `after restart` 셋 그대로.
- commit `e7d7faf`.

### Task 2

- commit `2259b14`, push → run 41065218866(push, main). 두 job 초록. host 13:40:52 → 13:44:01(3분 9초), container 13:40:54 →
  13:44:07(3분 13초). 큐 대기는 push 뒤 3초.
- host 단계: checkout 2초 · shellcheck 받기 1초 미만 · zig 받기 9초 · `quick_check.sh` 2분 54초(shellcheck 두 번 27초 · fmt + ast-check +
  shared 5초 · init 크로스 빌드 약 2분 20초, cold cache). 로그에 `shellcheck 52 files` · `shellcheck notes: 46` · `PASS`, 버전 불일치
  줄 없음.
- container 단계: `docker build` 46초(캐시 없음 — design의 "몇 분" 걱정은 틀렸다, runner의 네트워크가 빠르다) · sanity 5초 · `cd init
  && zig build` 2분 17초(aarch64, cold). 층 캐시(M1 후보)는 필요 없다 — 시간의 대부분이 Zig 빌드다.

### Task 3

- (a) `gh-m0-mut-a`(`probe/run.sh`의 `|| exit 1`을 뺌) → run 41065384460(workflow_dispatch). host 빨강 — 로그에 SC2164 warning과
  `quick_check: FAIL: shellcheck`. container 초록(3분 17초).
- (b) `gh-m0-mut-b`(`shared/screen_args.zig` 27행 들여쓰기 한 칸) → run 41065427544. host 빨강 — `zig fmt --check`가
  `shared/screen_args.zig`를 찍고 `quick_check: FAIL: zig-fmt`. container 초록(3분 7초) — 서식이 깨져도 컴파일은 되므로 맞다.
- 둘 다 `quick_check.sh`가 실패한 단계 뒤에도 나머지 단계를 끝까지 돌고 마지막에 실패한 단계 이름을 모아 말한다(설계대로).
- 브랜치 둘은 원격 · 로컬에서 지웠다. commit 없음.

### Task 4

- 문서 셋(lessons "범용 명령" → `make quick`, key-files 두 줄, project_zig_upgrade의 fmt 절과 "다음에 올릴 때 고칠 자리").
- 루트 게이트 22/22, 10분 11초(prebuild 311 + lanes 299초), 22회차 verify 줄 전부 `ok`(`out/gate-logs/20261030-134638`). 바뀐 것이 지시자 주석 둘 · `for _` · `|| exit 1`이라
  게이트에 보일 것은 없었고, 보이지 않았다.
