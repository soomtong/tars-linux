# WY-M3 — 배율

Date: 2026-11-20
Design: `docs/specs/2026-11-19-tars-wayland-server-design.md`(결정 5 · 27~31)
Status: 끝(2026-11-20). 브랜치 `app-layer-0-3`.

## 확인(조사 `wy-m3`, 세션 scratchpad `wy-m3/research.md` — HEAD `593cb94`의 코드와 vendored xml)

- HS 배율은 화면을 열 때 한 번 정해진다(`drm.zig:555` `scale.pick`). 배율 > 1이면 `fb.pixels`가 논리 그림자, `fb.out`이 물리 dumb 버퍼다.
  `present`(`drm.zig:327-336`)는 배율 > 1이면 `presentScaled`가 clip마다 그림자를 늘리고 곧바로 DIRTYFB — 늘리기와 내보내기 사이에
  끼어들 자리가 없다. `present`를 부르는 곳은 `presentFrame`(셸 프레임 · `renderApp`)과 화살표만 옮기는 바퀴 둘이다.
- 창은 지금 논리 그림자에만 쓰인다 — `srv.paint`가 버퍼 크기로 `fitIn` → `blit`. 배율 2 화면에서 2배 버퍼를 보내면 서버가 그것을
  "논리 2배 크기 버퍼"로 보고 가운데를 잘라 보인다.
- 서버: 판은 compositor 4 · output 4. `set_buffer_scale`을 버린다(`server.zig:584`). `wl_output.mode`는 논리 크기, `scale 1`.
  output resource를 모으지 않아 `wl_surface.enter`를 보낼 수 없다. zig-wayland 스캐너는 판을 올리면 자식(`wl_surface`)의 `offset`(5) ·
  `preferred_buffer_scale` · `preferred_buffer_transform`(6)을 만든다 — exhaustive switch라 `.offset`을 빠뜨리면 컴파일이 안 된다.
- 포인터 좌표는 논리이고 `surfacePoint`는 `last_fit` 기준이다 — `fit`을 surface 크기로 하면 한 줄도 안 바뀐다.
- 둠은 compositor 4로 bind, `wl_output` 없음, bs 1 — 바뀌지 않는다. SDL3 데모는 HIGH_PIXEL_DENSITY를 안 쓴다 — 늘 논리 크기 버퍼.
- hidpi 체인(`HS-M0`, 2880 × 1800, monitor 45502)은 부팅 A(auto → 배율 2) · B(`display_scale=1`)이고 screendump는 물리다. 판정 도구는
  `ppm_blocks`(2 × 2 블록 검사). wayland · display 체인은 1280 × 800 → 배율 1.

## 누가 무엇을 하나

구현은 Herdr 서브에이전트 `wy-m3`(Opus — 조사를 한 같은 에이전트)에 두 단계로. lead는 plan · 대조 · 게이트 · commit. 서브에이전트는
commit하지 않는다.

- 단계 A — protocol과 크기. 할 일 1~3. 끝나면 bs 2 창이 바른 크기 · 자리 · 포인터 좌표로 서지만 화면은 2 × 2 블록(흐림)이다 —
  그게 단계 A의 맞는 결과다.
- 단계 B — present 단계의 물리 합성 · 화살표 · 체인. 할 일 4~6.

## 착수 전에 확정한 것

1. 판(결정 27): `wl_compositor` 6(서버 상수 · `build.zig` 스캐너 · `tars-wl-test`의 bind). `wl_output` 4 그대로. `build.zig`의
   "viewporter는 M2에서" 주석은 결정 31로 고친다.
2. `Server.start`에 물리 크기와 배율을 더 준다. `fb_w/fb_h`(논리)는 configure · `placeWorkspace` · `configureColumn`에 그대로.
   `wl_output.mode` = 물리, `scale` = S.
3. `preferred_buffer_scale(S)`: `create_surface` 직후, `surface.getVersion() >= 6`일 때만.
4. output resource 목록(키보드 목록과 같은 모양). 창이 처음 configure될 때(`placeWorkspace` · `configureColumn`의 첫 번) 그 클라이언트의
   output마다 `surface.enter`. output을 나중에 bind하면 bind 때 이미 보이는 그 클라이언트의 surface에 enter. leave는 없음.
5. `Surface`에 `pending_scale` · `scale`(기본 1). `set_buffer_scale`: `<= 0`이면 `invalid_scale`, 아니면 pending. commit에서 current,
   버퍼가 있으면 `w % scale` · `h % scale`이 0이 아니면 `invalid_size`(결정 28). `.offset`은 버림, surface 판 5+의 attach x · y가 0이
   아니면 `invalid_offset`.
