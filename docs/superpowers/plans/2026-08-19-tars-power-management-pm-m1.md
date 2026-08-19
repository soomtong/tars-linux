# TARS Power Management PM-M1 Implementation Plan

> **이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md`):** 파일 작성과
> 명령 실행은 사용자가 직접 하고, Claude는 각 Step의 정확한 내용을 제시하고
> 결과를 해석한다. 다른 저장소용 SUB-SKILL 문구는 이 저장소에 적용하지 않는다.

**Goal:** 게스트 안에서 시스템을 **되살릴** 수 있게 한다. Ctrl+Alt+Del을 누르면
커널이 우리를 건너뛰고 재부팅하는 대신 PID 1에게 `SIGINT`로 알려 주고, PID 1이
PM-M0에서 만든 종료 순서를 그대로 탄 뒤 `reboot(RESTART)`를 부른다. 이
milestone이 끝나면 "설정을 고치고 재부팅해야 반영된다"는 CP의 정책이 게스트
안에서 사람 손 없이 완결된다.

**Design doc:** `docs/superpowers/specs/2026-08-19-tars-power-management-design.md`
(결정 1의 `SIGINT` 절반, 결정 4, 결정 8의 부팅 A, 결정 9가 이 milestone의
몫이다. design은 이미 승인되어 있으므로 다시 논의하지 않는다.)

**Tech Stack:** Zig 0.16.0(`std.os.linux`의 `sigaction`/`reboot`), QEMU monitor
`sendkey`, `awk`, Docker(`tars-devcontainer`, arm64)

---

## 왜 이 순서인가

```
Task 1   power.zig에 restart를 더한다              ← 부팅 없이 도는 저울
  ↓      SIGINT → Action.restart → reboot(RESTART)
  ↓      로그 문구가 바뀌므로 PM-M0 게이트도 함께 고친다
Task 2   게이트에 부팅 A를 붙이고 **실패를 본다**   ← 커널이 우리를 건너뛴다
  ↓      "재부팅은 되는데 우리를 거치지 않았다"가 실패로 잡혀야 한다
Task 3   reboot(CAD_OFF) — 같은 게이트가 통과한다
  ↓
Task 4   BF 게이트의 사각지대를 닫는다              ← 이월된 숙제
  ↓
