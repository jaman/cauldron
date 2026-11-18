defmodule Crossing.Art do
  @moduledoc """
  The atlas the game draws with.

  The pictures are files: `priv/art` holds one 32-pixel PNG per art, and `atlas.txt`
  gives each its glyph and colour for a terminal without pixels. `book/make_crossing_art.py`
  draws them, so they are reproducible from source, and a client may install the atlas on
  every mount because installing is idempotent.
  """

  alias Cauldron2D.Atlas

  @name :crossing
  @tile 32
  @void {8, 10, 18}

  @doc "The atlas name everything else refers to."
  @spec name() :: atom()
  def name, do: @name

  @doc "The size of a tile, in pixels."
  @spec tile() :: pos_integer()
  def tile, do: @tile

  @doc "Load the pictures and install the atlas, returning its name."
  @spec install() :: atom()
  def install do
    if Atlas.installed?(@name) do
      @name
    else
      {:ok, atlas} = Atlas.load(@name, dir(), tile: @tile, void: @void)
      Atlas.install(atlas)
      @name
    end
  end

  defp dir, do: Path.join(:code.priv_dir(:crossing), "art")
end
