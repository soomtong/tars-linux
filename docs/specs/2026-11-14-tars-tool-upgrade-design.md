# TARS Tool Upgrade — Design

접두사: TU

Date: 2026-11-14
Status: 닫힘(2026-11-14, TU-M0 — 체인 `devtools` PASS). plan은 `docs/plans/2026-11-14-tars-tool-upgrade-tu-m0.md`.

계기: 0.2.2를 낼지 묻는 자리에서(2026-11-14) TP design 결정 3("개발 도구의 판을 올리는 것은 버전을 낼 때 한 번")이 이번 판의 일로
떠올랐다. 사용자: "이번 판올림은 각각의 포함되는 유틸리티 랭귀지 버전을 업그레이드 하는 것으로 의미를 삼으면 되겠다." 이어서 "잠깐
외출해야 되니까 모든 결정을 위임합니다" — 아래 결정은 lead가 내렸다.

관련 문서: TP design(결정 1 출처의 순서, 결정 3 판 올리기) · OD design(같은 날의 odin · rust 1.100.0) · `measurements.md` 103(TCG는
AVX2를 못 잡는다 — 받을 때 `objdump`로 본다) · 기억 `project_release`.

## 확인 (2026-11-14)

1. GitHub 릴리스로 받는 69줄을 각 저장소의 latest와 대조했다(`gh api`). 판이 다른 것은 아래 결정 1의 열여섯과 duckdb · mitos ·
   python-build-standalone · ffmpeg(BtbN)이다.
2. 나머지 upstream: zig 0.17.1 · erlang OTP-29.1.2 · docker 29.9.3 · sqlite 3.54.1은 최신이다. go 1.27.4(go.dev JSON), node 26.13.1
   (26 줄의 최신 — 27은 alpha뿐).
3. debian · vendor-repo 줄은 trixie 컨테이너에 네 저장소를 붙여 `apt-cache policy`의 Candidate와 대조했다 — 다른 것은 postgresql-18
   (`18.6-1.pgdg13+2` → `18.7-1.pgdg13+2`) 하나다.
4. sha256은 GitHub이 자산마다 내는 digest, go.dev의 JSON, nodejs.org의 `SHASUMS256.txt`에서 받았다. 받은 파일과 다시 대조하는 것은
   build.sh다(`fetch_checked`).

## 결정

### 결정 1 — 올리는 것(열여섯 + 패키지 하나)

| 묶음 | 도구 |
|---|---|
| base | cmake 4.4.5 → 4.5.0 |
| lang-native | go 1.27.3 → 1.27.4 (rust 1.100.0 · odin은 OD-M0) |
| lang-script | cyber 0.4.9 → 0.4.10 · luau 0.745 → 0.747 · node 26.13.0 → 26.13.1 (janet은 결정 2) |
| util | ast-grep 0.51.2 · uv 0.13.8 · dua-cli 3.0.3 · hugo 0.170.0 · lazygit 0.66.3 · fzf 0.75.0 · leaf 1.29.3 · fd 10.5.2 · tree-sitter 0.27.2 |
| editor | ttt 1.11.0 → 1.12.1 |
| container | docker buildx 0.38.2 → 0.39.0 |
| server | postgresql-18 18.7, 그리고 `systemd-standalone-sysusers` · `systemd-standalone-tmpfiles`(결정 4) |

cci는 v0.7.2가 최신이라 그대로다(사용자가 cci · cyber를 짚었다).

### 결정 2 — 올리지 않는 것

- duckdb 2.0.0: CLI가 x86-64-v3로 빌드돼 맥북 에어 2011에서 서지 않는다(TP-M8의 결정 그대로).
- mitos 0.1.3 → 0.2.1: 주 편집기이고 폭이 크다. 바뀐 것을 읽고 `runtime/grammars`의 크기를 다시 재는 일(`carryover.md` LD 절)과 함께
  따로 한다.
- python-build-standalone 20261110: 판이 3.15.2 그대로인 다시 빌드다. 판올림의 뜻(판이 바뀌는 것)에 안 든다.
- janet 1.43.0: 결정 3에 걸렸다 — 배포 실행 파일이 AVX2 · BMI2(`shlx` 288)를 `cpuid` 분기 없이 인터프리터 곳곳(`janet_loop_fiber` 등)에서
  쓴다. 1.42.1은 둘 다 0이었다. Sandy Bridge에서 `Illegal instruction`이다. manifest에 한 줄로 남겼다.
- ffmpeg(BtbN): manifest의 규칙대로 월말 빌드에 고정한다 — 지금 것(2026-10-31)이 가장 최근의 월말이다.

### 결정 3 — 받을 때의 CPU 수준

새로 받는 실행 파일 가운데 `%ymm`(AVX/AVX2) · `shlx`(BMI2)를 쓰는 것을 `objdump -d`로 센다(`measurements.md` 103). 옛 판보다 늘었거나
옛 판에 없던 것이 보이면 그 실행 파일이 CPU를 가려 고르는지(런타임 분기) 배포처의 설명으로 본다. 확인이 안 서면 그 도구는 옛 판으로
둔다.

### 결정 4 — server의 systemd는 standalone 둘로

pgdg의 `postgresql-common` 294부터 `systemd | systemd-standalone-sysusers | systemd-sysusers`와 `… -tmpfiles`를 요구한다(293은 안 했다).
고정하지 않은 의존이라 pg 판과 상관없이 다시 거두면 apt가 첫째 선택지 systemd 전체를 고르고, verify가 `libsystemd-core-257.so needs
libsystemd-shared-257.so`로 멈췄다. 둘째 선택지를 server 줄로 이름 지어 준다(각 340 · 455KB, 실행 파일 하나씩 — TARS는 안 부른다).
`postgresql-common`을 293에 고정하는 길은 버렸다 — pgdg에서 옛 판이 사라지면 다시 막힌다.

## 비목표

1. 출처를 바꾸는 것(결정 1의 순서) — 판만 바꾼다.
2. 판올림 외의 0.2.2 일(배포 모양 · release 노트)은 기억 `project_release`와 OD design의 "배포"가 맡는다.

## Milestone

- TU-M0 — 결정 1~4. plan `docs/plans/2026-11-14-tars-tool-upgrade-tu-m0.md`.
