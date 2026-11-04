# TARS HiDPI Scale — Design

접두사: HS

Status: 닫힘(2026-11-05) — HS-M0 그림자 + 늘리는 present(`scale.zig`), `display_scale`(`ARGC` 14), `hidpi` 체인(monitor 45502). 결정 4의 "바로 적용"은 `tars-config reload` 뒤 `reload terminal`이다(plan 확정 10).

사용자의 요청(2026-11-04, MB design 머리의 인용)에서 "macbookpro 15 2013 … 레티나 디스플레이가 추가됨"을 받는다. MB가 장치를,
DB가 설치기를 맡는다.

관련 문서: RM design(simpledrm이 펌웨어의 모드를 그대로 받는다 — 실기에서 패널의 네이티브 해상도), FS · FR(unifont 17, `font.zig`가
stb_truetype으로 16px에 굽는다), DR design(바뀐 행만 칠하고 clip으로 present), SB design(상태 줄 띠), PS design(설정 키가 argv 칸으로
terminal에 닿는 길).

## 한 줄 요약

terminal이 논리 해상도(물리 ÷ 배율)의 그림자 버퍼에 지금처럼 그리고, present가 바뀐 사각형만 정수배로 늘려 VRAM에 옮긴다. 배율은
`tars.conf`의 `display_scale`(`auto` · `1` · `2` · `3`, 기본 `auto`)이고 `auto`는 "논리 화면이 1280×800보다 작아지지 않는 가장 큰 정수"다.
배율 1은 지금과 비트 단위로 같은 길이다.

## 왜 이 모양인가

MacBook Pro Retina 15"는 2880×1800이다. 지금 terminal은 셀 8×16 고정이라 360열 × 112행, 글자 하나가 패널에서 약 0.9mm다.

### 확인 1 — 셀 크기는 상수이고 수십 자리에 박혀 있다

`terminal/src/main.zig`의 `CELL_W`(8) · `ROW_HEIGHT`가 렌더 · 포인터 좌표 · PTY 픽셀 크기 · kitty 이미지 · 상태 줄 · 다중 클릭 판정
(`pointer.MULTI_CLICK_PX == CELL_W`의 assert)에 쓰인다. 셀을 런타임 값으로 바꾸면 그 전부가 바뀐다.

### 확인 2 — unifont는 늘려도 같은 그림이다

`font.zig`는 unifont를 16px에 굽고 그때 배율이 정확히 0.25라 안티앨리어싱이 일어나지 않는다(`main.zig`의 주석). 비트맵 폰트를
32px로 다시 굽는 것과 16px 그림의 픽셀을 2×2로 늘리는 것은 같은 픽셀을 낸다. 그래서 "크게 그리기"를 "작게 그리고 늘리기"로 바꿔도
글자 모양에서 잃는 것이 없다.

### 확인 3 — present는 이미 사각형 목록을 받는다

`drm.Framebuffer.present(clips)`가 DR-M2부터 바뀐 사각형만 DIRTYFB로 넘긴다. `Framebuffer.shadow(pixels)`는 같은 크기의 다른 버퍼를
가리키는 값이다. 늘리기는 "논리 clip을 물리 clip으로 바꾸고, 그 사각형의 픽셀을 복제해 옮긴다"는 한 층으로 들어간다.

## 결정

1. 늘리기는 `drm.zig` 한 층이다. 배율이 1보다 크면 `App.fb`가 논리 크기의 메모리 버퍼(그림자)를 가리키고, 물리 dumb 버퍼는 따로
   든다. present가 논리 clip마다 그 사각형을 `scale × scale` 블록으로 물리 버퍼에 쓰고, `scale`을 곱한 clip으로 DIRTYFB한다. clip이
   없으면(전체 손상) 화면 전체를 옮긴다. 렌더 코드(`CELL_W` · `ROW_HEIGHT` · 포인터 · 상태 줄 · 이미지)는 한 줄도 안 바뀐다 — 그들에게
   화면은 논리 크기다.
