# GV-M0 — Zig 0.17.1 · ghostty vt-1.0.0

Date: 2026-11-10
Design: `docs/specs/2026-11-10-tars-ghostty-vt-design.md`
Status: 끝났다(2026-11-10).

## 착수 전에 확정한 것

design의 확인 1~5(HEAD `e4baa09`). 고칠 자리는 기억 `project_zig_upgrade`의 "다음에 올릴 때 고칠 자리"와 같다.

## Task 1 — `zig fmt` (commit 하나)

`zig fmt init/src/main.zig init/src/reload.zig init/src/reload_test.zig`. 공백만 바뀌어야 한다 — `git diff -w`가 비면 확인이다.
`make quick` 초록. 이 commit만으로 CI(`checks`)가 다시 초록이어야 한다.

## Task 2 — Zig 0.17.1 (commit 하나)

- `devcontainer/Dockerfile`: `ENV ZIG_VERSION=0.17.1`, `ARG ZIG_SHA256=a1546d56…ed7795`(aarch64-linux).
- `.github/workflows/checks.yml`: `ZIG_SHA256: 3581863e…e9b17a`(x86_64-linux).
- 이미지 태그가 Dockerfile 해시라 로컬에 새 태그가 없다 — `make container`가 ghcr.io에서 못 받고 굽는다. 컨테이너 안 `zig version`이 `0.17.1`.

## Task 3 — ghostty vt-1.0.0 (commit 하나)

- `terminal/vendor_libghostty_vt.sh`: `GHOSTTY_SHA="0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec"`(주석에 태그 `vt-1.0.0`),
  `GHOSTTY_SHA256="2f38f10edcc7498a91a4b02baf317f408c9808f637b341c22966b2c7522b95ea"`.
- `terminal/src/vt.zig:191`: `@alignCast(@fieldParentPtr("term", h.terminal))`, 주석 한 줄(GV design 결정 3).
- `terminal/ghostty-src`는 트리가 있으면 다시 안 받는다(`prepare.sh:15`) — 지우고 `prepare.sh`로 다시 받는다.

## Task 4 — 게이트

1. 컨테이너에서 `terminal` 빌드 · 호스트 검사(`zig build test`), init의 `zig build test`.
2. 루트 게이트 `make gate`(33체인, 지난번 1,926초). 이미지가 새것이라 개발 도구 묶음도 다시 굽는다.

## 결과

commit 셋: `695be61`(fmt) · `c759ba7`(Zig 0.17.1) · `7c853e6`(ghostty vt-1.0.0). plan과 다른 자리는 하나다.

1. Task 1: `reload.zig`는 `zig fmt`의 출력을 그대로 받지 않았다. 주석 사이에 홀로 선 원소가 앞 두 줄의 다섯 칸 격자에 맞춰지며
   `"cursor_shape"`만 세 칸 더 들여쓰였다 — 사람이 맞추면 fmt가 다시 밀어내는 자리라 CO-M1이 빨개진 이유로 읽는다. 주석 셋을 위로
   모으고 세 키를 격자 셋째 줄로 넣었다(원소 순서 · 값 그대로, fmt를 두 번 돌려도 그대로). 사용자 "can apply zig fmt? any reason?"
2. Task 2: 새 이미지(태그 `c7ba57a9ed37`)는 층 캐시로 23초에 구워졌다. 컨테이너 `zig version` = `0.17.1`.
3. Task 3: tarball을 두 번 받아 sha256이 같고, 푼 트리가 `git archive vt-1.0.0`과 `diff -rq` 0이다(VS-M0 규칙). `make terminal` 2분 16초.
4. Task 4-1: 컨테이너에서 terminal `zig build test` 89/89 단계, init `zig build test` 47/47 단계 성공.
5. Task 4-2: 루트 게이트 33/33 첫 판 PASS(33분 43초 — prebuild 363초 + lanes 1,513초, 잘린 줄 0, `out/gate-logs/20261110-130631`).
   devtools 체인(TP-M1)의 게스트 zig hello는 58초(묶음의 zig는 이미 0.17.1이었다).
