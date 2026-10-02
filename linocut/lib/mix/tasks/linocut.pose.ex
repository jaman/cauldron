defmodule Mix.Tasks.Linocut.Pose do
  @shortdoc "Write OpenPose skeletons for an animation cycle"

  @moduledoc """
  Draw a cycle of poses as OpenPose skeletons, one PNG a frame, for a ControlNet to draw a
  character into.

      mix linocut.pose --out poses --frames 8 --size 768x1024

  The pictures are named `pose_0.png` upward. Give them to a model with an `openpose`
  ControlNet and `preprocess: "as_is"`, so the skeleton is read as drawn.

  ## Options

    * `--out` — the directory to write into, required
    * `--frames` — how many frames the cycle is cut into. Default `8`
    * `--size` — `WIDTHxHEIGHT` of each picture. Default `768x1024`
    * `--thickness` — how wide a limb is drawn, as a share of the smaller side.
      Default `0.018`
  """

  use Mix.Task

  alias FrenchCurve.{Png, Raster}
  alias Linocut.Pose

  @switches [out: :string, frames: :integer, size: :string, thickness: :float]

  @impl Mix.Task
  def run(argv) do
    {opts, _rest} = OptionParser.parse!(argv, strict: @switches)

    out = Keyword.get(opts, :out) || Mix.raise("give --out")
    frames = Keyword.get(opts, :frames, 8)
    size = opts |> Keyword.get(:size, "768x1024") |> sized()
    thickness = Keyword.get(opts, :thickness, 0.018)

    File.mkdir_p!(out)

    for frame <- 0..(frames - 1)//1 do
      raster =
        frame
        |> Kernel./(frames)
        |> Pose.walk()
        |> Pose.skeleton(size, thickness: thickness)

      path = Path.join(out, "pose_#{frame}.png")
      File.write!(path, Png.encode(raster.width, raster.height, Raster.to_rgba_binary(raster)))
    end

    {width, height} = size
    Mix.shell().info("#{out}: #{frames} skeletons of #{width}x#{height}")
  end

  defp sized(spec) do
    case String.split(spec, "x") do
      [width, height] -> {String.to_integer(width), String.to_integer(height)}
      _other -> Mix.raise("--size wants WIDTHxHEIGHT, got " <> spec)
    end
  end
end
