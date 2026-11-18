import common;

[[vk::push_constant]] ConstantBuffer<TilePush> push;

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

[shader("fragment")]
float4 fragment_main(Varyings input) : SV_Target {
  Layer layer = *push.layer;
  return layer.source.Load(int3(int2(input.position.xy), 0));
}
