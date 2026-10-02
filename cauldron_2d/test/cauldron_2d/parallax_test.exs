defmodule Cauldron2D.ParallaxTest do
  @moduledoc """
  Parallax layers: where a layer sits for a given focus, what reaches the raster, and how
  often a layer is redrawn.

  Assertions are on pixels a caller can read back and on how many times a layer's cell
  function was asked, not on how the cache is arranged.
  """

  use ExUnit.Case, async: false

  alias Cauldron2D.{Atlas, Blend, Parallax, Surface}
  alias Cauldron2D.Parallax.{Bands, Layer, Panorama, Scatter, Strip}
  alias FrenchCurve.Raster

  @tile 4
  @atlas :parallax_test
  @void {9, 9, 9}

  setup_all do
    solid = fn colour -> Raster.new(@tile, @tile, background: colour) end

    Atlas.new(@atlas, tile: @tile, void: @void)
    |> Atlas.put(:red, solid.({255, 0, 0, 255}), glyph: "r ", color: {255, 0, 0})
    |> Atlas.put(:green, solid.({0, 255, 0, 255}), glyph: "g ", color: {0, 255, 0})
    |> Atlas.put(:blue, solid.({0, 0, 255, 255}), glyph: "b ", color: {0, 0, 255})
    |> Atlas.put(:wide, Raster.new(2 * @tile, @tile, background: {0, 0, 255, 255}),
      glyph: "w ",
      color: {0, 0, 255}
    )
    |> Atlas.install()

    :ok
  end

  setup do
    Parallax.forget(@atlas)
    :ok
  end

  describe "Layer.focus/3" do
    test "a factor of 1 follows the world and a factor of 0 stays at the origin" do
      follows = Parallax.layer(name: :follows, cell: &void/1, factor: 1.0)
      pinned = Parallax.layer(name: :pinned, cell: &void/1, factor: 0.0)

      assert Layer.focus(follows, {20.0, -3.0}, 0) == {20.0, -3.0}
      assert Layer.focus(pinned, {20.0, -3.0}, 0) == {0.0, 0.0}
    end

    test "the factor applies to the distance from the layer's own origin" do
      layer = Parallax.layer(name: :offset, cell: &void/1, factor: 0.5, origin: {10.0, 0.0})

      assert Layer.focus(layer, {20.0, 0.0}, 0) == {15.0, 0.0}
      assert Layer.focus(layer, {10.0, 0.0}, 0) == {10.0, 0.0}
    end

    test "each axis takes its own factor" do
      layer = Parallax.layer(name: :axes, cell: &void/1, factor: {0.25, 0.75})

      assert Layer.focus(layer, {8.0, 8.0}, 0) == {2.0, 6.0}
    end

    test "drift moves the layer on its own, in tiles a second" do
      layer = Parallax.layer(name: :drifts, cell: &void/1, factor: 0.0, drift: {4.0, -2.0})

      assert Layer.focus(layer, {0.0, 0.0}, 0) == {0.0, 0.0}
      assert Layer.focus(layer, {0.0, 0.0}, 250) == {1.0, -0.5}
      assert Layer.focus(layer, {0.0, 0.0}, 1000) == {4.0, -2.0}
    end

    test "a number is taken as the same factor on both axes" do
      assert Parallax.layer(name: :both, cell: &void/1, factor: 0.5).factor == {0.5, 0.5}
    end
  end

  describe "compose/3" do
    test "a layer's picture shifts by its factor times the camera's distance" do
      assert reds(stripe(1.0), 0.0) == [0, 1, 2, 3, 16, 17, 18, 19]
      assert reds(stripe(1.0), 1.0) == [12, 13, 14, 15, 28, 29, 30, 31]
      assert reds(stripe(0.5), 1.0) == [0, 1, 14, 15, 16, 17, 30, 31]
      assert reds(stripe(0.0), 1.0) == reds(stripe(1.0), 0.0)
    end

    test "drift shifts a pinned layer the same way the focus would" do
      drifting =
        Parallax.layer(
          name: :drifting,
          cell: Parallax.strip(stripe_rows()),
          factor: 0.0,
          drift: {4.0, 0.0},
          void: :opaque,
          cache: false
        )

      assert reds(drifting, 0.0, 250) == reds(stripe(1.0), 1.0)
    end

    test "a transparent void lets the layer behind show through" do
      pixels = two_layers(:transparent)

      assert Enum.at(pixels, 0) == <<255, 0, 0, 255>>
      assert Enum.at(pixels, 4) == <<0, 255, 0, 255>>
    end

    test "an opaque void hides the layer behind" do
      {r, g, b} = @void
      pixels = two_layers(:opaque)

      assert Enum.at(pixels, 0) == <<255, 0, 0, 255>>
      assert Enum.at(pixels, 4) == <<r, g, b, 255>>
    end

    test "a pane of fractional tiles composes at the pixels asked for" do
      layers = [stripe(1.0), Parallax.panorama(name: :wide_strip, art: :wide, size: {2, 1})]

      for {width, height} <- [{472, 200}, {296, 152}, {84, 44}, {655, 399}] do
        raster =
          Parallax.compose(@atlas, layers,
            focus: {40.3, 11.0},
            size: {width / @tile, height / @tile},
            pixels: {width, height}
          )

        assert Raster.dimensions(raster) == {width, height}
      end
    end

    test "layers of both sides at a fractional pane stack together" do
      layers = [
        stripe(1.0),
        Parallax.panorama(name: :over, art: :wide, size: {2, 1}, front: true)
      ]

      size = {472 / @tile, 200 / @tile}

      behind = Parallax.compose(@atlas, layers, focus: {3.7, 1.0}, size: size, pixels: {472, 200})

      front =
        Parallax.compose(@atlas, layers,
          focus: {3.7, 1.0},
          size: size,
          pixels: {472, 200},
          front: true
        )

      assert Raster.dimensions(Surface.stack(behind, front)) == {472, 200}
    end

    test "a side with no layer composes to nothing" do
      behind = Parallax.layer(name: :behind, cell: &void/1)

      assert Parallax.compose(@atlas, [behind], focus: {0.0, 0.0}, size: {8, 2}, front: true) ==
               nil
    end

    test "the raster is exactly the pane asked for" do
      raster = Parallax.compose(@atlas, [stripe(1.0)], focus: {0.0, 0.0}, size: {8, 3})

      assert Raster.dimensions(raster) == {8 * @tile, 3 * @tile}
    end

    test "a layer's movers are placed in the layer's own tiles" do
      layer =
        Parallax.layer(
          name: :with_movers,
          cell: &void/1,
          factor: 1.0,
          void: :opaque,
          movers: [{:blue, {0.0, 0.0}}]
        )

      pixels = row(Parallax.compose(@atlas, [layer], focus: {0.0, 0.0}, size: {8, 2}), 4)

      assert Enum.at(pixels, 4 * @tile) == <<0, 0, 255, 255>>
    end

    test "a layer is redrawn once for each of its tiles the camera crosses" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      layer =
        Parallax.layer(
          name: :counted,
          cell: fn coordinate ->
            Agent.update(counter, &(&1 + 1))
            void(coordinate)
          end,
          factor: 1.0,
          void: :opaque
        )

      for focus <- [0.0, 0.25, 0.5, 0.75] do
        Parallax.compose(@atlas, [layer], focus: {focus, 0.0}, size: {8, 2})
      end

      assert Agent.get(counter, & &1) == 27

      Parallax.compose(@atlas, [layer], focus: {1.0, 0.0}, size: {8, 2})

      assert Agent.get(counter, & &1) == 54
    end

    test "a layer built with cache: false is redrawn every frame" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      layer =
        Parallax.layer(
          name: :uncached,
          cell: fn coordinate ->
            Agent.update(counter, &(&1 + 1))
            void(coordinate)
          end,
          factor: 1.0,
          void: :opaque,
          cache: false
        )

      for focus <- [0.0, 0.25],
          do: Parallax.compose(@atlas, [layer], focus: {focus, 0.0}, size: {8, 2})

      assert Agent.get(counter, & &1) == 54
    end
  end

  describe "Scatter" do
    test "the same seed and coordinate always give the same cell" do
      one = Scatter.cells(seed: 7, density: 0.3, arts: [:red, :blue])
      two = Scatter.cells(seed: 7, density: 0.3, arts: [:red, :blue])

      for x <- -20..20, y <- -5..5, do: assert(one.({x, y}) == two.({x, y}))
    end

    test "a different seed places art differently" do
      one = Scatter.cells(seed: 1, density: 0.3, arts: [:red])
      two = Scatter.cells(seed: 2, density: 0.3, arts: [:red])

      assert Enum.any?(-50..50, fn x -> one.({x, 0}) != two.({x, 0}) end)
    end

    test "density nothing places nothing and density everything places everywhere" do
      none = Scatter.cells(seed: 3, density: 0.0, arts: [:red])
      all = Scatter.cells(seed: 3, density: 1.0, arts: [:red])

      assert Enum.all?(-50..50, fn x -> none.({x, 0}) == :void end)
      assert Enum.all?(-50..50, fn x -> all.({x, 0}) == {:red, [], nil} end)
    end

    test "rows confine art to those tile rows" do
      cells = Scatter.cells(seed: 4, density: 1.0, arts: [:red], rows: 2..3)

      assert cells.({0, 1}) == :void
      assert cells.({0, 2}) == {:red, [], nil}
      assert cells.({0, 3}) == {:red, [], nil}
      assert cells.({0, 4}) == :void
    end

    test "weights decide how often each art is drawn" do
      cells = Scatter.cells(seed: 5, density: 1.0, arts: [{:red, 9}, {:blue, 1}])

      counts =
        for x <- 1..2000, reduce: %{} do
          acc ->
            {art, _, _} = cells.({x, 0})
            Map.update(acc, art, 1, &(&1 + 1))
        end

      assert counts[:red] > counts[:blue] * 4
    end

    test "a density between the ends places art on some tiles and not others" do
      cells = Scatter.cells(seed: 6, density: 0.25, arts: [:red])
      placed = Enum.count(1..4000, fn x -> cells.({x, 0}) != :void end)

      assert placed > 800 and placed < 1200
    end
  end

  describe "Strip" do
    test "a legend reads characters into cells" do
      assert Strip.legend(["r.b"], %{"r" => :red, "." => :void, "b" => :blue}) ==
               [[{:red, [], nil}, :void, {:blue, [], nil}]]
    end

    test "wrapping on x repeats sideways and leaves other rows empty" do
      cells = Strip.cells(Strip.legend(["r..."], %{"r" => :red, "." => :void}), wrap: :x)

      assert cells.({0, 0}) == {:red, [], nil}
      assert cells.({4, 0}) == {:red, [], nil}
      assert cells.({-4, 0}) == {:red, [], nil}
      assert cells.({1, 0}) == :void
      assert cells.({0, 1}) == :void
    end

    test "wrapping on both axes repeats in every direction" do
      cells = Strip.cells(Strip.legend(["r..."], %{"r" => :red, "." => :void}), wrap: :both)

      assert cells.({0, 7}) == {:red, [], nil}
      assert cells.({-8, -3}) == {:red, [], nil}
    end

    test "wrapping on nothing is empty outside the tiles" do
      cells = Strip.cells(Strip.legend(["r..."], %{"r" => :red, "." => :void}), wrap: :none)

      assert cells.({0, 0}) == {:red, [], nil}
      assert cells.({4, 0}) == :void
      assert cells.({-1, 0}) == :void
    end

    test "no tiles is empty everywhere" do
      cells = Strip.cells([])

      assert cells.({0, 0}) == :void
    end
  end

  describe "Panorama" do
    test "copies of the picture cover the pane and no more" do
      assert Panorama.places(true, 0, 8, 10, 0) == [0]
      assert Panorama.places(true, 5, 8, 10, 0) == [0, 10]
      assert Panorama.places(true, 10, 8, 10, 0) == [10]
      assert Panorama.places(true, -1, 2, 10, 0) == [-10, 0]
      assert Panorama.places(true, 0, 25, 10, 0) == [0, 10, 20]
    end

    test "a picture that does not wrap sits where it was put" do
      assert Panorama.places(false, 100, 8, 10, 3) == [3]
    end

    test "an offset moves every copy" do
      assert Panorama.places(true, 0, 8, 10, 3) == [-7, 3]
    end

    test "the picture is drawn across the pane" do
      layer =
        Parallax.panorama(
          name: :panorama,
          art: :wide,
          size: {2, 1},
          wrap: :x,
          factor: 1.0,
          void: :opaque
        )

      raster = Parallax.compose(@atlas, [layer], focus: {0.0, 0.0}, size: {8, 2})

      assert Enum.at(row(raster, @tile), 0) == <<0, 0, 255, 255>>
      assert Enum.at(row(raster, @tile), 8 * @tile - 1) == <<0, 0, 255, 255>>
      assert Enum.at(row(raster, 0), 0) == <<9, 9, 9, 255>>
    end
  end

  describe "Bands" do
    test "each band rolls its own rows and a row no band covers stays put" do
      bands = Bands.new([{0..0, 1.0}, {1..1, 0.0}])
      raster = gradient(16, 8)

      rolled = Bands.roll(raster, bands, {1.0, 0.0}, @tile)

      assert Enum.at(row(rolled, 0), 0) == Enum.at(row(raster, 0), 12)
      assert row(rolled, @tile) == row(raster, @tile)
    end

    test "no bands leaves the picture alone" do
      raster = gradient(16, 8)

      assert Bands.roll(raster, nil, {3.0, 0.0}, @tile) == raster
    end

    test "the factor of a row outside every band is nothing" do
      bands = Bands.new([{0..1, 0.5}])

      assert Bands.factor(bands, 0) == 0.5
      assert Bands.factor(bands, 5) == 0.0
    end
  end

  describe "Blend" do
    test "the C library and the Elixir fallback paint the same pixels" do
      beneath = noise(4096, 11)
      above = noise(4096, 29)

      assert Blend.over(beneath, above) == Blend.elixir_over(beneath, above, [])
    end

    test "a clear pixel keeps what is under it and a solid one replaces it" do
      beneath = <<10, 20, 30, 255, 10, 20, 30, 255>>
      above = <<200, 100, 50, 0, 200, 100, 50, 255>>

      assert Blend.over(beneath, above) == <<10, 20, 30, 255, 200, 100, 50, 255>>
    end
  end

  describe "Surface void" do
    test "an empty tile is the void colour by default and clear when asked" do
      {r, g, b} = @void

      assert binary_part(Surface.tile_binary(@atlas, :void, 1, 0), 0, 4) == <<r, g, b, 255>>

      assert binary_part(Surface.tile_binary(@atlas, :void, 1, 0, :transparent), 0, 4) ==
               <<0, 0, 0, 0>>
    end

    test "a raster given as under shows through the grid's empty tiles" do
      under = Raster.new(8 * @tile, 2 * @tile, background: {0, 255, 0, 255})
      rows = for _y <- 1..2, do: for(_x <- 1..8, do: :void)

      raster = Surface.compose(@atlas, rows, [], void: :transparent, under: under)

      assert Enum.at(row(raster, 0), 0) == <<0, 255, 0, 255>>
    end
  end

  defp void(_coordinate), do: :void

  defp stripe_rows, do: Parallax.legend(["r..."], %{"r" => :red, "." => :void})

  defp stripe(factor) do
    Parallax.layer(
      name: :"stripe_#{factor}",
      cell: Parallax.strip(stripe_rows()),
      factor: factor,
      void: :opaque,
      cache: false
    )
  end

  defp reds(layer, focus, at \\ 0) do
    @atlas
    |> Parallax.compose([layer], focus: {focus, 0.0}, size: {8, 2}, at: at)
    |> row(0)
    |> Enum.with_index()
    |> Enum.filter(fn {pixel, _x} -> pixel == <<255, 0, 0, 255>> end)
    |> Enum.map(&elem(&1, 1))
  end

  defp two_layers(void) do
    back =
      Parallax.layer(
        name: :back,
        cell: fn _coordinate -> {:green, [], nil} end,
        factor: 0.0,
        void: :opaque
      )

    front =
      Parallax.layer(
        name: :"front_#{void}",
        cell: Parallax.strip(stripe_rows()),
        factor: 1.0,
        void: void
      )

    @atlas
    |> Parallax.compose([back, front], focus: {0.0, 0.0}, size: {8, 2})
    |> row(0)
  end

  defp row(%Raster{width: width} = raster, y) do
    rgba = Raster.to_rgba_binary(raster)

    for x <- 0..(width - 1), do: binary_part(rgba, (y * width + x) * 4, 4)
  end

  defp gradient(width, height) do
    rgba =
      for _y <- 1..height, x <- 0..(width - 1), into: <<>> do
        <<x * 16, 0, 0, 255>>
      end

    Raster.from_rgba(width, height, rgba)
  end

  defp noise(pixels, seed) do
    state = :rand.seed_s(:exsss, {seed, seed, seed})

    {binary, _state} =
      Enum.reduce(1..pixels, {<<>>, state}, fn _n, {acc, state} ->
        {values, state} =
          Enum.reduce(1..4, {[], state}, fn _c, {values, state} ->
            {value, state} = :rand.uniform_s(256, state)
            {[value - 1 | values], state}
          end)

        {acc <> IO.iodata_to_binary(Enum.map(values, &<<&1>>)), state}
      end)

    binary
  end
end
