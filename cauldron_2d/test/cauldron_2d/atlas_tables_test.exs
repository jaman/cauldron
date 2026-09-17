defmodule Cauldron2D.Atlas.TablesTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.{Atlas, Surface}
  alias FrenchCurve.Raster

  @tile 4

  defp atlas(name),
    do:
      Atlas.new(name, tile: @tile)
      |> Atlas.put(:floor, Raster.new(@tile, @tile, background: {1, 2, 3, 255}))

  test "a cache table outlives the process that installed the atlas" do
    task = Task.async(fn -> Atlas.install(atlas(:atlas_tables_test)) end)
    assert :atlas_tables_test = Task.await(task)
    refute Process.alive?(task.pid)
    assert :ets.whereis(Atlas.cache(:atlas_tables_test)) != :undefined

    assert binary_part(Surface.tile_binary(:atlas_tables_test, {:floor, [], nil}), 0, 4) ==
             <<1, 2, 3, 255>>

    assert :ets.info(Atlas.cache(:atlas_tables_test), :owner) == Process.whereis(Atlas.Tables)
  end

  test "a table is made once and kept across installs; a changed atlas only empties it" do
    Atlas.install(atlas(:atlas_tables_kept))
    reference = :ets.whereis(Atlas.cache(:atlas_tables_kept))
    Surface.tile_binary(:atlas_tables_kept, {:floor, [], nil})
    assert :ets.info(Atlas.cache(:atlas_tables_kept), :size) == 1
    Atlas.install(atlas(:atlas_tables_kept))
    assert :ets.info(Atlas.cache(:atlas_tables_kept), :size) == 1

    Atlas.install(
      Atlas.new(:atlas_tables_kept, tile: @tile, void: {9, 9, 9})
      |> Atlas.put(:floor, Raster.new(@tile, @tile))
    )

    assert :ets.whereis(Atlas.cache(:atlas_tables_kept)) == reference
    assert :ets.info(Atlas.cache(:atlas_tables_kept), :size) == 0
  end
end
