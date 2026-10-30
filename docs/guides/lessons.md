# TARS 작업 요령

서브프로젝트를 넘어 유효한 것만 모은 문서다. 2026-09-27에 `HANDOFF.md`가
193KB까지 자라 거기서 떼어 냈다 — 지금 상태와 다음 할 일은 `HANDOFF.md`에,
서브프로젝트 하나의 경과는 그 design(`docs/specs/`)과 기억
(`docs/decisions/`)에 있고, 이 문서와 아래 표의 네 문서에는 "다음 사람이 같은 벽에 부딪치지 않게"
하는 것만 둔다.

규칙 넷.

- 줄 번호를 적지 않는다. 심볼로 `rg`한다. 틀린 번호는 없는 번호보다 나쁘다.
- 낡은 항목은 고치거나 지운다. 이 다섯 문서에 "그때는 그랬다"를 쌓지 않는다 — 역사는
  git에 있다.
- 서브프로젝트 하나에만 해당하는 것은 여기가 아니라 그 design의 실측 절에 적는다.
- 새 항목은 성격에 맞는 파일에 — 실측은 `measurements.md`, 안 되는 접근은 `dead-ends.md`,
  미룬 일은 `carryover.md`, 파일의 책임과 깨지는 자리는 `key-files.md`. 여기에는 게이트
  운영과 범용 명령만 둔다.

## 옮긴 절 (2026-10-26, LS-M0)

이 문서는 1,736줄까지 자라 2026-10-26에 네 절을 떼어 냈다(옛 파일은
`git show 9dca7d3:docs/guides/lessons.md`, 줄의 내력은 `git blame -C -C`). 지난 plan ·
design · 스크립트 주석이 `lessons "<옛 절 이름>"`으로 가리키는 것은 아래 파일에 있다.
`lessons N` · `lessons 실측 N` · `실측 N`은 `measurements.md`의 N번이다(번호는 그대로).

| 옛 절 이름 | 파일 | 그 안의 `##` 제목 |
|---|---|---|
| 서브프로젝트를 넘어 유효한 실측 | `docs/guides/measurements.md` | (번호 목록 1 ~ 92) |
| 시도했으나 안 되는 접근 | `docs/guides/dead-ends.md` | 조사용 Zig 프로그램을 저장소 밖에서 돌리는 법 |
| 이월 숙제 · IP-M2가 남긴 것 · TR-M2가 남긴 것 | `docs/guides/carryover.md` | IP-M2가 남긴 것 (그대로 이월) · TR-M2가 남긴 것 (그대로 이월) |
| 핵심 파일 · 감독 루프의 구조 · 참고: vendor된 ghostty 소스의 프롬프트 인젝션 | `docs/guides/key-files.md` | 두 프로그램이 함께 컴파일하는 것 (`shared/`) · 게스트 화면 쪽 (`terminal/src/`) · PID 1 쪽 (`init/src/`) · 게이트 · 기억 · 감독 루프의 구조 (HD-M2가 만든 것, 그대로 유효) · 참고: vendor된 ghostty 소스의 프롬프트 인젝션 (조치 불필요, 인지만) |

게이트를 돌리고 읽는 법과 범용 명령은 그대로 이 문서에 있다.

## 게이트를 돌리고 읽는 법

```bash
# 루트 게이트 (스물두 체인 × 1, 동시 JOBS줄 — GP-M2부터 9분 51초. 순차 1회는 32분 23초, 2회는 1시간 01분 18초였다. 회차별 초는 끝의 표)
# 요약 로그는 저장소의 out/ 아래에 두지 않는다 — check.sh의 clean()이 게이트 시작에 out/을 통째로 지워 열린 파일이 떨어져
# 나간다(SA-M1에서 요약 한 줄을 잃었다). 체인별 로그는 게이트가 끝에 out/gate-logs/<시각>/으로 옮기므로 거기는 남는다.
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/gate.log 2>&1

# 반복을 늘리거나 동시 실행 수를 정할 때(파일은 안 고친다). JOBS 기본값은 메모리에서 계산한다 — 4GB면 2, 8GB 이상이면 6
docker run --rm -e RUNS=3 -e JOBS=4 -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/gate.log 2>&1

# 체인 하나
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer ./net/check.sh > /tmp/net.log 2>&1

# 이미지 재빌드 (Dockerfile을 고쳤을 때, 30~50초)
{ time docker build -t tars-devcontainer devcontainer/ ; } 2>&1 | tail -3
```

`--platform`을 붙이지 않는다(`project_build_host_arch`).

게이트를 돌리기 전에 OrbStack이 켜져 있는지 본다 — 꺼져 있으면 `docker.sock`이
없다고 0.2초 만에 끝난다(`orb start`). 저장소를 새로 받았거나 Dockerfile이 바뀐
커밋을 받았으면 이미지부터 굽는다. 안 구우면 `make_initrd.sh`가 sysroot에서 파일을
못 찾아 `make_initrd: cannot resolve …`나 `cp`의 에러로 죽고, 그 메시지가 답이다.

루트 게이트는 Bash 도구의 10분 상한을 넘으므로 `run_in_background`로 돌린다.
완료 알림이 실행 직후에 오는 일이 여러 번 있었다 — 알림이 오면
`pgrep -f 'tars-devcontainer bash check.sh'`가 비었는지 먼저 보고 판정한다.
`| tail`로 감싸지 않는다(진행이 안 보이고 종료 코드가 `tail`의 것이 된다).

