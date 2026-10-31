# VS-M0 — 받는 자리 여섯에 sha256 대조

Date: 2026-10-31
Design: `docs/specs/2026-10-31-tars-vendor-sha256-design.md`
Status: 진행 중

## 착수 전에 확정한 것

design의 확인 1~8에 더해, plan을 쓰며 읽은 것.

1. 컨테이너 안에서 한 줄을 돌리는 꼴은 `Makefile`의 `IN_CONTAINER`(`docker run --rm -v "$PWD":/workspace -w /workspace
   tars-devcontainer bash -c '…'`)다. 받는 분기 확인(design 결정 5의 1)은 이 꼴로 스크립트 다섯을 부른다.
2. Dockerfile은 단일 stage(`FROM debian:trixie-slim` 하나)다. `ARG ZIG_SHA256`은 `ENV ZIG_VERSION` 바로 아래에 두면 그 뒤의
   `RUN`에서 보인다. 지금 이미지는 `9d5eebc3e08e`(6일 전, 1.54GB).
3. 로컬에 다섯 트리가 다 있다(`kernel/src/linux-6.18.42` · `boot/limine-binary` · `terminal/ghostty-src` · `vendor/stb_*.h` 둘).
   옮길 자리는 같은 디렉터리 옆의 `*.before-vs`다 — `.gitignore`가 `kernel/src/` · `boot/limine-binary/` · `terminal/vendor/*`를
   디렉터리 · 글롭으로 막으므로 `kernel/src/linux-6.18.42.before-vs` · `terminal/vendor/stb_image.h.before-vs`는 걸리지만
   `boot/limine-binary.before-vs` · `terminal/ghostty-src.before-vs`는 안 걸린다. `git status`에 뜨는 동안만 두고 확인이 끝나면
   지운다(commit 전 `git status`가 이것을 잡는 자리다).
4. `kernel/build.sh`는 받은 뒤 `tar -C src -xf`로 풀고 지운다. 대조 줄은 `curl` 다음 · `tar` 앞이다. 다섯 스크립트가 다 같은 자리다.
5. `vendor_libghostty_vt.sh`의 CC-M0 주석은 "이 스크립트가 하는 일은 소스 트리를 받아 두는 것 하나다"라고 끝난다 — "받아 대조해
   두는 것"으로 한 단어 고친다.

## Task 1 — 여섯 자리 · 문서 낡은 줄

자리(design 결정 2 · 3):

- `terminal/vendor_libghostty_vt.sh` — `GHOSTTY_SHA256` + 출처 주석(두 번 받아 같음 · 지난 트리와 diff 0, 바뀌면 풀어서 diff 뒤 고친다),
  `curl` 뒤 대조 한 줄, CC-M0 주석 한 단어.
- `terminal/vendor_stb_truetype.sh` · `vendor_stb_image.sh` — `STB_SHA256` + 출처 주석(blob, 두 번 받아 같음), 대조 한 줄.
- `kernel/build.sh` — `KERNEL_SHA256` + 출처 주석(kernel.org `v6.x/sha256sums.asc`), 대조 한 줄.
- `boot/build.sh` — `LIMINE_SHA256` + 출처 주석(GitHub release asset digest, `gh api …/releases/tags/v12.5.2`), 대조 한 줄.
- `devcontainer/Dockerfile` — `ARG ZIG_SHA256=…` + 출처 주석(ziglang.org `index.json`, aarch64-linux 행 — `checks.yml`은 x86_64 행),
  `RUN` 안에 `&& echo … | sha256sum -c -`.
- 문서: `docs/guides/key-files.md`의 `vendor_fonts.sh` 줄 삭제, `project_zig_upgrade.md` "고칠 자리"에 Dockerfile 해시,
  `reference_ghostty_source.md`의 빌드 입력 줄에 `GHOSTTY_SHA256`.

확인:

1. `git diff --stat` — 지운 줄은 주석 한 단어 자리와 `vendor_fonts.sh` 줄 · 바꾼 문서 줄뿐이어야 한다. `git diff | rg '^-[^-]'`로
   지운 줄을 전부 읽는다.
