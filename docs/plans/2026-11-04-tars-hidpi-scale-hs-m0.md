# HS-M0 — 그림자 + 늘리는 present, `display_scale`의 길, `hidpi` 체인

> 구현 파일은 서브에이전트가 넣고, lead가 diff를 실제 파일과 대조한 뒤 루트 게이트 · commit한다. 줄 번호는 2026-11-04
> `ec94555` 기준이라 낡을 수 있다 — 고치기 전에 `rg`로 다시 찾는다.

Goal: HS design 결정 1~6을 한 milestone에 넣는다. 2880×1800 화면에서 terminal이 논리 1440×900의 그림자에 지금처럼 그리고,
`present`가 바뀐 사각형만 정수배로 늘려 dumb 버퍼에 옮긴다. 배율은 `tars.conf`의 `display_scale`(`auto` · `1` · `2` · `3`)이다.
배율 1은 HS 전과 같은 길이다 — 그림자가 없고 `present`의 첫 줄이 갈래를 가른다.

Architecture: 순수한 반쪽(배율 고르기 `scale.pick`, 사각형 늘리기 `scale.upscale`)은 새 파일 `terminal/src/scale.zig`이고
호스트 검사 `scale_test`가 본다. 화면에 닿는 반쪽은 `drm.zig` — `Framebuffer`가 `scale` · `out` · `out_pitch`를 더 들고, `open`이
배율을 골라 그림자를 잡고, `present`가 배율이 1보다 크면 `presentScaled`로 간다. 설정은 PS-M0(`d2244ce`)의 길을 그대로 밟는다 —
init `config.zig`의 키 하나 → `screen_args`의 칸 하나(`ARGC` 14) → terminal `decode` → `drm.open`의 인자.

## 착수 전에 확인한 것 (2026-11-04, `ec94555`)

1. `drm.open`은 `main.zig`의 `openScreen` 한 자리에서 불리고, `fb.present`는 둘(`presentFrame`, 포인터만 움직인 회차의 화살표
   present)이다. 둘 다 `drm.ClipList.init(self.fb.width, self.fb.height)`의 clip을 넘긴다 — fb가 논리 크기면 clip도 논리 좌표다.
2. 렌더 · 덤프 · verify가 `self.fb`에서 읽는 것은 `width` · `height` · `pitch` · `pixels`뿐이다(`getPixel` · `fillRect` ·
   `setPixel` · `copyClips`의 `@memcpy`). 그래서 이 넷을 논리 그림자로 돌리면 렌더러 쪽은 한 줄도 안 바뀐다(design 결정 1).
   `modeset` · `present`만 `fd` · `fb_id`를 쓴다.
3. `openScreen`(준비 1)이 `readArgs`(준비 2)보다 먼저였다. `readArgs`는 argv를 되돌릴 뿐(시스템 콜 · 로그 없음)이라 앞으로
   당겨도 로그 순서가 안 바뀐다.
4. `drm.zig`는 `c_drm` 번역을 끌어와 호스트 검사에서 못 돈다(호스트 검사 모듈 어디도 `drm.zig`를 import하지 않는다). 그래서
   검사할 셈은 따로 뺀다(확정 2).
5. 격자 셈: `GRID_X` · `GRID_Y` 20, `CELL_W` 8, `ROW_HEIGHT` 16. 1440×900은 (1440 − 40) / 8 = 175열, (900 − 40) / 16 = 53행.
   2880×1800은 355열 × 110행이다 — 사용자 요청의 "360열 × 112행"은 여백을 뺀 셈이 아니었다. 판정은 355를 본다.
6. QEMU(컨테이너)의 `virtio-gpu-pci` 속성은 `xres` · `yres`(기본 1280 · 800), `edid` 기본 on이다
   (`qemu-system-x86_64 -device virtio-gpu-pci,help`). 커넥터의 첫 모드가 그 크기다.
7. PS-M0이 키를 더하며 고친 자리(`git show d2244ce --stat`): `screen_args.zig`(+ 검사), init `config.zig` · `reload.zig` ·
   `main.zig`(config 줄 · reload terminal 줄 · `encode`) · `config_edit.zig`(`hint` — enum이면 저절로), ARGC 길이의 argv 상수 여섯
   (`bluetooth` 둘 · `clock` · `net` · `wifi` · `main` 둘), `gate_lib.sh`의 `cut_log_lines` 정규식과 그 자가검사 글자(`check.sh`),
   `config/check.sh`의 `TC_LIST_WANT`, 호스트 검사 넷(`config_test` · `config_edit_test` · `reload_test` · `screen_args_test`).
