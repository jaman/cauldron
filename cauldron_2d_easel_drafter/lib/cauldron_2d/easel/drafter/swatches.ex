defmodule Cauldron2D.Easel.Drafter.Swatches do
  @moduledoc """
  A drafter widget that draws a grid of colours, two cells a swatch, and reports the
  one the pointer pressed.

      {:easel_swatches, [id: :swatches, colours: rows, cursor: {3, 2}, on_pick: :swatch, flex: 1]}

  `colours` is rows of `{r, g, b}`; the swatch under `cursor` is marked. A press sends
  the application `{:swatch, %{x: column, y: row}}` as its `:on_pick` event.
  `chart/0` is a chart of hues by lightness with a row of greys, the grid a colour
  picker starts from.
  """

  use Drafter.Widget, handles: [:press]

  alias Drafter.Draw.{Segment, Strip}

  @hues 24
  @shades 8

  defstruct [:on_pick, :widget_id, colours: [], cursor: nil]

  @type t :: %__MODULE__{}

  @doc "The tag this widget answers to in a component tree: `:easel_swatches`."
  @spec component_tag() :: atom()
  def component_tag, do: :easel_swatches

  @doc false
  @spec from_component_opts(term(), keyword()) :: map()
  def from_component_opts(_args, opts) do
    opts
    |> Keyword.take([:colours, :cursor, :on_pick])
    |> Map.new()
    |> Map.put(:id, Keyword.get(opts, :__widget_id__))
  end

  @impl true
  def mount(props) do
    props = Map.new(props)

    %__MODULE__{
      colours: Map.get(props, :colours, []),
      cursor: Map.get(props, :cursor),
      on_pick: Map.get(props, :on_pick),
      widget_id: Map.get(props, :id)
    }
  end

  @impl true
  def update(props, %__MODULE__{} = state) do
    props = Map.new(props)

    %{
      state
      | colours: Map.get(props, :colours, state.colours),
        cursor: Map.get(props, :cursor, state.cursor),
        on_pick: Map.get(props, :on_pick, state.on_pick)
    }
  end

  @doc "Hues across by lightness down, #{@hues} by #{@shades}, then a row of greys."
  @spec chart() :: [[{byte(), byte(), byte()}]]
  def chart do
    shades =
      for shade <- 1..@shades,
          do: for(hue <- 0..(@hues - 1), do: hsl(hue * 360 / @hues, 0.85, shade / (@shades + 1)))

    greys = for step <- 0..(@hues - 1), do: grey(round(step * 255 / (@hues - 1)))
    shades ++ [greys]
  end

  defp grey(value), do: {value, value, value}

  @doc "An `{r, g, b}` from a hue in degrees, a saturation and a lightness, 0.0 to 1.0."
  @spec hsl(number(), number(), number()) :: {byte(), byte(), byte()}
  def hsl(hue, saturation, lightness) do
    c = (1 - abs(2 * lightness - 1)) * saturation
    h = :math.fmod(hue, 360) / 60
    x = c * (1 - abs(:math.fmod(h, 2) - 1))
    m = lightness - c / 2

    {r, g, b} =
      cond do
        h < 1 -> {c, x, 0}
        h < 2 -> {x, c, 0}
        h < 3 -> {0, c, x}
        h < 4 -> {0, x, c}
        h < 5 -> {x, 0, c}
        true -> {c, 0, x}
      end

    {round((r + m) * 255), round((g + m) * 255), round((b + m) * 255)}
  end

  @impl true
  def render(%__MODULE__{} = state, rect) do
    state.colours
    |> Enum.with_index()
    |> Enum.map(fn {row, y} ->
      row
      |> Enum.with_index()
      |> Enum.map(fn {colour, x} ->
        Segment.new(mark(state.cursor, {x, y}), %{bg: colour, fg: contrast(colour)})
      end)
      |> Strip.new()
      |> Strip.fit_to_width(max(rect.width, 1))
    end)
    |> Enum.take(max(rect.height, 1))
    |> pad(rect)
  end

  defp mark({x, y}, {x, y}), do: "[]"
  defp mark(_cursor, _cell), do: "  "

  defp contrast({r, g, b}), do: if(r + g + b > 380, do: {0, 0, 0}, else: {255, 255, 255})

  defp pad(strips, rect) do
    strips ++
      List.duplicate(
        Strip.new([Segment.new(String.duplicate(" ", max(rect.width, 1)), %{})]),
        max(rect.height - length(strips), 0)
      )
  end

  @impl true
  def handle_press(x, y, %__MODULE__{} = state) do
    if state.on_pick && Drafter.AppRegistry.whereis() do
      Drafter.AppRegistry.send_to_loop(
        {:widget_action, state.widget_id, {:app_callback, state.on_pick, %{x: div(x, 2), y: y}}}
      )
    end

    {:ok, state}
  end
end
