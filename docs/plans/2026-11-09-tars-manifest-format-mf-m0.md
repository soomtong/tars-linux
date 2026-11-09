# MF-M0 — manifest.toml과 Zig 변환기

Date: 2026-11-09
Design: `docs/specs/2026-11-09-tars-manifest-format-design.md`(결정 1~8)
Status: 착수 전

## 착수 전에 확정한 것

plan을 쓰며 읽은 것(HEAD `96c1d17`).

1. Zig는 개발 컨테이너 0.17.0(`devcontainer/Dockerfile:567`), 호스트 0.17.1. 0.17의 파일 입출력은 `std.process.Init`의 `io`를 거친다 —
   `std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .unlimited)`(선례 `terminal/src/font_test.zig:17`), `Dir.writeFile(io, .{ .sub_path, .data })`,
   `Dir.rename(old, new_dir, new, io)`, 인자는 `init.minimal.args.toSlice(arena)`.
2. stamp에 `manifest.sh`의 sha256이 들어간다(`build.sh:305`) — design 2판 결정 8. 묶음 열한 개를 다시 굽는다(4분 남짓).
   harvest 캐시는 `harvest.sh:46`이 `harvest.sh` · `harvest-skip.tsv` · 줄 · 저장소 상태만 본다. 이 milestone은 `harvest.sh`를 고치지 않는다
   (주석 한 자도 — 고치면 debian · vendor-repo 묶음을 망으로 다시 거둔다).
3. `build.sh` · 훅 다섯의 주석에 `manifest.tsv`라는 이름이 있다. `build.sh` · 훅도 stamp에 들어가지만 어차피 다시 굽는 판이라 함께 고친다.
   `harvest.sh`의 주석(`:9` 등)만 그대로 둔다.
4. debian 45줄 모두 5열 = 도구 이름(design 확인). 그러니 TOML의 debian 도구에는 `package`가 하나도 없다. 변환기는 `package`를 받지만
   지금은 쓰는 곳이 없다.
5. 지금 `devlayer/build/*.sqfs`가 HEAD의 manifest와 맞는지 모른다(fakesteak 13:21, 나머지 09:30~09:33). Task 0이 먼저 확인한다.

## Task 0 — 기준 재기

- `make dev-layers DEV_LAYERS="base docs editor lang-beam lang-jvm lang-native lang-script media server util fakesteak"` — 모두 `cached`이길
  바란다. 아니면 그 묶음이 새로 구워지고, 그것이 기준이 된다.
- `shasum -a 256 devlayer/build/*.sqfs > <scratchpad>/before.sha256`, 옛 TSV를 `<scratchpad>/manifest.tsv.orig`로 복사.

## Task 1 — 변환기 `devlayer/manifest-gen.zig`

한 파일, 세 부분.

