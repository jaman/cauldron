defmodule Cistern.Client do
  @moduledoc """
  What the terminal, the browser and the window need to put the game in front of a
  player: the `Cauldron2D.Client.Game` for Cistern.

      Drafter.run(Cauldron2D.Drafter.Client, props: %{game: Cistern.Client})

  The lobby lists the worlds `Cistern.Worlds.register/0` made known; without any, the
  game offers one world of the player's own.
  """

  @behaviour Cauldron2D.Client.Game

  alias Cauldron2D.Worlds
  alias Cistern.{Art, Game, Sound}

  @impl true
  def title, do: %{name: "CISTERN", tagline: "catch the rain"}

  @impl true
  def atlas, do: Art.install()

  @impl true
  def actions, do: [:left, :right]

  @impl true
  def keymaps do
    [
      arrows: %{left: [:left, :a], right: [:right, :d]},
      vi: %{left: [:h], right: [:l]}
    ]
  end

  @impl true
  def toggles, do: []

  @impl true
  def steering, do: [:left, :right]

  @impl true
  def worlds(_props) do
    case Worlds.list() do
      [] ->
        [
          %{
            id: :own,
            name: "A cistern of your own",
            world: {Game, [hz: 30]},
            players: 0,
            humans: []
          }
        ]

      worlds ->
        worlds
    end
  end

  @impl true
  def scene(view) do
    {width, height} = view.size
    floor = height - 1

    %{
      focus: {width / 2, height / 2},
      bounds: view.size,
      cell: fn {_x, y} -> if(y == floor, do: {:floor, [], nil}, else: {:sky, [], nil}) end,
      movers:
        Enum.flat_map(view.buckets, &bucket(&1, floor - 1.0)) ++
          Enum.map(view.drops, &{&1.kind, {&1.x / 1, &1.y}}),
      labels: Enum.map(view.buckets, &{&1.name, {&1.x, floor - 2.0}, name_colour(&1)})
    }
  end

  defp name_colour(%{robot?: true}), do: {170, 215, 245}
  defp name_colour(_bucket), do: {255, 240, 200}

  defp bucket(%{robot?: true} = held, row), do: halves(:bucket_robot, held, row)
  defp bucket(held, row), do: halves(:bucket, held, row)

  defp halves(art, %{x: x}, row), do: [{art, {x, row}}, {art, {x + 1, row}}]

  @impl true
  def hud(%{me: nil}), do: [["watching"]]

  def hud(%{me: me} = view) do
    [
      {:score, [{"caught #{me.score}", {255, 224, 120}}]},
      {:misses, [{"missed #{String.duplicate("x ", me.misses)}", {235, 110, 130}}]},
      {:drops, [{"#{length(view.drops)} in the air", nil}]}
    ]
  end

  @impl true
  def outcome(view), do: Game.outcome(view)

  @impl true
  def listener(%{me: nil}), do: nil
  def listener(%{me: me, size: {_width, height}}), do: {me.x + 1, height - 1.0}

  @impl true
  def sounds, do: &Sound.voice/1

  @impl true
  def music, do: Sound.pieces()

  @impl true
  def cue(%{drops: drops}, :play), do: Sound.cue(length(drops))
  def cue(_view, _screen), do: nil

  @impl true
  def guide do
    [
      {"the field",
       [
         %{art: :bucket, name: "bucket", text: "yours; the arrows or the pointer move it"},
         %{art: :drop, name: "drop", text: "worth one"},
         %{art: :drop_gold, name: "gold drop", text: "worth three"}
       ]}
    ]
  end
end
