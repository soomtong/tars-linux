# DY-M2 — Mesa · SDL3 묶음과 데모 프로그램

Date: 2026-11-13
Design: `docs/specs/2026-11-12-tars-display-yield-design.md`
Status: 끝(2026-11-14). 사용자 2026-11-13 — 조사 결과의 추천 방향에 "confirmed". 결과는 맨 아래.

## 착수 전에 확정한 것

design 결정 10(SDL3 + `SDL_Renderer`, GLES)을 다음 셋으로 구체화한다. 끝났을 때 되는 것:

```
$ tars-fullscreen tars-gpu-demo        ← 화면 가득 움직이는 그림(GLES). 친 키가 화면에 찍힌다. Esc로 끝나고 콘솔이 돌아온다
$ tars-fullscreen tars-gpu-demo        ← Ctrl+Cmd+Backspace로도 끝난다(M1의 탈출 조합)
$ tars-gpu-demo                        ← gpu 묶음이 없으면 "libSDL3.so.0이 없다 — gpu 묶음" 한 줄로 끝난다
```

1. 출처는 Debian trixie 패키지 그대로다(`kind = "debian"`, 새 묶음 `gpu`). Mesa를 직접 빌드하지 않는다 — 크기를 줄이는 대신 빌드 체인
   하나를 통째로 떠안는다. LLVM은 QEMU(3D 없는 virtio-gpu)의 llvmpipe가 쓴다.
2. 입력에 `SDL_EVDEV_DEVICES` 힌트를 채우지 않는다. Debian의 SDL3은 libudev를 dlopen하는 빌드이고, libudev가 서면 udevd 없이도 `/sys`를
   훑어 능력 비트로 키보드를 짐작한다. 힌트를 읽는 갈래는 libudev 없는 빌드에만 있다(아래 확인 3). `libudev.so.1`은 initrd에 이미 있다.
3. 데모는 Zig 프로그램 `tars-gpu-demo`이고 initrd에 싣는다(`tars-kms-fill`처럼 — 실기에서도 같은 것으로 본다). `libSDL3.so.0`은 dlopen한다
   — 빌드 때 .so가 필요 없고, 묶음이 없을 때 이유를 말할 수 있다. 타입 · 상수는 SDL 3.2.10 헤더에서 쓰는 것만 손으로 옮긴다(Task 2의 정정).

## 확인 (2026-11-13, 이 plan을 쓰기 전)

프로브는 `--platform=linux/amd64 debian:trixie-slim`에서 apt-get install하고 설치 전후를 비교했다(harvest.sh와 같은 방식).

1. 판: `libsdl3-0` 3.2.10+ds-1, `libegl1` · `libgles2` 1.7.0-1+b2, `libegl-mesa0` · `libgbm1` · `mesa-libgallium` 25.0.7-2+deb13u1.
   `libsdl3-0`의 Depends가 `libgbm1`을, 그것이 `mesa-libgallium`을, 그것이 `libllvm19`를 끌어온다 — SDL3만 따로 싣는 길은 없다.
2. 크기: 새 파일 228MiB(libLLVM 124 · libz3 26 · libgallium 40 · SDL3 2.8, 나머지는 X11 · wayland · pulse · pipewire · alsa 라이브러리),
   squashfs zstd15로 69MiB. 2GiB까지 남은 자리는 약 146MiB(LD-M0) — 넣고도 77MiB가 남는다. base와 겹치는 파일은 LD-M0이 지운다.
3. SDL 3.2.10(`release-3.2.10`, `877399b`)의 입력 길:
   - `SDL_kmsdrmvideo.c:1461` — KMSDRM이 `SDL_EVDEV_Init()`을 부르고 반환값을 안 본다. 입력이 못 서도 화면은 뜬다.
   - `SDL_evdev.c:175` — `SDL_USE_LIBUDEV`면 `SDL_UDEV_Init` → `libudev.so.1` dlopen(`SDL_udev.c:39`). 실패하면 evdev 전체가 없다 —
     힌트(`:192`의 `#else`)는 컴파일되지 않은 갈래라 대신 서지 않는다.
   - `SDL_udev.c:466` — `ID_INPUT_*`가 없으면(udevd가 없으면) `guess_device_class`(능력 비트). 주석이 바로 이 경우를 말한다.
   - 기억 `project_display_yield` 15("힌트를 채워야 키가 간다")는 libudev 없는 빌드의 이야기였다 — Task 4에서 고친다.
