defmodule Cauldron.SFX.Kino.EditorTest do
  use ExUnit.Case, async: true

  alias Cauldron.SFX
  alias Cauldron.SFX.Kino.Editor

  @moduletag :tmp_dir

  test "new/1 opens the starter bank" do
    assert %Kino.JS.Live{} = Editor.new()
  end

  test "new/1 opens a bank file", %{tmp_dir: dir} do
    path = Path.join(dir, "sfx.json")
    :ok = SFX.write(SFX.starter(), path)

    assert %Kino.JS.Live{} = Editor.new(path)
  end

  test "the payload says what the cell draws" do
    ctx = %{assigns: %{editor: Cauldron.SFX.Editor.mount(%{bank: SFX.starter()})}}
    payload = Editor.payload(ctx)

    assert payload.title == "SFX"
    assert payload.summary =~ "6 events"
    assert length(payload.rows) == 6
    assert Enum.any?(payload.rows, & &1.selected)
    assert Enum.any?(payload.buttons, &(&1.label == "play" and &1.key == "p"))
  end

  test "the payload is JSON, as Kino sends it" do
    ctx = %{assigns: %{editor: Cauldron.SFX.Editor.mount(%{bank: SFX.starter()})}}

    json = JSON.encode!(Editor.payload(ctx))
    assert json =~ ~s("buttons")
  end
end