체인 목록은 `check.sh`의 `CHAINS` 배열 하나다. 진입 검사 셋
(`require_build_steps` · `require_no_early_exit_pipe` · `require_explicit_nic`)과
실행이 같은 목록을 쓰므로 체인을 더하거나 뺄 때 고칠 자리가 하나다. 셋은 통과하면
아무 말도 안 한다. 새 체인을 게이트 전에 셋에만 대 보는 법:

```bash
bash -c 'source <(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic()/,/^}/p" check.sh)
  require_build_steps ./X/check.sh && require_no_early_exit_pipe ./X/check.sh &&
  require_explicit_nic ./X/check.sh && echo ENTRY-OK'
```

새 체인이 QEMU를 띄우면 `-nic none`이나 `-netdev`를 줘야 한다(WN-M1). QEMU는
NIC를 말하지 않으면 기본 NIC를 붙인다.

타이핑 대기는 `gate_lib.sh`에 있다(`type_keys` · `wait_for_screen` ·
`type_loopback_roundtrips` · `GUEST_MEM=512`). 부르는 쪽은 fd 3(monitor)과 `$LOG`를
갖춰야 한다. `GUEST_MEM`을 QEMU 기본 128MiB로 두면 푼 initramfs가 tmpfs를 채워
기계가 아예 안 켜진다(UT-M2).

쓰는 포트는 45455~45480이다. monitor는 45455(terminal) · 45456(config) ·
45457(input) · 45458(power) · 45459(device) · 45460(render) · 45461(copy) ·
45462(hangul) · 45463(tools) · 45464(net) · 45467~45470(net의 부팅 B~E) ·
45471(machine) · 45472 · 45473(nic) · 45474 · 45480(firewall)이고, `hostfwd`는
45465 · 45466(net)과 45475~45479(firewall)다. `boot` · `install`은 monitor를 안 쓴다.
PD의 `pointer`가 45488(부팅 A) · 45489(부팅 B)를 쓴다(service가 45481~45486, pane이 45487 · 부팅 B 45490 — CB-M0). AU의 `audio`는 부팅 A · B · C가 monitor를 안 쓰고(전원은 프로브의 `kill -TERM 1`) 부팅 D만 45491을 쓴다(`usb-audio`의 `device_add`). VD의 `dictation`은 45492를 TLS 상대(`openssl s_server`, 부팅 A)에, 45493을 부팅 B의 monitor에 쓴다. BS의 `battery`는 부팅 A만 45494를 쓴다(부팅 B는 monitor가 없다). 새 체인은 45495부터 쓴다.

### 회차의 로그는 `out/gate-logs/<시각>/<체인>-<회차>/`에 남고 셈 줄이 먼저 말한다 (AL-M0 · GF-M1)

AL-M0부터 루트 `check.sh`의 `run_chain`이 회차마다 `TMPDIR=<GATE_LOGS>/<체인>-<회차>`를 주고, 체인이 `mktemp`로 만든 게스트 로그가
전부 거기에 남는다(체인은 로그를 안 지운다 — 지우던 8체인 14자리를 AL-M0이 고쳤다. audio는 부팅 넷이 같은 파일을 덮어 써 마지막 하나만
남아 있었다). GF-M1부터 게이트가 어떻게 끝나든(초록 · 빨강 · Ctrl+C) EXIT trap이 그 트리를 저장소의 `out/gate-logs/<시작 시각>/`으로
옮기고 `logs moved to …` 한 줄을 찍는다 — `--rm` 컨테이너의 `/tmp`를 호스트에 묶을 필요가 없다. 통과한 판도 남는다. 다음 게이트의
`clean()`이 `out/`을 지우니 남길 판은 밖으로 옮긴다. `make check CHAIN=x`는 같은 것을 `out/gate-logs/<체인>/`에 둔다. 회차가 끝날 때마다 `cut log lines A=0 B=0 C=0` 한 줄이 찍힌다. A는 `terminal:` 줄
안에 `tars-init:`이 낀 수, B는 그 반대(init 고유 `reload terminal: pid ` 줄 제외), C는 2048바이트를 넘어 ` [cut]`으로 잘린 줄이다. 셋 중 하나라도
0이 아니면 그 회차는 FAIL이다. 체인이 빨갰을 때 이 줄이 0이면 끼어듦은 원인이 아니다 — 그 체인의 판정과 타이밍을 본다.

### 프로브가 연달아 찍는 줄은 줄마다 기다린다 (TC-M3)

앞 줄을 `wait_for_log` · `wait_for_screen`으로 기다리고 다음 줄을 곧바로 `grep`하면 그 사이가 경합이다 — 프로브가 두 줄 사이에
무엇을 재든(TC-M1 wifi 검사 12의 `grep -c` 넷과 `stat`) TCG에서는 수백 ms이고, 열두 판을 지난 검사가 루트 게이트에서 처음 빨갰다
(TC-M3 Task 5c — 실패한 run의 마지막 로그 줄이 정확히 앞 줄이었다). 줄의 머리를 기다리고 값은 그 뒤에 견준다 — 값까지 든 글자를
기다리면 틀린 값이 "안 왔다"로 보인다. 프로세스 하나가 차례로 찍는 줄들(terminal의 시작 줄 셋 `keyboard=` · `hangul=` · `clipboard scope=`)도
같다. TC의 루트 게이트가 드러낸 간헐 셋은 전부 게이트 쪽이었다 — `set`의 답을 안 기다린 것(M2 5b), init 로그가 화면 dump를 자른
것(M3 5b, 바로 아래 AU-M2 절의 덧붙임), 프로브의 둘째 줄을 안 기다린 것(M3 5c).

