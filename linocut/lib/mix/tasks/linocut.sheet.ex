defmodule Mix.Tasks.Linocut.Sheet do
  @shortdoc "Cut a sprite sheet into the frames of one .pic"

  @moduledoc """
  Read a sprite sheet, clear its background, cut it into frames and write them as one
  `.pic` with the frames separated by `---`.

      mix linocut.sheet run.png --out art/runner.pic --key corner --size 24x36 --expect 6

  ## Options

    * `--out` — where to write the `.pic`, required
    * `--key` — the background colour to clear, as `#rrggbb` or `corner` for the top-left
      pixel's colour. Default `corner`
    * `--tolerance` — how far from `--key` a colour may be and still be cleared. Default `40`
    * `--band` — which row of frames to cut, counting from the top, or `all` for every row
      in turn. Default `0`
    * `--gap` — how many blank columns or rows separate one frame from the next. Default `6`
    * `--size` — `WIDTHxHEIGHT` to draw each frame at. Default the frames' own size
    * `--colours` — how many colours the palette may hold. Default `16`
    * `--alpha` — the alpha at or above which a pixel counts as opaque. Default `128`
    * `--expect` — fail unless exactly this many frames were found
    * `--order` — the frames to write and the order to write them in, as indexes into what
      was cut counting from `0`, such as `0,1,2,3,2,1`. A frame may be left out or used
      more than once. Default every frame, left to right
    * `--nearest` — resample by taking one pixel rather than averaging
  """

  use Mix.Task

  alias FrenchCurve.Raster
  alias Linocut.{Quantise, Resample, Sheet}

  @keys ~c"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

  @switches [
    out: :string,
    key: :string,
    tolerance: :integer,
    band: :string,
    gap: :integer,
    size: :string,
    colours: :integer,
    alpha: :integer,
    expect: :integer,
    order: :string,
    nearest: :boolean
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, rest} = OptionParser.parse!(argv, strict: @switches)

    source = List.first(rest) || Mix.raise("give the sheet to read")
    out = Keyword.get(opts, :out) || Mix.raise("give --out")
    alpha = Keyword.get(opts, :alpha, 128)

    frames =
      source
      |> read!()
      |> cleared(Keyword.get(opts, :key, "corner"), Keyword.get(opts, :tolerance, 40))
      |> cut(Keyword.get(opts, :band, "0"), Keyword.get(opts, :gap, 6))
      |> counted(Keyword.get(opts, :expect))
      |> ordered(Keyword.get(opts, :order))
      |> Enum.map(&sized(&1, Keyword.get(opts, :size), Keyword.get(opts, :nearest, false)))

    palette = palette(frames, Keyword.get(opts, :colours, 16), alpha)
    reduced = Enum.map(frames, &Quantise.to_palette(&1, palette, alpha: alpha))

    File.mkdir_p!(Path.dirname(out))
    File.write!(out, Linocut.Pic.write(text(reduced, palette, alpha)))

    {width, height} = Raster.dimensions(hd(reduced))

    Mix.shell().info(
      "#{out}: #{length(reduced)} frames of #{width}x#{height}, #{length(palette)} colours"
    )
  end

  defp read!(path) do
    case Linocut.load(path) do
      {:ok, raster} -> raster
      {:error, reason} -> Mix.raise("#{path}: #{inspect(reason)}")
    end
  end

  defp cleared(raster, "corner", tolerance) do
    <<r, g, b, _a>> = binary_part(Raster.to_rgba_binary(raster), 0, 4)
    clear(raster, {r, g, b}, tolerance)
  end

  defp cleared(raster, spec, tolerance) do
    {r, g, b, _a} = Linocut.Palette.color(spec)
    clear(raster, {r, g, b}, tolerance)
  end

  defp clear(%Raster{width: width, height: height} = raster, {kr, kg, kb}, tolerance) do
    rgba =
      for <<r, g, b, a <- Raster.to_rgba_binary(raster)>>, into: <<>> do
        if abs(r - kr) <= tolerance and abs(g - kg) <= tolerance and abs(b - kb) <= tolerance,
          do: <<0, 0, 0, 0>>,
          else: <<r, g, b, a>>
      end

    Raster.from_rgba(width, height, rgba)
  end

  defp cut(raster, "all", gap), do: Sheet.cut_all(raster, gap: gap)

  defp cut(raster, band, gap), do: Sheet.cut(raster, band: String.to_integer(band), gap: gap)

  defp counted([], _expect), do: Mix.raise("no frames found: is the background keyed out?")

  defp counted(frames, nil), do: frames

  defp counted(frames, expect) when length(frames) == expect, do: frames

  defp counted(frames, expect),
    do: Mix.raise("found #{length(frames)} frames, expected #{expect}")

  defp ordered(frames, nil), do: frames

  defp ordered(frames, spec) do
    for text <- String.split(spec, ","), index = String.to_integer(String.trim(text)) do
      Enum.at(frames, index) ||
        Mix.raise("--order names frame #{index} but only #{length(frames)} were cut")
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

  defp palette(frames, colours, alpha) do
    {width, height} = Raster.dimensions(hd(frames))
    together = frames |> Enum.map(&Raster.to_rgba_binary/1) |> IO.iodata_to_binary()

    together
    |> then(&Raster.from_rgba(width, height * length(frames), &1))
    |> Quantise.palette(colours, alpha: alpha)
  end

  defp text(frames, palette, alpha) do
    keys = palette |> Enum.zip(@keys) |> Map.new(fn {colour, key} -> {colour, <<key>>} end)

    %{
      palette: Enum.map(palette, fn colour -> {Map.fetch!(keys, colour), hex(colour)} end),
      frames: Enum.map(frames, &rows(&1, keys, alpha))
    }
  end

  defp rows(%Raster{width: width} = raster, keys, alpha) do
    raster
    |> Raster.to_rgba_binary()
    |> then(&for(<<pixel::binary-size(4) <- &1>>, do: pixel))
    |> Enum.chunk_every(width)
    |> Enum.map(fn row -> Enum.map_join(row, &character(&1, keys, alpha)) end)
  end

  defp character(<<_r, _g, _b, a>>, _keys, alpha) when a < alpha, do: "."
  defp character(<<r, g, b, _a>>, keys, _alpha), do: Map.fetch!(keys, {r, g, b})

  defp hex({r, g, b}), do: "#" <> Base.encode16(<<r, g, b>>, case: :lower)
end
