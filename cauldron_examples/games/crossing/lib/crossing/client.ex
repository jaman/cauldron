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
  def look, do: %{projection: :top}

  @impl true
  def scene(view), do: scene(view, %{})

  @impl true
  def scene(%{frog: frog, lanes: lanes}, _look) do
    {width, height} = Game.size()

    %{
      focus: {width / 2, height / 2},
      bounds: Game.size(),
      cell: &cell/1,
      eye: {:frog, frog, :east},
      movers:
        Enum.flat_map(lanes, fn lane ->
          Enum.flat_map(Lanes.items(lane), fn edge ->
            for step <- 0..(lane.length - 1) do
              {segment(lane, step), {edge + step + 0.5, lane.row}, :east}
            end
          end)
        end),
      labels: []
    }
  end

  @impl true
  def hud(%{score: score, lives: lives, status: status}) do
    first = [
      {"score #{score}", {246, 238, 214}},
      {"   lives #{lives}", {150, 210, 150}}
    ]

    case status do
      :playing -> [first, [{"arrows or WASD to hop", {140, 150, 140}}]]
      :over -> [first, [{"over: ctrl-c twice to leave", {230, 130, 120}}]]
    end
  end

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

  defp cell({x, 0}), do: if(rem(x, 3) == 1, do: :bank, else: :water_a)

  defp cell({x, row}) when row in 1..5,
    do: if(rem(x + row, 2) == 0, do: :water_a, else: :water_b)

  defp cell({_x, row}) when row in 7..11, do: :road
  defp cell({x, y}), do: Enum.at([:grass_a, :grass_c, :grass_b], rem(x * 7 + y * 13, 3))
end
