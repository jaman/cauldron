import common;

struct BloomPush {
  Frame *frame;
  DescriptorHandle<Texture2D> source;
  float2 source_texel;
  float threshold;
  uint first;
}

[[vk::push_constant]] ConstantBuffer<BloomPush> push;

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

float3 tap(float2 uv) {
  return push.source.SampleLevel(push.frame->linear_clamp, uv, 0).rgb;
}

float3 bright(float3 color) {
  float level = max(color.r, max(color.g, color.b));
  float knee = push.threshold * 0.5;
  float soft = clamp(level - push.threshold + knee, 0, 2 * knee);
  soft = soft * soft / (4 * knee + 1e-4);
  return color * max(soft, level - push.threshold) / max(level, 1e-4);
}

[shader("fragment")]
float4 downsample_main(Varyings input) : SV_Target {
  float2 t = push.source_texel;
  float2 uv = input.uv;
  float3 center = tap(uv);
  float3 inner = tap(uv + t * float2(-1, -1)) + tap(uv + t * float2(1, -1)) + tap(uv + t * float2(-1, 1)) + tap(uv + t * float2(1, 1));
  float3 outer_corners = tap(uv + t * float2(-2, -2)) + tap(uv + t * float2(2, -2)) + tap(uv + t * float2(-2, 2)) + tap(uv + t * float2(2, 2));
  float3 outer_edges = tap(uv + t * float2(-2, 0)) + tap(uv + t * float2(2, 0)) + tap(uv + t * float2(0, -2)) + tap(uv + t * float2(0, 2));
  float3 color = center * 0.125 + inner * 0.125 + outer_corners * 0.03125 + outer_edges * 0.0625;
  if (push.first != 0) color = bright(color);
  return float4(color, 1);
}

[shader("fragment")]
float4 upsample_main(Varyings input) : SV_Target {
  float2 t = push.source_texel;
  float2 uv = input.uv;
  float3 color = tap(uv) * 4;
  color += (tap(uv + t * float2(-1, 0)) + tap(uv + t * float2(1, 0)) + tap(uv + t * float2(0, -1)) + tap(uv + t * float2(0, 1))) * 2;
  color += tap(uv + t * float2(-1, -1)) + tap(uv + t * float2(1, -1)) + tap(uv + t * float2(-1, 1)) + tap(uv + t * float2(1, 1));
  return float4(color / 16, 1);
}
