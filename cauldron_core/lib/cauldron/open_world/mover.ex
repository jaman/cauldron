defmodule Cauldron.OpenWorld.Mover do
  @moduledoc """
  A body that gets about a `Cauldron.OpenWorld.Map` on its own: it walks the ground,
  falls, climbs ground too steep to walk and swims where the water is deep.

      mover = Cauldron.OpenWorld.Mover.new({120.0, 80.0}, map)
      mover = Cauldron.OpenWorld.Mover.step(mover, map, %{toward: {1.0, 0.0}, dash: false, leap: false}, pace, 1 / 60)
      {mover.point, mover.height, mover.mode}

  `step/5` moves it for `seconds` by what it intends:

    * `:toward` — where it wants to go, `{x, y}` on the map, no longer than 1; shorter
      goes slower
    * `:dash` — go at the dash speed while it has stamina
    * `:leap` — jump, or let go of what it climbs

  Its `mode` is `:ground`, `:air`, `:climb` or `:swim`. It walks ground that rises less
  than `steep` for each unit across, and climbs ground that rises more while it has
  stamina, which climbing, dashing and swimming spend and standing on the ground
  restores. The map's edges (`Cauldron.OpenWorld.Map.travel/3`) and the things standing
  on it stop it; `stopped` lists the edges that stopped it this step. `heading` is the
  way it faces, in radians from the map's `x` axis towards its `y` axis.

  ## Pace

  `pace` is a map of what the body can do, every key required:

    * `:run`, `:dash`, `:climb`, `:swim` — speeds, units a second; `:climb` is along the
      face
    * `:quicken` — how fast it changes speed, units a second each second
    * `:turn` — how fast it turns, radians a second
    * `:leap` — the upward speed of a jump; `:fall` — how fast falling quickens
    * `:steep` — the rise for each unit across beyond which ground is climbed
    * `:ledge` — the drop it steps down without falling
    * `:float` — the depth of water it starts to swim in; `:draft` — how far below the
      water's surface its feet are while swimming
    * `:radius` — how wide it is against things
    * `:tire_dash`, `:tire_climb`, `:tire_swim` — stamina spent a second, of 1.0;
      `:rest` — stamina regained a second on the ground
  """

  alias Cauldron.OpenWorld.Map, as: World
  alias Cauldron.OpenWorld.Thing

  @type mode :: :ground | :air | :climb | :swim
  @type intent :: %{toward: {number(), number()}, dash: boolean(), leap: boolean()}
  @type t :: %__MODULE__{
          point: World.point(),
          height: float(),
          heading: float(),
          speed: float(),
          rise: float(),
          mode: mode(),
          stamina: float(),
          stopped: [module()]
        }

  @enforce_keys [:point, :height]
  defstruct [:point, :height, heading: 0.0, speed: 0.0, rise: 0.0, mode: :ground, stamina: 1.0, stopped: []]

  @doc "A body standing on the ground of `map` at `point`."
  @spec new(World.point(), World.t()) :: t()
  def new({x, y}, %World{} = map),
    do: %__MODULE__{point: {x / 1, y / 1}, height: World.height(map, {x, y}) || 0.0}

  @doc "The body `seconds` later, having done what `intent` asks as far as `pace` and `map` let it."
  @spec step(t(), World.t(), intent(), map(), number()) :: t()
  def step(%__MODULE__{mode: :ground} = mover, map, intent, pace, seconds), do: walked(mover, map, intent, pace, seconds)
  def step(%__MODULE__{mode: :air} = mover, map, intent, pace, seconds), do: fallen(mover, map, intent, pace, seconds)
  def step(%__MODULE__{mode: :climb} = mover, map, intent, pace, seconds), do: climbed(mover, map, intent, pace, seconds)
  def step(%__MODULE__{mode: :swim} = mover, map, intent, pace, seconds), do: swum(mover, map, intent, pace, seconds)

  defp walked(mover, map, intent, pace, seconds) do
    dashing? = intent.dash and mover.stamina > 0.0 and pressed(intent) > 0.05
    top = if dashing?, do: pace.dash, else: pace.run * pressed(intent)
    mover = mover |> turned(intent, pace, seconds) |> paced(top, pace, seconds)
    {point, stopped} = reached(mover, map, pace, seconds)
    ground = World.height(map, point) || mover.height
    stamina = if dashing?, do: spent(mover.stamina, pace.tire_dash, seconds), else: rested(mover.stamina, pace, seconds)
    mover = %{mover | stopped: stopped, stamina: stamina}

    cond do
      intent.leap -> %{mover | mode: :air, rise: pace.leap / 1}
      too_steep?(mover, point, ground, pace) -> against(mover, intent)
      deep?(map, point, ground, pace) -> %{mover | point: point, height: afloat(map, point, pace), mode: :swim}
      ground < mover.height - pace.ledge -> %{mover | point: point, mode: :air, rise: 0.0}
      true -> %{mover | point: point, height: ground}
    end
  end

  defp fallen(mover, map, intent, pace, seconds) do
    mover = turned(mover, intent, pace, seconds)
    {point, stopped} = reached(mover, map, pace, seconds)
    rise = mover.rise - pace.fall * seconds
    height = mover.height + rise * seconds
    ground = World.height(map, point) || height
    mover = %{mover | stopped: stopped}

    cond do
      ground > mover.height + pace.ledge and too_steep?(mover, point, ground, pace) -> against(%{mover | height: height, rise: rise}, intent)
      height > ground and not sunk?(map, point, height, pace) -> %{mover | point: point, height: height, rise: rise}
      deep?(map, point, ground, pace) -> %{mover | point: point, height: afloat(map, point, pace), rise: 0.0, mode: :swim}
      true -> %{mover | point: point, height: ground, rise: 0.0, mode: :ground}
    end
  end

  defp climbed(mover, _map, %{leap: true}, pace, _seconds),
    do: %{mover | mode: :air, rise: pace.leap * 0.5, speed: pace.run / 1, heading: mover.heading + :math.pi()}

  defp climbed(%__MODULE__{stamina: stamina} = mover, _map, _intent, _pace, _seconds) when stamina <= 0.0,
    do: %{mover | mode: :air, rise: 0.0, speed: 0.0}

  defp climbed(mover, map, intent, pace, seconds) do
    {rise_x, rise_y} = World.slope(map, mover.point) || {0.0, 0.0}
    grade = :math.sqrt(rise_x * rise_x + rise_y * rise_y)
    {toward_x, toward_y} = intent.toward
    along = if grade > 0.0, do: (toward_x * rise_x + toward_y * rise_y) / grade, else: 0.0
    reach = pace.climb * seconds / :math.sqrt(1.0 + along * along * grade * grade)
    {x, y} = mover.point
    {point, stopped} = World.travel(map, mover.point, {x + toward_x * reach, y + toward_y * reach})
    moving? = pressed(intent) > 0.05
    drain = if moving?, do: pace.tire_climb, else: pace.tire_climb * 0.5

    mover = %{
      mover
      | point: point,
        height: World.height(map, point) || mover.height,
        heading: if(grade > 0.0, do: :math.atan2(rise_y, rise_x), else: mover.heading),
        speed: if(moving?, do: pace.climb / 1, else: 0.0),
        stamina: spent(mover.stamina, drain, seconds),
        stopped: stopped
    }

    if grade < pace.steep, do: %{mover | mode: :ground}, else: mover
  end

  defp swum(mover, map, intent, pace, seconds) do
    mover = mover |> turned(intent, pace, seconds) |> paced(pace.swim * pressed(intent), pace, seconds)
    {point, stopped} = reached(mover, map, pace, seconds)
    ground = World.height(map, point) || mover.height
    mover = %{mover | stopped: stopped, stamina: spent(mover.stamina, pace.tire_swim, seconds)}

    if deep?(map, point, ground, %{pace | float: pace.float * 0.8}),
      do: %{mover | point: point, height: afloat(map, point, pace)},
      else: %{mover | point: point, height: ground, mode: :ground}
  end

  defp against(mover, intent) do
    if mover.stamina > 0.0 and pressed(intent) > 0.05,
      do: %{mover | mode: :climb, speed: 0.0, rise: 0.0},
      else: %{mover | speed: 0.0}
  end

  defp too_steep?(mover, point, ground, pace) do
    {from_x, from_y} = mover.point
    {to_x, to_y} = point
    across = :math.sqrt((to_x - from_x) * (to_x - from_x) + (to_y - from_y) * (to_y - from_y))
    across > 1.0e-6 and (ground - mover.height) / across > pace.steep
  end

  defp deep?(map, point, ground, pace) do
    case World.water(map, point) do
      nil -> false
      level -> level - ground > pace.float
    end
  end

  defp sunk?(map, point, height, pace) do
    case World.water(map, point) do
      nil -> false
      level -> height <= level - pace.draft
    end
  end

  defp afloat(map, point, pace), do: World.water(map, point) - pace.draft

  defp reached(%__MODULE__{point: {x, y}, heading: heading, speed: speed} = mover, map, pace, seconds) do
    target = {x + :math.cos(heading) * speed * seconds, y + :math.sin(heading) * speed * seconds}
    {point, stopped} = World.travel(map, mover.point, target)
    {clear(map, point, pace.radius), stopped}
  end

  defp clear(map, {x, y} = point, radius) do
    map
    |> World.things(point, radius + 4.0)
    |> Enum.reduce({x, y}, fn %Thing{position: {thing_x, thing_y}} = thing, {x, y} ->
      room = radius + thing.radius * thing.scale
      {off_x, off_y} = {x - thing_x, y - thing_y}
      apart = :math.sqrt(off_x * off_x + off_y * off_y)

      if thing.radius > 0.0 and apart < room and apart > 1.0e-6,
        do: {thing_x + off_x / apart * room, thing_y + off_y / apart * room},
        else: {x, y}
    end)
  end

  defp turned(mover, intent, pace, seconds) do
    {toward_x, toward_y} = intent.toward

    if pressed(intent) > 0.05 do
      wanted = :math.atan2(toward_y, toward_x)
      gap = :math.atan2(:math.sin(wanted - mover.heading), :math.cos(wanted - mover.heading))
      step = pace.turn * seconds
      %{mover | heading: if(abs(gap) <= step, do: wanted, else: mover.heading + step * sign(gap))}
    else
      mover
    end
  end

  defp paced(mover, top, pace, seconds) do
    change = pace.quicken * seconds
    speed = if mover.speed < top, do: min(mover.speed + change, top), else: max(mover.speed - change, top)
    %{mover | speed: speed / 1}
  end

  defp pressed(%{toward: {x, y}}), do: min(:math.sqrt(x * x + y * y), 1.0)
  defp spent(stamina, rate, seconds), do: max(stamina - rate * seconds, 0.0)
  defp rested(stamina, pace, seconds), do: min(stamina + pace.rest * seconds, 1.0)
  defp sign(value) when value < 0, do: -1.0
  defp sign(_value), do: 1.0
end
