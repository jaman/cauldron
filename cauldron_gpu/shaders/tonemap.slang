import common;

[[vk::push_constant]] ConstantBuffer<DrawPush> push;

struct Varyings {
  float4 position : SV_Position;
  float2 uv;
}

[shader("vertex")]
Varyings vertex_main(uint vertex_id : SV_VertexID) {
  Varyings out;
  out.position = fullscreen_position(vertex_id, out.uv);
  return out;
}

float3 aces(float3 color) {
  float3 numerator = color * (2.51 * color + 0.03);
  float3 denominator = color * (2.43 * color + 0.59) + 0.14;
  return saturate(numerator / denominator);
}

float2 blocked(Frame frame, float2 uv) {
  if (frame.resolution.x <= 0 || frame.resolution.y <= 0) return uv;
  float2 local = (uv - frame.viewport.xy) / frame.viewport.zw;
  local = (floor(local * frame.resolution.xy) + 0.5) / frame.resolution.xy;
  return frame.viewport.xy + local * frame.viewport.zw;
}

[shader("fragment")]
float4 fragment_main(Varyings input) : SV_Target {
  Frame frame = *push.frame;
  float2 at = blocked(frame, input.uv);
  float3 hdr = frame.hdr.SampleLevel(frame.point_clamp, at, 0).rgb;
  if (frame.bloom.x > 0) hdr += frame.bloom_texture.SampleLevel(frame.linear_clamp, at, 0).rgb * frame.bloom.x;
  float3 exposed = hdr * frame.settings.x;
  uint mode = uint(frame.bloom.z);
  float3 mapped = mode == 1 ? exposed / (1 + max(exposed.r, max(exposed.g, exposed.b))) * 1.5 : mode == 2 ? saturate(exposed) : aces(exposed);
  float4 view = frame.viewport;
  bool outside = any(input.uv < view.xy) || any(input.uv > view.xy + view.zw);
  float3 shown = outside ? float3(0) : saturate(pow(srgb_encode(saturate(mapped)), frame.curve.x) * frame.curve.y + frame.curve.z);
  shown = lerp(shown, frame.screen_tint.rgb, frame.screen_tint.a);
  if (frame.bloom.w > 0) {
    float4 overlay = frame.overlay.SampleLevel(frame.point_clamp, input.uv, 0);
    shown = frame.curve.w > 0 ? shown * (1 - overlay.a) + srgb_encode(overlay.rgb) : lerp(shown, srgb_encode(overlay.rgb), overlay.a);
  }
  if (frame.layers.x > 0) {
    float4 flat = frame.flat.SampleLevel(frame.point_clamp, input.uv, 0);
    shown = shown * (1 - flat.a) + flat.rgb;
  }
  return float4(srgb_decode(shown), 1);
}
