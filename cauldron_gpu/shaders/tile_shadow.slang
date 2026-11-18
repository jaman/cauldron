import common;

[[vk::push_constant]] ConstantBuffer<TilePush> push;

struct Varyings {
  float4 position : SV_Position;
  float2 texel;
}

static const float2 corners[6] = { float2(0, 0), float2(1, 0), float2(0, 1), float2(0, 1), float2(1, 0), float2(1, 1) };

[shader("vertex")]
Varyings vertex_main(uint vertex_id : SV_VertexID) {
  Layer layer = *push.layer;
  Tile tile = push.tiles[push.first + vertex_id / 6];
  float2 corner = corners[vertex_id % 6];
  bool transpose = (tile.shape.x & 4u) != 0;
  float2 drawn = transpose ? tile.source.wz : tile.source.zw;
  float2 scale = layer.port.zw / layer.view.zw;
  float2 pixel = layer.port.xy + (tile.placement.xy + corner * drawn - layer.view.xy) * scale;
  float2 along = transpose ? corner.yx : corner;
  float2 unit = float2((tile.shape.x & 1u) != 0 ? 1 - along.x : along.x, (tile.shape.x & 2u) != 0 ? 1 - along.y : along.y);
  Varyings out;
  out.position = target_position(layer, pixel);
  out.texel = tile.source.xy + unit * tile.source.zw;
  return out;
}

[shader("fragment")]
float4 fragment_main(Varyings input) : SV_Target {
  Layer layer = *push.layer;
  if (outside_port(layer, input.position.xy)) discard;
  float4 texel = layer.source.Load(int3(int2(floor(input.texel + 1.0 / 256.0)), 0));
  uint pen = uint(texel.r * 255.0 + 0.5);
  if (pen == layer.counts.y) discard;
  if (((layer.counts.z >> pen) & 1u) == 0) discard;
  float3 under = layer.behind.Load(int3(int2(input.position.xy), 0)).rgb;
  if (layer.counts.w != 0) under = srgb_encode(under);
  float3 result = under;
  for (uint index = 0; index < layer.counts.x; index++) {
    float3 colour = layer.palette.Load(int3(int(index), 0, 0)).rgb;
    if (all(abs(colour - under) < 0.6 / 255.0)) {
      result = layer.palette.Load(int3(int(index), 1, 0)).rgb;
      break;
    }
  }
  return float4(layer.counts.w != 0 ? srgb_decode(result) : result, 1);
}
