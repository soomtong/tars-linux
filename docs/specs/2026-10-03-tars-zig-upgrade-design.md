# TARS Zig Upgrade — Design

접두사: ZU

Status: 끝났다(2026-10-24) — M0 · M1(2026-10-03, `**` → `@splat`, `@cImport` → translate-c 패키지) · M2(2026-10-24, 컨테이너 0.17.0 · ghostty `3d07ef9` · 고침 47자리 · `zig fmt`, 실측 6~10, 루트 게이트 22/22).

관련 문서: `docs/specs/2026-08-13-tars-zig-migration-design.md`(Rust를 Zig 0.16으로 옮긴 ZM) ·
`docs/decisions/project_zig_c_uapi_rule.md`(translate-c가 fortify 헤더를 못 넘는 일) ·
참조 구현 `/Users/dp/Repository/_a-book/monorepo`의 `3aad8cc`(같은 사용자의 다른 저장소에서 2026-10-03에
0.17로 올린 커밋).

## 한 줄 요약

Zig 0.16.0을 0.17.0으로 올린다. 막는 것은 우리 코드가 아니라 ghostty다. 그래서 0.16에서도 되는 고침을
지금 먼저 해 두고, 전환하는 날의 diff를 버전 줄 · ghostty SHA · 패키지 URL 몇 줄로 줄인다.

## 왜 지금인가

0.17.0이 나왔다(릴리즈 노트 `https://ziglang.org/download/0.17.0/release-notes.html`). 사용자가 다른
저장소를 같은 날 올렸고, 이 저장소의 계획을 세우자고 했다. 2026-10-03에 사용자가 범위를 정했다 — ghostty가
0.17로 가면 그때 마무리하고, 지금은 0.16에서 고쳐도 충분한 것만 고친다.

## 착수 전에 아는 것

2026-10-03에 확인했다. 우리 코드의 파손 목록은 macOS의 0.17 컴파일러
(`~/.local/zig/zig-aarch64-macos-0.17.0/zig`)로 `ast-check` · `fmt --check`를 돌려 뽑았다. 빌드는 하지 않았다.

1. 빌드는 컨테이너의 zig로 한다. `devcontainer/Dockerfile:406`의 `ZIG_VERSION=0.16.0`이 그 값이다.
   호스트 macOS의 zig 버전은 빌드와 무관하다.
2. ghostty가 막는다. `terminal/build.zig.zon`이 `ghostty-src`를 패키지로 잡으므로 `zig build`는
   ghostty의 `build.zig`를 컴파일한다. ghostty의 `requireZig`(`ghostty-src/src/build/zig.zig`)는
   major · minor가 정확히 같아야 통과한다 — 고정한 `2602886`은 `0.16.0`을 요구한다.
3. ghostty 업스트림은 아직 0.16이다. main의 `minimum_zig_version`은 `0.16.0`(마지막 zon 변경
   2026-09-27)이고, 0.17 전환은 draft PR #14519(2026-10-02, 파일 228개, 본문 "NOT AT ALL
   COMPLETE")와 추적 이슈 #14518에 있다. 0.16 전환은 이슈 2026-04-10 → 닫힘 2026-07-22였다.
4. 우리 코드에서 0.17이 거부하는 것은 둘이다.
   - 배열 곱 `**` 제거(`@splat`으로) — 25곳, 12파일. init 10파일 · terminal 2파일
     (`drm.zig` · `input.zig`) · 테스트의 문자열 `"a" ** n` 포함.
   - `@cImport` 제거(translate-c 패키지로) — terminal 5파일: `drm.zig` · `pty.zig` · `main.zig` ·
     `font.zig` · `input.zig`. init에는 없다.
5. 0.17이 거부하지는 않지만 바꾸는 것.
   - `@intFromEnum` → `@backingInt` — 0.17 `zig fmt`가 스스로 고쳐 쓴다(`power` · `firewall` ·
     `services` · `service_cli`). 옛 이름도 컴파일된다.
   - `std.builtin` → `std.lang` — `terminal/build.zig:37` 한 곳. deprecated다.
6. 참조 구현이 고친 나머지(`dupeZ` · `std.ascii.indexOfIgnoreCase` · `b.build_root` · `b.args` ·
   `addFmt` 경로 · `@typeInfo` 필드 · `allocPrint` · `ArrayList.getLast`)는 우리 코드에 없다.
