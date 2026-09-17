defmodule Cauldron2D.SaveTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Save

  setup do
    dir = Path.join(System.tmp_dir!(), "cauldron_save_#{System.unique_integer([:positive])}")
    previous = System.get_env("XDG_DATA_HOME")
    System.put_env("XDG_DATA_HOME", dir)

    on_exit(fn ->
      if previous,
        do: System.put_env("XDG_DATA_HOME", previous),
        else: System.delete_env("XDG_DATA_HOME")

      File.rm_rf!(dir)
    end)

    :ok
  end

  test "a game state written to a slot reads back, is listed, and can be deleted" do
    assert Save.list(:my_game) == []
    assert :ok = Save.write(:my_game, "quick", %{level: 3, rng: {1, 2}})
    assert :ok = Save.write(:my_game, "camp", %{level: 1})
    assert {:ok, %{level: 3, rng: {1, 2}}} = Save.read(:my_game, "quick")
    assert [%{slot: "quick", at: %DateTime{}}, %{slot: "camp"}] = Save.list(:my_game)
    assert :ok = Save.delete(:my_game, "quick")
    assert {:error, :enoent} = Save.read(:my_game, "quick")
    assert [%{slot: "camp"}] = Save.list(:my_game)
  end

  test "a slot name that would leave the saves directory is refused" do
    assert {:error, :bad_slot} = Save.write(:my_game, "../etc", %{})
    assert {:error, :bad_slot} = Save.read(:my_game, "a/b")
  end

  test "a file that is not a saved term is an error, not a crash" do
    File.mkdir_p!(Path.dirname(Save.path(:my_game, "bad")))
    File.write!(Save.path(:my_game, "bad"), "garbage")
    assert {:error, :corrupt} = Save.read(:my_game, "bad")
  end
end