### 체인은 동시에 돈다 — 둘이 같은 자리에 쓰면 안 된다 (GP-M2)

루트 게이트는 `prebuild`(빌드 한 번) 뒤에 체인을 `JOBS`줄씩 동시에 돌린다. 줄의 출력은 그 줄이 끝날 때 한 덩어리로 찍히고,
빨간 체인이 있어도 끝까지 돈 뒤 `TARS check FAIL: <체인들>`로 모은다. 체인을 더하거나 고칠 때 볼 것 넷.

- 포트는 체인마다 따로다(위의 목록). 같은 포트를 쓰면 동시에 도는 남의 게스트에 붙는다.
- 호스트 쪽 파일은 `mktemp`(회차의 `TMPDIR`)나 그 체인 이름이 든 `out/<체인>-….img`에 둔다. 둘 이상이 같은 경로에 쓰면 안 된다.
  예외인 `out/tars.iso`와 limine 도구는 그것을 쓰는 체인(스크립트가 `make_iso.sh`를 부르는 체인)을 `check.sh`가 한 줄로 묶어 지킨다.
- 체인이 부르는 호스트 검사(`zig build test`)도 같은 컨테이너에서 겹친다. init 검사 일곱이 /tmp 아래 고정 경로를 써서 첫 병렬
  게이트의 10체인이 부팅 전에 죽었다(`dial to a closed listener succeeded`). 검사가 파일을 만들면 `test_scratch.zig`의
  `enter`를 `main` 맨 앞에서 부르고 경로는 상대 경로로 둔다. symlink의 상대 대상은 링크가 놓인 디렉터리에서 풀리므로 같은
  자리의 형제는 이름만 준다.
- 공유 산출물은 제자리에서 다시 쓰지 않는다 — 다 만든 뒤 `mv`로 바꿔치기한다(`make_initrd.sh`, tools 검사 1d).

### 게이트는 첫 회차에만 clean하고 나머지는 증분이다 (GL-M0)

`clean()`은 `run_chain` 안이 아니라 게이트 시작에서 한 번만 불린다. 그래서
회차 시간이 1회차와 뒤 회차에서 크게 다른 것이 정상이다.

빌드 스텝을 빠뜨린 체인은 진입 검사가 막는다. `check.sh`가 첫 부팅 전에
체인 스크립트를 전부 훑어 `kernel/build.sh` · `init`의 `zig build` ·
`terminal/prepare.sh` · `kernel/make_initrd.sh` 넷을 부르는지 본다. 빌드
스텝이 새로 생기면 `BUILD_STEPS` 목록도 함께 고쳐야 한다.

커널은 입력이 안 바뀌면 아예 빌드하지 않는다 (GL-M1). `kernel/build.sh`가
`.config`와 자기 자신의 sha256을 `build/.tars-build-stamp`에 적어 두고 대조한다.
게이트 로그의 `skipping make` 횟수는 `체인 수 × 회차 수`여야 한다(회차 수는 `check.sh`의 `RUNS`, 지금 1 — 그러면 체인 수).
GP-M2부터 clean 직후의 빌드는 체인이 아니라 `prebuild`가 하고(그 출력은 `<GATE_LOGS>/prebuild.out`이라 게이트 로그에 안 섞인다),
체인의 빌드 호출은 전부 건너뛴다. 그 수보다 적으면 어느 체인이 `prebuild`가 안 덮은 입력으로 커널을 다시 빌드한 것이고,
동시에 도는 다른 체인과 같은 트리에 쓴 것이다. `build.sh`가 해시에 들어가는 이유는
`KERNEL_VERSION`이 그 안에 있기 때문이고, 커널 버전을 올릴 사람은 이것을 알아야
한다.


### 이 게이트의 시간은 ±3분 수준의 잡음을 가진다

CM 시절 세 기준선이 51분 20초 → 54분 40초 → 54분 15초인데, 증가분을 갈랐다고
말할 수 있었던 적이 없다. CM-M2는 코드가 분명히 1분 10초를 더했는데도 전체가
25초 줄었다.

GL-M0의 30분 06초는 그 잡음의 열 배라 갈렸다. 절약을 주장하려면 이 정도
크기여야 한다는 기준으로 삼는다.

CS-M0은 세 회차의 폭이 10초였다(21분 27초 · 32초 · 37초). 타이핑을 안
더했으니 안 늘어야 맞고 실제로 안 늘었지만, 이것도 "우리 코드가 시간을 안
더했다"의 증명이 아니라 확인이다.

값이 기준선에서 크게 벗어나면 코드를 의심하기 전에 기계를 먼저 의심한다.
TR-M2를 끝내며 처음 잰 값이 6시간 12분이었고(8배), 판정은 멀쩡히 3/3이었으며
원인은 Chrome의 영상 재생이었다. 이 게이트는 arm64 위에서 `qemu-system-x86_64`를
TCG로 돌리므로 전부 CPU 바운드다. `{ time docker run ... ; } 2> /tmp/gate.time`
으로 감싼다.

### `pmset -g log`로는 CPU 부하를 사후에 알 수 없다 (CM-M2에서 드러났다)

TR-M2 때 Chrome을 짚을 수 있었던 것은 assertion에 앱 이름이 찍혀 있었기
때문이다. 그런 이름이 없으면 이 로그로는 부하를 못 가른다.

- `Amphetamine`과 `caffeinate`는 부하가 아니다. 둘 다 수면 방지 도구이고,
  28분짜리 게이트가 잠들지 않게 해 주므로 오히려 측정에 도움이 된다.
  Claude Code가 스스로 띄운다 — 이것을 배경 부하의 증거로 읽으면 안 된다.
