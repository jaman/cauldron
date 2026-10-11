defmodule Cauldron2D.Drafter.Server do
  @moduledoc """
  Serve a game over ssh, with its accounts, its web endpoint and its beacon.

      {:ok, server} = Cauldron2D.Drafter.Server.start(game: MyGame.Client, port: 2222, web: {:my_game, MyGame.Web.Endpoint, 2280})
      Cauldron2D.Drafter.Server.stop(server)

  Players register on first connection as `new@host` (`:register_as`), or through
  whatever login the game's web pages offer. Each account is given its own sound
  port on the server — `:sound_port` for the first account, the next number for the
  next, and so on — kept in its props as `:pulse_port`; the terminal client's audio
  goes as raw PCM through the `ssh -R <port>:127.0.0.1:4713` tunnel to a player
  program on the player's machine. The worlds are the game's, registered with
  `Cauldron2D.Worlds` before or after the server starts.

  ## Options

    * `:game` — the module implementing `Cauldron2D.Client.Game`. Required
    * `:port` — the ssh port, `0` for any free one. Default `2222`
    * `:ip` — what to bind, as `Drafter.Server.start_ssh/2` takes it. Default `:any`
    * `:accounts` — the account file, or a running `Drafter.Accounts` server. Default
      `Cauldron2D.Paths.data(atlas, "accounts.terms")`
    * `:accounts_name` — a name for the accounts server it starts. Default none
    * `:sound_port` — the first account's sound port, `false` for none. Default `24713`
    * `:system_dir` — the ssh host key directory. Default: drafter's temporary keys
    * `:register_as` — the name that registers. Default `"new"`
    * `:mount_props` — merged into every session's mount props. Default `%{}`
    * `:send_buffer` — the bytes of each connection's send buffer
      (`Drafter.Server.start_ssh/2`), so a session drawing faster than its connection
      carries skips frames instead of falling behind. Default `65536`
    * `:login_timeout` — the milliseconds a player has from connecting to logging in,
      ssh's host key question and the password included. Default `600000`
    * `:web` — `{otp_app, endpoint, port}`: the game's Phoenix endpoint, started on
      every IPv4 interface at that port. Default: none
    * `:beacon` — call on the local network with `Cauldron2D.Beacon`. Default `true`
    * `:beacon_port` — its port. Default `Cauldron2D.Beacon.port/0`
    * `:node` — name this VM so other nodes can join its worlds, `false` for none.
      Default `<atlas>@<host>`, when the VM is not already named

  Returns `{:ok, %{daemon, port, accounts, http, node, beacon}}`, `port` the ssh port
  served on; `stop/1` stops what was
  started, leaving the worlds registered.
  """

  alias Cauldron2D.{Beacon, Paths}

  @supervisor Cauldron2D.Drafter.Server.Supervisor
  @sound_port 24_713
  @send_buffer 65_536
  @login_timeout 600_000
  @closed "The server closed this session."

  @type t :: %{
          daemon: pid() | [pid()],
          port: pos_integer(),
          accounts: pid(),
          http: pos_integer() | nil,
          node: node() | nil,
          beacon: pid() | nil,
          web: module() | nil
        }

  @doc "Start serving; see the module documentation for the options."
  @spec start(keyword()) :: {:ok, t()} | {:error, term()}
  def start(opts) do
    game = Keyword.fetch!(opts, :game)
    :ok = ensure(:ssh)
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)

    with {:ok, port} <- free_port(Keyword.get(opts, :port, 2222)),
         opts = Keyword.put(opts, :port, port),
         {:ok, accounts} <- accounts(game, opts),
         {:ok, daemon} <- daemon(game, accounts, opts),
         {:ok, http, endpoint} <- web(Keyword.get(opts, :web)) do
      node = if Keyword.get(opts, :beacon, true), do: named_node(game, Keyword.get(opts, :node))

      beacon =
        if Keyword.get(opts, :beacon, true),
          do: beacon(game, http, node, Keyword.get(opts, :beacon_port, Beacon.port()))

      {:ok,
       %{
         daemon: daemon,
         port: port,
         accounts: accounts,
         http: http,
         node: node,
         beacon: beacon,
         web: endpoint
       }}
    end
  end

  @doc """
  Stop what `start/1` started. Returns once the ssh port, the web endpoint and the
  beacon are stopped, so the port can be served on again at once. Then, from a process
  of its own, each player connected over ssh is disconnected — their game left, their
  terminal restored and `notice` shown on it (default "#{@closed}") — and the
  accounts server is stopped; the caller may be a process those players' games call.
  """
  @spec stop(t(), String.t()) :: :ok
  def stop(%{daemon: daemon, accounts: accounts} = server, notice \\ @closed) do
    Drafter.Server.stop_ssh_listening(daemon)
    if endpoint = Map.get(server, :web), do: stop_web(endpoint)
    if beacon = Map.get(server, :beacon), do: GenServer.stop(beacon)
    {:ok, _disconnecting} = Task.start(fn -> disconnect(daemon, accounts, notice) end)
    :ok
  end

  defp disconnect(daemon, accounts, notice) do
    Drafter.Server.stop_ssh(daemon, notice)
    if is_pid(accounts) and Process.alive?(accounts), do: GenServer.stop(accounts)
  end

  defp accounts(game, opts) do
    case Keyword.get(opts, :accounts) do
      pid when is_pid(pid) ->
        {:ok, pid}

      path ->
        Drafter.Accounts.start_link(
          path: path || Paths.data(game.atlas(), "accounts.terms"),
          name: Keyword.get(opts, :accounts_name),
          default_props: sound_ports(Keyword.get(opts, :sound_port, @sound_port))
        )
    end
  end

  defp sound_ports(false), do: fn _number -> %{} end
  defp sound_ports(first), do: fn number -> %{pulse_port: first + number} end

  defp free_port(0) do
    with {:ok, socket} <- :gen_tcp.listen(0, []) do
      {:ok, port} = :inet.port(socket)
      :gen_tcp.close(socket)
      {:ok, port}
    end
  end

  defp free_port(port), do: {:ok, port}

  defp daemon(game, accounts, opts) do
    port = Keyword.get(opts, :port, 2222)

    daemon_opts =
      [
        port: port,
        ip: Keyword.get(opts, :ip, :any),
        auth: {:accounts, accounts},
        register_as: Keyword.get(opts, :register_as, "new"),
        tunnel: true,
        send_buffer: Keyword.get(opts, :send_buffer, @send_buffer),
        login_timeout: Keyword.get(opts, :login_timeout, @login_timeout),
        mount_props:
          Map.merge(
            %{game: game, accounts: accounts, served_by: %{host: hostname(), port: port}},
            Keyword.get(opts, :mount_props, %{})
          )
      ] ++ Keyword.take(opts, [:system_dir])

    Drafter.Server.start_ssh(Cauldron2D.Drafter.Client, daemon_opts)
  end

  defp web(nil), do: {:ok, nil, nil}

  defp web({otp_app, endpoint, port}) do
    config = Application.get_env(otp_app, endpoint, [])

    Application.put_env(
      otp_app,
      endpoint,
      Keyword.merge(config,
        http: [ip: {0, 0, 0, 0}, port: port],
        url: [host: hostname(), port: port],
        server: true
      )
    )

    case DynamicSupervisor.start_child(@supervisor, endpoint) do
      {:ok, _pid} -> {:ok, port, endpoint}
      {:error, {:already_started, _pid}} -> {:ok, port, endpoint}
      {:error, reason} -> {:error, {:web, reason}}
    end
  end

  defp stop_web(endpoint) do
    case Process.whereis(endpoint) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(@supervisor, pid)
    end
  end

  defp named_node(_game, false), do: nil

  defp named_node(game, name) do
    if Node.alive?(), do: Node.self(), else: start_node(name || :"#{game.atlas()}@#{hostname()}")
  end

  defp start_node(name) do
    System.cmd("epmd", ["-daemon"])

    case Node.start(name, :shortnames) do
      {:ok, _} -> Node.self()
      {:error, _} -> nil
    end
  end

  defp beacon(game, http, node, port) do
    case Beacon.start_link(
           game: game.atlas(),
           host: hostname(),
           http: http && "http://#{hostname()}:#{http}",
           node: node,
           port: port
         ) do
      {:ok, beacon} -> beacon
      _ -> nil
    end
  end

  @doc "This machine's name, as players are told to connect to it."
  @spec hostname() :: String.t()
  def hostname do
    case :inet.gethostname() do
      {:ok, name} -> to_string(name)
      _ -> "host"
    end
  end

  defp ensure(app) do
    case Application.ensure_started(app) do
      :ok -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end
end