8. 판정의 "논리 그림과 맞춰 본다": terminal의 `dumpInk`가 폭 2칸 글자의 칸에서 논리 fb를 되읽어 바탕과 다른 픽셀을 센다
   (`terminal: ink> R,C U+XXXX left=L right=R`). fish는 `echo 한`를 `한`으로 찍는다. 그 칸의 물리 상자(32×32)의 잉크가
   `4 × (L + R)`이면 늘린 그림이 논리 그림과 픽셀째 같다.

## 확정 (design을 코드로 옮기며 정한 것)

1. 값의 이름: `screen_args.DisplayScale = enum { auto, @"1", @"2", @"3" }`. 이름이 숫자인 enum이라 `@tagName`이 곧 설정 파일과
   argv의 글자이고, init의 `parse` · `hint`(`auto | 1 | 2 | 3`) · `reload.same` · `fieldText`가 다른 enum 키와 같은 갈래로 다룬다.
   `fixed() ?u32`가 `auto`면 null, 숫자면 그 수다. `Accel`처럼 구조체로 감쌀 이유가 없다 — 받는 값이 넷뿐이다.
2. `terminal/src/scale.zig`(순수): `pick(fixed: ?u32, w, h) u32`와 `upscale(src, src_pitch, dst, dst_pitch, Rect, s)`. `pick`은
   `fixed`가 있으면 그것(1~3으로 자름), 없으면 `clamp(min(w / 1280, h / 800), 1, 3)`. 강제한 배율은 화면이 작아도 쓴다 — 사람이
   적은 값을 조용히 바꾸지 않는다(PS design 결정 6과 같은 규칙), `kms: scale` 줄이 말한다. `upscale`은 논리 행마다 물리 첫 행을
   픽셀째(`@memset` s칸) 짓고 나머지 `s − 1`행은 그 행을 `@memcpy`한다.
3. `drm.Framebuffer`에 `scale: u32 = 1` · `out: [*]u8` · `out_pitch: u32`. 배율 1이면 `out == pixels`이고 아무도 안 읽는다.
   1보다 크면 `width` · `height` · `pitch` · `pixels`가 논리 그림자(heap, `pitch = width × 4`)이고 `out`이 dumb 버퍼다.
   `shadow()`(verify의 그림자)는 `out = pixels`다 — `present`를 부르면 안 되는 값이라 그대로다.
4. `present`의 첫 줄이 `if (self.scale != 1) return self.presentScaled(clips);`이다. 그 아래는 한 글자도 안 바뀐다(design 결정 2).
   `presentScaled`는 clip마다 `upscale`하고 `scale`을 곱한 clip을 스택의 `[MAX_CLIPS]Clip`에 지어 DIRTYFB에 넘긴다. clip이 없으면
   논리 전체를 옮기고 DIRTYFB도 clip 없이. DIRTYFB를 안 받는 드라이버는 옮긴 뒤 `modeset`이다.
5. `drm.open(allocator, path, want: ?u32)`가 dumb 버퍼 · fb · DIRTYFB 물음까지 지금처럼 한 뒤 배율을 고른다. 1보다 크면 논리 크기를
   내림(`dumb.width / s`)으로 정하고 그림자를 잡고 물리 버퍼를 0으로 한 번 지운다 — 나머지 띠가 검게 남는다(design 결정 3 끝).
   줄은 `kms: present by …` 다음에 늘 하나: `kms: scale N (WxH -> wxh)`.
6. `App.open`의 순서: `readArgs` → `openScreen(a.display_scale)` → `openVerify` → `spawnFirst(a)`(확인 3).
7. init의 두 줄(`tars-init: config …` · `reload terminal: …`)은 맨 끝에 `display_scale=`를 붙인다. 앞 줄을 끝을 못 박고 보는 체인
   (`pane` · `pointer`)이 그대로다. `cut_log_lines`의 정규식과 `check.sh`의 자가검사 글자를 함께 고친다(확인 7).
8. `reload.groupOf`에서 `display_scale`은 `terminal` 갈래다 — `reload terminal`이 terminal을 다시 띄우고 그 terminal이 화면을 다시
   연다(design 결정 4). 갈래 수는 4/3/11/1이 된다.
