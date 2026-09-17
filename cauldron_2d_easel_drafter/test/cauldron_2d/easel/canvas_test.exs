defmodule Cauldron2D.Easel.Drafter.CanvasTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Easel
  alias Cauldron2D.Easel.Drafter.Canvas

  defp bg(strip, column), do: strip.segments |> Enum.at(column) |> Map.get(:style) |> Map.get(:bg)

  test "each pixel is a block of cells in its colour, transparent ones a checkerboard" do
    easel = Easel.new(2, 2, palette: [{"R", :red}]) |> Easel.paint({1, 0}, "R")
    state = Canvas.mount(%{easel: easel, zoom: 4, id: :canvas})
    strips = Canvas.render(state, %{x: 0, y: 0, width: 8, height: 4})
    assert length(strips) == 4
    assert bg(hd(strips), 1) == {255, 0, 0}
    assert bg(hd(strips), 0) != {255, 0, 0}
    assert bg(hd(strips), 0) != bg(Enum.at(strips, 2), 0)
    assert Enum.all?(strips, &(&1.width == 8))
  end

  test "the onion skin shows the frame before faintly under the one in hand" do
    easel =
      Easel.new(1, 1, palette: [{"W", :white}]) |> Easel.paint({0, 0}, "W") |> Easel.add_frame()

    plain =
      Canvas.render(Canvas.mount(%{easel: easel, zoom: 2, id: :c}), %{
        x: 0,
        y: 0,
        width: 2,
        height: 1
      })

    onion =
      Canvas.render(Canvas.mount(%{easel: easel, zoom: 2, onion: true, id: :c}), %{
        x: 0,
        y: 0,
        width: 2,
        height: 1
      })

    {pr, _, _} = bg(hd(plain), 0)
    {orr, _, _} = bg(hd(onion), 0)
    assert orr > pr
  end

  test "the largest zoom that fits is even and at least 2" do
    easel = Easel.new(16, 16)
    assert Canvas.fit(easel, {64, 32}) == 4
    assert Canvas.fit(easel, {200, 20}) == 2
    assert Canvas.fit(easel, {10, 4}) == 2
    assert Canvas.cell_size(6) == {6, 3}
  end
end
