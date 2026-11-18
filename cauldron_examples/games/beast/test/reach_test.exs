defmodule Beast.ReachTest do
  use ExUnit.Case, async: true

  alias Beast.{Reach, Region, Tuning}

  for number <- 1..Region.count() do
    @number number
    test "the beast can reach everything region #{number} asks of it" do
      assert Reach.problems(Region.load(@number), Tuning.new()) == []
    end
  end
end
