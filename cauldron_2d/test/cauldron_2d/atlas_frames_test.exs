defmodule Cauldron2D.AtlasFramesTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.{Atlas, Surface}
  alias FrenchCurve.Raster

  @tile 4

  defp solid(colour), do: Raster.new(@tile, @tile, background: colour)
  defp name(suffix), do: :"atlas_frames_#{suffix}"

  defp animated(suffix) do
    name(suffix)
    |> Atlas.new(tile: @tile)
    |> Atlas.put(
      :torch,
      [solid({255, 0, 0, 255}), solid({0, 255, 0, 255}), solid({0, 0, 255, 255})],
      fps: 10,
      glyph: "i "
    )
    |> Atlas.put(:floor, solid({9, 9, 9, 255}))
  end

  test "an art put as a list of rasters has frames and a rate; a single raster has one frame" do
    atlas = animated(:frames)
    torch = Atlas.entry(atlas, :torch)
    assert length(torch.frames) == 3
    assert torch.fps == 10
    assert torch.sprite == hd(torch.frames)
    assert Atlas.entry(atlas, :floor).frames == [Atlas.entry(atlas, :floor).sprite]
    assert Atlas.animated?(atlas, :torch)
    refute Atlas.animated?(atlas, :floor)
  end

  test "the frame at a time cycles at the rate" do
    atlas = animated(:at)
    assert Atlas.frame_at(atlas, :torch, 0) == Enum.at(Atlas.entry(atlas, :torch).frames, 0)
    assert Atlas.frame_at(atlas, :torch, 100) == Enum.at(Atlas.entry(atlas, :torch).frames, 1)
    assert Atlas.frame_at(atlas, :torch, 250) == Enum.at(Atlas.entry(atlas, :torch).frames, 2)
    assert Atlas.frame_at(atlas, :torch, 300) == Enum.at(Atlas.entry(atlas, :torch).frames, 0)
    assert Atlas.frame_index(atlas, :torch, 100) == 1
    assert Atlas.frame_index(atlas, :floor, 100_000) == 0
  end

  test "frames of the wrong size are refused like any other raster" do
    assert_raise ArgumentError, fn ->
      Atlas.new(name(:bad), tile: @tile)
      |> Atlas.put(:torch, [solid({0, 0, 0, 255}), Raster.new(2, 2)])
    end
  end

  test "a surface composed at a time draws that frame, cached per frame" do
    Atlas.install(animated(:surface))
    red = Surface.compose(name(:surface), [[{:torch, [], nil}]], [], at: 0)
    green = Surface.compose(name(:surface), [[{:torch, [], nil}]], [], at: 100)
    assert binary_part(red.rgba, 0, 4) == <<255, 0, 0, 255>>
    assert binary_part(green.rgba, 0, 4) == <<0, 255, 0, 255>>
    assert Surface.compose(name(:surface), [[{:torch, [], nil}]], [], at: 300).rgba == red.rgba

    over = Surface.compose(name(:surface), [[{:floor, [:torch], nil}]], [], at: 200)
    assert binary_part(over.rgba, 0, 4) == <<0, 0, 255, 255>>

    mover = Surface.compose(name(:surface), [[{:floor, [], nil}]], [{:torch, {0, 0}}], at: 100)
    assert binary_part(mover.rgba, 0, 4) == <<0, 255, 0, 255>>
  end

  test "the glyph view is the same whatever the time" do
    atlas = animated(:glyphs)

    camera =
      Cauldron2D.Camera.view(focus: {0, 0}, size: {1, 1}, cell: fn _ -> {:torch, [], nil} end)

    assert Cauldron2D.Camera.glyphs(atlas, camera) == [[{"i ", {255, 0, 255}}]]
  end
end
