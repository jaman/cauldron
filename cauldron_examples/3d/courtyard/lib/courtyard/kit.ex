defmodule Courtyard.Kit do
  @moduledoc """
  Builds glTF documents (`Cauldron3D.Formats.Gltf`) from modular kits: documents whose
  nodes are separate parts laid out side by side. `assemble/2` keeps a kit's meshes,
  materials and images and replaces its instances with the parts named, each placed at a
  position and a turn about +Y. A part's own position in the kit is left out, so a
  position places the part's origin. `pick/2` keeps the parts named where the kit has
  them, for a variant made of several parts.

      {:ok, wall} = Courtyard.Kit.assemble(kit, [{"wall_standard_standard_01", {3.0, 0.0, 0.0}, 0.0}])
      Cauldron3D.Scene.Gltf.upload(target, wall)

  A name no node of the kit has is `{:error, {:unknown_part, name}}`.
  """

  alias Cauldron3D.Formats.Gltf
  alias Cauldron3D.Scene.Gltf.Placement
  alias Cauldron3D.Scene.{Quat, Transform}

  @type part :: {String.t(), {float(), float(), float()}, float()}

  @doc "`kit` with its instances replaced by `parts`."
  @spec assemble(Gltf.t(), [part()]) :: {:ok, Gltf.t()} | {:error, {:unknown_part, String.t()}}
  def assemble(%Gltf{} = kit, parts) do
    meshes = Map.new(kit.instances, &{&1.name, &1.mesh})

    parts
    |> Enum.reduce_while([], fn {name, position, yaw}, placed ->
      case Map.fetch(meshes, name) do
        {:ok, mesh} ->
          placed_part = %{
            mesh: mesh,
            node: nil,
            skin: nil,
            name: name,
            matrix: matrix(position, yaw)
          }

          {:cont, [placed_part | placed]}

        :error ->
          {:halt, {:error, {:unknown_part, name}}}
      end
    end)
    |> then(fn
      {:error, _reason} = error -> error
      placed -> {:ok, %{kit | instances: Enum.reverse(placed)}}
    end)
  end

  @doc "`kit` with only the instances whose names are in `names`, where the kit has them."
  @spec pick(Gltf.t(), [String.t()]) :: Gltf.t()
  def pick(%Gltf{} = kit, names),
    do: %{kit | instances: Enum.filter(kit.instances, &(&1.name in names))}

  defp matrix(position, yaw),
    do:
      Placement.matrix(
        Transform.new(position: position, rotation: Quat.axis_angle({0.0, 1.0, 0.0}, yaw))
      )
end
