# TARS Vendor Sha256 — Design

Date: 2026-10-31
Status: 초안 — 사용자 검토 전

GH-M1이 남긴 다음 후보 둘(vendor sha256 · ghcr.io 이미지) 가운데 "vendor sha256"에서 시작한다. 사용자가 골랐다(2026-10-31).

## 한 줄 요약

저장소가 네트워크에서 받는 파일 가운데 sha256을 대조하지 않는 여섯 자리(ghostty tarball · `stb_truetype.h` · `stb_image.h` ·
커널 tarball · limine tarball · Dockerfile의 Zig aarch64 tarball)에 기대 해시 한 줄과 대조 한 줄을 더한다. 받는 모양 · 푸는 자리 ·
산출물은 그대로이고, 다른 파일이 들어오면 그 자리에서 `FAILED`로 멈춘다. 코드(Zig) 0줄.

## 배경

- 이 저장소는 커널 · 부트로더 · vendor 소스를 직접 받아 빌드한다. 받는 자리의 절반은 이미 대조한다 — `kernel/vendor_firmware.sh`의
  linux-firmware · wireless-regdb · sof-bin(WL-M1 · AU-M3), `checks.yml`의 shellcheck · Zig x86_64(GH-M0), `build.zig.zon`의
  의존성(Zig가 zon 해시로), 폰트는 저장소 안(FR-M0). 나머지 절반은 "URL이 커밋 SHA나 버전을 박고 있으니 됐다"로 남아 있었다.
- 대조가 없을 때의 실패는 원인에서 멀다. ghostty 트리가 조용히 다른 커밋이 되면 `vt_test`가 틀리거나 게스트 화면이 달라지고,
  커널 tarball이 다르면 게이트가 다른 커널로 부팅한다 — 폰트(`terminal/vendor/fonts/README`)와 firmware가 버전을 고정한 이유와
  같다. GH design 위험 2가 "sha256이 안 맞는 빨강은 재실행으로 안 풀린다"라고 구분해 둔 자리가 지금은 여섯 자리에서 비어 있다.
- CI의 `container` job은 push마다 깨끗한 runner에서 `prepare.sh`를 돌리므로 받는 분기를 매번 탄다. 로컬 게이트는 트리가 이미 있어
  받지 않는다 — 대조가 실제로 도는 자리는 CI와 새 저장소의 첫 빌드다.

## 착수 전에 확인한 것

2026-10-31, HEAD `e214773`.

1. 대조 없는 여섯 자리와 받는 모양. 전부 "산출물이 없으면 받는다 → 푼다 → tarball을 지운다"다 — 이미 있는 트리는 다시 받지
   않으므로 대조는 받는 그 순간 한 번이다.

   | 자리 | 파일 | 크기 | 출처 |
   |------|------|------|------|
   | `terminal/vendor_libghostty_vt.sh` | `ghostty-src.tar.gz`(커밋 `3d07ef9`) | 39.7MB | GitHub archive |
   | `terminal/vendor_stb_truetype.sh` | `stb_truetype.h`(커밋 `2c980bb`) | 199KB | raw.githubusercontent |
   | `terminal/vendor_stb_image.sh` | `stb_image.h`(커밋 `2c980bb`) | 283KB | raw.githubusercontent |
   | `kernel/build.sh` | `linux-6.18.42.tar.xz` | — | cdn.kernel.org |
   | `boot/build.sh` | `limine-binary.tar.gz`(`v12.5.2`) | 1.9MB | GitHub release asset |
   | `devcontainer/Dockerfile` | `zig-aarch64-linux-0.17.0.tar.xz` | 52.9MB | ziglang.org |

2. 기대 해시 여섯. 공식 해시가 있는 셋은 그것을 읽었고, 없는 셋(GitHub archive · raw)은 두 번 받아 같은 값인지 봤다.

   | 파일 | sha256 | 근거 |
   |------|--------|------|
   | `ghostty-src.tar.gz` | `3949e4bf93f345c7729faecac6b9916aeb5a2b745de5671a7fe8d4725040046c` | 두 번 받아 같음 + 아래 3 |
   | `stb_truetype.h` | `ecd30b05e0dd4fea3a13c26810dd9e1992dc379049482c393d5a19e6b5090aab` | 두 번 받아 같음 |
   | `stb_image.h` | `594c2fe35d49488b4382dbfaec8f98366defca819d916ac95becf3e75f4200b3` | 두 번 받아 같음 |
   | `linux-6.18.42.tar.xz` | `35a8ef5e8fb44467e56a42b40c23c4c10a61d1e95ff8d738f285230e8bed63e7` | kernel.org `v6.x/sha256sums.asc` |
   | `limine-binary.tar.gz` | `4c760c09c53560d859b362319a3dc63b79cca3d47f35d69ab0106a13b8057055` | GitHub release asset `digest`(`gh api`) |
   | `zig-aarch64-linux-0.17.0.tar.xz` | `9e8d11661d4ae3bd57702a3832781e23ad151dde5798e16a5ccd503f65234ff8` | ziglang.org `index.json` `shasum`(GH design 확인 7과 같다) |

