# TARS Zig Migration — Design

**Date:** 2026-08-13
**Status:** **완료 (2026-08-13). ZM-M1·M2·M3 전부 끝났다.**

## 배경

Terminal Foundation(TF-M0~M4, `2026-08-08-tars-terminal-foundation-design.md`,
2026-08-13 완료)까지 끝난 뒤 다음 서브프로젝트 후보는 둘이었다.

1. **설정 영속화 + 부팅 셸 선택** (`docs/decisions/
   project_boot_shell_selection.md`) — virtio-blk 디스크와 파일시스템을
   붙여 재부팅을 넘어 살아남는 설정 저장소를 만들고, 첫 사용 사례로 부팅
   셸 선택을 얹는다.
2. **Rust 컴포넌트를 Zig로 재작성** (`docs/decisions/
   project_zig_rewrite_intent.md`).

2번을 먼저 하기로 했다. 이유는 순서 의존성이다. 1번은 블록 장치 대기,
mount, 설정 파일 파싱을 전부 `init` 안에 넣게 되는데, `init`은 결국 Zig로
옮길 코드다. `project_zig_rewrite_intent`에 이미 "`init/`에 Rust 코드를
크게 늘리는 작업이 생기면 그 시점에 지금 Zig로 옮기는 게 나은지 먼저
짚어준다 — 버릴 코드에 시간을 쓰지 않기 위해서"라고 적어둔 그 시점이다.

또 하나, 지금은 재작성에 안전망이 있다. 루트 `check.sh`가 BF·TF 두 체인을
각 3회 돌려 `TARS check PASS`로 끝난다. 동작을 바꾸지 않는 재작성은 게이트가
가장 잘 잡아주는 종류의 작업이다.

남은 Rust는 세 곳뿐이다 — `init/src/main.rs` 118줄, 은퇴한 `kms/src/main.rs`
325줄, `devcontainer/Dockerfile:25-31`의 rustup 설치 27줄.

### 설계 도중 드러난 두 번째 동기: 빌드 호스트의 이중 에뮬레이션

설계 대화에서 사용자가 "Zig로 전환하면 macOS → Docker → QEMU 다중 가상화
문제가 풀리느냐"고 물었고, 확인해 보니 예상보다 심각한 상태였다.

호스트는 `arm64`(Apple Silicon)인데 `devcontainer/Dockerfile:1`이
`FROM --platform=linux/amd64`다. 그래서 층이 이렇게 쌓인다.

```text
macOS (arm64)
 └─ Docker의 Linux VM (arm64 네이티브)
     └─ x86_64 에뮬레이션 (Rosetta 또는 qemu-user)
         └─ gcc / cargo / zig / qemu-system-x86_64   ← 컴파일러도 에뮬레이션
             └─ QEMU가 x86_64 게스트를 TCG로 에뮬레이션  ← TARS
```

**에뮬레이터를 에뮬레이션하고 있다.** `qemu-system-x86_64` 바이너리 자체가
x86_64라 Rosetta를 통과한 다음, 그 안에서 게스트 x86_64를 다시 TCG로 돈다.
BF 부팅 34초와 커널 컴파일 시간의 상당 부분이 여기서 나온다.

Zig 전환은 이 문제의 **필요조건 하나**를 거의 공짜로 준다. Zig는 크로스
컴파일이 기본값이고 libc를 번들로 들고 다녀서, arm64에서 네이티브 속도로
x86_64 리눅스 바이너리를 뽑는다. Rust도 크로스 컴파일은 되지만 C를 링크하는
순간 크로스 sysroot를 직접 챙겨야 해서 훨씬 번거롭다.

다만 **충분조건은 아니다.** Docker는 이 저장소에서 컴파일러 노릇만 하는 게
아니라 커널 빌드 호스트이자 initrd에 들어갈 x86_64 리눅스 유저랜드(`fish`,
coreutils, glibc `.so`)의 공급원이다. 그래서 목표는 Docker를 없애는 것이
아니라 **컨테이너를 arm64 네이티브로 바꾸고 안에서 크로스 컴파일하는 것**이다.
에뮬레이션 층이 두 겹에서 한 겹으로 준다. 게스트 x86_64는 Apple Silicon에서
어차피 가속이 불가능하므로 TCG로 남는다.

이 작업을 ZM-M3으로 이 서브프로젝트 안에 넣는다. Rust가 사라진 직후가
`Dockerfile`을 건드리기 가장 좋은 순간이기 때문이다.

## 목표

저장소에서 Rust를 완전히 제거하고, 그 결과로 열리는 빌드 호스트
arm64 네이티브화까지 간다. 완료 상태의 정의는 다음 셋이 동시에 성립하는
것이다.

