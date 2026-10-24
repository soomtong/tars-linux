# ZU-M2 — 컨테이너 Zig를 0.17로, ghostty를 0.17 전환 커밋으로

Date: 2026-10-24
Design: `docs/specs/2026-10-03-tars-zig-upgrade-design.md` 결정 1 · 4, 위험 2, Milestone ZU-M2
Status: 끝났다(2026-10-24). 루트 게이트 22/22. 경과는 맨 아래 "한 대로".

> 신호가 왔다. ghostty PR #14519 "Update to Zig 0.17"이 2026-10-20에 병합됐고(merge commit `3d07ef9`),
> main의 `build.zig.zon`이 `minimum_zig_version = "0.17.0"`이다. Zig 0.17.0은 2026-10-01에 나왔고 호스트
> macOS에는 `/opt/homebrew/bin/zig`로 이미 있다. 2026-10-20 확인 때는 PR이 open이었다.

Goal: 컨테이너의 Zig가 0.17.0이고 `terminal/ghostty-src`가 `3d07ef9`다. 두 `zig build` · `zig build test`와
루트 게이트 22체인이 선다. 0.16을 적은 문서가 0.17을 말한다.

Architecture: 바뀌는 층은 셋이다. 도구(`devcontainer/Dockerfile`의 `ZIG_VERSION`), 의존(ghostty SHA ·
translate-c 패키지 판), 우리 코드(0.17이 없앤 std 선언 · ghostty가 바꾼 API 둘 · M0 뒤에 다시 들어온 `**`).
코드 고침은 전부 기계적이고 자리가 확정돼 있다(아래 표). 기능은 하나도 바뀌지 않는다.

---

## 착수 전에 아는 것 (2026-10-24, 호스트 0.17로 사본을 빌드해서)

방법: `terminal`과 `init`을 `/tmp/zu2`에 복사하고 `ghostty-src`만 `3d07ef9` tarball로 바꾼 뒤 호스트
`zig 0.17.0`(aarch64-macos)으로 게스트 바이너리(`x86_64-linux`)를 빌드했다. 컴파일러가 거부하는 것은 이것으로
전부 보이지만, `linux/input.h`를 번역하는 프로그램 다섯(`terminal` · `input_test` · `status_test` ·
`pointer_test` · `touchpad_test`)은 macOS에 그 헤더가 없어 컴파일을 못 봤고, Linux 시스템 콜을 직접 부르는
검사(`logline_test`, init 검사 전부)는 macOS에서 실행이 안 된다. 그 여섯은 Task 5가 컨테이너에서 본다.

1. ghostty `3d07ef9`는 0.17 의존으로 그대로 선다. `ghostty-vt` 모듈 이름 · 루트(`src/lib_vt.zig`)가 같고,
   simd(highway · simdutf) · uucode · wuffs가 빌드된다. `2602886`에서 1,312 커밋 뒤이고 `src/terminal`은
   108 M · 25 A · 1 R(328 커밋)이다. 새로 들어온 것은 kitty clipboard · dnd · 상대 placement, `paste.zig`,
   `xt_checksum.zig`, `search/terminal.zig`, OSC 파서 셋이다. 우리 코드가 쓰는 선언 열다섯(`Pin` ·
   `Screen` · `Selection` · `TerminalStream` · `search.Screen` · `RenderState` · `input.encodeMouse` …)
   가운데 컴파일이 깨지는 것은 아래 3의 둘뿐이다.
2. translate-c. ghostty는 0.17에서 zon의 URL · hash 대신 저장소 안 `./pkg/translate-c`(wrapper)를 받고,
   그 wrapper가 codeberg 판 `translate_c-02ff0c5…`(2.0.0, aro도 codeberg)와 `../apple-sdk`를 받는다.
   `Translator.init(dep, .{ .name, .c_source_file, .target, .optimize, .link_libc })`와 `.mod` ·
   `addIncludePath`는 그대로라 우리 `translateC`는 한 글자도 안 바뀐다 — design 결정 4("M2는 zon 두 줄만")가
   성립한다. 새 판은 `optimize`를 `std.lang.Optimize`로 받는다.
3. 0.17이 거부하는 우리 코드와 고침 모양(사본에서 전부 적용해 섰다).

