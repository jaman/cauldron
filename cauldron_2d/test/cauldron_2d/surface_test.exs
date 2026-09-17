defmodule Cauldron2D.SurfaceTest do
  @moduledoc """
  The compositor and the atlas it draws from, against a small hand-built atlas.

  Assertions are on what a caller can observe — bytes in a raster, glyphs and colours — not on
  how the cache is arranged.
  """

  use ExUnit.Case, async: false

  alias Cauldron2D.{Atlas, Camera, Surface}
  alias FrenchCurve.Backend.Kitty
  alias FrenchCurve.{Draw, Raster}

  @tile 8

  setup_all do
    opaque = fn color -> Raster.new(@tile, @tile, background: color) end

    Atlas.new(:surface_test, tile: @tile, void: {6, 7, 11})
    |> Atlas.put(:floor, opaque.({40, 45, 62, 255}), glyph: "· ", color: {60, 66, 88})
    |> Atlas.put(:wall, opaque.({88, 96, 124, 255}), glyph: "▓▓", color: {90, 98, 128})
    |> Atlas.put(:twin, opaque.({88, 96, 124, 255}), glyph: "▓▓", color: {90, 98, 128})
    |> Atlas.put(:player, player(), glyph: "@ ", color: {245, 235, 200})
    |> Atlas.put(:item, item(), glyph: "◈ ", color: {90, 215, 235})
    |> Atlas.put(:mist, opaque.({0, 0, 200, 128}), glyph: "~ ", color: {0, 0, 200})
    |> Atlas.put(:veil, opaque.({200, 0, 0, 128}), glyph: "^ ", color: {200, 0, 0})
    |> Atlas.tint(:dim, fn {r, g, b, a} -> {div(r, 3), div(g, 3), div(b, 3), a} end)
    |> Atlas.install()

    :ok
  end

  defp player do
    Raster.new(@tile, @tile) |> Draw.fill_rect({2, 2}, {5, 5}, {245, 232, 200, 255})
  end

  defp item do
    Raster.new(@tile, @tile) |> Draw.fill_rect({3, 3}, {4, 4}, {90, 215, 235, 255})
  end

  describe "the atlas" do
    test "keeps art, glyph and colour together so the two renderers cannot drift" do
      entry = Atlas.entry(Atlas.fetch(:surface_test), :floor)

      assert entry.glyph == "· "
      assert entry.color == {60, 66, 88}
      assert byte_size(entry.sprite.raster.rgba) == @tile * @tile * 4
    end

    test "refuses a tile that is not the atlas's size" do
      atlas = Atlas.new(:wrong_size, tile: @tile)

      assert_raise ArgumentError, ~r/One tile size per atlas/, fn ->
        Atlas.put(atlas, :big, Raster.new(@tile * 2, @tile))
      end
    end

    test "gives identical art the same id, which is what makes the cache dedupe" do
      atlas = Atlas.fetch(:surface_test)

      assert Atlas.entry(atlas, :wall).sprite.id == Atlas.entry(atlas, :twin).sprite.id
      assert Atlas.entry(atlas, :wall).sprite.id != Atlas.entry(atlas, :floor).sprite.id
    end

    test "says which art is missing rather than failing obscurely" do
      assert_raise ArgumentError, ~r/no art :nonexistent/, fn ->
        Atlas.entry(Atlas.fetch(:surface_test), :nonexistent)
      end
    end
  end

  describe "composing a frame" do
    test "magnifies a raster by repeating each pixel, so a picture twice as large is the same picture" do
      raster =
        Raster.new(2, 2)
        |> Raster.put_pixel(0, 0, {255, 0, 0, 255})
        |> Raster.put_pixel(1, 1, {0, 0, 255, 255})

      twice = Surface.magnify(raster, 2)
      assert Raster.dimensions(twice) == {4, 4}
      assert Raster.get_pixel(twice, 1, 1) == {255, 0, 0, 255}
      assert Raster.get_pixel(twice, 2, 0) == Raster.get_pixel(raster, 1, 0)
      assert Raster.get_pixel(twice, 3, 3) == {0, 0, 255, 255}
      assert Surface.magnify(raster, 1) == raster
    end

    test "produces a raster of exactly the viewport's pixels" do
      cells = List.duplicate(List.duplicate({:floor, [], nil}, 5), 3)
      raster = Surface.compose(:surface_test, cells)

      assert raster.width == 5 * @tile
      assert raster.height == 3 * @tile
      assert byte_size(raster.rgba) == raster.width * raster.height * 4
    end

    test "puts each tile where the caller said it was" do
      cells = [
        [{:floor, [], nil}, {:wall, [], nil}],
        [{:wall, [], nil}, {:floor, [], nil}]
      ]

      raster = Surface.compose(:surface_test, cells)

      assert pixel(raster, 2, 2) == art_pixel(:floor, 2, 2)
      assert pixel(raster, @tile + 2, 2) == art_pixel(:wall, 2, 2)
      assert pixel(raster, 2, @tile + 2) == art_pixel(:wall, 2, 2)
    end

    test "composites overlays over terrain rather than replacing it" do
      standing = Surface.tile_binary(:surface_test, {:floor, [:player], nil})
      floor = Surface.tile_binary(:surface_test, {:floor, [], nil})

      assert byte_size(standing) == byte_size(floor)
      assert standing != floor
      assert binary_part(standing, 0, 4) == binary_part(floor, 0, 4)
    end

    test "paints overlays in order, last on top" do
      item_then_player = Surface.tile_binary(:surface_test, {:floor, [:item, :player], nil})
      player_then_item = Surface.tile_binary(:surface_test, {:floor, [:player, :item], nil})

      assert item_then_player != player_then_item
    end

    test "a tint darkens, and void carries nothing at all" do
      lit = Surface.tile_binary(:surface_test, {:floor, [], nil})
      dim = Surface.tile_binary(:surface_test, {:floor, [], :dim})
      void = Surface.tile_binary(:surface_test, :void)

      assert brightness(dim) < brightness(lit)
      assert void == :binary.copy(<<6, 7, 11, 255>>, @tile * @tile)
    end

    test "an empty grid still yields a raster rather than failing, of one tile" do
      raster = Surface.compose(:surface_test, [])

      assert %Raster{} = raster
      assert {raster.width, raster.height} == {@tile, @tile}
    end
  end

  describe "compositing something see-through onto something see-through" do
    defp alpha_of(tile), do: binary_part(tile, 3, 1)

    test "the result is more opaque than either, not as opaque as the more opaque" do
      tile = Surface.tile_binary(:surface_test, {:mist, [:veil], nil})

      assert alpha_of(tile) == <<192>>
    end

    test "both layers show through, in proportion to how much covers how much" do
      <<r, _g, b, _a, _rest::binary>> = Surface.tile_binary(:surface_test, {:mist, [:veil], nil})

      assert r > 0, "the half-transparent red on top should show"
      assert b > 0, "the half-transparent blue beneath should show through it"
      assert r > b, "what is on top should dominate"
    end

    test "over an opaque base it is the plain weighted mix it always was" do
      <<r, _g, _b, a, _rest::binary>> = Surface.tile_binary(:surface_test, {:floor, [:veil], nil})

      assert a == 255, "an opaque base stays opaque"
      assert r == round(200 * (128 / 255) + 40 * (1 - 128 / 255))
    end

    test "a fully transparent overlay leaves the base exactly as it was" do
      alone = Surface.tile_binary(:surface_test, {:mist, [], nil})
      covered = Surface.tile_binary(:surface_test, {:mist, [:player], nil})

      assert binary_part(alone, 0, 4) == binary_part(covered, 0, 4)
    end

    test "a fully opaque overlay replaces the base entirely" do
      tile = Surface.tile_binary(:surface_test, {:mist, [:wall], nil})

      assert binary_part(tile, 0, 4) == <<88, 96, 124, 255>>
    end

    test "a composed frame is a raster french_curve can serialise" do
      raster = Surface.compose(:surface_test, [[{:floor, [:player], nil}, {:wall, [], :dim}]])

      assert byte_size(Kitty.transmit(raster, 1)) > 0
      assert byte_size(Kitty.transmit(raster, 1, compress: true)) > 0
    end
  end

  describe "glyphs" do
    test "fall back to the topmost overlay, then terrain" do
      camera = %Camera{
        origin: {0, 0},
        columns: 3,
        rows: 1,
        cells: [[{:floor, [], nil}, {:floor, [:player], nil}, :void]]
      }

      assert [[{"· ", _}, {"@ ", _}, {"  ", {6, 7, 11}}]] = Camera.glyphs(:surface_test, camera)
    end

    test "are tinted by the same function as the pixels" do
      camera = %Camera{origin: {0, 0}, columns: 1, rows: 1, cells: [[{:floor, [], :dim}]]}
      [[{_glyph, dimmed}]] = Camera.glyphs(:surface_test, camera)

      assert dimmed == {20, 22, 29}
    end
  end

  defp pixel(raster, x, y), do: binary_part(raster.rgba, (y * raster.width + x) * 4, 4)

  defp art_pixel(art, x, y) do
    sprite = Atlas.entry(Atlas.fetch(:surface_test), art).sprite
    binary_part(sprite.raster.rgba, (y * sprite.width + x) * 4, 4)
  end

  defp brightness(tile) do
    for(<<r, g, b, _a <- tile>>, do: r + g + b) |> Enum.sum()
  end

  describe "composing at a reduced scale" do
    test "halves the raster and keeps every tile and mover in place" do
      cells = [
        [{:floor, [], nil}, {:wall, [], nil}],
        [{:wall, [], nil}, {:floor, [], nil}]
      ]

      raster = Surface.compose(:surface_test, cells, [{:player, {@tile, 0}}], scale: 2)

      assert raster.width == @tile
      assert raster.height == @tile
      assert pixel(raster, 1, 1) == art_pixel(:floor, 2, 2)
      assert pixel(raster, 1, @tile - 2) == art_pixel(:wall, 2, 2)
      assert pixel(raster, div(@tile, 2) + 1, 1) == art_pixel(:player, 2, 2)
      assert pixel(raster, div(@tile, 2), 0) == art_pixel(:wall, 0, 0)
    end

    test "is the same picture as the full scale, sampled" do
      cells = [[{:floor, [], nil}, {:wall, [:item], nil}]]
      full = Surface.compose(:surface_test, cells, [{:player, {3, 2}}])
      half = Surface.compose(:surface_test, cells, [{:player, {3, 2}}], scale: 2)

      for y <- 0..(half.height - 1), x <- 0..(half.width - 1) do
        assert pixel(half, x, y) == pixel(full, x * 2, y * 2), "at #{x},#{y}"
      end
    end
  end
end
