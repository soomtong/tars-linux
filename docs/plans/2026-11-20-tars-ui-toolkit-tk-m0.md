# TK-M0 — 공유 모듈 · 툴킷 빌드 · 창 층 · 글자 · `tars-tk-demo`

Date: 2026-11-20
Design: `docs/specs/2026-11-20-tars-ui-toolkit-design.md`(결정 1~12)
Status: 끝(2026-11-20). 브랜치 `app-layer-0-3`.

## 확인

design의 확인 절 1~9(조사 `tk-m0`, 세션 scratchpad `tk/research.md`)가 이 plan의 근거다. 이 plan에서 새로 정하는 것은 아래 확정 절.

## 누가 무엇을 하나

구현은 Herdr 서브에이전트 `tk-m0`(Opus — 조사도 같은 에이전트)에 세 단계로. lead는 plan · 대조 · 게이트 · commit.

- 단계 A — 공유 모듈 뽑기(변화 0). `shared/theme.zig` · `shared/glyph.zig`, terminal이 그것을 쓰게. 할 일 1. 판정은 루트 게이트 그대로(lead).
- 단계 B — `toolkit/` 빌드 · 창 층 · z2d · 글자 · `tars-tk-demo` · initrd · 글꼴. 할 일 2~4.
- 단계 C — 체인 `toolkit` · 루트 `CHAINS` · 함께 고칠 곳. 할 일 5 · 6.

## 착수 전에 확정한 것

1. 단계 A: `shared/theme.zig`에 terminal의 색 상수(`main.zig`의 MARGIN · STATUS_* · SEPARATOR · APP_BACKDROP, `vt.zig`의 셀 배경 · 전경 · MATCH_BG ·
   CURRENT_BG · CURSOR_COLOR, `pointer.zig`의 POINTER_*)를 값 그대로. terminal은 이름을 그쪽에서 받는다(같은 이름의 `const X = theme.X`로 두어도 된다).
   `shared/glyph.zig`는 stb 한 겹(em 기준 · 픽셀 높이 기준 둘 다 받는 `init` — terminal은 지금처럼 `ScaleForPixelHeight(16)`, 툴킷은 em),
   `font.zig`는 감싸개로 남는다. font_test 표 · `terminal` 체인 · 루트 게이트가 그대로여야 한다. 바이너리의 바이트가 바뀌는 것은 괜찮다(행동이 같으면).
2. `toolkit/build.zig` · `build.zig.zon`(zig-wayland v0.7.0 같은 url · hash, z2d v0.13.2 url + hash), 모듈 `tk`, 실행 파일 `tars-tk-demo`. 대상은 terminal과
   같은 x86_64 sysroot · 같은 최적화 모드. `terminal/prepare.sh` 끝에서 부른다. 호스트 검사 `zig build test`(z2d를 끌어들이는 검사가 Debug 자체 백엔드에서
   메모리를 넘으면 그 검사 모듈만 LLVM으로 — 실측 4).
3. 창 층(design 결정 9): 버퍼 둘 · release · 버퍼마다 z2d `Surface` 한 번 · configure를 늘 따름 · 바뀐 것이 있을 때만 frame + commit · `preferred_buffer_scale` →
   물리 버퍼 + `set_buffer_scale` · `tars_menu_manager_v1` bind · `damage_buffer`(TK-M0은 통째). 키는 받아서 `tk> key code=` 줄만(TK-M2가 responder).
4. 글자(결정 5 · 6): 글꼴은 Pretendard Regular .otf 1.3.9 원본 그대로를 고른다(design 확인 4 — 가장 작은 UI 비례폭, 줄 높이 16). `terminal/vendor_fonts`의
   받기 방식(있으면 그것, 없으면 vendor 스크립트와 같은 `fetch url 파일 sha256`)으로 받고, 라이선스 원문(OFL.txt)과 출처 · sha256을 함께 싣는다.
   initrd `/vendor/fonts/Pretendard-Regular.otf`. em 기준 · 서브픽셀 x · 감마(처음 값 1.0 — 판정에서 고름) · f32 advance · kern.
5. `tars-tk-demo`: configure 크기 전체를 테마 배경, 가운데 둥근 사각형(r 12, 정한 색), 그 안 "안녕"(14 px), 아래에 표본 네 줄(13 px · 14 px 한글 · 라틴 · 숫자 —
   결정 4의 사람 판정용). 로그 `tk> configure w= h= scale=` · `tk> draw w= h= dirty=x,y,w,h us=` · `tk> commit`. `Cmd+Q`(close)에 끝난다.
