---
name: project_layer_dedup
description: "LD-M0(2026-11-12): base 아닌 묶음은 굽기 직전에 base와 경로 · 내용이 같은 파일을 지운다 — 그래서 묶음은 base 없이 온전하지 않다(init은 base가 못 서면 아무것도 안 얹고, make_iso는 base 없이 안 싣는다, 예외는 devlayer/standalone-bundles). emacs-nox를 뺐고 fakesteak 묶음이 기본 판에 들어갔다(자동 실행은 base가 없을 때만). 묶음 열둘, 2GiB까지 148MiB"
metadata:
  type: project
---

# 묶음 사이 중복 지우기 · emacs 빼기 · fakesteak (LD-M0)

사용자(2026-11-12): "묶음 사이 같은 파일 지우기부터 조사해줘. emacs, doom custom 잘 안쓰는거 같아. tars-agent(claude code, codex, pi 같은 것)를
만들건데 그렇게 되면 에디터는 더 안쓰게 될거야." · "기본판에 fakesteak 추가하자 심심할 때 켜두면 재밌더라." → "emacs 빼고 나머지는 권고대로 …
임플리멘테이션까지 진행해 줘. 나는 운전을 좀 할게." 결정은 lead가 정했고 LD design에 까닭이 있다.

- 지금의 모양: `devlayer/build.sh`가 verify와 묶음끼리 대조 뒤, stamp 앞에서 `base.paths`와 줄이 같은 경로를 지운다(`deduped=N`). 지운 목록이
  stamp에 들어 base가 바뀌면 다른 묶음도 다시 구워진다. `.paths`는 지우기 전의 온전한 표다.
- 묶음은 열둘이다(fakesteak이 기본 `DEV_LAYERS`와 기본 판에 들어왔다). 체인 · 문서의 묶음 수와 목록은 이름 순(editor 다음 fakesteak)이다.
- fakesteak의 첫 패널 자동 실행은 `/usr/share/tars/layers/base`(base의 출처 기록)가 없을 때만 돈다 — 기본 판은 손으로 친다, 납품 데모 판은 뜬다.
- manifest 생성기는 도구 이름이 두 번 나오면 멈춘다(`tool X again`) — 같은 도구를 두 묶음에 적는 길은 없다.
- 숫자: 묶음 1,908 → 1,762MiB, 기본 판 구성 ISO 1,992,007,680 B(0.2.1 기본 판보다 145.4MiB 작다).

Why: 0.2.1 기본 판이 2GiB까지 2.9MB였다 — 어느 묶음이든 판을 올리면 넘칠 자리였다. 겹침은 거의 다 base와의 것이었고(같은 경로 · 다른 내용 0),
editor의 겹침 107MiB는 emacs의 `libgccjit`가 끈 gcc 쪽이었다.

How to apply:

- base 없이 혼자 실릴 묶음을 새로 만들면 `devlayer/standalone-bundles`에 적는다 — 안 적으면 base와 겹친 것이 지워져 혼자서는 깨진다.
- 묶음을 더하거나 빼면 devtools 체인의 묶음 수 · `LAYERS` · lowerdir 글자 · 부팅 3의 수를 함께 고친다(LD-M0에서 두 번 빨갰다).
- 남은 것: base가 깨진 부팅은 체인에 없다, mitos 285MiB, 경로만 다른 같은 내용 32MiB — `carryover.md`의 LD 절.
- 관련: [[project_release]](배포 절차 3) · [[feedback_release_iteration]] · [[project_minimal_iso]].
