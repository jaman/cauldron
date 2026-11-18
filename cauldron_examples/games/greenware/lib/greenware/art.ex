defmodule Greenware.Art do
  @moduledoc """
  Procedural placeholder art: the rooms of the Bake, its people, and the objects a
  scene points at. Everything is drawn from clay-coloured shapes and cached; the final
  sprites replace these functions.
  """

  alias Cauldron2D.Raster
  alias Greenware.Art.Draw, as: D
  alias Greenware.{Canvas, Palette}

  @width 1280
  @height 720

  @doc "A minimal atlas for the client contract; the game paints its own picture."
  def install_atlas do
    if Cauldron2D.Atlas.installed?(:greenware) do
      :greenware
    else
      Cauldron2D.Atlas.new(:greenware, tile: 16)
      |> Cauldron2D.Atlas.put(:void, Raster.new(16, 16, background: {18, 13, 10, 255}),
        glyph: "  ",
        color: {18, 13, 10}
      )
      |> Cauldron2D.Atlas.install()

      :greenware
    end
  end

  def width, do: @width
  def height, do: @height

  @doc "A background at the game's size, cached by name: the clay artwork when it is there, the drawn placeholder otherwise."
  def background(kind) do
    cached({:background, kind}, fn ->
      case png("bg_#{kind}.png") do
        nil -> build_background(kind) |> Raster.to_rgba_binary()
        raster -> Raster.to_rgba_binary(raster)
      end
    end)
  end

  @doc "A figure at its own size, cached by name."
  def figure(kind) do
    cached({:figure, kind}, fn -> png("fig_#{kind}.png") || build_figure(kind) end)
  end

  @doc "A scene prop at its own size, cached by name."
  def prop(kind) do
    cached({:prop, kind}, fn -> png("prop_#{kind}.png") || build_prop(kind) end)
  end

  defp png(name) do
    case :code.priv_dir(:greenware) do
      dir when is_list(dir) ->
        path = Path.join([dir, "art", name])

        if File.exists?(path) do
          case path |> File.read!() |> Linocut.Png.decode() do
            {:ok, raster} -> raster
            _ -> nil
          end
        end

      _ ->
        nil
    end
  end

  @doc "A small icon for a hub card, cached by name."
  def icon(kind), do: cached({:icon, kind}, fn -> build_icon(icon_prop(kind)) end)

  @doc "The icon of the mended thing, for a hub card that is done."
  def icon_mended(kind),
    do: cached({:icon_mended, kind}, fn -> build_icon_from(prop_mended(icon_prop(kind))) end)

  defp icon_prop(:key), do: :key
  defp icon_prop(:wing), do: :bird
  defp icon_prop(:bucket), do: :well
  defp icon_prop(:face), do: :mirror
  defp icon_prop(:music_box), do: :box
  defp icon_prop(:hub), do: :ferris
  defp icon_prop(:bridge), do: :chasm
  defp icon_prop(:sky), do: :kiln
  defp icon_prop(kind), do: kind

  @doc "A soft radial glow, white with alpha."
  def glow(radius), do: cached({:glow, radius}, fn -> build_glow(radius) end)

  @doc "A figure as an rgba binary tuple, so the painter never re-encodes it."
  def figure_binary(kind), do: binary({:figure_binary, kind}, fn -> figure(kind) end)

  @doc "A prop as an rgba binary tuple."
  def prop_binary(kind), do: binary({:prop_binary, kind}, fn -> prop(kind) end)

  @doc "The mended version of a prop, or the broken one when it has no mended art."
  def prop_mended(kind),
    do: cached({:prop_mended, kind}, fn -> png("prop_#{kind}_mended.png") || prop(kind) end)

  @doc "Whether a painted mended version of `kind` is on disk."
  def mended?(kind) do
    case :code.priv_dir(:greenware) do
      dir when is_list(dir) -> File.exists?(Path.join([dir, "art", "prop_#{kind}_mended.png"]))
      _ -> false
    end
  end

  def prop_mended_binary(kind),
    do: binary({:prop_mended_binary, kind}, fn -> prop_mended(kind) end)

  @doc "An icon as an rgba binary tuple."
  def icon_binary(kind), do: binary({:icon_binary, kind}, fn -> icon(kind) end)

  @doc "A glow as an rgba binary tuple."
  def glow_binary(radius), do: binary({:glow_binary, radius}, fn -> glow(radius) end)

  defp binary(key, fun) do
    cached(key, fn ->
      raster = fun.()
      {width, height} = Raster.dimensions(raster)
      {Raster.to_rgba_binary(raster), width, height}
    end)
  end

  defp cached(key, fun) do
    full = {__MODULE__, key}

    case :persistent_term.get(full, nil) do
      nil ->
        value = fun.()
        :persistent_term.put(full, value)
        value

      value ->
        value
    end
  end

  # -- backgrounds ---------------------------------------------------------

  defp build_background(:workshop) do
    base = Canvas.gradient(@width, @height, Palette.c(:umber), Palette.c(:soot))
    raster = Raster.from_rgba(@width, @height, base)

    raster
    |> fill({0, 300}, {640, 60}, Palette.c(:leather))
    |> fill({0, 296}, {640, 8}, Palette.c(:ink))
    |> back_wall()
    |> shelf(58)
    |> shelf(132)
    |> window({500, 88}, 54)
    |> hanging_tools()
    |> bench()
    |> grain(700, Palette.a(:bone, 0.06))
    |> Raster.finalize()
  end

  defp build_background(:garden) do
    base = Canvas.gradient(@width, @height, {78, 110, 92, 255}, {30, 52, 43, 255})
    raster = Raster.from_rgba(@width, @height, base)

    raster
    |> hills()
    |> fill({0, 292}, {640, 68}, {42, 63, 39, 255})
    |> leaves()
    |> well_bg()
    |> grain(900, Palette.a(:sage, 0.07))
    |> Raster.finalize()
  end

  defp build_background(:cellar) do
    base = Canvas.gradient(@width, @height, {31, 34, 38, 255}, {12, 13, 16, 255})
    raster = Raster.from_rgba(@width, @height, base)

    raster
    |> arches()
    |> fill({0, 300}, {640, 60}, {22, 24, 25, 255})
    |> cellar_shelves()
    |> puddles()
    |> grain(650, Palette.a(:bone, 0.05))
    |> Raster.finalize()
  end

  defp build_background(:fair) do
    base = Canvas.gradient(@width, @height, {86, 53, 78, 255}, {35, 26, 38, 255})
    raster = Raster.from_rgba(@width, @height, base)

    raster
    |> fair_sun()
    |> fill({0, 292}, {640, 68}, {38, 28, 35, 255})
    |> ferris_bg()
    |> tents()
    |> string_lights()
    |> grain(600, Palette.a(:amber, 0.08))
    |> Raster.finalize()
  end

  defp build_background(:kiln) do
    base = Canvas.gradient(@width, @height, {58, 50, 44, 255}, {18, 16, 15, 255})
    raster = Raster.from_rgba(@width, @height, base)

    raster
    |> ash_hills()
    |> fill({0, 300}, {640, 60}, {26, 23, 21, 255})
    |> kiln_bg()
    |> cracks()
    |> grain(850, Palette.a(:ember, 0.07))
    |> Raster.finalize()
  end

  defp build_background(:title) do
    build_background(:workshop)
  end

  defp build_background(_), do: build_background(:workshop)

  defp back_wall(raster) do
    raster
    |> fill({0, 0}, {640, 300}, {40, 28, 23, 255})
    |> fill({0, 0}, {640, 18}, {24, 16, 13, 255})
  end

  defp shelf(raster, y) do
    raster
    |> fill({24, y}, {590, 4}, {30, 20, 16, 255})
    |> fill({24, y + 4}, {590, 2}, {13, 9, 7, 255})
  end

  defp window(raster, {cx, cy}, radius) do
    raster
    |> D.fill_circle({cx, cy}, radius + 5, {25, 20, 18, 255})
    |> D.fill_circle({cx, cy}, radius, {48, 65, 67, 255})
    |> D.fill_circle({cx + 14, cy - 16}, 18, {73, 90, 86, 255})
    |> D.fill_circle({cx + 16, cy - 18}, 15, {96, 110, 96, 255})
    |> D.line({cx - radius, cy}, {cx + radius, cy}, {25, 20, 18, 255})
    |> D.line({cx, cy - radius}, {cx, cy + radius}, {25, 20, 18, 255})
  end

  defp hanging_tools(raster) do
    raster
    |> D.line({96, 20}, {96, 92}, {26, 18, 15, 255})
    |> fill({90, 92}, {12, 22}, {32, 22, 17, 255})
    |> D.line({142, 20}, {142, 78}, {26, 18, 15, 255})
    |> D.fill_polygon([{136, 78}, {148, 78}, {142, 96}], {38, 26, 19, 255})
    |> D.line({188, 20}, {188, 86}, {26, 18, 15, 255})
    |> D.fill_circle({188, 92}, 9, {35, 24, 18, 255})
    |> D.line({534, 20}, {534, 72}, {26, 18, 15, 255})
    |> fill({527, 72}, {14, 26}, {45, 31, 23, 255})
  end

  defp bench(raster) do
    raster
    |> fill({0, 300}, {640, 60}, {49, 33, 25, 255})
    |> fill({0, 300}, {640, 4}, {74, 50, 36, 255})
    |> fill({44, 318}, {20, 42}, {34, 22, 17, 255})
    |> fill({576, 318}, {20, 42}, {34, 22, 17, 255})
  end

  defp hills(raster) do
    raster
    |> D.fill_polygon(
      [
        {0, 250},
        {90, 186},
        {180, 236},
        {290, 170},
        {390, 232},
        {500, 190},
        {639, 250},
        {639, 359},
        {0, 359}
      ],
      {44, 72, 58, 255}
    )
    |> D.fill_polygon(
      [
        {0, 286},
        {120, 244},
        {240, 280},
        {360, 232},
        {520, 280},
        {639, 254},
        {639, 359},
        {0, 359}
      ],
      {35, 58, 46, 255}
    )
  end

  defp leaves(raster) do
    raster
    |> D.fill_polygon([{20, 320}, {52, 140}, {96, 320}], {52, 81, 48, 255})
    |> D.fill_polygon([{560, 330}, {592, 120}, {640, 330}], {46, 74, 44, 255})
    |> D.fill_polygon([{120, 340}, {144, 210}, {174, 340}], {58, 88, 52, 255})
    |> D.fill_circle({112, 176}, 22, {63, 97, 56, 255})
    |> D.fill_circle({586, 156}, 26, {63, 97, 56, 255})
  end

  defp well_bg(raster) do
    raster
    |> fill({430, 204}, {96, 10}, {62, 50, 40, 255})
    |> fill({438, 208}, {80, 8}, {28, 22, 19, 255})
  end

  defp arches(raster) do
    Enum.reduce([80, 240, 400, 560], raster, fn cx, acc ->
      acc
      |> D.fill_circle({cx, 154}, 54, {24, 24, 27, 255})
      |> fill({cx - 54, 154}, {108, 156}, {24, 24, 27, 255})
      |> D.fill_circle({cx, 154}, 42, {14, 15, 18, 255})
      |> fill({cx - 42, 154}, {84, 156}, {14, 15, 18, 255})
    end)
  end

  defp cellar_shelves(raster) do
    raster
    |> fill({30, 196}, {180, 5}, {34, 30, 27, 255})
    |> fill({30, 250}, {180, 5}, {34, 30, 27, 255})
    |> fill({430, 196}, {180, 5}, {34, 30, 27, 255})
    |> fill({430, 250}, {180, 5}, {34, 30, 27, 255})
  end

  defp puddles(raster) do
    raster
    |> D.fill_polygon([{90, 330}, {180, 320}, {230, 340}, {140, 352}], {30, 45, 47, 255})
    |> D.fill_polygon([{420, 338}, {520, 326}, {560, 348}, {450, 356}], {30, 45, 47, 255})
  end

  defp fair_sun(raster) do
    raster
    |> D.fill_circle({500, 96}, 44, {116, 75, 80, 255})
    |> D.fill_circle({500, 96}, 34, {148, 95, 82, 255})
  end

  defp ferris_bg(raster) do
    cx = 170
    cy = 180

    raster
    |> D.circle({cx, cy}, 120, {53, 42, 47, 255})
    |> then(fn acc ->
      Enum.reduce(0..11, acc, fn index, acc ->
        angle = index * :math.pi() / 6
        x = cx + round(118 * :math.cos(angle))
        y = cy + round(118 * :math.sin(angle))
        D.line(acc, {cx, cy}, {x, y}, {53, 42, 47, 255})
      end)
    end)
    |> fill({cx - 4, cy}, {8, 170}, {53, 42, 47, 255})
  end

  defp tents(raster) do
    raster
    |> D.fill_polygon([{330, 330}, {400, 220}, {470, 330}], {97, 52, 55, 255})
    |> D.fill_polygon([{430, 330}, {500, 244}, {570, 330}], {73, 50, 63, 255})
    |> fill({392, 292}, {24, 38}, {44, 28, 30, 255})
  end

  defp string_lights(raster) do
    Enum.reduce(0..10, raster, fn index, acc ->
      x = 300 + index * 34
      y = 140 + round(18 * :math.sin(index * 0.9))
      D.fill_circle(acc, {x, y}, 3, {222, 168, 91, 255})
    end)
    |> D.line({295, 140}, {640, 150}, {55, 40, 45, 255})
  end

  defp ash_hills(raster) do
    raster
    |> D.fill_polygon(
      [
        {0, 260},
        {120, 206},
        {260, 256},
        {400, 198},
        {540, 258},
        {639, 224},
        {639, 359},
        {0, 359}
      ],
      {39, 34, 30, 255}
    )
  end

  defp kiln_bg(raster) do
    raster
    |> fill({430, 126}, {150, 176}, {42, 35, 29, 255})
    |> D.fill_circle({505, 230}, 54, {28, 23, 20, 255})
    |> D.fill_circle({505, 230}, 34, {96, 47, 31, 255})
    |> D.fill_circle({505, 236}, 22, {219, 112, 58, 255})
    |> fill({500, 40}, {30, 90}, {37, 31, 27, 255})
    |> D.fill_circle({515, 36}, 24, {31, 28, 26, 255})
  end

  defp cracks(raster) do
    raster
    |> D.line({40, 330}, {120, 316}, {22, 18, 16, 255})
    |> D.line({120, 316}, {180, 338}, {22, 18, 16, 255})
    |> D.line({240, 350}, {300, 324}, {22, 18, 16, 255})
    |> D.line({300, 324}, {334, 352}, {22, 18, 16, 255})
  end

  defp grain(raster, count, colour) do
    Enum.reduce(1..count, raster, fn index, acc ->
      x = :erlang.phash2({:gx, index}, 640)
      y = :erlang.phash2({:gy, index}, 360)
      alpha = :erlang.phash2({:ga, index}, 100) / 100

      if alpha > 0.2,
        do:
          Raster.put_pixel(acc, x * 2, y * 2, put_elem(colour, 3, round(elem(colour, 3) * alpha))),
        else: acc
    end)
  end

  # -- figures -------------------------------------------------------------

  defp build_figure(:greenware) do
    base = Palette.c(:terracotta)
    shadow = Palette.shade(base, -0.35)
    light = Palette.shade(base, 0.18)

    new_raster(64, 96)
    |> blob({32, 70}, 22, 28, shadow)
    |> blob({30, 68}, 21, 26, base)
    |> blob({22, 62}, 8, 11, light)
    |> blob({32, 30}, 13, 14, base)
    |> blob({31, 29}, 12, 12, light)
    |> D.fill_circle({32, 29}, 13, base)
    |> D.fill_circle({32, 27}, 10, light)
    |> arm({23, 58}, {14, 76}, 4, base)
    |> arm({41, 58}, {50, 76}, 4, base)
    |> fill({27, 58}, {10, 7}, {178, 135, 78, 255})
    |> fill({31, 59}, {2, 5}, {86, 62, 34, 255})
    |> D.fill_circle({30, 28}, 2, {55, 38, 28, 255})
    |> D.fill_circle({35, 28}, 2, {55, 38, 28, 255})
    |> Raster.finalize()
  end

  defp build_figure(:cat) do
    black = {34, 28, 27, 255}
    dark = {20, 17, 17, 255}
    amber = {214, 156, 76, 255}

    new_raster(56, 48)
    |> blob({28, 34}, 17, 10, black)
    |> blob({28, 32}, 16, 9, black)
    |> D.fill_circle({28, 20}, 10, black)
    |> D.fill_polygon([{20, 14}, {22, 4}, {28, 11}], black)
    |> D.fill_polygon([{36, 14}, {34, 4}, {28, 11}], black)
    |> D.fill_circle({24, 20}, 2, amber)
    |> D.fill_circle({32, 20}, 2, amber)
    |> D.line({26, 26}, {30, 26}, dark)
    |> D.line({44, 34}, {52, 24}, black)
    |> D.line({52, 24}, {54, 30}, black)
    |> fill({24, 40}, {4, 5}, dark)
    |> fill({30, 40}, {4, 5}, dark)
    |> Raster.finalize()
  end

  defp build_figure(:green_man) do
    green = Palette.c(:moss)
    light = Palette.c(:leaf)
    dark = Palette.shade(green, -0.35)

    new_raster(72, 116)
    |> blob({36, 82}, 20, 32, dark)
    |> blob({35, 80}, 18, 30, green)
    |> D.fill_circle({36, 32}, 15, green)
    |> D.fill_circle({34, 30}, 12, light)
    |> D.fill_polygon([{22, 24}, {26, 8}, {34, 20}], light)
    |> D.fill_polygon([{50, 24}, {46, 8}, {38, 20}], light)
    |> arm({20, 68}, {6, 88}, 5, green)
    |> arm({52, 68}, {66, 88}, 5, green)
    |> D.fill_circle({30, 32}, 2, dark)
    |> D.fill_circle({42, 32}, 2, dark)
    |> D.line({30, 39}, {42, 39}, dark)
    |> Raster.finalize()
  end

  defp build_figure(:boy) do
    paper = {206, 188, 154, 255}
    ink = {55, 42, 34, 255}
    line = {123, 91, 63, 255}

    new_raster(48, 88)
    |> D.fill_polygon([{9, 84}, {24, 8}, {40, 84}], paper)
    |> D.fill_circle({24, 18}, 12, paper)
    |> D.circle({24, 18}, 12, line)
    |> D.fill_circle({20, 17}, 1, ink)
    |> D.fill_circle({28, 17}, 1, ink)
    |> D.line({20, 24}, {28, 24}, ink)
    |> D.line({9, 84}, {16, 48}, line)
    |> D.line({39, 84}, {32, 48}, line)
    |> Raster.finalize()
  end

  defp build_figure(:choir) do
    plate = {219, 204, 172, 255}
    ink = {81, 66, 52, 255}

    new_raster(72, 64)
    |> D.fill_polygon([{10, 54}, {58, 54}, {62, 48}, {14, 42}], plate)
    |> D.fill_polygon([{8, 40}, {60, 42}, {64, 34}, {12, 28}], {198, 180, 148, 255})
    |> D.fill_polygon([{12, 26}, {54, 28}, {58, 20}, {16, 14}], plate)
    |> D.line({22, 20}, {28, 26}, ink)
    |> D.line({38, 24}, {34, 30}, ink)
    |> D.line({20, 44}, {28, 50}, ink)
    |> D.line({42, 46}, {46, 40}, ink)
    |> Raster.finalize()
  end

  defp build_figure(:potter) do
    robe = {58, 44, 38, 255}
    dark = {29, 23, 21, 255}
    ember = {214, 126, 62, 255}

    new_raster(76, 120)
    |> D.fill_polygon([{16, 116}, {28, 40}, {48, 40}, {60, 116}], robe)
    |> D.fill_polygon([{26, 46}, {38, 8}, {50, 46}], robe)
    |> D.fill_circle({38, 40}, 14, dark)
    |> D.fill_circle({33, 38}, 2, ember)
    |> D.fill_circle({43, 38}, 2, ember)
    |> D.line({33, 54}, {43, 54}, dark)
    |> Raster.finalize()
  end

  defp build_figure(_kind), do: build_figure(:greenware)

  # -- props ---------------------------------------------------------------

  defp build_prop(:cup) do
    clay = Palette.c(:terracotta)

    new_raster(72, 64)
    |> D.fill_polygon([{12, 12}, {56, 12}, {48, 56}, {20, 56}], clay)
    |> D.fill_polygon([{18, 12}, {50, 12}, {44, 48}, {24, 48}], {86, 44, 30, 255})
    |> D.circle({60, 30}, 10, clay)
    |> D.line({55, 24}, {55, 40}, clay)
    |> D.line({28, 12}, {32, 30}, {80, 42, 29, 255})
    |> Raster.finalize()
  end

  defp build_prop(:key) do
    clay = Palette.c(:ochre)

    new_raster(96, 48)
    |> D.fill_circle({18, 24}, 10, clay)
    |> D.fill_rect({28, 21}, {78, 6}, clay)
    |> D.fill_rect({58, 27}, {6, 12}, clay)
    |> D.fill_rect({70, 27}, {6, 14}, clay)
    |> Raster.finalize()
  end

  defp build_prop(:door) do
    wood = {63, 43, 31, 255}

    new_raster(120, 180)
    |> fill({0, 0}, {120, 180}, wood)
    |> fill({10, 10}, {99, 70}, {53, 36, 26, 255})
    |> fill({10, 92}, {99, 76}, {53, 36, 26, 255})
    |> D.fill_circle({100, 92}, 4, {185, 143, 72, 255})
    |> Raster.finalize()
  end

  defp build_prop(:bucket) do
    clay = Palette.c(:terracotta)

    new_raster(72, 64)
    |> D.fill_polygon([{12, 14}, {60, 14}, {52, 54}, {20, 54}], clay)
    |> D.fill_polygon([{18, 14}, {54, 14}, {46, 46}, {26, 46}], {86, 44, 30, 255})
    |> D.line({12, 14}, {60, 14}, {186, 132, 82, 255})
    |> D.line({20, 54}, {52, 54}, {78, 40, 28, 255})
    |> Raster.finalize()
  end

  defp build_prop(:well) do
    stone = {72, 66, 55, 255}

    new_raster(120, 96)
    |> fill({8, 32}, {104, 56}, stone)
    |> ellipse({60, 32}, 52, 12, {92, 84, 70, 255})
    |> ellipse({60, 34}, 36, 8, {27, 24, 21, 255})
    |> D.line({20, 32}, {20, 4}, {45, 36, 27, 255})
    |> D.line({100, 32}, {100, 4}, {45, 36, 27, 255})
    |> D.line({18, 6}, {102, 6}, {45, 36, 27, 255})
    |> Raster.finalize()
  end

  defp build_prop(:arm) do
    clay = Palette.c(:leather)

    new_raster(120, 70)
    |> ellipse({40, 35}, 22, 12, clay)
    |> ellipse({80, 32}, 18, 10, clay)
    |> D.fill_circle({102, 30}, 12, clay)
    |> D.line({58, 34}, {64, 33}, {60, 40, 30, 255})
    |> Raster.finalize()
  end

  defp build_prop(:dam) do
    stone = Palette.c(:slate)

    new_raster(180, 110)
    |> fill({0, 0}, {180, 110}, stone)
    |> fill({0, 0}, {179, 8}, {88, 98, 96, 255})
    |> D.line({88, 12}, {78, 54}, {26, 29, 30, 255})
    |> D.line({78, 54}, {96, 82}, {26, 29, 30, 255})
    |> Raster.finalize()
  end

  defp build_prop(:lamp) do
    clay = Palette.c(:ochre)

    new_raster(96, 88)
    |> ellipse({44, 50}, 24, 20, clay)
    |> fill({32, 66}, {24, 8}, clay)
    |> D.fill_polygon([{64, 46}, {88, 34}, {92, 40}, {68, 54}], clay)
    |> D.circle({26, 46}, 14, clay)
    |> D.fill_circle({44, 50}, 5, {78, 48, 28, 255})
    |> Raster.finalize()
  end

  defp build_prop(:plate) do
    clay = Palette.c(:bone)

    new_raster(120, 100)
    |> ellipse({60, 50}, 54, 36, clay)
    |> ellipse({60, 50}, 42, 26, {190, 176, 148, 255})
    |> D.line({24, 34}, {44, 62}, {93, 78, 62, 255})
    |> D.line({76, 30}, {66, 64}, {93, 78, 62, 255})
    |> D.line({40, 66}, {82, 70}, {93, 78, 62, 255})
    |> Raster.finalize()
  end

  defp build_prop(:doll) do
    clay = Palette.c(:rose)

    new_raster(64, 120)
    |> D.fill_circle({32, 20}, 14, clay)
    |> fill({24, 32}, {16, 38}, clay)
    |> D.line({24, 40}, {10, 62}, clay)
    |> D.line({40, 40}, {54, 62}, clay)
    |> D.line({30, 70}, {28, 104}, clay)
    |> Raster.finalize()
  end

  defp build_prop(:ferris) do
    wheel = {112, 92, 54, 255}

    raster =
      new_raster(220, 220)
      |> D.circle({110, 96}, 96, wheel)
      |> then(fn acc ->
        Enum.reduce(0..11, acc, fn index, acc ->
          angle = index * :math.pi() / 6
          x = 110 + round(94 * :math.cos(angle))
          y = 96 + round(94 * :math.sin(angle))
          D.line(acc, {110, 96}, {x, y}, wheel)
        end)
      end)

    raster
    |> fill({106, 96}, {8, 120}, wheel)
    |> Raster.finalize()
  end

  defp build_prop(:mirror) do
    frame = Palette.c(:brass)
    glass = {67, 78, 78, 255}

    new_raster(110, 140)
    |> ellipse({55, 70}, 48, 62, frame)
    |> ellipse({55, 70}, 40, 54, glass)
    |> D.line({30, 40}, {42, 28}, {112, 128, 116, 255})
    |> D.line({66, 30}, {78, 44}, {112, 128, 116, 255})
    |> Raster.finalize()
  end

  defp build_prop(:box) do
    wood = {82, 52, 38, 255}

    new_raster(120, 90)
    |> fill({8, 36}, {104, 48}, wood)
    |> fill({8, 30}, {104, 8}, {108, 71, 47, 255})
    |> ellipse({60, 22}, 22, 10, {177, 136, 72, 255})
    |> fill({30, 20}, {60, 4}, {59, 42, 31, 255})
    |> Raster.finalize()
  end

  defp build_prop(:chasm) do
    new_raster(240, 110)
    |> fill({0, 0}, {240, 110}, {28, 23, 20, 255})
    |> D.fill_polygon([{0, 0}, {100, 0}, {84, 34}, {40, 46}, {0, 40}], {43, 36, 30, 255})
    |> D.fill_polygon([{140, 0}, {239, 0}, {239, 40}, {196, 46}, {154, 32}], {43, 36, 30, 255})
    |> D.fill_polygon([{100, 12}, {140, 12}, {130, 28}, {110, 28}], {66, 38, 26, 255})
    |> Raster.finalize()
  end

  defp build_prop(:heart) do
    clay = Palette.c(:terracotta)

    new_raster(100, 100)
    |> D.fill_circle({36, 34}, 22, clay)
    |> D.fill_circle({64, 34}, 22, clay)
    |> D.fill_polygon([{14, 34}, {86, 34}, {50, 90}], clay)
    |> D.line({50, 16}, {46, 44}, {75, 38, 27, 255})
    |> D.line({46, 44}, {54, 66}, {75, 38, 27, 255})
    |> Raster.finalize()
  end

  defp build_prop(:kiln) do
    new_raster(160, 200)
    |> fill({10, 20}, {140, 180}, {48, 39, 32, 255})
    |> D.fill_circle({80, 130}, 46, {32, 26, 22, 255})
    |> D.fill_circle({80, 134}, 32, {104, 53, 33, 255})
    |> D.fill_circle({80, 140}, 18, {223, 125, 66, 255})
    |> fill({34, 0}, {26, 30}, {43, 35, 29, 255})
    |> Raster.finalize()
  end

  defp build_prop(:bird) do
    new_raster(80, 60)
    |> ellipse({36, 34}, 24, 14, {112, 95, 78, 255})
    |> D.fill_circle({58, 24}, 9, {112, 95, 78, 255})
    |> D.fill_polygon([{36, 20}, {72, 6}, {52, 34}], {89, 74, 61, 255})
    |> D.line({40, 30}, {52, 38}, {70, 56, 44, 255})
    |> D.fill_circle({61, 22}, 2, {22, 18, 16, 255})
    |> Raster.finalize()
  end

  defp build_prop(_kind), do: build_prop(:cup)

  # -- icons ---------------------------------------------------------------

  defp build_icon(kind), do: build_icon_from(prop(kind))

  defp build_icon_from(prop) do
    {width, height} = Raster.dimensions(prop)
    scale = min(96 / width, 96 / height)
    new_width = max(1, round(width * scale))
    new_height = max(1, round(height * scale))
    # nearest sample into a small raster
    for y <- 0..(new_height - 1),
        x <- 0..(new_width - 1),
        reduce: Raster.new(new_width, new_height) do
      acc ->
        source = {min(width - 1, floor(x / scale)), min(height - 1, floor(y / scale))}
        Raster.put_pixel(acc, x, y, Raster.get_pixel(prop, elem(source, 0), elem(source, 1)))
    end
  end

  # -- helpers -------------------------------------------------------------

  defp blob(raster, {cx, cy}, rx, ry, colour) do
    points =
      for index <- 0..31 do
        angle = index * :math.pi() / 16
        wobble = 1.0 + 0.06 * :math.sin(index * 2.7)
        {cx + rx * :math.cos(angle) * wobble, cy + ry * :math.sin(angle) * wobble}
      end

    D.fill_polygon(raster, points, colour)
  end

  defp arm(raster, {x1, y1}, {x2, y2}, radius, colour) do
    raster
    |> D.line({x1, y1}, {x2, y2}, colour)
    |> then(fn acc ->
      Enum.reduce(0..8, acc, fn step, acc ->
        t = step / 8
        x = round(x1 + (x2 - x1) * t)
        y = round(y1 + (y2 - y1) * t)
        D.fill_circle(acc, {x, y}, radius, colour)
      end)
    end)
  end

  defp build_glow(radius) do
    actual = radius * 2
    size = actual * 2 + 1

    for y <- 0..(actual * 2), x <- 0..(actual * 2), reduce: Raster.new(size, size) do
      acc ->
        dx = x - actual
        dy = y - actual
        distance = :math.sqrt(dx * dx + dy * dy)
        alpha = max(0.0, 1.0 - distance / actual) ** 2
        Raster.put_pixel(acc, x, y, {255, 232, 178, round(alpha * 255)})
    end
  end

  defp new_raster(width, height), do: Raster.new(width * 2, height * 2)

  defp fill(raster, {x, y}, {width, height}, colour),
    do: D.fill_rect(raster, {x, y}, {x + width - 1, y + height - 1}, colour)

  defp ellipse(raster, {cx, cy}, rx, ry, colour) do
    points =
      for index <- 0..47 do
        angle = index * :math.pi() / 24
        {cx + rx * :math.cos(angle), cy + ry * :math.sin(angle)}
      end

    D.fill_polygon(raster, points, colour)
  end
end
