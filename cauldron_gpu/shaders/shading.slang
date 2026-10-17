module shading;

import common;

public static const float PI = 3.14159265;

float distribution(float n_dot_h, float roughness) {
  float a = roughness * roughness;
  float a2 = a * a;
  float d = n_dot_h * n_dot_h * (a2 - 1) + 1;
  return a2 / max(PI * d * d, 1e-6);
}

float geometry(float n_dot_v, float n_dot_l, float roughness) {
  float k = (roughness + 1) * (roughness + 1) / 8;
  float gv = n_dot_v / (n_dot_v * (1 - k) + k);
  float gl = n_dot_l / (n_dot_l * (1 - k) + k);
  return gv * gl;
}

float3 fresnel(float cos_theta, float3 f0) {
  return f0 + (1 - f0) * pow(1 - cos_theta, 5);
}

public float3 brdf(float3 albedo, float metallic, float roughness, float3 normal, float3 view, float3 light) {
  float3 half_vector = normalize(view + light);
  float n_dot_l = saturate(dot(normal, light));
  float n_dot_v = max(dot(normal, view), 1e-4);
  float n_dot_h = saturate(dot(normal, half_vector));
  float3 f0 = lerp(float3(0.04), albedo, metallic);
  float3 f = fresnel(saturate(dot(half_vector, view)), f0);
  float3 specular = distribution(n_dot_h, roughness) * geometry(n_dot_v, n_dot_l, roughness) * f / max(4 * n_dot_v * n_dot_l, 1e-4);
  float3 diffuse = (1 - f) * (1 - metallic) * albedo / PI;
  return (diffuse + specular) * n_dot_l;
}

float sample_cascade(Frame frame, uint cascade, float2 uv) {
  switch (cascade) {
    case 0: return frame.shadow_map0.SampleLevel(frame.point_clamp, uv, 0).r;
    case 1: return frame.shadow_map1.SampleLevel(frame.point_clamp, uv, 0).r;
    case 2: return frame.shadow_map2.SampleLevel(frame.point_clamp, uv, 0).r;
    default: return frame.shadow_map3.SampleLevel(frame.point_clamp, uv, 0).r;
  }
}

float split(Frame frame, uint cascade) {
  return cascade == 0 ? frame.cascade_splits.x : cascade == 1 ? frame.cascade_splits.y : cascade == 2 ? frame.cascade_splits.z : frame.cascade_splits.w;
}

public float shadow_factor(Frame frame, float3 world, float3 normal) {
  float distance = length(world - frame.camera_position.xyz);
  uint cascade = 0;
  while (cascade < 4 && distance > split(frame, cascade)) cascade++;
  if (cascade >= 4) return 1;
  float offset = split(frame, cascade) / frame.settings.z * 2.0;
  float4 clip = mul(frame.shadow_cascades[cascade], float4(world + normal * offset, 1));
  float3 ndc = clip.xyz / clip.w;
  float2 uv = float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
  if (any(uv < 0) || any(uv > 1) || ndc.z <= 0) return 1;
  float2 texel = 1.0 / frame.settings.z;
  float lit = 0;
  for (int y = -1; y <= 1; y++)
    for (int x = -1; x <= 1; x++)
      lit += ndc.z >= sample_cascade(frame, cascade, uv + float2(x, y) * texel) - 0.0005 ? 1 : 0;
  return lit / 9;
}

float attenuation(Light light, float3 to_light) {
  float distance_squared = max(dot(to_light, to_light), 1e-4);
  float range = light.position_range.w;
  float falloff = saturate(1 - pow(distance_squared / (range * range), 2));
  return falloff * falloff / distance_squared;
}

public float3 light_contribution(Frame frame, Light light, float3 world, float3 normal, float3 view, float3 albedo, float metallic, float roughness, float traced_shadow) {
  uint kind = uint(light.direction_kind.w);
  float3 color = light.color.rgb * light.color.w;
  if (kind == LIGHT_DIRECTIONAL) {
    float3 direction = -light.direction_kind.xyz;
    bool traced = (frame.counts.y & EFFECT_RT_SHADOWS) != 0 && traced_shadow >= 0;
    float shadow = light.cone.z > 0 ? (traced ? traced_shadow : shadow_factor(frame, world, normal)) : 1;
    return brdf(albedo, metallic, roughness, normal, view, direction) * color * shadow;
  }
  float3 to_light = light.position_range.xyz - world;
  float3 direction = normalize(to_light);
  float strength = attenuation(light, to_light);
  if (kind == LIGHT_SPOT) {
    float cosine = dot(-direction, light.direction_kind.xyz);
    strength *= smoothstep(cos(light.cone.y), cos(light.cone.x), cosine);
  }
  return brdf(albedo, metallic, roughness, normal, view, direction) * color * strength;
}

public float3 display_lights(Frame frame, Light *lights, float3 world, float3 normal, float traced_shadow) {
  float3 sum = float3(0);
  for (uint index = 0; index < frame.counts.x; index++) {
    Light light = lights[index];
    uint kind = uint(light.direction_kind.w);
    float3 color = light.color.rgb * light.color.w;
    if (kind == LIGHT_DIRECTIONAL) {
      bool traced = (frame.counts.y & EFFECT_RT_SHADOWS) != 0 && traced_shadow >= 0;
      float shadow = light.cone.z > 0 ? (traced ? traced_shadow : shadow_factor(frame, world, normal)) : 1;
      sum += color * saturate(dot(normal, -light.direction_kind.xyz)) * shadow;
      continue;
    }
    float3 to_light = light.position_range.xyz - world;
    float range = light.position_range.w;
    float strength = saturate(dot(normal, normalize(to_light))) * max(1 - dot(to_light, to_light) / (range * range), 0);
    if (kind == LIGHT_SPOT) {
      float3 offset = -to_light;
      float along = dot(offset, light.direction_kind.xyz);
      float across = length(offset - light.direction_kind.xyz * along) / max(along * tan(light.cone.y), 1e-6);
      strength *= along > 0 ? max(1 - across * across, 0) : 0;
    }
    sum += color * strength;
  }
  return sum;
}

public float3 apply_fog(Frame frame, float3 color, float distance) {
  float amount = 1 - exp(-frame.fog.w * distance);
  return lerp(color, frame.fog.rgb, saturate(amount));
}

public float3 roughness_fresnel(float3 albedo, float metallic, float roughness, float3 normal, float3 view) {
  float n_dot_v = saturate(dot(normal, view));
  float3 f0 = lerp(float3(0.04), albedo, metallic);
  return f0 + (max(float3(1 - roughness), f0) - f0) * pow(1 - n_dot_v, 5);
}

public float3 sky_reflection(Frame frame, float3 normal, float3 view, float roughness, float occlusion) {
  return sky(frame, reflect(-view, normal)) * lerp(1.0, 0.25, roughness) * frame.settings.w * occlusion;
}

public float3 surface_color(Frame frame, Light *lights, float3 world, float3 normal, float3 view, float3 albedo, float metallic, float roughness,
                            float3 indirect, float3 reflected, float3 emissive, float traced_shadow) {
  float3 fresnel_term = roughness_fresnel(albedo, metallic, roughness, normal, view);
  float3 color = albedo * indirect * (1 - fresnel_term) * (1 - metallic) + reflected * fresnel_term + emissive;
  for (uint index = 0; index < frame.counts.x; index++)
    color += light_contribution(frame, lights[index], world, normal, view, albedo, metallic, roughness, traced_shadow);
  return color;
}