- `coreaudiod` assertion(`com.apple.audio.contextNNN`)은 오디오 세션이
  열려 있었다는 것만 말한다. 어느 앱인지도, CPU를 얼마나 썼는지도 없다.

부하를 정말로 재려면 게이트를 돌리는 동안 `powermetrics`나 `top`으로 표본을
남겨야 한다. 사후에는 못 본다.


### 게이트 로그를 조사하는 법

각 체인은 시리얼 로그를 `mktemp` 파일에 담고 실패했을 때만 뿜는다. GF-M1부터
그 파일이 호스트에 남는다 — 루트 게이트는 `out/gate-logs/<시각>/<체인>-<회차>/`,
`make check CHAIN=x`는 `out/gate-logs/<체인>/`. 특정 줄은 거기서 찾는다.

```bash
make check CHAIN=copy > /tmp/copy.out 2>&1
grep -ah "찾을 문구" out/gate-logs/copy/tmp.*
```

체인을 `docker run … bash copy/check.sh`로 직접 돌리면 `TMPDIR`을 주는 쪽이
없어 예전처럼 컨테이너 `/tmp`에 쓰고 `--rm`과 함께 사라진다. 로그가 필요하면
`make check`를 쓰거나 `-e TMPDIR=`로 bind mount 아래를 준다.

`grep`에 `-a`를 반드시 붙인다. 로그에 NUL이 한 바이트라도 있으면 `grep`이
파일을 binary로 취급해 `Binary file ... matches`만 뱉는다.

긴 게이트를 돌릴 때 `| tail -N`을 붙이지 않는다. `tail`이 파이프가 닫힐
때까지 아무것도 안 내보내서 진행 상황을 볼 수 없다. 파일로 리다이렉트하고
따로 들여다본다. 파이프를 거치면 종료 코드가 `tail`의 것이 되는 것도
주의한다. 에러 본문은 `grep -aE '^src/.*error'`로 뽑는 편이 빠르다.

`style>`·`screen>` 줄을 셀 때는 마지막 프레임만 잘라낸다. 그 줄들은 매
프레임 다시 찍히므로 로그 전체에서 세면 "지금 화면이 어떻게 생겼는가"가
아니라 "부팅 이후 몇 번 찍혔는가"가 된다. `copy/check.sh`의 `last_frame`이 그
방법이고, `inverted_cells`·`screen_count`와 CS-M0의 검사 16이 그것 위에 서
있다.

`terminal/check.sh`의 `Connection refused`는 실패가 아니다. QEMU monitor가
열릴 때까지 0.5초 간격으로 스무 번 다시 시도하는 loop의 첫 시도다
(`terminal/check.sh`의 monitor 재시도 loop).


### 파이프 뒤의 `grep -q`는 게이트가 막는다 (GA-M1)

`check.sh`의 진입 검사에 `require_no_early_exit_pipe`가 있다. 체인 열하나와
`gate_lib.sh`·`check.sh` 자신을 훑어, 주석이 아닌 줄에서 파이프 뒤의
`grep`/`rg`에 `-q`가 있으면 첫 부팅 전에 게이트를 세우고 줄 번호를 찍는다.
`-aqE`처럼 `q`가 플래그 가운데 있어도, `--quiet`와 `rg -q`도 잡힌다.

그래서 이 함정은 이제 손으로 세지 않는다. 고칠 때의 처방은 `-q`를 빼고
`>/dev/null`로 버리는 것이다 — 뒤단이 입력을 끝까지 읽으므로 앞단이
SIGPIPE를 안 받는다.

주의 둘. (1) lint를 고칠 때 `grep -n`을 먼저 걸고 주석을 나중에 거르는
순서를 유지한다 — 뒤집으면 줄 번호가 원본과 어긋난다. (2) lint를 손으로
확인하려고 `check.sh`의 사본을 `/tmp`에서 돌리면 맨 위의
`cd "$(dirname "$0")"`가 작업 디렉터리를 옮겨 체인 파일을 전부 못 찾고,
증상이 거짓 양성과 똑같이 생긴다. 잘라낸 사본에서 그 줄을 빼고 돌린다.

본문은 `docs/decisions/project_gate_accuracy.md`에 있다.

### ⚠ 캐시는 컨테이너 안에서 지운다

`project_zig_out_staleness`의 처방(음성 확인 전에 `.zig-cache`와 `zig-out`을
지운다)을 호스트(macOS)에서 치면 바로 뒤의 `zig build`가
`error: FileNotFound` 한 줄로 죽는다 — 9회 중 2회. 같은 삭제를 컨테이너
안에서 하면 6/6 정상이다. `--verbose`를 줘도 한 줄도 더 안 나오고
컴파일 에러와 구분이 안 되는 모양이라 더 나쁘다. `docker run … bash -c 'rm -rf init/.zig-cache init/zig-out'`
형태로 친다.

### docker 작업은 한 번에 하나 (PD)

OrbStack VM(4GB)에서 cold `zig build`(약 3GB)와 다른 컨테이너의 QEMU(512MB)가 겹치면
OOM(exit 137)이나 VM 재시작이 난다. 체인 하나가 도는 동안 다른 컨테이너에서 빌드하지
않는다. `install` 체인의 시리얼 로그를 남기려면 `rm -rf "$WORK"`를 뺀 사본을 덮는다.

### 로그 문구는 두 곳에 중복된다

