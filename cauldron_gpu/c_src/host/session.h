#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "../core/render_window.h"
#include "channel.h"

namespace cg::host {

class Request {
 public:
  explicit Request(const std::vector<uint8_t> &bytes) : bytes_(bytes) {}

  uint8_t u8() { return static_cast<uint8_t>(big_endian(1)); }
  uint32_t u32() { return static_cast<uint32_t>(big_endian(4)); }
  uint64_t u64() { return big_endian(8); }
  std::string text(size_t size);
  std::string rest() { return text(bytes_.size() - at_); }
  size_t at() const { return at_; }
  bool failed() const { return failed_; }

 private:
  uint64_t big_endian(size_t width);

  const std::vector<uint8_t> &bytes_;
  size_t at_ = 0;
  bool failed_ = false;
};

class Session {
 public:
  explicit Session(Channel &channel) : channel_(channel) {}

  bool handle(std::vector<uint8_t> packet);
  void close();

 private:
  void open(Request &request);
  void submit_inline(std::vector<uint8_t> packet);
  void submit_shared(Request &request);
  void capture(Request &request);
  void resize(Request &request);
  void relative_mouse(Request &request);
  void frames(Request &request);
  void send_event(const SDL_Event &event);
  void send_error(const std::string &message);
  void reply_closed(uint32_t tag);

  Channel &channel_;
  std::unique_ptr<RenderWindow> window_;
};

}
