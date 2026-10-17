#include "bloom.h"

#include <algorithm>
#include <fstream>
#include <iterator>

namespace cg {

namespace {

struct BloomPush {
  uint64_t frame;
  uint64_t source;
  float source_texel[2];
  float threshold;
  uint32_t first;
};

static_assert(sizeof(BloomPush) == 32);

}

Bloom::~Bloom() {
  release_levels();
  for (cg_pipeline *pipeline : {downsample_, upsample_})
    if (pipeline) backend_->pipeline_destroy(device_, pipeline);
}

bool Bloom::create_pipelines(const std::string &shader_directory) {
  std::ifstream file(shader_directory + "/bloom." + backend_->shader_extension, std::ios::binary);
  std::vector<char> code{std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>()};
  if (code.empty()) return false;
  cg_pipeline_desc desc{};
  desc.vertex = {code.data(), code.size(), "vertex_main"};
  desc.fragment = {code.data(), code.size(), "downsample_main"};
  desc.color_count = 1;
  desc.color_formats[0] = CG_FORMAT_RGBA16F;
  desc.depth_format = CG_FORMAT_UNDEFINED;
  desc.cull = CG_CULL_NONE;
  desc.label = "bloom downsample";
  downsample_ = backend_->pipeline_create(device_, &desc);
  desc.fragment.entry = "upsample_main";
  desc.blend[0] = CG_BLEND_ADD;
  desc.label = "bloom upsample";
  upsample_ = backend_->pipeline_create(device_, &desc);
  return downsample_ && upsample_;
}

void Bloom::release_levels() {
  for (Level &level : levels_) backend_->texture_destroy(device_, level.texture);
  levels_.clear();
}

bool Bloom::resize(uint32_t width, uint32_t height) {
  if (width == width_ && height == height_ && !levels_.empty()) return true;
  release_levels();
  width_ = width;
  height_ = height;
  uint32_t level_width = width, level_height = height;
  for (uint32_t index = 0; index < Levels; index++) {
    level_width = std::max(level_width / 2, 1u);
    level_height = std::max(level_height / 2, 1u);
    cg_texture_desc desc{CG_TEXTURE_2D, CG_FORMAT_RGBA16F, level_width, level_height, 1, CG_TEXTURE_RENDER_TARGET | CG_TEXTURE_SAMPLED, "bloom"};
    cg_texture *texture = backend_->texture_create(device_, &desc);
    if (!texture) return false;
    levels_.push_back({texture, level_width, level_height});
  }
  return true;
}

void Bloom::pass(cg_cmd *cmd, cg_pipeline *pipeline, const Level &target, cg_load load, uint64_t frame, cg_texture *source,
                 uint32_t source_width, uint32_t source_height, float threshold, bool first) {
  cg_pass_desc pass{};
  pass.color_count = 1;
  pass.colors[0] = {target.texture, load, true, {0, 0, 0, 1}};
  pass.label = "bloom";
  backend_->cmd_begin_pass(cmd, &pass);
  backend_->cmd_set_pipeline(cmd, pipeline);
  BloomPush push{frame, backend_->texture_handle(source), {1.0f / source_width, 1.0f / source_height}, threshold, first ? 1u : 0u};
  backend_->cmd_push(cmd, &push, sizeof(push));
  backend_->cmd_draw(cmd, 3, 1, 0);
  backend_->cmd_end_pass(cmd);
}

void Bloom::record(cg_cmd *cmd, uint64_t frame, cg_texture *source, uint32_t source_width, uint32_t source_height, float threshold) {
  if (levels_.empty() || !downsample_ || !upsample_) return;
  pass(cmd, downsample_, levels_[0], CG_LOAD_DONT_CARE, frame, source, source_width, source_height, threshold, true);
  for (size_t index = 1; index < levels_.size(); index++)
    pass(cmd, downsample_, levels_[index], CG_LOAD_DONT_CARE, frame, levels_[index - 1].texture, levels_[index - 1].width,
         levels_[index - 1].height, threshold, false);
  for (size_t index = levels_.size() - 1; index > 0; index--)
    pass(cmd, upsample_, levels_[index - 1], CG_LOAD_LOAD, frame, levels_[index].texture, levels_[index].width, levels_[index].height,
         threshold, false);
}

}
