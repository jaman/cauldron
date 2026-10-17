#include "resources.h"

#include <cmath>
#include <algorithm>
#include <cstring>

namespace cg {

namespace {

cg_format texture_format(TextureFormat format) {
  switch (format) {
    case TextureFormat::Rgba8Linear: return CG_FORMAT_RGBA8_UNORM;
    case TextureFormat::Rgba16Float: return CG_FORMAT_RGBA16F;
    default: return CG_FORMAT_RGBA8_SRGB;
  }
}

Sphere part_bounds(const MeshData &mesh, const MeshPart &part) {
  Vec3 low{1e30f, 1e30f, 1e30f}, high{-1e30f, -1e30f, -1e30f};
  for (uint32_t at = part.first; at < part.first + part.count; at++) {
    const float *p = mesh.vertices[mesh.indices[at]].position_u;
    low = {std::min(low.x, p[0]), std::min(low.y, p[1]), std::min(low.z, p[2])};
    high = {std::max(high.x, p[0]), std::max(high.y, p[1]), std::max(high.z, p[2])};
  }
  if (part.count == 0) return {{0, 0, 0}, 0};
  Vec3 centre = (low + high) * 0.5f;
  return {centre, length(high - centre)};
}

uint32_t mip_count(uint32_t width, uint32_t height) {
  uint32_t largest = width > height ? width : height;
  return static_cast<uint32_t>(std::floor(std::log2(static_cast<double>(largest)))) + 1;
}

}

Resources::~Resources() {
  for (auto &[id, mesh] : meshes_) destroy_mesh(mesh);
  for (auto &[id, texture] : textures_) backend_->texture_destroy(device_, texture.texture);
  if (white_.texture) backend_->texture_destroy(device_, white_.texture);
  if (black_.texture) backend_->texture_destroy(device_, black_.texture);
  for (cg_sampler *sampler : {samplers_.nearest_repeat, samplers_.nearest_clamp, samplers_.linear_repeat, samplers_.linear_clamp})
    if (sampler) backend_->sampler_destroy(device_, sampler);
}

bool Resources::create_defaults() {
  cg_sampler_desc desc{CG_FILTER_NEAREST, CG_FILTER_LINEAR, CG_ADDRESS_REPEAT, 1};
  samplers_.nearest_repeat = backend_->sampler_create(device_, &desc);
  desc.address = CG_ADDRESS_CLAMP;
  samplers_.nearest_clamp = backend_->sampler_create(device_, &desc);
  desc = {CG_FILTER_LINEAR, CG_FILTER_LINEAR, CG_ADDRESS_REPEAT, 8};
  samplers_.linear_repeat = backend_->sampler_create(device_, &desc);
  desc.address = CG_ADDRESS_CLAMP;
  samplers_.linear_clamp = backend_->sampler_create(device_, &desc);
  return samplers_.nearest_repeat && samplers_.nearest_clamp && samplers_.linear_repeat && samplers_.linear_clamp;
}

uint64_t Resources::sampler_handle(bool linear, bool clamp) const {
  cg_sampler *sampler = linear ? (clamp ? samplers_.linear_clamp : samplers_.linear_repeat)
                               : (clamp ? samplers_.nearest_clamp : samplers_.nearest_repeat);
  return backend_->sampler_handle(sampler);
}

const GpuMesh *Resources::mesh(uint32_t id) const {
  auto found = meshes_.find(id);
  return found == meshes_.end() ? nullptr : &found->second;
}

const GpuTexture *Resources::texture(uint32_t id) const {
  auto found = textures_.find(id);
  return found == textures_.end() ? nullptr : &found->second;
}

void Resources::apply(cg_cmd *cmd, Changes &changes) {
  if (!defaults_uploaded_) {
    const uint8_t white[4] = {255, 255, 255, 255};
    const uint8_t black[4] = {0, 0, 0, 255};
    white_ = solid(cmd, white, "white");
    black_ = solid(cmd, black, "black");
    defaults_uploaded_ = true;
  }
  for (uint32_t id : changes.dropped_meshes) drop_mesh(id);
  for (uint32_t id : changes.dropped_textures) drop_texture(id);
  for (auto &[id, mesh] : changes.meshes) put_mesh(cmd, id, mesh);
  for (auto &[id, texture] : changes.textures) put_texture(cmd, id, texture);
  changes = Changes{};
  release_staging();
}

void Resources::put_mesh(cg_cmd *cmd, uint32_t id, const MeshData &mesh) {
  drop_mesh(id);
  if (mesh.vertices.empty() || mesh.indices.empty()) return;
  size_t vertex_bytes = mesh.vertices.size() * sizeof(Vertex);
  size_t index_bytes = mesh.indices.size() * sizeof(uint32_t);
  GpuMesh gpu;
  gpu.vertices = backend_->buffer_create(device_, vertex_bytes, CG_MEMORY_GPU, "mesh vertices");
  gpu.indices = backend_->buffer_create(device_, index_bytes, CG_MEMORY_GPU, "mesh indices");
  if (!gpu.vertices || !gpu.indices) {
    if (gpu.vertices) backend_->buffer_destroy(device_, gpu.vertices);
    if (gpu.indices) backend_->buffer_destroy(device_, gpu.indices);
    return;
  }
  staged(cmd, mesh.vertices.data(), vertex_bytes, gpu.vertices);
  staged(cmd, mesh.indices.data(), index_bytes, gpu.indices);
  gpu.vertex_count = static_cast<uint32_t>(mesh.vertices.size());
  gpu.index_count = static_cast<uint32_t>(mesh.indices.size());
  if (!mesh.skin.empty()) {
    gpu.skin = backend_->buffer_create(device_, mesh.skin.size(), CG_MEMORY_GPU, "mesh skin");
    if (gpu.skin) staged(cmd, mesh.skin.data(), mesh.skin.size(), gpu.skin);
  }
  if (!mesh.colors.empty()) {
    gpu.colors = backend_->buffer_create(device_, mesh.colors.size(), CG_MEMORY_GPU, "mesh colors");
    if (gpu.colors) staged(cmd, mesh.colors.data(), mesh.colors.size(), gpu.colors);
  }
  if (ray_tracing_)
    gpu.accel = backend_->accel_create_geometry(device_, cmd, gpu.vertices, static_cast<uint32_t>(mesh.vertices.size()), sizeof(Vertex),
                                               gpu.indices, static_cast<uint32_t>(mesh.indices.size()));
  gpu.parts = mesh.parts.empty() ? std::vector<MeshPart>{{0, static_cast<uint32_t>(mesh.indices.size())}} : mesh.parts;
  for (const MeshPart &part : gpu.parts) gpu.bounds.push_back(part_bounds(mesh, part));
  meshes_[id] = std::move(gpu);
}

void Resources::put_canvas(cg_cmd *cmd, uint32_t id, const TextureData &texture) {
  cg_texture_desc desc{CG_TEXTURE_2D, CG_FORMAT_RGBA8_UNORM, texture.width, texture.height, 1,
                       CG_TEXTURE_SAMPLED | CG_TEXTURE_RENDER_TARGET, "canvas"};
  cg_texture *created = backend_->texture_create(device_, &desc);
  if (!created) return;
  cg_pass_desc pass{};
  pass.color_count = 1;
  pass.colors[0] = {created, CG_LOAD_CLEAR, true, {0, 0, 0, 0}};
  pass.label = "canvas clear";
  backend_->cmd_begin_pass(cmd, &pass);
  backend_->cmd_end_pass(cmd);
  textures_[id] = {created, backend_->texture_handle(created), sampler_handle(texture.linear_filter, true), texture.width, texture.height, true, texture.linear_filter};
}

void Resources::put_texture(cg_cmd *cmd, uint32_t id, const TextureData &texture) {
  drop_texture(id);
  if (texture.canvas) return put_canvas(cmd, id, texture);
  cg_texture_desc desc{CG_TEXTURE_2D, texture_format(texture.format), texture.width, texture.height,
                       texture.mips ? mip_count(texture.width, texture.height) : 1, CG_TEXTURE_SAMPLED, "texture"};
  cg_texture *created = backend_->texture_create(device_, &desc);
  if (!created) return;
  uint32_t bytes_per_pixel = texture.format == TextureFormat::Rgba16Float ? 8 : 4;
  cg_buffer *staging = backend_->buffer_create(device_, texture.pixels.size(), CG_MEMORY_UPLOAD, "texture staging");
  if (!staging) {
    backend_->texture_destroy(device_, created);
    return;
  }
  std::memcpy(backend_->buffer_contents(staging), texture.pixels.data(), texture.pixels.size());
  backend_->cmd_copy_to_texture(cmd, staging, 0, texture.width * bytes_per_pixel, created, 0, 0, texture.width, texture.height);
  if (desc.mip_levels > 1) backend_->cmd_generate_mips(cmd, created);
  staging_.push_back(staging);
  textures_[id] = {created, backend_->texture_handle(created), sampler_handle(texture.linear_filter, texture.clamp), texture.width, texture.height, false, texture.linear_filter};
}

void Resources::drop_mesh(uint32_t id) {
  auto found = meshes_.find(id);
  if (found == meshes_.end()) return;
  destroy_mesh(found->second);
  meshes_.erase(found);
}

void Resources::destroy_mesh(GpuMesh &mesh) {
  backend_->buffer_destroy(device_, mesh.vertices);
  backend_->buffer_destroy(device_, mesh.indices);
  if (mesh.accel) backend_->accel_destroy(device_, mesh.accel);
  if (mesh.skin) backend_->buffer_destroy(device_, mesh.skin);
  if (mesh.colors) backend_->buffer_destroy(device_, mesh.colors);
}

void Resources::drop_texture(uint32_t id) {
  auto found = textures_.find(id);
  if (found == textures_.end()) return;
  backend_->texture_destroy(device_, found->second.texture);
  textures_.erase(found);
}

void Resources::staged(cg_cmd *cmd, const void *data, size_t size, cg_buffer *destination) {
  cg_buffer *staging = backend_->buffer_create(device_, size, CG_MEMORY_UPLOAD, "staging");
  if (!staging) return;
  std::memcpy(backend_->buffer_contents(staging), data, size);
  backend_->cmd_copy_buffer(cmd, staging, 0, destination, 0, size);
  staging_.push_back(staging);
}

GpuTexture Resources::solid(cg_cmd *cmd, const uint8_t rgba[4], const char *label) {
  cg_texture_desc desc{CG_TEXTURE_2D, CG_FORMAT_RGBA8_UNORM, 1, 1, 1, CG_TEXTURE_SAMPLED, label};
  cg_texture *created = backend_->texture_create(device_, &desc);
  cg_buffer *staging = backend_->buffer_create(device_, 4, CG_MEMORY_UPLOAD, "solid staging");
  std::memcpy(backend_->buffer_contents(staging), rgba, 4);
  backend_->cmd_copy_to_texture(cmd, staging, 0, 4, created, 0, 0, 1, 1);
  staging_.push_back(staging);
  return {created, backend_->texture_handle(created), sampler_handle(false, false), 1, 1, false, false};
}

void Resources::release_staging() {
  for (cg_buffer *buffer : staging_) backend_->buffer_destroy(device_, buffer);
  staging_.clear();
}

}
