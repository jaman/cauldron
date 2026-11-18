defmodule Beast.Client do
  @moduledoc """
  The `Cauldron.Client.Game` for the beast's journey: its own title and summary
  (`Beast.Title`, `Beast.Summary`), its pause menu, and the regions and hud in its own
  art and font (`Beast.Scene`).

      mix beast

  The arrows (or A and D) run, Up or W jumps, Down or S ducks, Space strikes (hold it
  after a jab for a heavy blow; ducking, it strikes low), X rolls, Escape rests. On a
  controller the d-pad or left stick runs, `A` (or up on the d-pad) jumps, `X` strikes,
  `B` rolls, `Y` (or down on the d-pad) ducks and `Start` rests.
  """

  use Cauldron2D.Client.Game

  alias Beast.{Art, Game, Menus, Scene, Sound, Summary, Title}

  @impl true
  def title, do: %{name: "BEAST", tagline: "a journey across four lands"}

  @impl true
  def atlas, do: Art.install()

  @impl true
  def actions, do: [:left, :right, :jump, :attack, :dodge, :duck]

  @impl true
  def keymaps do
    [
      arrows: %{
        left: [:left],
        right: [:right],
        jump: [:up],
        duck: [:down],
        attack: [:" "],
        dodge: [:x]
      },
      wasd: %{left: [:a], right: [:d], jump: [:w], duck: [:s], attack: [:j], dodge: [:k]}
    ]
  end

  @impl true
  def holds, do: Enum.map(actions(), &{&1, 120})

  @impl true
  def start, do: {:play, :journey, title: true}

  @impl true
  def fronts(_props), do: %{title: Title, summary: Summary}

  @impl true
  def look, do: %{projection: :top, projections: [:top], zoom: 2}

  @impl true
  def chat?, do: false

  @impl true
  def options, do: %{shake: true, initials: "AAA"}

  @impl true
  def client_keys,
    do: %{
      {:look, :boxes?} => :b,
      menu: :escape,
      back: nil,
      title: nil,
      pause: nil,
      settings: nil
    }

  @impl true
  def worlds(_props),
    do: [%{id: :journey, name: "The journey", world: {Game, [hz: 50]}, players: 0, humans: []}]

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
  def listener(%{me: me}), do: {me.body.x, me.body.y}

  @impl true
  def audio, do: [rate: 48_000]

  @impl true
  def sounds, do: &Sound.voice/1

  @impl true
  def music, do: Sound.pieces()

  @impl true
  def cue(%{boss: boss}, :play) when boss != nil, do: Sound.cue(:boss)
  def cue(%{region: %{id: id}}, :play), do: Sound.cue(id)
  def cue(_view, _screen), do: Sound.cue(:title)
end