`init` 코드(또는 커널)와 `check.sh` 양쪽에 있다. 한쪽을 고치면 다른 쪽도
고쳐야 한다.

`linked /dev/fd to /proc/self/fd`(BH-M2. `config/check.sh`의 1차가 본다) ·
`config shell=… net=… ntp=… timezone=… firewall=… esc_latin=… clipboard=…`(키를 더할 때는 맨 뒤에 붙인다 — EL-M0이 `esc_latin=`을, 같은 날 CB-M0이 `clipboard=`를 그렇게 붙였다. 그리고 이 줄의 판정을 줄 끝 `$`에 고정하지 않는다 — EL이 `esc_latin=on$`로 고정했다가 CB가 뒤에 키를 붙이자 hangul 체인이 깨졌다. 경계는 `( |$)`다, `hangul/check.sh`의 `toggles=` 판정처럼. `terminal: clipboard scope=`는 짝인 terminal 줄이다. `net/check.sh`의
검사 3이 `config shell=.* net=dhcp`로 본다 — 앞부분을 고치면 다른 체인들의
grep이 함께 깨진다) · `net=off, leaving the network alone`(NW-M2. 꺼진
부팅도 침묵하지 않는다) · `started dhcpcd (pid N), it picks the interface`(WN-M2. `net` · `nic`가 보고,
`net link`는 없어야 한다) · `firewall=off, inbound is open` ·
`firewall up from /etc/tars/firewall.nft,` · `firewall up from /etc/tars/firewall-base.nft` ·
`nft -f /etc/tars/firewall.nft exited 1`(FW. `firewall/check.sh`가 본다) ·
`eth0: leased 10.0.2.15`(dhcpcd 자신의 말. 검사 5가 이것을 기다린다) ·
`signal handlers installed (TERM, INT)` · `ctrl-alt-del now arrives as SIGINT` ·
`shutdown requested (action power_off)` · `shutdown requested (action restart)` ·
`sent SIGTERM to every process` · `sent SIGHUP to every process`(SL-M1.
`power` 부팅 둘과 `device`가 본다) · `every child is gone (reaped N)` ·
`grace period expired (reaped N)` · `sent SIGKILL to what was left` ·
`filesystems synced` · `calling reboot(POWER_OFF)` · `calling reboot(RESTART)` ·
`giving up on terminal` · `started terminal`(개수 3) ·
`started console shell`(개수 1) · `restarting {s} in 1s` ·
`keyboard device /dev/input/event` · `no keyboard found`(없어야 한다) ·
`power button /dev/input/event` · `watching N power button(s)`(개수 1) ·
`no power button found`(없어야 한다) · `power button pressed` ·
`ACPI: button: Power Button`(커널) · `reboot: Power down`(커널) ·
`Power off not available: System halted instead`(커널, 없어야 한다) ·
`Restarting system`(커널, 끄는 부팅에는 없어야 하고 재시작 부팅에는 있어야 한다) ·
`terminal: style>` · `terminal: pixel>` · `terminal: render> first frame` ·
`terminal: ink>` · `terminal: font>` · `terminal: scroll>` · `terminal: key>` ·
`terminal: copy>` · `terminal: copy> word_next` · `terminal: copy> word_prev`
(CN-M0) · `terminal: clip>` · `terminal: clip> paste len=… bracketed=…`(`bracketed=`는 PE-M1, 맨
뒤에 붙였으므로 `clip> paste len=11`을 접두로 보는 판정이 그대로 맞는다) ·
`terminal: find> open` · `terminal: find> type needle=… len=…` ·
`terminal: find> erase` · `terminal: find> cancel` ·
`terminal: find> submit matches=… moved=… us=…` ·
`terminal: find> next moved=…` · `terminal: find> prev moved=…`(CN-M1) ·
`terminal: style> N cell(s) hidden by the find prompt`(CN-M1) ·
`terminal: find> hl spans=… cells=… cur=… us=…`(CS-M0, `cur=`은 SP-M0) ·
`terminal: find> overlay text=…`(CS-M1. SP-M1 뒤로 `/needle [3/12]`도
이 줄로 나온다 — 새 로그를 하나도 안 만들었다) ·
`terminal: cursor> vt=… drawn=… row=… col=… cols=… ink=… box=…`(CU-M0. 매
프레임 `dumpInk` 뒤에 찍힌다. 셸 커서가 없으면 `vt=… drawn=none`으로 끝난다.
`render` 검사 20~32가 본다. 25~32는 CU-M1이 vim으로 더했다) ·
`tars-init: audio: alsactl init once a sound card shows up (pid N)` · `alsactl init turned the mixer on (generic rules, exit 99)` ·
`alsactl restore set the mixer from /config/asound.state` · `stored the mixer in /config/asound.state` · `mixer not stored, it was not
set this boot` · `no sound card within 5000ms, the mixer is left alone`(AU-M1, `init/src/audio.zig`) · `default card is N for playback, N
for capture` · `… N (device 6) for capture`(AU-M2 · M3, 바뀔 때만) · `audio-probe: …` 줄들(`audio/probe.sh`가 찍고 `audio/check.sh`가
본다 — 끝을 봐야 하는 값은 대괄호로 감싼다) · `snd_hda_codec_generic hdaudioC0D0: autoconfig for Generic`(커널) ·
`usbcore: registered new interface driver snd-usb-audio`(커널, 부팅 D) ·
`terminal: dictate> start pid=N ws=N leaf=N` · `phase recording` · `stop pid=N` · `phase transcribing` · `cancel pid=N` · `ignored phase=…` ·
`exit code=N`/`exit signal=N` · `insert len=N bracketed=0|1 ws=N leaf=N` · `refused password at=start|insert …` · `no pane shell=N` ·
`notice …` · `nothing left to insert` · `spawn failed at …`(VD-M1, `terminal/src/main.zig`의 받아쓰기 절 — 받아 적은 글자는 어느 줄에도
없다) · `terminal: status> dict ink=N` · `tars-dictate: recording; Ctrl+C stops (at most Ns)` · `tars-dictate: recording stopped …`(VD-M0의
표준 에러 — M1부터 terminal이 파이프로 읽어 단계를 옮기고 시리얼에 다시 찍는다. 글자를 바꾸면 `dictation.phaseAfter`와 체인이 함께
깨진다) · `dictate-probe: …`(`dictation/probe.sh`) · `stub: POST /ok/s1 …`(`dictation/stub.pl`의 로그 — 체인이 요청 수와 WAV 머리를 센다)

