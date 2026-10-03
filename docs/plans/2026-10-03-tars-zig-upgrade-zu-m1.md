# ZU-M1 — `@cImport` 다섯을 translate-c 패키지로

> 0.16에서 하는 milestone이다. 0.17이 없앤 `@cImport`를, 0.17이 권하는 모양(translate-c 패키지의
> `Translator`)으로 지금 옮긴다. 패키지는 ghostty가 0.16에서 이미 쓰는 판을 그대로 받는다.

Goal: `terminal/src`에서 `@cImport`가 0줄이 되고, 0.16에서 게스트 바이너리 · 호스트 검사 · 루트 게이트가
지금처럼 선다. M2는 zon의 URL · hash만 codeberg 판으로 바꾸면 된다.

Architecture: C 헤더 번역이 Zig 소스(`@cImport`)에서 `build.zig`로 옮겨 간다. 번역 결과는 모듈이고, 각
파일은 `@import("<이름>")`으로 받는다. 번역은 대상(target)마다 따로다 — 같은 헤더라도 x86_64 게스트와
arm64 호스트의 glibc · 커널 헤더가 다르기 때문이다.

---

## 착수 전에 아는 것 (2026-10-03, 패키지 소스를 읽어서)

1. 패키지: `https://deps.files.ghostty.org/translate_c-80f8b6e4f45a303268717d8e5f4f91d7837138bb.tar.gz`,
   hash `translate_c-0.0.0-Q_BUWmU6BwB_9JKG2l2W7i_mhmYWeRseTGBEHi_YlV5f`, `minimum_zig_version = 0.16.0`.
2. `Translator.init(dep, .{ .name, .c_source_file, .target, .optimize, .link_libc = true })` → `.mod`.
   include 경로는 `addIncludePath`, define은 `defineCMacro`.
3. 패키지도 fortify를 켠다. `src/main.zig:233` — `optimize`가 ReleaseSafe면 `-D_FORTIFY_SOURCE=2`를
   붙인다. 그리고 그 인자는 우리가 주는 `defineCMacro` · `extra_args`보다 뒤에 붙는다 — 명령줄로
   `_FORTIFY_SOURCE=0`을 줘도 진다. `drm.zig:21`이 기대한 "옮기면 저절로 필요 없어진다"는 그대로는
   성립하지 않는다. 끄는 길은 둘이다.
   - (가) stub 헤더 안의 `#undef _FORTIFY_SOURCE`. 소스 안의 지시문은 명령줄 define 뒤에 처리된다.
     지금의 `@cDefine("_FORTIFY_SOURCE", "0")`과 같은 자리다.
   - (나) 번역만 `.optimize = .Debug`. 번역 모듈은 선언뿐이라 실행 파일의 최적화와 무관하다.
4. 첫 빌드가 translate-c 실행 파일(aro 포함)을 컴파일한다. 루트 게이트는 시작에 `terminal/.zig-cache`를
   지우므로(`check.sh:15`) 게이트마다 첫 체인이 한 번 낸다.
5. 누가 무엇을 쓰나.

| 파일 | 헤더 | 대상 | fortify 우회 |
|---|---|---|---|
| `drm.zig` | `fcntl.h` · `sys/ioctl.h` · `sys/mman.h` | 게스트 | 있음 |
| `pty.zig` | `pty.h` · `sys/ioctl.h` · `unistd.h` | 게스트 (`terminal` · `pty_test`) | 있음 |
| `main.zig` | `poll.h` | 게스트 | 있음 |
| `font.zig` | `stb_truetype.h`(`vendor/`) | 게스트 · 호스트(`font_test`) | 없음 |
| `input.zig` | `linux/input.h` | 게스트 · 호스트(`input_test` · `status_test`) | 없음 |

## 결정

### M1-A — 파일마다 번역 모듈 하나

`c_drm` · `c_pty` · `c_poll` · `c_stb_truetype` · `c_input`. 지금 `@cImport` 하나가 한 파일의 이름공간이고,
`main.zig:19`가 "헤더를 통째로 끌어오면 이름 충돌만 는다"며 일부러 좁혀 둔 것을 지킨다. 한 모듈로 합치면
`input.zig`의 `pub const c`(검사가 `KEY_*`를 읽는다)에 glibc 전체가 섞인다.

### M1-B — `build.zig`에 도움 함수 하나

`fn translate(b, tc, name, header_text, target, optimize) *std.Build.Module` — stub 헤더를
`b.addWriteFiles().add(name ++ ".h", header_text)`로 만들고 `Translator.init`의 `.mod`를 돌려준다.
`font` · `input`은 게스트 · 호스트로 두 번 부른다. 받는 쪽은 `m.addImport("c_input", ...)`.

