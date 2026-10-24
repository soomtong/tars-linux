---
name: project_screen_args
description: "init → terminal argv 계약을 한 파일로 모은 Screen Args(SA-M0, 2026-10-24). shared/screen_args.zig를 두 build.zig가 b.path(\"../shared/…\")로 named module로 붙인다 — target 없는 모듈 하나가 게스트 exe와 호스트 검사에 같이 간다. 0.17의 @tagName은 sentinel이 있다 · enum을 옮기면 그 메서드는 자유 함수가 된다 · Toggles.parse(.file|.argv, text, sink)가 파일 넷 · argv 다섯을 한 함수에 둔다 · 왕복 검사는 init의 zig build test 한 곳"
metadata:
  type: project
---

# Screen Args (SA)

2026-10-24 프로젝트 점검이 남긴 다섯 가운데 추천 1순위를 사용자가 골랐다(2026-10-24). 설계는
`docs/specs/2026-10-24-tars-screen-args-design.md`, plan은 `docs/plans/2026-10-24-tars-screen-args-sa-m0.md`.

## 무엇을 세웠나

init이 terminal에 execve argv로 넘기는 값의 종류(`Keyboard` · `HangulLayout` · `LatinLayout` · `ToggleKey` · `Toggles` ·
`ClipboardScope`)와 자리(`Slot` · `ARGC`)와 손으로 띄울 때의 기본값이 `shared/screen_args.zig` 한 파일에 있다. SA 전에는 enum이
`init/src/config.zig`와 `terminal/src/{hangul,input,clipboard}.zig`에 한 벌씩 있었고 둘을 잇는 것이 argv의 문자열과 "짝이어야
한다"는 주석뿐이었다. 양쪽은 옛 이름을 별명으로 다시 내보낸다(`config.Keyboard` · `hangul.Layout` · `input.Toggles` ·
`clipboard.Scope`)라 바깥 호출자는 그대로다. argv의 모양은 위치 기반 아홉 칸 그대로다 — 깨질 자리는 위치가 아니라 정의가 두
벌인 것이었다(design 결정 3, `key=value`를 고르지 않은 이유).

## 두 build.zig가 같은 파일을 named module로 붙인다

Zig는 모듈 뿌리 밖의 파일을 `@import`하지 못하지만 `b.createModule(.{ .root_source_file = b.path("../shared/screen_args.zig") })`는
된다(0.17). target · optimize를 주지 않은 모듈 하나를 x86_64 게스트 exe와 호스트 test에 함께 `addImport`해도 된다 — 각자의
target으로 컴파일된다. 그 파일을 트리에 둔 모듈마다 붙여야 하고(init 9 · terminal 6), 빠뜨리면 컴파일러가
"no module named 'screen_args' available within module …"으로 어느 모듈인지 말한다. 캐시는 바르다 — 아무것도 안 바꾸면 `cached`,
공유 파일만 건드리면 그것을 보는 exe만 다시 컴파일되고 안 보는 tars-install은 `cached`로 남는다(`zig build --summary all`).

공유 파일은 순수해야 한다. init이 libc를 링크하지 않으므로([[project_zig_c_uapi_rule]]) 거기서 libc를 끌어오면 init이 깨진다.
모르는 이름을 알리는 길은 호출자가 주는 sink(`unknown(name)`)다 — init은 로그를 찍고 terminal은 `ignore_unknown`을 준다.

## 함정

- 0.17의 `@tagName`은 `*const [N:0]u8`, sentinel이 있는 문자열을 준다. `config.zig`의 `arg()` switch 넷은 "@tagName은 sentinel이
  없다"는 낡은 전제 위에 손으로 쓴 것이었다. 이제 `arg()`는 `@tagName(self)` 한 줄이다.
- Zig의 enum은 선언 밖에서 메서드를 더할 수 없다. enum을 공유 파일로 옮기면 그 위에 얹혀 있던 메서드(`hangul.Layout`의
  `lookup` · `nonSyllable` 등 넷)는 그 파일의 자유 함수가 된다 — `layout.lookup(ch)`가 `hangul.lookup(layout, ch)`로.
- 0.17 `zig fmt`가 `@intFromEnum`을 `@backingInt`로, `**`는 컴파일러가 거부한다(`@splat`). 새 파일은 호스트 `zig fmt`를 한 번
  거친 뒤 컨테이너에 넣는다([[project_zig_upgrade]]).
- 전환 키 목록의 파서는 파일과 argv가 일부러 다르다 — 파일은 넷(`esc_latin`은 모르는 이름), argv는 다섯(EL design 결정 1). 한
  함수에 두려면 `comptime` 인자 하나(`Toggles.parse(.file | .argv, …)`)면 된다.
- 왕복 검사(`shared/screen_args_test.zig`)는 init의 `zig build test` 한 곳에만 등록했다. terminal 쪽에도 넣으면 같은 검사가 두 번
  돌고 빠뜨릴 곳이 둘이 된다. 검사 모듈의 뿌리는 `shared/`라 `screen_args.zig`를 파일로 import한다.

## 다음(M1)

`Args` 구조체와 `encode` · `decode`를 공유 파일에 더해 init의 쓰는 자리 둘(부팅 · `doReloadTerminal`)과 terminal의 읽는 자리가 한
함수 쌍을 거치게 한다(design 결정 7). `Rescue.slot`을 `Slot`으로 바꿀지는 그때 본다.
