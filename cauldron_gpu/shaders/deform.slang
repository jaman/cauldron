import common;

struct DeformPush {
  Vertex *source;
  Vertex *blend_source;
  uint2 *skin;
  float4 *bones;
  Vertex *target;
  uint count;
  float blend;
  uint bone_count;
  uint pad;
}

[[vk::push_constant]] ConstantBuffer<DeformPush> push;

float3x4 bone(uint index) {
  return float3x4(push.bones[index * 3], push.bones[index * 3 + 1], push.bones[index * 3 + 2]);
}

[shader("compute")]
[numthreads(64, 1, 1)]
void compute_main(uint3 id : SV_DispatchThreadID) {
  uint index = id.x;
  if (index >= push.count) return;
  Vertex vertex = push.source[index];
  float3 position = vertex.position_u.xyz;
  float3 normal = vertex.normal_v.xyz;
  if (push.blend_source != nullptr && push.blend > 0) {
    Vertex other = push.blend_source[index];
    position = lerp(position, other.position_u.xyz, push.blend);
    normal = lerp(normal, other.normal_v.xyz, push.blend);
  }
  if (push.bone_count > 0 && push.skin != nullptr) {
    uint2 skin = push.skin[index];
    float3 skinned_position = float3(0);
    float3 skinned_normal = float3(0);
    for (uint slot = 0; slot < 4; slot++) {
      float weight = float((skin.y >> (slot * 8)) & 0xff) / 255.0;
      if (weight <= 0) continue;
      uint bone_index = min((skin.x >> (slot * 8)) & 0xff, push.bone_count - 1);
      float3x4 matrix = bone(bone_index);
      skinned_position += mul(matrix, float4(position, 1)) * weight;
      skinned_normal += mul(matrix, float4(normal, 0)) * weight;
    }
    position = skinned_position;
    normal = skinned_normal;
  }
  vertex.position_u.xyz = position;
  vertex.normal_v.xyz = normalize(normal);
  push.target[index] = vertex;
}
