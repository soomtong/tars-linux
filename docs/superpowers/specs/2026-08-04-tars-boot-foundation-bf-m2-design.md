# TARS Boot Foundation — BF-M2 Design

**Date:** 2026-08-04
**Status:** Completed (2026-08-05) — QEMU serial 로그에서 fish 배너 확인,
`kernel/check.sh` PASS

## 배경

[BF-M1](2026-08-03-tars-boot-foundation-bf-m1-design.md)에서 kernel.org
6.18.42 LTS를 `allnoconfig`에서 반복 확장한 `.config`로 빌드하고, init
바이너리가 없어 `Kernel panic - not syncing: No working init found`가
발생하는 지점까지 검증했다. 이 문서는 다음 단계인 **BF-M2 — 직접 만든
init(PID 1)**을 다룬다. 전체 milestone 구조와 배경은
[design doc](2026-08-01-tars-boot-foundation-design.md)을 참고.

## 목표

Rust로 작성한 init 바이너리가 PID 1로 실행되어 `/proc`, `/sys`, `/dev`
(devtmpfs)를 mount한 뒤 fish를 실행해 shell prompt에 도달한다. BF-M1과
동일하게 QEMU `-kernel`/`-initrd` direct boot를 유지한다 (bootloader는
아직 도입하지 않음).

## 비목표

- bootloader(Limine), hybrid ISO — BF-M3
- coreutils(`ls`, `cat` 등) 포함 — exit gate는 "shell prompt 등장"이며,
  실제 명령 실행 가능 여부는 이번 milestone의 범위 밖
- musl 등 정적 링크 — 이번 milestone은 의도적으로 glibc 동적 링크를
  선택해 ELF 인터프리터/동적 링커 로딩 경로를 학습 대상으로 삼는다
  (아래 핵심 설계 결정 1 참고)
- shell 자체 구현 — init만 직접 만들고, shell은 데스크톱 Linux 바이너리를
  재사용한다

## 핵심 설계 결정

### 1. Rust 빌드 전략: std + glibc 동적 링크

`x86_64-unknown-linux-gnu` 타깃으로 표준 라이브러리를 그대로 사용해
동적 링크 바이너리를 만든다. `no_std` + raw syscall이나 musl 정적 링크
대신 이 방식을 택한 이유:

- host가 이미 x86_64 Linux devcontainer이므로 크로스 컴파일 설정이
  필요 없다
- init 자신도 glibc 동적 링크이므로, 커널이 ELF 헤더의 `PT_INTERP`를
  읽어 `/lib64/ld-linux-x86-64.so.2`를 먼저 실행한다는 사실을 init
  바이너리 자체로 확인하게 된다 — "커널이 어디까지 하고 그다음부터는
  내 코드"라는 이번 서브프로젝트의 핵심 목표와 자연스럽게 이어진다
- fish를 그대로 재사용하기로 했으므로(핵심 설계 결정 3), initramfs에
  동적 링커/공유 라이브러리를 담는 작업이 어차피 필요하다 — init까지
  같은 방식으로 통일하면 배울 대상이 늘지 않고 오히려 하나로 줄어든다

### 2. Syscall 호출: `libc` crate (raw FFI)

`nix` 같은 safe wrapper 대신 `libc` crate로 `mount(2)`, `execve(2)`를
`unsafe extern "C"` 시그니처 그대로 호출한다. 인자 순서와 반환값
(`errno`)을 직접 다뤄야 하므로 "이 syscall이 정확히 무엇을 하는지"가
가장 선명하게 드러난다. `nix`의 추상화는 이 학습 목표에는 노이즈다.

### 3. init 동작 순서

```
1. mount("proc",  "/proc", "proc",     0, NULL)
2. mount("sysfs", "/sys",  "sysfs",    0, NULL)
3. mount("devtmpfs", "/dev", "devtmpfs", 0, NULL)
4. open("/dev/console"), setsid(), ioctl(fd, TIOCSCTTY, 0), dup2(fd, 0/1/2)
5. execve("/usr/bin/fish", ["/usr/bin/fish"], envp)
```

각 `mount()` 호출은 반환값을 확인해 실패 시 `errno`를 serial(표준
출력)로 로그만 남기고 계속 진행한다 — 하나의 mount 실패로 나머지
단계까지 막지 않는다. 마지막 `execve()`는 **fork 없이 자기 자신을
대체**한다: init 프로세스(PID 1)가 그대로 fish가 된다. fish가 종료되면
PID 1이 사라지므로 커널이 panic하는데, 이는 이번 milestone에서 의도적으로
막지 않는다 — "PID 1은 죽으면 안 된다"는 경계를 보여주는 결과이며,
exit gate(프롬프트 확인) 이후 QEMU를 강제 종료하므로 실제로 이 경로를
밟을 필요도 없다.