6. 체인 `toolkit/check.sh`(monitor 45509, 부팅 하나 — 디스크 없음, 1280 × 800, PS/2라 Cmd는 `alt-`): 판정
   1 셸에서 `tars-tk-demo &` → `wl> column` · `tk> configure w=… h=…`(pane 크기) · 서버 로그에 menu manager bind(`wl> keys pid=N native`).
   2 screendump: 둥근 사각형 가운데 = 정한 색, 모서리 바깥 한 점 = 배경, 모서리 대각선 한 칸 = 중간값(AA).
   3 "안녕" 상자 안 잉크 > 0이고 중간값이 있다. 결정 4의 1배 PNG를 체인 로그 폴더에 남긴다(사람 판정).
   4 `Cmd+R` → 새 `tk> configure` → `tk> draw`, 둥근 사각형 가운데가 새 폭의 가운데로.
   5 idle 2초 동안 `tk> commit` 0줄.
   6 `Cmd+Q` → 데모가 끝나고 셸이 전체 폭(wayland 판정 22의 모양).
   루트 `CHAINS` 끝에 `"TK-M0:./toolkit/check.sh"`(36체인). 함께 고칠 곳: `prebuild`에 toolkit `zig build test`, `LOGLINE_DIRS`(툴킷이 logline을 쓰면 —
   쓰지 않으면 stderr 줄), quick_check의 fmt · ast 목록, `.gitignore`(`toolkit/zig-out` · `.zig-cache` · `zig-pkg`), 루트 `clean()`, make_initrd의
   `cp` · `OWN_BINS` · `copy_lib_deps`, Makefile의 `check` 필터에 `toolkit`.

## 할 일

1. (A) `shared/theme.zig` · `shared/glyph.zig` · terminal이 쓰게 · quick_check 목록(glyph는 `zig run`에서 뺌). 호스트 검사 · `make quick` · 체인 단독
   terminal · pane · status 계열 하나 이상(색 판정이 있는 것).
2. (B) `toolkit/` 빌드 · zon · prepare.sh 한 줄 · 호스트 검사(메모리 버퍼 백엔드로 둥근 사각형 · 글자 상자 픽셀 표).
3. (B) 창 층 · 글자 · `tars-tk-demo`.
4. (B) 글꼴 받기 · 라이선스 · initrd · `docs/guides/initrd-criteria.md`의 기준 표에 한 줄.
5. (C) 체인 `toolkit` 판정 1~6, 루트 `CHAINS` · 함께 고칠 곳.
6. (C) 도움말: 사용자가 치는 것이 생기면(`tars-tk-demo`는 시험용이라 안 적어도 된다 — 판단을 report에).
7. lead: 단계마다 대조 · commit, 끝에 루트 게이트(36체인).

## 판정

- 단계 A: 루트 게이트 35/35(변화 0). 단계 C 뒤: 루트 게이트 36/36, verify mismatch 0, 결정 4의 사람 판정을 결과에.

## plan에서 실측할 것

1. 게스트(TCG)의 `tk> draw us=` — 616 × 752 통째(둥근 사각형 + 글자). 2. 결정 4의 화면 판정과 감마 값. 3. 글꼴 sha256 · initrd gzip 증가분.
4. z2d를 끌어들인 호스트 검사의 백엔드 · 메모리. 5. `tars-tk-demo` 크기(strip 뒤)와 NEEDED. 6. 단계 A 뒤 terminal 바이너리 크기 차이.
7. 첫 configure 크기와 `Cmd+R` 순환의 크기. 8. `/vendor/fonts/`가 로그인 사용자 uid로 읽히는가(체인은 root — 설치된 기계에서 볼 자리는 carryover).

## 결과

구현은 `tk-m0`(Herdr, Opus — 조사도 같은 에이전트), lead는 대조 · 게이트 · commit.

1. 단계 A `2a1c245`: `shared/theme.zig`(셸 색 상수 열여덟 + 셀 기본색 둘, 값 그대로 — lead가 지운 리터럴과 기계로 대조, 다름 0) · `shared/glyph.zig`(stb 한 겹 —
   `Size = pixel_height | em`, 서브픽셀 x, f32 advance, kern). `font.zig`는 감싸개(16 px · unifont · sprite · 정수 셀). `stbtt_GetCodepointBitmap`은
   v1.26에서 서브픽셀 0의 `…BitmapSubpixel`을 그대로 부르므로 coverage가 같다. 체인 단독 terminal · pane · hangul · copy · pointer · wayland PASS,
   루트 게이트 35/35(prebuild 475초 + lanes 1,615초, `out/gate-logs/20261120-104410`), verify mismatch 0. strip 뒤 terminal +128 B.
