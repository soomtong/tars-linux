---
name: feedback_release_iteration
description: "0.1.4는 MacBook Air · Pro 실기 확인이 성공할 때까지, 0.2.1 기본 판은 cyber 새 판이 나올 때마다(2026-11-12) 같은 번호로 거듭 낸다(2026-11-05 사용자). 낼 때마다 이전 판의 release · 원격 tag를 지우고 기록 · 노트 · 소개 페이지에 '다시 냈다'는 말이나 이전 판의 값(sha256 등)을 남기지 않는다 — 늘 처음 낸 판처럼 보이게"
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

# 0.2.1 기본 판을 cyber 판에 맞춰 바꾸기 (2026-11-12)

사용자(2026-11-12): cyber 0.4.7을 받은 뒤 "0.2.1 배포판(base version devlayer included) 지금 빌드한 버전으로 교체" → "교체하고
교체한 흔적을 내지 마. 0.2.1은 아무도 사용하고 있지 않아." → "사이버랭 버전업을 더 하면 이 작업을 한 번 더 할게."

Why: cyber(soomtong/cyber)는 사용자가 직접 관리하는 언어라 판이 자주 나온다. 0.2.1을 받은 사람이 아직 없으니 번호를 올리기보다
지금의 0.2.1 하나를 최신 cyber로 맞춰 두는 편이 낫다.

How to apply (cyber 판이 또 나오면):

- 받기 · 대조 · manifest 세 줄 · `make quick` · `make check CHAIN=devtools`는 평소대로 한다(HANDOFF의 cyber 절들). 체인이 PASS여야 다음으로 간다.
- 커밋(`Bump cyber <판> in the dev layer manifest`) → 로컬 태그를 그 커밋으로 옮긴다. 메시지는 원래 것을 다시 쓴다
  (`git tag -l --format='%(contents)' v0.2.1`을 파일로 → `git tag -d` → `git tag -a -F`).
- 체인 빌드는 커밋 전의 dirty 트리에서 구웠으므로 `rm -f devlayer/build/*.stamp && make dev-layers` 뒤에
  `make iso ISO_LAYERS="<묶음 열하나>"`. 2GiB 한도(0.2.1은 여유 몇 MB)를 넘지 않는지 크기를 본다. smoke는 [[project_release]] 절차 4.
- 주의(2026-11-12): `main`에는 0.2.1 뒤의 일(GU-M0 ghostty vt-1.0.1, LD-M0 묶음 중복 지우기 · emacs 빼기 · fakesteak)이 들어 있다. 이 위에서
  지으면 cyber만이 아니라 그것들도 0.2.1에 실린다 — cyber 새 판은 다음 판(0.2.2)에 싣거나, 0.2.1로 내려면 태그 커밋에서 가지를 내어 cyber만
  올린다. 어느 쪽인지 사용자에게 묻는다.
- 바뀌는 것은 기본 판 하나다(cyber는 `lang-script`). barebone · fakesteak 자산은 그대로 두고 `SHA256SUMS`의 기본 판 줄만 바꾼다.
- 바깥: 원격 태그를 새 커밋으로 옮기고, 기본 판 ISO와 `SHA256SUMS`를 같은 release에 덮어 올리고(`--clobber`), 노트의 cyber 판 글자를
  고친다. 받아서 `shasum -c`.
- 기록에는 지금 판의 값만 둔다: `project_release.md`의 description · 0.2.1 표(tag · 크기 · sha256) · 본문의 cyber 판, `HANDOFF.md`의 태그 줄,
  `gh-pages`의 `data.js` sha256. "교체", "다시 냄", 이전 sha256은 쓰지 않는다.
- 함정: 묶음 · ISO를 굽는 동안 추적 파일을 고치지 않는다. 출처 기록이 굽는 순간의 `git describe --dirty`라 2026-11-12에 기억 파일을
  고친 몇십 초 사이 `docs` · `editor`가 `v0.2.1-dirty`로 구워졌다(그 둘의 stamp만 지우고 다시 구웠다). 기록은 빌드가 끝난 뒤 고치고,
  올리기 전 `unsquashfs -cat devlayer/build/<묶음>.sqfs usr/share/tars/layers/<묶음>`으로 열하나를 본다.
