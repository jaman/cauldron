#include "channel.h"

#include <cerrno>
#include <cstdlib>

#include <fcntl.h>

#if defined(_WIN32)
#include <io.h>
#include <share.h>

#include <algorithm>
#else
#include <unistd.h>
#endif

namespace cg::host {

namespace {

#if defined(_WIN32)

long long read_some(int descriptor, uint8_t *data, size_t size) {
  return _read(descriptor, data, static_cast<unsigned>(std::min<size_t>(size, 1u << 30)));
}

long long write_some(int descriptor, const uint8_t *data, size_t size) {
  return _write(descriptor, data, static_cast<unsigned>(std::min<size_t>(size, 1u << 30)));
}

void take_standard_streams(int &input, int &output) {
  input = _dup(0);
  output = _dup(1);
  _setmode(input, _O_BINARY);
  _setmode(output, _O_BINARY);
  int nothing = -1;
  _sopen_s(&nothing, "NUL", _O_RDONLY, _SH_DENYNO, 0);
  _dup2(nothing, 0);
  _close(nothing);
  _dup2(2, 1);
}

#else

long long read_some(int descriptor, uint8_t *data, size_t size) { return read(descriptor, data, size); }

long long write_some(int descriptor, const uint8_t *data, size_t size) { return write(descriptor, data, size); }

void take_standard_streams(int &input, int &output) {
  input = dup(STDIN_FILENO);
  output = dup(STDOUT_FILENO);
  int nothing = open("/dev/null", O_RDONLY);
  dup2(nothing, STDIN_FILENO);
  close(nothing);
  dup2(STDERR_FILENO, STDOUT_FILENO);
}

#endif

bool read_exactly(int descriptor, uint8_t *data, size_t size) {
  while (size > 0) {
    long long count = read_some(descriptor, data, size);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) return false;
    data += count;
    size -= static_cast<size_t>(count);
  }
  return true;
}

bool write_exactly(int descriptor, const uint8_t *data, size_t size) {
  while (size > 0) {
    long long count = write_some(descriptor, data, size);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) return false;
    data += count;
    size -= static_cast<size_t>(count);
  }
  return true;
}

}

Channel::Channel() { take_standard_streams(input_, output_); }

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
  if (!write_exactly(output_, header, 4) || !write_exactly(output_, bytes.data(), bytes.size())) std::_Exit(0);
}

}
