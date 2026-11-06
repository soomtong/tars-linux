# TP-M6 — BEAM 언어(erlang · elixir · gleam), 여섯째 묶음 lang-beam

> 2026-11-06, `feaa5ec` 기준. 줄 번호는 낡을 수 있다. 결과는 끝의 "결과" 절(구현 뒤 채운다).

Goal: design "Milestone"의 순서대로 BEAM 계열 셋을 새 묶음 `lang-beam`(design 결정 7의 이름)에 싣는다. 판정은 묶음마다의 것 — 망 없이 hello
(design "판정"의 TP-M2 이후 줄).

사용자 결정(2026-11-06, 조사를 단계별로 보고): gleam은 캐시 시드에 더해 `gleam new` 뒤 `manifest.toml`을 넣는다(결정 D). 조사의 네 단계
(erlang · elixir · gleam · erlang의 man)마다 결과를 보고 다음으로 넘어갔다.

## 착수 전 확인 (2026-11-06)

amd64 trixie-slim 컨테이너(OrbStack), 망을 끊고(`--network none`) 돌렸다.

1. 판과 sha256:

   | 도구 | 판 | 받는 것 | 크기 | sha256의 출처 | 풀린 크기 |
   |---|---|---|---|---|---|
   | erlang | OTP-29.1.2 | builds.hex.pm `builds/otp/amd64/ubuntu-24.04/OTP-29.1.2.tar.gz` | 76,377,800 | `builds.txt` 넷째 열 | 175MiB |
   | erlang man | 29.1.2 | erlang/otp release `otp_doc_man_29.1.2.tar.gz` | 1.9MB | GitHub `digest` = `SHA256.txt` | man 606 |
   | elixir | 1.20.5 | elixir-lang/elixir release `elixir-otp-29.zip` | 8,643,796 | GitHub `digest` | 30MiB 안팎 |
   | gleam | 1.19.2 | gleam-lang/gleam release `gleam-v1.19.2-x86_64-unknown-linux-musl.tar.gz` | 10,565,692 | GitHub `digest` | 25MiB 안팎 |

   erlang/otp의 GitHub release에는 linux 바이너리가 없다(Windows · 소스 · 문서). builds.hex.pm이 design 결정 1의 `prebuilt` 자리다. ubuntu-22.04판
   (GLIBC 2.35까지)과 24.04판(2.38까지) 둘 다 trixie(2.41)에서 선다 — 더 새 도구 사슬인 24.04판으로 한다.
2. erlang: tarball(맨 위 `OTP-29.1.2/`)을 푼 것만으로는 `bin/erl`이 없다. 동봉 `Install`이 `erts-17.1.1/bin/erl.src`의 `%FINAL_ROOTDIR%`에 경로를
   박고 실행 파일 · 부트 파일을 `bin/`에 놓는다. `sed` · `cp`뿐이라 arm64 빌드 컨테이너에서 돈다. `-cross`는 "파일이 있는 자리(`pwd`)"와 "박을
   경로(인자)"를 가른다 — 다른 자리에서 `Install -cross -minimal /usr/local/lib/erlang-29.1.2`를 돌리고 그 트리를 옮겨도 선다. 만들어진 `erl`은
   `find_rootdir "$0"`로 자기 자리를 먼저 찾는다 — `/usr/local/bin`의 링크로 불러도 선다(elixir · gleam이 그 링크 위에서 돌았다).
   - `beam.smp`의 `NEEDED`: libtinfo · libz · libstdc++ · libm · libgcc_s · libc. crypto NIF는 libcrypto.so.3. `%ymm` 0. 판은 `emu_flavor=jit` 하나다.
   - 망 없이 `erl -noshell -eval`(crypto sha256까지) 1.5초, `erlc` + 실행 `tp-erlc=42`, `escript`의 `ssl:start()` `ok`.
