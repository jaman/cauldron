if Code.ensure_loaded?(Cauldron3D.Formats.Gltf.Rig) do
  defmodule Cauldron3D.Scene.Gltf.Animator do
    @moduledoc """
    Plays a glTF document's clips on the instances `Cauldron3D.Scene.Gltf.upload/3` placed.

        {:ok, document} = Cauldron3D.Formats.Gltf.read("hero.glb")
        {:ok, placed} = Cauldron3D.Scene.Gltf.upload(target, document)
        animator = Cauldron3D.Scene.Gltf.Animator.new(document, placed)
        walk = Enum.find(document.animations, &(&1.name == "Walk"))

        sample = Cauldron3D.Formats.Gltf.Clip.sample(walk, seconds, loop: true)
        Cauldron3D.Scene.Target.submit(target, Cauldron3D.Scene.Gltf.Animator.poses(animator, sample))

    `poses/2` gives one `{:pose, id, %Cauldron3D.Scene.Pose{}}` for each skinned instance and each
    instance with morph targets: the skin's bone matrices for the sample, and the morph
    weights the sample sets for the instance's node (the mesh's own weights where it sets
    none). Mix clips with `Cauldron3D.Formats.Gltf.Clip.blend/3` before posing.

    Nodes without a skin that a clip translates, turns or scales are not moved.
    """

    alias Cauldron3D.Formats.Gltf
    alias Cauldron3D.Formats.Gltf.{Clip, Rig}
    alias Cauldron3D.Scene.Pose

    @type t :: %__MODULE__{
            rig: Rig.t(),
            skins: %{pos_integer() => non_neg_integer()},
            morphs: %{pos_integer() => {non_neg_integer(), [float()]}}
          }

    @enforce_keys [:rig, :skins, :morphs]
    defstruct [:rig, :skins, :morphs]

    @doc "An animator for `document`, whose instances were placed as `placed` (`Cauldron3D.Scene.Gltf.upload/3`'s result)."
    @spec new(Gltf.t(), map()) :: t()
    def new(document, %{skins: skins, morphs: morphs}) do
      %__MODULE__{
        rig: Rig.new(document),
        skins: Map.new(skins),
        morphs: Map.new(morphs, fn {id, node, weights} -> {id, {node, weights}} end)
      }
    end

    @doc "The poses for `sample` (`Cauldron3D.Formats.Gltf.Clip.sample/3`); the rest pose for none."
    @spec poses(t(), Clip.sample()) :: [{:pose, pos_integer(), Pose.t()}]
    def poses(%__MODULE__{} = animator, sample \\ Clip.empty()) do
      transforms = Rig.pose_sample(animator.rig, sample)

      animator.skins
      |> Map.keys()
      |> Enum.concat(Map.keys(animator.morphs))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(fn id ->
        {:pose, id,
         %Pose{
           bones: bones(animator, transforms, id),
           weights: weights(animator, sample, id)
         }}
      end)
    end

    defp bones(animator, transforms, id) do
      case Map.fetch(animator.skins, id) do
        {:ok, skin} -> Rig.bones(animator.rig, transforms, skin)
        :error -> []
      end
    end

    defp weights(animator, sample, id) do
      case Map.fetch(animator.morphs, id) do
        {:ok, {node, defaults}} -> sampled(Map.get(sample.weights, node), defaults)
        :error -> []
      end
    end

    defp sampled(nil, defaults), do: defaults

    defp sampled(weights, defaults),
      do:
        weights |> Kernel.++(Enum.drop(defaults, length(weights))) |> Enum.take(length(defaults))
  end
end