새 copy 명령의 로그는 공짜다 — switch 아래의 `dumpCopy(screen,
@tagName(cmd))`가 이미 찍는다. 새 `dump` 함수를 만들지 않는다. `find>`는 그와
별개로 프롬프트 내용을 찍는 창구다 — 오버레이는 `cells()`에 안 섞여
`screen>`에 영영 안 나오므로 이 줄이 유일한 관측 수단이다.

`find> hl`과 `find> overlay`는 매 프레임 찍힌다(CS-M0·CS-M1). "바뀔 때만"으로
하면 상태가 하나 늘고, 그 판정이 틀렸을 때 증상이 "로그가 안 나온다"라 조사하기
나쁘다. `style>`가 프레임당 16줄 상한이라(`STYLE_DUMP_LIMIT`) 셀 수를 그것만으로
셀 수 없다 — `find> hl`에는 상한이 없고, 둘을 함께 보는 것이 검사 16이다.

`find> overlay`가 오버레이 내용의 유일한 관측 수단이다(CS-M1). `screen>`에
영영 안 나오는 데다 `dumpStyles`도 덮인 줄을 통째로 건너뛴다(`overlaid_row`).
`find> submit matches=0`은 "검색이 못 찾았다"까지만 말하지 "화면에 그렇게
쓰였다"를 말하지 않는다 — 그 둘을 가르는 것이 검사 18이다.

`terminal: screen>`의 형식은 절대 바꾸지 않는다 — 다섯 체인이 이 줄로
화면을 판정한다. CN-M1의 검색 프롬프트가 오버레이인 이유가 이것이다.


### 커널 printk가 terminal의 화면 줄을 가운데서 자른다 (AU-M2)

커널의 콘솔 출력은 UART에 직접 쓰고(console write), terminal이 `/dev/console`에 쓴 것은 tty 버퍼를 거쳐 IRQ로 한 글자씩 나간다.
그래서 printk 한 줄이 terminal의 `screen>` 덤프 한가운데에 떨어질 수 있다 —

```
terminal: screen> … | 196 | [    7.359211] random: crng init done\r\n
197 | 198 | 199 | 200 | root@(none) ~# \r\n
```

뒤 조각에는 머리가 없어 `grep "terminal: screen>"`이 못 보고, 기다리던 글자가 거기 있으면 `wait_for_screen`이 15초 뒤에 빨개진다.
AU-M2 루트 게이트에서 `pointer` 체인 부팅 B의 `seq 200`이 그렇게 죽었다(1회차는 초록, 2회차만 — crng 초기화 시각이 판마다 다르다).
`gate_lib.sh`의 `joined_screen_dump`가 꼬리에 커널 시각 표식(`CONFIG_PRINTK_TIME`)이 붙은 `screen>` 줄을 다음 줄과 이어 붙이고,
`wait_for_screen`은 그것을 읽는다. 체인이 `grep -a 'terminal: screen>' "$LOG" | tail -n 1`로 직접 읽는 자리 67곳은 그대로다 —
기다림이 성공한 뒤의 같은 덤프를 읽으므로 드물지만, 그 자리가 이상한 값으로 빨개지면 로그에서 `[ *[0-9]*\.[0-9]*\]`가 `screen>`
줄 안에 있는지 먼저 본다. 한 write()로 쓴다고 안 잘리는 것이 아니다 — 자르는 것은 전송이지 write가 아니다.
덤으로 하나 — `gate_lib.sh`에 함수를 더할 때는 체인들이 같은 이름을 이미 정의하고 있는지 `rg`로 먼저 본다. 처음 이름이
`screen_lines`였는데 `pointer/check.sh`가 같은 이름으로 화면 줄 개수를 세고 있어서(source 뒤에 정의되어 덮는다) `wait_for_screen`이
화면 대신 숫자 "3"을 받아 세 판 내리 "프롬프트가 안 떴다"로 빨갰다. 증상은 결정적이었고 `set -x`가 한 번에 보여 줬다.

덧붙임(TC-M3, 2026-10-07). init의 줄도 같은 UART에 써서 같은 모양으로 자른다 — TC-M3 루트 게이트 2회차의 config 7차가 `whence -w fzf`
뒤에 끼어든 `tars-init: audio: no sound card within 5000ms …` 때문에 마지막 dump를 못 이어 빨갰고(그 뒤 화면이 안 바뀌어 새 dump가
없었다 — 한 번의 자름이 곧 실패다), `joined_screen_dump`가 이제 `tars-init: ` 조각도 떼고 잇는다. 접두사는 일부러 그 하나로 좁다 —
`[a-z-]+: `로 넓히면 화면 글자 `fzf-history-widget: function`을 끼어든 줄로 보고 뗀다. 루트 `check.sh`의 진입 검사
`require_screen_dump_joins`가 잘린 조각 넷(안 잘림 · printk · init · init 조각과 온전한 tars-init 줄)을 QEMU 없이 0.1초에 보므로, 다른
쓰기(dhcpcd `[pid]:` · sshd · 서비스)의 접두사를 더할 때 그 함수에 조각 하나를 함께 더한다.

