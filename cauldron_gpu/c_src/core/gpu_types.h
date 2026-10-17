#pragma once

#include <cstdint>

namespace cg {

struct GpuInstance {
  float model[16];
  float normal[16];
  float previous_model[16];
  float shading_ambient[4];
  float shading_directional[4];
  float shading_direction[4];
  float swell[4];
  float standing[4];
};

struct GpuMaterial {
  float base_color[4];
  float emissive[4];
  float params[4];
  uint32_t flags[4];
  float extra[4];
  uint64_t base_texture;
  uint64_t metallic_roughness_texture;
  uint64_t emissive_texture;
  uint64_t lightmap_texture;
  uint64_t sampler;
  uint64_t lightmap_sampler;
  uint64_t normal_texture;
  uint64_t occlusion_texture;
};

struct GpuLight {
  float position_range[4];
  float color[4];
  float direction_kind[4];
  float cone[4];
};

struct GpuFrame {
  float view_proj[16];
  float inverse_view_proj[16];
  float shadow_cascades[64];
  float previous_view_proj[16];
  float unjittered_view_proj[16];
  float camera_position[4];
  float previous_camera_position[4];
  float sky_top[4];
  float sky_horizon[4];
  float sky_ground[4];
  float ambient[4];
  float fog[4];
  float screen[4];
  float settings[4];
  float ray_tracing[4];
  uint32_t counts[4];
  float cascade_splits[4];
  float bloom[4];
  float light_styles[256];
  float screen_tint[4];
  float sky_picture[4];
  float viewport[4];
  float display[4];
  float view_forward[4];
  float resolution[4];
  float curve[4];
  float layers[4];
  uint64_t gbuffer_albedo;
  uint64_t gbuffer_normal;
  uint64_t gbuffer_emissive;
  uint64_t gbuffer_baked;
  uint64_t depth;
  uint64_t shadow_map0;
  uint64_t hdr;
  uint64_t point_clamp;
  uint64_t linear_clamp;
  uint64_t gbuffer_motion;
  uint64_t shadow_map1;
  uint64_t shadow_map2;
  uint64_t shadow_map3;
  uint64_t bloom_texture;
  uint64_t overlay;
  uint64_t overlay_pad;
  uint64_t sky_textures[6];
  uint64_t sky_sampler;
  uint64_t sky_pad;
  uint64_t behind;
  uint64_t lit;
  uint64_t light_table;
  uint64_t light_table_pad;
  uint64_t nearest;
  uint64_t nearest_pad;
  uint64_t flat;
  uint64_t flat_pad;
};

struct DrawPush {
  uint64_t frame;
  uint64_t vertices;
  uint64_t instances;
  uint64_t materials;
  uint64_t lights;
  uint32_t instance;
  uint32_t material;
  uint64_t rt;
  uint64_t traced;
  uint64_t reflections;
  uint64_t previous_vertices;
  uint32_t cascade;
  uint32_t pad;
  uint64_t gi;
  uint64_t history;
  uint64_t colors;
};

struct DenoisePush {
  uint64_t frame;
  uint64_t rt;
  uint64_t reflections;
  uint64_t gi;
  uint64_t previous;
  uint64_t current;
  uint32_t reset;
  uint32_t pad;
};

struct DeformPush {
  uint64_t source;
  uint64_t blend_source;
  uint64_t skin;
  uint64_t bones;
  uint64_t target;
  uint32_t count;
  float blend;
  uint32_t bone_count;
  uint32_t pad;
};

struct GpuSprite {
  float placement[4];
  float shape[4];
  float source[4];
  float colour[4];
  float texel[4];
  uint64_t texture;
  uint64_t sampler;
};

struct GpuLayer {
  float view[4];
  float port[4];
  float target[4];
  uint32_t counts[4];
  uint64_t source;
  uint64_t sampler;
};

struct LayerPush {
  uint64_t frame;
  uint64_t layer;
  uint64_t items;
  uint32_t first;
  uint32_t pad;
};

struct TracedPart {

  uint32_t first;
  uint32_t count;
  uint32_t material;
  uint32_t pad;
};

struct TracedInstance {
  uint64_t vertices;
  uint64_t indices;
  uint64_t parts;
  uint32_t part_count;
  uint32_t instance;
};

enum GpuMaterialFlag : uint32_t {
  GpuMaterialUnlit = 1,
  GpuMaterialHasLightmap = 4,
  GpuMaterialBlend = 8,
  GpuMaterialHasNormalMap = 16,
  GpuMaterialSky = 32,
  GpuMaterialWarp = 64,
  GpuMaterialAdd = 256,
  GpuMaterialMultiply = 512,
  GpuMaterialReflection = 1024
};

enum Effect : uint32_t { EffectRayTracedShadows = 1, EffectRayTracedReflections = 2, EffectRayTracedGlobalIllumination = 4, EffectUpscaling = 8, EffectFrameGeneration = 16, EffectRayTracedAmbientOcclusion = 32 };

static_assert(sizeof(GpuInstance) == 272);
static_assert(sizeof(GpuMaterial) == 144);
static_assert(sizeof(GpuLight) == 64);
static_assert(sizeof(GpuFrame) == 2128);
static_assert(sizeof(GpuSprite) == 96);
static_assert(sizeof(GpuLayer) == 80);
static_assert(sizeof(DrawPush) == 112);
static_assert(sizeof(DenoisePush) == 56);
static_assert(sizeof(DeformPush) == 56);
static_assert(sizeof(TracedInstance) == 32);

}
