#pragma once

#include <memory>
#include <string>
#include <vector>

#include "../gpu.h"
#include "bloom.h"
#include "gpu_types.h"
#include "resources.h"

namespace cg {

enum class BlendKind : uint8_t { Alpha = 0, Add = 1, Multiply = 2 };

struct Draw {
  const GpuMesh *mesh;
  uint32_t part;
  uint32_t instance;
  uint32_t material;
  bool double_sided;
  bool casts_shadow;
  uint64_t vertices;
  uint64_t previous_vertices;
  bool visible;
  bool smear;
  bool standing;
  BlendKind blend;
  bool depth_always;
  uint64_t colors;
};

struct SpriteRun {
  uint32_t mode;
  uint32_t first;
  uint32_t count;
};

struct LayerDraw {
  LayerKind kind;
  cg_texture *target;
  bool clear;
  float clear_colour[4];
  uint64_t layer;
  uint64_t items;
  std::vector<SpriteRun> runs;
};

struct FrameInputs {
  uint64_t frame;
  uint64_t instances;
  uint64_t materials;
  uint64_t lights;
  bool shadows;
  uint32_t effects;
  cg_accel *scene;
  uint64_t traced;
  bool upscale;
  bool generate;
  bool reset_history;
  float jitter_x;
  float jitter_y;
  float delta_time;
  float near_plane;
  float far_plane;
  float fov_y;
  std::vector<Draw> draws;
  std::vector<Draw> transparent;
  float bloom_strength;
  float bloom_threshold;
  bool flat_only;
  std::vector<LayerDraw> layers;
};

struct Targets {
  uint32_t width = 0;
  uint32_t height = 0;
  uint32_t output_width = 0;
  uint32_t output_height = 0;
  cg_texture *motion_geometry = nullptr;
  cg_texture *motion = nullptr;
  cg_texture *upscaled = nullptr;
  cg_texture *final = nullptr;
  cg_texture *previous_final = nullptr;
  cg_texture *generated = nullptr;
  cg_texture *albedo = nullptr;
  cg_texture *normal = nullptr;
  cg_texture *emissive = nullptr;
  cg_texture *baked = nullptr;
  cg_texture *depth = nullptr;
  cg_texture *hdr = nullptr;
  cg_texture *behind = nullptr;
  cg_texture *nearest = nullptr;
  cg_texture *shadow_maps[4] = {nullptr, nullptr, nullptr, nullptr};
  cg_texture *capture = nullptr;
  cg_texture *flat = nullptr;
};

class Passes {
 public:
  static constexpr uint32_t ShadowMapSize = 2048;
  static constexpr uint32_t Cascades = 4;

  Passes(const cg_backend *backend, cg_device *device) : backend_(backend), device_(device) {}
  ~Passes();

  bool create_pipelines(const std::string &shader_directory, bool ray_tracing, std::string &error);
  bool ray_tracing() const { return raytrace_ != nullptr; }
  bool resize(uint32_t width, uint32_t height, uint32_t output_width, uint32_t output_height, bool generate);
  bool upscaling() const { return upscaler_ != nullptr; }
  bool generating() const { return interpolator_ != nullptr; }
  cg_texture *bloom_result() const { return bloom_ ? bloom_->result() : nullptr; }
  bool generated_valid() const { return generated_valid_; }
  void finish_generated();
  void record_generated_capture(cg_cmd *cmd, cg_buffer *readback);
  const Targets &targets() const { return targets_; }
  void record(cg_cmd *cmd, const FrameInputs &inputs);
  void record_capture(cg_cmd *cmd, const FrameInputs &inputs, cg_buffer *readback);

 private:
  cg_texture *target(cg_format format, uint32_t usage, uint32_t width, uint32_t height, const char *label);
  void release_targets(bool including_shadow_map);
  void shadow_pass(cg_cmd *cmd, const FrameInputs &inputs);
  void geometry_pass(cg_cmd *cmd, const FrameInputs &inputs);
  void ray_trace(cg_cmd *cmd, const FrameInputs &inputs);
  void lighting_pass(cg_cmd *cmd, const FrameInputs &inputs);
  void forward_pass(cg_cmd *cmd, const FrameInputs &inputs);
  void copy_behind(cg_cmd *cmd, const FrameInputs &inputs);
  void tonemap_pass(cg_cmd *cmd, const FrameInputs &inputs, cg_texture *output, cg_pipeline *pipeline);
  void layer_passes(cg_cmd *cmd, const FrameInputs &inputs);
  void present_flat(cg_cmd *cmd, const FrameInputs &inputs, cg_texture *output, cg_pipeline *pipeline);
  void draw(cg_cmd *cmd, const FrameInputs &inputs, const Draw &draw, uint32_t cascade);

  const cg_backend *backend_;
  cg_device *device_;
  Targets targets_;
  cg_pipeline *shadow_ = nullptr;
  cg_pipeline *geometry_ = nullptr;
  cg_pipeline *geometry_double_sided_ = nullptr;
  cg_pipeline *lighting_ = nullptr;
  cg_pipeline *tonemap_ = nullptr;
  cg_pipeline *capture_tonemap_ = nullptr;
  cg_pipeline *raytrace_ = nullptr;
  cg_pipeline *forward_[3][2][2] = {};
  cg_pipeline *copy_ = nullptr;
  cg_pipeline *sprite_[3] = {};
  cg_pipeline *columns_ = nullptr;
  cg_pipeline *present_ = nullptr;
  cg_pipeline *capture_present_ = nullptr;
  std::unique_ptr<Bloom> bloom_;
  cg_buffer *traced_ = nullptr;
  cg_buffer *reflections_ = nullptr;
  cg_buffer *gi_ = nullptr;
  cg_buffer *histories_[2] = {nullptr, nullptr};
  uint32_t history_index_ = 0;
  bool history_fresh_ = true;
  cg_pipeline *denoise_ = nullptr;
  void release_traced_buffers();
  void denoise(cg_cmd *cmd, const FrameInputs &inputs);
  cg_upscaler *upscaler_ = nullptr;
  cg_interpolator *interpolator_ = nullptr;
  bool generated_ready_ = false;
  bool generated_valid_ = false;
  void interpolate(cg_cmd *cmd, const FrameInputs &inputs);
  void upscale(cg_cmd *cmd, const FrameInputs &inputs);
  DrawPush push_for(const FrameInputs &inputs) const;
};

}