3. elixir: zip에 맨 위 디렉터리가 없다(`bin/` · `lib/` · `man/`). 셸 스크립트가 링크를 따라 자기 자리를 찾는다. 망 없이 `elixir -e`
   (`tp-ex=1.20.5-42`, 2.0초) · `iex`(`40 + 2` → 42) · `mix new` · `mix compile` · `mix test`가 된다. 의존 없는 프로젝트는 `~/.hex` · `~/.mix`를 만들지
   않는다. 로캘이 UTF-8이 아니면 매번 `native name encoding of latin1` 경고 — TARS는 init이 `LANG=C.UTF-8`을 준다(`environ.zig`).
   - `mix test` 한 판이 `qemu: uncaught target signal 4 (Illegal instruction)`로 죽었다. 같은 명령의 다음 판과 `+JMsingle true` 판은 지났다.
     OrbStack이 그 프로세스를 qemu-user로 돌렸고 컨테이너의 `/proc/cpuinfo`에 기능 플래그가 없었다 — 결정적이지 않으므로 바이너리의 CPU 수준이 아니라
     에뮬레이터 쪽으로 본다(위험 1). 판정은 체인(SandyBridge를 흉내 내는 시스템 QEMU)이 한다.
4. gleam: musl 정적(static-pie). 함수 53,287개 가운데 `%ymm` · `%zmm`을 쓰는 것은 130개 — aws-lc의 손 어셈블리(`aes_gcm_*_avx512` 둘이
   39,177개씩) · 이름에 `avx2`가 붙은 함수 · `memchr` · `aho_corasick`. 실행 중에 CPUID로 고르는 경로다.
   - `gleam new`가 만든 프로젝트는 `gleam_stdlib`(dependencies) · `gleeunit`(dev)를 Hex에서 받는다. 망 없이는 판 고르기(`Resolving versions`)에서
     `repo.hex.pm/packages/gleam_stdlib`에 묻다가 실패한다. 캐시를 채워도, `gleam.toml`에 판을 정확히 적어도 같다. `--offline`은 없다.
   - 망이 있을 때 받는 것: `gleam_stdlib 1.0.5` · `gleeunit 1.11.0`, 164KB. 캐시 `~/.cache/gleam/hex/hexpm/packages/<outer_checksum 대문자>.tar`.
   - `manifest.toml`(판과 `outer_checksum`을 고정)이 있고 캐시가 차 있으면 망 없이 `gleam run` · `gleam test`가 된다.
   - 런처 시험(사용자 tars, 망 없음, 빈 캐시): 기본 · `--template javascript` · `--name hi_there p3dir`가 모두 `manifest.toml`을 받고 선다. 이미 있는
     디렉터리에는 gleam이 새로 만들기를 거부하고 런처도 손대지 않는다. 첫 실행이 캐시에 tarball 둘을 채운다.
5. erlang man: `otp_doc_man`은 `man/` 아래 man1 17 · man3 542 · man4 9 · man6 13 · man7 25. `Install`의 `format_man_pages`는 `cat*` 디렉터리를
   만들 뿐이다 — `Install` 뒤에 `<ROOT>/man`으로 풀면 된다. 망 없이 `erl -man lists` · `erl -man erl`이 man-db로 열린다. man3 이름은 `.3`이다
   (`string.3`은 C의 `string(3)`과 부딪친다).

## 결정 (이 plan이 정한다 — 뒤집을 것이 있으면 글자로)

A. 묶음은 `lang-beam`(design 결정 7). `DEV_LAYERS` · 체인의 `LAYERS` · `ISO_LAYERS`에 넣고, 이름 순이라 lowerdir는 `… lang-beam lang-jvm …`
   자리다(`base` 다음). 체인의 묶음 수는 여섯이 된다.
B. 새 종류 `hex`. `maven`(TP-M5 결정 B)과 같은 꼴 — URL 자리는 잠금 파일(`devlayer/hex/<이름>.lock`, 한 줄에 `<이름>-<판>.tar <sha256>`), sha256 자리는
   그 파일의 sha256. build.sh가 `https://repo.hex.pm/tarballs/<이름>-<판>.tar`를 받아 sha256을 대조하고, `into=`의 도구 디렉터리 `seed/packages/`에
   `<sha256 대문자>.tar`로 둔다 — gleam 캐시의 이름이다. Hex는 tarball의 sha256을 레지스트리의 `outer_checksum`으로 낸다(그 값이 `manifest.toml`에
   있다) — upstream의 `digest`와 같은 자리.
C. erlang은 `prebuilt` 한 줄(`hook=otp-install`)과 man 한 줄(`upstream`, `into=erlang strip=0`). 훅 `devlayer/hooks/otp-install.sh`는 tarball을 도구
   디렉터리에 풀고(맨 위 하나를 벗긴다) 그 안에서 `./Install -cross -minimal /<도구 디렉터리>`를 부른다. 자리표가 남으면 멈춘다.
   `exe=bin/erl,bin/erlc,bin/escript,bin/dialyzer,bin/typer,bin/ct_run`.