7. ghostty는 0.16에서 이미 translate-c 패키지를 쓴다 — zon의 `translate_c`(lazy,
   `https://deps.files.ghostty.org/translate_c-80f8b6e4f45a303268717d8e5f4f91d7837138bb.tar.gz`,
   hash `translate_c-0.0.0-Q_BUWmU6BwB_9JKG2l2W7i_mhmYWeRseTGBEHi_YlV5f`). 0.17의 참조 구현은
   codeberg `875969d`(hash `translate_c-0.0.0-Q_BUWoFOBwAhz77Zd15HCVuhTKzdUKc94kezmCeJ7IC_`)를 쓴다.
   API는 둘 다 `Translator.init(dep, .{ .c_source_file, .target, .optimize })`와 `.mod`다.
8. `drm.zig:21`에 GL-M3이 남긴 숙제가 있다 — `@cImport`를 빌드 단계 번역으로 옮기면 fortify를 끄는
   줄 셋(`drm` · `main` · `pty`)이 필요 없어질 수 있다.

## 결정

### 결정 1 — 전환은 ghostty를 따라간다

ghostty를 직접 0.17로 고치지 않는다. ghostty `src`에만 `**`가 57곳이고 의존성(`uucode` 등)도 함께
옮겨야 해서, 업스트림 #14519가 하는 일을 우리가 대신하게 된다. ghostty는 SHA로 고정하므로 태그 릴리즈를
기다릴 필요는 없다. main에 0.17 전환이 들어가면 M2를 연다.

### 결정 2 — 0.16과 0.17 양쪽에서 컴파일되는 고침만 지금 한다

`**`와 `@cImport`가 그것이다. `@backingInt` · `std.lang`은 0.16에 없으므로 M2로 미룬다.

### 결정 3 — `**`는 `@splat`으로 바꾼다

`@splat`의 배열 결과는 0.14부터 있다. 모양은 결과 타입이 보이는 자리에서 `@splat(v)`이고, 타입이
안 보이는 문자열 연결(`"stop " ++ "n" ** 32`)은 `@as([N]u8, @splat('n'))`이다. 구체적인 줄은 M0 plan에.

### 결정 4 — `@cImport`는 `b.addTranslateC`를 거치지 않고 translate-c 패키지로 바로 간다

0.17에서 `b.addTranslateC`는 deprecated다. ghostty가 0.16에서 쓰는 패키지(착수 전 7)를 그대로 받으면
최종 모양에 지금 도착하고, M2는 zon의 URL · hash 두 줄을 codeberg 판으로 바꾸기만 한다. 번역
모듈을 헤더 묶음마다 하나로 할지, 파일마다 하나로 할지는 M1 plan이 정한다.

### 결정 5 — fortify 우회는 재 보고 뺀다

M1이 fortify를 끄는 줄 없이 ReleaseSafe로 지어 본다. 번역이 통하면 세 자리를 지우고, 통하지 않으면
남기되 `drm.zig`의 설명을 새 사실로 고친다.

M1 plan을 쓰며 패키지 소스를 읽어 보니(2026-10-03) 패키지도 ReleaseSafe 번역에 `-D_FORTIFY_SOURCE=2`를
붙이고, 그 인자가 우리의 명령줄 define보다 뒤에 온다. 그래서 "통하면 지운다"는 기대보다 "자리를
`@cDefine`에서 stub 헤더의 `#undef`로 옮긴다"가 될 공산이 크다. 판정은 M1 Task 3이다.

## 위험

### 위험 1 — ghostty 전환이 길어진다

0.16 때는 석 달 반이었다. 그동안 M2는 열지 않는다. M0 · M1은 그와 무관하게 끝난다.

### 위험 2 — ghostty SHA를 올리면 0.17 말고 다른 것도 따라온다

`vt.zig`가 쓰는 API — `RenderState`, kitty placement(TG), `takeReplies`(TQ) — 가 바뀌었을 수 있다.
M2의 첫 일은 `2602886`부터 전환 커밋까지 `src/terminal`의 변화를 읽는 것이다.

### 위험 3 — 패키지 번역이 `@cImport`와 조금 다르다

같은 구현이라고 릴리즈 노트가 적지만 옵션 기본값이 다를 수 있다. 이미 아는 차이 후보가 있다 —
`main.zig`의 `c.poll`(fortify 아래에서 `c_int`/`bool`), `pty.zig`가 직접 선언하는 `execv`. M1의 판정은
`terminal` 테스트와 루트 게이트다.

## 비목표

