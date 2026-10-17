#pragma once

#include <cstddef>
#include <cstdint>
#include <string_view>
#include <vector>

namespace cg::host {

class Term {
 public:
  Term();

  Term &atom(std::string_view name);
  Term &boolean(bool value);
  Term &integer(int64_t value);
  Term &number(double value);
  Term &tuple(uint8_t arity);
  Term &map(uint32_t pairs);
  Term &binary(const void *data, size_t size);
  Term &binary(std::string_view text) { return binary(text.data(), text.size()); }

  const std::vector<uint8_t> &bytes() const { return bytes_; }

 private:
  void big_endian(uint64_t value, int width);

  std::vector<uint8_t> bytes_;
};

}