덧붙임(GF-M2, 2026-10-24). 자르는 것은 `screen>` 줄만이 아니다. GF-M1 루트 게이트의 pointer가 `terminal: pointer> at … ink=118[   12.315317]
random: crng init done`으로 빨갰고(`wait_for_at`의 `ink=118$`), 같은 판의 로그 57개에서 terminal 줄 안에 커널 시각 표식이 든 체인이
여섯이었다(style> · pixel> · scroll> · pointer>). `gate_lib.sh`의 `tlog`가 이제 모든 `terminal:` · `kms:` 줄을 같은 규칙으로 잇고(뗀 커널
조각은 바로 뒤에 제 줄로 다시 낸다 — pointer가 `input: QEMU QEMU USB Mouse` 줄을 센다), 체인이 terminal 줄을 `grep -a … "$LOG"`로 직접
읽던 119곳이 `tlog | grep -a …`가 됐다. `-q` · `-c`는 그대로다(머리는 안 잘리고, `-q`는 파이프 뒤에서 SIGPIPE). 위 "67곳" 처방은 이로써
닫혔다. `tlog`는 1MB 로그에서 24ms(grep 8ms)라 폴링 0.1초 안이지만, "표지가 보일 때까지 기다린 뒤 마지막 줄을 읽는" 자리는 그 사이 새
프레임의 부분 줄을 읽을 수 있다 — pointer `probe_result`가 그렇게 ''를 읽어 "표지가 든 마지막 줄"을 읽게 고쳤다. 새 읽기를 쓸 때는 기다린
글자가 든 줄을 읽는다.

덧붙임(RS-M2 · M3, 2026-10-11). 앞에 붙는 것도 있다. 콘솔(`/dev/console`)에 도는 둘째 fish의 프롬프트가 줄바꿈 없이 끝나
바로 다음에 쓰인 terminal의 줄이 무엇이든 그 뒤에 붙는다(`ESC]133;A;…root@(none) ~# …ESC[=5u=terminal: …`). 콘솔 fish는 TCG에서
늦게 떠 부팅 뒤 아무 때나 찍힌다. 전부터 있었는데 붙는 줄이 대개 `screen>`이라 곧 다음 프레임이 와서 안 보였고, RS-M2가 프레임을
줄이자 pointer · battery 체인이 빨갰다. `joined_screen_dump`가 줄 중간의 `screen>`도 읽고, 마지막 줄을 꺼내 `^terminal:`로
대조하거나 통째로 비교하는 자리는 `from_terminal`을 거친다. 새 대기 함수가 그렇게 대조하면 `from_terminal`을 끼운다. 진입 검사의
조각은 `console`이다.

### 호스트 부하 아래 dmix가 xrun 구간을 두 번 더한다 (AU-M1)

`audio` 체인의 사각파 판정이 간헐적으로 `other` 16~19프레임으로 빨갰다. 부하 없이 열다섯 판은 전부 0이고, 컨테이너에 CPU 부하
여섯(`perl -e '1 while 1'`)을 걸면 다섯 판 중 둘이 그랬다. 그 프레임은 정확히 두 배(±16000) 49프레임이 한 덩어리로 있고 뒤가
0이다 — TCG 게스트의 하드웨어 포인터가 밀려 xrun이 나면 dmix가 그 구간을 하드웨어 버퍼에 두 번 더하고 나머지를 비운다. 우리 코드도
볼륨도 아니다(볼륨이 틀리면 값이 ±800이 되어 `tone`이 0이다). `count_tap`이 `doubled`를 따로 세어 판정에 안 쓰고, 사각파 하한은
48,000 중 40,000이다(하한의 일은 음소거 · 틀린 볼륨을 잡는 것이고 둘 다 `tone`이 0이다). 부하 없는 루트 게이트에서도 47,9xx가
나온다 — xrun은 늘 조금 있다.

### 폭 고정 칸의 기대 글자는 검사 출력에서 베낀다 (BS-M1)

배터리 칸은 `battery.CELL_LEN` 넉 자이고 숫자를 오른쪽에 붙인다. 그런데 BS의 design 결정 11 표와 M1 plan이 잔량 10의 칸을
`  10%`(공백 둘, 다섯 자)로 적었다. 실제는 ` 10%`이고 공백 둘은 `  5%`뿐이다. 코드는 맞았고 첫 battery 체인이 A3에서
빨갰다(`cell=" 10%" ink norm=0 plug=0 low=66`). 앞 공백의 개수는 사람이 눈으로 세면 틀리는 값이다. 칸의 폭을 고정하는
함수(배터리의 `cellText`)가 있으면, 게이트의 기대 글자는 사람이 적지 않고 그 함수의 호스트 검사가 찍은 값이나 실측 줄에서
베낀다. 판정 글자를 따옴표로 감싸 찍는 것(`cell=" 50%"`)도 같은 이유다 — 따옴표가 없으면 로그에서도 앞 공백이 안 보인다.

## 범용 명령

끝난 milestone의 측정 하네스는 여기 없다 — 각 plan의 Task에 글자 그대로 있다.

