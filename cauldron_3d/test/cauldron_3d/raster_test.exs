defmodule Cauldron3D.RasterTest do
  use ExUnit.Case, async: true

  alias Cauldron3D.{Camera, Polygon, Render, View}

  test "of two crossing polygons each pixel shows the nearer, split where they cross" do
    view = View.new(Camera.first_person({0.0, 0.0, 0.0}, 0.0, 0.0), {40, 20})

    square = %Polygon{
      points: [
        {100.0, -30.0, -30.0},
        {100.0, 30.0, -30.0},
        {100.0, 30.0, 30.0},
        {100.0, -30.0, 30.0}
      ],
      paint: {:flat, 1}
    }

    wall = %Polygon{
      points: [
        {60.0, -40.0, -10.0},
        {200.0, 40.0, -10.0},
        {200.0, 40.0, 10.0},
        {60.0, -40.0, 10.0}
      ],
      paint: {:flat, 2}
    }

    frame = Render.draw(view, [square, wall], bands: 1)
    row = binary_part(frame.pixels, 10 * 40, 40)

    crossing_y = -40.0 + 80.0 * (100.0 - 60.0) / (200.0 - 60.0)
    crossing_x = 20 + -crossing_y / 100.0 * 20

    for x <- 14..25 do
      expected = if x + 0.5 > crossing_x, do: 2, else: 1
      assert :binary.at(row, x) == expected, "column #{x}"
    end
  end
end
