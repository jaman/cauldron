#include "channel.h"

#include <cerrno>

#include <fcntl.h>
#include <unistd.h>

namespace cg::host {

namespace {

bool read_exactly(int descriptor, uint8_t *data, size_t size) {
  while (size > 0) {
    ssize_t count = read(descriptor, data, size);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) return false;
    data += count;
    size -= static_cast<size_t>(count);
  }
  return true;
}

bool write_exactly(int descriptor, const uint8_t *data, size_t size) {
  while (size > 0) {
    ssize_t count = write(descriptor, data, size);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) return false;
    data += count;
    size -= static_cast<size_t>(count);
  }
  return true;
}

}

Channel::Channel() : input_(dup(STDIN_FILENO)), output_(dup(STDOUT_FILENO)) {
  int nothing = open("/dev/null", O_RDONLY);
  dup2(nothing, STDIN_FILENO);
  close(nothing);
  dup2(STDERR_FILENO, STDOUT_FILENO);
}

bool Channel::receive(std::vector<uint8_t> &packet) {
  uint8_t header[4];
  if (!read_exactly(input_, header, 4)) return false;
  size_t size = (size_t(header[0]) << 24) | (size_t(header[1]) << 16) | (size_t(header[2]) << 8) | header[3];
  packet.resize(size);
  return read_exactly(input_, packet.data(), size);
}

void Channel::send(const Term &term) {
  const std::vector<uint8_t> &bytes = term.bytes();
  uint32_t size = static_cast<uint32_t>(bytes.size());
  uint8_t header[4] = {uint8_t(size >> 24), uint8_t(size >> 16), uint8_t(size >> 8), uint8_t(size)};
  std::lock_guard lock(write_mutex_);
  if (!write_exactly(output_, header, 4) || !write_exactly(output_, bytes.data(), bytes.size())) _exit(0);
}

}
