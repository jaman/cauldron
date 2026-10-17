module common;

public struct Vertex {
  public float4 position_u;
  public float4 normal_v;
  public float4 lightmap_uv;
}

public struct Instance {
  public float4x4 model;
  public float4x4 normal;
  public float4x4 previous_model;
  public float4 shading_ambient;
  public float4 shading_directional;
  public float4 shading_direction;
  public float4 swell;
  public float4 standing;
}

public struct Material {
  public float4 base_color;
  public float4 emissive;
  public float4 params;
  public uint4 flags;
  public float4 extra;
  public DescriptorHandle<Texture2D> base_texture;
  public DescriptorHandle<Texture2D> metallic_roughness_texture;
  public DescriptorHandle<Texture2D> emissive_texture;
  public DescriptorHandle<Texture2D> lightmap_texture;
  public DescriptorHandle<SamplerState> sampler;
  public DescriptorHandle<SamplerState> lightmap_sampler;
  public DescriptorHandle<Texture2D> normal_texture;
  public DescriptorHandle<Texture2D> occlusion_texture;
}

public struct Light {
  public float4 position_range;
  public float4 color;
  public float4 direction_kind;
  public float4 cone;
}

public struct Frame {
  public float4x4 view_proj;
  public float4x4 inverse_view_proj;
  public float4x4 shadow_cascades[4];
  public float4x4 previous_view_proj;
  public float4x4 unjittered_view_proj;
  public float4 camera_position;
  public float4 previous_camera_position;
  public float4 sky_top;
  public float4 sky_horizon;
  public float4 sky_ground;
  public float4 ambient;
  public float4 fog;
  public float4 screen;
  public float4 settings;
  public float4 ray_tracing;
  public uint4 counts;
  public float4 cascade_splits;
  public float4 bloom;
  public float4 light_styles[64];
  public float4 screen_tint;
  public float4 sky_picture;
  public float4 viewport;
  public float4 display;
  public float4 view_forward;
  public float4 resolution;
  public float4 curve;
  public float4 layers;
  public DescriptorHandle<Texture2D> gbuffer_albedo;
  public DescriptorHandle<Texture2D> gbuffer_normal;
  public DescriptorHandle<Texture2D> gbuffer_emissive;
  public DescriptorHandle<Texture2D> gbuffer_baked;
  public DescriptorHandle<Texture2D> depth;
  public DescriptorHandle<Texture2D> shadow_map0;
  public DescriptorHandle<Texture2D> hdr;
  public DescriptorHandle<SamplerState> point_clamp;
  public DescriptorHandle<SamplerState> linear_clamp;
  public DescriptorHandle<Texture2D> gbuffer_motion;
  public DescriptorHandle<Texture2D> shadow_map1;
  public DescriptorHandle<Texture2D> shadow_map2;
  public DescriptorHandle<Texture2D> shadow_map3;
  public DescriptorHandle<Texture2D> bloom_texture;
  public DescriptorHandle<Texture2D> overlay;
  public DescriptorHandle<Texture2D> overlay_pad;
  public DescriptorHandle<Texture2D> sky0;
  public DescriptorHandle<Texture2D> sky1;
  public DescriptorHandle<Texture2D> sky2;
  public DescriptorHandle<Texture2D> sky3;
  public DescriptorHandle<Texture2D> sky4;
  public DescriptorHandle<Texture2D> sky5;
  public DescriptorHandle<SamplerState> sky_sampler;
  public DescriptorHandle<SamplerState> sky_pad;
  public DescriptorHandle<Texture2D> behind;
  public DescriptorHandle<Texture2D> lit;
  public DescriptorHandle<Texture2D> light_table;
  public DescriptorHandle<Texture2D> light_table_pad;
  public DescriptorHandle<Texture2D> nearest;
  public DescriptorHandle<Texture2D> nearest_pad;
  public DescriptorHandle<Texture2D> flat;
  public DescriptorHandle<Texture2D> flat_pad;
}