| 무엇 | 자리 | 고침 |
|---|---|---|
| 배열 곱 `**` (M0 뒤 WP · AU · BV · config_edit이 다시 넣었다) | `terminal/src/layout.zig:262` · `layout_test.zig:146`, `init/src/audio.zig:332` · `config_edit_test.zig:147` · `version_test.zig:35` | M0 plan의 표대로 `@splat`. 0.17 파서는 `**`를 `*` `*`로 읽어 "binary operator '*' has whitespace on one side"라고 말한다 |
| `Allocator.dupeZ` 삭제 | `terminal/src/clipboard_test.zig:9` | `alloc.dupeSentinel(u8, s, 0)` — sentinel이 마지막 인자 |
| `std.fmt.bufPrintZ` 삭제 | `terminal/src/main.zig:1941` · `:2287`, `init/src/install.zig` 7곳(79 · 127 · 179 · 409 · 614 · 624 · 625) · `storage.zig:141` · `services_test.zig:49` | `std.fmt.bufPrintSentinel(buf, fmt, args, 0)` |
| `std.ascii.indexOfIgnoreCase` 삭제 | `init/src/audio.zig:359` | `std.ascii.findIgnoreCase` |
| `linux.waitpid` · `wait4`의 status가 `*i32`, `linux.W.*`는 여전히 `u32` | 시스템 콜 자리 8 — `firewall.zig:46` · `main.zig:903` · `power.zig:199` · `install.zig:323` · `config_front.zig:155` · `audio.zig:263` 등 | `var status: u32`는 두고 호출에 `@ptrCast(&status)`. `W.*` 호출 12자리는 안 바뀐다 |
| `@typeInfo(T).@"struct".fields` 삭제 — `field_names` · `field_types` 두 슬라이스로 갈렸다. `.@"enum".fields`도 `field_names` | `init/src/config_edit.zig:34` · `:53` · `:76` · `:94`, `reload.zig:57` · `:72` · `:82` · `:92` · `:132`, `reload_test.zig:41` | 이름만 쓰는 루프는 `inline for (info.field_names, 0..) \|f_name, i\|`, 타입도 쓰는 루프는 `inline for (info.field_names, info.field_types) \|f_name, f_type\|`. 안 쓰는 capture는 오류다(`reload.zig:72`가 그랬다) |
| `std.builtin.OptimizeMode` → `std.lang.Optimize`, 멤버가 `.debug` · `.safe` · `.fast` · `.small` | `terminal/build.zig:38` · `:41`(`.ReleaseSafe`) · `:430`, `init/build.zig:33` · `:55` · `:69` · `:85`(`.ReleaseSafe`) | 옛 이름은 decl alias라 `.ReleaseSafe` 리터럴은 "no field named"로 거부된다. `.safe` |
| `b.build_root` 삭제(BV-M0가 2026-10-20에 넣었다) | `init/build.zig:360` | `b.root.root_dir.handle.readFileAlloc(b.graph.io, "../VERSION", b.allocator, .limited(4096))` — ghostty `build.zig:28`과 같은 모양 |
| `b.pathFromRoot` 삭제 | `init/build.zig:365` | `b.pathResolve(&.{ b.root.toString(b.allocator) catch @panic("OOM"), ".." })`. 사본은 `.git`이 없어 git 가지는 못 봤다 — Task 5가 버전 글자에 `+<sha>`가 붙는지 본다 |
| ghostty: `effects.write_pty` 콜백이 `[]const u8`을 받는다(전에는 `[:0]const u8`) | `terminal/src/vt.zig:120` | 매개변수 타입만. 본문은 `pushReply(bytes)`라 종단을 안 쓴다 |
| ghostty: kitty `Placement.Location`에 `relative`(P=/Q= 부모 상대 placement)가 늘었다 | `terminal/src/vt.zig:1029`의 `switch (p.location)` | `.virtual, .relative => continue`. ghostty 자신의 storage 순회(`graphics_storage.zig:483` · `:608`)도 같다. 상대 placement를 그리는 것은 비목표 |

