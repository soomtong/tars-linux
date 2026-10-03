# TARS Zig Upgrade — Design

접두사: ZU

Status: 진행 중(2026-10-03) — M0 끝(`**` 25줄 → `@splat`, 실측 1 · 2). M1은 0.16에서 한다. M2는 ghostty의 0.17 전환이 업스트림에 들어간 뒤에 연다.

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