1. ghostty를 우리 손으로 0.17에 맞추기(결정 1).
2. 호스트 macOS의 zig · zls 버전. 빌드는 컨테이너에서 한다.
3. 0.17에만 있는 이름으로 미리 바꾸기(`@backingInt` · `std.lang`).
4. 0.17의 새 기능 쓰기(`@divCeil`, 증분 컴파일 등).

## Milestone

한 milestone이 끝나면 다음 plan을 그때 쓴다.

- ZU-M0 — `**` 25곳을 `@splat`으로(0.16). 판정은 두 `zig build test`와 0.17 `ast-check`의
  `**` 오류 0줄.
- ZU-M1 — `@cImport` 다섯을 translate-c 패키지로, fortify 우회 재기(0.16). 루트 게이트.
- ZU-M2 — ghostty 0.17 전환 뒤. `ZIG_VERSION` · `GHOSTTY_SHA` · zon(`minimum_zig_version` ·
  translate-c URL) · `zig fmt` · `std.lang` · 0.16을 적은 문서들(`check.sh` 주석 · lessons ·
  decisions · crash course). 루트 게이트, 닫기.

## 실측 (M0, 2026-10-03)

### 실측 1 — `**`를 지우면 0.17이 거부하는 것은 `@cImport` 다섯뿐이다

0.17 `ast-check`로 본 남은 오류는 `drm` · `font` · `input` · `main` · `pty`의 `@cImport`다. `**`는
파싱 오류라 같은 파일의 `@cImport`(AstGen 오류)를 가렸다 — 착수 전 4의 "terminal 5파일"은 맞았고,
M0 plan의 "셋"은 가려진 출력을 읽은 것이었다.

### 실측 2 — 0.16 `zig fmt`가 고칠 것이 이미 61줄 있다

`zig fmt --check init terminal/src`가 M0 전에도 후에도 같은 12파일을 짚는다(`hangul.zig` 25줄 ·
`storage.zig` 9줄 · `devices_test.zig` 8줄 등, 빈 줄 같은 것). 이 저장소에는 fmt 게이트가 없다. M0은
건드리지 않았다. M2가 0.17 `zig fmt`를 돌리면 이 61줄이 `@backingInt` 고침과 섞여 함께 바뀐다 — 그
diff를 읽을 때 둘을 나눠 본다.

## 실측 (M1, 2026-10-03)

### 실측 3 — 패키지 번역에서 fortify를 꺼야 하는 것은 `poll.h` 하나다

우회 없이 ReleaseSafe로 지으면(mutation) 에러는 하나다 — `c_poll.zig`의 `expected type 'c_int', found
'bool'`. glibc의 fortify `poll` 래퍼가 `__builtin.object_size`의 `c_int` 자리에 `__USE_FORTIFY_LEVEL > 1`을
놓는다. GL-M3이 `@cImport`에서 본 `drm` · `pty`의 `C import failed`(`bits/fcntl2.h`의
`__attribute__((error))`)는 패키지의 번역기에서 나지 않는다. 결정 5대로 통하는 둘은 지웠고, `c_poll`
stub 헤더 하나에 `#undef _FORTIFY_SOURCE`를 뒀다 — 명령줄 define은 패키지가 맨 뒤에 붙이는
`-D_FORTIFY_SOURCE=2`에 진다.

동작 변화는 `nm -D`로 본 `__read_chk@GLIBC_2.4` 하나다(`pty.zig`의 `c.read`). 경위와 표는
`docs/decisions/project_zig_c_uapi_rule.md`의 ZU-M1 절에 있다.

### 실측 4 — 패키지의 첫 빌드 비용은 측정 편차 안이다

`terminal/.zig-cache`를 지운 `zig build`가 M1 전 74.2초, M1 뒤 67.9초다(translate-c 실행 파일 컴파일
포함, 패키지는 이미 `zig-pkg/`에 받은 뒤). 위험으로 본 "게이트마다 첫 체인이 내는 비용"은 잴 수 있는
크기가 아니었다. 게스트 바이너리는 10,963,008 → 10,963,352바이트(+344, fortify 래퍼).

### 실측 5 — 루트 게이트는 첫 판에 초록이다

17체인 3/3, `FAIL` 0줄, 1시간 1분 50초. `__read_chk`를 지나는 `pty`의 읽기와 fortify를 켠 `drm`이
부팅하는 모든 체인에서 섰다.

## 실측 (M2, 2026-10-24)

### 실측 6 — ghostty `3d07ef9`는 0.17 의존으로 그대로 서고, 우리 코드가 깨지는 자리는 47이다

