import common;

[[vk::push_constant]] ConstantBuffer<ColumnsPush> push;

struct Varyings {
  float4 position : SV_Position;
}

static const float2 corners[6] = { float2(0, 0), float2(1, 0), float2(0, 1), float2(0, 1), float2(1, 0), float2(1, 1) };

[shader("vertex")]
Varyings vertex_main(uint vertex_id : SV_VertexID) {
  Layer layer = *push.layer;
  Varyings out;
  out.position = target_position(layer, layer.port.xy + corners[vertex_id % 6] * layer.port.zw);
  return out;
}

[shader("fragment")]
float4 fragment_main(Varyings input) : SV_Target {
  Layer layer = *push.layer;
  if (outside_port(layer, input.position.xy)) discard;
  uint count = layer.counts.x;
  if (count == 0) return float4(0, 0, 0, 1);
  float2 local = input.position.xy - layer.port.xy;
  uint column = min(uint(local.x * float(count) / layer.port.z), count - 1);
  float4 entry = push.columns[column];
  float down = local.y / layer.port.w;
  float2 uv = float2(entry.x, 0.5 + (down - 0.5) * entry.y);
  if (any(uv < 0) || any(uv > 1)) return float4(0, 0, 0, 1);
  float4 picture = layer.source.SampleLevel(layer.sampler, uv, 0);
  return float4(picture.rgb * entry.z, picture.a);
}
