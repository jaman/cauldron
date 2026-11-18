defmodule Cauldron.SFX.Editor.DrafterTest do
  use ExUnit.Case, async: true

  alias Cauldron.SFX
  alias Cauldron.SFX.Editor.Drafter
  alias Mix.Tasks.Cauldron.Sfx

  @moduletag :tmp_dir

  defp drafter(props \\ []) do
    Drafter.mount(Keyword.merge([bank: SFX.starter(), sink: TuningFork.Sink.Silent], props))
  end

  test "draws" do
    assert Drafter.render(drafter())
  end

  test "a key goes to the editor" do
    state = Drafter.update({:key, :down}, drafter())

    assert state.model.selected == 1
  end

  test "p starts a stage and plays through it" do
    state = Drafter.update({:key, :p}, drafter())

    assert is_pid(state.stage)
    assert Process.alive?(state.stage)
    assert state.model.said =~ "played"
  end

  test "q stops the stage and asks the editor to finish" do
    state = Drafter.update({:key, :p}, drafter())
    stage = state.stage

    assert {:stop, :normal} = Drafter.update({:key, :q}, state)
    refute Process.alive?(stage)
  end

  test "the task's props read a file, or start from the starter bank", %{tmp_dir: dir} do
    path = Path.join(dir, "sfx.json")
    :ok = SFX.write(SFX.starter(), path)

    assert %{bank: bank, out: ^path} = Sfx.props([path])
    assert length(SFX.events(bank)) == 6

    assert %{bank: starter, out: "sfx.json"} = Sfx.props([])
    assert length(SFX.events(starter)) == 6
  end

  test "n names a new event, a key at a time" do
    state = Drafter.update({:key, :n}, drafter())
    assert state.naming == ""

    state =
      Enum.reduce([:l, :a, :s, :e, :r], state, fn key, state ->
        Drafter.update({:key, key}, state)
      end)

    assert state.naming == "laser"

    state = Drafter.update({:key, :enter}, state)

    assert state.naming == nil
    assert "laser" in state.model.names
    assert state.model.said =~ "added laser"
  end

  test "escape leaves the name alone" do
    state = Drafter.update({:key, :n}, drafter())
    state = Drafter.update({:key, :escape}, state)

    assert state.naming == nil
    assert length(state.model.names) == 6
  end

  test "w writes the bank" do
    out = Path.join(System.tmp_dir!(), "drafter_sfx_#{System.unique_integer([:positive])}.json")
    on_exit(fn -> File.rm(out) end)

    state = Drafter.update({:key, :w}, drafter(out: out))

    assert state.model.said == "wrote #{out}"
    assert File.exists?(out)
  end
end
