---
name: project_motion_graphics_survey
description: Codrops식 모션 그래픽을 TARS에서 "CSS처럼" 짓는 층의 검토(2026-11-18, 구현 안 함 — 향후 계획). WebGL만으로는 셰이더 절반만 옮겨지고 쉬움의 대부분은 DOM · CSS · 트윈에서 온다. 길 셋(브라우저 엔진 · JS + WebGL shim · TARS 고유 선언형 층) 가운데 고유 선언형 층을 추천, 첫걸음은 실기 crocus 측정
metadata:
  type: project
---

계기: 사용자(2026-11-18): "terminal based WebGL api가 탑재되면 Codrops(https://x.com/codrops)에서 소개되는 다양한 모션 그래픽
예제들이 구현될 수 있는가? 어떤 API가 있으면 이런 효과를 쉽게 — 마치 Web CSS 작업처럼 — 구현할 수 있을까?" → 검토 뒤
"향후 계획 정도로 담아두고 실제 구현은 다음에 생각하자." design도 plan도 아직 없다. 다시 열면 design부터 쓴다.

x.com은 로그인이 있어야 해서 열어 보지 않았다. 아래는 Codrops 예제(tympanus.net/codrops)의 일반적인 구성에 기댄 판단이다.

## 판단

- Codrops 예제는 두 부분이다. GPU 쪽(GLSL · Three.js/OGL 장면 · 후처리)은 WebGL2(= GLES 3.0)만 있으면 옮겨진다. 웹 쪽(DOM 배치 ·
  CSS · 스크롤 · hover · 글자 배치 · GSAP 타임라인)은 브라우저가 해 주던 일이고, "쉬워 보이는" 까닭의 대부분이 여기에 있다.
  터미널에 WebGL만 붙이면 앞의 것만 풀린다 — "CSS처럼"은 뒤의 것을 대신할 선언형 층을 설계하는 일이다.
- 지금의 자리: terminal은 CPU로 그린다(dumb buffer, DY design에서 "메인 터미널을 GPU 기반으로"는 안 골랐다). GPU 프로그램은
  화면 양보(DY, [[project_display_yield]])로 화면 전체를 받아 SDL3(kmsdrm · opengles2)로 돈다. gpu 묶음에 Mesa가 있다. 패널 안에서
  돌리려면 terminal이 GPU 합성기가 되어야 하고, 그것은 DY의 결정을 다시 여는 별도 서브프로젝트다.
- 하드웨어 상한(에어 2011, HD 3000): crocus는 Gen6에서 GLES 3.0 · GL 3.3을 낼 것으로 본다 — 실기 확인 전. WebGPU 계열(Three.js
  TSL)은 안 된다(Sandy Bridge용 Vulkan 드라이버가 없다 — hasvk는 Ivy Bridge부터), `WebGPURenderer`의 WebGL2 폴백만 남는다. 단순한
  왜곡 · 노이즈는 될 것이고 raymarching · 다단 bloom · 수만 파티클은 버거울 것이다. QEMU는 llvmpipe 약 2fps라 게이트는 시간을
  고정한 N번째 프레임의 screendump여야 한다.

## 길 셋

| | 모양 | 장점 | 비용 · 위험 |
|---|---|---|---|
| A. 브라우저 엔진 | WPE WebKit + cog(DRM 백엔드)를 화면 양보로 | Codrops 코드가 거의 그대로 돈다 | 묶음이 수백 MB 단위(추정), ISO 2GiB 한도와 부딪친다. 터미널 기반이 아니다 |
| B. JS + WebGL shim | bun/node 위에 GLES3을 `WebGL2RenderingContext`로 감싸 Three.js · GSAP을 돌림 | 셰이더 · Three.js 부분을 재사용 | DOM에 기대는 부분(글자 텍스처 · 이미지 로딩 · 이벤트)을 shim으로 하나씩 메운다 — 브라우저를 반쯤 다시 만들기 쉽다 |
| C. TARS 고유 선언형 층 | 장면 파일(요소 · 스타일 · 전환) + GLSL filter + 트윈을 네이티브 런타임(Zig, SDL3/EGL)이 해석 | "CSS처럼"을 우리가 정한다, 이해가 쌓인다 | 설계 · 구현 분량이 가장 크다. 셰이더만 복사되고 나머지는 다시 쓴다 |

추천은 C다. 첫 milestone을 작게 둘 수 있다 — 화면 전체 사각형 하나 + 셰이더 파일 + 표준 uniform + 파일을 고치면 다시 읽기는
DY-M3의 SDL3 데모 위에 바로 선다. 그다음 상자 → 전환 → 입력 바인딩 순으로 넓힌다.

## C의 재료 다섯 (Codrops 효과를 나눈 것)

1. 상자 — 글자 · 이미지 · 사각형, 단순한 flow나 절대 좌표.
2. 변형과 전환 — `transform` · `opacity` · `transition: 600ms ease-out` · keyframes.
3. 셰이더 filter — 요소나 화면에 `filter: shader("ripple.frag")`, 표준 uniform(`u_time` · `u_mouse` · `u_resolution` · `u_progress` ·
   `u_texture`)이 저절로 들어온다(Shadertoy식 약속).
4. 입력 바인딩 — hover · pointer 위치 · 스크롤 진행도를 uniform이나 전환의 방아쇠로(`:hover { --u-strength: 1 }`).
5. 후처리 패스 — 화면 전체에 filter 사슬.

텍스트 파일(CSS 부분집합 문법)로 쓰고 고치면 다시 읽는다. 스크립트가 필요한 자리는 cyber 층.

## 다시 열 때 먼저 할 것

1. 실기 측정 — 에어 2011에서 GPU 데모 판: `gl` 줄이 crocus인가, GLES 판, 전체 화면 fragment shader의 fps(`carryover.md` DY 절과
   같은 실기 한 번에 본다). 무거운 효과를 목표에 넣을지가 여기서 갈린다.
2. 기준 예제 3~5개 — 사용자가 Codrops에서 고른다(예: 이미지 hover 왜곡 · 글자 분해 · 파티클 · 스크롤 갤러리). 게이트의 합격 기준이 된다.
3. 화면 전체(양보, 지금 공짜)인가 패널 안(terminal GPU 합성, 큰 결정)인가.
4. 빠진 재료 — GPU 글자(한글 포함, MSDF나 atlas), 이미지 텍스처(stb_image는 있다), 양보 중 pointer · 스크롤 입력, vsync(page flip),
   게이트용 고정 `u_time`.
5. 크기 예산 — ISO가 2GiB 한도 근처다([[project_release_0_2]]). A는 이것부터 풀어야 한다.
