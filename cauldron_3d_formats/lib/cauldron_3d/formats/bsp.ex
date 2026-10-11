defmodule Cauldron3D.Formats.Bsp do
  @moduledoc """
  A map file of the Quake family read into a `Cauldron3D.Bsp`, with its entity text: the
  `BSP29` and `BSP2` layouts, and `BSP30` with its textures' own palettes and lighting in
  red, green and blue.

      {:ok, %{bsp: bsp, entities: text}} =
        Cauldron3D.Formats.Bsp.parse(bytes,
          hulls: [{{-16.0, -16.0, -24.0}, {16.0, 16.0, 32.0}}],
          texture: &MyGame.texture/2
        )

  ## Options

    * `:hulls` — the boxes of hulls 1 and up, as `{mins, maxs}`, in the order the map
      was compiled with; hull 0, the point hull, is built from the nodes. Default `[]`
    * `:texture` — `fun(name, mips)` returning the texture entry for `Cauldron3D.Bsp`'s
      `textures` (`%{name:, kind:, mips:}` and whatever else the game keeps), given the
      lower-case name and the four mips; the mips are `[]` for a texture the map names but
      does not hold, which the game finds elsewhere (a `BSP30` map's WAD3 files, say).
      Default: every texture `:solid`, a missing one a placeholder

  A face has a lightmap only when its texture's kind is `:solid`. Each model's bounds are
  the file's spread by one unit on every side, as Quake engines load them.
  """

  alias Cauldron3D.Bsp, as: World
  alias Cauldron3D.Bsp.Face
  alias Cauldron3D.Formats.Bsp.Lumps
  alias Cauldron3D.{Hull, Texture}

  @lumps [
    :entities,
    :planes,
    :textures,
    :vertices,
    :visibility,
    :nodes,
    :texinfo,
    :faces,
    :lighting,
    :clipnodes,
    :leaves,
    :marks,
    :edges,
    :surfedges,
    :models
  ]

  @doc "The world and entity text of a map file's bytes."
  @spec parse(binary(), keyword()) ::
          {:ok, %{bsp: World.t(), entities: String.t()}} | {:error, :not_a_map}
  def parse(data, opts \\ [])

  def parse(<<29::little-32, rest::binary>> = data, opts),
    do: {:ok, build(data, rest, :bsp29, opts)}

  def parse(<<"BSP2", rest::binary>> = data, opts), do: {:ok, build(data, rest, :bsp2, opts)}

  def parse(<<30::little-32, rest::binary>> = data, opts),
    do: {:ok, build(data, rest, :bsp30, opts)}

  def parse(_data, _opts), do: {:error, :not_a_map}

  @doc "A texture entry of kind `:solid`, the default for `:texture`; a placeholder when `mips` is `[]`."
  @spec solid(String.t(), [Texture.t()]) :: map()
  def solid(name, []), do: %{missing() | name: name}
  def solid(name, mips), do: %{name: name, kind: :solid, mips: mips}

  @doc "A placeholder texture entry: a checked square of colours 15 and 0."
  @spec missing() :: map()
  def missing do
    mips =
      for level <- 0..3 do
        size = Bitwise.bsr(16, level)

        pixels =
          for y <- 0..(size - 1),
              x <- 0..(size - 1),
              into: <<>>,
              do: <<if(rem(div(x * 4, size) + div(y * 4, size), 2) == 0, do: 15, else: 0)>>

        Texture.new(size, size, pixels)
      end

    %{name: "", kind: :solid, mips: mips}
  end

  defp build(data, header, :bsp30, opts) do
    data
    |> build(header, :bsp29, Keyword.put(opts, :palettes, true))
    |> put_in([:bsp, Access.key(:light_channels)], 3)
    |> put_in([:bsp, Access.key(:game)], :half_life)
  end

  defp build(data, header, layout, opts) do
    lumps = lumps(data, header)
    planes = lumps.planes |> Lumps.planes() |> List.to_tuple()
    nodes = lumps.nodes |> Lumps.nodes(layout) |> List.to_tuple()
    leaves = Lumps.leaves(lumps.leaves, layout)
    marks = lumps.marks |> Lumps.marks(layout) |> List.to_tuple()
    models = Lumps.models(lumps.models)

    textures =
      textures(
        lumps.textures,
        Keyword.get(opts, :texture, &solid/2),
        Keyword.get(opts, :palettes, false)
      )

    world = %World{
      planes: planes,
      nodes: nodes,
      leaves: leaves |> Enum.map(&leaf(&1, marks)) |> List.to_tuple(),
      faces: faces(lumps, layout, textures) |> List.to_tuple(),
      textures: textures,
      lightmaps: lumps.lighting,
      visibility: visibility(leaves, lumps.visibility, hd(models)),
      world_leaves: hd(models).visleafs,
      models:
        models
        |> Enum.map(&Map.take(&1, [:mins, :maxs, :origin, :heads, :first_face, :face_count]))
        |> Enum.map(&widened/1)
        |> List.to_tuple()
    }

    %{
      bsp: %{world | hulls: hulls(world, lumps.clipnodes, layout, Keyword.get(opts, :hulls, []))},
      entities: entities(lumps.entities)
    }
  end

  defp lumps(data, header) do
    entries =
      for <<offset::little-32, length::little-32 <- binary_part(header, 0, 15 * 8)>>,
        do: {offset, length}

    @lumps
    |> Enum.zip(entries)
    |> Map.new(fn {name, {offset, length}} -> {name, binary_part(data, offset, length)} end)
  end

  defp leaf(leaf, marks) do
    faces =
      if leaf.mark_count > 0,
        do:
          for(i <- leaf.first_mark..(leaf.first_mark + leaf.mark_count - 1), do: elem(marks, i)),
        else: []

    %{contents: leaf.contents, faces: faces, mins: leaf.mins, maxs: leaf.maxs}
  end

  defp faces(lumps, layout, textures) do
    vertices = lumps.vertices |> Lumps.vertices() |> List.to_tuple()
    edges = lumps.edges |> Lumps.edges(layout) |> List.to_tuple()
    surfedges = lumps.surfedges |> Lumps.surfedges() |> List.to_tuple()
    texinfo = lumps.texinfo |> Lumps.texinfo() |> List.to_tuple()

    for face <- Lumps.faces(lumps.faces, layout) do
      info = elem(texinfo, face.texinfo)
      kind = elem(textures, info.texture).kind

      %Face{
        plane: face.plane,
        back?: face.back?,
        points: points(face, edges, surfedges, vertices),
        texture: info.texture,
        s: info.s,
        t: info.t,
        lightmap: if(kind in [:solid, :masked], do: face.light),
        styles: face.styles
      }
      |> Face.measured()
    end
  end

  defp points(face, edges, surfedges, vertices) do
    for i <- face.first_edge..(face.first_edge + face.edge_count - 1) do
      case elem(surfedges, i) do
        edge when edge >= 0 -> elem(vertices, elem(elem(edges, edge), 0))
        edge -> elem(vertices, elem(elem(edges, -edge), 1))
      end
    end
  end

  defp textures(<<count::little-32, rest::binary>> = lump, texture, palettes?) do
    <<offsets::binary-size(^count * 4), _::binary>> = rest

    for <<offset::little-signed-32 <- offsets>> do
      if offset < 0,
        do: missing(),
        else: miptex(binary_part(lump, offset, byte_size(lump) - offset), texture, palettes?)
    end
    |> List.to_tuple()
  end

  defp textures(_lump, _texture, _palettes?), do: {}

  @doc """
  The name and four mips of a `miptex` record, as a map file or a WAD3 holds one; the mips
  are `[]` when the record names a texture without its pixels. With `palettes?`, the
  palette that follows the smallest mip is given to each.
  """
  @spec miptex(binary(), boolean()) :: {String.t(), [Texture.t()]} | :error
  def miptex(
        <<name::binary-16, width::little-32, height::little-32, offsets::binary-16, _::binary>> =
          data,
        palettes?
      )
      when width > 0 and height > 0 do
    name = name |> :binary.split(<<0>>) |> hd() |> String.downcase()
    offsets = for <<offset::little-32 <- offsets>>, do: offset

    if Enum.any?(offsets, &(&1 == 0)) do
      {name, []}
    else
      palette = if palettes?, do: palette(data, List.last(offsets), width, height)

      mips =
        for {offset, level} <- Enum.with_index(offsets) do
          {w, h} = {max(Bitwise.bsr(width, level), 1), max(Bitwise.bsr(height, level), 1)}
          mip(binary_part(data, offset, w * h), w, h, palette)
        end

      {name, mips}
    end
  end

  def miptex(_data, _palettes?), do: :error

  defp miptex(data, texture, palettes?) do
    case miptex(data, palettes?) do
      {name, mips} -> texture.(name, mips)
      :error -> missing()
    end
  end

  defp palette(data, last, width, height) do
    at = last + max(Bitwise.bsr(width, 3), 1) * max(Bitwise.bsr(height, 3), 1)

    case data do
      <<_::binary-size(^at), 256::little-16, colours::binary-768, _::binary>> -> colours
      _ -> nil
    end
  end

  defp mip(pixels, w, h, nil), do: Texture.new(w, h, pixels)
  defp mip(pixels, w, h, palette), do: Texture.new(w, h, pixels, palette)

  defp widened(%{mins: {x0, y0, z0}, maxs: {x1, y1, z1}} = model),
    do: %{model | mins: {x0 - 1, y0 - 1, z0 - 1}, maxs: {x1 + 1, y1 + 1, z1 + 1}}

  defp visibility(_leaves, <<>>, _world), do: nil

  defp visibility(leaves, lump, world) do
    bytes = div(world.visleafs + 7, 8)

    leaves
    |> Enum.map(fn
      %{vis: vis} when vis < 0 ->
        nil

      %{vis: vis} ->
        lump
        |> binary_part(vis, byte_size(lump) - vis)
        |> expand(bytes)
        |> shifted(div(world.visleafs + 8, 8))
    end)
    |> List.to_tuple()
  end

  defp expand(data, bytes), do: expand(data, bytes, [])

  defp expand(_data, left, acc) when left <= 0, do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp expand(<<0, run, rest::binary>>, left, acc),
    do: expand(rest, left - run, [:binary.copy(<<0>>, run) | acc])

  defp expand(<<byte, rest::binary>>, left, acc), do: expand(rest, left - 1, [<<byte>> | acc])
  defp expand(<<>>, left, acc), do: expand(<<>>, 0, [:binary.copy(<<0>>, left) | acc])

  defp shifted(bits, bytes) do
    bits
    |> binary_part(0, min(byte_size(bits), bytes))
    |> :binary.decode_unsigned(:little)
    |> Bitwise.bsl(1)
    |> :binary.encode_unsigned(:little)
    |> pad(bytes)
  end

  defp pad(bits, bytes) when byte_size(bits) >= bytes, do: binary_part(bits, 0, bytes)
  defp pad(bits, bytes), do: bits <> :binary.copy(<<0>>, bytes - byte_size(bits))

  defp hulls(world, clipnode_lump, layout, boxes) do
    clipnodes = clipnode_lump |> Lumps.clipnodes(layout) |> List.to_tuple()
    %{heads: [point_head | heads]} = elem(world.models, 0)
    origin = {0.0, 0.0, 0.0}

    point = %Hull{
      clipnodes: point_clipnodes(world),
      planes: world.planes,
      head: point_head,
      mins: origin,
      maxs: origin
    }

    sized =
      for {{mins, maxs}, head} <- Enum.zip(boxes, heads),
          do: %Hull{
            clipnodes: clipnodes,
            planes: world.planes,
            head: head,
            mins: mins,
            maxs: maxs
          }

    [point | sized]
  end

  defp point_clipnodes(world) do
    child = fn
      child when child >= 0 -> child
      child -> elem(world.leaves, -child - 1).contents
    end

    world.nodes
    |> Tuple.to_list()
    |> Enum.map(fn node -> {node.plane, child.(node.front), child.(node.back)} end)
    |> List.to_tuple()
  end

  defp entities(text), do: text |> :binary.split(<<0>>) |> hd()
end
