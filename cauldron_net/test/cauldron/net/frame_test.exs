defmodule Cauldron.Net.FrameTest do
  use ExUnit.Case, async: true

  alias Cauldron.Net.Frame

  defp status(scene, hud, outcome), do: Frame.status(scene, hud, outcome, fn _name -> nil end)

  test "a status carries the hud, the outcome, the focus and a subject only when the scene names one" do
    status =
      status(
        %{focus: {10.5, 4.25}},
        [[{"fuel ", {255, 255, 0}}, {"████", {0, 200, 0}}], [{"score 3", nil}]],
        nil
      )

    assert status.focus == [10.5, 4.25]
    assert status.hud == [[["fuel ", "#ffff00"], ["████", "#00c800"]], [["score 3", nil]]]
    assert status.over == nil
    refute Map.has_key?(status, :subject)

    over =
      status(%{focus: {0, 0}, subject: "bob"}, [], %{
        title: "Victory",
        lines: ["a 3"],
        score: 9
      })

    assert over.over == %{title: "Victory", lines: ["a 3"]}
    assert over.subject == "bob"

    refute Map.has_key?(status(nil, [], nil), :focus)
  end

  test "hud rows may carry a tag, sent beside the rows only when any row has one" do
    refute Map.has_key?(status(nil, [[{"a", nil}]], nil), :tags)

    tagged =
      status(
        nil,
        [{:fuel, [{"fuel ██", {255, 255, 0}}]}, [{"plain", nil}], {:score, [{"3", nil}]}],
        nil
      )

    assert tagged.hud == [[["fuel ██", "#ffff00"]], [["plain", nil]], [["3", nil]]]
    assert tagged.tags == ["fuel", nil, "score"]
  end
end
