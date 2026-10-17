#pragma once

#include <string>
#include <vector>

#include "../gpu.h"

namespace cg {

class Bloom {
 public:
  static constexpr uint32_t Levels = 5;

  Bloom(const cg_backend *backend, cg_device *device) : backend_(backend), device_(device) {}
  ~Bloom();

  bool create_pipelines(const std::string &shader_directory);
  bool resize(uint32_t width, uint32_t height);
  void record(cg_cmd *cmd, uint64_t frame, cg_texture *source, uint32_t source_width, uint32_t source_height, float threshold);
  cg_texture *result() const { return levels_.empty() ? nullptr : levels_.front().texture; }

 private:
  struct Level {
    cg_texture *texture;
    uint32_t width;
    uint32_t height;
  };

  void release_levels();
  void pass(cg_cmd *cmd, cg_pipeline *pipeline, const Level &target, cg_load load, uint64_t frame, cg_texture *source, uint32_t source_width,
            uint32_t source_height, float threshold, bool first);

  const cg_backend *backend_;
  cg_device *device_;
  cg_pipeline *downsample_ = nullptr;
  cg_pipeline *upsample_ = nullptr;
  std::vector<Level> levels_;
  uint32_t width_ = 0;
  uint32_t height_ = 0;
};

}
