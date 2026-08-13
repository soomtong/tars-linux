---
name: project_build_host_arch
description: "빌드 호스트는 arm64이고 게스트 산출물은 전부 x86_64 크로스다 — docker run에 --platform을 붙이지 않는다; x86_64 바이너리의 의존은 ldd가 아니라 readelf; initrd 유저랜드는 컨테이너가 아니라 amd64 sysroot에서 온다; 호스트에서 도는 도구는 호스트 아키텍처로 다시 빌드해야 하고 그 실패는 binfmt 때문에 qemu-user 메시지로 위장해서 온다"
metadata:
  node_type: memory
  type: project
---

2026-08-13 ZM-M3에서 빌드 컨테이너를 `linux/amd64`에서 호스트와 같은
**arm64**로 바꿨다. 게스트(TARS)는 여전히 x86_64다. 즉 이 저장소는 이제
**전부 크로스 빌드**이며, 컨테이너 안에서 x86_64 바이너리가 실행되는 일은
없어야 한다 — 만들어서 initrd/ISO에 담을 뿐이고, 실행은 QEMU 게스트에서만
일어난다.

## 왜 바꿨나

`Dockerfile:1`이 `FROM --platform=linux/amd64`였다. 호스트가 Apple
Silicon이므로 층이 이렇게 쌓여 있었다: gcc·zig·**qemu-system-x86_64
바이너리 자체**가 Rosetta 에뮬레이션을 통과하고, 그 안에서 다시 게스트
x86_64를 TCG로 번역했다. **에뮬레이터를 에뮬레이션하고 있었다.**

전환 효과(같은 머신, `nproc` 10, 2026-08-13 실측):

| 항목 | amd64 컨테이너 | arm64 컨테이너 | 배수 |
|---|---|---|---|
| 커널 clean 빌드 | 9분 55초 | 46.5초 | 12.8× |
| BF 체인 1회(빌드+부팅) | 17분 40초 | 1분 48초 | 9.8× |
| QEMU 부팅만 | 33~34초 | ~4초 | 8.5× |
| 루트 게이트 전체(6회) | (미측정, BF 3회만 53분) | 8분 52초 | — |

부팅이 8.5배 빨라진 것이 TCG가 JIT이라는 사실과 맞는다. 이미지는 1.11GB →
1.3GB(sysroot + 크로스 툴체인).

## 네 가지 규칙

**1. `docker run`/`docker build`에 `--platform`을 붙이지 않는다.** 붙이면
없앤 층이 그대로 돌아온다. 이미지가 정말 arm64인지는 `uname -m`이
`aarch64`인지로 본다.

**2. x86_64 바이너리의 동적 의존은 `ldd`가 아니라 `readelf`로 본다.**
`ldd`는 대상 바이너리를 **실제 동적 로더에 태워서** 답을 얻으므로 arm64
호스트에서는 쓸 수 없다. `readelf`는 파일을 읽기만 한다. 대신 `ldd`가
대신 해주던 두 가지를 직접 해야 한다.

- 인터프리터는 `DT_NEEDED`가 아니라 **`PT_INTERP`**에 있다(`readelf -p .interp`).
- 의존의 의존은 **재귀**로 따라가야 한다.

그리고 `ldd`가 소네임을 절대 경로로 해석해 돌려주기 때문에 가려져 있던
사실 하나: **Zig가 만든 바이너리는 로더를 `DT_NEEDED`에도 적는다**
(`terminal`에 `ld-linux-x86-64.so.2`가 들어 있다. Debian이 만든 `fish`·
`mkdir`에는 없다). `PT_INTERP` 처리와 겹치므로 `NEEDED` 순회에서
`ld-linux*`는 건너뛴다 — 안 그러면 initrd에 로더 사본이 둘 생긴다.

**3. initrd 유저랜드는 컨테이너가 아니라 `$AMD64_SYSROOT`에서 온다.**
`Dockerfile`이 `apt-get download <pkg>:amd64` → `dpkg -x`로
`/usr/local/amd64-sysroot`에 구워두고, `kernel/make_initrd.sh`는 거기서만
복사한다. 이미지 빌드 때 한 번만 네트워크를 쓰는 구조라 게이트(clean 재빌드
6회)가 오프라인·재현 가능하게 유지된다.

