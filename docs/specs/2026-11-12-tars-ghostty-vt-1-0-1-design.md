# TARS Ghostty VT 1.0.1 — Design

접두사: GU

Date: 2026-11-12
Status: 설계(2026-11-12). 구현 전 — 다음 판에 싣는다(사용자, 2026-11-12). plan은 `docs/plans/2026-11-12-tars-ghostty-vt-gu-m0.md`.

계기: 사용자(2026-11-12): "libghostty 1.0.1 패치가 올라왔습니다. 성능 향상이 두드러진 부분이 있어서 우리 프로젝트에도 반영하는
것이 어떨까 검토해주세요." → memset/memcpy 변경이 우리와 무관하다는 lead의 첫 답에 "이런 내용은 중요하다. 왜 무관한가?" →
"1번 확인하고 design에 적어줘."

관련 문서: GV design(`2026-11-10-tars-ghostty-vt-design.md` — vt-1.0.0으로 올린 절차와 결정 2 "태그가 가리키는 SHA로 고정") ·
기억 `reference_ghostty_source`(빌드 입력 `terminal/ghostty-src`와 `vendor_libghostty_vt.sh`의 `GHOSTTY_SHA` · `GHOSTTY_SHA256`) ·
`measurements.md` 96 · 97 · 98(키 하나의 프레임 구간).

## 한 줄 요약

`terminal`이 잡는 ghostty를 태그 `vt-1.0.0`(`0fa3d57`)에서 `vt-1.0.1`(`108cacb`)로 올린다. 우리 코드는 안 바뀐다. 얻는 것은 resize ·
scrollback 쪽 버그 수정이고, 라이브러리의 처리량 향상(5~9%)은 우리 화면 시간에서 몫이 작다. 1.0.1이 더한 "memcpy를 glibc로 돌리기"는
라이브러리를 올려도 우리에게 안 온다 — 우리 바이너리는 그 대상 조건을 모두 갖췄으므로 켜려면 우리 root에서 따로 켠다(결정 2, 실기 측정 뒤).

## 확인 (2026-11-12, HEAD `2b484ea`)

저장소는 건드리지 않았다. scratchpad의 `terminal` · `shared` 사본에서 컨테이너(`tars-devcontainer`, Zig 0.17.1, aarch64)로 쟀다.

1. 태그. `vt-1.0.1`은 서명된 annotated 태그(`e9dc690`, 메시지 "libghostty-vt 1.0.1")이고 커밋 `108cacb17ed8990840cd14abfce43d8ed8503ca1`
   (2026-11-11, "libghostty-vt: set version to 1.0.1-dev")을 가리킨다. `vt-1.0.0`보다 91커밋 앞, 69파일. GitHub release 문서는 없다.
   태그 커밋의 `build.zig`도 `lib_version = "1.0.1-dev"`다 — `vt-1.0.0`도 `"1.0.0-dev"`였으니 ghostty의 관행이고, 우리는 Zig 모듈만 써서 안 읽는다.
   archive tarball(`archive/108cacb….tar.gz`)의 sha256은 `2c276d3e62cb15fb38f0d7f621f199029d1d4df86538096c6bec2a107cad7159`.
   `build.zig.zon`의 바뀐 의존은 lazy인 iterm2 테마 하나뿐이라 우리 zon은 안 바뀐다.
2. 빌드 · 검사. ghostty만 바꾼 사본에서 `zig build -Doptimize=ReleaseSafe` 성공(144초), `zig build test` 89/89 단계 — GV-M0 Task 4-1과 같은 숫자.
   우리 코드에서 고칠 곳은 없다.
3. 처리량. 우리 `vt.zig`와 같은 모양(155x47, `max_scrollback_lines` 1000, 64KB마다 `nextSlice` 뒤 `RenderState.update`)으로 64MB를
   다섯 번씩 먹여 가장 빠른 값. 두 회차가 같았다.

   | 작업 | 1.0.0 | 1.0.1 | 차이 |
   |---|---|---|---|
   | A `ls --color`식 스크롤(SGR 섞인 줄) | 309 MB/s | 336 MB/s | +8.6% |
   | B 전체 화면 다시 그리기(CUP · SGR · EL) | 181 MB/s | 189 MB/s | +4.6% |
   | C 잘못된 UTF-8 섞인 출력 | 169 MB/s | 184 MB/s | +8.5% |

   해당 커밋: `endUpdate`의 style-run 처리(`96d3798` · `15a4432` · `f28124c`, A), CSI 숫자 파싱(`691d3f3`, B), SIMD UTF-8 오류
   경로(`c1f4409`, C). 이 숫자는 aarch64다 — 게스트(x86_64)의 절대값은 다르다. 바뀐 코드는 대부분 아키텍처와 상관없는 Zig라 방향은 같다고 본다.
