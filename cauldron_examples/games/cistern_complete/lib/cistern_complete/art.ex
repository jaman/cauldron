defmodule CisternComplete.Art do
  @moduledoc """
  The game's pictures, loaded from `priv/art` into the atlas `:cistern_complete`: the
  pictures the image model drew and `mix cauldron.assets` finished (the Squall in its
  four moods, the keeper, the jars, hail, the dusk backdrop, the title painting), the
  ones drawn by hand (the rain, splashes and rings, the yoke, the grate, the cobbles,
  lightning, the menu frame, the cursor and the hud's gauges), and the font `:pixel`.

  Two tints shade a mover: `:robot`, the robot's keeper and jars in cool blues, and
  `:flash`, a hit's white.
  """

  alias Cauldron2D.Atlas

  @name :cistern_complete
  @tile 16

  @doc "The atlas name."
  @spec name() :: Atlas.name()
  def name, do: @name

  @doc "The art directory."
  @spec dir() :: Path.t()
  def dir, do: Path.join(:code.priv_dir(:cistern_complete), "art")

  @doc "Load the directory and install the atlas, once; returns its name."
  @spec install() :: Atlas.name()
  def install do
    if Atlas.installed?(@name) do
      @name
    else
      {:ok, atlas} =
        Atlas.load(@name, dir(),
          tile: @tile,
          void: {20, 14, 28},
          fonts: [pixel: [file: "font.png", cell: {8, 8}, chars: chars(), space: 3]]
        )

      atlas
      |> Atlas.tint(:robot, &robot/1)
      |> Atlas.tint(:flash, &flash/1)
      |> Atlas.install()
    end
  end

  defp chars, do: " !%'()*+,-./0123456789:<>?ABCDEFGHIJKLMNOPQRSTUVWXYZ_x"

  defp robot({r, g, b, a}), do: {div(b * 3, 4), div(g + b, 2), min(255, r + 30), a}

  defp flash({r, g, b, a}), do: {div(r + 255 * 3, 4), div(g + 255 * 3, 4), div(b + 255 * 3, 4), a}
end