호스트 macOS의 0.17.0으로 `terminal` · `init` 사본을 빌드해서 뽑고(plan의 "착수 전에 아는 것"), 컨테이너
0.17.0이 확인했다. ghostty 쪽에서 컴파일이 깨진 것은 둘뿐이다 — `effects.write_pty` 콜백의 인자가
`[]const u8`이 됐고, kitty `Placement.Location`에 `relative`(P=/Q= 부모 상대 placement)가 늘었다. 나머지
45는 Zig std가 없앤 것(`bufPrintZ` 11 · `dupeZ` 1 · `indexOfIgnoreCase` 1 · `@typeInfo(...).fields` 10 ·
`std.builtin.OptimizeMode` · `b.build_root` · `b.pathFromRoot` 9) · std 안의 어긋남(`waitpid`는 `*i32`인데
`W.*`는 `u32` — 8) · M0 뒤에 다시 들어온 `**` 5다. 그 다섯은 전부 2026-10-03 뒤의 WP · AU · BV · config_edit
코드다 — 컨테이너 컴파일러가 거부하지 않는 문법은 다시 들어온다. 이제 컨테이너가 0.17이라 게이트가 막는다.

착수 전 6("참조 구현이 고친 나머지는 우리 코드에 없다")은 그날은 맞았고 그 뒤 세 주 동안 `dupeZ` · `b.build_root` ·
`std.ascii.indexOfIgnoreCase`가 들어왔다. 신호를 기다리는 동안 코드는 멈춰 있지 않는다.

### 실측 7 — translate-c는 zon 두 줄만 바뀌었다 (결정 4 성립)

ghostty 0.17은 zon의 URL 대신 저장소 안 `pkg/translate-c`(wrapper)를 받고, wrapper가 codeberg 판
`translate_c-02ff0c5…`(2.0.0)와 `apple_sdk`를 받는다. `Translator.init(dep, .{ .name, .c_source_file, .target,
.optimize, .link_libc })` · `.mod` · `addIncludePath`가 그대로라 우리 `translateC`는 안 바뀌었다. wrapper를
거치지 않고 안쪽 패키지를 바로 받았다 — wrapper가 더 주는 것은 `addImportToModule` 하나이고 그것이 `translateC`다.

### 실측 8 — 0.17 `zig fmt`는 438줄 · 30파일을 바꾸고, 그중 84줄이 `@backingInt`다

`@intFromEnum` → `@backingInt` 84줄(옛 이름도 컴파일된다), 0.17이 `type`을 식별자로 허용해 `@"type"` → `type`
(`input_test.zig`의 `input_event`), 끝 쉼표 없는 여러 줄 호출을 한 줄로 합치기, 문자열 배열의 열 정렬. M0 실측 2의
61줄이 이 안에 있다. 고침과 따로 commit해서 diff를 갈랐다(plan 결정 M2-D).

### 실측 9 — terminal 바이너리가 4.6MB 커졌고 그 전부가 디버그 섹션이다

컨테이너 0.17, 캐시 없는 빌드: init `zig build` + `zig build test` 1분 14초, terminal `./prepare.sh`(빈 `zig-pkg`에
패키지를 다시 받고 translate-c · aro를 컴파일하는 것 포함) 2분 37초, 이어진 `zig build test` 4.5초.
`zig-out/bin/terminal`은 15,176,440바이트(M1 10,577,544). `size -A`로 보면 `.debug_*`가 12.0MB(`.debug_loc` 5.8MB ·
`.debug_info` 2.8MB · `.debug_line` 1.4MB), `.text` 2.1MB, `.rodata` 0.4MB — 커진 것은 0.17 컴파일러가 더 내는 디버그
정보다. `kernel/make_initrd.sh:154`가 strip을 안 하므로(패닉 trace의 심볼을 지키려고, TF-M4) 이 4.6MB는 initrd에 그대로
실린다. 이번에는 두고 HANDOFF에 적었다 — `.debug_loc`만 떼는 길(`strip --strip-debug`는 심볼은 남긴다)을 다음에 잰다.

### 실측 10 — 루트 게이트는 첫 판에 22/22다

고침 commit과 fmt commit을 함께 덮어 한 번 돌렸다(plan 결정 M2-D). `FAIL` 0줄, prebuild 364초 + lanes 305초 =
11분 12초(GF-M2 때 prebuild 약 4분 — 빈 `zig-pkg`에 패키지를 다시 받고 translate-c · aro를 처음 컴파일한 몫이다. 다음
게이트부터는 캐시가 있다). 호스트 0.17로 사본에서 뽑은 고침 표 밖의 오류는 컨테이너에서도 하나도 안 나왔다.