Task 5   루트 게이트를 갱신하고 3/3
```

**Task 1이 맨 앞인 이유**는 PM-M0과 같다. 부팅 20초를 쓰기 전에 0.1초로 잡을
수 있는 실패를 먼저 잡는다. 다만 이번 Task 1에는 PM-M0에 없던 성격이 하나
있다 — **로그 문구 하나가 바뀌기 때문에 기존 게이트를 함께 고쳐야 한다.**
`signal handlers installed (TERM)`이 `(TERM, INT)`가 되는데, 그 문자열은
`power/check.sh:179`가 요구하고 있다. 고치지 않으면 PM-M0 게이트가 깨진다.
이것이 `project_gate_chain_composition`이 적어 둔 "로그 문구는 두 곳에
중복된다"가 실제로 청구서를 내미는 첫 자리다.

**Task 2가 구현보다 앞인 이유는 PM-M0 때보다 훨씬 절실하다.** PM-M0의 실패는
"아무 일도 일어나지 않음"이었지만, **PM-M1의 실패는 "성공처럼 보인다."**
`reboot(CAD_OFF)`가 없는 지금도 Ctrl+Alt+Del을 누르면 커널이 즉시 재부팅하므로
(`kernel/reboot.c:832`의 `if (C_A_D) schedule_work(&cad_work);`), 게스트는 다시
뜨고, 새 설정을 읽고, zsh를 띄운다. design 결정 8이 나열한 부팅 A의 마커 셋
(`starting as PID 1` 두 번 · `config shell=zsh` · `started console shell
(/usr/bin/zsh)`)이 **구현을 하나도 안 한 상태에서 전부 통과한다.**

그래서 이 plan은 design이 정하지 않은 검사를 아래 "이번에 정하는 것"에서
추가한다. 그 검사 없이 게이트를 만들면, 게이트가 자기가 안 보는 것을
통과시킨다 — Task 4에서 닫으려는 사각지대와 똑같은 실패다.

**Task 4를 여기에 두는 이유**는 design 결정 9가 적은 그대로 시점이다. 감독
루프에 손을 댄 milestone이 그 루프의 관측되지 않던 경로에 검사를 다는 자리다.

## 이번에 정하는 것 다섯 (design doc이 안 정한 자리)

**1. `reboot(CAD_OFF)`는 `install()` 안이 아니라 별도 함수다.**

design 결정 4는 "mount 직후, 자식을 띄우기 전에" 부르라고만 했다. 자연스러운
구현은 `install()` 안에 한 줄 더하는 것인데, **그렇게 하면 호스트 검사가
`reboot(2)`를 부르게 된다.** `power_test`는 `install()`을 부르고, 그 검사는
Docker 컨테이너 안에서 돈다. 컨테이너에 `CAP_SYS_BOOT`이 없으면 `EPERM`으로
끝나지만, 있으면 **개발 기계의 커널이 `C_A_D`를 0으로 바꾼다.** 그것은 이
저장소의 검사가 호스트를 건드리는 일이고, PM-M0이 "`shutdown()`을 호스트에서
부르지 말 것"이라고 적어 둔 것과 정확히 같은 종류의 위험이다.

그래서 `disableCtrlAltDel()`을 따로 두고, 그것을 부르는 자리는 `main.zig`
하나로 한정한다. **`power_test`가 부르는 함수 중에는 `reboot(2)`를 부르는
것이 하나도 없다**는 성질을 유지하는 것이 규칙이다.

부르는 순서는 `install()` **다음**이다. 순서가 뒤집히면 그 사이의 짧은 창에서
Ctrl+Alt+Del이 눌렸을 때 핸들러 없는 `SIGINT`가 도착한다. PID 1이라 커널이
버려 주므로 사고는 안 나지만, "키를 빼앗기 전에 받을 준비를 끝낸다"가 읽기에
맞다.

**2. 부팅 A는 재부팅이 아니라 "우리를 거쳐 간 재부팅"을 본다.**

위에서 적은 대로 재부팅 자체는 구현 없이도 일어난다. 그래서 부팅 A가 요구하는
줄에 다음 넷을 **더한다.** 이 넷이 커널의 직접 재부팅과 우리 종료 순서를
가르는 유일한 증거다.

| 문구 | 무엇을 가르는가 |
|---|---|
| `tars-init: ctrl-alt-del now arrives as SIGINT` | `CAD_OFF`가 실제로 먹었다 |
| `tars-init: shutdown requested (action restart)` | 키가 우리 핸들러에 닿았다 |
| `tars-init: calling reboot(RESTART)` | 재부팅을 **우리가** 시켰다 |
| `Restarting system` (커널이 찍는다, `reboot.c:294`) | 커널이 그 요청을 받았다 |

**3. 두 부팅의 순서는 B(끄기) → A(되살리기)이고, 디스크는 한 번만 굽는다.**

부팅 A는 게스트 안에서 `/config/tars.conf`를 `shell=zsh`로 고치므로, **끝나고
나면 디스크가 zsh다.** 그 디스크로 부팅 B를 돌리면 `power/check.sh:140`의
`config shell=bash` 검사와 `:147`의 `bash-` 프롬프트 검사가 무너진다.

순서를 뒤집으면 그 문제가 통째로 사라진다. 부팅 B는 설정을 고치지 않으므로
(치는 것은 `kill -TERM 1` 하나다) 디스크는 `shell=bash`인 채로 남고, 부팅 A가
그것을 그대로 물고 뜬다. **두 부팅 사이에 `make_disk.sh`를 다시 부를 필요가
없다.**

CP 체인이 "두 부팅 사이에서는 절대 다시 굽지 않는다"고 못 박은 것과 결과는
같지만 이유는 다르다. CP는 영속성이 검증 대상이라 다시 구우면 증명이
무너졌다. PM은 부팅 A **한 번 안에서** 편집·재부팅·반영이 전부 일어나므로
영속성에 기대지 않는다. 여기서 다시 굽지 않는 것은 단지 필요가 없어서다.

**4. "2차 부팅의 로그"는 `awk`로 잘라낸다.**

부팅 A는 QEMU 하나가 두 번 부팅하므로 **로그 파일이 하나**다. design 결정 8이
"그 뒤에 `config shell=zsh`가 있다"고 순서를 요구한 것을 `grep`만으로는 지킬
수 없다. 두 번째 `starting as PID 1`부터를 잘라내어 거기서만 찾는다.

```bash
awk '/tars-init: starting as PID 1/{n++} n>=2' "$LOG_A"
```

이 한 줄이 "재부팅 뒤에"라는 조건을 파일 자체로 만들어 준다.

**5. 무한 재부팅은 개수로 잡는다.**

design의 "위험과 대응"이 적은 그대로다. `-no-reboot`을 뺐으므로 게스트가
계속 재부팅하면 게이트가 영영 안 끝난다. 마커를 본 뒤 **3초를 더 기다렸다가**
`starting as PID 1`의 개수를 다시 센다. 셋 이상이면 그 자체가 실패다.

3초인 근거는 부팅 한 번이 약 4초라는 실측이다. 고리에 빠졌다면 그 안에 최소
한 번 더 늘어난다.

## 사전 준비

모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서 실행한다.
`main` 브랜치, working tree가 깨끗한 상태에서 시작한다.

**`docker run`/`docker build`에 `--platform`을 붙이지 않는다**
(`docs/decisions/project_build_host_arch.md`).

**이번에 `/tmp` + `cp` + `diff` 경로를 쓰는 파일은 하나다** —
`power/check.sh`(Task 2에서 214줄이 340줄 남짓이 된다). 나머지는 전부 짧은
블록이라 인라인으로 제시한다.

**인라인으로 제시하는 블록은 "넣을 것"만 적는다.** 문맥 줄을 포함한 블록을
제시했다가 기존 줄이 복제된 사고가 IP-M2에 있었다.

**이미지 재빌드는 필요 없다.** zsh는 이미 initrd에 들어가고(CP-M2가 쓴다),
`awk`는 devcontainer의 기본 도구다.

---

## Task 1: `SIGINT`이 재시작이 된다

부팅 없이 판정할 수 있는 전부다. `reboot(RESTART)`는 호스트에서 부를 수
없으므로, 여기서 보는 것은 "`SIGINT`이 `Action.restart`라는 값이 되는가"까지다.

**Files:**
- Modify: `init/src/power_test.zig` (검사 추가)
- Modify: `init/src/power.zig` (`Action`, `onSignal`, `install`, `shutdown`)
- Modify: `power/check.sh:179` (바뀌는 로그 문구)

- [ ] **Step 1: 실패할 검사를 먼저 쓴다**

`init/src/power_test.zig`의 마지막 줄

```zig
    std.debug.print("power_test: SIGTERM becomes a pending power_off action\n", .{});
}
```

에서 `}` **앞**에 이 블록을 넣는다(마지막 `}`는 그대로 두고 그 위에 끼운다).

```zig

    // 4. 같은 핸들러가 SIGINT를 다르게 기록해야 한다. 이것이 PM-M1의 전부다 —
    //    Ctrl+Alt+Del은 reboot(CAD_OFF) 뒤에 **SIGINT로** 도착하므로
    //    (kernel/reboot.c:835의 kill_cad_pid(SIGINT, 1)), 키보드 경로와
    //    `kill -INT 1` 경로가 이 한 분기로 합쳐진다.
    _ = linux.kill(linux.getpid(), .INT);

    const got_int = power.take() orelse {
        std.debug.print("FAIL: SIGINT was delivered but no action was recorded\n", .{});
        return error.SignalNotObserved;
    };
    if (got_int != .restart) {
        std.debug.print("FAIL: SIGINT recorded {s}, want restart\n", .{@tagName(got_int)});
        return error.WrongAction;
    }

    // 5. 마지막에 온 시그널이 이긴다. 감독 루프는 take()를 한 번에 하나씩만
    //    처리하므로, 두 요청이 겹치면 나중 것이 남는 편이 예측 가능하다.
    _ = linux.kill(linux.getpid(), .TERM);
    _ = linux.kill(linux.getpid(), .INT);
    const last = power.take() orelse {
        std.debug.print("FAIL: nothing was recorded after two signals\n", .{});
        return error.SignalNotObserved;
    };
    if (last != .restart) {
        std.debug.print("FAIL: TERM then INT recorded {s}, want restart\n", .{@tagName(last)});
        return error.WrongAction;
    }

    std.debug.print("power_test: SIGINT becomes a pending restart action\n", .{});
