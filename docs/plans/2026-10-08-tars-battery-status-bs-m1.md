# BS-M1 — 상태 줄 오른쪽 끝에 배터리 칸이 뜨고 바뀐다

Date: 2026-10-09
Design: `docs/specs/2026-10-08-tars-battery-status-design.md`
Status: 끝났다(2026-10-09). 구현은 Sonnet 서브에이전트가 Task 0 ~ 8을 글자 그대로 넣었고(plan 코드를 고친 곳 0, 컴파일 에러 0, plan의 기대 글자 하나를 고쳤다 — 확정 20), 루트 게이트 22체인 × 2는 22체인 전부 `PASS: 2/2`, 1시간 00분 18초, `skipping make` 43, 44회차 전부 `A=0 B=0 C=0`, hangul `383 … (off=87)` 두 번, 빨간 줄 0. 값은 맨 아래 "BS-M1이 실측한 것". BS의 마지막 milestone이다.

## 누가 무엇을 하나

design 결정 12. Task 0~8은 구현 서브에이전트가 main 작업 트리에서 직접 편집하고 돌린다. Task 9(루트 게이트 2회 · 실측 절 · commit)는
lead가 한다. 구현자는 commit하지 않고, 끝에 `git diff --stat` · `git diff | rg '^-'` · 각 Task의 명령 출력을 그대로 보고한다. 이 plan의
"착수 전에 확정한 것" 절은 구현자가 고치지 않는다.

권하는 모델은 Sonnet이다. 이유와 한계는 둘이다.

- 구현자가 새로 지을 코드가 없다. `main.zig`의 편집 열여덟은 `old_string` · `new_string`을 글자 그대로 넣고, 새 파일
  `battery/check.sh`는 이 plan의 블록을 글자 그대로 Write로 넣고, `check.sh` · `machine/check.sh`의 편집 셋도 글자 그대로다.
- 그러나 이 plan의 Zig 코드는 컨테이너의 zig 0.16.0으로 컴파일해 본 글자가 아니다(plan을 쓰는 동안 BS-M0의 루트 게이트가 Docker를
  쓰고 있었다). 호스트의 zig 0.17로 문법과 배터리 절의 타입을 봤을 뿐이다(확정 15). 그래서 Task 4의 첫 빌드가 컴파일 에러를 낼 수
  있다. 에러가 가리키는 자리만 고치고 무엇을 어떻게 고쳤는지 보고에 적는다. 고칠 자리가 다섯을 넘거나, 고치려면 이 plan의 동작(로그
  줄의 모양 · 판정의 기대값)을 바꿔야 하면 멈추고 보고한다 — 그때는 lead가 Opus로 올릴지 정한다. 체인이 plan의 기대와 다르게
  빨개져도 고치지 말고 멈추고 보고한다.

| 파일 | 무엇을 | 줄 |
|---|---|---|
| `terminal/src/main.zig` | 편집 열여덟 — 배터리 절 · `drainUevents`가 알리기 · 처음 훑기 · poll timeout · 주기 · 색 셋 · `Status` · `drawStatus` · `dumpStatus` | +392 −10 |
| `battery/check.sh` | 새 파일 — 스물두번째 체인. 검사 0 · 부팅 A(A1 ~ A5) · 부팅 B(B1) | +397 |
| `check.sh` | 편집 둘 — `CHAINS`에 한 줄, 그 위의 체인 설명에 한 문단 | +7 |
| `machine/check.sh` | 편집 하나 — 판정 14(`battery> scan seen=0`) | +28 |

합해서 추적 파일 셋 +427 −10, 새 파일 하나 397줄. `terminal/src/battery.zig` · `battery_test.zig` · `status.zig` · `build.zig` ·
`kernel/.config` · `boot/limine.conf` · `init/`은 한 줄도 안 바뀐다. design의 `Status:` · `CLAUDE.md` · `MEMORY.md` · `docs/decisions/` ·
`docs/guides/` · `HANDOFF.md`는 구현자가 안 고친다.

모든 명령은 저장소 루트에서 친다. 서브에이전트의 Bash는 호출마다 작업 디렉터리가 돌아가므로 명령 앞에
`cd /Users/dp/Repository/tars-linux &&`를 붙인다. 빌드 · 체인은 언제나 컨테이너에서 한다(호스트의 zig는 0.17, 컨테이너는 0.16.0).
호스트에서 찾을 때는 `rg`를 쓴다(이 기계에 GNU grep이 없다). 측정 파일은 `/tmp/run/bs1/` 아래에 둔다. `/tmp/run/bs1-plan/`은 이 plan을
쓰며 만든 사본이다. 지우지 않는다.

Docker VM의 메모리가 4GB다. 컨테이너 둘을 겹쳐 돌리면 `zig build`가 `Killed`로 죽거나 VM이 재시작된다(lessons PD-6). 컨테이너는 언제나
하나씩 돌린다. 다른 에이전트가 같은 시간에 돌 수 있으므로(특히 lead의 BS-M0 루트 게이트) 모든 `docker run`을 아래로 감싼다. 명령이
실패해도 lock은 꼭 푼다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run … ; rc=$?
rmdir /tmp/run/docker.lock
```

20분 넘게 기다리면 `docker ps`를 보고, 컨테이너가 하나도 없으면 lock이 낡은 것이니 `rmdir`하고 진행한다. 루트 게이트는 50분 안팎이라
lock을 그만큼 오래 들 수 있다 — 컨테이너가 하나라도 있으면 lock을 지우지 않고 기다린다.

## 이 milestone이 끝나면

- 배터리가 있는 기계에서 상태 줄의 오른쪽 끝에 넉 자 칸(`100%` · ` 85%` · `  5%` · `  ?%`)이 뜬다. 넉 자의 오른쪽 끝이 격자의 오른쪽 끝과
  같다. 색이 셋이다 — 방전 중 회색(`0x909AA0`), 어댑터가 꽂혀 있으면 초록(`0x60C070`), 꽂혀 있지 않고 15% 이하면 빨강(`0xE05040`).
- 값은 처음 훑기(첫 프레임 전) · power_supply uevent · 60초 주기로 바뀐다. 값이 바뀌었을 때만 다시 그린다. 배터리가 없으면 poll은
  지금처럼 무한 대기다.
- 시리얼 로그에 줄 셋이 생긴다 — `terminal: battery> scan seen=… present=… pick=…`(훑은 결과가 바뀔 때),
  `terminal: battery> read <이름> capacity=… status=… class=…`(읽은 값이 바뀔 때), `terminal: status> battery cell="…" ink norm=… plug=… low=…`
  (`dumpStatus`가 찍을 때마다, 배터리가 없으면 `cell=none`).
- `status> text=` 줄은 배터리가 있든 없든 BS 전과 글자가 같다(design 결정 6).
- 스물두번째 체인 `battery/check.sh`가 칸이 뜨고 · 바뀌고 · 사라지는 것과 색을 본다. machine 체인이 limine 부팅에 test_power가 없는
  것(`seen=0`)을 본다.
- 배터리가 없는 스물한 체인은 화면이 한 픽셀도 안 바뀐다. 시리얼 로그에는 `battery> scan seen=1 present=0 pick=none` 한 줄과 프레임마다
  `status> battery cell=none …` 한 줄이 더해진다.

## 착수 전에 확정한 것

2026-10-09. BS-M0의 구현이 작업 트리에 있고(커밋 전) 그 루트 게이트가 돌던 때다. design · BS-M0 plan · `main.zig` · 게이트 스크립트를
읽어 정했다. Docker는 안 켰다.

1. `battery.zig`는 그대로 부른다. 시그니처를 하나도 안 바꾼다. 쓰는 것은 `Status` · `statusName` · `parseStatus` · `parseCapacity` ·
   `counts` · `pick` · `Class` · `class` · `CELL_LEN` · `cellText` · `ueventIsPowerSupply` · `PERIOD_MS` · `pollTimeout`이다. `LOW_MAX`는 안
   쓴다(`class`가 쓴다).

2. 칸의 타입은 `main.zig`의 `BatteryCell`(`text: [4]u8` · `class: battery.Class`)이다. design 결정 6은 "`?battery.Cell` 또는 그에 해당하는
   것"이라고 했다. `battery.zig`에 `Cell`이 없고, 더하면 BS-M0이 검사를 끝낸 파일을 고치게 된다. 구조체는 값 둘을 담을 뿐이고 그 위에
   순수 함수가 없으므로 `main.zig`에 둔다 — `PointerDev`가 `main.zig`에 있는 것과 같다.

3. `seen`은 `battery.counts(kind, null, null)`로 센다. `present` · `scope`를 null로 넘기면 그 함수는 `type`만 본다(파일이 없는 것과 같다).
   `type`이 `Battery`인지 보는 비교를 `main.zig`에 다시 적지 않는다.

4. 파일 읽기의 실패는 셋으로 가른다(`SysfsWhy` — `no_file` = `ENOENT`, `no_device` = `ENODEV`, `other`). "배터리가 빠졌다"(`.gone`)는
   `status`가 `ENOENT` · `ENODEV`이거나 `capacity`가 `ENODEV`일 때다. design 결정 8은 "읽기가 `ENOENT` · `ENODEV`로 실패하면 다시
   훑는다"라고 했는데, `capacity`의 `ENOENT`만은 빠진 것으로 안 본다. ACPI에는 `capacity`를 아예 안 내는 배터리가 있고(design 확인 6),
   그 배터리에 `ENOENT`를 빠짐으로 보면 칸이 `  ?%`가 아니라 영영 안 뜨고 주기마다 다시 훑는다. `status`는 test_power · ACPI 둘 다 속성
   표에 언제나 있다. `status`의 그 밖의 실패는 `Unknown`, `capacity`의 그 밖의 실패는 "모른다"(`  ?%`)다(design 결정 3).

5. `present` · `scope` 파일은 "없다"뿐 아니라 "못 읽었다"도 null로 넘긴다. 그러면 `counts`가 "있다" · "통과"로 본다. test_power에서는
   밟히지 않는 갈래다(`present`는 언제나 읽히고 `scope`는 파일이 없다, BS-M0 plan 확정 2).

6. 시계. 처음 훑기 앞에서 `std.Io.Clock.now(.awake, init.io)`로 원점을 하나 잡고, 지금 시각은
   `@divTrunc(origin.untilNow(init.io, .awake).nanoseconds, 1_000_000)`의 밀리초다. 이 모양은 `main.zig`의 `find> submit`과 렌더 시간이
   이미 쓰는 것이다(`untilNow(…).nanoseconds`). `Timestamp`의 필드를 직접 읽지 않는 것은 그 필드 이름을 0.16에서 확인할 길이 없었기
   때문이다(호스트 0.17에는 `nanoseconds: i96`가 있다). 처음 훑기의 `now_ms`는 0이다 — 원점을 방금 잡았다.

7. 처음 훑기는 `needs_redraw`를 안 켠다. `needs_redraw`의 초기값이 false이고 첫 프레임은 셸의 첫 출력이 그린다. 처음 훑기가 그 앞이라 첫
   프레임의 `Status`에 칸이 이미 들어 있다(검사 B1). 여기서 켜면 셸보다 먼저 빈 프레임이 하나 그려져 스물한 체인 전부의 `screen>` 줄
   수가 하나씩 는다.

8. 다시 그리기와 메모의 비교가 다르다. 다시 그릴지는 `scanBattery` · `tickBattery`가 정한다 — 고른 이름이 바뀌었거나 칸(`?BatteryCell`)이
   `std.meta.eql`로 달라졌을 때 참이다. `dumpStatus`의 메모는 `sameBatteryCell`(글자와 갈래를 따로 비교하는 함수)을 쓴다. 같은 함수를 쓰면
   mutation m3(갈래를 뺀다)가 다시 그리기도 막아서, A4가 빨개졌을 때 메모 때문인지 안 그려서인지가 안 갈린다. 메모만 고장 난 판에서는
   화면은 초록으로 바뀌는데 새 `status>` 줄이 안 찍힌다 — design 결정 10이 말한 구멍이 정확히 그 모양이다.

9. 로그 줄은 design 결정 10의 모양 그대로다. 더한 규칙이 넷이다.
   - `scan` 줄은 처음 훑기에서 무조건, 그 뒤로는 `seen` · `present` · 고른 이름 중 하나라도 바뀌었을 때 찍는다. 디렉터리를 못 열면
     `terminal: battery> scan failed error=<Zig 에러 이름>`을 찍고 고른 것을 잊는다. 다음 훑기는 처음 훑기처럼 무조건 찍는다.
   - `read` 줄은 `(status, capacity)`가 지난 읽기와 다를 때 찍는다. 고른 배터리가 바뀌면 지난 읽기를 잊으므로 새 배터리의 첫 읽기는
     반드시 찍힌다. 잔량을 모르면 `capacity=?`다. `status=`는 커널의 글자(`statusName`)라 `Not charging`이면 값에 공백이 든다 — 이 줄을
     공백으로 나눠 읽는 판정은 없다.
   - `status> battery` 줄은 `dumpStatus`의 다섯째 줄이다(`dict ink` 뒤). 여백이 없는 화면에서는 `… low=0 (no room)`이다.
   - 전부 `logline.print` 한 번이다(AL).

10. `drawStatus`의 자리 산수. 칸의 시작 col은 `cols - 4`이고 x는 `GRID_X + (cols - 4) * CELL_W`다 — `drawRun`이 col을 받아 그 x를
    계산하므로 col만 넘긴다. 1280 × 800(게이트의 QEMU 화면 전부, BS-M0 체인 로그 29줄이 모두 `terminal: grid 155x47 (fb 1280x800)`)이면
    col 151, x 1228 ~ 1259다. 겹침 방지는 "왼쪽 문자열이 끝난 col + 2 > 151이면 안 그린다"이다. 2는 `status.zig`의 `GAP` 길이인데 그 이름이
    pub이 아니라서 `status.COPY_TAIL.len - status.COPY.len`으로 얻는다(design 결정 6이 `status.zig`를 안 고치기로 했다). 왼쪽 문자열의
    끝 col은 받아쓰기 칸을 그린 `drawRun`의 반환값이다 — 지금은 그 값을 `_ =`로 버리고 있어 `col =`로 바꾼다.

11. `Status`에 `cols: u16`과 `battery: ?BatteryCell`이 더해진다. `cols`는 `main`이 시작할 때 구한 격자 전체의 폭이고 패널의 폭이 아니다.
    `Status`를 만드는 자리는 `main`의 하나뿐이다(`rg 'Status = \.\{|: Status = '`가 한 줄).

12. `drainUevents`가 `bool`을 돌려준다 — power_supply를 하나라도 봤거나 `ENOBUFS`였으면 참이다. 부르는 자리는 하나뿐이고, 그 줄을
    `const supply_seen = fds[1].revents & c.POLLIN != 0 and drainUevents(…);`로 바꾼다. `and`는 앞이 거짓이면 뒤를 안 부르므로 지금처럼
    소켓에 읽을 것이 있을 때만 읽는다.

13. 배터리 블록의 자리는 `drainUevents` 바로 뒤다. 조건은 하나다 — `if (!needs_redraw) { … continue; }`보다 앞이어야 한다. 뒤면 키도 PTY
    출력도 없는 바퀴(uevent나 timeout으로만 깬 바퀴)에서 칸을 고쳐도 화면이 안 바뀐다. 그것이 검사 A3의 자리다.

14. 게이트 검사 A3의 방식. bash에서 `( sleep 5; echo 10 > battery_capacity ) &`를 친다. 판정은 셋이다.
    - 칸이 빨강 ` 10%`가 된다.
    - 그 칸을 그린 프레임의 `screen>` 줄이 바로 앞 프레임의 것과 글자까지 같다(`redraw_alone`). PTY 출력이 그 프레임에 끼었으면 다르다.
    - 앞 프레임부터 그 `status> battery` 줄까지 `key>` 줄이 없다.

    이 판정은 로그를 다 받은 뒤에 거꾸로 읽으므로, 게이트가 "프롬프트가 다 그려진 순간"을 맞혀 기준을 잡을 필요가 없다. 5초는 bash가
    `[1] <pid>`와 프롬프트를 다 그릴 여유다 — 그 프레임이 5초 넘게 늦으면 칸의 프레임과 겹쳐 둘째 판정이 거짓으로 빨갛다(design 위험이
    아니라 이 plan의 선택이다. 그렇게 빨개지면 구현자는 고치지 않고 보고하고, 수를 늘릴지는 lead가 정한다). 셋째 판정 때문에 A3에서는
    `type_keys`의 마지막 키(`ret`) 뒤로 아무것도 안 친다.

15. 코드를 본 범위. 이 plan의 편집을 `/tmp/run/bs1-plan/src/main.zig`(HEAD의 `main.zig` 사본)에 기계로 넣었고(`edits.py` · `apply.py`,
    열여덟 편집이 각각 정확히 한 번 맞았다) 호스트 zig 0.17로 `zig ast-check`가 에러 없이 끝났다. 배터리 절 · 색 상수 · 시계 산수는 따로
    뽑아(`bat_check.zig`) `zig build-obj -lc -fno-emit-bin`으로 타입까지 봤다. 그때 `std.fmt.bufPrintZ`만 0.17의 이름
    (`bufPrintSentinel`)으로 바꿨다 — 0.16에는 `bufPrintZ`가 있다(`tryOpenPointer`가 쓴다). 0.16의 컴파일 · 호스트 검사 · 체인은 Task 4 ·
    5가 처음 본다. `battery/check.sh` · `check.sh` · `machine/check.sh`는 사본에서 `bash -n`과 루트 `check.sh`의 진입 검사 셋
    (`require_build_steps` · `require_no_early_exit_pipe` · `require_explicit_nic`)을 지났다. 그 진입 검사가 machine의 첫 초안 한 줄을
    잡았다 — `[ … ] || ! grep -aqF …`처럼 `||` 뒤의 `grep -q`도 그 regex에 걸린다. 그래서 판정 14는 `if`를 둘로 나눴다.

16. 포트는 45494 하나다. `docs/guides/lessons.md`의 포트 목록이 "새 체인은 45494부터"라고 적는다. 부팅 B는 monitor가 없다.

17. BS-M0의 사본 실측(`/tmp/run/bs0/measure.out`)이 BS-M0 plan Task 6의 기대와 같았다 — `-kernel` 부팅의 `test_battery`는 `present [0]` ·
    `status [Discharging]` · `capacity [50]` · `scope [-]`이고, `-append test_power.battery_present=true`면 `present [1]`이고, ISO 부팅은
    `supplies []`이고, 세 부팅 다 `deliberately report errors` 줄이 0이다. 그래서 검사 A1 · A2 · B1과 machine 판정 14의 기대값이 그 값이다.
    test_power의 파라미터 setter는 끝의 줄바꿈을 떼고 대소문자를 안 가린다(`map_get_value`) — `echo true >`가 쓰는 `true\n`이 맞는다.

18. 검사 A5의 줄 수 판정(`scan` 셋 · `read` 셋)은 design에 없던 것이다. 훑기 줄 · 읽기 줄이 "바뀔 때만" 찍힌다는 것을 게이트가 보는
    자리가 이것뿐이다. A3 · A4의 uevent도 다시 훑지만 결과가 같으므로 `scan` 줄이 안 는다. 검사 A4의 픽셀 수 비교(초록 `plug=`이 A3의
    빨강 `low=`와 같다)도 더한 것이다 — 같은 넉 자를 색만 바꿔 칠했다는 증거이고 IS-M1의 `on=87 off=87`과 같은 종류다.

19. 중간 상태는 빌드하지 않는다. Task 1의 배터리 절이 Task 3의 색 상수를 쓰므로 Task 1 · 2 · 3만 넣은 파일은 컴파일되지 않는다(Zig의
    `AstGen`이 쓰이지 않는 함수의 이름도 찾는다). 빌드는 Task 4가 끝난 뒤 한 번이다. Task마다 보는 것은 `git diff --stat`의 수다.

20. (구현 중에 고침, 2026-10-09) 이 plan과 design 결정 11의 표가 잔량 10의 칸을 `  10%`(다섯 자)로 적었다. 칸은 `CELL_LEN` 넉 자라
    실제 글자는 ` 10%`(공백 하나)이고 `  5%`만 공백 둘이다. 코드는 맞았고 체인 A3의 패턴만 틀려 첫 battery 체인이 A3에서 빨갰다
    (실측 줄 `cell=" 10%" ink norm=0 plug=0 low=66`). lead가 두 문서의 글자를 고쳤고 구현자가 `battery/check.sh`를 고쳤다.

## Task 0: 바꾸기 전의 기준값

1. 돌고 있는 게이트나 컨테이너가 있는지, Docker가 켜져 있는지 본다.

   ```bash
   docker info >/dev/null 2>&1 && echo DOCKER-OK
   docker ps --format '{{.Names}} {{.Image}} {{.Status}}'
   ls -d /tmp/run/docker.lock 2>&1
   ```

   `DOCKER-OK`가 안 나오면 `orb start`를 치고 다시 본다. 컨테이너가 있으면 끝나기를 기다린다(위 lock 절차). 남의 컨테이너를 죽이지 않는다.

2. 작업 트리를 본다.

   ```bash
   cd /Users/dp/Repository/tars-linux && git status --short && git log --oneline -3
   ls terminal/src/battery.zig terminal/src/battery_test.zig battery 2>&1
   git diff --quiet terminal/src/main.zig check.sh machine/check.sh; echo "untouched exit=$?"
   rg -c 'battery' terminal/src/main.zig; echo "rg exit=$?"
   mkdir -p /tmp/run/bs1
   ```

   기대.
   - `battery.zig` · `battery_test.zig`가 있다. BS-M0이 commit됐으면 `git log`의 맨 위 근처에 그 commit이 있고, 아니면 `git status`에 BS-M0의
     일곱 파일(`boot/limine.conf` · `init/src/disk_test.zig` · `kernel/.config` · `terminal/build.zig` · `wifi/check.sh` · `??` 둘)이 있다. 둘 다
     괜찮다. 그 밖의 소스 파일이 `M`이면 멈추고 보고한다.
   - `ls`의 `battery`는 `No such file or directory`다.
   - `untouched exit=0` — 이 milestone이 고칠 세 파일이 아직 그대로다.
   - `rg -c`가 아무것도 안 찍고 `rg exit=1` — `main.zig`에 `battery`라는 낱말이 없다.

3. BS-M0의 루트 게이트가 끝났는지 본다. lead가 commit 전에 그 게이트를 돌리고 있다. Task 5부터 Docker가 필요하므로, lock이 있으면 기다린다.

## Task 1: 배터리 절 — 시스템 콜 층

design 결정 1 · 2 · 3 · 4 · 7 · 8 · 10. 편집 둘이다. `battery.zig`를 import하고, 받아쓰기 절과 포인터 절 사이에 배터리 절을 넣는다.

배터리 절에 들어가는 것(위에서 아래 순서).

| 이름 | 하는 일 |
|---|---|
| `BATTERY_DIR` · `BATTERY_NAME_MAX` · `BATTERY_PATH_MAX` · `BATTERY_FILE_MAX` · `BATTERY_MAX` | 디렉터리와 버퍼 크기 |
| `BatteryCell` | 칸 하나 — 글자 넉 자와 갈래(확정 2) |
| `BatteryRead` | 마지막으로 읽은 `status` · `capacity`. `read` 줄의 메모 |
| `BatteryState` | 고른 이름 · 지난 `seen`/`present` · 지난 읽기 · 칸 · 기한 |
| `SysfsWhy` · `SysfsRead` · `readSysfs` | 파일 하나를 한 번 읽고, 실패를 셋으로 가른다(확정 4) |
| `scanBattery` | 디렉터리를 훑어 `counts`로 거르고 `pick`으로 고르고 읽는다. `scan` 줄 · `scan failed` 줄 |
| `readBattery` | 고른 배터리의 두 파일 → `class` · `cellText` → 칸, 기한 = 지금 + 60초. `read` 줄 |
| `tickBattery` | 주기 읽기. 빠졌으면 다시 훑는다 |
| `batteryColor` | 갈래 → 색 상수(Task 3이 정의한다) |
| `sameBatteryCell` | `dumpStatus`의 메모가 쓰는 비교(확정 8) |
| `dumpBatteryInk` | `status> battery` 줄 |

### 편집 1a — import

`terminal/src/main.zig` — `old_string`:

```zig
const logline = @import("logline.zig");
const clipboard = @import("clipboard.zig");
```

`new_string`:

```zig
const logline = @import("logline.zig");
const battery = @import("battery.zig");
const clipboard = @import("clipboard.zig");
```

### 편집 1b — 배터리 절

`old_string`은 포인터 절의 머리 줄 하나다. `new_string`은 배터리 절 전체와, 그 뒤에 같은 머리 줄이다.

`terminal/src/main.zig` — `old_string`:

```zig
// ── 포인터 장치(PD-M0) ───────────────────────────────────────────────
```

`new_string`:

```zig
// ── 배터리(BS-M1) ─────────────────────────────────────────────────────
//
// 훑고 읽는 시스템 콜 쪽이다. 판단(거르기 · 고르기 · 칸 글자 · 갈래 · timeout)은 전부
// `battery.zig`에 있고 여기는 파일 · 디렉터리 · 로그만 다룬다(BS design 결정 7). 포인터
// 절과 같은 경계다.

