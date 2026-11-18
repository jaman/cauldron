# Draws the book's engine figures, and the three stages of a Cauldron world.
#
#     cd cauldron_2d && mix run ../book/make_figures.exs
#
# Writes:
#   book/assets/stage-tiles.png   a grid of tiles, the first 2D a game has
#   book/assets/stage-art.png     the same world with art: texture, shadow, water
#   book/assets/stage-open.png    an open world: a sampled height field, streamed cells,
#                                 things, a backdrop, and the window that loads cells
#
# Each is drawn with Cauldron2D.Render and Cauldron2D.Shapes, so the figures are the
# engine's own output rather than an artist's impression.

alias Cauldron2D.{Raster, Render, Shapes}

# ---------------------------------------------------------------- colours

grass = {134, 162, 114, 255}
grass_dark = {123, 150, 104, 255}
sand = {214, 195, 148, 255}
sand_dark = {201, 181, 134, 255}
water = {79, 125, 156, 255}
water_light = {96, 143, 174, 255}
water_deep = {58, 96, 125, 255}
stone = {145, 145, 150, 255}
stone_dark = {120, 120, 126, 255}
ink = {40, 40, 44, 255}
trunk = {122, 85, 58, 255}
canopy = {63, 107, 69, 255}
canopy_light = {85, 130, 83, 255}
skin = {226, 156, 124, 255}
body = {201, 95, 63, 255}
cream = {243, 234, 216, 255}
shadow = {0, 0, 0, 70}

# ---------------------------------------------------------------- sprites

tree = fn ->
  r = Raster.new(22, 28, background: {0, 0, 0, 0})
  r = Shapes.fill_rect(r, {10, 16}, {13, 27}, trunk)
  r = Shapes.fill_rect(r, {8, 24}, {15, 25}, shadow)
  r = Shapes.fill_polygon(r, [{11, 0}, {20, 8}, {20, 16}, {11, 21}, {2, 16}, {2, 8}], canopy)
  Shapes.fill_polygon(r, [{11, 3}, {16, 8}, {16, 14}, {11, 17}, {6, 14}, {6, 8}], canopy_light)
end

figure = fn ->
  r = Raster.new(14, 22, background: {0, 0, 0, 0})
  Shapes.fill_rect(r, {3, 20}, {10, 20}, shadow)
  r = Shapes.fill_rect(r, {4, 15}, {5, 21}, ink)
  r = Shapes.fill_rect(r, {8, 15}, {9, 21}, ink)
  r = Shapes.fill_rect(r, {3, 8}, {10, 16}, body)
  r = Shapes.fill_rect(r, {1, 9}, {2, 14}, body)
  r = Shapes.fill_rect(r, {11, 9}, {12, 14}, body)
  r = Shapes.fill_rect(r, {4, 17}, {9, 18}, cream)
  r = Shapes.fill_rect(r, {4, 2}, {9, 8}, skin)
  r = Shapes.fill_rect(r, {5, 4}, {6, 5}, ink)
  Shapes.fill_rect(r, {7, 4}, {8, 5}, ink)
end

rock = fn ->
  r = Raster.new(12, 10, background: {0, 0, 0, 0})
  r = Shapes.fill_rect(r, {1, 3}, {10, 8}, stone)
  Shapes.fill_rect(r, {2, 1}, {9, 2}, stone_dark)
end

# ---------------------------------------------------------------- stage one

tile = 16
columns = 40
rows = 24

speckle? = fn x, y, n -> rem(x * 31 + y * 17 + n * 7, 11) == 0 end

texture = fn kind, base, dot ->
  r = Raster.new(tile, tile, background: base)

  for y <- 0..(tile - 1), x <- 0..(tile - 1), reduce: r do
    r ->
      cond do
        kind == :water and rem(y + div(x, 5), 6) == 0 -> Shapes.fill_rect(r, {x, y}, {x, y}, water_light)
        kind == :water -> r
        speckle?.(x, y, 2) -> Shapes.fill_rect(r, {x, y}, {x, y}, dot)
        true -> r
      end
  end
end

