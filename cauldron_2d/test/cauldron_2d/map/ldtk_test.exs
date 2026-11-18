defmodule Cauldron2D.Map.LdtkTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Map.Ldtk

  @project JSON.encode!(%{
             "defaultGridSize" => 16,
             "levels" => [
               %{
                 "identifier" => "Level_0",
                 "worldX" => 0,
                 "worldY" => 0,
                 "pxWid" => 48,
                 "pxHei" => 32,
                 "fieldInstances" => [%{"__identifier" => "music", "__value" => "forest"}],
                 "layerInstances" => [
                   %{
                     "__identifier" => "Entities",
                     "__type" => "Entities",
                     "__cWid" => 3,
                     "__cHei" => 2,
                     "__gridSize" => 16,
                     "entityInstances" => [
                       %{
                         "iid" => "a1",
                         "__identifier" => "Hero",
                         "px" => [24, 16],
                         "width" => 16,
                         "height" => 32,
                         "fieldInstances" => [%{"__identifier" => "lives", "__value" => 3}]
                       }
                     ]
                   },
                   %{
                     "__identifier" => "Ground",
                     "__type" => "Tiles",
                     "__cWid" => 3,
                     "__cHei" => 2,
                     "__gridSize" => 16,
                     "gridTiles" => [%{"px" => [32, 16], "t" => 7, "f" => 1}]
                   },
                   %{
                     "__identifier" => "Collisions",
                     "__type" => "IntGrid",
                     "__cWid" => 3,
                     "__cHei" => 2,
                     "__gridSize" => 16,
                     "intGridCsv" => [0, 0, 1, 1, 1, 1]
                   }
                 ]
               }
             ]
           })

  test "a level's grid, tiles and entities read in cells, with their fields" do
    {:ok, project} = Ldtk.parse(@project)
    level = Ldtk.level(project, "Level_0")
    assert level.fields == %{"music" => "forest"}

    assert Ldtk.layer(level, "Collisions").values == %{
             {2, 0} => 1,
             {0, 1} => 1,
             {1, 1} => 1,
             {2, 1} => 1
           }

    assert Ldtk.layer(level, "Ground").tiles == [%{at: {2, 1}, tile: 7, flips: [:horizontal]}]

    assert [%{name: "Hero", x: 1.5, y: 1.0, width: 1.0, height: 2.0, fields: %{"lives" => 3}}] =
             Ldtk.layer(level, "Entities").entities
  end
end
