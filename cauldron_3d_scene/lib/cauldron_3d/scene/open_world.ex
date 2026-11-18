if Code.ensure_loaded?(Cauldron.OpenWorld.Map) do
  defmodule Cauldron3D.Scene.OpenWorld do
    @moduledoc """
    A `Cauldron.OpenWorld.Map` as things to draw. A map point `{x, y}` lies at `x` on the
    scene's X axis and `y` on its Z axis, and heights are on Y.

    Everything made for a cell is in the cell's own space, with its low corner at the
    origin, and is placed with `origin/2`:

      * `ground/3` — the cell's ground as a mesh (`Cauldron3D.Scene.Terrain`)
      * `water/2` — a level square at the cell's water height, or `nil`
      * `things/2` — the cell's things stood on the ground, as one scatter for each kind
      * `cover/3` — places scattered over the ground where one of its four kinds lies,
        for grass, flowers or stones

    `panel/1` is a map panel as a mesh in the scene's space.

        mesh = Cauldron3D.Scene.OpenWorld.ground(map, {2, 3}, step: 2, skirt: 4.0)
        transform = Cauldron3D.Scene.OpenWorld.origin(map, {2, 3})
        {:instance, 40, %Cauldron3D.Scene.Instance{mesh: handle, materials: [soil], transform: transform}}

    `Cauldron3D.Scene.OpenWorld.Shown` keeps the cells round a viewer drawn as it moves.
    """

    alias Cauldron.OpenWorld.{Cell, Panel, Thing}
    alias Cauldron.OpenWorld.Map, as: World
    alias Cauldron3D.Scene.{Mesh, Scatter, Terrain, Transform}

    @doc "Where the meshes and scatters of the cell at `address` are placed."
    @spec origin(World.t(), Cell.address()) :: Transform.t()
    def origin(%World{} = map, address) do
      {x, y} = World.origin(map, address)
      %Transform{position: {x, 0.0, y}}
    end

    @doc """
    The ground of the cell at `address`, or `nil` where the map holds none. Options
    `:step` and `:skirt` are `Cauldron3D.Scene.Terrain.mesh/4`'s. The cell's ground kinds
    become the vertices' colours.
    """
    @spec ground(World.t(), Cell.address(), keyword()) :: Mesh.t() | nil
    def ground(%World{samples: samples, cell_size: size} = map, address, opts \\ []) do
      with %Cell{} = cell <- World.cell(map, address) do
        Terrain.mesh(
          samples,
          size,
          &height(map, cell, &1, &2),
          Keyword.put(opts, :kinds, kinds(cell, samples))
        )
      end
    end

    # A cell with no kinds of its own leaves terrain to the default.
    defp kinds(%Cell{kinds: nil}, _samples), do: nil

    defp kinds(%Cell{} = cell, samples) do
      fn across, along -> Cell.kind(cell, samples, across, along) end
    end

    @doc "A level square over the cell at `address` at its water height, or `nil` for a cell without water."
    @spec water(World.t(), Cell.address()) :: Mesh.t() | nil
    def water(%World{cell_size: size} = map, address) do
      case World.cell(map, address) do
        %Cell{water: level} when is_number(level) ->
          Mesh.new(
            [
              %{position: {0.0, level, 0.0}, uv: {0.0, 0.0}},
              %{position: {0.0, level, size}, uv: {0.0, 1.0}},
              %{position: {size, level, size}, uv: {1.0, 1.0}},
              %{position: {size, level, 0.0}, uv: {1.0, 0.0}}
            ],
            [0, 1, 2, 0, 2, 3]
          )

        _none ->
          nil
      end
    end

    @doc "The things of the cell at `address` stood on its ground: `%{kind => scatter}`."
    @spec things(World.t(), Cell.address()) :: %{term() => Scatter.t()}
    def things(%World{} = map, address) do
      {origin_x, origin_y} = World.origin(map, address)

      case World.cell(map, address) do
        %Cell{things: things} ->
          things
          |> Enum.group_by(& &1.kind)
          |> Map.new(fn {kind, same} ->
            {kind, Scatter.upright(Enum.map(same, &stood(map, &1, origin_x, origin_y)))}
          end)

        nil ->
          %{}
      end
    end

    @doc """
    Places spread over the cell at `address` where ground kind `:kind` (0 to 3) lies:
    `:per` places for each unit of area where the kind is whole, fewer where it thins,
    each `:size` (`{least, most}`, default `{1.0, 1.0}`) big and turned at random. The same
    `:seed` (default 0) gives the same places.
    """
    @spec cover(World.t(), Cell.address(), keyword()) :: Scatter.t()
    def cover(%World{cell_size: size} = map, {column, row} = address, opts) do
      kind = Keyword.fetch!(opts, :kind)
      count = round(Keyword.fetch!(opts, :per) * size * size)
      {least, most} = Keyword.get(opts, :size, {1.0, 1.0})
      seed = Keyword.get(opts, :seed, 0)
      {origin_x, origin_y} = World.origin(map, address)

      places =
        for index <- 0..(count - 1)//1,
            x = chance({seed, column, row, index, :x}) * size,
            y = chance({seed, column, row, index, :y}) * size,
            amounts = World.kind(map, {origin_x + x, origin_y + y}),
            amounts != nil,
            chance({seed, column, row, index, :keep}) * 255.0 < elem(amounts, kind) do
          scale = least + (most - least) * chance({seed, column, row, index, :size})
          turn = chance({seed, column, row, index, :turn}) * 2.0 * :math.pi()
          {{x, World.height(map, {origin_x + x, origin_y + y}), y}, scale, turn}
        end

      Scatter.upright(places)
    end

    @doc "A map panel as an upright rectangle in the scene's space, its picture's `span` across it."
    @spec panel(Panel.t()) :: Mesh.t()
    def panel(%Panel{
          from: {from_x, from_y},
          to: {to_x, to_y},
          base: base,
          height: height,
          span: {left, right}
        }) do
      Mesh.new(
        [
          %{position: {from_x, base, from_y}, uv: {left, 1.0}},
          %{position: {to_x, base, to_y}, uv: {right, 1.0}},
          %{position: {to_x, base + height, to_y}, uv: {right, 0.0}},
          %{position: {from_x, base + height, from_y}, uv: {left, 0.0}}
        ],
        [0, 1, 2, 0, 2, 3]
      )
    end

    defp stood(map, %Thing{position: {x, y} = point} = thing, origin_x, origin_y) do
      ground = World.height(map, point) || 0.0
      {{x - origin_x, ground + thing.height, y - origin_y}, thing.scale, thing.turn}
    end

    defp height(%World{samples: samples}, cell, across, along)
         when across in 0..samples//1 and along in 0..samples//1,
         do: Cell.height(cell, samples, across, along)

    defp height(
           %World{samples: samples, cell_size: size} = map,
           %Cell{address: address} = cell,
           across,
           along
         ) do
      {origin_x, origin_y} = World.origin(map, address)
      step = size / samples

      World.height(map, {origin_x + across * step, origin_y + along * step}) ||
        Cell.height(
          cell,
          samples,
          across |> max(0) |> min(samples),
          along |> max(0) |> min(samples)
        )
    end

    defp chance(key), do: :erlang.phash2(key, 1_000_000) / 1_000_000
  end
end
