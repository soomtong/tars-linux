# GU-M0 — ghostty vt-1.0.1

Date: 2026-11-12
Design: `docs/specs/2026-11-12-tars-ghostty-vt-1-0-1-design.md`
Status: 끝났다(2026-11-12).

## 착수 전에 확정한 것

design의 확인 1~8(HEAD `2b484ea`)과 결정 1~3. 우리 코드는 안 바뀐다(확인 2). glibc로 돌리기(결정 2)는 이 milestone에 없다.
판을 내는 일(결정 3 — 다음 판)도 이 milestone 밖이다. 컨테이너 이미지 · Zig는 그대로다(0.17.1, GV-M0).

## Task 1 — ghostty vt-1.0.1 (commit 하나)

- `terminal/vendor_libghostty_vt.sh`
  - 주석: `# 태그 vt-1.0.1(libghostty-vt 1.0.1, GU-M0). …`(뒤 문장은 그대로).
  - `GHOSTTY_SHA="108cacb17ed8990840cd14abfce43d8ed8503ca1"`.
  - `GHOSTTY_SHA256="2c276d3e62cb15fb38f0d7f621f199029d1d4df86538096c6bec2a107cad7159"`.
  - 세 줄 바뀜, 지우는 줄도 세 줄이다 — `git diff | rg '^-'`로 그 셋만인지 본다.
- VS-M0 규칙: tarball을 두 번 받아 sha256이 같고, 푼 트리가 태그의 트리와 `diff -rq` 0인지 본다. 태그의 트리는 scratchpad에서
  `git init` · `git fetch --depth 1 https://github.com/ghostty-org/ghostty refs/tags/vt-1.0.1` · `git archive FETCH_HEAD`로 만든다
  (`_study/ghostty`는 얕은 clone이라 태그가 없을 수 있다).
- `terminal/ghostty-src`는 트리가 있으면 다시 안 받는다(`prepare.sh:15`) — 지우고 `make terminal`로 다시 받는다. 지우기 전에
  `rg -o 'lib_version = "[^"]*"' terminal/ghostty-src/build.zig`가 `1.0.0-dev`인지 보고, 받은 뒤 `1.0.1-dev`인지 본다.
- commit 메시지: `GU-M0: ghostty vt-1.0.1`.

## Task 2 — 검사

1. 컨테이너에서 terminal `zig build test`가 89/89 단계(design 확인 2와 같아야 한다). init은 ghostty를 안 쓰므로 돌리지 않는다.
2. `make quick` 초록.
3. 게스트용 `terminal`의 모양이 같은지 — `file`(dynamically linked) · `readelf -d`의 `NEEDED` 여섯 · `nm`의 `t memset` · `t memcpy` ·
   `t memmove`가 그대로다(design 확인 8 — 1.0.1이 우리 root에 아무것도 안 넣는다는 확인 7을 바이너리로 본다). 크기를 GV-M0 뒤 값과 함께 적는다.

## Task 3 — 루트 게이트

`make gate`(33체인). 지난 판은 34분 51초(`out/gate-logs/20261111-162704`)였다 — 실행 전에 알린다. 이미지가 같고 묶음 stamp도 같아
개발 도구 묶음은 다시 안 구워진다(prebuild가 짧다).

볼 것:
- 판정 글자를 바꿀 체인은 없다고 본다(design 결정 1). 빨간 체인이 나오면 그 체인의 로그부터 — 1.0.1의 resize · scrollback 수정이
  화면 모양을 바꿨을 수 있는 자리는 pane resize를 하는 체인(WP 계열)과 scrollback을 올려 보는 체인이다.
- DC-M2 boot 7의 4초 여유는 호스트가 바쁘면 모자란다(HANDOFF 다음 할 것 4) — 그 체인 하나만 빨갛고 그 줄이 시간이면 단독으로 다시 돌린다.

## Task 4 — 닫기

- 이 plan의 `결과` 절(숫자: tarball 대조, 89/89, 바이너리 모양 · 크기, 게이트 판 수 · 시간 · 로그 자리).
- design `Status:` 닫힘, `docs/guides/completed.md` 표 끝 한 행, 기억 하나(`docs/decisions/`)와 `MEMORY.md` 한 줄 — 기억에는 design 확인
  7 · 8(1.0.1의 glibc 돌리기가 Zig 모듈로는 안 온다, 우리 바이너리는 대상 조건을 갖췄다)과 결정 2의 "켜기 전에 실기에서 잰다"를 남긴다.
  `reference_ghostty_source`의 "지금 `3d07ef9`"는 낡은 글자라 `vt-1.0.1`(`108cacb`)로 고친다.
- 소개 페이지: 다음 판을 낼 때 함께 고친다(사용자가 치는 것은 안 바뀐다 — `docs/help/*.md`도 그대로).
- `HANDOFF.md`.

## 결과

commit 하나: `44a986e`(ghostty vt-1.0.1). plan과 다른 자리는 없다.

1. Task 1: tarball을 두 번 받아 sha256이 같고(`2c276d3e…7cad7159`), 태그를 얕게 fetch한 `FETCH_HEAD`가 `108cacb`(design 뒤로 안 옮겨졌다),
   푼 트리와 `git archive`가 `diff -rq` 0. 지우기 전 `lib_version` `1.0.0-dev` → 받은 뒤 `1.0.1-dev`, 스크립트의 `sha256sum -c` OK,
   저장소에 풀린 `ghostty-src`도 태그 트리와 `diff -rq` 0. `make terminal` 121초.
2. Task 2: 컨테이너 terminal `zig build test` 89/89 단계, `make quick` PASS. 게스트 `terminal`은 dynamically linked · `NEEDED` 여섯 ·
   `nm`의 `t memset` · `t memcpy`(`memcpyFast`) · `t memmove` 그대로(design 확인 7을 바이너리로 봤다). 크기 15,316,112 → 15,631,576 B
   (+315,464 B, +2.1%) — 앞 값은 기록에 없어 scratchpad 사본에 vt-1.0.0을 끼워 같은 맨 `zig build`(`guest-optimize` 기본 ReleaseSafe)로 쟀다.
3. Task 3: 루트 게이트 33/33 첫 판 PASS(35분 33초 — prebuild 374초 + lanes 1,618초, 회차 33개 모두 `cut log lines A=0 B=0 C=0`,
   `out/gate-logs/20261112-073112`). devtools 체인(TP-M1) 875초, DC-M2 147초. 판정 글자를 바꾼 체인은 없다.
