defmodule CauldronNative.Device.Request do
  @moduledoc """
  Sends a request to the native side: the JSON `{"id": id, "action": action, ...params}`,
  `id` the request's tag as `term_to_binary/1` in URL-safe Base64, so the answer carries
  the tag back (`CauldronNative.Device.Answer`).
  """

  alias CauldronNative.Native

  @doc "Send `action` with `params`, its answers tagged `tag`."
  @spec send(term(), String.t(), map()) :: :ok
  def send(tag, action, params),
    do: Native.request(JSON.encode!(Map.merge(%{id: id(tag), action: action}, params)))

  @doc "The id a request tagged `tag` is sent with."
  @spec id(term()) :: String.t()
  def id(tag), do: tag |> :erlang.term_to_binary() |> Base.url_encode64(padding: false)
end