**추가된 단계 4(2026-08-05, Task 5 실측 후 추가):** 처음엔 mount 이후
바로 execve했더니 fish가 `tcgetpgrp failed` 경고 후 `setpgid:
Inappropriate ioctl for device`(ENOTTY)로 job control 설정에 실패해
치명적 신호로 스스로 종료했고, 커널이 `Attempted to kill init!`으로
panic했다. fish 4.0은 내부적으로 멀티스레드를 쓰므로(자동완성/문법
강조용) panic 로그의 `PID`는 개별 스레드 TID였지만, 커널의
`is_global_init()` 판정은 스레드 그룹 ID(PID 1)를 보기 때문에
"init을 죽였다"는 panic으로 이어졌다. 원인은 controlling terminal이
없어서였다 — 일반적인 터미널에서는 로그인 셸/터미널 에뮬레이터가
이를 대신 설정해주지만, PID 1로 직접 실행되는 init은 아무도 대신 해주지
않는다. `/dev/console`을 열어 `TIOCSCTTY` ioctl로 현재 세션의
controlling terminal로 지정하고 표준입출력을 그리로 연결해야 fish의
job control이 정상 동작한다. `setsid()`는 PID 1이 이미 자기 세션의
리더라 실패(`EPERM`)할 수 있지만 무시한다(이미 원하는 상태이므로) —
mount 실패 처리와 동일한 "실패해도 계속 진행" 철학이다.

### 4. Shell: bash 대신 fish, 의존 라이브러리 + terminfo 데이터 복사

**결정 배경(2026-08-04, plan 작성 전 재검토):** 당초 bash를 채택했으나,
devcontainer 안에서 실측한 결과 fish로도 무리 없이 전환 가능하다고
판단해 fish로 변경한다. devcontainer(Debian bookworm) 안에서 `ldd
/usr/bin/fish`와 `ldd /bin/bash`를 비교한 결과:

**버전 갱신(2026-08-05, Task 1 진행 중 재검토):** fish 4.0(2025-02
릴리스)이 C++에서 Rust로 완전히 재작성되면서 curses/terminfo 의존
방식이 바뀌었고(Rust crate로 자체 구현 + xterm-256color fallback 내장),
musl 정적 링크 빌드도 배포된다는 사실을 확인해 devcontainer 베이스를
`debian:bookworm-slim`에서 `debian:trixie-slim`으로 바꾸고 apt로 fish
4.0.2를 설치하기로 했다(핵심 설계 결정 5 참고). **아래 `ldd` 비교표와
terminfo 결론은 bookworm/fish 3.6.0 기준 실측 결과이며, trixie/fish
4.0.2로 전환한 뒤에는 그대로 믿지 않고 Task 4에서 동일한 실험(`ldd`
비교, `/usr/lib/terminfo` 제거 후 `env -i fish -i` 실행)을 다시 수행해
확인한다** — fish 공식 블로그의 "terminfo fallback 내장" 서술만으로
`/usr/lib/terminfo/l/linux` 포함 여부를 결정하지 않는다.

| | bash | fish 3.6.0 (bookworm) |
|---|---|---|
| 의존 `.so` | `libtinfo.so.6`, `libc.so.6`, `ld-linux-x86-64.so.2` (3개) | 위 3개 + `libpcre2-32.so.0`, `libstdc++.so.6`, `libm.so.6`, `libgcc_s.so.1` (7개) |

**fish 4.0.2(trixie) 재실측 결과:** `kernel/make_initrd.sh` Step 3
실행으로 실제 initramfs에 담긴 `ldd usr/bin/fish` 결과를 확인했다 —
`libgcc_s.so.1`, `libc.so.6`, `libpcre2-8.so.0`, `libpcre2-32.so.0`,
`libm.so.6`, `/lib64/ld-linux-x86-64.so.2` (6개). fish 3.6.0과 비교하면
**`libstdc++.so.6`가 사라지고**(C++→Rust 재작성이 실제 링크 의존성에
반영됨) `libpcre2-8.so.0`이 새로 추가됐다(PCRE2의 8-bit 변형, 32-bit
변형과 별개로 필요해짐).

