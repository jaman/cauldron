defmodule Crossing.Art do
  @moduledoc """
  The board's tiles, drawn in code and installed into a `Cauldron2D.Atlas`.

  Everything is a 16-pixel raster with a two-cell glyph beside it, so the game reads in a
  terminal with pixels and in one without. The shapes are deliberately small and cheap —
  rectangles, circles, a few lines — but they are outlined, shaded and textured.

  What moves is drawn in parts. A log is a left end, a middle and a right end; a car is
  two parts, a truck three and a bus four. Each part fills its tile edge to edge and
  lights its top row the same way, so the parts join without a seam, and only the outer
  parts carry a wheel. That is what stops a two-tile car reading as two cars.

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
    {:car_l, "▛▜", {206, 76, 84}},
    {:car_r, "▛▜", {206, 76, 84}},
    {:truck_l, "▛▜", {86, 128, 186}},
    {:truck_mid, "▛▜", {206, 146, 58}},
    {:truck_r, "▛▜", {86, 128, 186}},
    {:bus_l, "▛▜", {92, 150, 210}},
    {:bus_mid, "▛▜", {78, 134, 196}},
    {:bus_r, "▛▜", {92, 150, 210}},
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

  # --- which raster an art is -----------------------------------------------------

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
  defp raster(:car_l), do: car(:left)
  defp raster(:car_r), do: car(:right)
  defp raster(:truck_l), do: truck(:left)
  defp raster(:truck_mid), do: truck(:middle)
  defp raster(:truck_r), do: truck(:right)
  defp raster(:bus_l), do: bus(:left)
  defp raster(:bus_mid), do: bus(:middle)
  defp raster(:bus_r), do: bus(:right)
  defp raster(:frog), do: frog(false)
  defp raster(:frog_hop), do: frog(true)
  defp raster(:bank), do: bank()
  defp raster(:shadow), do: shadow()

  # --- ground ---------------------------------------------------------------------

  defp tile(colour), do: Raster.new(@tile, @tile, background: colour)

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
      nil -> raster
      {x, y} -> flower(raster, x, y)
    end
  end

  defp flower(raster, x, y) do
    raster
    |> Raster.put_pixel(x, y - 1, {238, 236, 210, 255})
    |> Raster.put_pixel(x - 1, y, {238, 236, 210, 255})
    |> Raster.put_pixel(x + 1, y, {238, 236, 210, 255})
    |> Raster.put_pixel(x, y + 1, {238, 236, 210, 255})
    |> Raster.put_pixel(x, y, {236, 206, 96, 255})
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
    |> Draw.fill_rect({2, 0}, {6, 1}, {180, 182, 190, 255})
    |> Draw.fill_rect({10, 0}, {14, 1}, {180, 182, 190, 255})
  end

  defp speckle(raster, colour, salt) do
    Enum.reduce(0..9, raster, fn step, raster ->
      x = rem(step * 5 + salt * 7, @tile)
      y = rem(step * 3 + salt * 5, @tile)
      Raster.put_pixel(raster, x, y, colour)
    end)
  end

  # --- logs -----------------------------------------------------------------------

  defp log(side) do
    raster =
      {150, 104, 62, 255}
      |> tile()
      |> Draw.fill_rect({0, 3}, {@tile - 1, 12}, {162, 114, 68, 255})
      |> Draw.fill_rect({0, 3}, {@tile - 1, 4}, {186, 136, 84, 255})
      |> Draw.fill_rect({0, 11}, {@tile - 1, 12}, {120, 80, 46, 255})
      |> bark()

    case side do
      :middle ->
        raster

      :left ->
        raster
        |> Draw.fill_circle({1, 8}, 5, {176, 126, 78, 255})
        |> Draw.fill_circle({1, 8}, 3, {132, 90, 54, 255})
        |> Draw.fill_circle({1, 8}, 1, {104, 70, 42, 255})
        |> outline({46, 32, 22, 255})

      :right ->
        raster
        |> Draw.fill_circle({15, 8}, 5, {176, 126, 78, 255})
        |> Draw.fill_circle({15, 8}, 3, {132, 90, 54, 255})
        |> Draw.fill_circle({15, 8}, 1, {104, 70, 42, 255})
        |> outline({46, 32, 22, 255})
    end
  end

  defp bark(raster) do
    Enum.reduce(2..4, raster, fn line, raster ->
      y = line * 3
      Draw.line(raster, {3, y}, {12, y}, {136, 92, 56, 255})
    end)
  end

  # --- cars, trucks and buses -----------------------------------------------------

  defp car(side) do
    {186, 66, 76, 255}
    |> tile()
    |> Draw.fill_rect({0, 3}, {@tile - 1, 11}, {210, 82, 92, 255})
    |> Draw.fill_rect({0, 3}, {@tile - 1, 4}, {238, 120, 126, 255})
    |> Draw.fill_rect({0, 10}, {@tile - 1, 11}, {150, 44, 56, 255})
    |> Draw.fill_rect({3, 5}, {12, 8}, {120, 208, 240, 255})
    |> Draw.fill_rect({3, 5}, {12, 5}, {196, 240, 255, 255})
    |> wheel(if(side == :left, do: 3, else: 12))
    |> outline({52, 22, 28, 255})
  end

  defp truck(:left), do: cab() |> wheel(3) |> outline({26, 44, 74, 255})
  defp truck(:right), do: cab() |> wheel(12) |> outline({26, 44, 74, 255})

  defp truck(:middle) do
    {196, 138, 56, 255}
    |> tile()
    |> Draw.fill_rect({0, 1}, {@tile - 1, 12}, {210, 150, 62, 255})
    |> Draw.fill_rect({0, 1}, {@tile - 1, 2}, {236, 180, 92, 255})
    |> Draw.fill_rect({0, 11}, {@tile - 1, 12}, {160, 108, 40, 255})
    |> Draw.fill_rect({2, 4}, {13, 5}, {176, 120, 44, 255})
    |> Draw.fill_rect({2, 8}, {13, 9}, {176, 120, 44, 255})
  end

  defp cab do
    {78, 120, 178, 255}
    |> tile()
    |> Draw.fill_rect({0, 1}, {@tile - 1, 12}, {92, 138, 198, 255})
    |> Draw.fill_rect({0, 1}, {@tile - 1, 2}, {124, 172, 226, 255})
    |> Draw.fill_rect({2, 4}, {13, 8}, {170, 218, 246, 255})
    |> Draw.fill_rect({2, 4}, {13, 5}, {212, 240, 252, 255})
  end

  defp bus(:left), do: bus_body() |> wheel(3) |> outline({24, 44, 70, 255})
  defp bus(:right), do: bus_body() |> wheel(12) |> outline({24, 44, 70, 255})

  defp bus(:middle) do
    bus_body()
    |> Draw.fill_rect({1, 4}, {5, 8}, {188, 228, 250, 255})
    |> Draw.fill_rect({8, 4}, {12, 8}, {188, 228, 250, 255})
  end

  defp bus_body do
    {82, 140, 200, 255}
    |> tile()
    |> Draw.fill_rect({0, 1}, {@tile - 1, 12}, {96, 156, 216, 255})
    |> Draw.fill_rect({0, 1}, {@tile - 1, 2}, {128, 188, 238, 255})
    |> Draw.fill_rect({0, 11}, {@tile - 1, 12}, {58, 106, 160, 255})
  end

  defp wheel(raster, x) do
    raster
    |> Draw.fill_circle({x, 13}, 2, {38, 38, 46, 255})
    |> Draw.fill_circle({x, 13}, 1, {78, 78, 92, 255})
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
