defmodule Cauldron2D do
  @moduledoc """
  A 2D tile engine for terminals: a grid of tile ids, drawn as pixels or as glyphs depending on
  what the terminal supports.

  | | |
  |---|---|
  | `Cauldron2D.Atlas` | the catalogue: a sprite, a glyph and a colour per tile |
  | `Cauldron2D.Surface` | a grid of cells composited into one raster |
  | `Cauldron2D.Camera` | which part of the world is on screen |
  | `Cauldron2D.Loop` | a fixed timestep |
  | `Cauldron2D.Renderer` | pixels or glyphs |
  | `Cauldron2D.Rng` | a seeded generator carried in state |

  Drawing a surface in a terminal is `cauldron_2d_drafter`; nothing in this package depends on a UI
  framework.

      atlas =
        Cauldron2D.Atlas.new(:my_game, tile: 16, void: {6, 7, 11})
        |> Cauldron2D.Atlas.put(:floor, floor_raster(), glyph: "· ", color: {60, 66, 88})
        |> Cauldron2D.Atlas.install()

      camera =
        Cauldron2D.Camera.view(focus: {x, y}, bounds: {w, h}, size: {40, 24}, cell: &cell_at/1)

      raster = Cauldron2D.Surface.compose(atlas, camera.cells)
  """

  @version Mix.Project.config()[:version]

  @doc """
  The engine's version.

  Read from the project at compile time, so it answers the same whether or not the `:cauldron_2d`
  application has been loaded.
  """
  @spec version() :: String.t()
  def version, do: @version
end