/// power_supply 장치가 모이는 디렉터리(BS design 결정 1). 항목은 장치 디렉터리로 가는
/// 심볼릭 링크이고, 이름은 기계마다 다르다(`BAT0` · `BAT1` · `test_battery`).
const BATTERY_DIR = "/sys/class/power_supply";
/// 장치 이름의 상한. 실기에서 긴 이름은 UCSI의 `ucsi-source-psy-USBC000:001`(27자)
/// 정도다. 넘는 이름은 고를 후보에서 빼고 `seen` · `present`에는 센다.
const BATTERY_NAME_MAX = 64;
/// `BATTERY_DIR/<이름>/<파일>`과 NUL. 23 + 1 + 64 + 1 + 8(`capacity`) + 1 = 98바이트다.
const BATTERY_PATH_MAX = 128;
/// 파일 하나의 내용. 가장 긴 값이 `Not charging`과 줄바꿈(13바이트)이다.
const BATTERY_FILE_MAX = 64;
/// 한 번의 훑기에서 고를 후보의 상한. 넘으면 나머지를 후보에서 빼고 `present`에는 센다.
const BATTERY_MAX = 8;

/// 상태 줄의 배터리 칸 하나(BS design 결정 4 · 5). 글자 넉 자와 색의 갈래다.
///
/// 둘을 함께 드는 이유는 결정 10이다. 잔량이 그대로인 채 어댑터를 꽂으면 글자(` 50%`)는
/// 그대로이고 갈래만 바뀐다 — 하나만 들면 그 전환이 화면에도 로그에도 안 나온다.
const BatteryCell = struct {
    text: [battery.CELL_LEN]u8,
    class: battery.Class,
};

/// 고른 배터리에서 마지막으로 읽은 값. `battery> read` 줄은 이것이 바뀔 때만 찍는다.
const BatteryRead = struct {
    status: battery.Status,
    capacity: ?u8,
};

/// 배터리 절의 상태 전부. `main`이 하나를 들고 부르는 함수마다 넘긴다.
const BatteryState = struct {
    /// 고른 배터리의 이름. `pick_len`이 0이면 고른 것이 없다 — 장치 이름은 비어 있을 수 없다.
    name: [BATTERY_NAME_MAX]u8 = undefined,
    pick_len: usize = 0,
    /// 지난 훑기의 `seen` · `present`(design 결정 10). `scan` 줄은 이 둘과 고른 이름이
    /// 바뀔 때만 찍는다.
    seen: usize = 0,
    present: usize = 0,
    /// 한 번이라도 훑었는가. 처음 훑기는 결과가 무엇이든 찍는다 — 기준선이 없으면 게이트가
    /// "부팅 직후의 배터리"를 볼 창구가 없다(`dumpStatus`의 첫 프레임과 같은 이유).
    scanned: bool = false,
    /// 지난 읽기. 고른 배터리가 바뀌면 null로 돌려서 새 배터리의 첫 읽기가 반드시 찍힌다.
    last_read: ?BatteryRead = null,
    /// 상태 줄에 그릴 칸. 고른 배터리가 없으면 null이고, 그러면 화면이 BS 전과 한 픽셀도
    /// 안 다르다(design 목표 3).
    cell: ?BatteryCell = null,
    /// 다음 주기 읽기의 시각(`main`이 잡은 원점부터의 단조 시계 밀리초). 고른 배터리가
    /// 없으면 null이고 poll은 무한 대기다(`battery.pollTimeout`).
    due: ?i64 = null,

    fn pickName(self: *const BatteryState) ?[]const u8 {
        if (self.pick_len == 0) return null;
        return self.name[0..self.pick_len];
    }
};

/// sysfs 파일을 못 읽은 이유. `readBattery`가 셋을 다르게 다룬다.
const SysfsWhy = enum {
    ok,
    /// `ENOENT` — 파일이 없다. 속성 표에 없는 속성이거나(test_power의 `scope`) 장치가 빠졌다.
    no_file,
    /// `ENODEV` — 연 사이에 장치가 빠졌다.
    no_device,
    /// 그 밖의 실패. ACPI 배터리의 `_BST` 평가가 실패하면 `EIO` 같은 것이 온다.
    other,
};

/// sysfs 파일 하나를 읽은 결과. `bytes`가 null이면 못 읽었고 그 이유가 `why`다.
const SysfsRead = struct {
    bytes: ?[]const u8,
    why: SysfsWhy = .ok,
};

/// `BATTERY_DIR/<name>/<file>`을 한 번 읽는다. sysfs의 속성 파일은 `show` 한 번이 내용
/// 전부라 read 한 번으로 끝난다.
///
/// errno는 실패한 호출 바로 뒤에 읽는다 — `close`가 errno를 덮을 수 있다.
fn readSysfs(name: []const u8, file: []const u8, buf: *[BATTERY_FILE_MAX]u8) SysfsRead {
    var path_buf: [BATTERY_PATH_MAX]u8 = undefined;
    const path = std.fmt.bufPrintZ(&path_buf, BATTERY_DIR ++ "/{s}/{s}", .{ name, file }) catch
        return .{ .bytes = null, .why = .other };
    const fd = std.c.open(path, .{ .ACCMODE = .RDONLY, .CLOEXEC = true });
    if (fd >= 0) {
        const n = std.c.read(fd, buf, buf.len);
        if (n >= 0) {
            _ = std.c.close(fd);
            return .{ .bytes = buf[0..@intCast(n)] };
        }
    }
    const why: SysfsWhy = switch (std.c.errno(-1)) {
        .NOENT => .no_file,
        .NODEV => .no_device,
        else => .other,
    };
    if (fd >= 0) _ = std.c.close(fd);
    return .{ .bytes = null, .why = why };
}

