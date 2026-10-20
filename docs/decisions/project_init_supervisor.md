---
name: project_init_supervisor
description: "PID 1(tars-init)은 셸이 되지 않고 자식 둘을 감독한다 · `waitpid(-1, WNOHANG)`으로 고아까지 거둔다 · `supervise()`는 noreturn · 거두기를 `poll`(1000ms)보다 앞에 둔 순서가 1초 backoff다 · `SA_RESTART`를 끈다 · 깨운 fd는 반드시 읽는다 · 10초 미만 연속 3회면 포기 · 고치면 BF와 PM부터 돌린다"
metadata:
  node_type: memory
  type: project
---

IS(2026-08-14)가 세웠고 HD-M2(2026-08-22)가 감독 루프를 `poll` 구조로 바꿨다.
그 전의 `init`은 `/terminal`을 fork한 뒤 `execve`로 자신을 fish로 덮어써서,
셸이 끝나면 `Attempted to kill init!`으로 패닉했고 고아를 거둘 코드가 없었다.
코드는 `init/src/main.zig`의 `supervise()`, 게이트는 BF · PM · TF 체인이다.
milestone별 경과와 게이트 시간은 2026-10-20에 지웠다(커밋 이력에 있다).

```
PID 1 = tars-init         ← supervise()가 noreturn. 절대 반환하지 않는다
  ├─ /terminal            ← 죽으면 재시작
  │    └─ fish (PTY)
  └─ fish (/dev/console)  ← 죽으면 재시작
```

## 네 가지 결정

1. `execve` 대신 fork 둘 + 감독 루프. `setsid()` + `TIOCSCTTY`가 콘솔 셸 자식
   안으로 내려갔고, PID 1은 초기 세션에 남아 커널이 열어 준 fd 0/1/2로 자기
   로그를 시리얼에 찍는다.
2. `waitpid(-1, ...)`로 아무 자식이나 거둔다. 리눅스가 부모 잃은 프로세스를
   전부 PID 1에 재부모화하므로 돌아온 pid가 목록에 없는 것이 정상이고,
   `reaped orphan pid N`만 찍고 넘어간다. 이것이 PID 1이 지는 유일한 의무다.
3. 루프는 죽음을 기다리는 것이 아니라 돌아야 할 것이 도는지 확인하는 구조다.
   매 바퀴 안 떠 있는 자식을 먼저 띄우므로 `fork` 실패가 특별 취급 없이 다음
   바퀴에 재시도된다.
4. 재시작 폭주 방지: 1초 backoff + 10초를 못 채우고 죽은 것이 연속 3회면 포기.
   포기해도 루프는 돈다(고아 수거 의무는 남는다). 3회인 이유는 BF 체인이다 —
   GPU가 없어 `/terminal`이 매번 죽으므로 이 숫자가 곧 BF 로그의 노이즈이자
   시리얼 출력 경합 횟수다. 로그 문구 `restarting {s} in 1s`는 지금도 참이다.

`supervise()`를 `noreturn`으로 선언해 실수로 넣은 `return`을 컴파일 타임에
막는다 — PID 1의 반환은 곧 커널 패닉이다.

## 감독 루프는 `poll` 구조다 (2026-08-22 HD-M2)

PID 1이 전원 버튼을 직접 열면서([[project_device_discovery]]) 자식의 죽음과 버튼
fd를 함께 기다려야 하게 됐다. 블로킹 `waitpid`로는 하나만 기다릴 수 있다.

```
1. power.take()   → 종료 요청이 있으면 shutdown(noreturn)
2. start()        → 안 떠 있고 포기하지 않은 자식을 띄운다
3. waitpid(-1, WNOHANG) 반복 → 거둘 것을 전부 거둔다
4. poll(버튼 fd들, 1000ms)   → 유일하게 잠드는 자리
```

거두기(3)를 `poll`(4)보다 앞에 둔 순서가 backoff다. 죽은 자식을 그 바퀴에서
거두고 곧바로 1초를 자므로 재시작은 다음 바퀴 머리에서 일어난다. 그래서
`sleepOneSecond()`와 `alive == 0` 분기(블로킹 `waitpid`가 `ECHILD`로 즉시 돌아와
바쁜 루프가 되는 것을 막던 것)가 함께 사라졌다 — 자식도 버튼도 없으면
`poll(fds, 0, 1000)`이 그냥 1초 `sleep`이다. `Child`에 `restart_after` 필드를
더하는 길은 가장 민감한 코드에 상태를 얹는 것이라 물렸다.

### `SA_RESTART`는 `poll`에서도 같은 이유로 필수다

`SA_RESTART`가 켜져 있으면 커널이 `poll`을 안에서 재시작한다
([[project_power_management]]). 끈 채로 두어야 `poll`이 `EINTR`로 깨어나고
`if (e != .INTR)` 분기가 흐름을 루프 머리로 돌려보낸다. PM 체인 부팅
2(Ctrl+Alt+Del → SIGINT → 재부팅)가 이 성질을 정면으로 밟는다.

### 1초 타임아웃이 덮는 것은 `SIGCHLD` 경합이다

