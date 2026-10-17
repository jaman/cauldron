import common;

struct DenoisePush {
  Frame *frame;
  float2 *rt;
  float4 *reflections;
  float4 *gi;
  History *previous;
  History *current;
  uint reset;
  uint pad;
}

[[vk::push_constant]] ConstantBuffer<DenoisePush> push;

static const float INDIRECT_FRAMES = 16;
static const float REFLECTION_FRAMES = 8;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint3 id : SV_DispatchThreadID) {
  Frame frame = *push.frame;
  int2 size = int2(frame.screen.xy);
  if (int(id.x) >= size.x || int(id.y) >= size.y) return;
  uint index = id.y * uint(size.x) + id.x;
  float2 uv = (float2(id.xy) + 0.5) * frame.screen.zw;
  float depth = frame.depth.SampleLevel(frame.point_clamp, uv, 0).r;
  History next;
  if (depth <= 0) {
    next.reflection = float4(0);
    next.gi_ao = float4(0, 0, 0, 1);
    next.info = float4(0);
    push.current[index] = next;
    return;
  }
  float3 world = world_position(frame, uv, depth);
  float distance = length(world - frame.camera_position.xyz);
  float previous_distance = length(world - frame.previous_camera_position.xyz);
  float2 previous_uv = uv + frame.gbuffer_motion.SampleLevel(frame.point_clamp, uv, 0).xy;
  int2 previous_pixel = int2(previous_uv * frame.screen.xy);
  bool inside = all(previous_uv >= 0) && all(previous_uv < 1);
  History previous = push.previous[clamp(previous_pixel.y, 0, size.y - 1) * size.x + clamp(previous_pixel.x, 0, size.x - 1)];
  bool same_surface = abs(previous.info.x - previous_distance) < previous_distance * 0.03 + 0.02;
  bool valid = push.reset == 0 && inside && previous.info.y > 0 && same_surface;
  float count = valid ? previous.info.y + 1 : 1;
  float indirect_weight = 1 / min(count, INDIRECT_FRAMES);
  float reflection_weight = 1 / min(count, REFLECTION_FRAMES);
  float4 sample = float4(push.gi[index].rgb, push.rt[index].y);
  float4 reflection = push.reflections[index];
  next.gi_ao = valid ? lerp(previous.gi_ao, sample, indirect_weight) : sample;
  next.reflection = valid ? lerp(previous.reflection, reflection, reflection_weight) : reflection;
  next.info = float4(distance, count, 0, 0);
  push.current[index] = next;
}
