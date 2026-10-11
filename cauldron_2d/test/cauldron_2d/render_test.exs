defmodule Cauldron2D.RenderTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.{Blend, DrawList, Render}
  alias FrenchCurve.Raster

  defp picture(width, height, seed) do
    for index <- 0..(width * height - 1),
        into: <<>>,
        do: <<rem(index * seed, 256), rem(index * 7 + seed, 256), 90, rem(index * 31, 256)>>
  end

  defp operations do
    [
      {:raster, {6, 4, picture(6, 4, 3)}, {2, 1}},
      {:sprite, {5, 3, picture(5, 3, 5)},
       %{position: {9.5, 7.25}, origin: {2, 1}, scale: {2, 3}, angle: 30}},
      {:sprite, {5, 3, picture(5, 3, 9)},
       %{position: {12, 3}, scale: {-1, 1}, angle: 90, blend: {255, 128, 0}, alpha: 0.5}},
      {:raster, {6, 4, picture(6, 4, 11)}, {-3, 10}}
    ]
  end

  defp both(size, operations, opts) do
    native = Render.render(size, operations, opts)
    elixir = Render.render(size, operations, [native: false] ++ opts)
    assert Raster.to_rgba_binary(native) == Raster.to_rgba_binary(elixir)
    native
  end

  setup do
    assert Blend.available?(), "the C library is not loaded; C cannot be compared with Elixir"
    :ok
  end

  test "C and Elixir draw the same frame, and the number of bands never changes it" do
    one = both({20, 13}, operations(), bands: 1, background: {10, 20, 30, 255})
    refute Raster.to_rgba_binary(one) == :binary.copy(<<10, 20, 30, 255>>, 20 * 13)

    for bands <- [2, 3, 7, 13, 40] do
      assert both({20, 13}, operations(), bands: bands, background: {10, 20, 30, 255}) == one
    end
  end

  test ":rgb gives three bytes a pixel" do
    assert Render.render({2, 1}, [], background: {1, 2, 3, 4}, format: :rgb) ==
             <<1, 2, 3, 1, 2, 3>>
  end

  test "a picture background is kept byte for byte, see-through pixels included" do
    backdrop = <<12, 34, 56, 0, 1, 2, 3, 128, 200, 100, 50, 255, 9, 9, 9, 0>>
    frame = both({2, 2}, [], background: {2, 2, backdrop}, bands: 2)
    assert Raster.to_rgba_binary(frame) == backdrop
  end

  test "pictures and backgrounds of the wrong size, and malformed colours, are refused" do
    assert_raise ArgumentError, fn ->
      Render.render({2, 2}, [], background: {3, 2, <<0::192>>})
    end

    assert_raise ArgumentError, fn -> Render.render({2, 2}, [], background: {1, 2, 3}) end
    assert_raise ArgumentError, fn -> Render.render({2, 2}, [], background: {1, 2, 3, 300}) end

    for picture <- [{2, 2, <<0::96>>}, {-1, -1, <<0::32>>}, {0, 5, <<>>}, :not_a_picture] do
      assert_raise ArgumentError, fn -> Render.render({4, 4}, [{:raster, picture, {0, 0}}]) end

      assert_raise ArgumentError, fn ->
        Render.render({4, 4}, [{:raster, picture, {0, 0}}], native: false)
      end
    end
  end

  test "a band call with negative or overflowing sizes is refused by both paths" do
    transform = Blend.transform(%{position: {0, 0}})

    for {width, height, rgba} <- [{-1, -1, <<0::32>>}, {-2_147_483_648, -2_147_483_648, <<>>}] do
      item = [{rgba, width, height, transform}]
      assert_raise ArgumentError, fn -> Blend.render_band(4, 0, 4, <<0::32>>, item) end
      assert_raise ArgumentError, fn -> Blend.elixir_render_band(4, 0, 4, <<0::32>>, item) end
    end

    assert_raise ArgumentError, fn -> Blend.render_band(4, 3, 1, <<0::32>>, []) end
    assert_raise ArgumentError, fn -> Blend.elixir_render_band(-4, 0, 1, <<0::32>>, []) end
  end

  test "huge and non-finite placements draw nothing and crash nothing" do
    blank = {16, 8, :binary.copy(<<0, 0, 0, 255>>, 128)}
    square = {2, 2, :binary.copy(<<255, 0, 0, 255>>, 4)}

    for placement <- [
          %{position: {3.0e9, 0}},
          %{position: {0, 0}, origin: {-3.0e9, 0}},
          %{position: {-3.0e9, -3.0e9}, scale: {-1.0e300, -1.0e300}}
        ] do
      frame = both({16, 8}, [{:sprite, square, placement}], background: blank)
      assert Raster.to_rgba_binary(frame) == elem(blank, 2)
    end

    {_width, _height, rgba} = square
    <<head::binary-16, _rest::binary>> = Blend.transform(%{position: {1, 1}})

    for bad <- [<<0, 0, 0, 0, 0, 0, 248, 127>>, <<0, 0, 0, 0, 0, 0, 240, 127>>] do
      transform =
        head <>
          :binary.copy(bad, 2) <> :binary.copy(<<0, 0, 0, 0, 0, 0, 240, 63>>, 8) <> <<0::64>>

      item = [{rgba, 2, 2, transform}]
      background = elem(blank, 2)
      assert Blend.render_band(16, 0, 8, background, item) == background
      assert Blend.elixir_render_band(16, 0, 8, background, item) == background
    end
  end

  test "alpha and blend outside their ranges are held to them, the same in C and Elixir" do
    square = {2, 2, :binary.copy(<<200, 100, 50, 255>>, 4)}
    base = {4, 4, :binary.copy(<<10, 10, 10, 255>>, 16)}

    over =
      both({4, 4}, [{:sprite, square, %{position: {1, 1}, alpha: 2.0, blend: {400, -5, 255}}}],
        background: base
      )

    full =
      both({4, 4}, [{:sprite, square, %{position: {1, 1}, alpha: 1.0, blend: {255, 0, 255}}}],
        background: base
      )

    assert over == full

    under = both({4, 4}, [{:sprite, square, %{position: {1, 1}, alpha: -1.0}}], background: base)
    assert Raster.to_rgba_binary(under) == elem(base, 2)
  end

  test "a draw list keeps a picture whose origin lies outside it but which lands in the frame" do
    red = Raster.from_rgba(2, 2, :binary.copy(<<255, 0, 0, 255>>, 4))
    items = [%{picture: :red, position: {-50, 2}, origin: {-60, 0}}]
    raster = DrawList.render(items, {32, 8}, fn :red -> red end)

    reds =
      for {<<255, 0, 0, 255>>, index} <-
            Enum.with_index(for <<p::binary-4 <- Raster.to_rgba_binary(raster)>>, do: p),
          do: {rem(index, 32), div(index, 32)}

    assert reds == [{10, 2}, {11, 2}, {10, 3}, {11, 3}]
  end

  test "GameMaker blending applies its factors to the alpha channel too, the same in C and Elixir" do
    clear = :binary.copy(<<0, 0, 0, 0>>, 4)
    white = :binary.copy(<<255, 255, 255, 255>>, 4)
    half = fn mode -> %{position: {0, 0}, scale: {2, 2}, alpha: 0.5, mode: {:gamemaker, mode}} end

    for native <- [true, false] do
      assert Blend.draw(clear, {2, 2}, white, {2, 2}, half.(:over), native: native) ==
               :binary.copy(<<128, 128, 128, 64>>, 4)

      assert Blend.draw(clear, {2, 2}, white, {2, 2}, half.(:add), native: native) ==
               :binary.copy(<<128, 128, 128, 64>>, 4)

      assert Blend.draw(white, {2, 2}, white, {2, 2}, half.(:subtract), native: native) ==
               :binary.copy(<<0, 0, 0, 128>>, 4)
    end
  end

  test "subtractive drawing scales the canvas by one less colour times alpha, keeping its alpha, the same in C and Elixir" do
    base = :binary.copy(<<200, 100, 50, 128>>, 4)
    picture = :binary.copy(<<255, 0, 51, 255>>, 4)
    half = %{position: {0, 0}, scale: {2, 2}, alpha: 0.5, mode: :subtract}

    for native <- [true, false] do
      assert Blend.draw(base, {2, 2}, picture, {2, 2}, half, native: native) ==
               :binary.copy(<<100, 100, 45, 128>>, 4)
    end
  end

  test "additive drawing adds colour times alpha to the canvas, held at 255, the same in C and Elixir" do
    base = :binary.copy(<<10, 10, 10, 255>>, 4)
    picture = :binary.copy(<<200, 100, 50, 255>>, 4)
    half = %{position: {0, 0}, scale: {2, 2}, alpha: 0.5, mode: :add}
    full = %{half | alpha: 1.0}

    for native <- [true, false] do
      assert Blend.draw(base, {2, 2}, picture, {2, 2}, half, native: native) ==
               :binary.copy(<<110, 60, 35, 255>>, 4)

      assert Blend.draw(:binary.copy(<<100, 200, 250, 255>>, 4), {2, 2}, picture, {2, 2}, full,
               native: native
             ) ==
               :binary.copy(<<255, 255, 255, 255>>, 4)
    end
  end
end
