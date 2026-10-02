defmodule Mix.Tasks.Linocut.Import do
  @shortdoc "Turn an image file into a .pic at a chosen size and palette"

  @moduledoc """
  Read an image, reduce it to a pixel-art palette, and write it as a `.pic`.

      mix linocut.import sky.png --out art/sky.pic --size 160x96 --colours 12
      mix linocut.import ruins.png --out art/ruins.pic --size 320x64 --key corner

  ## Options

    * `--out` — where to write the `.pic`, required
    * `--size` — `WIDTHxHEIGHT` to redraw at. Default the picture's own size
    * `--crop` — `X,Y,WIDTH,HEIGHT` of the source to keep, before resizing. Default all
    * `--seam` — `X,Y` pixels of the far edge to fade into the near one so the picture
      tiles, after resizing; the result loses that many pixels on each axis. Default none
    * `--colours` — how many colours the palette may hold. Default `16`
    * `--key` — a colour to make clear, as `#rrggbb` or `corner` for the top-left pixel's
      colour. Default none
    * `--tolerance` — how far from `--key` a colour may be and still be cleared, as a
      distance in each channel. Default `20`
    * `--alpha` — the alpha at or above which a pixel counts as opaque. Default `128`
    * `--nearest` — resample by taking one pixel rather than averaging, which keeps hard
      pixel art hard
  """

  use Mix.Task

  alias FrenchCurve.Raster
  alias Linocut.{Quantise, Resample, Seam}

  @keys ~c"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

  @switches [
    out: :string,
    size: :string,
    crop: :string,
    seam: :string,
    colours: :integer,
    key: :string,
    tolerance: :integer,
    alpha: :integer,
    nearest: :boolean
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, rest} = OptionParser.parse!(argv, strict: @switches)

    source = List.first(rest) || Mix.raise("give the image to read")
    out = Keyword.get(opts, :out) || Mix.raise("give --out")
    colours = Keyword.get(opts, :colours, 16)
    alpha = Keyword.get(opts, :alpha, 128)

    raster =
      source
      |> read!()
      |> cropped(Keyword.get(opts, :crop))
      |> keyed(Keyword.get(opts, :key), Keyword.get(opts, :tolerance, 20))
      |> sized(Keyword.get(opts, :size), Keyword.get(opts, :nearest, false))
      |> closed(Keyword.get(opts, :seam))

    {reduced, palette} = Quantise.reduce(raster, colours, alpha: alpha)

    File.mkdir_p!(Path.dirname(out))
    File.write!(out, Linocut.Pic.write(text(reduced, palette, alpha)))

    {width, height} = Raster.dimensions(reduced)
    Mix.shell().info("#{out}: #{width}x#{height}, #{length(palette)} colours")
  end

  defp read!(path) do
    case Linocut.load(path) do
      {:ok, raster} -> raster
      {:error, reason} -> Mix.raise("#{path}: #{inspect(reason)}")
    end
  end

  defp cropped(raster, nil), do: raster

  defp cropped(raster, spec) do
    case String.split(spec, ",") do
      [x, y, width, height] ->
        Raster.crop(
          raster,
          {String.to_integer(x), String.to_integer(y)},
          {String.to_integer(width), String.to_integer(height)}
        )

      _other ->
        Mix.raise("--crop wants X,Y,WIDTH,HEIGHT, got " <> spec)
    end
  end

  defp keyed(raster, nil, _tolerance), do: raster

  defp keyed(raster, "corner", tolerance) do
    <<r, g, b, _a>> = binary_part(Raster.to_rgba_binary(raster), 0, 4)
    clear(raster, {r, g, b}, tolerance)
  end

  defp keyed(raster, spec, tolerance) do
    {r, g, b, _a} = Linocut.Palette.color(spec)
    clear(raster, {r, g, b}, tolerance)
  end

  defp clear(%Raster{width: width, height: height} = raster, {kr, kg, kb}, tolerance) do
    rgba =
      for <<r, g, b, a <- Raster.to_rgba_binary(raster)>>, into: <<>> do
        if abs(r - kr) <= tolerance and abs(g - kg) <= tolerance and abs(b - kb) <= tolerance do
          <<0, 0, 0, 0>>
        else
          <<r, g, b, a>>
        end
      end

    Raster.from_rgba(width, height, rgba)
  end

  defp closed(raster, nil), do: raster

  defp closed(raster, spec) do
    case String.split(spec, ",") do
      [x, y] -> Seam.close(raster, x: String.to_integer(x), y: String.to_integer(y))
      _other -> Mix.raise("--seam wants X,Y, got " <> spec)
    end
  end

  defp sized(raster, nil, _nearest), do: raster

  defp sized(raster, size, nearest) do
    case String.split(size, "x") do
      [width, height] ->
        Resample.to(raster, {String.to_integer(width), String.to_integer(height)},
          mode: if(nearest, do: :nearest, else: :area)
        )

      _other ->
        Mix.raise("--size wants WIDTHxHEIGHT, got #{size}")
    end
  end

  defp text(%Raster{width: width} = raster, palette, alpha) do
    keys = palette |> Enum.zip(@keys) |> Map.new(fn {colour, key} -> {colour, <<key>>} end)

    rows =
      raster
      |> Raster.to_rgba_binary()
      |> then(&for(<<pixel::binary-size(4) <- &1>>, do: pixel))
      |> Enum.chunk_every(width)
      |> Enum.map(fn row -> Enum.map_join(row, &character(&1, keys, alpha)) end)

    %{
      palette: Enum.map(palette, fn colour -> {Map.fetch!(keys, colour), hex(colour)} end),
      frames: [rows]
    }
  end

  defp character(<<_r, _g, _b, a>>, _keys, alpha) when a < alpha, do: "."
  defp character(<<r, g, b, _a>>, keys, _alpha), do: Map.fetch!(keys, {r, g, b})

  defp hex({r, g, b}) do
    "#" <>
      Base.encode16(<<r, g, b>>, case: :lower)
  end
end