public struct TracedPart {
  public uint first;
  public uint count;
  public uint material;
  public uint pad;
}

public struct TracedInstance {
  public Vertex *vertices;
  public uint *indices;
  public TracedPart *parts;
  public uint part_count;
  public uint instance;
}

public struct History {
  public float4 reflection;
  public float4 gi_ao;
  public float4 info;
}

public struct Sprite {
  public float4 placement;
  public float4 shape;
  public float4 source;
  public float4 colour;
  public float4 texel;
  public DescriptorHandle<Texture2D> texture;
  public DescriptorHandle<SamplerState> sampler;
}

public struct Layer {
  public float4 view;
  public float4 port;
  public float4 target;
  public uint4 counts;
  public DescriptorHandle<Texture2D> source;
  public DescriptorHandle<SamplerState> sampler;
}

public struct SpritePush {
  public Frame *frame;
  public Layer *layer;
  public Sprite *sprites;
  public uint first;
  public uint pad;
}

public struct ColumnsPush {
  public Frame *frame;
  public Layer *layer;
  public float4 *columns;
  public uint first;
  public uint pad;
}

public float4 target_position(Layer layer, float2 pixel) {
  float2 ndc = pixel * layer.target.zw * float2(2, -2) + float2(-1, 1);
  return float4(ndc, 0, 1);
}

public bool outside_port(Layer layer, float2 pixel) {
  return any(pixel < layer.port.xy) || any(pixel >= layer.port.xy + layer.port.zw);
}

public struct DrawPush {

  public Frame *frame;
  public Vertex *vertices;
  public Instance *instances;
  public Material *materials;
  public Light *lights;
  public uint instance;
  public uint material;
  public float2 *rt;
  public TracedInstance *traced;
  public float4 *reflections;
  public Vertex *previous_vertices;
  public uint cascade;
  public uint pad;
  public float4 *gi;
  public History *history;
  public uint *colors;
}

public static const uint MATERIAL_UNLIT = 1;
public static const uint MATERIAL_HAS_LIGHTMAP = 4;
public static const uint MATERIAL_BLEND = 8;
public static const uint MATERIAL_HAS_NORMAL_MAP = 16;
public static const uint MATERIAL_SKY = 32;
public static const uint MATERIAL_WARP = 64;
public static const uint MATERIAL_ADD = 256;
public static const uint MATERIAL_MULTIPLY = 512;
public static const uint MATERIAL_REFLECTION = 1024;
public static const uint SKY_LAYERS = 1;
public static const uint SKY_BOX = 2;
public static const float SKY_MARK = 2;
public static const uint LIGHT_DIRECTIONAL = 0;
public static const uint LIGHT_POINT = 1;
public static const uint LIGHT_SPOT = 2;
public static const uint EFFECT_RT_SHADOWS = 1;
public static const uint EFFECT_RT_REFLECTIONS = 2;
public static const uint EFFECT_RT_GLOBAL_ILLUMINATION = 4;
public static const uint EFFECT_RT_AMBIENT_OCCLUSION = 32;

public float3 world_position(Frame frame, float2 uv, float depth) {
  float4 clip = float4(uv.x * 2 - 1, 1 - uv.y * 2, depth, 1);
  float4 world = mul(frame.inverse_view_proj, clip);
  return world.xyz / world.w;
}

float3 layered_sky(Frame frame, float3 direction) {
  float reach = length(float3(direction.x, direction.z, 3 * direction.y));
  float2 point = float2(direction.x, -direction.z) * (378.0 / 128.0) / max(reach, 1e-6);
  float seconds = frame.sky_picture.w;
  float3 back = frame.sky0.SampleLevel(frame.sky_sampler, point + seconds * frame.sky_picture.y, 0).rgb;
  float4 front = frame.sky1.SampleLevel(frame.sky_sampler, point + seconds * frame.sky_picture.z, 0);
  return lerp(back, front.rgb, front.a);
}

