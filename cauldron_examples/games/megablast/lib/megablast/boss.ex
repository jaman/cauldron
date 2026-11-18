defmodule Megablast.Boss do
  @moduledoc """
  A great creature at a stage's middle or end: a core and the parts grown on it.

  It comes down to a hold ahead of the ship and sways there. While any part lives the
  core is armoured and shots ring off it; with the parts gone it can be hurt. Its guns
  follow its phase: the phases are listed with the share of the core's health they begin
  below, so a wounded boss fires harder.

  A design is `%{name, core, parts, phases, sway}`, the `core` and each part
  `%{art, hp, radius}` with a part's `at`, its offset from the core in tiles, and each
  phase `%{below, guns}`, a gun `%{from, every, pattern}` where `from` is `:core` or a
  part's name. A boss is the design's state in play: where it is, what each piece has
  left, and each gun's wait.
  """

  alias Cauldron2D.Projectiles.Pattern

  @hold 6.5

  @type piece :: %{
          name: atom(),
          art: atom(),
          hp: non_neg_integer(),
          max: pos_integer(),
          radius: number(),
          at: {number(), number()}
        }
  @type t :: map()

  @doc "A boss of `design` coming in above `{x, y}`."
  @spec new(map(), {number(), number()}) :: t()
  def new(design, {x, y}) do
    core = Map.merge(design.core, %{name: :core, max: design.core.hp, at: {0.0, 0.0}})
    parts = Enum.map(design.parts, &Map.merge(&1, %{max: &1.hp}))

    %{
      design: design,
      x: x / 1,
      y: y - 10.0,
      home: x / 1,
      age: 0.0,
      hit: 0.0,
      pieces: [core | parts],
      waits: %{}
    }
  end

  @doc "The pieces still standing, each at its place in the lane."
  @spec pieces(t()) :: [map()]
  def pieces(boss) do
    for piece <- boss.pieces, piece.hp > 0 do
      {dx, dy} = piece.at
      Map.merge(piece, %{x: boss.x + dx, y: boss.y + dy, armoured?: armoured?(boss, piece)})
    end
  end

  @doc "Whether the boss is beaten: its core destroyed."
  @spec beaten?(t()) :: boolean()
  def beaten?(boss), do: core(boss).hp <= 0

  @doc "How much of its core's health is left, `0.0..1.0`."
  @spec health(t()) :: float()
  def health(boss), do: core(boss).hp / core(boss).max

  @doc "The boss `dt` seconds on: coming down to its hold `@hold` tiles ahead of `depth`, then swaying."
  @spec move(t(), number(), number()) :: t()
  def move(boss, dt, depth) do
    hold = depth - @hold
    sway = Map.get(boss.design, :sway, 3.0)
    aged = %{boss | age: boss.age + dt, hit: max(0.0, boss.hit - dt)}

    if aged.y < hold,
      do: %{aged | y: min(hold, aged.y + 4.0 * dt)},
      else: %{aged | y: hold, x: boss.home + :math.sin(aged.age * 0.55) * sway}
  end

  @doc """
  The boss after `damage` strikes piece `name`, and what it came to: `:rang` (armour),
  `:struck`, `:broken` (a part destroyed) or `:beaten` (the core destroyed).
  """
  @spec strike(t(), atom(), pos_integer()) :: {t(), :rang | :struck | :broken | :beaten}
  def strike(boss, name, damage) do
    piece = Enum.find(boss.pieces, &(&1.name == name))

    if armoured?(boss, piece) do
      {boss, :rang}
    else
      hp = max(0, piece.hp - damage)

      struck = %{
        boss
        | hit: 0.12,
          pieces: Enum.map(boss.pieces, &if(&1.name == name, do: %{&1 | hp: hp}, else: &1))
      }

      {struck, outcome(name, hp)}
    end
  end

  defp outcome(:core, 0), do: :beaten
  defp outcome(_part, 0), do: :broken
  defp outcome(_name, _hp), do: :struck

  @doc "The boss after its guns' `dt` seconds, and the bullets they fired at `target`."
  @spec fire(t(), number(), {number(), number()} | nil, number()) ::
          {t(), [Cauldron2D.Projectiles.shot()]}
  def fire(boss, dt, target, speed) do
    guns = guns(boss)

    {waits, bullets} =
      guns
      |> Enum.with_index()
      |> Enum.map_reduce([], fn {gun, index}, acc ->
        left = Map.get(boss.waits, index, gun.every) - dt
        shoot(boss, gun, index, left, target, speed, acc)
      end)

    {%{boss | waits: Map.new(waits)}, bullets}
  end

  defp shoot(boss, gun, index, left, target, speed, acc) do
    case from(boss, gun.from) do
      nil ->
        {{index, gun.every}, acc}

      _from when left > 0 ->
        {{index, left}, acc}

      at ->
        {{index, gun.every},
         acc ++ Pattern.fire(gun.pattern, at, target, speed, phase: boss.age * 1.3)}
    end
  end

  defp from(boss, name) do
    case Enum.find(pieces(boss), &(&1.name == name)) do
      nil -> nil
      piece -> {piece.x, piece.y + 0.6}
    end
  end

  defp guns(boss) do
    left = if parts?(boss), do: health(boss), else: min(health(boss), 0.98)
    boss.design.phases |> Enum.filter(&(left <= &1.below)) |> List.last() |> Map.fetch!(:guns)
  end

  defp parts?(boss), do: Enum.any?(boss.pieces, &(&1.name != :core and &1.hp > 0))

  defp armoured?(boss, %{name: :core}), do: parts?(boss)
  defp armoured?(_boss, _part), do: false

  defp core(boss), do: Enum.find(boss.pieces, &(&1.name == :core))
end