1. 아래 검색이 아무것도 찾지 못한다. **ZM-M2에서 실제로 쓴 형태로
   정정했다** — 원래 적어둔 `--glob '!docs/**'` 하나로는 `HANDOFF.md`와
   `MEMORY.md`(둘 다 기록이라 Rust 언급이 남아야 한다), vendor된 ghostty
   소스가 걸린다.

   ```bash
   rg -n 'cargo|rustup' \
     --glob '!docs/**' --glob '!terminal/ghostty-src/**' \
     --glob '!HANDOFF.md' --glob '!MEMORY.md' .
   ```
2. `devcontainer/Dockerfile`에 rustup이 없고 `--platform=linux/amd64`도 없다.
3. 그 상태에서 `./check.sh`가 `TARS check PASS`로 끝난다.

## 비목표

- **동작 변경.** ZM-M1·M2는 관측 가능한 동작을 한 줄도 바꾸지 않는다.
  이 서브프로젝트의 안전망 전체가 "결과가 이전과 같다"에 달려 있어서,
  재작성 실수와 새 기능을 구분할 수 없게 되면 게이트가 무의미해진다.
- **PID 1 기능 보강.** 지금 `init`은 fork한 `/terminal`이 죽어도 `waitpid`로
  거두지 않고(좀비), fish가 종료되면 PID 1이 `main`을 빠져나가 커널 패닉이
  난다. 고칠 가치는 있지만 위 이유로 이번에 섞지 않는다. 별도 작업으로 남긴다.
- **은퇴한 DF 게이트 부활.** `project_gate_chain_composition`에 기록된
  "무의미해진 게이트는 되살리지 않고 은퇴" 원칙을 따른다.
- **설정 영속화 / 부팅 셸 선택.** 이 서브프로젝트가 끝난 뒤의 다음 후보다.
- **커널을 Zig로 컴파일.** 지원되는 경로가 아니다. 커널은 계속 GNU
  툴체인으로 빌드하되, ZM-M3에서 크로스 컴파일로 바꾼다.

## 핵심 설계 결정

### 1. `init`은 libc를 링크하지 않는다

세 갈래가 있었다. **(A)** `link_libc = true` + `@cImport(<sys/mount.h>)`로
현재 Rust 코드와 1:1 대응. TF-M3에서 검증된 패턴이다. **(B)**
`std.os.linux`의 raw syscall 직접 호출, libc 링크 없음. **(C)** libc는
링크하되 `std.c` 사용.

**B를 고른다.** `init`이 하는 일은 `mount`, `fork`, `execve`, `open`,
`setsid`, `ioctl`, `dup2` — 전부 시스템 콜 그 자체이고 libc가 해주는 것은
얇은 래퍼뿐이다. 이 저장소에서 libc 없이 성립하는 유일한 컴포넌트다.
얻는 것이 셋이다.

1. **fortify 제약이 원천적으로 사라진다.** `project_zig_c_uapi_rule`에
   기록된 대로 Debug가 아닌 최적화 모드에서 Zig가 붙이는
   `-D_FORTIFY_SOURCE`가 glibc `bits/fcntl2.h`를 활성화시켜 `@cImport`를
   깨뜨린다. glibc 헤더를 읽지 않으면 그 문제가 존재하지 않는다. `init`은
   `ReleaseSafe`로도 빌드할 수 있게 된다.
2. **initrd에서 `make_initrd.sh:45`의 `copy_lib_deps "$WORKDIR/init"`를
   지울 수 있다.** PID 1이 정적 바이너리가 되면 라이브러리 로딩 실패로
   부팅이 죽는 경로 자체가 없어진다.
3. **학습 목표에 맞는다.** `mount(2)`가 실패하면 libc는 `-1`을 주고 `errno`를
   세팅하지만 커널은 `-EINVAL` 같은 음수를 그대로 반환한다. libc를 걷어내면
   그 변환이 어디서 일어나는지를 코드로 직접 보게 된다.

대가는 하나다. `println!`을 못 쓴다. `std.debug.print`는 libc 없이도
동작하지만 stderr로 나간다 — `/dev/console`이 stdout·stderr 양쪽에 붙어
있으므로 시리얼 로그에는 그대로 찍힌다.

### 2. `kms/`는 Zig로 옮기지 않고 삭제한다

`kms`가 하던 일(DRM 모드 설정 → dumb buffer → framebuffer)은 이미
`terminal/src/drm.zig`가 Zig로 다시 구현해 매 게이트마다 실제로 돌고 있다.
로그 접두사까지 `kms:`를 그대로 쓴다. Zig로 옮기면 사실상 중복 코드가 되고,
`display/check.sh`를 되살리는 것은 위 비목표에 적은 원칙에 어긋난다.

