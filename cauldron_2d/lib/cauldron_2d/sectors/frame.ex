defmodule Cauldron2D.Sectors.Frame do
  @moduledoc """
  An indexed-colour picture drawn a column, a plane or a line at a time — the drawing a
  sector view does — and turned into RGBA through a palette at the end.

      frame =
        Frame.new(320, 200)
        |> Frame.fill(0)
        |> Frame.columns(pictures, [Frame.column(x, {top, bottom}, wall, {texel_x, v, step}, light)])
        |> Frame.plane(pictures, plane, tops, bottoms)

      Frame.to_raster(frame, palette)

  Every drawing call takes a frame and gives one back, and the frame given back is the one
  to keep drawing on. Where the NIF loaded the frame is drawn on in place, so a frame must
  be drawn on by one process at a time, and an earlier value of it is the same frame.

  ## Columns

  `column/6` describes one vertical run of pixels at screen column `x` from row `top` to row
  `bottom`, filled from the picture at `{texel_x, v, step}`: from picture column `texel_x`,
  row `top` reading the picture at row `v` and each row below `step` further on. The texel goes through light table `light`. A
  plain column wraps both its picture column and its rows, as a wall texture repeats. With
  `masked: true` neither wraps — rows outside the picture and transparent texels are
  skipped — which is how a sprite is drawn. With `shimmer: true` the column draws no texels:
  each pixel takes the colour of a pixel a row above or below it already on the frame,
  through `light`, for a figure seen as a blur.

  ## Planes

  `plane/5` fills, column by column, the rows between `tops` and `bottoms` with a
  horizontal plane seen in perspective: a floor or a ceiling at `height` above the eye
  (negative below it), textured with its picture tiled across the world one texel per
  unit, its world `x` along the picture's columns and its world `-y` along the rows.
  Each pixel's light table is `start - floor(fade / distance)`, clamped to the tables, or
  `fixed` where that is not `-1`. With `sky: true` the plane is not perspective at all: the
  picture is wrapped around the view, `sky_columns` picture columns per radian of
  heading, its rows from `sky_mid` at the horizon down by `sky_step` a pixel, drawn
  through `fixed`'s table or table `0`.

  The view a plane is drawn for is `x`, `y` and `angle` (radians, `0` along `+x`, the world's
  `+y` up and to the left of the screen) with the eye at screen `center_x`, `center_y`, and
  `focal_x`, `focal_y` the distances in pixels at which one world unit spans one pixel
  across and down.

  `available?/0` says whether the NIF loaded; where it did not, every call draws the same
  picture in Elixir, many times slower.
  """

  alias Cauldron2D.Sectors.Pictures
  alias FrenchCurve.Raster

  @on_load :load_nif

  @enforce_keys [:width, :height]
  defstruct [:width, :height, :native, :pixels]

  @type t :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          native: reference() | nil,
          pixels: binary() | nil
        }

  @type plane :: %{
          required(:x1) => non_neg_integer(),
          required(:x2) => non_neg_integer(),
          required(:picture) => non_neg_integer(),
          required(:height) => number(),
          required(:x) => number(),
          required(:y) => number(),
          required(:angle) => number(),
          required(:center_x) => number(),
          required(:center_y) => number(),
          required(:focal_x) => number(),
          required(:focal_y) => number(),
          optional(:sky) => boolean(),
          optional(:start) => integer(),
          optional(:fade) => number(),
          optional(:fixed) => integer(),
          optional(:sky_columns) => number(),
          optional(:sky_mid) => number(),
          optional(:sky_step) => number()
        }

  @doc false
  def load_nif do
    "sector_nif"
    |> Cauldron2D.Native.path()
    |> :erlang.load_nif(0)
    |> then(&:persistent_term.put({__MODULE__, :native}, &1 == :ok))
  end

  @doc "Whether the NIF is loaded and drawing is done in C."
  @spec available?() :: boolean()
  def available?, do: :persistent_term.get({__MODULE__, :native}, false)

  @doc "A frame of `width` by `height`, every pixel colour `0`. `native: false` draws it in Elixir."
  @spec new(pos_integer(), pos_integer(), keyword()) :: t()
  def new(width, height, opts \\ []) when width > 0 and height > 0 do
    if Keyword.get(opts, :native, true) and available?(),
      do: %__MODULE__{width: width, height: height, native: native_new(width, height)},
      else: %__MODULE__{width: width, height: height, pixels: :binary.copy(<<0>>, width * height)}
  end

  @doc "Every pixel set to `colour`."
  @spec fill(t(), byte()) :: t()
  def fill(%__MODULE__{native: nil} = frame, colour),
    do: %{frame | pixels: :binary.copy(<<colour>>, frame.width * frame.height)}

  def fill(%__MODULE__{native: ref} = frame, colour) do
    native_fill(ref, colour)
    frame
  end

  @doc """
  One column for `columns/3`. Options: `masked: true`, `shimmer: true`; see the moduledoc.
  """
  @spec column(
          integer(),
          {integer(), integer()},
          non_neg_integer(),
          {integer(), number(), number()},
          non_neg_integer(),
          keyword()
        ) :: binary()
  def column(x, {top, bottom}, picture, {texel_x, v, step}, light, opts \\ []) do
    flags = flag(opts, :masked, 1) + flag(opts, :shimmer, 2)

    <<x::16-little, top::16-little-signed, bottom::16-little-signed, flags::16-little,
      picture::32-little-signed, texel_x::32-little-signed, light::16-little, 0::16,
      v * 1.0::float-64-little, step * 1.0::float-64-little>>
  end

  defp flag(opts, key, bit), do: if(Keyword.get(opts, key, false), do: bit, else: 0)

  @doc "The columns, as `column/6` made them, drawn in order: a list or one binary of them."
  @spec columns(t(), Pictures.t(), iodata()) :: t()
  def columns(%__MODULE__{native: nil} = frame, pictures, records) do
    records
    |> IO.iodata_to_binary()
    |> each_column(frame, pictures)
  end

  def columns(%__MODULE__{native: ref} = frame, %Pictures{native: set}, records) do
    native_columns(ref, set, IO.iodata_to_binary(records))
    frame
  end

  @doc "A plane, as the moduledoc describes, between `tops` and `bottoms`: one row each per column from `x1` to `x2`."
  @spec plane(t(), Pictures.t(), plane(), [integer()], [integer()]) :: t()
  def plane(frame, pictures, plane, tops, bottoms) do
    plane =
      Map.merge(
        %{
          sky: false,
          start: 0,
          fade: 0.0,
          fixed: -1,
          sky_columns: 0.0,
          sky_mid: 0.0,
          sky_step: 1.0
        },
        plane
      )

    count = plane.x2 - plane.x1 + 1

    if count < 1 or length(tops) != count or length(bottoms) != count,
      do:
        raise(
          ArgumentError,
          "a plane needs one top and one bottom for each of its #{count} columns"
        )

    drawn_plane(frame, pictures, plane, tops, bottoms)
  end

  defp drawn_plane(%__MODULE__{native: nil} = frame, pictures, plane, tops, bottoms),
    do: elixir_plane(frame, pictures, plane, tops, bottoms)

  defp drawn_plane(%__MODULE__{native: ref} = frame, %Pictures{native: set}, plane, tops, bottoms) do
    native_plane(ref, set, plane_params(plane), rows(tops), rows(bottoms))
    frame
  end

  defp rows(values),
    do: for(value <- values, into: <<>>, do: <<clamp16(value)::16-little-signed>>)

  defp clamp16(value), do: value |> max(-32_768) |> min(32_767)

  defp plane_params(plane) do
    sky = if plane.sky, do: 1, else: 0

    head =
      <<plane.x1::16-little, plane.x2::16-little, sky::16-little, 0::16,
        plane.picture::32-little-signed, plane.start::32-little-signed,
        plane.fixed::32-little-signed, 0::32, 0::32>>

    floats =
      for value <- [
            plane.fade,
            plane.height,
            plane.x,
            plane.y,
            plane.angle,
            plane.center_x,
            plane.center_y,
            plane.focal_x,
            plane.focal_y,
            plane.sky_columns,
            plane.sky_mid,
            plane.sky_step
          ],
          into: <<>>,
          do: <<value * 1.0::float-64-little>>

    head <> floats
  end

  @doc "Straight lines, `[{x0, y0, x1, y1, colour}]`, end points included and clipped to the frame."
  @spec lines(t(), [{integer(), integer(), integer(), integer(), byte()}]) :: t()
  def lines(%__MODULE__{native: nil} = frame, lines), do: elixir_lines(frame, lines)

  def lines(%__MODULE__{native: ref} = frame, lines) do
    records =
      for {x0, y0, x1, y1, colour} <- lines, into: <<>> do
        <<clamp16(x0)::16-little-signed, clamp16(y0)::16-little-signed,
          clamp16(x1)::16-little-signed, clamp16(y1)::16-little-signed, colour, 0>>
      end

    native_lines(ref, records)
    frame
  end

  @doc "The frame's colour indexes, row by row."
  @spec pixels(t()) :: binary()
  def pixels(%__MODULE__{native: nil, pixels: pixels}), do: pixels
  def pixels(%__MODULE__{native: ref}), do: native_pixels(ref)

  @doc "The frame as RGBA through `palette`, 256 colours of three bytes each."
  @spec rgba(t(), binary()) :: binary()
  def rgba(%__MODULE__{native: nil, pixels: pixels}, palette) when byte_size(palette) == 768,
    do:
      for(<<index <- pixels>>,
        into: <<>>,
        do: <<:binary.part(palette, index * 3, 3)::binary, 255>>
      )

  def rgba(%__MODULE__{native: ref}, palette) when byte_size(palette) == 768,
    do: native_rgba(ref, palette)

  @doc "The frame as a raster through `palette`."
  @spec to_raster(t(), binary()) :: Raster.t()
  def to_raster(frame, palette),
    do: Raster.from_rgba(frame.width, frame.height, rgba(frame, palette))

  @doc false
  def native_new(_width, _height), do: :erlang.nif_error(:not_loaded)
  @doc false
  def native_set(_pictures, _tables), do: :erlang.nif_error(:not_loaded)
  @doc false
  def native_fill(_frame, _colour), do: :erlang.nif_error(:not_loaded)
  @doc false
  def native_columns(_frame, _set, _records), do: :erlang.nif_error(:not_loaded)
  @doc false
  def native_plane(_frame, _set, _params, _tops, _bottoms), do: :erlang.nif_error(:not_loaded)
  @doc false
  def native_lines(_frame, _records), do: :erlang.nif_error(:not_loaded)
  @doc false
  def native_pixels(_frame), do: :erlang.nif_error(:not_loaded)
  @doc false
  def native_rgba(_frame, _palette), do: :erlang.nif_error(:not_loaded)
  @doc false
  def native_size(_frame), do: :erlang.nif_error(:not_loaded)

  defp each_column(records, frame, pictures) do
    writes =
      for <<x::16-little, top::16-little-signed, bottom::16-little-signed, flags::16-little,
            picture::32-little-signed, texel_x::32-little-signed, light::16-little, _pad::16,
            v::float-64-little, step::float-64-little <- records>>,
          reduce: %{} do
        written ->
          elixir_column(
            written,
            frame,
            pictures,
            {x, top, bottom, flags, picture, texel_x, light, v, step}
          )
      end

    applied(frame, writes)
  end

  defp elixir_column(
         written,
         frame,
         pictures,
         {x, top, bottom, flags, picture, texel_x, light, v, step}
       ) do
    masked? = Bitwise.band(flags, 1) == 1
    shimmer? = Bitwise.band(flags, 2) == 2

    with true <-
           x >= 0 and x < frame.width and picture >= 0 and picture < Pictures.count(pictures),
         %{width: width} = pic <- elem(pictures.pictures, picture),
         {:ok, column} <- picture_column(texel_x, width, masked?) do
      {v, top} = if top < 0, do: {v + step * (0 - top), 0}, else: {v, top}
      bottom = min(bottom, frame.height - 1)
      table = clamp(light, 0, pictures.maps - 1) * 256

      Enum.reduce(top..bottom//1, {written, v}, fn y, {acc, row_v} ->
        {texel_write(
           acc,
           frame,
           pictures,
           pic,
           column,
           {x, y, row_v},
           {masked?, shimmer?, table}
         ), row_v + step}
      end)
      |> elem(0)
    else
      _skipped -> written
    end
  end

  defp picture_column(texel_x, width, true) when texel_x < 0 or texel_x >= width, do: :skip
  defp picture_column(texel_x, _width, true), do: {:ok, texel_x}
  defp picture_column(texel_x, width, false), do: {:ok, wrap(texel_x, width)}

  defp texel_write(acc, frame, pictures, pic, column, {x, y, v}, {masked?, shimmer?, table}) do
    row = floor(v)

    cond do
      masked? and hole?(pic, column, row) ->
        acc

      shimmer? ->
        near = clamp(y + shimmer(x, y), 0, frame.height - 1)
        source = read(acc, frame, near * frame.width + x)
        Map.put(acc, y * frame.width + x, :binary.at(pictures.tables, table + source))

      true ->
        row = if masked?, do: row, else: wrap(row, pic.height)
        texel = :binary.at(pic.pixels, column * pic.height + row)
        Map.put(acc, y * frame.width + x, :binary.at(pictures.tables, table + texel))
    end
  end

  defp hole?(pic, _column, row) when row < 0 or row >= pic.height, do: true
  defp hole?(%{mask: nil}, _column, _row), do: false
  defp hole?(pic, column, row), do: :binary.at(pic.mask, column * pic.height + row) == 0

  defp shimmer(x, y) do
    hash = Bitwise.band((x * 7 + y) * 2_654_435_761, 0xFFFFFFFF)
    if Bitwise.band(Bitwise.bsr(hash, 16), 1) == 1, do: 1, else: -1
  end

  defp read(written, frame, index),
    do: Map.get_lazy(written, index, fn -> :binary.at(frame.pixels, index) end)

  defp applied(frame, writes) when map_size(writes) == 0, do: frame

  defp applied(%__MODULE__{pixels: pixels} = frame, writes) do
    sorted = writes |> Map.to_list() |> List.keysort(0)
    %{frame | pixels: splice(pixels, sorted, 0, [])}
  end

  defp splice(pixels, [], at, acc),
    do: IO.iodata_to_binary(Enum.reverse([binary_part(pixels, at, byte_size(pixels) - at) | acc]))

  defp splice(pixels, [{index, byte} | rest], at, acc),
    do: splice(pixels, rest, index + 1, [<<byte>>, binary_part(pixels, at, index - at) | acc])

  defp elixir_plane(frame, _pictures, %{picture: picture}, _tops, _bottoms)
       when picture < 0,
       do: frame

  defp elixir_plane(frame, pictures, plane, tops, bottoms) do
    if plane.picture >= Pictures.count(pictures) do
      frame
    else
      pic = elem(pictures.pictures, plane.picture)

      writes =
        [tops, bottoms]
        |> Enum.zip()
        |> Enum.with_index(plane.x1)
        |> Enum.reduce(%{}, fn {{top, bottom}, x}, acc ->
          plane_column(
            acc,
            frame,
            pictures,
            plane,
            pic,
            x,
            {max(top, 0), min(bottom, frame.height - 1)}
          )
        end)

      applied(frame, writes)
    end
  end

  defp plane_column(acc, frame, _pictures, _plane, _pic, x, {top, bottom})
       when x < 0 or x >= frame.width or top > bottom,
       do: acc

  defp plane_column(acc, frame, pictures, %{sky: true} = plane, pic, x, {top, bottom}) do
    angle = plane.angle + :math.atan2(plane.center_x - (x + 0.5), plane.focal_x)
    column = wrap(floor(angle * plane.sky_columns), pic.width)
    table = clamp(if(plane.fixed >= 0, do: plane.fixed, else: 0), 0, pictures.maps - 1) * 256

    Enum.reduce(top..bottom, acc, fn y, written ->
      row = wrap(floor(plane.sky_mid + (y + 0.5 - plane.center_y) * plane.sky_step), pic.height)
      texel = :binary.at(pic.pixels, column * pic.height + row)
      Map.put(written, y * frame.width + x, :binary.at(pictures.tables, table + texel))
    end)
  end

  defp plane_column(acc, frame, pictures, plane, pic, x, {top, bottom}) do
    {forward_x, forward_y} = {:math.cos(plane.angle), :math.sin(plane.angle)}
    {right_x, right_y} = {:math.sin(plane.angle), -:math.cos(plane.angle)}
    across = (x + 0.5 - plane.center_x) / plane.focal_x

    Enum.reduce(top..bottom, acc, fn y, written ->
      dy = y + 0.5 - plane.center_y
      distance = if abs(dy) < 1.0e-9, do: 0.0, else: -plane.height * plane.focal_y / dy

      if distance <= 0.0 do
        written
      else
        world_x = plane.x + forward_x * distance + right_x * distance * across
        world_y = plane.y + forward_y * distance + right_y * distance * across
        u = wrap(floor(world_x), pic.width)
        v = wrap(floor(-world_y), pic.height)
        light = plane_light(plane, distance, pictures.maps)
        texel = :binary.at(pic.pixels, u * pic.height + v)
        Map.put(written, y * frame.width + x, :binary.at(pictures.tables, light * 256 + texel))
      end
    end)
  end

  defp plane_light(%{fixed: fixed}, _distance, _maps) when fixed >= 0, do: fixed

  defp plane_light(plane, distance, maps),
    do: clamp(plane.start - floor(plane.fade / max(distance, 1.0)), 0, maps - 1)

  defp elixir_lines(frame, lines) do
    writes =
      Enum.reduce(lines, %{}, fn {x0, y0, x1, y1, colour}, acc ->
        bresenham(acc, frame, {x0, y0}, {x1, y1}, colour)
      end)

    applied(frame, writes)
  end

  defp bresenham(acc, frame, {x0, y0}, {x1, y1}, colour) do
    dx = abs(x1 - x0)
    dy = -abs(y1 - y0)
    step = {if(x0 < x1, do: 1, else: -1), if(y0 < y1, do: 1, else: -1)}
    trace(acc, frame, {x0, y0}, {x1, y1}, {dx, dy, dx + dy}, step, colour, 0)
  end

  defp trace(acc, frame, {x, y} = at, finish, {dx, dy, err}, {sx, sy} = step, colour, guard) do
    acc = plot(acc, frame, at, colour)

    if at == finish or guard > 65_536 do
      acc
    else
      e2 = 2 * err
      {x, err} = if e2 >= dy, do: {x + sx, err + dy}, else: {x, err}
      {y, err} = if e2 <= dx, do: {y + sy, err + dx}, else: {y, err}
      trace(acc, frame, {x, y}, finish, {dx, dy, err}, step, colour, guard + 1)
    end
  end

  defp plot(acc, frame, {x, y}, _colour)
       when x < 0 or y < 0 or x >= frame.width or y >= frame.height,
       do: acc

  defp plot(acc, frame, {x, y}, colour), do: Map.put(acc, y * frame.width + x, colour)

  defp wrap(value, size) do
    case rem(value, size) do
      result when result < 0 -> result + size
      result -> result
    end
  end

  defp clamp(value, low, _high) when value < low, do: low
  defp clamp(value, _low, high) when value > high, do: high
  defp clamp(value, _low, _high), do: value
end
