# TARS Font in Repo — Design

Date: 2026-10-31
Status: design

GH-M1이 남긴 다음 후보 "unifont 미러"에서 시작한다. 사용자가 미러가 아니라 저장소 안에 두는 쪽으로 골랐다(2026-10-31).

## 한 줄 요약

GNU Unifont 17.0.03(`unifont.otf`, 5.3MB, gzip 1.3MB)을 지금 자리 `terminal/vendor/fonts/` 그대로 커밋하고, 받는 스크립트
`terminal/vendor_fonts.sh`를 지운다. 라이선스 원문(`OFL-1.1.txt`)과 출처 · 버전 · sha256을 적은 `README`를 옆에 둔다. 폰트를 읽는
코드(게스트 `main.zig` · `font_test.zig` · `make_initrd.sh`)는 0줄 바뀐다. CI의 terminal step에서 `ftp.gnu.org`의 100초가 빠진다.

## 배경

- 폰트는 지금 `prepare.sh` → `vendor_fonts.sh`가 `ftp.gnu.org`에서 받고 sha256을 대조한다. `terminal/vendor/`는 `.gitignore`다.
- GH-M1의 runner에서 이 다운로드가 회차마다 103 · 106 · 약 100초 걸렸다 — `container` 7분 30초 가운데 바깥 몫으로 가장 크다.
  로컬에서는 같은 URL이 3초, `ftpmirror.gnu.org`가 2초다. runner와 GNU 서버 사이의 일이라 미러가 runner에서 나을지는 모른다.
- 폰트는 바이트 하나까지 고정된 입력이다. `font_test.zig`의 기대값 표가 이 버전의 실측이고, `vendor_fonts.sh` 머리 주석이 "다른
  파일이 조용히 들어오면 표가 통째로 틀어진다"고 적어 sha256을 대조하는 이유로 삼았다. 바뀌지 않는 입력을 매번 네트워크에서
  받는 것보다 저장소가 들고 있는 편이 그 성질에 맞다 — 바꾸면 commit의 diff에 보인다.

## 착수 전에 확인한 것

2026-10-31, HEAD `1c4f02b`.

1. 파일: `terminal/vendor/fonts/unifont.otf` 5,321,400바이트(5.3MB), sha256 `26071c5a…`(= `vendor_fonts.sh`의 `SHA256`).
   `gzip -9`로 1,308,617바이트 — git pack에 더해지는 크기는 이쯤이다. 지금 `.git`은 48MB, pack 17.06MiB.
2. 읽는 자리는 셋이고 모두 상대 경로 `vendor/fonts/unifont.otf`다.
   - 게스트 terminal `main.zig`(`App.open`) — initrd 안의 `vendor/fonts/`를 읽는다. 호스트 경로가 아니다.
   - `font_test.zig` — `terminal/`에서 도는 `zig build test`가 읽는다(`build.zig` 253행 주석).
   - `kernel/make_initrd.sh:179` — `cp ../terminal/vendor/fonts/unifont.otf "$WORKDIR/vendor/fonts/unifont.otf"`.
   경로를 그대로 두면 셋 다 0줄이다.
3. 받는 자리는 `terminal/prepare.sh`의 `./vendor_fonts.sh` 한 줄이다. 그 밖에 이름이 나오는 곳은 주석과 도움말 — `check.sh:10`
   (`terminal/vendor  stb_truetype.h + unifont`), `Makefile:88`(`vendor 셋(stb_truetype · ghostty lib-vt · unifont)`).
4. 라이선스: SIL OFL 1.1과 GNU GPL v2+(Font Embedding Exception)의 이중(`docs/decisions/project_font_selection.md`). 배포 tarball
   `unifont-17.0.03.tar.gz` 안에 `OFL-1.1.txt` · `COPYING`이 있다. OFL은 폰트를 재배포할 때 저작권 고지와 라이선스를 함께 두라고
   한다 — 공개 저장소에 올리는 것이 재배포다.
5. `.gitignore`의 `terminal/vendor/`는 디렉터리째 무시한다. git은 무시된 디렉터리 안의 파일을 `!`로 되살리지 못한다 —
   `terminal/vendor/*`로 바꾸고 `!terminal/vendor/fonts/`를 둬야 한다.

## 결정

### 결정 1. 자리는 그대로 `terminal/vendor/fonts/`

새 자리(예: `terminal/fonts/`)로 옮기면 "받은 것"과 "커밋한 것"이 디렉터리로 갈린다. 그 대가는 `font_test.zig` · `make_initrd.sh`의
경로와 주석 몇 곳이고, 게스트의 경로(`main.zig`)는 initrd 안이라 어차피 그대로다. 그대로 두면 코드 0줄이고, 섞이는 것은
`.gitignore` 두 줄과 `README` 한 장이 설명한다. 그대로 둔다.

`.gitignore`:

```
terminal/vendor/*
!terminal/vendor/fonts/
```

`terminal/vendor/` 아래의 `stb_truetype.h` · `stb_image.h`는 계속 무시되고 받는다.

