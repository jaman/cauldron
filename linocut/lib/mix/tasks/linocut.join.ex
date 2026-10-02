defmodule Mix.Tasks.Linocut.Join do
  @shortdoc "Join separately drawn pictures into the frames of one .pic"

  @moduledoc """
  Read several pictures of the same subject, clear their backgrounds, line them up on one
  canvas and write them as the frames of one `.pic`.

      mix linocut.join --out art/runner.pic --size 22x36 --colours 10 \\
        pose1.png pose2.png pose3.png pose4.png

  Each picture is cropped to what it holds, then every frame is stood on the same floor
  and lined up by the body above it, so a stride that reaches wide does not shift the
  figure sideways.

  ## Options

    * `--out` — where to write the `.pic`, required
    * `--key` — the background colour to clear, as `#rrggbb` or `corner` for the top-left
      pixel's colour. Default `corner`
    * `--tolerance` — how far from `--key` a colour may be and still be cleared. Default `40`
    * `--size` — `WIDTHxHEIGHT` to draw each frame at. Default the frames' own size
    * `--colours` — how many colours the shared palette may hold. Default `16`
    * `--alpha` — the alpha at or above which a pixel counts as opaque. Default `128`
    * `--anchor` — the fraction of a frame's height, from the top, whose middle the frames
      are lined up by. Default `0.35`
    * `--nearest` — resample by taking one pixel rather than averaging
  """

  use Mix.Task

  alias FrenchCurve.Raster
  alias Linocut.{Frames, Resample}

  @switches [
    out: :string,
    key: :string,
    tolerance: :integer,
    size: :string,
    colours: :integer,
    alpha: :integer,
    anchor: :float,
    nearest: :boolean
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, sources} = OptionParser.parse!(argv, strict: @switches)

    if sources == [], do: Mix.raise("give the pictures to join")
    out = Keyword.get(opts, :out) || Mix.raise("give --out")
    alpha = Keyword.get(opts, :alpha, 128)

    frames =
      sources
      |> Enum.map(&read!/1)
      |> Enum.map(
        &cleared(&1, Keyword.get(opts, :key, "corner"), Keyword.get(opts, :tolerance, 40))
      )
      |> Frames.align(alpha: 16, anchor: Keyword.get(opts, :anchor, 0.35))
      |> Enum.map(&sized(&1, Keyword.get(opts, :size), Keyword.get(opts, :nearest, false)))

    File.mkdir_p!(Path.dirname(out))
    File.write!(out, Frames.to_pic(frames, Keyword.get(opts, :colours, 16), alpha))

    {width, height} = Raster.dimensions(hd(frames))
    Mix.shell().info("#{out}: #{length(frames)} frames of #{width}x#{height}")
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

  defp sized(raster, nil, _nearest), do: raster

  defp sized(raster, size, nearest) do
    case String.split(size, "x") do
      [width, height] ->
        Resample.to(raster, {String.to_integer(width), String.to_integer(height)},
          mode: if(nearest, do: :nearest, else: :area)
        )

      _other ->
        Mix.raise("--size wants WIDTHxHEIGHT, got " <> size)
    end
  end
end
