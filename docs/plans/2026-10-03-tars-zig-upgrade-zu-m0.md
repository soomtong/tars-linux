# ZU-M0 — 배열 곱 `**` 25곳을 `@splat`으로

> 0.16에서 하는 milestone이다. 컴파일러는 그대로 0.16.0이고, 바뀌는 것은 문법 하나다. 동작은 바뀌지
> 않는다 — 모든 자리가 컴파일 시간에 값이 정해지는 초기값이다.

Goal: 0.17이 거부하는 `**`를 우리 코드에서 없앤다. 0.16의 두 `zig build test`가 그대로 서고,
0.17 `ast-check`에 `**` 오류가 0줄이다.

Architecture: `**`는 두 모양으로 쓰였다. 결과 타입이 보이는 배열 초기값(12줄)과, 테스트가 긴 문자열을
만드는 문자열 곱(13줄)이다. 두 번째는 `"a" ** n`이 포인터(`*const [n:0]u8`)인 반면 `@splat`은 배열
값을 만드므로, 슬라이스 자리에는 `&`를 붙인다. 모든 피연산자가 comptime이라 `&`는 정적 상수를 가리킨다.

---

## 무엇을 바꾸나

### 모양 1 — 배열 초기값(타입이 보인다)

| 자리 | 지금 | 바꾼 뒤 |
|---|---|---|
| `init/src/storage.zig:151` | `[_]u8{0} ** LABEL_LEN` | `@splat(0)` |
| `init/src/devices.zig:147` | `[_]u8{0} ** MAX_PATH` | `@splat(0)` |
| `init/src/config.zig:205` | `.name = [_]u8{0} ** TZ_NAME_MAX` | `.name = @splat(0)` |
| `init/src/control.zig:293` | `.path = [_]u8{0} ** 108` | `.path = @splat(0)` |
| `init/src/control_test.zig:63` | 같은 줄 | 같은 고침 |
| `init/src/net.zig:69` | `.name = [_]u8{0} ** 16` · `._pad = [_]u8{0} ** 14` | 둘 다 `@splat(0)` |
| `terminal/src/drm.zig:60` | `[_]u8{0} ** 32` | `@splat(0)` |
| `terminal/src/input.zig:443` | `[_]u8{0} ** 8` | `@splat(0)` |
| `terminal/src/image_test.zig:13` | `[_]u32{BG} ** (64 * 64)` | `@splat(BG)` |

`init/src/config_test.zig:214-215`(`var seen = [_]bool{false} ** N`)과 `control_test.zig:188`
(`const big = [_]u8{'x'} ** 100`)은 타입이 없는 선언이라 `var seen: [N]bool = @splat(false);` 모양으로
타입을 앞에 적는다.

### 모양 2 — 테스트의 문자열 곱

| 지금 | 바꾼 뒤 | 이유 |
|---|---|---|
| `f("a" ** N)` | `f(&@as([N]u8, @splat('a')))` | 슬라이스 자리 — `&` |
| `"stop " ++ "n" ** 32` | `"stop " ++ @as([32]u8, @splat('n'))` | `++`는 배열을 받는다 |
| `"a" ** 0` | `""` | 빈 문자열 그대로 |
| `const x = "a" ** N;` | `const x: [N]u8 = @splat('a');` 뒤 쓰는 자리에서 `&x` | 쓰는 자리를 읽고 정한다 |

자리: `environ_test.zig:165,171` · `config_test.zig:937-939,970` · `control_test.zig:76,82,83,98` ·
`services_test.zig:72,73,121`.

도움 함수(`rep('a', 64)` 같은 것)는 만들지 않는다. 파일 넷에 흩어진 13줄이라 이득보다 한 단계 더 읽는
비용이 크다.

`"a" ** n`이 주던 종단 0(`:0`)은 잃는다. 받는 쪽이 전부 `[]const u8`이라 쓰지 않는다 — 컴파일러가
확인해 준다(`[:0]const u8`을 받는 자리가 있으면 타입 오류가 난다).

## Task 1: 고친다

위 표대로 편집한다. 매 파일 뒤 `git diff --stat`, 지운 줄은 `git diff | rg '^-'`로 `**` 줄만 빠졌는지 본다.

## Task 2: 0.16으로 잰다(컨테이너, 몇 분)

```bash
make container
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c '(cd init && zig build && zig build test) && (cd terminal && zig build test)'
```

## Task 3: 0.17로 잰다(호스트, 몇 초)

```bash
Z=~/.local/zig/zig-aarch64-macos-0.17.0/zig
rg -n '\S \*\* ' --glob '*.zig' init terminal/src          # 0줄
for f in $(fd -e zig . init terminal/src); do $Z ast-check "$f"; done 2>&1 | rg 'error'
```

남는 오류는 `@cImport` 셋(`drm` · `font` · `input` — ast-check은 파일당 첫 오류에서 멈춘다)뿐이어야
한다. 그것은 M1의 몫이다.

## 끝났다고 말할 조건

- `rg '\S \*\* '`가 `init` · `terminal/src`에서 0줄.
- 0.16 컨테이너에서 init 빌드 · init 테스트 · terminal 테스트가 선다.
- 0.17 `ast-check`의 오류가 `@cImport`뿐이다.
- 루트 게이트는 돌리지 않는다 — 바뀐 값이 전부 comptime 초기값이고, 테스트가 그 자리를 지난다.
  M1의 루트 게이트가 이 milestone도 함께 덮는다.

## 한 대로 (2026-10-03)

Task 1은 모양 2에서 plan과 달라졌다. 표는 `++` 자리와 슬라이스 자리를 나눴지만, 문자열 곱 13줄을 전부
`&@as([N]u8, @splat('x'))` 한 모양으로 바꿨다. 배열 포인터는 문자열 리터럴과 같은 종류라 `++`의
피연산자로도, `[]const u8` 인자로도, `const long = ...` 뒤 `long ++ "..."`로도 그대로 쓰인다 — 자리마다
따질 것이 없어진다. 편집 전에 `/tmp`의 작은 테스트로 0.16 · 0.17 둘 다에서 확인했다. `"a" ** 0`만 `""`다.

`sd` 정규식 하나가 `Timezone.parse("a" ** 64)`의 호출 괄호까지 먹어 `parse&@as(...)`를 만들었고,
`git diff | rg '^[-+] '`로 읽다가 보고 손으로 고쳤다. diff는 12파일 25줄 더하기 · 25줄 빼기다.

Task 2(0.16 컨테이너, 1분 4초) — init 빌드 · init 테스트 · terminal 테스트가 섰다. 바꾼 자리를 지나는
`control_test` · `services_test` · `environ_test` · `config_test`(65자 timezone 거부 줄) · `image_test`가
로그에 찍혔다.

Task 3 — `**` 0줄. 0.17 `ast-check`의 오류는 `@cImport` 다섯(`drm` · `font` · `input` · `main` · `pty`)이다.
plan은 셋(`drm` · `font` · `input`)이라고 적었는데 틀렸다. 착수 전에 보인 셋은 `**`가 없는 `font` ·
`main` · `pty`였다. `**` 오류는 파싱 단계에서 나서 같은 파일의 `@cImport` 오류(AstGen 단계)를 가리므로,
`drm` · `input`의 `@cImport`는 `**`를 고친 뒤에야 보였다.
