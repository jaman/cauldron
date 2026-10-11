defmodule Cauldron2D.StatesTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.States

  @table %{
    stand: %{picture: :a, tics: 0, action: :note, next: :aim},
    aim: %{picture: :b, tics: 0, action: :note, next: :fire},
    fire: %{picture: :c, tics: 3, action: :note, next: :gone},
    gone: %{picture: :d, tics: 2, action: :note, next: nil},
    flinch: %{picture: :e, tics: 4, action: nil, next: :stand},
    hit: %{picture: :f, tics: 0, action: :flinch, next: :stand}
  }

  defp act(actor, :note), do: Map.update(actor, :log, [actor.state], &(&1 ++ [actor.state]))
  defp act(actor, :flinch), do: States.enter(actor, @table, :flinch, &act/2)

  test "zero-tick states pass straight through, each running its action" do
    actor = States.enter(%{}, @table, :stand, &act/2)

    assert actor.state == :fire
    assert actor.tics == 3
    assert actor.log == [:stand, :aim, :fire]
  end

  test "an action that enters another state wins over the state's own next" do
    actor = States.enter(%{}, @table, :hit, &act/2)

    assert actor.state == :flinch
    assert actor.tics == 4
  end

  test "running out of a state with no next finishes the actor" do
    actor = States.enter(%{}, @table, :gone, &act/2)
    actor = actor |> States.tick(@table, &act/2) |> States.tick(@table, &act/2)

    assert actor.state == nil
  end
end
