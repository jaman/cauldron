defmodule Cauldron3D.SpringBones do
  @moduledoc """
  Bones that swing on their own, such as hair, sleeves and skirts, posed with the rest of
  a skeleton (`Cauldron3D.Skeleton`). Each chain starts at a bone and takes in every bone
  under it. Each spring bone keeps the end of a stick (its tail) in the world: the tail
  carries on with the speed it had, less `:drag`, is pulled back towards the bone's rest
  direction by `:stiffness` and down `:gravity` by `:gravity_power`, stays the bone's
  length away, and is pushed out of the chain's collision spheres by `:hit_radius`. The
  bone then turns to point at its tail.

  A bone's own position and rotation are those of `Cauldron3D.Skeleton.pose/3`: `parents`
  with each bone's parent before it, and `locals`, `{position, rotation}` relative to the
  parent. A bone with children points at its first child; a bone without points on along
  the line from its parent, 7 cm long. Scale is not applied.

      springs = Cauldron3D.SpringBones.new(parents, locals, root, chains, colliders)
      {transforms, springs} = Cauldron3D.SpringBones.pose(springs, parents, locals, root, 1 / 60)

  A chain is a map with `:bones` (the bones it starts at), `:stiffness`, `:drag` (`0.0` to
  `1.0`), `:gravity` (a direction), `:gravity_power`, `:hit_radius` and `:colliders`
  (indices into `colliders`). A collider is `%{bone: bone, spheres: [{offset, radius}]}`,
  each offset in the bone's space. `root` is the transform the skeleton is placed by, so
  the tails swing as the whole skeleton moves. Steps longer than `max_step/0` are taken as
  that long.
  """

  alias Cauldron3D.{Quat, Skeleton, Vec}

  @leaf_length 0.07
  @max_step 1 / 30

  @type collider :: %{bone: non_neg_integer(), spheres: [{Vec.t(), float()}]}
  @type chain :: %{
          bones: [non_neg_integer()],
          stiffness: float(),
          drag: float(),
          gravity: Vec.t(),
          gravity_power: float(),
          hit_radius: float(),
          colliders: [non_neg_integer()]
        }
  @type t :: %__MODULE__{joints: %{non_neg_integer() => map()}, colliders: [collider()]}

  @enforce_keys [:joints, :colliders]
  defstruct [:joints, :colliders]

  @doc "The longest step `pose/5` takes, in seconds."
  @spec max_step() :: float()
  def max_step, do: @max_step

  @doc "Spring bones at rest for the skeleton placed by `root`."
  @spec new(tuple(), [{Vec.t(), Quat.t()}], Skeleton.transform(), [chain()], [collider()]) ::
          t()
  def new(parents, locals, root, chains, colliders) do
    rest = Skeleton.pose(parents, locals, root)
    locals = List.to_tuple(locals)
    children = children(parents)

    joints =
      for chain <- chains,
          start <- chain.bones,
          bone <- [start | descendants(children, start)],
          into: %{} do
        {bone, joint(bone, chain, locals, children, rest)}
      end

    %__MODULE__{joints: joints, colliders: colliders}
  end

  @doc """
  Every bone's transform, as `Cauldron3D.Skeleton.pose/3` gives them, with the spring bones
  moved on by `dt` seconds, and the springs as they now are.
  """
  @spec pose(t(), tuple(), [{Vec.t(), Quat.t()}], Skeleton.transform(), number()) ::
          {tuple(), t()}
  def pose(%__MODULE__{} = springs, parents, locals, root, dt) do
    dt = dt |> max(0.0) |> min(@max_step)
    unswung = Skeleton.pose(parents, locals, root)
    spheres = spheres(springs.colliders, unswung)

    {transforms, joints} =
      locals
      |> Enum.with_index()
      |> Enum.reduce({{}, springs.joints}, fn {{position, rotation}, bone}, {done, joints} ->
        parent = parent_transform(parents, bone, done, root)

        case joints do
          %{^bone => joint} ->
            {own, joint} = swing(joint, parent, position, rotation, spheres, dt)
            {Tuple.insert_at(done, tuple_size(done), own), Map.put(joints, bone, joint)}

          _rigid ->
            own = Skeleton.concat(parent, Skeleton.transform(position, rotation))
            {Tuple.insert_at(done, tuple_size(done), own), joints}
        end
      end)

    {transforms, %{springs | joints: joints}}
  end

  defp joint(bone, chain, locals, children, rest) do
    {position, rotation} = elem(locals, bone)

    {axis, length} =
      case Map.get(children, bone, []) do
        [child | _] ->
          {offset, _rotation} = elem(locals, child)
          {Vec.normalize(offset), Vec.length(offset)}

        [] ->
          {Quat.rotate(Quat.conjugate(rotation), Vec.normalize(position)), @leaf_length}
      end

    world = elem(rest, bone)
    tail = Skeleton.apply(world, Vec.scale(axis, length))

    %{
      axis: axis,
      length: length,
      tail: tail,
      previous: tail,
      stiffness: chain.stiffness,
      drag: chain.drag,
      gravity: Vec.scale(Vec.normalize(chain.gravity), chain.gravity_power),
      hit_radius: chain.hit_radius,
      colliders: chain.colliders
    }
  end

  defp swing(joint, parent, position, rotation, spheres, dt) do
    origin = Skeleton.apply(parent, position)
    rest_axis = Quat.rotate(rotation, joint.axis)
    pulled = Skeleton.rotate(parent, rest_axis)

    next =
      joint.tail
      |> Vec.madd(Vec.sub(joint.tail, joint.previous), 1.0 - joint.drag)
      |> Vec.madd(pulled, joint.stiffness * dt)
      |> Vec.madd(joint.gravity, dt)
      |> at_length(origin, joint.length)
      |> pushed_out(joint, spheres, origin)

    turned = Quat.from_to(rest_axis, unrotate(parent, Vec.sub(next, origin)))
    own = Skeleton.concat(parent, Skeleton.transform(position, Quat.multiply(turned, rotation)))
    {own, %{joint | previous: joint.tail, tail: next}}
  end

  defp pushed_out(point, joint, spheres, origin) do
    joint.colliders
    |> Enum.flat_map(&Enum.at(spheres, &1, []))
    |> Enum.reduce(point, fn {centre, radius}, point ->
      reach = radius + joint.hit_radius
      away = Vec.sub(point, centre)

      if Vec.length(away) < reach,
        do: centre |> Vec.madd(Vec.normalize(away), reach) |> at_length(origin, joint.length),
        else: point
    end)
  end

  defp at_length(point, origin, length),
    do: Vec.madd(origin, Vec.normalize(Vec.sub(point, origin)), length)

  defp spheres(colliders, transforms) do
    for %{bone: bone, spheres: spheres} <- colliders do
      transform = elem(transforms, bone)
      for {offset, radius} <- spheres, do: {Skeleton.apply(transform, offset), radius}
    end
  end

  defp parent_transform(parents, bone, done, root) do
    case elem(parents, bone) do
      parent when parent >= 0 and parent < tuple_size(done) -> elem(done, parent)
      _none -> root
    end
  end

  defp unrotate({{a, b, c, _}, {d, e, f, _}, {g, h, i, _}}, {x, y, z}),
    do: {a * x + d * y + g * z, b * x + e * y + h * z, c * x + f * y + i * z}

  defp children(parents) do
    parents
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Enum.reject(fn {parent, _bone} -> parent < 0 end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp descendants(children, bone) do
    children
    |> Map.get(bone, [])
    |> Enum.flat_map(&[&1 | descendants(children, &1)])
  end
end
