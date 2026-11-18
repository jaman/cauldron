#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace cg {

struct DecodedImage {
  uint32_t width = 0;
  uint32_t height = 0;
  std::vector<uint8_t> pixels;
};

struct ReducedImage {
  bool png = false;
  uint32_t width = 0;
  uint32_t height = 0;
  std::vector<uint8_t> bytes;
};

bool decode_image(const uint8_t *data, size_t size, DecodedImage &image, std::string &error);
bool reduce_image(const uint8_t *data, size_t size, uint32_t max_side, bool srgb, int quality, ReducedImage &image, std::string &error);

}
