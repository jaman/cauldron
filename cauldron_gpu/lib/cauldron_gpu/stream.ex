defmodule CauldronGPU.Stream do
  @moduledoc """
  The binary change stream the renderer reads: a sequence of operations, each a one-byte
  code and its fields, little-endian. `encode/1` turns changes into it.

  A change is one of:

    * `:tick` — the changes that follow belong to a new game tick; poses are
      interpolated from the previous tick's
    * `{:mesh, id, %CauldronGPU.Mesh{}}`, `{:drop_mesh, id}`
    * `{:texture, id, %CauldronGPU.Texture{}}`, `{:drop_texture, id}`
    * `{:canvas, id, %CauldronGPU.Canvas{}}` — a texture the renderer draws into, dropped
      as a texture is
    * `{:material, id, %CauldronGPU.Material{}}`, `{:drop_material, id}`
    * `{:instance, id, %CauldronGPU.Instance{}}`
    * `{:move, id, %CauldronGPU.Transform{}}` or `{:move, id, transform, snap: true}`
    * `{:pose, id, %CauldronGPU.Pose{}}` — bends instance `id`'s mesh until the next pose
    * `{:remove_instance, id}`
    * `{:light, id, %CauldronGPU.Light{}}`, `{:remove_light, id}`
    * `%CauldronGPU.Camera{}`
    * `%CauldronGPU.Environment{}`
    * `{:light_styles, [scale | {r, g, b}]}` — the brightness of light styles 0, 1, …, a
      number for all three colours or one each (1.0 normal, up to 64 styles; styles not
      listed stay as they were, 1.0 at first)
    * `{:overlay, texture_handle | nil}` — a picture drawn over the finished frame, stretched
      to it, see-through by its alpha (a HUD, menus); `nil` removes it.
      `{:overlay, texture_handle, :premultiplied}` takes its colours as already multiplied by
      its alpha, so a pixel with colour and no alpha adds its colour (an additive HUD)
    * `{:screen_tint, {r, g, b, a}}` — the finished frame's display colours blended towards
      the display colour `{r, g, b}` by `a`; the overlay is blended over display colours too
    * `{:layers, [layer]}` — the 2D layers drawn each frame, in order, until the next
      `:layers` change; a layer is a `CauldronGPU.SpriteLayer` or a
      `CauldronGPU.ColumnLayer`, and `{:layers, []}` removes them
    * `{:effects, [effect]}` with effects `:ray_traced_shadows`, `:ray_traced_reflections`,
      `:ray_traced_global_illumination`, `:ray_traced_ambient_occlusion`, `:upscaling`,
      `:frame_generation`; a renderer that cannot provide one ignores it

  Ids are integers from 1 to 2³²−1. Positions and directions follow
  `CauldronGPU.Transform`'s frame.
  """

  alias CauldronGPU.{
    Camera,
    Canvas,
    ColumnLayer,
    Environment,
    Handle,
    Instance,
    Light,
    Material,
    Mesh,
    Pose,
    Sprite,
    SpriteLayer,
    Texture,
    Transform
  }

  @type id :: pos_integer()
  @type change ::
          :tick
          | {:mesh, id(), Mesh.t()}
          | {:drop_mesh, id()}
          | {:texture, id(), Texture.t()}
          | {:drop_texture, id()}
          | {:canvas, id(), Canvas.t()}
          | {:layers, [SpriteLayer.t() | ColumnLayer.t()]}
          | {:material, id(), Material.t()}
          | {:drop_material, id()}
          | {:instance, id(), Instance.t()}
          | {:move, id(), Transform.t()}
          | {:move, id(), Transform.t(), keyword()}
          | {:pose, id(), Pose.t()}
          | {:remove_instance, id()}
          | {:light, id(), Light.t()}
          | {:remove_light, id()}
          | Camera.t()
          | Environment.t()
          | {:light_styles, [number() | {number(), number(), number()}]}
          | {:overlay, Handle.t() | nil}
          | {:overlay, Handle.t(), :premultiplied}
          | {:screen_tint, {number(), number(), number(), number()}}
          | {:effects, [atom()]}

  @op %{
    tick: 1,
    mesh: 2,
    drop_mesh: 3,
    texture: 4,
    drop_texture: 5,
    material: 6,
    drop_material: 7,
    instance: 8,
    move: 9,
    remove_instance: 10,
    light: 11,
    remove_light: 12,
    camera: 13,
    environment: 14,
    effects: 15,
    skinned_mesh: 16,
    pose: 17,
    light_styles: 18,
    overlay: 19,
    screen_tint: 20,
    canvas: 21,
    layers: 22
  }

  @effects %{
    ray_traced_shadows: 1,
    ray_traced_reflections: 2,
    ray_traced_global_illumination: 4,
    upscaling: 8,
    frame_generation: 16,
    ray_traced_ambient_occlusion: 32
  }

  @doc "The operation code that drops an object of `kind`."
  @spec drop_op(Handle.kind()) :: non_neg_integer()
  def drop_op(:mesh), do: @op.drop_mesh
  def drop_op(:texture), do: @op.drop_texture
  def drop_op(:material), do: @op.drop_material

  @doc "The stream for `changes`, as iodata."
  @spec encode([change()]) :: iodata()
  def encode(changes), do: Enum.map(changes, &op/1)

  defp op(:tick), do: <<@op.tick>>
  defp op({:mesh, id, %Mesh{} = mesh}), do: mesh(id, mesh)
  defp op({:drop_mesh, id}), do: <<@op.drop_mesh, id::little-32>>
  defp op({:texture, id, %Texture{} = texture}), do: texture(id, texture)
  defp op({:drop_texture, id}), do: <<@op.drop_texture, id::little-32>>

  defp op({:canvas, id, %Canvas{} = canvas}),
    do:
      <<@op.canvas, id::little-32, flag(canvas.filter == :linear), canvas.width::little-32,
        canvas.height::little-32>>

  defp op({:layers, layers}),
    do: [<<@op.layers, length(layers)::little-32>>, Enum.map(layers, &layer/1)]

  defp op({:material, id, %Material{} = material}), do: material(id, material)
  defp op({:drop_material, id}), do: <<@op.drop_material, id::little-32>>
  defp op({:instance, id, %Instance{} = instance}), do: instance(id, instance)
  defp op({:move, id, %Transform{} = transform}), do: move(id, transform, false)

  defp op({:move, id, %Transform{} = transform, opts}),
    do: move(id, transform, Keyword.get(opts, :snap, false))

  defp op({:pose, id, %Pose{} = pose}), do: pose(id, pose)

  defp op({:overlay, texture}), do: <<@op.overlay, handle_id(texture)::little-32, 0>>

  defp op({:overlay, texture, :premultiplied}),
    do: <<@op.overlay, handle_id(texture)::little-32, 1>>

  defp op({:screen_tint, {r, g, b, a}}), do: [<<@op.screen_tint>>, floats([r, g, b, a])]

  defp op({:light_styles, scales}),
    do: [<<@op.light_styles, length(scales)::little-32>>, Enum.map(scales, &style_colour/1)]

  defp op({:remove_instance, id}), do: <<@op.remove_instance, id::little-32>>
  defp op({:light, id, %Light{} = light}), do: light(id, light)
  defp op({:remove_light, id}), do: <<@op.remove_light, id::little-32>>
  defp op(%Camera{} = camera), do: camera(camera)
  defp op(%Environment{} = environment), do: environment(environment)
  defp op({:effects, effects}), do: <<@op.effects, effect_bits(effects)::little-32>>

  defp mesh(id, %Mesh{parts: parts, skin: skin} = mesh) do
    code = if skin, do: @op.skinned_mesh, else: @op.mesh

    [
      <<code, id::little-32, Mesh.vertex_count(mesh)::little-32,
        Mesh.index_count(mesh)::little-32, length(parts)::little-32>>,
      Enum.map(parts, fn {first, count} -> <<first::little-32, count::little-32>> end),
      mesh.vertices,
      mesh.indices,
      skin || <<>>,
      colors(mesh.colors)
    ]
  end

  defp layer(%SpriteLayer{} = layer) do
    [
      layer_head(0, layer.target, layer.clear, layer.port),
      rect(layer.view),
      <<length(layer.sprites)::little-32>>,
      Enum.map(layer.sprites, &sprite/1)
    ]
  end

  defp layer(%ColumnLayer{} = layer) do
    [
      layer_head(1, layer.target, layer.clear, layer.port),
      <<handle_id(layer.source)::little-32, length(layer.columns)::little-32>>,
      Enum.map(layer.columns, fn {u, v_scale, shade} -> floats([u, v_scale, shade]) end)
    ]
  end

  defp layer_head(kind, target, clear, port) do
    [
      <<kind, target_id(target)::little-32, flag(clear != nil)>>,
      floats(Tuple.to_list(clear || {0, 0, 0, 0})),
      rect(port)
    ]
  end

  defp target_id(:frame), do: 0
  defp target_id(%Handle{} = canvas), do: handle_id(canvas)

  defp rect(nil), do: floats([0, 0, 0, 0])
  defp rect({x, y, width, height}), do: floats([x, y, width, height])

  defp sprite(%Sprite{} = sprite) do
    {x, y} = sprite.position
    {origin_x, origin_y} = sprite.origin
    {scale_x, scale_y} = sprite.scale
    {cos, sin} = turn(sprite.angle)
    {red, green, blue} = sprite.colour

    [
      <<handle_id(sprite.texture)::little-32, sprite_mode(sprite.mode)::little-32>>,
      rect(sprite.source),
      floats([
        x,
        y,
        origin_x,
        origin_y,
        scale_x,
        scale_y,
        cos,
        sin,
        red,
        green,
        blue,
        sprite.alpha
      ])
    ]
  end

  defp turn(degrees) do
    quarters = degrees / 90

    if quarters == Float.round(quarters * 1.0),
      do: elem({{1, 0}, {0, 1}, {-1, 0}, {0, -1}}, Integer.mod(round(quarters), 4)),
      else: {:math.cos(degrees * :math.pi() / 180), :math.sin(degrees * :math.pi() / 180)}
  end

  defp sprite_mode(:over), do: 0
  defp sprite_mode(:add), do: 1
  defp sprite_mode(:subtract), do: 2

  defp colors(nil), do: <<0::little-32>>
  defp colors(colors), do: [<<1::little-32>>, colors]

  defp style_colour({r, g, b}), do: floats([r, g, b])
  defp style_colour(scale), do: floats([scale, scale, scale])

  defp pose(id, %Pose{blend_to: blend_to, blend: blend, bones: bones}) do
    [
      <<@op.pose, id::little-32, handle_id(blend_to)::little-32>>,
      floats([blend]),
      <<length(bones)::little-32>>,
      Enum.map(bones, &floats/1)
    ]
  end

  defp texture(id, %Texture{} = texture) do
    [
      <<@op.texture, id::little-32, texture_format(texture.format),
        flag(texture.filter == :linear), flag(texture.wrap == :clamp), flag(texture.mipmaps),
        texture.width::little-32, texture.height::little-32>>,
      texture.pixels
    ]
  end

  defp material(id, %Material{} = material) do
    flags =
      flag(material.unlit) + 2 * flag(material.double_sided) +
        4 * flag(material.alpha_mode == :blend) + 8 * flag(material.sky) +
        16 * flag(material.warp) +
        64 * flag(material.alpha_mode == :add) + 128 * flag(material.alpha_mode == :multiply) +
        65_536 * flag(material.uv_from == :reflection) +
        256 * material.lightmap_styles

    [
      <<@op.material, id::little-32>>,
      floats(Tuple.to_list(material.base_color)),
      floats(Tuple.to_list(material.emissive)),
      floats([
        material.emissive_strength,
        material.metallic,
        material.roughness,
        material.alpha_cutoff
      ]),
      <<flags::little-32>>,
      Enum.map(
        [
          material.base_texture,
          material.metallic_roughness_texture,
          material.emissive_texture,
          material.lightmap
        ],
        &<<handle_id(&1)::little-32>>
      ),
      floats([material.lightmap_scale]),
      <<handle_id(material.normal_texture)::little-32,
        handle_id(material.occlusion_texture)::little-32>>,
      floats([material.normal_scale, material.smear]),
      floats(Tuple.to_list(material.uv_scroll))
    ]
  end

  defp instance(id, %Instance{} = instance) do
    flags =
      flag(instance.hidden) + 2 * flag(not instance.shadows) + 4 * flag(instance.snap) +
        8 * flag(instance.in_front) + 16 * flag(not instance.depth_test) +
        32 * flag(instance.standing != nil)

    [
      <<@op.instance, id::little-32, handle_id(instance.mesh)::little-32, flags::little-32>>,
      transform(instance.transform),
      <<length(instance.materials)::little-32>>,
      Enum.map(instance.materials, &<<handle_id(&1)::little-32>>),
      shading(instance.shading),
      swell(instance.swell),
      floats(Tuple.to_list(instance.standing || {0.0, 0.0}))
    ]
  end

  defp swell(nil), do: floats([0.0, 0.0, 0.0])
  defp swell({width, height, speed}), do: floats([width, height, speed])

  defp shading(nil), do: [<<0::little-32>>, floats(List.duplicate(0.0, 9))]

  defp shading({ambient, directional, direction}),
    do: [
      <<1::little-32>>,
      floats(Tuple.to_list(ambient) ++ Tuple.to_list(directional) ++ Tuple.to_list(direction))
    ]

  defp move(id, transform, snap) do
    [<<@op.move, id::little-32, 4 * flag(snap)::little-32>>, transform(transform)]
  end

  defp light(id, %Light{} = light) do
    [
      <<@op.light, id::little-32, light_kind(light.kind), flag(light.shadows), 0::16>>,
      floats(Tuple.to_list(light.color) ++ [light.intensity]),
      floats(Tuple.to_list(light.position) ++ Tuple.to_list(light.direction)),
      floats([light.range, light.inner_cone, light.outer_cone])
    ]
  end

  defp camera(%Camera{} = camera) do
    [
      <<@op.camera>>,
      floats(Tuple.to_list(camera.position) ++ Tuple.to_list(camera.rotation)),
      floats([camera.fov_y, camera.near, camera.far]),
      <<4 * flag(camera.snap)::little-32>>,
      floats(Tuple.to_list(camera.viewport) ++ [camera.aspect || 0.0]),
      floats(Tuple.to_list(camera.resolution || {0, 0}))
    ]
  end

  defp environment(%Environment{} = environment) do
    [
      <<@op.environment>>,
      floats(
        Tuple.to_list(environment.sky_top) ++
          Tuple.to_list(environment.sky_horizon) ++
          Tuple.to_list(environment.sky_ground) ++
          Tuple.to_list(environment.ambient) ++
          [environment.ambient_intensity] ++
          Tuple.to_list(environment.fog_color) ++
          [
            environment.fog_density,
            environment.exposure,
            environment.shadow_distance,
            environment.reflections,
            environment.ao_radius,
            environment.ao_strength,
            environment.render_scale,
            environment.bloom_strength,
            environment.bloom_threshold
          ]
      ),
      <<tone_map(environment.tone_map)::little-32>>,
      sky_picture(environment.sky_picture),
      floats(Tuple.to_list(environment.sky_scroll)),
      <<flag(environment.light_space == :display)::little-32>>,
      floats([environment.gamma, environment.contrast, environment.brightness]),
      light_table(environment.light_table)
    ]
  end

  defp light_table(nil), do: <<0::little-32, 0.0::little-float-32>>

  defp light_table({texture, reach}),
    do: <<handle_id(texture)::little-32, reach::little-float-32>>

  defp sky_picture(nil), do: <<0::little-32, 0::size(6 * 32)>>

  defp sky_picture({:layers, back, front}),
    do: [
      <<1::little-32>>,
      Enum.map([back, front, nil, nil, nil, nil], &<<handle_id(&1)::little-32>>)
    ]

  defp sky_picture({:box, faces}) do
    handles = Enum.map(~w(pos_x neg_x pos_y neg_y pos_z neg_z)a, &Map.fetch!(faces, &1))
    [<<2::little-32>>, Enum.map(handles, &<<handle_id(&1)::little-32>>)]
  end

  defp transform(%Transform{position: position, rotation: rotation, scale: scale}) do
    floats(Tuple.to_list(position) ++ Tuple.to_list(rotation) ++ Tuple.to_list(scale))
  end

  defp floats(values), do: for(value <- values, into: <<>>, do: <<value::little-float-32>>)
  defp flag(true), do: 1
  defp flag(false), do: 0
  defp handle_id(nil), do: 0
  defp handle_id(%Handle{id: id}), do: id
  defp texture_format(:srgb), do: 0
  defp texture_format(:linear), do: 1
  defp texture_format(:rgba16f), do: 2
  defp tone_map(:aces), do: 0
  defp tone_map(:neutral), do: 1
  defp tone_map(:clamp), do: 2
  defp light_kind(:directional), do: 0
  defp light_kind(:point), do: 1
  defp light_kind(:spot), do: 2
  defp effect_bits(effects), do: effects |> Enum.map(&Map.fetch!(@effects, &1)) |> Enum.sum()
end
