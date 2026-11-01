---
name: project_zig_rewrite_intent
description: "Rust를 Zig로 재작성하려던 의도(2026-08-10)와 결말 — init은 옮겼고 kms는 옮기지 않고 지웠다(ZM, 2026-08-13 완료). 저장소와 빌드 이미지 어디에도 Rust는 없다. 동기는 학습이라 '어느 언어가 더 안전한가'로 되묻지 않는다"
metadata:
  type: project
---

2026-08-10 결정: Rust 컴포넌트(`init/` = PID 1, `kms/`)를 전부 Zig로 재작성한다. 동기는 성능이나 이식성이 아니라
Zig를 제대로 써보고 싶다는 학습 욕구다([[user_learning_goal]]과 같은 결) — "Rust가 더 안전하다" 같은 논거로
되묻지 않는다. 그때 걱정했던 "translate-c가 커널 UAPI 헤더에서 자주 막힌다"는 TF-M3이 과했다고 확인했다 —
막히는 것은 구조체가 아니라 `_IOR`/`_IOWR` 매크로다([[project_zig_c_uapi_rule]]).

## 결말 (2026-08-13, Zig Migration ZM-M1 · M2)

- `init/`은 Zig로 옮겼다(ZM-M1). libc를 링크하지 않고 `std.os.linux` raw syscall만 쓰는 정적 바이너리다 —
  `@cImport` 문제가 아예 발생하지 않는 경로였다([[project_zig_c_uapi_rule]]의 "세 번째 길").
- `kms/`는 옮기지 않고 지웠다(ZM-M2). `terminal/src/drm.zig`가 같은 일(DRM 모드 설정 → dumb buffer →
  framebuffer)을 이미 Zig로 하고 있어서 옮기면 중복 코드가 된다. "재작성"이 항상 이식을 뜻하지는 않는다.
- 툴체인도 지웠다(ZM-M2). `devcontainer/Dockerfile`에서 rustup이 빠져 이미지가 1.75GB → 1.11GB가 됐다.

How to apply: 새 컴포넌트는 Zig로 만든다. 옛 Rust 구현을 참고해야 하면 작업 트리가 아니라 git 히스토리를
본다(`git show 0ec3c13^:kms/src/main.rs`). 어떤 컴포넌트를 다른 언어로 "옮길" 때는 그 기능이 이미 다른 곳에
구현돼 있지 않은지 먼저 확인한다 — `kms`가 그 경우였다. design은 `docs/specs/2026-08-13-tars-zig-migration-design.md`.
