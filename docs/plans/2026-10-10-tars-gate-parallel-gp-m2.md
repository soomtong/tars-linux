# GP-M2 — 체인을 동시에 돌린다

Date: 2026-10-10
Design: `docs/specs/2026-10-10-tars-gate-parallel-design.md`
Status: 끝났다(2026-10-10). 루트 게이트 9분 51초. 값은 맨 아래 "GP-M2가 실측한 것" — 첫 게이트가 드러낸 init 호스트 검사의
고정 경로를 고친 것이 3 · 4다.

## 누가 무엇을 하나

편집이 `check.sh` 한 파일이라 lead가 직접 넣는다.

| 파일 | 무엇을 |
|---|---|
| `check.sh` | 빌드 단계(`prebuild`) · 줄(lane) 만들기 · 동시 `JOBS`개 실행 · 줄 출력 모으기 · 빨간 체인 집계 |
| `init/src/test_scratch.zig` + `*_test.zig` 일곱 | 첫 게이트 뒤에 더했다 — 호스트 검사의 자리를 프로세스마다 나눈다(실측 3 · 4) |

체인 스크립트는 한 줄도 안 바뀐다. `run_chain`(회차 · 로그 디렉터리 · 잘린 줄 · 시간)도 그대로 쓴다.

## 착수 전에 확정한 것 (2026-10-10, HEAD `97333dd`)

1. 포트는 체인끼리 안 겹친다 — 주석을 뺀 코드에서 체인마다 따로다(firewall 45474~45480 · net 45464~45470 · service 45481~45486 등).
2. 호스트 쪽 고정 경로는 없다. 체인 안의 `pgrep` · `/tmp/…`는 전부 게스트에서 치거나 게스트에 심는 probe 안의 것이다.
3. `out/` 아래 디스크 이미지는 체인마다 이름이 다르다(17체인). 둘 이상이 쓰는 것은 `out/tars.iso` 하나다.
4. boot · machine · install은 셋 다 `boot/build.sh`(limine 도구를 `make -B`로 매번 다시 빌드)와 `make_iso.sh`(`out/tars.iso`를 제자리에
   쓰고 `limine bios-install`이 고친다)를 부르고 그 ISO로 부팅한다. 셋은 한 줄로 묶어 그 안에서 차례로 돈다. 묶을 체인은 이름을
   적지 않고 "주석 아닌 줄에서 `make_iso.sh`를 부르는 체인"으로 찾는다 — ISO 체인이 늘어도 안 빠진다. 세 체인 합은 GP-M1에서
   252(빌드 포함) · 21 · 111초이고 빌드를 빼면 약 160초로 config 체인(194초)보다 짧다.
5. 체인이 부르는 빌드 명령은 종류가 여덟이다 — `kernel/build.sh` 22 · `init`의 `zig build` 22 · `terminal/prepare.sh` 21 ·
   `make_initrd.sh` 23 · `init`의 `zig build test` 12 · `terminal`의 `zig build test` 10(+ terminal 체인이 그 디렉터리에서 직접 1) ·
   `boot/build.sh` 3 · `make_iso.sh` 3. 빌드 단계는 앞의 여섯과 `boot/build.sh`를 한 번 돌린다. `make_iso.sh`는 ISO 줄 안의 일이다.
   pointer 체인의 replay 빌드는 자기 `out/pd-replay`에 따로 하므로 빌드 단계에 넣지 않는다.
6. 빌드 단계 뒤에는 `skipping make`가 체인 수 × `RUNS`(지금 22)여야 한다 — 첫 체인도 커널을 안 빌드했다는 뜻이다.
7. 출력은 줄마다 `<GATE_LOGS>/lane-<n>.out`에 모았다가 줄이 끝날 때 한 덩어리로 찍는다. 끝난 순서대로 찍힌다.
8. 빨간 체인이 있어도 나머지 줄은 끝까지 돈다(지금은 첫 실패에서 멈춘다). 끝에 빨간 체인 목록을 찍고 `exit 1`.
   `run_chain`의 `exit 1`은 줄의 subshell만 끝낸다.
