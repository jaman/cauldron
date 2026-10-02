defmodule Beast.Scenery do
  @moduledoc """
  The demo's parallax layers, back to front: the sunset, the far ridge, the ruins, a
  scatter of bones on the ground, and the scrub that passes in front of the runner.

  `layers/0` gives them all, ready for a scene's `:layers`.
  """

  alias Cauldron2D.Parallax

  @surface Beast.Terrain.surface()

  @doc "The layers, backmost first."
  @spec layers() :: [Parallax.Layer.t()]
  def layers do
    [sky(), ridge(), ruins(), treeline(), scrub()]
  end

  defp sky do
    Parallax.panorama(
      name: :sky,
      art: :sky,
      size: {44, 22},
      at: {0, @surface - 22},
      wrap: :x,
      factor: {0.0, 1.0},
      void: :opaque
    )
  end

  defp ridge do
    Parallax.panorama(
      name: :ridge,
      art: :mountains,
      size: {40, 12},
      at: {0, @surface - 12},
      wrap: :x,
      factor: {0.12, 1.0}
    )
  end

  defp ruins do
    Parallax.panorama(
      name: :ruins,
      art: :ruins,
      size: {32, 12},
      at: {0, @surface - 12},
      wrap: :x,
      factor: {0.4, 1.0}
    )
  end

  defp treeline do
    Parallax.layer(
      name: :treeline,
      cell:
        Parallax.scatter(
          seed: 1871,
          density: 0.22,
          arts: [{:snag, 4}, {:spire, 1}],
          rows: (@surface - 1)..(@surface - 1)
        ),
      factor: {0.62, 1.0}
    )
  end

  defp scrub do
    Parallax.panorama(
      name: :scrub,
      art: :scrub,
      size: {40, 5},
      at: {0, @surface - 1},
      wrap: :x,
      factor: {1.35, 1.0},
      front: true
    )
  end
end
