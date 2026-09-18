defmodule Cauldron2D.Drafter.SurfaceLabelsTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Drafter.{Sprites, Surface}
  alias Drafter.Session.Context
  alias FrenchCurve.Raster

  @tile 8

  setup_all do
    Atlas.new(:label_widget_test, tile: @tile, void: {0, 0, 0})
    |> Atlas.put(:floor, Raster.new(@tile, @tile, background: {40, 45, 62, 255}),
      glyph: "· ",
      color: {60, 66, 88}
    )
    |> Atlas.put(:ship, Raster.new(@tile, @tile, background: {245, 232, 200, 255}),
      glyph: "> ",
      color: {245, 235, 200}
    )
    |> Atlas.install()

    :ok
  end

  setup do
    state =
      Surface.mount(%{
        atlas: :label_widget_test,
        focus: {5, 5},
        cell: fn _ -> {:floor, [], nil} end,
        labels: [{"alice", {5.0, 6.0}, {255, 255, 0}}],
        id: :map
      })

    {:ok, state: state}
  end

  defp rect(width, height), do: %{x: 0, y: 0, width: width, height: height}

  defp text(strips),
    do: Enum.map_join(strips, "\n", fn strip -> Enum.map_join(strip.segments, & &1.text) end)

  test "in text mode a label's characters overlay the glyphs at its tile, in its colour", %{
    state: state
  } do
    strips = Surface.render(%{state | mode: :text}, rect(20, 10))
    drawn = text(strips)
    assert drawn =~ "alice"
    row = Enum.at(strips, 6)
    assert Enum.any?(row.segments, &(&1.text == "a" and &1.style.fg == {255, 255, 0}))
    assert Enum.all?(strips, &(&1.width == 20))
  end

  test "a label off the pane is left out, and one half off is cut", %{state: state} do
    drawn =
      text(
        Surface.render(
          %{state | mode: :text, labels: [{"far", {30.0, 30.0}, {255, 0, 0}}]},
          rect(20, 10)
        )
      )

    refute drawn =~ "far"

    cut =
      text(
        Surface.render(
          %{state | mode: :text, labels: [{"edgeword", {7.5, 5.0}, {255, 0, 0}}]},
          rect(20, 10)
        )
      )

    assert cut =~ "edgew"
    refute cut =~ "edgeword"
  end

  test "labels are folded in by a re-render like every other prop", %{state: state} do
    assert Surface.update(%{labels: []}, state).labels == []
    assert Surface.update(%{focus: {1, 1}}, state).labels == state.labels

    assert Surface.from_component_opts(nil, labels: [{"x", {0, 0}, {1, 2, 3}}], __widget_id__: :m).labels ==
             [{"x", {0, 0}, {1, 2, 3}}]
  end

  test "with placements a label is a stored image at the drawn scale, placed at its cell", %{
    state: state
  } do
    Context.put_terminal_protocol(:kitty)
    Context.put_cell_size({10, 20})

    on_exit(fn ->
      Process.delete(:drafter_terminal_protocol)
      Process.delete(:drafter_cell_size)
    end)

    {paint, _clear, region} = Surface.image(%{state | mode: :kitty}, rect(20, 10), :map)
    paint = IO.iodata_to_binary(paint)
    id = Sprites.label_id(:label_widget_test, "alice", {255, 255, 0}, 3)
    assert paint =~ "a=t,i=#{id}"
    assert region.place =~ "a=p,i=#{id}"

    {again, _clear, _region} = Surface.image(%{state | mode: :kitty}, rect(20, 10), :map)
    refute IO.iodata_to_binary(again) =~ "a=t,i=#{id}"
  end
end
