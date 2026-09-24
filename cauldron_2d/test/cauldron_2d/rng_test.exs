defmodule Cauldron2D.RngTest do
  @moduledoc """
  The generator, checked for the two things a game needs from it: the same seed replays the
  same run, and the distributions are the ones the docs claim.

  Distribution tests use fixed seeds and wide bounds, so they assert a real property without
  failing on an unlucky day.
  """

  use ExUnit.Case, async: true

  alias Cauldron2D.Rng

  defp take(rng, count, fun) do
    Enum.map_reduce(1..count, rng, fn _step, rng -> fun.(rng) end)
  end

  describe "replaying a run" do
    test "the same seed and the same calls give the same values" do
      {first, _rng} = take(Rng.new(99), 50, &Rng.roll(&1, 1_000))
      {again, _rng} = take(Rng.new(99), 50, &Rng.roll(&1, 1_000))

      assert first == again
    end

    test "random/0 hands back the seed it used, so a run can be replayed" do
      {rng, seed} = Rng.random()
      {values, _rng} = take(rng, 20, &Rng.roll(&1, 100))
      {replayed, _rng} = take(Rng.new(seed), 20, &Rng.roll(&1, 100))

      assert values == replayed
    end
  end

  describe "rolling" do
    test "between is inclusive at both ends and never outside them" do
      {values, _rng} = take(Rng.new(5), 500, &Rng.between(&1, -3, 3))

      assert Enum.all?(values, &(&1 in -3..3))
      assert Enum.min(values) == -3
      assert Enum.max(values) == 3
    end

    test "dice sums as many rolls as it was asked for" do
      {values, _rng} = take(Rng.new(8), 200, &Rng.dice(&1, 3, 6))

      assert Enum.all?(values, &(&1 in 3..18))
      assert Enum.min(values) < 8, "three dice should sometimes roll low"
      assert Enum.max(values) > 13, "three dice should sometimes roll high"
    end

    test "chance at one in one is always true, and at one in a thousand is mostly false" do
      {always, _rng} = take(Rng.new(9), 20, &Rng.chance(&1, 1, 1))
      assert Enum.uniq(always) == [true]

      {rarely, _rng} = take(Rng.new(10), 500, &Rng.chance(&1, 1, 1_000))
      assert Enum.count(rarely, & &1) <= 5
    end
  end

  describe "picking from a list" do
    test "an empty list gives nil and the generator back unchanged" do
      rng = Rng.new(12)

      assert {nil, ^rng} = Rng.pick(rng, [])
    end

    test "every element comes up, and nothing else does" do
      {values, _rng} = take(Rng.new(13), 400, &Rng.pick(&1, [:a, :b, :c, :d]))

      assert Enum.sort(Enum.uniq(values)) == [:a, :b, :c, :d]
    end
  end

  describe "picking by weight" do
    test "an empty list gives nil" do
      rng = Rng.new(15)

      assert {nil, ^rng} = Rng.weighted(rng, [])
    end

    test "a heavier value comes up more often, in roughly its proportion" do
      pairs = [{1, :rare}, {9, :common}]
      {values, _rng} = take(Rng.new(16), 2_000, &Rng.weighted(&1, pairs))

      assert_in_delta Enum.count(values, &(&1 == :common)) / 2_000, 0.9, 0.04
    end

    test "a weight of zero is never chosen rather than crashing" do
      pairs = [{0, :never}, {1, :always}]
      {values, _rng} = take(Rng.new(17), 300, &Rng.weighted(&1, pairs))

      assert Enum.uniq(values) == [:always]
    end

    test "a zero weight at the end of the list is not chosen either" do
      pairs = [{1, :always}, {0, :never}]
      {values, _rng} = take(Rng.new(18), 300, &Rng.weighted(&1, pairs))

      assert Enum.uniq(values) == [:always]
    end

    test "weights that are all zero are refused by name, not by function clause" do
      assert_raise ArgumentError, ~r/at least one positive weight/, fn ->
        Rng.weighted(Rng.new(19), [{0, :a}, {0, :b}])
      end
    end

    test "a negative weight is refused by name" do
      assert_raise ArgumentError, ~r/non-negative integer weights/, fn ->
        Rng.weighted(Rng.new(20), [{-1, :a}, {2, :b}])
      end
    end

    test "something that is not a weight and a value is refused by name" do
      assert_raise ArgumentError, ~r/\{weight, value\} pairs/, fn ->
        Rng.weighted(Rng.new(21), [:not_a_pair])
      end
    end
  end

  describe "shuffling" do
    test "everything that went in comes out, once each" do
      list = Enum.to_list(1..200)
      {shuffled, _rng} = Rng.shuffle(Rng.new(22), list)

      assert Enum.sort(shuffled) == list
    end

    test "an empty list and a single element are left alone" do
      rng = Rng.new(23)

      assert {[], ^rng} = Rng.shuffle(rng, [])
      assert {[:one], ^rng} = Rng.shuffle(rng, [:one])
    end

    test "a long list is genuinely moved rather than nudged" do
      list = Enum.to_list(1..2_000)
      {shuffled, _rng} = Rng.shuffle(Rng.new(25), list)

      ascending =
        shuffled |> Enum.chunk_every(2, 1, :discard) |> Enum.count(fn [a, b] -> a < b end)

      assert_in_delta ascending / 1_999, 0.5, 0.05
      assert Enum.count(Enum.zip(list, shuffled), fn {was, now} -> was == now end) < 20
    end

    test "every ordering of three turns up, and no one of them dominates" do
      counts =
        Enum.reduce(1..1_200, %{}, fn seed, acc ->
          {order, _rng} = Rng.shuffle(Rng.new(seed), [:a, :b, :c])
          Map.update(acc, order, 1, &(&1 + 1))
        end)

      assert map_size(counts) == 6

      for {_order, count} <- counts do
        assert_in_delta count / 1_200, 1 / 6, 0.04
      end
    end
  end
end
