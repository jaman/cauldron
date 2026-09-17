defmodule Cauldron2D.PathsTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Paths

  setup do
    saved =
      for var <- ["XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME"],
          do: {var, System.get_env(var)}

    on_exit(fn ->
      for {var, value} <- saved,
          do: if(value, do: System.put_env(var, value), else: System.delete_env(var))
    end)

    :ok
  end

  test "each kind of directory follows its XDG variable, then the conventional default" do
    System.put_env("XDG_CONFIG_HOME", "/tmp/cfg")
    System.put_env("XDG_DATA_HOME", "/tmp/dat")
    System.put_env("XDG_CACHE_HOME", "/tmp/cch")
    assert Paths.config(:my_game, "alice.settings") == "/tmp/cfg/my_game/alice.settings"
    assert Paths.data("my_game", ["saves", "one.save"]) == "/tmp/dat/my_game/saves/one.save"
    assert Paths.cache(:my_game) == "/tmp/cch/my_game"

    System.delete_env("XDG_CONFIG_HOME")
    System.delete_env("XDG_DATA_HOME")
    System.delete_env("XDG_CACHE_HOME")
    home = System.user_home!()
    assert Paths.config(:my_game) == Path.join(home, ".config/my_game")
    assert Paths.data(:my_game) == Path.join(home, ".local/share/my_game")
    assert Paths.cache(:my_game) == Path.join(home, ".cache/my_game")
  end
end