flat = fn colour -> Raster.new(tile, tile, background: colour) end

river = 30..33
bank = [29, 34]
path_rows = 12..13

tiles_ops =
  for y <- 0..(rows - 1), x <- 0..(columns - 1) do
    cond do
      x in river -> {:raster, flat.(water), {x * tile, y * tile}}
      x in bank -> {:raster, flat.(sand), {x * tile, y * tile}}
      y in path_rows -> {:raster, flat.(sand), {x * tile, y * tile}}
      true -> {:raster, flat.(grass), {x * tile, y * tile}}
    end
  end

grid = fn raster ->
  Enum.reduce(0..(columns - 1), raster, fn x, r ->
    Shapes.line(r, {x * tile, 0}, {x * tile, rows * tile - 1}, {0, 0, 0, 26})
  end)
  |> then(fn r ->
    Enum.reduce(0..(rows - 1), r, fn y, r ->
      Shapes.line(r, {0, y * tile}, {columns * tile - 1, y * tile}, {0, 0, 0, 26})
    end)
  end)
end

stage_tiles =
  Render.render({columns * tile, rows * tile}, tiles_ops, background: grass)
  |> then(fn r -> grid.(r) end)

File.write!(
  Path.expand("../book/assets/stage-tiles.png", __DIR__),
  FrenchCurve.Png.encode(stage_tiles.width, stage_tiles.height, Raster.to_rgba_binary(stage_tiles))
)

# ---------------------------------------------------------------- stage two

grass_tile = texture.(:grass, grass, grass_dark)
sand_tile = texture.(:sand, sand, sand_dark)
water_tile = texture.(:water, water, water_light)

art_ops =
  for y <- 0..(rows - 1), x <- 0..(columns - 1) do
    cond do
      x in river -> {:raster, water_tile, {x * tile, y * tile}}
      x in bank -> {:raster, sand_tile, {x * tile, y * tile}}
      y in path_rows -> {:raster, sand_tile, {x * tile, y * tile}}
      y in 6..7 and x in 7..8 -> {:raster, sand_tile, {x * tile, y * tile}}
      true -> {:raster, grass_tile, {x * tile, y * tile}}
    end
  end

trees = [
  {3, 3}, {8, 2}, {13, 4}, {18, 2}, {23, 3}, {26, 1}, {5, 9}, {17, 8}, {21, 9},
  {24, 7}, {36, 5}, {38, 9}, {3, 17}, {14, 18}, {20, 16}, {25, 18}, {37, 19}, {33, 3}
]

stones = [{11, 8}, {23, 14}, {31, 18}, {33, 10}, {13, 15}]

art_ops = art_ops ++ for {x, y} <- stones, do: {:sprite, rock.(), %{position: {x * tile + 2, y * tile + 5}}}

art_ops =
  art_ops ++
    for {x, y} <- Enum.sort_by(trees, fn {_x, y} -> y end),
        do: {:sprite, tree.(), %{position: {x * tile - 3, y * tile - 12}}}

art_ops = art_ops ++ [{:sprite, figure.(), %{position: {8 * tile + 1, 11 * tile + 2}}}]

stage_art = Render.render({columns * tile, rows * tile}, art_ops, background: grass)

File.write!(
  Path.expand("../book/assets/stage-art.png", __DIR__),
  FrenchCurve.Png.encode(stage_art.width, stage_art.height, Raster.to_rgba_binary(stage_art))
)

# ---------------------------------------------------------------- stage three

wide = 660
high = 372
water_level = 2.0

height = fn x, y ->
  8.0 +
    12.0 * :math.sin(x / 61.0) +
    9.0 * :math.cos(y / 43.0) +
    4.0 * :math.sin((x + y) / 23.0) +
    2.0 * :math.cos((x - y) / 11.0)
end

slope = fn f, x, y -> {f.(x + 1, y) - f.(x - 1, y), f.(x, y + 1) - f.(x, y - 1)} end

tint = fn {r, g, b, _a}, light ->
  {round(min(255, r * light)), round(min(255, g * light)), round(min(255, b * light))}