D. gleam(사용자 결정): `upstream` 한 줄(`hook=gleam`)과 `hex` 한 줄(`gleam-seed`, `into=gleam`). 훅 `devlayer/hooks/gleam.sh`가 진짜 바이너리를
   `libexec/gleam`에, 런처를 `bin/gleam`(`exe=bin/gleam`)에 둔다. 런처(확인 4의 시험판 그대로):
   - 실행마다 `${XDG_CACHE_HOME:-$HOME/.cache}/gleam/hex/hexpm/packages/`에 없는 tarball만 `seed/packages/`에서 `cp -r --update=none`.
   - `libexec/gleam`을 부르고, 하위 명령이 `new`이고 성공했으면 만든 디렉터리(`--name` · `--template`의 값을 건너뛴 첫 위치 인자)에 `manifest.toml`이 없고
     `gleam.toml`의 두 요구가 gleam 기본 틀(`">= 1.0.0 and < 2.0.0"`)과 같을 때만 `seed/manifest.toml`을 넣는다.
   - 시드 `manifest.toml`은 `devlayer/files/lang-beam/usr/local/lib/gleam-1.19.2/seed/manifest.toml`(TP-M4 결정 D의 자리). 잠금 파일의 sha256과
     그 파일의 `outer_checksum`이 같아야 한다 — build.sh가 대조한다(`hex` 줄을 굽는 뒤, files 얹은 뒤).
   - 대가(사용자가 받아들였다): 망이 있을 때도 새 프로젝트는 `gleam_stdlib 1.0.5` · `gleeunit 1.11.0`으로 시작한다. `gleam update`로 올린다.
E. elixir는 `upstream` 한 줄, `strip=0 exe=bin/elixir,bin/elixirc,bin/iex,bin/mix`.
F. 새 선택 키 `man1=<디렉터리>`: 도구 디렉터리 기준 그 디렉터리의 `*.1`을 `/usr/local/share/man/man1/`에 링크한다(이름이 이미 있으면 멈춘다).
   erlang man 줄은 `man1=man/man1`(17), elixir는 `man1=man`. erlang의 man3 · 4 · 6 · 7(589)은 링크하지 않는다 — `erl -man`이 `<ROOT>/man`을
   읽는다(확인 5, `string.3`의 이름 충돌). 선택 키는 다섯이 된다(HANDOFF의 한도 — 넘으면 TSV를 옮긴다). TP-M5의 clojure 훅이 손으로 하던 링크는
   그대로 둔다(훅 안의 일이다).
G. 체인: devtools 부팅 2에 더한다(망 없이, 사용자로). 기다리는 글자는 계산된 값이다(TP-M4 확인한 것 9).
   1. erlang: `erl -noshell -eval`(OTP 판 · JIT · crypto), `erlc` 모듈 + 실행, `escript`
   2. elixir: `elixir -e`(판 · 계산), `iex`에 한 줄, 경고 `latin1`이 없다
   3. `mix new` → `mix test`를 세 번(위험 1 — JIT의 Illegal instruction이 한 번이라도 나오면 빨강)
   4. gleam: `gleam new` → `gleam run` · `gleam test`(빈 캐시에서 시작, 끝에 tarball 둘)
   5. man: `erl -man lists`, `man mix`
   상한은 처음 하나에 300초, 잰 뒤 세 배(60초 아래로는 안 내린다). 체인을 가를지는 lane-0의 합으로 본다(TP-M5 plan 확인한 것 6).

## 할 일

1. 매니페스트: lang-beam에 erlang · erlang-man · elixir · gleam · gleam-seed. `devlayer/hex/gleam-seed.lock`, 시드 `manifest.toml`.
2. `devlayer/manifest.sh` · `build.sh`: 종류 `hex`(결정 B), 선택 키 `man1=`(결정 F), 시드 `manifest.toml`과 잠금 파일의 대조(결정 D).
3. 훅 `otp-install.sh`(결정 C) · `gleam.sh`(결정 D).
4. lang-beam을 잇는 자리: `Makefile`의 `DEV_LAYERS`, `devtools/check.sh`의 빌드 줄 · `LAYERS` · lowerdir · 묶음 수(여섯, 부팅 3은 다섯), `rg -n 'lang-script'`로 한 번 더.
5. `make dev-layers` — 숫자: lang-beam의 풀린 크기 · zstd, NEEDED(libtinfo · libcrypto가 initrd에서 풀리는지).
6. chroot로 결정 G의 덩이를 먼저.
7. 빨강: (a) gleam 런처의 `manifest.toml` 넣기를 막으면 G-4가 `Resolving versions`의 망 오류로 멈춘다. (b) 훅의 `Install`을 빼면 `erl`이 없어 G-1이 멈춘다.
8. 체인 혼자 한 번, 숫자로 상한을 고친다.
9. `make quick`, 루트 게이트. design(결정 1의 `hex` · `man1=`, Milestone), HANDOFF.

