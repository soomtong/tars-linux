# MS-M1 — init의 `main`을 `Boot`와 단계 일곱으로 나눈다

Date: 2026-10-25
Design: `docs/specs/2026-10-25-tars-main-split-design.md` 결정 8
Status: 끝났다(2026-10-25, 루트 게이트 22/22, prebuild 293초 + lanes 289초). 값은 맨 아래 "MS-M1이 실측한 것".

## 누가 무엇을 하나

고치는 파일은 `init/src/main.zig` 하나다. M0과 같은 이유로 lead가 직접 넣고, 두 Task로 나눠 Task마다 컨테이너 빌드 · 로그 집합
비교 · 체인 하나를 거친 뒤 commit 하나를 만든다. M0(1,072줄)보다 작다 — `main` 406줄 가운데 210줄이 주석이고 코드는 200줄이 안 된다.

| Task | 무엇을 | 검사 |
|---|---|---|
| 1 | `Boot` 필드 · `mountEarly` · `readConfig` · `probeDevices`, `main`의 앞 절반이 그 호출로 | 빌드 · (a) · config 체인 |
| 2 | `buildEnv` · `startHelpers` · `placeChildren`, `main`이 단계 호출 일곱과 `supervise` | 빌드 · (a) · boot 체인 |
| 3 | 호스트 `fmt` · `ast-check`, 루트 게이트, 닫기 | 22/22 |

## 착수 전에 확정한 것

1. 검사 명령은 M0 plan의 확정 1 · 2를 init에 맞춘 것이다. 로그 집합 비교는 `diff -w`다(M0 실측 3).

   ```bash
   rg -o 'logline\.print\(\s*"[^"]*"' --multiline init/src/main.zig | sort > /tmp/ms-init-logs-before.txt   # 56줄
   rg -o 'logline\.print\(\s*"[^"]*"' --multiline init/src/main.zig | sort | diff -w /tmp/ms-init-logs-before.txt -
   docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer bash -c 'zig build && zig build test'
   make check CHAIN=config    # Task 1 — `config shell=` 줄 · seed · 설정 디스크의 길
   make check CHAIN=boot      # Task 2 — 탈출로 1(terminal이 정확히 3번 죽고 rescue가 발동) · 자식 둘의 argv
   ```

   체인을 고른 이유 — config는 `readConfig`가 만드는 로그 줄과 seed 넷, boot는 `-vga none`이라 `children[0]`의 `rescue`와
   `MAX_FAST_RESTARTS`가 실제로 밟힌다(`boot/check.sh`가 재시작 횟수를 정확히 3으로 센다 — `placeChildren`이 `rescue_flag`의 조건을
   그대로 옮겼는지가 거기서 드러난다). 루트 게이트는 나머지(service · net · wifi · audio)를 본다.
2. `Boot`의 모양. 프로세스 수명 내내 살아야 하는 것(design 배경의 아홉)과 단계 사이를 건너는 값이 필드다. init은 힙이 없으므로
   버퍼는 `= undefined` 기본값으로 두고 단계가 채운다. 값으로 돌려주지 않는다 — argv · env 블록이 이 안의 버퍼를 가리킨다(design
   결정 8). `main`의 첫 줄이 `var boot: Boot = .{};`이고 단계는 전부 `*Boot`를 받는다.

   | 묶음 | 필드 | 채우는 단계 |
   |---|---|---|
   | 설정 | `cfg: config.Config` · `mounted: bool` · `noconfig: bool` | `readConfig` |
   | 장치 | `keyboard_path: devices.Path` · `button_fds: [devices.MAX_BUTTONS]i32` · `button_count: usize` | `probeDevices` |
   | 셸 · env | `shell: config.Shell` · `shell_path: [:0]const u8` · `tz_buf: [environ.TZ_ENTRY_MAX]u8` · `tz_entry: []const u8` · `env_buf: environ.Block` · `envp` · `kernel_env` | `buildEnv` |
   | 자식 | `terminal_toggle_buf: [config.TOGGLE_ARG_MAX]u8` · `service_list: services.List` · `live: Live` · `children: [SLOTS]Child` | `placeChildren` |

   `envp` · `kernel_env`의 타입은 지금 `environ.withTarsEnv`의 반환과 `init.environ.block.slice.ptr`의 타입 그대로다(코드를 보고 적는다).
   `shell_path`는 `shell.path()`의 반환 타입이다.