2. 배율 1은 그림자를 안 만든다. 지금처럼 VRAM에 바로 그린다. 기존 체인 스물일곱이 그 길을 비트 단위로 그대로 밟는다.
3. `display_scale`(`tars.conf`) — `auto`(기본) · `1` · `2` · `3`. `auto`는 `min(width / 1280, height / 800)`을 내림하고 1~3으로 자른다.
   | 화면 | auto |
   |---|---|
   | 1280×800(QEMU 기본) · 1366×768(MacBookAir4,1) · 1920×1080 | 1 |
   | 2560×1600 · 2880×1800(Retina 15") | 2 |
   | 3840×2160 | 2 |
   | 3840×2400 | 3 |
   배율이 화면을 나누어떨어뜨리지 못하면 논리 크기를 내림하고 남는 오른쪽 · 아래 띠는 검게 둔다.
4. 설정이 닿는 길은 PS와 같다 — init `config.zig`의 키 하나 → `shared/screen_args.zig`의 `Args` 칸 하나(`ARGC` +1) → terminal의
   `decode`. `tars-config set display_scale=…`과 `tars-config reload terminal`이 바로 적용한다(terminal이 다시 뜨며 화면을 다시 연다).
5. 로그 한 줄 — `kms: scale N (WxH -> wxh)`. 배율 1이어도 찍는다(`kms: scale 1 (1280x800 -> 1280x800)`). 실기에서 사용자가 이 줄로
   무엇이 골라졌는지 본다.
6. 포인터는 논리 좌표로 움직인다. 같은 손의 움직임이 Retina에서 물리 픽셀로는 두 배를 간다 — macOS의 "points"와 같다.

## 게이트

새 체인 `hidpi/check.sh`(HS-M0)가 virtio-gpu를 2880×1800으로 물린다(`-device virtio-gpu-pci,xres=2880,yres=1800`). 판정은 plan이
정하되 적어도 다음을 본다.

- `kms: scale 2 (2880x1800 -> 1440x900)`과 `terminal: grid`의 열 · 행이 1440×900 기준이다.
- QEMU `screendump`의 그림이 2880×1800이고, 글자 하나의 픽셀이 2×2 블록이다(논리 그림과 맞춰 본다).
- 키를 친 뒤 바뀐 행이 물리 화면에도 그려졌다(부분 present가 늘린 사각형을 옮겼다).
- `display_scale=1`을 심은 부팅은 같은 화면에서 `scale 1`이고 격자가 360열이다(설정이 auto를 이긴다).

monitor 포트는 45502부터 쓴다(HANDOFF).

## 위험

1. 배율 2의 present 비용. 전체 손상이면 2880×1800 × 4바이트 = 20.7MB를 쓴다. 키 하나는 바뀐 행만이라 작다. TCG의 숫자는 M0이 잰다.
2. Apple 펌웨어가 Limine에게 넘기는 GOP 모드가 네이티브가 아닐 수 있다(예: 1440×900). 그러면 `auto`가 1을 고르고 화면은 그대로
   선명하다 — 틀린 것이 아니다. 로그 한 줄이 그것을 말한다.
3. Limine 메뉴(설치된 디스크의 3초)는 Retina에서 작게 보인다. 부트로더의 일이라 이 설계 밖이다.

## 비목표

1. 1.5배 같은 소수 배율. 비트맵 폰트를 늘리는 이 방식은 정수배만 선명하다.
2. 화면의 물리 크기(mm)로 DPI를 셈하기. simpledrm은 mm를 96 DPI로 지어 내므로 쓸 수 없다. EDID를 읽는 길은 나중에.
3. 큰 셀에 더 고운 폰트(벡터 폰트를 32px로). 폰트 선택(FS)의 일이다.

## Milestone

- HS-M0 — 그림자 + 늘리는 present, `display_scale`의 길, `hidpi` 체인.