4. 0.17 `zig fmt`가 바꾸는 것: init 250줄 · 24파일, terminal 188줄 · 6파일 = 438줄 · 30파일. 그중 84줄이
   `@intFromEnum` → `@backingInt` 자동 치환이고 나머지가 M0 실측 2의 빈 줄 · 줄 바꿈이다. 옛 `@intFromEnum`도
   컴파일된다. 고침과 섞이면 diff를 못 읽으므로 따로 commit한다(Task 6).
5. 호스트에서 돈 검사: terminal의 `zig build test` 72단계 가운데 61이 섰다 — `layout` · `battery` · `dictation` ·
   `clipboard` · `font` · `hangul` · `image` · `pacing`이 통과, 못 본 것은 위의 여섯이다. init은 게스트 네
   바이너리(`init` · `tars-config` · `tars-install` · `tars-service`)가 전부 섰다.
6. 0.16을 적은 자리(코드 · 문서). `check.sh:11`(zig-pkg 주석) · `devcontainer/Dockerfile:476` · `terminal/build.zig.zon:5` ·
   `:8-10`(ZU-M1 주석) · `docs/guides/lessons.md:901` · `:1080` · `:1084` · `:1085` · `docs/decisions/project_zig_c_uapi_rule.md:66-67` ·
   `:110` · `docs/study/2026-08-11-zig-0.16-crash-course.md`(머리 · `:1262`) · `HANDOFF.md` · 소스 주석 넷(`terminal/src/input_test.zig:325` ·
   `init/src/devices_test.zig:96` · `storage.zig:16` · `disk.zig:78`). 소스 주석이 말하는 "0.16에 없다"는 0.17에도 그대로다 —
   `std.time.Timer` · `std.posix.getenv`는 0.17 std에도 없고 `std.os.linux.pread`는 있다(`linux.zig:1720`). "0.16부터 없다"로 고친다.
7. 도구. `make container`는 이미지가 없을 때만 굽는다 — 다시 구울 때는 `docker build -t tars-devcontainer devcontainer/`를
   직접 친다. zig 층(`Dockerfile:476`)이 sysroot 층들 뒤라 캐시가 살아 zig tarball(약 50MB) 받기만 한다.
   `vendor_libghostty_vt.sh`는 `ghostty-src`가 없을 때만 받으므로 SHA를 바꾼 뒤 `rm -rf terminal/ghostty-src`가 필요하다.
   `terminal/zig-pkg`에는 0.16 판 패키지 28개(`translate_c-0.0.0` · `libxev` · `vaxis` …)가 남는다 — 한 번 `rm -rf`해서
   0.17 판만 다시 받는다(네트워크가 있을 때).