4. 우리 화면에서의 몫. 키 하나의 프레임에서 라이브러리 `update`는 0.04ms(`cells()`의 6%, `measurements.md` 97)이고, `seq 1 200000`
   약 1.1초에서 vt 처리는 수 ms다(1.3MB). 3의 향상은 체감 밖이다.
5. 버그 수정 중 우리에게 걸리는 것: 열이 느는 resize에서 매달린 pin(`1b8b3f5`, 우리는 pane resize를 한다), 행이 늘고 열이 줄 때
   scrollback이 안 내려오던 것(`321a32a`), resize 뒤 남던 프롬프트(`8ad3f60`), render 갱신 실패 뒤 dirty 행 다시 시도(`3e29fcd`, OOM
   경로), kitty 이미지 교체 때 전송이 끝날 때까지 옛 이미지 유지(`c4b91fe`), 가지치기한 page 메모리 재사용(`d0addb9`).
6. `src/quirks_memset.zig`(338 → 591줄)의 두 갈래.
   - 손으로 짠 SIMD `memset` 덮어쓰기: x86_64 · Darwin · 동적 glibc에서는 꺼진다(같은 파일의 `enabled`). 우리와 무관하다.
   - 새 `Glibc` 절: 동적 glibc 실행 파일 · 공유 라이브러리에서 `memset` · `memcpy` · `memmove`를 glibc 구현으로 돌린다. 까닭(파일 주석) —
     Zig는 compiler_rt를 바이너리 안에 정적으로 넣고 그 안에 이 함수들의 weak 정의가 있다. 바이너리 안의 정의는 공유 라이브러리의 것을
     늘 이기므로 glibc를 링크해도 glibc의 것은 안 불린다. glibc는 실행 중에 CPU를 보고 고르지만(IFUNC) compiler_rt는 컴파일 때 고정이라
     `-Dcpu=baseline` x86_64에서는 SSE2다. ghostty 실측(Ryzen 7 5800X, glibc 2.42): baseline에서 ASCII 6~10%, erase · resize 4% 빠르고,
     AVX2 native 빌드에서는 차이가 없다. 켜는 방법은 strong 심볼 `memset` 등을 정의해 버전 붙은 glibc 심볼로 `jmp`하는 asm이다
     (`.symver ghostty_glibc_memset, memset@GLIBC_2.2.5` 꼴, 셋 다 `.hidden`).
7. 6의 `Glibc` 절은 Zig 모듈로 받는 우리에게 안 온다. `src/lib_vt.zig:177`이 `if (@import("root") == lib)` 안에서만
   `_ = @import("quirks_memset.zig")`를 하고, 우리 바이너리의 root는 `terminal/src/main.zig`다. 파일 주석도 공유 코드에서 import하지 말라고
   한다(Zig 모듈을 받는 쪽 바이너리에 export를 넣지 않으려고).
