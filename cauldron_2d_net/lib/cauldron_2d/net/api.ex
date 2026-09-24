defmodule Cauldron2D.Net.Api do
  @moduledoc """
  What a client on another machine asks a server over plain HTTP, as a plug a game
  forwards a path to: a token for a name and password (`POST /token`, with `register:
  true` to make the account first), the worlds (`GET /worlds`) as a lobby lists them,
  how the server is keeping up (`GET /stats`), and the boards (`GET /leaders?period=day|
  week|all&metric=<name>&world=<name>`) when the game keeps a ledger.

      forward "/api", Cauldron2D.Net.Api, login: &MyGame.Web.Auth.login/2, register: &MyGame.Web.Auth.register/2, token: &MyGame.Web.Auth.token/1, ledger: MyGame.Ledger

  ## Options

    * `:login` — a function of a name and a password, `{:ok, name}` or `:error`. Required
    * `:register` — a function of a name and a password, `{:ok, name}` or `{:error, reason}`.
      Default: registration refused
    * `:token` — a function from a name to the token a socket connects with. Required
    * `:ledger` — a `Cauldron2D.Ledger` for the boards. Default: none, `GET /leaders` is 404
  """

  use Plug.Router

  alias Cauldron2D.{Ledger, Stats, Worlds}

  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

  @impl Plug
  def init(opts) do
    %{
      login: Keyword.fetch!(opts, :login),
      register:
        Keyword.get(opts, :register, fn _name, _password -> {:error, :no_registration} end),
      token: Keyword.fetch!(opts, :token),
      ledger: Keyword.get(opts, :ledger)
    }
  end

  @impl Plug
  def call(conn, opts), do: conn |> put_private(:cauldron_api, opts) |> super([])

  defp settings(conn), do: conn.private.cauldron_api

  post "/token" do
    opts = settings(conn)

    case conn.body_params do
      %{"username" => username, "password" => password} = params ->
        result =
          if Map.get(params, "register") in [true, "true"],
            do: opts.register.(username, password),
            else: opts.login.(username, password)

        case result do
          {:ok, name} -> json(conn, 200, %{token: opts.token.(name), username: name})
          :error -> json(conn, 401, %{error: "no such name and password"})
          {:error, reason} -> json(conn, 422, %{error: to_string(reason)})
        end

      _other ->
        json(conn, 400, %{error: "username and password wanted"})
    end
  end

  get "/worlds" do
    json(conn, 200, Enum.map(Worlds.list(), &world_json/1))
  end

  get "/stats" do
    json(conn, 200, %{worlds: Stats.worlds(), node: Stats.node()})
  end

  get "/leaders" do
    case settings(conn).ledger do
      nil ->
        json(conn, 404, %{error: "no ledger"})

      ledger ->
        conn = fetch_query_params(conn)
        period = period(conn.query_params["period"])
        metrics = Ledger.metrics(ledger)

        metric =
          Enum.find(
            metrics,
            List.first(metrics),
            &(Atom.to_string(&1) == conn.query_params["metric"])
          )

        board = Ledger.board(ledger, period, metric, world: conn.query_params["world"])

        json(
          conn,
          200,
          Enum.map(board, &Map.update!(&1, :account, fn account -> to_string(account) end))
        )
    end
  end

  match _ do
    json(conn, 404, %{error: "not found"})
  end

  @doc "A world as the API lists it: strings for the id and the kind, no world."
  @spec world_json(map()) :: map()
  def world_json(world) do
    %{
      id: to_string(world.id),
      name: world.name,
      map: Map.get(world, :map),
      note: Map.get(world, :note),
      players: Map.get(world, :players, 0),
      teams: Map.get(world, :teams, []),
      kind: kind(Map.get(world, :kind))
    }
  end

  defp kind({text, {r, g, b}}),
    do: %{text: text, colour: "#" <> Base.encode16(<<r, g, b>>, case: :lower)}

  defp kind(text) when is_binary(text), do: %{text: text, colour: nil}
  defp kind(_none), do: nil

  defp period("day"), do: :day
  defp period("week"), do: :week
  defp period(_other), do: :all

  defp json(conn, status, body),
    do:
      conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(body))
end