```

- [ ] **Step 2: 실패를 확인한다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init \
  tars-devcontainer bash -c "zig build test"
```

기대: **`power_test`가 시그널 2에 죽는다.** PM-M0 Task 1의 Step 4에서 시그널
15로 죽었던 것과 같은 모양이고, 이유도 같다 — `.INT` 분기가 없어서
`onSignal`이 `return`해 버리고, 그러면 `SIGINT`의 기본 동작(프로세스 종료)이
일어나지 않는다… 가 아니다. **핸들러는 이미 달려 있지 않다.** `install()`이
`.TERM`에만 `sigaction`을 걸어 두었으므로 `SIGINT`는 기본 동작 그대로
프로세스를 죽인다.

```
run power_test: error: the following command terminated unexpectedly:
... (signal 2)
```

이 구분이 중요하다. **핸들러가 없어서 죽는 것**과 **핸들러가 있는데 분기가
없어서 무시하는 것**은 다른 실패인데, 지금은 앞의 것이다. 다음 Step이 둘 다
고친다.

- [ ] **Step 3: `Action`에 `restart`를 더한다**

`init/src/power.zig`의

```zig
/// PID 1이 시그널을 받고 하기로 한 일. PM-M0은 끄는 것 하나뿐이고,
/// PM-M1에서 SIGINT가 restart를 더한다.
pub const Action = enum(u8) {
    power_off = 1,
};
```

을 이것으로 바꾼다.

```zig
/// PID 1이 시그널을 받고 하기로 한 일. 값이 0이 아닌 이유는 pending의 0이
/// "요청 없음"을 뜻하기 때문이다.
pub const Action = enum(u8) {
    power_off = 1,
    restart = 2,
};
```

- [ ] **Step 4: `onSignal`에 `.INT` 분기를 더한다**

`init/src/power.zig`의

```zig
    const action: Action = switch (sig) {
        .TERM => .power_off,
        else => return,
    };
```

을 이것으로 바꾼다.

```zig
    const action: Action = switch (sig) {
        .TERM => .power_off,
        .INT => .restart,
        else => return,
    };
```

- [ ] **Step 5: `install()`이 두 시그널을 건다**

`init/src/power.zig`의

```zig
    if (failed(linux.sigaction(.TERM, &act, null))) |e| {
        std.debug.print("tars-init: failed to install SIGTERM handler (errno {d})\n", .{
            @intFromEnum(e),
        });
        return;
    }
    std.debug.print("tars-init: signal handlers installed (TERM)\n", .{});
```

를 이것으로 바꾼다.

```zig
    if (failed(linux.sigaction(.TERM, &act, null))) |e| {
        std.debug.print("tars-init: failed to install SIGTERM handler (errno {d})\n", .{
            @intFromEnum(e),
        });
        return;
    }
    // 같은 act를 그대로 재사용한다. 두 시그널이 하는 일은 "정수 하나를
    // 남긴다"로 동일하고, 무엇을 남길지는 onSignal 안에서 갈린다.
    if (failed(linux.sigaction(.INT, &act, null))) |e| {
        std.debug.print("tars-init: failed to install SIGINT handler (errno {d})\n", .{
            @intFromEnum(e),
        });
        return;
    }
    std.debug.print("tars-init: signal handlers installed (TERM, INT)\n", .{});
```

- [ ] **Step 6: `shutdown()`이 `RESTART`를 부를 수 있게 한다**

`init/src/power.zig`의

```zig
    const cmd: linux.LINUX_REBOOT.CMD = switch (action) {
        .power_off => .POWER_OFF,
    };
```

을 이것으로 바꾼다.

```zig
    // RESTART는 POWER_OFF와 달리 ACPI 없이도 그대로 동작한다. 커널이
    // kernel_restart()로 들어가 "Restarting system"을 찍고(reboot.c:294)
    // 기계를 리셋한다 — QEMU에서는 -no-reboot이 없으면 정말 다시 뜬다.
    const cmd: linux.LINUX_REBOOT.CMD = switch (action) {
        .power_off => .POWER_OFF,
        .restart => .RESTART,
    };
```

- [ ] **Step 7: 통과를 확인한다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init \
  tars-devcontainer bash -c "zig build test"
```

기대: 마지막 세 줄이 이렇게 나온다.

```
tars-init: signal handlers installed (TERM, INT)
power_test: SIGTERM becomes a pending power_off action
power_test: SIGINT becomes a pending restart action
```

- [ ] **Step 8: 바뀐 로그 문구를 게이트에도 반영한다**

`power/check.sh:179`의

```bash
  "tars-init: signal handlers installed (TERM)" \
```

를 이것으로 바꾼다.

```bash
  "tars-init: signal handlers installed (TERM, INT)" \
