# TARS Render Speed RS-M1 — 칠하기를 행 단위 `@memset`으로

Design: `docs/specs/2026-10-11-tars-render-speed-design.md` · 기준선: RS-M0(`a2fd36a`)

프레임버퍼에 찍히는 값은 바이트까지 같게 두고 칠하는 방법만 바꾼다(design 결정 4). 판정은 기존 게이트가, 효과는
RS-M0의 프로브가 한다.

## 착수 전에 소스로 확정한 것

1. 사각형을 한 색으로 칠하는 자리는 셋이다 — `drm.zig`의 `fill`(화면 전체), `main.zig`의 `drawCellBackground`(셀 하나,
   구분선과 프롬프트 반전도 이것), `main.zig`의 `fillRect`(bar · underline 커서 띠). 셋 다 픽셀마다 `setPixel`이다.
2. `setPixel` · `getPixel`은 그 밖에 글리프(`drawGlyph`) · 이미지(`image.zig`) · 화살표(`pointer.zig`) · 덤프가 쓴다. 한 점씩
   다루는 자리라 그대로 둔다. `image.zig` · `pointer.zig`는 대상을 `anytype`으로 받으므로 시그니처가 같으면 안 바뀐다.
3. `pixels`의 `volatile`은 지켜 주는 것이 없다. dumb buffer는 `MAP_SHARED`로 잡은 보통 메모리이고 장치 레지스터가 아니다.
   포인터가 `mmap`(extern)에서 와 struct에 담겼으므로 컴파일러는 그 메모리를 `ioctl`(extern)이 읽을 수 있다고 봐야 하고,
   그래서 `present` 앞의 쓰기를 지울 수 없다. 렌더 뒤 `getPixel`로 되읽는 덤프도 같은 메모리라 순서가 지켜진다.
4. `present()`의 `kms: set crtc …` 줄은 프레임마다 시리얼 한 줄이고 `frame_us` 안이다. `rg 'set crtc'`로 이 줄을 읽는 체인이
   없다. `gate_lib.sh`의 `joined_screen_dump`가 `^(terminal|kms): `를 줄의 경계로 보지만 경계가 하나 줄 뿐이다.

## 바꾸는 것

| 파일 | 변경 |
|---|---|
| `drm.zig` | `pixels: [*]volatile u8` → `[*]u8`. `setPixel` · `getPixel`의 포인터도 `volatile`을 뺀다. `fillRect(x, y, w, h, color)`을 더한다 — 행마다 그 행의 `[*]u32`를 구해 `@memset(row[0..w], color)` 한 번. `fill`은 `fillRect(0, 0, width, height, color)`. `present`의 `logline.print` 줄을 지운다 |
| `main.zig` | `drawCellBackground`의 본문이 `fb.fillRect(x, y, CELL_W, ROW_HEIGHT, color)` 한 줄. `main.zig`의 `fillRect`를 지우고 부르는 자리(커서 띠)가 `fb.fillRect`를 부른다. 그 함수의 범위 주석은 부르는 자리로 옮긴다 |

`fillRect`도 범위 검사를 안 한다 — `setPixel`과 같은 규율이고, 부르는 자리가 이미 격자 · 화면 안으로 자른 사각형만
넘긴다(1의 셋 다).

## 게이트

1. `zig build test`(호스트 검사) — `drm.zig`를 직접 보는 검사는 없지만 `main.zig`의 컴파일이 함께 걸린다.
2. 프로브 3회(`m1` 라벨) — RS-M0 표와 비교한다. 기대: (a)의 `frame`과 (b)의 `frame_sum`이 크게 준다. `frames`는 그대로
   365다(합치기는 M2). `dump` · `other`는 그대로다.
3. 루트 게이트(약 10분) — 22체인. 픽셀 동일의 판정은 `render`(`pixel>` · `ink>`) · `pane`(구분선 `SEPARATOR` 픽셀 수) ·
   `pointer`(화살표 save-under) · `hangul`(`ink fg=`) 체인이 한다.

## 결과 (2026-10-11)

호스트 검사 PASS. diff는 더한 줄 29 · 지운 줄 34(`drm.zig` · `main.zig`), 지운 줄은 픽셀 루프 셋 · `volatile` 셋 ·
`kms: set crtc` 한 줄 · `main.zig`의 `fillRect` 본문이고 그 범위 주석은 부르는 자리로 옮겼다.

프로브 3회(`m1`), RS-M0과 같은 판:

```
m1-run1  (b) span=2943ms frames=367 frame_sum=698ms dump_sum=448ms other=1798ms   (a) frame=4.901 dump=4.489
m1-run2  (b) span=2963ms frames=367 frame_sum=682ms dump_sum=472ms other=1809ms   (a) frame=3.303 dump=4.388
m1-run3  (b) span=2959ms frames=366 frame_sum=698ms dump_sum=452ms other=1809ms   (a) frame=4.771 dump=4.485
```

| | M0 | M1 | |
|---|---|---|---|
| (b) span | 5,501ms | 2,959ms | −46% |
| (b) frame 합 | 3,364ms | 698ms | −79% |
| (b) dump 합 | 377ms | 452ms | +20% |
| (a) frame | 11.6ms | 4.9ms | −58% |
| (a) dump | 2.6ms | 4.5ms | +73% |

`frames` · `other`는 그대로다(합치기는 M2, `other`는 파서 몫). 덤프가 는 것은 덤프 코드가 안 바뀌었으므로 시리얼
쪽으로 본다 — 가설: 프레임이 빨라져 다음 덤프가 앞 덤프의 UART 배출이 끝나기 전에 와서 `write`가 tty 버퍼를 기다린다.
확인은 안 했다. 이제 (a)에서 덤프가 그리기와 비슷한 크기다.

루트 게이트(22체인 × 1, 동시 6): 22체인 전부 `PASS: 1/1`, prebuild 234초 + 줄 321초 = 9분 15초, `skipping make` 22,
잘린 줄 0. 픽셀 동일은 `render` · `pane` · `pointer` · `hangul` 체인이 그대로 지나간 것으로 본다.
