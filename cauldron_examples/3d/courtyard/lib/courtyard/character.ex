defmodule Courtyard.Character do
  @moduledoc """
  The figure the viewer walks: the VRoid Project's CC0 avatar AvatarSample_D (Darkness),
  a VRM file `mix courtyard.fetch character` downloads.

    * `load/0` — what the world needs to move and pose it: its rig
      (`Cauldron3D.Formats.Gltf.Rig`), its VRM extension (`Cauldron3D.Formats.Vrm`) and
      its humanoid bones by name, as rig bones
    * `upload/2` — puts it in a `Cauldron3D.Scene.Target` with lit materials, answering
      `%{changes, handles, data}` like a `Courtyard.Scene`'s upload, `data` being
      `%{skins: [{id, skin}], instances: %{id => instance}}`; its instances start at
      `first_id/0`

      {:ok, character} = Courtyard.Character.load()
  """

  alias Cauldron3D.Formats.{Gltf, Vrm}
  alias Cauldron3D.Formats.Gltf.Rig
  alias Courtyard.Assets

  @first_id 90_000

  @type t :: %__MODULE__{rig: Rig.t(), vrm: Vrm.t(), bones: %{String.t() => non_neg_integer()}}

  @enforce_keys [:rig, :vrm, :bones]
  defstruct [:rig, :vrm, :bones]

  @doc "The id of the character's first instance."
  @spec first_id() :: pos_integer()
  def first_id, do: @first_id

  @doc "The character's rig, VRM extension and humanoid bones."
  @spec load() :: {:ok, t()} | {:error, term()}
  def load do
    with {:ok, document} <- document(),
         {:ok, vrm} <- Vrm.read(document) do
      rig = Rig.new(document)
      bones = Map.new(vrm.humanoid, fn {name, node} -> {name, Rig.bone(rig, node)} end)
      {:ok, %__MODULE__{rig: rig, vrm: vrm, bones: bones}}
    end
  end

  @doc "Uploads the character to `target`."
  @spec upload(Cauldron3D.Scene.Target.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def upload(target, _opts) do
    with {:ok, document} <- document(),
         {:ok, result} <-
           Cauldron3D.Scene.Gltf.upload(target, Vrm.lit(document), first_id: @first_id) do
      {:ok,
       %{
         changes: [],
         handles: result.handles,
         data: %{
           skins: result.skins,
           instances:
             Map.new(result.instances, fn {:instance, id, instance} -> {id, instance} end)
         }
       }}
    end
  end

  defp document do
    if Assets.ready?(:character),
      do: Gltf.read(Assets.character()),
      else: {:error, {:missing, Assets.fetch_command(:character)}}
  end
end
