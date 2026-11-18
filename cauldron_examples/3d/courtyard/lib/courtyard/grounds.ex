defmodule Courtyard.Grounds do
  @moduledoc """
  The walk grids (`Cauldron3D.WalkGrid`) of the courtyard's scenes, which keep the
  character out of walls and the camera on the near side of them.

    * `all/0` — every scene's grid that can be had, by scene; a scene not downloaded has
      none
    * `cached/2` — a scene's grid read from its folder or from the user's cache folder
      (`cauldron/walk_grids`), or built by the function given and kept in the cache, so a
      scene whose folder cannot be written (inside an app) still keeps its grid
    * `sources/2` — a glTF document's triangles, placed at each of `places`, as walk grid
      sources

      grids = Courtyard.Grounds.all()
  """

  alias Cauldron3D.Scene.Gltf.Placement
  alias Cauldron3D.Scene.Transform
  alias Cauldron3D.WalkGrid
  alias Courtyard.{Assets, Scenes}

  @file_name "walk_grid_1.etf"

  @doc "Every scene's grid that `ground/0` gives, by scene."
  @spec all() :: %{Scenes.scene() => WalkGrid.t()}
  def all do
    for scene <- Scenes.all(),
        {:ok, grid} <- [Scenes.module(scene).ground()],
        into: %{},
        do: {scene, grid}
  end

  @doc "Downloaded scene `scene`'s grid, read from its folder or the cache, or built by `build` and kept in the cache."
  @spec cached(Assets.scene(), (-> {:ok, WalkGrid.t()} | {:error, term()})) ::
          {:ok, WalkGrid.t()} | {:error, term()}
  def cached(scene, build) do
    kept =
      Path.join([
        :filename.basedir(:user_cache, "cauldron"),
        "walk_grids",
        "#{scene}_#{@file_name}"
      ])

    with {:error, _reason} <- read(Path.join(Assets.folder(scene), @file_name)),
         {:error, _reason} <- read(kept),
         {:ok, grid} <- build.() do
      File.mkdir_p!(Path.dirname(kept))
      File.write!(kept, :erlang.term_to_binary(grid))
      {:ok, grid}
    end
  end

  @doc "The triangles of `document` placed at each of `places`."
  @spec sources(map(), [Transform.t()]) :: [WalkGrid.source()]
  def sources(document, places) do
    for place <- places,
        instance <- document.instances,
        primitive <- Enum.at(document.meshes, instance.mesh).primitives do
      matrix = Placement.multiply(Placement.matrix(place), instance.matrix)
      {primitive.positions, primitive.indices, rows(matrix)}
    end
  end

  defp read(path) do
    case File.read(path) do
      {:ok, bytes} -> {:ok, :erlang.binary_to_term(bytes)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp rows(m) do
    {{elem(m, 0), elem(m, 4), elem(m, 8), elem(m, 12)},
     {elem(m, 1), elem(m, 5), elem(m, 9), elem(m, 13)},
     {elem(m, 2), elem(m, 6), elem(m, 10), elem(m, 14)}}
  end
end
