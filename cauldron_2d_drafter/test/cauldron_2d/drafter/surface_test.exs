defmodule Cauldron2D.Drafter.SurfaceTest do
  @moduledoc """
  The widget's two renderings, exercised without a terminal.

  The text path is checked as strips of segments. The pixel path is checked as bytes: that a
  frame produces a transmit and a placement, that the placement is sized to the pane, and that
  the previous frame is deleted before the next is drawn.
  """

  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Drafter.Surface
  alias FrenchCurve.Raster

  @tile 8

  setup_all do
    Atlas.new(:widget_test, tile: @tile, void: {6, 7, 11})
    |> Atlas.put(:floor, Raster.new(@tile, @tile, background: {40, 45, 62, 255}),
      glyph: "· ",
      color: {60, 66, 88}
    )
    |> Atlas.put(:player, Raster.new(@tile, @tile, background: {245, 232, 200, 255}),
      glyph: "@ ",
      color: {245, 235, 200}
    )
    |> Atlas.install()

    :ok
  end

  setup do
    state =
      Surface.mount(%{
        atlas: :widget_test,
        focus: {5, 5},
        cell: fn
          {5, 5} -> {:floor, [:player], nil}
          {0, _} -> :void
          _other -> {:floor, [], nil}
        end,
        id: :map
      })

    {:ok, state: state}
  end

  defp rect(width, height), do: %{x: 0, y: 0, width: width, height: height}

  describe "text mode" do
    setup %{state: state}, do: {:ok, state: %{state | mode: :text}}

    test "fills the pane exactly", %{state: state} do
      strips = Surface.render(state, rect(80, 24))

      assert length(strips) == 24
      assert Enum.all?(strips, &(&1.width == 80))
    end

    test "draws what the cell function said was there", %{state: state} do
      drawn =
        state
        |> Surface.render(rect(80, 24))
        |> Enum.map_join("\n", fn strip -> Enum.map_join(strip.segments, & &1.text) end)

      assert drawn =~ "@ "
      assert drawn =~ "· "
    end

    test "produces no image", %{state: state} do
      assert Surface.image(state, rect(80, 24), :map) == nil
    end
  end

  describe "braille mode" do
    setup %{state: state}, do: {:ok, state: %{state | mode: :braille}}

    test "fills the pane with braille cells and produces no image", %{state: state} do
      strips = Surface.render(state, rect(80, 24))

      assert length(strips) == 24
      assert Enum.all?(strips, &(&1.width == 80))
      assert Surface.image(state, rect(80, 24), :map) == nil
      assert Surface.protocol(state) == nil
    end

    test "lights the bright art and leaves the dark floor unlit", %{state: state} do
      text = fn strips ->
        Enum.map_join(strips, "\n", fn strip -> Enum.map_join(strip.segments, & &1.text) end)
      end

      drawn = text.(Surface.render(state, rect(80, 24)))

      floor_only =
        text.(Surface.render(%{state | cell: fn _ -> {:floor, [], nil} end}, rect(80, 24)))

      assert String.contains?(drawn, "⣿")
      refute String.contains?(floor_only, "⣿")
      assert String.contains?(floor_only, "⠀")
    end

    test "scrolls by fractions of a tile like the pixel modes", %{state: state} do
      text = fn strips ->
        Enum.map_join(strips, "\n", fn strip -> Enum.map_join(strip.segments, & &1.text) end)
      end

      lit = %{
        state
        | cell: fn
            {20, 10} -> {:floor, [:player], nil}
            _ -> {:floor, [], nil}
          end
      }

      whole = text.(Surface.render(%{lit | focus: {20, 10}}, rect(20, 10)))
      shifted = text.(Surface.render(%{lit | focus: {20.25, 10}}, rect(20, 10)))

      assert whole != shifted
    end
  end

  describe "pixel mode" do
    setup %{state: state} do
      kept = {System.get_env("TERM"), System.get_env("TERM_PROGRAM")}

      on_exit(fn ->
        {term, program} = kept
        if term, do: System.put_env("TERM", term), else: System.delete_env("TERM")

        if program,
          do: System.put_env("TERM_PROGRAM", program),
          else: System.delete_env("TERM_PROGRAM")
      end)

      {:ok, state: %{state | mode: :kitty}}
    end

    defp on_a_real_kitty do
      System.delete_env("TERM_PROGRAM")
      System.put_env("TERM", "xterm-kitty")
    end

    defp on_iterm do
      System.delete_env("KITTY_WINDOW_ID")
      System.put_env("TERM", "xterm-256color")
      System.put_env("TERM_PROGRAM", "iTerm.app")
      System.put_env("TERM_PROGRAM_VERSION", "3.5.0")
    end

    test "transmits an image and places it over the pane", %{state: state} do
      on_a_real_kitty()
      {paint, _clear, region} = Surface.image(state, rect(80, 24), :map)
      paint = IO.iodata_to_binary(paint)

      assert paint =~ "\e_G"
      assert paint =~ "a=t,i="
      assert paint =~ "a=p,i="
      assert paint =~ "c=80,r=24"
      assert %{dx: 0, dy: 0, cols: 80, rows: 24, place: place} = region

      assert place =~ "a=p,i="
      refute place =~ "a=t,i="
      assert String.ends_with?(paint, place)
    end

    test "a kitty terminal with no placements draws in one command", %{state: state} do
      on_iterm()
      {paint, clear, region} = Surface.image(state, rect(80, 24), :map)
      paint = IO.iodata_to_binary(paint)

      assert paint =~ "a=T", "transmitted and displayed together"
      refute paint =~ "a=t,i=", "storing it would leave a picture the terminal never draws"
      refute paint =~ "a=p", "and a placement means nothing there"
      assert paint =~ "c=80,r=24", "still fitted to the pane"
      assert region.place == nil, "so the compositor sends the picture again instead"

      assert clear =~ "a=d",
             "an overlay outlives the text and the screen, so it has to be deletable"

      assert String.starts_with?(paint, clear), "and each frame removes the one before it"
    end

    test "iTerm itself is given its own inline protocol, not a kitty overlay", %{state: state} do
      on_iterm()

      assert FrenchCurve.Capability.detect(System.get_env()) == :iterm2

      paint =
        %{state | mode: :iterm2}
        |> Surface.image(rect(80, 24), :map)
        |> elem(0)
        |> IO.iodata_to_binary()

      assert String.starts_with?(paint, "\e]1337"), "cells, which the screen takes away on exit"
      refute paint =~ "a=T"
    end

    test "compresses by default, and can be told not to", %{state: state} do
      on_a_real_kitty()
      {compressed, _, _} = Surface.image(state, rect(80, 24), :map)
      {plain, _, _} = Surface.image(%{state | compress: false}, rect(80, 24), :map)

      assert IO.iodata_to_binary(compressed) =~ "o=z"
      refute IO.iodata_to_binary(plain) =~ "o=z"
      assert byte_size(IO.iodata_to_binary(compressed)) < byte_size(IO.iodata_to_binary(plain))
    end

    test "clears the previous frame before drawing the next", %{state: state} do
      on_a_real_kitty()
      {paint, clear, _region} = Surface.image(state, rect(80, 24), :map)

      assert clear =~ "a=d"
      assert String.starts_with?(IO.iodata_to_binary(paint), clear)
    end

    test "renders blank cells beneath the image", %{state: state} do
      strips = Surface.render(state, rect(80, 24))

      assert length(strips) == 24

      assert Enum.all?(strips, fn strip ->
               Enum.all?(strip.segments, &(String.trim(&1.text) == ""))
             end)
    end
  end

  describe "zoom" do
    defp text(strips),
      do: Enum.map_join(strips, "\n", fn strip -> Enum.map_join(strip.segments, & &1.text) end)

    defp asked(state, rect) do
      {:ok, seen} = Agent.start_link(fn -> MapSet.new() end)

      counting = %{
        state
        | cell: fn tile ->
            Agent.update(seen, &MapSet.put(&1, tile))
            state.cell.(tile)
          end
      }

      Surface.render(counting, rect)
      Surface.image(counting, rect, :map)
      tiles = Agent.get(seen, & &1)
      Agent.stop(seen)
      tiles
    end

    test "in text mode a tile at zoom 2 is four cells wide and two rows tall, and at 0.5 every other tile is drawn",
         %{state: state} do
      one = %{state | mode: :text, focus: {5, 5}}

      lines =
        one |> Map.put(:zoom, 2) |> Surface.render(rect(20, 10)) |> text() |> String.split("\n")

      assert Enum.count(lines, &String.contains?(&1, "@ @ ")) == 2
      assert Enum.count(lines, &String.contains?(&1, "· @ @ · ")) == 2

      wide = asked(%{one | zoom: 0.5}, rect(20, 10))
      assert Enum.any?(wide, fn {x, _} -> x >= 5 + 8 end)
      assert Enum.all?(wide, fn {x, y} -> rem(x - 5, 2) == 0 and rem(y - 5, 2) == 0 end)

      lines =
        one |> Map.put(:zoom, 0.5) |> Surface.render(rect(20, 10)) |> text() |> String.split("\n")

      assert length(lines) == 10 and Enum.all?(lines, &(String.length(&1) == 20))
    end

    test "in braille mode zoom 2 lights the art over four times the cells", %{state: state} do
      braille = %{state | mode: :braille}

      lit = fn zoom ->
        braille
        |> Map.put(:zoom, zoom)
        |> Surface.render(rect(40, 20))
        |> text()
        |> String.graphemes()
        |> Enum.count(&(&1 == "⣿"))
      end

      assert lit.(2) == 4 * lit.(1)
      assert lit.(0.5) < lit.(1)
    end

    test "in pixel mode zoom in transmits fewer pixels fitted to the same pane, zoom out the same pixels over more tiles",
         %{state: state} do
      on_a_real_kitty()
      pixel = %{state | mode: :kitty, placements: false}
      {native, _, _} = Surface.image(pixel, rect(80, 24), :map)
      {closer, _, _} = Surface.image(%{pixel | zoom: 2}, rect(80, 24), :map)
      {farther, _, _} = Surface.image(%{pixel | zoom: 0.5}, rect(80, 24), :map)
      assert IO.iodata_to_binary(native) =~ "s=320,v=192"
      assert IO.iodata_to_binary(closer) =~ "s=160,v=96"
      assert IO.iodata_to_binary(closer) =~ "c=80,r=24"
      assert IO.iodata_to_binary(farther) =~ "s=320,v=192"

      assert Enum.count(asked(%{pixel | zoom: 0.5}, rect(80, 24))) >
               4 * Enum.count(asked(%{pixel | zoom: 2}, rect(80, 24)))
    end

    test "a sixel terminal gets the zoomed-in image scaled up itself, since sixels cannot be fitted",
         %{state: state} do
      pixel = %{state | mode: :sixel}
      {native, _, _} = Surface.image(pixel, rect(80, 24), :map)
      {closer, _, _} = Surface.image(%{pixel | zoom: 2}, rect(80, 24), :map)
      assert IO.iodata_to_binary(native) =~ "\"1;1;320;192"
      assert IO.iodata_to_binary(closer) =~ "\"1;1;320;192"
    end

    test "the levels a surface can draw exactly, by mode" do
      assert Surface.zoom_levels(:widget_test, :text) == [4, 2, 1, 0.5, 0.25, 0.125, 0.0625]
      assert Surface.zoom_levels(:widget_test, :braille) == [2, 1, 0.5, 0.25]
      assert Surface.zoom_levels(:widget_test, :kitty) == [4, 2, 1, 0.5, 0.25, 0.125]
      assert Surface.zoom_levels(:widget_test, nil) == Surface.zoom_levels(:widget_test, :kitty)
    end

    test "zoom mounts at 1 and can be re-rendered", %{state: state} do
      assert state.zoom == 1
      assert Surface.update(%{zoom: 2}, state).zoom == 2
    end
  end

  describe "mounting" do
    test "takes props as a map or as a keyword list, the same either way" do
      as_map = Surface.mount(%{atlas: :widget_test, focus: {1, 2}, compress: false})
      as_list = Surface.mount(atlas: :widget_test, focus: {1, 2}, compress: false)

      assert as_map == as_list
    end

    test "compress: false means false, not the default" do
      assert Surface.mount(%{compress: false}).compress == false
      assert Surface.mount(%{}).compress == true
    end

    test "what is not given falls back to its documented default" do
      state = Surface.mount(%{})

      assert state.movers == []
      assert state.mode == nil
      assert state.on_geometry == nil
    end
  end

  describe "updating" do
    test "takes new props rather than silently keeping the old", %{state: state} do
      moved = Surface.update(%{focus: {9, 9}}, state)

      assert moved.focus == {9, 9}
      assert Surface.update(%{}, state).focus == {5, 5}
    end

    test "a key absent from a re-render leaves that part of the view alone", %{state: state} do
      kept = Surface.update(%{focus: {9, 9}}, %{state | mode: :kitty, compress: false})

      assert kept.mode == :kitty
      assert kept.compress == false
    end

    test "every option can be changed by a re-render, not only the camera ones", %{state: state} do
      changed =
        Surface.update(
          %{
            mode: :text,
            compress: false,
            on_geometry: :moved,
            atlas: :other,
            movers: [{:a, {1, 1}}]
          },
          state
        )

      assert changed.mode == :text
      assert changed.compress == false
      assert changed.on_geometry == :moved
      assert changed.atlas == :other
      assert changed.movers == [{:a, {1, 1}}]
    end

    test "a mode that was forced can be unforced again", %{state: state} do
      forced = %{state | mode: :kitty}

      assert Surface.update(%{mode: nil}, forced).mode == nil
      assert Surface.update(%{}, forced).mode == :kitty
    end
  end

  describe "a frame that cannot be composed" do
    test "is reported rather than showing as a blank pane", %{state: state} do
      broken = %{state | mode: :kitty, atlas: :no_such_atlas}

      logged =
        ExUnit.CaptureLog.capture_log(fn ->
          assert Surface.image(broken, rect(80, 24), :map) == nil
        end)

      assert logged =~ "no atlas installed under :no_such_atlas"
      assert logged =~ "pane is blank"
    end

    test "is logged once rather than on every frame", %{state: state} do
      broken = %{state | mode: :kitty, atlas: :no_such_atlas}

      logged =
        ExUnit.CaptureLog.capture_log(fn ->
          for _frame <- 1..5, do: Surface.image(broken, rect(80, 24), :map)
        end)

      assert length(String.split(logged, "pane is blank")) == 2
    end
  end

  test "renders something rather than crashing before it has a world", %{state: state} do
    assert Surface.render(%{state | cell: nil}, rect(10, 4)) |> length() == 4
    assert Surface.image(%{state | focus: nil}, rect(10, 4), :map) == nil
  end

  test "answers to the tag a component tree uses" do
    assert Surface.component_tag() == :cauldron_surface

    props =
      Surface.from_component_opts(nil, atlas: :widget_test, focus: {1, 2}, __widget_id__: :m)

    assert props.atlas == :widget_test
    assert props.focus == {1, 2}
    assert props.id == :m
  end
end
