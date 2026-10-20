---
name: project_build_version
description: "시스템 안의 버전 표시 Build Version(BV-M0, 2026-10-20). 원천은 저장소 뿌리 VERSION 한 줄이고 init/build.zig가 git에 물어 태그 그대로 · clean이면 맨 <ver>, 아니면 +<sha>(-dirty)를 붙인다. tars-config version과 부팅 첫 줄 (TARS <ver>)이 한 build option에서 나온다. 컨테이너 git 2.47의 diff는 --no-optional-locks여도 .git/index를 쓴다 — dirty는 status로 묻는다. tag가 make iso보다 먼저다"
metadata:
  type: project
---

# Build Version (BV)

HANDOFF의 TODO에서 사용자가 골랐다(2026-10-20): 받은 사람이 자기 ISO가 몇 버전인지 알 길이 없었다. 설계는
`docs/specs/2026-10-20-tars-build-version-design.md`, plan은 `docs/plans/2026-10-20-tars-build-version-bv-m0.md`.

## 결정

- 원천은 `VERSION` 한 줄 + git 꼬리표(사용자가 셋 중 골랐다 — 태그만 · 파일만은 버렸다).
- 글자: HEAD == `v<VERSION>`이고 추적 파일이 clean이면 `0.1.0`, 아니면 `0.1.0+<sha7>`, 고친 데가 있으면 `-dirty`.
  git을 못 쓰면(`.git` 없음) `VERSION` 그대로. dirty 물음이 실패하면 dirty로 친다.
- 값은 `build_info` options 모듈 하나로 init과 tars-config에 같이 간다. tars-install · tars-service에는 안 붙였다.
- 명령은 `tars-config version` · `--version` · `-V`(stdout `TARS <ver>`), `help` 첫 줄에도 같은 글자.
- 부팅 로그는 새 줄이 아니라 첫 줄 끝 — `tars-init: starting as PID 1 (TARS <ver>)`. 이 줄을 보는 곳(power · tools 체인,
  release smoke)이 모두 부분 일치라 그대로 맞는다.
- 게이트는 CP 체인 부팅 1. 꼬리표 규칙은 셸로 다시 짓지 않고 화면 글자와 로그 괄호 안이 같은지만 본다 — 규칙은
  `version_test`가 본다.

## 함정

- 컨테이너의 git 2.47.3에서 `git diff --quiet HEAD`는 `--no-optional-locks`를 붙여도 매번 `.git/index`를 다시 썼다(mtime으로
  잼). `git --no-optional-locks status --porcelain --untracked-files=no`는 안 쓴다. 호스트 git은 그 뒤 다시 안 써서 번갈아
  쓰기는 없었다.
- 컨테이너는 root인데 `safe.directory` 없이도 저장소를 읽었다(OrbStack이 주인을 `dp`로 보인다). 그래도 `-c safe.directory=*`를
  둔다 — 거절되면 꼬리표가 조용히 사라진다.
- 버전이 태그에 기대므로 release는 VERSION 커밋 → tag → `make iso`다(`project_release`의 절차).
- 게이트 이미지는 언제나 `-dirty`다(편집 중에 돌린다). 커밋 뒤의 이미지는 `+<sha>`다.

## 실측

- `git status` 0.05~0.15초, 캐시 적중 `zig build` 0.1초 안팎 — 체인마다 다시 물어도 비용이 없다.
- 루트 게이트 1회차: 20/22, PM-M1 · UT-M3가 병렬 레인의 initrd 다시 조립 경합으로 빨갰다(lessons "이월 숙제" BV).
  2회차 22/22 PASS(prebuild 285초 + 레인 328초).

관련: [[project_release]], [[project_gate_chain_composition]]