4. 드라이버: `libgallium` 안에 `crocus`(맥북 에어 2011, Sandy Bridge HD 3000) · `iris` · `virgl` · `llvmpipe` · `softpipe`의 이름이 있다.
   `/usr/lib/x86_64-linux-gnu/dri/`는 없고 GBM 백엔드는 `gbm/dri_gbm.so`(libgbm1)다.
5. SDL 3.2.10 소스: `https://github.com/libsdl-org/SDL/releases/download/release-3.2.10/SDL3-3.2.10.tar.gz`,
   sha256 `f87be7b4dec66db4098e9c167b2aa34e2ca10aeb5443bdde95ae03185ed513e0`(16MB, `include/SDL3/` 85개).

못 본 것(Task 1 · 3이 실행으로 본다): Debian이 정말 `SDL_USE_LIBUDEV`로 빌드했는지, `dri_gbm.so`가 드라이버를 찾는 길, QEMU에서 잡히는 드라이버.

## Task 1 — 묶음 `gpu` (commit 하나)

1. `devlayer/manifest.toml`에 절 하나: `libsdl3-0` · `libegl1` · `libegl-mesa0` · `libgles2`(판은 확인 1). `libgbm1` · `mesa-libgallium`은
   의존으로 온다(`gpu.pkgs`에 남는다). 주석에 확인 2 · 3의 숫자와 까닭.
2. `make dev-layers`로 굽고 `verify.sh`의 NEEDED 검사를 지난다. dlopen하는 것(`libudev.so.1` · `libEGL_mesa.so.0` · `dri_gbm.so`)은 NEEDED에
   안 잡히므로 묶음 뿌리에서 손으로 본다 — 결과 절에 적는다. `/usr/share/glvnd/egl_vendor.d/50_mesa.json`이 묶음에 있어야 한다.
3. 묶음이 열셋이 된다: `Makefile`의 `DEV_LAYERS`(기본값과 `help` 줄), LD-M0이 고친 자리(`devtools/check.sh`의 묶음 목록 · `12 layers` ·
   lowerdir 줄), 기억 `project_release`의 `ISO_LAYERS`. 2GiB 안인지 `tars-dev.iso` 크기로 본다.

## Task 2 — `tars-gpu-demo` (commit 하나)

1. 자리: `init/src/gpu_demo.zig`, `init/build.zig`에 이 실행 파일 하나만 target `x86_64-linux-gnu`(terminal과 같은 glibc 동적 — init의
   나머지는 musl 정적이라 dlopen이 없다). `make_initrd.sh`가 initrd의 `usr/bin/tars-gpu-demo`로 싣고 `OWN_BINS`에 더한다.
2. SDL 헤더(정정, 구현 중 2026-11-13): 처음에는 tarball의 헤더를 `@cImport`하려 했으나 ZU-M1부터 `@cImport`가 없고 C 헤더는 translate_c
   패키지로 번역한다 — 함수 스물둘을 위해 16MB tarball과 번역을 끌어올 값어치가 없다. 쓰는 타입(`SDL_Event`의 128바이트 · 키 이벤트 ·
   `SDL_DisplayMode` · `SDL_FRect`)과 상수만 손으로 옮기고 자리마다 헤더의 줄을 적는다. 함수는 `dlopen("libSDL3.so.0")` · `dlsym`의 표.
   SDL3은 3.x 안에서 ABI를 지킨다.
3. 하는 일: `SDL_Init(VIDEO)` → 전체 화면 창 → `SDL_CreateRenderer(NULL)` → 매 frame 색 띠 몇 개가 돌고, 친 키 이름을 화면 아래에
   (SDL의 디버그 글꼴 `SDL_RenderDebugText`). Esc면 끝. 인자 `--seconds N`이면 N초 뒤 스스로 끝(체인용).
