defmodule Cauldron3D.Bsp.Surfaces do
  @moduledoc """
  Faces' textures with their light worked in, made once and kept until the light changes.

  A surface covers its face's lightmap area at one mip level: each pixel is the texture's
  colour taken through the light table at the light there, blended between the four
  nearest lightmap samples. A face's light is the sum of its styles' samples, each scaled
  by the style's value over 256.

      cache = Cauldron3D.Bsp.Surfaces.new()
      Cauldron3D.Bsp.Surfaces.fetch(cache, bsp, face_index, mip, light)

  `light` is a map: `:table` (rows of 256 colours, brightest first), `:rows` (how many),
  `:styles` (a map or tuple from style number to scale, 256 being normal; a missing style
  is 256) and `:unlit` (the light of a face with no lightmap, default 255).

  For a picture in full colour the map has `:rgba` instead of `:table` and `:rows`: a
  palette as `Cauldron3D.Texture.colours/1` makes it, for textures without their own.
  The surface is then an RGBA texture lit from the world's grey or red-green-blue
  lightmaps (`Cauldron3D.Bsp`'s `light_channels`):

    * each lightmap sample's channel is the sum over the face's styles of its sample
      times `trunc(colour * scale)`, a style given in `:styles` as a scale or as
      `{scale, {r, g, b}}` (a grey lightmap's one sample serving all three channels); a
      face with no lightmap has `:unlit` in every channel (default 32768), and with
      `:fixed` every face has that in every channel instead
    * `:store`, a function of a sample's `{r, g, b}`, gives the value kept for it
      (default the sums themselves)
    * the kept values are blended between the four nearest samples at each texel's
      centre, and `:shade`, a function of the blended `{r, g, b}`, gives the three
      numbers the texture's channels are multiplied by (default each over 32768)

  A face whose texture is of kind `:masked` is `{0, 0, 0, 0}` where its texture is
  colour 255. `:scroll` moves the texture (not its light) that many of its own pixels
  along `s`.

  The cache is an ETS table owned by the process that made it, readable and writable by
  any; one surface is kept per face and mip.
  """

  alias Cauldron3D.{Bsp, Paint, Texture}
  alias Cauldron3D.Bsp.Face

  @type cache :: :ets.tid()

  @doc "An empty cache."
  @spec new() :: cache()
  def new,
    do:
      :ets.new(:cauldron_3d_surfaces, [
        :set,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])

  @doc "Forget every surface, as when a new world is loaded."
  @spec clear(cache()) :: :ok
  def clear(cache) do
    :ets.delete_all_objects(cache)
    :ok
  end

  @doc "The surface of face `index` at `mip`, made now if it is missing or its light has changed."
  @spec fetch(cache(), Bsp.t(), non_neg_integer(), 0..3, map()) :: Texture.t()
  def fetch(cache, %Bsp{} = bsp, index, mip, light) do
    case cached(cache, bsp, index, mip, light) do
      {:ok, _key, surface} -> surface
      {:missing, job} -> make(cache, job)
    end
  end

  @doc """
  The cached surface as `{:ok, {index, mip}, surface}`, or `{:missing, job}`: everything
  `make/2` needs to make it, without the world, so it can be handed to another process;
  `job.key` is `{index, mip}`.
  """
  @spec cached(cache(), Bsp.t(), non_neg_integer(), 0..3, map()) ::
          {:ok, {non_neg_integer(), 0..3}, Texture.t()} | {:missing, map()}
  def cached(cache, %Bsp{} = bsp, index, mip, light) do
    face = elem(bsp.faces, index)

    scales =
      case Map.get(light, :fixed) do
        nil -> Enum.map(face.styles, &scale(light, &1))
        value -> [{:fixed, value}]
      end
      |> then(&[{:scroll, Map.get(light, :scroll, 0)} | &1])

    case :ets.lookup(cache, {index, mip}) do
      [{key, ^scales, surface}] ->
        {:ok, key, surface}

      _missing ->
        entry = elem(bsp.textures, face.texture)
        texture = entry |> Map.fetch!(:mips) |> Enum.at(mip)
        channels = bsp.light_channels

        {:missing,
         %{
           key: {index, mip},
           face: face,
           texture: texture,
           mip: mip,
           scales: scales,
           samples: samples(bsp.lightmaps, face, channels),
           light:
             light
             |> Map.take([:table, :rows, :unlit, :rgba, :store, :shade, :fixed, :scroll])
             |> Map.merge(%{channels: channels, mask?: entry.kind == :masked})
         }}
    end
  end

  @doc "Make the surface a `cached/5` job describes, and keep it in the cache."
  @spec make(cache(), map()) :: Texture.t()
  def make(cache, job) do
    surface = build(job.face, job.texture, job.samples, job.mip, job.scales, job.light)
    :ets.insert(cache, {job.key, job.scales, surface})
    surface
  end

  @doc """
  A face's surface at `mip` from the texture at that mip and the face's lightmap
  `samples` (every style's, in order; `nil` for an unlit face), its styles at `scales`.
  """
  @spec build(Face.t(), Texture.t(), binary() | nil, 0..3, [number()], map()) :: Texture.t()
  def build(%Face{} = face, %Texture{} = texture, samples, mip, scales, %{rgba: colours} = light) do
    {s_extent, t_extent} = face.extents
    {s_min, t_min} = face.mins
    width = max(Bitwise.bsr(s_extent, mip), 1)
    height = max(Bitwise.bsr(t_extent, mip), 1)
    {s_start, t_start} = {Bitwise.bsr(s_min, mip), Bitwise.bsr(t_min, mip)}
    grid = luxel_grid(face, samples, Enum.reject(scales, &match?({:scroll, _}, &1)), light)
    shade = Map.get(light, :shade, &default_shade/1)
    colours = texture.colours || colours
    mask? = Map.get(light, :mask?, false)
    step = Bitwise.bsl(1, mip) / face.luxel
    across = texture.width
    scroll = trunc(Map.get(light, :scroll, 0) / Bitwise.bsl(1, mip))
    first_column = Integer.mod(s_start + scroll, across)

    pixels =
      for j <- 0..(height - 1), into: <<>> do
        texture_row = Integer.mod(t_start + j, texture.height) * across
        texels = binary_part(texture.pixels, texture_row, across)
        row = luxel_row(grid, (j + 0.5) * step)

        for i <- 0..(width - 1), into: <<>> do
          index = :binary.at(texels, rem(first_column + i, across))
          multipliers = shade.(luxel_sample(row, (i + 0.5) * step))
          rgba_texel(Texture.colour(colours, index), multipliers, mask? and index == 255)
        end
      end

    Texture.rgba(width, height, pixels)
  end

  def build(%Face{} = face, %Texture{} = texture, samples, mip, scales, light) do
    {s_extent, t_extent} = face.extents
    {s_min, t_min} = face.mins
    width = max(Bitwise.bsr(s_extent, mip), 1)
    height = max(Bitwise.bsr(t_extent, mip), 1)
    {s_start, t_start} = {Bitwise.bsr(s_min, mip), Bitwise.bsr(t_min, mip)}
    grid = light_grid(face, samples, Enum.reject(scales, &match?({:scroll, _}, &1)), light)
    rows_of = &Paint.light_row(&1, %{light_rows: light.rows})
    step = Bitwise.bsl(1, mip) / face.luxel

    pixels =
      for j <- 0..(height - 1), into: <<>> do
        texture_row = Integer.mod(t_start + j, texture.height) * texture.width
        light_row = light_row(grid, j * step)

        for i <- 0..(width - 1), into: <<>> do
          texel =
            :binary.at(texture.pixels, texture_row + Integer.mod(s_start + i, texture.width))

          row = rows_of.(sample(light_row, i * step))
          <<:binary.at(light.table, row * 256 + texel)>>
        end
      end

    Texture.new(width, height, pixels)
  end

  defp scale(light, style) do
    case Map.get(light, :styles) do
      nil -> 256
      styles when is_tuple(styles) and style < tuple_size(styles) -> elem(styles, style)
      styles when is_map(styles) -> Map.get(styles, style, 256)
      _ -> 256
    end
  end

  defp default_shade({r, g, b}), do: {r / 32_768, g / 32_768, b / 32_768}

  defp rgba_texel(_colour, _multipliers, true), do: <<0, 0, 0, 0>>

  defp rgba_texel(<<r, g, b, a>>, {mr, mg, mb}, false),
    do: <<channel(r * mr), channel(g * mg), channel(b * mb), a>>

  defp luxel_grid(%Face{} = face, samples, scales, light) do
    {across, down} = Face.lightmap_size(face)
    store = Map.get(light, :store, & &1)
    channels = Map.get(light, :channels, 1)

    values =
      case {Map.get(light, :fixed), samples} do
        {nil, nil} ->
          unlit = Map.get(light, :unlit, 32_768)
          List.duplicate(store.({unlit, unlit, unlit}), across * down)

        {nil, samples} ->
          sums(samples, scales, across * down, channels) |> Enum.map(store)

        {value, _samples} ->
          List.duplicate(store.({value, value, value}), across * down)
      end

    {across, down, List.to_tuple(values)}
  end

  defp sums(samples, scales, size, channels) do
    scales
    |> Enum.with_index()
    |> Enum.filter(fn {_scale, index} -> (index + 1) * size * channels <= byte_size(samples) end)
    |> Enum.map(fn {scale, index} -> style_sums(samples, scale, index * size, size, channels) end)
    |> case do
      [] -> List.duplicate({0, 0, 0}, size)
      styles -> Enum.zip_with(styles, &add_sums/1)
    end
  end

  defp style_sums(samples, scale, first, size, channels) do
    {sr, sg, sb} = style_rgb(scale)
    part = binary_part(samples, first * channels, size * channels)

    case channels do
      3 -> for <<r, g, b <- part>>, do: {r * sr, g * sg, b * sb}
      _ -> for <<v <- part>>, do: {v * sr, v * sg, v * sb}
    end
  end

  defp style_rgb({scale, {r, g, b}}), do: {trunc(r * scale), trunc(g * scale), trunc(b * scale)}
  defp style_rgb(scale), do: {trunc(scale), trunc(scale), trunc(scale)}

  defp add_sums(sums) do
    Enum.reduce(sums, {0, 0, 0}, fn {r, g, b}, {ar, ag, ab} -> {ar + r, ag + g, ab + b} end)
  end

  defp luxel_row({across, down, values}, y) do
    y0 = min(trunc(y), down - 1)
    y1 = min(y0 + 1, down - 1)
    fy = y - y0

    {across,
     for x <- 0..(across - 1) do
       mix3(elem(values, y0 * across + x), elem(values, y1 * across + x), fy)
     end
     |> List.to_tuple()}
  end

  defp luxel_sample({across, row}, x) do
    x0 = min(trunc(x), across - 1)
    x1 = min(x0 + 1, across - 1)
    mix3(elem(row, x0), elem(row, x1), x - x0)
  end

  defp mix3({ar, ag, ab}, {br, bg, bb}, t),
    do: {ar + (br - ar) * t, ag + (bg - ag) * t, ab + (bb - ab) * t}

  defp channel(value) when value >= 255, do: 255
  defp channel(value), do: trunc(value)

  defp samples(_lightmaps, %Face{lightmap: nil}, _channels), do: nil

  defp samples(lightmaps, %Face{} = face, channels) do
    {across, down} = Face.lightmap_size(face)

    size =
      min(across * down * length(face.styles) * channels, byte_size(lightmaps) - face.lightmap)

    binary_part(lightmaps, face.lightmap, max(size, 0))
  end

  defp light_grid(%Face{} = face, nil, _scales, light) do
    {across, down} = Face.lightmap_size(face)
    value = Map.get(light, :unlit, 255) / 1
    {across, down, List.to_tuple(List.duplicate(value, across * down))}
  end

  defp light_grid(%Face{} = face, samples, scales, light) do
    channels = Map.get(light, :channels, 1)
    {across, down} = Face.lightmap_size(face)
    size = across * down

    values =
      scales
      |> Enum.with_index()
      |> Enum.filter(fn {_scale, index} ->
        (index + 1) * size * channels <= byte_size(samples)
      end)
      |> Enum.map(fn {scale, index} ->
        for i <- 0..(size - 1),
            do: :binary.at(samples, (index * size + i) * channels) * scalar(scale) / 256
      end)
      |> Enum.zip_with(&Enum.sum/1)

    values = if values == [], do: List.duplicate(0.0, size), else: values
    {across, down, List.to_tuple(values)}
  end

  defp scalar({scale, _rgb}), do: scale
  defp scalar(scale), do: scale

  defp light_row({across, down, values}, y) do
    y0 = min(trunc(y), down - 1)
    y1 = min(y0 + 1, down - 1)
    fy = y - y0

    {across,
     for x <- 0..(across - 1) do
       elem(values, y0 * across + x) * (1 - fy) + elem(values, y1 * across + x) * fy
     end
     |> List.to_tuple()}
  end

  defp sample({across, row}, x) do
    x0 = min(trunc(x), across - 1)
    x1 = min(x0 + 1, across - 1)
    fx = x - x0
    elem(row, x0) * (1 - fx) + elem(row, x1) * fx
  end
end