`waitpid(WNOHANG)`이 "없다"를 답한 뒤 `poll`이 잠들기 전에 자식이 죽으면 알려 줄
것이 없다 — 핸들러가 없는 `SIGCHLD`는 `poll`을 깨우지 않는다. 타임아웃이 그
틈을 덮고 대가는 최대 1초의 지각이다. `SIGCHLD` 핸들러는 `power.zig`의
`signal handlers installed (TERM, INT)` 로그와 그것을 grep하는 게이트를 흔들어
물렸고, `signalfd`는 `SA_RESTART`를 끄고 얻은 구조를 통째로 버리는 것이라 물렸다.

### 깨어났으면 반드시 읽어야 한다

버튼 fd가 깨웠는데 읽지 않으면 그 `revents`가 매 `poll`마다 다시 서서 바쁜
루프가 된다(아래 `POLLHUP` 절과 같은 함정). `drainButton`이 `EAGAIN`까지
비우고, 읽어도 낫지 않는 `POLLERR` · `POLLHUP` · `POLLNVAL`로 깨어났으면 그
`fd`를 `-1`로 바꿔 목록에서 뺀다(POSIX가 음수 fd를 건너뛴다). 핫플러그 지원이
아니라 장치가 사라졌을 때 CPU를 태우지 않게 하는 것이 전부다.

### 이 코드의 진짜 계약은 HD 체인이 아니라 BF와 PM에 있다

모든 체인이 이 코드를 딛고 선다. 고친 뒤에는 새 체인이 아니라 이것들을 본다.

- BF 체인(`boot/check.sh`)의 `started terminal` 정확히 3회 — backoff가
  살아 있는지를 개수로 잡는다. `poll` 타임아웃이 `sleep`을 대신하지 못하면
  여기가 먼저 어긋난다.
- PM 체인(`power/check.sh`)의 `started console shell` 정확히 1회 — 루프
  머리의 `take()`가 `start()`보다 앞이라는 순서를 지킨다.
- TF 체인의 `reaped orphan pid` — `WNOHANG`으로도 재부모화된 고아를 거두는지.

## 게이트와의 결합 — 일부러 만든 것

재시작을 검증하려면 `/terminal`이 죽어 줘야 한다. 그래서 TF 시절
`terminal/src/main.zig` 끝의 무한 sleep을 지웠다 — 감독자가 없던 때의
임시방편이었고, 지금은 새 프롬프트가 영영 안 돌아오게 만든다.

같은 이유로 `terminal`은 자기 PTY 자식(fish)을 `waitpid`하지 않는다. 그 좀비가
PID 1로 재부모화되어야 게이트가 `tars-init: reaped orphan pid N`으로 수거를
관측한다. 여기서 미리 거두면 그 증거가 사라진다.

TF 게이트(`terminal/check.sh`)는 `42` 검증 뒤 `exit`를 주입하고 셋을 본다:
`terminal: spawned child pid` 개수 증가(재시작), `reaped orphan pid`(수거),
`Attempted to kill init` 부재(패닉 없음). 삽입 위치는 QEMU monitor fd 3이 아직
열려 있는 구간이어야 한다.

## `POLLHUP` — 도달 불가능했던 EOF 처리

PTY master는 slave가 전부 닫히면 `POLLIN`이 아니라 `POLLHUP`을 올린다. 남은
출력이 있는 동안은 `POLLIN|POLLHUP`이지만 다 읽으면 `POLLHUP`만 남는다.
`revents & POLLIN`만 보면 `read`를 못 부른 채 `poll`이 즉시 돌아오는 바쁜
루프에 빠진다 — 로그는 조용해서 멈춘 것처럼 보이지만 CPU는 100%다. 처방은
`revents & (POLLIN | POLLHUP | POLLERR)`이고, `readSome`이 `read <= 0`에서 빈
슬라이스를 돌려주므로 `POLLHUP`에서도 일단 `read`하면 두 경우가 다 처리된다.

이 EOF 처리 코드는 TF-M3부터 있었지만 게이트가 셸을 죽여 본 적이 없어 한 번도
실행되지 않았다([[project_gate_chain_composition]]의 "게이트는 자기가 안 보는
것을 통과시킨다").

## 남은 사각지대

BF 게이트는 배너가 보이는 즉시 QEMU를 죽이므로 재시작 · 포기 경로를 관측하지
못한다. `given_up`이 깨져 무한 재시작이 나도 BF는 PASS한다. 재시작 정책을
건드릴 때는 손으로 확인한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c \
  'timeout 20 qemu-system-x86_64 -cdrom out/tars.iso -serial stdio -display none -no-reboot 2>&1 \
   | grep -E "tars-init:|OpenFailed|Attempted to kill"'
```

How to apply: 감독 루프를 고칠 때는 (1) 루프 머리의 `power.take()`가
`start()`보다 앞이라는 순서를 깨지 않고, (2) 잠드는 자리가 `EINTR`로 깨어나
루프 머리로 돌아가는지 확인하며(`SA_RESTART`를 켜는 순간 조용히 깨진다),
(3) `poll`이 깨운 fd는 반드시 읽어 비우고, (4) 고친 뒤에는 HD 체인이 아니라
BF와 PM을 먼저 돌린다. 감독 대상은 `Kind` enum에 컴파일 타임으로 고정돼 있고,
늘리려면 `Child.argv` 배열 길이(`main.zig`, 지금 `[9:null]`)도 함께 본다.

관련: [[project_power_management]], [[project_device_discovery]],
[[project_boot_shell_selection]], [[project_gate_chain_composition]],
[[project_zig_c_uapi_rule]]