```bash
# 통과한 회차의 시리얼 로그를 본다. GF-M1부터 make check가 체인의 TMPDIR을
# 끝에 out/gate-logs/<체인>/으로 옮기므로 따로 꺼낼 일이 없다. 새 화면 판정을
# 넣었으면 실패 대비가 아니라 기본 절차다. 시리얼 로그는 tars-init 줄이 든 파일이다.
make check CHAIN=net > /tmp/net.out 2>&1; echo "exit=$?"
SERIAL="$(grep -al "tars-init" out/gate-logs/net/tmp.* | head -1)"

# render verify(DR-M1)의 줄. 루트 게이트는 회차마다 check_verify_lines로 판정하지만 make check에는
# 판정이 없다 — 돌린 뒤 ok가 아닌 줄을 이렇게 본다. 한 줄도 없으면 initrd의 표식이 빠진 것이다
# (TARS_RENDER_VERIFY). 커널 printk가 자른 줄은 여기 걸리므로 하나면 tlog로 이어서 다시 본다.
grep -rah 'terminal: verify>' out/gate-logs/net | grep -av ' ok us=' | grep -av ' on bytes='

# 흔들리는 검사를 잡을 때는 위를 여러 판 돌리고 죽은 판의 로그만 남긴다.

# 그 로그에서 ANSI를 걷어내고 마지막 화면을 행으로 복원한다.
# ⚠ tr '|'가 명령줄 안의 파이프 문자도 함께 쪼갠다(IN-M1 실측 9).
perl -pe 's/\e\][^\a\e]*(\a|\e\\)//g; s/\e\[[0-9;?>=]*[a-zA-Z]//g;
          s/\e[()][AB0]//g; s/\r/\n/g' "$SERIAL" > /tmp/serial.clean
grep -a "terminal: screen>" /tmp/serial.clean | tail -1 | tr '|' '\n' | tail -12

# mutation은 사본을 만들어 -v로 덮는다. sd는 파일 인자를 in-place로 고치므로
# cp를 먼저 하고 사본에 친다. 사본에 chmod +x를 잊지 않는다.
cp net/check.sh /tmp/run/check.sh && sd -F '<뺄 것>' '' /tmp/run/check.sh && chmod +x /tmp/run/check.sh
docker run --rm -v "$PWD":/workspace -v /tmp/run/check.sh:/workspace/net/check.sh:ro \
  -w /workspace tars-devcontainer bash net/check.sh

# 도구 하나가 실제로 부르는 것을 세기 (Installed-Size가 아니라 이것을 본다).
# 재귀로 따라가는 판은 FW-M0 plan의 Task 2에 있다.
docker run --rm tars-devcontainer bash -c '
  apt-get update -qq; mkdir -p /tmp/w; cd /tmp/w
  apt-get download -qq <패키지>:amd64 >/dev/null 2>&1
  mkdir -p root; for d in *.deb; do dpkg -x "$d" root; done
  readelf -d root/<경로> | sed -n "s/.*(NEEDED).*\[\(.*\)\]/  \1/p"'

# 게스트 패닉 trace의 주소를 파일:줄로 푼다. initrd의 우리 바이너리는 --strip-debug라
# 게스트는 `???:?:?: 0x… in main.App.tick`까지만 찍는다(LI-M1). 원본은 zig-out에 있다 —
# 그 로그를 낸 빌드의 zig-out이어야 한다(다시 빌드하면 주소가 바뀐다). non-PIE라 주소를
# 그대로 넣는다. -i가 게스트 trace에 없는 inline 사슬을 낸다. init 계열은 init/zig-out/bin/<이름>.
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  x86_64-linux-gnu-addr2line -f -i -C -e terminal/zig-out/bin/terminal 0x1190982 0x112b42d

# initrd 목록 (gzip이다 — cpio에 바로 주면 0줄이다)
zcat kernel/initrd.cpio | cpio -it 2>/dev/null | grep <이름>

# 설정 디스크를 부팅 없이 읽고 쓰기
debugfs -R "ls -l /" <이미지>; debugfs -R "cat tars.conf" <이미지>
debugfs -w -R "write <호스트 파일> <디스크 안 경로>" <이미지>

# 대화형 셸을 재는 컨테이너 (devcontainer에는 zsh도 fish도 없다).
# 스크립트는 호스트에서 Write로 만들고 docker cp로 넣는다(heredoc 금지).
docker run -d --name tars-measure tars-devcontainer sleep 7200
docker exec tars-measure bash -c 'apt-get update -qq && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq zsh fish >/dev/null 2>&1'

# 게이트가 아닌 1분짜리 검사(GH-M0). 호스트의 shellcheck · zig로 shellcheck(51파일, warning 이상) ·
# zig fmt --check · ast-check · shared/의 순수 검사 · init 크로스 빌드. 명령은 quick_check.sh에 있고
# CI(.github/workflows/checks.yml의 host job)가 같은 파일을 돌린다 — 사람이 안 돌려도 push마다 돈다.
# "shellcheck notes: N" 줄은 판정이 아니다(기준선 46, 2026-10-30). 호스트 검사(zig build test)는 여기에 없다 —
# macOS에서 init 검사가 안 끝난다. CI의 container job이 push마다 돈다(GH-M1).
make quick
```

편집 스크립트를 셸 heredoc으로 감쌀 때 바깥 구분자가 안쪽 내용의 `EOF`와 겹치면
zsh가 파싱에서 멈춘다(FW-M1). 안쪽에 heredoc이 있으면 스크립트를 Write로 파일에
쓰고 돌린다.
