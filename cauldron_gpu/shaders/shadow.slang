import common;

[[vk::push_constant]] ConstantBuffer<DrawPush> push;

[shader("vertex")]
float4 vertex_main(uint vertex_id : SV_VertexID) : SV_Position {
  Vertex vertex = push.vertices[vertex_id];
  Instance instance = push.instances[push.instance];
  float4 world = mul(instance.model, float4(vertex.position_u.xyz, 1));
  return mul(push.frame->shadow_cascades[push.cascade], world);
}
