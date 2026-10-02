defmodule Cauldron2D.Projection.GlyphsTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Projection.{Glyphs, Iso, Oblique}
  alias FrenchCurve.Raster

  @tile 8
  @size {160, 96}
  @step {16, 16}

  setup_all do
    Atlas.new(:glyphs_test, tile: @tile, void: {6, 7, 11})
    |> Atlas.put(:grass, Raster.new(@tile, @tile, background: {40, 160, 40, 255}), glyph: ", ")
    |> Atlas.put(:stone, Raster.new(@tile, @tile, background: {90, 90, 96, 255}), glyph: ". ")
    |> Atlas.put(:pillar, Raster.new(@tile, @tile, background: {160, 120, 80, 255}),
      height: 2,
      glyph: "||"
    )
    |> Atlas.put(:hero, Raster.new(@tile, @tile, background: {250, 250, 20, 255}), glyph: "@ ")
    |> Atlas.install()

    :ok
  end

  defp town({3, 6}), do: {:stone, [:pillar], nil}
  defp town({x, _y}) when x < 0, do: :void
  defp town({x, y}) when rem(x + y, 4) == 0, do: {:grass, [], nil}
  defp town(_position), do: {:stone, [], nil}

  defp opts(Iso, extra),
    do:
      Keyword.merge(
        [
          focus: {4.0, 6.0},
          cell: &town/1,
          size: @size,
          step: @step,
          facing: 0,
          facings: 4,
          tilt: 1.0
        ],
        extra
      )

  defp opts(Oblique, extra),
    do:
      Keyword.merge(
        [focus: {4.0, 6.0}, cell: &town/1, size: @size, step: @step, squash: 0.5],
        extra
      )

  defp text(grid), do: Enum.map_join(grid, "\n", fn row -> Enum.map_join(row, &elem(&1, 0)) end)

  for module <- [Iso, Oblique] do
    describe "#{inspect(module)} as glyphs" do
      test "the grid is the picture divided by the step" do
        grid = Glyphs.compose(:glyphs_test, unquote(module), opts(unquote(module), []))

        assert length(grid) == 6
        assert Enum.all?(grid, &(length(&1) == 10))
      end

      test "every slot carries a glyph and a colour" do
        grid = Glyphs.compose(:glyphs_test, unquote(module), opts(unquote(module), []))

        for row <- grid, {glyph, colour} <- row do
          assert String.length(glyph) == 2
          assert tuple_size(colour) == 3
        end
      end

      test "a slot shows the glyph of the cell the projection draws there" do
        settings = opts(unquote(module), [])
        {across, down} = @step
        grid = Glyphs.compose(:glyphs_test, unquote(module), settings)

        for row <- [0, 3, 5], column <- [0, 4, 9] do
          {wx, wy} =
            unquote(module).unproject(
              :glyphs_test,
              {(column + 0.5) * across, (row + 0.5) * down},
              settings
            )

          {glyph, _colour} = grid |> Enum.at(row) |> Enum.at(column)

          case town({floor(wx), floor(wy)}) do
            :void ->
              assert glyph == "  "

            {base, overlays, _tint} ->
              art = List.last([base | overlays])
              assert glyph == Atlas.entry(Atlas.fetch(:glyphs_test), art).glyph
          end
        end
      end

      test "a void cell is drawn as blank in the void colour" do
        settings = opts(unquote(module), focus: {-40.0, 6.0})
        grid = Glyphs.compose(:glyphs_test, unquote(module), settings)

        assert Enum.any?(List.flatten(grid), &(&1 == {"  ", {6, 7, 11}}))
      end

      test "a mover is drawn over the ground at its own slot" do
        plain = Glyphs.compose(:glyphs_test, unquote(module), opts(unquote(module), []))

        with_hero =
          Glyphs.compose(
            :glyphs_test,
            unquote(module),
            opts(unquote(module), movers: [{:hero, {4.0, 6.0}}])
          )

        refute text(plain) =~ "@"
        assert text(with_hero) =~ "@"
      end

      test "a mover outside the grid is left out" do
        grid =
          Glyphs.compose(
            :glyphs_test,
            unquote(module),
            opts(unquote(module), movers: [{:hero, {900.0, 900.0}}])
          )

        refute text(grid) =~ "@"
      end

      test "a label is written from its own slot rightwards" do
        grid =
          Glyphs.compose(
            :glyphs_test,
            unquote(module),
            opts(unquote(module), labels: [{"hi", {4.0, 6.0}, {255, 255, 255}}])
          )

        assert text(grid) =~ "hi"
      end
    end
  end

  describe "volumes" do
    test "a volume tints the slots it covers and leaves the glyphs alone" do
      volume = %{at: {4.0, 6.0}, shape: {:sphere, 2.0, 0.0}, colour: {255, 0, 0}, strength: 0.8}
      plain = Glyphs.compose(:glyphs_test, Iso, opts(Iso, []))
      tinted = Glyphs.compose(:glyphs_test, Iso, opts(Iso, volumes: [volume]))

      assert Enum.map(plain, fn row -> Enum.map(row, &elem(&1, 0)) end) ==
               Enum.map(tinted, fn row -> Enum.map(row, &elem(&1, 0)) end)

      changed =
        Enum.count(Enum.zip([List.flatten(plain), List.flatten(tinted)]), fn {{_g, was},
                                                                              {_h, now}} ->
          was != now
        end)

      assert changed > 0

      assert changed < length(List.flatten(plain)),
             "a sphere of two tiles should not reach every slot of the grid"
    end

    test "no volume leaves every colour as it was" do
      plain = Glyphs.compose(:glyphs_test, Iso, opts(Iso, []))

      assert Glyphs.compose(:glyphs_test, Iso, opts(Iso, volumes: [])) == plain
    end
  end

  describe "turning and zooming" do
    test "a different facing draws a different grid" do
      straight = Glyphs.compose(:glyphs_test, Iso, opts(Iso, facing: 0))
      turned = Glyphs.compose(:glyphs_test, Iso, opts(Iso, facing: 1))

      refute text(straight) == text(turned)
    end

    test "a smaller step shows more of the world in the same grid" do
      near = Glyphs.compose(:glyphs_test, Iso, opts(Iso, step: {8, 8}, size: {80, 48}))
      far = Glyphs.compose(:glyphs_test, Iso, opts(Iso, step: {32, 32}, size: {320, 192}))

      assert length(near) == length(far)
      refute text(near) == text(far)
    end

    test "a tilt draws a different grid" do
      upright = Glyphs.compose(:glyphs_test, Iso, opts(Iso, tilt: 1.0))
      flatter = Glyphs.compose(:glyphs_test, Iso, opts(Iso, tilt: 0.5))

      refute text(upright) == text(flatter)
    end

    test "the oblique grid is fixed unless four facings are asked for" do
      fixed = Glyphs.compose(:glyphs_test, Oblique, opts(Oblique, []))

      assert text(Glyphs.compose(:glyphs_test, Oblique, opts(Oblique, facing: 2))) == text(fixed)

      turned = Glyphs.compose(:glyphs_test, Oblique, opts(Oblique, facing: 1, facings: 4))

      refute text(turned) == text(fixed)
    end
  end
end
