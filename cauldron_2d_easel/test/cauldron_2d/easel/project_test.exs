defmodule Cauldron2D.Easel.ProjectTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.{Atlas, Easel}
  alias Cauldron2D.Easel.Project

  setup do
    dir = Path.join(System.tmp_dir!(), "easel_project_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "wall.pic"), "W #5a7cf0\n\nWWWW\nWWWW\nWWWW\nWWWW\n")

    File.write!(
      Path.join(dir, "flame.pic"),
      "R red\n\nR...\n....\n....\n....\n---\n.R..\n....\n....\n....\n"
    )

    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "a project lists the arts of a directory with their frames, and opens one as an easel", %{
    dir: dir
  } do
    project = Project.open(dir, tile: 4)

    assert Project.arts(project) == [
             %{name: :flame, file: "flame.pic", frames: 2},
             %{name: :wall, file: "wall.pic", frames: 1}
           ]

    assert {:ok, easel} = Project.load(project, :flame)
    assert length(easel.frames) == 2
    assert Easel.size(easel) == {4, 4}
    assert {:error, :enoent} = Project.load(project, :nope)
  end

  test "a new art starts transparent at the tile size and saves as a pic; a save keeps the manifest's glyph",
       %{dir: dir} do
    project = Project.open(dir, tile: 4)
    easel = Project.new_art(project, palette: [{"G", :green}]) |> Easel.paint({0, 0}, "G")
    assert Easel.size(easel) == {4, 4}
    {:ok, project} = Project.save(project, :gem, easel)
    assert Enum.any?(Project.arts(project), &(&1.name == :gem))
    assert File.exists?(Path.join(dir, "gem.pic"))
    {:ok, project} = Project.put_entry(project, :gem, glyph: "* ", color: {0, 255, 0}, fps: 12)
    assert Project.entry(project, :gem) == %{glyph: "* ", color: {0, 255, 0}, fps: 12}
    assert Project.entry(project, :wall) == %{}
    assert File.read!(Path.join(dir, "atlas.txt")) =~ "gem\t* \t#00ff00\t12"
    reopened = Project.open(dir, tile: 4)
    assert Project.entry(reopened, :gem) == %{glyph: "* ", color: {0, 255, 0}, fps: 12}
  end

  test "installing a project builds the atlas from the directory with the manifest's glyphs, and tells subscribers",
       %{dir: dir} do
    project = Project.open(dir, tile: 4)
    {:ok, project} = Project.put_entry(project, :wall, glyph: "# ")
    Atlas.subscribe(:easel_project_test)
    assert {:ok, :easel_project_test} = Project.install(project, :easel_project_test)
    assert_receive {:cauldron_atlas, :easel_project_test, :changed}
    atlas = Atlas.fetch(:easel_project_test)
    assert Atlas.entry(atlas, :wall).glyph == "# "
    assert length(Atlas.entry(atlas, :flame).frames) == 2
    assert Atlas.entry(atlas, :flame).glyph == "FL"
  end

  test "the manifest is what Atlas.load reads too", %{dir: dir} do
    File.write!(Path.join(dir, "atlas.txt"), "wall\t# \t#010203\t\nflame\tf \t\t3\n")
    {:ok, atlas} = Atlas.load(:easel_manifest_test, dir, tile: 4)
    assert Atlas.entry(atlas, :wall).glyph == "# "
    assert Atlas.entry(atlas, :wall).color == {1, 2, 3}
    assert Atlas.entry(atlas, :flame).fps == 3
    {:ok, over} = Atlas.load(:easel_manifest_over, dir, tile: 4, arts: [wall: [glyph: "@ "]])
    assert Atlas.entry(over, :wall).glyph == "@ "
  end
end

defmodule Cauldron2D.Easel.ProjectDeriveTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Easel
  alias Cauldron2D.Easel.Project

  setup do
    dir =
      Path.join(System.tmp_dir!(), "easel_project_derive_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "knight.pic"), "H #a05000\nC #2040c0\n\n.HH.\n....\nCCCC\nC..C\n")
    File.write!(Path.join(dir, "hat.pic"), "B #000000\n\nBBBB\n....\n....\n....\n")
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, project: Project.open(dir, tile: 4), dir: dir}
  end

  test "a derived art is a manifest line; it lists with its source, loads as an easel, and one that cannot be made is refused",
       %{project: project} do
    {:ok, project} =
      Project.derive(project, :knight_red, "from knight; colour C #c02020; over hat")

    assert Enum.map(Project.arts(project), & &1.name) == [:hat, :knight, :knight_red]

    assert %{derived: "from knight; colour C #c02020; over hat", frames: 1} =
             Enum.find(Project.arts(project), &(&1.name == :knight_red))

    refute Map.has_key?(Enum.find(Project.arts(project), &(&1.name == :knight)), :derived)

    {:ok, easel} = Project.load(project, :knight_red)
    assert Easel.colour(easel, "C") == {192, 32, 32, 255}
    assert Easel.key_at(easel, {0, 0}, 0) == "B"

    assert {:error, message} = Project.derive(project, :ghost_hat, "from ghost; over hat")
    assert message =~ "ghost"
    assert {:error, message} = Project.derive(project, :knight, "from hat")
    assert message =~ "knight"
  end

  test "a clone is a picture of its own, free of its source", %{project: project} do
    {:ok, project} = Project.clone(project, :knight, :knight2)
    {:ok, original} = Project.load(project, :knight)
    {:ok, copy} = Project.load(project, :knight2)
    assert copy.frames == original.frames
    assert Enum.map(Project.arts(project), & &1.file) == ["hat.pic", "knight.pic", "knight2.pic"]

    {:ok, project} = Project.derive(project, :knight_left, "from knight; flip h")
    {:ok, project} = Project.clone(project, :knight_left, :knight_west)
    {:ok, west} = Project.load(project, :knight_west)
    assert Easel.key_at(west, {3, 0}, 0) == "."
    assert Easel.key_at(west, {1, 0}, 0) == "H"
    assert Enum.find(Project.arts(project), &(&1.name == :knight_west)).file == "knight_west.pic"
  end

  test "installing builds the derived arts too", %{project: project} do
    {:ok, project} = Project.derive(project, :knight_red, "from knight; colour C #c02020")
    {:ok, :easel_project_derived} = Project.install(project, :easel_project_derived)
    assert :knight_red in Cauldron2D.Atlas.arts(Cauldron2D.Atlas.fetch(:easel_project_derived))
  end
end
