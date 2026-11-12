---
name: project_ghostty_glibc_mem
description: "ghostty vt-1.0.1(GU-M0, 2026-11-12)이 더한 'memset · memcpy · memmove를 glibc로 돌리기'는 Zig 모듈로 받는 우리에게 안 온다(`lib_vt.zig`의 root 조건). 우리 terminal은 대상 조건을 다 갖췄다(x86_64 baseline · 동적 glibc 2.41 · 지금은 compiler_rt의 SSE2 고정 구현). 켜려면 main.zig root에서 따로, 실기 측정 뒤"
metadata:
  type: project
---

# ghostty 1.0.1의 glibc mem 함수 돌리기

사용자(2026-11-12): lead가 "memset/memcpy 변경은 x86_64 · 동적 glibc에서 빠지니 무관하다"고 답하자 "이런 내용은 중요하다. 왜 무관한가?"
→ 확인해 보니 그 답은 틀렸다(파일 첫 30줄만 읽고 단정했다). 근거는 GU design 확인 6 ~ 8.

- 1.0.1의 `src/quirks_memset.zig`는 두 갈래다. 손으로 짠 SIMD `memset`은 x86_64 · Darwin · 동적 glibc에서 꺼지고, 새 `Glibc` 절은
  동적 glibc 실행 파일에서 세 함수를 glibc(IFUNC — 실행 중 CPU를 보고 고른다)로 돌린다. Zig는 compiler_rt를 바이너리 안에 넣고 그
  weak 정의가 공유 라이브러리의 것을 늘 이겨서, 그냥 두면 glibc의 것은 한 번도 안 불린다.
- 우리에게 안 오는 까닭: `lib_vt.zig:177`의 `if (@import("root") == lib)` 안에서만 import된다. 우리 root는 `terminal/src/main.zig`다.
  GU-M0 뒤 게스트 `terminal`의 `nm`도 `t memset` · `t memcpy` · `t memmove` 그대로였다.
- 우리 바이너리는 대상이다: `x86_64` · `.gnu` · `baseline`, 실행 파일 · `.dynamic`, Zig 0.17.1 기본 glibc 2.31(≥ 2.14), 게스트 sysroot의
  Debian glibc 2.41에 `memset@@GLIBC_2.2.5` · `memmove@@GLIBC_2.2.5` · `memcpy@@GLIBC_2.14`(셋 다 IFUNC).

Why: 렌더러의 `memcpy` · `memset`(프레임버퍼 지우기, 지난 목록 약 110KB 복사)까지 모두 SSE2 고정 구현으로 간다. vt 처리량보다 이쪽이
우리 화면 시간에 더 닿을 수 있다. 하지만 ghostty의 숫자(baseline ASCII 6~10%)는 Zen 3 것이고, 맥북 에어 2011(SandyBridge, AVX2 없음)에서
glibc가 고르는 구현이 나은지는 모른다. QEMU TCG는 SIMD를 흉내 내서 이 차이를 못 잰다.

How to apply:

- 켤 때는 라이브러리 올리기와 섞지 않는 따로의 일이다(GU design 결정 2). 모양: `main.zig`의 `comptime`에 `.symver` 별칭으로 버전 붙은
  glibc 심볼에 `jmp`하는 asm 셋(`.hidden`), 출처 주석(`quirks_memset.zig`의 `Glibc`, `vt-1.0.1`, MIT). `nm`에서 셋이 `U`로 바뀌는지 본다.
- 켜기 전후로 실기에서 `seq 1 200000`과 키 하나의 frame 구간(`measurements.md` 98의 프로브)을 잰다. 측정은 사용자 몫이다.
- ghostty가 compiler_rt를 고치면 이 장치가 필요 없어진다 — 파일의 "When to delete this"(`readelf --dyn-syms`에서 셋이 `UND`인지).
- 관련: [[reference_ghostty_source]] · [[project_zig_upgrade]].
