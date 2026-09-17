defmodule Cauldron2D.Net.RoundTripTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Net.{Frame, Wire}

  @sheet %{arts: %{wall: 1, ship: 2}, tile: 16}

  defp over_json(term), do: term |> Jason.encode!() |> Jason.decode!()

  test "a frame Frame writes is the frame Wire reads" do
    written =
      Frame.frame(
        %{
          focus: {10.5, 4.25},
          movers: [{:ship, {10.0, 3.75}}],
          labels: [{"me", {1.0, 2.0}, {255, 0, 0}}]
        },
        [[{"fuel", {255, 255, 0}}, {"3", nil}]],
        %{title: "Over", lines: ["a"]},
        @sheet
      )

    read = written |> over_json() |> Wire.frame()

    assert read.focus == {10.5, 4.25}
    assert read.movers == [{2, 10.0, 3.75}]
    assert read.hud == [[{"fuel", "#ffff00"}, {"3", nil}]]
    assert read.labels == [{"me", 1.0, 2.0, "#ff0000", 1}]
    assert read.over == %{"title" => "Over", "lines" => ["a"]}
  end

  test "a map Frame writes is the map Wire reads" do
    written =
      Frame.map(
        %{width: 2, height: 1, cell: fn {x, _} -> if x == 0, do: :wall end, wrap?: true},
        @sheet
      )

    assert written |> over_json() |> Wire.map() == %{
             width: 2,
             height: 1,
             tile: 16,
             wrap: true,
             rows: [[1, 0]]
           }
  end
end
