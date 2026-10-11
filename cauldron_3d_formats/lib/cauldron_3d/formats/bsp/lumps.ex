defmodule Cauldron3D.Formats.Bsp.Lumps do
  @moduledoc """
  The records of a Quake map's lumps, decoded, in the two layouts: `:bsp29`, the
  original, and `:bsp2`, which widens indices and bounds for larger maps.
  """

  @doc "Planes as `{normal, distance}`."
  @spec planes(binary()) :: [{tuple(), float()}]
  def planes(data) do
    for <<x::little-float-32, y::little-float-32, z::little-float-32, d::little-float-32,
          _type::little-32 <- data>>,
        do: {{x, y, z}, d}
  end

  @doc "Vertices as `{x, y, z}`."
  @spec vertices(binary()) :: [tuple()]
  def vertices(data),
    do: for(<<x::little-float-32, y::little-float-32, z::little-float-32 <- data>>, do: {x, y, z})

  @doc "Nodes as maps of plane, children (a negative child is the leaf `-child - 1`), bounds and faces."
  @spec nodes(binary(), :bsp29 | :bsp2) :: [map()]
  def nodes(data, :bsp29) do
    for <<plane::little-32, front::little-signed-16, back::little-signed-16, x0::little-signed-16,
          y0::little-signed-16, z0::little-signed-16, x1::little-signed-16, y1::little-signed-16,
          z1::little-signed-16, first::little-16, count::little-16 <- data>> do
      node(plane, front, back, {x0, y0, z0}, {x1, y1, z1}, first, count)
    end
  end

  def nodes(data, :bsp2) do
    for <<plane::little-32, front::little-signed-32, back::little-signed-32, x0::little-float-32,
          y0::little-float-32, z0::little-float-32, x1::little-float-32, y1::little-float-32,
          z1::little-float-32, first::little-32, count::little-32 <- data>> do
      node(plane, front, back, {x0, y0, z0}, {x1, y1, z1}, first, count)
    end
  end

  @doc "Texture axes as `%{s: {axis, offset}, t: {axis, offset}, texture:, flags:}`."
  @spec texinfo(binary()) :: [map()]
  def texinfo(data) do
    for <<sx::little-float-32, sy::little-float-32, sz::little-float-32, so::little-float-32,
          tx::little-float-32, ty::little-float-32, tz::little-float-32, to::little-float-32,
          texture::little-32, flags::little-32 <- data>> do
      %{s: {{sx, sy, sz}, so}, t: {{tx, ty, tz}, to}, texture: texture, flags: flags}
    end
  end

  @doc "Faces as maps of plane, side, edges, texinfo, light styles and lightmap offset."
  @spec faces(binary(), :bsp29 | :bsp2) :: [map()]
  def faces(data, :bsp29) do
    for <<plane::little-16, side::little-16, first::little-signed-32, count::little-16,
          texinfo::little-16, styles::binary-4, light::little-signed-32 <- data>>,
        do: face(plane, side, first, count, texinfo, styles, light)
  end

  def faces(data, :bsp2) do
    for <<plane::little-32, side::little-32, first::little-signed-32, count::little-32,
          texinfo::little-32, styles::binary-4, light::little-signed-32 <- data>>,
        do: face(plane, side, first, count, texinfo, styles, light)
  end

  @doc "Clip nodes as `{plane, front, back}`, a negative child being contents."
  @spec clipnodes(binary(), :bsp29 | :bsp2) :: [tuple()]
  def clipnodes(data, :bsp29) do
    for <<plane::little-32, front::little-signed-16, back::little-signed-16 <- data>>,
      do: {plane, front, back}
  end

  def clipnodes(data, :bsp2) do
    for <<plane::little-32, front::little-signed-32, back::little-signed-32 <- data>>,
      do: {plane, front, back}
  end

  @doc "Leaves as maps of contents, visibility offset, bounds and marked faces."
  @spec leaves(binary(), :bsp29 | :bsp2) :: [map()]
  def leaves(data, :bsp29) do
    for <<contents::little-signed-32, vis::little-signed-32, x0::little-signed-16,
          y0::little-signed-16, z0::little-signed-16, x1::little-signed-16, y1::little-signed-16,
          z1::little-signed-16, first::little-16, count::little-16, _ambient::binary-4 <- data>> do
      leaf(contents, vis, {x0, y0, z0}, {x1, y1, z1}, first, count)
    end
  end

  def leaves(data, :bsp2) do
    for <<contents::little-signed-32, vis::little-signed-32, x0::little-float-32,
          y0::little-float-32, z0::little-float-32, x1::little-float-32, y1::little-float-32,
          z1::little-float-32, first::little-32, count::little-32, _ambient::binary-4 <- data>> do
      leaf(contents, vis, {x0, y0, z0}, {x1, y1, z1}, first, count)
    end
  end

  @doc "The face index list leaves point into."
  @spec marks(binary(), :bsp29 | :bsp2) :: [non_neg_integer()]
  def marks(data, :bsp29), do: for(<<face::little-16 <- data>>, do: face)
  def marks(data, :bsp2), do: for(<<face::little-32 <- data>>, do: face)

  @doc "Edges as `{from, to}` vertex indices."
  @spec edges(binary(), :bsp29 | :bsp2) :: [tuple()]
  def edges(data, :bsp29), do: for(<<a::little-16, b::little-16 <- data>>, do: {a, b})
  def edges(data, :bsp2), do: for(<<a::little-32, b::little-32 <- data>>, do: {a, b})

  @doc "Signed edge references: a negative one runs its edge backwards."
  @spec surfedges(binary()) :: [integer()]
  def surfedges(data), do: for(<<edge::little-signed-32 <- data>>, do: edge)

  @doc "Brush models as maps of bounds, origin, hull heads, visible leaf count and faces."
  @spec models(binary()) :: [map()]
  def models(data) do
    for <<x0::little-float-32, y0::little-float-32, z0::little-float-32, x1::little-float-32,
          y1::little-float-32, z1::little-float-32, ox::little-float-32, oy::little-float-32,
          oz::little-float-32, h0::little-signed-32, h1::little-signed-32, h2::little-signed-32,
          h3::little-signed-32, visleafs::little-32, first::little-32, count::little-32 <- data>> do
      %{
        mins: {x0, y0, z0},
        maxs: {x1, y1, z1},
        origin: {ox, oy, oz},
        heads: [h0, h1, h2, h3],
        visleafs: visleafs,
        first_face: first,
        face_count: count
      }
    end
  end

  defp node(plane, front, back, mins, maxs, first, count) do
    %{
      plane: plane,
      front: front,
      back: back,
      mins: float(mins),
      maxs: float(maxs),
      first_face: first,
      face_count: count
    }
  end

  defp leaf(contents, vis, mins, maxs, first, count) do
    %{
      contents: contents,
      vis: vis,
      mins: float(mins),
      maxs: float(maxs),
      first_mark: first,
      mark_count: count
    }
  end

  defp face(plane, side, first, count, texinfo, <<a, b, c, d>>, light) do
    %{
      plane: plane,
      back?: side != 0,
      first_edge: first,
      edge_count: count,
      texinfo: texinfo,
      styles: Enum.reject([a, b, c, d], &(&1 == 255)),
      light: if(light < 0, do: nil, else: light)
    }
  end

  defp float({x, y, z}), do: {x / 1, y / 1, z / 1}
end