6. 크기(결정 29): `paint` · `logCommit`이 surface 크기(버퍼 ÷ bs)로 `fitIn`. 논리 그림자 blit은 bs로 솎는다(가장 가까운 픽셀 —
   `sy = (oy + y) · bs / k`, 열도 같다, bs 1이면 지금 식). `wl> commit` 줄은 bs가 1이 아닐 때만 끝에 ` bs=N`, `Toplevel.Sig`에 bs.
   bs 1 클라이언트의 줄은 바이트까지 지금과 같다.
7. 물리 합성(결정 30): `Framebuffer.present` = `stage(clips)` + `flush(clips)`. App이 프레임마다 "물리로 합성할 창(bs > 1이고 화면 배율 > 1)
   과 그 논리 사각형" 목록을 든다(보이는 것만, 최대 8). `stage` 뒤에 clip ∩ 사각형만 `fit` × S로 `out`에 옮기고(k · S == bs면 행 memcpy),
   화살표가 그 사각형과 겹치면 화살표의 불투명 픽셀만 ×S로 다시 찍는다(`scale.upscaleMasked`). 세 자리 모두(셸 프레임 · `renderApp` ·
   화살표만 옮기는 바퀴). 순수한 부분(clip ∩ 사각형, ×S의 `Fit`, 잘라 옮기는 blit)은 `wl_logic` · `scale`에 호스트 검사와 함께.
8. `tars-wl-test`: `--buffer-scale N`(1..3, 버퍼 = surface × N, attach 전에 `setBufferScale`, `--follow-size`면 configure × N, `--size`는
   surface 크기), `--checker`(1 버퍼 픽셀 바둑판, `(x + y) & 1`이면 `--color`, 아니면 `FFFFFF`). surface listener `wl-test> preferred scale=N` ·
   `wl-test> surface enter`, `wl_output` bind(4)와 `done`에서 `wl-test> output mode=WxH scale=N`.
9. 둠 · SDL3는 고치지 않는다. wayland · display 체인(배율 1)의 판정은 하나도 바뀌지 않아야 한다 — 그것이 회귀 검사다.
10. 체인 라벨은 `HS-M0` 그대로(DY-M2가 WY-M2 판정을 받고도 DY-M2인 선례).

## 체인

hidpi 부팅 A(배율 2)에 판정 6 · 7, 부팅 B(배율 1)에 판정 8. 포트 · 부팅 수 그대로. 새 도구 `ppm_checker f b x0 y0 x1 y1` — 사각형 안
`((x−x0)/b + (y−y0)/b) & 1`로 두 색 중 무엇이어야 하는지 정하고 다른 픽셀 수(바둑판 원점의 홀짝은 사각형 왼쪽 위로 맞춘다).

6. `tars-wl-test --buffer-scale 2 --checker --follow-size &` → `wl-test> preferred scale=2` · `wl-test> output mode=2880x1800 scale=2` ·
   `wl> commit … bs=2`. `pane>` 줄의 사각형(물리 = 논리 × 2)에서 `ppm_checker … 1` = 0, `ppm_blocks … 2` > 0.
7. 순서: (a) 셸에 포커스(`Cmd+[`) · 한 줄 치기(부분 프레임) → 창 사각형 `ppm_checker 1` = 0. (b) 통째 프레임(`Cmd+R` — 새 configure ·
   새 버퍼) → 새 사각형에서 다시 0. (c) 포인터를 창 위로 옮긴 뒤 바둑판이 화살표 밖에서 그대로(`ppm_checker 1`을 화살표 상자를 뺀 띠에서).
   (d) 닫고 `--buffer-scale 1 --checker --follow-size`로 다시 → `ppm_checker 2` = 0 · `ppm_blocks 2` = 0(늘린 길).
8. 부팅 B: `tars-wl-test --checker --follow-size &` → `preferred scale=1` · `output mode=2880x1800 scale=1`, commit 줄에 `bs=` 없음. 판정 5(reload)
   앞에서 닫는다.

## 할 일

1. (A) 판 6 · `.offset` · attach `invalid_offset` · `set_buffer_scale`(pending/current, 오류 둘) · preferred · output 목록과 enter ·
   `wl_output` 물리 mode + scale.
2. (A) `fit`을 surface 크기로 · 논리 blit의 bs 솎기 · `logCommit`의 ` bs=` · `Sig`. 호스트 검사(surface 크기 fit, 솎기, 같은 화면 점이 bs 1 ·
   bs 2에서 같은 surface 점).
3. (A) `tars-wl-test`의 `--buffer-scale` · `--checker` · 새 줄 셋.
4. (B) `stage` / `flush` 나누기, 물리 합성 목록 · 잘라 옮기는 blit · 화살표 마스크, 세 present 자리.
5. (B) hidpi 판정 6 · 7 · 8, `ppm_checker`, 체인 머리 주석.
6. (B) 도움말 — 사용자가 치는 것이 바뀌지 않으면 손대지 않는다(배율은 설정 키 `display_scale` 그대로).
7. lead: 체인 · verify grep · 루트 게이트.

## 판정

