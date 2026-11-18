defmodule Crossing.Art do
  @moduledoc """
  The board's tiles, drawn in code and installed into a `Cauldron2D.Atlas`.

  Everything is a 16-pixel raster with a two-cell glyph beside it, so the game reads in a
  terminal with pixels and in one without. The shapes are deliberately small and cheap —
  rectangles, circles, a few lines — but they are outlined, shaded and textured, and the
  logs and carts come in segments: a three-tile log is a left end, a middle and a right
  end, so it looks like one thing rather than three.

  `install/0` is idempotent, so a client may call it on every mount.
  """

  alias Cauldron2D.Atlas
  alias FrenchCurve.{Draw, Raster}

  @tile 16
  @name :crossing
  @void {14, 20, 18}

  @catalogue [
    {:grass_a, "░░", {84, 138, 78}},
    {:grass_b, "░░", {80, 132, 74}},
    {:grass_c, "░░", {86, 136, 76}},
    {:water_a, "≈≈", {58, 108, 168}},
    {:water_b, "≈≈", {58, 108, 168}},
    {:road, "▓▓", {62, 64, 74}},
    {:log_left, "▬▬", {150, 104, 62}},
    {:log_mid, "▬▬", {150, 104, 62}},
    {:log_right, "▬▬", {150, 104, 62}},
    {:car_front, "▛▜", {206, 76, 84}},
    {:car_back, "▛▜", {176, 62, 74}},
    {:truck_back, "▛▜", {206, 146, 58}},
    {:truck_mid, "▛▜", {190, 132, 52}},
    {:truck_front, "▛▜", {86, 128, 186}},
    {:bus_back, "▛▜", {92, 150, 210}},
    {:bus_mid, "▛▜", {78, 134, 196}},
    {:bus_front, "▛▜", {64, 116, 178}},
    {:frog, "♞ ", {132, 214, 96}},
    {:frog_hop, "♞ ", {150, 226, 110}},
    {:bank, "○ ", {120, 170, 110}},
    {:shadow, "  ", {0, 0, 0}}
  ]

  @doc "The atlas name everything else refers to."
  @spec name() :: atom()
  def name, do: @name

  @doc "Draw the catalogue and install it, returning the atlas name."
  @spec install() :: atom()
  def install do
    if Atlas.installed?(@name) do
      @name
    else
      @catalogue
      |> Enum.reduce(Atlas.new(@name, tile: @tile, void: @void), &add/2)
      |> Atlas.install()
    end
  end

  defp add({art, glyph, colour}, atlas) do
    frames = if art in [:water_a, :water_b], do: [fps: 3], else: []
    Atlas.put(atlas, art, rasters(art), [glyph: glyph, color: colour] ++ frames)
  end

  # --- pieces ---------------------------------------------------------------------

  defp rasters(:water_a), do: [water(0), water(3)]
  defp rasters(:water_b), do: [water(5), water(8)]
  defp rasters(art), do: [raster(art)]

  defp raster(:grass_a), do: grass({92, 146, 82, 255}, {70, 118, 66, 255}, 1, {11, 5})
  defp raster(:grass_b), do: grass({88, 140, 78, 255}, {66, 112, 62, 255}, 5, nil)
  defp raster(:grass_c), do: grass({86, 136, 76, 255}, {64, 110, 60, 255}, 3, {4, 11})
  defp raster(:road), do: road()
  defp raster(:log_left), do: log(:left)
  defp raster(:log_mid), do: log(:middle)
  defp raster(:log_right), do: log(:right)
  defp raster(:car_front), do: car(false)
  defp raster(:car_back), do: car(true)
  defp raster(:truck_back), do: truck(:back)
  defp raster(:truck_mid), do: truck(:middle)
  defp raster(:truck_front), do: truck(:front)
  defp raster(:bus_back), do: bus(:back)
  defp raster(:bus_mid), do: bus(:middle)
  defp raster(:bus_front), do: bus(:front)
  defp raster(:frog), do: frog(false)
  defp raster(:frog_hop), do: frog(true)
  defp raster(:bank), do: bank()
  defp raster(:shadow), do: shadow()

  defp tile(colour), do: Raster.new(@tile, @tile, background: colour)

  # --- ground ---------------------------------------------------------------------

  defp grass(base, tuft, salt, flower) do
    raster =
      tile(base)
      |> Draw.fill_rect({0, 0}, {@tile - 1, 0}, {104, 158, 92, 255})
      |> Draw.fill_rect({0, @tile - 1}, {@tile - 1, @tile - 1}, {74, 122, 70, 255})

    raster =
      Enum.reduce(0..7, raster, fn step, raster ->
        x = rem(step * 5 + salt * 3, @tile - 2) + 1
        y = rem(step * 7 + salt * 5, @tile - 4) + 2

        raster
        |> Raster.put_pixel(x, y, tuft)
        |> Raster.put_pixel(x + 1, y, tuft)
        |> Raster.put_pixel(x, y + 1, tuft)
      end)

    case flower do
      nil ->
        raster

      {x, y} ->
        raster
        |> Raster.put_pixel(x, y - 1, {238, 236, 210, 255})
        |> Raster.put_pixel(x - 1, y, {238, 236, 210, 255})
        |> Raster.put_pixel(x + 1, y, {238, 236, 210, 255})
        |> Raster.put_pixel(x, y + 1, {238, 236, 210, 255})
        |> Raster.put_pixel(x, y, {236, 206, 96, 255})
    end
  end

  defp water(shift) do
    raster =
      tile({52, 100, 162, 255})
      |> Draw.fill_rect({0, 2}, {@tile - 1, 3}, {64, 116, 178, 255})
      |> Draw.fill_rect({0, 10}, {@tile - 1, 11}, {64, 116, 178, 255})

    Enum.reduce(0..2, raster, fn band, raster ->
      y = 4 + band * 5
      x = rem(band * 6 + shift, 8)

      raster
      |> Draw.line({x, y}, {x + 5, y}, {96, 152, 210, 255})
      |> Draw.line({x + 2, y + 1}, {x + 7, y + 1}, {86, 142, 200, 255})
    end)
  end

  defp road do
    tile({58, 60, 70, 255})
    |> Draw.fill_rect({0, 0}, {@tile - 1, 1}, {66, 68, 80, 255})
    |> Draw.fill_rect({0, @tile - 2}, {@tile - 1, @tile - 1}, {48, 50, 60, 255})
    |> speckle({72, 74, 88, 255}, 3)
    |> Draw.fill_rect({2, 7}, {6, 8}, {180, 182, 190, 255})
    |> Draw.fill_rect({10, 7}, {14, 8}, {180, 182, 190, 255})
  end

  defp speckle(raster, colour, salt) do
    Enum.reduce(0..9, raster, fn step, raster ->
      x = rem(step * 5 + salt * 7, @tile)
      y = rem(step * 3 + salt * 5, @tile)
      Raster.put_pixel(raster, x, y, colour)
    end)
  end

  # --- what moves -----------------------------------------------------------------

  defp log(:left) do
    {150, 104, 62, 255}
    |> tile()
    |> Draw.fill_rect({0, 3}, {@tile - 1, 12}, {162, 114, 68, 255})
    |> Draw.fill_rect({0, 3}, {@tile - 1, 4}, {186, 136, 84, 255})
    |> Draw.fill_rect({0, 11}, {@tile - 1, 12}, {120, 80, 46, 255})
    |> bark()
    |> Draw.fill_circle({1, 8}, 5, {176, 126, 78, 255})
    |> Draw.fill_circle({1, 8}, 3, {132, 90, 54, 255})
    |> Draw.fill_circle({1, 8}, 1, {104, 70, 42, 255})
    |> outline({46, 32, 22, 255})
  end

  defp log(:middle) do
    {150, 104, 62, 255}
    |> tile()
    |> Draw.fill_rect({0, 3}, {@tile - 1, 12}, {162, 114, 68, 255})
    |> Draw.fill_rect({0, 3}, {@tile - 1, 4}, {186, 136, 84, 255})
    |> Draw.fill_rect({0, 11}, {@tile - 1, 12}, {120, 80, 46, 255})
    |> bark()
  end

  defp log(:right) do
    {150, 104, 62, 255}
    |> tile()
    |> Draw.fill_rect({0, 3}, {@tile - 1, 12}, {162, 114, 68, 255})
    |> Draw.fill_rect({0, 3}, {@tile - 1, 4}, {186, 136, 84, 255})
    |> Draw.fill_rect({0, 11}, {@tile - 1, 12}, {120, 80, 46, 255})
    |> bark()
    |> Draw.fill_circle({15, 8}, 5, {176, 126, 78, 255})
    |> Draw.fill_circle({15, 8}, 3, {132, 90, 54, 255})
    |> Draw.fill_circle({15, 8}, 1, {104, 70, 42, 255})
    |> outline({46, 32, 22, 255})
  end

  defp bark(raster) do
    Enum.reduce(2..4, raster, fn line, raster ->
      y = line * 3
      Draw.line(raster, {3, y}, {12, y}, {136, 92, 56, 255})
    end)
  end

  defp car(front?) do
    {186, 66, 76, 255}
    |> tile()
    |> Draw.fill_rect({0, 3}, {@tile - 1, 11}, {210, 82, 92, 255})
    |> Draw.fill_rect({0, 3}, {@tile - 1, 4}, {238, 120, 126, 255})
    |> Draw.fill_rect({0, 10}, {@tile - 1, 11}, {150, 44, 56, 255})
    |> windows(front?)
    |> Draw.fill_circle({4, 13}, 2, {38, 38, 46, 255})
    |> Draw.fill_circle({11, 13}, 2, {38, 38, 46, 255})
    |> outline({52, 22, 28, 255})
  end

  defp windows(raster, true) do
    raster
    |> Draw.fill_rect({2, 5}, {6, 8}, {120, 208, 240, 255})
    |> Draw.fill_rect({9, 5}, {13, 8}, {120, 208, 240, 255})
    |> Draw.fill_rect({2, 5}, {6, 5}, {196, 240, 255, 255})
  end

  defp windows(raster, false) do
    raster
    |> Draw.fill_rect({3, 5}, {12, 8}, {96, 178, 214, 255})
    |> Draw.fill_rect({3, 5}, {12, 5}, {170, 226, 250, 255})
  end

  # --- the frog -------------------------------------------------------------------

  defp frog(hop?) do
    body = if hop?, do: {150, 226, 110, 255}, else: {126, 206, 92, 255}
    belly = if hop?, do: {186, 240, 150, 255}, else: {166, 232, 130, 255}

    Raster.new(@tile, @tile)
    |> Draw.fill_circle({4, 12}, 2, body)
    |> Draw.fill_circle({11, 12}, 2, body)
    |> Draw.fill_circle({8, 9}, 5, body)
    |> Draw.fill_circle({8, 8}, 3, belly)
    |> Draw.fill_circle({5, 4}, 2, body)
    |> Draw.fill_circle({11, 4}, 2, body)
    |> Draw.fill_circle({5, 4}, 1, {250, 252, 240, 255})
    |> Draw.fill_circle({11, 4}, 1, {250, 252, 240, 255})
    |> Raster.put_pixel(5, 4, {26, 40, 24, 255})
    |> Raster.put_pixel(11, 4, {26, 40, 24, 255})
    |> Draw.fill_rect({7, 10}, {9, 11}, {88, 150, 66, 255})
    |> outline({38, 62, 34, 255})
  end

  defp truck(:back) do
    {196, 138, 56, 255}
    |> tile()
    |> Draw.fill_rect({0, 2}, {@tile - 1, 12}, {210, 150, 62, 255})
    |> Draw.fill_rect({0, 2}, {@tile - 1, 3}, {236, 180, 92, 255})
    |> Draw.fill_rect({0, 11}, {@tile - 1, 12}, {160, 108, 40, 255})
    |> Draw.fill_rect({3, 5}, {12, 6}, {176, 120, 44, 255})
    |> Draw.fill_rect({3, 9}, {12, 10}, {176, 120, 44, 255})
    |> Draw.fill_circle({4, 13}, 2, {38, 38, 46, 255})
    |> Draw.fill_circle({11, 13}, 2, {38, 38, 46, 255})
    |> outline({52, 36, 18, 255})
  end

  defp truck(:middle) do
    {190, 132, 52, 255}
    |> tile()
    |> Draw.fill_rect({0, 2}, {@tile - 1, 12}, {204, 144, 58, 255})
    |> Draw.fill_rect({0, 2}, {@tile - 1, 3}, {230, 174, 88, 255})
    |> Draw.fill_rect({0, 11}, {@tile - 1, 12}, {156, 104, 38, 255})
    |> Draw.fill_rect({3, 5}, {12, 6}, {172, 116, 42, 255})
    |> Draw.fill_rect({3, 9}, {12, 10}, {172, 116, 42, 255})
  end

  defp truck(:front) do
    {78, 120, 178, 255}
    |> tile()
    |> Draw.fill_rect({0, 3}, {@tile - 1, 12}, {92, 138, 198, 255})
    |> Draw.fill_rect({0, 3}, {@tile - 1, 4}, {124, 172, 226, 255})
    |> Draw.fill_rect({2, 5}, {13, 9}, {168, 216, 244, 255})
    |> Draw.fill_rect({2, 5}, {13, 6}, {206, 236, 252, 255})
    |> Draw.fill_circle({4, 13}, 2, {38, 38, 46, 255})
    |> Draw.fill_circle({11, 13}, 2, {38, 38, 46, 255})
    |> outline({26, 44, 74, 255})
  end

  defp bus(:back) do
    {82, 140, 200, 255}
    |> tile()
    |> Draw.fill_rect({0, 2}, {@tile - 1, 12}, {96, 156, 216, 255})
    |> Draw.fill_rect({0, 2}, {@tile - 1, 3}, {128, 188, 238, 255})
    |> Draw.fill_rect({2, 5}, {13, 8}, {44, 62, 92, 255})
    |> Draw.fill_circle({4, 13}, 2, {38, 38, 46, 255})
    |> Draw.fill_circle({11, 13}, 2, {38, 38, 46, 255})
    |> outline({24, 44, 70, 255})
  end

  defp bus(:middle) do
    {78, 134, 196, 255}
    |> tile()
    |> Draw.fill_rect({0, 2}, {@tile - 1, 12}, {92, 150, 210, 255})
    |> Draw.fill_rect({0, 2}, {@tile - 1, 3}, {124, 184, 234, 255})
    |> Draw.fill_rect({1, 5}, {5, 8}, {188, 228, 250, 255})
    |> Draw.fill_rect({8, 5}, {12, 8}, {188, 228, 250, 255})
    |> Draw.fill_rect({0, 11}, {@tile - 1, 12}, {58, 106, 160, 255})
  end

  defp bus(:front) do
    {68, 118, 180, 255}
    |> tile()
    |> Draw.fill_rect({0, 2}, {@tile - 1, 12}, {84, 140, 200, 255})
    |> Draw.fill_rect({0, 2}, {@tile - 1, 3}, {118, 176, 230, 255})
    |> Draw.fill_rect({2, 4}, {13, 9}, {170, 218, 246, 255})
    |> Draw.fill_rect({2, 4}, {13, 5}, {212, 240, 252, 255})
    |> Draw.fill_circle({4, 13}, 2, {38, 38, 46, 255})
    |> Draw.fill_circle({11, 13}, 2, {38, 38, 46, 255})
    |> outline({24, 42, 66, 255})
  end

  # --- the far bank ---------------------------------------------------------------

  defp bank do
    tile({52, 100, 162, 255})
    |> Draw.fill_circle({8, 8}, 7, {84, 146, 88, 255})
    |> Draw.fill_circle({8, 8}, 6, {104, 170, 102, 255})
    |> Draw.fill_circle({8, 8}, 2, {60, 110, 66, 255})
    |> Draw.fill_polygon([{8, 1}, {9, 3}, {7, 3}], {70, 120, 70, 255})
    |> Draw.fill_circle({11, 5}, 1, {246, 226, 150, 255})
    |> outline({44, 78, 50, 255})
  end

  defp shadow do
    Raster.new(@tile, @tile, background: {0, 0, 0, 0})
    |> Draw.fill_circle({8, 8}, 6, {0, 0, 0, 60})
    |> Draw.fill_circle({8, 8}, 4, {0, 0, 0, 40})
  end

  # --- a dark edge around whatever is not transparent ------------------------------

  defp outline(raster, colour) do
    Enum.reduce(0..(@tile - 1), raster, fn y, raster ->
      Enum.reduce(0..(@tile - 1), raster, fn x, raster -> outline_pixel(raster, x, y, colour) end)
    end)
  end

  defp outline_pixel(raster, x, y, colour) do
    if alpha(Raster.get_pixel(raster, x, y)) == 0 and edge?(raster, x, y) do
      Raster.put_pixel(raster, x, y, colour)
    else
      raster
    end
  end

  defp edge?(raster, x, y) do
    Enum.any?([{1, 0}, {-1, 0}, {0, 1}, {0, -1}], fn {dx, dy} ->
      px = x + dx
      py = y + dy

      px >= 0 and px < @tile and py >= 0 and py < @tile and
        alpha(Raster.get_pixel(raster, px, py)) > 40
    end)
  end

  defp alpha(nil), do: 0
  defp alpha({_r, _g, _b, a}), do: a
end
