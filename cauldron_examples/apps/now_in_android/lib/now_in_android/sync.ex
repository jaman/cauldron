defmodule NowInAndroid.Sync do
  @moduledoc """
  Brings the news up to date from the news server (`apps/now_in_android_server`), as the
  sample syncs from its backend, and tells the user about new resources in the topics
  they follow with a notification each, which opens the resource when tapped.

  The server is `NIA_SERVER` when the app was built with it, else this Mac as the
  device sees it: `http://10.0.2.2:4180` from the Android emulator, `http://localhost:4180`
  from the iOS simulator and the Mac.
  """

  require Logger

  alias CauldronNative.Notifications
  alias NowInAndroid.{Content, News}

  @doc """
  Fetch the server's news, keep what is new, and notify the user of the new resources in
  `followed` topics; the new resources, or `{:error, reason}` when the server could not
  be reached.
  """
  @spec run(MapSet.t()) :: {:ok, [map()]} | {:error, term()}
  def run(followed) do
    case fetch(server() <> "/news") do
      {:ok, json} ->
        added = json |> Enum.map(&Content.resource/1) |> News.merge()
        added |> Enum.filter(&followed?(&1, followed)) |> Enum.each(&notify/1)
        {:ok, added}

      {:error, reason} ->
        Logger.warning("The news server #{server()} could not be reached: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "The news server's address."
  @spec server() :: String.t()
  def server do
    case System.get_env("NIA_SERVER") do
      address when address in [nil, ""] -> default_server(CauldronNative.Device.system())
      address -> address
    end
  end

  defp default_server(:android), do: "http://10.0.2.2:4180"
  defp default_server(_apple), do: "http://localhost:4180"

  defp fetch(url) do
    request =
      {String.to_charlist(url), [{~c"accept", ~c"application/json"}, {~c"connection", ~c"close"}]}

    case :httpc.request(:get, request, [timeout: 10_000, connect_timeout: 5_000],
           body_format: :binary
         ) do
      {:ok, {{_version, 200, _reason}, _headers, body}} -> JSON.decode(body)
      {:ok, {{_version, status, _reason}, _headers, _body}} -> {:error, {:status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp followed?(resource, followed),
    do: Enum.any?(resource.topics, &MapSet.member?(followed, &1))

  defp notify(resource),
    do: Notifications.schedule({:news, resource.id}, "New in Now in Android", resource.title)
end
