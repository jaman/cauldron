#pragma once

#include <unordered_map>
#include <vector>

#include "../gpu.h"
#include "frame_arena.h"
#include "gpu_types.h"
#include "resources.h"
#include "scene.h"

namespace cg {

struct Deformed {
  uint64_t vertices = 0;
  uint64_t previous_vertices = 0;
  cg_accel *accel = nullptr;
};

class Deformer {
 public:
  Deformer(const cg_backend *backend, cg_device *device) : backend_(backend), device_(device) {}
  ~Deformer();

  bool create_pipeline(const std::string &shader_directory);
  std::unordered_map<uint32_t, Deformed> run(cg_cmd *cmd, FrameArena &arena, const Scene &scene, const Resources &resources,
                                             bool build_accels);
  void release_frame(std::unordered_map<uint32_t, Deformed> &frame);

 private:
  struct Buffers {
    cg_buffer *current = nullptr;
    cg_buffer *previous = nullptr;
    uint32_t count = 0;
    bool has_previous = false;
  };

  Buffers &buffers_for(uint32_t id, uint32_t count);
  void forget_unposed(const Scene &scene);
  void dispatch(cg_cmd *cmd, const std::vector<DeformPush> &jobs);

  const cg_backend *backend_;
  cg_device *device_;
  cg_pipeline *pipeline_ = nullptr;
  std::unordered_map<uint32_t, Buffers> buffers_;
};

}