4. 단계 줄(stderr, 체인과 사람이 같은 줄을 본다): `tars-gpu-demo: sdl 3.2.10` · `video kmsdrm` · `renderer opengles2` ·
   `gl <GL_RENDERER>`(`SDL_GL_GetProcAddress("glGetString")`) · `mode WxH` · `key <이름>` · `frames N in Mms` · `esc`.
   dlopen 실패는 `tars-gpu-demo: libSDL3.so.0 not found — the gpu bundle is not here`로 끝(코드 1).
5. 순수한 부분(인자 · 줄 만들기)만 호스트 시험. SDL을 부르는 부분은 체인이 본다.

## Task 3 — 체인 `display` 부팅 3 (commit 하나)

홈 디스크에 `.tars/layers/base.sqfs` · `gpu.sqfs`를 넣은 부팅 하나를 더한다(init은 `/home/.tars/layers`에서 묶음을 찾는다 —
`init/src/layers.zig`). 홈 이미지는 64MiB에서 묶음 크기만큼 키운다. display 체인이 `make dev-layers`의 산출물을 쓰게 되므로 devtools 체인처럼
그것을 먼저 부르는지(prebuild) 본다.

1. 묶음 없는 부팅 1에서 `tars-gpu-demo` → `not found — the gpu bundle` 줄(코드 1).
2. 부팅 3: `tars-fullscreen tars-gpu-demo` → `yield pid` → 데모의 `video kmsdrm` · `renderer opengles2` · `gl …`(llvmpipe이든 virgl이든
   적힌 것을 결과에 남긴다) → 화면이 검지 않다(`screendump` · `ppm_ink`) → `x y z`를 치면 `key X` · `key Y` · `key Z`(힌트 없이 — 확인 3의 판정)
   → Esc → `esc` → `reclaim` → 셸 줄에 `xyz`가 없다.
3. 탈출: 다시 띄우고 `ctrl-meta_l-backspace` → `escape … (SIGTERM)` → `reclaim`(SDL은 SIGTERM에 `SDL_EVENT_QUIT`을 낸다 — SIGKILL 줄이 없어야 한다).
4. design 위험 3: 복귀 뒤 터미널 화면이 M1과 같이 그려진다(`screendump`의 잉크). 커서 plane · 감마가 남는지는 화면으로 본다.
5. 판정에 걸린 시간을 적는다 — llvmpipe가 느리면 `--seconds`와 기다림을 늘린다.

## Task 4 — 안내 · 기억 (commit 하나, 닫기와 함께여도 된다)

1. `docs/help/desk.md`: `tars-gpu-demo` 한 줄(gpu 묶음이 있어야 한다).
2. 기억 `project_display_yield` 15 정정(확인 3), design 결정 10에 묶음 이름과 확인 2의 숫자.
3. 실기(사용자): 맥북 에어 2011에서 `tars-fullscreen tars-gpu-demo 2>/tmp/gpu.log` — `gl` 줄이 crocus인지, frame 수. `carryover.md`의 DY 절에.

## 위험

1. Debian이 `SDL_USE_LIBUDEV` 없이 빌드했다면 키가 안 온다(그때 힌트는 선다) — Task 3의 `key` 판정이 바로 드러낸다. 그러면
   `tars-fullscreen`이 `/dev/input/event*`로 힌트를 채운다(M1 결과 6의 원안).
2. `guess_device_class`가 QEMU의 키보드를 키보드로 못 보면 같은 판정이 빨갛다. 그때는 SDL 소스의 판정과 장치의 능력 비트를 대조한다.
3. llvmpipe는 CPU 하나(커널이 SMP를 안 쓴다 — `carryover.md` CE 절)에서 느리다. 체인은 frame 수가 아니라 "그렸다"만 본다.
4. 묶음 열셋이 2GiB를 넘으면 사용자에게 묻는다(기본 판에서 뺄지, Mesa를 줄일지).

## 결과

commit: `ec302fc`(plan) · `ec26a23`(Task 1) · `9c90a92`(Task 2) · `e5152a1`(Task 3) · `6ac4591`(Task 4의 안내). 2026-11-13~14 로컬 세션.

