defmodule Cauldron2D.Drafter.SurfaceProjectionTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Drafter.Surface
  alias Drafter.Session.Context
  alias FrenchCurve.Raster

  @tile 8
  @roof {200, 40, 40, 255}

  setup_all do
    Atlas.new(:projection_widget, tile: @tile, void: {6, 7, 11})
    |> Atlas.put(:floor, Raster.new(@tile, @tile, background: {40, 45, 62, 255}), glyph: "· ")
    |> Atlas.put(:house, Raster.new(@tile, @tile, background: {160, 120, 80, 255}),
      height: 1,
      faces: %{top: Raster.new(@tile, @tile, background: @roof)}
    )
    |> Atlas.put(:hero, Raster.new(@tile, @tile, background: {245, 232, 200, 255}), glyph: "@ ")
    |> Atlas.install()

    :ok
  end

  setup do
    Context.put_terminal_env(%{"TERM" => "xterm-kitty"})
    on_exit(fn -> Process.delete(:drafter_terminal_env) end)

    state =
      Surface.mount(%{
        atlas: :projection_widget,
        focus: {5.5, 5.5},
        cell: fn
          {7, 5} -> {:floor, [:house], nil}
          _other -> {:floor, [], nil}
        end,
        movers: [{:hero, {5.5, 5.5}, 0.0}],
        id: :map
      })

    {:ok, state: state}
  end

  defp rect(width, height), do: %{x: 0, y: 0, width: width, height: height}

  test "the glyph-set and braille renderings draw the projections too", %{state: state} do
    for projection <- [:iso, :first_person], mode <- [:octant, :sextant, :braille] do
      strips = Surface.render(%{state | projection: projection, mode: mode}, rect(40, 12))
      assert length(strips) == 12, "#{projection} #{mode}"
      assert Enum.all?(strips, &(&1.width == 40)), "#{projection} #{mode}"
    end
  end

  test "plain glyphs draw the isometric and oblique projections, and turn with them",
       %{state: state} do
    top = Surface.render(%{state | mode: :text}, rect(40, 12))

    for projection <- [:iso, :oblique] do
      drawn = Surface.render(%{state | mode: :text, projection: projection}, rect(40, 12))
      refute drawn == top, "#{projection} glyphs should not be the top-down grid"
    end

    patterned = %{
      state
      | mode: :text,
        projection: :iso,
        cell: fn {x, y} -> if x > y, do: {:floor, [:house], nil}, else: {:floor, [], nil} end
    }

    straight = Surface.render(%{patterned | facing: 0}, rect(40, 12))
    turned = Surface.render(%{patterned | facing: 1}, rect(40, 12))

    refute straight == turned
  end

  test "plain glyphs stay top-down where the projection casts rays", %{state: state} do
    top = Surface.render(%{state | mode: :text}, rect(40, 12))

    for projection <- [:mode7, :first_person] do
      drawn = Surface.render(%{state | mode: :text, projection: projection}, rect(40, 12))
      assert drawn == top, "#{projection} glyphs should be the top-down grid"
    end
  end

  test "plain glyphs zoom through the text levels where they draw top-down" do
    text = Surface.zoom_levels(:projection_widget, :text, :top)

    for projection <- [:mode7, :first_person] do
      assert Surface.zoom_levels(:projection_widget, :text, projection) == text
    end

    assert Surface.zoom_levels(:projection_widget, :text, :iso) == [2, 1, 0.5, 0.25]
  end

  test "the oblique view is fixed under a plain facings count and turns under its own",
       %{state: state} do
    patterned = %{
      state
      | mode: :text,
        projection: :oblique,
        cell: fn {x, y} -> if x > y, do: {:floor, [:house], nil}, else: {:floor, [], nil} end
    }

    plain = %{patterned | facings: 4}

    assert Surface.render(%{plain | facing: 1}, rect(40, 12)) ==
             Surface.render(%{plain | facing: 0}, rect(40, 12))

    asked = %{patterned | facings: %{oblique: 4}}

    refute Surface.render(%{asked | facing: 1}, rect(40, 12)) ==
             Surface.render(%{asked | facing: 0}, rect(40, 12))
  end

  test "a facings map still turns the isometric view", %{state: state} do
    patterned = %{
      state
      | mode: :text,
        projection: :iso,
        facings: %{iso: 4, oblique: 4},
        cell: fn {x, y} -> if x > y, do: {:floor, [:house], nil}, else: {:floor, [], nil} end
    }

    refute Surface.render(%{patterned | facing: 1}, rect(40, 12)) ==
             Surface.render(%{patterned | facing: 0}, rect(40, 12))
  end

  test "a pane cell maps to a world point in the top and isometric views and to nothing in first person",
       %{state: state} do
    assert {x, y} = Surface.world_at(state, rect(40, 12), {20, 6})
    assert_in_delta x, 5.5, 0.6
    assert_in_delta y, 5.5, 0.6

    assert {ix, iy} = Surface.world_at(%{state | projection: :iso}, rect(40, 12), {20, 6})
    assert_in_delta ix, 5.5, 0.6
    assert_in_delta iy, 5.5, 0.6

    assert Surface.world_at(%{state | projection: :first_person}, rect(40, 12), {20, 6}) == nil
  end

  test "movers with a heading are drawn by the top-down renderings as before", %{state: state} do
    strips = Surface.render(%{state | mode: :text}, rect(40, 12))
    text = Enum.map_join(strips, "\n", fn strip -> Enum.map_join(strip.segments, & &1.text) end)

    assert text =~ "@ "
  end
