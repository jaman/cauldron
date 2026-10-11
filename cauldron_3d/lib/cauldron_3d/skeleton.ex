defmodule Cauldron3D.Skeleton do
  @moduledoc """
  Bones posed into place: each bone's own position and rotation relative to its parent,
  turned into a transform from the bone's space to the model's.

  A transform is three rows `{{r00, r01, r02, tx}, {r10, r11, r12, ty}, {r20, r21, r22,
  tz}}`: a point `p` goes to `{row0 · p + tx, row1 · p + ty, row2 · p + tz}`.

      parents = {-1, 0, 1}
      locals = [{{0.0, 0.0, 0.0}, q0}, {{0.0, 0.0, 10.0}, q1}, {{0.0, 0.0, 10.0}, q2}]
      transforms = Cauldron3D.Skeleton.pose(parents, locals)
      Cauldron3D.Skeleton.apply(elem(transforms, 2), {0.0, 0.0, 0.0})

  A bone's parent comes before it; `-1` marks a bone with none.
  """

  alias Cauldron3D.{Quat, Vec}

  @type transform :: {tuple(), tuple(), tuple()}

  @doc "The transform that changes nothing."
  @spec identity() :: transform()
  def identity, do: {{1.0, 0.0, 0.0, 0.0}, {0.0, 1.0, 0.0, 0.0}, {0.0, 0.0, 1.0, 0.0}}

  @doc "The transform of a rotation `q` followed by a move to `position`."
  @spec transform(Vec.t(), Quat.t()) :: transform()
  def transform({tx, ty, tz}, q) do
    {{a, b, c}, {d, e, f}, {g, h, i}} = Quat.to_rows(q)
    {{a, b, c, tx}, {d, e, f, ty}, {g, h, i, tz}}
  end

  @doc "The transform doing `inner` and then `outer`."
  @spec concat(transform(), transform()) :: transform()
  def concat({o0, o1, o2}, {i0, i1, i2}) do
    {row(o0, i0, i1, i2), row(o1, i0, i1, i2), row(o2, i0, i1, i2)}
  end

  @doc "Each bone's transform into the model's space, `root` applied to the bones without a parent."
  @spec pose(tuple(), [{Vec.t(), Quat.t()}], transform()) :: tuple()
  def pose(parents, locals, root \\ identity()) do
    locals
    |> Enum.with_index()
    |> Enum.reduce({}, fn {{position, q}, bone}, done ->
      own = transform(position, q)

      world =
        case elem(parents, bone) do
          parent when parent >= 0 and parent < tuple_size(done) -> concat(elem(done, parent), own)
          _ -> concat(root, own)
        end

      Tuple.insert_at(done, tuple_size(done), world)
    end)
  end

  @doc "Point `point` moved by `transform`."
  @spec apply(transform(), Vec.t()) :: Vec.t()
  def apply({{a, b, c, tx}, {d, e, f, ty}, {g, h, i, tz}}, {x, y, z}),
    do: {a * x + b * y + c * z + tx, d * x + e * y + f * z + ty, g * x + h * y + i * z + tz}

  @doc "Direction `vector` turned by `transform`, its move left out."
  @spec rotate(transform(), Vec.t()) :: Vec.t()
  def rotate({{a, b, c, _}, {d, e, f, _}, {g, h, i, _}}, {x, y, z}),
    do: {a * x + b * y + c * z, d * x + e * y + f * z, g * x + h * y + i * z}

  @doc "Where `transform` puts the origin."
  @spec origin(transform()) :: Vec.t()
  def origin({{_, _, _, tx}, {_, _, _, ty}, {_, _, _, tz}}), do: {tx, ty, tz}

  defp row({a, b, c, t}, {i00, i01, i02, i03}, {i10, i11, i12, i13}, {i20, i21, i22, i23}) do
    {a * i00 + b * i10 + c * i20, a * i01 + b * i11 + c * i21, a * i02 + b * i12 + c * i22,
     a * i03 + b * i13 + c * i23 + t}
  end
end