```

**이 한 줄을 빼먹으면 다음 Step에서 PM-M0 게이트가 깨진다.**
`power/check.sh:81`의 마커 목록에도 같은 문구가 있지만 그쪽은 괄호가 없어서
(`"tars-init: signal handlers installed"`) 고칠 필요가 없다 — 실패 보고용
목록이라 부분 일치로 충분하기 때문이다.

- [ ] **Step 9: PM-M0 게이트가 그대로 도는지 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash power/check.sh
```

기대: 전과 같이 `PM-M0 PASS: the guest shut itself down from a shell command`.

`SIGINT` 핸들러가 하나 늘었을 뿐 끄는 경로는 한 줄도 안 바뀌었으므로 통과가
정상이다. 여기서 깨진다면 Step 8을 안 했거나 `power.zig` 편집이 틀린 것이다.

- [ ] **Step 10: 커밋**

```bash
git add init/src/power.zig init/src/power_test.zig power/check.sh
git commit -m "Let a SIGINT ask PID 1 to restart"
```

---

## Task 2: 부팅 A를 붙이고 "우리를 거치지 않은 재부팅"이 실패로 잡히는 것을 본다

**이 Task의 실패는 PM-M0 Task 2와 성격이 다르다.** 그때는 아무 일도 일어나지
않는 것을 봤지만, 이번에는 **게스트가 실제로 재부팅하고 새 설정으로 다시 뜬다.**
`reboot(CAD_OFF)`가 없어서 커널이 우리를 건너뛰고 직접 재부팅하기 때문이다
(`kernel/reboot.c:26`의 `static int C_A_D = 1;`).

그래서 이 Step에서 확인해야 할 것은 "실패했다"가 아니라 **"어느 줄에서
실패했는가"** 다. `shutdown requested (action restart)`가 없어서 실패해야
한다. `starting as PID 1`이 두 번 안 나와서 실패한다면 그것은 게이트가 아직
아무것도 증명하지 못한다는 뜻이다.

**Files:**
- Modify: `power/check.sh` (부팅 A 추가, 214줄 → 340줄 남짓)

- [ ] **Step 1: 게이트 스크립트를 통째로 교체한다**

**이 파일은 340줄이 넘으므로 `/tmp` 경로를 쓴다.** Claude가
`/tmp/tars-power-check-m1.sh`에 완성본을 만들어 두면, 다음 명령으로 제자리에
넣고 대조한다.

```bash
cp /tmp/tars-power-check-m1.sh power/check.sh
chmod +x power/check.sh
diff /tmp/tars-power-check-m1.sh power/check.sh && echo "identical"
```

완성본은 **Task 1 Step 8의 수정을 포함한 현재 파일에, 아래 두 덩어리가 더해진
것**이다. 기존 214줄은 마지막 두 줄을 빼고 한 글자도 바뀌지 않는다.

먼저 기존 파일의 마지막 두 줄

```bash
echo "PM-M0 PASS: the guest shut itself down from a shell command"
```

를 이것으로 바꾼다(`kill`/`wait`/`QEMU_PID=""` 세 줄은 그 위에 그대로 둔다).

```bash
echo "boot 1/2 PASS: the guest shut itself down from a shell command"
```

그리고 파일 끝에 부팅 A 전체를 이어 붙인다.

