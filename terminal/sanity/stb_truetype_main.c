#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"

#include <stdio.h>
#include <stdlib.h>

int main(void) {
  FILE *f = fopen("vendor/fonts/Hanme_8x4x4.ttf", "rb");
  if (!f) {
    perror("fopen");
    return 1;
  }
  fseek(f, 0, SEEK_END);
  long size = ftell(f);
  fseek(f, 0, SEEK_SET);

  unsigned char *data = malloc((size_t)size);
  if (fread(data, 1, (size_t)size, f) != (size_t)size) {
    fprintf(stderr, "short read\n");
    fclose(f);
    return 1;
  }
  fclose(f);

  stbtt_fontinfo font;
  if (!stbtt_InitFont(&font, data, 0)) {
    fprintf(stderr, "stbtt_InitFont failed\n");
    return 1;
  }

  float scale = stbtt_ScaleForPixelHeight(&font, 16.0f);
  int w, h, xoff, yoff;
  unsigned char *bitmap =
      stbtt_GetCodepointBitmap(&font, scale, scale, 'A', &w, &h, &xoff, &yoff);
  if (!bitmap) {
    fprintf(stderr, "stbtt_GetCodepointBitmap failed\n");
    return 1;
  }

  int nonzero = 0;
  for (int i = 0; i < w * h; i++) {
    if (bitmap[i] > 0) {
      nonzero++;
    }
  }

  printf("glyph 'A': %dx%d pixels, %d non-zero\n", w, h, nonzero);

  stbtt_FreeBitmap(bitmap, NULL);
  free(data);

  return nonzero > 0 ? 0 : 1;
}
