defmodule Cauldron2D.Drafter.PlacementsTest do
  @moduledoc """
  The placement rendering: the grid as one stored image, movers as placed sprites.
  """

  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Drafter.{Sprites, Surface}
  alias Drafter.Session.Context
  alias FrenchCurve.Raster

  @tile 8

  setup_all do
    Atlas.new(:placement_test, tile: @tile, void: {0, 0, 0})
    |> Atlas.put(:floor, Raster.new(@tile, @tile, background: {40, 45, 62, 255}),
      glyph: "· ",
      color: {60, 66, 88}
    )
    |> Atlas.put(:ship, Raster.new(@tile, @tile, background: {245, 232, 200, 255}),
      glyph: "> ",
      color: {245, 235, 200}
    )
    |> Atlas.put(:shot, Raster.new(@tile, @tile, background: {255, 0, 0, 255}),
      glyph: "· ",
      color: {255, 0, 0}
    )
    |> Atlas.install()

    :ok
  end

  setup do
    Context.put_terminal_env(%{"TERM" => "xterm-kitty"})
    Context.put_terminal_protocol(:kitty)
    Context.put_cell_size({10, 20})

    on_exit(fn ->
      Process.delete(:drafter_terminal_env)
      Process.delete(:drafter_terminal_protocol)
      Process.delete(:drafter_cell_size)
    end)

    state =
      Surface.mount(%{
        atlas: :placement_test,
        focus: {5, 5},
        cell: fn _ -> {:floor, [], nil} end,
        movers: [{:ship, {5.25, 5.5}}, {:shot, {6.0, 5.0}}],
        id: :world
      })

    {:ok, state: state}
  end

  defp rect, do: %{x: 3, y: 2, width: 20, height: 10}

  describe "the sprite sheet" do
    test "stores every art under a stable id" do
      bytes = IO.iodata_to_binary(Sprites.transmit(:placement_test))
      assert bytes =~ "a=t,i=#{Sprites.image_id(:placement_test, :ship)}"
      assert bytes =~ "a=t,i=#{Sprites.image_id(:placement_test, :shot)}"
      assert bytes =~ "s=8,v=8"
      refute bytes =~ "a=p"
      assert Sprites.image_id(:placement_test, :ship) == Sprites.image_id(:placement_test, :ship)
      assert Sprites.image_id(:placement_test, :ship) != Sprites.image_id(:placement_test, :shot)
    end

    test "is stored at the size asked for, resampled pixel by pixel" do
      bytes = IO.iodata_to_binary(Sprites.transmit(:placement_test, size: {20, 20}))
      assert bytes =~ "s=20,v=20"
      raster = Sprites.resampled(Raster.new(2, 2, background: {1, 2, 3, 255}), {5, 3})
      assert {raster.width, raster.height} == {5, 3}
      assert Raster.get_pixel(raster, 4, 2) == {1, 2, 3, 255}
      assert bytes =~ "a=t,i=#{Sprites.image_id(:placement_test, :ship)}"
    end

    test "an animated art is stored once per frame, and the id at a time follows the animation" do
      Atlas.new(:placement_anim, tile: @tile)
      |> Atlas.put(
        :flame,
        [
          Raster.new(@tile, @tile, background: {255, 0, 0, 255}),
          Raster.new(@tile, @tile, background: {0, 255, 0, 255})
        ],
        fps: 10
      )
      |> Atlas.put(:rock, Raster.new(@tile, @tile))
      |> Atlas.install()

      bytes = IO.iodata_to_binary(Sprites.transmit(:placement_anim))
      first = Sprites.image_id(:placement_anim, :flame)
      second = Sprites.image_id(:placement_anim, :flame, 100)
      assert first == Sprites.image_id(:placement_anim, :flame, 0)
      assert second == first + 1
      assert Sprites.image_id(:placement_anim, :flame, 200) == first
      assert bytes =~ "a=t,i=#{first}"
      assert bytes =~ "a=t,i=#{second}"

      assert Sprites.image_id(:placement_anim, :rock, 500) ==
               Sprites.image_id(:placement_anim, :rock)
    end
  end

  describe "a frame with placements" do
    test "places each mover at its cell with a pixel offset, on the sprite layer", %{state: state} do
      {paint, _clear, region} = Surface.image(state, rect(), :world)
      paint = IO.iodata_to_binary(paint)

      ship = Sprites.image_id(:placement_test, :ship)
      assert paint =~ "a=p,i=#{ship}"
      assert paint =~ "z=1"
      assert paint =~ "c=2,r=1"
      assert paint =~ "X=5,Y=10"
      assert region.place =~ "a=p,i=#{ship}"
    end

    test "a mover that only moved is placed again, never deleted first", %{state: state} do
      Surface.image(state, rect(), :world)
      nudged = %{state | movers: [{:ship, {5.45, 5.5}}, {:shot, {6.0, 5.0}}]}
      {moved, _clear, _region} = Surface.image(nudged, rect(), :world)
      moved = IO.iodata_to_binary(moved)

      refute moved =~ "a=d,d=z", "the whole sprite layer was wiped to move one sprite"
      refute moved =~ "a=d,d=i", "a sprite was deleted rather than re-placed where it moved to"
      assert moved =~ "a=p,i=#{Sprites.image_id(:placement_test, :ship)}"
    end

    test "a mover that is gone takes its placement with it", %{state: state} do
      Surface.image(state, rect(), :world)
      {fewer, _clear, _region} = Surface.image(%{state | movers: []}, rect(), :world)

      assert IO.iodata_to_binary(fewer) =~ "a=d",
             "the placement of a mover that left was never taken off the screen"
    end

    test "the sprites are stored at the size of the cells they occupy, once", %{state: state} do
      ship = Sprites.image_id(:placement_test, :ship)
      {paint, _clear, _region} = Surface.image(state, rect(), :world)
      assert IO.iodata_to_binary(paint) =~ "a=t,i=#{ship},f=32,s=20,v=20"
      {again, _clear, _region} = Surface.image(state, rect(), :world)
      refute IO.iodata_to_binary(again) =~ "a=t,i=#{ship}"
    end

    test "the grid is stored at its own size and fitted to the pane by the terminal", %{
      state: state
    } do
      {paint, _clear, region} = Surface.image(state, rect(), {:world, :fitted_grid})
      paint = IO.iodata_to_binary(paint)
      assert paint =~ "s=88,v=88"
      assert paint =~ "c=20,r=10"
      assert region.place =~ "c=20,r=10"
    end

    test "a larger font stores the sprites larger, at the same cell", %{state: state} do
      Context.put_cell_size({16, 32})
      {paint, _clear, _region} = Surface.image(state, rect(), :world)
      paint = IO.iodata_to_binary(paint)
      assert paint =~ "a=t,i=#{Sprites.image_id(:placement_test, :ship)},f=32,s=32,v=32"
      assert paint =~ "X=8,Y=16"
      assert paint =~ "\e[#{2 + 5 + 1};#{3 + 10 + 1}H"
    end

    test "zoomed in the movers are composited, not placed", %{state: state} do
      {paint, _clear, _region} = Surface.image(%{state | zoom: 2}, rect(), :world)
      refute IO.iodata_to_binary(paint) =~ ~r{a=p[^\e]*z=1}
    end

    test "the grid is sent once and only placed again while its tiles do not change", %{
      state: state
    } do
      id = {:world, System.unique_integer()}

      state = %{
        state
        | cell: fn {x, y} -> {:floor, if(rem(x + y, 3) == 0, do: [:shot], else: []), nil} end
      }

      {first, _, _} = Surface.image(state, rect(), id)
      {second, _, _} = Surface.image(%{state | movers: [{:ship, {5.5, 5.5}}]}, rect(), id)

      assert IO.iodata_to_binary(first) =~ "a=t,i="
      refute IO.iodata_to_binary(second) =~ "a=t,i="
      assert IO.iodata_to_binary(second) =~ "a=p,i="

      {moved, _, _} = Surface.image(%{state | focus: {9, 9}}, rect(), id)
      assert IO.iodata_to_binary(moved) =~ "a=t,i="
    end

    test "a mover outside the pane is not placed", %{state: state} do
      {paint, _, _} = Surface.image(%{state | movers: [{:ship, {30.0, 15.0}}]}, rect(), :world)
      refute IO.iodata_to_binary(paint) =~ "a=p,i=#{Sprites.image_id(:placement_test, :ship)}"
    end

    test "clearing removes the grid image and the sprite layer", %{state: state} do
      {_, clear, _} = Surface.image(state, rect(), :world)
      clear = IO.iodata_to_binary(clear)
      assert clear =~ "a=d,d=i"
      assert clear =~ "a=d,d=z,z=1"
    end
  end

  describe "without the terminal's cell size" do
    test "movers are composited into one image instead", %{state: state} do
      Process.delete(:drafter_cell_size)
      {paint, _, _} = Surface.image(state, rect(), :world)
      refute IO.iodata_to_binary(paint) =~ ~r{a=p[^\e]*z=1}
    end
  end

  describe "the session's probed protocol" do
    test "decides between glyphs and pixels", %{state: state} do
      assert Surface.protocol(state) == :kitty
      Context.put_terminal_protocol(:sixel)
      assert Surface.protocol(state) == :sixel
      assert Surface.protocol(%{state | mode: :text}) == nil
      assert Surface.image(%{state | mode: :text}, rect(), :world) == nil
    end

    test "a probe that named no protocol falls back to detecting the session's environment",
         %{state: state} do
      Context.put_terminal_protocol(nil)
      assert Surface.protocol(state) == FrenchCurve.Capability.detect(Context.terminal_env())
      assert Surface.protocol(state) == :kitty
    end
  end

  describe "scrolling by fractions of a tile" do
    test "the grid is placed through a source window shifted by the fraction", %{state: state} do
      {paint, _, region} = Surface.image(%{state | focus: {5.3, 5.2}}, rect(), :world)
      paint = IO.iodata_to_binary(paint)

      assert paint =~ "x=2,y=2,w=80,h=80"
      assert paint =~ "c=20,r=10"
      assert region.place =~ "x=2,y=2,w=80,h=80"
    end

    test "a mover at the focus sits at the same pane cell whatever the fraction", %{state: state} do
      placement = fn focus ->
        {paint, _, _} =
          Surface.image(%{state | focus: focus, movers: [{:ship, focus}]}, rect(), :world)

        paint = IO.iodata_to_binary(paint)

        [_, cursor, offsets] =
          Regex.run(
            ~r/(\e\[\d+;\d+H)\e_Ga=p,i=#{Sprites.image_id(:placement_test, :ship)}[^\e]*?(X=\d+,Y=\d+)/,
            paint
          )

        {cursor, offsets}
      end

      assert placement.({5.0, 5.0}) == placement.({5.3, 5.2})
      assert placement.({5.0, 5.0}) == placement.({5.9, 5.7})
    end

    test "without placements the composed image is cropped to the pane", %{state: state} do
      Process.delete(:drafter_cell_size)
      {paint, _, _} = Surface.image(%{state | focus: {5.3, 5.2}}, rect(), :world)
      assert IO.iodata_to_binary(paint) =~ "s=80,v=80"
    end
  end
end