9. 견본의 주석은 PS의 포인터 넷처럼 영어 세 줄이다(`# display_scale: auto | 1 | 2 | 3` …). 견본은 3574바이트(`MAX_FILE` 4096),
   `user=`가 붙으면 3814바이트다(config_test가 찍는다).
10. design 결정 4의 "`tars-config set display_scale=…`과 `tars-config reload terminal`이 바로 적용한다"에는 한 걸음이 빠져 있다 —
    `reload terminal`은 init이 지금 쓰는 값(`live.cfg`)으로 argv를 짓고, 그 값은 `tars-config reload`가 파일을 다시 읽어야 바뀐다
    (`doReloadTerminal`, PS-M0의 pointer 부팅 C와 같은 순서). 그래서 체인은 set → reload → reload terminal을 친다. 코드가 아니라
    design의 문장이 짧았던 것이라 design은 그대로 두고 여기 적는다.
11. monitor 포트는 45502 하나다. 두 부팅이 차례로 돌고, 앞 QEMU를 거둔 뒤 같은 번호로 다시 연다(QEMU의 listen 소켓은
    `SO_REUSEADDR`). 45503은 안 쓴다.

## Task 1: `screen_args` · init — 키 하나의 길

- `DisplayScale`(확정 1), `Slot.display_scale = 13`, `ARGC` 14, `default_display_scale = .auto`, `Args.display_scale`, `encode` ·
  `decode`(`enumAt`).
- init: `config.DisplayScale`, `Config.display_scale = .auto`(`touchpad_accel` 다음, `user` 앞), `parse`의 갈래(clipboard와 같은
  모양, `unknown display_scale '…', falling back to …`), 견본 세 줄(확정 9), `reload.groupOf`(확정 8), `main.zig`의 config 줄 ·
  reload 줄 · `doReloadTerminal`의 `a.display_scale` · 부팅의 `encode`. ARGC 길이 상수 여섯에 `null` 하나씩.
- `gate_lib.sh` · `check.sh` 자가검사 · `config/check.sh` `TC_LIST_WANT`(확정 7).

## Task 2: 호스트 검사

- `screen_args_test`: `DisplayScale` 왕복, `fixed()`, `4` · `1.5`를 안 받음, 13번 칸, `Args` 왕복 둘에 값, 빈 argv의 기본값, 엉뚱한
  글자(`4`)가 그 칸만 기본값, `argvOf`의 마지막 칸.
- `config_test`: `display_scale=1` · `2` · `3` · `auto` · `4` · `1.5` · 빈 값 · 틀린 둘째 줄이 앞 값을 안 지움 · 체인 부팅 B의 줄.
  `expect`의 비교와 실패 줄에 필드 하나.
- `config_edit_test`: 키 19, `OTHER`에 `display_scale=2`, `hint`가 `auto | 1 | 2 | 3`, `set display_scale=4` · `=1.5`가 init의
  말로 거절, `showKeyLines`의 `#display_scale=auto`.
- `reload_test`: `OTHER`에 한 칸(비트 순서가 필드 순서), 갈래 4/3/11/1, `configReply`의 `display_scale=auto`.
- `scale_test`(새): `pick`의 design 표 전부와 1024×768 · 640×480(0이 안 된다) · 7680×4800(상한), 강제 셋. `upscale`을 s = 1 · 2 · 3에서
  전체 · 가운데 조각 · 픽셀 하나 · 빈 사각형으로, 물리 pitch에 여분을 두고 물리 픽셀 전부를 본다(안은 논리 픽셀, 밖은 표식).

## Task 3: terminal

- `scale.zig`(확정 2), `build.zig`에 `scale_test`(pacing_test와 같은 모양).
- `drm.zig`(확정 3 · 4 · 5), `getPixel` 주석에 "배율이 있으면 논리 그림자를 읽는다".
- `main.zig`(확정 6). `CELL_W` · `ROW_HEIGHT` · 렌더 · 포인터 · 상태 줄은 안 바뀐다.

## Task 4: `hidpi/check.sh`(HS-M0) — 스물여덟째 체인

`-device virtio-gpu-pci,xres=2880,yres=1800`, monitor 45502, 머리는 다른 체인과 같은 빌드 여섯.

