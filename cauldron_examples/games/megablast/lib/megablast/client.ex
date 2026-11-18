defmodule Megablast.Client do
  @moduledoc """
  The `Cauldron.Client.Game` for the lane: its own title and summary
  (`Megablast.Title`, `Megablast.Summary`), its pause menu, and the lane and hud in its
  own art and font (`Megablast.Scene`).

      mix megablast

  The arrows (or WASD) steer and move up and down, Space fires, B bombs, Escape pauses.
  In the shop, Up and Down choose and Space buys.
  """

  use Cauldron2D.Client.Game

  alias Megablast.{Art, Game, Menus, Scene, Sound, Summary, Title}

  @impl true
  def title, do: %{name: "MEGABLAST", tagline: "five stages up the living lane"}

  @impl true
  def atlas, do: Art.install()

  @impl true
  def actions, do: [:left, :right, :thrust, :brake, :fire, :bomb]

  @impl true
  def keymaps do
    [
      arrows: %{
        left: [:left],
        right: [:right],
        thrust: [:up],
        brake: [:down],
        fire: [:" "],
        bomb: [:b]
      },
      wasd: %{left: [:a], right: [:d], thrust: [:w], brake: [:s], fire: [:" "], bomb: [:e]}
    ]
  end

  @impl true
  def holds, do: Enum.map(actions(), &{&1, 120})

  @impl true
  def start, do: {:play, :lane, title: true}

  @impl true
  def fronts(_props), do: %{title: Title, summary: Summary}

  @impl true
  def look, do: %{projection: :top, projections: [:top], zoom: 2}

  @impl true
  def chat?, do: false

  @impl true
  def options, do: %{shake: true, initials: "AAA"}

  @impl true
  def client_keys, do: %{menu: :escape, back: nil, title: nil, pause: nil, settings: nil}

  @impl true
  def worlds(_props),
    do: [%{id: :lane, name: "The living lane", world: {Game, [hz: 50]}, players: 0, humans: []}]

  @impl true
  def scene(view, look) do
    view = if get_in(look, [:options, :shake]) == false, do: %{view | shake: 0.0}, else: view
    Scene.build(view, look)
  end

  @impl true
  def open_menu(settings), do: Menus.pause(settings)

  @impl true
  def menu_event(menu, event, settings), do: Cauldron.Menu.event(menu, event, settings)

  @impl true
  def outcome(view), do: Game.outcome(view)

  @impl true
  def listener(%{me: nil}), do: nil
  def listener(%{me: me}), do: {me.x, me.y}

  @impl true
  def audio, do: [rate: 48_000]

  @impl true
  def sounds, do: &Sound.voice/1

  @impl true
  def music, do: Sound.pieces()

  @impl true
  def cue(%{phase: phase}, :play) when phase in [:boss, :shop], do: Sound.cue(phase)
  def cue(%{stage: stage}, :play), do: Sound.cue(stage.number)
  def cue(_view, _screen), do: Sound.cue(:title)
end
