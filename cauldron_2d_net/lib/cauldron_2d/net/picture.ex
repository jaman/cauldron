defmodule Cauldron2D.Net.Picture do
  @moduledoc """
  A server-drawn picture as it goes to a client: a truecolour PNG, deflated at the
  fastest level, so a frame costs the server about a millisecond to encode.

      Cauldron2D.Net.Picture.png(raster)
  """

  alias FrenchCurve.Png

  alias Cauldron2D.Raster

  @doc "`raster` as PNG bytes."
  @spec png(Raster.t()) :: binary()
  def png(%FrenchCurve.Raster{width: width, height: height} = raster),
    do: Png.encode(width, height, Raster.to_rgba_binary(raster))
end
