import common;
import shading;

[[vk::push_constant]] ConstantBuffer<DrawPush> push;

struct Varyings {
  float4 position : SV_Position;
  float3 world;
  float3 normal;
  float2 uv;
  float4 lightmap_uv;
  float4 colour;
}

[shader("vertex")]
Varyings vertex_main(uint vertex_id : SV_VertexID) {
  Vertex vertex = push.vertices[vertex_id];
  Instance instance = push.instances[push.instance];
  float2 uv = float2(vertex.position_u.w, vertex.normal_v.w);
  float4 world = mul(instance.model, float4(swollen(*push.frame, instance, vertex.position_u.xyz, vertex.normal_v.xyz, uv), 1));
  Varyings out;
  out.position = squeezed_in_front(instance, mul(push.frame->view_proj, world));
  out.world = world.xyz;
  out.normal = mul(instance.normal, float4(vertex.normal_v.xyz, 0)).xyz;
  out.uv = uv;
  out.lightmap_uv = vertex.lightmap_uv;
  out.colour = vertex_colour(push.colors, vertex_id);
  return out;
}

float4 smeared(Frame frame, Material material, float4 position, float smear) {
  float2 screen_uv = position.xy * frame.screen.zw;
  uint2 block = uint2(position.xy / (smear * frame.screen.y));
  uint choice = (block.x * 73856093u) ^ (block.y * 19349663u) ^ (frame.counts.z * 83492791u);
  float shift = ((choice * 2654435761u) >> 16 & 1) == 0 ? -smear : smear;
  return float4(frame.behind.SampleLevel(frame.point_clamp, screen_uv + float2(0, shift), 0).rgb * material.base_color.rgb, 1);
}

float4 lit(Frame frame, Material material, Varyings input, bool front, float4 base, float3 emissive) {
  float4 metallic_roughness = material.metallic_roughness_texture.Sample(material.sampler, input.uv);
  float metallic = material.params.x * metallic_roughness.b;
  float roughness = max(material.params.y * metallic_roughness.g, 0.04);
  float3 normal = mapped_normal(material, normalize(input.normal) * (front ? 1.0 : -1.0), input.world, input.uv);
  float3 view = normalize(frame.camera_position.xyz - input.world);
  float distance = length(input.world - frame.camera_position.xyz);
  float4 baked = surface_light(frame, material, push.instances[push.instance], input.lightmap_uv, normal, input.world);
  if (frame.display.x > 0 && baked.w > 0) {
    float3 light = baked.rgb + display_lights(frame, push.lights, input.world, normal, -1);
    return float4(apply_fog(frame, display_lit(base.rgb, light, emissive), distance), base.a);
  }
  float3 indirect = baked.w > 0 ? baked.rgb : frame.ambient.rgb * frame.ambient.w;
  float3 color = surface_color(frame, push.lights, input.world, normal, view, base.rgb, metallic, roughness, indirect,
                               sky_reflection(frame, normal, view, roughness, 1), emissive, -1);
  return float4(apply_fog(frame, color, distance), base.a);
}

float4 surface(Varyings input, bool front) {
  Frame frame = *push.frame;
  Material material = push.materials[push.material];
  if ((material.flags.x & MATERIAL_SKY) != 0) return float4(sky(frame, normalize(input.world - frame.camera_position.xyz)), 1);
  Instance instance = push.instances[push.instance];
  if (instance.standing.z > 0 && hidden_while_standing(frame, instance, input.position)) discard;
  input.uv = surface_uv(frame, material, input.uv, input.world, normalize(input.normal));
  float4 base = material.base_color * material.base_texture.Sample(material.sampler, input.uv) * input.colour;
  float smear = asfloat(material.flags.z);
  if (smear > 0) {
    if (base.a < material.params.z) discard;
    return smeared(frame, material, input.position, smear);
  }
  float3 emissive = material.emissive.rgb * material.emissive_texture.Sample(material.sampler, input.uv).rgb;
  if ((material.flags.x & MATERIAL_UNLIT) != 0) return float4(base.rgb + emissive, base.a);
  return lit(frame, material, input, front, base, emissive);
}

[shader("fragment")]
float4 fragment_main(Varyings input, bool front : SV_IsFrontFace) {
  Material material = push.materials[push.material];
  float4 result = surface(input, front);
  if ((material.flags.x & MATERIAL_ADD) != 0) return float4(result.rgb * result.a, 0);
  if ((material.flags.x & MATERIAL_MULTIPLY) != 0) return float4(lerp(float3(1), result.rgb, result.a), 1);
  return result;
}
