defmodule Cistern.Art do
  @moduledoc """
  The game's tiles, loaded from the `.pic` files in `priv/art` into the atlas
  `:cistern`: the sky in three heights, the town's roofs and walls, the cobbles, the
  Squall in its two moods, the rain and its shadows, the splashes, the keeper and the
  jars, and the robot's keeper and jars, which the manifest derives from the player's
  by recolouring them.
  """

  alias Cauldron2D.Atlas

  @name :cistern
  @tile 16

  @doc "The atlas name."
  @spec name() :: Atlas.name()
  def name, do: @name

  @doc "The art directory."
  @spec dir() :: Path.t()
  def dir, do: Path.join(:code.priv_dir(:cistern), "art")

  @doc "Load the directory and install the atlas, once; returns its name."
  @spec install() :: Atlas.name()
  def install do
    if Atlas.installed?(@name) do
      @name
    else
      {:ok, atlas} = Atlas.load(@name, dir(), tile: @tile, void: {10, 11, 20})
      Atlas.install(atlas)
    end
  end
end
