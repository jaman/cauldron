defmodule Courtyard.Fetch.Http do
  @moduledoc """
  HTTPS for the fetch: whole files, where a link redirects, and byte ranges of a file.

      {:ok, bytes} = Courtyard.Fetch.Http.get("https://example.com/file")
  """

  @timeout 600_000

  @doc "The body at `url`, following redirects."
  @spec get(String.t()) :: {:ok, binary()} | {:error, term()}
  def get(url) do
    started()

    case :httpc.request(:get, {String.to_charlist(url), []}, options(), body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} -> {:ok, body}
      {:ok, {{_, status, _}, _headers, _body}} -> {:error, {:http, status, url}}
      {:error, reason} -> {:error, {reason, url}}
    end
  end

  @doc "Where `url` redirects to, and the size of the file there."
  @spec located(String.t()) :: {:ok, charlist(), non_neg_integer()} | {:error, term()}
  def located(url) do
    started()

    with {:ok, {{_, status, _}, headers, _}} when status in [301, 302, 303, 307, 308] <-
           :httpc.request(
             :get,
             {String.to_charlist(url), []},
             [autoredirect: false] ++ options(),
             []
           ),
         location when location != nil <- header(headers, ~c"location"),
         {:ok, {{_, 200, _}, head, _}} <- :httpc.request(:head, {location, []}, options(), []) do
      {:ok, location, head |> header(~c"content-length") |> List.to_integer()}
    else
      {:ok, {{_, status, _}, _headers, _body}} -> {:error, {:http, status, url}}
      nil -> {:error, {:no_location, url}}
      {:error, reason} -> {:error, {reason, url}}
    end
  end

  @doc "Bytes `from` to `to` (inclusive) of the file at `location`."
  @spec range(charlist(), non_neg_integer(), non_neg_integer()) ::
          {:ok, binary()} | {:error, term()}
  def range(location, from, to) do
    request = {location, [{~c"range", ~c"bytes=#{from}-#{to}"}]}

    case :httpc.request(:get, request, options(), body_format: :binary) do
      {:ok, {{_, 206, _}, _headers, body}} -> {:ok, body}
      {:ok, {{_, status, _}, _headers, _body}} -> {:error, {:http, status, :range}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp options, do: [timeout: @timeout, connect_timeout: 30_000, ssl: ssl()]

  defp ssl do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]
  end

  defp started do
    {:ok, _} = Application.ensure_all_started([:inets, :ssl])
    :ok
  end

  defp header(headers, name),
    do: Enum.find_value(headers, fn {key, value} -> if key == name, do: value end)
end
