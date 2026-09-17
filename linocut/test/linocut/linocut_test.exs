defmodule LinocutTest do
  use ExUnit.Case, async: true

  alias FrenchCurve.Raster

  defp pixel(raster, x, y), do: Raster.get_pixel(raster, x, y)
  defp on?(raster, x, y), do: elem(pixel(raster, x, y), 3) > 0

  describe "sprite/3" do
    test "a picture with a palette becomes a raster of its size" do
      raster =
        Linocut.sprite(
          """
          ..RR..
          .RWWR.
          """,
          R: "#c33",
          W: :white
        )

      assert Raster.dimensions(raster) == {6, 2}
      assert pixel(raster, 2, 0) == {204, 51, 51, 255}
      assert pixel(raster, 2, 1) == {255, 255, 255, 255}
      assert pixel(raster, 0, 0) == {0, 0, 0, 0}
    end

    test "colours may be six-digit hex, eight-digit hex, names or tuples" do
      raster = Linocut.sprite("abcd", a: "#0a0b0c", b: "#0a0b0c80", c: :cyan, d: {1, 2, 3})
      assert pixel(raster, 0, 0) == {10, 11, 12, 255}
      assert pixel(raster, 1, 0) == {10, 11, 12, 128}
      assert pixel(raster, 2, 0) == {0, 255, 255, 255}
      assert pixel(raster, 3, 0) == {1, 2, 3, 255}
    end

    test "a size option centres the picture on a larger canvas" do
      raster = Linocut.sprite("XX", [X: :red], size: {6, 4})
      assert Raster.dimensions(raster) == {6, 4}
      assert on?(raster, 2, 1) and on?(raster, 3, 1)
      refute on?(raster, 0, 0)
    end

    test "a character the palette lacks is an error" do
      assert_raise ArgumentError, ~r/no colour for "Z"/, fn -> Linocut.sprite("Z", []) end
    end
  end

  describe "outline/2" do
    test "draws a filled shape scaled to fit the size" do
      raster =
        Linocut.outline([{15, 0}, {-8, 8}, {-8, -8}], size: {16, 16}, fill: :white, stroke: :red)

      assert Raster.dimensions(raster) == {16, 16}
      assert on?(raster, 8, 8)
      assert on?(raster, 14, 8), "the nose points right"
      refute on?(raster, 1, 1)
    end

    test "y grows upward in the shape and downward on the raster" do
      raster = Linocut.outline([{0, 8}, {-4, -8}, {4, -8}], size: {16, 16}, fill: :white)
      assert on?(raster, 8, 2), "the point at +y is at the top"
    end

    test "rotate turns the shape counter-clockwise on screen" do
      up =
        Linocut.outline([{15, 0}, {-8, 8}, {-8, -8}],
          size: {16, 16},
          fill: :white,
          rotate: :math.pi() / 2
        )

      assert on?(raster_top(up), 0, 0)
    end
  end

  defp raster_top(raster) do
    for x <- 0..15, y <- 0..1, on?(raster, x, y), reduce: Raster.new(16, 16) do
      acc -> Raster.put_pixel(acc, 0, 0, {255, 255, 255, 255})
    end
  end

  describe "headings/3" do
    test "gives one raster per heading, the first pointing right" do
      rasters = Linocut.headings([{15, 0}, {-8, 8}, {-8, -8}], 4, size: {16, 16}, fill: :white)
      assert length(rasters) == 4
      assert Enum.all?(rasters, &(Raster.dimensions(&1) == {16, 16}))
      assert on?(Enum.at(rasters, 0), 14, 8)
      assert on?(Enum.at(rasters, 1), 8, 1)
      assert on?(Enum.at(rasters, 2), 1, 8)
      assert on?(Enum.at(rasters, 3), 8, 14)
    end
  end

  describe "derivations" do
    test "recolour swaps exact colours" do
      raster =
        Linocut.sprite("RG", R: :red, G: :green)
        |> Linocut.recolour(%{{255, 0, 0, 255} => {0, 0, 255, 255}})

      assert pixel(raster, 0, 0) == {0, 0, 255, 255}
      assert pixel(raster, 1, 0) == {0, 255, 0, 255}
    end

    test "recolour takes a function" do
      raster =
        Linocut.sprite("R", R: :red)
        |> Linocut.recolour(fn {r, g, b, a} -> {div(r, 2), g, b, a} end)

      assert pixel(raster, 0, 0) == {127, 0, 0, 255}
    end

    test "tint mixes toward a colour, leaving transparency alone" do
      raster = Linocut.sprite("R.", R: :black) |> Linocut.tint({255, 255, 255}, 0.5)
      assert pixel(raster, 0, 0) == {128, 128, 128, 255}
      assert pixel(raster, 1, 0) == {0, 0, 0, 0}
    end

    test "scale enlarges by whole pixels" do
      raster = Linocut.sprite("RG", R: :red, G: :green) |> Linocut.scale(3)
      assert Raster.dimensions(raster) == {6, 3}
      assert pixel(raster, 2, 2) == {255, 0, 0, 255}
      assert pixel(raster, 3, 0) == {0, 255, 0, 255}
    end
  end

  describe "Strip" do
    test "loops through its frames at its rate" do
      frames = [Linocut.sprite("R", R: :red), Linocut.sprite("G", G: :green)]
      strip = Linocut.Strip.new(frames, 10)
      assert pixel(Linocut.Strip.frame_at(strip, 0), 0, 0) == {255, 0, 0, 255}
      assert pixel(Linocut.Strip.frame_at(strip, 100), 0, 0) == {0, 255, 0, 255}
      assert pixel(Linocut.Strip.frame_at(strip, 200), 0, 0) == {255, 0, 0, 255}
    end
  end

  describe "Cache" do
    setup do
      dir = Path.join(System.tmp_dir!(), "linocut_cache_#{System.unique_integer([:positive])}")
      previous = System.get_env("XDG_CACHE_HOME")
      System.put_env("XDG_CACHE_HOME", dir)

      on_exit(fn ->
        File.rm_rf!(dir)

        if previous,
          do: System.put_env("XDG_CACHE_HOME", previous),
          else: System.delete_env("XDG_CACHE_HOME")
      end)

      :ok
    end

    test "renders once and reads back the same rasters" do
      render = fn ->
        Linocut.headings([{15, 0}, {-8, 8}, {-8, -8}], 8, size: {16, 16}, fill: :white)
      end

      first = Linocut.Cache.fetch("ship", "1", render)
      second = Linocut.Cache.fetch("ship", "1", fn -> flunk("rendered twice") end)

      assert Enum.map(first, &Raster.to_rgba_binary/1) ==
               Enum.map(second, &Raster.to_rgba_binary/1)
    end
  end

  describe "Preview" do
    test "a sheet tiles rasters left to right" do
      sheet =
        Linocut.Preview.sheet([Linocut.sprite("R", R: :red), Linocut.sprite("G", G: :green)],
          columns: 2,
          gap: 1
        )

      assert Raster.dimensions(sheet) == {3, 1}
      assert pixel(sheet, 0, 0) == {255, 0, 0, 255}
      assert pixel(sheet, 2, 0) == {0, 255, 0, 255}
    end

    test "to_terminal produces braille text without a terminal" do
      text = Linocut.Preview.to_terminal(Linocut.sprite("RR", R: :red), protocol: :braille)
      assert is_binary(text)
    end
  end
end
