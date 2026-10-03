// PNG 하나만 푼다(TG design 결정 6 · TG-M3 plan 정한 것 5). 나머지 형식과
// 파일 입출력은 빼서 게스트 바이너리에 안 들어가게 한다.
#define STBI_ONLY_PNG
#define STBI_NO_STDIO
#define STBI_NO_LINEAR
#define STBI_NO_HDR
// 라이브러리의 한 변 상한과 같게 둔다(`graphics_image.zig:17`). 실제 선은
// 그보다 훨씬 낮은 png.zig의 10MB 검사다.
#define STBI_MAX_DIMENSIONS 10000
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
