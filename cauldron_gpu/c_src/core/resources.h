#pragma once

#include <unordered_map>
#include <vector>

#include "../gpu.h"
#include "scene.h"

namespace cg {

struct Sphere {
  Vec3 centre;
  float radius;
};

struct GpuMesh {
  cg_buffer *vertices = nullptr;
  cg_buffer *indices = nullptr;
  cg_accel *accel = nullptr;
  cg_buffer *skin = nullptr;
  cg_buffer *colors = nullptr;
  uint32_t vertex_count = 0;
  uint32_t index_count = 0;
  std::vector<MeshPart> parts;
  std::vector<Sphere> bounds;
};

struct GpuTexture {
  cg_texture *texture = nullptr;
  uint64_t handle = 0;
  uint64_t sampler = 0;
  uint32_t width = 0;
  uint32_t height = 0;
  bool canvas = false;
  bool linear = false;
};

struct Samplers {
  cg_sampler *nearest_repeat = nullptr;
  cg_sampler *nearest_clamp = nullptr;
  cg_sampler *linear_repeat = nullptr;
  cg_sampler *linear_clamp = nullptr;
};

class Resources {
 public:
  Resources(const cg_backend *backend, cg_device *device, bool ray_tracing)
      : backend_(backend), device_(device), ray_tracing_(ray_tracing) {}
  ~Resources();

  bool create_defaults();
  void apply(cg_cmd *cmd, Changes &changes);

  const GpuMesh *mesh(uint32_t id) const;
  const GpuTexture *texture(uint32_t id) const;
  const GpuTexture &white() const { return white_; }
  const GpuTexture &black() const { return black_; }
  const Samplers &samplers() const { return samplers_; }
  uint64_t sampler_handle(bool linear, bool clamp) const;

 private:
  void put_mesh(cg_cmd *cmd, uint32_t id, const MeshData &mesh);
  void put_texture(cg_cmd *cmd, uint32_t id, const TextureData &texture);
  void put_canvas(cg_cmd *cmd, uint32_t id, const TextureData &texture);
  void drop_mesh(uint32_t id);
  void drop_texture(uint32_t id);
  void destroy_mesh(GpuMesh &mesh);
  void staged(cg_cmd *cmd, const void *data, size_t size, cg_buffer *destination);
  GpuTexture solid(cg_cmd *cmd, const uint8_t rgba[4], const char *label);
  void release_staging();

  const cg_backend *backend_;
  cg_device *device_;
  bool ray_tracing_;
  std::unordered_map<uint32_t, GpuMesh> meshes_;
  std::unordered_map<uint32_t, GpuTexture> textures_;
  std::vector<cg_buffer *> staging_;
  Samplers samplers_;
  GpuTexture white_;
  GpuTexture black_;
  bool defaults_uploaded_ = false;
};

}
