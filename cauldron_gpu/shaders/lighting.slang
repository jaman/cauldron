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

float traced_shadow(Frame *frame, float2 uv) {
  if ((frame->counts.y & EFFECT_RT_SHADOWS) == 0) return 1;
  int2 size = int2(frame->screen.xy);
  int2 pixel = clamp(int2(uv * frame->screen.xy), int2(0), size - 1);
  return push.rt[pixel.y * size.x + pixel.x].x;
}

float4 filtered_indirect(Frame *frame, float2 uv, float depth, float3 normal) {
  if (frame->counts.y == 0) return float4(frame->ambient.rgb * frame->ambient.w, 1);
  int2 size = int2(frame->screen.xy);
  int2 pixel = clamp(int2(uv * frame->screen.xy), int2(0), size - 1);
  float4 sum = float4(0);
  float weight = 0;
  for (int y = -2; y <= 2; y++)
    for (int x = -2; x <= 2; x++) {
      int2 neighbour = clamp(pixel + int2(x, y), int2(0), size - 1);
      float2 neighbour_uv = (float2(neighbour) + 0.5) * frame->screen.zw;
      float neighbour_depth = frame->depth.SampleLevel(frame->point_clamp, neighbour_uv, 0).r;
      float3 neighbour_normal = frame->gbuffer_normal.SampleLevel(frame->point_clamp, neighbour_uv, 0).xyz;
      float closeness = exp(-abs(neighbour_depth - depth) / max(depth * 0.02, 1e-7)) * pow(saturate(dot(normal, normalize(neighbour_normal))), 8);
      sum += push.history[neighbour.y * size.x + neighbour.x].gi_ao * closeness;
      weight += closeness;
    }
  float4 filtered = sum / max(weight, 1e-4);
  if ((frame->counts.y & EFFECT_RT_GLOBAL_ILLUMINATION) == 0) filtered.rgb = frame->ambient.rgb * frame->ambient.w;
  return filtered;
}

float2 sky_motion(Frame *frame, float2 uv, float3 far_point) {
  float3 direction = far_point - frame->camera_position.xyz;
  float4 previous = mul(frame->previous_view_proj, float4(frame->camera_position.xyz + direction, 1));
  return clip_to_uv(previous) - uv;
}

float3 traced_reflection(Frame *frame, float2 uv, float3 fallback) {
  if ((frame->counts.y & EFFECT_RT_REFLECTIONS) == 0) return fallback;
  int2 pixel = clamp(int2(uv * frame->screen.xy), int2(0), int2(frame->screen.xy) - 1);
  float4 mirrored = push.history[pixel.y * int(frame->screen.x) + pixel.x].reflection;
  return lerp(fallback, mirrored.rgb * frame->settings.w, mirrored.a);
}

float away(Frame *frame, float2 uv, float depth) {
  return depth <= 0 ? 1e9 : length(world_position(frame, uv, depth) - frame->camera_position.xyz);
}

float outlined(Frame *frame, float2 uv, float depth, float4 normal_sample) {
  float width = frame->outline.w;
  if (width <= 0) return 0;
  float here = away(frame, uv, depth);
  bool plain = depth > 0 && normal_sample.w < 0;
  float3 normal = depth > 0 ? normalize(normal_sample.xyz) : float3(0);
  float edge = 0;
  float nearest = here;
  for (int side = 0; side < 4; side++) {
    float2 step = side == 0 ? float2(1, 0) : side == 1 ? float2(-1, 0) : side == 2 ? float2(0, 1) : float2(0, -1);
    float2 at = uv + step * width * frame->screen.zw;
    float other_depth = frame->depth.SampleLevel(frame->point_clamp, at, 0).r;
    float4 other = frame->gbuffer_normal.SampleLevel(frame->point_clamp, at, 0);
    bool other_plain = other_depth > 0 && other.w < 0;
    float there = away(frame, at, other_depth);
    nearest = min(nearest, there);
    if (!other_plain && there < here - max(here * 0.03, 0.05)) edge = 1;
    if (!plain && !other_plain && depth > 0 && other_depth > 0 && abs(there - here) < here * 0.03 && dot(normal, normalize(other.xyz)) < 0.35) edge = max(edge, 0.8);
  }
  return edge * saturate(1 - nearest / frame->shade.w);
}

[shader("fragment")]
Lit fragment_main(Varyings input) {
  Frame *frame = push.frame;
  float depth = frame->depth.SampleLevel(frame->point_clamp, input.uv, 0).r;
  float3 far_point = world_position(frame, input.uv, 1e-7);
  float3 view_ray = normalize(far_point - frame->camera_position.xyz);
  Lit out;
  float4 baked_sample = frame->gbuffer_baked.SampleLevel(frame->point_clamp, input.uv, 0);
  float4 normal_sample = frame->gbuffer_normal.SampleLevel(frame->point_clamp, input.uv, 0);
  float edge = outlined(frame, input.uv, depth, normal_sample);
  if (depth <= 0 || baked_sample.w >= SKY_MARK) {
    out.color = float4(lerp(sky(frame, view_ray), frame->outline.rgb, edge), 1);
    out.motion = sky_motion(frame, input.uv, far_point);
    return out;
  }
  out.motion = frame->gbuffer_motion.SampleLevel(frame->point_clamp, input.uv, 0).xy;
  float4 albedo_sample = frame->gbuffer_albedo.SampleLevel(frame->point_clamp, input.uv, 0);
  float4 emissive_sample = frame->gbuffer_emissive.SampleLevel(frame->point_clamp, input.uv, 0);
  float3 world = world_position(frame, input.uv, depth);
  float3 normal = normalize(normal_sample.xyz);
  float3 view = normalize(frame->camera_position.xyz - world);
  float roughness = abs(normal_sample.w);
  float4 indirect_light = filtered_indirect(frame, input.uv, depth, normal);
  float occlusion = indirect_light.w * albedo_sample.a;
  float3 indirect = (baked_sample.w > 0 ? baked_sample.rgb : indirect_light.rgb) * occlusion;
  if (frame->display.x > 0 && baked_sample.w > 0) {
    float3 light = baked_sample.rgb + display_lights(frame, push.lights, world, normal, traced_shadow(frame, input.uv));
    float3 shown = display_lit(albedo_sample.rgb, light, emissive_sample.rgb);
    out.color = float4(apply_fog(frame, shown, length(world - frame->camera_position.xyz)), 1);
    return out;
  }
  float3 color;
  if (frame->toon.x > 0) {
    color = toon_color(frame, push.lights, world, normal, view, albedo_sample.rgb, indirect, emissive_sample.rgb, traced_shadow(frame, input.uv));
  } else {
    float3 reflected = traced_reflection(frame, input.uv, sky_reflection(frame, normal, view, roughness, occlusion));
    color = surface_color(frame, push.lights, world, normal, view, albedo_sample.rgb, emissive_sample.w, roughness, indirect, reflected,
                          emissive_sample.rgb, traced_shadow(frame, input.uv));
  }
  color = lerp(color, frame->outline.rgb, edge);
  out.color = float4(apply_fog(frame, color, length(world - frame->camera_position.xyz)), 1);
  return out;
}
