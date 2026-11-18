defmodule Cauldron.Net.RoundTripTest do
  use ExUnit.Case, async: true

  alias Cauldron.Net.{Frame, Wire}

  test "a status Frame writes is the status Wire reads" do
    read =
      %{focus: {10.5, 4.25}, subject: "me"}
      |> Frame.status(
        [[{"fuel", {255, 255, 0}}, {"3", nil}]],
        %{title: "Over", lines: ["a"]},
        fn _name -> nil end
      )
      |> Jason.encode!()
      |> Jason.decode!()
      |> Wire.status()

    assert read.focus == {10.5, 4.25}
    assert read.subject == "me"
    assert read.hud == [[{"fuel", "#ffff00"}, {"3", nil}]]
    assert read.over == %{"title" => "Over", "lines" => ["a"]}
  end
end
