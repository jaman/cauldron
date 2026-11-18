defmodule Cauldron2D.Net.Wire do
  @moduledoc """
  The pushes `Cauldron2D.Net.Drawer` sends read into plain shapes, for a client joining a
  served world over its WebSocket: a sheet's tile, URL, size and void colour, and who
  draws.

      Cauldron2D.Net.Wire.sheet(%{"tile" => 16, "url" => "/atlas.png", "void" => "#000000", "width" => 256, "height" => 128})
  """

  alias Cauldron.Net.Wire

  @doc "A `\"drawing\"` payload: who draws the world and the screen, `:server` or `:client`."
  @spec drawing(map()) :: %{world: :server | :client, screen: :server | :client}
  def drawing(payload),
    do: %{world: part(Wire.field(payload, :world)), screen: part(Wire.field(payload, :screen))}

  defp part(part) when part in [:server, "server"], do: :server
  defp part(part) when part in [:client, "client"], do: :client

  @doc "A `\"sheet\"` payload, `Cauldron2D.Net.Atlas.index/2`'s: the tile size, the void colour, the sheet's URL and size."
  @spec sheet(map()) :: %{
          tile: pos_integer(),
          url: String.t(),
          void: {byte(), byte(), byte()},
          width: pos_integer(),
          height: pos_integer()
        }
  def sheet(payload) do
    %{
      tile: Wire.field(payload, :tile),
      url: Wire.field(payload, :url),
      void: rgb(Wire.field(payload, :void)),
      width: Wire.field(payload, :width),
      height: Wire.field(payload, :height)
    }
  end

  defp rgb("#" <> hex),
    do: hex |> Base.decode16!(case: :mixed) |> then(fn <<r, g, b>> -> {r, g, b} end)

  defp rgb(_none), do: {0, 0, 0}
end
