# LI-M1 — initrd의 우리 바이너리 다섯을 `--strip-debug`한다

Date: 2026-10-26
Design: `docs/specs/2026-10-26-tars-lean-initrd-design.md` 결정 1 ~ 4 · 6 · 7
Status: plan

## 누가 무엇을 하나

lead가 직접 넣는다. 고치는 파일은 스크립트 하나와 문서 · 주석이다. commit은 Task마다 하나다.

| Task | 무엇을 | 검사 |
|---|---|---|
| 1 | `kernel/make_initrd.sh` — 도구 확인 · strip 루프 · 주석 | `make_initrd.sh` 한 번, initrd 안 다섯의 `.debug_info` 0 · 크기 |
| 2 | 주석과 문서 — `init/build.zig:23-25`, lessons "범용 명령", decisions 둘 | `git diff`로 읽기 |
| 3 | 루트 게이트, 실측, 닫기 | 22/22 |

## 착수 전에 확정한 것

1. strip은 사본이 `$WORKDIR`에 놓인 뒤 한 자리에서 한다. `cp` 다섯 줄은 안 건드린다 — 목록 `OWN_BINS`(`$WORKDIR` 기준 경로 다섯)를
   두고 루프 하나로 strip한다. `install_tool`처럼 목록을 한 곳에 둬 빼먹을 자리를 없애는 모양이다(UT-M1 결정 7). 자리는 terminal의
   `cp` · `chmod` 바로 뒤, `copy_lib_deps` 앞이다 — `copy_lib_deps`가 읽는 `NEEDED`는 strip 뒤에도 같다(`.dynamic`은 안 떨어진다).
2. 도구는 `x86_64-linux-gnu-strip`이다(LI-M0 실측 4). 없으면 sysroot 검사와 같은 모양으로 이유를 찍고 `exit 1`한다(design 위험 3).
3. 옛 주석 둘("strip은 여전히 안 한다" · "옛 주석은 …")은 LI의 문단 하나로 바꾼다. TF-M4의 판단과 그것이 뒤집힌 이유(LI-M0 실측 3)를
   한두 줄로 남기고, 실측 본문은 plan을 가리킨다. GL-M3 문단(ReleaseSafe 크기)은 그대로다.
4. lessons "범용 명령"에 넣는 것은 trace 주소를 푸는 명령 한 덩이다. 조건 — 그 로그를 낸 빌드의 `zig-out`(게이트 로그는 그 회차의 빌드,
   다시 빌드하면 주소가 바뀐다) — 을 주석에 적는다.
5. decisions는 `project_gate_chain_composition`의 strip 문단(77 ~ 83)과 `project_gate_latency`의 한 줄(112 ~ 113). 지우지 않고 "LI에서
   바뀌었다"를 붙인다(design 결정 7).
6. 게이트 전후의 비교값 — HC-M2 루트 게이트 10분 5초(prebuild 309초 + lanes 294초), 그때의 initrd 크기는 안 적혀 있다. 기준 initrd는
   지금 정상 빌드의 99,264,851바이트(LI-M0 Task 5)다.

## Task 1: `make_initrd.sh`

확정 1 · 2 · 3. 돌린 뒤 `initrd.cpio` 크기와, 첫 archive를 풀어 다섯의 크기 · `readelf -S`의 `.debug_info` 유무를 본다.

## Task 2: 주석과 문서

확정 3 ~ 5.

## Task 3: 루트 게이트 · 닫기

`./check.sh` 22체인(약 10분, `run_in_background`, 요약 `/tmp/gate.log`). 결과 · prebuild 시간 · initrd 크기를 아래에 적고, design 닫기 절을
한다.

## LI-M1이 실측한 것

(Task 3에서 적는다)
