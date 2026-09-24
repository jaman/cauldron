defmodule Parade.Game do
  @moduledoc """
  The courtyard as a `Cauldron2D.Game`: players walk, and a handful of walkers circle the
  yard so there is always something animating.

  A player's input may carry `:heading`, the eye's, and then walking is relative to it,
  as the terminal client's first-person view sends it.

  A player holding one of `Parade.Spell`'s actions is aiming it: the area it would cover
  is in their view, faintly, following where they stand and which way the knight faces,
  and letting go casts it there. An emanation then keeps up with whoever it was laid on,
  by `Cauldron2D.Projection.Volume.anchored/2`. Holding `:squares` marks every area out
  in whole tiles for that player instead of at its true reach.

  `:go` released over a tile sets a route there, found with `Cauldron2D.Route`, and the
  knight walks it until it arrives or a direction key takes over.
  """

  @behaviour Cauldron2D.Game

  alias Cauldron2D.Projection.Volume
  alias Cauldron2D.{Rng, Route, Trace}
  alias Parade.{Art, Legend, Spell}

  @speed 2.0
  @wander_speed 1.1
  @walk_hold 0.15
  @directions %{left: {-1, 0}, right: {1, 0}, up: {0, -1}, down: {0, 1}}

  @type mover :: %{
          x: float(),
          y: float(),
          heading: float(),
          colour: atom(),
          moved_at: float() | nil
        }
  @type player :: %{
          id: term(),
          name: String.t(),
          mover: mover(),
          held: MapSet.t(atom()),
          eye: float() | nil,
          push: float(),
          aim: {number(), number()} | nil,
          route: Route.t()
        }
  @type walker :: %{mover: mover(), target: {float(), float()}, wait: float()}
  @type t :: %__MODULE__{
          players: %{term() => player()},
          walkers: [walker()],
          spells: [Spell.t()],
          rng: Rng.t(),
          elapsed: float()
        }

  defstruct players: %{}, walkers: [], spells: [], rng: nil, elapsed: 0.0

  @impl true
  def init(opts) do
    Art.install()
    Legend.install()
    rng = Rng.new(Keyword.get(opts, :seed, 20_260_924))
    {walkers, rng} = Enum.map_reduce(Enum.drop(Art.colours(), 1), rng, &walker/2)
    %__MODULE__{walkers: walkers, rng: rng}
  end

  defp walker(colour, rng) do
    {place, rng} = somewhere(rng)
    {%{mover: mover(place, colour), target: place, wait: 0.0}, rng}
  end

  defp somewhere(rng) do
    {{x, y}, rng} = Rng.pick(rng, Legend.open())
    {{x + 0.5, y + 0.5}, rng}
  end

  defp mover({x, y}, colour),
    do: %{x: x, y: y, heading: :math.pi() / 2, colour: colour, moved_at: nil}

  @impl true
  def join(%__MODULE__{} = game, id, props) do
    player = %{
      id: id,
      name: Map.get(props, :username, "player"),
      mover: mover(centre(), hd(Art.colours())),
      held: MapSet.new(),
      eye: nil,
      push: 1.0,
      aim: nil,
      route: []
    }

    {:ok, %{game | players: Map.put(game.players, id, player)}}
  end

  defp centre do
    {width, height} = Legend.size()
    {width / 2, height / 2}
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
            eye: Map.get(input, :heading),
            push: push(input),
            aim: Map.get(input, :aim)
        }

        game
        |> cast(player.held, updated)
        |> Map.update!(:players, &Map.put(&1, id, sent(player.held, updated)))

      :error ->
        game
    end
  end

  defp cast(game, was_held, player) do
    Enum.reduce(Spell.kinds(), game, fn kind, acc ->
      if MapSet.member?(was_held, kind) and not MapSet.member?(player.held, kind),
        do: %{acc | spells: raise_spell(acc, kind, player)},
        else: acc
    end)
  end

  defp raise_spell(game, kind, %{mover: mover} = player) do
    Spell.cast(
      game.spells,
      kind,
      {mover.x, mover.y},
      mover.heading,
      game.elapsed,
      subject(game, kind, player)
    )
  end

  defp subject(game, kind, player) do
    case Spell.tracks(kind) do
      :self -> {:player, player.id}
      :other -> nearest(game, player)
      nil -> nil
    end
  end

  defp nearest(%__MODULE__{walkers: []}, _player), do: nil

  defp nearest(%__MODULE__{walkers: walkers}, %{mover: %{x: x, y: y}}) do
    {_walker, index} =
      walkers
      |> Enum.with_index()
      |> Enum.min_by(fn {%{mover: mover}, _index} ->
        (mover.x - x) * (mover.x - x) + (mover.y - y) * (mover.y - y)
      end)

    {:walker, index}
  end

  defp sent(was_held, player) do
    if MapSet.member?(was_held, :go) and not MapSet.member?(player.held, :go),
      do: %{player | route: routed(player)},
      else: player
  end

  defp routed(%{aim: nil}), do: []

  defp routed(%{aim: aim, mover: mover}) do
    case Route.to(&open?/1, {mover.x, mover.y}, aim, size: Legend.size()) do
      {:ok, route} -> told(route, mover, aim)
      :none -> told([], mover, aim)
    end
  end

  defp told(route, mover, {aim_x, aim_y}) do
    Trace.write(:route,
      from_x: mover.x,
      from_y: mover.y,
      aim_x: aim_x,
      aim_y: aim_y,
      steps: length(route),
      first_x: route != [] && elem(hd(route), 0),
      first_y: route != [] && elem(hd(route), 1),
      goal_x: route != [] && elem(List.last(route), 0),
      goal_y: route != [] && elem(List.last(route), 1)
    )

    route
  end

  defp open?({x, y}), do: Legend.walkable?({x + 0.5, y + 0.5})

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

  @impl true
  def step(%__MODULE__{} = game, dt) do
    game = %{game | elapsed: game.elapsed + dt}

    game
    |> Map.update!(:players, &Map.new(&1, fn {id, player} -> {id, walk(player, game, dt)} end))
    |> Map.update!(:spells, &Spell.burning(&1, game.elapsed))
    |> wander(dt)
  end

  defp walk(%{route: [_ | _]} = player, game, dt) do
    case direction(player.held) do
      {0, 0} -> stepped(player, game, dt)
      _keys -> walked(%{player | route: []}, game, dt)
    end
  end

  defp walk(player, game, dt), do: walked(player, game, dt)

  defp stepped(%{mover: mover, route: route} = player, game, dt) do
    from = {mover.x, mover.y}
    {{x, y}, left} = Route.advance(route, from, @speed * dt)
    heading = Route.heading(route, from) || mover.heading

    if left == [], do: Trace.write(:arrived, x: x, y: y, steps_left: 0)

    %{
      player
      | mover: %{mover | x: x, y: y, heading: heading, moved_at: game.elapsed},
        route: left
    }
  end

  defp walked(%{eye: eye} = player, game, dt) when is_float(eye) do
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

  defp walked(player, game, dt) do
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

  defp wander(%__MODULE__{} = game, dt) do
    {walkers, rng} =
      Enum.map_reduce(game.walkers, game.rng, &step_walker(&1, &2, game.elapsed, dt))

    %{game | walkers: walkers, rng: rng}
  end

  defp step_walker(%{wait: wait} = walker, rng, _elapsed, dt) when wait > 0,
    do: {%{walker | wait: wait - dt}, rng}

  defp step_walker(%{mover: mover, target: {tx, ty}} = walker, rng, elapsed, dt) do
    {dx, dy} = {tx - mover.x, ty - mover.y}
    distance = :math.sqrt(dx * dx + dy * dy)

    if distance < 0.15 do
      {place, rng} = somewhere(rng)
      {%{walker | target: place, wait: 0.4}, rng}
    else
      step = min(@wander_speed * dt, distance)
      heading = :math.atan2(dy, dx)
      moved = stride(mover, {dx, dy}, step, elapsed, heading)
      {%{walker | mover: moved}, rng}
    end
  end

  @impl true
  def view(%__MODULE__{} = game, id) do
    me = Map.get(game.players, id)

    %{
      me: me && %{name: me.name, mover: me.mover, route: me.route},
      movers:
        Enum.map(game.walkers, & &1.mover) ++ Enum.map(Map.values(game.players), & &1.mover),
      volumes:
        game.spells
        |> Spell.volumes(game.elapsed, marking(me))
        |> Volume.anchored(subjects(game))
        |> Kernel.++(aiming(me)),
      marking: marking(me),
      elapsed: game.elapsed
    }
  end

  defp subjects(%__MODULE__{} = game) do
    players =
      for {id, %{mover: mover}} <- game.players,
          into: %{},
          do: {{:player, id}, {{mover.x, mover.y}, mover.heading}}

    walkers =
      for {%{mover: mover}, index} <- Enum.with_index(game.walkers),
          into: %{},
          do: {{:walker, index}, {{mover.x, mover.y}, mover.heading}}

    Map.merge(players, walkers)
  end

  defp marking(nil), do: :measured

  defp marking(%{held: held}),
    do: if(MapSet.member?(held, :squares), do: :squares, else: :measured)

  defp aiming(nil), do: []

  defp aiming(%{held: held, mover: mover} = player) do
    for kind <- Spell.kinds(),
        MapSet.member?(held, kind),
        do: Spell.aimed(kind, {mover.x, mover.y}, mover.heading, marking(player))
  end

  @impl true
  def drain_events(%__MODULE__{} = game), do: {[], game}

  @doc "Whether a mover has stepped within the last moment, at `elapsed` seconds into the game."
  @spec walking?(mover(), float()) :: boolean()
  def walking?(%{moved_at: nil}, _elapsed), do: false
  def walking?(%{moved_at: at}, elapsed), do: elapsed - at < @walk_hold
end
