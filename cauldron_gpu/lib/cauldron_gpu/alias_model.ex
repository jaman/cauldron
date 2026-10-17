if Code.ensure_loaded?(Cauldron3D.Mesh) do
  defmodule CauldronGPU.AliasModel do
    @moduledoc """
    A Quake alias model (a `Cauldron3D.Mesh` posed by keyframes, as read by
    `Cauldron3D.Formats.Mdl`) uploaded for drawing: one mesh per keyframe pose, every one
    with the same vertices in the same order and the same indices, so a
    `CauldronGPU.Pose` blends between any two; each skin as a base texture and, when it
    has palette colours 224 to 254, a glow texture holding only those. Skin textures have
    no mipmaps: every skin is read at full size, as Quake reads it.

        bytes = Files.read(files, "progs/soldier.mdl")
        {:ok, mdl} = Cauldron3D.Formats.Mdl.parse(bytes)
        model = CauldronGPU.AliasModel.upload(gpu, mdl, palette, names: CauldronGPU.AliasModel.frame_names(bytes))
        material = CauldronGPU.AliasModel.material(gpu, model)
        instance = CauldronGPU.AliasModel.instance(model, [material], CauldronGPU.Placement.transform(1 / 32, origin, 90))
        CauldronGPU.submit(gpu, CauldronGPU.AliasModel.animate(model, 7, instance, "stand", 1.25))

    Vertices stay in the model's own units and axes (x forward, y left, z up);
    `CauldronGPU.Placement.transform/3` stands a model at a map point.

    An animation is the poses whose names share a stem once trailing digits are taken
    off (`stand1` … `stand8` is `"stand"`), in pose order. `frame/3` plays the model's
    frame numbers as the game numbers them, a frame group cycling by its own intervals.
    """

    import Bitwise, only: [band: 2]

    alias CauldronGPU.{Handle, Instance, Material, Mesh, Pose, Stream, Texture, Transform}

    @type skin :: %{base: Handle.t(), glow: Handle.t() | nil}
    @type sample :: {non_neg_integer(), non_neg_integer(), float()}
    @type t :: %__MODULE__{
            poses: tuple(),
            skins: [skin()],
            names: tuple(),
            animations: %{String.t() => [non_neg_integer()]},
            frames: tuple(),
            flags: non_neg_integer()
          }

    @enforce_keys [:poses, :skins, :names, :animations, :frames, :flags]
    defstruct [:poses, :skins, :names, :animations, :frames, :flags]

    @rotate_flag 8

    @doc """
    Uploads `mdl` (a map with `:mesh`, a `Cauldron3D.Mesh`, and the game's frame table
    `:frames`, such as a `Cauldron3D.Formats.Mdl`). `palette` is 768 bytes.

    Options: `:names`, one name per pose (`frame_names/1`; without them there are no
    animations), and `:filter`, `:nearest` (default) or `:linear`.
    """
    @spec upload(CauldronGPU.Target.t(), map(), binary(), keyword()) :: t()
    def upload(gpu, %{mesh: %Cauldron3D.Mesh{} = mesh, frames: frames} = mdl, palette, opts \\ []) do
      filter = Keyword.get(opts, :filter, :nearest)
      [first_skin | _] = mesh.skins
      {corners, indices} = corners(mesh.triangles)
      size = {first_skin.width, first_skin.height}
      index_binary = for index <- indices, into: <<>>, do: <<index::little-32>>

      poses =
        mesh.frames
        |> Tuple.to_list()
        |> Enum.map(fn pose ->
          CauldronGPU.Target.mesh(gpu, %Mesh{
            vertices: vertices(pose, corners, size),
            indices: index_binary
          })
        end)
        |> List.to_tuple()

      names = Keyword.get(opts, :names, [])

      %__MODULE__{
        poses: poses,
        skins: Enum.map(mesh.skins, &skin(gpu, &1, colours(palette), filter)),
        names: List.to_tuple(names),
        animations: stems(names),
        frames: frames,
        flags: Map.get(mdl, :flags, 0)
      }
    end

    @doc "The name of every pose in the `.mdl` file `bytes`, in pose order (a frame group's poses each have one)."
    @spec frame_names(binary()) :: [String.t()]
    def frame_names(
          <<"IDPO", 6::little-32, _::binary-40, skin_count::little-32, width::little-32,
            height::little-32, vertex_count::little-32, triangle_count::little-32,
            frame_count::little-32, _sync::little-32, _flags::little-32, _size::little-32,
            body::binary>>
        ) do
      body = skip_skins(body, skin_count, width * height)
      skipped = vertex_count * 12 + triangle_count * 16
      <<_::binary-size(^skipped), frames::binary>> = body
      frame_entries(frames, frame_count, vertex_count * 4 + 24, [])
    end

    @doc """
    A material drawing skin `:skin` (default 0). Options: `:lightmap`, a texture whose
    texel at lightmap coordinates `{0, 0}` lights the whole model (a 1×1 texture of the
    light where it stands), times `:light_scale` (default 2.0).
    """
    @spec material(CauldronGPU.Target.t(), t(), keyword()) :: Handle.t()
    def material(gpu, %__MODULE__{skins: skins}, opts \\ []) do
      skin = Enum.at(skins, Keyword.get(opts, :skin, 0)) || hd(skins)

      CauldronGPU.Target.material(gpu, %Material{
        base_texture: skin.base,
        emissive: if(skin.glow, do: {1.0, 1.0, 1.0}, else: {0.0, 0.0, 0.0}),
        emissive_texture: skin.glow,
        lightmap: Keyword.get(opts, :lightmap),
        lightmap_scale: Keyword.get(opts, :light_scale, 2.0),
        roughness: 0.9
      })
    end

    @doc "An instance of the model's first pose with `materials` at `transform`."
    @spec instance(t(), [Handle.t()], Transform.t()) :: Instance.t()
    def instance(%__MODULE__{poses: poses}, materials, %Transform{} = transform),
      do: %Instance{mesh: elem(poses, 0), materials: materials, transform: transform}

    @doc "Whether the game spins the model about its up axis (model flag 8, pickups)."
    @spec rotates?(t()) :: boolean()
    def rotates?(%__MODULE__{flags: flags}), do: band(flags, @rotate_flag) != 0

    @doc "The animation names, sorted."
    @spec animations(t()) :: [String.t()]
    def animations(%__MODULE__{animations: animations}),
      do: animations |> Map.keys() |> Enum.sort()

    @doc """
    The two poses `{from, to, blend}` of `animation` at `time` seconds. Options: `:fps`,
    poses a second (default 10), and `:loop` (default `true`); an animation that does not
    loop holds its last pose. Returns `{:error, :unknown_animation}` for a name the model
    lacks.
    """
    @spec sample(t(), String.t(), number(), keyword()) ::
            {:ok, sample()} | {:error, :unknown_animation}
    def sample(%__MODULE__{animations: animations}, animation, time, opts \\ []) do
      case animations do
        %{^animation => poses} ->
          {:ok, step(poses, time * Keyword.get(opts, :fps, 10), Keyword.get(opts, :loop, true))}

        _ ->
          {:error, :unknown_animation}
      end
    end

    @doc """
    The two poses `{from, to, blend}` of the game's frame number `frame` (out of range is
    frame 0) at `time` seconds: a single frame is its pose unblended, a frame group moves
    through its poses by their intervals.
    """
    @spec frame(t(), integer(), number()) :: sample()
    def frame(%__MODULE__{frames: frames}, frame, time) do
      entry =
        if frame >= 0 and frame < tuple_size(frames),
          do: elem(frames, frame),
          else: elem(frames, 0)

      group_sample(entry, time)
    end

    @doc """
    The changes showing instance `id` (as `instance`, at its transform) in `sample`: the
    instance on pose `from`, then its `{:pose, …}` blending `blend` of the way to `to`.
    """
    @spec pose(t(), Stream.id(), Instance.t(), sample()) :: [Stream.change()]
    def pose(%__MODULE__{poses: poses}, id, %Instance{} = instance, {from, to, blend}) do
      [
        {:instance, id, %{instance | mesh: elem(poses, from)}},
        {:pose, id, %Pose{blend_to: elem(poses, to), blend: blend}}
      ]
    end

    @doc "`pose/4` for `animation` at `time` (options as `sample/4`); an unknown animation shows pose 0."
    @spec animate(t(), Stream.id(), Instance.t(), String.t(), number(), keyword()) :: [
            Stream.change()
          ]
    def animate(%__MODULE__{} = model, id, %Instance{} = instance, animation, time, opts \\ []) do
      case sample(model, animation, time, opts) do
        {:ok, sample} -> pose(model, id, instance, sample)
        {:error, :unknown_animation} -> pose(model, id, instance, {0, 0, 0.0})
      end
    end

    @doc "Every handle the model holds."
    @spec handles(t()) :: [Handle.t()]
    def handles(%__MODULE__{poses: poses, skins: skins}),
      do:
        Tuple.to_list(poses) ++
          Enum.flat_map(skins, &Enum.reject([&1.base, &1.glow], fn handle -> is_nil(handle) end))

    defp corners(triangles) do
      {table, indices} =
        for {{a, b, c}, {uv_a, uv_b, uv_c}} <- triangles,
            corner <- [{a, uv_a}, {c, uv_c}, {b, uv_b}],
            reduce: {%{}, []} do
          acc -> add_corner(acc, corner)
        end

      corners = table |> Enum.sort_by(&elem(&1, 1)) |> Enum.map(&elem(&1, 0))
      {corners, Enum.reverse(indices)}
    end

    defp add_corner({table, indices}, corner) do
      case table do
        %{^corner => index} -> {table, [index | indices]}
        _ -> {Map.put(table, corner, map_size(table)), [map_size(table) | indices]}
      end
    end

    defp vertices(%{vertices: positions, normals: normals}, corners, {width, height}) do
      for {index, {s, t}} <- corners, into: <<>> do
        {x, y, z} = elem(positions, index)
        {nx, ny, nz} = elem(normals, index)

        <<x::little-float-32, y::little-float-32, z::little-float-32, s / width::little-float-32,
          nx::little-float-32, ny::little-float-32, nz::little-float-32,
          t / height::little-float-32, 0::little-float-32, 0::little-float-32, 0::little-float-32,
          0::little-float-32>>
      end
    end

    defp colours(palette),
      do: for(<<r, g, b <- palette>>, do: <<r, g, b, 255>>) |> List.to_tuple()

    defp skin(gpu, %Cauldron3D.Texture{} = texture, colours, filter) do
      base = for <<index <- texture.pixels>>, into: <<>>, do: elem(colours, index)

      %{
        base: CauldronGPU.Target.texture(gpu, picture(texture, base, filter)),
        glow: glow(gpu, texture, colours, filter)
      }
    end

    defp glow(gpu, texture, colours, filter) do
      if texture.pixels |> :binary.bin_to_list() |> Enum.any?(&fullbright?/1) do
        pixels =
          for <<index <- texture.pixels>>,
            into: <<>>,
            do: if(fullbright?(index), do: elem(colours, index), else: <<0, 0, 0, 255>>)

        CauldronGPU.Target.texture(gpu, picture(texture, pixels, filter))
      end
    end

    defp fullbright?(index), do: index >= 224 and index < 255

    defp picture(texture, pixels, filter),
      do: %Texture{
        width: texture.width,
        height: texture.height,
        pixels: pixels,
        filter: filter,
        mipmaps: false
      }

    defp stems(names) do
      names
      |> Enum.with_index()
      |> Enum.group_by(fn {name, _} -> stem(name) end, fn {_, index} -> index end)
    end

    defp stem(name), do: String.replace(name, ~r/\d+$/, "")

    defp step([pose], _position, _loop), do: {pose, pose, 0.0}

    defp step(poses, position, true) do
      count = length(poses)
      whole = floor(position)
      at = Integer.mod(whole, count)
      {Enum.at(poses, at), Enum.at(poses, rem(at + 1, count)), position - whole}
    end

    defp step(poses, position, false) do
      last = length(poses) - 1
      whole = floor(position)

      cond do
        whole < 0 -> {hd(poses), hd(poses), 0.0}
        whole >= last -> {List.last(poses), List.last(poses), 0.0}
        true -> {Enum.at(poses, whole), Enum.at(poses, whole + 1), position - whole}
      end
    end

    defp group_sample({:single, pose}, _time), do: {pose, pose, 0.0}

    defp group_sample({:group, entries}, time) do
      {_, cycle} = List.last(entries)
      at = if cycle > 0, do: :math.fmod(time, cycle), else: 0.0
      count = length(entries)
      position = Enum.find_index(entries, fn {_, until} -> at < until end) || count - 1
      {pose, until} = Enum.at(entries, position)
      start = if position == 0, do: 0.0, else: elem(Enum.at(entries, position - 1), 1)
      {next, _} = Enum.at(entries, rem(position + 1, count))
      blend = if until > start, do: (at - start) / (until - start), else: 0.0
      {pose, next, min(max(blend, 0.0), 1.0)}
    end

    defp skip_skins(body, 0, _size), do: body

    defp skip_skins(<<0::little-32, body::binary>>, count, size) do
      <<_::binary-size(^size), rest::binary>> = body
      skip_skins(rest, count - 1, size)
    end

    defp skip_skins(<<1::little-32, group::little-32, body::binary>>, count, size) do
      skipped = group * 4 + group * size
      <<_::binary-size(^skipped), rest::binary>> = body
      skip_skins(rest, count - 1, size)
    end

    defp frame_entries(_body, 0, _pose_size, names), do: Enum.reverse(names)

    defp frame_entries(<<0::little-32, body::binary>>, count, pose_size, names) do
      {name, rest} = pose_name(body, pose_size)
      frame_entries(rest, count - 1, pose_size, [name | names])
    end

    defp frame_entries(
           <<1::little-32, group::little-32, _bounds::binary-8, body::binary>>,
           count,
           pose_size,
           names
         ) do
      <<_intervals::binary-size(^group * 4), rest::binary>> = body

      {group_names, rest} =
        Enum.map_reduce(1..group, rest, fn _, acc -> pose_name(acc, pose_size) end)

      frame_entries(rest, count - 1, pose_size, Enum.reverse(group_names) ++ names)
    end

    defp pose_name(<<_bounds::binary-8, name::binary-16, _::binary>> = body, pose_size) do
      <<_::binary-size(^pose_size), rest::binary>> = body
      {name |> :binary.split(<<0>>) |> hd(), rest}
    end
  end
end
