# CE-M1 — 커널: namespace · cgroup v2 · seccomp · bridge · NAT, init의 cgroup2

Date: 2026-11-11
Design: `docs/specs/2026-11-11-tars-container-environment-design.md`(결정 2 · 3)
Status: 진행 중. 결정은 사용자 위임(2026-11-11).

## 착수 전에 확정한 것

1. 옵션 목록은 design 결정 2. 켜는 법은 KU · UB와 같다 — `scripts/config -e …` 뒤 `olddefconfig`로 해소하고 해소본의 차이를 읽는다.
2. `SMP`가 꺼져 있어 `CPUSETS`는 해소본에 안 선다(`-e CPUSETS`를 줘도 사라진다). `docker info`의 `WARNING: No cpuset support`가 그 결과다.
3. cgroup2의 자리는 `/sys/fs/cgroup`(sysfs가 `CGROUPS`와 함께 만드는 디렉터리) — `/sys`를 붙인 바로 뒤.

## Task 1 — `kernel/.config`

design 결정 2의 옵션. 해소본이 따라 켠 것을 결과에 적는다.

## Task 2 — init

`mountEarly`에 `mountFs("cgroup2", "/sys/fs/cgroup", "cgroup2", NOSUID | NODEV | NOEXEC)` 한 줄. 로그는 기존 `mounted … at …` 꼴.

## Task 3 — 판정

체인 `tools`: `tars-init: mounted cgroup2 at /sys/fs/cgroup`, `cat /sys/fs/cgroup/cgroup.controllers`에 `cpu` · `io` · `memory` · `pids`,
`/proc/self/ns/user`가 있다, `/proc/self/status`에 `Seccomp:` 줄.

## Task 4 — 재기

bzImage 크기(앞 · 뒤), 빌드 시간, 부팅의 `init waited`(carryover PD 절의 TCG 풀기 시간 — 커널 배치가 움직인다).

## 결과

(게이트 뒤 적는다.)
