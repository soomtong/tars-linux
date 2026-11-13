# DY-M2 — Mesa · SDL3 묶음과 데모 프로그램

Date: 2026-11-13
Design: `docs/specs/2026-11-12-tars-display-yield-design.md`
Status: 열림. 사용자 2026-11-13 — 조사 결과의 추천 방향에 "confirmed".

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