/// 디렉터리를 훑어 칸에 들어갈 배터리를 고르고, 고른 것을 읽는다(BS design 결정 1 · 2 · 8).
/// 처음 훑기와, uevent가 power_supply를 알렸을 때 부른다.
///
/// 고른 이름이나 칸(글자 · 갈래)이 바뀌었으면 참이다. 부르는 쪽은 그때만 다시 그린다 —
/// 값이 그대로인 uevent가 다시 그리기를 부르면 배터리가 없는 체인에도 `screen>` 프레임이
/// 하나 더 생긴다(design 결정 8 · 위험 6).
///
/// `seen`은 `type`이 `Battery`인 장치의 수다. `counts`에 `present` · `scope`를 null로 넘기면
/// 그 함수는 `type`만 본다 — 같은 비교를 여기 다시 적지 않는다.
///
/// 디렉터리를 못 열면 `scan failed` 줄을 찍고 고른 것을 잊는다. terminal은 산다 — 칸이
/// 없을 뿐이다. 그다음 훑기는 처음 훑기처럼 결과를 찍는다.
fn scanBattery(io: std.Io, bat: *BatteryState, now_ms: i64) bool {
    var dir = std.Io.Dir.openDirAbsolute(io, BATTERY_DIR, .{ .iterate = true }) catch |err| {
        logline.print("terminal: battery> scan failed error={s}\n", .{@errorName(err)});
        const had = bat.pick_len != 0 or bat.cell != null;
        bat.* = .{};
        return had;
    };
    defer dir.close(io);

    var name_bufs: [BATTERY_MAX][BATTERY_NAME_MAX]u8 = undefined;
    var names: [BATTERY_MAX][]const u8 = undefined;
    var n_names: usize = 0;
    var seen: usize = 0;
    var present: usize = 0;
    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        var kind_buf: [BATTERY_FILE_MAX]u8 = undefined;
        var present_buf: [BATTERY_FILE_MAX]u8 = undefined;
        var scope_buf: [BATTERY_FILE_MAX]u8 = undefined;
        // `type`을 못 읽는 장치는 무엇인지 모르므로 안 센다.
        const kind = readSysfs(entry.name, "type", &kind_buf).bytes orelse continue;
        if (!battery.counts(kind, null, null)) continue;
        seen += 1;
        // 파일이 없거나 못 읽으면 null이다. `counts`는 그것을 "있다" · "통과"로 본다
        // (design 결정 1의 표). test_battery에는 `scope`가 없다(BS-M0 plan 확정 2).
        const pres = readSysfs(entry.name, "present", &present_buf).bytes;
        const scope = readSysfs(entry.name, "scope", &scope_buf).bytes;
        if (!battery.counts(kind, pres, scope)) continue;
        present += 1;
        if (n_names == BATTERY_MAX or entry.name.len > BATTERY_NAME_MAX) continue;
        @memcpy(name_bufs[n_names][0..entry.name.len], entry.name);
        names[n_names] = name_bufs[n_names][0..entry.name.len];
        n_names += 1;
    }
    const picked = battery.pick(names[0..n_names]);

    const old = bat.pickName();
    const name_changed = if (old) |o| (picked == null or !std.mem.eql(u8, o, picked.?)) else picked != null;
    if (!bat.scanned or name_changed or seen != bat.seen or present != bat.present) {
        logline.print("terminal: battery> scan seen={d} present={d} pick={s}\n", .{ seen, present, picked orelse "none" });
    }
    bat.scanned = true;
    bat.seen = seen;
    bat.present = present;
    if (name_changed) {
        if (picked) |p| {
            @memcpy(bat.name[0..p.len], p);
            bat.pick_len = p.len;
        } else {
            bat.pick_len = 0;
        }
        bat.last_read = null;
    }

    const old_cell = bat.cell;
    if (bat.pickName() == null) {
        bat.cell = null;
        bat.due = null;
    } else if (readBattery(bat, now_ms) == .gone) {
        // 훑은 사이에 빠졌다. 칸을 지우고 다음 주기에 다시 본다 — 그 읽기도 실패하면
        // `tickBattery`가 다시 훑는다. 빠진 것을 알리는 uevent가 대개 그보다 먼저 온다.
        bat.cell = null;
        bat.due = now_ms + battery.PERIOD_MS;
    }
    return name_changed or !std.meta.eql(old_cell, bat.cell);
}

/// 고른 배터리의 `status` · `capacity`를 읽어 칸을 짓고 다음 주기를 정한다(BS design
/// 결정 3 · 4 · 5 · 8).
///
/// `.gone`이면 장치가 빠졌다는 뜻이고 아무것도 안 바꾼다 — `status`가 `ENOENT` · `ENODEV`이거나
/// `capacity`가 `ENODEV`일 때다. `capacity`의 `ENOENT`는 빠진 것이 아니다. ACPI에는 잔량을
/// 아예 안 내는 배터리가 있고(design 확인 6) 그 칸은 `  ?%`다. `status`의 그 밖의 실패는
/// `Unknown`, `capacity`의 그 밖의 실패는 "모른다"다(결정 3).
///
/// `battery> read` 줄은 읽은 값이 지난번과 다를 때만 찍는다(결정 10). `status=`는 커널의
/// 글자 그대로라 `Not charging`이면 값에 공백이 든다.
fn readBattery(bat: *BatteryState, now_ms: i64) enum { ok, gone } {
    const name = bat.pickName() orelse return .gone;
    var status_buf: [BATTERY_FILE_MAX]u8 = undefined;
    var cap_buf: [BATTERY_FILE_MAX]u8 = undefined;
    const status_file = readSysfs(name, "status", &status_buf);
    const cap_file = readSysfs(name, "capacity", &cap_buf);
    if (status_file.why == .no_file or status_file.why == .no_device or cap_file.why == .no_device) return .gone;

    const got: BatteryRead = .{
        .status = battery.parseStatus(status_file.bytes orelse ""),
        .capacity = if (cap_file.bytes) |b| battery.parseCapacity(b) else null,
    };
    const cls = battery.class(got.status, got.capacity);
    if (!std.meta.eql(bat.last_read, @as(?BatteryRead, got))) {
        var num_buf: [3]u8 = undefined;
        const cap_text: []const u8 = if (got.capacity) |v|
            (std.fmt.bufPrint(&num_buf, "{d}", .{v}) catch "?")
        else
            "?";
        logline.print("terminal: battery> read {s} capacity={s} status={s} class={s}\n", .{
            name, cap_text, battery.statusName(got.status), @tagName(cls),
        });
    }
    bat.last_read = got;
    var cell: BatteryCell = .{ .text = undefined, .class = cls };
    _ = battery.cellText(got.capacity, &cell.text);
    bat.cell = cell;
    bat.due = now_ms + battery.PERIOD_MS;
    return .ok;
}

/// 주기 읽기(BS design 결정 8). 기한이 지났을 때만 부른다. 고른 배터리의 두 파일만 읽고,
/// 빠졌으면(그 uevent를 놓쳤다) 디렉터리를 다시 훑는다. 칸이 바뀌었으면 참이다.
fn tickBattery(io: std.Io, bat: *BatteryState, now_ms: i64) bool {
    const old_cell = bat.cell;
    if (readBattery(bat, now_ms) == .gone) return scanBattery(io, bat, now_ms);
    return !std.meta.eql(old_cell, bat.cell);
}

/// 갈래 → 색(BS design 결정 5).
fn batteryColor(cls: battery.Class) u32 {
    return switch (cls) {
        .normal => STATUS_BAT,
        .plugged => STATUS_BAT_PLUG,
        .low => STATUS_BAT_LOW,
    };
}

/// `dumpStatus`의 메모가 배터리 칸을 비교한다(BS design 결정 10). 글자와 갈래를 둘 다 본다.
///
/// 갈래를 빼면 IS-M1이 `CAPS`에서 겪은 구멍이 다시 생긴다 — 잔량이 그대로인 채 어댑터를
/// 꽂으면 글자는 그대로이고 색만 바뀌어서, 화면은 초록인데 새 `status>` 줄이 안 찍힌다.
/// battery 체인의 검사 A4가 그 자리를 본다.
///
/// 다시 그릴지를 정하는 쪽(`scanBattery` · `tickBattery`)은 이 함수가 아니라
/// `std.meta.eql`로 칸 전체를 비교한다. 이 함수를 고친 mutation이 메모만 건드리게 하려는
/// 것이다(BS-M1 plan Task 7) — 같은 함수를 쓰면 A4가 빨개져도 메모 때문인지 다시 그리기를
/// 안 해서인지가 안 갈린다.
fn sameBatteryCell(a: ?BatteryCell, b: ?BatteryCell) bool {
    const x = a orelse return b == null;
    const y = b orelse return false;
    return std.mem.eql(u8, &x.text, &y.text) and x.class == y.class;
}

/// `status> battery` 줄(BS design 결정 10). `dumpStatus`가 `status>` 줄들의 끝에 부른다.
///
/// 색 셋을 한 줄에 함께 찍는다 — `caps ink`와 같은 이유로, 하나만 보면 "안 그렸다"와
/// "다른 색으로 그렸다"가 안 갈린다. `cell=`의 값을 따옴표로 감싸는 것은 앞의 공백이
/// 값이기 때문이다(` 50%`). `tail`은 여백이 없을 때의 ` (no room)`이고 보통은 빈 문자열이다.
fn dumpBatteryInk(cell: ?BatteryCell, norm: usize, plug: usize, low: usize, tail: []const u8) void {
    if (cell) |b| {
        logline.print("terminal: status> battery cell=\"{s}\" ink norm={d} plug={d} low={d}{s}\n", .{ &b.text, norm, plug, low, tail });
    } else {
        logline.print("terminal: status> battery cell=none ink norm={d} plug={d} low={d}{s}\n", .{ norm, plug, low, tail });
    }
}

// ── 포인터 장치(PD-M0) ───────────────────────────────────────────────
```

### 1-3. 확인

```bash
cd /Users/dp/Repository/tars-linux && git diff --stat terminal/src/main.zig && git diff terminal/src/main.zig | rg '^-'
```

기대: `1 file changed, 270 insertions(+)`, `rg '^-'`는 `--- a/terminal/src/main.zig` 한 줄. 빌드는 아직 안 한다(확정 19).

## Task 2: 갱신 배선 — uevent · 처음 훑기 · poll timeout · 주기

design 결정 8. 편집 넷이다.

- 2a — `drainUevents`가 `bool`을 돌려준다(확정 12). power_supply는 `battery.ueventIsPowerSupply`가 가른다. `ENOBUFS`도 참이다.
- 2b — 처음 훑기. `scanPointers` 바로 뒤다(확정 6 · 7).
- 2c — poll의 timeout이 `battery.pollTimeout(지금, 기한)`이 된다. 고른 배터리가 없으면 기한이 null이고 답이 -1이라 지금과 같다.
- 2d — poll 뒤의 배터리 블록. uevent가 power_supply를 봤으면 다시 훑고, 아니면 기한이 지났을 때만 읽는다. 칸이 바뀌었을 때만
  `needs_redraw`를 켠다(확정 13).

### 편집 2a — `drainUevents`

`terminal/src/main.zig` — `old_string`:

```zig
/// 버린 것이다 — 놓친 장치가 있을 수 있으므로 디렉터리를 다시 훑는다. 이미
/// 연 경로는 건너뛴다.
fn drainUevents(fd: c_int, io: std.Io, devs: *[pointer.MAX_DEVICES]?PointerDev) void {
    // 커널 uevent 하나는 `UEVENT_BUFFER_SIZE`(2048바이트) 안이다.
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = std.c.read(fd, &buf, buf.len);
        if (n < 0) {
            if (std.c.errno(n) != .NOBUFS) return; // EAGAIN — 다 읽었다
            scanPointers(io, devs);
            continue;
        }
        if (n == 0) return;
        const name = pointer.ueventAddedNode(buf[0..@intCast(n)]) orelse continue;
        tryOpenPointer(devs, name);
    }
}
```

`new_string`:

```zig
/// 버린 것이다 — 놓친 장치가 있을 수 있으므로 디렉터리를 다시 훑는다. 이미
/// 연 경로는 건너뛴다.
///
/// power_supply의 uevent를 하나라도 봤으면 참이다(BS-M1, design 결정 8). 이름도
/// `ACTION`도 안 본다 — test_power가 배터리를 켜고 끄는 uevent는 `test_battery`가
/// 아니라 `test_ac`에서 오고(BS design 확인 4), 배터리를 갈아 끼우면 `add` · `remove`가
/// 온다. `ENOBUFS`도 참이다. 버려진 메시지에 power_supply가 있었을 수 있다.
fn drainUevents(fd: c_int, io: std.Io, devs: *[pointer.MAX_DEVICES]?PointerDev) bool {
    // 커널 uevent 하나는 `UEVENT_BUFFER_SIZE`(2048바이트) 안이다.
    var buf: [4096]u8 = undefined;
    var supply = false;
    while (true) {
        const n = std.c.read(fd, &buf, buf.len);
        if (n < 0) {
            if (std.c.errno(n) != .NOBUFS) return supply; // EAGAIN — 다 읽었다
            scanPointers(io, devs);
            supply = true;
            continue;
        }
        if (n == 0) return supply;
        const msg = buf[0..@intCast(n)];
        if (battery.ueventIsPowerSupply(msg)) supply = true;
        const name = pointer.ueventAddedNode(msg) orelse continue;
        tryOpenPointer(devs, name);
    }
}
```

### 편집 2b — 처음 훑기

`terminal/src/main.zig` — `old_string`:

```zig
    touchpad_screen = .{ .w = fb.width, .notch_px = ROW_HEIGHT * @as(u32, @intCast(WHEEL_ROWS)) };
    scanPointers(init.io, &pointer_devs);
```

`new_string`:

```zig
    touchpad_screen = .{ .w = fb.width, .notch_px = ROW_HEIGHT * @as(u32, @intCast(WHEEL_ROWS)) };
    scanPointers(init.io, &pointer_devs);

    // 배터리(BS-M1, design 결정 8). 포인터와 같은 이유로 uevent 소켓을 연 뒤에 훑는다 —
    // 반대면 훑은 뒤 소켓을 열기 전에 생긴 배터리를 놓친다.
    //
    // 시계의 원점을 여기서 잡는다. 주기의 기한은 이 시각부터의 밀리초다. 렌더 시간을 재는
    // 것과 같은 단조 시계(`.awake`)이고, 커널에 `SUSPEND`가 없어서 잠든 시간은 따질 일이 없다.
    //
    // 처음 훑기는 다시 그리기를 안 켠다. 첫 프레임은 셸의 첫 출력이 그리고, 그 프레임의 상태
    // 줄에 칸이 이미 있다(battery 체인 검사 B1). 여기서 켜면 셸보다 먼저 프레임이 하나 더
    // 그려져 모든 체인의 `screen>` 줄 수가 바뀐다.
    const battery_clock = std.Io.Clock.now(.awake, init.io);
    var battery_state: BatteryState = .{};
    _ = scanBattery(init.io, &battery_state, 0);
```

### 편집 2c — poll timeout

`terminal/src/main.zig` — `old_string`:

```zig
        // -1 = 무한 대기. 이벤트가 없으면 CPU를 전혀 쓰지 않는다.
        const ready = c.poll(&fds, @intCast(nfds), -1);
```

`new_string`:

```zig
        // 고른 배터리가 없으면 -1(무한 대기)이다. 이벤트가 없으면 CPU를 전혀 쓰지 않는다.
        // 있으면 다음 주기 읽기까지의 밀리초다(BS design 결정 8) — 한 시간에 60번 깬다.
        // 키 때문에 깼든 timeout으로 깼든, 읽는 것은 아래에서 기한이 지났을 때뿐이다.
        const poll_now: i64 = @intCast(@divTrunc(battery_clock.untilNow(init.io, .awake).nanoseconds, 1_000_000));
        const ready = c.poll(&fds, @intCast(nfds), battery.pollTimeout(poll_now, battery_state.due));
