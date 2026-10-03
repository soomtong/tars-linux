# TG-M3 — PNG를 받고 서브프로젝트를 닫는다

Goal: design 결정 6. `sys.decode_png`를 `stb_image`로 채워 `f=100`(PNG)이 `EINVAL` 대신
그려지게 한다. 반사실 하나, 루트 게이트, 문서로 TG를 닫는다.

Architecture: `stb_truetype`과 같은 모양이다. `vendor_stb_image.sh`가 같은 고정 SHA에서
`stb_image.h`(v2.30)를 `terminal/vendor/`(커밋 안 함)에 받고, `src/stb_image_impl.c`가
구현을 PNG만 켜서 컴파일한다. Zig 쪽 `src/png.zig`가 `ghostty_vt.sys.DecodePngFn` 모양의
함수 하나를 내놓고, `Screen.init`이 그것을 `ghostty_vt.sys.decode_png`에 넣는다.

---

## 정한 것

1. 설치는 `Screen.init`이 한다. 이 변수는 프로세스 전역이라 `main.zig`에서 한 번 넣어도
   되지만, 그러면 `vt_test`가 게스트와 다른 디코더(없음)로 돈다. 화면을 만드는 쪽이
   전부 같은 것을 쓰게 하는 자리가 `init`이다. 같은 값을 여러 번 넣는 것은 무해하다.
2. 디코드 전에 머리만 읽는다. `stb_image`는 라이브러리의 제한된 할당자를 안 거치고
   `malloc`으로 푼다. 라이브러리의 상한(한 변 10000 · 400MB, `graphics_image.zig:17`)은
   데스크톱 기준이다. 그래서 `stbi_info_from_memory`로 폭·높이를 보고, RGBA로
   10,000,000바이트(저장 한도, design 결정 5)를 넘으면 `error.InvalidData`로 거절한다.
   `STBI_MAX_DIMENSIONS`도 10000으로 라이브러리와 맞춘다.
3. `stb_image`가 준 버퍼는 받은 할당자(`alloc`)로 복사하고 `stbi_image_free`로 돌려준다.
   라이브러리는 결과를 같은 `alloc`으로 해제한다(`sys.zig`의 계약).
4. 요청 채널은 4(RGBA)로 고정한다. 라이브러리는 PNG 결과를 rgba로 적는다
   (`graphics_image.zig:584`). 그래서 `vt.ImageFormat`에 gray를 더하지 않는다.
5. 컴파일 옵션은 `STBI_ONLY_PNG` · `STBI_NO_STDIO` · `STBI_NO_LINEAR` · `STBI_NO_HDR`.
   쓰지 않는 디코더와 파일 입출력을 뺀다.

## Task 1: vendor와 빌드

`vendor_stb_image.sh`(`vendor_stb_truetype.sh`를 그대로 따른다), `prepare.sh`에 한 줄,
`src/stb_image_impl.c`. `build.zig`에서 `vt.zig`를 import하는 모듈 셋(terminal · vt_test ·
image_test)에 include 경로와 C 파일을 더한다.

## Task 2: `png.zig`와 설치

정한 것 1~4.

## Task 3: 검사

`vt_test`:

| 검사 | 무엇 | 기대 |
|---|---|---|
| 75 | 2×2 PNG(이미지 1과 같은 네 색, 75바이트) | `format == .rgba`, 16바이트, 픽셀 `FF0000FF 00FF00FF 0000FFFF FFFFFFFF` |
| 76 | 진짜로 풀리는 1600×1600 단색 PNG를 `png.decode`에 직접 | `error.InvalidData` |
| 77 | 1580×1580 단색 PNG(9,985,600바이트) | 풀린다 — 선이 너무 낮지 않다 |

76의 선: 1600×1600×4 = 10,240,000 > 10,000,000. PNG가 온전하므로 우리 선이 없으면 디코드가
성공한다 — 그래서 `InvalidData`가 곧 선의 증거다. 77이 반대쪽을 본다. 둘 다 단색이라 압축하면
작고, `terminal/src/testdata/`에 커밋한다.

`render` 체인 검사 19: 같은 PNG를 `f=100,i=4,c=4,r=2`로 보내 `imgpx> id=4`가 이미지 1과 같은
`FF0000/00FF00/0000FF/FFFFFF`.

## Task 4: 반사실

`Screen.init`의 설치 줄을 지운다. 예측: `vt_test` 75가 부팅 전에 잡는다(PNG가 `EINVAL`로
저장되지 않는다). 되돌린다.

## Task 5: 루트 게이트

`docs/guides/lessons.md`의 명령으로 17체인 × 3. 약 1시간. 배경으로 돌린다.

## Task 6: 문서와 닫기

design `Status: 끝났다` · 실측 · `CLAUDE.md` 완료 표 한 줄 · `docs/decisions/project_terminal_graphics.md`
와 `MEMORY.md` 한 줄 · `HANDOFF.md` 맨 위 절 · `docs/guides/lessons.md`에 서브프로젝트를 넘는
것(fish 문자열 강조가 style 상한을 넘김 · `\134`). `feedback_superpowers_off.md`에 이 검증의
관찰을 적는다.

## 한 대로 (2026-10-03)

Task 1 ~ 4는 plan대로 했다. 다른 것:

- 검사 76 · 77은 plan을 쓰는 중에 고쳤다. 처음 안은 "머리만 고친 PNG"였는데 그것은 몸통이
  모자라서 선이 없어도 실패한다 — 선의 증거가 못 된다. 온전한 단색 PNG 둘로 바꿨다.
- 루트 `.gitignore`의 `*.png`가 testdata를 막아서 예외 한 줄을 더했다.
- `vt_test`의 `big`이라는 이름이 이미 있어서(lessons의 그 함정) 첫 컴파일이 shadowing으로
  막혔다. `huge`로 바꿨다.
- `png.zig`는 헤더를 `@cImport`하지 않고 함수 셋을 `extern`으로 선언한다(fortify 자리를
  늘리지 않으려고).
