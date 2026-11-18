defmodule Beast.Hero do
  @moduledoc """
  The beast, as the player plays it: a body, which way it faces, its health, and what
  it is doing.

    * free — `:left` and `:right` run, a press of `:jump` jumps (letting go early cuts it
      short; pressed up to 0.1 s before landing it jumps on landing, and up to 0.1 s after
      running off a ledge it still jumps — `Cauldron2D.Jump`), `:duck` held on the
      ground crouches low under blows and arrows
    * `{:move, move, t}` — a blow (`Beast.Moves`): a press of `:attack` jabs; pressed again
      in a blow's recovery, or up to 0.2 s before it, it goes on to the next of the combo;
      off the ground it kicks;
      ducking it strikes low (`:low`, then `:sweep`), crouched until the combo ends. The
      other direction held in a blow's wind-up turns the beast and the blow with it; a
      direction, jump or roll in its recovery ends the blow there and does that instead
    * `{:charge, t}` — the attack still held after a jab, until let go: a heavy blow when it
      was held long enough
    * `{:dodge, t}` — a press of `:dodge` on the ground rolls, untouchable while it rolls
    * `{:hurt, t}` — thrown back by a wound, untouchable a while after
    * `:dead` — at no health; it still falls, and `down` counts the seconds since

  `step/4` moves it on by `dt` seconds through a region's grid; `strike/1` is the box its
  active blow covers, if any. `landed` is what the blow in hand has already struck, so a
  blow lands on each thing once.
  """

  alias Beast.Moves
  alias Cauldron.{Presses, Timers, Tuning}
  alias Cauldron2D.{BoxBody, Jump}

  @stand {0.8, 2.6}
  @crouch 1.5
  @hurt_seconds 0.35
  @crouched [:low, :sweep]
  @combo_buffer 0.2
  @jump_buffer 0.1

  @type t :: map()

  @doc "A beast for player `id` standing at `{x, y}`."
  @spec new(term(), String.t(), {number(), number()}, Tuning.t()) :: t()
  def new(id, name, at, tuning) do
    %{
      id: id,
      name: name,
      body: BoxBody.new(at, @stand),
      facing: 1,
      state: :free,
      health: Tuning.get(tuning, :health),
      timers: %{},
      ducking?: false,
      held: MapSet.new(),
      presses: Presses.new(),
      jump: Jump.new(),
      stone: at,
      key?: false,
      deaths: 0,
      score: 0,
      down: 0.0,
      landed: MapSet.new()
    }
  end

  @doc "The beast holding what its player holds."
  @spec hold(t(), MapSet.t(atom())) :: t()
  def hold(hero, held), do: %{hero | held: held}

  @doc "Whether blows land on the beast now."
  @spec open?(t()) :: boolean()
  def open?(%{state: :dead}), do: false
  def open?(%{state: {:dodge, _t}}), do: false
  def open?(hero), do: not untouchable?(hero)

  @doc "Whether the beast is untouchable a while after a wound or being brought back."
  @spec untouchable?(t()) :: boolean()
  def untouchable?(hero), do: Timers.running?(hero.timers, :untouchable)

  @doc "The beast `dt` seconds on through `grid`."
  @spec step(t(), number(), BoxBody.grid(), Tuning.t()) :: t()
  def step(%{state: :dead} = hero, dt, grid, tuning) do
    fallen = fall(%{hero | body: %{hero.body | vx: hero.body.vx * 0.9}}, dt, tuning)
    %{fallen | body: BoxBody.move(fallen.body, dt, grid), down: hero.down + dt}
  end

  def step(hero, dt, grid, tuning) do
    hero
    |> act(dt, tuning)
    |> fall(dt, tuning)
    |> then(&%{&1 | body: BoxBody.move(&1.body, dt, grid)})
    |> then(&%{&1 | jump: Jump.step(&1.jump, &1.body, dt)})
    |> crouch(grid)
    |> then(
      &%{
        &1
        | presses: Presses.settle(&1.presses, &1.held, dt),
          timers: Timers.step(&1.timers, dt)
      }
    )
  end

  defp act(%{state: {:hurt, t}} = hero, dt, _tuning) do
    if t + dt >= @hurt_seconds, do: %{hero | state: :free}, else: %{hero | state: {:hurt, t + dt}}
  end

  defp act(%{state: {:dodge, t}} = hero, dt, tuning) do
    if t + dt >= Tuning.get(tuning, :dodge_time),
      do: %{
        hero
        | state: :free,
          timers: Timers.start(hero.timers, :rest, Tuning.get(tuning, :dodge_rest)),
          body: %{hero.body | vx: 0.0}
      },
      else: %{
        hero
        | state: {:dodge, t + dt},
          body: %{hero.body | vx: hero.facing * Tuning.get(tuning, :dodge)}
      }
  end

  defp act(%{state: {:move, move, t}} = hero, dt, tuning) do
    t = t + dt
    hero = %{hero | body: %{hero.body | vx: if(hero.body.grounded?, do: 0.0, else: hero.body.vx)}}
    in_move(hero, move, t, Moves.part(move, t), tuning)
  end

  defp act(%{state: {:charge, t}} = hero, dt, tuning) do
    cond do
      MapSet.member?(hero.held, :attack) ->
        %{hero | state: {:charge, t + dt}, body: %{hero.body | vx: 0.0}}

      t >= Tuning.get(tuning, :charge) ->
        begin(hero, :heavy)

      true ->
        %{hero | state: :free}
    end
  end

  defp act(hero, _dt, tuning), do: free(hero, tuning)

  defp in_move(hero, move, _t, :done, _tuning) do
    if attack_held?(hero, move),
      do: %{hero | state: {:charge, 0.0}},
      else: %{hero | state: :free}
  end

  defp in_move(hero, move, t, :recover, tuning) do
    cond do
      combo?(hero, move) -> hero |> used(:attack) |> begin(Moves.data(move).next)
      breaks_off?(hero) -> free(%{hero | state: :free}, tuning)
      true -> %{hero | state: {:move, move, t}}
    end
  end

  defp in_move(hero, move, t, :windup, _tuning) do
    if direction(hero.held) == -hero.facing,
      do: %{hero | facing: -hero.facing, state: {:move, move, t}},
      else: %{hero | state: {:move, move, t}}
  end

  defp in_move(hero, move, t, _part, _tuning), do: %{hero | state: {:move, move, t}}

  defp combo?(hero, move),
    do: Moves.data(move).next != nil and wants?(hero, :attack, @combo_buffer)

  defp begin(hero, move),
    do: %{hero | state: {:move, move, 0.0}, landed: MapSet.new(), ducking?: move in @crouched}

  defp opening(%{body: %{grounded?: false}}), do: :air
  defp opening(%{held: held}), do: if(MapSet.member?(held, :duck), do: :low, else: :jab)

  defp breaks_off?(hero),
    do:
      direction(hero.held) != 0 or wants?(hero, :jump, @jump_buffer) or
        wants?(hero, :dodge, 0.0)

  defp attack_held?(hero, move), do: move == :jab and MapSet.member?(hero.held, :attack)

  defp wants?(hero, action, window),
    do: Presses.buffered?(hero.presses, hero.held, action, window)

  defp used(hero, action), do: %{hero | presses: Presses.clear(hero.presses, action)}

  defp free(hero, tuning) do
    body = hero.body

    cond do
      wants?(hero, :attack, @combo_buffer) ->
        hero |> used(:attack) |> begin(opening(hero))

      wants?(hero, :dodge, 0.0) and body.grounded? and not Timers.running?(hero.timers, :rest) ->
        %{used(hero, :dodge) | state: {:dodge, 0.0}}

      wants?(hero, :jump, @jump_buffer) and Jump.ready?(hero.jump, body) ->
        {jump, body} = Jump.launch(hero.jump, body, Tuning.get(tuning, :jump))
        %{used(hero, :jump) | jump: jump, body: body}

      true ->
        run(hero, tuning)
    end
  end

  defp run(hero, tuning) do
    ducking? = MapSet.member?(hero.held, :duck) and hero.body.grounded?
    direction = if ducking?, do: 0, else: direction(hero.held)
    facing = if direction == 0, do: hero.facing, else: direction

    %{
      hero
      | ducking?: ducking?,
        facing: facing,
        body: %{hero.body | vx: direction * Tuning.get(tuning, :run)}
    }
  end

  defp direction(held) do
    cond do
      MapSet.member?(held, :right) -> 1
      MapSet.member?(held, :left) -> -1
      true -> 0
    end
  end

  defp fall(hero, dt, tuning) do
    held? = MapSet.member?(hero.held, :jump)
    %{hero | body: Jump.fall(hero.body, held?, Tuning.get(tuning, :gravity), dt)}
  end

  defp crouch(%{ducking?: true} = hero, _grid), do: %{hero | body: %{hero.body | h: @crouch}}
  defp crouch(hero, _grid), do: %{hero | body: %{hero.body | h: elem(@stand, 1)}}

  @doc "The box `{left, top, right, bottom}` the beast's active blow covers, and the blow, or `nil`."
  @spec strike(t()) :: {{number(), number(), number(), number()}, Moves.data()} | nil
  def strike(%{state: {:move, move, t}} = hero) do
    if Moves.part(move, t) == :active do
      data = Moves.data(move)
      %{x: x, y: y, h: h} = hero.body
      near = x + hero.facing * 0.2
      far = x + hero.facing * (0.2 + data.reach)
      {{min(near, far), y - h * 0.85, max(near, far), y - h * 0.25}, data}
    end
  end

  def strike(_hero), do: nil

  @doc "The beast after a wound of `damage` from the side `from` (`-1` left, `1` right)."
  @spec wound(t(), pos_integer(), -1 | 1, Tuning.t()) :: t()
  def wound(hero, damage, from, tuning) do
    health = max(0, hero.health - damage)
    knock = Tuning.get(tuning, :knock)
    body = %{hero.body | vx: -from * knock, vy: -6.0, grounded?: false}

    if health == 0,
      do: %{hero | health: 0, state: :dead, down: 0.0, body: body},
      else: %{
        hero
        | health: health,
          state: {:hurt, 0.0},
          timers: Timers.start(hero.timers, :untouchable, Tuning.get(tuning, :hurt_time)),
          body: body
      }
  end

  @doc "The beast brought back at its last standing stone, healed, after a death or a fall."
  @spec revive(t(), Tuning.t()) :: t()
  def revive(hero, tuning) do
    %{
      hero
      | body: BoxBody.new(hero.stone, @stand),
        state: :free,
        health: Tuning.get(tuning, :health),
        timers: Timers.start(hero.timers, :untouchable, 2.0),
        deaths: hero.deaths + 1
    }
  end
end
