#pragma once

#include <cstdint>

namespace cg {

struct TerminalSize {
  uint32_t columns;
  uint32_t rows;
  uint32_t width;
  uint32_t height;
};

bool terminal_size(TerminalSize &size);

}
