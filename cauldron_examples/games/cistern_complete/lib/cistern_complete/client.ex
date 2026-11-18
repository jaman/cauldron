defmodule CisternComplete.Client do
  @moduledoc """
  The `Cauldron.Client.Game` for Cistern finished: its own title and summary
  (`CisternComplete.Title`, `CisternComplete.Summary`), its own pause menu, the square
  and its hud drawn in the game's own art and font (`CisternComplete.Scene`).

      mix cistern_complete

  The arrows or A and D walk, Down or S pours, Escape pauses.
  """

  use Cauldron2D.Client.Game

  alias CisternComplete.{Art, Game, Menus, Scene, Sound, Summary, Title}

  @impl true
  def title, do: %{name: "CISTERN", tagline: "the town is dry, and a storm has come"}

  @impl true
  def atlas, do: Art.install()

  @impl true
  def actions, do: [:left, :right, :pour]

  @impl true
  def keymaps do
    [
      arrows: %{left: [:left], right: [:right], pour: [:down, :" "]},
      wasd: %{left: [:a], right: [:d], pour: [:s, :" "]}
    ]
  end

  @impl true
  def holds, do: [{:left, 120}, {:right, 120}, {:pour, 120}]

  @impl true
  def steering, do: [:left, :right]

  @impl true
  def start, do: {:play, :solo, title: true}

  @impl true
  def fronts(_props), do: %{title: Title, summary: Summary}

  @impl true
  def look, do: %{projection: :top, projections: [:top], zoom: 2}

  @impl true
  def chat?, do: false

  @impl true
  def options, do: %{flashing: true, initials: "AAA"}

  @impl true
  def client_keys, do: %{menu: :escape, back: nil, title: nil, pause: nil, settings: nil}

  @impl true
  def worlds(_props) do
    [
      %{id: :solo, name: "A square of your own", world: {Game, [hz: 30]}, players: 0, humans: []},
      %{
        id: :versus,
        name: "Versus the robot",
        world: :cistern_complete_versus,
        players: 0,
        humans: []
      }
    ]
  end

  @impl true
  def scene(view, look), do: view |> Scene.build(look) |> calm(look)

  defp calm(scene, %{options: %{flashing: false}}), do: Map.put(scene, :volumes, [])
  defp calm(scene, _look), do: scene

  @impl true
  def open_menu(settings), do: Menus.pause(settings)

  @impl true
  def menu_event(menu, event, settings), do: Cauldron.Menu.event(menu, event, settings)

  @impl true
  def outcome(view), do: Game.outcome(view)

  @impl true
  def listener(%{me: nil}), do: nil
  def listener(%{me: me}), do: {me.offset + me.yoke.centre, 10}

  @impl true
  def audio, do: [rate: 48_000]

  @impl true
  def sounds, do: &Sound.voice/1

  @impl true
  def music, do: Sound.pieces()

  @impl true
  def cue(%{me: %{level: level}}, :play), do: Sound.cue(level)
  def cue(_view, _screen), do: Sound.cue(:title)
end
