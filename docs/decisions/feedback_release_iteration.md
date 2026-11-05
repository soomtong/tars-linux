---
name: feedback_release_iteration
description: "0.1.4는 MacBook Air · Pro 실기 확인이 성공할 때까지 같은 번호로 거듭 낸다(2026-11-05 사용자). 낼 때마다 이전 판의 release · 원격 tag를 지우고 기록 · 노트 · 소개 페이지에 '다시 냈다'는 말이나 이전 판의 값(sha256 등)을 남기지 않는다 — 늘 처음 낸 판처럼 보이게"
metadata:
  type: feedback
---

# 같은 번호로 거듭 내기 (0.1.4)

사용자(2026-11-05): "0.1.4 버전을 다시 release 합시다. 배포도 다시 해주시구요. 다시 배포했다는 표현은 모두 제거해주세요. 이전 실패한
0.1.4 release 흔적도 없애주세요. macbook air, macbook pro 테스트가 성공하기 전까지 0.1.4 버전의 반복 배포가 계속 있을 예정이니
참고해주세요."

Why: 0.1.4는 맥 두 대에서 실기로 고쳐 가는 중이다. 받는 사람에게는 "지금의 0.1.4" 하나만 의미가 있고, 이전 판의 해시나 "다시 냈다"는
설명은 혼란만 준다.

How to apply:

- 절차는 [[project_release]]의 1~7 그대로다. 다른 점은 앞뒤뿐이다 — 로컬 tag를 새 커밋으로 옮기고(`git tag -d` → `git tag -a`) `make iso` ·
  smoke를 먼저 통과시킨 뒤에야 `gh release delete v0.1.4 --yes` · `git push origin :refs/tags/v0.1.4` · tag push · `gh release create`.
  smoke가 실패하면 바깥의 판이 그대로 남는다.
- release 노트 · `project_release.md`의 0.1.4 절 · `HANDOFF.md` · 소개 페이지(`data.js`)에는 지금 판의 값만 둔다. "다시 냄", "첫 판",
  이전 sha256을 쓰지 않는다. 커밋 메시지도 `re-release`를 쓰지 않는다(예: `Release record: 0.1.4 values`).
- 이미 push된 커밋 메시지에 그런 말이 남았으면 메시지만 고쳐 force push한다(사용자 승인, 2026-11-05). tree가 같으므로 tag를 새 hash로
  옮겨도 올린 ISO는 그대로 맞다 — `git rev-parse v0.1.4^{tree}`로 본다.
- 실기 확인이 성공해 0.1.4를 굳히면 이 기억은 닫는다(다음 번호부터는 평소 절차).
