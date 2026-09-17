defmodule Cauldron2D.MapTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Map, as: TileMap

  @classic """
  # Created by xmapedit

  mapwidth : 6
  mapheight : 3
  mapname : Tiny
  edgewrap : yes
  maxrobots: 2

  mapData: \\multiline: EndOfMapdata
  xxxxxx
  x _  x
  xqx.sx
  EndOfMapdata
  """

  @picture """
  ####
  #..#
  ####
  """

  describe "parse/1 on the classic header format" do
    test "reads options with their case and spacing normalised" do
      {:ok, map} = TileMap.parse(@classic)
      assert map.options["mapname"] == "Tiny"
      assert map.options["edgewrap"] == "yes"
      assert map.options["maxrobots"] == "2"
    end

    test "reads the grid between the multiline markers" do
      {:ok, map} = TileMap.parse(@classic)
      assert map.width == 6
      assert map.height == 3
      assert TileMap.at(map, {1, 1}) == " "
      assert TileMap.at(map, {2, 1}) == "_"
      assert TileMap.at(map, {1, 2}) == "q"
    end

    test "pads short rows and cuts a row longer than the width" do
      {:ok, map} =
        TileMap.parse("mapwidth: 4\nmapheight: 2\nmapData: \\multiline: END\nab\nabcd\nEND\n")

      assert TileMap.at(map, {3, 0}) == " "

      {:ok, cut} =
        TileMap.parse("mapwidth: 2\nmapheight: 1\nmapData: \\multiline: END\nabc\nEND\n")

      assert cut.width == 2
      assert TileMap.at(cut, {1, 0}) == "b"
    end

    test "a missing terminator runs to the end of the text" do
      assert {:ok, %{height: 1}} = TileMap.parse("mapData: \\multiline: END\nab\n")
    end

    test "missing rows are blank" do
      {:ok, map} =
        TileMap.parse("mapwidth: 2\nmapheight: 3\nmapData: \\multiline: END\nab\nEND\n")

      assert TileMap.at(map, {0, 2}) == " "
    end
  end

  describe "parse/1 on a bare picture" do
    test "takes the rows as the grid and the widest row as the width" do
      {:ok, map} = TileMap.parse(@picture)
      assert map.width == 4
      assert map.height == 3
      assert map.options == %{}
      assert TileMap.at(map, {1, 1}) == "."
    end
  end

  describe "at/2" do
    test "is space outside the grid unless the map wraps" do
      {:ok, map} = TileMap.parse(@picture)
      assert TileMap.at(map, {-1, 0}) == " "
      assert TileMap.at(map, {4, 5}) == " "

      {:ok, wrapping} = TileMap.parse(@classic, wrap: "edgewrap")
      {:ok, flat} = TileMap.parse(@classic)
      assert TileMap.at(flat, {-1, 0}) == " "
      assert TileMap.at(wrapping, {-1, 0}) == "x"
      assert TileMap.at(wrapping, {6, 1}) == "x"
    end
  end

  describe "option/4" do
    test "converts by type with a default" do
      {:ok, map} = TileMap.parse(@classic)
      assert TileMap.option(map, "maxrobots", :integer, 0) == 2
      assert TileMap.option(map, "edgewrap", :boolean, false) == true
      assert TileMap.option(map, "gravity", :float, -1.5) == -1.5
      assert TileMap.option(map, "mapname", :string, "?") == "Tiny"
      assert TileMap.option(map, "maxrobots", :boolean, false) == false
    end
  end

  describe "cells/2" do
    test "applies a legend to every character and keeps what it returns" do
      {:ok, map} = TileMap.parse(@classic)

      legend = fn
        "x" -> :wall
        "q" -> {:diagonal, :nw}
        "s" -> {:diagonal, :se}
        "_" -> :base
        _ -> nil
      end

      cells = TileMap.cells(map, legend)
      assert cells[{0, 0}] == :wall
      assert cells[{2, 1}] == :base
      assert cells[{1, 2}] == {:diagonal, :nw}
      assert cells[{4, 2}] == {:diagonal, :se}
      refute Map.has_key?(cells, {1, 1})
      refute Map.has_key?(cells, {3, 2})
    end
  end

  describe "positions/2" do
    test "lists where a character occurs, row-major" do
      {:ok, map} = TileMap.parse(@classic)
      assert TileMap.positions(map, "_") == [{2, 1}]
      assert length(TileMap.positions(map, "x")) == 11
    end
  end

  describe "parse_file/1" do
    test "reads a gzipped file" do
      dir = Path.join(System.tmp_dir!(), "cauldron_map_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      path = Path.join(dir, "tiny.map.gz")
      File.write!(path, :zlib.gzip(@classic))
      assert {:ok, %{width: 6}} = TileMap.parse_file(path)
      File.rm_rf!(dir)
    end
  end
end
