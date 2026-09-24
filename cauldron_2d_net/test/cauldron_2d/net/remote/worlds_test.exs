defmodule Cauldron2D.Net.Remote.WorldsTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Net.ApiTest.Race
  alias Cauldron2D.Net.Remote
  alias Cauldron2D.{Player, Worlds}

  test "a world on a node is named through the registry and starts on first use; the node's worlds list" do
    :ok = Worlds.register(:remote_pit, game: Race, name: "Remote Pit")
    on_exit(fn -> Worlds.close(:remote_pit) end)
    assert {:ok, worlds} = Remote.node_worlds(node())
    assert Enum.any?(worlds, &(&1.id == :remote_pit))
    :ok = Player.join({:via, Remote.Worlds, {:node, node(), :remote_pit}}, :alice, %{})
    assert Worlds.running?(:remote_pit)
    assert {:error, _} = Remote.node_world(node(), :nope)
  end
end
