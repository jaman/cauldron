defmodule Beast.Art do
  @moduledoc """
  The beast's pictures in the atlas `:beast`, from `priv/art`: what the image model drew
  and `mix cauldron.assets` finished — the beast in its poses and its run, punch, kick and low sweep
  (cut from video), the creatures, the four bosses, each region's painted layers and
  rock, the title painting — the hand-drawn missiles, ledges, spikes, doors, gates,
  stones, fruit, key, hearts and effects, and the font `:pixel`.

  As the atlas is installed:

    * the archer's pictures, which the image model drew facing right, are mirrored, so
      every creature's picture faces left as `Beast.Scene` draws them
    * `hero_run` becomes an animation of its eight frames
    * `hero_punch_<n>`, `hero_kick_<n>` and `hero_sweep_<n>`, `n` from `1` to `5`, are cut
      from their strips
    * `hero`, the beast standing, is the guard stance that opens its punch
      (`hero_punch_1`), so it faces the way every other picture of the beast faces
    * `<rock>_<n>`, `n` from `0` to `15`, are cut from each region's rock
    * the beast's, the creatures' and the bosses' pictures get a one-pixel dark outline
      around them, so they stand out from any backdrop
    * `<layer>_tile` is each painted layer beside its own mirror image, so it repeats
      along the region without a seam; the layers are muted and darkened, the sky most
      and the near layer least, so the actors in front of them read clearly, and the far
      and near layers stand on solid ground of their own bottom's colour as tall again
      as themselves, so they never end in mid-air over a pit

  A picture the build has not made yet is left out; `fallback/2` gives what to draw in
  its place. Two tints shade a mover: `:flash`, a struck thing's white, and `:hurt`.
  """

  alias Cauldron2D.Atlas
  alias Cauldron2D.Raster

  @name :beast
  @tile 16
  @strips [hero_punch: 5, hero_kick: 5, hero_sweep: 5]
  @drawn_facing_right [:archer, :archer_draw]
  @movers ~w(hero_run hero_punch hero_kick hero_sweep hero_charge hero_duck hero_hurt hero_jump
              hero_roll crawler bat goblin goblin_raise archer archer_draw troll troll_raise mage
              mage_cast wyrm spirit spirit_open)a
  @outline <<14, 6, 8, 255>>
  @haze {12, 8, 16}
  @desaturate 0.4
  @hazes %{sky: 0.45, far: 0.35, near: 0.2}
  @rocks [:rock_plain, :rock_caverns, :rock_tree, :rock_castle]
  @layers [
    :plain_sky,
    :plain_far,
    :plain_near,
    :caverns_sky,
    :caverns_far,
    :tree_sky,
    :tree_far,
    :castle_sky,
    :castle_far
  ]

  @doc "The atlas name."
  @spec name() :: Atlas.name()
  def name, do: @name

  @doc "Load the directory, make the derived pictures, and install the atlas, once; returns its name."
  @spec install() :: Atlas.name()
  def install do
    if Atlas.installed?(@name) do
      @name
    else
      {:ok, atlas} =
        Atlas.load(@name, Path.join(:code.priv_dir(:beast), "art"),
          tile: @tile,
          void: {12, 6, 10},
          fonts: [pixel: [file: "font.png", cell: {8, 8}, chars: chars(), space: 3]]
        )

      atlas
      |> faced()
      |> outline_movers()
      |> run()
      |> strips()
      |> stance()
      |> rocks()
      |> layers()
      |> Atlas.tint(:flash, &flash/1)
      |> Atlas.tint(:hurt, &hurt/1)
      |> Atlas.install()
    end
  end

  @doc "`art` when the atlas has it, else `fallback`."
  @spec fallback(atom(), atom()) :: atom()
  def fallback(art, fallback) do
    if Map.has_key?(Atlas.fetch(@name).entries, art), do: art, else: fallback
  end

  defp chars, do: " !%'()*+,-./0123456789:<>?ABCDEFGHIJKLMNOPQRSTUVWXYZ_x"

  defp picture(atlas, art),
    do: atlas |> Atlas.entry(art) |> Map.fetch!(:sprite) |> Map.fetch!(:raster)

  defp present?(atlas, art), do: Map.has_key?(atlas.entries, art)

  defp faced(atlas) do
    Enum.reduce(@drawn_facing_right, atlas, fn art, acc ->
      if present?(acc, art) do
        entry = Atlas.entry(acc, art)

        Atlas.put(acc, art, Cauldron2D.Picture.flip(picture(acc, art), :horizontal),
          glyph: entry.glyph,
          color: entry.color
        )
      else
        acc
      end
    end)
  end

  defp outline_movers(atlas) do
    Enum.reduce(@movers, atlas, fn art, acc ->
      if present?(acc, art) do
        entry = Atlas.entry(acc, art)
        Atlas.put(acc, art, outlined(picture(acc, art)), glyph: entry.glyph, color: entry.color)
      else
        acc
      end
    end)
  end

  defp run(atlas) do
    if present?(atlas, :hero_run) do
      strip = picture(atlas, :hero_run)

      Atlas.put(
        atlas,
        :hero_run,
        Cauldron2D.Picture.frames(strip, {div(strip.width, 8), strip.height}),
        fps: 12,
        glyph: "B ",
        color: {150, 170, 140}
      )
    else
      atlas
    end
  end

  defp strips(atlas) do
    Enum.reduce(@strips, atlas, fn {art, count}, acc ->
      if present?(acc, art), do: cut_strip(acc, art, count), else: acc
    end)
  end

  defp stance(atlas) do
    if present?(atlas, :hero_punch_1),
      do:
        Atlas.put(atlas, :hero, picture(atlas, :hero_punch_1),
          glyph: "B ",
          color: {150, 170, 140}
        ),
      else: atlas
  end

  defp cut_strip(atlas, art, count) do
    strip = picture(atlas, art)

    strip
    |> Cauldron2D.Picture.frames({div(strip.width, count), strip.height})
    |> Enum.with_index(1)
    |> Enum.reduce(atlas, fn {frame, n}, acc ->
      Atlas.put(acc, :"#{art}_#{n}", frame, glyph: "B ", color: {150, 170, 140})
    end)
  end

  defp rocks(atlas), do: Enum.reduce(@rocks, atlas, &rock/2)

  defp rock(rock, atlas) do
    if present?(atlas, rock), do: rock_tiles(atlas, rock, picture(atlas, rock)), else: atlas
  end

  defp rock_tiles(atlas, rock, raster) do
    Enum.reduce(0..15, atlas, fn n, acc ->
      Atlas.put(
        acc,
        :"#{rock}_#{n}",
        Raster.crop(raster, {rem(n, 4) * @tile, div(n, 4) * @tile}, {@tile, @tile}),
        glyph: "##",
        color: Atlas.entry(acc, rock).color
      )
    end)
  end

  defp layers(atlas) do
    Enum.reduce(@layers, atlas, fn layer, acc ->
      if present?(acc, layer),
        do:
          Atlas.put(acc, :"#{layer}_tile", mirrored(backdrop(layer, picture(acc, layer))),
            glyph: "  "
          ),
        else: acc
    end)
  end

  defp backdrop(layer, raster) do
    depth =
      layer |> Atom.to_string() |> String.split("_") |> List.last() |> String.to_existing_atom()

    hazed = hazed(raster, Map.fetch!(@hazes, depth))
    if depth == :sky, do: hazed, else: grounded(hazed)
  end

  defp mirrored(%{width: width, height: height} = raster) do
    flipped = Raster.to_rgba_binary(Cauldron2D.Picture.flip(raster, :horizontal))
    source = Raster.to_rgba_binary(raster)

    rows =
      for y <- 0..(height - 1),
          do: [
            binary_part(source, y * width * 4, width * 4),
            binary_part(flipped, y * width * 4, width * 4)
          ]

    Raster.from_rgba(width * 2, height, IO.iodata_to_binary(rows))
  end

  defp outlined(%{width: width, height: height} = raster) do
    rgba = Raster.to_rgba_binary(raster)
    solid = for <<_r, _g, _b, a <- rgba>>, into: <<>>, do: <<if(a > 0, do: 1, else: 0)>>
    mask = {solid, width, height}

    pixels =
      for y <- 0..(height - 1),
          x <- 0..(width - 1),
          into: <<>>,
          do: outlined_pixel(rgba, mask, x, y)

    Raster.from_rgba(width, height, pixels)
  end

  defp outlined_pixel(rgba, {_solid, width, _height} = mask, x, y) do
    cond do
      solid?(mask, x, y) -> binary_part(rgba, (y * width + x) * 4, 4)
      edge?(mask, x, y) -> @outline
      true -> <<0, 0, 0, 0>>
    end
  end

  defp edge?(mask, x, y) do
    solid?(mask, x - 1, y) or solid?(mask, x + 1, y) or solid?(mask, x, y - 1) or
      solid?(mask, x, y + 1)
  end

  defp solid?({solid, width, height}, x, y)
       when x >= 0 and y >= 0 and x < width and y < height,
       do: :binary.at(solid, y * width + x) == 1

  defp solid?(_mask, _x, _y), do: false

  defp hazed(%{width: width, height: height} = raster, amount) do
    {hr, hg, hb} = @haze

    pixels =
      for <<r, g, b, a <- Raster.to_rgba_binary(raster)>>, into: <<>> do
        grey = (r * 77 + g * 150 + b * 29) / 256

        <<toward(r, grey, hr, amount), toward(g, grey, hg, amount), toward(b, grey, hb, amount),
          a>>
      end

    Raster.from_rgba(width, height, pixels)
  end

  defp toward(channel, grey, haze, amount) do
    muted = channel + (grey - channel) * @desaturate
    round(muted * (1 - amount) + haze * amount)
  end

  defp grounded(%{width: width, height: height} = raster) do
    rgba = Raster.to_rgba_binary(raster)
    bottom = binary_part(rgba, (height - 4) * width * 4, 4 * width * 4)
    opaque = for <<r, g, b, a <- bottom>>, a > 0, do: {r, g, b}
    count = max(1, length(opaque))

    {r, g, b} =
      Enum.reduce(opaque, {0, 0, 0}, fn {r, g, b}, {sr, sg, sb} -> {sr + r, sg + g, sb + b} end)

    fill = <<round(r / count * 0.7), round(g / count * 0.7), round(b / count * 0.7), 255>>
    Raster.from_rgba(width, height * 2, rgba <> :binary.copy(fill, width * height))
  end

  defp flash({r, g, b, a}), do: {div(r + 255 * 3, 4), div(g + 255 * 3, 4), div(b + 255 * 3, 4), a}
  defp hurt({r, g, b, a}), do: {min(255, r + 110), div(g, 2), div(b, 2), a}
end
