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

[shader("fragment")]
float4 fragment_main(Varyings input) : SV_Target {
  Frame frame = *push.frame;
  float4 flat = frame.flat.SampleLevel(frame.point_clamp, input.uv, 0);
  return float4(srgb_decode(flat.rgb), 1);
}