1. Task 1: harvest `packages=76 paths=1354`, verify `elf=461 unresolved=0 dropped=108`(base와 같은 파일), 구운 크기 `unpacked=223MiB zstd15=68MiB`
   (`gpu.sqfs` 72MiB). dlopen으로만 열리는 것(`libEGL_mesa.so.0` · `gbm/dri_gbm.so` · `egl_vendor.d/50_mesa.json` · `libSDL3.so.0`)이
   묶음 안에 있다. `libudev1`은 harvest의 `dep`(trixie-slim에 있어 묶음에 안 든다)이고 initrd에 있다.
   devtools 체인 PASS(빌드 뒤 737초): `tars-dev.iso` 2,064,447,488 B — 2GiB까지 약 79MiB. 열셋을 얹는 데 85ms.
   첫 판은 체인이 도는 동안 내가 Task 2 코드를 넣어 init 빌드에서 멈췄다 — 체인은 작업 트리를 그대로 빌드한다(lead의 잘못).
2. Task 2: plan의 `@cImport`는 ZU-M1부터 없다 — 헤더 대신 쓰는 타입 · 상수만 손으로 옮겼다(plan Task 2의 정정). 함수 스물둘은 dlsym 표.
   NEEDED가 `libc.so.6` · `libdl.so.2`라 `make_initrd.sh`가 terminal처럼 `copy_lib_deps`를 부른다(libdl은 terminal이 안 데려온다).
   Zig 0.17의 `@typeInfo(T).@"struct"`는 `fields`가 아니라 `field_names`다.
3. Task 3: display 체인 PASS(부팅 셋, 7분 22초). QEMU(TCG · 3D 없는 virtio-gpu)에서 잡힌 것: `video kmsdrm` · `renderer opengles2` ·
   `gl llvmpipe (LLVM 19.1.7, 128 bits)` · `mode 1280x800`. 약 2fps(`frames 9 in 4101ms`) — 그래도 화면 가운데의 색이 1초 사이에 바뀐다.
   키 X · Y · Z · Esc가 힌트 없이 왔다 — plan 확인 3(Debian SDL3은 libudev로 `/sys`를 훑고 능력 비트로 짐작한다)이 실행으로 맞았다.
4. 탈출 조합의 SIGKILL: 첫 둘째 판은 판정 14가 빨갰다(`escape … (SIGKILL)`). 데모에 끝내기의 시간을 찍게 하니 `left the loop 205ms` ·
   `shut down 493ms after the request` — 데모 자신은 빨랐다. 남은 것은 `main`이 돌아간 뒤 glibc `exit`가 부르는 Mesa · LLVM의 전역
   소멸자였다. `SDL_Quit` 뒤 `exit_group(0)`으로 끝내게 하니 PASS(`shut down 825ms`). 여유는 크지 않다 — SIGTERM은 그리던 frame이 끝난
   뒤의 `PollEvent`에서야 QUIT이 되므로 TCG의 frame 하나(최대 1초 남짓)가 더 든다. 게이트에서 빨개지면 이 자리다.
   SDL로 만든 다른 앱도 같은 소멸자를 탈 수 있다 — 실기(i915 · crocus, LLVM 안 씀)에서는 짧을 것으로 보지만 재지 않았다.
5. design 위험 3: 복귀 뒤 screendump에서 색 · 글자가 평소와 같다(감마 그대로). 커서 plane은 screendump가 찍는지 확실하지 않아 못 봤다 —
   데모는 `SDL_HideCursor`를 부른다.
6. 루트 게이트: 34/34 첫 판 PASS(약 33분 — prebuild 약 7분 + lanes 약 26분, 회차 34개 모두 `cut log lines A=0 B=0 C=0`,
   `out/gate-logs/20261113-150007`). DY 157초(부팅 셋), 데모의 끝내기 `shut down 686ms`. 체인 이름은 게이트 뒤에 `DY-M1` → `DY-M2`(닫기 commit).
7. 안 본 것: i915 실기(crocus), 맥북 에어 2011의 frame 수.
