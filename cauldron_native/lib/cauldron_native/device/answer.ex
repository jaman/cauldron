defmodule CauldronNative.Device.Answer do
  @moduledoc """
  Decodes an answer from the native side into the message an app gets,
  `{:device, tag, answer}`. The JSON is `{"id": id, "status": "ok" | "cancelled" |
  "error", "value": value}`, `id` as `CauldronNative.Device.Request` made it.

  Values become Elixir terms: the platform's words (`"granted"`, `"opened"`, …) atoms, a
  position a `CauldronNative.Location.Reading`, a push token `{:token, service, token}`,
  a push message `{:received, data}` or `{:opened, data}`, the weather a
  `CauldronNative.Weather.Report`, products a list of `CauldronNative.Purchases.Product`
  and owned products `{:owned, keys}`, a subscription's status and transactions as
  `CauldronNative.Purchases` describes them; anything else, such as paths, stays as the JSON
  gave it.
  """

  alias CauldronNative.Location.Reading
  alias CauldronNative.Purchases.Product
  alias CauldronNative.Weather.Report

  @words Map.new(
           ~w(granted denied finished not_declared not_configured unavailable unsupported scheduled opened started purchased pending not_found failed requested)a,
           &{Atom.to_string(&1), &1}
         )
  @services %{"apns" => :apns, "fcm" => :fcm}

  @doc "The message for `json`, or `:invalid` when it is not an answer to a request."
  @spec decode(binary()) :: {:device, term(), term()} | :invalid
  def decode(json) do
    with {:ok, %{"id" => id, "status" => status} = message} <- JSON.decode(json),
         {:ok, tag} <- tag(id) do
      {:device, tag, answered(status, Map.get(message, "value"))}
    else
      _invalid -> :invalid
    end
  end

  defp answered("ok", value), do: {:ok, value(value)}
  defp answered("cancelled", _value), do: :cancelled
  defp answered(_error, reason), do: {:error, value(reason)}

  defp value(word) when is_map_key(@words, word), do: Map.fetch!(@words, word)
  defp value(%{"latitude" => _, "longitude" => _} = reading), do: Reading.from_json(reading)

  defp value(%{"token" => token, "service" => service}) when is_map_key(@services, service),
    do: {:token, Map.fetch!(@services, service), token}

  defp value(%{"weather" => report}), do: Report.from_json(report)
  defp value(%{"products" => products}), do: Enum.map(products, &Product.from_json/1)
  defp value(%{"owned" => keys}), do: {:owned, Enum.map(keys, &Product.key/1)}

  defp value(%{"subscription" => subscription}),
    do: %{
      current: optional_key(subscription["current"]),
      next: optional_key(subscription["next"]),
      expires: moment(subscription["expires"])
    }

  defp value(%{"transactions" => transactions}),
    do:
      for(
        transaction <- transactions,
        do: %{
          id: transaction["id"],
          key: Product.key(transaction["key"]),
          purchased_at: moment(transaction["purchased"]),
          subscription?: transaction["subscription"] == true
        }
      )

  defp value(%{"received" => data}), do: {:received, data}
  defp value(%{"opened" => data}), do: {:opened, data}
  defp value(value), do: value

  defp optional_key(nil), do: nil
  defp optional_key(key), do: Product.key(key)

  defp moment(nil), do: nil
  defp moment(seconds), do: DateTime.from_unix!(round(seconds))

  defp tag(id) do
    {:ok, id |> Base.url_decode64!(padding: false) |> :erlang.binary_to_term([:safe])}
  rescue
    _invalid -> :error
  end
end
