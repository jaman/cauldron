defmodule Cauldron2D.Easel.Drafter.Canvas do
  @moduledoc """
  A drafter widget that draws an easel's frame zoomed, every pixel a block of cells in
  its colour, and reports where the pointer paints.

      {:easel_canvas, [id: :canvas, easel: easel, zoom: 4, on_paint: :paint, flex: 1]}

  A pixel is `zoom` cells wide and half as many tall, so it stays square; transparent
  pixels show a checkerboard. With `:onion` the frame before the one in hand shows
  faintly under it. A press or a drag over a pixel sends the application
  `{:paint, %{x: x, y: y, phase: :start | :drag | :end}}` as its `:on_paint` event.
  """

  use Drafter.Widget, handles: [:press, :drag, :mouse_up]

  alias Cauldron2D.Easel
  alias Drafter.Draw.{Segment, Strip}

  @checker {{40, 40, 48}, {56, 56, 66}}

  defstruct [:easel, :on_paint, :widget_id, zoom: 4, onion: false, rect: nil]

  @type t :: %__MODULE__{}

  @doc "The tag this widget answers to in a component tree: `:easel_canvas`."
  @spec component_tag() :: atom()
  def component_tag, do: :easel_canvas

  @doc false
  @spec from_component_opts(term(), keyword()) :: map()
  def from_component_opts(_args, opts) do
    opts
    |> Keyword.take([:easel, :zoom, :onion, :on_paint])
    |> Map.new()
    |> Map.put(:id, Keyword.get(opts, :__widget_id__))
  end

  @impl true
  def mount(props) do
    props = Map.new(props)

    %__MODULE__{
      easel: Map.get(props, :easel),
      zoom: Map.get(props, :zoom, 4),
      onion: Map.get(props, :onion, false),
      on_paint: Map.get(props, :on_paint),
      widget_id: Map.get(props, :id)
    }
  end

  @impl true
  def update(props, %__MODULE__{} = state) do
    props = Map.new(props)

    %{
      state
      | easel: Map.get(props, :easel, state.easel),
        zoom: Map.get(props, :zoom, state.zoom),
        onion: Map.get(props, :onion, state.onion),
        on_paint: Map.get(props, :on_paint, state.on_paint)
    }
  end

  @doc false
  @spec on_rect_change(map(), t()) :: t()
  def on_rect_change(rect, %__MODULE__{} = state), do: %{state | rect: rect}

  @doc "The cells a pixel takes, `{columns, rows}`, at `zoom`."
  @spec cell_size(pos_integer()) :: {pos_integer(), pos_integer()}
  def cell_size(zoom), do: {max(2, zoom), max(1, div(zoom, 2))}

  @doc "The largest zoom at which `{width, height}` pixels fit in `{columns, rows}` cells, at least 2."
  @spec fit(Easel.t(), {pos_integer(), pos_integer()}) :: pos_integer()
  def fit(%Easel{width: width, height: height}, {columns, rows}) do
    Enum.max([2, min(div(columns, width), div(rows * 2, height)) |> div(2) |> Kernel.*(2)])
  end

  @impl true
  def render(%__MODULE__{easel: nil}, rect), do: blank(rect)

  def render(%__MODULE__{easel: easel} = state, rect) do
    {columns, rows} = cell_size(state.zoom)
    frame = Enum.at(easel.frames, easel.frame)
    under = if state.onion and easel.frame > 0, do: Enum.at(easel.frames, easel.frame - 1)

    for y <- 0..(easel.height - 1)//1, _row <- 1..rows//1 do
      for x <- 0..(easel.width - 1)//1 do
        Segment.new(String.duplicate(" ", columns), %{bg: colour_of(easel, frame, under, {x, y})})
      end
      |> Strip.new()
      |> Strip.fit_to_width(max(rect.width, 1))
    end
    |> Enum.take(max(rect.height, 1))
    |> pad(rect)
  end

  defp blank(rect),
    do:
      List.duplicate(
        Strip.new([Segment.new(String.duplicate(" ", max(rect.width, 1)), %{})]),
        max(rect.height, 1)
      )

  defp pad(strips, rect) do
    strips ++
      List.duplicate(
        Strip.new([Segment.new(String.duplicate(" ", max(rect.width, 1)), %{})]),
        max(rect.height - length(strips), 0)
      )
  end

  defp colour_of(easel, frame, under, {x, y}) do
    case {elem(elem(frame, y), x), under && elem(elem(under, y), x)} do
      {".", nil} -> checker({x, y})
      {".", "."} -> checker({x, y})
      {".", ghost} -> easel |> Easel.colour(ghost) |> over(checker({x, y}), 0.35)
      {key, _} -> easel |> Easel.colour(key) |> over(checker({x, y}), 1.0)
    end
  end

  defp checker({x, y}), do: if(rem(x + y, 2) == 0, do: elem(@checker, 0), else: elem(@checker, 1))

  defp over(nil, beneath, _strength), do: beneath

  defp over({r, g, b, a}, {br, bg, bb}, strength) do
    share = a / 255 * strength

    {round(r * share + br * (1 - share)), round(g * share + bg * (1 - share)),
     round(b * share + bb * (1 - share))}
  end

  @impl true
  def handle_press(x, y, state), do: report(state, x, y, :start)

  @impl true
  def handle_drag(x, y, state), do: report(state, x, y, :drag)

  @impl true
  def handle_mouse_up(x, y, state), do: report(state, x, y, :end)

  defp report(%__MODULE__{easel: nil} = state, _x, _y, _phase), do: {:ok, state}

  defp report(%__MODULE__{} = state, x, y, phase) do
    {columns, rows} = cell_size(state.zoom)
    pixel = %{x: div(x, columns), y: div(y, rows), phase: phase}

    if state.on_paint && Drafter.AppRegistry.whereis() do
      Drafter.AppRegistry.send_to_loop(
        {:widget_action, state.widget_id, {:app_callback, state.on_paint, pixel}}
      )
    end

    {:ok, state}
  end
end
