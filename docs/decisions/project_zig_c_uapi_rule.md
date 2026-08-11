---
name: project_zig_c_uapi_rule
description: "Zig에서 리눅스 UAPI를 쓸 때의 규칙 — 비트필드 없는 구조체는 @cImport로 그대로, _IOR/_IOWR 계열 ioctl 매크로만 손으로 재구현"
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

**Zig 라이브러리 타입을 구조체 필드로 쓸 때 주의:** 이건 C 상호운용이
아니라 Zig 쪽 함정인데 같은 세션에서 겪었다. 재수출된 이름이 **제네릭
함수**(`fn (comptime type) type`)일 수 있다 — `ghostty_vt.Stream`이
그랬고, 실제로 필요한 것은 인스턴스화된 `ghostty_vt.TerminalStream`이었다.
**재수출 줄이 아니라, 그 타입을 실제로 필드/변수로 선언한 사용처를 찾아
대조할 것.**

**How to apply:** 새로 커널 UAPI를 쓸 때는 먼저 `@cImport`로 구조체를
가져와 `@sizeOf`를 찍어보고, 기대값과 맞으면 그대로 진행한다. ioctl 번호가
필요해지는 시점에만 매크로를 손으로 푼다 — 미리 전부 `extern struct`로
옮기지 않는다. 관련: [[project_zig_rewrite_intent]]
