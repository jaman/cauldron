import common;

[[vk::push_constant]] ConstantBuffer<DrawPush> push;
[[vk::binding(0, 1)]] RaytracingAccelerationStructure scene;

static const uint AMBIENT_RAYS = 2;
static const float GLOSSY_ROUGHNESS = 0.7;

struct Hit {
  bool found;
  uint instance;
  uint primitive;
  float2 barycentrics;
  float distance;
}

RayDesc make_ray(float3 origin, float3 direction, float reach) {
  RayDesc ray;
  ray.Origin = origin;
  ray.Direction = direction;
  ray.TMin = 0.0;
  ray.TMax = reach;
  return ray;
}

Hit closest(float3 origin, float3 direction, float reach) {
  RayQuery<RAY_FLAG_NONE> query;
  query.TraceRayInline(scene, RAY_FLAG_NONE, 0xff, make_ray(origin, direction, reach));
  while (query.Proceed()) {}
  Hit hit;
  hit.found = query.CommittedStatus() == COMMITTED_TRIANGLE_HIT;
  hit.instance = hit.found ? query.CommittedInstanceIndex() : 0;
  hit.primitive = hit.found ? query.CommittedPrimitiveIndex() : 0;
  hit.barycentrics = hit.found ? query.CommittedTriangleBarycentrics() : float2(0);
  hit.distance = hit.found ? query.CommittedRayT() : reach;
  return hit;
}

uint hash(uint value) {
  value ^= value >> 16;
  value *= 0x7feb352d;
  value ^= value >> 15;
  value *= 0x846ca68b;
  value ^= value >> 16;
  return value;
}

float random(inout uint state) {
  state = hash(state);
  return float(state & 0xffffff) / 16777216.0;
}

float3 hemisphere(float3 normal, float u, float v) {
  float radius = sqrt(u);
  float angle = 6.2831853 * v;
  float3 tangent = normalize(abs(normal.y) < 0.99 ? cross(normal, float3(0, 1, 0)) : cross(normal, float3(1, 0, 0)));
  float3 bitangent = cross(normal, tangent);
  return normalize(tangent * radius * cos(angle) + bitangent * radius * sin(angle) + normal * sqrt(max(1 - u, 0)));
}

int sun_index(Frame frame) {
  for (uint index = 0; index < frame.counts.x; index++) {
    Light light = push.lights[index];
    if (uint(light.direction_kind.w) == LIGHT_DIRECTIONAL && light.cone.z > 0) return int(index);
  }
  return -1;
}

float sun_visibility(Frame frame, float3 origin) {
  int sun = sun_index(frame);
  return sun < 0 ? 1 : visible(origin, -push.lights[sun].direction_kind.xyz, 1e6);
}

float ambient_visibility(Frame frame, float3 origin, float3 normal, uint2 pixel) {
  uint state = hash(pixel.x * 1973 + pixel.y * 9277 + frame.counts.z * 26699);
  float open = 0;
  for (uint ray = 0; ray < AMBIENT_RAYS; ray++)
    open += visible(origin, hemisphere(normal, random(state), random(state)), frame.ray_tracing.x);
  return lerp(1.0, open / AMBIENT_RAYS, frame.ray_tracing.y);
}

uint part_material(TracedInstance traced, uint first_index) {
  for (uint index = 0; index < traced.part_count; index++) {
    TracedPart part = traced.parts[index];
    if (first_index >= part.first && first_index < part.first + part.count) return part.material;
  }
  return 0;
}

bool sky_hit(Hit hit) {
  TracedInstance traced = push.traced[hit.instance];
  return (push.materials[part_material(traced, hit.primitive * 3)].flags.x & MATERIAL_SKY) != 0;
}

float visible(float3 origin, float3 direction, float reach) {
  Hit hit = closest(origin, direction, reach);
  return !hit.found || sky_hit(hit) ? 1.0 : 0.0;
}

