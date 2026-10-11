defmodule Cauldron2D.Drafter.Client.ControllersTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Drafter.Client.Controllers

  test "unassigned controllers take the free players in the order they connected" do
    controllers =
      Controllers.new() |> Controllers.connect(4, "Pad") |> Controllers.connect(2, "Pad")

    assert Controllers.slots(controllers, %{}, 2) == %{4 => 0, 2 => 1}
    assert Controllers.slots(controllers, %{}, 1) == %{4 => 0, 2 => nil}
  end

  test "an assigned controller plays its player, and the others fill around it" do
    controllers =
      Controllers.new() |> Controllers.connect(0, "Pad") |> Controllers.connect(1, "Stick")

    assert Controllers.slots(controllers, %{"Stick" => 1}, 2) == %{1 => 0, 0 => 1}
    assert Controllers.slots(controllers, %{"Pad" => :none}, 2) == %{0 => nil, 1 => 0}
    assert Controllers.slots(controllers, %{"Pad" => 3}, 2) == %{0 => 0, 1 => 1}
  end

  test "controllers sharing a name are numbered, and one heard before connecting gets a name" do
    controllers =
      Controllers.new()
      |> Controllers.connect(0, "Pad")
      |> Controllers.connect(1, "Pad")
      |> Controllers.seen(7)

    assert [%{name: "Pad"}, %{name: "Pad #2"}, %{name: "controller 7"}] =
             Controllers.listed(controllers, Controllers.slots(controllers, %{}, 2))
  end
end
