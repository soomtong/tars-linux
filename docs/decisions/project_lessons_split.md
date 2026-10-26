---
name: project_lessons_split
description: "docs/guides/lessons.md 1,736줄을 허브(게이트 운영 · 범용 명령 · 옮긴 절 표)와 measurements · dead-ends · carryover · key-files 넷으로 나눈 Lessons Split(LS-M0, 2026-10-26). 글은 옮기기만, 실측 번호 1~92 그대로, 참조하는 쪽(스크립트 주석 · decisions · 지난 plan)은 안 고치고 허브 표로 닿게, comm은 LC_ALL=C, 게이트 없음"
metadata:
  type: project
---

# Lessons Split (LS)

2026-10-24 프로젝트 점검이 남긴 둘 가운데 (4)를 사용자가 골랐다(2026-10-26). 설계는
`docs/specs/2026-10-26-tars-lessons-split-design.md`, plan은 `docs/plans/2026-10-26-tars-lessons-split-ls-m0.md`.

## 무엇을 세웠나

`docs/guides/`의 다섯 파일. 새 항목은 성격에 맞는 파일에 쓴다(허브 규칙 넷째).

- `lessons.md` — 허브. 규칙 넷, "옮긴 절" 표, 게이트를 돌리고 읽는 법, 범용 명령.
- `measurements.md` — 다시 조사하지 말 실측. 번호 1~92가 옮기기 전과 같다.
- `dead-ends.md` — 시도했으나 안 되는 접근.
- `carryover.md` — 이월 숙제 + 옛 꼬리의 IP-M2 · TR-M2.
- `key-files.md` — 핵심 파일 지도 + 옛 꼬리의 감독 루프 · ghostty 프롬프트 인젝션.

commit은 Task마다 하나 — `634e886`(옮기기) · `3819dff`(`CLAUDE.md` · `README.md`) · 닫기.

## 결정과 그 이유

- 참조하는 쪽은 고치지 않는다. 지난 plan/spec이 `lessons "핵심 파일"`을 31번 인용하고, 스크립트 주석 여섯 · decisions 다섯이
  `lessons 41` 같은 실측 번호로 가리킨다. 허브의 표 한 번과 번호 보존으로 전부 닿는다. 스크립트를 0줄 바꿨으니 게이트도 안 돌았다.
  새로 쓰는 글은 새 파일 이름으로 가리킨다.
- 글의 정리(이월 숙제의 닫힌 `[x]` 셋, 낡은 실측)는 섞지 않았다. 섞으면 "옮겼다"를 기계로 못 본다 — MS의 동작 변경 / 옮기기 분리와
  같은 이유. 각 파일이 작아진 지금 정리는 따로 할 수 있다.

## 함정

- `comm`으로 줄 집합을 견줄 때 `LC_ALL=C`를 둔다. 한글 로케일의 `sort` 순서가 `comm`의 기대와 어긋나 실제로는 양쪽에 한 번씩 있는 줄 둘이
  "새 쪽에만"으로 나왔다. 줄 집합 확인은 순서 확인(절마다 `diff`)과 함께 둔다 — 집합은 순서를 못 본다.
- `git log -L` · `blame`은 새 파일에서 끊긴다. 옛 줄의 내력은 `git blame -C -C`이고, 옛 파일은 `9dca7d3:docs/guides/lessons.md`.

## 관련

[[project_main_split]] — 옮기기만 한 것을 기계로 확인한 선례. [[project_host_checks]] — 점검의 (3).
