defmodule Cauldron2D.BeaconTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Beacon

  test "a call names the game, the host, the web url and the node, and reads back" do
    line = Beacon.line(:my_game, "arcade", "http://192.168.1.5:2280", :my_game@arcade)
    assert line == "cauldron 1 my_game arcade http://192.168.1.5:2280 my_game@arcade"

    assert {:ok,
            %{
              game: "my_game",
              host: "arcade",
              http: "http://192.168.1.5:2280",
              node: :my_game@arcade
            }} = Beacon.parse(line)

    assert {:ok, %{http: nil, node: nil}} = Beacon.parse("cauldron 1 my_game arcade - -")
    assert :error = Beacon.parse("expilot 1 arcade - -")
  end

  test "a listener hears a beacon on its port and keeps it for a while, only for its game" do
    port = 40_000 + :rand.uniform(10_000)
    {:ok, listener} = Beacon.Listener.start_link(game: :my_game, port: port, name: nil)
    {:ok, other} = Beacon.start_link(game: :other_game, host: "elsewhere", port: port)

    {:ok, beacon} =
      Beacon.start_link(game: :my_game, host: "arcade", http: "http://h:1", port: port)

    Process.sleep(200)
    assert [%{host: "arcade", http: "http://h:1", from: _}] = Beacon.Listener.found(listener)
    GenServer.stop(beacon)
    GenServer.stop(other)
    GenServer.stop(listener)
  end
end
