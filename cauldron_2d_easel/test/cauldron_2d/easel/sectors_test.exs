defmodule Cauldron2D.Easel.SectorsTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Easel.Sectors
  alias Cauldron2D.Sectors.Map, as: SectorMap

  @names %{"wall" => 0, "floor" => 1, "ceiling" => 2}

  defp rooms do
    Sectors.new(grid: 32)
    |> Sectors.draw_room([{0, 0}, {0, 256}, {256, 256}, {256, 0}])
    |> Sectors.draw_room([{256, 64}, {384, 64}, {384, 192}, {256, 192}], floor: 16)
  end

  defp two_sided(doc), do: doc.lines |> Map.values() |> Enum.filter(& &1.back)

  test "a room drawn against another opens only the shared stretch of wall" do
    doc = rooms()
    [opening] = two_sided(doc)

    assert {Map.fetch!(doc.vertices, opening.from), Map.fetch!(doc.vertices, opening.to)} in [
             {{256.0, 64.0}, {256.0, 192.0}},
             {{256.0, 192.0}, {256.0, 64.0}}
           ]

    assert opening.front.middle == nil
    assert map_size(doc.lines) == 3 + 3 + 3
  end

  test "the built map finds each room and keeps its heights", %{} do
    {:ok, map} = Sectors.to_map(rooms(), &Map.get(@names, &1))

    first = SectorMap.sector_at(map, {100.0, 100.0})
    second = SectorMap.sector_at(map, {300.0, 128.0})

    assert first != second
    assert elem(map.sectors, second).floor == 16.0
    assert elem(map.sectors, first).floor == 0.0
  end

  test "removing a room turns its opening back into a wall of the other" do
    doc = rooms()
    second = Sectors.sector_at(doc, {300.0, 128.0})
    doc = Sectors.delete_sector(doc, second)

    assert two_sided(doc) == []
    assert map_size(doc.sectors) == 1
    assert Enum.all?(Map.values(doc.lines), &(&1.front.middle != nil))
  end

  test "undo steps back through edits, and a saved document reads back the same", %{} do
    doc = rooms()
    assert map_size(Sectors.undo(doc).sectors) == 1
    assert Sectors.redo(Sectors.undo(doc)).lines == doc.lines

    path = Path.join(System.tmp_dir!(), "sectors_#{System.unique_integer([:positive])}.json")
    :ok = Sectors.save(doc, path)
    {:ok, read} = Sectors.load(path)
    File.rm(path)

    assert {read.vertices, read.lines, read.sectors} == {doc.vertices, doc.lines, doc.sectors}
  end
end
