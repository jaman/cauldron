defmodule Vale.Land do
  @moduledoc """
  The vale as a `Cauldron.OpenWorld.Map`: a lake among meadows and hills, steep crags to
  climb, woods, and a ring of country beyond that is seen and never reached.

      map = Vale.Land.map()
      Cauldron.OpenWorld.Map.height(map, Vale.Land.start())

  The map is eight cells of 64 metres a side. The inner six by six are simulated; the
  outer ring is shown only, and `Cauldron.OpenWorld.Edge.Scenery` stops walkers at the
  line between them. Past the ring, four panels (`Cauldron.OpenWorld.Panel`) stand on the
  map's sides carrying the painted mountains, with `Cauldron.OpenWorld.Edge.Backdrop` in
  front of them.

  This module is also the vale's `Cauldron.OpenWorld.Store`: `fetch/2` makes the cell at
  an address from the seed it is given, the same every time. `map/0` holds every cell;
  it is made once and kept.

  Ground kinds, in order: grass, rock, sand, flowers. Things: `:pine`, `:oak`, `:bush`
  and `:boulder`.
  """

  @behaviour Cauldron.OpenWorld.Store

  alias Cauldron.Noise
  alias Cauldron.OpenWorld.{Cell, Edge, Panel, Thing}
  alias Cauldron.OpenWorld.Map, as: World

  @cells 8
  @size 64.0
  @samples 64
  @seed 2026
  @lake {250.0, 262.0}
  @peak {372.0, 150.0}

  @doc "The whole vale, every cell in place."
  @spec map() :: World.t()
  def map do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        map = made()
        :persistent_term.put(__MODULE__, map)
        map

      map ->
        map
    end
  end

  @doc "Where a walker first stands: on the meadow by the lake's south shore."
  @spec start() :: World.point()
  def start, do: {250.0, 362.0}

  @doc "The height of the lake's surface."
  @spec water() :: float()
  def water, do: 0.0

  @doc "How far the map reaches along each axis."
  @spec span() :: float()
  def span, do: @cells * @size

  @impl true
  def fetch(seed, {column, row} = address)
      when column in 0..(@cells - 1)//1 and row in 0..(@cells - 1)//1 do
    role = if column in 1..(@cells - 2) and row in 1..(@cells - 2), do: :simulated, else: :shown

    {:ok,
     Cell.sampled(address, @samples, @size, &height(seed, &1),
       role: role,
       kinds: &kinds(seed, &1),
       water: water(),
       things: things(seed, address)
     )}
  end

  def fetch(_seed, _address), do: :none

  defp made do
    world =
      World.new(
        cell_size: @size,
        samples: @samples,
        edges: [{Edge.Scenery, margin: 1.5}, {Edge.Backdrop, margin: 2.0}],
        panels: panels()
      )

    addresses = for column <- 0..(@cells - 1), row <- 0..(@cells - 1), do: {column, row}

    addresses
    |> Task.async_stream(&fetch(@seed, &1), ordered: false, timeout: :infinity)
    |> Enum.reduce(world, fn {:ok, {:ok, cell}}, world -> World.put(world, cell) end)
  end

  defp panels do
    far = span()

    for {{from, to}, index} <-
          Enum.with_index([
            {{0.0, 0.0}, {far, 0.0}},
            {{far, 0.0}, {far, far}},
            {{far, far}, {0.0, far}},
            {{0.0, far}, {0.0, 0.0}}
          ]) do
      %Panel{
        from: from,
        to: to,
        base: -12.0,
        height: 150.0,
        picture: :range,
        span: {index / 4, (index + 1) / 4}
      }
    end
  end

  defp height(seed, {x, y}) do
    rolling = Noise.fractal(seed, x / 110.0, y / 110.0, octaves: 4) * 9.0
    crag = crag(seed, x, y)
    {lake_x, lake_y} = @lake
    basin = 13.0 * :math.exp(-((x - lake_x) * (x - lake_x) + (y - lake_y) * (y - lake_y)) / 5200.0)
    rim = rim(x, y) * 16.0
    4.5 + rolling + crag - basin + rim
  end

  defp crag(seed, x, y) do
    {peak_x, peak_y} = @peak
    away = :math.sqrt((x - peak_x) * (x - peak_x) + (y - peak_y) * (y - peak_y))
    dome = 34.0 * :math.exp(-away * away / 1900.0)
    ledges = Float.floor(dome / 7.0) * 7.0
    rough = Noise.fractal(seed + 5, x / 26.0, y / 26.0, octaves: 3) * 2.2
    dome * 0.35 + ledges * 0.65 + rough * min(dome / 6.0, 1.0)
  end

  defp rim(x, y) do
    far = span()
    edge = Enum.min([x, y, far - x, far - y])
    drop = max(1.0 - edge / 90.0, 0.0)
    drop * drop
  end

  defp kinds(seed, {x, y} = point) do
    here = height(seed, point)
    steep = steepness(seed, x, y)
    bloom = Noise.fractal(seed + 21, x / 38.0, y / 38.0, octaves: 2)

    cond do
      steep > 1.05 -> {0, 255, 0, 0}
      steep > 0.8 -> {110, 145, 0, 0}
      here < water() + 0.9 -> {0, 0, 255, 0}
      here < water() + 1.5 -> {130, 0, 125, 0}
      bloom > 0.32 -> {150, 0, 0, 105}
      true -> {255, 0, 0, 0}
    end
  end

  defp steepness(seed, x, y) do
    across = (height(seed, {x + 2.0, y}) - height(seed, {x - 2.0, y})) / 4.0
    along = (height(seed, {x, y + 2.0}) - height(seed, {x, y - 2.0})) / 4.0
    :math.sqrt(across * across + along * along)
  end

  defp things(seed, {column, row} = address) do
    for index <- 0..139,
        x = column * @size + spot(seed, address, index, :x) * @size,
        y = row * @size + spot(seed, address, index, :y) * @size,
        thing = thing(seed, address, index, {x, y}),
        thing != nil,
        do: thing
  end

  defp thing(seed, address, index, {x, y} = point) do
    wood = Noise.fractal(seed + 33, x / 85.0, y / 85.0, octaves: 3)
    pick = spot(seed, address, index, :kind)
    scale = 0.75 + spot(seed, address, index, :scale) * 0.7
    turn = spot(seed, address, index, :turn) * 2.0 * :math.pi()

    case {kinds(seed, point), wood} do
      {{255, 0, 0, 0}, wood} when wood > 0.12 and pick < 0.5 ->
        %Thing{kind: :pine, position: point, scale: scale, turn: turn, radius: 0.35}

      {{255, 0, 0, 0}, wood} when wood > 0.12 and pick < 0.75 ->
        %Thing{kind: :oak, position: point, scale: scale, turn: turn, radius: 0.45}

      {{255, 0, 0, 0}, wood} when wood > -0.05 and pick > 0.93 ->
        %Thing{kind: :bush, position: point, scale: scale, turn: turn}

      {{_grass, rock, _sand, _bloom}, _wood} when rock > 100 and pick > 0.8 ->
        %Thing{kind: :boulder, position: point, scale: scale * 1.3, turn: turn, radius: 0.8}

      {{255, 0, 0, 0}, _wood} when pick > 0.985 ->
        %Thing{kind: :boulder, position: point, scale: scale, turn: turn, radius: 0.7}

      _nothing ->
        nil
    end
  end

  defp spot(seed, address, index, what),
    do: :erlang.phash2({seed, address, index, what}, 1_000_000) / 1_000_000
end
