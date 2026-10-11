defmodule Cauldron2D.Projection.Volume.Native do
  @moduledoc """
  The per-pixel half of `Cauldron2D.Projection.Volume`, in C.

  `tint/6` takes a rectangle of pixels, the rays that look through it and one volume,
  and gives the rectangle back with the volume's colour blended in. It understands the
  shapes of `Cauldron2D.Projection.Volume.Shapes` and nothing else; a volume with a
  shape module of its own is drawn in Elixir.

  `available?/0` says whether the library built and loaded. Where it did not, `Volume`
  draws every volume in Elixir and answers the same picture some fifteen times slower.
  """

  @on_load :load_nif

  @doc false
  def load_nif do
    "volume_nif"
    |> Cauldron2D.Native.path()
    |> :erlang.load_nif(0)
    |> then(&:persistent_term.put({__MODULE__, :native}, &1 == :ok))
  end

  @doc "Whether the library is loaded and volumes are drawn in C."
  @spec available?() :: boolean()
  def available?, do: :persistent_term.get({__MODULE__, :native}, false)

  @doc """
  `pixels`, a `width` by `height` rectangle of RGBA, with `volume` blended in.

  `plan` is `{origin, origin_x, origin_y, direction, direction_x, direction_y}`, each a
  triple, giving the ray through the rectangle's pixel `{column, row}` as
  `origin + column * origin_x + row * origin_y` looking along
  `direction + column * direction_x + row * direction_y`.

  `limits` is one native float per pixel, how far that pixel can see before something
  opaque stops it, or an empty binary for no limit.

  `volume` is `{kind, falloff, {x, y}, {red, green, blue}, {strength, density,
  thickness}, params, cells}`, where `params` is the shape's numbers as native doubles
  and `cells` is `nil` or `{x, y, width, height, bits}`, one byte per tile.
  """
  @spec tint(binary(), pos_integer(), pos_integer(), tuple(), binary(), tuple()) :: binary()
  def tint(_pixels, _width, _height, _plan, _limits, _volume),
    do: :erlang.nif_error(:not_loaded)
end
