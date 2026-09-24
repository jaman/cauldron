defmodule Cauldron2D.Drafter.SurfaceCostTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Drafter.Surface
  alias Drafter.Session.Context
  alias FrenchCurve.Raster

  @tile 32
  @rect %{x: 0, y: 0, width: 120, height: 34}
  @slack 6

  setup_all do
    Atlas.new(:cost_surface, tile: @tile, void: {6, 7, 11})
    |> Atlas.put(:ground, Raster.new(@tile, @tile, background: {128, 128, 128, 255}))
    |> Atlas.put(:wall, Raster.new(@tile, @tile, background: {180, 140, 100, 255}), height: 2)
    |> Atlas.put(:knight, Raster.new(@tile, 48, background: {250, 250, 250, 255}))
    |> Atlas.install()

    :ok
  end

  setup do
    Context.put_terminal_env(%{"TERM" => "xterm-kitty"})
    on_exit(fn -> Process.delete(:drafter_terminal_env) end)
    :ok
  end

  defp cells({x, y}) when rem(x, 7) == 0 and rem(y, 5) == 0, do: {:ground, [:wall], nil}
  defp cells(_position), do: {:ground, [], nil}

  defp state(projection, zoom) do
    Surface.mount(%{
      atlas: :cost_surface,
      focus: {12.0, 8.5},
      cell: &cells/1,
      projection: projection,
      facing: 3,
      facings: 16,
      density: %{iso: 16, oblique: 16, top: 16, mode7: 6, first_person: 6},
      zoom: zoom,
      mode: :kitty
    })
  end

  defp bytes(projection, zoom) do
    {paint, _clear, _region} = Surface.image(state(projection, zoom), @rect, :cost)
    IO.iodata_length(paint)
  end

  defp pixels(projection, zoom) do
    {{width, height}, _step, _aspect} = Surface.picture(state(projection, zoom), @rect)
    width * height
  end

  describe "what a frame costs the terminal" do
    test "zooming out does not make the isometric picture bigger" do
      near = pixels(:iso, 1)

      for zoom <- [0.5, 0.25] do
        assert pixels(:iso, zoom) <= near,
               "at zoom #{zoom} the isometric view composes #{pixels(:iso, zoom)} pixels " <>
                 "against #{near} at zoom 1; a terminal is sent every one of them, every frame"
      end
    end

    test "zooming out does show more world, so the step is not simply ignored" do
      {far_left, _y} = Surface.world_at(state(:iso, 0.25), @rect, {0, 17})
      {near_left, _y} = Surface.world_at(state(:iso, 1), @rect, {0, 17})
      {middle, _y} = Surface.world_at(state(:iso, 1), @rect, {60, 17})

      assert abs(far_left - middle) > abs(near_left - middle) * 3
    end

    test "zooming in does not make it bigger either" do
      assert pixels(:iso, 2) <= pixels(:iso, 1)
    end

    test "a frame of the sampled views is a fraction of a blitted one" do
      assert pixels(:first_person, 1) * 4 < pixels(:iso, 1)
      assert pixels(:mode7, 1) * 4 < pixels(:iso, 1)
    end

    test "the bytes a frame sends stay within reach of a frame at rest" do
      near = bytes(:iso, 1)

      for zoom <- [0.5, 0.25] do
        assert bytes(:iso, zoom) < near * @slack,
               "zoom #{zoom} sent #{bytes(:iso, zoom)} bytes against #{near} at zoom 1. " <>
                 "More world in the same pixels is a busier picture and compresses less, " <>
                 "which on this scene costs under three times a frame at rest; composing " <>
                 "the picture four times larger for every step out costs fifteen."
      end
    end
  end
end
