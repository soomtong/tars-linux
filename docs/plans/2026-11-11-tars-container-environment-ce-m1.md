# CE-M1 — 커널: namespace · cgroup v2 · seccomp · bridge · NAT, init의 cgroup2

Date: 2026-11-11
Design: `docs/specs/2026-11-11-tars-container-environment-design.md`(결정 2 · 3)
Status: 끝났다(2026-11-12). 결정은 사용자 위임(2026-11-11).

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

구현 `c410002`. plan과 다른 자리 하나: `INOTIFY_USER`를 더했다(CE-M2의 프로브가 찾았다 — design 결정 2).

- 해소본이 따라 켠 것: `POSIX_MQUEUE_SYSCTL`, `BPF_JIT_DEFAULT_ON`, `TASKS_RCU` 계열, `PAGE_COUNTER` · `SLAB_OBJ_EXT`(memcg),
  `CGROUP_WRITEBACK`, `GROUP_SCHED_WEIGHT` · `GROUP_SCHED_BANDWIDTH`, `SOCK_CGROUP_DATA`, `NET_XGRESS` · `NETFILTER_BPF_LINK`,
  `NF_NAT_REDIRECT` · `NF_NAT_MASQUERADE`, `NFT_FIB` · `NFT_REJECT_IPV4` · `NF_REJECT_IPV4`, `STP` · `LLC` · `BRIDGE_IGMP_SNOOPING`,
  `NET_SOCK_MSG`, `FS_POSIX_ACL`, `EXECMEM`, `BINARY_PRINTF`. `CPUSETS`는 SMP가 없어 안 섰다.
- bzImage: 11,486,208(LT 뒤) → 12,174,336(+672KiB) → 12,190,720 B(inotify +16KiB). vmlinux 42,490,144 → 44,805,592 B. 빌드 3분 48초.
- 부팅: `install` 부팅 7의 `init waited 900ms`는 그대로다(carryover PD 절의 신호 — 커널이 커졌지만 창이 안 닫혔다).
- 게스트: `tars-init: mounted cgroup2 at /sys/fs/cgroup`, `cgroup.controllers` = `cpu io memory pids`, `/proc/self/ns`에 `user` · `pid` ·
  `time` · `cgroup`, `Seccomp:` 줄 둘. tools 검사 28.

루트 게이트(2026-11-12, `0e1b888`의 코드): 32/33 — 34분 51초(prebuild 344초 + lanes 1,614초), 잘린 줄 0, `out/gate-logs/20261111-162704`. 빨간 하나는 pm(PM-M0)의 화면 판정이 옛 프롬프트 `tars@(none) ~>`를 기다린 것(LT-M0이 놓친 자리)이고, 그 한 줄을 고친 뒤 pm 단독이 초록이었다. 커널 · init · initrd는 그 사이 바뀌지 않아 게이트를 통째로 다시 돌리지 않았다.