3. 받은 ghostty tarball을 풀어 지금의 `terminal/ghostty-src`와 `diff -rq`(`.zig-cache` · `zig-out` · `zig-pkg` 제외) — 0줄. 게이트가
   지금 빌드하는 트리가 그 해시의 tarball이다. 커널 소스 · limine은 같은 대조를 하지 않았다(tarball을 푼 뒤 빌드가 트리 안에
   산출물을 남겨 `diff`가 뜻이 없다) — 버전이 URL에 있고 공식 해시를 쓰므로 대신 받는 분기를 다시 타 본다(결정 5).
4. 저장소 안의 대조 꼴은 둘이다. `vendor_firmware.sh`의 `fetch()`는 `.tmp`로 받아 `sha256sum -c --status`, 틀리면 URL · 기대 ·
   실제 세 줄을 찍고 지운다. `checks.yml`은 `echo "$SHA  file" | sha256sum -c -` 한 줄이다(성공에 `file: OK` 한 줄, 실패에
   `FAILED`와 exit 1).
5. 여섯 자리는 전부 Linux에서 돈다 — vendor 스크립트 · `build.sh` 둘은 컨테이너 안(게이트 prebuild · `make kernel` · CI `container`),
   Dockerfile은 `docker build`다. `sha256sum`은 coreutils라 ubuntu 베이스에 있다. 호스트 macOS에서 부르는 자리는 없다.
6. `kernel/build.sh`는 자기 자신을 스탬프에 넣는다(`cat .config build.sh | sha256sum`, GL-M1). 이 파일을 고치면 로컬 `make
   kernel`이 다음 한 번 커널을 통째로 다시 빌드한다. 게이트는 `clean()`이 `kernel/build/`를 지워 매 회차 진짜로 빌드하므로
   게이트 시간에는 0이다.
7. GitHub archive의 바이트 안정성. 2023-01-30에 GitHub이 archive의 압축을 바꿔 해시가 달라졌다가 되돌렸고, 그 뒤 "바꾸려면 최소
   여섯 달 전에 알린다"고 했다. 바뀌면 빨강은 재실행으로 안 풀리고 해시 한 줄을 고치는 일이다(위험 1).
8. 낡은 글 하나 — `docs/guides/key-files.md`의 `terminal/vendor_fonts.sh` 줄. FR-M0이 그 파일을 지웠다. 이번 일이 vendor 스크립트
   줄을 고치므로 함께 지운다.

## 결정

### 결정 1. 여섯 자리 전부 — "받는 것은 대조한다"

HANDOFF의 "vendor sha256"은 terminal의 셋이었지만, 같은 한 줄 패턴이 여섯 자리에 같은 뜻으로 들어가므로 한 번에 한다. 셋만 하면
"ghostty는 대조하는데 커널은 안 한다"는 설명하기 어려운 선이 남는다. 받는 자리는 `rg -n 'curl -sSL -o'`로 찾을 수 있고, 다음에
받는 자리를 더하는 사람은 이 여섯을 본보기로 한다.

### 결정 2. 모양은 `checks.yml`의 한 줄 — 변수 하나, 대조 한 줄

스크립트 다섯은 머리의 버전 변수 옆에 `*_SHA256="…"` 한 줄, 받은 직후에

```
echo "${GHOSTTY_SHA256}  ghostty-src.tar.gz" | sha256sum -c -
```

한 줄. `set -e`라 `FAILED`에서 멈추고 `sha256sum`이 실패 줄을 찍는다. `vendor_firmware.sh`의 `fetch()` 꼴(세 줄 메시지)을 가져오지
않는다. `gate_lib.sh`에 공통 함수를 두지도 않는다 — `prepare.sh` · `build.sh`는 게이트 밖(README의 빌드 한 줄)에서도 불리고
`gate_lib.sh`를 source하지 않는다.

