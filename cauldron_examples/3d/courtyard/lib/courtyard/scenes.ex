defmodule Courtyard.Scenes do
  @moduledoc """
  The scenes the courtyard switches between, in order: `:courtyard` (made in code),
  `:alley` (Poly Haven) and `:atrium` (Intel Sponza), each a `Courtyard.Scene`.

      Courtyard.Scenes.module(:alley)
      Courtyard.Scenes.next(:atrium)
      #=> :courtyard
  """

  @scenes [
    courtyard: Courtyard.Scenes.Courtyard,
    alley: Courtyard.Scenes.Alley,
    atrium: Courtyard.Scenes.Atrium
  ]

  @type scene :: :courtyard | :alley | :atrium

  @doc "Every scene, in order."
  @spec all() :: [scene()]
  def all, do: Keyword.keys(@scenes)

  @doc "The module of `scene`."
  @spec module(scene()) :: module()
  def module(scene), do: Keyword.fetch!(@scenes, scene)

  @doc "The scene after `scene`, the first after the last."
  @spec next(scene()) :: scene()
  def next(scene) do
    scenes = all()
    Enum.at(scenes, rem(Enum.find_index(scenes, &(&1 == scene)) + 1, length(scenes)))
  end

  @doc "Where a viewer first stands in each scene."
  @spec starts() :: %{scene() => Courtyard.Scene.pose()}
  def starts, do: Map.new(@scenes, fn {scene, module} -> {scene, module.start()} end)
end
