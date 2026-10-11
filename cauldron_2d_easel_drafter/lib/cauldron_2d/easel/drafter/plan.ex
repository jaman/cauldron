defmodule Cauldron2D.Easel.Drafter.Plan do
  @moduledoc """
  A drafter widget that draws a sector document from above — walls, openings, the room
  in hand, the room being drawn, the eye — and reports the world point under a press.

      {:sector_plan, [id: :plan, doc: doc, view: %{center: {x, y}, scale: 0.5},
                      drafting: points, selected: sector_id, eye: eye, on_point: :point, flex: 1]}

  Each cell shows two pixels, one above the other. `scale` is pixels to a world unit.
  A press sends the application `{on_point, %{x: x, y: y}}` in world units, unsnapped.
  """

  use Drafter.Widget, handles: [:press]

  alias Cauldron2D.Easel.Sectors
  alias Cauldron2D.Sectors.Frame
  alias Drafter.Draw.Strip

  @black 0
  @wall 1
  @opening 2
  @selected 3
  @drafting 4
  @eye 5
  @grid 6

  defstruct [
    :doc,
    :on_point,
    :widget_id,
    :eye,
    view: %{center: {0.0, 0.0}, scale: 0.5},
    drafting: [],
    selected: nil,
    rect: nil
  ]

  @type t :: %__MODULE__{}

  @doc "The tag this widget answers to in a component tree: `:sector_plan`."
  @spec component_tag() :: atom()
  def component_tag, do: :sector_plan

  @doc false
  @spec from_component_opts(term(), keyword()) :: map()
  def from_component_opts(_args, opts) do
    opts
    |> Keyword.take([:doc, :view, :drafting, :selected, :eye, :on_point])
    |> Map.new()
    |> Map.put(:id, Keyword.get(opts, :__widget_id__))
  end

  @impl true
  def mount(props) do
    props = Map.new(props)

    struct(
      __MODULE__,
      Map.merge(Map.take(props, [:doc, :view, :drafting, :selected, :eye, :on_point]), %{
        widget_id: Map.get(props, :id)
      })
    )
  end

  @impl true
  def update(props, %__MODULE__{} = state),
    do:
      struct(
        state,
        Map.take(Map.new(props), [:doc, :view, :drafting, :selected, :eye, :on_point])
      )

  @doc false
  @spec on_rect_change(map(), t()) :: t()
  def on_rect_change(rect, %__MODULE__{} = state), do: %{state | rect: rect}

  @impl true
  def render(%__MODULE__{doc: nil}, rect), do: blank(rect)

  def render(%__MODULE__{} = state, rect) do
    width = max(rect.width, 1)
    height = max(rect.height, 1) * 2

    width
    |> Frame.new(height)
    |> Frame.fill(@black)
    |> Frame.lines(
      grid(state, {width, height}) ++
        walls(state, {width, height}) ++
        drafting(state, {width, height}) ++ eye(state, {width, height})
    )
    |> Frame.to_raster(palette())
    |> FrenchCurve.render(:cells, set: :half, background: {0, 0, 0})
    |> Enum.map(fn row -> row |> Strip.from_cells() |> Strip.fit_to_width(width) end)
  end

  defp blank(rect),
    do:
      List.duplicate(
        Strip.from_text(String.duplicate(" ", max(rect.width, 1))),
        max(rect.height, 1)
      )

  defp palette do
    colours = [
      {0, 0, 0},
      {220, 220, 230},
      {200, 170, 60},
      {230, 70, 60},
      {90, 220, 110},
      {120, 180, 255},
      {40, 44, 56}
    ]

    for {r, g, b} <- colours ++ List.duplicate({0, 0, 0}, 256 - length(colours)),
        into: <<>>,
        do: <<r, g, b>>
  end

  @doc "The world point at pixel `{px, py}` of a pane `size` pixels across."
  @spec world_at(map(), {number(), number()}, {number(), number()}) :: {float(), float()}
  def world_at(view, {px, py}, {width, height}) do
    {cx, cy} = view.center
    {cx + (px - width / 2) / view.scale, cy - (py - height / 2) / view.scale}
  end

  defp screen(view, {x, y}, {width, height}) do
    {cx, cy} = view.center
    {round(width / 2 + (x - cx) * view.scale), round(height / 2 - (y - cy) * view.scale)}
  end

  defp grid(state, size) do
    step = state.doc.grid * 4

    if step * state.view.scale < 6 do
      []
    else
      {x0, y1} = world_at(state.view, {0, 0}, size)
      {x1, y0} = world_at(state.view, size, size)

      for x <- range(x0, x1, step), y <- range(y0, y1, step) do
        {sx, sy} = screen(state.view, {x, y}, size)
        {sx, sy, sx, sy, @grid}
      end
    end
  end

  defp range(low, high, step),
    do:
      Stream.iterate(Float.floor(low / step) * step, &(&1 + step))
      |> Enum.take_while(&(&1 <= high))

  defp walls(state, size) do
    for {_id, line} <- state.doc.lines do
      {x0, y0} = screen(state.view, Map.fetch!(state.doc.vertices, line.from), size)
      {x1, y1} = screen(state.view, Map.fetch!(state.doc.vertices, line.to), size)
      {x0, y0, x1, y1, line_colour(line, state.selected)}
    end
  end

  defp line_colour(line, selected) do
    cond do
      selected != nil and
          (line.front.sector == selected or (line.back && line.back.sector == selected)) ->
        @selected

      line.back != nil ->
        @opening

      true ->
        @wall
    end
  end

  defp drafting(%{drafting: []}, _size), do: []

  defp drafting(state, size) do
    points = Enum.map(state.drafting, &screen(state.view, Sectors.snap(state.doc, &1), size))

    points
    |> Enum.zip(tl(points) ++ [hd(points)])
    |> Enum.map(fn {{x0, y0}, {x1, y1}} -> {x0, y0, x1, y1, @drafting} end)
  end

  defp eye(%{eye: nil}, _size), do: []

  defp eye(state, size) do
    %{x: x, y: y, angle: angle} = state.eye
    tip = {x + 24 * :math.cos(angle), y + 24 * :math.sin(angle)}
    {x0, y0} = screen(state.view, {x, y}, size)
    {x1, y1} = screen(state.view, tip, size)
    [{x0, y0, x1, y1, @eye}, {x0 - 1, y0, x0 + 1, y0, @eye}]
  end

  @impl true
  def handle_press(x, y, %__MODULE__{rect: rect} = state) when rect != nil do
    point =
      world_at(state.view, {x + 0.5, y * 2 + 1}, {max(rect.width, 1), max(rect.height, 1) * 2})

    if state.on_point && Drafter.AppRegistry.whereis() do
      Drafter.AppRegistry.send_to_loop(
        {:widget_action, state.widget_id,
         {:app_callback, state.on_point, %{x: elem(point, 0), y: elem(point, 1)}}}
      )
    end

    {:ok, state}
  end

  def handle_press(_x, _y, state), do: {:ok, state}
end
