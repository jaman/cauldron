#include "passes.h"

#include <algorithm>
#include <fstream>
#include <iterator>

namespace cg {

namespace {

std::vector<char> read_file(const std::string &path) {
  std::ifstream file(path, std::ios::binary);
  return {std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>()};
}

struct ShaderFile {
  std::vector<char> code;

  cg_shader entry(const char *name) const { return {code.data(), code.size(), name}; }
};

cg_pipeline_desc fullscreen_desc(const ShaderFile &file, cg_format format, const char *label) {
  cg_pipeline_desc desc{};
  desc.vertex = file.entry("vertex_main");
  desc.fragment = file.entry("fragment_main");
  desc.color_count = 1;
  desc.color_formats[0] = format;
  desc.depth_format = CG_FORMAT_UNDEFINED;
  desc.cull = CG_CULL_NONE;
  desc.label = label;
  return desc;
}

}

Passes::~Passes() {
  release_targets(true);
  release_traced_buffers();
  if (upscaler_) backend_->upscaler_destroy(device_, upscaler_);
  if (interpolator_) backend_->interpolator_destroy(device_, interpolator_);
  for (cg_pipeline *pipeline : {shadow_, geometry_, geometry_double_sided_, lighting_, tonemap_, capture_tonemap_, raytrace_, denoise_, copy_,
                                 sprite_[0], sprite_[1], sprite_[2], columns_, present_, capture_present_})
    if (pipeline) backend_->pipeline_destroy(device_, pipeline);
  for (auto &by_blend : forward_)
    for (auto &by_side : by_blend)
      for (cg_pipeline *pipeline : by_side)
        if (pipeline) backend_->pipeline_destroy(device_, pipeline);
}

bool Passes::create_pipelines(const std::string &shader_directory, bool ray_tracing, std::string &error) {
  auto load = [&](const char *name) {
    return ShaderFile{read_file(shader_directory + "/" + name + "." + backend_->shader_extension)};
  };
  ShaderFile shadow = load("shadow"), gbuffer = load("gbuffer"), lighting = load("lighting"), tonemap = load("tonemap"),
             forward = load("forward"), copy = load("copy"), sprite = load("sprite"), columns = load("columns"),
             present = load("present2d");
  if (shadow.code.empty() || gbuffer.code.empty() || lighting.code.empty() || tonemap.code.empty() || forward.code.empty() ||
      copy.code.empty() || sprite.code.empty() || columns.code.empty() || present.code.empty()) {
    error = "shaders not found in " + shader_directory;
    return false;
  }

  cg_pipeline_desc shadow_desc{};
  shadow_desc.vertex = shadow.entry("vertex_main");
  shadow_desc.depth_format = CG_FORMAT_D32F;
  shadow_desc.depth_compare = CG_COMPARE_GREATER_EQUAL;
  shadow_desc.depth_write = true;
  shadow_desc.cull = CG_CULL_NONE;
  shadow_desc.depth_bias = -2.0f;
  shadow_desc.depth_slope_bias = -2.0f;
  shadow_desc.label = "shadow";
  shadow_ = backend_->pipeline_create(device_, &shadow_desc);

  cg_pipeline_desc geometry_desc{};
  geometry_desc.vertex = gbuffer.entry("vertex_main");
  geometry_desc.fragment = gbuffer.entry("fragment_main");
  geometry_desc.color_count = 6;
  geometry_desc.color_formats[0] = CG_FORMAT_RGBA8_SRGB;
  geometry_desc.color_formats[1] = CG_FORMAT_RGBA16F;
  geometry_desc.color_formats[2] = CG_FORMAT_RGBA16F;
  geometry_desc.color_formats[3] = CG_FORMAT_RGBA16F;
  geometry_desc.color_formats[4] = CG_FORMAT_RG16F;
  geometry_desc.color_formats[5] = CG_FORMAT_R32F;
  geometry_desc.depth_format = CG_FORMAT_D32F;
  geometry_desc.depth_compare = CG_COMPARE_GREATER;
  geometry_desc.depth_write = true;
  geometry_desc.cull = CG_CULL_BACK;
  geometry_desc.label = "geometry";
  geometry_ = backend_->pipeline_create(device_, &geometry_desc);
  geometry_desc.cull = CG_CULL_NONE;
  geometry_desc.label = "geometry double sided";
  geometry_double_sided_ = backend_->pipeline_create(device_, &geometry_desc);

  cg_pipeline_desc lighting_desc = fullscreen_desc(lighting, CG_FORMAT_RGBA16F, "lighting");
  lighting_desc.color_count = 2;
  lighting_desc.color_formats[1] = CG_FORMAT_RG16F;
  lighting_ = backend_->pipeline_create(device_, &lighting_desc);
  cg_pipeline_desc tonemap_desc = fullscreen_desc(tonemap, backend_->surface_format(device_), "tonemap");
  tonemap_ = backend_->pipeline_create(device_, &tonemap_desc);
  cg_pipeline_desc capture_desc = fullscreen_desc(tonemap, CG_FORMAT_RGBA8_SRGB, "capture");
  capture_tonemap_ = backend_->pipeline_create(device_, &capture_desc);
  cg_pipeline_desc copy_desc = fullscreen_desc(copy, CG_FORMAT_RGBA16F, "copy behind");
  copy_ = backend_->pipeline_create(device_, &copy_desc);
  cg_pipeline_desc forward_desc{};
  forward_desc.vertex = forward.entry("vertex_main");
  forward_desc.fragment = forward.entry("fragment_main");
  forward_desc.color_count = 1;
  forward_desc.color_formats[0] = CG_FORMAT_RGBA16F;
  forward_desc.depth_format = CG_FORMAT_D32F;
  forward_desc.depth_write = false;
  forward_desc.label = "forward";
  bool forward_ready = true;
  for (int blend = 0; blend < 3; blend++)
    for (int side = 0; side < 2; side++)
      for (int depth = 0; depth < 2; depth++) {
        forward_desc.blend[0] = blend == 0 ? CG_BLEND_ALPHA : blend == 1 ? CG_BLEND_ADD : CG_BLEND_MULTIPLY;
        forward_desc.cull = side == 0 ? CG_CULL_BACK : CG_CULL_NONE;
        forward_desc.depth_compare = depth == 0 ? CG_COMPARE_GREATER : CG_COMPARE_ALWAYS;
        forward_[blend][side][depth] = backend_->pipeline_create(device_, &forward_desc);
        forward_ready = forward_ready && forward_[blend][side][depth];
      }
  cg_pipeline_desc sprite_desc = fullscreen_desc(sprite, CG_FORMAT_RGBA8_UNORM, "sprites");
  const cg_blend sprite_blends[3] = {CG_BLEND_ALPHA, CG_BLEND_ADD, CG_BLEND_MULTIPLY};
  for (int mode = 0; mode < 3; mode++) {
    sprite_desc.blend[0] = sprite_blends[mode];
    sprite_[mode] = backend_->pipeline_create(device_, &sprite_desc);
    forward_ready = forward_ready && sprite_[mode];
  }
  cg_pipeline_desc columns_desc = fullscreen_desc(columns, CG_FORMAT_RGBA8_UNORM, "columns");
  columns_ = backend_->pipeline_create(device_, &columns_desc);
  cg_pipeline_desc present_desc = fullscreen_desc(present, backend_->surface_format(device_), "present layers");
  present_ = backend_->pipeline_create(device_, &present_desc);
  cg_pipeline_desc capture_present_desc = fullscreen_desc(present, CG_FORMAT_RGBA8_SRGB, "capture layers");
  capture_present_ = backend_->pipeline_create(device_, &capture_present_desc);
  bloom_ = std::make_unique<Bloom>(backend_, device_);
  if (!bloom_->create_pipelines(shader_directory)) bloom_.reset();

  if (!shadow_ || !geometry_ || !geometry_double_sided_ || !lighting_ || !tonemap_ || !capture_tonemap_ || !forward_ready || !copy_ ||
      !columns_ || !present_ || !capture_present_) {
    error = "pipeline creation failed";
    return false;
  }
  if (ray_tracing) {
    ShaderFile raytrace = load("raytrace");
    cg_compute_desc raytrace_desc{raytrace.entry("compute_main"), {8, 8, 1}, "raytrace"};
    if (!raytrace.code.empty()) raytrace_ = backend_->compute_pipeline_create(device_, &raytrace_desc);
    ShaderFile denoise = load("denoise");
    cg_compute_desc denoise_desc{denoise.entry("compute_main"), {8, 8, 1}, "denoise"};
    if (!denoise.code.empty()) denoise_ = backend_->compute_pipeline_create(device_, &denoise_desc);
    if (!denoise_ && raytrace_) {
      backend_->pipeline_destroy(device_, raytrace_);
      raytrace_ = nullptr;
    }
  }
  for (cg_texture *&shadow_map : targets_.shadow_maps) {
    shadow_map = target(CG_FORMAT_D32F, CG_TEXTURE_DEPTH | CG_TEXTURE_SAMPLED, ShadowMapSize, ShadowMapSize, "shadow cascade");
    if (!shadow_map) return false;
  }
  return true;
}

cg_texture *Passes::target(cg_format format, uint32_t usage, uint32_t width, uint32_t height, const char *label) {
  cg_texture_desc desc{CG_TEXTURE_2D, format, width, height, 1, usage, label};
  return backend_->texture_create(device_, &desc);
}

void Passes::release_targets(bool including_shadow_map) {
  for (cg_texture *texture : {targets_.albedo, targets_.normal, targets_.emissive, targets_.baked, targets_.depth, targets_.hdr, targets_.behind, targets_.nearest, targets_.capture,
                              targets_.motion_geometry, targets_.motion, targets_.upscaled, targets_.final, targets_.previous_final,
                              targets_.generated, targets_.flat})
    if (texture) backend_->texture_destroy(device_, texture);
  Targets kept{};
  for (uint32_t index = 0; index < Cascades; index++) {
    if (including_shadow_map && targets_.shadow_maps[index]) backend_->texture_destroy(device_, targets_.shadow_maps[index]);
    else kept.shadow_maps[index] = targets_.shadow_maps[index];
  }
  targets_ = kept;
}

bool Passes::resize(uint32_t width, uint32_t height, uint32_t output_width, uint32_t output_height, bool generate) {
  if (width == targets_.width && height == targets_.height && output_width == targets_.output_width &&
      output_height == targets_.output_height && targets_.albedo && generate == (interpolator_ != nullptr))
    return true;
  release_targets(false);
  release_traced_buffers();
  if (upscaler_) backend_->upscaler_destroy(device_, upscaler_);
  if (interpolator_) backend_->interpolator_destroy(device_, interpolator_);
  upscaler_ = nullptr;
  interpolator_ = nullptr;
  generated_ready_ = false;
  if (width == 0 || height == 0 || output_width == 0 || output_height == 0) return false;
  if (width != output_width || height != output_height) {
    cg_upscaler_desc desc{width, height, output_width, output_height, CG_FORMAT_RGBA16F, CG_FORMAT_D32F, CG_FORMAT_RG16F, CG_FORMAT_RGBA16F};
    upscaler_ = backend_->upscaler_create(device_, &desc);
    if (!upscaler_) width = output_width, height = output_height;
  }
  if (raytrace_) {
    traced_ = backend_->buffer_create(device_, uint64_t(width) * height * 8, CG_MEMORY_GPU, "ray traced");
    reflections_ = backend_->buffer_create(device_, uint64_t(width) * height * 16, CG_MEMORY_GPU, "reflections");
    gi_ = backend_->buffer_create(device_, uint64_t(width) * height * 16, CG_MEMORY_GPU, "bounce light");
    for (cg_buffer *&history : histories_) history = backend_->buffer_create(device_, uint64_t(width) * height * 48, CG_MEMORY_GPU, "history");
    history_fresh_ = true;
  }
  uint32_t color = CG_TEXTURE_RENDER_TARGET | CG_TEXTURE_SAMPLED;
  targets_.width = width;
  targets_.height = height;
  if (bloom_ && !bloom_->resize(output_width, output_height)) bloom_.reset();
  targets_.output_width = output_width;
  targets_.output_height = output_height;
  targets_.motion_geometry = target(CG_FORMAT_RG16F, color, width, height, "geometry motion");
  targets_.motion = target(CG_FORMAT_RG16F, color, width, height, "motion");
  cg_format surface = backend_->surface_format(device_);
  if (generate && backend_->interpolator_create) {
    cg_upscaler_desc desc{width, height, output_width, output_height, surface, CG_FORMAT_D32F, CG_FORMAT_RG16F, surface};
    interpolator_ = backend_->interpolator_create(device_, &desc);
  }
  if (interpolator_) {
    uint32_t picture = CG_TEXTURE_RENDER_TARGET | CG_TEXTURE_SAMPLED | CG_TEXTURE_READBACK;
    targets_.final = target(surface, picture, output_width, output_height, "final");
    targets_.previous_final = target(surface, picture, output_width, output_height, "previous final");
    targets_.generated = target(surface, picture | CG_TEXTURE_STORAGE, output_width, output_height, "generated");
  }
  if (upscaler_) targets_.upscaled = target(CG_FORMAT_RGBA16F, color | CG_TEXTURE_STORAGE, output_width, output_height, "upscaled");
  targets_.albedo = target(CG_FORMAT_RGBA8_SRGB, color, width, height, "albedo");
  targets_.normal = target(CG_FORMAT_RGBA16F, color, width, height, "normal");
  targets_.emissive = target(CG_FORMAT_RGBA16F, color, width, height, "emissive");
  targets_.baked = target(CG_FORMAT_RGBA16F, color, width, height, "baked");
  targets_.depth = target(CG_FORMAT_D32F, CG_TEXTURE_DEPTH | CG_TEXTURE_SAMPLED, width, height, "depth");
  targets_.hdr = target(CG_FORMAT_RGBA16F, color, width, height, "hdr");
  targets_.behind = target(CG_FORMAT_RGBA16F, color, width, height, "behind");
  targets_.nearest = target(CG_FORMAT_R32F, color, width, height, "nearest depth");
  targets_.capture = target(CG_FORMAT_RGBA8_SRGB, CG_TEXTURE_RENDER_TARGET | CG_TEXTURE_READBACK, output_width, output_height, "capture");
  targets_.flat = target(CG_FORMAT_RGBA8_UNORM, color, output_width, output_height, "layers");
  return targets_.albedo && targets_.normal && targets_.emissive && targets_.baked && targets_.depth && targets_.hdr && targets_.behind && targets_.nearest &&
         targets_.capture && targets_.flat &&
         targets_.motion_geometry && targets_.motion && (!upscaler_ || targets_.upscaled) &&
         (!interpolator_ || (targets_.final && targets_.previous_final && targets_.generated));
}

void Passes::record(cg_cmd *cmd, const FrameInputs &inputs) {
  layer_passes(cmd, inputs);
  if (inputs.flat_only) {
    if (cg_texture *surface = backend_->frame_target(device_)) present_flat(cmd, inputs, surface, present_);
    return;
  }
  shadow_pass(cmd, inputs);
  geometry_pass(cmd, inputs);
  ray_trace(cmd, inputs);
  lighting_pass(cmd, inputs);
  forward_pass(cmd, inputs);
  upscale(cmd, inputs);
  if (bloom_ && inputs.bloom_strength > 0) {
    cg_texture *source = inputs.upscale && targets_.upscaled ? targets_.upscaled : targets_.hdr;
    uint32_t width = source == targets_.upscaled ? targets_.output_width : targets_.width;
    uint32_t height = source == targets_.upscaled ? targets_.output_height : targets_.height;
    bloom_->record(cmd, inputs.frame, source, width, height, inputs.bloom_threshold);
  }
  if (inputs.generate && interpolator_) {
    tonemap_pass(cmd, inputs, targets_.final, tonemap_);
    interpolate(cmd, inputs);
  } else if (cg_texture *surface = backend_->frame_target(device_)) {
    tonemap_pass(cmd, inputs, surface, tonemap_);
  }
}

void Passes::interpolate(cg_cmd *cmd, const FrameInputs &inputs) {
  bool reset = inputs.reset_history || !generated_ready_;
  cg_interpolate frame{targets_.final, targets_.previous_final, targets_.depth, targets_.motion, targets_.generated,
                       static_cast<float>(targets_.width), static_cast<float>(targets_.height), inputs.jitter_x, inputs.jitter_y,
                       inputs.delta_time, inputs.near_plane, inputs.far_plane, inputs.fov_y,
                       static_cast<float>(targets_.output_width) / static_cast<float>(targets_.output_height), reset, true};
  generated_valid_ = !reset;
  if (!reset) backend_->cmd_interpolate(cmd, interpolator_, &frame);
}

void Passes::finish_generated() {
  std::swap(targets_.final, targets_.previous_final);
  generated_ready_ = true;
}

void Passes::record_generated_capture(cg_cmd *cmd, cg_buffer *readback) {
  backend_->cmd_copy_texture_to_buffer(cmd, targets_.generated, readback, 0, targets_.output_width * 4);
}

void Passes::record_capture(cg_cmd *cmd, const FrameInputs &inputs, cg_buffer *readback) {
  if (inputs.flat_only) present_flat(cmd, inputs, targets_.capture, capture_present_);
  else tonemap_pass(cmd, inputs, targets_.capture, capture_tonemap_);
  backend_->cmd_copy_texture_to_buffer(cmd, targets_.capture, readback, 0, targets_.output_width * 4);
}

void Passes::upscale(cg_cmd *cmd, const FrameInputs &inputs) {
  if (!upscaler_ || !inputs.upscale) return;
  cg_upscale frame{targets_.hdr, targets_.depth, targets_.motion, targets_.upscaled, inputs.jitter_x, inputs.jitter_y,
                   static_cast<float>(targets_.width), static_cast<float>(targets_.height), inputs.reset_history, true};
  backend_->cmd_upscale(cmd, upscaler_, &frame);
}

void Passes::draw(cg_cmd *cmd, const FrameInputs &inputs, const Draw &item, uint32_t cascade) {
  uint64_t vertices = item.vertices ? item.vertices : backend_->buffer_address(item.mesh->vertices);
  DrawPush push{inputs.frame, vertices, inputs.instances, inputs.materials, inputs.lights, item.instance, item.material, 0, 0, 0,
                item.previous_vertices, cascade, 0, 0, 0, item.colors};
  backend_->cmd_push(cmd, &push, sizeof(push));
  const MeshPart &part = item.mesh->parts[item.part];
  backend_->cmd_draw_indexed(cmd, item.mesh->indices, part.count, 1, part.first);
}

void Passes::shadow_pass(cg_cmd *cmd, const FrameInputs &inputs) {
  for (uint32_t cascade = 0; cascade < Cascades; cascade++) {
    cg_pass_desc pass{};
    pass.depth = {targets_.shadow_maps[cascade], CG_LOAD_CLEAR, true, 0.0f};
    pass.label = "shadow";
    backend_->cmd_begin_pass(cmd, &pass);
    if (inputs.shadows) {
      backend_->cmd_set_pipeline(cmd, shadow_);
      for (const Draw &item : inputs.draws)
        if (item.casts_shadow) draw(cmd, inputs, item, cascade);
    }
    backend_->cmd_end_pass(cmd);
  }
}

void Passes::copy_behind(cg_cmd *cmd, const FrameInputs &inputs) {
  cg_pass_desc pass{};
  pass.color_count = 1;
  pass.colors[0] = {targets_.behind, CG_LOAD_DONT_CARE, true, {0, 0, 0, 1}};
  pass.label = "copy behind";
  backend_->cmd_begin_pass(cmd, &pass);
  backend_->cmd_set_pipeline(cmd, copy_);
  DrawPush push{inputs.frame, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
  backend_->cmd_push(cmd, &push, sizeof(push));
  backend_->cmd_draw(cmd, 3, 1, 0);
  backend_->cmd_end_pass(cmd);
}

void Passes::forward_pass(cg_cmd *cmd, const FrameInputs &inputs) {
  if (inputs.transparent.empty()) return;
  if (std::any_of(inputs.transparent.begin(), inputs.transparent.end(), [](const Draw &item) { return item.smear && item.visible; }))
    copy_behind(cmd, inputs);
  cg_pass_desc pass{};
  pass.color_count = 1;
  pass.colors[0] = {targets_.hdr, CG_LOAD_LOAD, true, {0, 0, 0, 1}};
  pass.depth = {targets_.depth, CG_LOAD_LOAD, true, 0.0f};
  pass.label = "forward";
  backend_->cmd_begin_pass(cmd, &pass);
  cg_pipeline *current = nullptr;
  for (const Draw &item : inputs.transparent) {
    if (!item.visible) continue;
    cg_pipeline *wanted = forward_[static_cast<int>(item.blend)][item.double_sided ? 1 : 0][item.standing || item.depth_always ? 1 : 0];
    if (wanted != current) backend_->cmd_set_pipeline(cmd, wanted);
    current = wanted;
    draw(cmd, inputs, item, 0);
  }
  backend_->cmd_end_pass(cmd);
}

void Passes::geometry_pass(cg_cmd *cmd, const FrameInputs &inputs) {
  cg_pass_desc pass{};
  pass.color_count = 6;
  cg_texture *colors[6] = {targets_.albedo, targets_.normal, targets_.emissive, targets_.baked, targets_.motion_geometry, targets_.nearest};
  for (int index = 0; index < 6; index++) pass.colors[index] = {colors[index], CG_LOAD_CLEAR, true, {0, 0, 0, 0}};
  pass.depth = {targets_.depth, CG_LOAD_CLEAR, true, 0.0f};
  pass.label = "geometry";
  backend_->cmd_begin_pass(cmd, &pass);
  cg_pipeline *current = nullptr;
  for (const Draw &item : inputs.draws) {
    if (!item.visible) continue;
    cg_pipeline *wanted = item.double_sided ? geometry_double_sided_ : geometry_;
    if (wanted != current) backend_->cmd_set_pipeline(cmd, wanted);
    current = wanted;
    draw(cmd, inputs, item, 0);
  }
  backend_->cmd_end_pass(cmd);
}

void Passes::release_traced_buffers() {
  for (cg_buffer *buffer : {traced_, reflections_, gi_, histories_[0], histories_[1]})
    if (buffer) backend_->buffer_destroy(device_, buffer);
  traced_ = reflections_ = gi_ = histories_[0] = histories_[1] = nullptr;
}

void Passes::denoise(cg_cmd *cmd, const FrameInputs &inputs) {
  cg_buffer *previous = histories_[history_index_ ^ 1u], *current = histories_[history_index_];
  DenoisePush push{inputs.frame, backend_->buffer_address(traced_), backend_->buffer_address(reflections_), backend_->buffer_address(gi_),
                   backend_->buffer_address(previous), backend_->buffer_address(current), (inputs.reset_history || history_fresh_) ? 1u : 0u, 0};
  backend_->cmd_set_compute_pipeline(cmd, denoise_);
  backend_->cmd_push(cmd, &push, sizeof(push));
  backend_->cmd_dispatch(cmd, (targets_.width + 7) / 8, (targets_.height + 7) / 8, 1);
  history_fresh_ = false;
}

DrawPush Passes::push_for(const FrameInputs &inputs) const {
  return {inputs.frame, 0, inputs.instances, inputs.materials, inputs.lights, 0, 0,
          traced_ ? backend_->buffer_address(traced_) : 0, inputs.traced,
          reflections_ ? backend_->buffer_address(reflections_) : 0, 0, 0, 0,
          gi_ ? backend_->buffer_address(gi_) : 0, histories_[history_index_] ? backend_->buffer_address(histories_[history_index_]) : 0, 0};
}

void Passes::ray_trace(cg_cmd *cmd, const FrameInputs &inputs) {
  if (!raytrace_ || !traced_ || !reflections_ || !gi_ || !histories_[0] || !histories_[1] || !inputs.scene || inputs.effects == 0) return;
  history_index_ ^= 1u;
  backend_->cmd_begin_compute(cmd, "raytrace");
  backend_->cmd_set_compute_pipeline(cmd, raytrace_);
  backend_->cmd_set_accel(cmd, inputs.scene);
  DrawPush push = push_for(inputs);
  backend_->cmd_push(cmd, &push, sizeof(push));
  backend_->cmd_dispatch(cmd, (targets_.width + 7) / 8, (targets_.height + 7) / 8, 1);
  backend_->cmd_end_compute(cmd);
  backend_->cmd_begin_compute(cmd, "denoise");
  denoise(cmd, inputs);
  backend_->cmd_end_compute(cmd);
}

void Passes::lighting_pass(cg_cmd *cmd, const FrameInputs &inputs) {
  cg_pass_desc pass{};
  pass.color_count = 2;
  pass.colors[0] = {targets_.hdr, CG_LOAD_DONT_CARE, true, {0, 0, 0, 1}};
  pass.colors[1] = {targets_.motion, CG_LOAD_DONT_CARE, true, {0, 0, 0, 0}};
  pass.label = "lighting";
  backend_->cmd_begin_pass(cmd, &pass);
  backend_->cmd_set_pipeline(cmd, lighting_);
  DrawPush push = push_for(inputs);
  backend_->cmd_push(cmd, &push, sizeof(push));
  backend_->cmd_draw(cmd, 3, 1, 0);
  backend_->cmd_end_pass(cmd);
}

void Passes::tonemap_pass(cg_cmd *cmd, const FrameInputs &inputs, cg_texture *output, cg_pipeline *pipeline) {
  cg_pass_desc pass{};
  pass.color_count = 1;
  pass.colors[0] = {output, CG_LOAD_DONT_CARE, true, {0, 0, 0, 1}};
  pass.label = "tonemap";
  backend_->cmd_begin_pass(cmd, &pass);
  backend_->cmd_set_pipeline(cmd, pipeline);
  DrawPush push{inputs.frame, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
  backend_->cmd_push(cmd, &push, sizeof(push));
  backend_->cmd_draw(cmd, 3, 1, 0);
  backend_->cmd_end_pass(cmd);
}

void Passes::layer_passes(cg_cmd *cmd, const FrameInputs &inputs) {
  for (const LayerDraw &layer : inputs.layers) {
    cg_pass_desc pass{};
    pass.color_count = 1;
    pass.colors[0] = {layer.target, layer.clear ? CG_LOAD_CLEAR : CG_LOAD_LOAD, true,
                      {layer.clear_colour[0], layer.clear_colour[1], layer.clear_colour[2], layer.clear_colour[3]}};
    pass.label = layer.kind == LayerKind::Sprites ? "sprites" : "columns";
    backend_->cmd_begin_pass(cmd, &pass);
    LayerPush push{inputs.frame, layer.layer, layer.items, 0, 0};
    if (layer.kind == LayerKind::Columns && layer.items) {
      backend_->cmd_set_pipeline(cmd, columns_);
      backend_->cmd_push(cmd, &push, sizeof(push));
      backend_->cmd_draw(cmd, 6, 1, 0);
    }
    for (const SpriteRun &run : layer.runs) {
      backend_->cmd_set_pipeline(cmd, sprite_[run.mode]);
      push.first = run.first;
      backend_->cmd_push(cmd, &push, sizeof(push));
      backend_->cmd_draw(cmd, run.count * 6, 1, 0);
    }
    backend_->cmd_end_pass(cmd);
  }
}

void Passes::present_flat(cg_cmd *cmd, const FrameInputs &inputs, cg_texture *output, cg_pipeline *pipeline) {
  cg_pass_desc pass{};
  pass.color_count = 1;
  pass.colors[0] = {output, CG_LOAD_DONT_CARE, true, {0, 0, 0, 1}};
  pass.label = "present layers";
  backend_->cmd_begin_pass(cmd, &pass);
  backend_->cmd_set_pipeline(cmd, pipeline);
  DrawPush push{inputs.frame, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
  backend_->cmd_push(cmd, &push, sizeof(push));
  backend_->cmd_draw(cmd, 3, 1, 0);
  backend_->cmd_end_pass(cmd);
}

}