float3 shade_hit(Frame frame, Hit hit, float3 origin, float3 direction) {
  TracedInstance traced = push.traced[hit.instance];
  uint first_index = hit.primitive * 3;
  Vertex a = traced.vertices[traced.indices[first_index]];
  Vertex b = traced.vertices[traced.indices[first_index + 1]];
  Vertex c = traced.vertices[traced.indices[first_index + 2]];
  float3 weights = float3(1 - hit.barycentrics.x - hit.barycentrics.y, hit.barycentrics.x, hit.barycentrics.y);
  float2 uv = float2(a.position_u.w, a.normal_v.w) * weights.x + float2(b.position_u.w, b.normal_v.w) * weights.y + float2(c.position_u.w, c.normal_v.w) * weights.z;
  float4 lightmap_uv = float4(a.lightmap_uv.xy * weights.x + b.lightmap_uv.xy * weights.y + c.lightmap_uv.xy * weights.z, a.lightmap_uv.zw);
  float3 local_normal = a.normal_v.xyz * weights.x + b.normal_v.xyz * weights.y + c.normal_v.xyz * weights.z;
  Instance instance = push.instances[traced.instance];
  float3 normal = normalize(mul(instance.normal, float4(local_normal, 0)).xyz);
  if (dot(normal, direction) > 0) normal = -normal;
  Material material = push.materials[part_material(traced, first_index)];
  float4 base = material.base_color * material.base_texture.SampleLevel(material.sampler, uv, 0);
  float3 emissive = material.emissive.rgb * material.emissive_texture.SampleLevel(material.sampler, uv, 0).rgb;
  if ((material.flags.x & MATERIAL_UNLIT) != 0) return base.rgb + emissive;
  bool has_lightmap = (material.flags.x & MATERIAL_HAS_LIGHTMAP) != 0;
  float3 indirect = has_lightmap ? baked_light(frame, material, lightmap_uv) : frame.ambient.rgb * frame.ambient.w;
  float3 color = base.rgb * indirect + emissive;
  int sun = sun_index(frame);
  if (sun >= 0) {
    Light light = push.lights[sun];
    float3 towards = -light.direction_kind.xyz;
    float3 hit_point = origin + direction * hit.distance + normal * frame.ray_tracing.z;
    float lit = saturate(dot(normal, towards)) * visible(hit_point, towards, 1e6);
    color += base.rgb / 3.14159265 * light.color.rgb * light.color.w * lit;
  }
  return color;
}

float3 ggx_half_vector(float3 normal, float roughness, float u, float v) {
  float a = roughness * roughness;
  float phi = 6.2831853 * u;
  float cos_theta = sqrt((1 - v) / (1 + (a * a - 1) * v));
  float sin_theta = sqrt(1 - cos_theta * cos_theta);
  float3 tangent = normalize(abs(normal.y) < 0.99 ? cross(normal, float3(0, 1, 0)) : cross(normal, float3(1, 0, 0)));
  float3 bitangent = cross(normal, tangent);
  return normalize(tangent * sin_theta * cos(phi) + bitangent * sin_theta * sin(phi) + normal * cos_theta);
}

float3 radiance_along(Frame frame, float3 origin, float3 direction) {
  Hit hit = closest(origin, direction, 1e5);
  return hit.found && !sky_hit(hit) ? shade_hit(frame, hit, origin, direction) : sky(frame, direction);
}

float4 reflection(Frame frame, float3 origin, float3 normal, float3 world, float roughness, inout uint state) {
  if (roughness > GLOSSY_ROUGHNESS) return float4(0);
  float3 view = normalize(world - frame.camera_position.xyz);
  float3 half_vector = roughness < 0.05 ? normal : ggx_half_vector(normal, roughness, random(state), random(state));
  float3 direction = reflect(view, half_vector);
  if (dot(direction, normal) <= 0) direction = reflect(view, normal);
  return float4(radiance_along(frame, origin, direction), 1 - roughness / GLOSSY_ROUGHNESS);
}

float4 bounce(Frame frame, float3 origin, float3 normal, inout uint state) {
  return float4(radiance_along(frame, origin, hemisphere(normal, random(state), random(state))), 1);
}

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint3 id : SV_DispatchThreadID) {
  Frame frame = *push.frame;
  uint width = uint(frame.screen.x);
  if (id.x >= width || id.y >= uint(frame.screen.y)) return;
  float2 uv = (float2(id.xy) + 0.5) * frame.screen.zw;
  float depth = frame.depth.SampleLevel(frame.point_clamp, uv, 0).r;
  float2 result = float2(1, 1);
  float4 mirrored = float4(0);
  float4 indirect = float4(0);
  uint state = hash(id.x * 7919 + id.y * 104729 + frame.counts.z * 1299709);
  if (depth > 0 && frame.gbuffer_baked.SampleLevel(frame.point_clamp, uv, 0).w < SKY_MARK) {
    float4 normal_sample = frame.gbuffer_normal.SampleLevel(frame.point_clamp, uv, 0);
    float3 normal = normalize(normal_sample.xyz);
    float3 world = world_position(frame, uv, depth);
    float3 origin = world + normal * frame.ray_tracing.z;
    if ((frame.counts.y & EFFECT_RT_SHADOWS) != 0) result.x = sun_visibility(frame, origin);
    if ((frame.counts.y & EFFECT_RT_AMBIENT_OCCLUSION) != 0) result.y = ambient_visibility(frame, origin, normal, id.xy);
    if ((frame.counts.y & EFFECT_RT_REFLECTIONS) != 0) mirrored = reflection(frame, origin, normal, world, normal_sample.w, state);
    if ((frame.counts.y & EFFECT_RT_GLOBAL_ILLUMINATION) != 0) indirect = bounce(frame, origin, normal, state);
  }
  push.rt[id.y * width + id.x] = result;
  push.reflections[id.y * width + id.x] = mirrored;
  push.gi[id.y * width + id.x] = indirect;
}
