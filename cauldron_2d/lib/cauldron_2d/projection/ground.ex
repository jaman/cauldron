defmodule Cauldron2D.Projection.Ground do
  @moduledoc """
  Samples a textured ground plane in perspective: for each pixel below the horizon the
  world point it looks at, the tile there, and that tile's texel, faded towards a void
  colour with distance.

      Cauldron2D.Projection.Ground.rows(%{
        grid: grid,
        size: {320, 200},
        tile: 16,
        camera: camera,
        void: {24, 30, 58},
        levels: 6,
        sky: sky
      })

  A `grid` is the world made into data the sampler can read without calling back into
  Elixir: `build_grid/3` turns a `fn {x, y} -> cell end` and a bounding box into one.

  The work is done by a NIF where one built and in Elixir where it did not; `available?/0`
  says which. The two answer the same picture but not always the same bytes: a pixel whose
  world point falls within a last-bit rounding of a texel boundary may take the neighbouring
  texel, so a handful of pixels a frame can differ, by one level of one channel. Where a
  tile's texture is one colour the two are identical.
  """

  @on_load :load_nif

  @type camera :: {
          float(),
          float(),
          float(),
          float(),
          float(),
          float(),
          float(),
          float(),
          float(),
          float(),
          float()
        }

  @type grid :: %{
          cells: binary(),
          bounds: {pos_integer(), pos_integer(), integer(), integer()},
          textures: binary()
        }

  @doc false
  def load_nif do
    :cauldron_2d
    |> :code.priv_dir()
    |> Path.join("plane_nif")
    |> to_charlist()
    |> :erlang.load_nif(0)
    |> case do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  @doc "Whether the NIF is loaded and the sampling is done in C."
  @spec available?() :: boolean()
  def available?, do: false

  @doc """
  The picture's rows as a map of row index to that row's pixels, the rows at and above
  the horizon taken from `sky` and the rest sampled from the plane.

  Takes `:grid`, `:size`, `:tile`, `:camera`, `:void`, `:levels` and `:sky`, where `sky`
  is a tuple of one four-byte pixel per row. `native: false` samples in Elixir even where
  the NIF loaded, which is how the two are checked against each other.
  """
  @spec rows(map()) :: %{non_neg_integer() => binary()}
  def rows(%{size: {width, height}} = spec) do
    {_fx, _fy, _dx, _dy, _rx, _ry, horizon, _projection, _vertical, _eye, _range} = spec.camera
    plane = sampled(spec)

    Map.new(0..(height - 1)//1, fn y ->
      if y <= horizon,
        do: {y, :binary.copy(elem(spec.sky, y), width)},
        else: {y, binary_part(plane, y * width * 4, width * 4)}
    end)
  end

  @doc """
  A grid of tile indices for `cell` over the box `{left, top, right, bottom}` in tiles,
  with the textures the indices point at.

  `arts` maps an art to its one-based index; a tile the map does not answer for, or whose
  art is not in `arts`, is `0` and drawn as the void.
  """
  @spec build_grid(
          ({integer(), integer()} -> term()),
          {integer(), integer(), integer(), integer()},
          %{
            optional(term()) => pos_integer()
          }
        ) :: {binary(), {pos_integer(), pos_integer(), integer(), integer()}}
  def build_grid(cell, {left, top, right, bottom}, arts) do
    width = right - left + 1
    height = bottom - top + 1

    cells =
      for y <- top..bottom//1, x <- left..right//1, into: <<>> do
        <<index_of(cell.({x, y}), arts)::unsigned-integer-size(16)>>
      end

    {cells, {width, height, left, top}}
  end

  defp index_of(:void, _arts), do: 0
  defp index_of({base, _overlays, _tint}, arts), do: Map.get(arts, base, 0)
  defp index_of(_cell, _arts), do: 0

  defp sampled(%{native: false} = spec), do: in_elixir(spec)
  defp sampled(spec), do: if(available?(), do: native(spec), else: in_elixir(spec))

  defp native(%{grid: grid, size: size, tile: tile, camera: camera} = spec),
    do: plane(grid.cells, grid.bounds, grid.textures, tile, size, camera, spec.void, spec.levels)

  @doc false
  def plane(_cells, _bounds, _textures, _tile, _size, _camera, _void, _levels),
    do: :erlang.nif_error(:not_loaded)

  defp in_elixir(%{size: {width, height}} = spec) do
    {fx, fy, dx, dy, rx, ry, horizon, projection, vertical, eye, range} = spec.camera
    {red, green, blue} = spec.void
    empty = <<red, green, blue, 255>>
    blank = :binary.copy(<<0, 0, 0, 0>>, width)

    for y <- 0..(height - 1)//1, into: <<>> do
      if y <= horizon do
        blank
      else
        depth = eye * vertical / (y - horizon)
        fog = min(spec.levels, trunc(max(depth, 0) / range * spec.levels))
        step = depth / projection

        row(spec, %{
          far?: depth > range,
          mix: fog / spec.levels,
          step: {rx * step, ry * step},
          from:
            {fx + dx * depth - rx * width / 2 * step, fy + dy * depth - ry * width / 2 * step},
          empty: empty,
          width: width
        })
      end
    end
  end

  defp row(_spec, %{far?: true, empty: empty, width: width}), do: :binary.copy(empty, width)

  defp row(spec, %{step: {sx, sy}, from: from, width: width} = plane) do
    {pixels, _point} =
      Enum.map_reduce(0..(width - 1)//1, from, fn _x, {wx, wy} ->
        {texel(spec, plane, {wx, wy}), {wx + sx, wy + sy}}
      end)

    IO.iodata_to_binary(pixels)
  end

  defp texel(spec, %{empty: empty, mix: mix}, {wx, wy}) do
    floor_x = :math.floor(wx)
    floor_y = :math.floor(wy)

    case at(spec.grid, trunc(floor_x), trunc(floor_y)) do
      0 ->
        empty

      index ->
        tile = spec.tile
        column = clamp(trunc((wx - floor_x) * tile), tile - 1)
        row = clamp(trunc((wy - floor_y) * tile), tile - 1)
        offset = ((index - 1) * tile * tile + row * tile + column) * 4

        if offset + 4 <= byte_size(spec.grid.textures),
          do: faded(binary_part(spec.grid.textures, offset, 4), empty, mix),
          else: empty
    end
  end

  defp faded(<<_, _, _, alpha>> = texel, _empty, _mix) when alpha < 128, do: texel

  defp faded(<<red, green, blue, _>>, <<fog_red, fog_green, fog_blue, _>>, mix) do
    <<channel(red, fog_red, mix), channel(green, fog_green, mix), channel(blue, fog_blue, mix),
      255>>
  end

  defp channel(value, fog, mix),
    do: value |> Kernel.+((fog - value) * mix) |> round() |> min(255) |> max(0)

  defp clamp(value, high), do: value |> min(high) |> max(0)

  defp at(%{cells: cells, bounds: {width, height, x0, y0}}, wx, wy) do
    column = wx - x0
    row = wy - y0

    if column < 0 or row < 0 or column >= width or row >= height do
      0
    else
      <<index::unsigned-integer-size(16)>> =
        binary_part(cells, (row * width + column) * 2, 2)

      index
    end
  end
end
