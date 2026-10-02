defmodule Megablast.Scenery do
  @moduledoc """
  The demo's parallax layers, back to front: the nebula, a scattered starfield, the coral
  that sprawls behind the lane, and dust that streaks past in front.

  The rock walls are not layers — they are the lane's own cells, so they bite and the
  turrets grow out of them.

  `layers/0` gives them all, ready for a scene's `:layers`.
  """

  alias Cauldron2D.Parallax

  @doc "The layers, backmost first."
  @spec layers() :: [Parallax.Layer.t()]
  def layers, do: [nebula(), stars(), coral(), dust()]

  defp nebula do
    Parallax.panorama(
      name: :nebula,
      art: :nebula,
      size: {40, 64},
      wrap: :both,
      factor: {0.0, 0.1},
      void: :opaque
    )
  end

  defp stars do
    Parallax.layer(
      name: :stars,
      cell: Parallax.scatter(seed: 90_210, density: 0.05, arts: [{:speck, 6}, {:star, 1}]),
      factor: {0.0, 0.34}
    )
  end

  defp coral do
    Parallax.panorama(
      name: :coral,
      art: :coral,
      size: {40, 64},
      wrap: :both,
      factor: {0.0, 0.62}
    )
  end

  defp dust do
    Parallax.layer(
      name: :dust,
      cell: Parallax.scatter(seed: 4477, density: 0.01, arts: [:speck]),
      factor: {0.0, 1.45},
      front: true
    )
  end
end
