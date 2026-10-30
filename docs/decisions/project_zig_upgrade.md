---
name: project_zig_upgrade
description: "Zig 0.16 → 0.17 전환(ZU, 2026-10-03 ~ 10-24)에서 남은 것. ghostty를 따라가며 SHA로 고정한다 · 두 버전에서 다 컴파일되는 고침은 미리 한다 · 컨테이너 컴파일러가 거부하지 않는 문법은 다시 들어온다 · 0.17이 없앤 std 선언과 대체 · std 안에서 waitpid(*i32)와 W.*(u32)가 어긋난다 · zig fmt는 고침과 따로 commit"
metadata:
  node_type: memory
  type: project
---

ZU(2026-10-03 M0 · M1, 2026-10-24 M2)가 세웠다. design은
`docs/specs/2026-10-03-tars-zig-upgrade-design.md`, 깨진 자리의 표는
`docs/plans/2026-10-24-tars-zig-upgrade-zu-m2.md`.

## 전환은 ghostty를 따라가고, 기다리는 동안 미리 할 것만 한다

`terminal`이 ghostty를 Zig 패키지로 잡으므로 컨테이너의 Zig는 ghostty가 요구하는
major · minor와 정확히 같아야 한다(`requireZig`). 그래서 새 Zig가 나와도 ghostty
main의 `minimum_zig_version`이 바뀌는 날이 전환일이고, 태그를 기다리지 않고 전환
커밋 SHA로 고정한다(0.17은 PR #14519, `3d07ef9`, 릴리즈 뒤 19일). 그동안은 두
버전에서 다 컴파일되는 고침(`**` → `@splat`, `@cImport` → translate-c 패키지)만
미리 한다 — 전환일에 남는 일이 기계적 치환 47자리였다.

## 컨테이너 컴파일러가 거부하지 않는 문법은 다시 들어온다

M0가 `**` 25곳을 지웠지만 세 주 뒤 M2가 다섯을 다시 지웠다(WP · AU · BV ·
config_edit). `dupeZ` · `b.build_root` · `indexOfIgnoreCase`도 그 사이에 들어왔다.
호스트 0.17 `ast-check`는 사람이 돌려야 하는 검사라 막지 못했다. 막는 것은
컨테이너 컴파일러의 버전 자체다 — 그래서 전환을 미루면 미룬 만큼 다시 지운다.

## 0.17이 없앤 것과 대체 (우리 코드에서 만난 것만)

| 없어진 것 | 대체 |
|---|---|
| `Allocator.dupeZ(T, s)` | `dupeSentinel(T, s, 0)` — sentinel이 마지막 |
| `std.fmt.bufPrintZ(buf, fmt, args)` | `bufPrintSentinel(buf, fmt, args, 0)` |
| `std.ascii.indexOfIgnoreCase` | `findIgnoreCase` |
| `@typeInfo(T).@"struct".fields` (`f.name` · `f.type`) | `field_names` · `field_types` 두 슬라이스를 함께 돈다. 안 쓰는 capture는 오류 |
| `std.builtin.OptimizeMode`, `.ReleaseSafe` | `std.lang.Optimize`, `.safe`(옛 이름은 decl alias라 리터럴로 못 쓴다) |
| `b.build_root.handle` | `b.root.root_dir.handle` |
| `b.pathFromRoot(p)` | `b.pathResolve(&.{ b.root.toString(b.allocator) catch @panic("OOM"), p })` |
| `@"type"` 필드 이름 | `type` — 0.17이 식별자로 허용하고 `zig fmt`가 바꾼다 |

std 안의 어긋남 하나: `linux.waitpid` · `wait4`가 `*i32`를 받는데 `linux.W.*`는
`u32`를 받는다. 시스템 콜 자리에 `@ptrCast(&status)`를 두고 `var status: u32`와
`W.*` 줄은 안 바꿨다(M2-B).

## ghostty 0.16 → 0.17 사이에 우리에게 보인 API 변화

`effects.write_pty` 콜백의 인자가 `[:0]const u8`에서 `[]const u8`로. kitty
`Placement.Location`에 `relative`(P=/Q= 부모 상대 placement)가 늘어 switch가
전부를 다루지 못했다 — `.virtual, .relative => continue`로 두고 상대 placement를
그리는 것은 비목표다. 1,312 커밋(src/terminal 328) 가운데 컴파일을 깨는 것은 이 둘뿐이었다.

## zig fmt는 고침과 따로 commit한다

0.17 `zig fmt`는 438줄 · 30파일을 바꾸고 그중 84줄이 `@intFromEnum` → `@backingInt`
자동 치환이다. 고침 commit과 섞이면 diff를 못 읽는다. 이 저장소에 fmt 게이트는
없었고(M0 실측 2) ZU는 만들지 않았다 — GH-M0(2026-10-30)부터 `quick_check.sh`가
`fmt --check` · `ast-check`를 호스트(`make quick`)와 CI에서 본다([[project_github_actions]]).

## 다음에 올릴 때 고칠 자리

Dockerfile의 `ENV ZIG_VERSION`이 정본이고 `quick_check.sh` · `checks.yml`이 그 줄을 읽는다.
해시는 버전마다 다르므로 `checks.yml`의 `ZIG_SHA256`(x86_64-linux tarball, ziglang.org
`index.json`의 `shasum`)을 함께 고친다. 둘이 어긋나면 host job이 `sha256sum -c`에서 빨개진다 —
우리 코드가 아닌 빨강이다.

## 호스트 0.17로 미리 잴 수 있는 것과 없는 것

macOS 호스트의 0.17로 `terminal` · `init` 사본의 게스트 빌드(`x86_64-linux`)를
돌리면 컴파일러가 거부하는 것은 전부 보인다 — 컨테이너 이미지를 굽기 전에 고침
표가 완성됐다. 못 보는 것은 `linux/input.h`를 번역하는 프로그램(macOS에 헤더가
없다)과 Linux 시스템 콜을 직접 부르는 검사의 실행(`logline_test`는 `linux.read`가
쓰레기를 돌려줘 ABRT, init 검사는 멈춘다 — 0.17 문제가 아니다). 사본은 `/tmp`에
두고 저장소는 건드리지 않는다.