3. 단계 일곱의 서명. `mountEarly()`만 자유 함수다(상태가 없다 — `power.install` · `disableCtrlAltDel` · mount 셋 · `mountDevpts` ·
   `linkDevFd` · `net.loopbackUp`). 나머지는 `Boot`의 메서드다 — `readConfig(self)` · `probeDevices(self)` · `buildEnv(self, init)` ·
   `startHelpers(self)` · `placeChildren(self)`. `init`(`std.process.Init.Minimal`)이 필요한 곳은 `buildEnv`뿐이고(`init.environ.block`),
   `placeChildren`이 `Live.kernel_env`에 넣을 포인터는 `buildEnv`가 `kernel_env` 필드에 남긴다. `main`은 이렇게 된다.

   ```zig
   pub fn main(init: std.process.Init.Minimal) void {
       logline.print("tars-init: starting as PID 1 (TARS {s})\n", .{build_info.version});
       mountEarly();
       var boot: Boot = .{};
       boot.readConfig();
       boot.probeDevices();
       boot.buildEnv(init);
       boot.startHelpers();
       boot.placeChildren();
       // CT-M1. 서비스를 띄우기 전에 연다 — 사람이 부팅 직후에 쳐도 받을 자리가 있다.
       const control_fd = control.open(control.DIR, control.PATH);
       supervise(&boot.children, boot.button_fds[0..boot.button_count], control_fd, &boot.live);
   }
   ```

   `starting as PID 1` 줄은 `main`의 첫 줄로 남는다 — BV design 결정 8의 자리이고 어느 단계에도 속하지 않는다.
4. 단계의 경계는 지금 `main`의 절 그대로다(design 결정 8의 표). `readConfig`는 `mountConfig` → `loadConfig` → cmdline 탈출로 →
   seed 넷 · `makeXdgDir` → `config shell=` 로그 줄까지. `probeDevices`는 `logDrmDevicePresence` → `resolveKeyboard` →
   `openPowerButtons`. `buildEnv`는 `resolveShell` → `resolveTimezone` · `tzEntry` → `withTarsEnv` → `env` 로그 → `ssh_env` ·
   `login.apply`. `startHelpers`는 `audio.start` → `firewall.up`. `placeChildren`은 `want_dhcpcd` · `want_wifi` · `want_chronyd` →
   `services.discover` → `shell_flag` · `console_flag` · `rescue_flag` → `screen_args.encode` → `Live` → `children` 열셋.
   로그 줄의 순서는 그대로다 — `config shell=` → DRM 존재 → `env …` 셋 → (audio · firewall · net · wifi · clock · services가 찍는 줄) →
   `control socket` → `started …`.
5. 지역으로 남는 것 — `toggle_buf` · `toggle_arg` · `ntp_buf`(`config shell=` 로그 한 줄에만 쓰인다) · `ssh_env` · `ssh_env_len`
   (`login.apply` 한 번) · `term_argv`(`children[0].argv`로 바로 들어간다 — 지금도 `const`다) · `shell_flag` · `console_flag` ·
   `rescue_flag` · `want_*`. `toggle_buf`의 주석 "이 배열이 argv로도 간다. `main()`의 스택에 살고 …"는 지운다 — design 확인 3.
6. 수명 주석. "`main()`의 스택에 살고 `supervise()`가 영영 반환하지 않으므로 프로세스 수명 내내 유효하다"는 문장이 여섯 자리
   (`toggle_buf` · `keyboard_path` · `button_fds` · `tz_buf` · `env_buf` · `service_list`)에 있다. `Boot`의 문서 주석에 한 번 쓰고 여섯
   자리에서는 지운다 — 각 필드의 문서 주석은 "무엇인가"만 남긴다. M0의 결정 10("주석은 옮기되 지우지 않는다")의 유일한 예외이고,
   같은 문장의 반복을 하나로 모으는 것이라 지워지는 정보는 없다.
7. 아홉 자리를 세는 `children[SLOT_SERVICES + i]` 반복문과 `placeService` 호출, `Live`의 초기화는 글자 그대로 옮긴다. `Live`의 필드
   `cfg` · `screen` · `mounted` · `noconfig` · `kernel_env` · `envp`가 전부 `Boot`의 필드에서 온다.
8. `supervise` · `doReload` · `doReloadTerminal` · `Child` · `Live`는 건드리지 않는다(design 비목표 3). `supervise`가 `*Live`를 받는
   서명도 그대로다 — `&boot.live`를 넘긴다.
