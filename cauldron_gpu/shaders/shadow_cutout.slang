import common;

[[vk::push_constant]] ConstantBuffer<DrawPush> push;

struct Varyings {
  float4 position : SV_Position;
  float2 uv;
  float alpha;
}

[shader("vertex")]
Varyings vertex_main(uint vertex_id : SV_VertexID, uint item : SV_InstanceID) {
  Vertex vertex = push.vertices[vertex_id];
  Instance instance = push.instances[push.instance];
  float3 normal = vertex.normal_v.xyz;
  float4 world = placed(push.frame, instance, push.scatter, item, vertex.position_u.xyz, normal);
  Varyings out;
  out.position = mul(push.frame->shadow_cascades[push.cascade], world);
  out.uv = float2(vertex.position_u.w, vertex.normal_v.w);
  out.alpha = vertex_colour(push.colors, vertex_id).a;
  return out;
}

[shader("fragment")]
void fragment_main(Varyings input) {
  Material material = push.materials[push.material];
  float alpha = material.base_color.a * material.base_texture.Sample(material.sampler, input.uv).a * input.alpha;
  if (alpha < material.params.z) discard;
}
