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
Varyings vertex_main(uint vertex_id : SV_VertexID, uint item : SV_InstanceID) {
  Vertex vertex = push.vertices[vertex_id];
  Instance instance = push.instances[push.instance];
  float2 uv = float2(vertex.position_u.w, vertex.normal_v.w);
  float3 normal = vertex.normal_v.xyz;
  float3 local = swollen(push.frame, instance, vertex.position_u.xyz, vertex.normal_v.xyz, uv);
  float4 world = placed(push.frame, instance, push.scatter, item, local, normal);
  Varyings out;
  out.position = squeezed_in_front(instance, mul(push.frame->view_proj, world));
  out.world = world.xyz;
  out.normal = mul(instance.normal, float4(normal, 0)).xyz;
  out.uv = uv;
  out.lightmap_uv = vertex.lightmap_uv;
  out.colour = vertex_colour(push.colors, vertex_id);
  return out;
}

float4 smeared(Frame *frame, Material material, float4 position, float smear) {
  float2 screen_uv = position.xy * frame->screen.zw;
  uint2 block = uint2(position.xy / (smear * frame->screen.y));
  uint choice = (block.x * 73856093u) ^ (block.y * 19349663u) ^ (frame->counts.z * 83492791u);
  float shift = ((choice * 2654435761u) >> 16 & 1) == 0 ? -smear : smear;
  return float4(frame->behind.SampleLevel(frame->point_clamp, screen_uv + float2(0, shift), 0).rgb * material.base_color.rgb, 1);
}

float4 lit(Frame *frame, Material material, Varyings input, bool front, float4 base, float3 emissive) {
  float4 metallic_roughness = material.metallic_roughness_texture.Sample(material.sampler, input.uv);
  float metallic = material.params.x * metallic_roughness.b;
  float roughness = max(material.params.y * metallic_roughness.g, 0.04);
  float3 normal = mapped_normal(material, normalize(input.normal) * (front ? 1.0 : -1.0), input.world, input.uv);
  float3 view = normalize(frame->camera_position.xyz - input.world);
  float distance = length(input.world - frame->camera_position.xyz);
  float4 baked = surface_light(frame, material, push.instances[push.instance], input.lightmap_uv, normal, input.world);
  if (frame->display.x > 0 && baked.w > 0) {
    float3 light = baked.rgb + display_lights(frame, push.lights, input.world, normal, -1);
    return float4(apply_fog(frame, display_lit(base.rgb, light, emissive), distance), base.a);
  }
  float3 indirect = baked.w > 0 ? baked.rgb : frame->ambient.rgb * frame->ambient.w;
  if (frame->toon.x > 0)
    return float4(apply_fog(frame, toon_color(frame, push.lights, input.world, normal, view, base.rgb, indirect, emissive, -1), distance), base.a);
  float3 color = surface_color(frame, push.lights, input.world, normal, view, base.rgb, metallic, roughness, indirect,
                               sky_reflection(frame, normal, view, roughness, 1), emissive, -1);
  return float4(apply_fog(frame, color, distance), base.a);
}

float2 ripple_slope(float2 point, float seconds, float pace) {
  float2 slope = float2(0);
  for (int wave = 0; wave < 4; wave++) {
    float2 heading = wave == 0 ? float2(0.96, 0.29) : wave == 1 ? float2(-0.37, 0.93) : wave == 2 ? float2(0.71, -0.71) : float2(-0.98, -0.21);
    float span = wave == 0 ? 1.0 : wave == 1 ? 0.61 : wave == 2 ? 0.37 : 0.23;
    float turns = 6.2831853 / span;
    slope += heading * cos(dot(point, heading) * turns + seconds * pace * sqrt(turns)) * span;
  }
  return slope;
}

float4 liquid(Frame *frame, Material material, Varyings input, bool front) {
  float seconds = frame->sky_picture.w;
  float2 screen_uv = input.position.xy * frame->screen.zw;
  float3 to_eye = frame->camera_position.xyz - input.world;
  float distance = length(to_eye);
  float3 view = to_eye / max(distance, 1e-4);
  float2 slope = ripple_slope(input.world.xz / max(material.liquid_waves.x, 1e-3), seconds, material.liquid_waves.y) * material.liquid_waves.z;
  float3 normal = normalize(float3(-slope.x, 1, -slope.y)) * (front ? 1.0 : -1.0);
  float behind_depth = frame->nearest.SampleLevel(frame->point_clamp, screen_uv, 0).r;
  float3 bed = world_position(frame, screen_uv, max(behind_depth, 1e-7));
  float drop = behind_depth <= 0 ? 1e4 : abs(input.world.y - bed.y);
  float through = behind_depth <= 0 ? 1e4 : length(bed - input.world);
  float2 bent_uv = saturate(screen_uv + normal.xz * material.liquid_waves.w * saturate(through) / max(distance, 1.0));
  float bent_depth = frame->nearest.SampleLevel(frame->point_clamp, bent_uv, 0).r;
  if (bent_depth > input.position.z) bent_uv = screen_uv;
  float3 behind = frame->behind.SampleLevel(frame->linear_clamp, bent_uv, 0).rgb;
  float clarity = max(material.liquid_shallow.w, 1e-3);
  float murk = 1 - exp(-drop / clarity);
  float3 seen = behind * lerp(float3(1), material.liquid_shallow.rgb, saturate(drop / (clarity * 0.25)));
  float3 color = lerp(seen, material.liquid_deep.rgb, murk);
  float glance = 0.02 + 0.98 * pow(1 - saturate(dot(normal, view)), 5);
  color = lerp(color, sky(frame, reflect(-view, normal)) * frame->settings.w, glance * material.liquid_deep.w);
  for (uint index = 0; index < frame->counts.x; index++) {
    Light light = push.lights[index];
    if (uint(light.direction_kind.w) != LIGHT_DIRECTIONAL) continue;
    float glint = pow(saturate(dot(reflect(-view, normal), -light.direction_kind.xyz)), 180);
    color += light.color.rgb * light.color.w * smoothstep(0.35, 0.5, glint) * material.liquid_deep.w * 0.25;
  }
  float shore = saturate(1 - drop / max(material.liquid_foam.w, 1e-3));
  float lap = sin(dot(input.world.xz, float2(2.3, 1.7)) + seconds * 1.3) * 0.5 + 0.5;
  float foam = smoothstep(0.72, 0.82, shore + lap * 0.12) + smoothstep(0.9, 0.97, frac(shore * 3 - seconds * 0.35)) * shore * step(0.05, shore) * 0.7;
  color = lerp(color, material.liquid_foam.rgb, saturate(foam));
  return float4(apply_fog(frame, color, distance), saturate(drop / 0.04));
}

float4 surface(Varyings input, bool front) {
  Frame *frame = push.frame;
  Material material = push.materials[push.material];
  if ((material.flags.x & MATERIAL_SKY) != 0) return float4(sky(frame, normalize(input.world - frame->camera_position.xyz)), 1);
  Instance instance = push.instances[push.instance];
  if (instance.standing.z > 0 && hidden_while_standing(frame, instance, input.position)) discard;
  if ((material.flags.x & MATERIAL_LIQUID) != 0) return liquid(frame, material, input, front);
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
