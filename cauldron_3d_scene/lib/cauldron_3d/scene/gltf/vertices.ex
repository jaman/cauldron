defmodule Cauldron3D.Scene.Gltf.Vertices do
  @moduledoc """
  A glTF primitive's packed attributes (`Cauldron3D.Formats.Gltf.Primitives`) as
  `Cauldron3D.Scene.Mesh` vertices: 48 bytes each, position, texture coordinates, normal and
  the second texture coordinates as lightmap coordinates, with no light styles.

      Cauldron3D.Scene.Gltf.Vertices.interleave(primitive, nil)
  """

  @no_styles <<65_535.0::little-float-32, 65_535.0::little-float-32>>
  @no_uv <<0.0::little-float-32, 0.0::little-float-32>>

  @doc """
  The primitive's vertices, its texture coordinates first carried through `transform`
  (`KHR_texture_transform`'s `%{offset, scale, rotation}`, or `nil` for none).
  """
  @spec interleave(map(), map() | nil) :: binary()
  def interleave(primitive, transform) do
    uvs = transformed(primitive.uvs, transform)
    lightmap = primitive.uvs1 || :binary.copy(@no_uv, div(byte_size(primitive.positions), 12))

    primitive.positions
    |> woven(primitive.normals, uvs, lightmap, [])
    |> IO.iodata_to_binary()
  end

  @doc "The primitive's vertex colours as four bytes each, or opaque white for none."
  @spec colors(map()) :: binary()
  def colors(%{colors: nil, positions: positions}),
    do: :binary.copy(<<255, 255, 255, 255>>, div(byte_size(positions), 12))

  def colors(%{colors: colors}) do
    for <<r::little-float-32, g::little-float-32, b::little-float-32,
          a::little-float-32 <- colors>>,
        into: <<>>,
        do: <<byte(r), byte(g), byte(b), byte(a)>>
  end

  @doc """
  The primitive's joints and weights as a `Cauldron3D.Scene.Mesh` skin, 8 bytes a vertex: four
  joint indices, then four weights out of 255 that sum to 255. `nil` for a primitive
  without both. Joints must be below 256.
  """
  @spec skin(map()) :: binary() | nil
  def skin(%{joints: joints, weights: weights}) when is_binary(joints) and is_binary(weights) do
    for <<j0::little-32, j1::little-32, j2::little-32, j3::little-32 <- joints>>,
      reduce: {<<>>, weights} do
      {skin,
       <<w0::little-float-32, w1::little-float-32, w2::little-float-32, w3::little-float-32,
         rest::binary>>} ->
        [b0, b1, b2, b3] = bytes([w0, w1, w2, w3])
        {<<skin::binary, j0, j1, j2, j3, b0, b1, b2, b3>>, rest}
    end
    |> elem(0)
  end

  def skin(_primitive), do: nil

  @doc """
  Morph target `index` of the primitive as a `Cauldron3D.Scene.Mesh` morph: its offsets from the
  mesh, zeros for a primitive without that target or without normal offsets.
  """
  @spec morph(map(), non_neg_integer()) :: Cauldron3D.Scene.Mesh.morph()
  def morph(%{positions: positions, targets: targets}, index) do
    zeros = :binary.copy(<<0.0::little-float-32>>, div(byte_size(positions), 4))

    case Enum.at(targets, index) do
      nil -> %{positions: zeros, normals: zeros}
      target -> %{positions: target.positions, normals: target.normals || zeros}
    end
  end

  @doc "The smallest and largest corner of the primitive's positions, or `nil` for none."
  @spec bounds(map()) :: {{float(), float(), float()}, {float(), float(), float()}} | nil
  def bounds(%{positions: <<>>}), do: nil

  def bounds(%{
        positions: <<x::little-float-32, y::little-float-32, z::little-float-32, rest::binary>>
      }),
      do: widened(rest, {x, y, z}, {x, y, z})

  defp widened(
         <<x::little-float-32, y::little-float-32, z::little-float-32, rest::binary>>,
         {lx, ly, lz},
         {hx, hy, hz}
       ),
       do:
         widened(rest, {min(lx, x), min(ly, y), min(lz, z)}, {max(hx, x), max(hy, y), max(hz, z)})

  defp widened(<<>>, low, high), do: {low, high}

  defp woven(
         <<position::binary-size(12), positions::binary>>,
         <<normal::binary-size(12), normals::binary>>,
         <<u::binary-size(4), v::binary-size(4), uvs::binary>>,
         <<lightmap::binary-size(8), lightmaps::binary>>,
         acc
       ),
       do:
         woven(positions, normals, uvs, lightmaps, [
           acc,
           position,
           u,
           normal,
           v,
           lightmap,
           @no_styles
         ])

  defp woven(<<>>, _normals, _uvs, _lightmaps, acc), do: acc

  defp transformed(uvs, nil), do: uvs

  defp transformed(uvs, %{offset: {ou, ov}, scale: {su, sv}, rotation: rotation}) do
    {cos, sin} = {:math.cos(rotation), :math.sin(rotation)}

    for <<u::little-float-32, v::little-float-32 <- uvs>>, into: <<>> do
      <<cos * su * u + sin * sv * v + ou::little-float-32,
        -sin * su * u + cos * sv * v + ov::little-float-32>>
    end
  end

  defp byte(value), do: value |> max(0.0) |> min(1.0) |> Kernel.*(255) |> round()

  defp bytes(weights) do
    weights = Enum.map(weights, &max(&1, 0.0))
    total = Enum.sum(weights)
    weights = if total > 0, do: Enum.map(weights, &(&1 / total)), else: [1.0, 0.0, 0.0, 0.0]
    rounded = Enum.map(weights, &round(&1 * 255))
    heaviest = weights |> Enum.with_index() |> Enum.max_by(&elem(&1, 0)) |> elem(1)
    List.update_at(rounded, heaviest, &(&1 + 255 - Enum.sum(rounded)))
  end
end
