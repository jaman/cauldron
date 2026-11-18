defmodule Beast.Creature do
  @moduledoc """
  The region's creatures. Each shows what it is about to do before it does it, so a
  player who watches can answer every attack:

    * `:crawler` — patrols; seeing the beast near and level, it crouches and shivers
      (`:windup`), then lunges along the ground (`:lunge`): jump it or roll through it
    * `:bat` — roosts; with the beast near it flies over its head and hovers (`:windup`),
      then dives at where the beast stood (`:dive`) and climbs away
    * `:goblin` — walks up to the beast, raises its club (`:windup`) and swings (`:swing`);
      struck while it raises the club it staggers and loses the swing
    * `:archer` — keeps its distance, draws (`:windup`) and looses an arrow at the beast's
      chest: duck it, jump it, or roll through it

  A creature is `%{id, kind, body, facing, hp, state, t, home}`. `step/5` moves it on;
  `strike/1` is the box its active attack covers and the damage; `shots/1` the arrows it
  loosed this step, cleared by the next.
  """

  alias Cauldron2D.BoxBody

  @kinds %{
    crawler: %{hp: 3, size: {1.2, 0.9}, speed: 2.0, flies?: false, worth: 50},
    bat: %{hp: 1, size: {0.9, 0.7}, speed: 6.0, flies?: true, worth: 40},
    goblin: %{hp: 5, size: {0.9, 2.2}, speed: 3.0, flies?: false, worth: 100},
    archer: %{hp: 3, size: {0.8, 2.4}, speed: 2.5, flies?: false, worth: 80}
  }

  @type t :: map()

  @doc "A creature of `kind` waiting at tile `{x, y}`."
  @spec new(atom(), {integer(), integer()}, term()) :: t()
  def new(kind, {x, y}, id) do
    stats = Map.fetch!(@kinds, kind)

    %{
      id: id,
      kind: kind,
      body: BoxBody.new({x + 0.5, y + 1.0}, stats.size),
      facing: -1,
      hp: stats.hp,
      state: :idle,
      t: 0.0,
      home: {x + 0.5, y + 1.0},
      hit: 0.0,
      shots: [],
      aim: nil
    }
  end

  @doc "What killing a creature of this kind scores."
  @spec worth(atom()) :: pos_integer()
  def worth(kind), do: Map.fetch!(@kinds, kind).worth

  @doc "The creature `dt` seconds on through `grid`, watching `target` (the beast's feet, or `nil`)."
  @spec step(t(), number(), BoxBody.grid(), {number(), number()} | nil, number()) :: t()
  def step(%{state: :dead} = creature, dt, _grid, _target, _gravity),
    do: %{creature | t: creature.t + dt}

  def step(creature, dt, grid, target, gravity) do
    stats = Map.fetch!(@kinds, creature.kind)
    creature = %{creature | t: creature.t + dt, hit: max(0.0, creature.hit - dt), shots: []}
    creature = think(creature, target, stats, grid)

    body =
      if stats.flies?,
        do: creature.body,
        else: %{creature.body | vy: min(30.0, creature.body.vy + gravity * dt)}

    %{creature | body: if(stats.flies?, do: fly(body, dt), else: BoxBody.move(body, dt, grid))}
  end

  defp fly(body, dt), do: %{body | x: body.x + body.vx * dt, y: body.y + body.vy * dt}

  defp enter(creature, state), do: %{creature | state: state, t: 0.0}

  defp think(%{kind: :crawler} = c, target, stats, _grid), do: crawl(c, target, stats)
  defp think(%{kind: :bat} = c, target, stats, _grid), do: flap(c, target, stats)
  defp think(%{kind: :goblin} = c, target, stats, _grid), do: brawl(c, target, stats)

  defp think(%{kind: :archer} = c, target, stats, grid) do
    case c.state do
      :windup when c.t >= 0.7 -> c |> track(target) |> loose() |> enter(:recover)
      :windup -> c |> track(target) |> push(0.0)
      :recover when c.t >= 1.0 -> enter(c, :idle)
      :recover -> push(c, 0.0)
      :stagger when c.t >= 0.5 -> enter(c, :idle)
      :stagger -> push(c, 0.0)
      _idle -> keep_off(c, target, stats.speed, grid)
    end
  end

  defp crawl(%{state: :windup, t: t} = c, _target, _stats) when t >= 0.45,
    do: c |> enter(:lunge) |> push(c.facing * 11.0)

  defp crawl(%{state: :windup} = c, _target, _stats), do: push(c, 0.0)

  defp crawl(%{state: :lunge, t: t} = c, _target, _stats) when t >= 0.35,
    do: c |> enter(:recover) |> push(0.0)

  defp crawl(%{state: :lunge} = c, _target, _stats), do: c
  defp crawl(%{state: :recover, t: t} = c, _target, _stats) when t >= 0.6, do: enter(c, :idle)
  defp crawl(%{state: :recover} = c, _target, _stats), do: c
  defp crawl(%{state: :stagger, t: t} = c, _target, _stats) when t >= 0.4, do: enter(c, :idle)
  defp crawl(%{state: :stagger} = c, _target, _stats), do: push(c, 0.0)

  defp crawl(c, target, stats) do
    if sees?(c, target, 5.0, 1.5),
      do: c |> face(target) |> enter(:windup),
      else: patrol(c, stats.speed)
  end

  defp flap(%{state: :windup, t: t} = c, _target, _stats) when t >= 0.7,
    do: dive(enter(c, :dive), c.aim)

  defp flap(%{state: :windup} = c, {tx, ty}, stats),
    do: towards(%{c | aim: {tx, ty - 1.2}}, {tx, ty - 4.5}, stats.speed)

  defp flap(%{state: :windup} = c, nil, _stats), do: enter(c, :climb)
  defp flap(%{state: :dive, t: t} = c, _target, _stats) when t >= 0.55, do: enter(c, :climb)
  defp flap(%{state: :dive} = c, _target, _stats), do: c
  defp flap(%{state: :climb, t: t} = c, _target, _stats) when t >= 1.2, do: enter(c, :idle)

  defp flap(%{state: :climb, home: {_hx, hy}} = c, _target, stats),
    do: towards(c, {c.body.x, hy}, stats.speed)

  defp flap(%{state: :stagger, t: t} = c, _target, _stats) when t >= 0.4, do: enter(c, :climb)

  defp flap(%{state: :stagger} = c, _target, _stats),
    do: towards(c, {c.body.x, c.body.y}, 0.0)

  defp flap(%{home: {hx, hy}} = c, target, stats) do
    if sees?(c, target, 8.0, 9.0),
      do: enter(c, :windup),
      else: towards(c, {hx, hy}, stats.speed / 2)
  end

  defp brawl(%{state: :windup, t: t} = c, _target, _stats) when t >= 0.5, do: enter(c, :swing)
  defp brawl(%{state: :windup} = c, _target, _stats), do: push(c, 0.0)
  defp brawl(%{state: :swing, t: t} = c, _target, _stats) when t >= 0.15, do: enter(c, :recover)
  defp brawl(%{state: :swing} = c, _target, _stats), do: c
  defp brawl(%{state: :recover, t: t} = c, _target, _stats) when t >= 0.5, do: enter(c, :idle)
  defp brawl(%{state: :recover} = c, _target, _stats), do: push(c, 0.0)
  defp brawl(%{state: :stagger, t: t} = c, _target, _stats) when t >= 0.5, do: enter(c, :idle)
  defp brawl(%{state: :stagger} = c, _target, _stats), do: push(c, 0.0)
  defp brawl(c, target, stats), do: approach(c, target, stats.speed)

  defp track(c, nil), do: c
  defp track(c, target), do: face(c, target)

  defp approach(c, target, speed) do
    cond do
      not sees?(c, target, 10.0, 3.0) -> push(c, 0.0)
      abs(elem(target, 0) - c.body.x) < 1.6 -> c |> face(target) |> enter(:windup)
      true -> c |> face(target) |> then(&push(&1, &1.facing * speed))
    end
  end

  defp keep_off(c, target, speed, grid) do
    if sees?(c, target, 11.0, 4.0),
      do: c |> face(target) |> shoot_or_back_off(target, speed, grid),
      else: push(c, 0.0)
  end

  defp shoot_or_back_off(c, {tx, _ty}, speed, grid) do
    if abs(tx - c.body.x) < 5.0 and room_behind?(c, grid),
      do: push(c, -c.facing * speed),
      else: c |> push(0.0) |> enter(:windup)
  end

  defp room_behind?(%{body: body, facing: facing}, grid) do
    column = floor(body.x - facing * (body.w / 2 + 0.3))
    feet = floor(body.y - 0.5)
    head = floor(body.y - body.h + 0.1)

    Enum.all?(head..feet//1, &(grid.({column, &1}) == :open)) and
      grid.({column, floor(body.y + 0.1)}) in [:solid, :platform]
  end

  defp loose(c) do
    arrow = %{
      x: c.body.x + c.facing * 0.6,
      y: c.body.y - 1.7,
      vx: c.facing * 12.0,
      vy: 0.0,
      kind: :arrow,
      damage: 1
    }

    %{c | shots: [arrow]}
  end

  defp patrol(c, speed) do
    {hx, _hy} = c.home

    facing =
      cond do
        c.body.x > hx + 3 -> -1
        c.body.x < hx - 3 -> 1
        c.body.vx == 0 and c.t > 0.2 -> -c.facing
        true -> c.facing
      end

    push(%{c | facing: facing}, facing * speed)
  end

  defp dive(c, nil), do: c

  defp dive(c, {tx, ty}) do
    {dx, dy} = {tx - c.body.x, ty - c.body.y}
    far = max(0.01, :math.sqrt(dx * dx + dy * dy))

    %{
      c
      | body: %{c.body | vx: dx / far * 12.0, vy: dy / far * 12.0},
        facing: if(dx < 0, do: -1, else: 1)
    }
  end

  defp towards(c, {x, y}, speed) do
    {dx, dy} = {x - c.body.x, y - c.body.y}
    far = :math.sqrt(dx * dx + dy * dy)

    if far < 0.1,
      do: %{c | body: %{c.body | vx: 0.0, vy: 0.0}},
      else: %{
        c
        | body: %{c.body | vx: dx / far * speed, vy: dy / far * speed},
          facing: if(dx < 0, do: -1, else: 1)
      }
  end

  defp push(c, vx), do: %{c | body: %{c.body | vx: vx / 1}}

  defp face(c, {tx, _ty}), do: %{c | facing: if(tx < c.body.x, do: -1, else: 1)}

  defp sees?(_c, nil, _across, _up), do: false
  defp sees?(c, {tx, ty}, across, up), do: abs(tx - c.body.x) < across and abs(ty - c.body.y) < up

  @doc "The box `{left, top, right, bottom}` the creature's active attack covers, and its damage, or `nil`."
  @spec strike(t()) :: {{number(), number(), number(), number()}, pos_integer()} | nil
  def strike(%{state: :lunge} = c), do: {BoxBody.box(c.body), 1}
  def strike(%{state: :dive} = c), do: {BoxBody.box(c.body), 1}

  def strike(%{state: :swing} = c) do
    %{x: x, y: y, h: h} = c.body
    far = x + c.facing * 1.6
    {{min(x, far), y - h * 0.9, max(x, far), y - h * 0.3}, 2}
  end

  def strike(_c), do: nil

  @doc "The creature after a blow of `damage` thrown `knock` tiles a second from side `from`; staggered out of a wind-up."
  @spec struck(t(), pos_integer(), number(), -1 | 1) :: t()
  def struck(c, damage, knock, from) do
    hp = c.hp - damage
    body = %{c.body | vx: from * knock, vy: if(c.kind == :bat, do: c.body.vy, else: -3.0)}

    cond do
      hp <= 0 ->
        %{c | hp: 0, state: :dead, t: 0.0, hit: 0.15, body: body}

      c.state in [:windup, :idle, :recover] ->
        %{c | hp: hp, state: :stagger, t: 0.0, hit: 0.15, body: body}

      true ->
        %{c | hp: hp, hit: 0.15, body: body}
    end
  end
end