```bash

# ============================================================== 부팅 2/2 (A)
# 재시작 경로. **-no-reboot을 뺀다** — 게스트가 reboot(RESTART)를 부르면 QEMU가
# 정말로 다시 부팅해야 하기 때문이다. 두 부팅의 QEMU 옵션이 이렇게 갈리는 것이
# PM을 기존 체인에 얹지 않고 새 체인으로 만든 이유였다(design 결정 8).
#
# 디스크는 방금 부팅 1이 쓰던 것을 그대로 재사용한다. 부팅 1은 설정을 고치지
# 않으므로(친 것은 kill -TERM 1 하나다) 여기 들어올 때 디스크는 여전히
# shell=bash이고, 그것이 이 부팅의 전제다. make_disk.sh를 다시 부르지 않는다.
#
# 이 부팅 하나가 증명하는 것:
#   Ctrl+Alt+Del → 커널이 PID 1에게 SIGINT를 보낸다(CAD_OFF를 불렀을 때만!)
#   → 우리 종료 순서가 돈다 → reboot(RESTART) → 커널이 기계를 리셋한다
#   → 같은 QEMU가 다시 뜬다 → 게스트가 아까 쓴 설정을 읽는다 → zsh가 뜬다

LOG_A="$(mktemp)"
# 두 번째 부팅 구간만 잘라낸 것. design 결정 8이 "그 뒤에"라고 요구한 순서를
# grep만으로는 지킬 수 없어서, 파일을 나누어 조건을 파일 자체로 만든다.
SECOND="$(mktemp)"

# 부팅 2에서 두 번째 부팅 구간을 다시 잘라낸다. 로그가 계속 자라므로 검사할
# 때마다 새로 자른다.
slice_second_boot() {
  awk '/tars-init: starting as PID 1/{n++} n>=2' "$LOG_A" > "$SECOND"
}

count_boots() {
  grep -c "tars-init: starting as PID 1" "$LOG_A" 2>/dev/null || true
}

report_failure_a() {
  echo "FAIL(boot 2): $1"
  echo "--- markers ---"
  local marker
  for marker in \
    "tars-init: signal handlers installed (TERM, INT)" \
    "tars-init: ctrl-alt-del now arrives as SIGINT" \
    "terminal: screen>" \
    "tars-init: shutdown requested (action restart)" \
    "tars-init: every child is gone" \
    "tars-init: filesystems synced" \
    "tars-init: calling reboot(RESTART)" \
    "Restarting system" \
    "tars-init: config shell=zsh"; do
    if grep -q "$marker" "$LOG_A"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- boots seen: $(count_boots) (want exactly 2) ---"
  echo "--- last 80 lines ---"
  tail -n 80 "$LOG_A"
  exit 1
}

# echo shell=zsh > /config/tars.conf — CP 체인과 같은 시퀀스다. sendkey가
# 보내는 것은 문자가 아니라 키이므로 '='는 equal, '>'는 shift-dot이다.
EDIT_KEYS=(e c h o spc s h e l l equal z s h spc shift-dot spc
           slash c o n f i g slash t a r s dot c o n f ret)

echo "=== boot 2/2: edit the config in the guest, then ctrl-alt-delete ==="

qemu-system-x86_64 \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -drive file="${REPO_ROOT}/out/power.img",if=virtio,format=raw \
  -display none \
  -serial file:"$LOG_A" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait &
QEMU_PID=$!

READY=0
for _ in $(seq 1 120); do
  if grep -q "terminal: screen>" "$LOG_A"; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || report_failure_a "terminal never rendered a prompt"
sleep 1

# 부팅 1과 같은 디스크이므로 여기도 bash여야 한다. 아니라면 부팅 1이 디스크를
# 건드렸다는 뜻이고, 그건 이 체인의 전제가 무너진 것이다.
grep -q "tars-init: config shell=bash" "$LOG_A" \
  || report_failure_a "the first boot left the disk in an unexpected state (not bash)"

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure_a "could not connect to the QEMU monitor"

echo "=== typing the config edit into the guest ==="
type_keys "${EDIT_KEYS[@]}"
sleep 1

# 여기가 이 체인의 심장이다. sendkey ctrl-alt-delete는 커널의 VT 키보드
# 핸들러(drivers/tty/vt/keyboard.c:618의 fn_boot_it)까지 가고, 그것이
# ctrl_alt_del()을 부른다. 그 다음에 무슨 일이 생기는지가 C_A_D 값에 갈린다:
#   C_A_D = 1 (기본값) → 커널이 우리를 건너뛰고 즉시 재부팅한다
#   C_A_D = 0 (우리가 CAD_OFF로 바꾼 뒤) → PID 1에게 SIGINT가 온다
# 겉으로는 둘 다 "재부팅됐다"로 보이기 때문에, 아래 검사가 그 둘을 가른다.
echo "=== sending ctrl-alt-delete ==="
echo "sendkey ctrl-alt-delete" >&3
sleep 0.3

exec 3<&-
exec 3>&-

# 두 번째 부팅이 시작될 때까지 기다린다.
BOOTS=0
for _ in $(seq 1 90); do
  BOOTS="$(count_boots)"
  if [ "${BOOTS:-0}" -ge 2 ]; then break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "${BOOTS:-0}" -ge 2 ] \
  || report_failure_a "the guest never came back up after ctrl-alt-delete"

# ★ 이 여섯 줄이 "재부팅됐다"와 "우리를 거쳐 재부팅됐다"를 가른다. 이것들
#   없이 위의 BOOTS >= 2만 보면, reboot(CAD_OFF)를 한 줄도 안 쓴 상태에서도
#   게이트가 통과한다 — 커널이 직접 재부팅해도 게스트는 다시 뜨기 때문이다.
for marker in \
  "tars-init: signal handlers installed (TERM, INT)" \
  "tars-init: ctrl-alt-del now arrives as SIGINT" \
  "tars-init: shutdown requested (action restart)" \
  "tars-init: sent SIGTERM to every process" \
  "tars-init: filesystems synced" \
  "tars-init: calling reboot(RESTART)"; do
  grep -q "$marker" "$LOG_A" || report_failure_a "missing restart log line: ${marker}"
done

# 커널 쪽 증거. 우리가 부른 reboot(2)를 커널이 정말 받았다는 줄이다
# (kernel/reboot.c:294). POWER_OFF와 달리 RESTART는 강등되지 않는다.
grep -q "Restarting system" "$LOG_A" \
  || report_failure_a "the kernel never reported 'Restarting system'"

# 재부팅 뒤의 구간에서만 찾는다. 1차 부팅의 줄과 섞이면 순서를 증명할 수 없다.
ZSH_OK=0
for _ in $(seq 1 60); do
  slice_second_boot
  if grep -q "tars-init: started console shell (pid .*, /usr/bin/zsh)" "$SECOND"; then
    ZSH_OK=1
    break
  fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done

slice_second_boot
grep -q "tars-init: config shell=zsh" "$SECOND" \
  || report_failure_a "the second boot did not read the config the guest had written"

[ "$ZSH_OK" = "1" ] \
  || report_failure_a "the second boot parsed zsh but never exec'd /usr/bin/zsh"

# 재부팅 고리 감시. -no-reboot을 뺐으므로 원리적으로 가능한 실패다. 부팅 한
# 번이 약 4초이므로, 고리에 빠졌다면 이 3초 안에 개수가 한 번 더 는다.
sleep 3
FINAL="$(count_boots)"
if [ "${FINAL:-0}" -gt 2 ]; then
  report_failure_a "the guest booted ${FINAL} times; it is stuck in a reboot loop"
fi

# 음성 검사 — 부팅 1과 같은 이유다. PID 1이 죽어서 커널이 패닉해도 시스템은
# 어차피 멈추고 QEMU는 -no-reboot 없이 다시 뜰 수 있다.
if grep -q "Attempted to kill init" "$LOG_A"; then
  report_failure_a "the kernel panicked instead of restarting cleanly"
fi

kill "$QEMU_PID" 2>/dev/null
wait "$QEMU_PID" 2>/dev/null
QEMU_PID=""

echo "boot 2/2 PASS: ctrl-alt-delete went through PID 1 and the new config took effect"

echo "--- init log (boot 2) ---"
grep 'tars-init:' "$LOG_A" || true

echo "PM-M1 PASS: the guest can shut itself down and bring itself back up"
```

