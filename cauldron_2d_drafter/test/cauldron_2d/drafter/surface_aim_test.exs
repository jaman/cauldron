defmodule Cauldron2D.Drafter.SurfaceAimTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Drafter.Surface
  alias Cauldron2D.Projection.{Iso, Oblique}
  alias Drafter.Session.Context
  alias FrenchCurve.Raster

  @tile 32
  @rect %{x: 0, y: 0, width: 120, height: 34}
  @focus {12.0, 8.5}

  setup_all do
    Atlas.new(:aim_surface, tile: @tile, void: {6, 7, 11})
    |> Atlas.put(:ground, Raster.new(@tile, @tile, background: {128, 128, 128, 255}))
    |> Atlas.put(:knight, Raster.new(@tile, 48, background: {250, 250, 250, 255}))
    |> Atlas.install()

    :ok
  end

  setup do
    Context.put_terminal_env(%{"TERM" => "xterm-kitty"})
    on_exit(fn -> Process.delete(:drafter_terminal_env) end)
    :ok
  end

  defp state(projection, mode) do
    Surface.mount(%{
      atlas: :aim_surface,
      focus: @focus,
      cell: fn _ -> {:ground, [], nil} end,
      projection: projection,
      facing: 3,
      facings: 16,
      tilt: 1.0,
      density: 16,
      zoom: 1,
      mode: mode
    })
  end

  defp cell_of(state, {px, py}) do
    {_size, {across, down}, _aspect} = Surface.picture(state, @rect)
    {px / across, py / down}
  end

  defp opts(state, kind) do
    {size, _step, aspect} = Surface.picture(state, @rect)
    zoom = Surface.fitting_zoom(state, elem(size, 1))
    drawn = {elem(size, 0) / zoom, elem(size, 1) / zoom}
    shrink = if kind == :iso, do: [shrink: max(1, round(1 / zoom))], else: []

    [
      focus: @focus,
      cell: state.cell,
      size: drawn,
      facing: 3,
      facings: 16,
      tilt: 1.0 * aspect,
      squash: 0.5 * aspect
    ] ++ shrink
  end

  defp close?({ax, ay}, {bx, by}, slack), do: abs(ax - bx) < slack and abs(ay - by) < slack

  describe "the point under a cell, in every mode the surface draws" do
    for mode <- [:kitty, :sextant, :quad, :braille] do
      test "isometric in #{mode}" do
        state = state(:iso, unquote(mode))
        zoom = Surface.fitting_zoom(state, elem(elem(Surface.picture(state, @rect), 0), 1))

        for world <- [{12.0, 8.5}, {14.0, 9.5}, {10.5, 6.5}] do
          {px, py} = Iso.project(:aim_surface, world, opts(state, :iso))
          back = Surface.world_at(state, @rect, cell_of(state, {px * zoom, py * zoom}))

          assert close?(back, world, 0.05),
                 "#{unquote(mode)}: clicked #{inspect(world)}, got #{inspect(back)}"
        end
      end
    end

    for mode <- [:kitty, :sextant, :braille] do
      test "oblique in #{mode}" do
        state = state(:oblique, unquote(mode))
        zoom = Surface.fitting_zoom(state, elem(elem(Surface.picture(state, @rect), 0), 1))

        for world <- [{12.0, 8.5}, {14.0, 9.5}] do
          {px, py} = Oblique.project(:aim_surface, world, opts(state, :oblique))
          back = Surface.world_at(state, @rect, cell_of(state, {px * zoom, py * zoom}))

          assert close?(back, world, 0.05),
                 "#{unquote(mode)}: clicked #{inspect(world)}, got #{inspect(back)}"
        end
      end
    end
  end

  describe "the top-down view" do
    test "answers for the zoom it is actually drawn at, not the one asked for" do
      asked =
        Surface.mount(%{
          atlas: :aim_surface,
          focus: @focus,
          cell: fn _ -> {:ground, [], nil} end,
          projection: :top,
          zoom: 0.7,
          mode: :kitty
        })

      drawn = %{
        asked
        | zoom: Enum.min_by(Surface.zoom_levels(:aim_surface, :kitty), &abs(:math.log(&1 / 0.7)))
      }

      assert Surface.world_at(asked, @rect, {30, 12}) == Surface.world_at(drawn, @rect, {30, 12})
    end
  end

  describe "the plain glyph mode" do
    test "has no picture, and answers from the grid above" do
      state = state(:iso, :text)

      assert Surface.picture(state, @rect) == nil
      assert {_x, _y} = Surface.world_at(state, @rect, {30, 12})
    end
  end
end
