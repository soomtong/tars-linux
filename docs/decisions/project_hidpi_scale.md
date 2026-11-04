---
name: project_hidpi_scale
description: "Retina 화면 배율(HS-M0, 2026-11-05) — 논리 그림자에 그리고 present가 바뀐 사각형만 정수배로 늘린다, display_scale=auto|1|2|3, 배율 1은 그대로. unifont는 늘려도 같은 그림이라 CELL_W를 안 건드렸다"
metadata:
  type: project
---

design은 `docs/specs/2026-11-04-tars-hidpi-scale-design.md`, plan은 `docs/plans/2026-11-04-tars-hidpi-scale-hs-m0.md`. MB 요청의 Retina 몫.

## 무엇이 섰나

- `drm.Framebuffer`에 `scale` · `out` · `out_pitch`. 배율이 1보다 크면 `pixels`가 논리 크기의 heap 그림자이고, `present`가
  `presentScaled`로 가서 clip마다 `scale.upscale`(순수 함수, `scale_test`가 물리 픽셀 전부를 본다) 뒤 늘린 clip으로 DIRTYFB.
- `display_scale`은 PS와 같은 길(`config.zig` → `screen_args` 칸 13, `ARGC` 14 → `openScreen`). auto = `min(w/1280, h/800)`을 1~3으로.
- 로그 `kms: scale N (WxH -> wxh)`는 배율 1에서도 찍힌다. 실기에서 무엇이 골라졌는지 이 줄로 본다.

## 배운 것

1. 셀 크기를 런타임 값으로 바꾸는 대신 present 한 층에서 늘렸다 — unifont는 16px에서 배율이 정확히 0.25라 안티앨리어싱이 없어서
   2×2 복제가 32px로 굽는 것과 같은 픽셀이다. 렌더 · 포인터 · 상태 줄 · 이미지는 논리 크기만 본다.
2. reload 줄 끝에 칸이 늘면 `gate_lib.sh`의 `cut_log_lines` 정규식과 루트 `check.sh`의 자가검사 글자를 함께 고친다.
3. `reload terminal`은 init이 지금 쓰는 값으로 띄운다. 설정을 바꿨으면 `tars-config reload` 뒤에.
4. 컨테이너 여럿이 같은 트리의 `.zig-cache`로 terminal을 동시에 빌드하면 깨진다(`libhighway.a: file not found`). 체인을 동시에 돌리려면
   한 컨테이너 안에서.
5. TCG 2880×1800: 통째 present 72ms, 키 하나 0.70ms. 칠할 셀이 적어 첫 프레임 전체는 배율 2가 오히려 빠르다(194~201 대 273~298ms).

관련: [[project_macbook_hardware]] · [[project_render_speed]] · [[project_dirty_rows]] · [[project_pointer_settings]]