### 결정 2. 폰트 옆에 `OFL-1.1.txt`와 `README`

- `OFL-1.1.txt` — 배포 tarball의 원문 그대로. 이중 라이선스 가운데 OFL로 재배포한다(GPL의 `COPYING`은 두지 않는다 — 하나로
  충분하고, OFL이 폰트에 맞춘 것이다).
- `README` — 출처 URL(`https://ftp.gnu.org/gnu/unifont/unifont-17.0.03/unifont-17.0.03.otf`), 버전, sha256, 라이선스, 그리고
  "올릴 때는 `font_test.zig`의 표를 다시 잰다". `vendor_fonts.sh` 머리 주석의 내용(왜 unifont인가 · 왜 버전을 고정하나)이 이리
  온다.

### 결정 3. `vendor_fonts.sh`를 지운다

sha256 대조가 지키던 것("다른 파일이 조용히 들어온다")은 이제 git이 지킨다 — 파일이 바뀌면 `git status`와 diff에 보인다. 대조만
하는 스크립트로 남기는 길도 있지만, 커밋된 파일을 매번 해시하는 것은 git이 이미 하는 일이다. `prepare.sh`에서 그 줄을 지우고,
`check.sh:10` · `Makefile:88`의 글을 고친다. sha256은 `README`에 남아 사람이 대조할 때 쓴다.

### 결정 4. 검증 — 루트 게이트와 CI 한 회차

`prepare.sh`와 `.gitignore`는 게이트의 입력이다. 확인은 셋.

1. 깨끗한 사본(`git archive`)에서 `cd terminal && ./prepare.sh && zig build test` — 폰트를 안 받고 PASS. 받는 줄(`Downloading …
   unifont`)이 없어야 한다.
2. push 뒤 CI — `terminal prepare and test` step의 시간이 GH-M1의 3분 28초에서 얼마나 주는지. 로그에 `ftp.gnu.org`가 없어야 한다.
3. 루트 게이트 1회(약 10분). 폰트 바이트가 같으므로 화면 판정이 하나도 안 바뀌어야 한다 — verify 줄 전부 `ok`.

mutation은 하지 않는다. 바뀐 것이 "어디서 오나"뿐이고 바이트는 같다 — 폰트가 틀어지면 `font_test`가 잡는다는 것은 TF 때 이미
보였다.

## 위험

1. 저장소가 커진다. pack에 약 1.3MB(지금 17MB의 8%). 폰트를 올릴 때마다 한 벌씩 쌓인다 — unifont는 해마다 몇 번 나오지만 우리는
   표를 다시 재야 하므로 자주 올리지 않는다.
2. 이미 받은 사본이 있는 작업 트리. 다른 clone이 pull하면 git이 그 무시된 파일을 덮는다 — 막히지 않는다(design을 쓰며 빈
   저장소 둘로 재현: `v/` → `v/*` + `!v/f/`로 바꾸고 `v/f/x`를 더한 commit을, 같은 무시된 파일이 있는 clone이 pull해 exit 0 ·
   `git status` 깨끗). 바이트가 다른 파일이 있었다면 그것이 조용히 덮인다 — 그것이 맞는 답이다.
3. ISO · initrd 안에는 폰트만 들어가고 라이선스 원문은 안 들어간다. 이번 일 전부터 그랬다(비목표 1).

## 비목표

1. initrd · ISO에 `OFL-1.1.txt`를 싣는 것. 게스트에 들어가는 다른 것들(Debian 패키지 · firmware)의 라이선스와 함께 한 번에 볼 일이다.
2. stb 두 헤더 · ghostty tarball을 저장소에 넣거나 sha256을 더하는 것. GH-M1이 남긴 다른 후보다.
3. 폰트 버전 올리기.

## Milestone

- FR-M0 — 위 결정 전부. Task 둘.
  1. 폰트 · `OFL-1.1.txt` · `README` 커밋, `.gitignore`, `vendor_fonts.sh` 삭제, `prepare.sh` · `check.sh` · `Makefile`의 글.
     깨끗한 사본에서 확인 1.
  2. push → CI(확인 2) → 루트 게이트(확인 3) → 문서와 닫기.

## 닫을 때(lead의 몫)

- 이 design의 `Status:`, `docs/guides/completed.md`의 한 행.
- `docs/decisions/project_font_selection.md`에 "FR-M0부터 저장소 안" 한 줄, `docs/decisions/project_github_actions.md`의 다음 후보에서
  "unifont 미러" 지우기. 새 기억 파일은 만들지 않는다(작은 일이다) — `MEMORY.md`의 font 줄을 고친다.
- `HANDOFF.md`. 소개 페이지에는 안 넣는다(내부 작업).

## 관련

- `docs/specs/2026-10-30-tars-github-actions-design.md` GH-M1 위험 9 — unifont 100초.
- `docs/decisions/project_font_selection.md` — 왜 unifont인가, 라이선스.
- `terminal/vendor_fonts.sh` — 지워지는 파일. 머리 주석이 `README`로 옮겨 간다.
