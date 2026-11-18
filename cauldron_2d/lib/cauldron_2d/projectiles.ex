defmodule Cauldron2D.Projectiles do
  @moduledoc """
  Shots in flight — bullets, arrows, missiles, thrown things — as plain maps a game keeps
  in its own state.

  A shot is a map with `:x` and `:y` in tiles, `:vx` and `:vy` in tiles a second, and any
  keys of the game's own (damage, owner, kind). The keys this module reads:

    * `:motion` — `:straight` (the default); `{:arc, gravity}`, falling at `gravity` tiles
      a second squared; or `{:homing, speed, turn}`, its velocity easing each second by
      `turn` of the way toward `speed` tiles a second at its target
    * `:ttl` — the seconds it lives; without it, it lives until the game drops it
    * `:age` — the seconds since it was let go, kept by `step/3` and `move/3`
    * `:pierce?` — `true` goes on through what it hits, hitting each thing once;
      `:struck` lists what it has hit

  `step/3` moves every shot and keeps those still in time and still wanted.
  `resolve/4` settles what each shot hits, one shot after another against the game's
  world as each hit leaves it, so a thing destroyed by one shot is not hit by the next.

      shots =
        Cauldron2D.Projectiles.step(world.shots, dt,
          target: &nearest_foe(world, &1),
          keep?: &on_screen?(world, &1)
        )

      {world, shots} =
        Cauldron2D.Projectiles.resolve(shots, world, &foe_in_reach/2, &damage_foe/3)
  """

  @type motion ::
          :straight | {:arc, number()} | {:homing, number(), number()}
  @type shot :: %{
          required(:x) => number(),
          required(:y) => number(),
          required(:vx) => number(),
          required(:vy) => number(),
          optional(:motion) => motion(),
          optional(:ttl) => number(),
          optional(:age) => number(),
          optional(:pierce?) => boolean(),
          optional(:struck) => [term()],
          optional(atom()) => term()
        }
  @type point :: {number(), number()}

  @doc """
  The shots `dt` seconds on: each moved (`move/3`), then kept while its age is under its
  `:ttl` and `keep?` is true of it.

  Options:

    * `:target` — a function from a shot to the point it homes on, or `nil` for none.
      Default none: homing shots fly on as they are
    * `:keep?` — a function from a moved shot to whether it stays, for bounds, solid
      tiles or anything else. Default: every shot stays
  """
  @spec step([shot()], number(), keyword()) :: [shot()]
  def step(shots, dt, opts \\ []) do
    target = Keyword.get(opts, :target, fn _shot -> nil end)
    keep? = Keyword.get(opts, :keep?, fn _shot -> true end)

    for shot <- shots,
        moved = move(shot, dt, target.(shot)),
        in_time?(moved),
        keep?.(moved),
        do: moved
  end

  @doc """
  One shot `dt` seconds on by its `:motion`, aged by `dt`. A homing shot with no `target`
  flies on as it is. An arcing shot moves by the velocity it had, then falls.
  """
  @spec move(shot(), number(), point() | nil) :: shot()
  def move(shot, dt, target \\ nil) do
    shot
    |> moved(Map.get(shot, :motion, :straight), dt, target)
    |> Map.update(:age, dt, &(&1 + dt))
  end

  @doc """
  Each shot's hits, settled in order: `find` is given the game's `acc` and a shot and
  answers `{id, thing}` for what the shot hits, or `nil`; `on_hit` is given `acc`, the
  shot and the thing, and answers `acc` after the hit. A shot that hits goes, unless it
  pierces: then it stays with `id` added to its `:struck`, and `find` should pass over
  what `struck?/2` says it has hit. Answers `{acc, shots}`, the shots that remain.
  """
  @spec resolve(
          [shot()],
          acc,
          (acc, shot() -> {term(), term()} | nil),
          (acc, shot(), term() -> acc)
        ) :: {acc, [shot()]}
        when acc: term()
  def resolve(shots, acc, find, on_hit) do
    {acc, kept} =
      Enum.reduce(shots, {acc, []}, fn shot, {acc, kept} ->
        case find.(acc, shot) do
          nil -> {acc, [shot | kept]}
          {id, thing} -> {on_hit.(acc, shot, thing), carried(shot, id) ++ kept}
        end
      end)

    {acc, Enum.reverse(kept)}
  end

  @doc "Whether `shot` has already hit the thing `id`."
  @spec struck?(shot(), term()) :: boolean()
  def struck?(shot, id), do: id in Map.get(shot, :struck, [])

  defp moved(shot, :straight, dt, _target), do: straight(shot, dt)
  defp moved(shot, {:homing, _speed, _turn}, dt, nil), do: straight(shot, dt)

  defp moved(shot, {:arc, gravity}, dt, _target),
    do: %{straight(shot, dt) | vy: shot.vy + gravity * dt}

  defp moved(shot, {:homing, speed, turn}, dt, {tx, ty}) do
    {dx, dy} = {tx - shot.x, ty - shot.y}
    far = max(0.001, :math.sqrt(dx * dx + dy * dy))
    ease = min(1.0, turn * dt)
    vx = shot.vx + (dx / far * speed - shot.vx) * ease
    vy = shot.vy + (dy / far * speed - shot.vy) * ease
    %{shot | vx: vx, vy: vy, x: shot.x + vx * dt, y: shot.y + vy * dt}
  end

  defp straight(shot, dt), do: %{shot | x: shot.x + shot.vx * dt, y: shot.y + shot.vy * dt}

  defp in_time?(%{ttl: ttl, age: age}), do: age < ttl
  defp in_time?(_shot), do: true

  defp carried(%{pierce?: true} = shot, id),
    do: [Map.update(shot, :struck, [id], &[id | &1])]

  defp carried(_shot, _id), do: []
end
