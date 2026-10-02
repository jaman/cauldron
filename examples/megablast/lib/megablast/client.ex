defmodule Megablast.Client do
  @moduledoc """
  The `Cauldron2D.Client.Game` for the lane: a vertical shooter flown up a rock corridor
  under four parallax layers.

      mix megablast

  Left and right steer and bank the ship, up and down move it along the lane, space fires,
  `^Q` quits. Flying to the bottom of the pane holds the view back rather than running off
  it, and braking lights the retro flame. Every pod collected adds a drone that fires with
  the ship; taking a hit loses them again.

  The nebula creeps at a tenth of the lane's pace, the starfield at a third and the coral
  at under two thirds, while a haze of dust streaks past in front half again faster.
  """

  @behaviour Cauldron2D.Client.Game

  alias Megablast.{Art, Game, Lane, Music, Scenery}

  @lift 3.0

  @impl true
  def title, do: %{name: "MEGABLAST", tagline: "down the chitin lane"}

  @impl true
  def atlas, do: Art.install()

  @impl true
  def actions, do: [:left, :right, :thrust, :brake, :fire]

  @impl true
  def keymaps do
    [
      arrows: %{left: [:left], right: [:right], thrust: [:up], brake: [:down], fire: [:" "]},
      wasd: %{left: [:a], right: [:d], thrust: [:w], brake: [:s], fire: [:" "]}
    ]
  end

  @impl true
  def toggles, do: []

  @impl true
  def holds, do: Enum.map(actions(), &{&1, 120})

  @impl true
  def start, do: {:play, :lane}

  @impl true
  def look, do: %{projection: :top, projections: [:top], zoom: 2}

  @impl true
  def chat?, do: false

  @impl true
  def lobby?, do: false

  @impl true
  def worlds(_props) do
    [%{id: :lane, name: "The chitin lane", world: {Game, [hz: 50]}, players: 0, humans: []}]
  end

  @impl true
  def scene(%{me: nil} = view) do
    %{
      focus: {Lane.middle(view.lane), view.depth + @lift},
      bounds: :unbounded,
      cell: Lane.cells(view.lane),
      movers: traffic(view),
      layers: Scenery.layers()
    }
  end

  def scene(%{me: me} = view) do
    %{
      focus: {Lane.middle(view.lane), view.depth + @lift},
      bounds: :unbounded,
      cell: Lane.cells(view.lane),
      movers: traffic(view) ++ ship(me, view.addon_reach),
      layers: Scenery.layers(),
      subject: :ship
    }
  end

  @impl true
  def hud(%{me: nil}), do: [["watching"]]

  def hud(%{me: me}) do
    [
      [{"MEGABLAST", {200, 220, 255}}],
      ["shield ", {String.duplicate("▮", me.shields), {64, 200, 255}}],
      ["drones ", {String.duplicate("◆", me.addons), {64, 255, 160}}],
      ["score  ", {Integer.to_string(me.score), {255, 200, 96}}]
    ]
  end

  @impl true
  def listener(%{me: nil}), do: nil
  def listener(%{me: me}), do: {me.x, me.y}

  @impl true
  def sounds, do: fn _event -> nil end

  @impl true
  def music do
    case Music.piece() do
      nil -> []
      piece -> [piece]
    end
  end

  @impl true
  def cue(_view, :play), do: Music.cue()
  def cue(_view, _screen), do: nil

  defp traffic(view) do
    Enum.map(view.turrets, &{Art.turret(&1.open?), {&1.x / 1, &1.y / 1}}) ++
      Enum.map(view.flak, &{:flak, {&1.x, &1.y}}) ++
      Enum.map(view.shots, &{:shot, {&1.x, &1.y}}) ++
      Enum.map(view.foes, &{&1.kind, {&1.x, &1.y}}) ++
      Enum.flat_map(view.others, &ship(&1, view.addon_reach))
  end

  defp ship(pilot, reach) do
    drones = Enum.map(Game.addons(pilot, reach), fn {x, y} -> {:addon, {x, y}} end)

    drones ++ retro(pilot) ++ [{Art.ship(pilot.bank), {pilot.x, pilot.y}}]
  end

  defp retro(%{braking?: true} = pilot), do: [{:retro, {pilot.x, pilot.y - 1.3}}]
  defp retro(_pilot), do: []
end
