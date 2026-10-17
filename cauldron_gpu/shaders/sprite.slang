import common;

[[vk::push_constant]] ConstantBuffer<SpritePush> push;

struct Varyings {
  float4 position : SV_Position;
  nointerpolation uint sprite;
}

static const float2 corners[6] = { float2(0, 0), float2(1, 0), float2(0, 1), float2(0, 1), float2(1, 0), float2(1, 1) };

float2 pixels_per_unit(Layer layer) {
  return layer.port.zw / layer.view.zw;
}

[shader("vertex")]
Varyings vertex_main(uint vertex_id : SV_VertexID) {
  Layer layer = *push.layer;
  uint index = push.first + vertex_id / 6;
  Sprite sprite = push.sprites[index];
  float2 scale = sprite.shape.xy * pixels_per_unit(layer);
  Varyings out;
  out.sprite = index;
  if (any(scale == 0)) {
    out.position = float4(0, 0, 0, 0);
    return out;
  }
  float2 margin = 1 / abs(scale);
  float2 texels = corners[vertex_id % 6] * (sprite.source.zw + 2 * margin) - margin;
  float2 offset = (texels - sprite.placement.zw) * scale;
  float2 turned = float2(offset.x * sprite.shape.z + offset.y * sprite.shape.w, -offset.x * sprite.shape.w + offset.y * sprite.shape.z);
  float2 anchor = layer.port.xy + (sprite.placement.xy - layer.view.xy) * pixels_per_unit(layer);
  out.position = target_position(layer, anchor + turned);
  return out;
}

[shader("fragment")]
float4 fragment_main(Varyings input) : SV_Target {
  Layer layer = *push.layer;
  float2 pixel = input.position.xy;
  if (outside_port(layer, pixel)) discard;
  Sprite sprite = push.sprites[input.sprite];
  float2 scale = sprite.shape.xy * pixels_per_unit(layer);
  float2 anchor = layer.port.xy + (sprite.placement.xy - layer.view.xy) * pixels_per_unit(layer);
  float2 reach = pixel - anchor;
  float cos_turn = sprite.shape.z, sin_turn = sprite.shape.w;
  float2 local = float2(reach.x * cos_turn - reach.y * sin_turn, reach.x * sin_turn + reach.y * cos_turn) / scale + sprite.placement.zw;
  if (any(local < 0) || any(local >= sprite.source.zw)) discard;
  float2 at = sprite.source.xy + (sprite.texel.w > 0 ? floor(local) + 0.5 : local);
  float4 texel = sprite.texture.SampleLevel(sprite.sampler, at * sprite.texel.xy, 0);
  float3 colour = texel.rgb * sprite.colour.rgb;
  float alpha = texel.a * sprite.colour.a;
  uint mode = uint(sprite.texel.z);
  if (mode == 1) return float4(colour * alpha, alpha);
  if (mode == 2) return float4(1 - colour * alpha, 1);
  return float4(colour, alpha);
}
