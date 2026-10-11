# TARS Render Speed RS-M3 — `present`를 DIRTYFB로

Design: `docs/specs/2026-10-11-tars-render-speed-design.md` · 앞 milestone: RS-M2(`f34df27`)

`present()`는 프레임마다 SETCRTC(모드셋)를 한다. 화면이 바뀌었다고 알리는 데 맞는 ioctl은 `DRM_IOCTL_MODE_DIRTYFB`이고,
모드셋은 시작에 한 번이면 된다. 이 milestone은 그 API를 제자리에 놓는다.

## 착수 전에 커널 소스(6.18.42)로 확정한 것

1. 두 드라이버가 다 지원한다. virtio-gpu(게이트 21체인)는 fb funcs에 `.dirty = drm_atomic_helper_dirtyfb`
   (`virtgpu_display.c:63`), simpledrm(`machine` 체인과 실기)은 `fb_create = drm_gem_fb_create_with_dirty`
   (`drm_sysfb_helper.h:175`) — 같은 helper다.
2. `.dirty`가 없는 드라이버면 ioctl이 `-ENOSYS`다(`drm_framebuffer.c`의 `drm_mode_dirtyfb_ioctl`). 판정은 드라이버의 funcs만
   보므로 plane에 걸기 전에 물어도 답이 같다. 걸리지 않은 fb의 dirty는 아무 일도 안 한다(`drm_damage_helper.c`가 그 fb를 쓰는
   plane만 고른다).
3. `num_clips = 0` · `clips_ptr = 0`은 fb 전체가 손상이라는 뜻이다(둘 중 하나만 0이면 `-EINVAL`).
4. `present`를 부르는 자리는 셋이다 — `main`의 시작(`fill` 뒤), `renderFinish`, 화살표만 고치는 갈래.

## 바꾸는 것

| 파일 | 변경 |
|---|---|
| `drm.zig` | `DrmModeFbDirtyCmd` 구조체. `Framebuffer.dirty: bool`. `open()`이 fb를 만든 뒤 DIRTYFB를 한 번 시험해 `dirty`를 정하고 `kms: present by dirtyfb` 또는 `kms: present by setcrtc` 한 줄을 찍는다. 지금 `present`의 본문(SETCRTC)은 `modeset()`이 된다. `present()`는 `dirty`면 DIRTYFB(clip 0), 아니면 `modeset()` |
| `main.zig` | 시작의 `fill` 뒤 `fb.present()`를 `fb.modeset()`으로. 모드셋은 여기 한 번이다 |
| `render/check.sh` | `kms: present by dirtyfb`(virtio-gpu) |
| `machine/check.sh` | 판정 3 뒤에 같은 줄(simpledrm) — 실기의 드라이버를 게이트가 직접 본다 |

- 모르는 드라이버는 지금과 같다(`dirty`가 false면 SETCRTC).
- clip은 안 쓴다. 손상 사각형을 아는 자리는 부분 갱신이 생길 때다 — 그때 `present`에 사각형을 넘기면 simpledrm이 VRAM으로
  옮기는 양이 준다. 이 milestone이 하는 것은 프레임마다의 모드셋(atomic check · commit 전체)을 없애는 것이다.

## 게이트

1. `zig build test`.
2. 프로브 3회(`m3`). QEMU에서 효과는 작다고 본다(RC-M0의 `present` 4%). (a)의 `frame`이 같거나 조금 준다.
3. 루트 게이트. 새 검사 둘(`render` · `machine`).

## 결과 (2026-10-11)

호스트 검사 PASS. 로그에 `kms: present by dirtyfb`.

프로브 3회(`m3`):

```
m3-run1  (b) span=2184ms frames=127 frame_sum=236ms dump_sum=185ms other=1762ms   (a) frame=4.565 dump=4.169
m3-run2  (b) span=2180ms frames=126 frame_sum=280ms dump_sum=152ms other=1747ms   (a) frame=3.773 dump=3.967
m3-run3  (b) span=2233ms frames=126 frame_sum=264ms dump_sum=184ms other=1785ms   (a) frame=3.415 dump=3.561
```

M2와의 차이는 잡음 안이다((b) 2,207 → 2,184ms, (a) frame 4.7 → 4.3ms). 기대한 대로다 — QEMU에서 모드셋은 원래 작았다.

### 루트 게이트 — 첫 판에서 pointer가 빨갰다, 꺼내는 함수들을 고쳤다

첫 판: 21 PASS, 새 검사 둘(`render` · `machine`) 초록. `PD-M4`가 `mouse_move 10 5` 뒤 마지막 `at` 줄이

```
ESC]133;A;special_key=1…root@(none) ~# …ESC[=5u=terminal: pointer> at x=650 y=405 buttons=0 wheel=0 shown=1 ink=118
```

라 `^terminal: pointer> at …`에 안 맞았다. M2 게이트와 같은 일(콘솔 fish의 프롬프트에 terminal의 줄이 붙는다)이 화면 줄이 아닌
줄에 일어났다. 콘솔 fish는 TCG에서 늦게 떠 프롬프트가 부팅 뒤 아무 때나 찍힌다. 프레임이 줄자 붙는 줄이 무해한 `screen>`에서
다른 줄로 옮겨 갔다.

처방: `gate_lib.sh`에 `from_terminal`(줄마다 첫 `terminal: ` 앞을 뗀다)을 두고, 마지막 줄을 꺼내 `^terminal:`로 대조하거나 줄
전체를 비교하는 자리 여섯이 거친다 — pointer의 `last_at` · `last_pane_line`, battery의 `last_line` · `redraw_alone` · `FIRST` ·
`FIRST_SCAN`. 루트 `check.sh`의 진입 검사 `require_screen_dump_joins`에 조각 `console`(M2의 `joined_screen_dump` 수정)과
`from_terminal`의 대조 하나를 더했다 — M2 때 빠뜨린 것이다(lessons "커널 printk가…" 절이 새 조각을 함께 더하라고 적고 있다).
둘 다 옛 `gate_lib.sh`(M2 전 · M3 전)에 대고 빨개지는 것을 봤다.

둘째 판: 22체인 전부 `PASS: 1/1`, prebuild 246초 + 줄 324초 = 9분 30초, `skipping make` 22, 잘린 줄 0.