## 판정

- `make dev-layers`가 초록이고, lang-beam의 NEEDED · 겹침 · 묶음 사이 검사가 지난다.
- 체인의 부팅 2에서 결정 G의 다섯 덩이가 망 없이 사용자로 돈다. `mix test` 세 번 중 Illegal instruction 0. 할 일 7의 빨강 둘을 봤다.
- 루트 게이트 초록, 잘린 줄 0.

## 비목표

1. rebar3 · Hex 패키지 미러(design 비목표 2). `mix deps.get` · `gleam add`는 망이 있어야 한다. 시드는 gleam이 새 프로젝트 하나를 세우는 데 필요한 둘뿐이다.
2. erlang의 HTML 문서(`otp_doc_html`, 32MB) — design 결정 19는 man과 dasht다.
3. gleam의 JavaScript 대상 실행(node는 lang-script에 있다 — 묶음 사이에 기대지 않는다. 체인은 erlang 대상만 본다).
4. 분산 Erlang(`epmd`, 노드 이름) — 링크하지 않는다(`erl -sname`이 `erts-*/bin/epmd`를 스스로 부른다).

## 위험

1. BEAM JIT과 에뮬레이터. 확인 3의 Illegal instruction은 OrbStack의 qemu-user에서 결정적이지 않게 났다. 체인(시스템 QEMU · TCG · SandyBridge)에서 나면 원인을
   판다 — JIT이 CPUID로 고른 명령을 TCG가 잘못 다루는지, 실기에서도 날 일인지. 우회는 `ERL_FLAGS="+JMsingle true"`(시스템 rc)나 22.04판으로 바꾸기.
   실기(에어 2011)는 사용자 확인으로 남긴다.
2. lang-beam의 libtinfo · libcrypto.so.3. initrd에 없으면 verify가 이름을 대고 멈춘다 — 그때 base에 `debian` 줄로 더한다.
3. 시드 `manifest.toml`과 gleam 판. gleam을 올리면 기본 틀의 요구 범위가 바뀔 수 있다 — 런처는 요구가 같을 때만 넣으므로 어긋나면 넣지 않을 뿐(망이 있어야 한다).
   체인이 그것을 본다(G-4가 망 없이 돈다).
4. ISO는 1.27GB에서 1.35GB 안팎(lang-beam zstd 70MiB 어림). 2GiB 한도까지 여유가 준다(`project_release_0_2.md`의 사용자 결정 대기).
5. 체인 시간이 1분 남짓 늘고 lane-0도 그만큼 는다.

## 확인한 것

1. Hex의 tarball을 따로 받은 sha256(`cee5b6c0…` · `ec31aba7…`)이 `manifest.toml`의 `outer_checksum`과 같다 — 결정 B의 전제. elixir의 `man/`에서 `*.1`은
   넷(`elixir` · `elixirc` · `iex` · `mix`)이고 틀 파일 `*.1.in` · `common`은 걸리지 않는다.
2. `make dev-layers`(lang-beam): 파일 4,961 · 풀면 218MiB · zstd15 84MiB(어림 70). verify `unresolved=0` — libtinfo · libz · libstdc++ · `libcrypto.so.3`가
   initrd에서 풀렸다(위험 2는 안 일어났다). `links=32` — 실행 파일 11(erlang 6 · elixir 4 · gleam 1)과 man1 21(erlang 17 · elixir 4), `dangling=0`. 시드
   `manifest.toml`과 잠금 파일의 대조를 지났다.
