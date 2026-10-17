#include "deformer.h"

#include <fstream>
#include <iterator>

namespace cg {

Deformer::~Deformer() {
  for (auto &[id, buffers] : buffers_) {
    if (buffers.current) backend_->buffer_destroy(device_, buffers.current);
    if (buffers.previous) backend_->buffer_destroy(device_, buffers.previous);
  }
  if (pipeline_) backend_->pipeline_destroy(device_, pipeline_);
}

bool Deformer::create_pipeline(const std::string &shader_directory) {
  std::ifstream file(shader_directory + "/deform." + backend_->shader_extension, std::ios::binary);
  std::vector<char> code{std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>()};
  if (code.empty() || !backend_->compute_pipeline_create) return false;
  cg_compute_desc desc{{code.data(), code.size(), "compute_main"}, {64, 1, 1}, "deform"};
  pipeline_ = backend_->compute_pipeline_create(device_, &desc);
  return pipeline_ != nullptr;
}

Deformer::Buffers &Deformer::buffers_for(uint32_t id, uint32_t count) {
  Buffers &buffers = buffers_[id];
  if (buffers.count != count) {
    if (buffers.current) backend_->buffer_destroy(device_, buffers.current);
    if (buffers.previous) backend_->buffer_destroy(device_, buffers.previous);
    uint64_t size = uint64_t(count) * sizeof(Vertex);
    buffers = {backend_->buffer_create(device_, size, CG_MEMORY_GPU, "deformed"),
               backend_->buffer_create(device_, size, CG_MEMORY_GPU, "deformed previous"), count, false};
  } else {
    std::swap(buffers.current, buffers.previous);
    buffers.has_previous = true;
  }
  return buffers;
}

void Deformer::forget_unposed(const Scene &scene) {
  for (auto entry = buffers_.begin(); entry != buffers_.end();) {
    auto instance = scene.instances.find(entry->first);
    if (instance != scene.instances.end() && instance->second.posed()) {
      ++entry;
      continue;
    }
    if (entry->second.current) backend_->buffer_destroy(device_, entry->second.current);
    if (entry->second.previous) backend_->buffer_destroy(device_, entry->second.previous);
    entry = buffers_.erase(entry);
  }
}

std::unordered_map<uint32_t, Deformed> Deformer::run(cg_cmd *cmd, FrameArena &arena, const Scene &scene, const Resources &resources,
                                                     bool build_accels) {
  forget_unposed(scene);
  std::unordered_map<uint32_t, Deformed> frame;
  if (!pipeline_) return frame;
  std::vector<DeformPush> jobs;
  std::vector<std::pair<uint32_t, const GpuMesh *>> built;
  for (auto &[id, instance] : scene.instances) {
    const GpuMesh *mesh = resources.mesh(instance.mesh);
    if (!instance.posed() || !mesh || (instance.flags & InstanceHidden)) continue;
    Buffers &buffers = buffers_for(id, mesh->vertex_count);
    if (!buffers.current || !buffers.previous) continue;
    const GpuMesh *blend = instance.blend_mesh ? resources.mesh(instance.blend_mesh) : nullptr;
    bool blends = blend && blend->vertex_count == mesh->vertex_count;
    bool skins = mesh->skin && !instance.bones.empty();
    uint64_t bones = skins ? arena.write(instance.bones.data(), instance.bones.size() * sizeof(float)) : 0;
    jobs.push_back({backend_->buffer_address(mesh->vertices), blends ? backend_->buffer_address(blend->vertices) : 0,
                    skins ? backend_->buffer_address(mesh->skin) : 0, bones, backend_->buffer_address(buffers.current),
                    mesh->vertex_count, instance.blend, skins ? static_cast<uint32_t>(instance.bones.size() / 12) : 0, 0});
    frame[id] = {backend_->buffer_address(buffers.current), buffers.has_previous ? backend_->buffer_address(buffers.previous) : 0,
                 nullptr};
    built.push_back({id, mesh});
  }
  dispatch(cmd, jobs);
  if (build_accels)
    for (auto &[id, mesh] : built)
      frame[id].accel = backend_->accel_create_geometry(device_, cmd, buffers_[id].current, mesh->vertex_count, sizeof(Vertex),
                                                        mesh->indices, mesh->index_count);
  return frame;
}

void Deformer::release_frame(std::unordered_map<uint32_t, Deformed> &frame) {
  for (auto &[id, deformed] : frame)
    if (deformed.accel) backend_->accel_destroy(device_, deformed.accel);
  frame.clear();
}

void Deformer::dispatch(cg_cmd *cmd, const std::vector<DeformPush> &jobs) {
  if (jobs.empty()) return;
  backend_->cmd_begin_compute(cmd, "deform");
  backend_->cmd_set_compute_pipeline(cmd, pipeline_);
  for (const DeformPush &job : jobs) {
    backend_->cmd_push(cmd, &job, sizeof(job));
    backend_->cmd_dispatch(cmd, (job.count + 63) / 64, 1, 1);
  }
  backend_->cmd_end_compute(cmd);
}

}
