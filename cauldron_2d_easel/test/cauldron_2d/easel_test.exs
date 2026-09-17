defmodule Cauldron2D.EaselTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Easel
  alias FrenchCurve.Raster

  @pic """
  R #c33
  W white

  ..RR..
  .RWWR.
  """

  defp key_at(easel, x, y, frame \\ nil), do: Easel.key_at(easel, {x, y}, frame || easel.frame)

  test "a new document is transparent, one frame, with a palette to paint from" do
    easel = Easel.new(4, 3, palette: [{"R", "#c33"}])
    assert Easel.size(easel) == {4, 3}
    assert length(easel.frames) == 1
    assert key_at(easel, 0, 0) == "."
    assert Easel.colour(easel, "R") == {204, 51, 51, 255}
    assert Easel.keys(easel) == ["R"]
  end

  test "a pic reads in and writes out the same" do
    {:ok, easel} = Easel.from_pic(@pic)
    assert Easel.size(easel) == {6, 2}
    assert key_at(easel, 2, 0) == "R"
    assert key_at(easel, 2, 1) == "W"
    assert Easel.to_pic(easel) == "R #cc3333\nW #ffffff\n\n..RR..\n.RWWR.\n"
    assert {:ok, again} = Easel.from_pic(Easel.to_pic(easel))
    assert again.frames == easel.frames
  end

  test "painting, lines, rectangles and fills change the current frame; undo and redo walk the history" do
    easel = Easel.new(5, 5, palette: [{"R", :red}, {"B", :blue}])
    painted = Easel.paint(easel, {1, 1}, "R")
    assert key_at(painted, 1, 1) == "R"
    assert key_at(easel, 1, 1) == "."

    lined = Easel.line(painted, {0, 4}, {4, 0}, "B")

    assert key_at(lined, 2, 2) == "B" and key_at(lined, 0, 4) == "B" and
             key_at(lined, 4, 0) == "B"

    boxed = Easel.rect(easel, {1, 1}, {3, 3}, "R")

    assert key_at(boxed, 1, 1) == "R" and key_at(boxed, 3, 1) == "R" and
             key_at(boxed, 2, 2) == "."

    filled_box = Easel.rect(easel, {1, 1}, {3, 3}, "R", fill: true)
    assert key_at(filled_box, 2, 2) == "R"

    flooded = Easel.fill(boxed, {2, 2}, "B")

    assert key_at(flooded, 2, 2) == "B" and key_at(flooded, 0, 0) == "." and
             key_at(flooded, 1, 1) == "R"

    outside = Easel.fill(boxed, {0, 0}, "B")
    assert key_at(outside, 4, 4) == "B" and key_at(outside, 2, 2) == "."

    undone = Easel.undo(lined)
    assert key_at(undone, 2, 2) == "." and key_at(undone, 1, 1) == "R"
    assert Easel.undo(Easel.undo(undone)) == Easel.undo(undone)
    assert Easel.redo(undone).frames == lined.frames
    assert Easel.redo(lined) == lined
    assert Easel.paint(undone, {0, 0}, "R") |> Easel.redo() |> key_at(2, 2) == "."
  end

  test "painting outside the picture or with an unknown key changes nothing; erasing paints transparent" do
    easel = Easel.new(2, 2, palette: [{"R", :red}])
    assert Easel.paint(easel, {5, 5}, "R") == easel
    assert Easel.paint(easel, {0, 0}, "Z") == easel
    assert easel |> Easel.paint({0, 0}, "R") |> Easel.erase({0, 0}) |> key_at(0, 0) == "."
  end

  test "the palette can gain, change, rename and lose colours; a lost colour's pixels go transparent" do
    easel = Easel.new(2, 1, palette: [{"R", :red}]) |> Easel.paint({0, 0}, "R")
    added = Easel.add_colour(easel, "G", "#00ff00")
    assert Easel.keys(added) == ["R", "G"]

    assert {:error, :taken} =
             Easel.add_colour(added, "R", :blue)
             |> then(fn e -> if e == added, do: {:error, :taken}, else: :changed end)

    changed = Easel.set_colour(added, "R", {1, 2, 3})
    assert Easel.colour(changed, "R") == {1, 2, 3, 255}
    renamed = Easel.rename_key(changed, "R", "X")
    assert key_at(renamed, 0, 0) == "X" and Easel.keys(renamed) == ["X", "G"]
    lost = Easel.remove_colour(renamed, "X")
    assert key_at(lost, 0, 0) == "." and Easel.keys(lost) == ["G"]
    assert Easel.rename_key(renamed, "X", ".") == renamed
    assert Easel.rename_key(renamed, "X", "GG") == renamed
  end

  test "flips, turns and shifts move the whole frame" do
    {:ok, easel} = Easel.from_pic("R #c33\n\nR..\n...\n")
    assert easel |> Easel.flip(:horizontal) |> key_at(2, 0) == "R"
    assert easel |> Easel.flip(:vertical) |> key_at(0, 1) == "R"
    turned = Easel.rotate(easel, 90)
    assert Easel.size(turned) == {2, 3}
    assert key_at(turned, 0, 2) == "R"
    shifted = Easel.shift(easel, 1, 1)
    assert key_at(shifted, 1, 1) == "R" and key_at(shifted, 0, 0) == "."
    assert Easel.shift(easel, -1, 0) |> key_at(0, 0) == "."
  end

  test "frames are added, duplicated, moved, chosen and dropped, at a rate" do
    easel = Easel.new(2, 2, palette: [{"R", :red}]) |> Easel.paint({0, 0}, "R")
    two = Easel.add_frame(easel)
    assert length(two.frames) == 2 and two.frame == 1 and key_at(two, 0, 0) == "."
    dup = Easel.duplicate_frame(easel)
    assert length(dup.frames) == 2 and dup.frame == 1 and key_at(dup, 0, 0) == "R"
    three = dup |> Easel.add_frame() |> Easel.paint({1, 1}, "R")
    moved = Easel.move_frame(three, 2, 0)
    assert moved.frame == 0 and key_at(moved, 1, 1) == "R" and key_at(moved, 0, 0) == "."
    chosen = Easel.select_frame(moved, 2)
    assert chosen.frame == 2
    assert Easel.select_frame(moved, 9) == moved
    dropped = Easel.delete_frame(chosen)
    assert length(dropped.frames) == 2 and dropped.frame == 1
    assert Easel.delete_frame(Easel.delete_frame(dropped)) |> Map.get(:frames) |> length() == 1
    assert Easel.set_fps(easel, 12).fps == 12
  end

  test "a frame renders to a raster and the document to a strip, and back from a png" do
    {:ok, easel} = Easel.from_pic(@pic)
    raster = Easel.raster(easel, 0)
    assert Raster.dimensions(raster) == {6, 2}
    assert Raster.get_pixel(raster, 2, 0) == {204, 51, 51, 255}
    two = Easel.duplicate_frame(easel)
    strip = Easel.strip(two)
    assert Raster.dimensions(strip) == {12, 2}

    {:ok, back} = Easel.from_png(Easel.to_png(two), frame: {6, 2})
    assert length(back.frames) == 2
    assert Easel.size(back) == {6, 2}
    assert length(Easel.keys(back)) == 2
    assert Easel.colour(back, key_at(back, 2, 0)) == {204, 51, 51, 255}
    assert Easel.key_at(back, {0, 0}, 0) == "."
  end

  test "a png with more colours than keys is refused rather than quantised silently" do
    raster =
      for x <- 0..99, reduce: Raster.new(100, 1) do
        acc -> Raster.put_pixel(acc, x, 0, {x, 0, 0, 255})
      end

    png = FrenchCurve.Png.encode(100, 1, Raster.to_rgba_binary(raster))
    assert {:error, {:too_many_colours, 100}} = Easel.from_png(png, frame: {100, 1})
  end

  test "load and save go by extension" do
    dir = Path.join(System.tmp_dir!(), "easel_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    {:ok, easel} = Easel.from_pic(@pic)
    :ok = Easel.save(easel, Path.join(dir, "ship.pic"))
    :ok = Easel.save(easel, Path.join(dir, "ship.png"))
    assert {:ok, from_pic} = Easel.load(Path.join(dir, "ship.pic"))
    assert {:ok, from_png} = Easel.load(Path.join(dir, "ship.png"), frame: {6, 2})
    assert from_pic.frames == easel.frames

    assert Easel.raster(from_png, 0) |> Raster.to_rgba_binary() ==
             Easel.raster(easel, 0) |> Raster.to_rgba_binary()

    assert {:error, {:unknown_format, ".gif"}} = Easel.save(easel, Path.join(dir, "ship.gif"))
    File.rm_rf!(dir)
  end
end

defmodule Cauldron2D.EaselDeriveTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Easel

  test "derive applies a line of operations to the easel itself, over names through the lookup" do
    knight =
      Easel.new(4, 4, palette: [{"H", "#a05000"}, {"C", "#2040c0"}], fps: 5)
      |> Easel.paint({0, 0}, "H")
      |> Easel.rect({0, 2}, {3, 3}, "C", fill: true)

    {:ok, red} = Easel.derive(knight, "colour C #c02020; flip h")
    assert Easel.colour(red, "C") == {192, 32, 32, 255}
    assert Easel.key_at(red, {3, 0}, 0) == "H"
    assert Easel.key_at(red, {0, 0}, 0) == "."
    assert red.fps == 5
    assert red.undo == []

    hat = "B #000000\n\nBBBB\n....\n....\n....\n"

    {:ok, hatted} =
      Easel.derive(knight, "over hat", fn
        "hat" -> {:ok, hat}
        _ -> :error
      end)

    assert Easel.key_at(hatted, {2, 0}, 0) == "B"

    assert {:error, message} = Easel.derive(knight, "over crown")
    assert message =~ "crown"
    assert {:error, message} = Easel.derive(knight, "bend 3")
    assert message =~ "bend"
  end
end
