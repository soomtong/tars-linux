---
name: project_zig_rewrite_intent
description: "Rust를 Zig로 재작성하려던 의도와 그 결말 — init은 옮겼고 kms는 옮기지 않고 지웠다(ZM, 2026-08-13 완료). 저장소에 Rust는 남아 있지 않다"
metadata: 
  node_type: memory
  type: project
  originSessionId: daf2dfeb-217c-47be-840c-bae2ac616ae2
  modified: 2026-08-10T13:58:09.815Z
---

2026-08-10 결정: TARS는 언젠가 **Rust 컴포넌트를 전부 Zig로 재작성**한다.
현재 Rust(`init/` = PID 1 `tars-init`, `kms/`)와 Zig(`terminal/`)를 혼용
중인데, 이 혼용은 의도된 아키텍처가 아니라 **과도기 상태**다.

동기는 성능이나 이식성이 아니라 **Zig를 제대로 써보고 싶다는 학습 욕구**다
([[user_learning_goal]]과 같은 결). 그래서 "Rust가 더 안전하다" 같은 논거로
재작성을 만류하지 말 것 — 목적이 다르다.

지금 당장 하지 않는다. TF-M3(evdev 키보드 입력) 이후 별도 서브프로젝트로
다루기로 했다.

2026-08-10 조사로 확인한 전제: Zig의 실질 강점은 `@cImport`보다 **툴체인**
(Clang + 97개 libc 번들, glibc 버전 지정 크로스 컴파일)이다. 반대로
`@cImport`는 Zig 0.16에서 deprecated(→ `b.addTranslateC`)됐고, translate-c는
비트필드 구조체를 opaque로 강등시켜 **커널 UAPI 헤더에서 자주 막힌다** —
이 저장소의 `terminal/src/drm.zig`가 이미 DRM 구조체를 손으로 `extern
struct`로 옮긴 이유다.

**2026-08-11 TF-M3에서 이 검증대의 답이 나왔다: 생각보다 덜 막힌다.**
`linux/input.h`의 `struct input_event`는 `@cImport`로 그대로 넘어왔고
(`@sizeOf == 24`), opaque 강등은 **비트필드가 있을 때만** 발동한다는 것이
확인됐다. 즉 "커널 UAPI 헤더에서 자주 막힌다"는 위 문장은 과했다 —
막히는 것은 구조체가 아니라 `_IOR`/`_IOWR` 계열 **매크로**다. 재작성
착수를 이 이유로 미룰 근거는 약해졌다. 상세 규칙은
[[project_zig_c_uapi_rule]].

## 결말 (2026-08-13, Zig Migration ZM-M1·M2)

**의도는 실행됐고, 두 컴포넌트의 운명은 갈렸다.**

- **`init/`은 Zig로 옮겼다**(ZM-M1). libc를 링크하지 않고 `std.os.linux`
  raw syscall만 쓰는 정적 바이너리다 — 위에서 걱정하던 `@cImport` 문제가
  아예 발생하지 않는 경로였다. 상세는 [[project_zig_c_uapi_rule]]의
  "세 번째 길".
- **`kms/`는 옮기지 않고 지웠다**(ZM-M2). `terminal/src/drm.zig`가 같은
  일(DRM 모드 설정 → dumb buffer → framebuffer)을 이미 Zig로 하고 있어서
  옮기면 중복 코드가 된다. "재작성"이 항상 이식을 뜻하지는 않는다.
- **툴체인도 지웠다**(ZM-M2). `devcontainer/Dockerfile`에서 rustup이 빠져
  이미지가 1.75GB → 1.11GB가 됐다. 이제 저장소와 빌드 이미지 어디에도
  Rust는 없다 — 위의 "과도기 상태"는 끝났다.

**How to apply:** 새 컴포넌트는 Zig로 만든다(이제 선택지가 하나다). 옛
Rust 구현을 참고해야 할 일이 생기면 작업 트리가 아니라 **git 히스토리**를
본다(`git show 0ec3c13^:kms/src/main.rs`). 어떤 컴포넌트를 다른 언어로
"옮길" 때는 옮기기 전에 **그 기능이 이미 다른 곳에서 구현돼 있지 않은지**
먼저 확인한다 — `kms`가 그 경우였다.
