defmodule Cauldron2D.Assets.Spec do
  @moduledoc """
  One picture a game asks for: the words, the model and its settings, and how the
  picture is finished as pixel art. `Cauldron2D.Assets.Manifest` makes them.

  A spec with `from` is an edit: the picture chosen for asset `from`, drawn again as its
  `prompt` instructs. With `video` as well it is an animation: that picture set moving
  as `prompt` says, and frames of the clip kept (`Cauldron2D.Assets.Frames`).

  A spec with `rig` is an animation of a rigged 3D character in the Studio: a body
  movement made from `motion`'s description, posed on the rig and rendered there
  (`motion` holds the movement and how it is shown), and frames of it kept.

  `digest/2` changes whenever anything that decides what the model draws changes — for an
  edit, the picture it starts from too — so a built picture is asked for again only then;
  the finishing does not count, since it is done again from the picture kept in the
  Studio.
  """

  @enforce_keys [:name, :prompt, :model, :size, :count]
  defstruct [
    :name,
    :prompt,
    :negative,
    :model,
    :size,
    :count,
    :seed,
    :from,
    :video,
    :rig,
    :motion,
    finish: []
  ]

  @type t :: %__MODULE__{
          name: atom(),
          prompt: String.t(),
          negative: String.t() | nil,
          model: String.t(),
          size: {pos_integer(), pos_integer()},
          count: pos_integer(),
          seed: non_neg_integer() | nil,
          from: atom() | nil,
          video: keyword() | nil,
          rig: String.t() | nil,
          motion: keyword() | nil,
          finish: keyword()
        }

  @doc "A number for everything that decides what the model draws, `source` the library id an edit starts from."
  @spec digest(t(), String.t() | nil) :: non_neg_integer()
  def digest(spec, source \\ nil)

  def digest(%__MODULE__{rig: rig} = spec, nil) when rig != nil,
    do:
      :erlang.phash2(
        {:rig, motion_request(spec, nil, nil), animation_request(spec, nil, nil), spec.count,
         spec.seed}
      )

  def digest(%__MODULE__{video: nil} = spec, nil),
    do: :erlang.phash2({spec.prompt, spec.negative, spec.model, spec.size, spec.count, spec.seed})

  def digest(%__MODULE__{} = spec, nil),
    do:
      :erlang.phash2(
        {%{spec | video: nil} |> digest(nil), Keyword.take(spec.video, [:model, :frames])}
      )

  def digest(%__MODULE__{} = spec, source), do: :erlang.phash2({digest(spec, nil), source})

  @doc "The Studio's `edit_image` arguments for an edit of library item `source`, in `project`."
  @spec edit_request(t(), String.t(), String.t()) :: map()
  def edit_request(%__MODULE__{} = spec, source, project) do
    %{
      image: source,
      prompt: spec.prompt,
      mode: "instruct",
      model: spec.model,
      count: spec.count,
      project: project
    }
    |> put_some(:seed, spec.seed)
  end

  @doc "The Studio's `make_video` arguments for an animation of library item `source`, in `project`."
  @spec video_request(t(), String.t(), String.t()) :: map()
  def video_request(%__MODULE__{video: video, size: {width, height}} = spec, source, project) do
    %{
      start_image: source,
      prompt: spec.prompt,
      model: Keyword.get(video, :model, "wan21_vace_1_3b"),
      frames: Keyword.get(video, :frames, 33),
      width: width,
      height: height,
      project: project
    }
    |> put_some(:seed, spec.seed)
    |> put_some(:negative_prompt, spec.negative)
  end

  @doc "The Studio's `make_motion` arguments for a rigged animation's movement, made with `seed`, in `project`."
  @spec motion_request(t(), non_neg_integer(), String.t()) :: map()
  def motion_request(%__MODULE__{motion: motion}, seed, project) do
    %{
      prompt: Keyword.fetch!(motion, :prompt),
      seconds: Keyword.get(motion, :seconds, 4),
      seed: seed,
      project: project
    }
    |> put_some(:model, motion[:model])
  end

  @doc """
  The Studio's `make_animation` arguments for the rig posed by library motion `motion_id`,
  in `project`. A loop is rendered `keep` frames long, so every frame is kept.
  """
  @spec animation_request(t(), String.t(), String.t()) :: map()
  def animation_request(%__MODULE__{rig: rig, motion: motion}, motion_id, project) do
    %{rig: rig, motion: motion_id, yaw: Keyword.get(motion, :yaw, 90), project: project}
    |> put_some(:loop, motion[:loop])
    |> put_some(:frames, if(motion[:loop], do: motion[:keep]))
    |> put_some(:arm_swing, motion[:arm_swing] && Map.new(motion[:arm_swing]))
  end

  @doc "The Studio's `generate_image` arguments for the spec, in `project`."
  @spec request(t(), String.t()) :: map()
  def request(%__MODULE__{size: {width, height}} = spec, project) do
    %{
      prompt: spec.prompt,
      model: spec.model,
      width: width,
      height: height,
      count: spec.count,
      project: project
    }
    |> put_some(:seed, spec.seed)
    |> put_some(:negative_prompt, spec.negative)
  end

  defp put_some(map, _key, nil), do: map
  defp put_some(map, key, value), do: Map.put(map, key, value)
end
