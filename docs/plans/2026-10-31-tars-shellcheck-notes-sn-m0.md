# SN-M0 — shellcheck note 46을 0으로, note도 판정

Date: 2026-10-31
Design: `docs/specs/2026-10-31-tars-shellcheck-notes-design.md`
Status: 끝났다(2026-10-31)

## 착수 전에 확정한 것

design의 확인 1~5에 더해, plan을 쓰며 읽은 것.

1. `dictation/check.sh:560`의 SC2016은 559행에서 시작한 `printf … \` 명령의 이어진 줄이다. 지시자는 명령이 시작하는 559행 위에
   단다(지시자는 다음 명령 하나에 걸린다). 551행은 그 줄 자체가 명령이다.
2. 대조할 기준: 루트 게이트는 시작에 `out/`을 지우므로 지난 회차(`out/gate-logs/20261030-154626`)를 scratchpad로 옮겨 두었다.
   `render` 체인의 `=== typing printf …` 줄 열 개가 `lane-6.out`에 있다 — 고친 뒤 회차의 같은 줄과 바이트로 비교한다.
3. `Makefile`의 `quick` 도움말은 수준(warning · note)을 말하지 않는다 — 0줄. 고칠 글은 `quick_check.sh`의 1단계 주석,
   `docs/guides/lessons.md`의 `make quick` 주석 둘.
4. 지시자 이유는 부르는 자리를 적는다(design 위험 3) — trap은 `trap cleanup EXIT`, 콜백은 `boot_once`.

## Task 1 — 지시자 28 · 고침 18 · 판정

자리는 design 결정 2~4의 표 그대로. 파일별:

- 지시자만: `boot` · `input` · `install` · `machine` · `terminal` · `tools`의 `check.sh`(cleanup 하나씩), `net/check.sh`(cleanup +
  monitor 고침), `config/check.sh`(cleanup + 콜백 아홉 = 열), `kernel/dictation/tars-dictate`(on_int · on_term · le32 = 셋),
  `audio/probe.sh` · `dictation/probe.sh`(SC2012), `dictation/check.sh`(SC2012 하나 · SC2016 둘), `service/check.sh`(SC2016 +
  monitor 고침).
- 고침만: `check.sh`(133행), `audio/check.sh`(300행), `firewall/check.sh`(monitor), `render/check.sh`(printf 일곱 · `\\)`),
  `kernel/tq-probe.sh`(`-r`).
- 둘 다: `site/capture.sh`(tr · `\\)` 고침, SC2012 지시자 둘).
- `quick_check.sh` 1단계: `-S warning` → `-S style`, `notes=…` 두 줄 삭제, 주석의 "판정은 warning 이상 … 기준선 46"을 "판정은
  style 이상(전부). note 46을 SN-M0이 0으로 만들었다"로.

확인:

1. `git diff --stat`로 지운 줄 수가 더한 줄 수보다 작은지(지시자는 더하기만, 고침은 한 줄 바꾸기), `git diff | rg '^-'`로 지운 줄을
   전부 읽는다 — 고친 18자리와 `quick_check.sh` 말고는 없어야 한다.
2. `make quick` PASS. shellcheck가 아무것도 안 찍는다.
3. mutation: `boot/check.sh`에 `echo $LOG` 한 줄 → `make quick`이 `FAIL: shellcheck`(SC2086 note). 되돌린다.
4. `bash -n site/capture.sh`, 고친 두 줄을 scratchpad 조각으로 — `tr`가 `A`→`a`, `\\)`가 `\`와 맞는다.

## Task 2 — 게이트 · commit · CI · 닫기

- 루트 게이트 1회(약 10분, `/tmp/gate.log`). 22/22, verify 줄 전부 `ok`, `render`의 `=== typing` 열 줄이 기준과 같다.
- commit 하나(Task 1). push → `gh run watch` — `host` 초록.
- 문서: design `Status:` · `completed.md` 한 행 · `project_github_actions.md` SN-M0 단락 · `MEMORY.md` · `lessons.md` · `HANDOFF.md`.
  commit 하나(닫기), push.

## 결과

### Task 1 (`6a1e4aa`)

- `git diff --stat`: 19파일, +44 −16. 지운 16줄은 design 결정 4 표의 자리 전부(`check.sh:133`은 SC2086 · SC2116이 한 줄)이고, 더한
  44줄은 지시자 28과 그 16줄의 새 꼴이다. `git diff | rg '^-[^-]'`로 지운 줄을 하나씩 읽었다.
- design의 수 하나를 바로잡았다 — SC2329는 trap 열(cleanup 여덟 · `on_int` · `on_term`)과 `boot_once` 콜백 아홉이다(합 19는 같다).
- 지시자 이유 둘을 넣고 나서 고쳤다. wav는 mktemp가 아니라 `tars-dictate`가 짓는 `/tmp/tars-dictate.<pid>.wav`이고, capture의
  프레임은 ffmpeg가 아니라 `start_recording`이 `%05d.ppm`으로 짓는다. 이유를 적는 것이 그 자리를 다시 읽게 했다.
- `make quick` PASS, shellcheck 51파일에서 출력 0.
- mutation: `boot/check.sh` 21행에 `echo $LOG` → `SC2086 (info)`, `quick_check: FAIL: shellcheck`, rc 1. 되돌린 뒤 그 파일의 diff는
  지시자 한 줄.
- 조각(scratchpad): `bash -n site/capture.sh` ok, `tr '[:upper:]' '[:lower:]' <<<Q` → `q`, `$(echo $hits)`와 `${hits//$'\n'/ }`가
  `12 40 77`로 같다, `printf '%s\n' $S | wc -l`과 `wc -l <<<"$S"`가 셋일 때 3 · 비었을 때 1로 같다.

### Task 2

- 루트 게이트(`out/gate-logs/20261030-160610`): 22/22, 10분 4초(prebuild 301 + lanes 302초). `verify lines` 합 8115, `VERIFY_OK_LINE`
  (`on bytes=` · `ok us=`) 밖의 줄 0, `failed` 0바이트.
- `render`의 `=== typing printf …` 열 줄을 지난 회차(`20261030-154626`)와 `diff` — 같다. `audio`의 `SOF for 19 …` 줄도 같다.
  게이트 로그를 `rg`로 바로 세면 `ok` 8052 · `on` 63으로 합이 8115보다 작다 — 게이트는 `tlog`로 printk에 잘린 줄을 이어 붙여
  센다. 숫자는 게이트의 줄을 읽는다.
- CI run 41088453820(`6a1e4aa`): 두 job 초록. `host` 2분 25초, 로그 `quick_check: shellcheck 51 files` → `quick_check: PASS`.
  `container` 7분 42초.
