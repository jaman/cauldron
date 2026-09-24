defmodule Cistern.Web do
  @moduledoc """
  The game in a browser: `Cauldron2D.Net.Pages` at `/play` for the title, the lobby,
  the world and the guide, and the player socket the world page connects to.

      mix cistern.serve            # http://localhost:4300/play

  Every visitor plays as `guest`; a game with accounts gives `Cauldron2D.Net.Pages` a
  function that reads the signed-in name instead.
  """

  defmodule Socket do
    @moduledoc "The player socket; every connection is `guest`."
    use Cauldron2D.Net.Socket, channel: Cistern.Web.Channel, verify: {Cistern.Web, :verify}
  end

  defmodule Channel do
    @moduledoc "A browser player in a cistern."
    use Cauldron2D.Net.Channel, game: Cistern.Client
  end

  defmodule Router do
    @moduledoc "The pages at `/play`, the sheet and the scripts with them."
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    forward("/play",
      to: Cauldron2D.Net.Pages,
      init_opts: [game: Cistern.Client, username: &Cistern.Web.username/1]
    )

    match _ do
      conn |> Plug.Conn.put_resp_header("location", "/play") |> Plug.Conn.send_resp(302, "")
    end
  end

  defmodule Endpoint do
    @moduledoc "The HTTP endpoint: the socket and the router."
    use Phoenix.Endpoint, otp_app: :cistern

    socket("/socket", Cistern.Web.Socket, websocket: true, longpoll: false)
    plug(Plug.Parsers, parsers: [:urlencoded, :json], pass: ["*/*"], json_decoder: Jason)
    plug(Cistern.Web.Router)
  end

  @doc "The player's name for a request."
  @spec username(Plug.Conn.t()) :: String.t()
  def username(_conn), do: "guest"

  @doc "The socket's verification: a connection that names itself with `name` is that player, any other a guest."
  @spec verify(map()) :: {:ok, map()} | :error
  def verify(%{"name" => ""}), do: :error
  def verify(%{"name" => name}) when is_binary(name), do: {:ok, %{username: name}}
  def verify(_params), do: {:ok, %{username: "guest"}}
end
