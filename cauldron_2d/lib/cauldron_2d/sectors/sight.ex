defmodule Cauldron2D.Sectors.Sight do
  @moduledoc """
  Whether one point in a sector map can see a body: the straight line between them must
  pass through every opening it crosses, between floor and ceiling.

      Cauldron2D.Sectors.Sight.visible?(world, {x, y, eye_z}, %{x: tx, y: ty, z: tz, height: 56.0})

  `world` is `%{map:, blockmap:, sectors:}` as `Cauldron2D.Sectors.Move` takes it. The
  look is a wedge from the eye to the target's feet and head; each opening crossed narrows
  it by its floor and its ceiling, and a one-sided line or a closed opening ends it. Bodies
  never block sight.

  A level may carry a table of sector pairs known never to see each other; pass it as
  `reject: {bits, sector_count}` and those pairs are answered at once.
  """

  alias Cauldron2D.Sectors.Map, as: SectorMap
  alias Cauldron2D.Sectors.{Move, Trace}

  @doc "Whether `eye` — `{x, y, z}` — sees any of `target`. See the moduledoc."
  @spec visible?(Move.world(), {number(), number(), number()}, map(), keyword()) :: boolean()
  def visible?(world, {x, y, eye_z} = eye, target, opts \\ []) do
    if rejected?(world, {x, y}, target, Keyword.get(opts, :reject)) do
      false
    else
      clear?(world, eye, target, eye_z)
    end
  end

  defp rejected?(_world, _from, _target, nil), do: false

  defp rejected?(world, from, target, {bits, count}) do
    s1 = SectorMap.sector_at(world.map, from)
    s2 = SectorMap.sector_at(world.map, {target.x, target.y})
    bit = s1 * count + s2
    byte = div(bit, 8)

    byte < byte_size(bits) and
      Bitwise.band(:binary.at(bits, byte), Bitwise.bsl(1, rem(bit, 8))) != 0
  end

  defp clear?(world, {x, y, _z}, target, eye_z) do
    total = :math.sqrt((target.x - x) * (target.x - x) + (target.y - y) * (target.y - y))

    if total < 1.0e-6 do
      true
    else
      top = (target.z + target.height - eye_z) / total
      bottom = (target.z - eye_z) / total

      world.map
      |> Trace.run(world.blockmap, {x, y}, {target.x, target.y}, bodies: false)
      |> Enum.reduce_while({top, bottom}, &narrow(world, &1, &2, total, eye_z))
      |> then(&(&1 != :blocked))
    end
  end

  defp narrow(world, %{fraction: fraction, line: index}, {top, bottom}, total, eye_z) do
    case Move.opening(world, index) do
      nil ->
        {:halt, :blocked}

      %{bottom: floor, top: ceiling} when floor >= ceiling ->
        {:halt, :blocked}

      opening ->
        distance = max(total * fraction, 1.0e-6)
        front = elem(world.sectors, SectorMap.side_sector(world.map, index, 0))
        back = elem(world.sectors, SectorMap.side_sector(world.map, index, 1))

        bottom =
          if front.floor != back.floor,
            do: max(bottom, (opening.bottom - eye_z) / distance),
            else: bottom

        top =
          if front.ceiling != back.ceiling,
            do: min(top, (opening.top - eye_z) / distance),
            else: top

        if top <= bottom, do: {:halt, :blocked}, else: {:cont, {top, bottom}}
    end
  end
end