```

### 편집 2d — poll 뒤의 배터리 블록

`terminal/src/main.zig` — `old_string`:

```zig
        if (fds[1].revents & c.POLLIN != 0) drainUevents(uevent_fd, init.io, &pointer_devs);
        if (pointerCount(&pointer_devs) == 0) pointer_shown = false;
```

`new_string`:

```zig
        const supply_seen = fds[1].revents & c.POLLIN != 0 and drainUevents(uevent_fd, init.io, &pointer_devs);
        // 배터리(BS-M1, design 결정 8). uevent가 power_supply를 봤으면(또는 메시지가
        // 버려졌으면) 디렉터리를 다시 훑는다. 아니면 기한이 지났을 때만 고른 배터리를
        // 읽는다 — 키를 칠 때마다 읽지 않는다. 어느 쪽이든 칸이 바뀌었을 때만 다시 그린다.
        //
        // 아래 `!needs_redraw`의 `continue`보다 앞이어야 한다. 뒤면 키도 PTY 출력도 없는
        // 바퀴(uevent나 timeout으로만 깬 바퀴)에서 칸을 고쳐도 화면이 안 바뀐다(검사 A3).
        {
            const bat_now: i64 = @intCast(@divTrunc(battery_clock.untilNow(init.io, .awake).nanoseconds, 1_000_000));
            const changed = if (supply_seen)
                scanBattery(init.io, &battery_state, bat_now)
            else if (battery_state.due) |due|
                bat_now >= due and tickBattery(init.io, &battery_state, bat_now)
            else
                false;
            if (changed) needs_redraw = true;
        }
        if (pointerCount(&pointer_devs) == 0) pointer_shown = false;
```

### 2-5. 확인

```bash
cd /Users/dp/Repository/tars-linux && git diff --stat terminal/src/main.zig && git diff terminal/src/main.zig | rg '^-'
```

기대: `1 file changed, 318 insertions(+), 7 deletions(-)`. `rg '^-'`는 머리 한 줄과 아래 일곱 줄이다.

```
-fn drainUevents(fd: c_int, io: std.Io, devs: *[pointer.MAX_DEVICES]?PointerDev) void {
-            if (std.c.errno(n) != .NOBUFS) return; // EAGAIN — 다 읽었다
-        if (n == 0) return;
-        const name = pointer.ueventAddedNode(buf[0..@intCast(n)]) orelse continue;
-        // -1 = 무한 대기. 이벤트가 없으면 CPU를 전혀 쓰지 않는다.
-        const ready = c.poll(&fds, @intCast(nfds), -1);
-        if (fds[1].revents & c.POLLIN != 0) drainUevents(uevent_fd, init.io, &pointer_devs);
```

## Task 3: 그리기 — 색 셋 · `Status` · `drawStatus`

design 결정 5 · 6. 편집 넷이다.

- 3a — 색 상수 셋과 `STATUS_BAT_GAP`. `STATUS_DICT` 바로 뒤다. 주석이 "왜 전용 색인가"를 기존 상수의 규칙대로 적는다.
- 3b — `drawStatus`의 끝. 받아쓰기 칸의 반환값을 `col`에 받고(확정 10), 오른쪽 끝에 칸을 그린다.
- 3c — `Status`에 필드 둘(확정 11).
- 3d — `main`에서 `Status`를 만드는 자리에 두 값.

`renderFinish`는 안 고친다. `drawStatus(fb, cache, st)`를 이미 부르고, 칸은 `st` 안에 있다.

### 편집 3a — 색 상수

`terminal/src/main.zig` — `old_string`:

```zig
const STATUS_DICT: u32 = 0x00F07070;
```

`new_string`:

```zig
const STATUS_DICT: u32 = 0x00F07070;

/// 배터리 칸의 색 셋(BS design 결정 5). 방전 중이거나 잔량을 모르면 `STATUS_BAT`(회색),
/// 어댑터가 꽂혀 있으면(`Charging` · `Full` · `Not charging`) `STATUS_BAT_PLUG`(초록),
/// 꽂혀 있지 않고 15% 이하면 `STATUS_BAT_LOW`(빨강)다. 고르는 것은 `battery.class`다.
///
/// 셋 다 전용 색인 이유는 `STATUS_COPY`와 같다(CI design 결정 3). `dumpStatus`가 띠 전체에서
/// 이 셋의 픽셀을 세어 `status> battery` 줄로 찍는데, 다른 칸이 같은 색을 쓰면 그 수가 이
/// 칸만 세지 않는다. `STATUS_BAT`이 눈에는 `STATUS_FG`와 거의 같은 회색인데 값이 다른 것도
/// 그 때문이다 — 재사용하면 배터리가 있는 부팅에서 `ink fg=`(hangul 체인의 기준값)가 바뀌고
/// 배터리 칸을 따로 셀 길이 없다. 초록이 밝고 빨강이 어두운 것은 적록 색약에서도 둘이
/// 갈리게 하려는 것이다(design 위험 4). 여백 · 상태 줄 색 다섯 · 구분선 · 매치 색 둘 · 커서 ·
/// 화살표 둘 어느 것과도 다르다.
const STATUS_BAT: u32 = 0x00909AA0;
const STATUS_BAT_PLUG: u32 = 0x0060C070;
const STATUS_BAT_LOW: u32 = 0x00E05040;

/// 배터리 칸과 왼쪽 문자열 사이에 남겨야 하는 칸 수(BS design 결정 6). 상태 줄이 칸을
/// 가르는 두 칸(`status.zig`의 `GAP`)과 같다. 그 이름은 pub이 아니고 design이 `status.zig`를
/// 안 고치기로 했으므로 `COPY_TAIL`(= `GAP ++ COPY`)에서 길이를 얻는다 — 2로 다시 적으면
/// `GAP`을 고친 사람이 이 파일을 안 고쳐도 컴파일이 통과한다.
const STATUS_BAT_GAP: u32 = status.COPY_TAIL.len - status.COPY.len;
```

### 편집 3b — `drawStatus`의 오른쪽 끝

`terminal/src/main.zig` — `old_string`:

```zig
    // 받아쓰기 칸(VD-M1). 받아쓰기가 없으면 빈 슬라이스다.
    _ = try drawRun(fb, cache, st.text[dict_at..], y, STATUS_DICT, col, fb.width);
}
```

`new_string`:

```zig
    // 받아쓰기 칸(VD-M1). 받아쓰기가 없으면 빈 슬라이스다.
    col = try drawRun(fb, cache, st.text[dict_at..], y, STATUS_DICT, col, fb.width);

    // 배터리 칸(BS-M1, design 결정 6). 왼쪽 문자열과 따로 오른쪽 끝에 그린다 — 넉 자의
    // 오른쪽 끝이 격자의 오른쪽 끝(`GRID_X + cols * CELL_W`)과 같다. 1280 × 800이면 격자가
    // 155칸이라 칸은 151 ~ 154번, x는 1228 ~ 1259다.
    //
    // 왼쪽 문자열의 끝 col에서 `STATUS_BAT_GAP`만큼 안 떨어져 있으면 안 그린다. 지금 가장
    // 긴 왼쪽 줄은 약 50칸이라 닿을 일이 없지만, `setPixel`에 범위 검사가 없는 저장소에서
    // 겹침을 산수로 막는 자리는 있어야 한다. 겹쳐 그리면 두 칸의 픽셀이 섞여 `dumpStatus`의
    // 셈도 틀린다.
    const cell = st.battery orelse return;
    if (st.cols < battery.CELL_LEN) return;
    const bat_col = @as(u32, st.cols) - battery.CELL_LEN;
    if (col + STATUS_BAT_GAP > bat_col) return;
    _ = try drawRun(fb, cache, &cell.text, y, batteryColor(cell.class), bat_col, fb.width);
}
```

### 편집 3c — `Status`의 필드 둘

`terminal/src/main.zig` — `old_string`:

```zig
    /// 받아쓰기 칸(VD-M1). 없으면 null이다. `workspace`와 같은 이유로 따로 나른다.
    dict: ?dictation.Show,
};
```

`new_string`:

```zig
    /// 받아쓰기 칸(VD-M1). 없으면 null이다. `workspace`와 같은 이유로 따로 나른다.
    dict: ?dictation.Show,
    /// 격자 전체의 칸 수(BS-M1). 배터리 칸의 자리가 격자의 오른쪽 끝이라 `drawStatus`가
    /// 이것으로 x를 센다(BS design 결정 6). `main`이 시작할 때 구한 `cols`이고 패널의
    /// 폭이 아니다.
    cols: u16,
    /// 배터리 칸(BS-M1). 고른 배터리가 없으면 null이고 아무것도 안 그린다.
    ///
    /// `text`에 안 들어 있다. 왼쪽 문자열과 따로 오른쪽 끝에 그리므로 `status.statusText`와
    /// `status> text=`가 BS 전과 같다(design 결정 6).
    battery: ?BatteryCell,
};
```

### 편집 3d — `Status`를 만드는 자리

`terminal/src/main.zig` — `old_string`:

```zig
            .workspace = ws_number,
            .dict = dict.show(),
        };
```

`new_string`:

```zig
            .workspace = ws_number,
            .dict = dict.show(),
            .cols = cols,
            // 배터리 절이 고친 칸(BS-M1). 이 프레임을 부른 것이 배터리가 아니어도 지금 값을 그린다.
            .battery = battery_state.cell,
        };
```

### 3-5. 확인

```bash
cd /Users/dp/Repository/tars-linux && git diff --stat terminal/src/main.zig && git diff terminal/src/main.zig | rg '^-' | rg -c -v '^---'
```

기대: `1 file changed, 366 insertions(+), 8 deletions(-)`과 `8`. 늘어난 `-` 줄 하나는
`-    _ = try drawRun(fb, cache, st.text[dict_at..], y, STATUS_DICT, col, fb.width);`다.

## Task 4: `dumpStatus` — 메모와 `status> battery` 줄, 그리고 첫 빌드

design 결정 10. 편집 여덟이다.

- 4a — 함수 주석에 다섯째 줄의 설명. `status> text=`가 안 바뀐다는 것을 적는다.
- 4b — 메모 인자 하나(`last_battery: *?BatteryCell`)와 비교 · 저장. 비교는 `sameBatteryCell`이다(확정 8).
- 4c — 여백이 없는 갈래에도 `status> battery … (no room)`.
- 4d · 4e — 띠를 훑는 같은 루프에서 세 색을 센다. x 범위를 안 잰다 — 세 색이 여백에서 이 칸에만 쓰인다.
- 4f — `dict ink` 줄 뒤에 `status> battery` 줄.
- 4g — `main`의 메모 변수 하나.
- 4h — `dumpStatus`를 부르는 자리.

`status> text=` 줄은 그대로다 — 그 줄의 fmt도 `st.text`도 안 바뀐다. 다만 메모가 넓어져서, 배터리 칸만 바뀐 프레임에도 `text=` 줄이 같은
글자로 한 번 더 찍힌다(`CAPS`만 바뀐 프레임과 같다).

### 편집 4a — 함수 주석

`terminal/src/main.zig` — `old_string`:

```zig
/// `render` 뒤에 불러야 한다. 그 전에 부르면 이전 프레임의 픽셀을 읽는다.
fn dumpStatus(
```

`new_string`:

```zig
/// 다섯째 줄(`status> battery`)은 오른쪽 끝의 배터리 칸이다(BS-M1). 칸의 글자와 색 셋의
/// 픽셀 수를 함께 찍고, 배터리가 없으면 `cell=none`이다. `text=` 줄은 배터리와 무관하게
/// 그대로다 — 칸이 왼쪽 문자열 밖에 있다(BS design 결정 6). 메모가 칸의 글자와 갈래도
/// 기억하는 이유는 `sameBatteryCell`에 있다.
///
/// `render` 뒤에 불러야 한다. 그 전에 부르면 이전 프레임의 픽셀을 읽는다.
fn dumpStatus(
```

### 편집 4b — 메모

`terminal/src/main.zig` — `old_string`:

```zig
    last_len: *?usize,
    last_caps: *bool,
) void {
    if (last_len.*) |n| {
        if (std.mem.eql(u8, last[0..n], st.text) and last_caps.* == st.caps) return;
    }
    @memcpy(last[0..st.text.len], st.text);
    last_len.* = st.text.len;
    last_caps.* = st.caps;
```

`new_string`:

```zig
    last_len: *?usize,
    last_caps: *bool,
    last_battery: *?BatteryCell,
) void {
    if (last_len.*) |n| {
        if (std.mem.eql(u8, last[0..n], st.text) and last_caps.* == st.caps and
            sameBatteryCell(last_battery.*, st.battery)) return;
    }
    @memcpy(last[0..st.text.len], st.text);
    last_len.* = st.text.len;
    last_caps.* = st.caps;
    last_battery.* = st.battery;
```

### 편집 4c — 여백이 없을 때

`terminal/src/main.zig` — `old_string`:

```zig
        logline.print("terminal: status> dict ink=0 (no room)\n", .{});
        return;
```

`new_string`:

```zig
        logline.print("terminal: status> dict ink=0 (no room)\n", .{});
        dumpBatteryInk(st.battery, 0, 0, 0, " (no room)");
        return;
```

### 편집 4d — 세 수

`terminal/src/main.zig` — `old_string`:

```zig
    var dict: usize = 0;
    var row: u32 = 0;
```

`new_string`:

```zig
    var dict: usize = 0;
    // 배터리 칸의 색 셋(BS-M1). 셋 다 여백 안에서 이 칸에만 쓰이므로 띠 전체를 세도 이
    // 칸의 수다 — x 범위를 안 재는 것은 위 `CAPS`의 이유 그대로다.
    var bat_norm: usize = 0;
    var bat_plug: usize = 0;
    var bat_low: usize = 0;
    var row: u32 = 0;
```

### 편집 4e — 세 색을 센다

`terminal/src/main.zig` — `old_string`:

```zig
            if (px == STATUS_DICT) dict += 1;
```

`new_string`:

```zig
            if (px == STATUS_DICT) dict += 1;
            if (px == STATUS_BAT) bat_norm += 1;
            if (px == STATUS_BAT_PLUG) bat_plug += 1;
            if (px == STATUS_BAT_LOW) bat_low += 1;
```

### 편집 4f — `status> battery` 줄

`terminal/src/main.zig` — `old_string`:

```zig
    logline.print("terminal: status> dict ink={d}\n", .{dict});
}
```

`new_string`:

```zig
    logline.print("terminal: status> dict ink={d}\n", .{dict});
    // 배터리 칸(BS-M1, design 결정 10). 배터리가 없어도 찍는다 — `cell=none`과 세 수 0이
    // "칸이 없다"의 판정이다(battery 체인 검사 A1 · A5).
    dumpBatteryInk(st.battery, bat_norm, bat_plug, bat_low, "");
}
```

### 편집 4g — `main`의 메모 변수

`terminal/src/main.zig` — `old_string`:

```zig
    var last_status_caps = false;
```

`new_string`:

```zig
    var last_status_caps = false;
    // 배터리 칸도 따로 기억한다(BS-M1). `CAPS`와 같은 이유다 — 잔량이 그대로인 채 어댑터를
    // 꽂으면 글자는 그대로이고 갈래만 바뀐다. 초기값은 `last_status_caps`와 같은 이유로
    // 무엇이든 된다.
    var last_status_battery: ?BatteryCell = null;
