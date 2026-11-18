#include "image.h"

#include <algorithm>
#include <cstring>

#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STBI_NO_STDIO
#include <stb_image.h>

#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include <stb_image_resize2.h>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STBI_WRITE_NO_STDIO
#include <stb_image_write.h>

namespace cg {

namespace {

void append(void *context, void *data, int size) {
  auto *bytes = static_cast<std::vector<uint8_t> *>(context);
  auto *start = static_cast<uint8_t *>(data);
  bytes->insert(bytes->end(), start, start + size);
}

bool transparent(const std::vector<uint8_t> &pixels) {
  for (size_t at = 3; at < pixels.size(); at += 4)
    if (pixels[at] != 255) return true;
  return false;
}

}

bool decode_image(const uint8_t *data, size_t size, DecodedImage &image, std::string &error) {
  int width = 0, height = 0, channels = 0;
  stbi_uc *pixels = stbi_load_from_memory(data, static_cast<int>(size), &width, &height, &channels, 4);
  if (!pixels) {
    error = stbi_failure_reason() ? stbi_failure_reason() : "unreadable image";
    return false;
  }
  image.width = static_cast<uint32_t>(width);
  image.height = static_cast<uint32_t>(height);
  image.pixels.resize(size_t(width) * height * 4);
  std::memcpy(image.pixels.data(), pixels, image.pixels.size());
  stbi_image_free(pixels);
  return true;
}

bool reduce_image(const uint8_t *data, size_t size, uint32_t max_side, bool srgb, int quality, ReducedImage &image, std::string &error) {
  DecodedImage source;
  if (!decode_image(data, size, source, error)) return false;
  uint32_t longest = std::max(source.width, source.height);
  double scale = longest > max_side ? static_cast<double>(max_side) / longest : 1.0;
  image.width = std::max(1u, static_cast<uint32_t>(source.width * scale + 0.5));
  image.height = std::max(1u, static_cast<uint32_t>(source.height * scale + 0.5));
  std::vector<uint8_t> pixels(size_t(image.width) * image.height * 4);
  const stbir_pixel_layout layout = STBIR_RGBA;
  unsigned char *done = srgb ? stbir_resize_uint8_srgb(source.pixels.data(), source.width, source.height, 0, pixels.data(), image.width, image.height, 0, layout)
                             : stbir_resize_uint8_linear(source.pixels.data(), source.width, source.height, 0, pixels.data(), image.width, image.height, 0, layout);
  if (!done) {
    error = "resize failed";
    return false;
  }
  image.png = transparent(pixels);
  int written = image.png ? stbi_write_png_to_func(append, &image.bytes, image.width, image.height, 4, pixels.data(), image.width * 4)
                          : stbi_write_jpg_to_func(append, &image.bytes, image.width, image.height, 4, pixels.data(), quality);
  if (!written) {
    error = "encoding failed";
    return false;
  }
  return true;
}

}
