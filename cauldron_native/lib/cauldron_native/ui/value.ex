defmodule CauldronNative.UI.Value do
  @moduledoc """
  Values that cross between the app and the platform in another form: a choice among terms
  goes as its position, a date or a time as ISO 8601 text.

    * `{:index, terms}` — the platform's position in `terms` becomes that term
    * `{:date, :date | :time | :date_time}` — ISO 8601 text becomes a `Date`, a `Time` or
      a `NaiveDateTime`, the time in the device's own zone
    * `{:map, ids}` — a map's marker position becomes that marker's id, and its view's
      region `%{latitude: _, longitude: _, distance: _}`
    * `nil` — the value as it comes
  """

  @type decode ::
          {:index, [term()]} | {:date, :date | :time | :date_time} | {:map, [term()]} | nil

  @doc "The app's value for the platform's `value`."
  @spec decode(decode(), term()) :: term()
  def decode({:index, terms}, index) when is_integer(index), do: Enum.at(terms, index)
  def decode({:date, :date}, text) when is_binary(text), do: Date.from_iso8601!(text)
  def decode({:date, :time}, text) when is_binary(text), do: Time.from_iso8601!(text)

  def decode({:date, :date_time}, text) when is_binary(text),
    do: NaiveDateTime.from_iso8601!(text)

  def decode({:map, ids}, index) when is_integer(index), do: Enum.at(ids, index)

  def decode({:map, _ids}, %{"latitude" => latitude, "longitude" => longitude} = region),
    do: %{latitude: latitude, longitude: longitude, distance: Map.get(region, "distance")}

  def decode(_decode, value), do: value

  @doc "A date or time as the platform takes it, and which of the three it is."
  @spec encode_date(Date.t() | Time.t() | NaiveDateTime.t()) ::
          {String.t(), :date | :time | :date_time}
  def encode_date(%Date{} = date), do: {Date.to_iso8601(date), :date}

  def encode_date(%Time{} = time),
    do: {time |> Time.truncate(:second) |> Time.to_iso8601(), :time}

  def encode_date(%NaiveDateTime{} = moment),
    do: {moment |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601(), :date_time}
end
