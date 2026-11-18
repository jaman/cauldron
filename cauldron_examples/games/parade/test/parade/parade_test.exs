defmodule Parade.LegendTest do
  use ExUnit.Case, async: true

  alias Parade.Legend

  @map """
  WWWWWW
  W..,,W
  W.P,,W
  WWWWWW
  """

  test "floors and blocks become cells, and the walls stand" do
    courtyard = Legend.build(@map)

    assert courtyard.size == {6, 4}
    assert courtyard.cells[{1, 1}] == {:stone, [], nil}
    assert courtyard.cells[{3, 1}] == {:grass, [], nil}
    assert courtyard.cells[{2, 2}] == {:stone, [:pillar, :pillar], nil}
    assert courtyard.cells[{0, 0}] == {:stone, [:wall], nil}
  end

  test "only the floors are walkable" do
    courtyard = Legend.build(@map)

    assert MapSet.member?(courtyard.walkable, {1, 1})
    refute MapSet.member?(courtyard.walkable, {2, 2})
    refute MapSet.member?(courtyard.walkable, {0, 0})
    assert length(courtyard.open) == 7
  end
end

defmodule Parade.ArtTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Parade.Art

  setup_all do
    Art.install()
    {:ok, atlas: Atlas.fetch(Art.name())}
  end

  test "every colour is present and differs from the others", %{atlas: atlas} do
    ids =
      for colour <- Art.colours(),
          do: Atlas.pose(atlas, Art.walker(colour, false), :front, 0).id

    assert length(Enum.uniq(ids)) == length(Art.colours())
  end
end

defmodule Parade.GameTest do
  use ExUnit.Case, async: false

  alias Parade.{Art, Game, Legend}

  setup_all do
    Art.install()
    Legend.install()
    :ok
  end

  defp holding(game, id, held, extra \\ %{}) do
    Game.handle_input(game, id, Map.merge(%{held: MapSet.new(held), aim: nil}, extra))
  end

  test "a player joins at the centre and walks where it is held" do
    {:ok, game} = Game.join(Game.init([]), "alice", %{username: "alice"})
    start = game.players["alice"].mover

    walked = game |> holding("alice", [:up]) |> Game.step(0.5) |> Game.step(0.5)
    moved = walked.players["alice"].mover

    assert moved.y < start.y
    assert Game.walking?(moved, walked.elapsed)
  end

  test "with an eye heading, walking is relative to it and the knight faces where it walks" do
    {:ok, game} = Game.join(Game.init([]), "alice", %{username: "alice"})
    start = game.players["alice"].mover

    east = game |> holding("alice", [:up], %{heading: 0.0}) |> Game.step(0.5)
    moved = east.players["alice"].mover

    assert moved.x > start.x
    assert_in_delta moved.y, start.y, 0.001
    assert_in_delta moved.heading, 0.0, 0.001

    left = game |> holding("alice", [:left], %{heading: 0.0}) |> Game.step(0.5)
    right = game |> holding("alice", [:right], %{heading: 0.0}) |> Game.step(0.5)

    assert left.players["alice"].mover.heading != right.players["alice"].mover.heading,
           "strafing each way must turn the knight each way, as it does isometric"
  end

  test "the walkers cross the yard on their own, and the view carries everyone" do
    game = Game.init([])
    {:ok, game} = Game.join(game, "alice", %{username: "alice"})
    before = Enum.map(game.walkers, & &1.mover)

    stepped = Enum.reduce(1..30, game, fn _, acc -> Game.step(acc, 1 / 30) end)
    view = Game.view(stepped, "alice")

    assert Enum.map(stepped.walkers, & &1.mover) != before
    assert length(view.movers) == length(Art.colours())
    assert Enum.all?(view.movers, &Legend.walkable?({&1.x, &1.y}))
  end
end
