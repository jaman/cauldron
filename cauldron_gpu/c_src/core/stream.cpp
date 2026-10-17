#include <algorithm>
#include <cstring>

#include "scene.h"

namespace cg {

namespace {

enum Op : uint8_t {
  OpTick = 1,
  OpMeshPut = 2,
  OpMeshDrop = 3,
  OpTexturePut = 4,
  OpTextureDrop = 5,
  OpMaterialPut = 6,
  OpMaterialDrop = 7,
  OpInstancePut = 8,
  OpInstanceMove = 9,
  OpInstanceDrop = 10,
  OpLightPut = 11,
  OpLightDrop = 12,
  OpCamera = 13,
  OpEnvironment = 14,
  OpEffects = 15,
  OpMeshPutSkinned = 16,
  OpInstancePose = 17,
  OpLightStyles = 18,
  OpOverlay = 19,
  OpScreenTint = 20,
  OpCanvas = 21,
  OpLayers = 22
};

class Reader {
 public:
  Reader(const uint8_t *data, size_t size) : data_(data), size_(size) {}

  bool done() const { return at_ >= size_; }
  bool failed() const { return failed_; }

  template <typename T>
  T read() {
    T value{};
    bytes(&value, sizeof(T));
    return value;
  }

  void bytes(void *out, size_t count) {
    if (failed_ || count > size_ - at_) {
      failed_ = true;
      std::memset(out, 0, count);
      return;
    }
    std::memcpy(out, data_ + at_, count);
    at_ += count;
  }

  Vec3 vec3() { return {read<float>(), read<float>(), read<float>()}; }
  Quat quat() { return normalize(Quat{read<float>(), read<float>(), read<float>(), read<float>()}); }

  Transform transform() {
    Transform result;
    result.position = vec3();
    result.rotation = quat();
    result.scale = vec3();
    return result;
  }

  bool fits(size_t count, size_t element) const {
    return !failed_ && element != 0 && count <= (size_ - at_) / element;
  }

  void fail() { failed_ = true; }

