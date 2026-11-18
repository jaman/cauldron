#pragma once

#include <cstdint>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "math.h"

namespace cg {

struct Vertex {
  float position_u[4];
  float normal_v[4];
  float lightmap_uv[4];
};

static_assert(sizeof(Vertex) == 48);

struct MeshPart {
  uint32_t first;
  uint32_t count;
};

struct MeshData {
  std::vector<Vertex> vertices;
  std::vector<uint32_t> indices;
  std::vector<MeshPart> parts;
  std::vector<uint8_t> skin;
  std::vector<uint8_t> colors;
  std::vector<float> morphs;
  uint32_t morph_count = 0;
};

enum class TextureFormat : uint8_t { Rgba8Srgb = 0, Rgba8Linear = 1, Rgba16Float = 2, R8 = 3 };

struct TextureData {
  TextureFormat format;
  bool linear_filter;
  bool clamp;
  bool mips;
  bool canvas = false;
  bool srgb = false;
  uint32_t width;
  uint32_t height;
  std::vector<uint8_t> pixels;
};

enum MaterialFlag : uint32_t { MaterialUnlit = 1, MaterialDoubleSided = 2, MaterialBlend = 4, MaterialSky = 8, MaterialWarp = 16, MaterialAdd = 64, MaterialMultiply = 128, MaterialReflection = 65536, MaterialNoOutline = 131072 };

struct MaterialData {
  float base_color[4] = {1, 1, 1, 1};
  float emissive[3] = {0, 0, 0};
  float emissive_strength = 1;
  float metallic = 0;
  float roughness = 1;
  float alpha_cutoff = 0;
  uint32_t flags = 0;
  uint32_t base_texture = 0;
  uint32_t metallic_roughness_texture = 0;
  uint32_t emissive_texture = 0;
  uint32_t lightmap_texture = 0;
  float lightmap_scale = 1;
  uint32_t normal_texture = 0;
  uint32_t occlusion_texture = 0;
  float normal_scale = 1;
  float smear = 0;
  float uv_scroll[2] = {0, 0};
  uint32_t layers[4] = {0, 0, 0, 0};
  float layer_scale = 0;
  bool liquid = false;
  float liquid_shallow[4] = {0, 0, 0, 0};
  float liquid_deep[4] = {0, 0, 0, 0};
  float liquid_foam[4] = {0, 0, 0, 0};
  float liquid_waves[4] = {0, 0, 0, 0};
};

enum InstanceFlag : uint32_t { InstanceHidden = 1, InstanceNoShadow = 2, InstanceSnap = 4, InstanceInFront = 8, InstanceNoDepthTest = 16, InstanceStanding = 32 };

struct Instance {
  uint32_t mesh = 0;
  uint32_t flags = 0;
  Transform previous;
  Transform current;
  std::vector<uint32_t> materials;
  uint32_t blend_mesh = 0;
  float blend = 0;
  std::vector<float> bones;
  std::vector<float> morph_weights;
  bool shaded = false;
  float shading[9] = {0, 0, 0, 0, 0, 0, 0, 1, 0};
  float swell[3] = {0, 0, 0};
  float standing[2] = {0, 0};
  uint32_t scatter = 0;
  float sway[4] = {0, 0, 0, 0};
  float fade[2] = {0, 0};

