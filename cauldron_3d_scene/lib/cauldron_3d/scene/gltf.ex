defmodule Cauldron3D.Scene.Gltf do
  @moduledoc """
  Puts a glTF document (`Cauldron3D.Formats.Gltf`) in a scene through a
  `Cauldron3D.Scene.Target`: one mesh for each glTF mesh a node places, with a part for each of
  its primitives, the materials those parts use, their images as encoded textures, and an
  instance for each node that places a mesh. Meshes, materials and images no node uses
  are not uploaded.

      {:ok, document} = Cauldron3D.Formats.Gltf.read("alley/barrel_stove_1k.gltf")
      {:ok, placed} = Cauldron3D.Scene.Gltf.upload(target, document, first_id: 100)
      Cauldron3D.Scene.Target.submit(target, placed.instances)

  Options:

    * `:first_id` — the instance id of the first instance; the rest follow. Default `1`
    * `:place` — a `Cauldron3D.Scene.Transform` applied to the whole document. Default none
    * `:places` — several transforms in place of `:place`: the document is uploaded once
      and placed at each, its instances numbered on from one place to the next
    * `:shadows` — whether its instances cast shadows. Default `true`

  The result is `%{instances, handles, bounds, skins, next_id}`: the
  `{:instance, id, instance}` changes to submit, every handle uploaded (to release when
  the document leaves the scene), the smallest and largest corner of everything placed
  (`nil` for nothing), `{id, skin}` for each skinned instance, `{id, node, weights}` for each
  instance whose mesh has morph targets (`weights` the ones the mesh starts with; none are
  applied until a pose gives them), and the first id not used.
  An image that is neither PNG nor JPEG is `{:error, {:image, index, :unknown_image}}`.

  A mesh whose primitives all have joints and weights is uploaded with its skin. Its
  instances are placed by the place alone, not by their node, and stand in their rest
  pose until posed: send `{:pose, id, %Cauldron3D.Scene.Pose{bones: bones}}` with the bones
  `Cauldron3D.Formats.Gltf.Rig.bones/4` gives for the instance's skin. A skin with more
  than 255 joints is `{:error, {:too_many_joints, skin}}`. A mesh keeps its first 64 morph
  targets.

  A material's `KHR_texture_transform` on its base texture is applied to the texture
  coordinates of the parts that use it. Occlusion strength other than one, texture
  coordinate sets other than the first for colour textures, and glTF's lights and cameras
  are not read.
  """

  alias Cauldron3D.Scene.Gltf.{Placement, Vertices}
  alias Cauldron3D.Scene.{Handle, Instance, Material, Mesh, Texture, Transform}
  alias Cauldron3D.Scene.Target

  @linear [:metallic_roughness_texture, :normal_texture, :occlusion_texture]
  @colour [:base_texture, :emissive_texture]
  @max_morphs 64

  @type result :: %{
          instances: [{:instance, pos_integer(), Instance.t()}],
          handles: [Handle.t()],
          bounds: {{float(), float(), float()}, {float(), float(), float()}} | nil,
          skins: [{pos_integer(), non_neg_integer()}],
          morphs: [{pos_integer(), non_neg_integer(), [float()]}],
          next_id: pos_integer()
        }

  @doc "Uploads `document` to `target`; see the module documentation for the options."
  @spec upload(Target.t(), map(), keyword()) :: {:ok, result()} | {:error, term()}
  def upload(target, document, opts \\ []) do
    used_meshes = document.instances |> Enum.map(& &1.mesh) |> Enum.uniq()
    used_materials = used_materials(document, used_meshes)

    with :ok <- joints_fit(document),
         {:ok, textures} <- textures(target, document, used_materials) do
      materials = materials(target, document, textures, used_materials)

      meshes =
        Map.new(used_meshes, fn index ->
          {index, mesh(target, Enum.at(document.meshes, index), document.materials)}
        end)

      first_id = Keyword.get(opts, :first_id, 1)
      instances = placed_instances(document, meshes, materials, first_id, opts)

      {:ok,
       %{
         instances: Enum.map(instances, &elem(&1, 0)),
         handles:
           Map.values(textures) ++
             Enum.map(Map.values(materials), & &1.handle) ++
             Enum.map(Map.values(meshes), & &1.handle),
         bounds: instances |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_nil/1) |> enclosing(),
         skins: instances |> Enum.map(&elem(&1, 2)) |> Enum.reject(&is_nil/1),
         morphs: instances |> Enum.map(&elem(&1, 3)) |> Enum.reject(&is_nil/1),
         next_id: first_id + length(instances)
       }}
    end
  end

  defp placed_instances(document, meshes, materials, first_id, opts) do
    opts
    |> Keyword.get(:places, [Keyword.get(opts, :place, %Transform{})])
    |> Enum.flat_map(fn place -> Enum.map(document.instances, &{Placement.matrix(place), &1}) end)
    |> Enum.with_index(first_id)
    |> Enum.map(fn {{place, placed}, id} ->
      placed_instance(id, place, placed, meshes, materials, opts)
    end)
  end

  defp placed_instance(id, place, placed, meshes, materials, opts) do
    mesh = Map.fetch!(meshes, placed.mesh)
    matrix = if mesh.skinned, do: place, else: Placement.multiply(place, placed.matrix)
    {change, bounds} = instance(id, mesh, materials, matrix, opts)
    {change, bounds, if(mesh.skinned, do: {id, placed.skin}), morphing(id, placed, mesh)}
  end

  defp morphing(_id, _placed, %{morphs: 0}), do: nil
  defp morphing(id, placed, mesh), do: {id, placed.node, mesh.weights}

  defp joints_fit(document) do
    document.instances
    |> Enum.map(& &1.skin)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.find(&(length(Enum.at(document.skins, &1).joints) > 255))
    |> then(fn
      nil -> :ok
      skin -> {:error, {:too_many_joints, skin}}
    end)
  end

  defp used_materials(document, used_meshes) do
    default = length(document.materials)

    used_meshes
    |> Enum.flat_map(&Enum.at(document.meshes, &1).primitives)
    |> Enum.map(&(&1.material || default))
    |> Enum.uniq()
  end

  defp textures(target, document, used_materials) do
    used_materials
    |> Enum.map(&Enum.at(document.materials, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.flat_map(&texture_uses/1)
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, %{}}, fn {reference, format} = use, {:ok, uploaded} ->
      image = Enum.at(document.images, reference.image)

      case Texture.encoded(image.bytes, texture_fields(reference, format)) do
        {:ok, texture} -> {:cont, {:ok, Map.put(uploaded, use, Target.texture(target, texture))}}
        {:error, reason} -> {:halt, {:error, {:image, reference.image, reason}}}
      end
    end)
  end

  defp texture_uses(material) do
    for {field, format} <- Enum.map(@colour, &{&1, :srgb}) ++ Enum.map(@linear, &{&1, :linear}),
        reference = Map.get(material, field),
        reference != nil,
        do: {texture_key(reference), format}
  end

  defp texture_key(reference), do: Map.take(reference, [:image, :wrap, :filter])

  defp texture_fields(reference, format) do
    {wrap_s, wrap_t} = reference.wrap
    wrap = if :clamp in [wrap_s, wrap_t] and wrap_s == wrap_t, do: :clamp, else: :repeat
    [format: format, filter: reference.filter, wrap: wrap, mipmaps: true]
  end

  defp materials(target, document, textures, used_materials) do
    sources = document.materials ++ [default_material()]

    Map.new(used_materials, fn index ->
      source = Enum.at(sources, index)

      material = %Material{
        base_color: source.base_color,
        base_texture: handle(textures, source.base_texture, :srgb),
        metallic: source.metallic,
        roughness: source.roughness,
        metallic_roughness_texture: handle(textures, source.metallic_roughness_texture, :linear),
        emissive: source.emissive,
        emissive_strength: source.emissive_strength,
        emissive_texture: handle(textures, source.emissive_texture, :srgb),
        normal_texture: handle(textures, source.normal_texture, :linear),
        normal_scale: source.normal_scale,
        occlusion_texture: handle(textures, source.occlusion_texture, :linear),
        alpha_mode: if(source.alpha_mode == :blend, do: :blend, else: :opaque),
        alpha_cutoff: if(source.alpha_mode == :mask, do: source.alpha_cutoff, else: 0.0),
        double_sided: source.double_sided,
        unlit: source.unlit
      }

      {index, %{handle: Target.material(target, material), transform: transform(source)}}
    end)
  end

  defp default_material do
    %{
      base_color: {1.0, 1.0, 1.0, 1.0},
      base_texture: nil,
      metallic: 1.0,
      roughness: 1.0,
      metallic_roughness_texture: nil,
      emissive: {0.0, 0.0, 0.0},
      emissive_strength: 1.0,
      emissive_texture: nil,
      normal_texture: nil,
      normal_scale: 1.0,
      occlusion_texture: nil,
      alpha_mode: :opaque,
      alpha_cutoff: 0.5,
      double_sided: false,
      unlit: false
    }
  end

  defp handle(_textures, nil, _format), do: nil

  defp handle(textures, reference, format),
    do: Map.fetch!(textures, {texture_key(reference), format})

  defp transform(%{base_texture: %{transform: transform}}), do: transform
  defp transform(_material), do: nil

  defp mesh(target, source, materials) do
    default = length(materials)

    {vertices, indices, parts, colors, skins, _count} =
      Enum.reduce(source.primitives, {[], [], [], [], [], 0}, fn primitive,
                                                                 {vertices, indices, parts,
                                                                  colors, skins, base} ->
        transform = transform(Enum.at(materials, primitive.material || default) || %{})
        count = div(byte_size(primitive.positions), 12)
        first = div(IO.iodata_length(indices), 4)

        shifted =
          for <<index::little-32 <- primitive.indices>>,
            into: <<>>,
            do: <<index + base::little-32>>

        {[vertices, Vertices.interleave(primitive, transform)], [indices, shifted],
         [{first, div(byte_size(shifted), 4)} | parts], [colors, Vertices.colors(primitive)],
         [Vertices.skin(primitive) | skins], base + count}
      end)

    skinned = skins != [] and Enum.all?(skins)
    morphs = morphs(source.primitives)

    mesh = %Mesh{
      vertices: IO.iodata_to_binary(vertices),
      indices: IO.iodata_to_binary(indices),
      parts: Enum.reverse(parts),
      colors: if(Enum.any?(source.primitives, & &1.colors), do: IO.iodata_to_binary(colors)),
      skin: if(skinned, do: skins |> Enum.reverse() |> IO.iodata_to_binary()),
      morphs: morphs
    }

    %{
      handle: Target.mesh(target, mesh),
      skinned: skinned,
      morphs: length(morphs),
      weights: weights(source, length(morphs)),
      parts: Enum.map(source.primitives, &(&1.material || default)),
      bounds:
        source.primitives |> Enum.map(&Vertices.bounds/1) |> Enum.reject(&is_nil/1) |> enclosing()
    }
  end

  defp morphs(primitives) do
    count = primitives |> Enum.map(&length(&1.targets)) |> Enum.max(fn -> 0 end) |> min(@max_morphs)

    for target <- 0..(count - 1)//1 do
      parts = Enum.map(primitives, &Vertices.morph(&1, target))

      %{
        positions: IO.iodata_to_binary(Enum.map(parts, & &1.positions)),
        normals: IO.iodata_to_binary(Enum.map(parts, & &1.normals))
      }
    end
  end

  defp weights(source, count),
    do: source.weights |> Kernel.++(List.duplicate(0.0, count)) |> Enum.take(count)

  defp instance(id, mesh, materials, matrix, opts) do

    instance = %Instance{
      mesh: mesh.handle,
      materials: Enum.map(mesh.parts, &Map.fetch!(materials, &1).handle),
      transform: Placement.transform(matrix),
      shadows: Keyword.get(opts, :shadows, true)
    }

    {{:instance, id, instance}, placed_bounds(mesh.bounds, matrix)}
  end

  defp placed_bounds(nil, _matrix), do: nil

  defp placed_bounds({{lx, ly, lz}, {hx, hy, hz}}, matrix) do
    for(x <- [lx, hx], y <- [ly, hy], z <- [lz, hz], do: Placement.point(matrix, {x, y, z}))
    |> Enum.map(&{&1, &1})
    |> enclosing()
  end

  defp enclosing([]), do: nil

  defp enclosing(boxes) do
    Enum.reduce(boxes, fn {{lx, ly, lz}, {hx, hy, hz}}, {{ax, ay, az}, {bx, by, bz}} ->
      {{min(lx, ax), min(ly, ay), min(lz, az)}, {max(hx, bx), max(hy, by), max(hz, bz)}}
    end)
  end
end
