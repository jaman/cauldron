defmodule Beast.Reach do
  @moduledoc """
  Where the beast can get to in a region, found by playing its own movement
  (`Beast.Hero.step/4`) from the start.

  From every place it can stand it walks a quarter tile either way, and jumps: straight
  up, and running either way for part or all of the flight, with the jump held or let
  go early. Each landing is a new place to stand. A flight that touches spikes or falls
  out of the region is not taken. The places are rounded to a quarter tile.

  The key is looked for with the region's doors shut; everything else with them open,
  from every place reached before, when the key was reached. The arena's gates are open.

      Beast.Reach.problems(Beast.Region.load(2), Beast.Tuning.new())
      #=> []

  A region whose ledge is out of reach is named by it: `[{:platform, {42, 13}}]`.
  """

  alias Beast.{Hero, Region}
  alias Cauldron.Tuning
  alias Cauldron2D.BoxBody

  @dt 1 / 50
  @quarter 0.25
  @flight 250
  @runs [0, 4, 8, 12, 16, 24, @flight]
  @short_jump 6

  @type spot :: {float(), integer()}
  @type tile :: {integer(), integer()}
  @type found :: %{stands: MapSet.t(spot()), touched: MapSet.t(tile())}
  @type problem ::
          {:key | :boss | :exit | :stone | :fruit | :platform, tile()}

  @doc """
  What `region` asks the beast to reach that it cannot under `tuning`: its key (with the
  doors shut), its boss, its way on, its standing stones, its fruit, and the top of each
  platform tile. `[]` when it can reach them all.
  """
  @spec problems(Region.t(), Tuning.t()) :: [problem()]
  def problems(region, tuning) do
    shut = explore(region, Region.grid(region, false, false), [start(region)], tuning)
    key? = region.keys == [] or Enum.any?(region.keys, &MapSet.member?(shut.touched, &1))

    open =
      if key?,
        do:
          explore(region, Region.grid(region, true, false), MapSet.to_list(shut.stands), tuning),
        else: shut

    missed(:key, region.keys, shut) ++
      Enum.flat_map(
        [
          boss: List.wrap(region.boss_at),
          exit: List.wrap(region.exit),
          stone: region.stones,
          fruit: region.fruit
        ],
        fn {kind, tiles} -> missed(kind, tiles, open) end
      ) ++ unstood(region, open)
  end

  @doc """
  Every place the beast can stand (its feet `{x, y}`) and every tile its body passes
  through, going from the places `from` through `grid`.
  """
  @spec explore(Region.t(), BoxBody.grid(), [spot()], Tuning.t()) :: found()
  def explore(region, grid, from, tuning) do
    found = %{stands: MapSet.new(from), touched: MapSet.new()}
    spread(from, found, region, grid, tuning)
  end

  defp spread([], found, _region, _grid, _tuning), do: found

  defp spread([spot | rest], found, region, grid, tuning) do
    {landings, found} =
      Enum.reduce(moves(), {[], found}, fn move, {landings, acc} ->
        case go(spot, move, region, grid, tuning) do
          {nil, touched} ->
            {landings, %{acc | touched: MapSet.union(acc.touched, touched)}}

          {landing, touched} ->
            {[landing | landings], %{acc | touched: MapSet.union(acc.touched, touched)}}
        end
      end)

    new = landings |> Enum.uniq() |> Enum.reject(&MapSet.member?(found.stands, &1))
    found = %{found | stands: Enum.into(new, found.stands)}
    spread(new ++ rest, found, region, grid, tuning)
  end

  defp moves do
    walks = for direction <- [-1, 1], do: {:walk, direction}

    jumps =
      for direction <- [-1, 1], run <- @runs, held <- [@flight, @short_jump] do
        {:jump, direction, run, held}
      end

    walks ++ [{:jump, 0, 0, @flight}, {:jump, 0, 0, @short_jump}] ++ jumps
  end

  defp go(spot, move, region, grid, tuning) do
    hero = standing(spot, tuning)

    Enum.reduce_while(0..@flight, {hero, MapSet.new()}, fn tick, {hero, touched} ->
      before = hero.body
      hero = hero |> Hero.hold(held(move, tick)) |> Hero.step(@dt, grid, tuning)
      touched = Enum.into(BoxBody.tiles(hero.body), touched)

      cond do
        hurt?(region, hero.body) -> {:halt, {nil, touched}}
        hero.body.y > region.height -> {:halt, {nil, touched}}
        settled?(move, before, hero.body, spot) -> {:halt, {place(hero.body), touched}}
        true -> {:cont, {hero, touched}}
      end
    end)
    |> landed()
  end

  defp landed({%{body: _body}, touched}), do: {nil, touched}
  defp landed(result), do: result

  defp held({:walk, direction}, _tick), do: MapSet.new([side(direction)])

  defp held({:jump, direction, run, jump}, tick) do
    [if(tick < jump, do: :jump), if(direction != 0 and tick < run, do: side(direction))]
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp side(-1), do: :left
  defp side(1), do: :right

  defp settled?({:walk, _direction}, _before, body, {x, _y}),
    do: body.grounded? and (abs(body.x - x) >= @quarter or body.vx == 0)

  defp settled?({:jump, _direction, _run, _held}, before, body, _spot),
    do: body.grounded? and not before.grounded?

  defp standing({x, y}, tuning) do
    hero = Hero.new(:reach, "reach", {x, y}, tuning)
    %{hero | body: %{hero.body | grounded?: true}}
  end

  defp place(body), do: {Float.round(body.x / @quarter) * @quarter, round(body.y)}

  defp hurt?(region, body), do: Region.spikes?(region, BoxBody.tiles(%{body | y: body.y + 0.05}))

  defp start(%{start: {x, y}}), do: {x + 0.5, y + 1}

  defp missed(kind, tiles, found),
    do: for(tile <- tiles, not MapSet.member?(found.touched, tile), do: {kind, tile})

  defp unstood(region, found) do
    half = Hero.new(:reach, "reach", {0, 0}, Beast.Tuning.new()).body.w / 2

    for {{tx, ty} = tile, :platform} <- Enum.sort(region.tiles),
        not Enum.any?(found.stands, fn {x, y} ->
          y == ty and x + half > tx and x - half < tx + 1
        end),
        do: {:platform, tile}
  end
end
