defmodule CauldronNative.Location.Reading do
  @moduledoc """
  Where the phone is: `latitude` and `longitude` in degrees, `accuracy` the radius in
  metres the position is within, `altitude` in metres above sea level, `speed` in metres
  a second, `heading` in degrees from north, and `time` when it was measured. Fields the
  phone did not measure are `nil`.
  """

  @enforce_keys [:latitude, :longitude, :accuracy, :time]
  defstruct [:latitude, :longitude, :accuracy, :altitude, :speed, :heading, :time]

  @type t :: %__MODULE__{
          latitude: float(),
          longitude: float(),
          accuracy: float(),
          altitude: float() | nil,
          speed: float() | nil,
          heading: float() | nil,
          time: DateTime.t()
        }

  @doc """
  The reading in the JSON the native side sends: `latitude`, `longitude`, `accuracy`,
  optional `altitude`, `speed` and `heading`, and `time` in milliseconds since 1970.
  """
  @spec from_json(map()) :: t()
  def from_json(%{"latitude" => latitude, "longitude" => longitude} = json) do
    %__MODULE__{
      latitude: latitude / 1,
      longitude: longitude / 1,
      accuracy: Map.get(json, "accuracy", 0) / 1,
      altitude: number(json["altitude"]),
      speed: number(json["speed"]),
      heading: number(json["heading"]),
      time: DateTime.from_unix!(trunc(Map.get(json, "time", 0)), :millisecond)
    }
  end

  defp number(nil), do: nil
  defp number(value), do: value / 1
end
