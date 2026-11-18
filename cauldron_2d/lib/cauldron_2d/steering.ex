defmodule Cauldron2D.Steering do
  @moduledoc """
  Steering for things that move freely — birds, ships, bats, seeking missiles — after
  Craig Reynolds' behaviours: each gives the velocity an agent wants, and `steer/4` turns
  the agent's velocity toward it no faster than its force allows. For movement across a
  grid, see `Cauldron2D.Steer` and `Cauldron2D.Grid.Path`.

  An agent is a map with `:x`, `:y`, `:vx` and `:vy` (tiles, tiles a second) and anything
  of the game's own.

      wanted = Cauldron2D.Steering.arrive(bat, {hero.x, hero.y - 2.0}, 6.0, 3.0)
      bat = Cauldron2D.Steering.steer(bat, wanted, 20.0, dt)

  Behaviours combine by adding their velocities, weighted, before steering:
  `Cauldron2D.Steering.blend([{seek, 1.0}, {separation, 1.5}])`.
  """

  @type agent :: %{
          required(:x) => number(),
          required(:y) => number(),
          required(:vx) => number(),
          required(:vy) => number(),
          optional(atom()) => term()
        }
  @type vector :: {number(), number()}
  @type point :: {number(), number()}

  @doc "Straight toward `target` at `speed`."
  @spec seek(agent(), point(), number()) :: vector()
  def seek(agent, {tx, ty}, speed), do: toward({tx - agent.x, ty - agent.y}, speed)

  @doc "Straight away from `threat` at `speed`."
  @spec flee(agent(), point(), number()) :: vector()
  def flee(agent, {tx, ty}, speed), do: toward({agent.x - tx, agent.y - ty}, speed)

  @doc "Toward `target` at `speed`, slowing within `slowing` tiles to stop on it."
  @spec arrive(agent(), point(), number(), number()) :: vector()
  def arrive(agent, {tx, ty}, speed, slowing) do
    offset = {tx - agent.x, ty - agent.y}
    far = magnitude(offset)
    toward(offset, if(far < slowing, do: speed * far / slowing, else: speed))
  end

  @doc "Toward where `quarry` (an agent) will be, judged by how long reaching it would take at `speed`."
  @spec pursue(agent(), agent(), number()) :: vector()
  def pursue(agent, quarry, speed), do: seek(agent, ahead(agent, quarry, speed), speed)

  @doc "Away from where `threat` (an agent) will be."
  @spec evade(agent(), agent(), number()) :: vector()
  def evade(agent, threat, speed), do: flee(agent, ahead(agent, threat, speed), speed)

  @doc """
  An aimless drift at `speed`: the heading `angle` (radians) turns by up to `jitter`
  radians each call, drawn from `rng` (`Cauldron.Rng`). Returns the velocity, the new
  heading and the generator, so the game keeps both.
  """
  @spec wander(number(), number(), number(), Cauldron.Rng.t()) ::
          {vector(), number(), Cauldron.Rng.t()}
  def wander(angle, speed, jitter, rng) do
    {draw, rng} = Cauldron.Rng.between(rng, -1000, 1000)
    angle = angle + draw / 1000 * jitter
    {{:math.cos(angle) * speed, :math.sin(angle) * speed}, angle, rng}
  end

  @doc "Away from every one of `others` nearer than `reach` tiles, harder the nearer, at most `speed`."
  @spec separation(agent(), [point()], number(), number()) :: vector()
  def separation(agent, others, reach, speed) do
    {x, y} =
      Enum.reduce(others, {0.0, 0.0}, fn {ox, oy}, {sx, sy} ->
        offset = {agent.x - ox, agent.y - oy}
        far = magnitude(offset)

        if far > 0 and far < reach do
          {ux, uy} = toward(offset, (reach - far) / reach)
          {sx + ux, sy + uy}
        else
          {sx, sy}
        end
      end)

    clamp({x * speed, y * speed}, speed)
  end

  @doc "The sum of weighted velocities, `[{velocity, weight}]`."
  @spec blend([{vector(), number()}]) :: vector()
  def blend(weighted) do
    Enum.reduce(weighted, {0.0, 0.0}, fn {{x, y}, weight}, {sx, sy} ->
      {sx + x * weight, sy + y * weight}
    end)
  end

  @doc """
  The agent after `dt` seconds of turning its velocity toward `wanted`, changing it by no
  more than `force` tiles a second each second, then moving by it.
  """
  @spec steer(agent(), vector(), number(), number()) :: agent()
  def steer(agent, {wx, wy}, force, dt) do
    {ax, ay} = clamp({wx - agent.vx, wy - agent.vy}, force * dt)
    {vx, vy} = {agent.vx + ax, agent.vy + ay}
    %{agent | vx: vx, vy: vy, x: agent.x + vx * dt, y: agent.y + vy * dt}
  end

  defp ahead(agent, quarry, speed) do
    time = magnitude({quarry.x - agent.x, quarry.y - agent.y}) / max(speed, 0.001)
    {quarry.x + quarry.vx * time, quarry.y + quarry.vy * time}
  end

  defp toward({0, 0}, _speed), do: {0.0, 0.0}
  defp toward({x, y}, _speed) when x == 0 and y == 0, do: {0.0, 0.0}

  defp toward({x, y} = vector, speed) do
    far = magnitude(vector)
    {x / far * speed, y / far * speed}
  end

  defp clamp(vector, most) do
    far = magnitude(vector)
    if far > most, do: toward(vector, most), else: vector
  end

  defp magnitude({x, y}), do: :math.sqrt(x * x + y * y)
end
