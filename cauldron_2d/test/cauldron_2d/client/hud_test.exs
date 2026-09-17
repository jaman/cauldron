defmodule Cauldron2D.Client.HudTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Client.Hud

  test "runs are normalised to text and a style" do
    assert Hud.runs(["plain", {"red", {255, 0, 0}}, {"bold", %{bold: true}}, {"none", nil}]) ==
             [{"plain", %{}}, {"red", %{fg: {255, 0, 0}}}, {"bold", %{bold: true}}, {"none", %{}}]

    assert Hud.runs({:score, ["a"]}) == [{"a", %{}}]
    assert Hud.tag({:score, ["a"]}) == :score
    assert Hud.tag(["a"]) == nil
  end

  test "a hud is normalised to a column, its width and the rows under" do
    assert Hud.layout([["a"], {:t, ["b"]}]) == %{left: [], width: 0, bottom: [["a"], {:t, ["b"]}]}
    assert Hud.layout(%{left: [["x"]], width: 12}) == %{left: [["x"]], width: 12, bottom: []}

    assert Hud.layout(%{left: [["x"]], width: 12, bottom: [["y"]]}) == %{
             left: [["x"]],
             width: 12,
             bottom: [["y"]]
           }
  end

  test "every row of a hud in reading order, and the plain text of a row" do
    hud = %{left: [["l1"], ["l2"]], width: 5, bottom: [[{"b1", nil}, " more"]]}
    assert Hud.rows(hud) == [["l1"], ["l2"], [{"b1", nil}, " more"]]
    assert Hud.text([{"b1", nil}, " more"]) == "b1 more"
    assert Hud.text({:tag, ["a", {"b", %{}}]}) == "ab"
  end

  test "a run's colour for a wire that carries one colour a run" do
    assert Hud.colour({"x", %{fg: {1, 2, 3}}}) == {1, 2, 3}
    assert Hud.colour({"x", %{bold: true}}) == nil
    assert Hud.colour({"x", %{fg: :yellow}}) == {255, 255, 0}
  end
end
