defmodule Cauldron2D.Assets.Frames do
  @moduledoc """
  An animation cut from a video clip and finished as one strip of pixel art.

  `extract/2` reads a clip's frames through `ffmpeg` (which must be on the path) and
  keeps `keep` of them spread evenly between two points of the clip. `finish/2` makes
  them pixel art together, so they match: each frame's background keyed out, every
  frame sampled on the first frame's pixel grid and held to the first frame's palette,
  all cut to the one box that holds every frame's figure, and fitted alike. `strip/1`
  lays them side by side.
  """

  alias FrenchCurve.Raster
  alias Linocut.{Pixelate, Quantise}

  @doc """
  `keep` frames of the clip at `path`. Options `:from` and `:to`, the share of the clip
  to take them between (default `0.0` and `1.0`).
  """
  @spec extract(Path.t(), keyword()) :: {:ok, [Raster.t()]} | {:error, term()}
  def extract(path, opts) do
    dir = Path.join(System.tmp_dir!(), "cauldron_frames_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    try do
      case System.cmd(
             "ffmpeg",
             ["-hide_banner", "-loglevel", "error", "-i", path, Path.join(dir, "%04d.png")],
             stderr_to_stdout: true
           ) do
        {_out, 0} -> {:ok, dir |> pictures() |> chosen(opts) |> Enum.map(&load!/1)}
        {out, status} -> {:error, {:ffmpeg, status, out}}
      end
    after
      File.rm_rf!(dir)
    end
  end

  @doc """
  The frames rendered into `dir` (`frame_0001.png` onwards, as the Studio's animations
  keep them), chosen as `extract/2` chooses them; without `:keep` every frame between
  `:from` and `:to` is kept, all of them by default.
  """
  @spec pick(Path.t(), keyword()) :: {:ok, [Raster.t()]} | {:error, term()}
  def pick(dir, opts) do
    case pictures(dir) do
      [] -> {:error, {:no_frames, dir}}
      files -> {:ok, files |> chosen(opts) |> Enum.map(&load!/1)}
    end
  end

  defp pictures(dir) do
    if File.dir?(dir),
      do:
        dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".png"))
        |> Enum.sort()
        |> Enum.map(&Path.join(dir, &1)),
      else: []
  end

  defp chosen(files, opts) do
    count = length(files)
    first = round(Keyword.get(opts, :from, 0.0) * (count - 1))
    last = round(Keyword.get(opts, :to, 1.0) * (count - 1))

    case Keyword.get(opts, :keep) do
      nil ->
        Enum.slice(files, first..last//1)

      keep ->
        for index <- 0..(keep - 1) do
          Enum.at(files, min(first + round(index * (last - first) / max(keep, 1)), count - 1))
        end
    end
  end

  defp load!(path) do
    {:ok, raster} = Linocut.load(path)
    raster
  end

  @doc """
  The frames finished as pixel art together. Options as `Linocut.Pixelate.finish/2`
  takes them: `:key` and `:tolerance`, `:palette` (a count chosen from the first frame,
  or a list), `:dither`, `:outline` and `:fit`.
  """
  @spec finish([Raster.t()], keyword()) :: [Raster.t()]
  def finish([_first | _] = frames, opts) do
    keyed = Enum.map(frames, &key(&1, opts))
    grid = Pixelate.grid(hd(keyed))
    sampled = Enum.map(keyed, &Pixelate.sample(&1, grid))
    palette = palette(hd(sampled), opts[:palette])

    shared = [
      palette: palette,
      dither: Keyword.get(opts, :dither, :none),
      outline: opts[:outline],
      trim: false,
      size: :grid
    ]

    sampled
    |> Enum.map(&Pixelate.finish(&1, Keyword.merge(shared, size: Raster.dimensions(&1))))
    |> cropped()
    |> Enum.map(&fit(&1, opts[:fit]))
  end

  @doc "The frames side by side, left to right."
  @spec strip([Raster.t()]) :: Raster.t()
  def strip([%Raster{width: width, height: height} | _] = frames) do
    rows =
      for y <- 0..(height - 1) do
        for frame <- frames,
            into: <<>>,
            do: binary_part(Raster.to_rgba_binary(frame), y * width * 4, width * 4)
      end

    Raster.from_rgba(width * length(frames), height, IO.iodata_to_binary(rows))
  end

  defp key(raster, opts) do
    case opts[:key] do
      nil -> raster
      _key -> Pixelate.key_border(raster, Keyword.get(opts, :tolerance, 60))
    end
  end

  defp palette(_raster, list) when is_list(list), do: list
  defp palette(raster, count) when is_integer(count), do: Quantise.palette(raster, count)
  defp palette(_raster, nil), do: nil

  defp cropped(frames) do
    boxes = for frame <- frames, box = opaque_box(frame), do: box

    case boxes do
      [] ->
        frames

      boxes ->
        {left, top} =
          {boxes |> Enum.map(&elem(&1, 0)) |> Enum.min(),
           boxes |> Enum.map(&elem(&1, 1)) |> Enum.min()}

        {right, bottom} =
          {boxes |> Enum.map(&elem(&1, 2)) |> Enum.max(),
           boxes |> Enum.map(&elem(&1, 3)) |> Enum.max()}

        Enum.map(frames, &Raster.crop(&1, {left, top}, {right - left + 1, bottom - top + 1}))
    end
  end

  defp opaque_box(%Raster{width: width} = raster) do
    points =
      for {<<_r, _g, _b, a>>, index} <-
            raster |> Raster.to_rgba_binary() |> chunk() |> Enum.with_index(),
          a > 0,
          do: {rem(index, width), div(index, width)}

    case points do
      [] ->
        nil

      points ->
        {points |> Enum.map(&elem(&1, 0)) |> Enum.min(),
         points |> Enum.map(&elem(&1, 1)) |> Enum.min(),
         points |> Enum.map(&elem(&1, 0)) |> Enum.max(),
         points |> Enum.map(&elem(&1, 1)) |> Enum.max()}
    end
  end

  defp chunk(rgba), do: for(<<pixel::binary-4 <- rgba>>, do: pixel)

  defp fit(raster, nil), do: raster

  defp fit(%Raster{width: width, height: height} = raster, {most_w, most_h}) do
    scale = min(1.0, min(most_w / width, most_h / height))

    Linocut.Resample.to(raster, {max(1, round(width * scale)), max(1, round(height * scale))},
      mode: :nearest
    )
  end
end
