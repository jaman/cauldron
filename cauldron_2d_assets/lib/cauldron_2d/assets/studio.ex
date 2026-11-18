defmodule Cauldron2D.Assets.Studio do
  @moduledoc """
  A client of NxDiffusion Studio, over its MCP server's HTTP transport: one JSON-RPC
  `tools/call` per request, its answer decoded.

      Cauldron2D.Assets.Studio.call("generate_image", %{prompt: "a clay jar", count: 2})
      #=> {:ok, %{"job_id" => "...", "status" => "queued"}}

  The server and token are each the option given, else the environment variable, else
  the application config, else the default (`Cauldron.Launch`'s order). The server is
  `call/3`'s `:url` option, else `NX_STUDIO_URL`, else `config :cauldron_2d_assets, studio: url`, else
  `http://localhost:4102/mcp`. A program on the Studio's own machine needs no token; from
  elsewhere the Studio's agent token is sent as a bearer token: the `:token` option, else
  `NX_STUDIO_TOKEN`, else `config :cauldron_2d_assets, studio_token: token`.

  Tools answer with text content, one block of it JSON; `call/3` gives that JSON
  decoded (or the text, when no block is JSON), and a tool's own error as
  `{:error, {:tool, message}}`.
  """

  @default "http://localhost:4102/mcp"
  @timeout 900_000

  @doc """
  The answer of tool `name` given `arguments`. Options: `:timeout` in milliseconds
  (default 15 minutes), `:url` and `:token` (see the module documentation).
  """
  @spec call(String.t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def call(name, arguments, opts \\ []) do
    body = %{
      jsonrpc: "2.0",
      id: System.unique_integer([:positive]),
      method: "tools/call",
      params: %{name: name, arguments: arguments}
    }

    case Req.post(url(opts),
           json: body,
           headers: headers(opts),
           receive_timeout: Keyword.get(opts, :timeout, @timeout),
           retry: false
         ) do
      {:ok, %{status: 200, body: %{"result" => result}}} -> answer(result)
      {:ok, %{status: 200, body: %{"error" => error}}} -> {:error, {:rpc, error}}
      {:ok, %{status: status, body: body}} -> {:error, {:http, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "The address requests go to, given `call/3`'s options."
  @spec url(keyword()) :: String.t()
  def url(opts \\ []) do
    setting(Keyword.get(opts, :url), "NX_STUDIO_URL", :studio) || @default
  end

  defp headers(opts) do
    base = [{"accept", "application/json"}]

    case setting(Keyword.get(opts, :token), "NX_STUDIO_TOKEN", :studio_token) do
      nil -> base
      token -> [{"authorization", "Bearer " <> token} | base]
    end
  end

  defp answer(%{"isError" => true, "content" => content}), do: {:error, {:tool, text(content)}}

  defp answer(%{"content" => content}) do
    content
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.find_value(fn block ->
      case Jason.decode(block["text"]) do
        {:ok, decoded} -> {:ok, decoded}
        {:error, _not_json} -> nil
      end
    end)
    |> case do
      nil -> {:ok, text(content)}
      decoded -> decoded
    end
  end

  defp text(content) do
    content
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map_join("\n", & &1["text"])
  end

  defp setting(given, variable, key),
    do: given || System.get_env(variable) || Application.get_env(:cauldron_2d_assets, key)
end