`display/check.sh:16-17`에 "파일과 `kms/` 크레이트를 남겨두는 것은 Rust로
쓴 DRM 참조 구현으로서의 가치 때문이다"라고 적혀 있었다. 이번에 그 결정을
뒤집는다 — "Rust를 전부 Zig로"라는 목표와 정면으로 부딪히고, 참고 구현으로서의
가치는 git 히스토리에 그대로 남는다. 실행되지 않는 코드가 작업 트리에 살아
있으면 다음 사람에게 혼란만 준다.

### 3. Milestone 순서: 코드 → 툴체인 → 빌드 호스트

ZM-M1(코드)과 ZM-M2(툴체인 제거)는 게이트가 "동작 동일"을 지켜준다.
ZM-M3(빌드 호스트)는 성격이 다르다 — 빌드 환경 전체가 바뀌므로 실패 모드가
넓고, 게이트가 깨졌을 때 원인 후보가 많다. 그래서 마지막에 둔다.

ZM-M1에서 Rust 소스를 **지우지 않는** 것도 같은 이유다. 게이트가 깨졌을 때
되돌아갈 곳을 한 milestone 동안 남겨둔다.

## Milestone 구성

### ZM-M1 — `init`을 Zig로

`init/build.zig`와 `init/src/main.zig`를 새로 만든다. libc 링크 없이
`std.os.linux` raw syscall을 직접 호출한다. Rust 소스는 남긴다.

함께 바뀌는 곳:

- `kernel/make_initrd.sh:20` — 복사 경로가 `init/target/release/tars-init`에서
  `init/zig-out/bin/init`으로
- `kernel/make_initrd.sh:45` — `copy_lib_deps "$WORKDIR/init"` 제거
- `boot/check.sh:7`, `terminal/check.sh:14` — `cargo build --release` →
  `zig build`
- `check.sh:18` — clean 목록에서 `init/target` → `init/zig-out
  init/.zig-cache`