받는 파일이 곧 "이미 있으면 안 받는다"의 검사 대상인 자리(stb 둘 — `-o "$DEST"`)는 `${DEST}.tmp`로 받아 대조한 뒤 `mv`한다.
`FAILED`로 멈춘 뒤 나쁜 파일이 `DEST`에 남으면 다음 실행이 "있다"로 건너뛰어 조용히 쓰기 때문이다 — plan의 mutation이 첫 꼴에서
그것을 잡았다(plan 결과). tarball 셋은 존재 검사가 푼 디렉터리에 걸려 있고 tarball은 풀기 전이라 남아도 다음 실행이 덮어쓴다 —
`.tmp` 없이 간다. `vendor_firmware.sh`가 `.tmp`를 쓰는 것도 같은 이유였다(받은 tarball 자체를 캐시로 남기므로).

다른 파일이 들어왔을 때 사람이 볼 것은 "실제 해시"다. `sha256sum -c`는 그것을 안 찍지만, 그 값은 `sha256sum <파일>` 한 번이고 어차피
버전을 올리는 사람이 기대값을 바꾸기 전에 출처(결정 3)와 대조해야 한다 — 실제 해시를 그대로 옮겨 적는 길을 만들지 않는다.

Dockerfile은 `ENV ZIG_VERSION` 아래에 `ARG ZIG_SHA256=…`(이미지에 안 남는다) 한 줄과 `RUN curl … && echo "${ZIG_SHA256}  /tmp/zig.tar.xz"
| sha256sum -c - && …` 한 조각. `checks.yml`의 `ZIG_SHA256`(x86_64)과 이름이 같되 값이 다르다 — 둘 다 같은 `index.json`의 다른 행이다.

### 결정 3. 해시의 출처를 주석에 적는다

여섯 자리마다 기대값 위에 어디서 읽었는지 한 줄 — `kernel.org sha256sums.asc` · `GitHub release digest` · `ziglang.org index.json` ·
`두 번 받아 같음(공식 해시 없음)`. 버전을 올리는 사람이 같은 자리에서 새 값을 읽게 하려는 것이다. 공식 해시가 없는 셋은 "두 번
받아 같은 값, 풀어서 지난 트리와 diff"가 절차다(확인 3).

### 결정 4. 버전을 올릴 때 고칠 자리

- Zig: Dockerfile `ZIG_VERSION` · Dockerfile `ZIG_SHA256`(aarch64) · `checks.yml` `ZIG_SHA256`(x86_64) 셋. `project_zig_upgrade.md`의
  "다음에 올릴 때 고칠 자리"에 Dockerfile 해시를 더한다.
- ghostty: `GHOSTTY_SHA`(커밋)와 `GHOSTTY_SHA256`(tarball) 둘. `reference_ghostty_source.md`에 한 줄.
- 커널 · limine · stb: 각 스크립트의 버전 변수 옆에 해시가 있으므로 그 파일 안에서 끝난다.

빠뜨리면 다음 받기가 `FAILED`로 멈춘다 — 조용히 넘어가는 길은 없다.

### 결정 5. 검증

게이트 입력(prepare.sh가 부르는 vendor 셋 · `kernel/build.sh` · `boot/build.sh`)이 바뀌므로 루트 게이트를 돈다. 대조 자체는 로컬
게이트가 안 탄다(트리가 있다) — 받는 분기를 일부러 탄다.

1. 받는 분기 다섯을 컨테이너 안에서 실제로 탄다 — `terminal/ghostty-src` · `terminal/vendor/stb_*.h` · `kernel/src/linux-6.18.42` ·
   `boot/limine-binary`를 옆으로 옮기고(`mv`, 지우지 않는다) 스크립트를 돌려 `… : OK` 줄 다섯. 끝나면 옮긴 것은 지운다(새로 받은
   것이 같은 해시다).
2. mutation 둘 — `vendor_stb_image.sh`의 해시 한 글자, Dockerfile의 해시 한 글자. 각각 `FAILED`로 멈추는지 본다(Dockerfile은 그
   층 앞이 캐시라 짧다). 되돌린다.
3. 컨테이너 이미지를 다시 굽는다(`docker build`, Zig 층부터). `make quick` PASS(shellcheck가 다섯 스크립트를 본다).
4. 루트 게이트 1회(약 10분). 22/22, verify 줄 전부 `ok`. prebuild 시간은 커널 빌드가 매번이라 이번 일로 안 바뀐다.
5. push 뒤 CI 한 회차 — `container` job이 깨끗한 runner에서 prepare.sh의 받는 분기를 타므로 `OK` 줄 셋이 로그에 있어야 한다.
   `docker build` 안의 Zig 대조도 같은 회차가 본다.