8. 고정 SHA는 전환 커밋 `3d07ef9`다(main 끝 `8ef0ec1`이 아니다). 0.17을 품은 가장 작은 상위 집합이고, 위험 2("0.17 말고
   다른 것도 따라온다")를 그만큼 줄인다. 뒤의 fix가 필요하면 그때 SHA를 올린다.

## 결정

### M2-A — translate-c는 ghostty의 wrapper가 아니라 그 안의 패키지를 바로 받는다

wrapper(`pkg/translate-c`)는 `apple_sdk`를 함께 끌고 우리에게 더 주는 것은 `addImportToModule` 도움 함수 하나다.
우리 `translateC`가 이미 그 역할이다. zon의 URL · hash만 wrapper가 쓰는 판으로 바꾼다 —
`https://deps.files.ghostty.org/translate_c-02ff0c523fb92a38939b04d0145c4a9602a74d56.tar.gz`,
`translate_c-2.0.0-Q_BUWltOBwBYABF84EUL208pIFeUIwbBs29FmVBaafN5`.

### M2-B — waitpid는 호출 자리의 `@ptrCast`로 맞춘다

std 안에서 `waitpid`(`*i32`)와 `W.*`(`u32`)가 어긋난 것이라 어느 쪽을 택해도 cast가 남는다. 시스템 콜 자리 8이
`W.*` 자리 12보다 적고, 상태값을 비트로 읽는 `W.*` 줄이 그대로여서 읽는 사람이 바뀐 곳을 적게 본다.

### M2-C — `@typeInfo` 루프는 쓰는 것만 돈다

이름만 쓰는 루프(`reload.zig:72` · `config_edit.zig:34` · `:94` · `reload_test.zig:41`)는 `field_names`만,
`f.type`도 쓰는 루프(`reload.zig:82` · `:92` · `:132`, `config_edit.zig:53` · `:76`)는 두 슬라이스를 함께 돈다.
0.17은 안 쓰는 capture를 오류로 본다.

### M2-D — `zig fmt`는 고침 뒤 따로 commit, 게이트는 그 뒤 한 번

고침 commit → fmt commit → 루트 게이트. 게이트가 10분이라 두 번 돌릴 이유가 없고, 빨개지면 fmt commit을 되돌려
가른다. 이 저장소에 fmt 게이트는 없다(M0 실측 2) — 이번에도 안 만든다.

### M2-E — crash course는 다시 쓰지 않는다

`docs/study/2026-08-11-zig-0.16-crash-course.md`는 0.16을 배우려고 쓴 글이고 1,600줄이다. 머리에 "컨테이너는
0.17이다. 0.17이 바꾼 것은 ZU design 실측 N과 이 plan의 표"를 한 단락 더하고 `:1262`의 `minimum_zig_version` 인용만
고친다.

## Task 1: 도구 (몇 분)

`devcontainer/Dockerfile:476`을 `ZIG_VERSION=0.17.0`으로. `docker build -t tars-devcontainer devcontainer/`.
확인: `docker run --rm tars-devcontainer zig version` → `0.17.0`.

## Task 2: ghostty를 다시 받는다 (몇 분)

`terminal/vendor_libghostty_vt.sh:6`의 `GHOSTTY_SHA`를 `3d07ef9e28c4af05065b9e2e546b8ac8f9b62df0`으로.
`rm -rf terminal/ghostty-src terminal/zig-pkg` 뒤 컨테이너에서 `cd terminal && ./prepare.sh`.
확인: `rg minimum_zig terminal/ghostty-src/build.zig.zon` → `"0.17.0"`.

## Task 3: zon과 두 `build.zig`

- `terminal/build.zig.zon`: `minimum_zig_version = "0.17.0"`, translate_c URL · hash(M2-A), ZU-M1 주석을
  "0.17 판. ghostty `pkg/translate-c`가 받는 것과 같은 판"으로.
- `terminal/build.zig`: `std.builtin.OptimizeMode` → `std.lang.Optimize`(38 · 430), `.ReleaseSafe` → `.safe`(41).
- `init/build.zig`: `.ReleaseSafe` → `.safe` 4, `buildVersion`의 `b.build_root` · `b.pathFromRoot`(착수 전 3의 표).

## Task 4: 소스 고침 (착수 전 3의 표, 약 47자리)

파일 단위로 넣고 매 파일 뒤 호스트 0.17 `ast-check`를 돈다(파서 오류가 같은 파일의 다른 오류를 가린다 — M0 실측 1).
`**`는 M0 plan의 치환표를 그대로 따른다. vt.zig의 `.relative`에는 "상대 placement는 그리지 않는다(ZU-M2)" 한 줄.

## Task 5: 컨테이너에서 세운다 (각 몇 분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c \
  'cd init && rm -rf .zig-cache zig-out && zig build && zig build test && \
   cd ../terminal && rm -rf .zig-cache zig-out && time zig build && zig build test'
```

- 호스트가 못 본 여섯이 여기서 처음 컴파일 · 실행된다. 남는 오류를 표에 더한다.
- `init`의 버전 글자: `strings init/zig-out/bin/init | rg '^0\.1\.0'`에 `+<sha>`(또는 dirty 표식)가 붙는지 — `pathResolve`가 맞다는 증거.
- 캐시를 지운 terminal 빌드 시간과 `zig-out/bin/terminal` 크기를 M1(67.9초 · 10,577,544바이트대)과 비교한다.

## Task 6: `zig fmt` (따로 commit)

컨테이너에서 `cd init && zig fmt build.zig src && cd ../terminal && zig fmt build.zig src`. `git diff --stat`으로
착수 전 4의 438줄 · 30파일과 대조하고, `git diff | rg '^[-+].*@(backingInt|intFromEnum)' | wc -l`로 84 × 2를 확인한다.
그 밖의 줄은 빈 줄 · 줄 바꿈이어야 한다 — 다른 것이 있으면 적는다.

## Task 7: 문서

착수 전 6의 자리 전부. `check.sh:11`은 "Zig의 프로젝트 로컬 패키지 캐시"로(버전을 빼는 쪽이 다음에 또 낡지 않는다).
`project_zig_c_uapi_rule.md:66`에 translate-c 판이 바뀐 사실 한 줄. design에 실측 6~N(이 plan의 착수 전 1 · 3 · 4 · 5와
Task 5 · 6의 값). `HANDOFF.md`의 "열린 대기 조건" 절을 지운다.

## Task 8: 루트 게이트 (약 10분)

`./check.sh` — 22/22. 빨개지면 `out/gate-logs/<시각>/`의 그 체인 로그부터 보고, fmt commit을 되돌려 가른다(M2-D).

## 끝났다고 말할 조건

- 컨테이너 `zig version`이 `0.17.0`, `terminal/ghostty-src/build.zig.zon`이 `"0.17.0"`, `GHOSTTY_SHA`가 `3d07ef9…`.
- `rg -n 'bufPrintZ|dupeZ|indexOfIgnoreCase|\.fields\b|build_root|pathFromRoot|std\.builtin|ReleaseSafe' init terminal/src terminal/build.zig`가
  0줄(`ghostty-src` · `zig-pkg` 제외). 호스트 0.17 `ast-check` · `fmt --check`가 두 `src`에서 0줄.
- 두 `zig build` · `zig build test`, 루트 게이트 22/22.
- 0.16을 적은 자리가 0.17을 말한다(`rg '0\.16' --glob '!docs/plans/**' --glob '!docs/specs/**'`로 남은 것이 "0.16부터 없다" 류의 역사 서술뿐).

## 닫을 때(lead의 몫)

design `Status:`를 "끝났다(날짜)"로. `docs/guides/completed.md` 표 끝에 ZU 한 행. `docs/decisions/`에 기억 한 파일
(0.16 → 0.17에서 깨진 것의 목록과 "컨테이너 컴파일러가 거부하지 않는 문법은 다시 들어온다"는 교훈) + `MEMORY.md` 한 줄.
`HANDOFF.md`. gh-pages `data.js`의 기능 목록(순서는 `site/README.md`).

## 한 대로 (2026-10-24)

Task 1~4는 plan대로. Task 4에서 셸을 거친 치환 둘(`'1'` · `'a'` 문자 리터럴)이 따옴표를 잃어 `@splat('';`로 들어갔고,
`reload.zig:72`는 `comptime`이 붙은 줄이라 이름만 도는 모양으로 바꾸는 패턴이 비껴갔다 — 호스트 `ast-check`가 셋을 잡았고
16진 이스케이프(`\x27`)로 다시 넣었다. 끝난 뒤 두 `src`의 `ast-check` 0줄.

Task 5 — 컨테이너 0.17에서 init(1분 14초, 검사 포함) · terminal(`prepare.sh` 2분 37초 + `zig build test` 4.5초) 전부 섰고,
호스트가 못 본 여섯(`terminal` · `input_test` · `status_test` · `pointer_test` · `touchpad_test` · `logline_test`)도 첫 판에
통과했다. 버전 글자 `0.1.0+51fac4d-dirty` — `pathResolve`의 git 가지가 맞다. 표 밖의 오류는 없었다. terminal 바이너리는
15,176,440바이트(M1 10,577,544)이고 커진 것은 전부 디버그 섹션이다(design 실측 9).

Task 6 — fmt diff 30파일 · +271/−167, `@backingInt` 84줄(= `@intFromEnum` 지운 84줄), 그 밖은 `@"type"` → `type`과 줄 정렬.
고침은 stage, fmt는 working tree로 갈라 두고 commit 둘로 냈다.

Task 7 — 착수 전 6의 자리 전부. crash course는 결정 M2-E대로 머리 한 단락과 zon 인용 한 줄. design에 실측 6~10.
기억은 `docs/decisions/project_zig_upgrade.md`.

Task 8 — 22/22, prebuild 364초 + lanes 305초(design 실측 10).
