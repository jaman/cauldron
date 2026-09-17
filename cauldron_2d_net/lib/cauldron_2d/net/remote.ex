defmodule Cauldron2D.Net.Remote do
  @moduledoc """
  What a client asks a server it does not run in: a token for a name and password over
  HTTP (`Cauldron2D.Net.Api`), the arenas, the server's stats and boards; and the same
  from a node it is connected to.

      {:ok, token} = Cauldron2D.Net.Remote.login("http://arcade:2280", "alice", "secret", false)
      {:ok, arenas} = Cauldron2D.Net.Remote.arenas("http://arcade:2280")
      {:ok, arenas} = Cauldron2D.Net.Remote.node_arenas(:"my_game@arcade")
      {:ok, world} = Cauldron2D.Net.Remote.node_world(:"my_game@arcade", :pit)

  `url` is the server's base URL with the API's path, `http://host:port/api` for an
  API forwarded at `/api`.
  """

  alias Cauldron2D.Arenas

  @type arena :: %{
          id: String.t(),
          name: String.t(),
          map: String.t() | nil,
          note: String.t() | nil,
          players: non_neg_integer(),
          teams: list(),
          kind: {String.t(), {byte(), byte(), byte()}} | nil
        }

  @doc "A token from `POST <url>/token`; `register?` makes the account first. `{:error, text}` with the server's reason."
  @spec login(String.t(), String.t(), String.t(), boolean()) ::
          {:ok, String.t()} | {:error, String.t()}
  def login(url, username, password, register?) do
    case request(
           :post,
           url <> "/token",
           Jason.encode!(%{username: username, password: password, register: register?})
         ) do
      {:ok, 200, %{"token" => token}} -> {:ok, token}
      {:ok, _status, %{"error" => error}} -> {:error, error}
      {:ok, status, _body} -> {:error, "the server said #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "The arenas from `GET <url>/arenas`."
  @spec arenas(String.t()) :: {:ok, [arena()]} | {:error, String.t()}
  def arenas(url) do
    case request(:get, url <> "/arenas", nil) do
      {:ok, 200, list} when is_list(list) -> {:ok, Enum.map(list, &arena/1)}
      {:ok, status, _body} -> {:error, "the server said #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp arena(map) do
    %{
      id: map["id"],
      name: map["name"],
      map: map["map"],
      note: map["note"],
      players: map["players"] || 0,
      teams: map["teams"] || [],
      kind: kind(map["kind"])
    }
  end

  defp kind(%{"text" => text, "colour" => "#" <> hex}),
    do: {text, hex |> Base.decode16!(case: :mixed) |> then(fn <<r, g, b>> -> {r, g, b} end)}

  defp kind(%{"text" => text}), do: {text, {255, 255, 255}}
  defp kind(_none), do: nil

  @doc "How the server is keeping up, from `GET <url>/stats`, with atom keys."
  @spec stats(String.t()) :: {:ok, %{arenas: [map()], node: map()}} | {:error, String.t()}
  def stats(url) do
    case request(:get, url <> "/stats", nil) do
      {:ok, 200, %{"arenas" => arenas, "node" => node}} ->
        {:ok,
         %{
           arenas: Enum.map(arenas, &arena_stats/1),
           node: Map.new(node, fn {key, value} -> {String.to_atom(key), value} end)
         }}

      {:ok, status, _body} ->
        {:error, "the server said #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp arena_stats(map) do
    %{
      name: map["name"],
      players: map["players"],
      hz: map["hz"],
      steps: map["steps"],
      ticks: map["ticks"],
      tick_us: %{
        mean: map["tick_us"]["mean"],
        p95: map["tick_us"]["p95"],
        max: map["tick_us"]["max"]
      },
      behind: map["behind"]
    }
  end

  @doc "A board from `GET <url>/leaders`, as `Cauldron2D.Ledger.board/4` gives it, accounts as strings."
  @spec leaders(String.t(), atom(), atom(), keyword()) :: {:ok, [map()]} | {:error, String.t()}
  def leaders(url, period, metric, opts \\ []) do
    query =
      URI.encode_query(
        %{period: period, metric: metric}
        |> Map.merge(if(opts[:arena], do: %{arena: opts[:arena]}, else: %{}))
      )

    case request(:get, url <> "/leaders?" <> query, nil) do
      {:ok, 200, list} when is_list(list) -> {:ok, Enum.map(list, &entry/1)}
      {:ok, status, _body} -> {:error, "the server said #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp entry(map) do
    %{
      name: map["name"],
      account: map["account"],
      value: map["value"],
      rounds: map["rounds"],
      values: Map.new(map["values"] || %{}, fn {key, value} -> {String.to_atom(key), value} end)
    }
  end

  @doc "The arenas of a connected node, as its `Cauldron2D.Arenas.list/0` gives them."
  @spec node_arenas(node()) :: {:ok, [map()]} | {:error, String.t()}
  def node_arenas(node) do
    case :rpc.call(node, Arenas, :list, []) do
      list when is_list(list) -> {:ok, list}
      {:badrpc, reason} -> {:error, "could not reach #{node}: #{inspect(reason)}"}
    end
  end

  @doc "The pid of arena `id`'s world on `node`, started there if it was not running."
  @spec node_world(node(), term()) :: {:ok, pid()} | {:error, String.t()}
  def node_world(node, id) do
    case :rpc.call(node, Arenas, :start, [id]) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, inspect(reason)}
      {:badrpc, reason} -> {:error, "could not reach #{node}: #{inspect(reason)}"}
    end
  end

  @doc "A board of a connected node's ledger."
  @spec node_leaders(node(), GenServer.name(), atom(), atom(), keyword()) ::
          {:ok, [map()]} | {:error, String.t()}
  def node_leaders(node, ledger, period, metric, opts \\ []) do
    case :rpc.call(node, Cauldron2D.Ledger, :board, [ledger, period, metric, opts]) do
      list when is_list(list) -> {:ok, list}
      {:badrpc, reason} -> {:error, "could not reach #{node}: #{inspect(reason)}"}
    end
  end

  defp request(method, url, body) do
    :inets.start()
    :ssl.start()

    request =
      if body,
        do: {String.to_charlist(url), [], ~c"application/json", body},
        else: {String.to_charlist(url), []}

    case :httpc.request(method, request, [ssl: [verify: :verify_none], timeout: 10_000],
           body_format: :binary
         ) do
      {:ok, {{_, status, _}, _headers, response}} -> {:ok, status, decode(response)}
      {:error, reason} -> {:error, "no answer from #{url}: #{inspect(reason)}"}
    end
  end

  defp decode(body) do
    case Jason.decode(body) do
      {:ok, json} -> json
      {:error, _} -> body
    end
  end
end
