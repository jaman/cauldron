defmodule Beast.Boss do
  @moduledoc """
  The great creature at the end of each region, in its arena. Its kind decides how it
  fights (`Beast.Bosses.Wyrm`, `Troll`, `Spirit`, `Mage`); this module is what they
  share.

  A boss is `%{kind, x, y, hp, max, state, t, fought, facing, hit, shots, spawns}`,
  `{x, y}` its feet, `t` the seconds in its state and `fought` the seconds since it
  woke. `step/3` moves it on, given where the beast's feet are; `strike/1` is the box its
  active attack covers and the damage; `hurtbox/1` the box blows land on, or `nil` while
  it cannot be hurt; `armoured?/1` whether a blow that lands only rings off;
  `opening?/1` whether it is in the moment its kind leaves open to blows; `hint/1` how
  to beat it, in a line. `shots` are the projectiles it let go this step, `spawns` the
  creatures it called.
  """

  alias Beast.Bosses.{Mage, Spirit, Troll, Wyrm}

  @kinds %{wyrm: Wyrm, troll: Troll, spirit: Spirit, mage: Mage}
  @names %{
    wyrm: "THE SAND WYRM",
    troll: "THE CAVE TROLL",
    spirit: "THE TREE SPIRIT",
    mage: "ZELEK THE MAGE"
  }
  @hints %{
    wyrm: "STRIKE ITS HEAD WHILE IT LIES DAZED",
    troll: "ROLL ITS CHARGE - HIT IT WINDED",
    spirit: "DODGE ROOTS - STRIKE THE OPEN FACE",
    mage: "HIT HIM AS HE CALLS LIGHTNING"
  }

  @type box :: {number(), number(), number(), number()}
  @type t :: map()

  @doc "A boss of `kind` waiting at tile `{x, y}`, in the arena from `left` to `right`."
  @spec new(atom(), {integer(), integer()}, {number(), number()}) :: t()
  def new(kind, {x, y}, arena) do
    module = Map.fetch!(@kinds, kind)

    Map.merge(
      %{
        kind: kind,
        x: x + 0.5,
        y: y + 1.0,
        ground: y + 1.0,
        facing: -1,
        t: 0.0,
        fought: 0.0,
        hit: 0.0,
        shots: [],
        spawns: [],
        arena: arena,
        hits: 0
      },
      module.init({x + 0.5, y + 1.0})
    )
  end

  @doc "What the boss is called."
  @spec name(atom()) :: String.t()
  def name(kind), do: Map.fetch!(@names, kind)

  @doc "How to beat a boss of `kind`, in a line."
  @spec hint(atom()) :: String.t()
  def hint(kind), do: Map.fetch!(@hints, kind)

  @doc "Whether the boss is in the moment its kind leaves open to blows."
  @spec opening?(t()) :: boolean()
  def opening?(%{state: :dead}), do: false
  def opening?(boss), do: module(boss).opening?(boss)

  @doc "The boss `dt` seconds on, watching the beast's feet at `target`."
  @spec step(t(), number(), {number(), number()} | nil) :: t()
  def step(%{state: :dead} = boss, dt, _target), do: %{boss | t: boss.t + dt}

  def step(boss, dt, target) do
    boss = %{
      boss
      | t: boss.t + dt,
        fought: boss.fought + dt,
        hit: max(0.0, boss.hit - dt),
        shots: [],
        spawns: []
    }

    module(boss).think(boss, dt, target || {boss.x, boss.y})
  end

  @doc "The box the boss's active attack covers, and its damage, or `nil`."
  @spec strike(t()) :: {box(), pos_integer()} | nil
  def strike(%{state: :dead}), do: nil
  def strike(boss), do: module(boss).strike(boss)

  @doc "The box blows land on, or `nil` while the boss is out of reach."
  @spec hurtbox(t()) :: box() | nil
  def hurtbox(%{state: :dead}), do: nil
  def hurtbox(boss), do: module(boss).hurtbox(boss)

  @doc "Whether a blow landing on the boss rings off without hurting it."
  @spec armoured?(t()) :: boolean()
  def armoured?(boss), do: module(boss).armoured?(boss)

  @doc "The boss after a blow of `damage`: hurt, beaten at no health, its kind told so it may react."
  @spec struck(t(), pos_integer()) :: t()
  def struck(boss, damage) do
    hp = max(0, boss.hp - damage * module(boss).weakness(boss))
    hurt = %{boss | hp: hp, hit: 0.15, hits: boss.hits + 1}
    if hp == 0, do: %{hurt | state: :dead, t: 0.0}, else: module(boss).wounded(hurt)
  end

  @doc "Whether the boss is in its second phase: under half its health."
  @spec raging?(t()) :: boolean()
  def raging?(boss), do: boss.hp * 2 < boss.max

  defp module(boss), do: Map.fetch!(@kinds, boss.kind)
end
