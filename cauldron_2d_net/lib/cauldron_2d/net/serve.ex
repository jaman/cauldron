defmodule Cauldron2D.Net.Serve do
  @moduledoc """
  Serves a game to browsers, and to desktops over the socket, with no web code of the
  game's own: its pages (`Cauldron2D.Net.Pages`) at `/play`, its player socket at
  `/socket` with every connection named by its `username` or `name` connect param (or
  `guest`), the pages naming the player by the `name` query param, kept in a cookie for the
  pages after it, and
  its channel (`Cauldron.Net.Channel`), drawn through `Cauldron2D.Net.Drawer` or the
  `:drawer` given.

      defmodule Mix.Tasks.MyGame.Serve do
        use Mix.Task

        def run(argv), do: Cauldron2D.Net.Serve.run(MyGame.Client, argv, port: 4300)
      end

  A game whose players sign in writes its own endpoint, as `Cauldron2D.Net.Pages` and
  `Cauldron.Net.Socket` describe.

  ## Flags

    * `--port PORT` — the port to listen on
    * `--drawing server|client|split` — who draws, over the config
      (`Cauldron2D.Net.Drawing`)

  ## Options

    * `:port` — the port when `--port` is not given. Default `4300`
    * `:drawing` — as `Cauldron2D.Net.Drawing.resolve/1` takes it, when `--drawing` is
      not given; left out, the environment and the config decide
    * `:before` — a function of no arguments run once the application has started, such
      as registering the game's worlds
    * `:secret_key_base` — the secret the player's saved settings are signed with.
      Default: one made for this run, so settings saved in a browser last for the run
    * `:drawer` — the drawer, `module` or `{module, opts}` (`Cauldron.Net.Drawer`), such as
      `Cauldron3D.Net.Drawer` for a 3D game. Default `Cauldron2D.Net.Drawer`, with the
      drawing `:drawing` gives
  """

  alias Cauldron2D.Net.Drawing

  @flags [port: :integer, drawing: :string]

  @doc "Starts the application and serves `game` with `argv`'s flags until the node stops."
  @spec run(module(), [String.t()], keyword()) :: no_return()
  def run(game, argv, opts \\ []) do
    {flags, _rest, _invalid} = OptionParser.parse(argv, strict: @flags)
    Mix.Task.run("app.start")
    if before = Keyword.get(opts, :before), do: before.()
    port = Keyword.get(flags, :port) || Keyword.get(opts, :port, 4300)
    drawing = parsed_drawing(Keyword.get(flags, :drawing)) || Keyword.get(opts, :drawing)

    {:ok, _endpoint} =
      start(game,
        port: port,
        drawing: drawing,
        secret_key_base: Keyword.get(opts, :secret_key_base),
        drawer: Keyword.get(opts, :drawer)
      )

    Mix.shell().info("#{game.title().name} at http://localhost:#{port}/play")
    Process.sleep(:infinity)
  end

  @doc """
  Starts the endpoint serving `game` under this process. Options: `:port` (default
  `4300`), `:drawing`, `:secret_key_base`, `:drawer`.
  """
  @spec start(module(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start(game, opts \\ []) do
    game.atlas()
    :persistent_term.put({__MODULE__, :game}, game)
    :persistent_term.put({__MODULE__, :drawing}, Keyword.get(opts, :drawing))
    :persistent_term.put({__MODULE__, :drawer}, Keyword.get(opts, :drawer))

    with {:ok, _pubsub} <- pubsub() do
      __MODULE__.Endpoint.start_link(
        http: [port: Keyword.get(opts, :port, 4300)],
        server: true,
        adapter: Bandit.PhoenixAdapter,
        secret_key_base: Keyword.get(opts, :secret_key_base) || secret(),
        pubsub_server: __MODULE__.PubSub
      )
    end
  end

  @doc false
  def game, do: :persistent_term.get({__MODULE__, :game})

  @doc false
  def drawing, do: :persistent_term.get({__MODULE__, :drawing}, nil)

  @doc false
  def drawer,
    do:
      :persistent_term.get({__MODULE__, :drawer}, nil) ||
        {Cauldron2D.Net.Drawer, drawing: drawing(), sheet_url: "/play/atlas.png"}

  @doc false
  def username(conn),
    do: Map.get(conn.query_params, "name") || conn.cookies["cauldron_name"] || "guest"

  @doc false
  def verify(%{"username" => ""}), do: :error

  def verify(%{"username" => name}) when is_binary(name) and name != "",
    do: {:ok, %{username: name}}

  def verify(%{"name" => name}) when is_binary(name) and name != "", do: {:ok, %{username: name}}
  def verify(_params), do: {:ok, %{username: "guest"}}

  defp pubsub do
    case Phoenix.PubSub.Supervisor.start_link(name: __MODULE__.PubSub) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  defp secret, do: Base.encode64(:crypto.strong_rand_bytes(48))

  defp parsed_drawing(nil), do: nil
  defp parsed_drawing(text), do: Drawing.parse(text)

  defmodule Channel do
    @moduledoc "The served game's channel: `Cauldron.Net.Channel` for the game `Cauldron2D.Net.Serve` serves."
    use Phoenix.Channel, log_handle_in: false

    alias Cauldron.Net.Channel, as: NetChannel
    alias Cauldron2D.Net.Serve

    @impl true
    def join("world:" <> id, params, socket),
      do:
        NetChannel.join(
          Serve.game(),
          [
            audio: %{rate: 44_100, channels: 2},
            drawer: Serve.drawer()
          ],
          id,
          params,
          socket
        )

    @impl true
    def handle_in(event, payload, socket),
      do: NetChannel.handle_in(event, payload, socket)

    @impl true
    def handle_info(message, socket), do: NetChannel.handle_info(message, socket)

    @impl true
    def terminate(_reason, socket), do: NetChannel.terminate(socket)
  end

  defmodule Socket do
    @moduledoc "The served game's player socket; a connection is the player its `name` param names, or `guest`. It also routes `\"voice\"` (`Cauldron.Net.Voice`)."
    use Cauldron.Net.Socket,
      channel: Cauldron2D.Net.Serve.Channel,
      verify: {Cauldron2D.Net.Serve, :verify},
      voice: true
  end

  defmodule Pages do
    @moduledoc "`Cauldron2D.Net.Pages` for the served game, its name from the `name` query param."
    @behaviour Plug

    alias Cauldron2D.Net.Pages, as: NetPages
    alias Cauldron2D.Net.Serve

    @impl Plug
    def init(_opts), do: []

    @impl Plug
    def call(conn, _opts) do
      conn = conn |> Plug.Conn.fetch_cookies() |> Plug.Conn.fetch_query_params() |> remembered()

      opts =
        NetPages.init(
          game: Serve.game(),
          username: &Serve.username/1,
          drawer: Serve.drawer()
        )

      NetPages.call(conn, opts)
    end

    defp remembered(%{query_params: %{"name" => name}} = conn)
         when is_binary(name) and name != "",
         do: Plug.Conn.put_resp_cookie(conn, "cauldron_name", name)

    defp remembered(conn), do: conn
  end

  defmodule Router do
    @moduledoc "The served game's pages at `/play`."
    use Plug.Router

    plug(:match)
    plug(:fetch_query_params)
    plug(:dispatch)

    forward("/play", to: Cauldron2D.Net.Serve.Pages)

    match _ do
      conn |> Plug.Conn.put_resp_header("location", "/play") |> Plug.Conn.send_resp(302, "")
    end
  end

  defmodule Endpoint do
    @moduledoc "The served game's HTTP endpoint: the socket and the pages."
    use Phoenix.Endpoint, otp_app: :cauldron_2d_net

    socket("/socket", Cauldron2D.Net.Serve.Socket,
      websocket: [check_origin: :conn],
      longpoll: false
    )

    plug(Plug.Parsers, parsers: [:urlencoded, :json], pass: ["*/*"], json_decoder: Jason)
    plug(Cauldron2D.Net.Serve.Router)
  end
end
