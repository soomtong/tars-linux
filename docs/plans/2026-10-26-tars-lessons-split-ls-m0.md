# LS-M0 — `lessons.md`를 허브와 네 파일로 나눈다

Date: 2026-10-26
Design: `docs/specs/2026-10-26-tars-lessons-split-design.md` 결정 1 ~ 6
Status: plan — 구현 전.

## 누가 무엇을 하나

lead가 직접 넣는다. 옮기기는 손으로 자르지 않고 `sed -n` 범위로 뽑는 스크립트(`/tmp/ls-split.sh`, 저장소 밖)로 한다 — 범위가 이 plan에
적힌 숫자 그대로 쓰이게. Task마다 commit 하나다. 게이트는 돌리지 않는다(design 결정 5).

| Task | 무엇을 | 검사 |
|---|---|---|
| 1 | 새 파일 넷을 뽑고 허브를 줄여 표를 넣는다 | 결정 4 (a) ~ (d), `git diff --stat`의 경로 |
| 2 | `CLAUDE.md` · `README.md`의 lessons 줄 | `git diff` 읽기 |
| 3 | 닫기 — design `Status:` · completed · 기억 · `MEMORY.md` · `HANDOFF.md` | `Read`로 대조 |

## 착수 전에 확정한 것

1. 기준 파일은 `git show 9dca7d3:docs/guides/lessons.md`(1,736줄, 끝 개행 하나)다. 아래 범위는 그 파일의 줄 번호다.

   | 새 파일 | 제목 줄 | 본문 범위 | 덧붙는 꼬리 |
   |---|---|---|---|
   | `lessons.md`(허브) | — | 1 ~ 419 | 표 절(아래 3) |
   | `measurements.md` | 421 | 422 ~ 915 | — |
   | `dead-ends.md` | 917 | 918 ~ 1167 | — |
   | `carryover.md` | 1169 | 1170 ~ 1291 | 1703 ~ 1716(IP-M2 · TR-M2) |
   | `key-files.md` | 1293 | 1294 ~ 1700 | 1718 ~ 1736(감독 루프 · ghostty) |

   떨어지는 줄은 절 사이의 빈 줄 일곱(420 · 916 · 1168 · 1292 · 1701 · 1702 · 1717)뿐이다. 꼬리를 붙일 때 앞에 빈 줄 하나를 넣는다.

2. 제목 수준(design 결정 2 (a)). 새 파일의 첫 줄은 제목 줄에서 `#` 하나를 뺀 것이다. 본문의 `### `는 `## `로 — 대상은 1130
   (dead-ends) · 1300 · 1315 · 1427 · 1527 · 1668(key-files) 여섯 줄이고, 코드 블록 안에는 `### `가 없다(design 확인 2). 꼬리의
   `## `는 그대로다. measurements · carryover 본문에는 `### `가 없다.

3. 새 파일의 머리말(design 결정 2 (b)). 제목 밑 빈 줄 하나, 그리고 이 두 줄, 빈 줄 하나, 본문.

   ```
   `docs/guides/lessons.md`(허브)에서 2026-10-26에 떼어 냈다(LS-M0). 규칙 — 줄 번호를 적지 않는다, 낡은 항목은 고치거나
   지운다, 서브프로젝트 하나에만 해당하는 것은 그 design에 — 은 허브의 것을 따른다.
   ```

   `measurements.md`에만 한 줄을 더한다 — "번호는 옮기기 전과 같다. 다른 문서의 `lessons N` · `lessons 실측 N`은 이 파일의 N번이다."

4. 허브(design 결정 2 (c) · 3). 1 ~ 15줄의 머리말에서 바뀌는 것 — 머리 단락의 "이 문서에는 … 하는 것만 둔다"를 "이 문서와 아래 표의
   네 문서에는"으로, 규칙 둘째의 "이 문서에"를 "이 다섯 문서에"로, 규칙 넷째 "새 항목은 성격에 맞는 파일에 — 실측은 `measurements.md`,
   … 게이트 운영과 범용 명령만 여기에"를 더한다(그래서 "규칙 셋"이 "규칙 넷"이 된다). 그리고 규칙 바로 밑, `## 게이트를 돌리고 읽는 법`
   앞에 `## 옮긴 절 (2026-10-26, LS-M0)` 표 — 열은 옛 절 이름(지난 문서가 인용한 글자 그대로) · 새 파일 · 그 안의 `## ` 제목.

5. 확인 명령(design 결정 4). `/tmp/ls-check.sh`로 묶는다. `norm`은 `sed -E 's/^#+ //'`와 빈 줄 빼기다.

   - (a) `comm -3 <(old | norm | sort) <(new5 | norm | sort)` — 왼쪽 칸(옛 쪽에만)은 머리말 4의 바뀐 줄뿐, 오른쪽 칸(새 쪽에만)은 머리말 3 ·
     4의 줄과 표뿐이어야 한다. 위 1 · 2 외의 줄이 나오면 멈춘다.
   - (b) 절마다 `diff <(sed -n 'A,Bp' old | norm) <(새 파일의 본문 | norm)` 빈 출력 — 본문은 머리말 다음 줄부터다. 꼬리 붙은 둘은 두 범위를
     이어 견준다.
   - (c) 허브 표의 `## ` 제목마다 그 파일에서 `rg -F -x`.
   - (d) `rg -c '^[0-9]+\. ' docs/guides/measurements.md`가 92, 첫 번호가 `1.`, 마지막이 `92.`.
   - 그리고 `git diff --stat`과 `git status --short`에 `docs/guides/` 밖의 경로가 없다(Task 1).

## Task 1: 뽑고, 줄이고, 표

1. `/tmp/ls-split.sh` — 위 1 · 2 · 3대로 새 파일 넷을 쓴다. 허브는 1 ~ 419줄로 자른다.
2. 허브의 머리말과 표를 `Edit`로 고친다(위 4).
3. `/tmp/ls-check.sh` (a) ~ (d). `git diff --stat`으로 더한 줄 · 지운 줄을 세고, 지운 쪽은 `git diff docs/guides/lessons.md | rg '^-'`가
   1 ~ 15줄의 바뀐 몇 줄과 420줄 이후 전부인지 본다.
4. commit — `Split lessons.md into a hub and four guides`. 본문에 옛 파일 `9dca7d3:docs/guides/lessons.md`과 `git blame -C -C`를 적는다.

## Task 2: 구조를 말하는 두 줄

- `CLAUDE.md` "참고"의 lessons 항목 — 허브와 네 파일을 적는다.
- `README.md` 문서 표 — lessons 줄을 허브의 설명으로 고치고 네 파일의 줄을 더한다.
- commit — `Point CLAUDE.md and README at the split guides`.

## Task 3: 닫기

- design `Status:`, `docs/guides/completed.md` 한 행, `docs/decisions/project_lessons_split.md`, `MEMORY.md` 한 줄, `HANDOFF.md`(후보 (4)
  지우기, 머리의 lessons 언급 · "이어받는 사람이 볼 것").
- 이 plan의 `Status:`와 아래 실측 절.
- commit — `Close Lessons Split: design status, memory, completed, handoff`.

## LS-M0가 실측한 것

(구현 뒤 채운다.)
