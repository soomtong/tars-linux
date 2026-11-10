# SS-M2 — CA 갱신의 시한 넘김: 그룹을 죽이고 검사로 밟는다

Date: 2026-11-10
Design: `docs/specs/2026-11-10-tars-service-stop-design.md`(결정 4)
Status: 착수(2026-11-10). 사용자가 나머지 결정을 위임했다("잠시 외출합니다. 나머지 결정을 위임합니다.", SS-M1 체인 도중).

## 착수 전에 확정한 것

1. `trust.refresh`(`init/src/trust.zig`)는 `update-ca-certificates`(셸 스크립트)를 fork · exec하고 5초(`WAIT_MS`) 넘으면 그 pid에만
   SIGKILL을 보낸다(design 확인 5). 스크립트가 띄운 자식은 남는다.
2. 부르는 자리는 `main.zig:1272` 하나(`/home`이 붙었을 때). 바꾸는 것은 trust.zig 안이다 — 부르는 모양은 그대로.
3. `trust_test`는 컨테이너에서 도는 검사다(`init/build.zig:330`, 시스템 콜을 직접 부른다).

## Task 1 — `trust.zig`

- 실행과 기다림을 `pub fn runWithin(path, argv, envp, wait_ms) Run`(`ok` · `failed: u32` · `timed_out` · `no_fork` · `no_wait`)로 뗀다.
  `refresh`는 그것을 부르고 지금과 같은 줄을 찍는다(글자 그대로 — devtools 체인이 `added the certificates`를 본다).
- 자식은 `setpgid(0, 0)` 뒤 exec, 부모도 fork 직후 `setpgid(pid, pid)`(둘 중 먼저 닿는 쪽이 이긴다 — 시한 넘김이 그룹이 서기 전에
  와도 그룹이 있다). 시한 넘김은 `kill(-pid, KILL)` 뒤 그 pid를 거둔다. 손자는 PID 1(게스트에서는 init 자신)이 감독 루프에서 거둔다.
- 줄 `took over 5s, killed` → `took over 5s, killed its process group`.

## Task 2 — `trust_test`

1. `/bin/true` → `ok`, `/bin/false` → `failed`(종료 코드 1).
2. `sh -c 'sleep 30 & echo $! > F; wait'`를 300ms 시한 → `timed_out`, 걸린 시간 300ms 안팎(2초 미만), 손자 `sleep`(F의 pid)이 죽었다
   (`/proc/PID/stat`이 없거나 Z). 손자를 그룹으로 안 죽이면 이 검사가 빨갛다 — 고치기 전 코드로 한 번 빨강을 본다.
3. 없는 경로 → `failed`(exec 실패의 127).

## Task 3 — 게이트

컨테이너 init `zig build test`, `make quick`, 루트 게이트(SS-M1과 함께 한 번).

## 결과

(게이트 뒤에 적는다)