```

### 편집 4h — 부르는 자리

`terminal/src/main.zig` — `old_string`:

```zig
        dumpStatus(fb, status_line, &last_status, &last_status_len, &last_status_caps);
```

`new_string`:

```zig
        dumpStatus(fb, status_line, &last_status, &last_status_len, &last_status_caps, &last_status_battery);
```

### 4-9. 확인과 첫 빌드

먼저 diff를 본다.

```bash
cd /Users/dp/Repository/tars-linux && git diff --stat terminal/src/main.zig && git diff terminal/src/main.zig | rg '^-'
```

기대: `1 file changed, 392 insertions(+), 10 deletions(-)`. `rg '^-'`는 머리 한 줄과 아래 열 줄이다(diff가 정렬을 다르게 잡아 순서가
다를 수는 있다. 줄의 집합이 같으면 된다).

```
-    _ = try drawRun(fb, cache, st.text[dict_at..], y, STATUS_DICT, col, fb.width);
-        if (std.mem.eql(u8, last[0..n], st.text) and last_caps.* == st.caps) return;
-fn drainUevents(fd: c_int, io: std.Io, devs: *[pointer.MAX_DEVICES]?PointerDev) void {
-            if (std.c.errno(n) != .NOBUFS) return; // EAGAIN — 다 읽었다
-        if (n == 0) return;
-        const name = pointer.ueventAddedNode(buf[0..@intCast(n)]) orelse continue;
-        // -1 = 무한 대기. 이벤트가 없으면 CPU를 전혀 쓰지 않는다.
-        const ready = c.poll(&fds, @intCast(nfds), -1);
-        if (fds[1].revents & c.POLLIN != 0) drainUevents(uevent_fd, init.io, &pointer_devs);
-        dumpStatus(fb, status_line, &last_status, &last_status_len, &last_status_caps);
```

그다음 사본과 같은지 본다. 사본은 이 plan의 편집을 HEAD의 `main.zig`에 기계로 넣은 것이다(확정 15).

```bash
cd /Users/dp/Repository/tars-linux && cmp terminal/src/main.zig /tmp/run/bs1-plan/src/main.zig && echo SAME-AS-PLAN-COPY
```

기대: `SAME-AS-PLAN-COPY`. 다르면 `diff terminal/src/main.zig /tmp/run/bs1-plan/src/main.zig`를 보고 plan의 글자에 맞춰 고친다(편집이
빗나갔거나 들여쓰기가 다르다). BS-M0의 commit 뒤에 `main.zig`가 바뀌었다면 사본이 낡은 것이니 그 diff를 보고에 적고 진행한다.

그리고 컨테이너에서 빌드하고 호스트 검사를 돌린다. 처음 빌드는 vendor가 있으면 2~4분이다.

```bash
cd /Users/dp/Repository/tars-linux
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer bash -c \
  './prepare.sh > /tmp/b.log 2>&1; echo "build exit=$?"; grep -aE "error:" /tmp/b.log | head -n 30;
   zig build test > /tmp/t.log 2>&1; echo "test exit=$?"; grep -aE "_test: all checks passed|FAIL" /tmp/t.log' \
  > /tmp/run/bs1/task4.out 2>&1
rmdir /tmp/run/docker.lock
cat /tmp/run/bs1/task4.out
```

기대: `build exit=0`, `error:` 줄 없음, `test exit=0`, `FAIL` 없음, `battery_test: all checks passed`가 있다.

`src/main.zig:…: error:`가 나오면 컴파일 에러다. "누가 무엇을 하나"의 규칙대로 그 자리만 고치고 다시 돌린다. 고친 줄의 전과 후를 보고에
적는다. 고친 뒤에는 `/tmp/run/bs1-plan/src/main.zig`와 다르게 되므로 `cmp`는 다시 안 본다.

## Task 5: `battery/check.sh` — 새 체인

design 결정 11. 템플릿은 `pointer/check.sh`다(빌드 단계 · `report_failure` · `wait_for_screen` · monitor 연결 · NUL 셈 · 부팅 사이의 끄기).

### 5-1. 새 파일

아래 블록을 글자 그대로 Write로 `battery/check.sh`에 넣고 실행 권한을 준다.

```bash
cd /Users/dp/Repository/tars-linux && chmod 0755 battery/check.sh && bash -n battery/check.sh && echo SYNTAX-OK
cmp battery/check.sh /tmp/run/bs1-plan/battery_check.sh && echo SAME-AS-PLAN-COPY
```

`battery/check.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# BS 체인 — 상태 줄의 배터리 칸(BS-M1). 스물두번째 체인.
#
# 이 게이트가 증명하는 사슬 전체:
#   커널에 test_power가 내장되고, 내장 cmdline의 test_power.battery_present=false가 그
#   배터리를 끈다(BS design 결정 9의 겹 1)
#   → terminal이 첫 프레임 전에 /sys/class/power_supply를 훑는다. test_battery가 있지만
#     present가 0이라 안 센다. 상태 줄은 BS 전과 같다(검사 A1)
#   → 셸에서 battery_present에 true를 쓰면 test_power가 test_ac에 uevent를 보낸다
#   → terminal의 uevent 소켓(PD-M0이 연 것)이 SUBSYSTEM=power_supply를 보고 다시 훑는다.
#     상태 줄의 오른쪽 끝에 넉 자 ` 50%`가 회색으로 뜬다(검사 A2)
#   → 키도 PTY 출력도 없이 잔량이 10이 되면 그 칸만 빨강 ` 10%`로 다시 그린다(검사 A3)
#   → 글자가 그대로인 채 충전이 시작되면 초록이 되고 새 줄이 찍힌다(검사 A4)
#   → 배터리를 끄면 칸이 사라진다(검사 A5)
#   → 부팅 cmdline으로 켠 배터리는 첫 프레임에 이미 칸이 있다(검사 B1)
#
# 판정은 전부 terminal의 줄이다 — battery> scan · battery> read(main.zig의 배터리 절)와
# status> battery(dumpStatus가 띠의 픽셀을 색마다 센 것). 화면 글자로는 판정하지 않는다.
# 상태 줄은 격자 밖이라 screen>에 안 나오고, 그래서 친 명령의 에코가 판정을 속일 자리도
# 없다(docs/decisions/project_gate_screen_echo.md). screen>은 검사 A3에서 "그 프레임에 칸
# 말고 바뀐 것이 없다"를 보는 데만 쓴다.
#
# 부팅이 둘이다. A는 내장 cmdline 그대로(배터리 꺼짐)이고 monitor로 친다. B는 -append로
# 배터리를 켜고 아무것도 안 친다. 둘 다 디스크를 물지 않는다 — 배터리는 설정과 무관하다.
#
# 주기 경로(60초)는 안 본다(BS design 결정 11). test_power의 setter가 전부 uevent를
# 부르므로 "uevent 없이 바뀐 값"을 게스트에서 만들 길이 없다. 그 길은 battery_test의
# pollTimeout 검사가 호스트에서 본다.

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

# sysfs 글자 · 고르기 · 갈래 · 칸 글자 · uevent · poll timeout은 여기서 먼저 걸러진다
# (battery_test, BS-M0) — 부팅 전에 잡을 수 있는 실패다.
if ! (cd ../terminal && zig build test); then
  echo "FAIL: terminal host tests failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# ── 검사 0: 커널과 부트로더가 가짜 배터리를 안다 (부팅 없음) ──────────────
#
# 기호 셋 중 하나만 빠져도 아래 부팅이 전부 빨갛지만, 그 빨강은 "terminal이 배터리를 못
# 읽는다"처럼 보인다. 여기서 먼저 갈라 둔다.
#
# 내장 cmdline은 낱말 하나만 본다(BS design 결정 9). 같은 줄에 wifi 체인의 낱말도 있다.
# 값이 0이 아니라 false인 것이 중요하다 — test_power는 0을 조용히 무시하고 배터리가 켜진
# 채 남는다(design 확인 2). 그 사고는 검사 A1이 다시 본다.
#
# limine의 블랙리스트는 실기에서 test_power를 아예 등록하지 않게 하는 겹 2다. 이 체인은
# -kernel로 떠서 limine을 안 지나므로 그 효과는 machine 체인이 본다(판정 14).
CONFIG=../kernel/.config
for sym in TEST_POWER ACPI_BATTERY POWER_SUPPLY; do
  if ! grep -x "CONFIG_${sym}=y" "$CONFIG" >/dev/null; then
    echo "FAIL: CONFIG_${sym}=y is missing from kernel/.config"
    exit 1
  fi
done
if ! grep -E '^CONFIG_CMDLINE="([^"]* )?test_power\.battery_present=false( [^"]*)?"$' "$CONFIG" >/dev/null; then
  echo "FAIL: the built-in cmdline no longer turns test_power's battery off (test_power.battery_present=false)"
  exit 1
fi
if ! grep -E '^[[:space:]]*cmdline:(.* )?initcall_blacklist=test_power_init( .*)?$' ../boot/limine.conf >/dev/null; then
  echo "FAIL: boot/limine.conf no longer keeps test_power from registering (initcall_blacklist=test_power_init)"
  exit 1
fi
echo "the kernel has test_power, ACPI_BATTERY and POWER_SUPPLY; the built-in cmdline turns the battery off; limine blacklists test_power"

# 스물한 체인이 45455~45493을 쓴다(docs/guides/lessons.md의 포트 목록). 부팅 B는 monitor가 없다.
MONITOR_PORT=45494

LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  exec 3<&- 2>/dev/null
  exec 3>&- 2>/dev/null
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

report_failure() {
  echo "FAIL: $1"
  echo "--- markers ---"
  local marker
  for marker in \
    "terminal: screen>" \
    "terminal: battery> scan " \
    "terminal: battery> scan failed" \
    "terminal: battery> read " \
    "terminal: status> battery " \
    "terminal: pointer> uevent failed" \
    "terminal: key>"; do
    if grep -aq "$marker" "$LOG"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- battery and status lines ---"
  grep -aE 'terminal: (battery> |status> (text=|battery ))' "$LOG" | tr -d '\r' | tail -n 30
  echo "--- last 40 lines ---"
  tail -n 40 "$LOG"
  exit 1
}

source ../gate_lib.sh

# 접두가 $1인 마지막 줄. 값이 줄 끝까지 가므로 \r를 지운다(HI-M1 실측 4).
last_line() {
  grep -a "$1" "$LOG" | tail -n 1 | tr -d '\r'
}

# 접두가 $1인 줄의 수.
count_lines() {
  grep -ac "$1" "$LOG" || true
}

# 마지막 status> text= 줄의 값(hangul/check.sh의 status_text와 같다).
status_text() {
  grep -a 'terminal: status> text=' "$LOG" | tail -n 1 | tr -d '\r' | sed -E 's/.*text=//'
}

# 접두가 $1인 마지막 줄이 패턴(ERE) $2에 맞을 때까지 기다린다. 있으면 0, 30초가 지나면 1.
# 15초가 아니라 30초인 것은 검사 A3이 셸의 sleep 5를 기다리기 때문이다.
wait_for_last() {
  local prefix="$1" pattern="$2" i
  for i in $(seq 1 300); do
    if grep -aqE -- "$pattern" <<<"$(last_line "$prefix")"; then return 0; fi
    sleep 0.1
  done
  return 1
}

# 검사 A3의 판정 재료. 접두가 $1인 첫 줄을 찾아, 그 앞의 screen> 두 줄(그 칸을 그린
# 프레임과 바로 앞 프레임)이 글자까지 같은지와, 앞 프레임부터 그 줄까지 사이의 key> 줄
# 수를 낸다. `same=1 keys=0`이면 그 프레임은 칸 말고 바뀐 것이 없고 키도 없었다.
# 그 줄이 없으면 `missing`이다.
redraw_alone() {
  tr -d '\r' < "$LOG" | awk -v want="$1" '
    found { next }
    index($0, want) == 1 { found = 1; next }
    /^terminal: screen>/ { prev = cur; cur = $0; gap = since; since = 0; next }
    /^terminal: key>/ { since++ }
    END {
      if (!found) { print "missing"; exit }
      printf "same=%d keys=%d\n", (prev != "" && prev == cur), gap + since
    }'
}

STATUS_A="EN  신세벌 PCS  쿼티  CAPS"
SCAN_OFF="terminal: battery> scan seen=1 present=0 pick=none"
SCAN_ON="terminal: battery> scan seen=1 present=1 pick=test_battery"
CELL_NONE="terminal: status> battery cell=none ink norm=0 plug=0 low=0"

# ── 부팅 A: test_power가 있고 배터리가 꺼져 있다 ────────────────────────
echo "=== boot A: test_power is built in and its battery is off ==="
qemu-system-x86_64 \
  -nic none \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

READY=0
for _ in $(seq 1 120); do
  if grep -aq "terminal: screen>" "$LOG"; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || report_failure "boot A: terminal never rendered a prompt"
wait_for_screen 'root@\(none\) ~#' ||
  report_failure "boot A: the shell prompt never showed up"
sleep 1

# ── 검사 A1: 꺼진 배터리는 칸이 아니다 ────────────────────────────────
#
# 키를 하나도 안 친다. 처음 훑기는 test_battery를 보지만(seen=1) present가 0이라 안
# 센다(present=0). 그래서 읽은 배터리가 없고(read 줄 0), 상태 줄 글자는 BS 전과 같고, 띠에
# 배터리 색이 한 픽셀도 없다. 이 셋이 스물한 체인이 BS-M1 뒤에도 그대로인 이유다.
#
# 내장 cmdline의 값이 false가 아니라 0이었다면(design 결정 9) 여기가 seen=1 present=1로
# 빨개진다. BS-M1 plan Task 7의 mutation m1이 그 자리를 본다.
echo "=== A1: the boot scan sees test_battery and does not count it ==="
SCAN="$(last_line 'terminal: battery> scan ')"
[ "$SCAN" = "$SCAN_OFF" ] ||
  report_failure "A1: the boot scan reads \"${SCAN}\", expected \"${SCAN_OFF}\""
[ "$(count_lines 'terminal: battery> read ')" -eq 0 ] ||
  report_failure "A1: terminal read a battery although none counts ($(last_line 'terminal: battery> read '))"
TEXT="$(status_text)"
[ "$TEXT" = "$STATUS_A" ] ||
  report_failure "A1: the status line reads \"${TEXT}\", expected \"${STATUS_A}\""
CELL="$(last_line 'terminal: status> battery ')"
[ "$CELL" = "$CELL_NONE" ] ||
  report_failure "A1: the battery cell reads \"${CELL}\", expected \"${CELL_NONE}\""
echo "${SCAN}; no battery was read; the status line is \"${TEXT}\" with no battery pixels"

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure "could not connect to the QEMU monitor on port ${MONITOR_PORT}"

# ── 검사 A2: 배터리를 켜면 uevent가 다시 훑게 하고 칸이 뜬다 ──────────────
#
# test_power는 배터리를 켜는 uevent를 test_battery가 아니라 test_ac에 보낸다(design 확인
# 4). 이름을 보고 다시 훑는 코드는 여기서 빨개진다. drainUevents가 power_supply를 안 알리는
# 코드도 여기서 빨개진다 — 고른 배터리가 없으면 주기 읽기도 없어서 남는 길이 없다(plan
# Task 7의 mutation m2).
#
# 잔량 50 · Discharging은 test_power의 기본값이다(BS-M0 Task 6이 sysfs에서 읽었다).
echo "=== A2: battery_present=true from the shell ==="
# cd /sys/module/test_power/parameters
type_keys c d spc slash s y s slash m o d u l e slash t e s t shift-minus p o w e r slash \
  p a r a m e t e r s ret
# echo true > battery_present
type_keys e c h o spc t r u e spc shift-dot spc b a t t e r y shift-minus p r e s e n t ret
wait_for_last 'terminal: battery> scan ' "^${SCAN_ON}\$" ||
  report_failure "A2: no rescan picked test_battery after battery_present=true (last scan: $(last_line 'terminal: battery> scan '))"
wait_for_last 'terminal: status> battery ' '^terminal: status> battery cell=" 50%" ink norm=[1-9][0-9]* plug=0 low=0$' ||
  report_failure "A2: the cell never showed \" 50%\" in the normal colour (last: $(last_line 'terminal: status> battery '))"
READ="$(last_line 'terminal: battery> read ')"
[ "$READ" = "terminal: battery> read test_battery capacity=50 status=Discharging class=normal" ] ||
  report_failure "A2: the read line is \"${READ}\", expected capacity=50 status=Discharging class=normal"
TEXT="$(status_text)"
[ "$TEXT" = "$STATUS_A" ] ||
  report_failure "A2: the status text changed to \"${TEXT}\"; the battery cell must stay out of it"
echo "$(last_line 'terminal: status> battery '); the status text is unchanged"

# ── 검사 A3: 키도 PTY 출력도 없이 칸이 바뀐다 ───────────────────────────
#
# bash의 배경 작업이 5초 뒤에 잔량을 쓴다. bash는 배경 작업이 끝난 것을 다음 프롬프트에서야
# 알린다(set -b가 꺼져 있다). 그래서 그 순간 PTY에 아무 글자도 안 나오고, 다시 그리기를 부를
# 수 있는 것은 uevent뿐이다(design 결정 11). 끝나는 순간 글자를 쓰는 셸(fish의 "has ended")이면
# 그 출력도 다시 그리기를 불러서 성공 경로가 둘이 된다
# (docs/decisions/project_gate_chain_composition.md).
#
# 판정은 셋이다. 칸이 빨강 ` 10%`가 됐다. 그 칸을 그린 프레임의 screen>이 바로 앞
# 프레임과 글자까지 같다 — PTY 출력이 끼었다면 다르다. 앞 프레임부터 그 줄까지 key> 줄이
# 없다. 5초는 bash가 `[1] <pid>`와 프롬프트를 다 그릴 여유다 — 그 프레임이 늦어 칸의
# 프레임과 겹치면 둘째 판정이 거짓으로 빨갛다.
echo "=== A3: the capacity drops to 10 while nothing is typed ==="
# /usr/bin/bash --norc
type_keys slash u s r slash b i n slash b a s h spc minus minus n o r c ret
wait_for_screen 'bash-[0-9]' ||
  report_failure "A3: bash never drew a prompt inside the pty"
# ( sleep 5; echo 10 > battery_capacity ) &
type_keys shift-9 spc s l e e p spc 5 semicolon spc e c h o spc 1 0 spc shift-dot spc \
  b a t t e r y shift-minus c a p a c i t y spc shift-0 spc shift-7 ret
wait_for_screen '\[1\] [0-9]+' ||
  report_failure "A3: bash never reported the background job"
wait_for_last 'terminal: status> battery ' '^terminal: status> battery cell=" 10%" ink norm=0 plug=0 low=[1-9][0-9]*$' ||
  report_failure "A3: the cell never turned into a low \" 10%\" (last: $(last_line 'terminal: status> battery '))"
ALONE="$(redraw_alone 'terminal: status> battery cell=" 10%"')"
[ "$ALONE" = "same=1 keys=0" ] ||
  report_failure "A3: the frame that drew \" 10%\" was not a battery-only redraw (${ALONE}, want same=1 keys=0)"
LOW_A3="$(last_line 'terminal: status> battery ' | sed -E 's/.* low=([0-9]+)$/\1/')"
READ="$(last_line 'terminal: battery> read ')"
[ "$READ" = "terminal: battery> read test_battery capacity=10 status=Discharging class=low" ] ||
  report_failure "A3: the read line is \"${READ}\", expected capacity=10 status=Discharging class=low"
echo "$(last_line 'terminal: status> battery '); ${ALONE}"

# ── 검사 A4: 글자가 그대로인 채 갈래만 바뀐다 ───────────────────────────
#
# 잔량이 10 그대로이고 상태만 Charging이 된다. 칸의 글자 ` 10%`는 그대로이고 색이
# 빨강에서 초록으로 바뀐다. dumpStatus의 메모가 글자만 기억하면 화면은 초록인데 새 줄이
# 안 찍힌다 — IS-M1이 CAPS에서 겪은 구멍이다(design 결정 10, plan Task 7의 mutation m3).
# 그리고 픽셀 수가 A3의 빨강과 같아야 한다. 같은 넉 자를 색만 바꿔 칠했다는 증거다.
echo "=== A4: the adapter goes in at the same capacity ==="
# echo charging > battery_status
type_keys e c h o spc c h a r g i n g spc shift-dot spc b a t t e r y shift-minus s t a t u s ret
wait_for_last 'terminal: status> battery ' '^terminal: status> battery cell=" 10%" ink norm=0 plug=[1-9][0-9]* low=0$' ||
  report_failure "A4: no new status> battery line with plug>0 after battery_status=charging (last: $(last_line 'terminal: status> battery '))"
READ="$(last_line 'terminal: battery> read ')"
[ "$READ" = "terminal: battery> read test_battery capacity=10 status=Charging class=plugged" ] ||
  report_failure "A4: the read line is \"${READ}\", expected capacity=10 status=Charging class=plugged"
# 같은 넉 자를 색만 바꿔 칠했으면 픽셀 수가 같다(IS-M1의 on=87 · off=87과 같은 증거).
PLUG_A4="$(last_line 'terminal: status> battery ' | sed -E 's/.* plug=([0-9]+) .*/\1/')"
[ "$PLUG_A4" = "$LOW_A3" ] ||
  report_failure "A4: the plugged cell has ${PLUG_A4} pixel(s) and the low one had ${LOW_A3}; the same four glyphs must only change colour"
echo "$(last_line 'terminal: status> battery '); the same ${PLUG_A4} pixel(s) as the low cell"

# ── 검사 A5: 배터리를 끄면 칸이 사라진다 ────────────────────────────────
#
# A2와 짝이다. 한 번 고른 배터리를 영영 붙들고 있는 코드는 A2를 통과하고 여기서 빨개진다
# (IS-M1 plan 확정 7과 같은 짝).
#
# 마지막에 줄 수를 센다. 훑기 줄은 결과가 바뀔 때만 찍히므로 셋이다(A1 · A2 · A5) — A3 · A4의
# uevent도 다시 훑지만 결과가 그대로다. 읽기 줄도 셋이다(A2 · A3 · A4).
echo "=== A5: battery_present=false takes the cell away ==="
# echo false > battery_present
type_keys e c h o spc f a l s e spc shift-dot spc b a t t e r y shift-minus p r e s e n t ret
wait_for_last 'terminal: battery> scan ' "^${SCAN_OFF}\$" ||
  report_failure "A5: no rescan dropped test_battery after battery_present=false (last scan: $(last_line 'terminal: battery> scan '))"
wait_for_last 'terminal: status> battery ' "^${CELL_NONE}\$" ||
  report_failure "A5: the cell did not go away (last: $(last_line 'terminal: status> battery '))"
TEXT="$(status_text)"
[ "$TEXT" = "$STATUS_A" ] ||
  report_failure "A5: the status text is \"${TEXT}\", expected \"${STATUS_A}\""
SCANS="$(count_lines 'terminal: battery> scan ')"
READS="$(count_lines 'terminal: battery> read ')"
[ "$SCANS" -eq 3 ] && [ "$READS" -eq 3 ] ||
  report_failure "A5: boot A printed ${SCANS} scan line(s) and ${READS} read line(s), expected 3 and 3"
echo "the cell is gone; boot A printed ${SCANS} scan and ${READS} read lines"

# NUL만 세어 한 번에 읽는다(pointer/check.sh와 같은 이유, AL-M1).
if [ "$(tr -cd '\0' < "$LOG" | wc -c)" -ne 0 ]; then
  report_failure "the boot A serial log contains NUL bytes"
fi

exec 3>&- 2>/dev/null
kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""

# ── 부팅 B: 부팅 cmdline이 배터리를 켜 둔다 ─────────────────────────────
#
# -append의 파라미터가 내장 cmdline의 false를 덮는다 — 커널이 내장 문자열 뒤에 부트로더의
# 것을 붙이고 같은 파라미터는 뒤의 것이 이긴다(design 확인 9). 키를 안 친다.
LOG_A="$LOG"
LOG="$(mktemp)"
echo "=== boot B: the battery is on, full and plugged from the kernel command line ==="
qemu-system-x86_64 \
  -nic none \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0 test_power.battery_present=true test_power.battery_status=full test_power.battery_capacity=100" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -serial file:"$LOG" \
  -no-reboot &
QEMU_PID=$!

READY=0
for _ in $(seq 1 120); do
  if grep -aq "terminal: status> battery " "$LOG"; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || report_failure "boot B: terminal never printed a status> battery line"

# ── 검사 B1: 첫 프레임에 이미 칸이 있다 ────────────────────────────────
#
# 첫 status> battery 줄은 첫 프레임의 것이다. 그 줄이 이미 초록 `100%`이면 처음 훑기가
# 첫 프레임 전에 돌았다. 처음 훑기를 첫 프레임 뒤로 미룬 코드는 첫 줄이 cell=none이다.
echo "=== B1: the first frame already has the cell ==="
FIRST="$(grep -a -m 1 'terminal: status> battery ' "$LOG" | tr -d '\r')"
grep -aqE '^terminal: status> battery cell="100%" ink norm=0 plug=[1-9][0-9]* low=0$' <<<"$FIRST" ||
  report_failure "B1: the first battery line is \"${FIRST}\", expected a plugged \"100%\""
FIRST_SCAN="$(grep -a -m 1 'terminal: battery> scan ' "$LOG" | tr -d '\r')"
[ "$FIRST_SCAN" = "$SCAN_ON" ] ||
  report_failure "B1: the first scan line is \"${FIRST_SCAN}\", expected \"${SCAN_ON}\""
FIRST_READ="$(grep -a -m 1 'terminal: battery> read ' "$LOG" | tr -d '\r')"
[ "$FIRST_READ" = "terminal: battery> read test_battery capacity=100 status=Full class=plugged" ] ||
  report_failure "B1: the first read line is \"${FIRST_READ}\", expected capacity=100 status=Full class=plugged"
echo "${FIRST}"

if [ "$(tr -cd '\0' < "$LOG" | wc -c)" -ne 0 ]; then
  report_failure "the boot B serial log contains NUL bytes"
fi

echo "boot A battery lines:"
grep -aE 'terminal: (battery> |status> battery )' "$LOG_A" | tr -d '\r'
echo "BS-M1 check PASS"
```

검사마다 무엇을 치고 무엇을 기다리나.

| 검사 | 치는 것 | 기다리는 줄 · 판정 |
|---|---|---|
| 0 | 없음(부팅 전) | `kernel/.config`의 `CONFIG_TEST_POWER=y` · `CONFIG_ACPI_BATTERY=y` · `CONFIG_POWER_SUPPLY=y`, 내장 cmdline의 낱말 `test_power.battery_present=false`, limine `cmdline:`의 낱말 `initcall_blacklist=test_power_init` |
| A1 | 없음 | 마지막 `scan` 줄이 `seen=1 present=0 pick=none`, `read` 줄 0, `text=`가 `EN  신세벌 PCS  쿼티  CAPS`, 마지막 칸 줄이 `cell=none ink norm=0 plug=0 low=0` |
| A2 | fish에서 `cd /sys/module/test_power/parameters` · `echo true > battery_present` | `scan … present=1 pick=test_battery`, 칸 줄 `cell=" 50%" … norm>0 plug=0 low=0`, `read … capacity=50 status=Discharging class=normal`, `text=` 그대로 |
| A3 | `/usr/bin/bash --norc`, 프롬프트 `bash-` 뒤 `( sleep 5; echo 10 > battery_capacity ) &`, `[1] <pid>` 뒤 아무것도 안 친다 | 칸 줄 `cell=" 10%" … norm=0 plug=0 low>0`(30초까지), `redraw_alone`이 `same=1 keys=0`, `read … capacity=10 status=Discharging class=low` |
| A4 | bash에서 `echo charging > battery_status` | 칸 줄 `cell=" 10%" … norm=0 plug>0 low=0`, `read … capacity=10 status=Charging class=plugged`, `plug=`이 A3의 `low=`와 같다 |
| A5 | bash에서 `echo false > battery_present` | `scan … present=0 pick=none`, 칸 줄 `cell=none … 0 0 0`, `text=` 그대로, 부팅 A 전체의 `scan` 줄 3 · `read` 줄 3 |
| B1 | 없음(`-append`로 켰다) | 첫 칸 줄이 `cell="100%" … norm=0 plug>0 low=0`, 첫 `scan` 줄이 `present=1 pick=test_battery`, 첫 `read` 줄이 `capacity=100 status=Full class=plugged` |

### 5-2. 체인 한 판

컨테이너 `/tmp`를 호스트에 묶어 시리얼 로그를 남긴다(lessons AL-M0 절). 체인의 시리얼 로그는 부팅마다 `mktemp` 파일이라 그 `/tmp`에
남고, `report_failure`는 끝에 그 로그의 마지막 40줄을 찍는다. 빌드가 데워져 있으면 3분 안팎이다.

```bash
cd /Users/dp/Repository/tars-linux && ch=battery && mkdir -p /tmp/run/bs1/logs-$ch && rm -rf /tmp/run/bs1/logs-$ch/*
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/bs1/logs-$ch:/tmp -w /workspace tars-devcontainer ./$ch/check.sh \
    > /tmp/run/bs1/chain-$ch.log 2>&1 ; } 2> /tmp/run/bs1/chain-$ch.time; echo "$ch exit=$?"
rmdir /tmp/run/docker.lock
rg -a '^(===|FAIL|terminal: |the |boot A|BS-M1)' /tmp/run/bs1/chain-$ch.log | tr -d '\r'; cat /tmp/run/bs1/chain-$ch.time
```

기대: `battery exit=0`, 그리고 순서대로 아래 줄들(`N`은 값을 안 정한 픽셀 수다. 보고에 실제 값을 적는다).

```
the kernel has test_power, ACPI_BATTERY and POWER_SUPPLY; the built-in cmdline turns the battery off; limine blacklists test_power
=== boot A: test_power is built in and its battery is off ===
=== A1: the boot scan sees test_battery and does not count it ===
terminal: battery> scan seen=1 present=0 pick=none; no battery was read; the status line is "EN  신세벌 PCS  쿼티  CAPS" with no battery pixels
=== A2: battery_present=true from the shell ===
terminal: status> battery cell=" 50%" ink norm=N plug=0 low=0; the status text is unchanged
=== A3: the capacity drops to 10 while nothing is typed ===
terminal: status> battery cell=" 10%" ink norm=0 plug=0 low=N; same=1 keys=0
=== A4: the adapter goes in at the same capacity ===
terminal: status> battery cell=" 10%" ink norm=0 plug=N low=0; the same N pixel(s) as the low cell
=== A5: battery_present=false takes the cell away ===
the cell is gone; boot A printed 3 scan and 3 read lines
=== boot B: the battery is on, full and plugged from the kernel command line ===
=== B1: the first frame already has the cell ===
terminal: status> battery cell="100%" ink norm=0 plug=N low=0
boot A battery lines:
…
BS-M1 check PASS
```

빨개지면 `FAIL:` 줄과 그 아래 `--- markers ---` · `--- battery and status lines ---`를 그대로 보고하고 멈춘다. 고치지 않는다. 특히 둘.

- A3이 `same=0`으로 빨개지면 bash의 `[1] <pid>` · 프롬프트 프레임이 5초 안에 다 안 그려진 것일 수 있다(확정 14). 그 회차의 시리얼 로그
  (`/tmp/run/bs1/logs-battery/tmp.*` 중 `terminal: battery>`가 든 파일)에서 `rg -a -n 'terminal: (screen>|status> battery|key>)'`의 마지막
  열 줄을 보고에 붙인다.
- A1이 `seen=1 present=1`로 빨개지면 내장 cmdline이 배터리를 못 끈 것이다 — `terminal/`이 아니라 `kernel/.config`를 의심한다.

## Task 6: 루트 `check.sh`의 `CHAINS`와 machine 체인의 판정 14

### 편집 6a — 체인 설명 한 문단

`check.sh` — `old_string`:

```bash
# 컨테이너의 openssl s_server(45492)로 본다. 게스트에 한 글자도 안 친다. 회차당 부팅 1회.
#
# 이름과 경로를 한 곳에 모은다. 진입 검사와 실행이 같은 목록을 쓰므로,
```

`new_string`:

```bash
# 컨테이너의 openssl s_server(45492)로 본다. 게스트에 한 글자도 안 친다. 회차당 부팅 1회.
#
# BS 체인은 상태 줄의 배터리 칸을 본다. 커널에 내장된 test_power가 가짜 배터리를 만들고 내장
# cmdline이 그것을 꺼 둔다. 부팅 A(monitor 45494)에서 셸로 test_power의 파라미터를 쓰면
# terminal이 uevent를 보고 다시 훑고, 오른쪽 끝의 칸이 뜨고 · 바뀌고 · 사라진다. 판정은
# terminal의 battery> 줄과 status> battery 줄(띠에서 색 셋의 픽셀을 센 것)이다. 부팅 B는
# -append로 켠 배터리가 첫 프레임에 이미 칸으로 있는 것을 본다. 회차당 부팅 2회.
#
# 이름과 경로를 한 곳에 모은다. 진입 검사와 실행이 같은 목록을 쓰므로,
```

### 편집 6b — `CHAINS`

`check.sh` — `old_string`:

```bash
  "VD-M0:./dictation/check.sh"
)
```

`new_string`:

```bash
  "VD-M0:./dictation/check.sh"
  "BS-M1:./battery/check.sh"
)
```

### 편집 6c — `machine/check.sh`의 판정 14

판정 13(`cpuidle`) 뒤 · "그리고 실제로 친다" 앞이다. 이 파일은 `set -euo pipefail`이라 판정이 `fail` 함수를 쓴다.

`machine/check.sh` — `old_string`:

```bash
echo "the thermal core and cpuidle both came up"
```

`new_string`:

```bash
echo "the thermal core and cpuidle both came up"

# ── BS-M1: limine으로 뜬 기계에는 가짜 배터리가 없다 ───────────────────
#
# 판정 14. 커널에는 게이트용 가짜 배터리(test_power)가 내장돼 있고, boot/limine.conf의
# initcall_blacklist=test_power_init가 limine으로 뜨는 부팅에서 그 등록을 막는다(BS design
# 결정 9의 겹 2). 이 체인이 limine을 지나는 UEFI 부팅이라 그 겹이 실제로 먹었는지를 여기서
# 본다 — battery 체인은 -kernel로 떠서 limine을 안 지난다.
#
# 블랙리스트는 이름이 틀려도 아무 말을 안 한다(pr_debug뿐이다, BS design 위험 3). 그래서
# 결과를 본다. 막혔으면 /sys/class/power_supply가 비어 seen=0이고, 이름이 안 맞았으면
# test_battery가 등록돼 seen=1이다. 막히지 않아도 칸은 안 뜬다(내장 cmdline이 끈다) —
# 화면으로는 안 갈리는 차이라 이 줄로 본다.
#
# 이 줄은 terminal의 처음 훑기가 첫 프레임 전에 찍는다. 위의 기다림이 `terminal: grid`까지만
# 보므로 여기서 30초까지 기다린다.
SCAN_SEEN=0
for _ in $(seq 1 30); do
  if grep -aq "terminal: battery> scan " "$LOG"; then SCAN_SEEN=1; break; fi
  sleep 1
done
if [ "$SCAN_SEEN" != "1" ]; then
  fail "terminal never printed a battery> scan line" "terminal: battery>" "terminal: grid"
fi
if ! grep -aqF "terminal: battery> scan seen=0 present=0 pick=none" "$LOG"; then
  fail "test_power registered on a limine boot; initcall_blacklist=test_power_init did not take" \
    "terminal: battery> scan" "Kernel command line" "test_ac"
fi
echo "limine's initcall_blacklist kept test_power from registering (battery> scan seen=0)"
```

### 6-4. 확인

```bash
cd /Users/dp/Repository/tars-linux && bash -n check.sh && bash -n machine/check.sh && echo SYNTAX-OK
git diff --stat check.sh machine/check.sh && git diff check.sh machine/check.sh | rg '^-'
cmp check.sh /tmp/run/bs1-plan/gate/check.sh && cmp machine/check.sh /tmp/run/bs1-plan/gate/machine/check.sh && echo SAME-AS-PLAN-COPY
```

기대: `SYNTAX-OK`, `check.sh | 7 +++++++` · `machine/check.sh | 28 ++++…` · `2 files changed, 35 insertions(+)`, `rg '^-'`는 머리 두 줄
(`--- a/check.sh` · `--- a/machine/check.sh`)뿐, `SAME-AS-PLAN-COPY`.

진입 검사 셋은 루트 게이트를 시작하는 순간에 돈다. 그 전에 새 체인 하나로 본다(design 끝 조건 4).

```bash
cd /Users/dp/Repository/tars-linux && bash -c '
  eval "$(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic() {/,/^}/p" check.sh)"
  for f in ./battery/check.sh ./machine/check.sh; do
    require_build_steps "$f" && require_no_early_exit_pipe "$f" && require_explicit_nic "$f" && echo "entry ok $f"
  done'
```

기대: `entry ok ./battery/check.sh` · `entry ok ./machine/check.sh`.

machine 체인은 Task 8에서 돈다.

## Task 7: mutation 셋과 주기 경로 실측

design 끝 조건 3. 저장소 파일은 안 건드린다 — 고친 사본을 `-v`로 `main.zig` 위에 덮는다(lessons "범용 명령"의 mutation 절). `sd`는 파일
인자를 in-place로 고치므로 `cp`를 먼저 하고 사본에 친다. `main.zig`에는 호스트 검사가 없어서(`main_test`가 없다) mutation이 부팅 전에 죽지
않는다.

| 판 | 편집 | 겨냥한 검사 | 왜 그 검사인가 |
|---|---|---|---|
| m1 | `"present"` → `"present_mutated"` — `present` 파일을 못 읽어 null이 되고, `counts`가 "있다"로 본다. `present` 거르기를 지운 것과 같다 | A1 | 꺼진 배터리를 센다 — 첫 `scan` 줄이 `present=1 pick=test_battery` |
| m2 | `if (battery.ueventIsPowerSupply(msg)) supply = true;` 한 줄을 지운다 | A2 | 고른 배터리가 없어 기한도 없다 — 남는 길이 없다(확정 12) |
| m3 | `sameBatteryCell`의 ` and x.class == y.class`를 지운다 | A4 | 글자가 같은 전환에 메모가 새 줄을 안 찍는다. 다시 그리기는 일어난다(확정 8) |

m1을 "거르기 줄을 지운다"로 안 하는 이유. `battery.counts(kind, pres, scope)`에서 `pres`를 빼면 `pres`가 쓰이지 않는 상수가 되어 Zig가 컴파일
에러를 낸다 — mutation이 게이트가 아니라 빌드에서 죽는다. 파일 이름을 바꾸면 컴파일은 그대로이고 동작은 "present를 안 본다"와 같다.

### 7-1. 사본을 만든다

```bash
cd /Users/dp/Repository/tars-linux && mkdir -p /tmp/run/bs1/mut
cp terminal/src/main.zig /tmp/run/bs1/mut/m1.zig && sd -F '"present"' '"present_mutated"' /tmp/run/bs1/mut/m1.zig
cp terminal/src/main.zig /tmp/run/bs1/mut/m2.zig && sd -F 'if (battery.ueventIsPowerSupply(msg)) supply = true;' '' /tmp/run/bs1/mut/m2.zig
cp terminal/src/main.zig /tmp/run/bs1/mut/m3.zig && sd -F ' and x.class == y.class' '' /tmp/run/bs1/mut/m3.zig
for m in m1 m2 m3; do echo "== $m"; diff terminal/src/main.zig /tmp/run/bs1/mut/$m.zig; done
```

기대: 판마다 한 줄이 바뀐다(lessons 52 — `sd -F`가 빗나가도 에러가 없으므로 이 diff가 그것을 본다).

```
== m1
<         const pres = readSysfs(entry.name, "present", &present_buf).bytes;
>         const pres = readSysfs(entry.name, "present_mutated", &present_buf).bytes;
== m2
<         if (battery.ueventIsPowerSupply(msg)) supply = true;
>
== m3
<     return std.mem.eql(u8, &x.text, &y.text) and x.class == y.class;
>     return std.mem.eql(u8, &x.text, &y.text);
```

(`diff`가 앞에 `2015c2015` 같은 줄 번호를 붙인다. m2의 `>` 줄은 공백 여덟 칸이다.)

### 7-2. 체인 세 판

판마다 3분 안팎이다. 체인 하나를 Bash 호출 하나로 돈다.

```bash
cd /Users/dp/Repository/tars-linux && m=m1 && mkdir -p /tmp/run/bs1/mut/logs-$m && rm -rf /tmp/run/bs1/mut/logs-$m/*
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -v /tmp/run/bs1/mut/$m.zig:/workspace/terminal/src/main.zig:ro \
  -v /tmp/run/bs1/mut/logs-$m:/tmp -w /workspace tars-devcontainer ./battery/check.sh > /tmp/run/bs1/mut/$m.out 2>&1; echo "$m exit=$?"
rmdir /tmp/run/docker.lock
rg -a '^(FAIL|===)' /tmp/run/bs1/mut/$m.out | tr -d '\r'
```

`m=`만 `m2` · `m3`으로 바꿔 차례로 친다. 기대는 판마다 `exit=1`이고 마지막 `===` 줄과 `FAIL` 줄이 아래와 같다(`N`은 픽셀 수).

```
== m1
=== A1: the boot scan sees test_battery and does not count it ===
FAIL: A1: the boot scan reads "terminal: battery> scan seen=1 present=1 pick=test_battery", expected "terminal: battery> scan seen=1 present=0 pick=none"
== m2
=== A2: battery_present=true from the shell ===
FAIL: A2: no rescan picked test_battery after battery_present=true (last scan: terminal: battery> scan seen=1 present=0 pick=none)
== m3
=== A4: the adapter goes in at the same capacity ===
FAIL: A4: no new status> battery line with plug>0 after battery_status=charging (last: terminal: status> battery cell=" 10%" ink norm=0 plug=0 low=N)
```

판정 넷 중 하나라도 다르면(다른 검사에서 빨갛다, 초록이다, 빌드에서 죽는다) 그 판의 `.out` 전부를 보고하고 멈춘다. lessons의 "mutation이
겨냥한 검사에 걸릴 것이라고 믿기(SL-M2)"가 그 경우다 — 앞의 검사가 먼저 죽였다면 그것도 그대로 적는다.

m2는 A2가 30초를 기다린 뒤 빨개지므로 다른 판보다 30초 길다. m3은 A4의 화면이 실제로 초록이 됐는지까지는 안 본다 — 그 판의 시리얼
로그에서 A4 뒤에 `screen>` 줄이 하나 늘었는지를 보고에 적는다(다시 그리기는 일어났고 메모만 막혔다는 증거).

```bash
f="$(rg -l -a 'terminal: battery> read test_battery capacity=10 status=Charging' /tmp/run/bs1/mut/logs-m3/ | head -n 1)"
tr -d '\r' < "$f" | awk '/battery> read test_battery capacity=10 status=Charging/ { on = 1 } on && /terminal: (screen>|status> )/ { print substr($0, 1, 60) }'
```

기대: `read … Charging` 줄 뒤에 `terminal: screen>` 줄이 하나 이상 있고, 그 뒤에 `terminal: status>` 줄이 하나도 없다.

### 7-3. 주기 경로가 60초 안에 값을 가져온다(실측)

design 결정 11의 끝 문단. m2 판에서는 uevent가 안 닿는다. 배터리를 부팅 cmdline으로 켜 두면 처음 훑기가 배터리를 고르고 기한을 잡으므로,
그 뒤에 잔량이 바뀌면 남는 길은 60초 주기뿐이다. 게스트에 한 글자도 안 친다 — BS-M0 Task 6처럼 설정 디스크의 `services.d/probe`가
20초 뒤에 잔량을 쓴다. 게이트가 아니라 한 번 재는 것이다.

아래 두 파일을 Write로 만든다.

`/tmp/run/bs1/m2probe.sh`:

```bash
#!/usr/bin/bash
# BS-M1 Task 7-3의 게스트 쪽 — 설정 디스크의 services.d/probe로 들어간다(BS-M0 Task 6과 같은 자리).
# 20초 뒤에 잔량을 한 번 쓰고 잠든다. 감독자가 끝난 서비스를 다시 띄우므로 나가지 않는다.
exec > /dev/console 2>&1 < /dev/null
sleep 20
echo 10 > /sys/module/test_power/parameters/battery_capacity
echo "bs1-probe: wrote capacity=10"
exec sleep 100000
```

`/tmp/run/bs1/m2period.sh`:

```bash
#!/usr/bin/env bash
# BS-M1 Task 7-3 — uevent를 못 보는 terminal(mutation m2)에서 주기 읽기가 60초 안에 값을 가져오는지
# 한 번 잰다(BS design 결정 11의 끝 문단). 게이트가 아니라 실측이다. 컨테이너 안에서 /workspace를
# 저장소로 두고 돈다. main.zig는 m2 사본이 -v로 덮여 있다.
set -uo pipefail
cd /workspace
OUT=/tmp/run/bs1
# $GUEST_MEM 하나 때문에 source한다(함수와 변수뿐이다).
source ./gate_lib.sh

(cd kernel && ./build.sh) || exit 1
(cd init && zig build) || exit 1
(cd terminal && ./prepare.sh) || exit 1
(cd kernel && ./make_initrd.sh) || exit 1

SEED="$(mktemp -d)"
mkdir -p "$SEED/services.d"
cp "$OUT/m2probe.sh" "$SEED/services.d/probe"
chmod 0755 "$SEED/services.d/probe"
DISK="$OUT/m2period.img"
rm -f "$DISK"
truncate -s 16M "$DISK"
mkfs.ext2 -F -q -m 0 -L tars-bs1 -d "$SEED" "$DISK"
rm -rf "$SEED"

LOG="$OUT/serial-m2period.log"
rm -f "$LOG"
qemu-system-x86_64 \
  -nic none \
  -m "$GUEST_MEM" \
  -kernel kernel/build/arch/x86/boot/bzImage \
  -initrd kernel/initrd.cpio \
  -append "console=ttyS0 test_power.battery_present=true" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -drive file="$DISK",if=virtio,format=raw \
  -serial file:"$LOG" \
  -no-reboot &
PID=$!

# 0.1초 간격으로 4분까지 본다. t0는 프로브가 잔량을 쓴 줄을 처음 본 때, t1은 칸이 ` 10%`가 된
# 줄을 처음 본 때다.
t0=""
t1=""
for _ in $(seq 1 2400); do
  if [ -z "$t0" ] && grep -aq 'bs1-probe: wrote capacity=10' "$LOG"; then t0="$(date +%s.%N)"; fi
  if [ -n "$t0" ] && grep -aq 'terminal: status> battery cell=" 10%"' "$LOG"; then t1="$(date +%s.%N)"; break; fi
  if ! kill -0 "$PID" 2>/dev/null; then break; fi
  sleep 0.1
done
kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null

grep -aE 'terminal: (battery> |status> battery )|bs1-probe:' "$LOG" | tr -d '\r'
if [ -n "$t0" ] && [ -n "$t1" ]; then
  echo "elapsed=$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.1f", b - a }')s"
else
  echo "elapsed=none (t0=${t0:-none})"
fi
```

돌린다. 빌드 넷과 부팅 하나로 3분 안팎이다.

```bash
cd /Users/dp/Repository/tars-linux
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -v /tmp/run/bs1/mut/m2.zig:/workspace/terminal/src/main.zig:ro \
  -v /tmp/run/bs1:/tmp/run/bs1 -w /workspace tars-devcontainer bash /tmp/run/bs1/m2period.sh > /tmp/run/bs1/m2period.out 2>&1; echo "exit=$?"
rmdir /tmp/run/docker.lock
cat /tmp/run/bs1/m2period.out | rg -a '^(terminal: |bs1-probe:|elapsed=)'
```

기대(줄 순서대로).

```
terminal: battery> scan seen=1 present=1 pick=test_battery
terminal: battery> read test_battery capacity=50 status=Discharging class=normal
terminal: status> battery cell=" 50%" ink norm=N plug=0 low=0
…(같은 줄이 프레임마다)
bs1-probe: wrote capacity=10
terminal: battery> read test_battery capacity=10 status=Discharging class=low
terminal: status> battery cell=" 10%" ink norm=0 plug=0 low=N
elapsed=…s
```

판정은 둘이다 — `scan` 줄이 하나뿐이다(uevent가 안 닿았다), 그리고 `elapsed`가 0보다 크고 62 이하다(60초 주기에 프레임 하나의 여유).
`elapsed`의 값은 "처음 훑기에서 60초"에서 "프로브가 쓴 시각"을 뺀 것에 가까울 것이다(대략 30 ~ 50초) — 그대로 보고에 적는다.
`elapsed=none`이면 주기 읽기가 안 돈 것이다. 그 출력 전부를 보고하고 멈춘다.

### 7-4. 되돌림

mutation은 `-v`로만 덮었으므로 저장소의 `main.zig`는 그대로다. 그러나 `terminal/zig-out` · `kernel/initrd.cpio`에는 m2로 지은 바이너리가
남아 있다. 다음 체인이 `./prepare.sh` · `./make_initrd.sh`를 부르므로 Task 8의 첫 체인이 원본으로 다시 짓는다(Zig는 내용 해시로 판단한다).

```bash
cd /Users/dp/Repository/tars-linux && git status --short && git diff --stat
```

기대: Task 4 · 6이 끝났을 때와 같다 — `main.zig` +392 −10, `check.sh` +7, `machine/check.sh` +28, `??`에 `battery/`(와 BS-M0이 commit
전이면 그 파일들). 다른 것이 보이면 멈추고 보고한다.

## Task 8: 체인 회전

바뀐 것마다 그것을 밟는 체인을 돈다. 순서에 뜻이 있다 — design 위험 6(값이 그대로인 power_supply uevent가 다시 그리기를 부르면 배터리가
없는 체인의 프레임 수가 는다)을 pointer · render가 먼저 본다. 체인 하나가 1~5분이라 체인마다 Bash 호출을 따로 한다.

| 순서 | 체인 | 왜 |
|---|---|---|
| 1 | terminal 호스트 검사 | 체인들이 부팅 전에 `zig build test`를 돈다 — 첫 체인이 그것이다. 따로 안 돈다 |
| 2 | `battery` | mutation 뒤 원본으로 다시 짓고, 체인이 초록인지 다시 본다 |
| 3 | `pointer` | `screen>` 줄을 세는 판정이 있다(design 위험 6). `drainUevents`가 바뀌었다 — 마우스 핫플러그(검사 6)가 같은 함수를 지난다 |
| 4 | `render` | 상태 줄 · 커서 · 이미지의 픽셀을 본다. 프레임 수가 바뀌면 여기서 갈린다 |
| 5 | `hangul` | `status> text=` · `ink fg=` · `caps ink`의 기준값(383 · 87)이 그대로인지 |
| 6 | `machine` | 판정 14 |

```bash
cd /Users/dp/Repository/tars-linux && ch=battery && mkdir -p /tmp/run/bs1/logs-$ch && rm -rf /tmp/run/bs1/logs-$ch/*
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/bs1/logs-$ch:/tmp -w /workspace tars-devcontainer ./$ch/check.sh \
    > /tmp/run/bs1/chain-$ch.log 2>&1 ; } 2> /tmp/run/bs1/chain-$ch.time; echo "$ch exit=$?"
rmdir /tmp/run/docker.lock
tail -n 3 /tmp/run/bs1/chain-$ch.log; cat /tmp/run/bs1/chain-$ch.time
```

`ch=`만 `pointer` · `render` · `hangul` · `machine`으로 바꿔 차례로 친다. 기대: 다섯 다 `exit=0`이고 로그에 `FAIL`이 없다. 시간은 체인마다
보고에 적는다.

그다음 셋을 본다.

1. hangul의 기준값. 같은 줄을 BS-M0의 루트 게이트 로그(lead의 것)에서도 뽑아 견준다.

   ```bash
   rg -a -o '[0-9]+ pixel\(s\) of text and a dim CAPS \(off=[0-9]+\)' /tmp/run/bs1/chain-hangul.log
   rg -a -o '[0-9]+ pixel\(s\) of text and a dim CAPS \(off=[0-9]+\)' /tmp/run/bs0/gate.log | sort | uniq -c
   ```

   기대: 첫 줄이 `383 pixel(s) of text and a dim CAPS (off=87)`이고, 둘째 명령의 줄과 같은 값이다(BS-M0 게이트는 회차가 둘이라 수가 2다).
   다르면 배터리가 없는 화면의 픽셀이 바뀐 것이다 — 멈추고 보고한다.

2. 배터리가 없는 체인의 배터리 줄. 네 체인의 시리얼 로그에서 배터리 줄의 모양을 센다.

   ```bash
   cd /tmp/run/bs1 && for ch in pointer render hangul machine; do
     echo "== $ch"
     rg -a --no-filename -o 'terminal: (battery> |status> battery ).*' logs-$ch/ | tr -d '\r' | sort | uniq -c
   done
   ```

   기대: pointer · render · hangul은 `terminal: battery> scan seen=1 present=0 pick=none`(부팅 수만큼)과
   `terminal: status> battery cell=none ink norm=0 plug=0 low=0`(프레임 수만큼) 두 모양뿐이다. machine은
   `terminal: battery> scan seen=0 present=0 pick=none` 하나와 `cell=none …` 줄이다. `battery> read` 줄 · `cell="` 줄 · `scan failed` 줄은
   없어야 한다. 있으면 멈추고 보고한다. 수는 보고에 적는다.

3. 전체 diff.

   ```bash
   cd /Users/dp/Repository/tars-linux && git status --short && git diff --stat && git diff | rg '^-' && wc -l battery/check.sh
   ```

   기대: `git diff --stat`에 이 milestone의 세 파일이 `terminal/src/main.zig | 402` · `check.sh | 7` · `machine/check.sh | 28`로 있다(BS-M0이
   commit 전이면 그 다섯 파일도 함께 보인다). `rg '^-'`의 줄은 Task 4-9의 열 줄과 각 파일의 머리 줄(BS-M0이 commit 전이면 그 milestone의
   줄)뿐이다. `wc -l`은 397. `??`에 `battery/`(와 BS-M0의 새 파일 둘) 말고는 없다 — 특히 `out/` · `*.img` 산출물이 안 보인다.

## Task 9: 루트 게이트(lead)

terminal 바이너리가 바뀌었으므로 스물두 체인 전부다(design 끝 조건 5). BS-M0의 게이트보다 battery 체인 한 판(회차당 부팅 2회)만큼 길다 —
약 55분이라 lead가 `run_in_background`로 돌린다. 알림이 오면 `pgrep -f 'tars-devcontainer bash check.sh'`가 비었는지 먼저 본다(lessons).

```bash
cd /Users/dp/Repository/tars-linux && mkdir -p /tmp/run/bs1/gate && rm -rf /tmp/run/bs1/gate/*
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/bs1/gate:/tmp -w /workspace tars-devcontainer bash check.sh \
    > /tmp/run/bs1/gate.log 2>&1 ; } 2> /tmp/run/bs1/gate.time; echo "gate exit=$?"
rmdir /tmp/run/docker.lock
```

기대.

- 마지막 줄 `TARS check PASS: all chains 2/2 consecutive runs succeeded (logs in /tmp/tars-gate.…)`.
- `rg -c 'skipping make' /tmp/run/bs1/gate.log`가 `43`(체인 22 × 회차 2 − 1, lessons GL-M1 절).
- `rg 'cut log lines' /tmp/run/bs1/gate.log | rg -v 'A=0 B=0 C=0'`가 아무것도 안 찍는다.
- `rg -a -o '[0-9]+ pixel\(s\) of text and a dim CAPS \(off=[0-9]+\)' /tmp/run/bs1/gate.log | sort | uniq -c`가 `2 383 pixel(s) of text and a dim CAPS (off=87)`.

빨개진 체인이 있으면 design 결정 12의 가름대로 terminal을 먼저 의심한다(커널은 BS-M0에서 스물한 체인을 지났다). battery 체인이 아닌 체인이면
그 회차의 로그에서 `terminal: battery>` · `terminal: status> battery` 줄부터 본다.

## 끝 조건

design "BS-M1" 절의 다섯과 그것을 보는 명령.

| design 끝 조건 | 보는 명령 | 기대 |
|---|---|---|
| 1. battery 체인이 초록이다(검사 0 · A1 ~ A5 · B1) | Task 5-2, Task 8의 2 | `battery exit=0`, `BS-M1 check PASS` |
| 2. machine 체인의 `seen=0` 판정이 초록이다 | Task 8의 6 | `machine exit=0`, `limine's initcall_blacklist kept test_power from registering (battery> scan seen=0)` |
| 3. mutation 셋이 겨냥한 검사에서 빨개진다 | Task 7-2 | m1 → A1, m2 → A2, m3 → A4의 `FAIL` 줄. 덤으로 7-3의 `elapsed` |
| 4. 진입 검사 셋을 새 체인이 통과한다 | Task 6-4, Task 9 | `entry ok ./battery/check.sh`, 게이트가 진입 검사에서 안 멈춘다 |
| 5. 루트 게이트 22체인이 초록이고 hangul의 383 · 87이 그대로다 | Task 9 | `2/2`, `skipping make` 43, cut 셋 0, `383 … (off=87)` 둘 |

## 닫을 때(lead의 몫)

- 이 plan의 `Status:`를 고치고 맨 아래에 "BS-M1이 실측한 것" 절을 더한다 — Task 4의 컴파일 에러를 고친 자리(있었다면), Task 5-2의 픽셀
  수(` 50%` · ` 10%` · `100%`), Task 7의 `FAIL` 줄 셋과 `elapsed`, Task 8의 체인 시간과 배터리 줄 셈, 루트 게이트의 시간.
- design의 "닫을 때" 절 전부(`Status:` · `CLAUDE.md`의 완료 표 · `docs/decisions/project_battery_status.md` · `MEMORY.md` ·
  `project_wireless.md` · `project_real_machine.md` · `docs/guides/lessons.md`의 포트 45494와 체인 목록과 "핵심 파일" · `running-tars.md` ·
  `HANDOFF.md`). `project_battery_status.md`에 이 plan의 확정 4(`capacity`의 `ENOENT`는 빠짐이 아니다) · 8(메모와 다시 그리기의 비교를
  가른 이유) · 14(A3을 로그를 거꾸로 읽어 판정한 이유)를 함께 담는다.
- commit은 하나다 — `main.zig` · `battery/check.sh` · `check.sh` · `machine/check.sh`. `git add`는 그 넷을 이름으로 준다.

## BS-M1이 실측한 것

lead가 2026-10-09에 쟀다. 구현자(Sonnet)의 보고와 `git diff`를 lead가 직접 대조했다 — `main.zig` +392 −10(지운 열 줄은 plan의 `old_string`),
`check.sh` +7, `machine/check.sh` +28, 새 파일 `battery/check.sh` 397줄. 전부 plan 사본과 `cmp`가 같다. 배터리 절의 코드(errno를 읽는 자리 ·
훑기 결과가 바뀔 때만 찍는 조건 · 처음 훑기가 다시 그리기를 안 켜는 것 · `continue` 앞의 배터리 블록)를 lead가 읽고 design 결정 8 · 10과
맞는지 봤다.

1. 빌드. 컨테이너 `prepare.sh` · `zig build test` 초록, 컴파일 에러 0. 호스트 검사 일곱(battery_test 포함) 전부 통과.
2. battery 체인. 첫 판은 검사 A3에서 빨갰다 — plan의 기대 글자 `  10%`(다섯 자)가 틀렸고 실제 칸은 ` 10%`(확정 20). 코드는 맞았다
   (`cell=" 10%" ink norm=0 plug=0 low=66`). 고친 뒤 `BS-M1 check PASS` 37초. 칸 픽셀: ` 50%` norm 73 · ` 10%` low 66 · ` 10%` plug 66 ·
   `100%` plug 90. A3 `same=1 keys=0`, A4의 plug 66 = A3의 low 66, A5 scan 3줄 · read 3줄, B1 첫 프레임에 `100%`.
3. mutation 셋. m1(`present` 파일 이름 바꿈) → A1(첫 scan이 `present=1 pick=test_battery`), m2(`ueventIsPowerSupply` 줄 삭제) → A2(마지막
   scan이 `present=0`인 채), m3(`sameBatteryCell`의 갈래 비교 삭제) → A4(`plug=0 low=66`인 채 — `screen>`은 있고 `status>`는 없어 메모만
   막혔다). 주기 경로(7-3, m2 바이너리): 잔량을 쓴 뒤 칸이 ` 10%`가 되기까지 40.2초(60초 안, scan 줄 하나).
4. 체인 다섯. battery 1분 18초 · pointer 1분 14초 · render 1분 48초 · hangul 1분 22초 · machine 21초 전부 PASS. hangul 기준값
   `383 pixel(s) of text and a dim CAPS (off=87)`이 BS-M0 게이트 로그와 같다. machine 판정 14 `battery> scan seen=0`. 네 체인의 배터리 줄은
   `scan seen=1 present=0 pick=none`(machine은 `seen=0`)과 `cell=none`뿐이고 `read` · `cell="` · `scan failed` 줄은 0.
5. 루트 게이트(22체인 × 2): 22체인 전부 `PASS: 2/2`, 1시간 00분 18초, `skipping make` 43, 44회차 전부 `A=0 B=0 C=0`, hangul `383 … (off=87)` 두 번, 빨간 줄 0
