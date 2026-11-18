defmodule Cauldron.SFX.EditorTest do
  use ExUnit.Case, async: true

  alias Cauldron.SFX
  alias Cauldron.SFX.Editor

  @moduletag :tmp_dir

  defp editor(props \\ []), do: Editor.mount(Keyword.merge([bank: SFX.starter()], props))

  defp press(state, key) do
    {state, effects} = Editor.key(state, key)
    {state, effects}
  end

  defp select(state, name) do
    index = Enum.find_index(state.names, &(&1 == name))
    %{state | selected: index, variant: 0}
  end

  test "mount lists the bank's events" do
    state = editor()

    assert state.names == ["boom", "click", "fire", "hurt", "jump", "pickup"]
    assert state.selected == 0
    assert state.variant == 0
  end

  test "down and up move the event, and a move resets the variant" do
    {state, []} = press(editor(), :down)
    {state, []} = press(state, :down)
    {state, []} = press(state, :up)

    assert state.selected == 1
    assert state.variant == 0
  end

  test "right and left move the variant, and it stops at the ends" do
    {state, []} = press(select(editor(), "fire"), :right)
    {state, []} = press(state, :right)
    {state, []} = press(state, :left)

    assert state.variant == 1

    {state, []} = press(select(editor(), "fire"), :right)
    {state, []} = press(state, :right)
    {state, []} = press(state, :right)
    {state, []} = press(state, :right)

    assert state.variant == 2
  end

  test "s cycles the shape of a tone" do
    {state, []} = press(select(editor(), "fire"), :s)

    assert SFX.variant(state.bank, "fire", 0)["shape"] == "saw"
  end

  test "s leaves a layered sound alone" do
    {state, []} = press(select(editor(), "boom"), :s)

    assert state.said =~ "layered"
    assert state.bank == editor().bank
  end

  test "+ and - change the event's gain" do
    {state, []} = press(select(editor(), "fire"), :+)
    {state, []} = press(state, :+)

    assert_in_delta SFX.event(state.bank, "fire").gain, 1.1, 0.001

    {state, []} = press(state, :-)

    assert_in_delta SFX.event(state.bank, "fire").gain, 1.05, 0.001
  end

  test "> and < change the event's pan" do
    {state, []} = press(select(editor(), "fire"), :>)
    {state, []} = press(state, :>)

    assert_in_delta SFX.event(state.bank, "fire").pan, 0.2, 0.001
  end

  test "] and [ move the variant's pitch a semitone" do
    {state, []} = press(select(editor(), "fire"), :"]")

    assert_in_delta SFX.variant(state.bank, "fire", 0)["freq"],
                    1320.0 * :math.pow(2, 1 / 12),
                    0.01
  end

  test "a adds a variant and d removes it" do
    {state, []} = press(select(editor(), "fire"), :a)

    assert length(SFX.event(state.bank, "fire").variants) == 4
    assert state.variant == 3

    {state, []} = press(state, :d)

    assert length(SFX.event(state.bank, "fire").variants) == 3
    assert state.variant == 2
  end

  test "an event keeps at least one variant" do
    {state, []} = press(select(editor(), "click"), :d)

    assert length(SFX.event(state.bank, "click").variants) == 1
    assert state.said =~ "at least one"
  end

  test "p asks the front end to play the event" do
    {state, [{:play, voice}]} = press(select(editor(), "fire"), :p)

    assert %{freq: 1320.0} = voice
    assert state.said =~ "played fire"
  end

  test "p on an event with nothing in it asks for nothing" do
    empty = Editor.mount(bank: SFX.new())
    {state, []} = press(empty, :p)

    assert state.said =~ "not an event"
  end

  test "q asks the front end to close" do
    assert {_state, [:quit]} = press(editor(), :q)
  end

  test "w writes the bank where it is told", %{tmp_dir: dir} do
    out = Path.join(dir, "sfx.json")
    {state, []} = press(select(editor(out: out), "fire"), :+)
    {state, []} = press(state, :w)

    assert state.said == "wrote #{out}"
    assert %{gain: gain} = SFX.read!(out) |> SFX.event("fire")
    assert_in_delta gain, 1.05, 0.001
  end

  test "2 and 1 change the decay" do
    {state, []} = press(select(editor(), "fire"), :"2")

    assert_in_delta SFX.variant(state.bank, "fire", 0)["decay"], 0.06, 0.001

    {state, []} = press(state, :"1")

    assert_in_delta SFX.variant(state.bank, "fire", 0)["decay"], 0.05, 0.001
  end

  test "4 and 3 change the sweep, and a noise does not sweep" do
    {state, []} = press(select(editor(), "fire"), :"4")

    assert_in_delta SFX.variant(state.bank, "fire", 0)["sweep"], 0.7, 0.001

    hiss = Editor.mount(bank: SFX.new(events: %{"hiss" => %{variants: [%{kind: "noise"}]}}))
    {state, []} = press(hiss, :"4")

    assert state.said =~ "only a tone sweeps"
  end

  test "6 and 5 change the cutoff" do
    {state, []} = press(select(editor(), "fire"), :"5")

    assert_in_delta SFX.variant(state.bank, "fire", 0)["cutoff"], 0.75, 0.001
  end

  test "a new event is added, selected, and starts as a tone" do
    {state, []} = Editor.command(editor(), {:new_event, "laser"})

    assert "laser" in state.names
    assert Editor.current(state) == "laser"
    assert [%{"kind" => "tone"}] = SFX.event(state.bank, "laser").variants
    assert state.said =~ "added laser"
  end

  test "a name already taken, or no name at all, adds nothing" do
    {state, []} = Editor.command(editor(), {:new_event, "fire"})
    assert state.said =~ "already an event"

    {state, []} = Editor.command(state, {:new_event, "  "})
    assert state.said =~ "needs a name"
    assert length(state.names) == 6
  end

  test "x removes the event and keeps the cursor in range" do
    {state, []} = press(select(editor(), "pickup"), :x)

    assert length(state.names) == 5
    refute "pickup" in state.names
    assert state.selected == 4
    assert state.said =~ "removed pickup"
  end

  test "a new event starts from the preset" do
    {state, []} = Editor.command(editor(), {:new_event, "beam"})

    assert [%{"shape" => "saw", "freq" => 1400.0}] = SFX.event(state.bank, "beam").variants
  end

  test "t cycles the preset, and says which" do
    {state, []} = press(editor(), :t)

    assert state.preset == 1
    assert state.said =~ "zap"
  end

  test "k and l change the event's space" do
    {state, []} = press(select(editor(), "fire"), :l)

    assert_in_delta SFX.event(state.bank, "fire").space, 0.1, 0.001
  end

  test "7 and 8 change the attack" do
    {state, []} = press(select(editor(), "fire"), :"8")

    assert_in_delta SFX.variant(state.bank, "fire", 0)["attack"], 0.007, 0.001
  end

  test "the view says what a front end draws" do
    view = editor() |> select("boom") |> Editor.view()

    assert view.title == "SFX"
    assert view.summary =~ "6 events"
    assert length(view.rows) == 6
    assert Enum.any?(view.rows, & &1.selected)
    assert view.detail =~ "layers"
    assert {"p", "play"} in view.keys
  end
end