  bool posed() const { return blend_mesh != 0 || !bones.empty() || !morph_weights.empty(); }
};

enum class LightKind : uint8_t { Directional = 0, Point = 1, Spot = 2 };

struct Light {
  LightKind kind = LightKind::Point;
  bool shadows = false;
  Vec3 color{1, 1, 1};
  float intensity = 1;
  Vec3 position;
  Vec3 direction{0, -1, 0};
  float range = 10;
  float inner_cone = 0.4f;
  float outer_cone = 0.6f;
};

struct Camera {
  Transform previous;
  Transform current;
  float fov_y = 1.2f;
  float near_plane = 0.05f;
  float far_plane = 1000;
  float viewport[4] = {0, 0, 1, 1};
  float aspect = 0;
  float resolution[2] = {0, 0};
};

struct Environment {
  Vec3 sky_top{0.25f, 0.45f, 0.85f};
  Vec3 sky_horizon{0.75f, 0.85f, 0.95f};
  Vec3 sky_ground{0.25f, 0.22f, 0.2f};
  Vec3 ambient{0.4f, 0.45f, 0.5f};
  float ambient_intensity = 0.3f;
  Vec3 fog_color{0.7f, 0.8f, 0.9f};
  float fog_density = 0;
  float exposure = 1;
  float shadow_distance = 60;
  float reflections = 1;
  float ao_radius = 1;
  float ao_strength = 1;
  float render_scale = 0.5f;
  float bloom_strength = 0.05f;
  float bloom_threshold = 1.0f;
  uint32_t tone_map = 0;
  uint32_t sky_picture = 0;
  uint32_t sky_textures[6] = {0, 0, 0, 0, 0, 0};
  float sky_scroll[2] = {0.0625f, 0.125f};
  bool display_light = false;
  float gamma = 1;
  float contrast = 1;
  float brightness = 0;
  uint32_t light_table = 0;
  float light_reach = 1;
  uint32_t shading = 0;
  float toon[3] = {3, 0.08f, 0};
  Vec3 shade{0.45f, 0.5f, 0.65f};
  Vec3 outline{0, 0, 0};
  float outline_width = 0;
  float outline_reach = 80;
  float wind[4] = {1, 0, 0, 1};
};

enum class SpriteMode : uint32_t { Over = 0, Add = 1, Subtract = 2 };

struct Sprite {
  uint32_t texture;
  uint32_t mode;
  float source[4];
  float position[2];
  float origin[2];
  float scale[2];
  float turn[2];
  float colour[4];
};

static_assert(sizeof(Sprite) == 72);

enum class LayerKind : uint8_t { Sprites = 0, Columns = 1, Tiles = 2, Shadows = 3, Priority = 4, PriorityShadows = 5 };

struct Tile {
  uint16_t source_x;
  uint16_t source_y;
  uint8_t width;
  uint8_t height;
  int16_t x;
  int16_t y;
  uint8_t flags;
  uint16_t base;
};

struct Layer {
  LayerKind kind = LayerKind::Sprites;
  uint32_t target = 0;
  bool clear = false;
  float clear_colour[4] = {0, 0, 0, 0};
  float port[4] = {0, 0, 0, 0};
  float view[4] = {0, 0, 0, 0};
  uint32_t source = 0;
  uint32_t palette = 0;
  uint32_t count = 0;
  uint32_t coverage = 0;
  uint32_t transparent = 0xFFFF;
  uint32_t pens = 0xFFFF;
  std::vector<Sprite> sprites;
  std::vector<float> columns;
  std::vector<Tile> tiles;
};

struct ScatterData {
  uint32_t count = 0;
  float centre[3] = {0, 0, 0};
  float radius = 0;
  float largest = 1;
  std::vector<uint8_t> placements;
};

struct Changes {
  std::vector<std::pair<uint32_t, MeshData>> meshes;
  std::vector<std::pair<uint32_t, TextureData>> textures;
  std::vector<std::pair<uint32_t, ScatterData>> scatters;
  std::vector<uint32_t> dropped_meshes;
  std::vector<uint32_t> dropped_textures;
  std::vector<uint32_t> dropped_scatters;
};

struct Scene {
  std::unordered_map<uint32_t, MaterialData> materials;
  std::unordered_map<uint32_t, Instance> instances;
  std::unordered_map<uint32_t, Light> lights;
  Camera camera;
  Environment environment;
  uint32_t requested_effects = 0;
  std::vector<float> light_styles = std::vector<float>(64 * 3, 1.0f);
  uint32_t overlay = 0;
  bool overlay_premultiplied = false;
  float screen_tint[4] = {0, 0, 0, 0};
  std::vector<float> pushers;
  std::vector<Layer> layers;
  bool camera_set = false;
  std::unordered_set<uint32_t> released_meshes;
  std::unordered_set<uint32_t> released_textures;
  std::unordered_set<uint32_t> released_materials;
  std::unordered_set<uint32_t> released_scatters;
  bool materials_changed = true;
  double previous_tick = 0;
  double current_tick = 0;

  void begin_tick(double now);
  float tick_progress(double now) const;
  void collect_released(Changes &changes);
};

bool apply_stream(Scene &scene, Changes &changes, const uint8_t *data, size_t size, double now, std::string &error);

}
