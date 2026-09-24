defmodule Cauldron2D.Input.PadTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Input
  alias Cauldron2D.Input.Pad

  @padmap %{
    left: [:dpad_left, {:axis, :left_x, :neg}],
    right: [:dpad_right, {:axis, :left_x, :pos}],
    thrust: [:a, {:axis, :right_trigger, :pos}],
    fire: [:x]
  }

  defp held(pad), do: pad |> Pad.held() |> MapSet.to_list() |> Enum.sort()

  defp button(pad, button, pressed),
    do: Pad.handle(pad, %{type: :button, device: 0, button: button, pressed: pressed})

  defp axis(pad, axis, value),
    do: Pad.handle(pad, %{type: :axis, device: 0, axis: axis, value: value})

  test "a button holds its action from press to release" do
    pad = Pad.new(@padmap)

    pad = button(pad, :dpad_left, true)
    assert held(pad) == [:left]

    pad = button(pad, :x, true)
    assert held(pad) == [:fire, :left]

    pad = button(pad, :dpad_left, false)
    assert held(pad) == [:fire]
  end

  test "an axis past the dead zone holds the action of its direction, at its strength" do
    pad = Pad.new(@padmap, deadzone: 0.25)

    pad = axis(pad, :left_x, -0.1)
    assert held(pad) == []

    pad = axis(pad, :left_x, -0.8)
    assert held(pad) == [:left]
    assert Pad.strength(pad) == %{left: 0.8}

    pad = axis(pad, :left_x, 1.0)
    assert held(pad) == [:right]
    assert Pad.strength(pad) == %{right: 1.0}

    pad = axis(pad, :left_x, 0.0)
    assert held(pad) == []
    assert Pad.strength(pad) == %{}
  end

  test "a button held in full outweighs a partly pushed axis on the same action" do
    pad = Pad.new(@padmap)

    pad = pad |> axis(:right_trigger, 0.5) |> button(:a, true)
    assert Pad.strength(pad) == %{}

    pad = button(pad, :a, false)
    assert Pad.strength(pad) == %{thrust: 0.5}
  end

  test "a controller going away releases everything it held" do
    pad = Pad.new(@padmap)

    pad = pad |> button(:x, true) |> axis(:left_x, 1.0)
    assert held(pad) == [:fire, :right]

    pad = Pad.handle(pad, %{type: :disconnected, device: 0})
    assert held(pad) == []
  end

  test "two controllers hold actions independently" do
    pad = Pad.new(@padmap)

    pad =
      pad
      |> Pad.handle(%{type: :button, device: 0, button: :x, pressed: true})
      |> Pad.handle(%{type: :button, device: 1, button: :a, pressed: true})
      |> Pad.handle(%{type: :button, device: 0, button: :x, pressed: false})

    assert held(pad) == [:thrust]
  end

  test "buttons and axes the map does not name are ignored" do
    pad = Pad.new(@padmap)

    pad =
      pad
      |> button(:y, true)
      |> axis(:right_y, 1.0)
      |> Pad.handle(%{type: :connected, device: 0, name: "Pad"})

    assert held(pad) == []
  end

  test "the default map steers the four directions with the d-pad and the left stick" do
    map = Pad.default_map([:left, :right, :up, :down, :fire])

    assert map == %{
             left: [:dpad_left, {:axis, :left_x, :neg}],
             right: [:dpad_right, {:axis, :left_x, :pos}],
             up: [:dpad_up, {:axis, :left_y, :neg}],
             down: [:dpad_down, {:axis, :left_y, :pos}]
           }
  end

  test "what the pad holds merges into the input's state with its strengths" do
    pad = Pad.new(@padmap) |> axis(:left_x, -0.6) |> button(:x, true)
    input = Input.new(%{fire: [:" "]}) |> Input.merge(Pad.held(pad), Pad.strength(pad))

    assert Input.state(input) == %{
             held: MapSet.new([:left, :fire]),
             aim: nil,
             strength: %{left: 0.6}
           }
  end

  test "an input with nothing held from outside reports no strengths" do
    input = Input.new(%{fire: [:" "]})

    assert Input.state(input) == %{held: MapSet.new(), aim: nil}
  end
end

defmodule Cauldron2D.Input.PadAimTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Input.Pad

  defp axis(pad, device, axis, value),
    do: Pad.handle(pad, %{type: :axis, device: device, axis: axis, value: value})

  test "a stick bound to aim points the way it is pushed, as a unit direction, past a radial deadzone" do
    pad = Pad.new(%{aim: [{:stick, :left}], fire: [:a]})
    assert Pad.aim_stick(pad) == :left
    assert Pad.aim(pad) == nil

    pad = pad |> axis(0, :left_x, 0.6) |> axis(0, :left_y, -0.8)
    {dx, dy} = Pad.aim(pad)
    assert_in_delta dx, 0.6, 0.001
    assert_in_delta dy, -0.8, 0.001

    assert Pad.aim(axis(pad, 0, :left_x, 0.2) |> axis(0, :left_y, 0.2)) == nil
    assert Pad.aim(axis(pad, 0, :left_x, 0.25) |> axis(0, :left_y, -0.25)) != nil

    assert Pad.held(pad) == MapSet.new()
    assert Pad.aim(Pad.handle(pad, %{type: :disconnected, device: 0})) == nil
  end

  test "an aim stick with a push holds its action past the ring, harder the further it goes" do
    pad =
      Pad.new(%{
        aim: [{:stick, :left, push: [action: :thrust, beyond: 0.6, least: 0.3, gain: 1.4]}]
      })

    assert Pad.push(pad) == %{action: :thrust, beyond: 0.6, least: 0.3, gain: 1.4}

    half = axis(pad, 0, :left_y, -0.5)
    assert Pad.aim(half) != nil
    assert Pad.held(half) == MapSet.new()

    ring = axis(pad, 0, :left_y, -0.65)
    assert Pad.held(ring) == MapSet.new([:thrust])
    assert_in_delta Pad.strength(ring)[:thrust], 0.3, 0.001

    far = pad |> axis(0, :left_x, -0.6) |> axis(0, :left_y, -0.6)
    assert Pad.held(far) == MapSet.new([:thrust])
    assert_in_delta Pad.strength(far)[:thrust], min(1.0, (0.8485 - 0.6) / 0.4 * 1.4), 0.01

    assert Pad.held(axis(far, 0, :left_x, 0.0) |> axis(0, :left_y, -0.4)) == MapSet.new()
    assert Pad.push(Pad.new(%{aim: [{:stick, :left}]})) == nil
  end

  test "without an aim stick the pad aims nothing, and the sticks still hold what the map gives them" do
    pad = Pad.new(Pad.default_map([:left, :right]))
    assert Pad.aim_stick(pad) == nil
    assert Pad.aim(axis(pad, 0, :left_x, 0.9)) == nil
    assert Pad.held(axis(pad, 0, :left_x, 0.9)) == MapSet.new([:right])
  end
end
