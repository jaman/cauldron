defmodule Cauldron2D.Parallax.Layer do
  @moduledoc """
  One depth of a parallax background.

      Cauldron2D.Parallax.Layer.new(
        name: :mountains,
        cell: Cauldron2D.Parallax.Strip.cells(rows, wrap: :x),
        factor: {0.25, 0.1},
        drift: {-0.4, 0.0}
      )

  `factor` is the share of the camera's distance from `origin` the layer moves: `1.0` moves
  with the world, `0.0` is pinned, above `1.0` is nearer than the world. `drift` is tiles a
  second the layer moves on its own, through the same arithmetic as `factor`.

  `movers` and `volumes` are in the layer's own tiles, either a list or a function of the
  layer's visible rectangle, `{{origin_x, origin_y}, {columns, rows}}`.

  `void` decides what an empty tile is: `:transparent` lets the layers behind show through,
  `:opaque` fills with the atlas's void colour, which is what the backmost layer wants.

  `front: true` puts the layer over the world rather than behind it. `animated: true` lets
  art with frames animate, redrawn `fps` times a second. `cache: false` redraws the layer
  every frame, which a layer whose movers move needs.
  """

  alias Cauldron2D.Parallax.Bands

  @type mover :: {term(), {number(), number()}} | {term(), {number(), number()}, number()}
  @type rect :: {{integer(), integer()}, {pos_integer(), pos_integer()}}
  @type pair :: {float(), float()}

  @type t :: %__MODULE__{
          name: atom(),
          cell: ({integer(), integer()} -> term()),
          movers: [mover()] | (rect() -> [mover()]),
          volumes: list() | (rect() -> list()),
          factor: pair(),
          drift: pair(),
          origin: pair(),
          void: :transparent | :opaque,
          picture: map() | nil,
          bands: Bands.t() | nil,
          front: boolean(),
          animated: boolean(),
          cache: boolean(),
          fps: pos_integer()
        }

  @enforce_keys [:name, :cell]
  defstruct [
    :name,
    :cell,
    :bands,
    :picture,
    movers: [],
    volumes: [],
    factor: {1.0, 1.0},
    drift: {0.0, 0.0},
    origin: {0.0, 0.0},
    void: :transparent,
    front: false,
    animated: false,
    cache: true,
    fps: 10
  ]

  @doc "A layer from `opts`, which must give `:name` and `:cell`."
  @spec new(keyword()) :: t()
  def new(opts) do
    layer = struct!(__MODULE__, opts)

    %{
      layer
      | factor: pair(layer.factor, :factor),
        drift: pair(layer.drift, :drift),
        origin: pair(layer.origin, :origin)
    }
    |> validate()
  end

  @doc "Where this layer is looked at from, for a world focus and a time in milliseconds."
  @spec focus(t(), {number(), number()}, number()) :: pair()
  def focus(%__MODULE__{} = layer, {fx, fy}, at) do
    {ox, oy} = layer.origin
    {px, py} = layer.factor
    {dx, dy} = layer.drift
    seconds = at / 1000

    {ox + (fx - ox) * px + dx * seconds, oy + (fy - oy) * py + dy * seconds}
  end

  @doc "The layer's movers for a visible rectangle."
  @spec movers(t(), rect()) :: [mover()]
  def movers(%__MODULE__{movers: movers}, rect) when is_function(movers, 1), do: movers.(rect)
  def movers(%__MODULE__{movers: movers}, _rect), do: movers

  @doc "The layer's volumes for a visible rectangle."
  @spec volumes(t(), rect()) :: list()
  def volumes(%__MODULE__{volumes: volumes}, rect) when is_function(volumes, 1),
    do: volumes.(rect)

  def volumes(%__MODULE__{volumes: volumes}, _rect), do: volumes

  defp pair({x, y}, _field) when is_number(x) and is_number(y), do: {x / 1, y / 1}
  defp pair(value, field) when is_number(value), do: pair({value, value}, field)

  defp pair(value, field),
    do: raise(ArgumentError, ":#{field} must be a number or a pair, got #{inspect(value)}")

  defp validate(%__MODULE__{void: void}) when void not in [:transparent, :opaque],
    do: raise(ArgumentError, ":void must be :transparent or :opaque")

  defp validate(%__MODULE__{cell: cell}) when not is_function(cell, 1),
    do: raise(ArgumentError, ":cell must be a function of one argument")

  defp validate(%__MODULE__{} = layer), do: layer
end
