defmodule Cauldron.Net.Voice.Ice do
  @moduledoc """
  The STUN and TURN servers a browser is given for a voice call, in the shape
  `RTCPeerConnection` takes: a list of `%{urls: [url], username: name, credential: secret}`, the
  last two only for TURN.

  `servers/2` builds the list from the voice settings (`Cauldron.Net.Voice.open/1`):

    * `stun:` — a list of STUN URLs, such as `["stun:stun.cloudflare.com:3478"]`
    * `turn:` — one of
      * `{:cloudflare, key_id, api_token}` — Cloudflare's TURN service; short-lived credentials
        are asked for at `rtc.live.cloudflare.com` and kept until a tenth of their lifetime is left
      * `{:shared_secret, urls, secret}` — a TURN server such as coturn with `use-auth-secret`;
        each player gets a username of the expiry time and their name, and its HMAC-SHA1 as the
        credential, good for a day
      * `{:static, urls, username, credential}` — a TURN server with one fixed login

  With neither, the list is empty and a browser only finds routes on its own network. URLs on
  port 53 are left out, since browsers do not reach TURN on that port.

      Cauldron.Net.Voice.Ice.servers(%{stun: [], turn: {:static, ["turn:example.com:3478"], "u", "p"}}, "ada")
  """

  require Logger

  @type server :: %{
          required(:urls) => [String.t()],
          optional(:username) => String.t(),
          optional(:credential) => String.t()
        }
  @type turn ::
          nil
          | {:cloudflare, String.t(), String.t()}
          | {:shared_secret, [String.t()], String.t()}
          | {:static, [String.t()], String.t(), String.t()}

  @day 86_400
  @cloudflare "https://rtc.live.cloudflare.com/v1/turn/keys/"

  @doc "The servers for `name`'s browser under `settings`, `%{stun: [url], turn: turn}`."
  @spec servers(%{stun: [String.t()], turn: turn()}, String.t()) :: [server()]
  def servers(%{stun: stun, turn: turn}, name) do
    stun_servers = if stun == [], do: [], else: [%{urls: stun}]

    (stun_servers ++ turn_servers(turn, name))
    |> Enum.map(&without_port_53/1)
    |> Enum.reject(&(&1.urls == []))
  end

  defp turn_servers(nil, _name), do: []

  defp turn_servers({:static, urls, username, credential}, _name),
    do: [%{urls: urls, username: username, credential: credential}]

  defp turn_servers({:shared_secret, urls, secret}, name) do
    username = "#{System.system_time(:second) + @day}:#{name}"
    credential = :hmac |> :crypto.mac(:sha, secret, username) |> Base.encode64()
    [%{urls: urls, username: username, credential: credential}]
  end

  defp turn_servers({:cloudflare, key_id, api_token}, _name) do
    case cached(key_id) do
      {:ok, servers} -> servers
      :stale -> fetch_cloudflare(key_id, api_token)
    end
  end

  defp cached(key_id) do
    case :persistent_term.get({__MODULE__, key_id}, nil) do
      {servers, until} -> if System.system_time(:second) < until, do: {:ok, servers}, else: :stale
      nil -> :stale
    end
  end

  defp fetch_cloudflare(key_id, api_token) do
    url = String.to_charlist(@cloudflare <> key_id <> "/credentials/generate-ice-servers")
    headers = [{~c"authorization", String.to_charlist("Bearer " <> api_token)}]
    body = Jason.encode!(%{ttl: @day})

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    with {:ok, {{_version, status, _reason}, _headers, reply}} when status in 200..299 <-
           :httpc.request(
             :post,
             {url, headers, ~c"application/json", body},
             [ssl: ssl, timeout: 5_000],
             body_format: :binary
           ),
         {:ok, %{"iceServers" => servers}} <- Jason.decode(reply) do
      servers = Enum.map(servers, &server/1) |> Enum.filter(&Map.has_key?(&1, :username))

      :persistent_term.put(
        {__MODULE__, key_id},
        {servers, System.system_time(:second) + div(@day * 9, 10)}
      )

      servers
    else
      failure ->
        Logger.warning(
          "voice: Cloudflare TURN credentials could not be fetched: #{inspect(failure)}"
        )

        []
    end
  end

  defp server(%{"urls" => urls} = entry) do
    base = %{urls: List.wrap(urls)}

    case entry do
      %{"username" => username, "credential" => credential} ->
        Map.merge(base, %{username: username, credential: credential})

      _no_login ->
        base
    end
  end

  defp without_port_53(%{urls: urls} = server),
    do: %{server | urls: Enum.reject(urls, &Regex.match?(~r/:53(\?|$)/, &1))}
end
