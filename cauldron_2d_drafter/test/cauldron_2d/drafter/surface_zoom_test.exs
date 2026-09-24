defmodule Cauldron2D.Drafter.SurfaceZoomTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Drafter.Surface
  alias FrenchCurve.Raster

  @tile 32
  @tall 48

  setup_all do
    Atlas.new(:zoom_widget, tile: @tile, void: {6, 7, 11})
    |> Atlas.put(:floor, Raster.new(@tile, @tile, background: {40, 45, 62, 255}))
    |> Atlas.put(:knight, Raster.new(@tile, @tall, background: {245, 232, 200, 255}))
    |> Atlas.install()

    :ok
  end

  defp state(zoom, mode \\ :sextant) do
    Surface.mount(%{
      atlas: :zoom_widget,
      focus: {4.0, 4.0},
      cell: fn _ -> {:floor, [], nil} end,
      projection: :iso,
      zoom: zoom,
      mode: mode
    })
  end

  defp widest(mode), do: List.last(Surface.zoom_levels(:zoom_widget, mode, :iso))

  describe "fitting_zoom/2" do
    test "the tallest art has a tile of room over its head in half the picture" do
      room = 2 * (@tall + @tile)

      for mode <- [:sextant, :braille, :kitty],
          height <- [24, 48, 72, 96, 144, 320, 640],
          zoom <- [2, 1, 0.5] do
        drawn = Surface.fitting_zoom(state(zoom, mode), height)

        assert height / drawn >= room or drawn == widest(mode),
               "#{mode} at height #{height}, zoom #{zoom}: drew at #{drawn}, " <>
                 "leaving #{height / drawn}px"
      end
    end

    test "a picture too short for the art at any zoom draws at the widest one" do
      assert Surface.fitting_zoom(state(2), 24) == widest(:sextant)
    end

    test "a tall picture keeps the zoom that was asked for" do
      assert Surface.fitting_zoom(state(2), 400) == 2
      assert Surface.fitting_zoom(state(1), 400) == 1
    end

    test "it never zooms in further than the caller asked" do
      assert Surface.fitting_zoom(state(0.5), 4000) == 0.5
      assert Surface.fitting_zoom(state(1), 4000) == 1
    end

    test "a sextant pane of two dozen rows steps well back from the closest zoom" do
      drawn = Surface.fitting_zoom(state(2), 24 * 3)

      assert drawn < 1
      assert 24 * 3 / drawn >= 2 * (@tall + @tile)
    end

    test "a picture the size a pixel mode draws keeps the closest zoom" do
      assert Surface.fitting_zoom(state(2, :kitty), 640) == 2
    end

    test "the extra step out is offered in every mode, since it costs nothing" do
      for mode <- [:sextant, :braille, :kitty, :iterm2, :text] do
        assert 0.25 in Surface.zoom_levels(:zoom_widget, mode, :iso)
      end
    end
  end

  describe "Cauldron2D.Atlas.tallest/1" do
    test "answers the tallest art, not the tile" do
      assert Atlas.tallest(:zoom_widget) == @tall
    end
  end
end