1. 읽기(`parse`). 줄 단위 상태 기계. 상태는 "표 밖 · `[[tool]]` 안 · 여러 줄 배열 안" 셋. 주석은 문자열 밖의 `#`부터 줄 끝까지.
   값은 기본 문자열(`"…"`, `\` · 제어 문자 거절) · 10진 정수 · 문자열 배열. 결과는 도구마다 `(키, 값, 줄 번호)`의 열을 적힌 순서대로.
   처음 보는 문법은 그 줄 번호로 `error.Syntax`.
2. 검사와 내보내기(`emit`). design 결정 2 · 3의 표를 코드의 표 하나(`kinds`)로 — 종류마다 반드시 키 · 받는 키 · 5열 · 6열을 만드는 법.
   공통 검사: 키 중복, `name` 중복(첫 줄 번호와 함께), 값의 공백 · 탭, 옵션 값의 `=`, `exe` 항목의 `,`, 빈 문자열, `strip`은 정수 ·
   나머지는 문자열 · `exe`는 배열. vendor-repo의 `repo`는 `[a-z0-9-]+`, `package`는 `[a-z0-9][a-z0-9.+-]*`(지금 `manifest_check`와 같다).
   선택 키는 적힌 순서대로 `키=값`을 공백으로 잇는다.
3. `main`. `manifest-gen <in.toml> <out.tsv>`. 진단은 `<in>:<줄>: <이유>`를 stderr에 찍고 1로 끝난다(여러 개면 다 찍는다 — 한 번에 고치게).
   출력은 `<out>.tmp`에 쓰고 rename.

`test` 블록: 정상 셋(upstream + exe 배열 여러 줄 · debian 최소 · vendor-repo), 거절 여덟 남짓(모르는 키, 종류에 안 맞는 키, 빠진 키,
이름 중복, 값의 공백, 작은따옴표, `[table]`, 닫히지 않은 배열). 출력 문자열을 그대로 대조한다.

## Task 2 — 옮기기(일회성, scratchpad)

`<scratchpad>/tsv2toml.awk`: 옛 TSV를 읽어 주석 · 빈 줄은 그대로, 도구 줄은 `[[tool]]` 덩어리로. 종류에 따라 design 결정 2의 키로
(debian은 5열이 이름과 같으면 `package`를 안 쓴다, vendor-repo는 5열을 `repo`/`package`로 가른다, maven · hex는 `lock`). 일곱째 열은
적힌 순서대로, `exe`는 배열(셋 이상이면 여러 줄), `strip`은 따옴표 없이. 도구 사이에는 빈 줄 하나.

파일 머리 주석은 새로 쓴다 — 옛 머리(열 설명 · 탭 경고)는 TSV의 것이라 맞지 않는다. 키 표와 종류 설명(옛 머리의 "종류는 넷이다" 절)을
TOML 말로 다시 적고, 생성 TSV의 자리와 `make quick`이 검사한다는 것을 적는다.

## Task 3 — 잇기

- `devlayer/manifest.sh`: `DEVLAYER_MANIFEST` 기본값을 `devlayer/build/manifest.tsv`로. 머리 주석의 출처 설명을 "생성된 것, 출처는 toml"로.
  `manifest_check` 앞에 파일이 없으면 `run make dev-layers (devlayer/manifest.toml → devlayer/build/manifest.tsv)`를 찍고 1. 검사 awk는 그대로.
- `Makefile` `dev-layers`: `keys.sh` 다음에 `$(IN_CONTAINER) 'mkdir -p devlayer/build && zig run --cache-dir devlayer/build/zig-cache
  --global-cache-dir devlayer/build/zig-cache devlayer/manifest-gen.zig -- devlayer/manifest.toml devlayer/build/manifest.tsv'`. 컴파일 시간을 잰다.
  `help`의 안내 한 줄(`:113`)을 toml로.
- `quick_check.sh`: 단계 8 — `zig test devlayer/manifest-gen.zig`와 `zig run devlayer/manifest-gen.zig -- devlayer/manifest.toml out/quick/manifest.tsv`.
  단계 2 · 3(fmt · ast-check)의 대상에 `devlayer/manifest-gen.zig`를 더한다. 머리 주석의 단계 수.
- 이름을 대는 주석: `build.sh`, `hooks/*.sh` 다섯, `needed-ignore.tsv:5`. `harvest.sh`는 제외(확인 2).
- 옛 `devlayer/manifest.tsv`를 `git rm`.

## Task 4 — 판정

1. `diff <(rg -v '^#|^\s*$' <scratchpad>/manifest.tsv.orig) <(rg -v '^#' devlayer/build/manifest.tsv)` 비어 있다.
2. 주석 줄 수: 옛 TSV의 주석 90줄이 모두 TOML에 있다(머리 주석 고친 것은 따로 센다) — `rg -c`와 눈으로.
3. Task 0과 같은 `make dev-layers`(묶음 열한 개, 4분 남짓) 뒤 `shasum -a 256 -c before.sha256`이 모두 OK.
   다르면: mksquashfs가 결정적이지 않은 것인지(같은 입력으로 두 번 구워 본다) 내용이 다른 것인지(`unsquashfs -lln` 대조)를 가른다.
4. `make quick` PASS.
5. 일부러 틀린 TOML 한 판(종류에 안 맞는 키 하나)으로 `make dev-layers DEV_LAYERS=docs`가 harvest 전에 줄 번호를 찍고 멈춘다.

## 비목표

design의 비목표 그대로. 버전 올리기 · 도구 더하기는 이 milestone에서 하지 않는다 — 바이트 대조가 판정이라 내용을 바꾸면 판정이 무너진다.

## 결과

(구현 뒤 적는다)