float3 boxed_sky(Frame frame, float3 direction) {
  float3 size = abs(direction);
  if (size.x >= size.y && size.x >= size.z) {
    float2 uv = float2(-direction.z * sign(direction.x), -direction.y) / size.x * 0.5 + 0.5;
    return direction.x > 0 ? frame.sky0.SampleLevel(frame.sky_sampler, uv, 0).rgb : frame.sky1.SampleLevel(frame.sky_sampler, uv, 0).rgb;
  }
  if (size.y >= size.z) {
    float2 uv = float2(direction.x, direction.z * sign(direction.y)) / size.y * 0.5 + 0.5;
    return direction.y > 0 ? frame.sky2.SampleLevel(frame.sky_sampler, uv, 0).rgb : frame.sky3.SampleLevel(frame.sky_sampler, uv, 0).rgb;
  }
  float2 uv = float2(direction.x * sign(direction.z), -direction.y) / size.z * 0.5 + 0.5;
  return direction.z > 0 ? frame.sky4.SampleLevel(frame.sky_sampler, uv, 0).rgb : frame.sky5.SampleLevel(frame.sky_sampler, uv, 0).rgb;
}

public float3 sky(Frame frame, float3 direction) {
  uint picture = uint(frame.sky_picture.x);
  if (picture == SKY_LAYERS) return layered_sky(frame, direction);
  if (picture == SKY_BOX) return boxed_sky(frame, direction);
  float up = direction.y;
  float3 above = lerp(frame.sky_horizon.rgb, frame.sky_top.rgb, pow(saturate(up), 0.6));
  float3 below = lerp(frame.sky_horizon.rgb, frame.sky_ground.rgb, pow(saturate(-up), 0.4));
  return up >= 0 ? above : below;
}

public float3 mapped_normal(Material material, float3 normal, float3 world, float2 uv) {
  if ((material.flags.x & MATERIAL_HAS_NORMAL_MAP) == 0) return normal;
  float3 tangent_normal = material.normal_texture.Sample(material.sampler, uv).xyz * 2 - 1;
  tangent_normal.xy *= material.emissive.w;
  float3 dp1 = ddx(world), dp2 = ddy(world);
  float2 duv1 = ddx(uv), duv2 = ddy(uv);
  float3 dp2perp = cross(dp2, normal), dp1perp = cross(normal, dp1);
  float3 tangent = dp2perp * duv1.x + dp1perp * duv2.x;
  float3 bitangent = dp2perp * duv1.y + dp1perp * duv2.y;
  float scale = rsqrt(max(max(dot(tangent, tangent), dot(bitangent, bitangent)), 1e-12));
  return normalize(tangent * scale * tangent_normal.x + bitangent * scale * tangent_normal.y + normal * tangent_normal.z);
}

public float3 light_style(Frame frame, uint style) {
  return frame.light_styles[style].rgb;
}

public float3 baked_light(Frame frame, Material material, float4 lightmap) {
  uint slots = clamp(material.flags.y, 1u, 4u);
  uint first = uint(lightmap.z), last = uint(lightmap.w);
  uint4 styles = uint4(first & 255, first >> 8, last & 255, last >> 8);
  float3 light = float3(0);
  for (uint slot = 0; slot < slots; slot++) {
    uint style = styles[slot];
    if (style >= 64) continue;
    float2 uv = float2(lightmap.x + float(slot) / float(slots), lightmap.y);
    light += material.lightmap_texture.SampleLevel(material.lightmap_sampler, uv, 0).rgb * light_style(frame, style);
  }
  return light * material.params.w;
}

public float2 surface_uv(Frame frame, Material material, float2 uv, float3 world, float3 normal) {
  if ((material.flags.x & MATERIAL_REFLECTION) != 0) {
    float3 reflected = reflect(normalize(world - frame.camera_position.xyz), normal);
    uv = float2(0.5 - reflected.z * 0.5, 0.5 - reflected.y * 0.5);
  }
  return warped_uv(frame, material, uv + material.extra.xy * frame.sky_picture.w);
}

