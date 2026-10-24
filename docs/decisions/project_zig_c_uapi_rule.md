---
name: project_zig_c_uapi_rule
description: "Zig에서 커널을 부를 때의 규칙. 시스템 콜만 쓰면 libc를 링크하지 않고 std.os.linux로 · C 번역은 구조체는 되고 ioctl 매크로는 안 된다 · 최적화 모드에서 glibc fortify가 번역을 깨고 파일마다 에러 문구가 달라 같은 원인으로 안 보인다 · translate-c 패키지는 -D_FORTIFY_SOURCE=2를 맨 뒤에 붙여 명령줄로 못 끄고 stub 헤더의 #undef로 c_poll 하나만 끈다"
metadata:
  node_type: memory
  type: project
---

TF-M3(2026-08-11)이 세우고 ZM-M1 · GL-M3 · ZU-M1이 더했다. 번역은
`terminal/build.zig`의 `translateC`가 하고, libc 없는 쪽의 본보기는 `init`이다.
milestone별 경과와 게이트 시간은 2026-10-20에 지웠다(커밋 이력에 있다).

## 구조체는 넘어오고 매크로는 안 넘어온다

`linux/input.h`의 `struct input_event`는 번역으로 온전히 넘어온다 — `@sizeOf`가
24(x86_64: `struct timeval` 16 + `type` 2 + `code` 2 + `value` 4)다. opaque로
강등됐다면 `@sizeOf` 자체가 컴파일 에러다. translate-c가 구조체를 opaque로
만드는 한계(ziglang/zig#1499, #4001)는 비트필드가 있을 때 발동하고 평범한
UAPI 구조체에는 해당하지 않는다. 새 구조체를 가져오면 먼저 `@sizeOf`를 찍어
기대값과 대조한다.

`_IOR`/`_IOWR`/`_IOW` 계열은 매크로 확장이라 못 가져온다.
`terminal/src/drm.zig`가 `_IOWR`을 비트 연산으로 손수 푼 것이 그 사례다.
다만 먼저 std를 찾는다 — `TIOCSCTTY`는 `std.os.linux.T.IOCSCTTY`(x86_64
`0x540e`)로 이미 있었다. `drm.zig`가 손으로 푼 것은 DRM 계열이 std에 없기
때문이지 매크로라서가 아니다.

가변 인자 libc 함수(`open(const char*, int, ...)`)는 번역 래퍼가 번거로워
`input.zig`/`pty.zig`처럼 `extern "c" fn`으로 필요한 시그니처만 직접 선언한다.
`execv`의 `char *const argv[]`가 `[*c]const [*c]u8`로 번역돼 Zig의
`?[*:0]const u8` 배열을 못 넘기는 것도 같은 이유다.

## 최적화 모드에서 glibc fortify가 번역을 깬다

Debug가 아닌 모드에서 Zig가 `-D_FORTIFY_SOURCE`를 붙이면 glibc의
`bits/fcntl2.h`가 켜지고, `__open_too_many_args()`처럼
`__attribute__((error))`가 달린 선언을 `@cImport`의 translate-c가 번역하지
못했다.

```
/usr/local/zig/lib/libc/include/generic-glibc/bits/fcntl2.h:46:5:
  error: call to '__error__' declared with attribute error:
  open can be called either with 2 or 3 arguments, not more
```

`@cImport` 시절의 처방은 블록 안에서 `@cDefine("_FORTIFY_SOURCE", "0")`을 먼저
선언하는 것이었고 GL-M3(2026-08-29)이 그렇게 `terminal`을 ReleaseSafe로
옮겼다. "fortify 때문에 Debug에 묶인다"는 틀린 결론이었다 — 끄면 된다.

함정은 벽의 크기다. 벽은 한 파일이 아니라 glibc 헤더를 읽는 블록 전부였고
(`drm.zig` · `main.zig`의 `poll.h` · `pty.zig`. `linux/input.h`와
`stb_truetype.h`는 glibc가 아니라 안 걸린다), 파일마다 에러 문구가 달랐다.
`drm.zig`는 `C import failed`인데 `poll`은 헤더가 아니라 `c.poll` 호출 자리에서
`expected type 'c_int', found 'bool'`로 잡힌다 — fortify가 켜지면 `poll`이
함수가 아니라 매크로가 되고 그 번역이 `c_int` 자리에 `bool`을 놓는다. 에러
문구로 검색해서는 같은 원인이라는 것을 알 수 없으므로, 한 곳을 고친 뒤 남는
에러를 다른 문제로 보지 않는다.

버퍼 검사를 잃어도 되는 근거는 대체물이다. ReleaseSafe는 Zig 자신의 안전
검사(경계 · 오버플로 · 널)를 켠 채로 두고, 그 블록들이 가져오는 것은 시스템
콜 래퍼라 fortify가 볼 버퍼가 우리 코드에 없다. 크기 효과(`terminal`
49,373,565 → 10,577,208바이트)는 [[project_gate_latency]]에 있다.

## translate-c 패키지로 옮겼더니 셋이 하나가 됐다 (ZU-M1)

Zig 0.17이 `@cImport`를 없애서 0.16에서 미리 translate-c 패키지(ghostty가
0.16에서 쓰는 `80f8b6e` 판)로 옮겼다. 번역은 `terminal/build.zig`의
`translateC`가 stub 헤더로 하고, 파일은 `@import("c_drm")`처럼 받는다. ZU-M2(2026-10-24)가 0.17 판
`02ff0c5`(2.0.0, ghostty의 `pkg/translate-c` wrapper가 받는 것과 같은 판)로 올렸다 —
`Translator.init`의 모양이 같아 `translateC`는 안 바뀌었다.

패키지도 ReleaseSafe 번역에 `-D_FORTIFY_SOURCE=2`를 붙이고(패키지
`src/main.zig:233`), 그 인자가 우리의 `defineCMacro` · `extra_args`보다 뒤에
온다. 명령줄로 `_FORTIFY_SOURCE=0`을 줘도 진다. 그래서 stub 헤더 안에
`#undef _FORTIFY_SOURCE`를 둔다(소스 안의 지시문이 명령줄 define 뒤에
처리된다).

우회 없이 지어 보면(mutation) 에러는 `c_poll` 하나다 — `poll`의
`expected type 'c_int', found 'bool'`은 그대로고 `drm` · `pty`의
`C import failed`는 사라졌다. 패키지의 번역기(aro)는 `__attribute__((error))`
선언을 넘긴다. 그래서 `#undef`는 `c_poll`에만 두고 나머지는 fortify를 켠
채로 둔다.

| 번역 | fortify | 근거 |
|---|---|---|
| `c_drm` | 켜짐 | mutation에서 번역 · 컴파일이 섰다 |
| `c_pty` | 켜짐 | 같다. `nm -D`에 `__read_chk@GLIBC_2.4`가 새로 생겼다 — `c.read`가 검사 래퍼를 지난다 |
| `c_poll` | 꺼짐 | 켜면 `c.poll`의 번역이 컴파일되지 않는다 |
| `c_input` · `c_stb_truetype` | 해당 없음 | glibc가 아니다 |

동작 변화는 그 `__read_chk` 하나다(전후 `nm -D` 비교).

곁가지로 Zig 쪽 함정 하나: 재수출된 이름이 제네릭 함수(`fn (comptime type)
type`)일 수 있다 — `ghostty_vt.Stream`이 그랬고 필요한 것은 인스턴스화된
`ghostty_vt.TerminalStream`이었다. 재수출 줄이 아니라 그 타입을 실제로
필드/변수로 선언한 사용처를 찾아 대조한다.

## 세 번째 길: libc를 아예 링크하지 않는다 (ZM-M1)

위 제약은 전부 libc 헤더를 번역할 때 생긴다. 하는 일이 시스템 콜뿐이면
`std.os.linux`의 raw syscall 래퍼로 충분하다. ZM-M1이 `init`(PID 1)을 이렇게
다시 썼다(`mount` · `mkdir` · `access` · `fork` · `execve` · `open` · `setsid` ·
`ioctl` · `dup2` · `close` · `exit`이 전부 있다). 얻는 것은 셋이다 — fortify
제약이 사라져 최적화 모드를 자유롭게 고르고, ioctl 상수를 std에서 찾는
경우가 많고, 정적 바이너리라 `kernel/make_initrd.sh`에 그 바이너리의
`copy_lib_deps` 줄이 필요 없다.

대가는 리눅스의 반환 규약을 직접 다루는 것이다. 커널은 실패를 음수 errno로
돌려주고 libc가 그것을 `-1` + `errno`로 바꾸던 일을 `std.os.linux.errno(rc)`가
대신한다.

Zig 0.16부터 `environ` 대체: `pub fn main(init: std.process.Init.Minimal)`로
선언하면 `init.environ.block.slice.ptr`이 커널이 스택에 올려준 envp다
(`std/start.zig:508-519`가 libc 없이 채운다). `execve`에 그대로 넘긴다 — std
자신도 같은 방식이다(`std/Io/Threaded.zig:16792`). 인자 없는 `main()`이나 전체
`Init`을 받으면 allocator · `Io.Threaded` · environ map 구성이 앞에 붙으므로
PID 1에는 `Minimal`이 맞다.

## How to apply

새 컴포넌트를 만들 때 먼저 "libc가 필요한가"를 묻는다. 시스템 콜만 쓰면 libc를
링크하지 않고 `std.os.linux`로 간다. C 라이브러리(`forkpty`, `stb_truetype`)가
필요할 때만 `translateC` 번역으로 가고, 그때는 구조체를 가져와 `@sizeOf`를
대조한다. ioctl 번호는 std에 있는지 먼저 찾고 없을 때만 매크로를 손으로
푼다 — 미리 전부 `extern struct`로 옮기지 않는다. glibc 헤더를 읽는 번역을
새로 더하면 ReleaseSafe로 지어 보고, 깨질 때만 그 stub 헤더에 `#undef`를 둔다.

관련: [[project_zig_rewrite_intent]] · [[project_gate_latency]]
