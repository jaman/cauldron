import common;
import shading;

[[vk::push_constant]] ConstantBuffer<DrawPush> push;

struct Varyings {
  float4 position : SV_Position;
  float2 uv;
}

struct Lit {
  float4 color : SV_Target0;
  float2 motion : SV_Target1;
}

[shader("vertex")]
Varyings vertex_main(uint vertex_id : SV_VertexID) {
  Varyings out;
  out.position = fullscreen_position(vertex_id, out.uv);
  return out;
}

float traced_shadow(Frame frame, float2 uv) {
  if ((frame.counts.y & EFFECT_RT_SHADOWS) == 0) return 1;
  int2 size = int2(frame.screen.xy);
  int2 pixel = clamp(int2(uv * frame.screen.xy), int2(0), size - 1);
  return push.rt[pixel.y * size.x + pixel.x].x;
}

float4 filtered_indirect(Frame frame, float2 uv, float depth, float3 normal) {
  if (frame.counts.y == 0) return float4(frame.ambient.rgb * frame.ambient.w, 1);
  int2 size = int2(frame.screen.xy);
  int2 pixel = clamp(int2(uv * frame.screen.xy), int2(0), size - 1);
  float4 sum = float4(0);
  float weight = 0;
  for (int y = -2; y <= 2; y++)
    for (int x = -2; x <= 2; x++) {
      int2 neighbour = clamp(pixel + int2(x, y), int2(0), size - 1);
      float2 neighbour_uv = (float2(neighbour) + 0.5) * frame.screen.zw;
      float neighbour_depth = frame.depth.SampleLevel(frame.point_clamp, neighbour_uv, 0).r;
      float3 neighbour_normal = frame.gbuffer_normal.SampleLevel(frame.point_clamp, neighbour_uv, 0).xyz;
      float closeness = exp(-abs(neighbour_depth - depth) / max(depth * 0.02, 1e-7)) * pow(saturate(dot(normal, normalize(neighbour_normal))), 8);
      sum += push.history[neighbour.y * size.x + neighbour.x].gi_ao * closeness;
      weight += closeness;
    }
  float4 filtered = sum / max(weight, 1e-4);
  if ((frame.counts.y & EFFECT_RT_GLOBAL_ILLUMINATION) == 0) filtered.rgb = frame.ambient.rgb * frame.ambient.w;
  return filtered;
}

float2 sky_motion(Frame frame, float2 uv, float3 far_point) {
  float3 direction = far_point - frame.camera_position.xyz;
  float4 previous = mul(frame.previous_view_proj, float4(frame.camera_position.xyz + direction, 1));
  return clip_to_uv(previous) - uv;
}

float3 traced_reflection(Frame frame, float2 uv, float3 fallback) {
  if ((frame.counts.y & EFFECT_RT_REFLECTIONS) == 0) return fallback;
  int2 pixel = clamp(int2(uv * frame.screen.xy), int2(0), int2(frame.screen.xy) - 1);
  float4 mirrored = push.history[pixel.y * int(frame.screen.x) + pixel.x].reflection;
  return lerp(fallback, mirrored.rgb * frame.settings.w, mirrored.a);
}

[shader("fragment")]
Lit fragment_main(Varyings input) {
  Frame frame = *push.frame;
  float depth = frame.depth.SampleLevel(frame.point_clamp, input.uv, 0).r;
  float3 far_point = world_position(frame, input.uv, 1e-7);
  float3 view_ray = normalize(far_point - frame.camera_position.xyz);
  Lit out;
  float4 baked_sample = frame.gbuffer_baked.SampleLevel(frame.point_clamp, input.uv, 0);
  if (depth <= 0 || baked_sample.w >= SKY_MARK) {
    out.color = float4(sky(frame, view_ray), 1);
    out.motion = sky_motion(frame, input.uv, far_point);
    return out;
  }
  out.motion = frame.gbuffer_motion.SampleLevel(frame.point_clamp, input.uv, 0).xy;
  float4 albedo_sample = frame.gbuffer_albedo.SampleLevel(frame.point_clamp, input.uv, 0);
  float4 normal_sample = frame.gbuffer_normal.SampleLevel(frame.point_clamp, input.uv, 0);
  float4 emissive_sample = frame.gbuffer_emissive.SampleLevel(frame.point_clamp, input.uv, 0);
  float3 world = world_position(frame, input.uv, depth);
  float3 normal = normalize(normal_sample.xyz);
  float3 view = normalize(frame.camera_position.xyz - world);
  float roughness = normal_sample.w;
  float4 indirect_light = filtered_indirect(frame, input.uv, depth, normal);
  float occlusion = indirect_light.w * albedo_sample.a;
  float3 indirect = (baked_sample.w > 0 ? baked_sample.rgb : indirect_light.rgb) * occlusion;
  if (frame.display.x > 0 && baked_sample.w > 0) {
    float3 light = baked_sample.rgb + display_lights(frame, push.lights, world, normal, traced_shadow(frame, input.uv));
    float3 shown = display_lit(albedo_sample.rgb, light, emissive_sample.rgb);
    out.color = float4(apply_fog(frame, shown, length(world - frame.camera_position.xyz)), 1);
    return out;
  }
  float3 reflected = traced_reflection(frame, input.uv, sky_reflection(frame, normal, view, roughness, occlusion));
  float3 color = surface_color(frame, push.lights, world, normal, view, albedo_sample.rgb, emissive_sample.w, roughness, indirect, reflected,
                               emissive_sample.rgb, traced_shadow(frame, input.uv));
  out.color = float4(apply_fog(frame, color, length(world - frame.camera_position.xyz)), 1);
  return out;
}
