defmodule Courtyard.Assets do
  @moduledoc """
  Where the downloaded scenes live and whether each is ready. `mix courtyard.fetch`
  fills the folders; `priv/assets.json` pins every file it fetches.

    * the alley — Poly Haven's CC0 models and ground texture at 1K, each model in a
      folder of its own (`model/1`, `ground/1`)
    * the atrium — Intel's Sponza (Creative Commons Attribution), its glTF and buffer with
      the textures reduced to 2048 and 1024 pixels a side (`atrium/1`)
    * the character — the VRoid Project's CC0 avatar AvatarSample_D (Darkness), a VRM
      file (`character/0`)

  Everything sits under the user's cache folder, `cauldron/assets` (`root/0`); the
  `CAULDRON_ASSETS` environment variable names another.

      Courtyard.Assets.ready?(:alley)
      Courtyard.Assets.model("barrel_stove")
  """

  @type scene :: :alley | :atrium | :character

  @doc "The folder every scene is kept under."
  @spec root() :: Path.t()
  def root,
    do:
      System.get_env("CAULDRON_ASSETS") ||
        Path.join(:filename.basedir(:user_cache, "cauldron"), "assets")

  @doc "The folder `scene` is kept in."
  @spec folder(scene()) :: Path.t()
  def folder(scene), do: Path.join(root(), Atom.to_string(scene))

  @doc "Whether `scene` has been fetched and checked in full."
  @spec ready?(scene()) :: boolean()
  def ready?(scene), do: File.exists?(complete_marker(scene))

  @doc "The file `mix courtyard.fetch` writes once `scene` is complete."
  @spec complete_marker(scene()) :: Path.t()
  def complete_marker(scene), do: Path.join(folder(scene), "complete")

  @doc "The pinned list of what to fetch, `priv/assets.json`."
  @spec manifest() :: map()
  def manifest do
    :courtyard
    |> Application.app_dir("priv/assets.json")
    |> File.read!()
    |> JSON.decode!()
  end

  @doc "The glTF file of the alley model `id`."
  @spec model(String.t()) :: Path.t()
  def model(id) do
    files = Enum.find(manifest()["alley"]["models"], &(&1["id"] == id))["files"]
    gltf = Enum.find(files, &String.ends_with?(&1["path"], ".gltf"))
    Path.join([folder(:alley), id, gltf["path"]])
  end

  @doc "The alley ground texture's maps, `{diffuse, normal, ambient_roughness_metal}`."
  @spec ground() :: {Path.t(), Path.t(), Path.t()}
  def ground do
    base = Path.join(folder(:alley), "ground")
    {Path.join(base, "Diffuse.jpg"), Path.join(base, "nor_gl.jpg"), Path.join(base, "arm.jpg")}
  end

  @doc "The atrium's glTF with its textures reduced to `side` pixels a side (2048 or 1024)."
  @spec atrium(2048 | 1024) :: Path.t()
  def atrium(side), do: Path.join(folder(:atrium), "sponza_#{side}.gltf")

  @doc "The character's VRM file."
  @spec character() :: Path.t()
  def character, do: Path.join(folder(:character), manifest()["character"]["file"])

  @doc "The command that fetches `scene`, for telling a player."
  @spec fetch_command(scene()) :: String.t()
  def fetch_command(scene), do: "mix courtyard.fetch #{scene}"
end
