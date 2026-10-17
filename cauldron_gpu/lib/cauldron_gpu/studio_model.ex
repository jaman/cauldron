if Code.ensure_loaded?(Cauldron3D.Formats.Studio) and Code.ensure_loaded?(Cauldron3D.Skeleton) do
  defmodule CauldronGPU.StudioModel do
    @moduledoc """
    A Half-Life studio model (`Cauldron3D.Formats.Studio`) uploaded for drawing: one
    skinned mesh in the model's rest pose, every vertex weighted wholly to its own bone,
    one mesh part per skin reference, and its textures.

        {:ok, studio} = Cauldron3D.Formats.Studio.parse(File.read!("barney.mdl"))
        studio = Cauldron3D.Formats.Studio.add_textures(studio, File.read!("barneyt.mdl"))
        model = CauldronGPU.StudioModel.upload(gpu, studio)
        materials = CauldronGPU.StudioModel.materials(gpu, model)
        instance = CauldronGPU.StudioModel.instance(model, materials, CauldronGPU.Placement.transform(1 / 32, origin, 90))
        CauldronGPU.submit(gpu, [{:instance, 3, instance}, CauldronGPU.StudioModel.pose(model, 3, "walk", 0.8)])

    Vertices stay in the model's own units and axes (x forward, y left, z up);
    `CauldronGPU.Placement.transform/3` stands a model at a map point. Sequences that move
    their motion bone along x, y or z have that movement taken out, so the model walks in
    place and the caller moves the instance.

    Texture flags are followed as far as the renderer's materials go: masked (`0x40`)
    textures are cut out at colour 255, fullbright (`0x04`) ones are drawn unlit;
    chrome and additive textures are drawn as plain textures.
    """

    import Bitwise, only: [band: 2]

    alias Cauldron3D.Formats.Studio
    alias Cauldron3D.Skeleton
    alias CauldronGPU.{Handle, Instance, Material, Mesh, Pose, Stream, Texture, Transform}

    @type t :: %__MODULE__{
            studio: Studio.t(),
            mesh: Handle.t(),
            skin_refs: [non_neg_integer()],
            textures: tuple(),
            unbind: tuple()
          }

    @enforce_keys [:studio, :mesh, :skin_refs, :textures, :unbind]
    defstruct [:studio, :mesh, :skin_refs, :textures, :unbind]

    @masked 0x40
    @fullbright 0x04

    @doc """
    Uploads `studio`'s textures and its mesh. Options: `:bodies`, a map from body part
    index to the model index drawn for it (default 0 for each part), and `:filter`,
    `:linear` (default) or `:nearest`. The textures must already be in `studio`
    (`Studio.add_textures/2` for a model whose textures are in a separate file).
    """
    @spec upload(CauldronGPU.Target.t(), Studio.t(), keyword()) :: t()
    def upload(gpu, %Studio{} = studio, opts \\ []) do
      bind = Skeleton.pose(studio.parents, rest(studio))
      models = chosen_models(studio, Keyword.get(opts, :bodies, %{}))
      groups = models |> Enum.flat_map(&model_meshes/1) |> Enum.group_by(&elem(&1, 1).skin)
      skin_refs = groups |> Map.keys() |> Enum.sort()
      {vertices, skins, indices, parts} = build(studio, groups, skin_refs, bind)

      mesh = %Mesh{
        vertices: vertices,
        indices: for(index <- indices, into: <<>>, do: <<index::little-32>>),
        parts: parts,
        skin: skins
      }

      %__MODULE__{
        studio: studio,
        mesh: CauldronGPU.Target.mesh(gpu, mesh),
        skin_refs: skin_refs,
        textures: upload_textures(gpu, studio, Keyword.get(opts, :filter, :linear)),
        unbind: bind |> Tuple.to_list() |> Enum.map(&invert/1) |> List.to_tuple()
      }
    end

    @doc """
    One material per mesh part for skin family `:family` (default 0; a family the model
    lacks is family 0). Options: `:lightmap`, a texture whose texel at lightmap
    coordinates `{0, 0}` lights the whole model, times `:light_scale` (default 2.0).
    """
    @spec materials(CauldronGPU.Target.t(), t(), keyword()) :: [Handle.t()]
    def materials(gpu, %__MODULE__{} = model, opts \\ []) do
      family = Keyword.get(opts, :family, 0)

      for ref <- model.skin_refs do
        case texture_index(model.studio, family, ref) do
          nil -> CauldronGPU.Target.material(gpu, %Material{})
          index -> CauldronGPU.Target.material(gpu, material(model, index, opts))
        end
      end
    end

    @doc "An instance of the model with `materials` at `transform`."
    @spec instance(t(), [Handle.t()], Transform.t()) :: Instance.t()
    def instance(%__MODULE__{mesh: mesh}, materials, %Transform{} = transform),
      do: %Instance{mesh: mesh, materials: materials, transform: transform}

    @doc "The sequence names, in order."
    @spec sequences(t()) :: [String.t()]
    def sequences(%__MODULE__{studio: studio}),
      do: studio.sequences |> Tuple.to_list() |> Enum.map(& &1.name)

    @doc """
    The bone matrices (3×4, row by row) posing the rest-pose mesh in `sequence` (a name,
    without regard to case, or an index; an unknown one is sequence 0) at `time` seconds
    into it, at the sequence's own frame rate. `opts` go to `Studio.locals/4`
    (`:controllers`, `:subblend` and so on).
    """
    @spec bones(t(), String.t() | non_neg_integer(), number(), keyword()) :: [Pose.matrix()]
    def bones(%__MODULE__{studio: studio, unbind: unbind}, sequence, time, opts \\ []) do
      index = sequence_index(studio, sequence)
      %{fps: fps} = info = elem(studio.sequences, index)

      studio
      |> Studio.locals(index, time * fps, opts)
      |> in_place(info)
      |> then(&Skeleton.pose(studio.parents, &1))
      |> Tuple.to_list()
      |> Enum.zip_with(Tuple.to_list(unbind), &flatten(Skeleton.concat(&1, &2)))
    end

    @doc "The `{:pose, id, …}` change for `bones/4`."
    @spec pose(t(), Stream.id(), String.t() | non_neg_integer(), number(), keyword()) ::
            Stream.change()
    def pose(%__MODULE__{} = model, id, sequence, time, opts \\ []),
      do: {:pose, id, %Pose{bones: bones(model, sequence, time, opts)}}

    @doc "Every handle the model holds."
    @spec handles(t()) :: [Handle.t()]
    def handles(%__MODULE__{mesh: mesh, textures: textures}),
      do: [mesh | textures |> Tuple.to_list() |> Enum.reject(&is_nil/1)]

    defp rest(studio) do
      for %{value: value} <- Tuple.to_list(studio.bones) do
        {x, y, z, ax, ay, az} = value
        {{x, y, z}, Cauldron3D.Quat.from_euler({ax, ay, az})}
      end
    end

    defp chosen_models(studio, bodies) do
      studio.body_parts
      |> Enum.with_index()
      |> Enum.flat_map(fn {part, index} ->
        case Enum.at(part.models, Map.get(bodies, index, 0)) do
          nil -> []
          model -> [model]
        end
      end)
    end

    defp model_meshes(model), do: Enum.map(model.meshes, &{model, &1})

    defp build(studio, groups, skin_refs, bind) do
      {vertices, skins, indices, parts, _} =
        Enum.reduce(skin_refs, {[], [], [], [], {%{}, 0}}, fn ref,
                                                              {vertices, skins, indices, parts,
                                                               table} ->
          size = texture_size(studio, ref)
          first = length(indices)

          {vertices, skins, indices, table} =
            for {model, mesh} <- Map.fetch!(groups, ref),
                {a, b, c} <- mesh.triangles,
                corner <- [a, c, b],
                reduce: {vertices, skins, indices, table} do
              acc -> add_corner(acc, model, corner, size, bind)
            end

          {vertices, skins, indices, [{first, length(indices) - first} | parts], table}
        end)

      {vertices |> Enum.reverse() |> IO.iodata_to_binary(),
       skins |> Enum.reverse() |> IO.iodata_to_binary(), Enum.reverse(indices),
       Enum.reverse(parts)}
    end

    defp add_corner(
           {vertices, skins, indices, {table, count}},
           model,
           {v, n, s, t} = corner,
           size,
           bind
         ) do
      key = {model.name, corner}

      case table do
        %{^key => index} ->
          {vertices, skins, [index | indices], {table, count}}

        _ ->
          bone = bone_of(model.vertex_bones, v)
          normal_bone = bone_of(model.normal_bones, n)
          position = Skeleton.apply(elem(bind, bone), elem(model.vertices, v))
          normal = Skeleton.rotate(elem(bind, normal_bone), normal_at(model.normals, n))

          {[vertex(position, normal, {s, t}, size) | vertices],
           [<<bone, 0, 0, 0, 255, 0, 0, 0>> | skins], [count | indices],
           {Map.put(table, key, count), count + 1}}
      end
    end

    defp bone_of(bones, index) when index < byte_size(bones), do: :binary.at(bones, index)
    defp bone_of(_bones, _index), do: 0

    defp normal_at(normals, index) when index < tuple_size(normals), do: elem(normals, index)
    defp normal_at(_normals, _index), do: {0.0, 0.0, 1.0}

    defp vertex({x, y, z}, {nx, ny, nz}, {s, t}, {width, height}) do
      <<x::little-float-32, y::little-float-32, z::little-float-32, s / width::little-float-32,
        nx::little-float-32, ny::little-float-32, nz::little-float-32,
        t / height::little-float-32, 0::little-float-32, 0::little-float-32, 0::little-float-32,
        0::little-float-32>>
    end

    defp texture_size(studio, ref) do
      with index when index != nil <- texture_index(studio, 0, ref),
           %Cauldron3D.Texture{width: width, height: height} <- elem(studio.textures, index) do
        {width, height}
      else
        _ -> {1, 1}
      end
    end

    defp texture_index(studio, family, ref) do
      families = tuple_size(studio.skins)
      family = if family >= 0 and family < families, do: family, else: 0

      with true <- families > 0,
           skins = elem(studio.skins, family),
           true <- ref < tuple_size(skins),
           index = elem(skins, ref),
           true <- index >= 0 and index < tuple_size(studio.textures),
           true <- elem(studio.textures, index) != nil do
        index
      else
        _ -> nil
      end
    end

    defp upload_textures(gpu, studio, filter) do
      studio.textures
      |> Tuple.to_list()
      |> Enum.zip(Tuple.to_list(studio.texture_flags))
      |> Enum.map(fn
        {nil, _flags} -> nil
        {texture, flags} -> CauldronGPU.Target.texture(gpu, picture(texture, flags, filter))
      end)
      |> List.to_tuple()
    end

    defp picture(texture, flags, filter) do
      colours = texture.colours || Cauldron3D.Texture.colours(texture.palette)
      masked? = band(flags, @masked) != 0

      pixels =
        for <<index <- texture.pixels>>, into: <<>> do
          if masked? and index == 255,
            do: <<0, 0, 0, 0>>,
            else: Cauldron3D.Texture.colour(colours, index)
        end

      %Texture{width: texture.width, height: texture.height, pixels: pixels, filter: filter}
    end

    defp material(model, index, opts) do
      flags = elem(model.studio.texture_flags, index)

      %Material{
        base_texture: elem(model.textures, index),
        alpha_cutoff: if(band(flags, @masked) != 0, do: 0.5, else: 0.0),
        unlit: band(flags, @fullbright) != 0,
        lightmap: Keyword.get(opts, :lightmap),
        lightmap_scale: Keyword.get(opts, :light_scale, 2.0),
        roughness: 0.9
      }
    end

    defp sequence_index(studio, name) when is_binary(name), do: Studio.sequence(studio, name) || 0

    defp sequence_index(studio, index)
         when is_integer(index) and index >= 0 and index < tuple_size(studio.sequences),
         do: index

    defp sequence_index(_studio, _index), do: 0

    defp in_place(locals, %{motion_bone: bone, motion_type: type})
         when bone >= 0 and band(type, 7) != 0 do
      List.update_at(locals, bone, fn {{x, y, z}, rotation} ->
        {{keep(x, type, 1), keep(y, type, 2), keep(z, type, 4)}, rotation}
      end)
    end

    defp in_place(locals, _info), do: locals

    defp keep(value, type, bit), do: if(band(type, bit) != 0, do: 0.0, else: value)

    defp invert({{a, b, c, tx}, {d, e, f, ty}, {g, h, i, tz}}) do
      {{a, d, g, -(a * tx + d * ty + g * tz)}, {b, e, h, -(b * tx + e * ty + h * tz)},
       {c, f, i, -(c * tx + f * ty + i * tz)}}
    end

    defp flatten({row0, row1, row2}),
      do: Tuple.to_list(row0) ++ Tuple.to_list(row1) ++ Tuple.to_list(row2)
  end
end
