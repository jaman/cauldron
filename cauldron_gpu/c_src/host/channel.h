#pragma once

#include <cstdint>
#include <mutex>
#include <vector>

#include "term.h"

namespace cg::host {

class Channel {
 public:
  Channel();
  Channel(const Channel &) = delete;
  Channel &operator=(const Channel &) = delete;

  bool receive(std::vector<uint8_t> &packet);
  void send(const Term &term);

 private:
  int input_;
  int output_;
  std::mutex write_mutex_;
};

}
