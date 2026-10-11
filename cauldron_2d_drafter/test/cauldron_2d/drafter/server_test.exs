defmodule Cauldron2D.Drafter.ServerTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Drafter.Server
  alias Cauldron2D.TestGames.Dots

  defmodule Served do
    @moduledoc false
    @behaviour Cauldron2D.Client.Game

    def title, do: %{name: "SERVED"}
    def atlas, do: :served_test
    def actions, do: [:left]
    def keymaps, do: [arrows: %{left: [:left]}]
    def toggles, do: []

    def worlds(_props),
      do: [%{id: :pit, name: "Pit", world: Cauldron2D.Worlds.world_name(:served_pit), players: 0}]

    def scene(view),
      do: %{
        focus: view.me.pos,
        bounds: {view.width, view.height},
        cell: fn _ -> :void end,
        movers: view.movers
      }

    def hud(_view), do: []
    def listener(_view), do: nil
    def sounds, do: fn _ -> nil end
    def music, do: []
    def cue(_view, _screen), do: nil
  end

  test "the server starts the ssh daemon and the accounts with sound ports, and stops again" do
    dir = Path.join(System.tmp_dir!(), "cauldron_server_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    :ok = Cauldron2D.Worlds.register(:served_pit, game: Dots)
    port = 39_000 + :rand.uniform(900)

    assert {:ok, server} =
             Server.start(
               game: Served,
               port: port,
               ip: {127, 0, 0, 1},
               accounts: Path.join(dir, "accounts.terms"),
               beacon: false,
               sound_port: 30_000
             )

    assert is_pid(server.accounts)
    assert server.http == nil and server.beacon == nil
    :ok = Drafter.Accounts.register(server.accounts, "alice", "a long enough password")

    assert {:ok, %{props: %{pulse_port: 30_000}}} =
             Drafter.Accounts.fetch(server.accounts, "alice")

    assert {:ok, _socket} =
             :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 2_000)

    accounts = Process.monitor(server.accounts)
    assert :ok = Server.stop(server)

    assert {:error, :econnrefused} =
             :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 2_000)

    assert_receive {:DOWN, ^accounts, :process, _pid, _reason}, 5_000
    Cauldron2D.Worlds.close(:served_pit)
    File.rm_rf!(dir)
  end
end
