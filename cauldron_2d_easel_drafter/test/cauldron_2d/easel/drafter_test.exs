defmodule Cauldron2D.Easel.DrafterTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Easel
  alias Cauldron2D.Easel.Drafter, as: Editor
  alias Drafter.Test, as: DT

  setup do
    dir = Path.join(System.tmp_dir!(), "easel_drafter_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "gem.pic"), "G #00ff00\nB #0000ff\n\n....\n....\n....\n....\n")

    ctx =
      DT.start_headless(Editor, %{dir: dir, tile: 4, atlas: :easel_drafter_test}, size: {80, 24})

    on_exit(fn ->
      DT.stop(ctx)
      File.rm_rf!(dir)
    end)

    {:ok, ctx: ctx, dir: dir}
  end

  test "the arts are listed and one opens for editing", %{ctx: ctx} do
    assert DT.screen_text(ctx) =~ "gem"
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "frame 1/1" end)
    assert DT.screen_text(ctx) =~ "brush: press or drag to paint"
    assert DT.get_state(ctx).key == "G"
  end

  test "a click on the canvas paints the pixel under it with the colour in hand; keys pick tools, colours, frames; s saves and w installs",
       %{ctx: ctx, dir: dir} do
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "frame 1/1" end)
    state = DT.get_state(ctx)
    assert state.zoom == 4

    DT.send_mouse(ctx, %{type: :mouse_down, button: :left, x: 4, y: 1})
    DT.send_mouse(ctx, %{type: :mouse_up, button: :left, x: 4, y: 1})

    assert :ok ==
             DT.wait_for(ctx, fn c -> Easel.key_at(DT.get_state(c).easel, {1, 0}, 0) == "G" end)

    DT.send_key(ctx, :"2")
    assert DT.get_state(ctx).key == "B"
    DT.send_key(ctx, :f)
    assert DT.get_state(ctx).tool == :fill
    DT.send_mouse(ctx, %{type: :mouse_down, button: :left, x: 0, y: 3})
    DT.send_mouse(ctx, %{type: :mouse_up, button: :left, x: 0, y: 3})

    assert :ok ==
             DT.wait_for(ctx, fn c -> Easel.key_at(DT.get_state(c).easel, {3, 3}, 0) == "B" end)

    assert Easel.key_at(DT.get_state(ctx).easel, {1, 0}, 0) == "G"

    DT.send_key(ctx, :u)
    assert Easel.key_at(DT.get_state(ctx).easel, {3, 3}, 0) == "."
    DT.send_key(ctx, :U)
    assert Easel.key_at(DT.get_state(ctx).easel, {3, 3}, 0) == "B"

    DT.send_key(ctx, :a)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "frame 2/2" end)
    DT.send_key(ctx, :",")
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "frame 1/2" end)

    DT.send_key(ctx, :s)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "saved gem.pic" end)
    assert File.read!(Path.join(dir, "gem.pic")) =~ "---"

    Cauldron2D.Atlas.subscribe(:easel_drafter_test)
    DT.send_key(ctx, :w)

    assert :ok ==
             DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "installed as :easel_drafter_test" end)

    assert_receive {:cauldron_atlas, :easel_drafter_test, :changed}, 1_000

    assert length(
             Cauldron2D.Atlas.entry(Cauldron2D.Atlas.fetch(:easel_drafter_test), :gem).frames
           ) == 2

    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "2 frames" end)
  end

  test "? shows the keys on any screen; the picker adds a chosen colour under the next free key; the eyedropper takes one from the picture",
       %{ctx: ctx} do
    DT.send_key(ctx, :"?")
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Tools       b brush" end)
    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "gem" end)

    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "frame 1/1" end)
    assert DT.screen_text(ctx) =~ "brush: press or drag to paint"

    DT.send_key(ctx, :c)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "New colour" end)
    DT.send_mouse(ctx, %{type: :mouse_down, button: :left, x: 6, y: 2})
    DT.send_mouse(ctx, %{type: :mouse_up, button: :left, x: 6, y: 2})
    assert :ok == DT.wait_for(ctx, fn c -> DT.get_state(c).picker.cursor == {3, 0} end)
    chosen = DT.get_state(ctx).picker.colour
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.get_state(c).picker == nil end)
    state = DT.get_state(ctx)
    assert state.key == "A"
    {r, g, b} = chosen
    assert Easel.colour(state.easel, "A") == {r, g, b, 255}

    DT.send_mouse(ctx, %{type: :mouse_down, button: :left, x: 0, y: 1})
    DT.send_mouse(ctx, %{type: :mouse_up, button: :left, x: 0, y: 1})

    assert :ok ==
             DT.wait_for(ctx, fn c -> Easel.key_at(DT.get_state(c).easel, {0, 0}, 0) == "A" end)

    DT.send_key(ctx, :"1")
    assert DT.get_state(ctx).key == "G"
    DT.send_click(ctx, :tool_eyedropper)
    assert :ok == DT.wait_for(ctx, fn c -> DT.get_state(c).tool == :eyedropper end)
    DT.send_mouse(ctx, %{type: :mouse_down, button: :left, x: 0, y: 1})
    DT.send_mouse(ctx, %{type: :mouse_up, button: :left, x: 0, y: 1})
    assert :ok == DT.wait_for(ctx, fn c -> DT.get_state(c).key == "A" end)
    assert DT.get_state(ctx).tool == :brush
  end

  test "a new art is named at the prompt and starts at the tile size; a colour is added at the prompt",
       %{ctx: ctx} do
    DT.send_key(ctx, :n)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "name:" end)
    for char <- String.graphemes("orb"), do: DT.send_char(ctx, char)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "orb  ·  4×4" end)
    assert DT.screen_text(ctx) =~ "none yet"

    DT.send_key(ctx, :"#")
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "key #rrggbb:" end)
    for char <- String.graphemes("O #ff8800"), do: DT.send_char(ctx, char)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.get_state(c).key == "O" end)
    assert Easel.colour(DT.get_state(ctx).easel, "O") == {255, 136, 0, 255}
  end