- [ ] **Step 2: 문법을 먼저 본다**

```bash
bash -n power/check.sh && echo "syntax ok"
```

- [ ] **Step 3: 실패를 확인한다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash power/check.sh
```

기대는 두 단계다.

1. `boot 1/2 PASS: the guest shut itself down from a shell command`가 먼저
   나온다. PM-M0이 만든 부팅은 그대로 통과해야 한다.
2. 그 다음 부팅 2에서 **`missing restart log line: tars-init: ctrl-alt-del now
   arrives as SIGINT`** 로 실패한다.

마커 목록에서는 `terminal: screen>`과 `signal handlers installed (TERM, INT)`가
`found`이고, `ctrl-alt-del now arrives as SIGINT`부터 `calling
reboot(RESTART)`까지가 `MISSING`이어야 한다. 그리고 **`--- boots seen: 2 ---`**
이 함께 보일 것이다.

**그 `2`가 이 Step의 핵심이다.** 게스트는 실제로 재부팅했고, `config
shell=zsh`도 아마 `found`일 것이다. 구현을 한 줄도 안 했는데 design이 나열한
마커 셋이 통과한 것이다 — 커널이 우리를 건너뛰고 직접 재부팅했기 때문이다.
게이트를 저 여섯 줄로 세우지 않았다면 이 milestone은 아무것도 안 하고
통과했을 것이고, 그것이 `project_gate_chain_composition`이 말하는 "게이트는
자기가 안 보는 것을 통과시킨다"의 실물이다.

`boots seen`이 2가 아니라 1이면 다른 문제다(sendkey가 안 닿았거나 VT 키보드
핸들러가 그 조합을 못 받았다). 그 경우 알려 달라 — Task 3이 고칠 수 있는
문제가 아니다.

- [ ] **Step 4: 커밋**

실패하는 게이트도 커밋한다. 다음 커밋이 무엇을 고쳤는지가 히스토리에 남는다.

```bash
git add power/check.sh
git commit -m "Ask the gate to prove the restart went through PID 1"
```

---

## Task 3: Ctrl+Alt+Del을 커널에서 빼앗는다

시스템 콜 한 번이다. 이 milestone에서 새로 쓰는 코드는 사실상 이 함수 하나뿐이고,
나머지는 전부 PM-M0이 만든 길을 재사용한다.

**Files:**
- Modify: `init/src/power.zig` (`disableCtrlAltDel` 추가)
- Modify: `init/src/main.zig` (`power.install()` 다음 줄)

- [ ] **Step 1: `power.zig`에 함수를 더한다**

`init/src/power.zig`의 `take()` 함수

```zig
/// 밀린 요청을 꺼내면서 지운다. 감독 루프가 매 바퀴 부른다.
pub fn take() ?Action {
    const raw = @atomicRmw(u8, &pending, .Xchg, 0, .seq_cst);
    if (raw == 0) return null;
    return @enumFromInt(raw);
}
```

**바로 아래**에 이 블록을 넣는다.

```zig

/// Ctrl+Alt+Del을 커널에게서 빼앗아 우리에게 돌린다.
///
/// 커널의 기본값은 C_A_D = 1이고(kernel/reboot.c:26), 그 상태에서 그 조합이
/// 눌리면 ctrl_alt_del()이 워크큐에 재부팅을 걸어 **PID 1을 완전히 건너뛴다**
/// (:832). 자식을 정리할 기회도, 디스크를 내려쓸 기회도 없다. CAD_OFF는 그
/// 분기를 반대쪽으로 돌려서 kill_cad_pid(SIGINT, 1)이 불리게 만든다(:835) —
/// 그 뒤부터 저 키는 우리 종료 순서를 탄다.
///
/// **install()과 한 함수로 합치지 않는 이유는 호스트 검사 때문이다.**
/// power_test는 install()을 부르고 Docker 컨테이너 안에서 도는데, 컨테이너에
/// CAP_SYS_BOOT이 있으면 이 호출이 **개발 기계의 커널** 설정을 바꾼다.
/// power_test가 부르는 함수 중에 reboot(2)를 부르는 것이 하나도 없어야
/// 한다는 것이 규칙이고, 이 분리가 그 규칙을 지킨다.
///
/// 실패해도 부팅은 계속한다. Ctrl+Alt+Del 하나 때문에 시스템이 안 뜨면
/// 곤란하고, `kill -INT 1` 경로는 이것과 무관하게 살아 있다.
pub fn disableCtrlAltDel() void {
    if (failed(linux.reboot(.MAGIC1, .MAGIC2, .CAD_OFF, null))) |e| {
        std.debug.print("tars-init: could not take over ctrl-alt-del (errno {d})\n", .{
            @intFromEnum(e),
        });
        return;
    }
    std.debug.print("tars-init: ctrl-alt-del now arrives as SIGINT\n", .{});
}
```

- [ ] **Step 2: `main.zig`에서 부른다**

`init/src/main.zig`의

```zig
    power.install();
```

**바로 아래**에 이 블록을 넣는다.

```zig

    // install()보다 **뒤**여야 한다. 순서가 뒤집히면 그 사이의 짧은 창에서
    // 눌린 Ctrl+Alt+Del이 핸들러 없는 SIGINT로 도착한다. PID 1이라 커널이
    // 버려 주므로 사고는 안 나지만, "키를 빼앗기 전에 받을 준비를 끝낸다"가
    // 읽기에 맞다.
    power.disableCtrlAltDel();
```

- [ ] **Step 3: 컴파일과 호스트 검사를 먼저 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init \
  tars-devcontainer bash -c "zig build && zig build test"
```

