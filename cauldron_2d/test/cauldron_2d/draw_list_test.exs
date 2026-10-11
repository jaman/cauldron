defmodule Cauldron2D.DrawListTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.DrawList
  alias FrenchCurve.Raster

  defp solid(colour), do: Raster.from_rgba(2, 2, :binary.copy(<<colour::binary-4>>, 4))

  defp pictures(:red), do: solid(<<255, 0, 0, 255>>)
  defp pictures(:blue), do: solid(<<0, 0, 255, 255>>)
  defp pictures(_), do: nil

  test "the item with less depth is drawn over the one with more, whatever the list order" do
    items = [
      %{picture: :red, position: {1, 1}, depth: -5},
      %{picture: :blue, position: {1, 1}, depth: 10},
      %{picture: :missing, position: {0, 0}}
    ]

    raster = DrawList.render(items, {4, 4}, &pictures/1)
    assert Raster.crop(raster, {1, 1}, {1, 1}) |> Raster.to_rgba_binary() == <<255, 0, 0, 255>>
  end

  test "the view and zoom place world pixels on the raster" do
    items = [%{picture: :red, position: {11, 10}}]
    raster = DrawList.render(items, {8, 8}, &pictures/1, view: {10, 10}, zoom: 2)

    red =
      for {<<255, 0, 0, 255>>, index} <-
            Enum.with_index(for <<p::binary-4 <- Raster.to_rgba_binary(raster)>>, do: p),
          do: {rem(index, 8), div(index, 8)}

    assert red == for(row <- 0..3, column <- 2..5, do: {column, row})
  end
end
