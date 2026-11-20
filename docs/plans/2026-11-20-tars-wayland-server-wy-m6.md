# WY-M6 — 호환 모드 · damage 부분 blit

Date: 2026-11-20
Design: `docs/specs/2026-11-19-tars-wayland-server-design.md`(결정 44~47), 요구사항 결정 3 · R-WY-10 · R-KIT-1 · R-CA-2
Status: 진행 중. 브랜치 `app-layer-0-3`.

## 확인(조사 `wy-m6`, 세션 scratchpad `wy-m6/research.md` — HEAD `e654a8e`, SDL 3.2.10 · 둠 소스)

- 툴킷은 popup · 장식을 안 쓰고(결정 9 · R-TKW-2 · 3) Cmd를 Super로 받아야 한다(R-KIT-1 · 6). damage는 TK-M1(더티)과 CR(위험 1)이 바란다.
  popup · 장식은 CR만 바란다 — 그래서 WY-M7로 뗐다(결정 44).
- 키의 수정키 비트는 `wlMask` → `modifierMask`(Super 0x40 · Ctrl 0x4)를 거쳐 서버의 `key`(키 뒤 `modifiers`)와 `enterKeyboard`가 보낸다. 클라이언트마다의
  기록은 `ClientRec`. SDL3는 `modifiers` 이벤트로 수정키를 바로잡는다 — 마스크만 Ctrl로 바꿔도 SDL은 Ctrl+V로 본다. 둠은 키 코드 29로 쏜다 — 마스크는 안 본다.
- 체인은 수정키 비트를 안 본다(클라이언트의 `mods depressed=` 줄은 찍히지만 판정이 안 읽는다).
- damage는 `server.zig`가 버린다. 셸 프레임은 commit이 온 app slot을 통째로(둘레 검정 + 창 전체 + clip 전체), `renderApp`도 통째. `blitClip`은 이미
  화면 clip을 받는다(물리 합성이 쓴다). 지금 클라이언트 셋(SDL · 둠 · `tars-wl-test`)은 전부 통째 damage라 이득이 0이다 — 부분 damage는 툴킷 · Chromium이 보낸다.
- render verify의 clip 판정(clip 밖이 안 바뀌었다)이 부분 blit의 clip 빼먹기를 공짜로 잡는다.

## 누가 무엇을 하나

구현은 Herdr 서브에이전트 `wy-m6`(Opus — 조사도 같은 에이전트)에 두 단계로. lead는 plan · 대조 · 게이트 · commit.

- 단계 A — 호환 모드 · `tars_menu_v1` 뼈대 · `tars-wl-test --native` · 판정 29. 할 일 1~3.
- 단계 B — damage 누적 · 부분 blit · `tars-wl-test --damage` · 판정 30 · 실측. 할 일 4~6.

## 착수 전에 확정한 것

1. `logic.compatMask(m) Mask`(순수 — depressed에 0x40이 있으면 지우고 0x4를 켬, latched · locked 그대로). 서버 `key`의 `modifiers` · `sent_mods` 비교와
   `enterKeyboard`에서 포커스 클라이언트가 호환이면 씌운다. 키 코드 · `input.zig` · `main.zig`의 키 길은 안 바뀐다.
2. `tars_menu_v1`: 저장소 안 `terminal/protocol/tars-menu-v1.xml`(vendor 밖 — `.gitignore`에 안 걸리는 자리, 라이선스 머리는 프로젝트의 것), global
   `tars_menu_manager_v1`(이름은 단계 A가 xml 관례에 맞게 정해 보고) 판 1, 요청 `destroy`. bind한 클라이언트의 `ClientRec.native = true`. 로그
   `wl> keys pid=N native`(bind), 포커스가 바뀌어 모드가 달라지면 `wl> keys to=ID mode=compat|native`.
3. `tars-wl-test --native`: 그 global을 bind. 수정키 줄 `mods depressed=0x…`는 지금 그대로.
4. damage(결정 47): `Surface.pending_damage` · `damage`(버퍼 좌표 합집합 하나, 버퍼 크기로 자름). `damage`(surface 좌표)는 × bs. commit이 누적에 합친다.
   통째 조건(버퍼 크기 · bs · fit 바뀜, 첫 그림, 통째 프레임, 앞 창 바뀜)이면 누적을 버퍼 전체로.