2. 단계 B `4af0ad8`: `toolkit/`(build · zon — z2d v0.13.2 · zig-wayland v0.7.0, 모듈 `tk`, `tars-tk-demo`, 호스트 검사 `tk_test` 열다섯), 창 층(버퍼 둘 · release ·
   configure를 따름 · 바뀐 것만 frame + commit · `preferred_buffer_scale` · `tars_menu_manager_v1` bind), `canvas`(z2d 둥근 사각형 · 감마 섞기), `text`(em ·
   서브픽셀 넷 · kern), 글꼴 `toolkit/vendor/fonts/Pretendard-Regular.otf` 1.3.9 원본(sha256 `3ffbacde…1c93`, OFL-1.1.txt · README — unifont처럼 커밋),
   `shared/theme.zig` 앱 토큰(`TK_BG 202C3C` · `TK_ACCENT 3C78D8` · `TK_TEXT F4F6F8` — 셸의 게이트 색과 다른 값), prepare.sh 한 줄, initrd(데모 · 글꼴).
   체인 단독 terminal · wayland · display PASS, verify mismatch 0. 한 번 부팅: `wl> keys pid=73 native` → `column` → `configure w=616 h=752` → `tk> draw …
   us=57620`(첫 장 — 글리프 굽기 포함) → `Cmd+R` → `w=1240` · `us=4363` → idle 3초 commit 0 → `Cmd+Q`로 끝.
3. 결정 4의 판정(lead, 실제 QEMU screendump 1배): 13 px · 14 px 한글 · 라틴 · 숫자가 읽힌다, 획 많은 음절도 구별된다, 숫자 간격이 고르다. 감마 1.8로 정했다.
4. 실측: z2d를 끌어들인 호스트 검사는 Debug 기본 백엔드에서 MaxRSS 478 MB로 섰다(design 위험 1은 z2d 자체 검사 전체의 일). `tars-tk-demo` strip-debug
   1,121,264 B, NEEDED는 이미 initrd에 있는 사슬. initrd gzip 어림 +1.53 MB(글꼴 1.05 + 데모 0.48). `THIRD_PARTY` 파일은 저장소에 없다 — 고지는 zon 주석 ·
   `vendor/fonts/README`. 단계 B에서 달라진 것: 버퍼 나이는 TK-M1(통째 그리기라 뜻이 없다), 같은 크기 configure는 ack만(idle commit 0).
5. 단계 C `5c3ec2b`: 체인 `toolkit/check.sh`(서른여섯째, monitor 45509, 판정 1~6 — native bind · column · 616 × 752, 둥근 사각형 좌표 색 · 대각선 중간값,
   "안녕" 상자 ink · 결정 4의 1배 PNG를 회차 로그 폴더에, `Cmd+R` 1240 폭 · 새 가운데, idle 2초 서버 commit 줄 그대로, `Cmd+Q` 뒤 스스로 끝남 · 셈
   `tk-2-2-1-1-2-2`), 루트 `CHAINS` · `prebuild`에 toolkit `zig build test`, `GAMMA = 1.8`, 데모의 같은 Face 둘을 하나로. 체인 단독 toolkit 두 번 연속 · terminal PASS.
   idle commit 0의 결정적 증거는 클라이언트 셈(commit = draw)이다 — 서버의 `wl> commit` 줄은 버퍼 모양이 바뀔 때만 찍힌다.
6. 루트 게이트 36/36 첫 판 PASS(prebuild 388초 + lanes 1,578초, `out/gate-logs/20261120-122030`), verify mismatch 0.

남은 걱정: 판정 2의 대각선 중간값은 z2d 판에 묶인 한 칸이다(판을 올리면 모서리 상자의 중간값 수로). 판정 좌표는 1280 × 800 · column 616에 묶였다
(데모 머리와 체인 머리가 같은 숫자를 적었다). `/vendor/fonts/`가 로그인 사용자 uid로 읽히는지는 체인(root)이 못 본다 — 설치된 기계에서(carryover).
