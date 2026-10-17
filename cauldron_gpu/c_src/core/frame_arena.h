#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>

#include "../gpu.h"

namespace cg {

class FrameArena {
 public:
  FrameArena() = default;
  FrameArena(const FrameArena &) = delete;
  FrameArena &operator=(const FrameArena &) = delete;

  void reset(const cg_backend *backend, cg_device *device, size_t needed) {
    backend_ = backend;
    device_ = device;
    used_ = 0;
    if (capacity_ >= needed && buffer_) return;
    if (buffer_) backend_->buffer_destroy(device_, buffer_);
    capacity_ = needed < 65536 ? 65536 : needed * 2;
    buffer_ = backend_->buffer_create(device_, capacity_, CG_MEMORY_UPLOAD, "frame arena");
    contents_ = buffer_ ? static_cast<uint8_t *>(backend_->buffer_contents(buffer_)) : nullptr;
    address_ = buffer_ ? backend_->buffer_address(buffer_) : 0;
  }

  void release() {
    if (buffer_) backend_->buffer_destroy(device_, buffer_);
    buffer_ = nullptr;
    capacity_ = 0;
  }

  bool ready() const { return contents_ != nullptr; }

  uint64_t write(const void *data, size_t size) {
    size_t at = (used_ + 255) & ~size_t(255);
    if (at + size > capacity_) return 0;
    if (size > 0) std::memcpy(contents_ + at, data, size);
    used_ = at + size;
    return address_ + at;
  }

 private:
  const cg_backend *backend_ = nullptr;
  cg_device *device_ = nullptr;
  cg_buffer *buffer_ = nullptr;
  uint8_t *contents_ = nullptr;
  uint64_t address_ = 0;
  size_t capacity_ = 0;
  size_t used_ = 0;
};

}
