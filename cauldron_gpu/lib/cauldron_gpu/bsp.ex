if Code.ensure_loaded?(Cauldron3D.Bsp) do
  defmodule CauldronGPU.Bsp do
    @moduledoc """
    A `Cauldron3D.Bsp` world uploaded for drawing: one mesh per brush model, a material per
    texture and lightmap page, the world's lightmaps packed into atlas pages.

        world = CauldronGPU.Bsp.upload(gpu, bsp, palette)
        CauldronGPU.submit(gpu, CauldronGPU.Bsp.instances(world, first_id: 1))

    `models` holds the brush models that have faces to draw, in order; `model/2` finds one by
    its number in the map (`*N` in an entity's model is number `N`).

    Vertices stay in the map's own units and axes (+Z up); `transform/1` turns them into the
    renderer's frame (+Y up) at `:scale` metres a unit, and `point/2` does the same for a
    single point such as a spawn spot.

    Texture kinds follow `Cauldron3D.Bsp`: `:solid` and `:masked` faces are lit by their
    lightmaps (every light style, each scaled by `{:light_styles, …}`, times `:light_scale`), `:masked` texels of colour 255 are cut
    out, `:sky` faces show the environment's sky (`sky_layers/3` gives a Quake world's),
    `:liquid` faces are drawn unlit and rippling, `:hidden` faces are left out. In a
    `:quake` world, palette colours 224 and up glow at full brightness.

    Options:
      * `:scale` — metres per map unit, default `1 / 32`
      * `:light_scale` — lightmap multiplier, default `2.0`
      * `:filter` — texture filtering, `:linear` (default) or `:nearest`
      * `:page_size` — lightmap atlas page size in luxels, default `2048`
    """

    alias Cauldron3D.Bsp, as: World
    alias Cauldron3D.Bsp.Face
    alias CauldronGPU.Bsp.{Atlas, Pictures}
    alias CauldronGPU.{Handle, Instance, Material, Mesh, Quat, Transform}

    @type t :: %__MODULE__{
            models: [{Handle.t(), [Handle.t()]}],
            numbers: %{non_neg_integer() => {Handle.t(), [Handle.t()]}},
            handles: [Handle.t()],
            scale: number()
          }

    @enforce_keys [:models, :handles, :scale]
    defstruct [:models, :handles, :scale, numbers: %{}]

    @doc "Uploads `bsp`'s textures, lightmaps and brush models. `palette` is 768 bytes, used by textures without their own."
    @spec upload(CauldronGPU.Target.t(), World.t(), binary(), keyword()) :: t()
    def upload(gpu, %World{} = bsp, palette, opts \\ []) do
      pictures = Pictures.upload(gpu, bsp, palette, Keyword.get(opts, :filter, :linear))
      atlas = Atlas.pack(bsp, Keyword.get(opts, :page_size, 2048))
      pages = Enum.map(Atlas.textures(atlas, bsp), &CauldronGPU.Target.texture(gpu, &1))
      light_scale = Keyword.get(opts, :light_scale, 2.0)

      numbered =
        for index <- 0..(tuple_size(bsp.models) - 1),
            model = build_model(bsp, elem(bsp.models, index), atlas),
            model != nil do
          {index, upload_model(gpu, model, pictures, pages, light_scale, atlas.slots)}
        end

      %__MODULE__{
        models: Enum.map(numbered, &elem(&1, 1)),
        numbers: Map.new(numbered),
        handles: pages ++ Pictures.handles(pictures),
        scale: Keyword.get(opts, :scale, 1 / 32)
      }
    end

    @doc "Brush model `number`'s mesh and materials, or `nil` when it has no faces to draw."
    @spec model(t(), non_neg_integer()) :: {Handle.t(), [Handle.t()]} | nil
    def model(%__MODULE__{numbers: numbers}, number), do: Map.get(numbers, number)

    @doc "The transform that places map coordinates in the renderer's frame."
    @spec transform(t() | number()) :: Transform.t()
    def transform(%__MODULE__{scale: scale}), do: transform(scale)

    def transform(scale),
      do: Transform.new(rotation: Quat.axis_angle({1, 0, 0}, -:math.pi() / 2), scale: scale)

    @doc "A map point in the renderer's frame."
    @spec point(t(), {number(), number(), number()}) :: {float(), float(), float()}
    def point(%__MODULE__{scale: scale}, {x, y, z}), do: {x * scale, z * scale, -y * scale}

    @doc "The camera rotation facing a map yaw of `degrees` (0 along +X, counter-clockwise from above)."
    @spec facing(number(), number()) :: Quat.t()
    def facing(degrees, pitch \\ 0.0),
      do: Quat.yaw_pitch((degrees - 90) * :math.pi() / 180, pitch)

    @doc """
    The brightness at `seconds` of a light style written as a pattern of letters, `a`
    dark to `z` brightest with `m` normal, stepping ten letters a second and repeating.

        CauldronGPU.Bsp.light_style("mmnmmommommnonmmonqnmmo", 2.35)
    """
    @spec light_style(String.t(), number()) :: float()
    def light_style("", _seconds), do: 1.0

    def light_style(pattern, seconds) do
      step = rem(trunc(seconds * 10), byte_size(pattern))
      (:binary.at(pattern, step) - ?a) / (?m - ?a)
    end

    @doc """
    The sky picture of a `:quake` world, for `CauldronGPU.Environment`'s `sky_picture`:
    its first `:sky` texture split into the back layer (the right half) and the front layer
    (the left half, colour 0 see-through), uploaded through `target`. `nil` when the world
    has no indexed sky texture. The caller keeps the two handles.
    """
    @spec sky_layers(CauldronGPU.Target.t(), World.t(), binary()) ::
            {:layers, Handle.t(), Handle.t()} | nil
    def sky_layers(target, %World{textures: textures}, palette) do
      case Enum.find(Tuple.to_list(textures), &(&1.kind == :sky)) do
        %{mips: [%{format: :indexed} = picture | _]} ->
          colours = picture_colours(picture.palette || palette)
          half = div(picture.width, 2)
          front = layer(picture, colours, 0, half, true)
          back = layer(picture, colours, half, half, false)

          {:layers, CauldronGPU.Target.texture(target, back),
           CauldronGPU.Target.texture(target, front)}

        _other ->
          nil
      end
    end

    @doc "Instance changes placing every brush model, ids counting up from `:first_id` (default 1)."
    @spec instances(t(), keyword()) :: [CauldronGPU.Stream.change()]
    def instances(%__MODULE__{} = world, opts \\ []) do
      first = Keyword.get(opts, :first_id, 1)

      world.models
      |> Enum.with_index(first)
      |> Enum.map(fn {{mesh, materials}, id} ->
        {:instance, id, %Instance{mesh: mesh, materials: materials, transform: transform(world)}}
      end)
    end

    defp upload_model(gpu, {mesh, groups}, pictures, pages, light_scale, slots) do
      materials =
        Enum.map(groups, fn {texture, page} ->
          material(gpu, pictures, texture, page && Enum.at(pages, page), light_scale, slots)
        end)

      {CauldronGPU.Target.mesh(gpu, mesh), materials}
    end

    defp material(gpu, pictures, texture, page, light_scale, light_styles) do
      picture = Pictures.get(pictures, texture)

      CauldronGPU.Target.material(gpu, %Material{
        base_texture: picture.base,
        emissive: if(picture.glow, do: {1.0, 1.0, 1.0}, else: {0.0, 0.0, 0.0}),
        emissive_texture: picture.glow,
        lightmap: page,
        lightmap_scale: light_scale,
        lightmap_styles: light_styles,
        alpha_cutoff: if(picture.kind == :masked, do: 0.5, else: 0.0),
        unlit: picture.kind == :liquid,
        sky: picture.kind == :sky,
        warp: picture.kind == :liquid,
        roughness: 0.9
      })
    end

    defp picture_colours(palette),
      do: List.to_tuple(for <<r, g, b <- palette>>, do: <<r, g, b, 255>>)

    defp layer(picture, colours, from, width, see_through?) do
      pixels =
        for row <- 0..(picture.height - 1),
            <<index <- binary_part(picture.pixels, row * picture.width + from, width)>>,
            into: <<>>,
            do: if(see_through? and index == 0, do: <<0, 0, 0, 0>>, else: elem(colours, index))

      %CauldronGPU.Texture{width: width, height: picture.height, pixels: pixels}
    end

    defp build_model(bsp, model, atlas) do
      faces =
        for index <- model.first_face..(model.first_face + model.face_count - 1)//1,
            face = elem(bsp.faces, index),
            elem(bsp.textures, face.texture).kind != :hidden,
            length(face.points) >= 3,
            do: {index, face}

      if faces == [], do: nil, else: mesh(bsp, faces, atlas)
    end

    defp mesh(bsp, faces, atlas) do
      groups =
        faces
        |> Enum.group_by(fn {index, face} -> {face.texture, Atlas.page(atlas, index)} end)
        |> Enum.sort_by(fn {key, _} -> key end)

      {vertices, indices, parts, _count, _index_count} =
        Enum.reduce(groups, {[], [], [], 0, 0}, fn {_key, group},
                                                   {vertices, indices, parts, count, index_count} ->
          {group_vertices, group_indices, count} = triangles(bsp, group, atlas, count)
          part = {index_count, length(group_indices)}

          {[group_vertices | vertices], [group_indices | indices], [part | parts], count,
           index_count + length(group_indices)}
        end)

      mesh = %Mesh{
        vertices: vertices |> Enum.reverse() |> IO.iodata_to_binary(),
        indices:
          indices
          |> Enum.reverse()
          |> List.flatten()
          |> Enum.map(&<<&1::little-32>>)
          |> IO.iodata_to_binary(),
        parts: Enum.reverse(parts)
      }

      {mesh, Enum.map(groups, fn {key, _} -> key end)}
    end

    defp triangles(bsp, group, atlas, count) do
      Enum.reduce(group, {[], [], count}, fn {index, face}, {vertices, indices, base} ->
        corners = Enum.map(face.points, &vertex(bsp, face, index, atlas, &1))
        fan = for corner <- 1..(length(corners) - 2), do: [base, base + corner + 1, base + corner]
        {[vertices | corners], [indices | List.flatten(fan)], base + length(corners)}
      end)
      |> then(fn {vertices, indices, next} -> {vertices, List.flatten(indices), next} end)
    end

    defp vertex(bsp, %Face{} = face, index, atlas, {x, y, z} = point) do
      {normal, _distance} = elem(bsp.planes, face.plane)
      {nx, ny, nz} = if face.back?, do: negate(normal), else: normal
      {s, t} = Face.st(face, point)
      %{mips: [first | _]} = elem(bsp.textures, face.texture)
      {lu, lv} = Atlas.uv(atlas, index, face, s, t)
      [s0, s1, s2, s3] = Atlas.styles(face)
      {first_styles, last_styles} = {s0 + 256 * s1, s2 + 256 * s3}

      <<x::little-float-32, y::little-float-32, z::little-float-32,
        s / first.width::little-float-32, nx::little-float-32, ny::little-float-32,
        nz::little-float-32, t / first.height::little-float-32, lu::little-float-32,
        lv::little-float-32, first_styles::little-float-32, last_styles::little-float-32>>
    end

    defp negate({x, y, z}), do: {-x, -y, -z}
  end
end
