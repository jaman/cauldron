defmodule Cauldron.Net.Link.WorldTest do
  use ExUnit.Case, async: true

  alias Cauldron.Net.Link.World

  @status %{
    focus: {1.5, 1.0},
    subject: "bob",
    hud: [[{"fuel", "#ff0000"}, {"3", nil}]],
    over: nil
  }

  test "the hud and the outcome read from the remote view, and a closed connection says so" do
    view = %{remote: %{status: @status}, world: "pit"}
    assert World.hud(view) == [[{"fuel", {255, 0, 0}}, {"3", nil}]]
    assert World.outcome(view) == nil

    assert World.outcome(%{
             remote: %{status: @status, ended: %{outcome: %{title: "Over", score: 3}}}
           }) == %{title: "Over", score: 3}

    assert [[{"connection closed: :normal", _}]] =
             World.hud(%{view | remote: %{}} |> Map.put(:closed, :normal))
  end
end