 private:
  const uint8_t *data_;
  size_t size_;
  size_t at_ = 0;
  bool failed_ = false;
};

void read_mesh(Reader &in, Changes &changes, bool skinned) {
  uint32_t id = in.read<uint32_t>();
  uint32_t vertex_count = in.read<uint32_t>();
  uint32_t index_count = in.read<uint32_t>();
  uint32_t part_count = in.read<uint32_t>();
  MeshData mesh;
  if (!in.fits(part_count, sizeof(MeshPart))) return in.fail();
  mesh.parts.resize(part_count);
  in.bytes(mesh.parts.data(), part_count * sizeof(MeshPart));
  if (!in.fits(vertex_count, sizeof(Vertex))) return in.fail();
  mesh.vertices.resize(vertex_count);
  in.bytes(mesh.vertices.data(), vertex_count * sizeof(Vertex));
  if (!in.fits(index_count, sizeof(uint32_t))) return in.fail();
  mesh.indices.resize(index_count);
  in.bytes(mesh.indices.data(), index_count * sizeof(uint32_t));
  if (skinned) {
    if (!in.fits(vertex_count, 8)) return in.fail();
    mesh.skin.resize(size_t(vertex_count) * 8);
    in.bytes(mesh.skin.data(), mesh.skin.size());
  }
  if (in.read<uint32_t>() != 0) {
    if (!in.fits(vertex_count, 4)) return in.fail();
    mesh.colors.resize(size_t(vertex_count) * 4);
    in.bytes(mesh.colors.data(), mesh.colors.size());
  }
  bool parts_fit = std::all_of(mesh.parts.begin(), mesh.parts.end(), [&](const MeshPart &part) {
    return part.first <= index_count && part.count <= index_count - part.first;
  });
  bool indices_fit = std::all_of(mesh.indices.begin(), mesh.indices.end(), [&](uint32_t index) { return index < vertex_count; });
  if (!parts_fit || !indices_fit) return in.fail();
  changes.meshes.emplace_back(id, std::move(mesh));
}

size_t bytes_per_pixel(TextureFormat format) {
  return format == TextureFormat::Rgba16Float ? 8 : 4;
}

void read_texture(Reader &in, Changes &changes) {
  uint32_t id = in.read<uint32_t>();
  TextureData texture;
  uint8_t format = in.read<uint8_t>();
  if (format > 2) return in.fail();
  texture.format = static_cast<TextureFormat>(format);
  texture.linear_filter = in.read<uint8_t>() != 0;
  texture.clamp = in.read<uint8_t>() != 0;
  texture.mips = in.read<uint8_t>() != 0;
  texture.width = in.read<uint32_t>();
  texture.height = in.read<uint32_t>();
  if (texture.width == 0 || texture.height == 0 || texture.width > 16384 || texture.height > 16384) return in.fail();
  size_t pixel_count = size_t(texture.width) * texture.height;
  size_t element = bytes_per_pixel(texture.format);
  if (!in.fits(pixel_count, element)) return in.fail();
  texture.pixels.resize(pixel_count * element);
  in.bytes(texture.pixels.data(), texture.pixels.size());
  changes.textures.emplace_back(id, std::move(texture));
}

void read_canvas(Reader &in, Changes &changes) {
  uint32_t id = in.read<uint32_t>();
  TextureData texture;
  texture.format = TextureFormat::Rgba8Linear;
  texture.linear_filter = in.read<uint8_t>() != 0;
  texture.clamp = true;
  texture.mips = false;
  texture.canvas = true;
  texture.width = in.read<uint32_t>();
  texture.height = in.read<uint32_t>();
  if (texture.width == 0 || texture.height == 0 || texture.width > 16384 || texture.height > 16384) return in.fail();
  changes.textures.emplace_back(id, std::move(texture));
}

bool read_layer(Reader &in, Layer &layer) {
  uint8_t kind = in.read<uint8_t>();
  if (kind > 1) return false;
  layer.kind = static_cast<LayerKind>(kind);
  layer.target = in.read<uint32_t>();
  layer.clear = in.read<uint8_t>() != 0;
  in.bytes(layer.clear_colour, sizeof(layer.clear_colour));
  in.bytes(layer.port, sizeof(layer.port));
  if (layer.kind == LayerKind::Sprites) {
    in.bytes(layer.view, sizeof(layer.view));
    uint32_t count = in.read<uint32_t>();
    if (!in.fits(count, sizeof(Sprite))) return false;
    layer.sprites.resize(count);
    in.bytes(layer.sprites.data(), size_t(count) * sizeof(Sprite));
    return std::all_of(layer.sprites.begin(), layer.sprites.end(), [](const Sprite &sprite) { return sprite.mode <= 2; });
  }
  layer.source = in.read<uint32_t>();
  uint32_t count = in.read<uint32_t>();
  if (count > 16384 || !in.fits(count, 3 * sizeof(float))) return false;
  layer.columns.resize(size_t(count) * 3);
  in.bytes(layer.columns.data(), layer.columns.size() * sizeof(float));
  return true;
}

void read_layers(Reader &in, Scene &scene) {
  uint32_t count = in.read<uint32_t>();
  if (count > 4096) return in.fail();
  std::vector<Layer> layers(count);
  for (Layer &layer : layers)
    if (!read_layer(in, layer)) return in.fail();
  if (in.failed()) return;
  scene.layers = std::move(layers);
}

void read_material(Reader &in, Scene &scene) {

  uint32_t id = in.read<uint32_t>();
  MaterialData material;
  in.bytes(material.base_color, sizeof(material.base_color));
  in.bytes(material.emissive, sizeof(material.emissive));
  material.emissive_strength = in.read<float>();
  material.metallic = in.read<float>();
  material.roughness = in.read<float>();
  material.alpha_cutoff = in.read<float>();
  material.flags = in.read<uint32_t>();
  material.base_texture = in.read<uint32_t>();
  material.metallic_roughness_texture = in.read<uint32_t>();
  material.emissive_texture = in.read<uint32_t>();
  material.lightmap_texture = in.read<uint32_t>();
  material.lightmap_scale = in.read<float>();
  material.normal_texture = in.read<uint32_t>();
  material.occlusion_texture = in.read<uint32_t>();
  material.normal_scale = in.read<float>();
  material.smear = std::max(in.read<float>(), 0.0f);
  material.uv_scroll[0] = in.read<float>();
  material.uv_scroll[1] = in.read<float>();
  if (in.failed()) return;
  scene.materials[id] = material;
  scene.materials_changed = true;
}

void read_instance(Reader &in, Scene &scene) {
  uint32_t id = in.read<uint32_t>();
  Instance instance;
  instance.mesh = in.read<uint32_t>();
  instance.flags = in.read<uint32_t>();
  instance.current = in.transform();
  uint32_t material_count = in.read<uint32_t>();
  if (!in.fits(material_count, sizeof(uint32_t))) return in.fail();
  instance.materials.resize(material_count);
  in.bytes(instance.materials.data(), material_count * sizeof(uint32_t));
  instance.shaded = in.read<uint32_t>() != 0;
  in.bytes(instance.shading, sizeof(instance.shading));
  in.bytes(instance.swell, sizeof(instance.swell));
  in.bytes(instance.standing, sizeof(instance.standing));
  if (in.failed()) return;
  auto existing = scene.instances.find(id);
  bool snap = existing == scene.instances.end() || (instance.flags & InstanceSnap);
  instance.previous = snap ? instance.current : existing->second.current;
  if (existing != scene.instances.end()) {
    instance.blend_mesh = existing->second.blend_mesh;
    instance.blend = existing->second.blend;
    instance.bones = existing->second.bones;
  }
  scene.instances[id] = std::move(instance);
}

void read_move(Reader &in, Scene &scene) {
  uint32_t id = in.read<uint32_t>();
  uint32_t flags = in.read<uint32_t>();
  Transform transform = in.transform();
  if (in.failed()) return;
  auto found = scene.instances.find(id);
  if (found == scene.instances.end()) return;
  found->second.previous = (flags & InstanceSnap) ? transform : found->second.current;
  found->second.current = transform;
}

void read_pose(Reader &in, Scene &scene) {
  uint32_t id = in.read<uint32_t>();
  uint32_t blend_mesh = in.read<uint32_t>();
  float blend = in.read<float>();
  uint32_t bone_count = in.read<uint32_t>();
  if (bone_count > 255 || !in.fits(bone_count, 12 * sizeof(float))) return in.fail();
  std::vector<float> bones(size_t(bone_count) * 12);
  in.bytes(bones.data(), bones.size() * sizeof(float));
  if (in.failed()) return;
  auto found = scene.instances.find(id);
  if (found == scene.instances.end()) return;
  found->second.blend_mesh = blend_mesh;
  found->second.blend = std::clamp(blend, 0.0f, 1.0f);
  found->second.bones = std::move(bones);
}

void read_light_styles(Reader &in, Scene &scene) {
  uint32_t count = in.read<uint32_t>();
  if (count > 64 || !in.fits(count, 3 * sizeof(float))) return in.fail();
  std::vector<float> scales(size_t(count) * 3);
  in.bytes(scales.data(), scales.size() * sizeof(float));
  if (in.failed()) return;
  std::copy(scales.begin(), scales.end(), scene.light_styles.begin());
}

void read_light(Reader &in, Scene &scene) {
  uint32_t id = in.read<uint32_t>();
  Light light;
  uint8_t kind = in.read<uint8_t>();
  if (kind > 2) return in.fail();
  light.kind = static_cast<LightKind>(kind);
  light.shadows = in.read<uint8_t>() != 0;
  in.read<uint16_t>();
  light.color = in.vec3();
  light.intensity = in.read<float>();
  light.position = in.vec3();
  light.direction = normalize(in.vec3());
  light.range = in.read<float>();
  light.inner_cone = in.read<float>();
  light.outer_cone = in.read<float>();
  if (in.failed()) return;
  scene.lights[id] = light;
}

void read_camera(Reader &in, Scene &scene) {
  Transform transform;
  transform.position = in.vec3();
  transform.rotation = in.quat();
  float fov_y = in.read<float>();
  float near_plane = in.read<float>();
  float far_plane = in.read<float>();
  uint32_t flags = in.read<uint32_t>();
  float viewport[4];
  in.bytes(viewport, sizeof(viewport));
  float aspect = in.read<float>();
  float resolution[2];
  in.bytes(resolution, sizeof(resolution));
  if (in.failed() || near_plane <= 0 || far_plane <= near_plane || fov_y <= 0 || viewport[2] <= 0 || viewport[3] <= 0) return in.fail();
  std::copy(std::begin(viewport), std::end(viewport), scene.camera.viewport);
  scene.camera.aspect = std::max(aspect, 0.0f);
  scene.camera.resolution[0] = std::max(std::floor(resolution[0]), 0.0f);
  scene.camera.resolution[1] = std::max(std::floor(resolution[1]), 0.0f);
  scene.camera.previous = (flags & InstanceSnap) ? transform : scene.camera.current;
  scene.camera.current = transform;
  scene.camera.fov_y = fov_y;
  scene.camera.near_plane = near_plane;
  scene.camera.far_plane = far_plane;
  scene.camera_set = true;
}

void read_environment(Reader &in, Scene &scene) {
  Environment environment;
  environment.sky_top = in.vec3();
  environment.sky_horizon = in.vec3();
  environment.sky_ground = in.vec3();
  environment.ambient = in.vec3();
  environment.ambient_intensity = in.read<float>();
  environment.fog_color = in.vec3();
  environment.fog_density = in.read<float>();
  environment.exposure = in.read<float>();
  environment.shadow_distance = in.read<float>();
  environment.reflections = in.read<float>();
  environment.ao_radius = in.read<float>();
  environment.ao_strength = in.read<float>();
  environment.render_scale = in.read<float>();
  environment.bloom_strength = in.read<float>();
  environment.bloom_threshold = in.read<float>();
  environment.tone_map = std::min(in.read<uint32_t>(), 2u);
  environment.sky_picture = std::min(in.read<uint32_t>(), 2u);
  for (uint32_t &texture : environment.sky_textures) texture = in.read<uint32_t>();
  environment.sky_scroll[0] = in.read<float>();
  environment.sky_scroll[1] = in.read<float>();
  environment.display_light = in.read<uint32_t>() != 0;
  environment.gamma = std::max(in.read<float>(), 0.01f);
  environment.contrast = in.read<float>();
  environment.brightness = in.read<float>();
  environment.light_table = in.read<uint32_t>();
  environment.light_reach = std::max(in.read<float>(), 1e-6f);
  if (in.failed()) return;
  scene.environment = environment;
}

void settle_moves(Scene &scene) {
  for (auto &[id, instance] : scene.instances) instance.previous = instance.current;
  scene.camera.previous = scene.camera.current;
}

bool read_op(Reader &in, Scene &scene, Changes &changes, double now) {
  switch (in.read<uint8_t>()) {
    case OpTick:
      settle_moves(scene);
      scene.begin_tick(now);
      break;
    case OpMeshPut: read_mesh(in, changes, false); break;
    case OpMeshPutSkinned: read_mesh(in, changes, true); break;
    case OpInstancePose: read_pose(in, scene); break;
    case OpLightStyles: read_light_styles(in, scene); break;
    case OpOverlay:
      scene.overlay = in.read<uint32_t>();
      scene.overlay_premultiplied = in.read<uint8_t>() != 0;
      break;
    case OpScreenTint: in.bytes(scene.screen_tint, sizeof(scene.screen_tint)); break;
    case OpCanvas: read_canvas(in, changes); break;
    case OpLayers: read_layers(in, scene); break;
    case OpMeshDrop: scene.released_meshes.insert(in.read<uint32_t>()); break;
    case OpTexturePut: read_texture(in, changes); break;
    case OpTextureDrop: scene.released_textures.insert(in.read<uint32_t>()); break;
    case OpMaterialPut: read_material(in, scene); break;
    case OpMaterialDrop: scene.released_materials.insert(in.read<uint32_t>()); break;
    case OpInstancePut: read_instance(in, scene); break;
    case OpInstanceMove: read_move(in, scene); break;
    case OpInstanceDrop: scene.instances.erase(in.read<uint32_t>()); break;
    case OpLightPut: read_light(in, scene); break;
    case OpLightDrop: scene.lights.erase(in.read<uint32_t>()); break;
    case OpCamera: read_camera(in, scene); break;
    case OpEnvironment: read_environment(in, scene); break;
    case OpEffects: scene.requested_effects = in.read<uint32_t>(); break;
    default: in.fail(); break;
  }
  return !in.failed();
}

}

void Scene::begin_tick(double now) {
  previous_tick = current_tick;
  current_tick = now;
}

void Scene::collect_released(Changes &changes) {
  if (released_meshes.empty() && released_textures.empty() && released_materials.empty()) return;
  std::unordered_set<uint32_t> used_meshes, used_materials, used_textures;
  for (auto &[id, instance] : instances) {
    used_meshes.insert(instance.mesh);
    if (instance.blend_mesh) used_meshes.insert(instance.blend_mesh);
    used_materials.insert(instance.materials.begin(), instance.materials.end());
  }
  for (auto released = released_materials.begin(); released != released_materials.end();) {
    if (used_materials.count(*released)) {
      ++released;
      continue;
    }
    materials.erase(*released);
    materials_changed = true;
    released = released_materials.erase(released);
  }
  used_textures.insert(overlay);
  used_textures.insert(std::begin(environment.sky_textures), std::end(environment.sky_textures));
  used_textures.insert(environment.light_table);
  for (const Layer &layer : layers) {
    used_textures.insert(layer.target);
    used_textures.insert(layer.source);
    for (const Sprite &sprite : layer.sprites) used_textures.insert(sprite.texture);
  }
  for (auto &[id, material] : materials)
    for (uint32_t texture : {material.base_texture, material.metallic_roughness_texture, material.emissive_texture, material.lightmap_texture,
                             material.normal_texture, material.occlusion_texture})
      used_textures.insert(texture);
  auto sweep = [](std::unordered_set<uint32_t> &released, const std::unordered_set<uint32_t> &used, std::vector<uint32_t> &dropped) {
    for (auto id = released.begin(); id != released.end();) {
      if (used.count(*id)) {
        ++id;
        continue;
      }
      dropped.push_back(*id);
      id = released.erase(id);
    }
  };
  sweep(released_meshes, used_meshes, changes.dropped_meshes);
  sweep(released_textures, used_textures, changes.dropped_textures);
}

float Scene::tick_progress(double now) const {
  double span = current_tick - previous_tick;
  if (previous_tick == 0 || span <= 0) return 1.0f;
  return static_cast<float>(std::clamp((now - current_tick) / span, 0.0, 1.0));
}

bool apply_stream(Scene &scene, Changes &changes, const uint8_t *data, size_t size, double now, std::string &error) {
  Reader in(data, size);
  while (!in.done())
    if (!read_op(in, scene, changes, now)) {
      error = "malformed change stream";
      return false;
    }
  return true;
}

}
