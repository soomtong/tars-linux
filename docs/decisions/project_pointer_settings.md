---
name: project_pointer_settings
description: "Pointer Settings(PS-M0~M1, 2026-11-04 끝남) — tars.conf의 mouse_scroll · touchpad_scroll · mouse_accel · touchpad_accel(0~10)을 장치 칸마다 든다. 휠은 칸의 부호, 이동은 pointer.Ballistics. 함정 — 두 칸이 같은 값인 게이트 조합은 '종류를 안 본다'를 못 잡는다, screen_row가 쓰는 중인 줄을 읽는다"
metadata:
  node_type: memory
  type: project
---

# Pointer Settings (PS)

design은 `docs/specs/2026-11-04-tars-pointer-settings-design.md`, plan은 `docs/plans/2026-11-04-tars-pointer-settings-ps-m0.md` ·
`-ps-m1.md`. PD design 비목표 6(가속) · 7(휠 방향)이 이리로 왔다. 사용자가 요청했고(2026-11-04) M0부터 끝까지 맡겼다.

## 사용자가 정한 것 (2026-11-04)

- 키는 종류별 넷 — `mouse_scroll` · `touchpad_scroll`(`normal` | `natural`), `mouse_accel` · `touchpad_accel`(0~10).
- 방향의 기본값은 PS 전 동작 그대로(마우스 `normal` · 터치패드 `natural`), 가속 기본 0.
- 가속은 0~100이 아니라 0~10 — 실기 근거 없이 101단계를 구분할 수 없다.
- 기본 속도(`*_speed`)는 비목표.

## 결정

- 값은 `shared/screen_args.zig`(`WheelDirection` · `Accel`, argv 칸 9~12, `ARGC` 13) → terminal `pointer.Prefs` → `takePointer`가 종류로
  반쪽을 골라 `PointerDev.wheel_sign` · `ballistics`에 든다(KK의 `swap_alt_meta`와 같은 모양).
- 적용은 `drainPointer`에서 디코더가 낸 Frame을 합치기 전 — 휠에 부호, 이동에 `Ballistics.apply`. 디코더 둘은 안 바뀌었다.
- `pointer.Ballistics`: 직전 이동 보고와의 간격으로 속도를 재고 `V_LOW` 0.3 · `V_HIGH` 3.0 px/ms 사이에서 배율 1 → `1 + level/10 × 3`,
  `IDLE_US` 100ms, 1/1000 고정소수점 + 축마다 끝수. 단계 0은 첫 줄에서 그대로 돌려준다(비트 단위로 PS 전과 같다). 출발값 넷은
  재지 않았다(design 위험 2).
- 게이트는 `pointer` 체인 부팅 C(monitor 45501) — 디스크에 `mouse_scroll=natural touchpad_scroll=normal touchpad_accel=10`.
  판정 가~마(휠 · reload terminal), 바(`tp-replay move 100 0`이 부팅 B의 128px보다 멀리, 상한 512).

## 함정

1. 게이트 설정이 두 칸에 같은 결과를 주면 "칸이 종류를 안 보고 다른 종류의 값을 쓴다"를 못 잡는다. M0의 마우스 natural ·
   터치패드 normal은 부호가 둘 다 −1이라 mutation b가 초록이었다 → 판정 마(부호가 다른 칸). M1은 처음부터 `mouse_accel=0` ·
   `touchpad_accel=10`으로 갈랐다. "기본값의 반대"를 고를 때 결과(부호 · 배율)가 칸마다 다른지를 본다.
2. `screen_row`(`pointer/check.sh`)가 시리얼 로그에 쓰이는 중인 `screen>` 줄을 읽어 아래 행이 없을 수 있다 — 3초 재시도(M0 실측 4).
3. 판정 라 · 마는 "읽어 둔 offset − 6"이 아니라 바닥에서의 거리(total − len − offset)로 본다. 도구를 띄운 명령의 줄바꿈이 늦게
   와 total이 는다.
4. TCG에서 `tp-replay`의 8ms 걸음이 늘어나 가속 이동이 셈(약 294px)보다 짧다(247px). 가속 판정은 값이 아니라 범위로 둔다.