end

# One pixel per map unit, shaded by the ground's steepness, coloured by its height.
relief =
  for y <- 0..(high - 1), x <- 0..(wide - 1), into: <<>> do
    h = height.(x, y)
    {dx, dy} = slope.(height, x, y)

    light =
      (0.72 - 0.55 * dx / 12.0 + 0.35 * dy / 12.0)
      |> max(0.45)
      |> min(1.25)

    {r, g, b} =
      cond do
        h < water_level - 3.0 -> tint.(water_deep, light)
        h < water_level -> tint.(water, light)
        h < water_level + 2.0 -> tint.(sand, light)
        h < 22.0 -> tint.(grass, light)
        h < 30.0 -> tint.(grass_dark, light)
        true -> tint.(stone, light)
      end

    <<r, g, b, 255>>
  end
  |> then(&Raster.from_rgba(wide, high, &1))

open_things =
  for {x, y} <- [
        {60, 80}, {120, 60}, {200, 110}, {260, 70}, {330, 120}, {410, 90},
        {470, 60}, {540, 110}, {610, 80}, {90, 220}, {170, 250}, {250, 210},
        {360, 240}, {430, 260}, {520, 220}, {600, 250}, {40, 320}, {300, 310}
      ],
      height.(x, y) > water_level + 3.0 do
    {:sprite, tree.(), %{position: {x, y - 24}}}
  end

open_rocks =
  for {x, y} <- [{150, 170}, {300, 140}, {490, 180}, {380, 320}, {620, 160}],
      height.(x, y) > water_level + 2.0,
      do: {:sprite, rock.(), %{position: {x, y - 8}}}

player = {330, 186}

open_ops = open_things ++ open_rocks ++ [{:sprite, figure.(), %{position: {elem(player, 0) - 6, elem(player, 1) - 20}}}]

stage_open = Render.render({wide, high}, open_ops, background: relief)

# The window that streams cells: the load radius, the keep radius, and the cell edges
# inside them. The player stands at the centre.
dashed_circle = fn raster, {cx, cy}, radius, colour ->
  Enum.reduce(0..719, raster, fn step, r ->
    angle = step * :math.pi() / 360.0
    x = round(cx + radius * :math.cos(angle))
    y = round(cy + radius * :math.sin(angle))
    if rem(step, 6) < 3, do: Shapes.fill_rect(r, {x, y}, {x, y}, colour), else: r
  end)
end

{p_x, p_y} = player

stage_open =
  stage_open
  |> then(&dashed_circle.(&1, {p_x, p_y}, 150, {0, 0, 0, 70}))
  |> then(&dashed_circle.(&1, {p_x, p_y}, 195, {0, 0, 0, 45}))

# cell edges, 64 map units, faint
stage_open =
  Enum.reduce(0..(div(wide, 64)), stage_open, fn column, r ->
    Shapes.line(r, {column * 64, 0}, {column * 64, high - 1}, {0, 0, 0, 22})
  end)

stage_open =
  Enum.reduce(0..(div(high, 64)), stage_open, fn row, r ->
    Shapes.line(r, {0, row * 64}, {wide - 1, row * 64}, {0, 0, 0, 22})
  end)

# The panel at the end of the simulated cells: a standing wall the map's edge stops
# movers at, drawn here as a band of stone with a lit top.
stage_open =
  Shapes.fill_rect(stage_open, {0, high - 24}, {wide - 1, high - 1}, stone_dark)

stage_open =
  Shapes.fill_rect(stage_open, {0, high - 24}, {wide - 1, high - 20}, stone)

stage_open =
  Enum.reduce(0..div(wide, 44), stage_open, fn joint, r ->
    x = joint * 44
    Shapes.fill_rect(r, {x, high - 24}, {x, high - 1}, {96, 96, 102, 255})
  end)

File.write!(
  Path.expand("../book/assets/stage-open.png", __DIR__),
  FrenchCurve.Png.encode(stage_open.width, stage_open.height, Raster.to_rgba_binary(stage_open))
)

IO.puts("wrote the three stage figures")
