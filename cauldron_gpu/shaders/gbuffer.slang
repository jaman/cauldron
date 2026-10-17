import common;

[[vk::push_constant]] ConstantBuffer<DrawPush> push;

struct Varyings {
  float4 position : SV_Position;
  float3 normal;
  float3 world;
  float2 uv;
  float4 lightmap_uv;
  float4 current_clip;
  float4 previous_clip;
  float4 colour;
}

struct Targets {
  float4 albedo : SV_Target0;
  float4 normal : SV_Target1;
  float4 emissive : SV_Target2;
  float4 baked : SV_Target3;
  float2 motion : SV_Target4;
  float nearest : SV_Target5;
}

[shader("vertex")]
Varyings vertex_main(uint vertex_id : SV_VertexID) {
  Vertex vertex = push.vertices[vertex_id];
  Instance instance = push.instances[push.instance];
  float2 uv = float2(vertex.position_u.w, vertex.normal_v.w);
  float4 world = mul(instance.model, float4(swollen(*push.frame, instance, vertex.position_u.xyz, vertex.normal_v.xyz, uv), 1));
  Varyings out;
  out.position = squeezed_in_front(instance, mul(push.frame->view_proj, world));
  out.normal = mul(instance.normal, float4(vertex.normal_v.xyz, 0)).xyz;
  out.world = world.xyz;
  out.uv = uv;
  out.colour = vertex_colour(push.colors, vertex_id);
  out.lightmap_uv = vertex.lightmap_uv;
  out.current_clip = mul(push.frame->unjittered_view_proj, world);
  float3 previous_position = push.previous_vertices != nullptr ? push.previous_vertices[vertex_id].position_u.xyz : vertex.position_u.xyz;
  out.previous_clip = mul(push.frame->previous_view_proj, mul(instance.previous_model, float4(previous_position, 1)));
  return out;
}

[shader("fragment")]
Targets fragment_main(Varyings input, bool front : SV_IsFrontFace) {
  Material material = push.materials[push.material];
  Targets out;
  out.motion = clip_to_uv(input.previous_clip) - clip_to_uv(input.current_clip);
  out.nearest = input.position.z;
  if ((material.flags.x & MATERIAL_SKY) != 0) {
    out.albedo = float4(0);
    out.normal = float4(normalize(input.normal), 1);
    out.emissive = float4(0);
    out.baked = float4(0, 0, 0, SKY_MARK);
    return out;
  }
  input.uv = surface_uv(*push.frame, material, input.uv, input.world, normalize(input.normal));
  float4 base = material.base_color * material.base_texture.Sample(material.sampler, input.uv) * input.colour;
  if (base.a < material.params.z) discard;
  float4 metallic_roughness = material.metallic_roughness_texture.Sample(material.sampler, input.uv);
  float metallic = material.params.x * metallic_roughness.b;
  float roughness = material.params.y * metallic_roughness.g;
  float3 emissive = material.emissive.rgb * material.emissive_texture.Sample(material.sampler, input.uv).rgb;
  float3 normal = mapped_normal(material, normalize(input.normal) * (front ? 1.0 : -1.0), input.world, input.uv);
  float occlusion = material.occlusion_texture.Sample(material.sampler, input.uv).r;
  bool unlit = (material.flags.x & MATERIAL_UNLIT) != 0;
  float4 baked = surface_light(*push.frame, material, push.instances[push.instance], input.lightmap_uv, normal, input.world);
  out.albedo = float4(unlit ? float3(0) : base.rgb, occlusion);
  out.normal = float4(normal, max(roughness, 0.04));
  out.emissive = float4(unlit ? base.rgb + emissive : emissive, metallic);
  out.baked = baked;
  return out;
}
