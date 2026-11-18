defmodule Town.Art do
  @moduledoc """
  The town's pictures, loaded from `priv/art` into the atlas `:town`: floor textures,
  props, the storeys of each kind of building (a ground storey with its door on one
  side, an upper storey with windows, a roof on top), and the villagers in five tunics,
  each with a standing and a walking art posed front, back and side, in two looks: the
  plain villager and the finer-drawn hero, both standing three quarters of a tile tall.
  """

  alias Cauldron2D.Atlas

  @name :town
  @tile 16
  @tunics [:blue, :green, :red, :purple, :gold]

  @doc "The atlas name."
  @spec name() :: Atlas.name()
  def name, do: @name

  @doc "The tunic colours villagers come in; the player wears the first."
  @spec tunics() :: [atom()]
  def tunics, do: @tunics

  @doc "The art directory."
  @spec dir() :: Path.t()
  def dir, do: Path.join(:code.priv_dir(:town), "art")

  @doc "Load the directory and install the atlas, once; returns its name."
  @spec install() :: Atlas.name()
  def install do
    if Atlas.installed?(@name) do
      @name
    else
      {:ok, atlas} = Atlas.load(@name, dir(), tile: @tile, void: {12, 12, 16})
      Atlas.install(atlas)
    end
  end

  @doc "The mover art for a villager in `tunic`, walking or standing, in the plain or the hero look."
  @spec villager(atom(), boolean(), :plain | :hero) :: atom()
  def villager(tunic, walking?, look \\ :plain)
  def villager(tunic, true, :plain), do: :"villager_#{tunic}_walk"
  def villager(tunic, false, :plain), do: :"villager_#{tunic}"
  def villager(tunic, true, :hero), do: :"hero_#{tunic}_walk"
  def villager(tunic, false, :hero), do: :"hero_#{tunic}"
end
