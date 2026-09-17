defmodule Cauldron2D.Net.FrameTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Net.Frame

  @sheet %{arts: %{wall: 1, ship: 2, shot: 3}, tile: 16}

  test "the map is rows of art indices, 0 for nothing" do
    cell = fn {x, y} -> if x == y, do: :wall, else: nil end
    map = Frame.map(%{width: 3, height: 2, cell: cell}, @sheet)
    assert map == %{width: 3, height: 2, tile: 16, wrap: false, rows: [[1, 0, 0], [0, 1, 0]]}

    assert Frame.map(%{width: 1, height: 1, cell: fn _ -> nil end, wrap?: true}, @sheet).wrap ==
             true
  end

  test "a frame carries the focus, the movers as index and position, the hud and the outcome" do
    frame =
      Frame.frame(
        %{
          focus: {10.5, 4.25},
          movers: [{:ship, {10.0, 3.75}}, {:shot, {11.0, 4.0}}, {:unknown, {0.0, 0.0}}],
          labels: [{"alice", {10.0, 5.0}, {255, 255, 0}}, {"big", {1, 2}, {0, 255, 0}, scale: 2}]
        },
        [[{"fuel ", {255, 255, 0}}, {"████", {0, 200, 0}}], [{"score 3", nil}]],
        nil,
        @sheet
      )

    assert frame.focus == [10.5, 4.25]
    assert frame.movers == [[2, 10.0, 3.75], [3, 11.0, 4.0]]
    assert frame.hud == [[["fuel ", "#ffff00"], ["████", "#00c800"]], [["score 3", nil]]]
    assert frame.labels == [["alice", 10.0, 5.0, "#ffff00", 1], ["big", 1.0, 2.0, "#00ff00", 2]]
    assert frame.over == nil

    over =
      Frame.frame(
        %{focus: {0.0, 0.0}, movers: []},
        [],
        %{title: "Victory", lines: ["a 3"]},
        @sheet
      )

    assert over.over == %{title: "Victory", lines: ["a 3"]}
  end

  test "hud rows may carry a tag, sent beside the rows only when any row has one" do
    plain = Frame.frame(%{focus: {0.0, 0.0}, movers: []}, [[{"a", nil}]], nil, @sheet)
    refute Map.has_key?(plain, :tags)

    tagged =
      Frame.frame(
        %{focus: {0.0, 0.0}, movers: []},
        [{:fuel, [{"fuel ██", {255, 255, 0}}]}, [{"plain", nil}], {:score, [{"3", nil}]}],
        nil,
        @sheet
      )

    assert tagged.hud == [[["fuel ██", "#ffff00"]], [["plain", nil]], [["3", nil]]]
    assert tagged.tags == ["fuel", nil, "score"]
  end
end