fish-common 패키지의 `.fish` completion 스크립트(수백 개)와
`/etc/fish/config.fish`는 없어도 fish 실행 자체는 정상 동작함을
`env -i HOME=/nonexistent fish -i` 실험으로 확인했다 — initramfs에
담지 않는다.

**terminfo 데이터 파일이라는 새 의존성 카테고리:** `ldd`는 동적
라이브러리 링크만 추적하고, 런타임에 파일 경로로 조회하는 데이터는
잡지 못한다. `/usr/lib/terminfo` 디렉터리를 치운 상태에서 재실행한
결과, fish는 `Could not set up terminal` 경고를 여러 줄 출력했다(치명적
에러는 아니고 명령 실행은 계속됨). bash는 terminfo가 없어도 조용히
정상 동작한다. 이는 fish의 라인 에디터가 자체적으로 terminfo lookup을
하기 때문이며, "링킹 의존성(ldd로 보이는 것)"과 "런타임 데이터 파일
의존성(ldd로 안 보이는 것)"이 서로 다른 카테고리라는 것을 보여주는
지점이다(bookworm/fish 3.6.0 기준). 이 프로젝트는 경고 로그 없이
깨끗하게 동작하는 쪽을 택해 `/usr/lib/terminfo/l/linux` 파일 하나만
initramfs에 포함하기로 했었다(전체 terminfo 데이터베이스가 아니라
`TERM=linux`용 엔트리 하나로 충분).

**재실측 결과(2026-08-05, trixie/fish 4.0.2, Task 4 진행 중):** 위에서
예고한 대로 다시 실측했다. trixie 이미지에는 terminfo 데이터가
`/usr/lib/terminfo/l/linux`가 아니라 `/usr/share/terminfo/l/linux`에
있다(ncurses-base 6.5, 경로 자체가 bookworm과 다름). 하지만 더 중요한
결과는 따로 있다 — `env -i HOME=/nonexistent fish -c 'exit'`를 terminfo
파일이 전혀 없는 상태(trixie-slim 이미지에는 애초에 `/usr/lib/terminfo`
경로가 존재하지 않음)에서 실행해도 **경고 없이 exit code 0으로 조용히
종료**됐다. fish 공식 블로그가 서술한 "Rust crate로 terminfo를 자체
처리하고 xterm-256color를 내장 fallback으로 쓴다"는 내용이 실측으로
확인된 것이다. 따라서 **terminfo 파일을 initramfs에 포함하지 않기로
결론을 바꾼다** — fish 3.6.0(C++/ncurses)에서만 있던 의존성이며 fish
4.0(Rust)에는 해당하지 않는다.

**세 번째 의존성 카테고리: `/usr/share/fish`(fish 자신의 런타임
에셋)(2026-08-05, Task 5 실측):** initramfs에 init/fish/라이브러리만
담아 부팅했더니 `Fish cannot find its asset files in '/usr/share/fish'`
에러로 fish가 즉시 종료됐다. `ldd`(링킹)나 terminfo(외부 데이터 조회)와
또 다른 카테고리다 — fish의 내장 함수 상당수가 컴파일된 코드가 아니라
`/usr/share/fish/functions/*.fish` 형태의 fish 스크립트로 구현돼 있어서
시작 시점에 필수로 읽어야 한다. `fish-common`의 completion 스크립트가
불필요하다는 기존 결론과는 별개의 대상이다(그 실험은 devcontainer
안에서 `/usr/share/fish` 자체는 그대로 있는 상태로 진행됐다). 전체
`/usr/share/fish`는 11M/1439개 파일로 커서, 셸 프롬프트 도달에 필요한
최소 집합만 추렸다: `functions/`(내장 함수 스크립트), `config.fish`
(기본 설정), `__fish_build_paths.fish`(fish 자신의 함수 검색 경로
부트스트랩). `completions/`, `vendor_completions.d/`, `groff/`, `man/`,
`tools/`, `vendor_conf.d/`, `vendor_functions.d/`는 제외했다 — 이
최소 집합만으로 asset 에러 없이 부팅에 성공했다.

```text
/init                          # Rust init 바이너리, 커널이 PID 1로 실행
/usr/bin/fish                  # devcontainer의 fish 바이너리 그대로 복사
/lib64/ld-linux-x86-64.so.2    # 동적 링커
/lib/x86_64-linux-gnu/*.so*    # ldd init && ldd fish 결과의 합집합
/usr/share/fish/functions/     # fish 내장 함수(스크립트로 구현됨)
/usr/share/fish/config.fish    # 기본 설정
/usr/share/fish/__fish_build_paths.fish  # 함수 검색 경로 부트스트랩
```