- 호스트 검사, 체인 hidpi · wayland · display · pointer PASS, 루트 게이트 35/35, verify mismatch 0.

## plan에서 실측할 것

1. libwayland-server 1.23.1이 resource 판보다 새 이벤트를 막는가(서버는 어차피 판을 본다 — 기록만).
2. SDL 3.2.10: non-HPD 창이 preferred 2를 받아도 버퍼 1배인가, attach x · y가 늘 0인가(아니면 결정 28의 `invalid_offset`에 끊긴다 —
   display 체인이 배율 1에서도 잡는다, compositor 판은 배율과 상관없이 6이므로).
3. 물리 합성 시간: 부팅 A에서 bs 2 column 통째 프레임의 `frame_us`와 bs 1의 것, 화살표만 옮기는 바퀴의 복사가 화살표 크기에 그치는지.
4. 부팅 A(175 × 53 격자)의 두 column 사각형 값.

## 결과

구현은 `wy-m3`(Herdr, Opus — 조사도 같은 에이전트), lead는 대조 · 게이트 · commit.

1. 단계 A `0b4de50`: compositor 6 · `preferred_buffer_scale`(판 6+만) · `set_buffer_scale`(오류 셋) · `wl_output` 물리 mode + scale · 첫 configure의
   `enter` · surface 크기 fit · ` bs=N`. 체인 단독 terminal · wayland · display · pointer · hidpi PASS, verify mismatch 0, bs 1의 `wl> commit` 줄은
   WY-M2 게이트와 바이트 같음. 실측 1: libwayland-server 1.23.1은 resource 판보다 새 이벤트를 막지 않는다(`wayland-server.c:215-245`) — 서버의
   판 검사가 유일한 방패다. 실측 2: SDL 3.2.10은 compositor를 `min(6, 서버)`로 bind하고 attach x · y는 늘 0, non-HPD 창은 버퍼 1배.
2. 단계 A에서 plan과 달라진 것: 클라이언트 줄 `surface enter` → `surface on output`(wayland 판정 16이 로그의 `enter`를 센다 — 체인을 바이트
   그대로 두려고). `tars-wl-test`가 첫 commit 전에 roundtrip 하나를 더 한다 — 판정 16이 configure를 보자마자 키를 치면 `get_keyboard` 전이라
   누름이 버려지는 경쟁(HEAD에도 있던 것, output bind로 확률이 바뀌었다). bs 2 창은 단계 A에서 "흐린 바둑판"이 아니라 흰색 한 색이다 —
   짝수 행 · 열만 남기는 솎기라서.
3. 위험으로 남긴 것: SDL은 커서 surface에 `set_buffer_scale(S)`를 보낸다 — 테마 커서 크기가 S의 배수가 아니면 `invalid_size`로 끊긴다
   (배율 1에선 안 나온다). SDL exclusive fullscreen(viewport 없음)은 `set_buffer_scale(mode.w / output_w)`를 보낸다 — 쓰는 클라이언트 없음.
4. 단계 B `f2a81c2`: `drm.present` = `stage` + `flush`, `presentComposed`(늘리기 → 물리 합성 clip ∩ 사각형 → 화살표 마스크 → 내보내기)를 셸 프레임 ·
   `renderApp` · 화살표만 옮기는 바퀴 셋이 함께 쓴다. `paintPhys`는 `last_fit`이 아니라 지금 버퍼로 자리를 다시 센다(그리기가 하한으로 미뤄진
   사이 화살표 바퀴가 오면 옛 자리로 작아진 버퍼를 읽지 않게). hidpi 판정 6 · 7a~7e · 8, `ppm_checker`(흰색 · `--color` 고정 — 단계 A의
   한 색 화면에서는 정확히 반 1,180,416이 bad), 부팅 A에 USB 마우스. 체인 단독 hidpi 195초 · terminal · wayland · display · pointer ·
   fullscreen 모두 첫 회차 PASS, verify mismatch 0.
5. 실측 3(TCG): Cmd+R 뒤 bs 2 창 1400 × 848 전체(물리 4,748,800 픽셀)를 옮긴 통째 프레임 50.6 ms — 셸을 다시 그리는 값(50~67 ms)에 묻혀
   드러나지 않는다. 화살표만 옮기는 바퀴는 1,824 픽셀(화살표 상자 둘 24 × 38 × 2)만 옮긴다. 줄 `wl> frame full …` · `wl> phys arrow …`는
   terminal 하나에 처음 네 번만.
6. 루트 게이트 35/35 첫 판 PASS(prebuild 350초 + lanes 1,560초, `out/gate-logs/20261120-014634`), verify 줄 14,503 중 mismatch 0.
   HS-M0의 PASS 줄은 "HS-M0 · WY-M3 — …"이다.

남은 걱정은 `docs/guides/carryover.md`의 "WY-M2 · WY-M3이 남긴 것" 절로 옮겼다.