public float3 swollen(Frame frame, Instance instance, float3 position, float3 normal, float2 uv) {
  if (instance.swell.y == 0) return position;
  return position + normal * instance.swell.y * sin(uv.x * instance.swell.x + frame.sky_picture.w * instance.swell.z);
}

public float4 vertex_colour(uint *colors, uint vertex_id) {
  if (colors == nullptr) return float4(1);
  uint packed = colors[vertex_id];
  float4 bytes = float4(packed & 255, (packed >> 8) & 255, (packed >> 16) & 255, packed >> 24) / 255.0;
  return float4(srgb_decode(bytes.rgb), bytes.a);
}

public float2 warped_uv(Frame frame, Material material, float2 uv) {
  if ((material.flags.x & MATERIAL_WARP) == 0) return uv;
  uint width, height;
  material.base_texture.GetDimensions(width, height);
  float2 texels = uv * float2(width, height);
  float seconds = frame.sky_picture.w;
  float2 moved = texels + 8 * sin(texels.yx / 8 + seconds);
  return moved / float2(width, height);
}

public float3 srgb_encode(float3 linear) {
  float3 c = max(linear, float3(0));
  return select(c <= 0.0031308, c * 12.92, 1.055 * pow(c, 1.0 / 2.4) - 0.055);
}

public float3 srgb_decode(float3 encoded) {
  float3 c = max(encoded, float3(0));
  return select(c <= 0.04045, c / 12.92, pow((c + 0.055) / 1.055, 2.4));
}

public float4 squeezed_in_front(Instance instance, float4 clip) {
  if (instance.shading_direction.w <= 0) return clip;
  clip.z = clip.w * 0.9 + clip.z * 0.1;
  return clip;
}

public float4 surface_light(Frame frame, Material material, Instance instance, float4 lightmap_uv, float3 normal, float3 world) {
  bool shaded = instance.shading_ambient.w > 0;
  bool has_lightmap = (material.flags.x & MATERIAL_HAS_LIGHTMAP) != 0;
  if (!shaded && !has_lightmap) return float4(0);
  float3 light = shaded ? max(instance.shading_ambient.rgb + instance.shading_directional.rgb * dot(normal, instance.shading_direction.xyz), float3(0))
                        : baked_light(frame, material, lightmap_uv);
  if (frame.display.w > 0) {
    float row = saturate(dot(world - frame.camera_position.xyz, frame.view_forward.xyz) / frame.display.z);
    light = float3(frame.light_table.SampleLevel(frame.linear_clamp, float2(saturate(light.r), row), 0).r,
                   frame.light_table.SampleLevel(frame.linear_clamp, float2(saturate(light.g), row), 0).g,
                   frame.light_table.SampleLevel(frame.linear_clamp, float2(saturate(light.b), row), 0).b);
  }
  return float4(light, 1);
}

public float3 display_lit(float3 albedo, float3 light, float3 emissive) {
  return any(emissive > 0) ? emissive : srgb_decode(srgb_encode(albedo) * light);
}

public bool hidden_while_standing(Frame frame, Instance instance, float4 position) {
  float2 uv = position.xy * frame.screen.zw;
  float nearest = frame.nearest.SampleLevel(frame.point_clamp, uv, 0).r;
  if (nearest <= position.z) return false;
  float3 normal = normalize(frame.gbuffer_normal.SampleLevel(frame.point_clamp, uv, 0).xyz);
  float height = world_position(frame, uv, nearest).y;
  bool own_floor = normal.y > 0.7071 && height <= instance.standing.x + 1e-3;
  bool own_ceiling = normal.y < -0.7071 && height >= instance.standing.y - 1e-3;
  return !(own_floor || own_ceiling);
}

public float2 clip_to_uv(float4 clip) {
  float2 ndc = clip.xy / clip.w;
  return float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
}

public float4 fullscreen_position(uint vertex_id, out float2 uv) {
  uv = float2((vertex_id << 1) & 2, vertex_id & 2);
  return float4(uv * float2(2, -2) + float2(-1, 1), 0, 1);
}
