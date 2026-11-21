// 툴킷의 이미지 디코더(TK-M6 plan 확정 10 — TK design 결정 2: terminal 것을 나누지 않고 툴킷이 따로 컴파일한다). 헤더는 terminal의
// vendor(`../terminal/vendor/stb_image.h`, prepare.sh가 받아 둔다)를 빌린다. PNG와 JPEG만 켜고 파일 입출력은 뺀다 — 디코더는 바이트만
// 받는다(`cg/image.zig`, plan 확정 15). 한 변 상한은 요구사항 결정 13의 8192와 같다(감싸개가 머리로 먼저 거르고, 이것은 둘째 울타리).
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STBI_NO_STDIO
#define STBI_NO_LINEAR
#define STBI_NO_HDR
#define STBI_MAX_DIMENSIONS 8192
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
