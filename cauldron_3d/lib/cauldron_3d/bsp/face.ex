defmodule Cauldron3D.Bsp.Face do
  @moduledoc """
  One face of a BSP world: a convex polygon on a plane, painted with a texture and lit
  by a lightmap.

    * `plane` — the plane index; `back?` true when the face looks along the plane's back
    * `points` — the corners, in order
    * `texture` — the texture index
    * `s`, `t` — `{axis, offset}`: a point's place on the texture is
      `Vec.dot(point, axis) + offset` across and down
    * `mins`, `extents` — `{s, t}`: where the lightmap starts on the texture and how far
      it reaches, multiples of `luxel`
    * `lightmap` — the byte offset of the face's samples in the world's lightmaps, or
      `nil` for an unlit face
    * `styles` — up to four light style numbers, one lightmap of
      `(div(s_extent, luxel) + 1) * (div(t_extent, luxel) + 1)` samples each, in order
    * `luxel` — how many texture pixels one lightmap sample covers, 16 by default
  """

  alias Cauldron3D.Vec

  @type t :: %__MODULE__{
          plane: non_neg_integer(),
          back?: boolean(),
          points: [Vec.t()],
          texture: non_neg_integer(),
          s: {Vec.t(), float()},
          t: {Vec.t(), float()},
          mins: {integer(), integer()},
          extents: {non_neg_integer(), non_neg_integer()},
          lightmap: non_neg_integer() | nil,
          styles: [non_neg_integer()],
          luxel: pos_integer()
        }

  defstruct plane: 0,
            back?: false,
            points: [],
            texture: 0,
            s: {{1.0, 0.0, 0.0}, 0.0},
            t: {{0.0, 1.0, 0.0}, 0.0},
            mins: {0, 0},
            extents: {0, 0},
            lightmap: nil,
            styles: [],
            luxel: 16

  @doc "Where a point lies on the face's texture, `{s, t}`."
  @spec st(t(), Vec.t()) :: {float(), float()}
  def st(%__MODULE__{s: {s_axis, s_offset}, t: {t_axis, t_offset}}, point),
    do: {Vec.dot(point, s_axis) + s_offset, Vec.dot(point, t_axis) + t_offset}

  @doc """
  The face with `mins` and `extents` worked out from its points: the smallest and largest
  texture place, out to whole luxels.
  """
  @spec measured(t()) :: t()
  def measured(%__MODULE__{luxel: luxel} = face) do
    {ss, ts} = face.points |> Enum.map(&st(face, &1)) |> Enum.unzip()
    s_min = floor(Enum.min(ss) / luxel) * luxel
    t_min = floor(Enum.min(ts) / luxel) * luxel
    s_max = ceil(Enum.max(ss) / luxel) * luxel
    t_max = ceil(Enum.max(ts) / luxel) * luxel
    %{face | mins: {s_min, t_min}, extents: {s_max - s_min, t_max - t_min}}
  end

  @doc "The lightmap's size in samples, `{across, down}`."
  @spec lightmap_size(t()) :: {pos_integer(), pos_integer()}
  def lightmap_size(%__MODULE__{extents: {s_extent, t_extent}, luxel: luxel}),
    do: {div(s_extent, luxel) + 1, div(t_extent, luxel) + 1}

  @doc "The middle of the face's corners."
  @spec centre(t()) :: Vec.t()
  def centre(%__MODULE__{points: points}),
    do: points |> Enum.reduce(&Vec.add/2) |> Vec.scale(1 / length(points))
end