## 위험

1. GitHub archive의 바이트가 바뀐다(확인 7). 그때 빨강은 `ghostty-src.tar.gz: FAILED`이고 `gh run rerun`으로 안 풀린다. 처방은 새
   tarball을 풀어 지난 트리와 `diff -rq` 0줄을 확인한 뒤 해시 한 줄을 고치는 것 — 주석의 절차(결정 3)가 그것이다. stb의 raw
   파일은 blob이라 바뀔 길이 없다.
2. 대조는 받는 순간 한 번이다. 이미 있는 트리가 바뀌어 있어도(사람이 손댔거나 빌드가 트리 안에 썼거나) 모른다. 지금 트리가
   tarball과 같음은 확인 3이 봤고, 트리를 계속 지키는 일은 이번 범위가 아니다(비목표 3).
3. `kernel/build.sh`를 고치면 로컬 증분 `make kernel`이 한 번 전체 빌드다(확인 6). 게이트는 영향 없다.
4. Dockerfile을 고치면 이미지를 다시 굽는다(Zig 층 하나, 그 앞은 캐시). `make container`는 이미지가 있으면 안 굽는다 — 결정 5의 3이
   `docker build`를 직접 부른다.
5. 공식 해시 없는 셋(ghostty · stb)의 기대값은 "오늘 받은 것"이다. 오늘 받은 것이 이미 바꿔치기된 것이라면 그것을 고정하는 셈이다
   — ghostty는 확인 3(지난 트리와 같다, 그 트리로 게이트가 수십 회 돌았다)이, stb는 커밋 SHA 고정 blob이라는 점이 근거다.

## 비목표

1. `build.zig.zon` 의존성 — Zig가 zon 해시로 대조한다.
2. apt 패키지 · 베이스 이미지 digest 핀(`FROM ubuntu:24.04@sha256:…`). apt 층은 어차피 날마다 움직이고 Debian이 서명한다 — 베이스만
   핀해서 얻는 것이 없다. ghcr.io 이미지(GH의 다른 후보)가 그 층을 통째로 고정하는 길이다.
3. 받아 둔 트리를 매 회차 다시 대조하는 것(위험 2). 트리 안에 빌드 산출물이 남아 단순 비교가 안 된다.
4. stb 헤더 둘을 저장소에 넣는 것(FR-M0이 폰트에 한 길, 482KB). 받는 자리를 없애는 것은 다른 판단(저장소 크기 · 라이선스 파일)이고
   이번 일은 받는 자리에 같은 규칙을 세우는 것이다. 원하면 `vendor_stb_*.sh` 둘을 지우는 한 걸음이다.
5. `vendor_firmware.sh`의 `fetch()`를 결정 2의 꼴로 맞추기 — 도는 것을 모양 때문에 고치지 않는다.

## Milestone

- VS-M0 — 위 결정 전부. Task 둘.
  1. 여섯 자리의 해시 · 대조 · 출처 주석, 문서의 낡은 줄(확인 8 · 결정 4). 확인 1 · 2 · 3.
  2. 루트 게이트(확인 4) → commit → push · CI(확인 5) → 닫기.

## 닫을 때(lead의 몫)

- 이 design의 `Status:`, `docs/guides/completed.md`의 한 행.
- `docs/decisions/project_github_actions.md`의 "남긴 것"에서 vendor sha256을 지우고 VS-M0 한 단락. 새 기억 파일은 만들지 않는다
  (작은 일이다) — `MEMORY.md`의 GitHub Actions 줄에 덧붙인다.
- `docs/decisions/project_zig_upgrade.md` "고칠 자리"(결정 4), `docs/decisions/reference_ghostty_source.md` 한 줄.
- `docs/guides/key-files.md` — `vendor_fonts.sh` 줄 삭제, vendor 스크립트 · `build.sh` 둘 · Dockerfile 줄에 "sha256 대조".
- `HANDOFF.md`. 소개 페이지에는 안 넣는다(내부 작업).

## 관련

- `docs/specs/2026-10-30-tars-github-actions-design.md` — 확인 7(Dockerfile은 대조하지 않는다) · 위험 2(sha256 빨강은 재실행으로 안
  풀린다) · 비목표 8(이 일을 따로 고른다).
- `kernel/vendor_firmware.sh` · `terminal/vendor/fonts/README` — 버전을 고정하는 같은 이유.
- `docs/decisions/project_font_selection.md` — FR-M0, 받지 않고 저장소에 둔 쪽.