대가는 **initrd에 새 바이너리를 넣으려면 `Dockerfile`의 패키지 목록을
고쳐야 한다**는 것이다(`apt-get install` 한 줄로 안 끝난다). `apt-get
download`는 의존을 따라가지 않으므로 목록은 명시적이다. 빠지면
`make_initrd.sh`가 소네임을 찍고 즉시 죽는다 — 조용히 통과하지 않게 일부러
그렇게 만들었다.

sysroot는 `.deb`가 푼 자리라 usrmerge 규칙대로 `/usr/lib/...`이지만,
initrd 안 라이브러리 자리는 `/lib/x86_64-linux-gnu`로 **고정**한다. 옛
`ldd` 방식이 만든 경로가 그것이고, 바꾸면 부팅은 되지만 이전 initrd와
파일 목록 대조가 불가능해진다.

**4. 호스트에서 도는 도구는 호스트 아키텍처로 다시 빌드해야 한다 — 그리고
그 실패는 위장하고 온다.** `boot/limine-binary/limine`(ISO에 부트 섹터를
써넣는 유틸리티)이 옛 amd64 컨테이너가 빌드한 x86_64 실행 파일로 남아
있었고, `make`는 그게 `limine.c`보다 새것이라 다시 만들지 않았다. 그 결과:

```
[qemu]: Could not open '/lib64/ld-linux-x86-64.so.2': No such file or directory
```

**커널이 `ENOEXEC`을 내는 대신 binfmt_misc가 qemu-user로 넘겼고**, 그
qemu-user가 컨테이너에 없는 x86_64 로더를 찾다 죽은 것이다. "아키텍처가
다르다"는 말을 한 번 걸러서 하는 셈이라 알아보기 어렵다. 대응은
`boot/build.sh`의 `make -C "$DIR" -B`(매번 다시 빌드, C 파일 하나라 1초
미만). `devcontainer/sanity/Makefile`도 같은 이유로 `CC`/`LD`를
`x86_64-linux-gnu-` 접두사로 바꿨다.

## 어디는 안 바꿔도 됐나

- **Zig 두 컴포넌트(`init`, `terminal`).** `build.zig`가
  `resolveTargetQuery`로 타깃을 x86_64에 고정해 둬서 호스트가 바뀌어도
  입력이 달라지지 않는다. **손댄 줄이 없다.** design doc이 "M3 전체가
  막힐 수 있는 유일한 지점"으로 지목한 `terminal/src/drm.zig`의
  `@cImport`도 문제가 아니었다 — 그건 glibc 헤더 셋(`fcntl.h`,
  `sys/ioctl.h`, `sys/mman.h`)만 읽고 DRM 구조체는 손으로 선언한다.
  게다가 타깃을 명시하는 순간 Zig에게는 이미 네이티브 빌드가 아니라서,
  그 헤더는 예전에도 Zig 번들에서 왔다.
- **커널 소스와 `.config`.** `ARCH=x86_64`는 그대로 두고
  `CROSS_COMPILE=x86_64-linux-gnu-`만 추가했다. `ARCH`는 어느 `arch/`
  트리를 쓸지 고를 뿐 컴파일러를 고르지 않는다.
- **`objtool`/`relocs`.** arm64로 빌드돼 x86 오브젝트를 읽는 호스트
  도구들이고, `CONFIG_UNWINDER_ORC=y`라 objtool을 많이 쓰는데도 아무 문제가
  없었다. 이게 이 milestone의 유일한 실질 위험이었다.

커널 크로스 컴파일러는 **`gcc-multilib-x86-64-linux-gnu`**여야 한다.
`CONFIG_X86_16BIT=y`라 `arch/x86/boot`의 실모드 코드가 `-m32`/`-m16`으로
빌드되기 때문이다. 이미지를 다시 굽기 전에 확인하는 가장 싼 방법:
`x86_64-linux-gnu-gcc -m32 -E -x c /dev/null`.

**How to apply:** 빌드 환경을 건드릴 때는 먼저 **"이 산출물은 누가
실행하는가"**를 묻는다 — 호스트가 실행하면 arm64로, 게스트가 실행하면
x86_64로 만들어야 한다. `.gitignore` 대상이면서 `clean()`에서도 빠진
디렉터리(`boot/limine-binary`, `terminal/ghostty-src`, `terminal/vendor`,
`terminal/zig-pkg`)는 옛 호스트의 산출물을 품고 살아남을 수 있으므로,
호스트가 바뀌는 작업에서는 그 넷을 먼저 훑는다. 관련:
[[project_gate_chain_composition]], [[project_zig_c_uapi_rule]],
[[project_zig_rewrite_intent]]