- `.gitignore` — `init/zig-out/`, `init/.zig-cache/` 추가. 이 저장소는
  빌드 산출물을 실수로 커밋한 전력이 있으므로(`CLAUDE.md`의 "Commit 전
  git status 확인") 첫 `zig build` 전에 먼저 넣는다.

`init`은 외부 패키지 의존이 없으므로 `init/.zig-cache`를 지운 clean 빌드가
네트워크 없이 완주한다. `terminal/zig-pkg`처럼 보존해야 하는 디렉터리가
새로 생기지 않는다(`project_gate_chain_composition` 참고).

**완료 조건:** BF 3/3 + TF 3/3, **그리고** 시리얼 로그의 `tars-init:`
마운트 네 줄(proc/sysfs/devtmpfs/devpts)이 전부 `mounted`인지 육안 확인.
아래 "검증 방법"에 적은 이유로 게이트 PASS만으로는 부족하다.

### ZM-M2 — Rust 흔적 제거 (완료, 2026-08-13)

`init/Cargo.toml`·`Cargo.lock`·`src/main.rs`·`target/`와 `kms/` 전체를
삭제한다. `display/`에는 `check.sh` 하나뿐이므로 디렉터리째 사라진다.
`.gitignore`에서 `init/target/`·`kms/target/` 두 줄도 뺀다.
`devcontainer/Dockerfile:25-31`의 rustup 설치를 제거하고 이미지를
재빌드한다.

**범위에 `kernel/check.sh`가 추가됐다.** 이 design을 쓸 때 놓친 파일인데
7번째 줄이 `cargo build --release`라 완료 조건 1번이 성립하지 않았다.
고치는 대신 **지웠다.** 이미 깨져 있었고(`terminal/prepare.sh`를 부르지
않아 clean 트리에서 `make_initrd.sh`가 terminal 바이너리를 못 찾는다),
살려도 TF 체인이 더 강하게 검증하는 것을 중복해서 볼 뿐이다.
[[project_gate_chain_composition]]의 "낡은 게이트는 되살리지 않고 은퇴"를
적용했다. `kernel/check-virtio-gpu.sh`는 남겼다 — 아무것도 빌드하지 않고
Rust와 무관한 수동 도구다.

**완료 조건:** Rust 툴체인이 없는 이미지 안에서 BF 3/3 + TF 3/3.

**결과:** `TARS check PASS`. 이미지 1.75GB → 1.11GB(0.64GB 감소).
initrd는 14MB로 변화 없음. 커밋 `94f3213`(plan), `0ec3c13`(소스·게이트
삭제), `ccfbd04`(Dockerfile).

### ZM-M3 — 빌드 호스트를 arm64 네이티브로 (완료, 2026-08-13)

`Dockerfile:1`의 `--platform=linux/amd64`를 제거한다. 따라오는 변경이 셋이다.

- **Zig 설치 URL** (`Dockerfile:36-37`)이 `zig-x86_64-linux`로 하드코딩돼
  있어 `aarch64`로 바꿔야 한다.
- **커널 크로스 빌드** — `gcc-x86-64-linux-gnu`를 설치하고 `kernel/build.sh:23`의
  `MAKE_ARGS`에 `CROSS_COMPILE=x86_64-linux-gnu-`를 추가한다.
- **initrd 유저랜드** — 가장 까다로운 부분이다. multiarch로 `fish:amd64`를
  그냥 설치하면 arm64 fish와 파일 경로가 충돌한다. 그래서
  `apt-get download fish:amd64` → `dpkg -x`로 별도 디렉터리에 풀어 거기서
  복사한다. `make_initrd.sh:35-43`의 소스 경로가 전부 바뀐다. 또
  `copy_lib_deps`가 쓰는 `ldd`는 x86_64 바이너리에 쓸 수 없으므로
  `readelf -d`로 바꾸거나 필요한 `.so`를 명시 목록으로 관리해야 한다.

`terminal/build.zig:4-9`는 손대지 않아도 된다 — 이미 `resolveTargetQuery`로
타깃을 `x86_64-linux-gnu`에 명시적으로 고정해 두었고 호스트 기본값을 쓰지
않는다.

**완료 조건:** BF 3/3 + TF 3/3, 그리고 **전환 전후 소요 시간 기록.** 이
milestone의 목적 자체가 속도라서 숫자가 남지 않으면 완료를 판정할 수 없다.

#### 실행 결과

`TARS check PASS`(BF 3/3, TF 3/3, 전체 8분 52초). `tars-init: starting as
PID 1` 6건, `init mounted all four filesystems` 6건, `tars-init: failed`
0건. 상세는 [[project_build_host_arch]].

| 항목 | 전 | 후 | 배수 |
|---|---|---|---|
| 커널 clean 빌드 | 9분 55초 | 46.5초 | 12.8× |
| Zig 두 컴포넌트 | ~6분(추정) | 49.3초 | ~7× |
| BF 체인 1회 | 17분 40초 | 1분 48초 | 9.8× |
| QEMU 부팅만 | 33~34초 | ~4초 | 8.5× |

이미지 1.11GB → 1.3GB. `nproc`은 양쪽 10으로 동일.

#### 위 서술에서 틀렸던 것과 예상 못 한 것

- **커널 크로스 컴파일러는 `gcc-x86-64-linux-gnu`로 부족하다.**
  `CONFIG_X86_16BIT=y`라 `arch/x86/boot`의 실모드 코드가 `-m32`/`-m16`으로
  빌드되므로 **`gcc-multilib-x86-64-linux-gnu`**를 써야 한다(trixie, arm64
  설치 가능). 지금 `Dockerfile`에 `gcc-multilib`이 있던 이유가 그것이었다.
- **유저랜드 조달은 `apt-get download`+`dpkg -x`가 맞았지만 시점이 다르다.**
  `make_initrd.sh`가 아니라 **`Dockerfile`이** 이미지 빌드 때 한 번
  `/usr/local/amd64-sysroot`에 구워둔다. 게이트는 clean 재빌드를 6회 하므로
  initrd 생성이 네트워크에 나가면 안 된다.
- **`ldd`→`readelf` 전환은 두 가지를 손으로 해야 한다** — 인터프리터는
  `PT_INTERP`에 따로 있고, 의존의 의존은 재귀로 따라가야 한다. 그리고
  **Zig 산출물은 로더를 `DT_NEEDED`에도 적는다**(Debian 바이너리는 안
  그런다). 이걸 그대로 처리하면 initrd에 로더 사본이 둘 생긴다.
- **`boot/limine-binary/limine`을 예상하지 못했다.** ISO에 부트 섹터를
  써넣는 **호스트용** 도구인데 옛 amd64 컨테이너의 산출물이 남아 있었고,
  `make`가 소스보다 새것이라 다시 만들지 않아 BF가 죽었다. 게다가
  binfmt_misc가 `ENOEXEC` 대신 qemu-user로 넘겨 에러가 위장돼서 왔다.
  `boot/build.sh`를 `make -C "$DIR" -B`로 고쳤다.
- **`devcontainer/sanity`가 범위에 추가됐다.** `gcc -m32`를 쓰므로 arm64에서
  깨진다. 지우지 않고 `CC`/`LD`를 크로스 접두사로 고쳤다.

각 milestone이 끝난 뒤에야 다음 milestone의 상세 plan을 작성한다 — 전체를
한 번에 미리 설계하지 않는다(Boot/Display/Terminal Foundation과 동일).

## 저장소 구조 (변경분)

```text
tars-linux/
├── init/              # Rust 크레이트 → Zig 프로젝트 (ZM-M1 신설, M2에 Rust 삭제)
├── kms/               # 삭제 (ZM-M2)
├── display/           # check.sh 하나뿐 → 디렉터리째 삭제 (ZM-M2)
└── devcontainer/      # rustup 제거(M2), arm64 네이티브 전환(M3)
```

## 검증 방법

기존 게이트를 그대로 쓴다. 루트 `check.sh`가 BF·TF 두 체인을 각 3회 연속
clean 재빌드로 돌리고 `TARS check PASS`로 끝난다.

**ZM-M1 시작 시점의 게이트에는 이번 작업에 특유한 사각지대가 있었다.**
게이트가 `tars-init:` 로그를 **하나도 grep하지 않았다** — `boot/check.sh`는
fish 배너를, `terminal/check.sh`는 `terminal: screen>`을 본다. 즉 `init`이
`/proc` 마운트에 실패해도 부팅만 되면 통과할 수 있었다. PID 1을 통째로 다시
쓰는 작업에서 이건 실제 위험이라, ZM-M1에서 두 체인에 `tars-init: mounted ...`
네 줄 검사를 넣어 막았다. 이제 `./check.sh` 한 바퀴가 6회 검증한다.
경위는 [[project_gate_chain_composition]]의 "게이트는 자기가 안 보는 것을
통과시킨다" 절.

## 리스크

- **~~`environ`~~ (ZM-M1에서 해소)** — `pub fn main(init:
  std.process.Init.Minimal)`의 `init.environ.block.slice.ptr`이 커널이 PID 1
  스택에 올려준 envp다. libc 없는 시작 경로(`std/start.zig:508-519`)가
  스택에서 직접 읽어 채운다. 실행 결과 fish가 정상 기동하고 terminal이
  프롬프트를 파싱했으므로 환경 변수 문제는 없었다.
- **~~ioctl 상수~~ (ZM-M1에서 해소)** — `std.os.linux.T.IOCSCTTY`가 이미
  존재한다(x86_64에서 `0x540e`, `std/os/linux.zig:5241`). 손으로 선언하지
  않았다. 상세는 [[project_zig_c_uapi_rule]]의 "세 번째 길" 절.
- **~~게이트의 init 사각지대~~ (ZM-M1에서 해소)** — 아래 "검증 방법"에 적은
  사각지대를 사람 눈이 아니라 스크립트로 막았다. 두 체인 모두
  `tars-init: mounted ...` 네 줄을 검사한다.
- **~~`terminal/src/drm.zig:3`의 `@cImport`~~ (ZM-M3: 처음부터 오해였다)** —
  "Zig 번들 헤더에 DRM UAPI가 있는지가 M3 전체를 막을 수 있다"고 적었는데,
  이 `@cImport`는 **DRM UAPI를 읽지 않는다.** `fcntl.h`·`sys/ioctl.h`·
  `sys/mman.h` 셋뿐이고 전부 glibc 헤더이며, DRM 구조체는 `drm.zig:9-40`에
  `extern struct`로 손수 선언돼 있다(ioctl 번호도 직접 계산). 게다가
  `build.zig`가 `resolveTargetQuery`로 타깃을 명시하는 순간 Zig에게 이건
  이미 네이티브 빌드가 아니라, 그 헤더는 예전에도 Zig 번들에서 왔다. M3에서
  `terminal`은 **한 줄도 고치지 않고** 크로스 빌드됐다. 리스크를 적을 때
  파일을 열어보지 않은 것이 원인이다.
- **objtool/relocs (ZM-M3에서 해소)** — 실제 위험은 이쪽이었다. arm64로
  빌드된 호스트 도구가 x86 오브젝트를 읽어야 하고 `CONFIG_UNWINDER_ORC=y`라
  objtool을 많이 쓰는데, 아무 문제 없이 통과했다.
- **`make_initrd.sh`의 복사 목록** — DF-M3와 TF-M4에서 이 목록이 바뀌면서
  다른 체인이 조용히 깨진 사고가 두 번 있었다. M1과 M3가 둘 다 이 파일을
  건드리므로, 변경 직후 반드시 두 체인을 모두 돌린다.
