defmodule Cauldron2D.Beacon do
  @moduledoc """
  How a server on the local network is found: the host says so every two seconds on a
  UDP port — `port/0`, the `:beacon_port` in the `:cauldron_2d` config, #{2299} unless
  set — to the broadcast address and to this machine, and whoever listens
  (`Cauldron2D.Beacon.Listener`) hears it.

      {:ok, beacon} = Cauldron2D.Beacon.start_link(game: :my_game, host: "arcade", http: "http://192.168.1.5:2280", node: :"my_game@arcade")

  A call is one line, `cauldron 1 <game> <host> <http url or -> <node or ->`. A node is
  joined with its cookie, which the host shows and the caller types; it never goes over
  the air. A host started with `:fields` calls `cauldron 2 <game> <host> <http or ->
  <node or -> <fields>` instead, the fields a map of strings, URL-encoded as a query
  string. `put/2` changes them while it calls.
  """

  use GenServer

  @port 2299
  @every_ms 2_000

  @type call :: %{
          game: String.t(),
          host: String.t(),
          http: String.t() | nil,
          node: atom() | nil,
          fields: %{String.t() => String.t()}
        }

  @doc "The UDP port the calls go out on: `config :cauldron_2d, beacon_port: n`, else #{@port}."
  @spec port() :: pos_integer()
  def port, do: Application.get_env(:cauldron_2d, :beacon_port, @port)

  @doc "Start calling; `:game` the game's name, `:host` the name to call as, `:http` the web URL or `nil`, `:node` the node name or `nil`, `:fields` a map of strings or `nil` (default), `:port` the UDP port (default `port/0`)."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "Change the fields `beacon` calls with, from its next call on."
  @spec put(GenServer.server(), %{String.t() => String.t()}) :: :ok
  def put(beacon, fields), do: GenServer.cast(beacon, {:fields, fields})

  @doc "The line a host calls with: `fields` `nil` for the first form, a map for the second."
  @spec line(atom() | String.t(), String.t(), String.t() | nil, atom() | nil, map() | nil) ::
          String.t()
  def line(game, host, http, node, fields \\ nil)

  def line(game, host, http, node, nil),
    do: "cauldron 1 #{game} #{host} #{http || "-"} #{node || "-"}"

  def line(game, host, http, node, fields),
    do: "cauldron 2 #{game} #{host} #{http || "-"} #{node || "-"} #{URI.encode_query(fields)}"

  @doc "A call heard, or `:error` for anything else."
  @spec parse(String.t()) :: {:ok, call()} | :error
  def parse(text) do
    case String.split(String.trim(text), " ") do
      ["cauldron", "1", game, host, http, node] ->
        {:ok, call(game, host, http, node, %{})}

      ["cauldron", "2", game, host, http, node, fields] ->
        {:ok, call(game, host, http, node, URI.decode_query(fields))}

      _ ->
        :error
    end
  end

  defp call(game, host, http, node, fields) do
    %{
      game: game,
      host: host,
      http: if(http == "-", do: nil, else: http),
      node: if(node == "-", do: nil, else: String.to_atom(node)),
      fields: fields
    }
  end

  @impl GenServer
  def init(opts) do
    {:ok, socket} = :gen_udp.open(0, [:binary, broadcast: true, active: false])

    parts =
      {Keyword.fetch!(opts, :game), Keyword.fetch!(opts, :host), Keyword.get(opts, :http),
       Keyword.get(opts, :node)}

    state = %{
      socket: socket,
      parts: parts,
      line: lined(parts, Keyword.get(opts, :fields)),
      port: Keyword.get(opts, :port, port())
    }

    send(self(), :call)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:call, state) do
    for address <- [{255, 255, 255, 255}, {127, 0, 0, 1}],
        do: :gen_udp.send(state.socket, address, state.port, state.line)

    Process.send_after(self(), :call, @every_ms)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:fields, fields}, state),
    do: {:noreply, %{state | line: lined(state.parts, fields)}}

  @impl GenServer
  def terminate(_reason, %{socket: socket}), do: :gen_udp.close(socket)

  defp lined({game, host, http, node}, fields), do: line(game, host, http, node, fields)
end
