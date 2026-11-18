defmodule Crossing.Client do
  @moduledoc """
  The terminal client for Crossing: the board, the frog and the hud.

      mix crossing
  """

  use Cauldron2D.Client.Game

  alias Crossing.{Art, Game, Lanes}

  @impl true
  def title, do: %{name: "CROSSING", tagline: "get to the far bank"}

  @impl true
  def atlas, do: Art.install()

  @impl true
  def actions, do: [:up, :down, :left, :right]

  @impl true
  def keymaps do
    [
      arrows: %{
        up: [:up, :w],
        down: [:down, :s],
        left: [:left, :a],
        right: [:right, :d]
      }
    ]
  end

  @impl true
  def worlds(_props) do
    [%{id: :crossing, name: "The crossing", world: {Game, []}, players: 0, humans: []}]
  end

  @impl true
  def start, do: {:play, :crossing}

  @impl true
  def look, do: %{projection: :top, zoom: 1}

  @impl true
  def scene(view), do: scene(view, %{})

  @impl true
  def scene(%{frog: {fx, fy}, lanes: lanes, snake: snake, elapsed: elapsed}, _look) do
    %{
      focus: {fx + 0.5, fy + 0.5},
      bounds: Game.size(),
      cell: &cell/1,
      eye: :frog,
      movers:
        Enum.flat_map(lanes, fn lane ->
          Enum.flat_map(Lanes.items(lane), fn edge ->
            for step <- 0..(lane.length - 1) do
              {art(lane, step, elapsed), {edge + step + 0.5, lane.row}, :east}
            end
          end)
        end) ++ if(visible_snake?(elapsed), do: [{:snake_0, {snake.x + 0.5, 6}, :east}], else: []),
      labels: []
    }
  end

  @impl true
  def hud(%{score: score, lives: lives, status: status, level: level, homes: homes}) do
    first = [
      {"level #{level}", {246, 238, 214}},
      {"   bank #{homes}/5", {150, 210, 150}},
      {"   score #{score}", {210, 190, 130}},
      {"   lives #{lives}", {210, 160, 120}}
    ]

    case status do
      :playing -> [first, [{"arrows or WASD to hop", {140, 150, 140}}]]
      :over -> [first, [{"over: ctrl-c twice to leave", {230, 130, 120}}]]
    end
  end

  defp visible_snake?(elapsed), do: :math.fmod(elapsed, 20.0) < 8.0

  defp art(lane, step, elapsed) when lane.row in 1..5 do
    if lane.kind == :turtle do
      if Lanes.surfaced?(lane, elapsed), do: :turtle_0, else: :turtle_under
    else
      segment(lane, step)
    end
  end

  defp art(lane, step, _elapsed), do: segment(lane, step)

  defp segment(lane, step) when lane.row in 1..5 do
    cond do
      step == 0 -> :log_left
      step == lane.length - 1 -> :log_right
      true -> :log_mid
    end
  end

  defp segment(lane, step), do: Enum.at(parts(kind(lane.row), lane.length, lane.dir), step)

  defp parts(kind, length, dir) do
    for step <- 0..(length - 1) do
      name = :"#{kind}_#{step}"
      if dir == 1, do: name, else: :"#{name}_w"
    end
  end

  defp kind(7), do: :car
  defp kind(8), do: :truck
  defp kind(9), do: :car
  defp kind(10), do: :bus
  defp kind(11), do: :truck

  defp cell(position) do
    case art(position) do
      :void -> :void
      art -> {art, [], nil}
    end
  end

  defp art({x, y}) when x < 0 or y < 0 or x > 14 or y > 12, do: :void
  defp art({x, 0}), do: if(rem(x, 3) == 1, do: :bank, else: :water_a)

  defp art({x, row}) when row in 1..5,
    do: if(rem(x + row, 2) == 0, do: :water_a, else: :water_b)

  defp art({_x, row}) when row in 7..11, do: :road
  defp art({x, y}), do: Enum.at([:grass_a, :grass_c, :grass_b], rem(x * 7 + y * 13, 3))
end