end

defmodule Cauldron2D.Easel.DrafterActualSizeTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Easel.Drafter, as: Editor
  alias Drafter.Test, as: DT

  setup do
    dir = Path.join(System.tmp_dir!(), "easel_actual_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "gem.pic"), "G #00ff00\n\nGG..\n....\n....\n....\n")
    File.write!(Path.join(dir, "atlas.txt"), "gem\t<>\t#00ff00\t8\n")
    ctx = DT.start_headless(Editor, %{dir: dir, tile: 4, art: :gem}, size: {80, 24})

    on_exit(fn ->
      DT.stop(ctx)
      File.rm_rf!(dir)
    end)

    {:ok, ctx: ctx}
  end

  test "the picture is installed as an atlas of its own and drawn at actual size beside the canvas; m tiles it",
       %{ctx: ctx} do
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "actual size" end)
    state = DT.get_state(ctx)
    assert Atlas.installed?(state.actual.name)
    assert Atlas.entry(Atlas.fetch(state.actual.name), :art).glyph == "<>"
    assert DT.screen_text(ctx) =~ "<>"
    refute state.tiled
    DT.send_key(ctx, :m)
    assert DT.get_state(ctx).tiled
  end

  test "a change to the picture reaches the atlas", %{ctx: ctx} do
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "actual size" end)
    before = DT.get_state(ctx).actual.fingerprint
    DT.send_key(ctx, :h)
    assert :ok == DT.wait_for(ctx, fn c -> DT.get_state(c).actual.fingerprint != before end)
    raster = hd(Atlas.entry(Atlas.fetch(DT.get_state(ctx).actual.name), :art).frames).raster
    assert FrenchCurve.Raster.get_pixel(raster, 3, 0) == {0, 255, 0, 255}
  end
end

defmodule Cauldron2D.Easel.DrafterDeriveTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Easel.Drafter, as: Editor
  alias Drafter.Test, as: DT

  setup do
    dir = Path.join(System.tmp_dir!(), "easel_derive_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "gem.pic"), "G #00ff00\n\nG...\n....\n....\n....\n")
    ctx = DT.start_headless(Editor, %{dir: dir, tile: 4}, size: {100, 24})

    on_exit(fn ->
      DT.stop(ctx)
      File.rm_rf!(dir)
    end)

    {:ok, ctx: ctx, dir: dir}
  end

  defp type(ctx, text),
    do: Enum.each(String.graphemes(text), &DT.send_key(ctx, String.to_atom(&1)))

  test "D derives an art from the one chosen, listed with its line; y clones one as a picture", %{
    ctx: ctx,
    dir: dir
  } do
    DT.send_key(ctx, :D)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "name = from gem" end)
    type(ctx, "ruby = from gem; colour G #ff0000; flip h")
    DT.send_key(ctx, :enter)

    assert :ok ==
             DT.wait_for(ctx, fn c ->
               DT.screen_text(c) =~ "ruby  ·  1 frame  ·  from gem; colour G #ff0000; flip h"
             end)

    assert File.read!(Path.join(dir, "atlas.txt")) =~
             "ruby\t\t\t\tfrom gem; colour G #ff0000; flip h"

    DT.send_key(ctx, :down)
    DT.send_key(ctx, :y)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "clone ruby as" end)
    type(ctx, "garnet")
    DT.send_key(ctx, :enter)

    assert :ok ==
             DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "garnet  ·  1 frame  ·  garnet.pic" end)

    assert File.read!(Path.join(dir, "garnet.pic")) =~ "...G"
  end

  test "a derived art opens for looking and refuses a save", %{ctx: ctx} do
    DT.send_key(ctx, :D)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "name = from gem" end)
    type(ctx, "twin")
    DT.send_key(ctx, :enter)

    assert :ok ==
             DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "twin  ·  1 frame  ·  from gem" end)

    DT.send_key(ctx, :down)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "twin  ·  4×4" end)
    DT.send_key(ctx, :s)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "twin is derived" end)
  end
end