5. `logic.damageScreen(f, bs, r) ?Area` — 버퍼 사각형 → 화면(`p · k / bs`, 바깥으로 반올림, ox · oy를 빼고 f로 자름). 호스트 검사(k 1 · bs 1, k 2 · bs 1,
   k 1 · bs 2, 잘린 창).
6. `paint`가 누적이 부분이면 그 화면 사각형만 `blitClip`으로 옮기고 그 사각형을 돌려준다 — 부르는 쪽(셸 프레임의 app slot · `renderApp`)은 그것만
   `clips.push`하고 둘레 `fillRect`를 안 한다. 누적은 실제로 옮긴 뒤 비운다. 물리 합성은 손대지 않는다(clip을 따라간다).
7. 로그 `wl> blit id= x= y= w= h= us=`(통째 · 부분 둘 다, terminal 하나에 처음 몇 번만 — `frame full`과 같은 상한).
8. `tars-wl-test --damage`: 창 전체를 한 번 칠하고, 그 뒤 frame마다 왼쪽 위 32 × 32 상자의 색을 바꿔 그 자리만 `damageBuffer`.

## 체인

wayland 부팅 1, 판정 28 뒤 · 9 앞:

29. 호환 모드. (가) 기본 창(`tars-wl-test --follow-size`)에 `alt-v` → 클라이언트 `mods depressed=0x4`가 있고 `0x40`이 없다, `key code=47`.
    (나) `--native` 창에 `alt-v` → `mods depressed=0x40`, 서버 `wl> keys pid=N native`. (다) 호환 창에서 `alt-1`(표)은 여전히 workspace — 클라이언트에 키 2가 안 간다.
30. damage. `--damage` 창 → `wl> blit id=ID … w=32 h=32` 한 줄 이상(부분), 다음 screendump에서 상자 자리 색이 바뀌고 상자 밖 한 점은 그대로. 판정 9(verify)가
    clip 판정으로 함께 지킨다.

## 할 일

1. (A) `compatMask`와 호스트 검사(Super만 · Super+Shift · Super+Ctrl · 없음), 서버 두 자리.
2. (A) `tars_menu_v1` xml · `build.zig` · global · `ClientRec.native` · 로그.
3. (A) `tars-wl-test --native`, 판정 29, 머리 주석 · PASS 줄. 도움말에 "앱에는 `Cmd`가 `Ctrl`로 간다(TARS 툴킷 앱은 `Cmd` 그대로)" — WY-M4 한 줄을 고친다.
4. (B) damage 누적 · `damageScreen` · `paint`의 부분 길 · 부르는 쪽 둘.
5. (B) `tars-wl-test --damage`, 판정 30.
6. (B) 실측 5 · 7을 `docs/guides/measurements.md`에 번호로(hidpi 배율 2 bs 2 한 번 — 임시 스크립트로 충분).
7. lead: 체인 · verify grep · 루트 게이트.

## 판정

- 호스트 검사, 체인 wayland · hangul · pointer · display · hidpi · pane PASS, 루트 게이트 35/35, verify mismatch 0.

## plan에서 실측할 것

1. 호환 모드의 SDL Ctrl+V — 실측 불가(SDL 붙여넣기 앱 없음), 소스 사실로. 2. `Cmd`만 눌렀다 뗀 호환 창의 줄(`0x4` → `0x0`).
3. zig-wayland가 만든 `tars_menu_v1` 이름. 4. `damage` · `damage_buffer`를 섞는 commit. 5. 부분 blit 32 × 32의 `us`와 통째의 `us`(배율 1 · 배율 2 bs 2),
   그 프레임의 `px=`. 6. 판정 9 · 루트 게이트의 verify mismatch 0. 7. 여러 commit이 한 프레임에 모일 때 합집합(상자 둘이 다 그려지는가).
