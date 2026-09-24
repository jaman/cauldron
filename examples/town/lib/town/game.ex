defmodule Town.Game do
  @moduledoc """
  A town to walk around: every player is a villager who walks with the four
  directions, and villagers of the town's own wander between the paved tiles.

  A player may also point: `:pick` on their own tile selects them, the aim then
  shows the way to the tile under it with its distance under the rule in force, and
  `:pick` again sends them along it; `:pick` on their own tile or `:cancel` puts the
  selection down. `:ruler` cycles `Town.Rules`, `:range` bounds how far a way may go.

  This is a `Cauldron2D.Game`: `init/1` builds the town and its villagers, `join/3`
  seats a player at the square, `step/2` walks everyone, `view/2` is what one player
  sees. Nothing here reads a clock or draws.

  ## Options

    * `:seed` — the generator's seed, so a game replays the same. Default: fresh
    * `:villagers` — how many villagers wander the town. Default `7`
  """

  @behaviour Cauldron2D.Game

  alias Cauldron2D.Grid.Path
  alias Cauldron2D.Rng
  alias Town.{Art, Legend, Rules}

  @speed 2.0
  @villager_speed 1.2
  @range 6
  @walk_hold 0.15
  @square {22.5, 21.5}
  @directions %{left: {-1, 0}, right: {1, 0}, up: {0, -1}, down: {0, 1}}

  @type mover :: %{
          x: float(),
          y: float(),
          heading: float(),
          tunic: atom(),
          moved_at: float() | nil,
          route: [{float(), float()}]
        }
  @type player :: %{
          id: term(),
          name: String.t(),
          mover: mover(),
          held: MapSet.t(atom()),
          was_held: MapSet.t(atom()),
          aim: {number(), number()} | nil,
          eye: float() | nil,
          push: float(),
          selected?: boolean()
        }
  @type villager :: %{mover: mover(), wait: float()}
  @type t :: %__MODULE__{
          players: %{term() => player()},
          villagers: [villager()],
          rng: Rng.t(),
          ruler: Rules.rule(),
          range: pos_integer() | nil,
          elapsed: float(),
          events: [term()]
        }

  defstruct players: %{},
            villagers: [],
            rng: nil,
            ruler: :euclid,
            range: nil,
            elapsed: 0.0,
            events: []

  @impl true
  def init(opts) do
    Legend.install()

    {rng, _seed} =
      case Keyword.get(opts, :seed) do
        nil -> Rng.random()
        seed -> {Rng.new(seed), seed}
      end

    {villagers, rng} = spawn_villagers(rng, Keyword.get(opts, :villagers, 7))
    %__MODULE__{rng: rng, villagers: villagers}
  end

  defp spawn_villagers(rng, count) do
    paved = Legend.paved()
    tunics = Art.tunics() -- [:blue]

    Enum.map_reduce(1..count//1, rng, fn index, rng ->
      {{x, y}, rng} = Rng.pick(rng, paved)
      tunic = Enum.at(tunics, rem(index, length(tunics)))
      {%{mover: mover({x + 0.5, y + 0.5}, tunic), wait: 0.0}, rng}
    end)
  end

  defp mover({x, y}, tunic),
    do: %{x: x, y: y, heading: :math.pi() / 2, tunic: tunic, moved_at: nil, route: []}

  @impl true
  def join(%__MODULE__{} = game, id, props) do
    player = %{
      id: id,
      name: Map.get(props, :username, "player"),
      mover: mover(@square, :blue),
      held: MapSet.new(),
      was_held: MapSet.new(),
      aim: nil,
      eye: nil,
      push: 1.0,
      selected?: false
    }

    {:ok, %{game | players: Map.put(game.players, id, player)}}
  end

  @impl true
  def leave(%__MODULE__{} = game, id), do: %{game | players: Map.delete(game.players, id)}

  @impl true
  def handle_input(%__MODULE__{} = game, id, %{held: held} = input) do
    case Map.fetch(game.players, id) do
      {:ok, player} ->
        updated = %{
          player
          | held: held,
            aim: Map.get(input, :aim),
            eye: Map.get(input, :heading),
            push: push(input)
        }

        %{game | players: Map.put(game.players, id, updated)}

      :error ->
        game
    end
  end

  @impl true
  def step(%__MODULE__{} = game, dt) do
    game = %{game | elapsed: game.elapsed + dt}

    game = presses(game)

    game
    |> Map.update!(:players, &Map.new(&1, fn {id, player} -> {id, act(player, game, dt)} end))
    |> wander(dt)
  end

  defp act(player, game, dt) do
    pressed = MapSet.difference(player.held, player.was_held)

    player
    |> pick(MapSet.member?(pressed, :pick), game)
    |> cancel(MapSet.member?(pressed, :cancel))
    |> walk(game, dt)
    |> Map.put(:was_held, player.held)
  end

  defp presses(game) do
    Enum.reduce(game.players, game, fn {_id, player}, acc ->
      pressed = MapSet.difference(player.held, player.was_held)

      acc
      |> then(
        &if MapSet.member?(pressed, :ruler), do: %{&1 | ruler: Rules.next(&1.ruler)}, else: &1
      )
      |> then(
        &if MapSet.member?(pressed, :range),
          do: %{&1 | range: if(&1.range, do: nil, else: @range)},
          else: &1
      )
    end)
  end

  defp pick(player, false, _game), do: player

  defp pick(%{aim: nil} = player, true, _game), do: player

  defp pick(%{selected?: false} = player, true, _game) do
    if tile(player.aim) == tile({player.mover.x, player.mover.y}),
      do: %{player | selected?: true},
      else: player
  end

  defp pick(%{selected?: true} = player, true, game) do
    case way(player, game) do
      nil ->
        %{player | selected?: false}

      {[], _distance} ->
        %{player | selected?: false}

      {path, _distance} ->
        %{player | selected?: false, mover: %{player.mover | route: Enum.map(path, &centre/1)}}
    end
  end

  defp cancel(player, false), do: player
  defp cancel(player, true), do: %{player | selected?: false, mover: %{player.mover | route: []}}

  @doc """
  The way from a selected player to the tile under their aim, with its distance under
  the rule in force: `{path, distance}`, or `nil` when there is no way or the aim is
  out of range.
  """
  @spec way(player(), t()) :: {[Legend.position()], number()} | nil
  def way(%{aim: nil}, _game), do: nil

  def way(%{aim: aim, mover: mover}, %{ruler: ruler, range: range}) do
    from = tile({mover.x, mover.y})
    to = tile(aim)
    distance = Rules.distance(ruler, from, to)

    with true <- range == nil or distance <= range,
         {:ok, path} <- Path.find(&Legend.walkable?(centre(&1)), from, to, size: Legend.size()) do
      {path, distance}
    else
      _no_way -> nil
    end
  end

  defp walk(%{mover: %{route: [next | rest]} = mover} = player, game, dt) do
    moved = towards(mover, next, @speed * dt, game.elapsed)
    route = if {moved.x, moved.y} == next, do: rest, else: [next | rest]
    %{player | mover: %{moved | route: route}}
  end

  defp walk(%{eye: eye} = player, game, dt) when is_float(eye) do
    case direction(player.held) do
      {0, 0} ->
        player

      screen ->
        {dx, dy} = relative(screen, eye)

        %{
          player
          | mover:
              stride(player.mover, {dx, dy}, pace(player, dt), game.elapsed, :math.atan2(dy, dx))
        }
    end
  end

  defp walk(player, game, dt) do
    case direction(player.held) do
      {0, 0} ->
        player

      {dx, dy} ->
        %{
          player
          | mover:
              stride(player.mover, {dx, dy}, pace(player, dt), game.elapsed, :math.atan2(dy, dx))
        }
    end
  end

  defp pace(%{push: push}, dt), do: @speed * push * dt

  defp push(%{held: held} = input) do
    strength = Map.get(input, :strength, %{})

    case for(
           action <- Map.keys(@directions),
           MapSet.member?(held, action),
           do: Map.get(strength, action, 1.0)
         ) do
      [] -> 1.0
      pushes -> Enum.max(pushes)
    end
  end

  defp direction(held) do
    Enum.reduce(@directions, {0, 0}, fn {action, {dx, dy}}, {x, y} ->
      if MapSet.member?(held, action), do: {x + dx, y + dy}, else: {x, y}
    end)
  end

  defp relative({dx, dy}, eye) do
    {fx, fy} = {:math.cos(eye), :math.sin(eye)}
    {-dy * fx - dx * fy, -dy * fy + dx * fx}
  end

  defp stride(mover, {dx, dy}, step, now, heading) do
    length = :math.sqrt(dx * dx + dy * dy)
    target = {mover.x + dx / length * step, mover.y + dy / length * step}

    cond do
      Legend.walkable?(target) ->
        %{mover | x: elem(target, 0), y: elem(target, 1), heading: heading, moved_at: now}

      Legend.walkable?({elem(target, 0), mover.y}) ->
        %{mover | x: elem(target, 0), heading: heading, moved_at: now}

      Legend.walkable?({mover.x, elem(target, 1)}) ->
        %{mover | y: elem(target, 1), heading: heading, moved_at: now}

      true ->
        %{mover | heading: heading}
    end
  end

  defp towards(mover, {tx, ty}, step, now) do
    dx = tx - mover.x
    dy = ty - mover.y
    distance = :math.sqrt(dx * dx + dy * dy)

    if distance <= step,
      do: %{mover | x: tx, y: ty, moved_at: now},
      else: %{
        mover
        | x: mover.x + dx / distance * step,
          y: mover.y + dy / distance * step,
          heading: :math.atan2(dy, dx),
          moved_at: now
      }
  end

  defp wander(game, dt) do
    {villagers, rng} =
      Enum.map_reduce(game.villagers, game.rng, &wander_one(&1, &2, game.elapsed, dt))

    %{game | villagers: villagers, rng: rng}
  end

  defp wander_one(%{mover: %{route: [next | rest]} = mover} = villager, rng, now, dt) do
    moved = towards(mover, next, @villager_speed * dt, now)
    route = if {moved.x, moved.y} == next, do: rest, else: [next | rest]
    {%{villager | mover: %{moved | route: route}}, rng}
  end

  defp wander_one(%{wait: wait} = villager, rng, _now, dt) when wait > 0,
    do: {%{villager | wait: wait - dt}, rng}

  defp wander_one(%{mover: mover} = villager, rng, _now, _dt) do
    {{x, y}, rng} = Rng.pick(rng, Legend.paved())
    {wait, rng} = Rng.roll(rng, 4)
    from = tile({mover.x, mover.y})

    case Path.find(&Legend.walkable?(centre(&1)), from, {x, y}, size: Legend.size(), limit: 400) do
      {:ok, path} ->
        {%{villager | mover: %{mover | route: Enum.map(path, &centre/1)}, wait: wait / 1}, rng}

      :none ->
        {%{villager | wait: wait / 1}, rng}
    end
  end

  @doc "The tile a world point is on."
  @spec tile({number(), number()}) :: Legend.position()
  def tile({x, y}), do: {floor(x), floor(y)}

  @doc "The centre of a tile."
  @spec centre(Legend.position()) :: {float(), float()}
  def centre({x, y}), do: {x + 0.5, y + 0.5}

  @impl true
  def view(%__MODULE__{} = game, id) do
    me = Map.get(game.players, id)

    %{
      me:
        me &&
          %{
            name: me.name,
            mover: me.mover,
            selected?: me.selected?,
            aim: me.aim,
            way: me.selected? && way(me, game)
          },
      movers:
        Enum.map(game.villagers, & &1.mover) ++ Enum.map(Map.values(game.players), & &1.mover),
      ruler: game.ruler,
      range: game.range,
      elapsed: game.elapsed
    }
  end

  @doc "Whether a mover has stepped within the last moment, at `elapsed` seconds into the game."
  @spec walking?(mover(), float()) :: boolean()
  def walking?(%{moved_at: nil}, _elapsed), do: false
  def walking?(%{moved_at: at}, elapsed), do: elapsed - at < @walk_hold

  @impl true
  def drain_events(%__MODULE__{events: events} = game),
    do: {Enum.reverse(events), %{game | events: []}}
end
