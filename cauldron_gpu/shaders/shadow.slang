import common;

[[vk::push_constant]] ConstantBuffer<DrawPush> push;

[shader("vertex")]
float4 vertex_main(uint vertex_id : SV_VertexID, uint item : SV_InstanceID) : SV_Position {
  Vertex vertex = push.vertices[vertex_id];
  Instance instance = push.instances[push.instance];
  float3 normal = vertex.normal_v.xyz;
  float4 world = placed(push.frame, instance, push.scatter, item, vertex.position_u.xyz, normal);
  return mul(push.frame->shadow_cascades[push.cascade], world);
}
