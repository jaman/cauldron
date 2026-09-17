defmodule Cauldron2D.Net.Remote.WorldsTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.{Arenas, Player}
  alias Cauldron2D.Net.ApiTest.Race
  alias Cauldron2D.Net.Remote

  test "a world on a node is named through the registry and starts on first use; the node's arenas list" do
    :ok = Arenas.register(:remote_pit, game: Race, name: "Remote Pit")
    on_exit(fn -> Arenas.close(:remote_pit) end)
    assert {:ok, arenas} = Remote.node_arenas(node())
    assert Enum.any?(arenas, &(&1.id == :remote_pit))
    :ok = Player.join({:via, Remote.Worlds, {:node, node(), :remote_pit}}, :alice, %{})
    assert Arenas.running?(:remote_pit)
    assert {:error, _} = Remote.node_world(node(), :nope)
  end
end
