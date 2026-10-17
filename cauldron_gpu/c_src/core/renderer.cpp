#include "renderer.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>

namespace cg {

namespace {

void copy_matrix(float out[16], const Mat4 &matrix) { std::memcpy(out, matrix.m, sizeof(matrix.m)); }

void copy_vec(float out[4], Vec3 value, float w) {
  out[0] = value.x;
  out[1] = value.y;
  out[2] = value.z;
  out[3] = w;
}

Mat4 translation(Vec3 offset) {
  Mat4 result;
  result.at(0, 3) = offset.x;
  result.at(1, 3) = offset.y;
  result.at(2, 3) = offset.z;
  return result;
}

Mat4 shadow_view_projection(Vec3 center, Vec3 direction, float extent, float depth) {
  Vec3 up = std::fabs(direction.y) > 0.99f ? Vec3{0, 0, 1} : Vec3{0, 1, 0};
  Mat4 rotation = look_along({0, 0, 0}, direction, up);
  Mat4 center_space = multiply(rotation, translation(center));
  float texel = 2 * extent / Passes::ShadowMapSize;
  Vec3 light_center{std::floor(center_space.at(0, 3) / texel) * texel, std::floor(center_space.at(1, 3) / texel) * texel,
                    center_space.at(2, 3) + depth * 0.5f};
  Mat4 view = multiply(translation(light_center * -1.0f), rotation);
  return multiply(reversed_orthographic(extent, extent, 0, depth), view);
}

struct Cascade {
  Mat4 view_projection;
  float split;
};

Cascade cascade(const Transform &eye, const Camera &camera, float aspect, Vec3 sun, float shadow_distance, uint32_t index) {
  auto split_at = [&](uint32_t at) { return shadow_distance * float((at + 1) * (at + 1)) / float(Passes::Cascades * Passes::Cascades); };
  float near_plane = index == 0 ? camera.near_plane : split_at(index - 1);
  float far_plane = split_at(index);
  float tan_y = std::tan(camera.fov_y * 0.5f);
  float spread = tan_y * tan_y * (1 + aspect * aspect);
  float centre_distance = std::min(far_plane, (near_plane + far_plane) * 0.5f * (1 + spread));
  float radius = std::max(std::sqrt((far_plane - centre_distance) * (far_plane - centre_distance) + far_plane * far_plane * spread),
                          std::sqrt((centre_distance - near_plane) * (centre_distance - near_plane) + near_plane * near_plane * spread));
  Vec3 forward = rotate(eye.rotation, {0, 0, -1});
  Vec3 centre = eye.position + forward * centre_distance;
  return {shadow_view_projection(centre, sun, radius, std::max(radius * 4, shadow_distance * 2)), far_plane};
}

struct Frustum {
  float planes[6][4];
};

Frustum frustum_of(const Mat4 &view_projection) {
  Frustum frustum{};
  for (int column = 0; column < 4; column++) {
    float x = view_projection.at(0, column), y = view_projection.at(1, column);
    float z = view_projection.at(2, column), w = view_projection.at(3, column);
    frustum.planes[0][column] = w + x;
    frustum.planes[1][column] = w - x;
    frustum.planes[2][column] = w + y;
    frustum.planes[3][column] = w - y;
    frustum.planes[4][column] = z;
    frustum.planes[5][column] = w - z;
  }
  return frustum;
}

bool inside(const Frustum &frustum, Vec3 centre, float radius) {
  for (const auto &plane : frustum.planes) {
    float normal_length = std::sqrt(plane[0] * plane[0] + plane[1] * plane[1] + plane[2] * plane[2]);
    if (plane[0] * centre.x + plane[1] * centre.y + plane[2] * centre.z + plane[3] < -radius * normal_length) return false;
  }
  return true;
}

float largest_scale(Vec3 scale) { return std::max(std::fabs(scale.x), std::max(std::fabs(scale.y), std::fabs(scale.z))); }

BlendKind blend_of(const MaterialData *material) {
  if (material && (material->flags & MaterialAdd)) return BlendKind::Add;
  if (material && (material->flags & MaterialMultiply)) return BlendKind::Multiply;
  return BlendKind::Alpha;
}

bool transparent(const MaterialData *material) {
  return material && ((material->flags & (MaterialBlend | MaterialAdd | MaterialMultiply)) || material->smear > 0);
}

float viewport_aspect(const Camera &camera, float width, float height) {
  if (camera.aspect > 0) return camera.aspect;
  return width * camera.viewport[2] / std::max(height * camera.viewport[3], 1.0f);
}

Mat4 camera_projection(const Camera &camera, float width, float height) {
  Mat4 projection = reversed_perspective(camera.fov_y, viewport_aspect(camera, width, height), camera.near_plane, camera.far_plane);
  float scale_x = camera.viewport[2], scale_y = camera.viewport[3];
  float shift_x = 2 * camera.viewport[0] + scale_x - 1, shift_y = 1 - 2 * camera.viewport[1] - scale_y;
  for (int column = 0; column < 4; column++) {
    projection.at(0, column) = scale_x * projection.at(0, column) + shift_x * projection.at(3, column);
    projection.at(1, column) = scale_y * projection.at(1, column) + shift_y * projection.at(3, column);
  }
  return projection;
}


float halton(uint32_t index, uint32_t base) {
  float result = 0, fraction = 1;
  while (index > 0) {
    fraction /= static_cast<float>(base);
    result += fraction * static_cast<float>(index % base);
    index /= base;
  }
  return result;
}

cg_accel_instance accel_instance(const Mat4 &model, cg_accel *geometry, bool visible) {
  cg_accel_instance out{};
  for (int row = 0; row < 3; row++)
    for (int column = 0; column < 4; column++) out.transform[row * 4 + column] = model.at(row, column);
  out.mask = visible ? 0xff : 0;
  out.geometry = geometry;
  return out;
}

GpuLight gpu_light(const Light &light, bool casts_shadow) {
  GpuLight out{};
  copy_vec(out.position_range, light.position, light.range);
  copy_vec(out.color, light.color, light.intensity);
  copy_vec(out.direction_kind, light.direction, static_cast<float>(light.kind));
  out.cone[0] = light.inner_cone;
  out.cone[1] = light.outer_cone;
  out.cone[2] = casts_shadow ? 1.0f : 0.0f;
  return out;
}

}

double now_seconds() {
  using namespace std::chrono;
  return duration<double>(steady_clock::now().time_since_epoch()).count();
}

Renderer::Renderer(const cg_backend *backend, std::string shader_directory, ErrorReporter report_error)
    : backend_(backend), shader_directory_(std::move(shader_directory)), report_error_(std::move(report_error)) {}

Renderer::~Renderer() {
  stop();
  finish_captures(true);
  deformer_.reset();
  passes_.reset();
  resources_.reset();
  for (FrameArena &arena : arenas_) arena.release();
  {
    std::lock_guard lock(mutex_);
    for (Batch &batch : batches_) batch.release();
    batches_.clear();
  }
  if (device_) backend_->device_destroy(device_);
}

bool Renderer::create_device(std::string &error) {
  device_ = backend_->device_create();
  if (!device_) {
    error = std::string("no ") + backend_->name + " device";
    return false;
  }
  return true;
}

cg_device_info Renderer::info() const {
  cg_device_info info{};
  backend_->device_info(device_, &info);
  return info;
}

bool Renderer::start(std::string &error) {
  cg_device_info device_info = info();
  bool ray_tracing = device_info.ray_tracing && backend_->accel_create_scene != nullptr;
  upscaling_ = device_info.upscaling && backend_->upscaler_create != nullptr;
  frame_generation_ = device_info.frame_generation && backend_->interpolator_create != nullptr && backend_->frame_end_pair != nullptr;
  resources_ = std::make_unique<Resources>(backend_, device_, ray_tracing);
  passes_ = std::make_unique<Passes>(backend_, device_);
  if (!resources_->create_defaults()) {
    error = "sampler creation failed";
    return false;
  }
  if (!passes_->create_pipelines(shader_directory_, ray_tracing, error)) return false;
  deformer_ = std::make_unique<Deformer>(backend_, device_);
  deformer_->create_pipeline(shader_directory_);
  running_ = true;
  thread_ = std::thread([this] { run(); });
  return true;
}

void Renderer::stop() {
  if (!running_.exchange(false)) return;
  wake_.notify_all();
  if (thread_.joinable()) thread_.join();
}

void Renderer::submit(Batch batch) {
  {
    std::lock_guard lock(mutex_);
    batches_.push_back(std::move(batch));
  }
  wake_.notify_all();
}

void Renderer::resize(uint32_t width, uint32_t height) {
  pending_width_ = width;
  pending_height_ = height;
  resized_ = true;
  wake_.notify_all();
}

void Renderer::request_capture(bool generated, CaptureReply reply) {
  {
    std::lock_guard lock(mutex_);
    capture_requests_.push_back({generated, std::move(reply)});
  }
  wake_.notify_all();
}

std::vector<CaptureRequest> Renderer::take_capture_requests() {
  std::vector<CaptureRequest> requests;
  std::lock_guard lock(mutex_);
  requests.swap(capture_requests_);
  return requests;
}

void Renderer::start_capture(cg_cmd *cmd, const FrameInputs &inputs, std::vector<CaptureRequest> requests) {
  std::vector<CaptureReply> pictures, generated;
  for (CaptureRequest &request : requests) (request.generated ? generated : pictures).push_back(std::move(request.reply));
  if (!generated.empty() && !(inputs.generate && passes_->generated_valid())) {
    std::lock_guard lock(mutex_);
    for (CaptureReply &reply : generated) capture_requests_.push_back({true, std::move(reply)});
    generated.clear();
  }
  start_generated_capture(cmd, std::move(generated));
  if (pictures.empty()) return;
  const Targets &targets = passes_->targets();
  cg_buffer *readback = backend_->buffer_create(device_, uint64_t(targets.output_width) * targets.output_height * 4, CG_MEMORY_READBACK, "capture");
  if (!readback) {
    for (CaptureReply &reply : pictures) reply(nullptr);
    return;
  }
  passes_->record_capture(cmd, inputs, readback);
  captures_.push_back({readback, targets.output_width, targets.output_height, frame_index_, false, std::move(pictures)});
}

void Renderer::start_generated_capture(cg_cmd *cmd, std::vector<CaptureReply> replies) {
  if (replies.empty()) return;
  const Targets &targets = passes_->targets();
  cg_buffer *readback = backend_->buffer_create(device_, uint64_t(targets.output_width) * targets.output_height * 4, CG_MEMORY_READBACK, "generated capture");
  if (!readback) {
    for (CaptureReply &reply : replies) reply(nullptr);
    return;
  }
  passes_->record_generated_capture(cmd, readback);
  bool bgra = backend_->surface_format(device_) == CG_FORMAT_BGRA8_SRGB || backend_->surface_format(device_) == CG_FORMAT_BGRA8_UNORM;
  captures_.push_back({readback, targets.output_width, targets.output_height, frame_index_, bgra, std::move(replies)});
}

void Renderer::end_frame(cg_cmd *cmd, const FrameInputs &inputs) {
  if (!inputs.generate || !passes_->generating()) {
    backend_->frame_end(device_, cmd);
    return;
  }
  const Targets &targets = passes_->targets();
  cg_texture *first = passes_->generated_valid() ? targets.generated : targets.final;
  backend_->frame_end_pair(device_, cmd, first, targets.final, 1.0f / std::max(refresh_rate_.load(), 1.0f));
  passes_->finish_generated();
}

void Renderer::finish_captures(bool everything) {
  std::vector<PendingCapture> waiting;
  for (PendingCapture &capture : captures_) {
    if (!everything && frame_index_ < capture.frame + 3) {
      waiting.push_back(std::move(capture));
      continue;
    }
    auto *pixels = static_cast<uint8_t *>(backend_->buffer_contents(capture.readback));
    if (capture.swap_red_blue && pixels)
      for (size_t at = 0; at < size_t(capture.width) * capture.height * 4; at += 4) std::swap(pixels[at], pixels[at + 2]);
    Capture result{capture.width, capture.height, pixels};
    for (CaptureReply &reply : capture.replies) reply(&result);
    backend_->buffer_destroy(device_, capture.readback);
  }
  captures_.swap(waiting);
}

bool Renderer::has_work() {
  std::lock_guard lock(mutex_);
  return !batches_.empty() || !capture_requests_.empty() || !captures_.empty();
}

void Renderer::run() {
  while (running_) {
    bool resized = resized_.exchange(false);
    if (resized && !offscreen_) backend_->surface_resize(device_, pending_width_, pending_height_);
    if (offscreen_ && !resized && !has_work()) {
      std::unique_lock lock(mutex_);
      wake_.wait_for(lock, std::chrono::milliseconds(50), [this] { return !running_ || !batches_.empty() || !capture_requests_.empty(); });
      continue;
    }
    if (draw_frame()) continue;
    take_batches();
    std::unique_lock lock(mutex_);
    wake_.wait_for(lock, std::chrono::milliseconds(16));
  }
}

void Renderer::take_batches() {
  std::deque<Batch> taken;
  {
    std::lock_guard lock(mutex_);
    taken.swap(batches_);
  }
  for (Batch &batch : taken) {
    std::string error;
    if (!apply_stream(scene_, changes_, batch.data, batch.size, batch.arrival, error)) report_error_(error);
    batch.release();
  }
}

bool Renderer::draw_frame() {
  cg_cmd *cmd = backend_->frame_begin(device_);
  if (!cmd) return false;
  double frame_started = now_seconds();
  record_interval(frame_started);
  finish_captures(false);
  std::vector<CaptureRequest> requests = take_capture_requests();
  take_batches();
  scene_.collect_released(changes_);
  resources_->apply(cmd, changes_);
  uint32_t width = pending_width_, height = pending_height_;
  FrameArena &arena = arenas_[frame_index_++ % 3];
  FrameInputs inputs{};
  bool upscale = (scene_.requested_effects & EffectUpscaling) && upscaling_;
  float scale = upscale ? std::clamp(scene_.environment.render_scale, 0.25f, 1.0f) : 1.0f;
  uint32_t render_width = std::max(1u, static_cast<uint32_t>(width * scale)), render_height = std::max(1u, static_cast<uint32_t>(height * scale));
  bool generate = should_generate((scene_.requested_effects & EffectFrameGeneration) && frame_generation_ && !offscreen_);
  if (passes_->resize(render_width, render_height, width, height, generate)) {
    if (!scene_.camera_set && !scene_.layers.empty()) build_flat_frame(arena, inputs);
    else build_frame(cmd, arena, inputs, now_seconds());
    if (arena.ready() && inputs.frame != 0) {
      passes_->record(cmd, inputs);
      start_capture(cmd, inputs, std::move(requests));
      requests.clear();
    }
    if (inputs.scene) backend_->accel_destroy(device_, inputs.scene);
  }
  if (!requests.empty()) {
    std::lock_guard lock(mutex_);
    capture_requests_.insert(capture_requests_.begin(), std::make_move_iterator(requests.begin()), std::make_move_iterator(requests.end()));
  }
  cpu_seconds_ = cpu_seconds_ * 0.9f + static_cast<float>(now_seconds() - frame_started) * 0.1f;
  end_frame(cmd, inputs);
  if (backend_->frame_gpu_seconds) gpu_seconds_ = gpu_seconds_ * 0.9f + backend_->frame_gpu_seconds(device_) * 0.1f;
  frames_drawn_++;
  return true;
}

void Renderer::record_interval(double started) {
  double previous = last_frame_started_;
  last_frame_started_ = started;
  if (previous == 0 || started - switched_at_ < 0.25) return;
  float interval = static_cast<float>(started - previous);
  float &average = generating_ ? interval_with_ : interval_without_;
  average = average == 0 ? interval : average * 0.9f + interval * 0.1f;
}

bool Renderer::should_generate(bool requested) {
  if (!requested) {
    generating_ = false;
    return false;
  }
  double now = now_seconds();
  if (now - switched_at_ < 2.0) return generating_;
  float refresh = std::max(refresh_rate_.load(), 1.0f);
  float without = interval_without_ > 0 ? 1.0f / interval_without_ : refresh;
  float with = interval_with_ > 0 ? 2.0f / interval_with_ : 2.0f * std::min(refresh * 0.5f, without / 1.4f);
  bool wanted = with > without * 1.1f;
  if (wanted != generating_) {
    generating_ = wanted;
    switched_at_ = now;
  }
  return generating_;
}

bool Renderer::has_opaque_part(const Instance &instance, const GpuMesh &mesh) const {
  for (uint32_t part = 0; part < mesh.parts.size(); part++) {
    uint32_t material_id = instance.materials.empty() ? 0 : instance.materials[std::min<size_t>(part, instance.materials.size() - 1)];
    auto found = scene_.materials.find(material_id);
    if (found == scene_.materials.end() || !transparent(&found->second)) return true;
  }
  return false;
}

FrameStats Renderer::stats() const {
  return {frames_drawn_.load(), gpu_seconds_.load(), cpu_seconds_.load(), refresh_rate_.load(), generating_};
}

void Renderer::write_sky(GpuFrame &frame, const Environment &environment, double now) {
  if (clock_origin_ == 0) clock_origin_ = now;
  frame.sky_picture[0] = static_cast<float>(environment.sky_picture);
  frame.sky_picture[1] = environment.sky_scroll[0];
  frame.sky_picture[2] = environment.sky_scroll[1];
  frame.sky_picture[3] = static_cast<float>(now - clock_origin_);
  for (int face = 0; face < 6; face++) {
    const GpuTexture *found = environment.sky_textures[face] ? resources_->texture(environment.sky_textures[face]) : nullptr;
    frame.sky_textures[face] = found ? found->handle : resources_->black().handle;
  }
  frame.sky_sampler = resources_->sampler_handle(true, environment.sky_picture == 2);
  frame.sky_pad = frame.sky_sampler;
}

void Renderer::write_materials(FrameArena &arena, FrameInputs &inputs, std::unordered_map<uint32_t, uint32_t> &slots) {
  std::vector<GpuMaterial> materials;
  materials.reserve(scene_.materials.size() + 1);
  auto texture_or = [&](uint32_t id, const GpuTexture &fallback) {
    const GpuTexture *found = id ? resources_->texture(id) : nullptr;
    return found ? *found : fallback;
  };
  auto add = [&](const MaterialData &data) {
    GpuMaterial out{};
    std::memcpy(out.base_color, data.base_color, sizeof(out.base_color));
    for (int index = 0; index < 3; index++) out.emissive[index] = data.emissive[index] * data.emissive_strength;
    out.params[0] = data.metallic;
    out.params[1] = data.roughness;
    out.params[2] = data.alpha_cutoff;
    out.params[3] = data.lightmap_scale;
    GpuTexture base = texture_or(data.base_texture, resources_->white());
    GpuTexture lightmap = texture_or(data.lightmap_texture, resources_->black());
    bool has_lightmap = data.lightmap_texture != 0 && resources_->texture(data.lightmap_texture) != nullptr;
    out.flags[0] = ((data.flags & MaterialUnlit) ? GpuMaterialUnlit : 0) | (has_lightmap ? GpuMaterialHasLightmap : 0) |
                   ((data.flags & MaterialBlend) ? GpuMaterialBlend : 0) | ((data.flags & MaterialSky) ? GpuMaterialSky : 0) |
                   ((data.flags & MaterialWarp) ? GpuMaterialWarp : 0) |
                   ((data.flags & MaterialAdd) ? GpuMaterialAdd : 0) | ((data.flags & MaterialMultiply) ? GpuMaterialMultiply : 0) |
                   ((data.flags & MaterialReflection) ? GpuMaterialReflection : 0);
    out.extra[0] = data.uv_scroll[0];
    out.extra[1] = data.uv_scroll[1];
    out.flags[1] = std::clamp((data.flags >> 8) & 0xffu, 1u, 4u);
    out.base_texture = base.handle;
    out.metallic_roughness_texture = texture_or(data.metallic_roughness_texture, resources_->white()).handle;
    out.emissive_texture = texture_or(data.emissive_texture, resources_->white()).handle;
    out.lightmap_texture = lightmap.handle;
    out.sampler = base.sampler;
    out.lightmap_sampler = resources_->sampler_handle(true, true);
    bool has_normal_map = data.normal_texture != 0 && resources_->texture(data.normal_texture) != nullptr;
    out.normal_texture = texture_or(data.normal_texture, resources_->white()).handle;
    out.occlusion_texture = texture_or(data.occlusion_texture, resources_->white()).handle;
    out.emissive[3] = data.normal_scale;
    std::memcpy(&out.flags[2], &data.smear, sizeof(float));
    if (has_normal_map) out.flags[0] |= GpuMaterialHasNormalMap;
    materials.push_back(out);
  };
  add(MaterialData{});
  for (auto &[id, data] : scene_.materials) {
    slots[id] = static_cast<uint32_t>(materials.size());
    add(data);
  }
  inputs.materials = arena.write(materials.data(), materials.size() * sizeof(GpuMaterial));
}

void Renderer::write_lights(FrameArena &arena, FrameInputs &inputs, std::vector<GpuLight> &lights, bool &sun_shadows, Vec3 &sun_direction) {
  for (auto &[id, light] : scene_.lights) {
    bool sun = !sun_shadows && light.kind == LightKind::Directional && light.shadows;
    if (sun) {
      sun_shadows = true;
      sun_direction = light.direction;
    }
    lights.push_back(gpu_light(light, sun));
  }
  GpuLight none{};
  inputs.lights = lights.empty() ? arena.write(&none, sizeof(none)) : arena.write(lights.data(), lights.size() * sizeof(GpuLight));
}

void Renderer::build_frame(cg_cmd *cmd, FrameArena &arena, FrameInputs &inputs, double now) {
  const Targets &targets = passes_->targets();
  size_t parts = 0, bones = 0;
  for (auto &[id, instance] : scene_.instances) {
    if (const GpuMesh *mesh = resources_->mesh(instance.mesh)) parts += mesh->parts.size();
    bones += instance.bones.size() * sizeof(float) + 256;
  }
  size_t needed = sizeof(GpuFrame) + (scene_.instances.size() + 1) * (sizeof(GpuInstance) + sizeof(TracedInstance)) + parts * sizeof(TracedPart) +
                  (scene_.materials.size() + 1) * sizeof(GpuMaterial) + (scene_.lights.size() + 1) * sizeof(GpuLight) + bones + layer_bytes() + 4096;
  arena.reset(backend_, device_, needed);
  if (!arena.ready()) return;

  float progress = scene_.tick_progress(now);
  std::unordered_map<uint32_t, uint32_t> material_slots;
  write_materials(arena, inputs, material_slots);
  std::vector<GpuLight> lights;
  bool sun_shadows = false;
  Vec3 sun_direction{0, -1, 0};
  write_lights(arena, inputs, lights, sun_shadows, sun_direction);
  inputs.shadows = sun_shadows;
  uint32_t wanted = scene_.requested_effects &
                    (EffectRayTracedShadows | EffectRayTracedReflections | EffectRayTracedGlobalIllumination | EffectRayTracedAmbientOcclusion);
  bool tracing = wanted && passes_->ray_tracing();
  std::unordered_map<uint32_t, Deformed> deformed = deformer_->run(cmd, arena, scene_, *resources_, tracing);

  std::vector<GpuInstance> instances;
  std::vector<std::pair<float, Draw>> sorted_transparent;
  Transform viewer = interpolate(scene_.camera.previous, scene_.camera.current, progress);
  Vec3 camera_position = viewer.position;
  Frustum frustum = frustum_of(multiply(camera_projection(scene_.camera, static_cast<float>(targets.width), static_cast<float>(std::max(targets.height, 1u))),
                                        view_matrix(viewer.position, viewer.rotation)));
  std::unordered_map<uint32_t, Mat4> current_models;
  std::vector<cg_accel_instance> traced;
  std::vector<TracedInstance> traced_tables;
  std::vector<TracedPart> traced_parts;
  std::vector<size_t> part_offsets;
  instances.reserve(scene_.instances.size());
  for (auto &[id, instance] : scene_.instances) {
    if (instance.flags & InstanceHidden) continue;
    const GpuMesh *mesh = resources_->mesh(instance.mesh);
    if (!mesh) continue;
    Transform pose = interpolate(instance.previous, instance.current, progress);
    GpuInstance gpu{};
    copy_matrix(gpu.model, model_matrix(pose));
    copy_matrix(gpu.normal, normal_matrix(pose));
    Mat4 model = model_matrix(pose);
    auto before = previous_models_.find(id);
    copy_matrix(gpu.previous_model, before == previous_models_.end() ? model : before->second);
    bool in_front = (instance.flags & InstanceInFront) != 0;
    if (instance.shaded) {
      std::copy(instance.shading, instance.shading + 3, gpu.shading_ambient);
      std::copy(instance.shading + 3, instance.shading + 6, gpu.shading_directional);
      std::copy(instance.shading + 6, instance.shading + 9, gpu.shading_direction);
      gpu.shading_ambient[3] = 1;
    }
    gpu.shading_direction[3] = in_front ? 1.0f : 0.0f;
    std::copy(instance.swell, instance.swell + 3, gpu.swell);
    bool standing = (instance.flags & InstanceStanding) != 0;
    bool depth_always = (instance.flags & InstanceNoDepthTest) != 0;
    gpu.standing[0] = instance.standing[0];
    gpu.standing[1] = instance.standing[1];
    gpu.standing[2] = standing ? 1.0f : 0.0f;
    current_models[id] = model;
    uint32_t index = static_cast<uint32_t>(instances.size());
    instances.push_back(gpu);
    auto deformation = deformed.find(id);
    bool animated = deformation != deformed.end();
    uint64_t vertices = animated ? deformation->second.vertices : backend_->buffer_address(mesh->vertices);
    uint64_t previous_vertices = animated ? deformation->second.previous_vertices : 0;
    cg_accel *accel = animated ? deformation->second.accel : mesh->accel;
    if (accel && !in_front) {
      traced.push_back(accel_instance(model_matrix(pose), accel, !(instance.flags & InstanceNoShadow) && has_opaque_part(instance, *mesh)));
      traced_tables.push_back({vertices, backend_->buffer_address(mesh->indices), 0,
                               static_cast<uint32_t>(mesh->parts.size()), index});
      part_offsets.push_back(traced_parts.size());
      for (uint32_t part = 0; part < mesh->parts.size(); part++) {
        uint32_t material_id = instance.materials.empty() ? 0 : instance.materials[std::min<size_t>(part, instance.materials.size() - 1)];
        auto slot = material_slots.find(material_id);
        traced_parts.push_back({mesh->parts[part].first, mesh->parts[part].count, slot == material_slots.end() ? 0 : slot->second, 0});
      }
    }
    for (uint32_t part = 0; part < mesh->parts.size(); part++) {
      uint32_t material_id = instance.materials.empty() ? 0 : instance.materials[std::min<size_t>(part, instance.materials.size() - 1)];
      auto slot = material_slots.find(material_id);
      const MaterialData *data = slot == material_slots.end() ? nullptr : &scene_.materials[material_id];
      bool double_sided = data && (data->flags & MaterialDoubleSided);
      bool visible = animated || part >= mesh->bounds.size() ||
                     inside(frustum, transform_point(model, mesh->bounds[part].centre), mesh->bounds[part].radius * largest_scale(pose.scale));
      Draw item{mesh, part, index, slot == material_slots.end() ? 0 : slot->second, double_sided,
                !(instance.flags & InstanceNoShadow) && !in_front && !(data && (data->flags & MaterialSky)), animated ? vertices : 0,
                previous_vertices, visible, data && data->smear > 0, standing, blend_of(data), depth_always,
                mesh->colors ? backend_->buffer_address(mesh->colors) : 0};
      if (transparent(data) || depth_always || standing) {
        Vec3 offset = pose.position - camera_position;
        sorted_transparent.push_back({dot(offset, offset), item});
      } else {
        inputs.draws.push_back(item);
      }
    }
  }
  if (!traced_tables.empty()) {
    uint64_t parts = arena.write(traced_parts.data(), traced_parts.size() * sizeof(TracedPart));
    for (size_t index = 0; index < traced_tables.size(); index++) traced_tables[index].parts = parts + part_offsets[index] * sizeof(TracedPart);
    inputs.traced = arena.write(traced_tables.data(), traced_tables.size() * sizeof(TracedInstance));
  }
  if (tracing && !traced.empty())
    inputs.scene = backend_->accel_create_scene(device_, cmd, traced.data(), static_cast<uint32_t>(traced.size()));
  inputs.effects = inputs.scene ? wanted : 0;
  deformer_->release_frame(deformed);
  previous_models_.swap(current_models);
  std::sort(sorted_transparent.begin(), sorted_transparent.end(), [](const auto &a, const auto &b) { return a.first > b.first; });
  for (auto &[distance, item] : sorted_transparent) inputs.transparent.push_back(item);
  GpuInstance identity{};
  inputs.instances = instances.empty() ? arena.write(&identity, sizeof(identity))
                                       : arena.write(instances.data(), instances.size() * sizeof(GpuInstance));

  const Environment &environment = scene_.environment;
  Transform eye = interpolate(scene_.camera.previous, scene_.camera.current, progress);
  float aspect = viewport_aspect(scene_.camera, static_cast<float>(targets.width), static_cast<float>(targets.height));
  Mat4 projection = camera_projection(scene_.camera, static_cast<float>(targets.width), static_cast<float>(targets.height));
  Mat4 unjittered = multiply(projection, view_matrix(eye.position, eye.rotation));
  inputs.upscale = passes_->upscaling();
  inputs.generate = passes_->generating();
  inputs.delta_time = last_frame_time_ > 0 ? static_cast<float>(now - last_frame_time_) : 1.0f / 60.0f;
  last_frame_time_ = now;
  inputs.near_plane = scene_.camera.near_plane;
  inputs.far_plane = scene_.camera.far_plane;
  inputs.fov_y = scene_.camera.fov_y;
  if (inputs.upscale) {
    inputs.jitter_x = halton(frame_index_ % 32 + 1, 2) - 0.5f;
    inputs.jitter_y = halton(frame_index_ % 32 + 1, 3) - 0.5f;
    projection.at(0, 2) -= 2.0f * inputs.jitter_x / static_cast<float>(targets.width);
    projection.at(1, 2) += 2.0f * inputs.jitter_y / static_cast<float>(targets.height);
  }
  inputs.reset_history = !has_previous_ || previous_size_ != std::pair{targets.width, targets.height};
  Mat4 view_proj = multiply(projection, view_matrix(eye.position, eye.rotation));
  Mat4 previous = has_previous_ ? previous_view_proj_ : unjittered;
  previous_view_proj_ = unjittered;
  previous_size_ = {targets.width, targets.height};
  has_previous_ = true;
  GpuFrame frame{};
  copy_matrix(frame.view_proj, view_proj);
  copy_matrix(frame.previous_view_proj, previous);
  copy_matrix(frame.unjittered_view_proj, unjittered);
  copy_matrix(frame.inverse_view_proj, inverse(view_proj));
  for (uint32_t index = 0; index < Passes::Cascades; index++) {
    Cascade slice = cascade(eye, scene_.camera, aspect, sun_direction, environment.shadow_distance, index);
    copy_matrix(frame.shadow_cascades + index * 16, slice.view_projection);
    frame.cascade_splits[index] = slice.split;
  }
  for (size_t style = 0; style < 64; style++) std::copy_n(scene_.light_styles.begin() + style * 3, 3, frame.light_styles + style * 4);
  std::copy(std::begin(scene_.screen_tint), std::end(scene_.screen_tint), frame.screen_tint);
  const GpuTexture *overlay = scene_.overlay ? resources_->texture(scene_.overlay) : nullptr;
  frame.overlay = overlay ? overlay->handle : 0;
  frame.overlay_pad = frame.overlay;
  frame.bloom[3] = overlay ? 1.0f : 0.0f;
  frame.curve[0] = environment.gamma;
  frame.curve[1] = environment.contrast;
  frame.curve[2] = environment.brightness;
  frame.curve[3] = scene_.overlay_premultiplied ? 1.0f : 0.0f;
  frame.bloom[0] = environment.bloom_strength;
  frame.bloom[1] = environment.bloom_threshold;
  frame.bloom[2] = static_cast<float>(environment.tone_map);
  write_sky(frame, environment, now);
  inputs.bloom_strength = environment.bloom_strength;
  inputs.bloom_threshold = environment.bloom_threshold;
  copy_vec(frame.camera_position, eye.position, static_cast<float>(now));
  copy_vec(frame.previous_camera_position, has_previous_eye_ ? previous_eye_ : eye.position, 0);
  previous_eye_ = eye.position;
  has_previous_eye_ = true;
  copy_vec(frame.sky_top, environment.sky_top, 1);
  copy_vec(frame.sky_horizon, environment.sky_horizon, 1);
  copy_vec(frame.sky_ground, environment.sky_ground, 1);
  copy_vec(frame.ambient, environment.ambient, environment.ambient_intensity);
  copy_vec(frame.fog, environment.fog_color, environment.fog_density);
  frame.screen[0] = static_cast<float>(targets.width);
  frame.screen[1] = static_cast<float>(targets.height);
  frame.screen[2] = 1.0f / frame.screen[0];
  frame.screen[3] = 1.0f / frame.screen[1];
  frame.settings[0] = environment.exposure;
  frame.settings[1] = environment.shadow_distance / Passes::ShadowMapSize * 1.5f;
  frame.settings[2] = static_cast<float>(Passes::ShadowMapSize);
  frame.settings[3] = environment.reflections;
  frame.ray_tracing[0] = environment.ao_radius;
  frame.ray_tracing[1] = environment.ao_strength;
  frame.ray_tracing[2] = frame.settings[1];
  frame.counts[0] = static_cast<uint32_t>(lights.size());
  frame.counts[1] = inputs.effects;
  frame.counts[2] = static_cast<uint32_t>(frame_index_);
  frame.gbuffer_albedo = backend_->texture_handle(targets.albedo);
  frame.gbuffer_normal = backend_->texture_handle(targets.normal);
  frame.gbuffer_emissive = backend_->texture_handle(targets.emissive);
  frame.gbuffer_baked = backend_->texture_handle(targets.baked);
  frame.depth = backend_->texture_handle(targets.depth);
  frame.shadow_map0 = backend_->texture_handle(targets.shadow_maps[0]);
  frame.shadow_map1 = backend_->texture_handle(targets.shadow_maps[1]);
  frame.shadow_map2 = backend_->texture_handle(targets.shadow_maps[2]);
  frame.shadow_map3 = backend_->texture_handle(targets.shadow_maps[3]);
  cg_texture *bloom = passes_->bloom_result();
  frame.bloom_texture = bloom ? backend_->texture_handle(bloom) : frame.hdr;
  if (!bloom) frame.bloom[0] = 0;
  frame.hdr = backend_->texture_handle(inputs.upscale ? targets.upscaled : targets.hdr);
  frame.point_clamp = resources_->sampler_handle(false, true);
  frame.linear_clamp = resources_->sampler_handle(true, true);
  frame.gbuffer_motion = backend_->texture_handle(targets.motion_geometry);
  std::copy(std::begin(scene_.camera.viewport), std::end(scene_.camera.viewport), frame.viewport);
  copy_vec(frame.view_forward, rotate(eye.rotation, Vec3{0, 0, -1}), 0);
  frame.resolution[0] = scene_.camera.resolution[0];
  frame.resolution[1] = scene_.camera.resolution[1];
  frame.nearest = backend_->texture_handle(targets.nearest);
  frame.nearest_pad = frame.nearest;
  const GpuTexture *table = environment.light_table ? resources_->texture(environment.light_table) : nullptr;
  frame.display[0] = environment.display_light ? 1.0f : 0.0f;
  frame.display[2] = environment.light_reach;
  frame.display[3] = table ? 1.0f : 0.0f;
  frame.light_table = table ? table->handle : resources_->white().handle;
  frame.light_table_pad = frame.light_table;
  frame.lit = backend_->texture_handle(targets.hdr);
  frame.behind = targets.behind ? backend_->texture_handle(targets.behind) : frame.lit;
  frame.layers[0] = build_layers(arena, inputs) ? 1.0f : 0.0f;
  frame.flat = frame.flat_pad = backend_->texture_handle(targets.flat);
  inputs.frame = arena.write(&frame, sizeof(frame));
}

size_t Renderer::layer_bytes() const {
  size_t bytes = 0;
  for (const Layer &layer : scene_.layers)
    bytes += sizeof(GpuLayer) + layer.sprites.size() * sizeof(GpuSprite) + layer.columns.size() / 3 * 16 + 512;
  return bytes;
}

void Renderer::build_flat_frame(FrameArena &arena, FrameInputs &inputs) {
  const Targets &targets = passes_->targets();
  arena.reset(backend_, device_, sizeof(GpuFrame) + layer_bytes() + 4096);
  if (!arena.ready()) return;
  inputs.flat_only = true;
  GpuFrame frame{};
  frame.layers[0] = build_layers(arena, inputs) ? 1.0f : 0.0f;
  frame.flat = frame.flat_pad = backend_->texture_handle(targets.flat);
  frame.point_clamp = resources_->sampler_handle(false, true);
  frame.linear_clamp = resources_->sampler_handle(true, true);
  inputs.frame = arena.write(&frame, sizeof(frame));
}

bool Renderer::build_layers(FrameArena &arena, FrameInputs &inputs) {
  const Targets &targets = passes_->targets();
  bool flat_started = false;
  for (const Layer &layer : scene_.layers) {
    cg_texture *target = targets.flat;
    uint32_t width = targets.output_width, height = targets.output_height;
    if (layer.target) {
      const GpuTexture *canvas = resources_->texture(layer.target);
      if (!canvas || !canvas->canvas) continue;
      target = canvas->texture;
      width = canvas->width;
      height = canvas->height;
    }
    LayerDraw draw{layer.kind, target, layer.clear, {}, 0, 0, {}};
    std::copy(std::begin(layer.clear_colour), std::end(layer.clear_colour), draw.clear_colour);
    if (!layer.target && !flat_started) {
      if (!layer.clear) std::fill(std::begin(draw.clear_colour), std::end(draw.clear_colour), 0.0f);
      draw.clear = true;
      flat_started = true;
    }
    GpuLayer gpu{};
    bool whole_target = layer.port[2] <= 0 || layer.port[3] <= 0;
    float port[4] = {whole_target ? 0 : layer.port[0], whole_target ? 0 : layer.port[1],
                     whole_target ? float(width) : layer.port[2], whole_target ? float(height) : layer.port[3]};
    bool target_pixels = layer.view[2] == 0 || layer.view[3] == 0;
    float view[4] = {target_pixels ? 0 : layer.view[0], target_pixels ? 0 : layer.view[1],
                     target_pixels ? port[2] : layer.view[2], target_pixels ? port[3] : layer.view[3]};
    std::copy(std::begin(port), std::end(port), gpu.port);
    std::copy(std::begin(view), std::end(view), gpu.view);
    gpu.target[0] = float(width);
    gpu.target[1] = float(height);
    gpu.target[2] = 1.0f / float(width);
    gpu.target[3] = 1.0f / float(height);
    if (layer.kind == LayerKind::Columns) build_columns(arena, layer, draw, gpu);
    else build_sprites(arena, layer, draw);
    draw.layer = arena.write(&gpu, sizeof(gpu));
    if (draw.layer) inputs.layers.push_back(std::move(draw));
  }
  if (inputs.flat_only && !flat_started) {
    inputs.layers.push_back({LayerKind::Sprites, targets.flat, true, {0, 0, 0, 0}, 0, 0, {}});
    flat_started = true;
  }
  return flat_started;
}

void Renderer::build_sprites(FrameArena &arena, const Layer &layer, LayerDraw &draw) {
  std::vector<GpuSprite> sprites;
  sprites.reserve(layer.sprites.size());
  for (const Sprite &sprite : layer.sprites) {
    const GpuTexture *texture = resources_->texture(sprite.texture);
    if (!texture || sprite.texture == layer.target) continue;
    bool whole = sprite.source[2] <= 0 || sprite.source[3] <= 0;
    GpuSprite out{{sprite.position[0], sprite.position[1], sprite.origin[0], sprite.origin[1]},
                  {sprite.scale[0], sprite.scale[1], sprite.turn[0], sprite.turn[1]},
                  {whole ? 0 : sprite.source[0], whole ? 0 : sprite.source[1], whole ? float(texture->width) : sprite.source[2],
                   whole ? float(texture->height) : sprite.source[3]},
                  {sprite.colour[0], sprite.colour[1], sprite.colour[2], sprite.colour[3]},
                  {1.0f / float(texture->width), 1.0f / float(texture->height), float(sprite.mode), texture->linear ? 0.0f : 1.0f},
                  texture->handle,
                  texture->sampler};
    uint32_t index = static_cast<uint32_t>(sprites.size());
    if (!draw.runs.empty() && draw.runs.back().mode == sprite.mode) draw.runs.back().count++;
    else draw.runs.push_back({sprite.mode, index, 1});
    sprites.push_back(out);
  }
  if (!sprites.empty()) draw.items = arena.write(sprites.data(), sprites.size() * sizeof(GpuSprite));
  if (!draw.items) draw.runs.clear();
}

void Renderer::build_columns(FrameArena &arena, const Layer &layer, LayerDraw &draw, GpuLayer &gpu) {
  const GpuTexture *source = resources_->texture(layer.source);
  size_t count = layer.columns.size() / 3;
  if (!source || layer.source == layer.target || count == 0) return;
  std::vector<float> entries(count * 4, 0.0f);
  for (size_t column = 0; column < count; column++) std::copy_n(layer.columns.begin() + column * 3, 3, entries.begin() + column * 4);
  gpu.source = source->handle;
  gpu.sampler = resources_->sampler_handle(true, true);
  gpu.counts[0] = static_cast<uint32_t>(count);
  draw.items = arena.write(entries.data(), entries.size() * sizeof(float));
}

}
