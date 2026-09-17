defmodule Cauldron2D.InputTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Input

  @keymap %{
    turn_left: [:left, :a],
    turn_right: [:right, :d],
    thrust: [:up, :w, :left_shift],
    fire: [:" ", {:f, [:ctrl]}],
    shield: [:s]
  }

  defp held(input),
    do: input |> Input.state() |> Map.fetch!(:held) |> MapSet.to_list() |> Enum.sort()

  describe "with key releases" do
    setup do
      {:ok, input: Input.new(@keymap, releases?: true, toggles: [:thrust])}
    end

    test "a key is held from its press to its release", %{input: input} do
      input = Input.handle(input, {:key_down, :left, []}, 0)
      assert held(input) == [:turn_left]

      input = Input.handle(input, {:key_down, :w, []}, 10)
      assert held(input) == [:thrust, :turn_left]

      input = Input.handle(input, {:key_up, :left, []}, 20)
      assert held(input) == [:thrust]
    end

    test "toggles are plain held keys when releases arrive", %{input: input} do
      input = input |> Input.handle({:key_down, :w, []}, 0) |> Input.handle({:key_up, :w, []}, 5)
      assert held(input) == []
    end

    test "modifier keys and chords match", %{input: input} do
      input = Input.handle(input, {:key_down, :left_shift, []}, 0)
      assert held(input) == [:thrust]

      input = Input.handle(input, {:key_down, :f, [:ctrl]}, 0)
      assert held(input) == [:fire, :thrust]

      input = Input.handle(input, {:key_down, :f, []}, 0)
      assert held(input) == [:fire, :thrust]
    end

    test "shifted letters release the same action their base key pressed", %{input: input} do
      input =
        input |> Input.handle({:key_down, :a, [:shift]}, 0) |> Input.handle({:key_up, :a, []}, 5)

      assert held(input) == []
    end

    test "legacy key events are ignored, so repeats change nothing", %{input: input} do
      input = input |> Input.handle({:key_down, :left, []}, 0) |> Input.handle({:key, :left}, 30)
      assert held(input) == [:turn_left]
      input = Input.handle(input, {:key, :right}, 40)
      assert held(input) == [:turn_left]
    end

    test "nothing expires", %{input: input} do
      input = input |> Input.handle({:key_down, :left, []}, 0) |> Input.expire(10_000)
      assert held(input) == [:turn_left]
    end
  end

  describe "without key releases" do
    setup do
      {:ok, input: Input.new(@keymap, releases?: false, toggles: [:thrust, :shield], tap_ms: 100)}
    end

    test "a press holds the action for the tap window", %{input: input} do
      input = Input.handle(input, {:key, :left}, 0)
      assert held(input) == [:turn_left]
      assert held(Input.expire(input, 90)) == [:turn_left]
      assert held(Input.expire(input, 101)) == []
    end

    test "repeats keep it held", %{input: input} do
      input =
        input
        |> Input.handle({:key, :left}, 0)
        |> Input.expire(80)
        |> Input.handle({:key, :left}, 80)
        |> Input.expire(160)

      assert held(input) == [:turn_left]
    end

    test "a toggle flips on each press and never expires", %{input: input} do
      input = Input.handle(input, {:key, :w}, 0)
      assert held(Input.expire(input, 10_000)) == [:thrust]
      input = Input.handle(input, {:key, :w}, 20_000)
      assert held(input) == []
    end

    test "an action in :holds stays held across the key-repeat delay, follows the repeats, and stops soon after they stop" do
      input =
        Input.new(@keymap, releases?: false, tap_ms: 100, holds: [thrust: 450], repeat_ms: 150)

      tapped = Input.handle(input, {:key, :w}, 0)
      assert held(Input.expire(tapped, 400)) == [:thrust]
      assert held(Input.expire(tapped, 451)) == []

      held_down =
        tapped
        |> Input.expire(300)
        |> Input.handle({:key, :w}, 300)
        |> Input.expire(400)
        |> Input.handle({:key, :w}, 400)
        |> Input.expire(500)

      assert held(held_down) == [:thrust]
      assert held(Input.expire(held_down, 549)) == [:thrust]
      assert held(Input.expire(held_down, 551)) == []
    end

    test "an uppercase letter presses its base key's action", %{input: input} do
      input = Input.handle(input, {:key, :A}, 0)
      assert held(input) == [:turn_left]
    end

    test "the terminal confirming releases switches modes", %{input: input} do
      input =
        input
        |> Input.handle({:key, :w}, 0)
        |> Input.handle({:key_release_support, true}, 1)

      assert Input.releases?(input)
      assert held(input) == []
      input = input |> Input.handle({:key_down, :w, []}, 2) |> Input.handle({:key_up, :w, []}, 3)
      assert held(input) == []
    end
  end

  describe "pointer and merging" do
    test "the last pointer position is kept as the aim" do
      input =
        Input.new(@keymap)
        |> Input.handle({:mouse, %{type: :move, x: 12, y: 3, modifiers: []}}, 0)

      assert Input.state(input).aim == {12, 3}
    end

    test "an outside source's held actions are merged in" do
      input = Input.new(@keymap, releases?: true) |> Input.handle({:key_down, :left, []}, 0)
      merged = Input.merge(input, MapSet.new([:fire]))
      assert held(merged) == [:fire, :turn_left]
      assert held(Input.merge(merged, MapSet.new())) == [:turn_left]
    end

    test "unknown keys are ignored" do
      input = Input.new(@keymap, releases?: true) |> Input.handle({:key_down, :z, []}, 0)
      assert held(input) == []
    end
  end

  describe "mouse buttons" do
    @mouse_keymap %{thrust: [:up, {:mouse, :right}], fire: [{:mouse, :left}]}

    test "a button is held from mouse down to mouse up, whether or not keys report releases" do
      for releases? <- [true, false] do
        input = Input.new(@mouse_keymap, releases?: releases?)

        down =
          Input.handle(
            input,
            {:mouse, %{type: :mouse_down, button: :left, x: 1, y: 1, modifiers: []}},
            0
          )

        assert held(down) == [:fire]
        assert held(Input.expire(down, 10_000)) == [:fire]

        up =
          Input.handle(
            down,
            {:mouse, %{type: :mouse_up, button: :left, x: 1, y: 1, modifiers: []}},
            5
          )

        assert held(up) == []
      end
    end

    test "a drag keeps the button held" do
      input =
        Input.new(@mouse_keymap)
        |> Input.handle(
          {:mouse, %{type: :mouse_down, button: :right, x: 1, y: 1, modifiers: []}},
          0
        )
        |> Input.handle({:mouse, %{type: :drag, button: :right, x: 2, y: 1, modifiers: []}}, 1)

      assert held(input) == [:thrust]
      assert Input.state(input).aim == {2, 1}
    end
  end

  describe "keys against the pointer" do
    @steer_keymap %{turn_left: [:left], turn_right: [:right], fire: [:" "]}

    test "pressing a steering key drops the aim until the pointer moves again" do
      input =
        Input.new(@steer_keymap, releases?: true, steering: [:turn_left, :turn_right])
        |> Input.handle({:mouse, %{type: :move, x: 12, y: 3, modifiers: []}}, 0)

      assert Input.state(input).aim == {12, 3}

      keyed = Input.handle(input, {:key_down, :left, []}, 1)
      assert Input.state(keyed).aim == nil
      assert held(keyed) == [:turn_left]

      moved = Input.handle(keyed, {:mouse, %{type: :move, x: 13, y: 3, modifiers: []}}, 2)
      assert Input.state(moved).aim == {13, 3}
    end

    test "a key that does not steer leaves the aim alone" do
      input =
        Input.new(@steer_keymap, releases?: true, steering: [:turn_left, :turn_right])
        |> Input.handle({:mouse, %{type: :move, x: 12, y: 3, modifiers: []}}, 0)
        |> Input.handle({:key_down, :" ", []}, 1)

      assert Input.state(input).aim == {12, 3}
    end

    test "taps drop the aim too" do
      input =
        Input.new(@steer_keymap, steering: [:turn_left])
        |> Input.handle({:mouse, %{type: :move, x: 12, y: 3, modifiers: []}}, 0)
        |> Input.handle({:key, :left}, 1)

      assert Input.state(input).aim == nil
    end
  end
end