9. 동시 실행 수는 `JOBS="${JOBS:-6}"`. 메모리 12GB(게스트 하나 약 0.7GB), GP-M0의 CPU 평균 57%라 6개가 코어 약 3.5개 몫이다.
   `-e JOBS=1`이면 한 줄씩 돈다(출력은 여전히 줄 단위로 모인다).
10. `wait -n -p`는 bash 5.1부터다. 컨테이너 bash를 Task 1에서 확인한다.

## Task

1. 컨테이너 bash 버전 확인. `check.sh` 편집, `bash -n`, 진입 검사 셋.
2. 줄 만들기만 떼어 돌려 ISO 줄이 BF · RM · DC 셋인지 본다.
3. 루트 게이트(`JOBS=6`). 바깥 시간 · `skipping make` 22 · 빨간 줄 · 체인별 시간을 GP-M1과 견준다. CPU 표본도 남긴다.
4. 결과를 아래 절에 적는다. 사용자 승인 뒤 commit.

## GP-M2가 실측한 것

1. 컨테이너 bash는 5.2.37이다(`wait -n -p` 됨).
2. 스케줄러만 떼어 `run_chain`을 가짜(0.2~1초 자고 CM-M2만 실패)로 돌렸다 — 줄 20(ISO 줄이 BF · RM · DC), 동시 최대 6,
   22체인 전부 돌고 빨간 뒤에도 다른 줄이 계속, 끝에 `TARS check FAIL: CM-M2`와 `exit=1`.
3. 첫 루트 게이트는 빨갰다(6분 44초) — 10체인이 부팅 전 1초 만에 init 호스트 검사(`control_test`의 `dial to a closed listener
   succeeded`)로 죽었다. 확정 2는 체인 스크립트의 고정 경로만 훑었고 체인이 부르는 호스트 검사의 안쪽은 안 봤다. init 검사 일곱
   (devices · storage · control · login · config_edit · wifi · services)이 /tmp 아래 고정 경로를 썼다. 부팅까지 간 12체인은 초록.
4. 사용자 결정으로 검사를 고쳤다(게이트가 잠그는 길 대신). `init/src/test_scratch.zig`의 `enter`가 `/tmp/tars-test-<pid>`를
   만들어 그리로 `chdir`하고, 일곱 검사의 경로 상수는 상대 경로가 됐다. 제품 코드는 안 바뀌었다. `services_test`의 symlink 대상은
   이름만 준다 — 상대 대상은 링크가 놓인 디렉터리에서 풀리므로 `DIR ++ "/a-first"`는 없는 곳이 된다(첫 실행에서 빨갰다).
   init 검사 단독 · 넷 동시 모두 `exit=0`, terminal 검사 `exit=0`.
5. `JOBS` 기본값을 메모리에서 계산한다(사용자 요청 — 장비마다 OrbStack 메모리가 다르다). min(6, (MemTotal − 1.5GiB) ÷ 1GiB,
   nproc), 최소 1. 4GB → 2, 8GB 이상 → 6(코어 4개면 4). 머리 줄이 근거를 찍는다(`6 at a time (memory 12016 MiB, 10 cpus)`).
6. 두 번째 루트 게이트 — 22체인 `PASS: 1/1`, 바깥 9분 51초(빌드 단계 246초 + 줄 336초), `skipping make` 22, 잘린 줄 0, `FAIL` 0.
   순차 1회(GP-M1, 32분 23초)의 약 3.3배다.
7. 동시에 돌아도 체인이 안 느려졌다 — GP-M1 대비 CP 194 → 193 · TD 187 → 188 · CM 172 → 169 · WL 127 → 121초.
8. 메모리(10초 표본 58개) — QEMU 동시 최대 6, 하나 최대 689MiB, VM 사용 최대 3.81GiB. 줄 하나 1GiB는 넉넉한 쪽이다.
9. 줄 336초는 하한 약 289초(체인 합 1,736 ÷ 6)보다 47초 길다. 긴 체인을 먼저 띄우면 그만큼 줄지만 잡음 안이라 안 했다.
