defmodule Cauldron2D.Net.Atlas do
  @moduledoc """
  A `Cauldron2D.Atlas` as a client that draws scenes itself needs it: every picture —
  each art's frames at their own size, its faces and its poses, each font's glyphs and
  their white silhouettes — packed onto one PNG, and an index of where each sits with
  what the drawing reads from the art.

      atlas = Cauldron2D.Net.Atlas.cached(:my_game)
      Cauldron2D.Net.Atlas.index(atlas, "/play/atlas-full.png")

  ## The index

    * `url`, `tile`, `void` (`#rrggbb`), `width`, `height` — the sheet
    * `arts` — by name (`Cauldron2D.Net.Scene.Items.art_name/1`): `%{frames, fps, size,
      height, faces, poses, stand, eye}`, a rectangle `[x, y, width, height]` on the
      sheet for each frame, each face by name, and each pose's frames by name
    * `fonts` — by name: `%{height, line, spacing, fallback, upcase, glyphs, white}`,
      `glyphs` and `white` by character as `[x, y, width, height, advance]`
    * `label_font` — the built-in label font's glyphs by character as rows of `#` and `.`, with
      its `advance` and `height`, for scene labels
    * `tints` — the atlas's tint names
    * `tallest` — how tall the tallest art stands, in pixels (`Cauldron2D.Atlas.tallest/1`)

  `tinted/3` is an art's pictures through one of the atlas's tints, a PNG and the same
  shape of index, for a client to draw tinted cells and movers with. `tinted_cell/4` is
  a tinted cell's base and tile-sized overlays blended and then tinted, every combination
  of their frames, for a client to draw such a cell with.
  """

  alias Cauldron2D.{Atlas, Blend}
  alias Cauldron2D.Net.Scene.Items
  alias Cauldron2D.Raster
  alias FrenchCurve.Png

  @width 1024

  @type t :: %{index: map(), png: binary()}

  @doc "The packed sheet and index of `atlas`."
  @spec build(Atlas.t() | Atlas.name()) :: t()
  def build(atlas) do
    atlas = Atlas.fetch(atlas)
    pictures = pictures(atlas)

    {places, {width, height}} =
      pack(Enum.map(pictures, fn {key, raster} -> {key, Raster.dimensions(raster)} end))

    sheet = paint(pictures, places, {width, height})
    rect = fn key -> Map.fetch!(places, key) end
    {r, g, b} = atlas.void

    index = %{
      tile: atlas.tile,
      void: "#" <> Base.encode16(<<r, g, b>>, case: :lower),
      width: width,
      height: height,
      arts:
        Map.new(atlas.entries, fn {art, entry} ->
          {Items.art_name(art), art_index(art, entry, rect)}
        end),
      fonts:
        Map.new(atlas.fonts, fn {name, kept} ->
          {Atom.to_string(name), font_index(name, kept, rect)}
        end),
      label_font: label_font(),
      tallest: Cauldron2D.Atlas.tallest(atlas),
      tints: Enum.map(Map.keys(atlas.tints), &Atom.to_string/1)
    }

    %{index: index, png: Png.encode(width, height, Raster.to_rgba_binary(sheet))}
  end

  @doc "The built atlas for the installed atlas `name`, built on first use and again when the atlas changes."
  @spec cached(Atlas.name()) :: t()
  def cached(name) when is_atom(name) do
    atlas = Atlas.fetch(name)

    case :persistent_term.get({__MODULE__, name}, nil) do
      {^atlas, built} ->
        built

      _stale ->
        built = build(atlas)
        :persistent_term.put({__MODULE__, name}, {atlas, built})
        built
    end
  end

  @doc "The index a client reads, with the sheet at `url`."
  @spec index(t(), String.t()) :: map()
  def index(built, url), do: Map.put(built.index, :url, url)

  @doc """
  The art named `name` through tint `tint`: `%{index, png}`, its own sheet and an index
  of its frames, faces and poses as the atlas index gives an art's; `nil` for an art or
  tint the atlas lacks.
  """
  @spec tinted(Atlas.name(), String.t(), String.t()) :: t() | nil
  def tinted(name, art_name, tint_name) do
    atlas = Atlas.fetch(name)
    arts = Items.arts(atlas)
    tint = Enum.find(Map.keys(atlas.tints), &(Atom.to_string(&1) == tint_name))

    with {:ok, art} <- Map.fetch(arts, art_name), true <- tint != nil do
      fun = Map.fetch!(atlas.tints, tint)
      entry = Atlas.entry(atlas, art)
      pictures = for {key, raster} <- art_pictures(art, entry), do: {key, recoloured(raster, fun)}

      {places, {width, height}} =
        pack(Enum.map(pictures, fn {key, raster} -> {key, Raster.dimensions(raster)} end))

      sheet = paint(pictures, places, {width, height})

      %{
        index: art_index(art, entry, &Map.fetch!(places, &1)),
        png: Png.encode(width, height, Raster.to_rgba_binary(sheet))
      }
    else
      _missing -> nil
    end
  end

  @doc """
  The cell of base `base_name` under the tile-sized overlays `overlay_names`, blended
  and then shaded through tint `tint_name` as `Cauldron2D.Surface` composes a tinted
  cell, at full tile size: `%{index, png}`, one picture for every combination of the
  arts' frames, or `nil` for an art or tint the atlas lacks or an overlay that is not
  the tile's size.

  `index` is `%{counts, frames}`: `counts` the number of frames of the base and of each
  overlay in order, and `frames` a rectangle `[x, y, width, height]` on the PNG for each
  combination, the last art's frame changing fastest, so the picture for frame indices
  `[i0, i1, ..., in]` is at `((i0 * c1 + i1) * c2 + ...) * cn + in`.
  """
  @spec tinted_cell(Atlas.name(), String.t(), [String.t()], String.t()) :: t() | nil
  def tinted_cell(name, base_name, overlay_names, tint_name) do
    atlas = Atlas.fetch(name)
    arts = Items.arts(atlas)
    tint = Enum.find(Map.keys(atlas.tints), &(Atom.to_string(&1) == tint_name))

    with {:ok, base} <- Map.fetch(arts, base_name),
         {:ok, overlays} <- fetch_all(arts, overlay_names),
         true <- tint != nil,
         true <- Enum.all?(overlays, &(Atlas.entry(atlas, &1).size == {atlas.tile, atlas.tile})) do
      layers = Enum.map([base | overlays], &Atlas.entry(atlas, &1).frames)
      fun = Map.fetch!(atlas.tints, tint)

      pictures =
        layers
        |> combinations()
        |> Enum.with_index()
        |> Enum.map(fn {sprites, i} -> {i, blended_cell(sprites, fun, atlas.tile)} end)

      {places, {width, height}} =
        pack(Enum.map(pictures, fn {key, raster} -> {key, Raster.dimensions(raster)} end))

      %{
        index: %{
          counts: Enum.map(layers, &length/1),
          frames: for({key, _} <- pictures, do: Map.fetch!(places, key))
        },
        png:
          Png.encode(
            width,
            height,
            Raster.to_rgba_binary(paint(pictures, places, {width, height}))
          )
      }
    else
      _missing -> nil
    end
  end

  defp fetch_all(arts, names) do
    found = Enum.map(names, &Map.fetch(arts, &1))

    if Enum.all?(found, &match?({:ok, _}, &1)),
      do: {:ok, Enum.map(found, fn {:ok, art} -> art end)},
      else: :error
  end

  defp combinations([]), do: [[]]

  defp combinations([frames | rest]),
    do: for(sprite <- frames, tail <- combinations(rest), do: [sprite | tail])

  defp blended_cell([base | overlays], fun, tile) do
    overlays
    |> Enum.reduce(Raster.to_rgba_binary(base.raster), fn sprite, beneath ->
      Blend.over(beneath, Raster.to_rgba_binary(sprite.raster))
    end)
    |> then(&Raster.from_rgba(tile, tile, &1))
    |> recoloured(fun)
  end

  defp pictures(atlas) do
    arts = Enum.flat_map(atlas.entries, fn {art, entry} -> art_pictures(art, entry) end)

    fonts =
      for {name, %{font: font, white: white}} <- atlas.fonts,
          {which, cut} <- [glyphs: font, white: white],
          {char, glyph} <- cut.glyphs,
          glyph.raster.width > 0 and glyph.raster.height > 0,
          do: {{:font, name, which, char}, glyph.raster}

    arts ++ fonts
  end

  defp art_pictures(art, entry) do
    frames =
      for {sprite, i} <- Enum.with_index(entry.frames), do: {{:frame, art, i}, sprite.raster}

    faces = for {face, sprite} <- entry.faces, do: {{:face, art, face}, sprite.raster}

    poses =
      for {pose, sprites} <- entry.poses,
          {sprite, i} <- Enum.with_index(sprites),
          do: {{:pose, art, pose, i}, sprite.raster}

    frames ++ faces ++ poses
  end

  defp art_index(art, entry, rect) do
    {w, h} = entry.size

    %{
      frames: for(i <- 0..(length(entry.frames) - 1), do: rect.({:frame, art, i})),
      fps: entry.fps,
      size: [w, h],
      height: entry.height,
      faces:
        Map.new(entry.faces, fn {face, _} -> {Atom.to_string(face), rect.({:face, art, face})} end),
      poses:
        Map.new(entry.poses, fn {pose, sprites} ->
          {Atom.to_string(pose),
           for(i <- 0..(length(sprites) - 1), do: rect.({:pose, art, pose, i}))}
        end),
      stand: entry.stand,
      eye: entry.eye
    }
  end

  defp font_index(name, %{font: font, white: white}, rect) do
    glyphs = fn cut, which ->
      Map.new(cut.glyphs, fn {char, glyph} ->
        {char, glyph_place(glyph, rect, {:font, name, which, char}) ++ [glyph.advance]}
      end)
    end

    %{
      height: font.height,
      line: font.line,
      spacing: font.spacing,
      fallback: font.fallback,
      upcase: font.upcase?,
      glyphs: glyphs.(font, :glyphs),
      white: glyphs.(white, :white)
    }
  end

  defp glyph_place(%{raster: %{width: width, height: height}}, rect, key)
       when width > 0 and height > 0,
       do: rect.(key)

  defp glyph_place(_glyph, _rect, _key), do: [0, 0, 0, 0]

  defp label_font do
    chars = for code <- 32..126, do: <<code>>
    %{advance: 4, height: 5, glyphs: Map.new(chars, &{&1, Linocut.Font.glyph(&1)})}
  end

  defp pack(sizes) do
    sorted = Enum.sort_by(sizes, fn {_key, {_w, h}} -> -h end)

    {places, _x, y, row} =
      Enum.reduce(sorted, {%{}, 0, 0, 0}, fn {key, {w, h}}, {places, x, y, row} ->
        {x, y, row} = if x + w > @width and x > 0, do: {0, y + row, 0}, else: {x, y, row}
        {Map.put(places, key, [x, y, w, h]), x + w, y, max(row, h)}
      end)

    width =
      places |> Map.values() |> Enum.map(fn [x, _, w, _] -> x + w end) |> Enum.max(fn -> 1 end)

    {places, {max(width, 1), max(y + row, 1)}}
  end

  defp paint(pictures, places, {width, height}) do
    rows = for _ <- 1..height, do: :binary.copy(<<0, 0, 0, 0>>, width)
    canvas = :array.from_list(rows)

    canvas =
      Enum.reduce(pictures, canvas, fn {key, raster}, canvas ->
        [x, y, w, _h] = Map.fetch!(places, key)
        rgba = Raster.to_rgba_binary(raster)

        Enum.reduce(0..(raster.height - 1)//1, canvas, fn row, canvas ->
          line = :array.get(y + row, canvas)
          {left, span} = {x * 4, w * 4}
          <<before::binary-size(^left), _::binary-size(^span), rest::binary>> = line
          :array.set(y + row, before <> binary_part(rgba, row * w * 4, w * 4) <> rest, canvas)
        end)
      end)

    Raster.from_rgba(width, height, IO.iodata_to_binary(:array.to_list(canvas)))
  end

  defp recoloured(raster, fun) do
    rgba =
      for <<r, g, b, a <- Raster.to_rgba_binary(raster)>>, into: <<>> do
        {r, g, b, a} = fun.({r, g, b, a})
        <<r, g, b, a>>
      end

    Raster.from_rgba(raster.width, raster.height, rgba)
  end
end