2. `make quick` PASS(shellcheck가 다섯 스크립트를 본다).
3. 받는 분기 다섯 — 트리를 `*.before-vs`로 옮기고 컨테이너 안에서 `vendor_libghostty_vt.sh` · `vendor_stb_*.sh` 둘 · `kernel/build.sh` ·
   `boot/build.sh`를 돌려 `…: OK` 다섯 줄. `kernel/build.sh`는 받은 뒤 커널 빌드까지 이어진다(스탬프가 깨졌으니 어차피 한 번은
   빌드한다 — 백그라운드로 두고 시간을 적는다). 새 `ghostty-src`와 옮긴 것을 `diff -rq`(캐시 제외) 0줄로 한 번 더 본 뒤
   `*.before-vs`를 지운다.
4. mutation 둘 — `vendor_stb_image.sh`의 해시 끝 글자를 바꾸고 `vendor/stb_image.h`를 옮긴 뒤 돌린다 → `FAILED`, rc 1. Dockerfile의
   해시 끝 글자를 바꾸고 `docker build` → Zig 층에서 멈춘다. 둘 다 되돌리고 `git diff`로 원복 확인.
5. `docker build -t tars-devcontainer devcontainer/`로 이미지를 다시 굽는다(Zig 층부터). `docker image ls`의 ID가 바뀐다.

## Task 2 — 게이트 · commit · CI · 닫기

- 루트 게이트 1회(약 10분, `/tmp/gate.log`). 22/22, verify 줄 전부 `ok`. prebuild 시간은 이번 일로 안 바뀐다(커널 빌드는 매 회차).
- commit 하나(Task 1). push → `gh run watch` — 두 job 초록. `container` 로그에서 `terminal prepare and test` step의 `OK` 줄 셋과
  `docker build` step의 `/tmp/zig.tar.xz: OK`를 찾는다.
- 문서: design `Status:` · `completed.md` 한 행 · `project_github_actions.md`의 "남긴 것"과 VS-M0 단락 · `MEMORY.md` · `key-files.md`의
  스크립트 줄 · `HANDOFF.md`. commit 하나(닫기), push.

## 결과

### Task 1

- `git diff --stat`: 9파일, +39 −4. 지운 넷은 CC-M0 주석의 한 단어 자리 · `key-files.md`의 `vendor_fonts.sh` 줄 · 문서 두 줄(ZU · ghostty
  기억)뿐이다. `git diff | rg '^-[^-]'`로 읽었다(key-files 줄은 markdown 불릿이라 `--`로 시작해 그 필터에 안 걸린다 — stat의 4와
  필터의 3이 다른 이유).
- `make quick` PASS(고친 뒤 두 번).
- 받는 분기 다섯을 컨테이너 안에서 탔다 — `ghostty-src.tar.gz: OK` · `vendor/stb_truetype.h.tmp: OK` · `vendor/stb_image.h.tmp: OK` ·
  `limine-binary.tar.gz: OK` · `src/linux-6.18.42.tar.xz: OK`. terminal 셋 5초, limine 2초, 커널은 받기 · 풀기 · 빌드까지 113초(`kernel/build/`가
  있어 증분). 새 `ghostty-src`는 옮겨 둔 트리와 `diff -rq`(캐시 제외) 0줄, stb 둘은 `cmp` 동일. `*.before-vs`는 지웠다.
- 컨테이너 안에 `rg`가 없다(GH design 확인 9의 runner와 같다) — 첫 재현에서 파이프가 죽어 `grep`으로 다시 돌렸다.
- mutation 둘 다 `FAILED`로 멈췄다.
  - Dockerfile 해시 끝 글자 → `docker build` rc 1, 88초(앞 층은 캐시, Zig 층의 `sha256sum: WARNING: 1 computed checksum did NOT match`).
  - `vendor_stb_image.sh` 해시 끝 글자 → rc 1. 그런데 첫 꼴(`-o "$DEST"`)은 나쁜 파일을 `vendor/stb_image.h`에 남겼다 — 다음 실행이
    "있다"로 건너뛰어 조용히 썼을 것이다. stb 둘을 `${DEST}.tmp`로 받아 대조 뒤 `mv`하는 꼴로 고치고(design 결정 2에 반영) 다시 돌렸다:
    `vendor/stb_image.h.tmp: FAILED`, `DEST` 없음. 정상 재현도 `.tmp` 꼴로 다시 — `OK` 둘, `cmp` 동일.
- 이미지 다시 굽기: 19초(Zig 층만), `/tmp/zig.tar.xz: OK`, ID `9d5eebc3e08e` → `6c2674d36158`.
