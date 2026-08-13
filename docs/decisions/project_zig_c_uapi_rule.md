---
name: project_zig_c_uapi_rule
description: "Zig에서 커널을 부를 때의 규칙 — 시스템 콜만 쓰면 libc를 링크하지 말고 std.os.linux로; libc가 필요할 때만 @cImport(구조체는 되고 ioctl 매크로는 안 되며 최적화 모드에서 fortify로 깨진다)"
metadata:
  node_type: memory
  type: project
---

2026-08-11 TF-M3(evdev 키보드 입력) 실행으로 확인된 규칙이다.

**구조체는 `@cImport`가 된다.** `linux/input.h`의 `struct input_event`를
`@cImport({ @cInclude("linux/input.h") })`로 가져와 `@sizeOf`가 **24**
(x86_64: `struct timeval` 16 + `type` 2 + `code` 2 + `value` 4)로 나왔다.
opaque로 강등됐다면 `@sizeOf` 자체가 컴파일 에러이므로, 필드까지 온전히
넘어왔다는 뜻이다. translate-c가 구조체를 opaque로 만드는 알려진 한계
(ziglang/zig#1499, #4001)는 **비트필드가 있을 때** 발동하며, 평범한 UAPI
구조체에는 해당하지 않는다.

**매크로는 안 된다.** `_IOR`/`_IOWR`/`_IOW` 계열은 매크로 확장이라
translate-c가 가져오지 못한다. `terminal/src/drm.zig:108-110`이 `_IOWR`을
비트 연산으로 손수 재구현한 것이 그 사례다. TF-M3에서는 입력 장치가
QEMU에 하나뿐이라 `/dev/input/event0`을 하드코딩하고 `EVIOCGBIT` 열거를
아예 하지 않아 이 한계에 부딪히지 않았다.

**가변 인자 libc 함수도 손으로 선언한다.** `open(const char*, int, ...)`
같은 것은 translate-c 래퍼가 쓰기 번거로워, `input.zig`/`pty.zig`처럼
`extern "c" fn`으로 필요한 시그니처만 직접 선언하는 편이 낫다.
`execv`의 `char *const argv[]`가 `[*c]const [*c]u8`로 번역돼 Zig의
`?[*:0]const u8` 배열을 못 넘기는 것도 같은 이유다.

**최적화 모드를 바꾸면 `@cImport`가 깨진다(2026-08-12 TF-M4에서 확인).**
initrd를 줄이려고 `zig build -Doptimize=ReleaseSafe`로 바꿨더니
`drm.zig:3`의 `@cImport` 전체가 `error: C import failed`로 실패했다. 원인은
우리 코드가 아니라 glibc의 fortify 헤더다 — Debug가 아닌 모드에서 Zig가
`-D_FORTIFY_SOURCE`를 붙이면 `bits/fcntl2.h`가 활성화되고, 그 안의
`__open_too_many_args()`처럼 `__attribute__((error))`가 달린 선언을
translate-c가 번역하지 못한다.

```
/usr/local/zig/lib/libc/include/generic-glibc/bits/fcntl2.h:46:5:
  error: call to '__error__' declared with attribute error:
  open can be called either with 2 or 3 arguments, not more
```

즉 **`@cImport`로 `fcntl.h`를 끌어다 쓰는 코드는 Debug 모드에 묶인다.**
우회는 `@cImport` 블록 안에서 `@cDefine("_FORTIFY_SOURCE", "0")`을 먼저
선언하는 것이지만, TF-M4에서는 종료 게이트 도중에 검증 대상 바이너리의
컴파일 모드를 바꾸는 위험을 피해 Debug를 유지하고 크기 문제는
[[project_gate_chain_composition]]에 적은 initrd gzip 압축으로 해결했다.
`@cImport`를 `b.addTranslateC`로 옮기게 되면(0.16 권장 경로) 이 제약도 함께
재검토할 것.

**Zig 라이브러리 타입을 구조체 필드로 쓸 때 주의:** 이건 C 상호운용이
아니라 Zig 쪽 함정인데 같은 세션에서 겪었다. 재수출된 이름이 **제네릭
함수**(`fn (comptime type) type`)일 수 있다 — `ghostty_vt.Stream`이
그랬고, 실제로 필요한 것은 인스턴스화된 `ghostty_vt.TerminalStream`이었다.
**재수출 줄이 아니라, 그 타입을 실제로 필드/변수로 선언한 사용처를 찾아
대조할 것.**

## 세 번째 길: libc를 아예 링크하지 않는다 (2026-08-13 ZM-M1에서 확인)

위 제약들은 전부 **libc 헤더를 `@cImport`로 읽을 때** 생긴다. 그런데
컴포넌트가 하는 일이 시스템 콜뿐이라면 libc가 필요 없다. `std.os.linux`가
raw syscall 래퍼를 이미 다 갖고 있다.

ZM-M1에서 `init`(PID 1)을 이 방식으로 다시 썼다. `mount`·`mkdir`·`access`·
`fork`·`execve`·`open`·`setsid`·`ioctl`·`dup2`·`close`·`exit`이 전부
`std.os.linux`에 있고, **첫 시도에 컴파일돼 게이트를 통과했다.** 얻은 것:

- **fortify 제약이 사라진다.** glibc 헤더를 안 읽으므로 최적화 모드를 자유롭게
  고를 수 있다. 위 절의 제약은 `@cImport`를 쓰는 코드에만 남는다.
- **ioctl 매크로를 손으로 풀 필요가 없는 경우가 많다.** `TIOCSCTTY`는
  `std.os.linux.T.IOCSCTTY`로 이미 있었다(x86_64 `0x540e`). std가 옮겨둔
  상수를 먼저 찾아볼 것 — `drm.zig`가 `_IOWR`을 손수 푼 것은 DRM 계열이
  std에 없기 때문이지 매크로라서가 아니다.
- **정적 바이너리가 된다.** `kernel/make_initrd.sh`에서 그 바이너리의
  `copy_lib_deps` 줄을 지울 수 있다.

대가는 리눅스의 반환 규약을 직접 다루는 것이다. 커널은 실패를 **음수 errno를
반환값으로** 돌려주고 libc가 그것을 `-1` + `errno` 전역으로 바꾼다.
`std.os.linux.errno(rc)`가 그 해석을 대신한다.

**Zig 0.16에서 `environ` 대체:** `pub fn main(init: std.process.Init.Minimal)`
로 선언하면 `init.environ.block.slice.ptr`이 커널이 스택에 올려준 envp다
(`std/start.zig:508-519`가 libc 없이 채운다). `execve`에 그대로 넘긴다 — std
자신이 같은 방식을 쓴다(`std/Io/Threaded.zig:16792`). 인자 없는 `main()`이나
전체 `Init`을 받으면 allocator·`Io.Threaded`·environ map 구성이 앞에 붙으므로
PID 1에는 `Minimal`이 맞다.

**How to apply:** 새 컴포넌트를 만들 때 먼저 **"이게 libc가 필요한가"**를
묻는다. 시스템 콜만 쓰면 libc를 링크하지 않고 `std.os.linux`로 간다 — 위
제약들이 통째로 사라진다. libc 함수(`forkpty`, `stb_truetype` 같은 C
라이브러리)가 필요할 때만 `@cImport` 경로로 가고, 그때는 먼저 구조체를
가져와 `@sizeOf`를 찍어 기대값과 맞는지 확인한다. ioctl 번호는 std에 있는지
먼저 찾고, 없을 때만 매크로를 손으로 푼다 — 미리 전부 `extern struct`로
옮기지 않는다. 관련: [[project_zig_rewrite_intent]]
