defmodule Megablast.Ship do
  @moduledoc """
  One pilot's ship: where it flies, how it banks, its shields and spare ships, its kit
  and credits, its score and chain, and what it fires.

  Held `:left` and `:right` steer and bank; `:thrust` and `:brake` move it up and down
  the view; `:fire` fires the kit's volley every reload and missiles every while; a press
  of `:bomb` lets a bomb go. A hit costs a shield and makes it untouchable a moment; the
  last shield lost costs a ship, one level of every weapon, and starts a new ship with
  full shields. With no ships left the pilot is out.
  """

  alias Cauldron.{Presses, Tuning}
  alias Megablast.{Lane, Weapons}

  @type t :: map()

  @doc "A new ship for pilot `id` at `{x, y}`."
  @spec new(term(), String.t(), {number(), number()}, Tuning.t(), boolean()) :: t()
  def new(id, name, {x, y}, tuning, robot?) do
    %{
      id: id,
      name: name,
      robot?: robot?,
      x: x / 1,
      y: y / 1,
      bank: 0,
      shields: get(tuning, :shields),
      lives: get(tuning, :lives),
      hurt: get(tuning, :hurt),
      reload: 0.0,
      missile: 0.0,
      credits: 0,
      score: 0,
      chain: 0,
      chain_left: 0.0,
      kit: Weapons.start(),
      held: MapSet.new(),
      presses: Presses.new(),
      out?: false,
      ready?: false,
      cursor: 0,
      flame?: false
    }
  end

  @doc "The ship holding what its pilot holds."
  @spec hold(t(), MapSet.t(atom())) :: t()
  def hold(ship, held), do: %{ship | held: held}

  @doc "The actions pressed since the last step: held now, not held then (`Cauldron.Presses`)."
  @spec pressed(t()) :: MapSet.t(atom())
  def pressed(ship), do: Presses.pressed(ship.presses, ship.held)

  @doc "The ship after a step of `dt` seconds, its held actions remembered for `pressed/1` next step."
  @spec settle(t(), number()) :: t()
  def settle(ship, dt), do: %{ship | presses: Presses.settle(ship.presses, ship.held, dt)}

  @doc "The ship flown `dt` seconds within the lane, the view at `depth` and carried on at `scroll` tiles a second."
  @spec fly(t(), number(), %{
          depth: number(),
          scroll: number(),
          lane: Lane.t(),
          tuning: Tuning.t()
        }) :: t()
  def fly(%{out?: true} = ship, _dt, _context), do: ship

  def fly(ship, dt, %{depth: depth, scroll: scroll, lane: lane, tuning: tuning}) do
    speed = 1.0 + ship.kit.engine * get(tuning, :engine_step)
    across = direction(ship.held, :right, :left)
    along = direction(ship.held, :brake, :thrust)

    y =
      clamp(
        ship.y + along * get(tuning, :lift) * speed * dt - scroll * dt,
        depth - get(tuning, :ceiling),
        depth + get(tuning, :floor)
      )

    {left, right} = Lane.edges(lane, y)
    margin = get(tuning, :margin)

    %{
      ship
      | x:
          clamp(ship.x + across * get(tuning, :steer) * speed * dt, left + margin, right - margin),
        y: y,
        bank: bank(ship.bank, across),
        flame?: along < 0,
        hurt: max(0.0, ship.hurt - dt),
        chain_left: max(0.0, ship.chain_left - dt),
        chain: if(ship.chain_left - dt <= 0, do: 0, else: ship.chain)
    }
  end

  @doc "The ship after its trigger's `dt` seconds, and the shots it fired."
  @spec trigger(t(), number(), Tuning.t()) :: {t(), [Weapons.shot()]}
  def trigger(%{out?: true} = ship, _dt, _tuning), do: {ship, []}

  def trigger(ship, dt, tuning) do
    firing? = MapSet.member?(ship.held, :fire)
    {ship, volley} = volley(ship, dt, firing?, tuning)
    {ship, missiles} = missiles(ship, dt, firing?)
    {ship, volley ++ missiles}
  end

  defp volley(ship, dt, firing?, tuning) do
    left = ship.reload - dt

    if firing? and left <= 0,
      do:
        {%{ship | reload: get(tuning, :reload)},
         Weapons.volley(ship.kit, {ship.x, ship.y}, get(tuning, :shot_speed))},
      else: {%{ship | reload: max(0.0, left)}, []}
  end

  defp missiles(ship, dt, firing?) do
    case Weapons.missile_every(ship.kit.homing) do
      nil ->
        {ship, []}

      every ->
        left = ship.missile - dt

        if firing? and left <= 0,
          do: {%{ship | missile: every}, Weapons.missiles(ship.kit, {ship.x, ship.y})},
          else: {%{ship | missile: max(0.0, left)}, []}
    end
  end

  @doc "Whether the ship lets a bomb go this step, and the ship with the bomb spent."
  @spec bomb(t()) :: {t(), boolean()}
  def bomb(%{out?: false, kit: %{bombs: bombs}} = ship) when bombs > 0 do
    if MapSet.member?(pressed(ship), :bomb),
      do: {%{ship | kit: %{ship.kit | bombs: bombs - 1}}, true},
      else: {ship, false}
  end

  def bomb(ship), do: {ship, false}

  @doc "Whether the ship can be hit now."
  @spec open?(t()) :: boolean()
  def open?(ship), do: not ship.out? and ship.hurt <= 0

  @doc "The ship after a hit, and whether it was lost."
  @spec hit(t(), Tuning.t()) :: {t(), :hurt | :lost | :out}
  def hit(ship, tuning) do
    hurt = get(tuning, :hurt)

    cond do
      ship.shields > 1 ->
        {%{ship | shields: ship.shields - 1, hurt: hurt}, :hurt}

      ship.lives > 1 ->
        {%{
           ship
           | lives: ship.lives - 1,
             shields: get(tuning, :shields),
             hurt: hurt * 1.5,
             kit: Weapons.lost(ship.kit),
             chain: 0
         }, :lost}

      true ->
        {%{ship | shields: 0, lives: 0, out?: true}, :out}
    end
  end

  @doc "The ship credited with a kill worth `points` and `credits`, its chain grown."
  @spec credit(t(), non_neg_integer(), non_neg_integer(), Tuning.t()) :: t()
  def credit(ship, points, credits, tuning) do
    chain = ship.chain + 1
    multiplier = min(get(tuning, :chain_most), 1 + div(chain, 5))

    %{
      ship
      | score: ship.score + points * multiplier,
        credits: ship.credits + credits,
        chain: chain,
        chain_left: get(tuning, :chain_time)
    }
  end

  @doc "The multiplier the ship's chain gives its next kill."
  @spec multiplier(t(), Tuning.t()) :: pos_integer()
  def multiplier(ship, tuning), do: min(get(tuning, :chain_most), 1 + div(ship.chain + 1, 5))

  defp direction(held, positive, negative) do
    cond do
      MapSet.member?(held, positive) -> 1
      MapSet.member?(held, negative) -> -1
      true -> 0
    end
  end

  defp bank(current, 0) when current > 0, do: current - 1
  defp bank(current, 0) when current < 0, do: current + 1
  defp bank(current, 0), do: current
  defp bank(current, across), do: clamp(current + across, -2, 2)

  defp clamp(value, low, high), do: value |> max(low) |> min(high)

  defp get(tuning, key), do: Tuning.get(tuning, key)
end