| | 부팅 | 판정 |
|---|---|---|
| 1 | A(디스크 없음) | `kms: connector … mode 2880x1800` · `kms: scale 2 (2880x1800 -> 1440x900)` · `terminal: grid 175x53 (fb 1440x900)` · config 줄의 `display_scale=auto` |
| 2 | A | 첫 프레임의 screendump가 2880x1800, 화면 전체에서 2×2 블록의 어긋남 0, 프롬프트 행(물리 (40, 40) 224×32)에 잉크 |
| 3 | A | `echo 한` 뒤(부분 프레임) — `ink> R,C U+D55C left=L right=R`의 칸의 물리 상자 32×32 잉크 = 4 × (L + R), 화면 전체 어긋남 0 |
| 4 | B(`display_scale=1`) | loaded 줄 · config 줄의 `display_scale=1` · `kms: scale 1 (2880x1800 -> 2880x1800)` · `terminal: grid 355x110 (fb 2880x1800)` · 프롬프트 행의 2×2 어긋남 > 0(판정 2의 셈이 늘리기를 실제로 가른다) |
| 5 | B | `tars-config set display_scale=2` → `display_scale: 1 -> 2`, `tars-config reload` → `tars-init: reload of /config/tars.conf`, `tars-config reload terminal` → init의 reload 줄 `display_scale=2`, 새 terminal의 `kms: scale 2 …` · `grid 175x53` · 프롬프트 |

`tars-config set`의 거절(`4` · `1.5`)은 `config_edit_test`가 본다 — 게스트에 칠 이유가 없다.

루트 `check.sh`: `CHAINS` 끝에 `"HS-M0:./hidpi/check.sh"`, 설명 단락 하나.

## Task 5: 체인 · mutation

1. 컨테이너에서 init · terminal `zig build test`, `zig fmt --check`(고친 파일).
2. `hidpi` 체인, 그리고 바뀐 길을 밟는 기존 체인 넷(`render` · `terminal` · `config` · `pointer`). `TARS_RENDER_VERIFY=1`로 돌리고
   회차의 `terminal: verify>` 줄이 전부 `ok`인지 본다(루트 게이트의 `check_verify_lines`와 같은 셈).
3. mutation(하나씩 넣고 `hidpi`만 돌린 뒤 되돌린다):

| | 망가뜨린 것 | 잡아야 할 판정 |
|---|---|---|
| a | `presentScaled`가 clip이 있으면 늘리기를 건너뛴다(통째만 옮긴다) | 3(한글의 물리 잉크 0) |
| b | `open`이 배율을 늘 1로 둔다 | 1(`scale 1`) |
| c | terminal이 `display_scale`을 무시한다(`openScreen`에 늘 `.auto`) | 4(부팅 B가 `scale 2`) |

## Task 6: 잰다

TCG에서 배율 2의 present 하나(통째 · 키 하나)가 얼마인지. 측정용으로만 `presentFrame` 앞뒤의 시각을 한 줄 찍는 계측을 넣고
`hidpi` 체인 한 판의 로그에서 읽은 뒤 지운다.

## 결과 (2026-11-04, 서브에이전트, worktree `hs`)

### 단위 검사

- init `zig build test` 통과 — `screen_args_test: all checks passed`, `config_edit_test: nineteen keys …`,
  `reload_test: nineteen keys in four groups — four now, three at the next spawn, eleven on the screen, one at the next boot`,
  `config_test: user= saved 3814 bytes (3574 without it)`.
- terminal `zig build test` 통과 — `scale_test: 1. auto keeps the screen at least 1280x800, 1..3 OK` · `2. a fixed scale wins
  over auto OK` · `3. upscale writes s x s blocks inside the rect and nothing outside OK`.
- 고친 Zig 파일 `zig fmt --check` 깨끗(init `main.zig` · `reload.zig`는 fmt가 줄을 맞춘 뒤).

### 체인 (`TARS_RENDER_VERIFY=1`, 회차마다 `verify>`가 전부 `ok`)

| 체인 | 결과 | 비고 |
|---|---|---|
| `hidpi`(HS-M0) | PASS | 부팅 A `verify> ok` 20, 부팅 B 60(reload 뒤의 terminal 포함), 잘린 줄 0 |
| `render` | PASS | `ok` 685, `kms: scale 1 (1280x800 -> 1280x800)` |
| `terminal` | PASS | `ok` 49, `grid 155x47 (fb 1280x800)` 그대로 |
| `config` | PASS | `ok` 1725, `tars-config list`의 `display_scale=auto` |
| `pointer` | HEAD에서 빨강, 아래 | 부팅 전 검사가 멈춘다. 그 한 줄을 임시로 뺀 판은 PASS(`ok` 876, PS-M0 · PS-M1 PASS) |