기대: 둘 다 통과. `power_test`의 출력은 Task 1 Step 7과 **한 글자도 달라지지
않아야 한다.** `ctrl-alt-del now arrives as SIGINT`가 거기 섞여 나온다면
`disableCtrlAltDel()`이 `install()` 안으로 들어갔다는 뜻이고, 그러면 Step 1의
주석이 경고한 위험이 그대로 살아난다.

- [ ] **Step 4: 게이트를 통과시킨다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash power/check.sh
```

기대: 마지막 줄이

```
PM-M1 PASS: the guest can shut itself down and bring itself back up
```

그 앞에 `boot 1/2 PASS`와 `boot 2/2 PASS`가 하나씩 있어야 한다.

**부팅 2의 init 로그를 통째로 보내 달라.** 게이트가 마지막에
`--- init log (boot 2) ---`로 찍어 준다. 그 로그 안에서 다음 순서가 보이는
것이 이 milestone이 만든 것 전부다.

```
tars-init: starting as PID 1                     ← 1차
tars-init: signal handlers installed (TERM, INT)
tars-init: ctrl-alt-del now arrives as SIGINT
tars-init: config shell=bash
...
tars-init: shutdown requested (action restart)    ← 키가 우리에게 닿았다
tars-init: sent SIGTERM to every process
tars-init: grace period expired (reaped N)
tars-init: sent SIGKILL to what was left
tars-init: every child is gone (reaped N)
tars-init: filesystems synced
tars-init: calling reboot(RESTART)
tars-init: starting as PID 1                      ← 2차
tars-init: config shell=zsh                       ← 아까 쓴 설정
tars-init: started console shell (pid N, /usr/bin/zsh)
```

- [ ] **Step 5: 다른 체인이 안 깨졌는지 본다**

`main.zig`를 건드렸으므로 나머지 넷을 한 번씩 돌린다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c \
  './boot/check.sh && ./terminal/check.sh && ./config/check.sh && ./input/check.sh'
```

기대: 넷 다 PASS. 새로 찍히는 줄 둘(`(TERM, INT)`,
`ctrl-alt-del now arrives as SIGINT`)은 다른 체인이 검사하지 않는다.

- [ ] **Step 6: 커밋**

```bash
git add init/src/power.zig init/src/main.zig
git commit -m "Route ctrl-alt-delete through PID 1"
```

---

## Task 4: BF 게이트의 사각지대를 닫는다

design 결정 9가 적은 이월 숙제다. `boot/check.sh`는 fish 배너를 보자마자 QEMU를
죽이므로, 감독 루프의 **재시작·포기 경로를 한 번도 관측한 적이 없다.**
`given_up`이 깨져서 무한 재시작이 나도 BF는 지금 통과한다.

BF 체인은 GPU가 없어서(`-cdrom`만 주고 virtio-gpu를 안 준다) `/terminal`이 매
회차 죽는 구성이다. **그 경로를 이미 매번 밟고 있으면서 보지 않고 있을 뿐이다.**

세 개라는 숫자는 `main.zig`의 코드에서 그대로 나온다. 처음 뜨고(1), 빨리 죽어
`fast_restarts`가 1이 되고 `MAX_FAST_RESTARTS`(3) 미만이라 재시작하고(2), 또 죽어
2가 되고 재시작하고(3), 세 번째로 죽을 때 3이 되어 `:301`의
`if (c.fast_restarts >= MAX_FAST_RESTARTS)`가 성립하며 포기한다.

**Files:**
- Modify: `boot/check.sh` (배너 확인 뒤 폴링 하나 + 판정 둘)

- [ ] **Step 1: 포기 로그를 기다리는 폴링을 넣는다**

`boot/check.sh`의

```bash
cat "$LOG"
```

**바로 위**에 이 블록을 넣는다.

```bash
# 배너가 나왔다고 바로 죽이면 감독 루프의 재시작·포기 경로를 영영 못 본다.
# BF 체인은 GPU가 없어서 /terminal이 매 회차 죽는 구성이므로, 그 경로를
# 이미 밟고 있으면서 관측만 안 하고 있었다. 재시작 backoff가 1초이고 세 번
# 죽어야 포기하므로 3초 남짓이면 끝난다 — 상한은 넉넉히 30초로 둔다.
GAVE_UP=0
if [ "$FOUND" = "1" ]; then
  for _ in $(seq 1 30); do
    if grep -q "tars-init: giving up on terminal" "$LOG"; then
      GAVE_UP=1
      break
    fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
      break
    fi
    sleep 1
  done
fi

```

- [ ] **Step 2: 판정 둘을 넣는다**

`boot/check.sh`의

```bash
  echo "init mounted all four filesystems"
```

**바로 아래**에 이 블록을 넣는다.

```bash

  # 감독 루프의 포기 경로. 이 줄이 없으면 init이 아직도 /terminal을 되살리고
  # 있다는 뜻이다.
  if [ "$GAVE_UP" != "1" ]; then
    echo "FAIL: init never gave up on the terminal"
    exit 1
  fi

  # "포기했다"는 줄 하나만으로는 그 뒤에도 계속 재시작하는 구현을 못 거른다.
  # 개수가 정책 그 자체다 — 처음 뜨고, 두 번 재시작하고, 세 번째 빠른 종료에서
  # 포기한다(main.zig의 MAX_FAST_RESTARTS = 3).
  #
  # grep -c는 매치가 0이면 종료 코드 1을 내는데 이 스크립트는 set -e라 그
  # 자리에서 죽는다. || true로 받아서 "0회였다"가 아래 판정까지 오게 한다.
  STARTS="$(grep -c "tars-init: started terminal" "$LOG" || true)"
  if [ "$STARTS" != "3" ]; then
    echo "FAIL: init started the terminal ${STARTS} times, want exactly 3"
    exit 1
  fi
  echo "init restarted the terminal twice and then gave up (started ${STARTS} times)"
```

- [ ] **Step 3: 문법을 본다**

