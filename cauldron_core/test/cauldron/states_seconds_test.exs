defmodule Cauldron.StatesSecondsTest do
  use ExUnit.Case, async: true

  alias Cauldron.States

  @table %{
    windup: %{picture: :raise, seconds: 0.2, action: nil, next: :swing},
    swing: %{picture: :swing, seconds: 0.1, action: :hit, next: :rest},
    rest: %{picture: :stand, seconds: -1, action: nil, next: nil}
  }

  defp act(actor, :hit), do: Map.update(actor, :hits, 1, &(&1 + 1))

  test "a state lasts its seconds, its action runs on entry, and the time in it is kept" do
    actor = States.enter(%{}, @table, :windup, &act/2)
    actor = States.step(actor, @table, 0.15, &act/2)
    assert {actor.state, actor.since} == {:windup, 0.15}

    actor = States.step(actor, @table, 0.1, &act/2)
    assert {actor.state, actor.since, actor.hits} == {:swing, 0.0, 1}

    actor = Enum.reduce(1..10, actor, fn _, a -> States.step(a, @table, 0.1, &act/2) end)
    assert {actor.state, actor.hits} == {:rest, 1}
    assert_in_delta actor.since, 0.9, 1.0e-9
  end
end
