defmodule Cistern.Art do
  @moduledoc """
  The game's tiles, loaded from the `.pic` files in `priv/art` into the atlas
  `:cistern`: `:sky`, `:floor`, `:bucket`, the animated `:drop`, and `:drop_gold`,
  which the manifest derives from `:drop` by recolouring it.
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
