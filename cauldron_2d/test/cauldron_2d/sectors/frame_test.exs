defmodule Cauldron2D.Sectors.FrameTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Sectors.{Frame, Pictures}

  @moduletag :sectors

  @width 48
  @height 36

  setup_all do
    rng = :rand.seed_s(:exsss, {7, 11, 13})
    {wall, rng} = bytes(rng, 16 * 24)
    {sprite, rng} = bytes(rng, 10 * 12)
    {mask, rng} = bytes(rng, 10 * 12)
    {flat, rng} = bytes(rng, 8 * 8)
    {tables, _rng} = bytes(rng, 256 * 6)

    pictures = [
      {:wall, %{width: 16, height: 24, pixels: wall}},
      {:sprite,
       %{
         width: 10,
         height: 12,
         pixels: sprite,
         mask: for(<<m <- mask>>, into: <<>>, do: <<rem(m, 2)>>)
       }},
      {:flat, %{width: 8, height: 8, pixels: flat}}
    ]

    {:ok, pictures: pictures, tables: tables}
  end

  @tag :native
  test "C and Elixir draw the same picture", %{pictures: pictures, tables: tables} do
    if Frame.available?() do
      native = draw(Pictures.new(pictures, tables), [])
      elixir = draw(Pictures.new(pictures, tables, native: false), native: false)

      assert Frame.pixels(native) == Frame.pixels(elixir)
      assert native |> Frame.pixels() |> :binary.bin_to_list() |> Enum.uniq() |> length() > 20
    end
  end

  defp draw(pictures, opts) do
    walls =
      for x <- 0..(@width - 1) do
        Frame.column(
          x,
          {4 - rem(x, 7), 30 + rem(x, 5)},
          0,
          {x * 3 - 20, -3.25 + x * 0.1, 0.83},
          rem(x, 6)
        )
      end

    sprites =
      for x <- 10..30 do
        Frame.column(x, {2, 40}, 1, {x - 15, -4.5, 0.61}, 2, masked: true)
      end

    blur = for x <- 32..40, do: Frame.column(x, {5, 25}, 1, {0, 0.0, 1.0}, 5, shimmer: true)

    view = %{
      x: 12.3,
      y: -7.6,
      angle: 0.7,
      center_x: 24.0,
      center_y: 18.0,
      focal_x: 24.0,
      focal_y: 28.8
    }

    floor = Map.merge(view, %{x1: 3, x2: 44, picture: 2, height: -41.0, start: 9, fade: 300.0})

    sky =
      Map.merge(view, %{
        x1: 0,
        x2: 20,
        picture: 0,
        height: 0.0,
        sky: true,
        sky_columns: 162.97,
        sky_mid: 12.0,
        sky_step: 0.9
      })

    @width
    |> Frame.new(@height, opts)
    |> Frame.fill(3)
    |> Frame.columns(pictures, walls)
    |> Frame.plane(pictures, floor, Enum.map(3..44, &(19 + rem(&1, 4))), List.duplicate(35, 42))
    |> Frame.plane(pictures, sky, List.duplicate(0, 21), Enum.map(0..20, &(6 + rem(&1, 3))))
    |> Frame.columns(pictures, sprites)
    |> Frame.columns(pictures, blur)
    |> Frame.lines([{-5, 3, 60, 33, 250}, {40, 0, 2, 35, 251}])
  end

  defp bytes(rng, count) do
    {list, rng} =
      Enum.map_reduce(1..count, rng, fn _index, state ->
        {value, state} = :rand.uniform_s(256, state)
        {value - 1, state}
      end)

    {:binary.list_to_bin(list), rng}
  end
end
