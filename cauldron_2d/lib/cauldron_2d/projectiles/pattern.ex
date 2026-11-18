defmodule Cauldron2D.Projectiles.Pattern do
  @moduledoc """
  The shapes shots are fired in, for guns, bosses and turrets: each pattern gives a list
  of `Cauldron2D.Projectiles` shots `%{x, y, vx, vy}` from a point, speeds in tiles a
  second, angles in radians with `0` along `+x` and `y` growing downward.

    * `{:aimed, n, arc}` — `n` shots spread over `arc`, centred on the target (a fan
      when there is none)
    * `{:fan, n, arc}` — `n` shots spread over `arc`, centred on the heading
    * `{:ring, n}` — `n` shots all round, turned by the phase; a phase that grows with
      time turns successive rings into a spiral
    * `{:rain, n}` — `n` shots along the heading, side by side a tile apart

      Cauldron2D.Projectiles.Pattern.fire({:ring, 12}, {x, y}, nil, 6.0, phase: clock * 1.3)

  Options: `:heading`, the direction a fan or rain fires along (default `:math.pi() / 2`,
  straight down), and `:phase` (default `0`).
  """

  @type t ::
          {:aimed, pos_integer(), number()}
          | {:fan, pos_integer(), number()}
          | {:ring, pos_integer()}
          | {:rain, pos_integer()}
  @type point :: {number(), number()}

  @doc "The shots of `pattern` fired from `from` at `target` (`nil` for none), at `speed`."
  @spec fire(t(), point(), point() | nil, number(), keyword()) :: [
          Cauldron2D.Projectiles.shot()
        ]
  def fire(pattern, from, target, speed, opts \\ [])

  def fire({:aimed, n, arc}, from, nil, speed, opts),
    do: fire({:fan, n, arc}, from, nil, speed, opts)

  def fire({:aimed, n, arc}, {x, y} = from, {tx, ty}, speed, _opts),
    do: spread(from, :math.atan2(ty - y, tx - x), n, arc, speed)

  def fire({:fan, n, arc}, from, _target, speed, opts),
    do: spread(from, heading(opts), n, arc, speed)

  def fire({:ring, n}, from, _target, speed, opts) do
    phase = Keyword.get(opts, :phase, 0)
    for index <- 0..(n - 1), do: shot(from, phase + index * 2 * :math.pi() / n, speed)
  end

  def fire({:rain, n}, {x, y}, _target, speed, opts) do
    heading = heading(opts)
    {across_x, across_y} = {:math.sin(heading), -:math.cos(heading)}

    for index <- 0..(n - 1) do
      offset = index - (n - 1) / 2
      shot({x + across_x * offset, y + across_y * offset}, heading, speed)
    end
  end

  defp heading(opts), do: Keyword.get(opts, :heading, :math.pi() / 2)

  defp spread(from, heading, 1, _arc, speed), do: [shot(from, heading, speed)]

  defp spread(from, heading, n, arc, speed) do
    for index <- 0..(n - 1), do: shot(from, heading - arc / 2 + index * arc / (n - 1), speed)
  end

  defp shot({x, y}, angle, speed),
    do: %{x: x / 1, y: y / 1, vx: :math.cos(angle) * speed, vy: :math.sin(angle) * speed}
end
