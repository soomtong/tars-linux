#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <ghostty/vt.h>

int main() {
  GhosttyOscParser parser;
  if (ghostty_osc_new(NULL, &parser) != GHOSTTY_SUCCESS) {
    fprintf(stderr, "ghostty_osc_new failed\n");
    return 1;
  }

  // "change window title" 명령(OSC 0): ESC ] 0 ; hello BEL
  ghostty_osc_next(parser, '0');
  ghostty_osc_next(parser, ';');
  const char *title = "hello";
  for (size_t i = 0; i < strlen(title); i++) {
    ghostty_osc_next(parser, title[i]);
  }

  GhosttyOscCommand command = ghostty_osc_end(parser, 0);
  GhosttyOscCommandType type = ghostty_osc_command_type(command);
  printf("Command type: %d\n", type);

  if (ghostty_osc_command_data(command, GHOSTTY_OSC_DATA_CHANGE_WINDOW_TITLE_STR, &title)) {
    printf("Extracted title: %s\n", title);
  } else {
    fprintf(stderr, "Failed to extract title\n");
    ghostty_osc_free(parser);
    return 1;
  }

  ghostty_osc_free(parser);
  return 0;
}