9. 큰 편집은 M0 실측 5대로 줄 번호로 자른다 — `main`의 시작 줄(`pub fn main`)부터 끝의 `}`까지를 새 본문(`Boot` + 단계 여섯 +
   `main`)으로 바꾸고, 그 뒤의 `comptime` 블록(`TZ_ENTRY_MAX` 검사)은 그대로 둔다.
10. 체인 스크립트는 한 줄도 안 고친다.

## Task 1: `Boot` · `mountEarly` · `readConfig` · `probeDevices`

`main` 바로 위에 `Boot`를 선언한다(확정 2). `mountEarly`와 두 메서드를 넣고 `main`의 앞 절반(`power.install`부터
`openPowerButtons`까지)을 그 호출 셋으로 바꾼다. 뒤 절반은 아직 `main` 안에 그대로이되 `cfg` · `storage_mounted` · `noconfig` ·
`keyboard_path` · `button_fds` · `button_count`를 `boot.`로 읽는다.

검사 — 빌드 · (a) · config 체인. commit `MS-M1: Move the init config and device phases into Boot`.

## Task 2: `buildEnv` · `startHelpers` · `placeChildren` · `main`

뒤 절반을 셋으로 나눠 메서드로 옮기고 `main`을 확정 3의 모양으로. 수명 주석 여섯을 `Boot`의 문서 주석 하나로(확정 6).

검사 — 빌드 · (a) · boot 체인. commit `MS-M1: Move the init env and children phases into Boot`.

## Task 3: 호스트 검사 · 루트 게이트 · 닫기

1. 호스트 0.17 `zig fmt --check` · `ast-check`(lessons "범용 명령").
2. 루트 게이트(`run_in_background`, 약 10분). 22/22면 닫는다.
3. 닫을 때(design "닫을 때") — design `Status:`를 "끝났다"로, `docs/guides/completed.md` 한 행, `docs/decisions/project_main_split.md`와
   `MEMORY.md` 한 줄, `HANDOFF.md`(열린 서브프로젝트 없음 · 후보에서 (2) 지우기), lessons "핵심 파일"의 init `main.zig` 줄.
   소개 페이지는 안 넣는다(design 비목표 5).

## MS-M1이 실측한 것

1. commit 둘 — Task 1 `4e85cad`(+145 −110), Task 2 `9bda00d`(+288 −269). `main.zig`는 1,472줄 → 1,526줄(+54). 함수 길이 —
   `Boot` 선언 46 · `readConfig` 85 · `probeDevices` 7 · `buildEnv` 77 · `startHelpers` 16 · `placeChildren` 163(자식 열셋의 리터럴) ·
   `mountEarly` 27 · `main` 27.
2. 두 Task 모두 컨테이너 `zig build && zig build test`가 첫 시도에 통과했고 호스트 `zig fmt`는 한 줄도 안 바꿨다. 체인 — Task 1 config ·
   Task 2 boot 모두 PASS. boot 체인에서 terminal이 정확히 세 번 뜨고 `giving up on terminal`로 끝나는 길(디스크가 없어 `rescue`가
   null인 길)이 그대로였고, init 로그의 순서(`starting` → `config shell=` → `env PATH` → `control socket` → `started …`)도 같았다.
3. 로그 서식 문자열 56개의 집합은 전후 같다(`diff -w`). "지운 줄 가운데 새 파일에 없는 것"은 두 Task 모두 선언 → 필드, `self.` ·
   `boot.` 접두사, 수명 주석 다섯, Task 1의 임시 별명 셋(`const cfg = boot.cfg;` 등)뿐이었다.
4. 확정 2와 달리 `Boot`의 필드는 Task 1에 설정 · 장치 묶음만 선언하고 셸 · env · 자식 묶음은 Task 2에서 더했다 — 채우는 단계와 함께
   들어가는 쪽이 읽기에 맞았다. `tz_entry`의 타입은 `[:0]const u8`(`environ.tzEntry`의 반환), `envp` · `kernel_env`는
   `[*:null]const ?[*:0]const u8`(`Live`와 같다).
5. 편집은 둘 다 줄 번호로 잘라 이어 붙였다(확정 9). Task 2는 필드 · 메서드 · `main` 조각 셋을 따로 파일로 쓰고 `button_count` 줄 ·
   `probeDevices`의 끝 · `mountEarly`의 끝을 경계로 끼웠다.
6. 루트 게이트 22/22(2026-10-25, `out/gate-logs/20261025-001156/`). prebuild 293초 + lanes 289초 — M0과 초 단위까지 같다. 느린 셋은
   CP 184 · TD 182 · CM 164.
