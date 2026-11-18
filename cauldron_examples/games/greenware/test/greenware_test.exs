defmodule GreenwareTest do
  use ExUnit.Case, async: false

  alias Cauldron.Test
  alias Greenware.{Campaign, Mend, Progress}
  alias Greenware.Mend.Puzzles
  alias Cauldron2D.Raster

  test "every scene names a real puzzle and every act has required scenes" do
    for scene <- Map.values(Campaign.scenes()) do
      assert is_atom(scene.puzzle)
      assert scene.puzzle in Puzzles.ids()
      assert is_map(Puzzles.puzzle(scene.puzzle))
      assert is_map(scene.hotspot)
    end

    for act <- Campaign.acts() do
      assert Campaign.act_scenes(act.id) != []
      assert Campaign.hub(act.id).id == act.hub
    end
  end

  test "every mending can be solved with the tools it gives" do
    for id <- Puzzles.ids() do
      puzzle = Puzzles.puzzle(id)
      mend = Mend.new(puzzle)

      mend =
        Enum.reduce(1..4, mend, fn _, mend ->
          Enum.reduce(Enum.to_list(puzzle.holes), mend, fn {x, y}, mend ->
            Mend.apply(mend, :thumb, x, y, 1.0)
          end)
        end)

      mend =
        Enum.reduce(Enum.to_list(puzzle.holes), mend, fn {x, y}, mend ->
          Mend.apply(mend, :wire, x, y, 1.0)
        end)

      mend = Enum.reduce(1..75, mend, fn _, mend -> Mend.apply(mend, :heat, 48, 36, 1.0) end)
      result = Mend.check(mend).result

      assert result.ok?, "#{id} is not solvable: #{inspect(result.rows)}"
    end
  end

  test "a fresh game opens the workshop and can be viewed" do
    driver = Test.new(Greenware.Game, game_opts: [fresh: true], hz: 30)
    {:ok, driver} = Test.join(driver, :mender, %{username: "mender", options: %{}})
    view = Test.view(driver, :mender)

    assert view.act == 1
    assert view.mode == :dialogue
    assert view.screen == :hub
    assert view.hub.title == "THE WORKSHOP"
    assert length(view.hub.entries) == 3
  end

  test "progress is remembered" do
    progress = %{Progress.new() | act: 3, completed: [:cup, :key], seen: [{:hub, 3}]}
    assert :ok = Progress.save(progress)
    assert %{act: 3, completed: [:cup, :key]} = Progress.load()
    assert Progress.exists?()
    Progress.delete()
    refute Progress.exists?()
  end

  test "the painter draws the title and a scene at 1280 by 720" do
    settings = %{music: 0.7, sfx: 0.8, bindings: %{}, options: %{}}
    title = Greenware.Title.init(:title, %{settings: settings, username: "mender"})
    raster = Greenware.Render.title(title, settings)
    assert Raster.dimensions(raster) == {1280, 720}

    driver = Test.new(Greenware.Game, game_opts: [fresh: true], hz: 30)
    {:ok, driver} = Test.join(driver, :mender, %{username: "mender", options: %{}})
    view = Test.view(driver, :mender)
    assert Raster.dimensions(Greenware.Render.frame(%{view | fade: 0.0}, %{})) == {1280, 720}
  end
end
