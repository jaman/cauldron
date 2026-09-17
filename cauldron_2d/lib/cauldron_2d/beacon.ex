defmodule Cauldron2D.Beacon do
  @moduledoc """
  How a server on the local network is found: the host says so every two seconds on a
  UDP port — `port/0`, the `:beacon_port` in the `:cauldron_2d` config, #{2299} unless
  set — to the broadcast address and to this machine, and whoever listens
  (`Cauldron2D.Beacon.Listener`) hears it.

      {:ok, beacon} = Cauldron2D.Beacon.start_link(game: :my_game, host: "arcade", http: "http://192.168.1.5:2280", node: :"my_game@arcade")

  A call is one line, `cauldron 1 <game> <host> <http url or -> <node or ->`. A node is
  joined with its cookie, which the host shows and the caller types; it never goes over
  the air.
  """

  use GenServer

  @port 2299
  @every_ms 2_000

  @type call :: %{game: String.t(), host: String.t(), http: String.t() | nil, node: atom() | nil}

  @doc "The UDP port the calls go out on: `config :cauldron_2d, beacon_port: n`, else #{@port}."
  @spec port() :: pos_integer()
  def port, do: Application.get_env(:cauldron_2d, :beacon_port, @port)

  @doc "Start calling; `:game` the game's name, `:host` the name to call as, `:http` the web URL or `nil`, `:node` the node name or `nil`, `:port` the UDP port (default `port/0`)."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "The line a host calls with."
  @spec line(atom() | String.t(), String.t(), String.t() | nil, atom() | nil) :: String.t()
  def line(game, host, http, node), do: "cauldron 1 #{game} #{host} #{http || "-"} #{node || "-"}"

  @doc "A call heard, or `:error` for anything else."
  @spec parse(String.t()) :: {:ok, call()} | :error
  def parse(text) do
    case String.split(String.trim(text), " ") do
      ["cauldron", "1", game, host, http, node] ->
        {:ok,
         %{
           game: game,
           host: host,
           http: if(http == "-", do: nil, else: http),
           node: if(node == "-", do: nil, else: String.to_atom(node))
         }}

      _ ->
        :error
    end
  end

  @impl GenServer
  def init(opts) do
    {:ok, socket} = :gen_udp.open(0, [:binary, broadcast: true, active: false])

    line =
      line(
        Keyword.fetch!(opts, :game),
        Keyword.fetch!(opts, :host),
        Keyword.get(opts, :http),
        Keyword.get(opts, :node)
      )

    state = %{socket: socket, line: line, port: Keyword.get(opts, :port, port())}
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
  def terminate(_reason, %{socket: socket}), do: :gen_udp.close(socket)
end