`pointer`의 빨강은 HS와 무관하다. MB-M0(`dad558c`)이 `CONFIG_MOUSE_BCM5974=y`를 켰는데 `pointer/check.sh`의 부팅 전 검사
(`for sym in HID_APPLE HID_MAGICMOUSE MOUSE_BCM5974 …`, PD design 결정 9)가 그 심볼을 아직 금지한다 —
`FAIL: CONFIG_MOUSE_BCM5974 is =y in kernel/.config, PD design 결정 9 leaves it off`. 이 plan에서는 고치지 않았다(lead의 몫). lead가 `c152f5d`에서 그 심볼을 금지 목록에서 뺐다(PD 비목표 10의 bcm5974 갈래를 MB가 열었다).

`hidpi` 한 판의 판정 줄:

```
kms: connector 38 connected, mode 2880x1800
kms: scale 2 (2880x1800 -> 1440x900)
terminal: grid 175x53 (fb 1440x900)
boot A: 2880x1800, 0 block mismatches, prompt row bg=102030 ink=960
boot A: terminal: ink> 1,0 U+D55C left=28 right=22 -> physical (40,72) 32x32 bg=102030 ink=200
kms: scale 1 (2880x1800 -> 2880x1800)
terminal: grid 355x110 (fb 2880x1800)
boot B: scale 1, grid 355x110, the prompt row has 93 2x2 mismatches (drawn at 1x)
tars-init: reload terminal: pid 39, shell /usr/bin/fish … touchpad_accel=0 display_scale=2
kms: scale 2 (2880x1800 -> 1440x900)
terminal: grid 175x53 (fb 1440x900)
```

`ink=200 = 4 × (28 + 22)` — 부분 present가 옮긴 한글 한 글자가 논리 그림과 픽셀째 같다. 체인 한 판은 빌드가 캐시일 때 약 4분이다.

### mutation (하나씩 넣고 `hidpi`만, 되돌린 뒤 `git diff --stat`이 그대로인 것을 봤다)

| | 망가뜨린 것 | 잡은 판정 |
|---|---|---|
| a | `presentScaled`가 clip이 있으면 늘리기를 건너뛴다 | 3 — `U+D55C has 0 ink pixels on the physical screen, expected 4 x 50 = 200` |
| b | `open`이 배율을 늘 1로 둔다 | 1 — `no 'kms: scale 2 (2880x1800 -> 1440x900)'` |
| c | terminal이 `display_scale`을 무시한다(`openScreen(.auto)`) | 4 — `boot B: no 'kms: scale 1 (2880x1800 -> 2880x1800)'` |

a에서 판정 2(첫 프레임)는 통과했다 — 첫 프레임은 clip 없는 통째라 그 길을 안 지난다. 그래서 판정 3이 부분 present의 유일한 증인이다.
같은 판에서 프롬프트 행의 잉크가 960이 아니라 512였다 — fish가 프롬프트를 여러 프레임에 나눠 그리고, 뒤 프레임은 부분 present라 빠졌다.

### 잰 것 (TCG, arm64 호스트의 x86_64, `presentFrame` 앞뒤, 측정용 줄은 지웠다)

| 화면 | 프레임 | present |
|---|---|---|
| 2880×1800, 배율 2 | 첫 프레임(통째, 20.7MB를 짓는다) | 72.1ms (1회) |
| 2880×1800, 배율 2 | 키 하나 · 셸 출력(clip 1, 행 하나) | 중앙값 0.70ms (18회, 0.62~6.6ms) |
| 2880×1800, 배율 1 | 첫 프레임(통째, DIRTYFB만) | 0.65ms (1회) |
| 2880×1800, 배율 1 | 키 하나(clip 1) | 중앙값 0.30ms (63회) |

첫 프레임 전체(`render> first frame`)는 배율 2가 194~201ms, 배율 1(같은 화면, 355열)이 273~298ms다 — 늘리는 72ms를 더해도 칠할 셀이
네 배 적은 쪽이 빠르다. 통째 present가 다시 오는 것은 워크스페이스 전환 · 분할 · 닫기뿐이다(DR-M2). 키 하나는 행 하나(논리 1440×16)를
늘려 0.4ms쯤 더한다.
