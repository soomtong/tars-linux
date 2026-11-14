# TU-M0 — 0.2.2의 도구 판올림

Date: 2026-11-14
Design: `docs/specs/2026-11-14-tars-tool-upgrade-design.md`
Status: 끝났다(2026-11-14). commit `bc48393`.

## 착수 전에 확정한 것

design의 확인 1~4와 결정 1~3. OD-M0(odin · rust 1.100.0 · `make iso-full`)의 commit 뒤에 시작한다 — 그 체인과 섞지 않는다.

## Task 1 — manifest (commit 하나)

1. `devlayer/manifest.toml`: 결정 1의 줄마다 version · url · sha256(패키지는 version). url은 옛 판의 글자만 새 판으로 바꾼 것이
   GitHub 자산 이름과 맞는지 digest 조회가 이미 봤다. 판이 박힌 다른 자리를 `rg`로 찾는다(도움말 · 체인의 기다리는 글자).
2. 검사: `make quick`, `make dev-layers`(바뀐 묶음 일곱이 다시 구워진다 — base가 바뀌면 base에 기대는 묶음도). 요약 줄의 크기 변화를 적는다.
3. 결정 3: 묶음을 푼 자리에서 새 실행 파일마다 `objdump -d | grep -c '%ymm'`과 옛 판의 같은 숫자.

## Task 2 — 체인

1. `make check CHAIN=devtools`. 판을 기다리는 글자(예: `tp-go-go1.27.3`)가 있으면 Task 1에서 함께 고친다.
2. 결과 절에 숫자.

## 결과

1. 첫 `make dev-layers`가 lang-script에서 멈췄다 — `devlayer/files/lang-script/usr/local/lib/node-26.13.0 has no tool at …`(build.sh의
   판 이름 지킴이). 디렉터리를 `node-26.13.1`로 `git mv`(npmrc 하나). 판이 박힌 files 디렉터리는 gleam · python · ruby · node 넷이다.
2. 둘째가 server에서 멈췄다 — `libsystemd-core-257.so needs libsystemd-shared-257.so`. pg 18.7 탓이 아니라 의존 `postgresql-common`이
   293 → 295가 되며 systemd를 요구한 것(design 결정 4). `systemd-standalone-sysusers` · `-tmpfiles`를 server 줄로 더해 apt가 그쪽으로
   풀었다(시뮬레이션에서 먼저 봤다). server 142MiB, systemd 없음.
3. 결정 3(objdump, 큰 ELF 셋의 `%ymm` · `shlx` 합): 열여섯 가운데 janet만 0 · 0 → 836 · 288. 나머지는 같거나 몇 개 차이 — Go로 지은
   것(go · hugo · lazygit · ttt · fzf · buildx)은 런타임의 같은 분기 코드라 숫자가 같다. janet 1.43.0은 `cpuid`가 0이고 `janet_loop_fiber`에
   159곳 — 빌드할 때부터 AVX2 · BMI2다(GCC 15.2 Ubuntu). 1.42.1로 되돌리고 manifest에 한 줄(design 결정 2).
4. 묶음 열셋 1,993,990,144 B(1,901.6MiB). 체인 `devtools` PASS(빌드 뒤 735초): go1.27.4 · node v26.13.1 · postgres 18.7 · buildx v0.39.0을
   기다리는 줄이 맞았다. cyber 349 · luau 411 · ttt 941 · cmake+ninja 2,579 · odin 10,449ms. 체인 ISO 2,139,084,800 B(2GiB까지 약 8MiB).
5. 접두사를 처음에 TR로 지었다가 Terminal Rendering(2026-08)과 겹쳐 TU로 바꿨다(commit 전 amend).