3. chroot(OrbStack, 망 없음, 사용자 1000, `LANG=C.UTF-8`): G1 `tp-m6-otp=29-jit-32` · `tp-m6-erlc=42` · `tp-m6-escript=ok`, G2 `tp-m6-ex=1.20.5-42` · `iex`의
   42(latin1 경고 없음), G4 캐시 0 → 2 · `manifest.toml` 넣음 · `Hello from tpg!` · `1 passed`, G5 `erl -man lists` · `man mix` · `man erl`.
4. G3: 새 프로젝트의 첫 `mix test`만 Illegal instruction으로 죽고 2 · 3회차는 지났다 — 조사(확인 3) 때와 같은 자리다. 첫 회차만 프로젝트를 컴파일한다. 해석:
   BEAM JIT은 CPUID로 기능(BMI2 · LZCNT 등)을 묻고 그 명령을 쓴다. OrbStack의 qemu-user가 흉내 내지 못하는 기능을 CPUID에 내놓으면 JIT이 그 명령에서
   SIGILL을 맞는다. 진짜 CPU와 체인의 `-cpu SandyBridge`는 CPUID가 정직하다 — 판정은 체인(위험 1). 체인에서도 첫 회차가 죽으면 진짜 문제로 본다.
5. 빨강(할 일 7): (a) 런처의 `manifest.toml` 넣기를 막으면 `manifest: no`, 망 없는 `gleam run`이 `repo.hex.pm/packages/gleam_stdlib`에서 멈춘다. (b) 훅의
   `Install`을 빼면 체인까지 가지 않고 훅의 검사가 `Install left no bin/erl`로 굽기를 멈춘다(할 일 7(b)의 "G-1이 멈춘다"보다 앞에서 잡힌다). 되돌리자
   stamp가 같아 `cached`.
6. 체인(SandyBridge · 1GiB, 혼자 한 판, 빌드 뒤 625초 — 488초에서): 위험 1은 일어나지 않았다. 새 프로젝트의 첫 `mix test`(컴파일 포함) 7.9초 · 이어서
   6.2 · 6.3초, 셋 다 `2 passed`, 로그에 `Illegal instruction` · `invalid opcode` 없음 — 확인한 것 4의 해석(OrbStack qemu-user의 CPUID)이 맞았다.
   erl 2.9초, elixir 2.9초, gleam run 13.9초. 상한은 그 세 배(60초 아래로는 안 내린다) — 하나짜리는 60초, `mix` 세 판과 gleam 덩이는 90초. 늘어난 137초
   가운데 BEAM 덩이는 50초 남짓이고 나머지는 이 판 전체가 느렸던 몫이다(kotlinc 55 → 69초, go run 98 → 113초).

## 결과

1. `make dev-layers`가 초록(확인한 것 2). lang-beam 84MiB, 묶음 여섯 1,161MiB, `tars-dev.iso` 1,360,758,784바이트 — GitHub release의 파일당 2GiB까지 약 0.7GB.
2. 체인 `devtools`가 초록(확인한 것 6). 부팅 1이 묶음 여섯을 6.4초에 복사, 부팅 2의 lowerdir가 `base lang-beam lang-jvm …`, 결정 G의 다섯 덩이가 망 없이
   사용자로 돈다. 부팅 3(lang-jvm이 깨짐)에서 lang-beam의 erl이 선다. 부팅 4가 옛 묶음 여섯을 지우고 새로.
3. 빨강 둘(확인한 것 5). 위험 1(JIT)은 체인에서 일어나지 않았다(확인한 것 6).
4. `make quick` PASS(72파일).
5. 루트 게이트 두 판. 1회차 32분 15초 30/31 — BT-M2가 `btvirt` general protection fault로 빨갰다. `carryover.md`의 간헐과 같은 서명이고 세 번째다(이번 변경과
   닿지 않는다 — BT-M2는 묶음을 얹지 않는다). 체인만 다시 돌린 판은 초록(3분 38초). 2회차 33분 38초 31/31(prebuild 442초 · lanes 1,472초 — lane-0의
   devtools가 729초), 31회차 모두 `cut log lines A=0 B=0 C=0`. 게이트 안의 BEAM: erl 3.1초, `mix test` 8.0 · 6.5 · 6.3초, gleam run 13.9초.
6. 위험 2(initrd의 libtinfo · libcrypto)는 안 일어났다. 위험 4: ISO 1.27 → 1.36GB. 위험 5: lanes 1,284 → 1,472초(devtools 567 → 729초 — TP-M5보다 이 판의
   기계가 전체로 느렸던 몫이 섞였다, 확인한 것 6).