### M1-C — fortify는 (가)부터 잰다

(가)가 지금 코드와 같은 뜻이고 이유가 헤더 한 줄에 붙어 있다. (나)는 번역의 다른 매크로(`-O2`가 켜는
`__OPTIMIZE__` 분기)까지 바꾼다. (가)가 안 되면 (나)를 재고 결과를 적는다. 어느 쪽이든 `drm.zig`의
GL-M3 설명은 새 사실로 고쳐 쓴다.

## Task 1: 패키지를 받는다

`terminal/build.zig.zon`의 `dependencies`에 `.translate_c = .{ .url, .hash }`(착수 전 1). lazy로 두지
않는다 — 모든 빌드가 쓴다. 컨테이너 안 `zig build`가 `terminal/zig-pkg/`에 받는다(커밋 안 함, 이미
`.gitignore`).

## Task 2: `build.zig`에 번역을 넣고 다섯 파일을 옮긴다

M1-B의 함수 · 모듈 일곱(게스트 다섯 + 호스트 둘) · `addImport`. 파일마다 `const c = @cImport(...)`를
`const c = @import("c_drm");` 모양으로 바꾼다. 이름 `c` · `stb`는 그대로 둬서 나머지 줄이 안 바뀌게 한다.
`execv` · `setenv` · `open` · `read`의 직접 선언은 그대로 둔다 — 번역기가 같아도 시그니처 문제는 같다.

## Task 3: fortify를 잰다 (컨테이너, 각 몇 분)

1. 우회 없이 ReleaseSafe로 `zig build` — 실패를 기대한다. 실패 줄을 적는다(GL-M3의 `C import failed`가
   패키지에서는 어떤 모양인지).
2. (가) stub 세 개에 `#undef _FORTIFY_SOURCE` — 선다를 기대한다.
3. (가)가 안 서면 (나).

## Task 4: 잰다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c \
  'cd terminal && rm -rf .zig-cache && time zig build && zig build test'
```

- `rm -rf .zig-cache` 뒤의 시간을 M1 전(`a4953c0`)과 비교한다 — 착수 전 4의 비용.
- 게스트 바이너리 크기를 M1 전과 비교한다(`zig-out/bin/terminal`, GL-M3 기준 10,577,200바이트대).
- 0.17 `ast-check`가 `init` · `terminal/src` 전부에서 오류 0줄.

## Task 5: 루트 게이트 (약 1시간)

M0도 함께 덮는다. 끝나면 `FAIL` 0줄과 걸린 시간을 적는다.

## Task 6: 문서

`drm.zig`의 GL-M3 설명, `png.zig:7-8`의 `@cImport` 언급, `build.zig:182 · 197`의 `@cImport` 주석,
`docs/decisions/project_zig_c_uapi_rule.md`에 착수 전 3과 Task 3의 결과. design의 실측.

## 끝났다고 말할 조건

- `rg '@cImport\(' terminal/src`가 0줄이고, 0.17 `ast-check` 오류가 0줄.
- 0.16에서 `zig build` · `zig build test` · 루트 게이트가 선다.
- fortify를 끄는 자리가 몇 개 남았고 왜인지가 한 곳에 적혀 있다.

## 한 대로 (2026-10-03)

Task 1 · 2는 plan대로 했다. Task 2에서 Python으로 `build.zig`에 넣은 Zig 여러 줄 문자열의 `\\`가
게스트 블록에서 `\` 하나로 들어갔다(Python 문자열 이스케이프). `rg '#include'`로 보고 `sd`로 고쳤다.

Task 3은 plan과 갈렸다. 1(우회 없음)의 에러가 셋이 아니라 `c_poll` 하나였다(design 실측 3). 그래서 2는
"stub 셋에 `#undef`"가 아니라 "`c_poll` 하나에 `#undef`"로 했고 그것으로 섰다. (나)는 재지 않았다.

Task 4 — 캐시를 지운 빌드 67.9초(M1 전 74.2초), 게스트 바이너리 +344바이트, `zig build test` 통과,
0.17 `ast-check` 오류 0줄, `rg '@cImport\('` 0줄(design 실측 4).

Task 6 — `drm.zig`의 GL-M3 설명(20줄)을 세 줄로 줄이고 경위는 `project_zig_c_uapi_rule.md`의 새 절로
옮겼다. `pty` · `main` · `png` · `input_test` · `build.zig`의 `@cImport` 언급을 번역 모듈 이름으로 고쳤다.

Task 5 — 루트 게이트 17체인 3/3, `FAIL` 0줄, 1시간 1분 50초(TG-M3 뒤 1시간 1분 25초). M0도 함께 덮었다.
