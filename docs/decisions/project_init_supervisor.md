---
name: project_init_supervisor
description: "PID 1(tars-init)은 자식 둘을 fork해 감독한다 — execve로 셸이 되지 않고, waitpid(-1)로 고아까지 거두며, 절대 반환하지 않는다; 재시작은 1초 backoff + 10초 미만 연속 3회면 포기; 게이트가 재시작을 관측하려면 terminal이 죽어줘야 한다는 결합이 있다"
metadata:
  node_type: memory
  type: project
---

2026-08-14 IS milestone. 그 전까지 `init`은 마운트 몇 개를 하고 `/terminal`을
fork한 뒤 **`execve`로 자신을 fish로 덮어썼다.** 즉 PID 1이 곧 셸이었고,
셸이 끝나면 커널이 `Attempted to kill init!`으로 패닉했으며, 재부모화된
고아를 거둘 코드가 아무 데도 없었다.

지금 구조:

```
PID 1 = tars-init         ← supervise()가 noreturn. 절대 반환하지 않는다
  ├─ /terminal            ← 죽으면 재시작
  │    └─ fish (PTY)
  └─ fish (/dev/console)  ← 죽으면 재시작
```

## 네 가지 결정

**1. `execve` 대신 fork 둘 + 감독 루프.** 콘솔 셸도 자식이 되면서
`setsid()` + `TIOCSCTTY`(제어 터미널 잡기)가 PID 1에서 **그 자식 안으로**
내려갔다. PID 1은 초기 세션에 남아 커널이 열어준 fd 0/1/2로 자기 로그를 계속
시리얼에 찍는다.

**2. `waitpid(-1, ...)`의 `-1`이 핵심이다.** 특정 pid가 아니라 "아무 자식이나"
기다린다. 리눅스가 부모 잃은 프로세스를 전부 PID 1에 재부모화하므로, 돌아온
pid가 내 목록에 없는 것이 **정상**이다 — 그 경우 `reaped orphan pid N`만
찍고 넘어간다. 이것이 PID 1이 지는 유일한 의무다.

**3. 루프는 "죽음을 기다리는" 것이 아니라 "돌아야 할 것이 도는지 확인하는"
구조다.** 매 바퀴 안 떠 있는 자식을 먼저 띄우고 그 다음에 `waitpid`로 잠든다.
덕분에 `fork` 실패가 특별 취급이 필요 없다(다음 바퀴에 자동 재시도).
`alive == 0` 분기가 반드시 있어야 한다 — 자식이 하나도 없으면 `waitpid`가
`ECHILD`로 **즉시** 반환해서 CPU를 태우는 바쁜 루프가 된다.

**4. 재시작 폭주 방지: 1초 backoff + 10초를 못 채우고 죽은 것이 연속 3회면
포기.** 포기해도 루프는 계속 돈다(고아 수거 의무는 남는다). 3회로 잡은 이유는
BF 체인이다 — GPU가 없어 `/terminal`이 매번 죽으므로 이 숫자가 곧 BF 로그의
노이즈이자 시리얼 출력 경합 횟수다.

`supervise()`를 `noreturn`으로 선언한 것은 타입 수준의 안전장치다. 실수로
`return`을 넣으면 컴파일이 안 된다 — PID 1의 반환은 곧 커널 패닉이므로
런타임이 아니라 컴파일 타임에 막는다.

## 게이트와의 결합 — 일부러 만든 것

**재시작을 검증하려면 `/terminal`이 죽어줘야 한다.** 그래서 TF 시절
`terminal/src/main.zig` 끝에 있던 무한 sleep("자식이 죽어도 화면을 유지한 채
남는다")을 지웠다. 그 코드는 되살려 줄 감독자가 없어서 필요했던 임시방편이고,
감독자가 생긴 지금은 새 프롬프트가 영영 안 돌아오게 만드는 방해물이다.

같은 이유로 **`terminal`은 자기 PTY 자식(fish)을 `waitpid`하지 않는다.**
일부러 그렇게 뒀다 — 그래야 그 좀비가 PID 1로 재부모화되고, 게이트가
`tars-init: reaped orphan pid N`으로 **수거가 실제로 도는 것을 관측**할 수
있다. 여기서 미리 거두면 그 증거가 사라진다.

TF 게이트(`terminal/check.sh`)는 `42` 검증 뒤 `exit`를 주입하고 셋을 본다:
`terminal: spawned child pid` 개수 증가(재시작), `reaped orphan pid`(수거),
`Attempted to kill init` 부재(패닉 없음). 삽입 위치는 QEMU monitor fd 3이 아직
열려 있는 구간이어야 한다.

## `POLLHUP` — 도달 불가능했던 EOF 처리

이 milestone에서 실제로 막힌 곳은 예상했던 DRM master 재획득이 아니라
`terminal`의 poll 루프였다. **PTY master는 slave가 전부 닫히면 `POLLIN`이
아니라 `POLLHUP`을 올린다.** 남은 출력이 있는 동안은 `POLLIN|POLLHUP`으로 함께
오지만 다 읽고 나면 `POLLHUP`만 남는다. `revents & POLLIN`만 보면 `read`를
영영 호출하지 못한 채 `poll`이 즉시 반환하는 바쁜 루프에 빠진다 — 로그가
조용해서 멈춘 것처럼 보이지만 CPU는 100%다.

고친 형태는 `revents & (POLLIN | POLLHUP | POLLERR)`이다. `readSome`이
`read <= 0`에서 빈 슬라이스를 돌려주므로, `POLLHUP`에서도 일단 `read`를
시도하는 것만으로 두 경우가 다 처리된다.

**교훈은 버그 자체가 아니라 그것이 살아남은 방식이다.** EOF 처리 코드는
TF-M3부터 있었지만 게이트가 셸을 죽여본 적이 없어 **한 번도 실행되지
않았다.** 도달 불가능한 코드를 "동작한다"고 믿고 있었다
([[project_gate_chain_composition]]의 "게이트는 자기가 안 보는 것을
통과시킨다").

## 남은 사각지대

BF 게이트는 배너가 보이는 즉시 QEMU를 죽이므로 **재시작·포기 경로를 전혀
관측하지 못한다.** `given_up`이 깨져 무한 재시작이 나도 BF는 PASS한다.
재시작 정책을 건드릴 때는 이걸 손으로 확인할 것:

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c \
  'timeout 20 qemu-system-x86_64 -cdrom out/tars.iso -serial stdio -display none -no-reboot 2>&1 \
   | grep -E "tars-init:|OpenFailed|Attempted to kill"'
```

**How to apply:** 다음 서브프로젝트(설정 영속화 + 부팅 셸 선택)가 이 구조
위에 얹힌다. 감독 대상은 지금 `Kind` enum에 컴파일 타임으로 고정돼 있고,
`Kind.path()`가 상수 대신 저장소에서 읽어온 값을 돌려주게 되는 것이 그
milestone의 모양이다. 시그널 처리(SIGTERM/reboot)는 아직 없다 — 전원 관리를
다룰 때 함께 한다. 관련: [[project_boot_shell_selection]],
[[project_gate_chain_composition]], [[project_zig_c_uapi_rule]]
