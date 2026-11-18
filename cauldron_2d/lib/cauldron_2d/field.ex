defmodule Cauldron2D.Field do
  @moduledoc """
  A fixed play field: a rectangle of a top-down world that is always shown whole, scaled
  to the largest size the pane allows with its shape kept, and centred between bars of
  the atlas's void colour.

  A game chooses how its world meets the window. A scene without a `:field` is open: a
  larger pane shows more of the world around the focus. A scene with a `:field` is fixed:
  a larger pane shows the same tiles larger.

      def scene(view) do
        %{cell: &cell/1, movers: movers(view), field: {15, 13}}
      end

  `:field` is `{width, height}` in tiles from the world's origin, or
  `{left, top, width, height}`. It applies to the top-down projection; in the other
  projections the scene is drawn as an open one around its `:focus`.

  `scene/3` turns a fixed scene into a `:picture` scene the front ends already draw: its
  `:picture` composes the field at the atlas's own pixels and letterboxes it into the
  size it is asked for, its `:native` and `:frame` are the field's size in pixels, and
  its `:focus` is the field's centre. The scene's `:screen` and `:outlines` are drawn
  inside the field. `world_at/2` maps a point of the frame back to the world.
  """

  alias Cauldron2D.{Atlas, Draw, Fit, Raster, Surface}

  @type t :: {number(), number()} | {number(), number(), number(), number()}
  @type rect :: {number(), number(), number(), number()}

  @doc "The field as `{left, top, width, height}` in tiles."
  @spec rect(t()) :: rect()
  def rect({width, height}), do: {0, 0, width, height}
  def rect({_left, _top, _width, _height} = rect), do: rect

  @doc "The centre of the field, in tiles."
  @spec centre(t()) :: {float(), float()}
  def centre(field) do
    {left, top, width, height} = rect(field)
    {left + width / 2, top + height / 2}
  end

  @doc "The field's size in pixels at the atlas's own tile size."
  @spec pixels(Atlas.name(), t()) :: {pos_integer(), pos_integer()}
  def pixels(atlas, field) do
    tile = Atlas.fetch(atlas).tile
    {_left, _top, width, height} = rect(field)
    {max(1, round(width * tile)), max(1, round(height * tile))}
  end

  @doc """
  Whether `scene` is drawn as a fixed field: it names a `:field`, has no `:picture` of its
  own, and is seen in `projection` `:top`.
  """
  @spec fixed?(map(), atom()) :: boolean()
  def fixed?(scene, projection),
    do: projection == :top and Map.get(scene, :field) != nil and Map.get(scene, :picture) == nil

  @doc """
  `scene` as a `:picture` scene showing its field, when `fixed?/2` holds; the scene
  unchanged otherwise. Applying it to its own result changes nothing.
  """
  @spec scene(map(), Atlas.name(), atom()) :: map()
  def scene(scene, atlas, projection) do
    if fixed?(scene, projection), do: pictured(scene, atlas), else: scene
  end

  @doc """
  The world point under `point`, a point of the frame as fractions of its width and
  height, for a scene `scene/3` made into a picture; `point` itself for any other scene,
  and `nil` for `nil` (the bars around the frame).
  """
  @spec world_at({number(), number()} | nil, map()) :: {float(), float()} | nil
  def world_at(nil, _scene), do: nil

  def world_at({u, v}, %{field: field, picture: picture}) when picture != nil do
    {left, top, width, height} = rect(field)
    {left + u * width, top + v * height}
  end

  def world_at(point, _scene), do: point

  @doc """
  `raster` scaled to the largest size that fits `{width, height}` pixels, each `aspect`
  times as wide as tall, with its shape kept, centred on a raster of that size filled
  with `void`. Scaling is nearest-pixel, and a whole-number scale repeats pixels exactly.
  """
  @spec letterbox(Raster.t(), {pos_integer(), pos_integer()}, number(), Atlas.rgb()) ::
          Raster.t()
  def letterbox(raster, {width, height} = size, aspect, void) do
    {x, y, fitted_width, fitted_height} =
      Fit.letterbox(size, 1 / aspect, Raster.dimensions(raster))

    scaled = resized(raster, {fitted_width, fitted_height})
    pixel = void_pixel(void)
    rgba = Raster.to_rgba_binary(scaled)
    line = :binary.copy(pixel, width)
    left = :binary.copy(pixel, x)
    right = :binary.copy(pixel, width - x - fitted_width)
    stride = fitted_width * 4

    rows =
      for <<row::binary-size(^stride) <- rgba>>, do: [left, row, right]

    Raster.from_rgba(
      width,
      height,
      IO.iodata_to_binary([
        List.duplicate(line, y),
        rows,
        List.duplicate(line, height - y - fitted_height)
      ])
    )
  end

  defp pictured(scene, atlas) do
    field = Map.fetch!(scene, :field)
    native = pixels(atlas, field)
    void = Atlas.fetch(atlas).void
    {_left, _top, width, height} = rect(field)

    view =
      Draw.new(
        atlas: atlas,
        focus: centre(field),
        cell: Map.get(scene, :cell),
        movers: Map.get(scene, :movers, []),
        labels: Map.get(scene, :labels, []),
        screen: Map.get(scene, :screen, []),
        outlines: Map.get(scene, :outlines, []),
        volumes: Map.get(scene, :volumes, []),
        layers: Map.get(scene, :layers, [])
      )

    draw = fn size, aspect ->
      view
      |> Draw.top_down({width, height}, 1, System.monotonic_time(:millisecond))
      |> letterbox(size, aspect, void)
    end

    Map.merge(scene, %{
      focus: centre(field),
      picture: draw,
      native: native,
      frame: native,
      screen: [],
      outlines: []
    })
  end

  defp resized(raster, size) do
    case {Raster.dimensions(raster), size} do
      {same, same} ->
        raster

      {{width, height}, {fitted_width, fitted_height}}
      when rem(fitted_width, width) == 0 and
             fitted_width * height == fitted_height * width ->
        Surface.magnify(raster, div(fitted_width, width))

      {from, to} ->
        nearest(raster, from, to)
    end
  end

  defp nearest(raster, {width, height}, {fitted_width, fitted_height}) do
    rgba = Raster.to_rgba_binary(raster)
    stride = width * 4
    offsets = for x <- 0..(fitted_width - 1), do: div((2 * x + 1) * width, 2 * fitted_width) * 4

    rows =
      for y <- 0..(fitted_height - 1) do
        row = binary_part(rgba, div((2 * y + 1) * height, 2 * fitted_height) * stride, stride)
        for offset <- offsets, into: <<>>, do: binary_part(row, offset, 4)
      end

    Raster.from_rgba(fitted_width, fitted_height, IO.iodata_to_binary(rows))
  end

  defp void_pixel({red, green, blue}), do: <<red, green, blue, 255>>
  defp void_pixel({red, green, blue, alpha}), do: <<red, green, blue, alpha>>
end
