defmodule Cauldron do
  @moduledoc """
  The engine every Cauldron game runs on, with no way of drawing in it: a game is a value
  and pure callbacks (`Cauldron.Game`), run for its players at a fixed tick by a
  `Cauldron.World`; input, menus, sound, saving and the client side every front end
  shares come with it.

  | | |
  |---|---|
  | `Cauldron.Game` | what a game gives a world to run |
  | `Cauldron.World` | runs a game and keeps its players supplied with views |
  | `Cauldron.Client.Game` | what a game gives a client to put on screen |
  | `Cauldron.Client.View` | how a kind of game is drawn and looked at, which `cauldron_2d` and 3D renderers implement |
  | `Cauldron.Input` | the actions a player is holding |
  | `Cauldron.Audio` | sound effects and music |

  How a game is drawn is another package's: `cauldron_2d` for tile worlds and 2D
  projections, `cauldron_gpu` and `cauldron_3d` for 3D scenes.
  """

  @version Mix.Project.config()[:version]

  @doc "The engine's version, read from the project at compile time."
  @spec version() :: String.t()
  def version, do: @version
end
