defmodule Cauldron3D.Formats.Gltf.Rig do
  @moduledoc """
  A glTF document's nodes as one skeleton (`Cauldron3D.Skeleton`), for posing skinned
  meshes. Nodes are put in an order with every parent before its children; `bone/2`
  gives a node's place in that order, and `parents` and `rest` are in it too, ready for
  `Cauldron3D.Skeleton.pose/3` and `Cauldron3D.SpringBones`. Node scale is not applied.

      rig = Cauldron3D.Formats.Gltf.Rig.new(document)
      neck = Cauldron3D.Formats.Gltf.Rig.bone(rig, 12)
      transforms = Cauldron3D.Formats.Gltf.Rig.pose(rig, %{neck => turn}, root)
      bones = Cauldron3D.Formats.Gltf.Rig.bones(rig, transforms, 0, unroot)

  `bones/4` gives the matrices a skin's vertices are moved by, in the order of the skin's
  joints, each 12 numbers row by row (`Cauldron3D.Scene.Pose`).
  """

  alias Cauldron3D.Formats.Gltf
  alias Cauldron3D.{Quat, Skeleton, Vec}

  @type t :: %__MODULE__{
          nodes: tuple(),
          bones: %{non_neg_integer() => non_neg_integer()},
          parents: tuple(),
          rest: [{Vec.t(), Quat.t()}],
          skins: [%{joints: [non_neg_integer()], inverse_binds: [Skeleton.transform()]}]
        }

  @enforce_keys [:nodes, :bones, :parents, :rest, :skins]
  defstruct [:nodes, :bones, :parents, :rest, :skins]

  @doc "The rig of every node in `document`."
  @spec new(Gltf.t()) :: t()
  def new(%Gltf{nodes: nodes, skins: skins}) do
    tree = List.to_tuple(nodes)

    order =
      nodes
      |> Enum.with_index()
      |> Enum.filter(&is_nil(elem(&1, 0).parent))
      |> Enum.flat_map(&below(tree, elem(&1, 1)))

    bones = order |> Enum.with_index() |> Map.new()

    %__MODULE__{
      nodes: List.to_tuple(order),
      bones: bones,
      parents: List.to_tuple(Enum.map(order, &parent_bone(tree, bones, &1))),
      rest: Enum.map(order, &{elem(tree, &1).translation, elem(tree, &1).rotation}),
      skins:
        Enum.map(skins, fn skin ->
          %{
            joints: Enum.map(skin.joints, &Map.fetch!(bones, &1)),
            inverse_binds: Enum.map(skin.inverse_binds, &rows/1)
          }
        end)
    }
  end

  @doc "The bone of node `node`."
  @spec bone(t(), non_neg_integer()) :: non_neg_integer()
  def bone(%__MODULE__{bones: bones}, node), do: Map.fetch!(bones, node)

  @doc "The rest pose with the bones in `turns` (bone => rotation) given those rotations instead."
  @spec locals(t(), %{non_neg_integer() => Quat.t()}) :: [{Vec.t(), Quat.t()}]
  def locals(%__MODULE__{rest: rest}, turns) do
    rest
    |> Enum.with_index()
    |> Enum.map(fn {{position, rotation}, bone} -> {position, Map.get(turns, bone, rotation)} end)
  end

  @doc "Every bone's transform, the bones in `turns` turned, the whole placed by `root`."
  @spec pose(t(), %{non_neg_integer() => Quat.t()}, Skeleton.transform()) :: tuple()
  def pose(%__MODULE__{} = rig, turns, root \\ Skeleton.identity()),
    do: Skeleton.pose(rig.parents, locals(rig, turns), root)

  @doc """
  Every bone's transform with the translations and rotations of `sample`
  (`Cauldron3D.Formats.Gltf.Clip.sample/3`, keyed by node) in place of the rest pose's, the
  whole placed by `root`. Bones the sample does not move keep their rest pose.
  """
  @spec pose_sample(t(), map(), Skeleton.transform()) :: tuple()
  def pose_sample(%__MODULE__{} = rig, sample, root \\ Skeleton.identity()) do
    locals =
      rig.rest
      |> Enum.with_index()
      |> Enum.map(fn {{position, rotation}, bone} ->
        node = elem(rig.nodes, bone)
        {Map.get(sample.translations, node, position), Map.get(sample.rotations, node, rotation)}
      end)

    Skeleton.pose(rig.parents, locals, root)
  end

  @doc """
  The matrices posing skin `skin` from `transforms` (as `pose/3` gives them), each joint's
  transform taken back through `unroot` first, so the result is in the space `root` placed
  the rig in.
  """
  @spec bones(t(), tuple(), non_neg_integer(), Skeleton.transform()) :: [[float()]]
  def bones(%__MODULE__{skins: skins}, transforms, skin, unroot \\ Skeleton.identity()) do
    %{joints: joints, inverse_binds: inverse_binds} = Enum.at(skins, skin)

    Enum.zip_with(joints, inverse_binds, fn bone, inverse_bind ->
      unroot
      |> Skeleton.concat(elem(transforms, bone))
      |> Skeleton.concat(inverse_bind)
      |> flatten()
    end)
  end

  @doc "The transform undoing `transform`, which turns and moves but does not scale."
  @spec invert(Skeleton.transform()) :: Skeleton.transform()
  def invert({{a, b, c, tx}, {d, e, f, ty}, {g, h, i, tz}}) do
    {{a, d, g, -(a * tx + d * ty + g * tz)}, {b, e, h, -(b * tx + e * ty + h * tz)},
     {c, f, i, -(c * tx + f * ty + i * tz)}}
  end

  defp below(tree, node), do: [node | Enum.flat_map(elem(tree, node).children, &below(tree, &1))]

  defp parent_bone(tree, bones, node) do
    case elem(tree, node).parent do
      nil -> -1
      parent -> Map.fetch!(bones, parent)
    end
  end

  defp rows(m) do
    {{elem(m, 0), elem(m, 4), elem(m, 8), elem(m, 12)},
     {elem(m, 1), elem(m, 5), elem(m, 9), elem(m, 13)},
     {elem(m, 2), elem(m, 6), elem(m, 10), elem(m, 14)}}
  end

  defp flatten({{a, b, c, d}, {e, f, g, h}, {i, j, k, l}}),
    do: [a, b, c, d, e, f, g, h, i, j, k, l]
end
