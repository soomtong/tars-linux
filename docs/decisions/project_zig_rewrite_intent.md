---
name: project_zig_rewrite_intent
description: "User wants to eventually rewrite TARS's Rust components in Zig to learn Zig properly; current Rust/Zig split is transitional, not a design goal"
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
struct`로 옮긴 이유다. TF-M3(evdev)에서 `linux/input.h`의 `struct
input_event`가 자동 번역되는지가 이 가설의 검증대이며, 그 결과를 재작성
착수 판단에 쓴다. 상세는 프로젝트의 `HANDOFF.md` "남은 작업" 절 참고.

**How to apply:** 새 컴포넌트를 만들 때 언어 선택을 물어야 한다면 Zig를
기본값으로 제안한다. `init/`이나 `kms/`에 Rust 코드를 크게 늘리는 작업이
생기면, 그 시점에 "이걸 지금 Zig로 옮기는 게 나은지" 먼저 짚어준다 —
버릴 코드에 시간을 쓰지 않기 위해서다. 재작성 자체는 별도 서브프로젝트로
brainstorming부터 시작하며, 이 저장소 관례대로 milestone 단위로 쪼갠다.
