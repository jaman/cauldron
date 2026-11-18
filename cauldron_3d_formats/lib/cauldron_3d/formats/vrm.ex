defmodule Cauldron3D.Formats.Vrm do
  @moduledoc """
  The VRM 0.x avatar extension of a glTF document (`Cauldron3D.Formats.Gltf`, read from a
  `.vrm` file, which is a `.glb`):

    * `humanoid` — the standard bone names (`"hips"`, `"spine"`, `"leftUpperArm"`, …) to
      their nodes
    * `chains` — the swinging bone chains, as `Cauldron3D.SpringBones` chains with nodes in
      place of bones
    * `colliders` — the spheres those chains keep out of, by node
    * `meta` — the file's `meta` object (title, author, licence) as decoded JSON

  VRM 0.x writes collider offsets and gravity directions with the Z axis reversed from
  glTF's; they are read back into glTF's axes. A VRM 0.x avatar faces −Z.

      {:ok, document} = Cauldron3D.Formats.Gltf.read("AvatarSample_D.vrm")
      {:ok, vrm} = Cauldron3D.Formats.Vrm.read(document)
      rig = Cauldron3D.Formats.Gltf.Rig.new(document)
      springs = Cauldron3D.Formats.Vrm.spring_bones(vrm, rig, root)

  A document without the extension is `{:error, :not_vrm}`.
  """

  alias Cauldron3D.Formats.Gltf
  alias Cauldron3D.Formats.Gltf.Rig
  alias Cauldron3D.{Skeleton, SpringBones}

  @type t :: %__MODULE__{
          humanoid: %{String.t() => non_neg_integer()},
          chains: [map()],
          colliders: [map()],
          meta: map()
        }

  @enforce_keys [:humanoid, :chains, :colliders, :meta]
  defstruct [:humanoid, :chains, :colliders, :meta]

  @doc "The avatar extension of `document`."
  @spec read(Gltf.t()) :: {:ok, t()} | {:error, :not_vrm}
  def read(%Gltf{extensions: %{"VRM" => vrm}}) do
    secondary = Map.get(vrm, "secondaryAnimation", %{})

    {:ok,
     %__MODULE__{
       humanoid:
         for(
           bone <- get_in(vrm, ["humanoid", "humanBones"]) || [],
           is_integer(bone["node"]),
           into: %{},
           do: {bone["bone"], bone["node"]}
         ),
       chains: Enum.map(Map.get(secondary, "boneGroups", []), &chain/1),
       colliders: Enum.map(Map.get(secondary, "colliderGroups", []), &collider/1),
       meta: Map.get(vrm, "meta", %{})
     }}
  end

  def read(%Gltf{}), do: {:error, :not_vrm}

  @doc "The node of standard bone `name`, or `nil` when the avatar has none."
  @spec node(t(), String.t()) :: non_neg_integer() | nil
  def node(%__MODULE__{humanoid: humanoid}, name), do: Map.get(humanoid, name)

  @doc """
  `document` with its unlit materials made lit: not metallic, with `roughness`. VRM files
  mark their toon materials unlit.
  """
  @spec lit(Gltf.t(), float()) :: Gltf.t()
  def lit(%Gltf{materials: materials} = document, roughness \\ 0.85) do
    %{
      document
      | materials:
          Enum.map(materials, fn
            %{unlit: true} = material ->
              %{material | unlit: false, metallic: 0.0, roughness: roughness}

            material ->
              material
          end)
    }
  end

  @doc "The avatar's spring bones at rest on `rig` placed by `root`."
  @spec spring_bones(t(), Rig.t(), Skeleton.transform()) :: SpringBones.t()
  def spring_bones(%__MODULE__{} = vrm, %Rig{} = rig, root) do
    chains =
      Enum.map(vrm.chains, &%{&1 | bones: Enum.map(&1.bones, fn node -> Rig.bone(rig, node) end)})

    colliders = Enum.map(vrm.colliders, &%{&1 | bone: Rig.bone(rig, &1.bone)})
    SpringBones.new(rig.parents, rig.rest, root, chains, colliders)
  end

  defp chain(group) do
    %{
      bones: Map.get(group, "bones", []),
      stiffness: number(group, "stiffiness", 1.0),
      drag: number(group, "dragForce", 0.4),
      gravity: vector(Map.get(group, "gravityDir", %{"x" => 0, "y" => -1, "z" => 0})),
      gravity_power: number(group, "gravityPower", 0.0),
      hit_radius: number(group, "hitRadius", 0.02),
      colliders: Map.get(group, "colliderGroups", [])
    }
  end

  defp collider(group) do
    %{
      bone: group["node"],
      spheres:
        for(
          sphere <- Map.get(group, "colliders", []),
          do: {vector(sphere["offset"]), number(sphere, "radius", 0.0)}
        )
    }
  end

  defp vector(%{"x" => x, "y" => y, "z" => z}), do: {x / 1, y / 1, -z / 1}
  defp vector(_missing), do: {0.0, 0.0, 0.0}

  defp number(map, key, default), do: Map.get(map, key, default) / 1
end