`kernel/make_initrd.sh`를 확장해 `ldd`로 `/init`과 `/usr/bin/fish` 각각의
의존 라이브러리를 추적하고, devcontainer 안의 실제 파일을 그대로
cpio에 담는다. terminfo는 포함하지 않는다(위 재실측 결과 참고).
`/usr/share/fish`는 위 최소 집합만 포함한다. coreutils는 포함하지
않는다(비목표 참고) — 실제로 fish 초기화 과정에서 `mkdir`/`uname`
호출이 실패하는 게 로그로 확인됐지만, fish가 이를 치명적으로 보지
않고 프롬프트까지 도달하므로 exit gate에는 영향이 없다.

### 5. devcontainer에 Rust 툴체인 추가: rustup, 베이스 이미지를 trixie로 변경

`devcontainer/Dockerfile`에 rustup 설치 스텝을 추가해 stable
`x86_64-unknown-linux-gnu` 타깃을 설치한다. Debian bookworm의 apt
`rustc`/`cargo`(1.63 계열, 구버전)는 최신 crate와 호환성 문제가 생길
수 있어 배제한다. 같은 Dockerfile에 `fish` apt 패키지도 추가한다 —
`--no-install-recommends`로 설치해도 fish-common이 python3/man-db 등을
끌어오지만, 이는 initramfs에 담을 대상이 아니라 devcontainer 안에서
`/usr/bin/fish`와 그 라이브러리를 추출해 오기 위한 소스일 뿐이다.

**베이스 이미지 변경(2026-08-05):** bookworm의 apt는 fish 3.6.0까지만
제공한다. fish 4.0(Rust 재작성) 이상을 쓰기 위해 devcontainer 베이스를
`debian:bookworm-slim`에서 `debian:trixie-slim`(Debian 13, 2025-08
릴리스, apt로 fish 4.0.2 제공)으로 바꾼다. 커널 빌드 도구 체인
(`build-essential`, `gcc-multilib` 등)은 trixie에서도 동일한 패키지명으로
제공되므로 나머지 apt 목록은 그대로 유지한다.

### 6. 검증: timeout 강제 종료 + 배너 grep

fish는 interactive 입력을 기다리므로 자연 종료되지 않는다. BF-M0/BF-M1과
동일하게 `timeout N초`로 QEMU를 강제 종료한 뒤, 로그에서 판정 문자열을
grep해 PASS/FAIL을 판정한다. fish의 기본 프롬프트는 ANSI color escape
sequence가 섞여 있어(`env -i` 실험으로 확인) 프롬프트 자체보다는 fish가
시작될 때 항상 출력하는 배너 문구 `Welcome to fish, the friendly
interactive shell`을 grep 대상으로 삼는다 — 색상 코드에 의존하지 않는
안정적인 판정 기준이다.

## 저장소 구조 변경

```text
init/
├── Cargo.toml       # libc crate 의존성
└── src/
    └── main.rs       # PID 1 진입점: mount 3회 + execve
kernel/
├── make_initrd.sh    # fish + ldd 의존 라이브러리까지 담도록 확장(terminfo는 불필요)
└── check.sh           # exit gate 메시지를 fish 배너 문자열로 변경
```

`devcontainer/Dockerfile`에 rustup 설치 스텝과 `fish` apt 패키지를
추가한다.

## QEMU 부팅 검증

BF-M1의 `check.sh` 패턴(빌드 → 실행 → grep → PASS/FAIL)을 그대로
재사용한다.

```bash
qemu-system-x86_64 \
  -kernel kernel/build/arch/x86/boot/bzImage \
  -initrd kernel/initrd.cpio \
  -append "console=ttyS0" \
  -serial stdio -display none -no-reboot
```

Exit gate는 serial 로그에서 mount 결과 로그 이후 fish 배너 문자열
(`Welcome to fish, the friendly interactive shell`)이 나타나는 것을
확인하는 것이다.

## 협업 방식

[BF-M0와 동일](2026-08-01-tars-boot-foundation-design.md#협업-방식): 설명
먼저 → 사용자가 직접 실행 → 결과 상세 설명. 승인된 내용의 git commit은
Claude Code가 대신 수행.

## 검증 방법

QEMU serial 출력에서 mount 로그 뒤 fish 배너 문자열 확인. BF-M0/BF-M1의
`check.sh`와 동일한 검증 스타일을 유지한다.
