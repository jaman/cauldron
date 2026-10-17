#include "terminal.h"

#if defined(_WIN32)

namespace cg {

bool terminal_size(TerminalSize &) { return false; }

}

#else

#include <fcntl.h>
#include <sys/ioctl.h>
#include <unistd.h>

namespace cg {

namespace {

bool from_descriptor(int descriptor, TerminalSize &size) {
  winsize window{};
  if (ioctl(descriptor, TIOCGWINSZ, &window) != 0 || window.ws_col == 0) return false;
  size = {window.ws_col, window.ws_row, window.ws_xpixel, window.ws_ypixel};
  return true;
}

}

bool terminal_size(TerminalSize &size) {
  if (from_descriptor(STDOUT_FILENO, size) || from_descriptor(STDIN_FILENO, size)) return true;
  int descriptor = open("/dev/tty", O_RDONLY | O_NOCTTY);
  if (descriptor < 0) return false;
  bool found = from_descriptor(descriptor, size);
  close(descriptor);
  return found;
}

}

#endif