8. 그런데 우리 `terminal`은 6의 대상 조건을 모두 갖췄다(1번 확인, 2026-11-12).
   - `terminal/build.zig:5-9`: `x86_64` · `linux` · `.gnu` · `cpu_model = .baseline`.
   - 게스트용 `zig-out/bin/terminal`: dynamically linked, `NEEDED libc.so.6`, interpreter `/lib64/ld-linux-x86-64.so.2`.
     `nm`에 `t memset` · `t memcpy`(= `compiler_rt.memcpy.memcpyFast`) · `t memmove` — 바이너리 안의 지역 심볼이다. 우리 렌더러의
     `memcpy` · `memset`(프레임버퍼 지우기, 지난 목록 46행 `memcpy` 약 110KB)도 모두 compiler_rt의 SSE2 고정 구현으로 간다.
   - `Glibc.enabled`의 조건: `link_libc` · GNU libc · `link_mode == .dynamic` · `output_mode`가 `.Exe`. `zig build-exe -target x86_64-linux-gnu
     -mcpu baseline -lc`에서 `@compileLog`가 `.Exe` · `.dynamic` · `true`를 찍었다.
   - 버전 조건(x86_64는 `min` 2.14): 버전을 안 적은 `x86_64-linux-gnu`에서 Zig 0.17.1의 `gnuLibCVersion()`은 2.31.0이다(`build-obj`로
     찍음, 같은 타깃에 `.2.14` · `.2.13`을 붙이면 그대로 나온다). 2.31 ≥ 2.14라 통과한다.
   - 게스트가 싣는 glibc(`make_initrd.sh`의 `SYSROOT` = `/usr/local/amd64-sysroot`, Debian GLIBC 2.41-12+deb13u4)에 묶을 심볼이 기본
     버전으로 있다: `memset@@GLIBC_2.2.5` · `memmove@@GLIBC_2.2.5` · `memcpy@@GLIBC_2.14`가 모두 IFUNC. `memcpy@GLIBC_2.2.5`는 IFUNC가 아닌
     FUNC다 — ghostty가 x86_64 `memcpy`만 2.14를 고르는 까닭이 그대로 보인다.

## 결정

### 결정 1 — 태그가 가리키는 SHA로 고정한다, commit 하나

GV 결정 2 그대로다. `terminal/vendor_libghostty_vt.sh`의 `GHOSTTY_SHA`를 `108cacb17ed8990840cd14abfce43d8ed8503ca1`로,
`GHOSTTY_SHA256`을 확인 1의 값으로 고치고 주석에 태그 이름 `vt-1.0.1`을 둔다. 우리 코드가 안 바뀌므로 commit은 하나다. 게이트는
`terminal`이 initrd에 들어가므로 루트 게이트 전체(약 35분)다. 판정 글자를 바꿀 체인은 없을 것으로 본다(확인 2) — 빨개지면 그 체인의 로그부터.

### 결정 2 — glibc로 돌리기는 이번 일에서 뺀다, 켜기 전에 실기에서 잰다

확인 7 · 8로 "1.0.1을 올리면 따라온다"도 "우리와 무관하다"도 아니다 — 라이브러리와 상관없이 우리 `main.zig` root에서 같은 asm을 두면
켜지고, 대상 조건은 모두 맞는다. 그래도 이번 milestone에 넣지 않는다.

- 효과를 잴 곳이 없다. ghostty의 숫자는 Zen 3다. 우리 실기(맥북 에어 2011, SandyBridge — AVX는 있고 AVX2는 없다)에서 glibc 2.41이 고르는
  구현이 compiler_rt의 SSE2보다 나은지는 모른다. 게이트의 QEMU TCG는 SIMD를 흉내 내므로 이 차이를 못 잰다.
- 바뀌는 범위가 ghostty보다 넓다. 우리 렌더러의 `memcpy` · `memset`이 함께 바뀌므로 라이브러리 올리기와 섞으면 빨강이나 느려짐을
  가르기 어렵다(GV 결정 1의 "나누면 `git revert` 하나로 가른다").

켤 때의 모양(다음 일의 출발점): `terminal/src/main.zig`의 `comptime` 블록에 확인 6의 asm 셋(심볼 버전은 확인 8의 셋)을 두고,
`nm`에서 `memset` · `memcpy` · `memmove`가 `U`(glibc 참조)로 바뀌는지 본다. 실기 측정은 `seq 1 200000`과 키 하나의 frame 구간
(`measurements.md` 98의 프로브)을 켜기 전후로. ghostty 코드는 MIT라 옮겨도 되지만, 주석의 출처(`quirks_memset.zig`의 `Glibc`, `vt-1.0.1`)를 남긴다.

### 결정 3 — 다음 판에 싣는다

사용자(2026-11-12): "다음 판에 싣는 걸로." 0.2.1은 교체하지 않는다 — `terminal`이 initrd에 들어가므로 교체하면 ISO 셋이 모두
바뀐다(cyber 때는 기본 판 하나였다). 판을 내는 일은 이 milestone 밖이다 — 내기로 할 때 [[project_release]]의 절차를 따른다.

## 비목표

1. 주석 속 ghostty 파일:줄 참조를 1.0.1 기준으로 다시 맞추기(GV 비목표 1과 같다).
2. libghostty-vt의 C ABI · 새 API를 쓰는 일.
3. 결정 2의 glibc 돌리기(별도 일).