end

defmodule Cauldron2D.Drafter.SurfaceSwitchTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Drafter.Surface
  alias Drafter.Session.Context
  alias FrenchCurve.Raster

  setup_all do
    Atlas.new(:switch_widget, tile: 8, void: {6, 7, 11})
    |> Atlas.put(:floor, Raster.new(8, 8, background: {40, 45, 62, 255}), glyph: "· ")
    |> Atlas.put(:hero, Raster.new(8, 8, background: {245, 232, 200, 255}), glyph: "@ ")
    |> Atlas.install()

    :ok
  end

  setup do
    Context.put_terminal_env(%{"TERM" => "xterm-ghostty"})
    Context.put_terminal_protocol(:kitty)
    Context.put_cell_size({10, 20})

    on_exit(fn ->
      Process.delete(:drafter_terminal_env)
      Process.delete(:drafter_terminal_protocol)
      Process.delete(:drafter_cell_size)
    end)

    state =
      Surface.mount(%{
        atlas: :switch_widget,
        focus: {5.5, 5.5},
        cell: fn _ -> {:floor, [], nil} end,
        movers: [{:hero, {5.5, 5.5}}],
        id: :map
      })

    {:ok, state: state}
  end

  defp rect, do: %{x: 0, y: 0, width: 40, height: 12}

  test "a surface drawing glyph sets or glyphs says its image is not active, so the compositor takes the picture down",
       %{state: state} do
    assert Surface.image_active?(state)
    refute Surface.image_active?(%{state | mode: :octant})
    refute Surface.image_active?(%{state | mode: :text})
    refute Surface.image_active?(%{state | focus: nil})
  end

  test "a projection frame after a placed top-down frame takes the placed sprites down with it",
       %{state: state} do
    {top_paint, _clear, _region} = Surface.image(state, rect(), :map)
    top = IO.iodata_to_binary(top_paint)

    assert [[_whole, sprite, placement]] =
             Regex.scan(~r/a=p,i=(\d+),q=2,C=1,p=(\d+),z=1/, top)

    {paint, clear, _region} = Surface.image(%{state | projection: :iso}, rect(), :map)

    assert IO.iodata_to_binary(paint) =~ "a=d,d=i,i=#{sprite},q=2,p=#{placement}"
    assert IO.iodata_to_binary(clear) =~ "a=d,d=z,z=1"
  end
end

defmodule Cauldron2D.Drafter.SurfaceModesTest do
  @moduledoc """
  The projections added beside the isometric view: the oblique grid, the mode 7 ground,
  and the isometric view's rotation in more than four steps.
  """

  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Drafter.Surface
  alias FrenchCurve.Raster

  @tile 8

  setup_all do
    Atlas.new(:modes_test, tile: @tile, void: {5, 6, 9})
    |> Atlas.put(:floor, Raster.new(@tile, @tile, background: {40, 90, 60, 255}), glyph: ". ")
    |> Atlas.put(:wall, Raster.new(@tile, @tile, background: {120, 120, 130, 255}),
      glyph: "##",
      height: 1
    )
    |> Atlas.put(:hero, Raster.new(@tile, @tile * 2, background: {220, 80, 80, 255}), glyph: "@ ")
    |> Atlas.install()

    :ok
  end

  defp cell({x, y}) when x in 0..15 and y in 0..15 do
    if rem(x, 7) == 0 and rem(y, 5) == 0, do: {:floor, [:wall], nil}, else: {:floor, [], nil}
  end

  defp cell(_beyond), do: :void

  defp surface(projection, extra \\ []) do
    fields =
      [
        atlas: :modes_test,
        focus: {8.0, 8.0},
        cell: &cell/1,
        movers: [{:hero, {8.5, 8.5}, 1.0}],
        projection: projection,
        mode: :kitty
      ] ++ extra

    struct!(Surface, fields)
  end

  defp drawn(projection, extra \\ []) do
    state = surface(projection, extra)
    {paint, _clear, _place} = Surface.image(state, %{x: 0, y: 0, width: 40, height: 12}, :probe)
    IO.iodata_to_binary(paint)
  end

  test "every projection draws something, and they do not draw the same thing" do
    pictures =
      for projection <- Surface.projections(), into: %{}, do: {projection, drawn(projection)}

    for {projection, bytes} <- pictures do
      assert byte_size(bytes) > 64, "#{projection} drew nothing"
    end

    assert pictures |> Map.values() |> Enum.uniq() |> length() == map_size(pictures)
  end

  test "the isometric view turns in as many steps as it is given" do
    quarter = drawn(:iso, facing: 1)
    eighth = drawn(:iso, facing: 1, facings: 8)

    assert quarter != eighth, "an eighth of a turn is not a quarter"
    assert drawn(:iso, facing: 2, facings: 8) != eighth
  end

  test "a fraction of a step turns the view too" do
    assert drawn(:iso, facing: 0.5, facings: 4) != drawn(:iso, facing: 0, facings: 4)
  end

  test "the oblique and mode 7 views answer for the tile under a cell" do
    rect = %{x: 0, y: 0, width: 40, height: 12}

    assert {x, y} = Surface.world_at(surface(:oblique), rect, {20, 6})
    assert x > 0 and y > 0

    assert {_x, _y} = Surface.world_at(surface(:mode7), rect, {20, 10})
    assert Surface.world_at(surface(:mode7), rect, {20, 0}) == nil, "nothing above the horizon"
  end
end
