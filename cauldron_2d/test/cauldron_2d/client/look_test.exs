defmodule Cauldron2D.Client.LookTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Client.Look
  alias Cauldron2D.Draw

  test "it answers for every projection a game can put the client in" do
    for projection <- Draw.projections() do
      look = %{projection: projection, facing: 0, facings: 4, heading: 0.0}

      steered = Look.steered(read([:up]), look)

      assert MapSet.member?(steered.held, :up) or Map.has_key?(steered, :heading),
             "#{projection} steered an :up into nothing the world can walk"
    end
  end

  test "isometric at finer facings sends the directions as held, with the view's heading" do
    look = %{projection: :iso, facing: 5, facings: 16, heading: 0.0}
    steered = Look.steered(read([:left]), look)
    assert MapSet.to_list(steered.held) == [:left]
    assert_in_delta steered.heading, :math.pi() / 8, 1.0e-9
  end

  test "the oblique view steers as held at its default facing and turns at four" do
    fixed = %{projection: :oblique, facing: 1, facings: 4, heading: 0.0}

    assert MapSet.to_list(Look.steered(read([:up]), fixed).held) == [:up]

    asked = %{projection: :oblique, facing: 1, facings: %{oblique: 4}, heading: 0.0}
    turned = Look.steered(read([:up]), asked)

    assert MapSet.size(turned.held) == 1
    refute MapSet.member?(turned.held, :up)
  end

  test "of the directions a stick holds, the isometric view keeps the one pushed hardest" do
    look = %{projection: :iso, facing: 0, facings: 4, heading: 0.0}
    read = read([:left, :up], %{left: 0.9, up: 0.3})
    assert MapSet.to_list(Look.steered(read, look).held) == [:left]
  end

  test "a facings map picks the count for the projection in view" do
    assert Look.turns_with_pointer?(%{projection: :iso, facings: %{iso: 16}})
    refute Look.turns_with_pointer?(%{projection: :iso, facings: %{iso: 4}})
    refute Look.turns_with_pointer?(%{projection: :oblique, facings: %{oblique: 4}})
    refute Look.turns_with_pointer?(%{projection: :oblique, facings: 16})
  end

  test "a drag turns first person, mode 7 and a free isometric view, but not four facings" do
    assert Look.turns_with_pointer?(%{projection: :first_person})
    assert Look.turns_with_pointer?(%{projection: :mode7})
    assert Look.turns_with_pointer?(%{projection: :iso, facings: 16})
    refute Look.turns_with_pointer?(%{projection: :iso, facings: 4})
    refute Look.turns_with_pointer?(%{projection: :oblique})
    refute Look.turns_with_pointer?(%{projection: :top})
  end

  defp read(held, strength \\ %{}),
    do: %{
      held: MapSet.new(held),
      strength: strength,
      pressed: MapSet.new(),
      released: MapSet.new()
    }
end