```bash
bash -n boot/check.sh && echo "syntax ok"
```

- [ ] **Step 4: BF 게이트를 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash boot/check.sh
```

기대: 다음 두 줄이 새로 보이고 마지막이 `PASS`다.

```
init mounted all four filesystems
init restarted the terminal twice and then gave up (started 3 times)
PASS
```

**여기서 `started N times, want exactly 3`으로 실패하면 알려 달라.** 그것은
게이트의 버그가 아니라 **처음으로 관측된 감독 루프의 실제 동작**이고, 그
숫자가 몇인지에 따라 무엇을 고칠지가 갈린다. 이 검사를 만든 목적이 정확히
그것이다.

- [ ] **Step 5: 커밋**

```bash
git add boot/check.sh
git commit -m "Watch the supervisor give up in the boot gate"
```

---

## Task 5: 루트 게이트를 갱신한다

**Files:**
- Modify: `check.sh:69-75` (주석과 체인 이름)
- Modify: `HANDOFF.md`

- [ ] **Step 1: 체인 이름을 올린다**

`check.sh`의

```bash
run_chain "PM-M0" ./power/check.sh
```

를 이것으로 바꾼다.

```bash
run_chain "PM-M1" ./power/check.sh
```

- [ ] **Step 2: 부팅 횟수 주석을 갱신한다**

`check.sh`의

```bash
# PM-M0은 부팅 1회다. 그래서 총 부팅 횟수는 18회에서 21회가 된다.
# PM-M1이 재부팅을 보는 부팅을 하나 더 붙이면 24회가 된다.
```

를 이것으로 바꾼다.

```bash
# PM-M1부터 이 체인도 회차당 QEMU를 **두 번** 띄운다. 1차는 -no-reboot을 단
# 채로 끄는 경로를(kill -TERM 1 → HALT), 2차는 그것을 **뺀** 채로 되살리는
# 경로를 본다(설정 편집 → ctrl-alt-delete → 재부팅 → 새 설정으로 zsh). 두
# 부팅의 QEMU 옵션이 이렇게 갈리는 것이 PM을 기존 체인에 얹지 않은 이유다.
#
# 그래서 총 부팅 횟수는 18회에서 24회가 된다.
#
# BF 체인도 PM-M1부터 몇 초 길어진다. 배너 뒤에 감독 루프가 /terminal을
# 포기하는 것까지 기다리기 때문이다 — 재시작 backoff가 1초라 3초 남짓이다.
```

- [ ] **Step 3: 루트 게이트를 돌린다**

이 명령은 30분 안팎으로 걸릴 것이다(PM-M0 시점의 실측이 26분 10초였고, 부팅
셋과 BF의 대기 셋이 더해진다).

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh
```

기대: 마지막 줄이

```
TARS check PASS: all chains 3/3 consecutive runs succeeded
```

그리고 그 앞에 `PM-M1 PASS: 3/3 consecutive runs succeeded`가 있어야 한다.

**실제 소요 시간을 기록해 달라.** `HANDOFF.md`와 다음 plan이 그 숫자를 쓴다.

- [ ] **Step 4: 커밋**

```bash
git add check.sh
git commit -m "Count the restart boot in the root gate"
```

- [ ] **Step 5: `HANDOFF.md`와 기억을 갱신한다**

Claude가 쓴다. 담을 것:

- PM-M1 완료, 그것으로 Power Management 서브프로젝트 전체가 끝났다는 것
- 루트 게이트 다섯 체인 24부팅과 실측 시간
- **로그 문구 중복 목록의 갱신** — `(TERM)`이 `(TERM, INT)`로 바뀌었고
  `ctrl-alt-del now arrives as SIGINT`와 `calling reboot(RESTART)`가 늘었다
- 이번에 알아낸 사실: 커널의 기본 `C_A_D = 1` 때문에 **게이트가 구현 없이도
  통과할 뻔했다**는 것(Task 2 Step 3에서 실제로 관측한 것)
- BF 사각지대가 닫혔다는 것과 그때 관측된 `started terminal` 실제 횟수
- 다음 서브프로젝트 후보 우선순위를 매길 자리라는 것

`docs/decisions/project_power_management.md`에도 한 문단을 더한다 —
"`disableCtrlAltDel()`을 `install()`과 분리한 이유는 호스트 검사가 `reboot(2)`를
부르면 안 되기 때문"이라는 규칙이 그것이다. 이것은 코드를 읽어서는 알 수 없고,
합치는 리팩터링이 언제든 다시 제안될 수 있는 종류의 결정이다.

---

## 완료 조건

- [ ] `zig build test`가 `power_test`의 검사 다섯을 통과한다(TERM, INT, 소비,
      마지막 시그널 우선, 그리고 아무것도 안 왔을 때의 null)
- [ ] `power/check.sh`가 부팅 둘 다 PASS한다
- [ ] `boot/check.sh`가 포기 경로를 관측하고 PASS한다
- [ ] 루트 게이트가 다섯 체인 3/3으로 PASS한다
- [ ] 커밋 다섯 개가 `main`에 있고 push까지 끝났다

## 이 milestone이 끝나면 무엇이 참이 되는가

CP가 정한 "설정을 고치고 **재부팅**해야 반영된다"는 정책이 게스트 안에서
사람 손 없이 완결된다. CP-M2는 그것을 증명하려고 QEMU를 두 번 띄우고 그
사이에 게이트가 개입해야 했다. PM-M1의 부팅 A는 **QEMU 하나가 스스로**
편집 → 재부팅 → 반영을 다 하고, 게이트는 그것을 지켜보기만 한다.

남는 것은 PM 비목표에 적힌 그대로다. 진짜 전원 차단(ACPI)은 `terminal`의
`/dev/input/event0` 상수를 먼저 고쳐야 하므로 별도 milestone이고,
`tars-config`는 이월 숙제로 남는다.
