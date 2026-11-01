---
name: project_gate_parallel
description: "루트 게이트를 1시간 01분 18초에서 9분 51초로 줄인 서브프로젝트 Gate Parallel(GP-M0~M2, 2026-10-10). 측정 → initrd 바꿔치기 → prebuild 한 번 뒤 체인을 동시 JOBS줄. 게이트는 계산이 아니라 기다림이라(빌드 뒤 CPU 평균 57%) 병렬의 상한은 메모리다. 체인끼리 같은 자리에 쓰면 안 된다 — 포트 · 호스트 파일 · 공유 산출물(제자리 쓰기 금지) · 체인이 부르는 호스트 검사의 /tmp 고정 경로"
metadata:
  type: project
---

Gate Parallel(GP)은 사용자의 요청 한 줄("how to improve test gates time. research first", 2026-10-10)에서 시작했다. design은
`docs/specs/2026-10-10-tars-gate-parallel-design.md`, plan은 `-gp-m0.md`(측정) · `-gp-m1.md`(initrd) · `-gp-m2.md`(병렬)이고 값은
각 plan의 실측 절에 있다. 같은 날 사용자가 `RUNS`를 1로 내리고([[feedback_gate_runs]]) OrbStack 메모리를 4GB에서 12GB로 늘렸다.
lead가 직접 구현했다(서브에이전트 없음).

## 결정

1. 측정이 먼저다. `run_chain`이 회차마다 `time:` 줄을 찍고 게이트 끝에 느린 순 표를 낸다. GL의 "추정이 아니라 단계별 실측"
   ([[project_gate_latency]])을 게이트에 붙박은 것이다. 이 표가 "부팅 전 CPU가 논다(평균 57%)"를 보여서 병렬이 서고, "고정 sleep
   줄이기(GP-M3)"는 전체 시간을 못 줄인다는 것도 보였다 — 전체를 정하는 것은 가장 긴 체인(config 약 193초)과 cold 빌드(약 4분)다.
2. 빌드는 `prebuild`가 한 번 한다. 체인이 빌드를 부르는 구조(`require_build_steps`)는 그대로 두고 그 호출이 전부 캐시 적중이
   되게 한다. 그래서 `skipping make`의 기대값이 체인 수 − 1에서 체인 수 × `RUNS`로 바뀌었다.
3. 줄(lane). `make_iso.sh`를 부르는 체인(boot · machine · install)은 `out/tars.iso`를 제자리에 쓰고 limine 도구를 `make -B`로 다시
   빌드하므로 한 줄로 묶어 차례로 돈다. 이름이 아니라 스크립트를 읽어 고른다.
4. `JOBS` 기본값은 컨테이너의 메모리에서 계산한다 — min(6, (MemTotal − 1.5GiB) ÷ 1GiB, nproc). 장비마다 OrbStack 메모리가
   다르기 때문이다(사용자 요청). 실측은 QEMU 하나 최대 689MiB, 여섯이 떴을 때 VM 3.81GiB(`check.sh`의 `default_jobs` 주석은 686MiB ·
   다섯 3.3GiB로 적혀 있다 — 어느 회차의 값인지는 GP-M2 plan의 실측 절이 정본). `-e JOBS=N` · `-e RUNS=N`이 앞선다.
5. 빨간 체인이 있어도 나머지는 끝까지 돌고 끝에 모아 찍는다. 줄의 출력은 그 줄이 끝날 때 한 덩어리다.
6. initrd의 "같은 내용이면 건너뛰기"는 안 했다. 같은 입력으로 만들어도 바이트가 다르고(cpio가 mtime · inode를 적는다) 아낄 것이
   2분 남짓이라 잡음 안이다.

## 함정

- 체인끼리 같은 자리에 쓰면 안 된다 — 포트 · 호스트 파일 · 공유 산출물의 `mv` 바꿔치기 · 호스트 검사의 `/tmp` 고정 경로
  (`test_scratch.enter`) · symlink 상대 대상은 `docs/guides/lessons.md`의 "체인은 동시에 돈다 — 둘이 같은 자리에 쓰면 안 된다(GP-M2)"
  절. 여기에만 있는 것 — 제자리 쓰기의 증상은 읽던 쪽이 중간부터 새 내용을 읽는 것이고 열어 둔 fd로 재 보면 보인다(GP-M1 확정
  3). 지키는 검사(tools 1d)는 "옛 내용이 온전하다"만 보면 안 되고 "inode가 바뀌었다"를 함께 본다 — 산출물이 재현 가능해지는 날
  제자리 쓰기도 같은 바이트를 내어 통과하기 때문이다. `/tmp` 고정 경로 일곱으로 첫 병렬 게이트의 10체인이 죽었을 때 사용자가
  게이트의 잠금 대신 검사를 고치는 쪽을 골랐다.
- 컨테이너 이미지에 `ps`가 없다. 프로세스의 RSS는 `/proc/<pid>/status`의 `VmRSS`로 읽는다.
- 게이트가 도는 동안 `check.sh`를 고치지 않는다. bash는 스크립트를 실행하며 조금씩 읽는다.

## How to apply

새 체인을 쓸 때 포트(45495부터) · 호스트 파일(`mktemp`나 `out/<체인>-…`) · 공유 산출물(바꿔치기) · 호스트 검사의 파일 자리
(`test_scratch.enter`)를 본다. 게이트 시간을 더 줄이려면 표의 머리(가장 긴 체인)와 cold 빌드를 본다. 줄 336초는 하한(체인 합
÷ 6, 약 289초)보다 47초 길다 — 긴 체인을 먼저 띄우면 그만큼이다.

관련: [[project_gate_latency]] · [[feedback_gate_runs]] · [[project_gate_chain_composition]] · [[project_gate_accuracy]]
