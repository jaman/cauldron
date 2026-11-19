defmodule Cauldron2D.Heading do
  @moduledoc """
  Headings by name or in radians.

  A heading is radians in world tiles, `0.0` along `+x` and `:math.pi() / 2` along `+y`
  (down the screen). A scene may give a mover's heading, or its own `:heading`, as a
  compass name instead:

      {:car, {3.5, 7}, :east}
      {:villager, {x, y}, :south_west}

  | name          | radians    |
  | ------------- | ---------- |
  | `:east`       | `0`        |
  | `:south_east` | `π / 4`    |
  | `:south`      | `π / 2`    |
  | `:south_west` | `3π / 4`   |
  | `:west`       | `π`        |
  | `:north_west` | `-3π / 4`  |
  | `:north`      | `-π / 2`   |
  | `:north_east` | `-π / 4`   |

  `Cauldron2D.Draw.props/4` and `Cauldron2D.Draw.new/1` turn names into radians, so every
  projection and front end reads numbers.
  """

  @type name ::
          :east
          | :south_east
          | :south
          | :south_west
          | :west
          | :north_west
          | :north
          | :north_east

  @type t :: number() | name()

  @doc "`heading` in radians; a number and `nil` are returned as they are. Raises `ArgumentError` on another atom."
  @spec radians(t() | nil) :: number() | nil
  def radians(nil), do: nil
  def radians(heading) when is_number(heading), do: heading
  def radians(:east), do: 0.0
  def radians(:south_east), do: :math.pi() / 4
  def radians(:south), do: :math.pi() / 2
  def radians(:south_west), do: 3 * :math.pi() / 4
  def radians(:west), do: :math.pi()
  def radians(:north_west), do: -3 * :math.pi() / 4
  def radians(:north), do: -:math.pi() / 2
  def radians(:north_east), do: -:math.pi() / 4

  def radians(other),
    do:
      raise(
        ArgumentError,
        "#{inspect(other)} is not a heading: a number of radians or a compass name"
      )

  @doc "A scene mover with its heading in radians; a mover without one is returned as it is."
  @spec mover(tuple()) :: tuple()
  def mover({art, position, heading}), do: {art, position, radians(heading)}
  def mover({art, position, heading, opts}), do: {art, position, radians(heading), opts}
  def mover(mover), do: mover

  @doc "Scene movers with their headings in radians."
  @spec movers([tuple()]) :: [tuple()]
  def movers(movers), do: Enum.map(movers, &mover/1)
end
