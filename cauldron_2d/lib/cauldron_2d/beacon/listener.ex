defmodule Cauldron2D.Beacon.Listener do
  @moduledoc """
  Hears the servers of one game calling on the local network (`Cauldron2D.Beacon`) and
  keeps those heard in the last six seconds.

      {:ok, _} = Cauldron2D.Beacon.Listener.start_link(game: :my_game)
      Cauldron2D.Beacon.Listener.found()

  ## Options

    * `:game` — the game whose servers to keep; others' calls are ignored. Required
    * `:port` — the UDP port. Default `Cauldron2D.Beacon.port/0`
    * `:name` — the process name. Default the module, `nil` for none

  A port it cannot open leaves it deaf, hearing nothing.
  """

  use GenServer

  alias Cauldron2D.Beacon

  @fresh_ms 6_000

  @type server :: %{
          game: String.t(),
          host: String.t(),
          http: String.t() | nil,
          node: atom() | nil,
          fields: %{String.t() => String.t()},
          from: :inet.ip_address(),
          heard: integer()
        }

  @doc "Start listening; see the module documentation for the options."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @doc "The servers heard in the last six seconds, the latest first."
  @spec found(GenServer.server()) :: [server()]
  def found(listener \\ __MODULE__), do: GenServer.call(listener, :found)

  @impl GenServer
  def init(opts) do
    port = Keyword.get(opts, :port, Beacon.port())
    game = opts |> Keyword.fetch!(:game) |> to_string()

    case :gen_udp.open(port, [:binary, active: true, reuseaddr: true] ++ reuseport()) do
      {:ok, socket} -> {:ok, %{socket: socket, game: game, servers: %{}}}
      {:error, _reason} -> {:ok, %{socket: nil, game: game, servers: %{}}}
    end
  end

  defp reuseport do
    case :os.type() do
      {:unix, :darwin} -> [{:raw, 0xFFFF, 0x0200, <<1::native-32>>}]
      {:unix, _} -> [{:raw, 1, 15, <<1::native-32>>}]
      _ -> []
    end
  end

  @impl GenServer
  def handle_call(:found, _from, state) do
    now = System.monotonic_time(:millisecond)

    fresh =
      state.servers
      |> Map.values()
      |> Enum.filter(&(now - &1.heard < @fresh_ms))
      |> Enum.sort_by(& &1.heard, :desc)

    {:reply, fresh, %{state | servers: Map.new(fresh, &{key(&1), &1})}}
  end

  @impl GenServer
  def handle_info({:udp, _socket, from, _port, data}, state) do
    case Beacon.parse(data) do
      {:ok, %{game: game} = call} when game == state.game ->
        server = Map.merge(call, %{from: from, heard: System.monotonic_time(:millisecond)})
        {:noreply, %{state | servers: Map.put(state.servers, key(server), server)}}

      _other ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp key(%{fields: %{"id" => id}}), do: {:id, id}
  defp key(server), do: server.http || server.node

  @impl GenServer
  def terminate(_reason, %{socket: nil}), do: :ok
  def terminate(_reason, %{socket: socket}), do: :gen_udp.close(socket)
end
