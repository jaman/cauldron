defmodule Town.RulesTest do
  use ExUnit.Case, async: true

  alias Town.Rules

  test "the three rules measure a knight's move differently" do
    assert_in_delta Rules.distance(:euclid, {0, 0}, {2, 1}), 2.236, 0.001
    assert Rules.distance(:dnd, {0, 0}, {2, 1}) == 2
    assert Rules.distance(:pathfinder, {0, 0}, {3, 3}) == 4
  end

  test "next cycles and labels round" do
    assert Rules.next(:euclid) == :dnd
    assert Rules.next(:pathfinder) == :euclid
    assert Rules.label(:euclid, 2.236) == "2.2"
    assert Rules.label(:dnd, 3) == "3"
  end
end
