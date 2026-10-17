#include "term.h"

#include <bit>
#include <cstring>

namespace cg::host {

namespace {

enum Tag : uint8_t {
  Version = 131,
  NewFloat = 70,
  SmallInteger = 97,
  Integer = 98,
  SmallTuple = 104,
  Binary = 109,
  SmallBig = 110,
  Map = 116,
  SmallAtomUtf8 = 119
};

}

Term::Term() { bytes_.push_back(Version); }

Term &Term::atom(std::string_view name) {
  bytes_.push_back(SmallAtomUtf8);
  bytes_.push_back(static_cast<uint8_t>(name.size()));
  bytes_.insert(bytes_.end(), name.begin(), name.end());
  return *this;
}

Term &Term::boolean(bool value) { return atom(value ? "true" : "false"); }

Term &Term::integer(int64_t value) {
  if (value >= 0 && value <= 255) {
    bytes_.push_back(SmallInteger);
    bytes_.push_back(static_cast<uint8_t>(value));
  } else if (value >= INT32_MIN && value <= INT32_MAX) {
    bytes_.push_back(Integer);
    big_endian(static_cast<uint32_t>(static_cast<int32_t>(value)), 4);
  } else {
    uint64_t magnitude = value < 0 ? uint64_t(0) - uint64_t(value) : uint64_t(value);
    std::vector<uint8_t> digits;
    for (; magnitude; magnitude >>= 8) digits.push_back(static_cast<uint8_t>(magnitude));
    bytes_.push_back(SmallBig);
    bytes_.push_back(static_cast<uint8_t>(digits.size()));
    bytes_.push_back(value < 0 ? 1 : 0);
    bytes_.insert(bytes_.end(), digits.begin(), digits.end());
  }
  return *this;
}

Term &Term::number(double value) {
  bytes_.push_back(NewFloat);
  big_endian(std::bit_cast<uint64_t>(value), 8);
  return *this;
}

Term &Term::tuple(uint8_t arity) {
  bytes_.push_back(SmallTuple);
  bytes_.push_back(arity);
  return *this;
}

Term &Term::map(uint32_t pairs) {
  bytes_.push_back(Map);
  big_endian(pairs, 4);
  return *this;
}

Term &Term::binary(const void *data, size_t size) {
  bytes_.push_back(Binary);
  big_endian(size, 4);
  const auto *start = static_cast<const uint8_t *>(data);
  bytes_.insert(bytes_.end(), start, start + size);
  return *this;
}

void Term::big_endian(uint64_t value, int width) {
  for (int shift = (width - 1) * 8; shift >= 0; shift -= 8) bytes_.push_back(static_cast<uint8_t>(value >> shift));
}

}
