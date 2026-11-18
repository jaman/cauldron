defmodule Vale.Figure do
  @moduledoc """
  The walker: a rigged figure and its clips, each a glTF file made in imachine and copied
  in by `mix vale.figure`.

    * `load/1` — what the world needs to pose it: its rig, its clips by name, how many
      skins it has and the scale and lift that stand it `:height` metres tall (default
      0.9) with its feet on the ground
    * `upload/2` — puts it in a `Cauldron3D.Scene.Target`, answering
      `%{skins: [{id, skin}], instances: %{id => instance}, handles: handles}`
    * `pose/2` — the bone matrices of every skin for a clip sample

  The files live in `folder/0`: `figure.glb`, the figure with its skin, and one
  `<clip>.glb` for each of `clips/0`. A clip file holds the same skeleton; only its
  clip is read.

      {:ok, figure} = Vale.Figure.load()
      sample = Cauldron3D.Formats.Gltf.Clip.sample(figure.clips.walk, 0.3, loop: true)
      Vale.Figure.pose(figure, sample)
  """

  alias Cauldron3D.Formats.Gltf
  alias Cauldron3D.Formats.Gltf.{Clip, Rig}
  alias Cauldron3D.Skeleton

  @clips ~w(idle walk jog sprint fall climb swim tread wave)a
  @first_id 900_000

  @type t :: %__MODULE__{
          rig: Rig.t(),
          clips: %{atom() => map()},
          skins: non_neg_integer(),
          scale: float(),
          lift: float()
        }

  @enforce_keys [:rig, :clips, :skins, :scale, :lift]
  defstruct [:rig, :clips, :skins, :scale, :lift]

  @doc "The clips a figure has, by name."
  @spec clips() :: [atom()]
  def clips, do: @clips

  @doc "The folder the figure's files are kept in."
  @spec folder() :: Path.t()
  def folder do
    root = System.get_env("CAULDRON_ASSETS") || Path.join(:filename.basedir(:user_cache, "cauldron"), "assets")
    Path.join(root, "vale")
  end

  @doc "The file of clip `name`, or of the figure itself for `:figure`."
  @spec file(atom()) :: Path.t()
  def file(name), do: Path.join(folder(), "#{name}.glb")

  @doc "The figure's rig and clips. Option `:height` is how tall it stands, in metres."
  @spec load(keyword()) :: {:ok, t()} | {:error, term()}
  def load(opts \\ []) do
    with {:ok, document} <- document(),
         {:ok, clips} <- read_clips(document) do
      {low, high} = reach(document)
      scale = Keyword.get(opts, :height, 0.9) / (high - low)

      {:ok,
       %__MODULE__{
         rig: Rig.new(document),
         clips: clips,
         skins: length(document.skins),
         scale: scale,
         lift: -low * scale
       }}
    end
  end

  @doc "Uploads the figure to `target`."
  @spec upload(Cauldron3D.Scene.Target.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def upload(target, _opts \\ []) do
    with {:ok, document} <- document(),
         {:ok, placed} <- Cauldron3D.Scene.Gltf.upload(target, document, first_id: @first_id) do
      {:ok,
       %{
         skins: placed.skins,
         handles: placed.handles,
         instances: Map.new(placed.instances, fn {:instance, id, instance} -> {id, instance} end)
       }}
    end
  end

  @doc "The bone matrices of each of the figure's skins for `sample`, by skin."
  @spec pose(t(), Clip.sample()) :: %{non_neg_integer() => [[float()]]}
  def pose(%__MODULE__{rig: rig, skins: skins}, sample) do
    transforms = Rig.pose_sample(rig, sample, Skeleton.identity())
    Map.new(0..(skins - 1)//1, &{&1, Rig.bones(rig, transforms, &1)})
  end

  defp document do
    if File.exists?(file(:figure)),
      do: Gltf.read(file(:figure)),
      else: {:error, {:missing, "mix vale.figure"}}
  end

  defp read_clips(document) do
    Enum.reduce_while(@clips, {:ok, %{}}, fn name, {:ok, clips} ->
      case read_clip(name, document) do
        {:ok, clip} -> {:cont, {:ok, Map.put(clips, name, clip)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp read_clip(name, document) do
    with true <- File.exists?(file(name)) || {:error, {:missing, "mix vale.figure"}},
         {:ok, %Gltf{animations: [clip | _others]} = source} <- Gltf.read(file(name)) do
      {:ok, Clip.onto(clip, source, document)}
    else
      {:ok, %Gltf{animations: []}} -> {:error, {:no_clip, name}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp reach(document) do
    heights =
      for mesh <- document.meshes,
          primitive <- mesh.primitives,
          <<_x::little-float-32, y::little-float-32, _z::little-float-32 <- primitive.positions>>,
          do: y

    Enum.min_max(heights)
  end
end
