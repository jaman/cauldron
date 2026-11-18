defmodule Cistern.Client do
  @moduledoc """
  What the terminal, the browser and the window need to put the game in front of a
  player: the `Cauldron.Client.Game` for Cistern.

      mix cistern

  The lobby lists the worlds `Cistern.Worlds.register/0` made known; without any, the
  game offers one world of the player's own.
  """

  use Cauldron2D.Client.Game

  alias Cauldron.Worlds
  alias Cistern.{Art, Field, Game, Sound}

  @gold {255, 214, 110}
  @water {120, 200, 255}
  @clay {217, 128, 74}
  @dim {110, 96, 120}

  @impl true
  def title, do: %{name: "CISTERN", tagline: "the town is dry, and a storm has come"}

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
  def steering, do: [:left, :right]

  @impl true
  def worlds(_props) do
    case Worlds.list() do
      [] ->
        [
          %{
            id: :own,
            name: "A square of your own",
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
  def scene(%{me: nil, size: {width, height} = size}) do
    %{focus: {width / 2, height / 2}, bounds: size, cell: &cell/1, movers: []}
  end

  def scene(%{me: me, size: {width, height} = size}) do
    %{
      focus: {width / 2, height / 2},
      bounds: size,
      cell: &cell/1,
      movers: shadows(me) ++ squall(me) ++ keeper(me) ++ drops(me) ++ splashes(me),
      labels: pops(me) ++ storm_label(me)
    }
  end

  @doc "What is drawn at a tile of the square: sky by height, the town's roofs and walls, the cobbles."
  @spec cell({integer(), integer()}) :: {atom(), [], nil}
  def cell({x, y}) do
    %{ground: ground, keeper: keeper} = Field.rows()

    art =
      cond do
        y >= ground -> :ground
        y == keeper -> Enum.at([:walls_a, :walls_c, :walls_b], pick(x, 3))
        y == keeper - 1 -> Enum.at([:roofs_a, :roofs_b, :roofs_c], pick(x, 3))
        y >= 7 -> :sky_low
        y == 6 -> :sky_dusk_b
        y >= 4 -> :sky_mid
        y == 3 -> :sky_dusk_a
        true -> Enum.at([:sky_high_a, :sky_high_b, :sky_high_c, :sky_high_d], pick({x, y}, 4))
      end

    {art, [], nil}
  end

  defp pick(at, count), do: :erlang.phash2(at, count)

  defp shadows(me) do
    ground = Field.rows().ground
    for drop <- me.drops, do: {shadow(drop.y), {drop.x - 0.5, ground}}
  end

  defp shadow(y) when y < 5, do: :shadow_far
  defp shadow(y) when y < 8, do: :shadow_mid
  defp shadow(_y), do: :shadow_near

  defp squall(%{squall: squall}) do
    art = if squall.mood == :grin, do: :squall_grin, else: :squall
    [{art, {squall.x - 0.5, Field.rows().squall}}]
  end

  defp keeper(me) do
    %{keeper: row, head: head} = Field.rows()

    {keeper, side, top} =
      if me.robot?,
        do: {:keeper_robot, :jar_robot, :jar_head_robot},
        else: {:keeper, :jar, :jar_head}

    [{keeper, {me.centre - 0.5, row}}] ++
      for jar <- Field.jars(me) do
        if jar.slot == :head, do: {top, {jar.x, head}}, else: {side, {jar.x, row}}
      end
  end

  defp drops(me), do: for(drop <- me.drops, do: {:drop, {drop.x - 0.5, drop.y}})

  defp splashes(me) do
    for splash <- me.splashes,
        do:
          {Enum.at([:splash_1, :splash_2, :splash_3], Cauldron.Effects.frame(splash, 3, 7.5)),
           {splash.x - 0.5, 10}}
  end

  defp pops(me),
    do: for(pop <- me.pops, do: {pop.text, {pop.x - 0.25, pop.y - pop.age * 1.5}, @gold})

  defp storm_label(%{lull: lull, level: level}) when lull > 0,
    do: [{"STORM #{level}", {6.6, 3.2}, @gold, [scale: 2]}]

  defp storm_label(_me), do: []

  @impl true
  def hud(%{me: nil}), do: [["watching"]]

  def hud(%{me: me, rivals: rivals}) do
    jars = Field.most_jars()

    [
      {:storm,
       [
         {"STORM #{me.level}", @gold},
         "     jars ",
         {String.duplicate("● ", Field.jar_count(me)), @clay},
         {String.duplicate("○ ", jars - Field.jar_count(me)), @dim}
       ]},
      {:score, [{"cistern #{me.caught}", @water}, "     ", {"score #{me.score}", @gold}]}
    ] ++ hint(me) ++ Enum.map(rivals, &rival/1)
  end

  defp hint(%{caught: 0, level: 1}),
    do: [{:hint, [{"walk under a ring: that is where the rain will fall", @dim}]}]

  defp hint(_me), do: []

  defp rival(rival) do
    status = if rival.out?, do: "out", else: String.duplicate("● ", rival.jars)

    {:rival,
     [
       {rival.name, if(rival.robot?, do: {170, 215, 245}, else: {255, 240, 200})},
       "  #{rival.score}  ",
       status
     ]}
  end

  @impl true
  def outcome(view), do: Game.outcome(view)

  @impl true
  def listener(%{me: nil}), do: nil
  def listener(%{me: me}), do: {me.offset + me.centre, Field.rows().keeper}

  @impl true
  def sounds, do: &Sound.voice/1

  @impl true
  def music, do: Sound.pieces()

  @impl true
  def cue(%{me: %Field{level: level}}, :play), do: Sound.cue(level)
  def cue(_view, _screen), do: nil

  @impl true
  def guide do
    [
      {"the square",
       [
         %{art: :squall, name: "the Squall", text: "drifts along the top and lets the rain go"},
         %{art: :drop, name: "rain", text: "catch every drop in your jars"},
         %{
           art: :shadow_near,
           name: "shadow",
           text: "where a drop will fall; it grows as the drop comes down"
         },
         %{
           art: :jar,
           name: "jar",
           text:
             "one on your head, one at each end of the yoke; a drop that reaches the ground breaks one"
         },
         %{art: :keeper, name: "keeper", text: "you; the arrows or the pointer walk you"}
       ]},
      {"storms",
       [
         %{
           art: :squall_grin,
           name: "a miss",
           text: "the storm steps back and starts again, one jar lighter"
         },
         %{
           art: :jar,
           name: "a mended jar",
           text: "fifteen catches in a row mend a broken side jar"
         }
       ]}
    ]
  end
end
