defmodule Megablast.Foe do
  @moduledoc """
  The creatures of the lane, each kind with its own health, path, gun and worth.

    * `:drone` — sweeps from side to side as it falls; one shot kills it
    * `:dart` — dives at where the ship was when it came in
    * `:spore` — drifts down, and bursts into three sporelets when killed
    * `:sporelet` — what a spore scatters
    * `:orb` — comes to a hold ahead of the ship, circles there, and fires at it
    * `:shell` — armoured; creeps down and fires a fan of five
    * `:turret` — grows out of the rock and fires at the ship

  A foe is `%{kind, x, y, hp, age, ...}`, the rest what its path needs. `move/2` is
  arithmetic on it; `fire/3` gives the bullets it lets go this step. `hit` counts down the
  seconds a struck foe flashes.
  """

  alias Cauldron2D.Projectiles.Pattern

  @kinds %{
    drone: %{hp: 1, points: 100, credits: 1, radius: 0.6, gun: nil},
    dart: %{hp: 1, points: 150, credits: 1, radius: 0.5, gun: nil},
    spore: %{hp: 3, points: 120, credits: 1, radius: 0.7, gun: nil},
    sporelet: %{hp: 1, points: 50, credits: 0, radius: 0.4, gun: nil},
    orb: %{hp: 5, points: 300, credits: 2, radius: 0.7, gun: {1.5, {:aimed, 1, 0.0}}},
    shell: %{hp: 10, points: 500, credits: 3, radius: 1.0, gun: {2.2, {:fan, 5, 1.2}}},
    turret: %{hp: 3, points: 200, credits: 1, radius: 0.6, gun: {1.8, {:aimed, 1, 0.0}}}
  }

  @type t :: map()
  @type context :: %{depth: number(), target: {number(), number()} | nil, fury: number()}

  @doc "The kinds of foe there are."
  @spec kinds() :: [atom()]
  def kinds, do: Map.keys(@kinds)

  @doc "What a kind of foe is worth: `%{points, credits}`."
  @spec worth(atom()) :: %{points: pos_integer(), credits: non_neg_integer()}
  def worth(kind), do: @kinds |> Map.fetch!(kind) |> Map.take([:points, :credits])

  @doc "How near a shot must come to strike a foe of this kind, in tiles."
  @spec radius(t()) :: number()
  def radius(%{kind: kind}), do: Map.fetch!(@kinds, kind).radius

  @doc "A new foe of `kind` at `{x, y}`, with the numbers its path needs from `opts`."
  @spec new(atom(), {number(), number()}, map()) :: t()
  def new(kind, {x, y}, opts \\ %{}) do
    stats = Map.fetch!(@kinds, kind)

    %{
      kind: kind,
      x: x / 1,
      y: y / 1,
      x0: x / 1,
      hp: stats.hp,
      age: 0.0,
      hit: 0.0,
      phase: Map.get(opts, :phase, 0.0),
      vx: Map.get(opts, :vx, 0.0),
      vy: Map.get(opts, :vy, 0.0),
      gun: gun_start(stats.gun, opts)
    }
  end

  defp gun_start(nil, _opts), do: nil
  defp gun_start({every, _pattern}, opts), do: every * (0.5 + Map.get(opts, :phase, 0.0) / 10)

  @doc "The foe `dt` seconds on along its path, in `context`."
  @spec move(t(), number(), context()) :: t()
  def move(foe, dt, context) do
    aged = %{foe | age: foe.age + dt, hit: max(0.0, foe.hit - dt)}
    path(aged, dt, context)
  end

  defp path(%{kind: :drone} = foe, dt, _context),
    do: %{foe | y: foe.y + 3.4 * dt, x: foe.x0 + :math.sin(foe.age * 1.6 + foe.phase) * 3.2}

  defp path(%{kind: :dart, age: age} = foe, dt, %{target: {tx, _ty}})
       when age <= 0.04 and foe.vx == 0.0,
       do: path(%{foe | vx: (tx - foe.x) / 2.2}, dt, %{target: nil})

  defp path(%{kind: :dart} = foe, dt, _context),
    do: %{foe | y: foe.y + 9.0 * dt, x: foe.x + foe.vx * dt}

  defp path(%{kind: :spore} = foe, dt, _context),
    do: %{foe | y: foe.y + 1.8 * dt, x: foe.x0 + :math.sin(foe.age * 0.9 + foe.phase) * 1.2}

  defp path(%{kind: :sporelet} = foe, dt, _context),
    do: %{foe | x: foe.x + foe.vx * dt, y: foe.y + foe.vy * dt}

  defp path(%{kind: :orb} = foe, dt, %{depth: depth}) do
    hold = depth - 5.0 + foe.phase / 3

    if foe.y < hold,
      do: %{foe | y: min(hold, foe.y + 5.0 * dt)},
      else: %{foe | y: hold, x: foe.x0 + :math.cos(foe.age * 1.1 + foe.phase) * 2.5}
  end

  defp path(%{kind: :shell} = foe, dt, %{depth: depth}),
    do: %{foe | y: min(depth - 1.0, foe.y + 1.4 * dt)}

  defp path(%{kind: :turret} = foe, _dt, _context), do: foe

  @doc """
  The foe after its gun's `dt` seconds, and the bullets it fired at `context`'s target,
  at `speed` tiles a second; a foe outside `{top, bottom}` holds its fire.
  """
  @spec fire(t(), number(), context(), number(), {number(), number()}) ::
          {t(), [Cauldron2D.Projectiles.shot()]}
  def fire(%{gun: nil} = foe, _dt, _context, _speed, _span), do: {foe, []}

  def fire(foe, dt, context, speed, {top, bottom}) do
    {every, pattern} = Map.fetch!(@kinds, foe.kind).gun
    left = foe.gun - dt * context.fury

    cond do
      left > 0 ->
        {%{foe | gun: left}, []}

      foe.y < top or foe.y > bottom ->
        {%{foe | gun: every}, []}

      true ->
        {%{foe | gun: every},
         Pattern.fire(pattern, {foe.x, foe.y}, context.target, speed * context.fury,
           phase: foe.age
         )}
    end
  end

  @doc "What a killed foe leaves behind it: a spore's three sporelets, for any other nothing."
  @spec remains(t()) :: [t()]
  def remains(%{kind: :spore, x: x, y: y}) do
    for angle <- [-2.4, -1.57, -0.74],
        do:
          new(:sporelet, {x, y}, %{vx: :math.cos(angle) * 4.0, vy: :math.sin(angle) * -3.0 + 1.5})
  end

  def remains(_foe), do: []
end
