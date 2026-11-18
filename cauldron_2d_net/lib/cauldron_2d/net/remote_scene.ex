defmodule Cauldron2D.Net.RemoteScene do
  @moduledoc """
  The scene of a remote world's view (`Cauldron.Net.Link.World` with
  `Cauldron2D.Net.Drawer`) for a 2D game's client: its focus and subject from the
  server's status, and a `:picture` — the server's picture, or the scene drawn here with
  the server's overlay over it — at whatever size the client asks, so a terminal shows
  what a browser shows. Before anything has arrived, and once the connection is closed,
  the picture is black.

      def scene(%{remote: _} = view), do: Cauldron2D.Net.RemoteScene.scene(view)
  """

  alias Cauldron2D.{Draw, Surface}
  alias Cauldron2D.Raster

  @doc "The scene of a remote view."
  @spec scene(map()) :: Cauldron.Client.Game.scene()
  def scene(%{remote: remote}) do
    status = Map.get(remote, :status) || %{}

    %{
      focus: Map.get(status, :focus) || {0.0, 0.0},
      cell: fn _ -> :void end,
      movers: [],
      picture: fn size, _aspect -> picture(remote, size) end
    }
    |> subject(status)
  end

  defp subject(scene, %{subject: subject}) when subject != nil,
    do: Map.put(scene, :subject, subject)

  defp subject(scene, _status), do: scene

  defp picture(%{drawn: %Draw{} = view} = remote, size) do
    tile = Cauldron2D.Atlas.fetch(view.atlas).tile
    pane = {max(1, div(elem(size, 0), tile)), max(1, div(elem(size, 1), tile))}

    case Draw.picture(view, pane) do
      nil -> blank(size)
      raster -> raster |> overlaid(Map.get(remote, :overlay)) |> fitted(size)
    end
  end

  defp picture(%{picture: %FrenchCurve.Raster{} = raster}, size), do: fitted(raster, size)
  defp picture(_remote, size), do: blank(size)

  defp overlaid(raster, %FrenchCurve.Raster{width: width, height: height} = overlay)
       when raster.width == width and raster.height == height,
       do: Surface.stack(raster, overlay)

  defp overlaid(raster, _overlay), do: raster

  defp blank({width, height}),
    do: Raster.new(max(1, width), max(1, height), background: {0, 0, 0, 255})

  defp fitted(%FrenchCurve.Raster{width: width, height: height} = raster, {width, height}),
    do: raster

  defp fitted(%FrenchCurve.Raster{} = raster, {width, height}) do
    source = Raster.to_rgba_binary(raster)

    rows =
      for y <- 0..(height - 1)//1 do
        sy = div(y * raster.height, height)

        for x <- 0..(width - 1)//1,
            into: <<>>,
            do: binary_part(source, (sy * raster.width + div(x * raster.width, width)) * 4, 4)
      end

    Raster.from_rgba(width, height, IO.iodata_to_binary(rows))
  end
end
