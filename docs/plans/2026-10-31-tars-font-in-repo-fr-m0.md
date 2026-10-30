# FR-M0 — unifont를 저장소 안에

Date: 2026-10-31
Design: `docs/specs/2026-10-31-tars-font-in-repo-design.md`
Status: plan

## 착수 전에 확정한 것

design의 확인 1~5에 더해, plan을 쓰며 읽은 것.

1. `vendor_fonts.sh`를 이름으로 부르는 곳은 실행 하나(`terminal/prepare.sh:19`)와 주석 둘 — `kernel/vendor_firmware.sh:10`("`terminal/
   vendor_fonts.sh`와 같은 이유다") · `terminal/src/font_test.zig:11`("vendor_fonts.sh가 그 버전에 고정하고 sha256으로 확인한다").
2. 글이 낡는 곳: `check.sh:10`(`terminal/vendor  stb_truetype.h + unifont` — 지우면 안 되는 것 목록. 이제 unifont는 추적 파일이라 그
   목록에서 빠진다) · `Makefile:88`(`vendor 셋(stb_truetype · ghostty lib-vt · unifont)`).
3. `quick_check.sh`의 shellcheck 대상이 `git ls-files '*.sh'`라 52 → 51파일이 된다. 숫자를 적은 곳은 `Makefile:139`(도움말) ·
   `docs/guides/lessons.md:440`. `completed.md`의 GH 행은 그날의 기록이라 그대로 둔다.
4. `vendor_fonts.sh` 머리 주석의 "이 경로를 읽는 곳이 다섯 군데"(make_initrd.sh · main.zig · font_test.zig · stb_truetype_main.c ·
   prepare.sh)는 `README`로 옮긴다 — 파일 이름에 버전을 안 넣는 이유다. `stb_truetype_main.c`는 이제 없는 파일이다(`fd`로
   0줄) — 옮기며 넷으로 고친다.
5. `OFL-1.1.txt`는 배포 tarball `unifont-17.0.03.tar.gz`(`ftp.gnu.org`)의 `unifont-17.0.03/OFL-1.1.txt`에서 꺼낸다. tarball의 `.sig`는
   대조하지 않는다 — 라이선스 글이고, 폰트 바이트는 sha256이 이미 맞다.

## Task 1 — 파일 넷 · `.gitignore` · 글

더하는 것:

- `terminal/vendor/fonts/unifont.otf` — 지금 작업 트리의 파일 그대로(sha256 `26071c5a97533cefdcbc6b0645e7ee279413049079f09f592b26916ca6c21bf5`를
  `git add` 전에 다시 본다).
- `terminal/vendor/fonts/OFL-1.1.txt` — 확정 5.
- `terminal/vendor/fonts/README`:

```
GNU Unifont 17.0.03 — TARS 터미널의 유일한 폰트(FR-M0, 2026-10-31부터 저장소 안).

출처    https://ftp.gnu.org/gnu/unifont/unifont-17.0.03/unifont-17.0.03.otf
sha256  26071c5a97533cefdcbc6b0645e7ee279413049079f09f592b26916ca6c21bf5
라이선스 SIL OFL 1.1(OFL-1.1.txt) — GNU GPL v2+(Font Embedding Exception)와의 이중
        라이선스 가운데 OFL로 재배포한다.

왜 unifont인가. 문턱값 렌더링(TR design 결정 4)에 쓸 수 있는 비트맵 폰트다 —
unitsPerEm이 64라 16px에서 scale이 정확히 0.25이고, coverage가 0 아니면 255뿐이라
게이트가 픽셀을 상수와 비교할 수 있다. 후보를 전부 잰 것은
docs/decisions/project_font_selection.md.

왜 버전을 고정하나. terminal/src/font_test.zig의 기대값 표가 이 버전의 실측이다.
다른 파일이 조용히 들어오면 표가 통째로 틀어지는데, 그때 나는 실패는 "글자가 좀
이상하다"라서 원인까지 멀다. 그래서 받지 않고 여기 둔다 — 바뀌면 diff에 보인다.

올릴 때. 파일을 바꾸고 이 README의 버전 · sha256을 고치고 font_test.zig의 표를
다시 잰다. 파일 이름에는 버전을 넣지 않는다 — 이 경로를 읽는 곳이 넷이다
(kernel/make_initrd.sh · terminal/src/main.zig · terminal/src/font_test.zig ·
terminal/prepare.sh의 주석).
```

바꾸는 것:

- `.gitignore`: `terminal/vendor/` → `terminal/vendor/*` · `!terminal/vendor/fonts/` 두 줄과 이유 한 줄 주석.
- `terminal/prepare.sh`: `./vendor_fonts.sh` 줄 삭제. 머리 주석의 "`../terminal/vendor/fonts/unifont.otf` 를 무조건 복사하므로"
  뒤에 "(폰트는 저장소에 있다, FR-M0)"를 더한다. 그 옆의 오타 `boot/check.ㅂsh`도 `boot/check.sh`로.
- `terminal/vendor_fonts.sh`: 삭제(`git rm`).
- `check.sh:10`: `terminal/vendor       stb_truetype.h + unifont` → `terminal/vendor       stb 헤더 둘(unifont는 fonts/ 아래에 커밋돼 있다)`.
- `Makefile:88`: `vendor 셋(stb_truetype · ghostty lib-vt · unifont)` → `vendor 셋(stb 헤더 둘 · ghostty lib-vt)`. `:139`의 `52파일` → `51파일`.
- `kernel/vendor_firmware.sh:10`: "`terminal/vendor_fonts.sh`와 같은 이유다" → "폰트(`terminal/vendor/fonts/README`)와 같은 이유다".
- `terminal/src/font_test.zig:11~12`: "vendor_fonts.sh가 그 버전에 고정하고 sha256으로 확인한다" → "폰트는 저장소에 커밋돼 있다
  (`vendor/fonts/README`)".
- `docs/guides/lessons.md:440`: `52파일` → `51파일`.

확인:

1. `git status --short`로 더해지는 것이 정확히 `terminal/vendor/fonts/` 아래 셋이고 `stb_*.h`가 안 보이는지(`git check-ignore -v
   terminal/vendor/stb_image.h`가 새 `terminal/vendor/*` 줄을 가리키는지).
2. `make quick` PASS, `shellcheck 51 files`.
3. 깨끗한 사본(`git archive` 뒤 HEAD — commit 뒤에 한다)의 컨테이너에서 `cd terminal && ./prepare.sh && zig build test` PASS, 로그에
   `unifont`를 받는 `Downloading` 줄이 없다.

commit 하나.

## Task 2 — CI · 루트 게이트 · 닫기

- push → `gh run watch`. `terminal prepare and test` 시간을 GH-M1의 3분 28초와 견주고, 로그에 `ftp.gnu.org`가 0인지.
- 루트 게이트 1회(약 10분, `/tmp/gate.log`). 22/22, verify 줄 전부 `ok`.
- 문서: design `Status:` · `completed.md` 한 행 · `project_font_selection.md`에 한 줄 · `project_github_actions.md`의 다음 후보에서
  "unifont" 지우기 · `MEMORY.md`의 font 줄 · `HANDOFF.md`(GH-M1 항목의 "남은 바깥 몫" 고침, 52파일 → 51).
- commit 하나(닫기).

## 결과

(Task마다 채운다)
