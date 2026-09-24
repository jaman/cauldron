defmodule Parade.Art do
  @moduledoc """
  The parade's pictures, loaded from `priv/art` into the atlas `:parade`: floor and wall
  textures of 32 pixels, and the knights, 32 by 48 in five liveries, each with a standing
  and a walking art posed front, back and side.

  The knight is taken from a sprite sheet in `priv/art/source`: each pose is resampled to
  32 by 48 and quantised to the sheet's palette, and the liveries recolour the cloak and
  hair through the manifest.
  """

  alias Cauldron2D.Atlas

  @name :parade
  @tile 32
  @colours [:crimson, :forest, :royal, :amber, :plum]

  @doc "The atlas name."
  @spec name() :: Atlas.name()
  def name, do: @name

  @doc "The tile size in pixels."
  @spec tile() :: pos_integer()
  def tile, do: @tile

  @doc "The liveries a knight's cloak and hair come in; the player wears the first."
  @spec colours() :: [atom()]
  def colours, do: @colours

  @doc "The art directory."
  @spec dir() :: Path.t()
  def dir, do: Path.join(:code.priv_dir(:parade), "art")

  @doc "Load the directory and install the atlas, once; returns its name."
  @spec install() :: Atlas.name()
  def install do
    if Atlas.installed?(@name) do
      @name
    else
      {:ok, atlas} = Atlas.load(@name, dir(), tile: @tile, void: {14, 14, 20})
      Atlas.install(atlas)
    end
  end

  @doc "The mover art for a knight in `colour`, walking or standing."
  @spec walker(atom(), boolean()) :: atom()
  def walker(colour, true), do: :"walker_#{colour}_walk"
  def walker(colour, false), do: :"walker_#{colour}"
end
