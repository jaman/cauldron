if Code.ensure_loaded?(Cauldron.OpenWorld.Map) do
  defmodule Cauldron3D.Scene.OpenWorld.Shown do
    @moduledoc """
    Keeps the cells of a `Cauldron.OpenWorld.Map` round its viewers drawn in a
    `Cauldron3D.Scene.Target`, cells coming and going as the viewers move and far cells
    drawn coarser.

        shown = Cauldron3D.Scene.OpenWorld.Shown.new(ground: soil, water: lake, load: 220.0, keep: 260.0)
        {changes, shown} = Cauldron3D.Scene.OpenWorld.Shown.frame(shown, target, map, [{130.0, 40.0}])

    `frame/5` does one step: it drops the cells that fell out of reach and builds and
    uploads up to `budget` cells that came into reach or changed detail, nearest first,
    answering the changes that show them.

    Building a cell's meshes takes the longest, so a caller that must not wait does the
    three parts itself: `due/3` says what to build and drop, `built/4` builds one cell
    without touching the target (in a task, say), and `put/3` and `drop/3` upload and
    remove.

    ## Options of `new/1`

      * `:ground` — the material of the ground; required
      * `:water` — the material of water, or `nil` to draw none
      * `:kinds` — `%{kind => look}`, how the things of each kind
        (`Cauldron.OpenWorld.Thing`) are drawn; a kind not listed is not drawn
      * `:cover` — a list of looks spread over the ground, each with `:kind` (0 to 3, the
        ground kind it grows on), `:per` (places for each unit of area) and optionally
        `:size` and `:seed` (`Cauldron3D.Scene.OpenWorld.cover/3`)
      * `:load`, `:keep` — how near a cell must come to be drawn and how far it must go
        to be dropped (`Cauldron.OpenWorld.Window`); `:load` is required
      * `:steps` — the ground's step at each detail level, finest first (default `[1]`)
      * `:distances` — how far away each coarser level begins (default `[]`)
      * `:skirt` — how far the ground's edges hang down (default 0)
      * `:things_within`, `:cover_within` — the coarsest level things and cover are
        drawn at (defaults 1 and 0)
      * `:first_id` — the first instance id used (default 1_000_000)

    A look is `%{mesh: handle, materials: [handle]}` with, optionally, `:sway`, `:fade` and
    `:shadows` as `Cauldron3D.Scene.Instance` takes them.
    """

    alias Cauldron.OpenWorld.{Cell, Window}
    alias Cauldron.OpenWorld.Map, as: World
    alias Cauldron3D.Scene.{Handle, Instance, OpenWorld, Stream, Target}

    @type built :: %{
            address: Cell.address(),
            level: non_neg_integer(),
            ground: Cauldron3D.Scene.Mesh.t(),
            water: Cauldron3D.Scene.Mesh.t() | nil,
            things: %{term() => Cauldron3D.Scene.Scatter.t()},
            cover: [{non_neg_integer(), Cauldron3D.Scene.Scatter.t()}]
          }
    @type t :: %__MODULE__{
            settings: map(),
            cells: %{
              Cell.address() => %{
                slot: non_neg_integer(),
                level: non_neg_integer(),
                handles: [Handle.t()],
                ids: [Stream.id()]
              }
            },
            free: [non_neg_integer()],
            slots: non_neg_integer()
          }

    @enforce_keys [:settings]
    defstruct [:settings, cells: %{}, free: [], slots: 0]

    @doc "Nothing shown yet, with the options above."
    @spec new(keyword()) :: t()
    def new(opts) do
      %__MODULE__{
        settings: %{
          ground: Keyword.fetch!(opts, :ground),
          water: Keyword.get(opts, :water),
          kinds: Keyword.get(opts, :kinds, %{}),
          cover: Keyword.get(opts, :cover, []),
          load: Keyword.fetch!(opts, :load),
          keep: Keyword.get(opts, :keep, Keyword.fetch!(opts, :load)),
          steps: Keyword.get(opts, :steps, [1]),
          distances: Keyword.get(opts, :distances, []),
          skirt: Keyword.get(opts, :skirt, 0),
          things_within: Keyword.get(opts, :things_within, 1),
          cover_within: Keyword.get(opts, :cover_within, 0),
          first_id: Keyword.get(opts, :first_id, 1_000_000)
        }
      }
    end

    @doc """
    What to do for viewers at `eyes`: `build`, the cells to build with the level each is
    drawn at, nearest first, and `drop`, the cells to remove.
    """
    @spec due(t(), World.t(), [World.point()]) :: %{
            build: [{Cell.address(), non_neg_integer()}],
            drop: [Cell.address()]
          }
    def due(%__MODULE__{settings: settings, cells: cells}, %World{} = map, eyes) do
      held = cells |> Map.keys() |> MapSet.new()
      step = Window.step(held, map, eyes, load: settings.load, keep: settings.keep)
      present = Enum.filter(step.held, &World.cell(map, &1))
      levels = Window.levels(map, present, eyes, settings.distances)
      top = length(settings.steps) - 1

      build =
        for address <- present,
            level = min(Map.fetch!(levels, address), top),
            not match?(%{level: ^level}, Map.get(cells, address)),
            do: {address, level}

      %{
        build: Enum.sort_by(build, fn {address, _level} -> nearest(map, address, eyes) end),
        drop: Enum.filter(held, &(&1 in step.drop or World.cell(map, &1) == nil))
      }
    end

    @doc "The meshes and scatters of the cell at `address` at detail `level`. Reads nothing but `map`."
    @spec built(t(), World.t(), Cell.address(), non_neg_integer()) :: built()
    def built(%__MODULE__{settings: settings}, %World{} = map, address, level) do
      step = Enum.at(settings.steps, level)

      %{
        address: address,
        level: level,
        ground: OpenWorld.ground(map, address, step: step, skirt: settings.skirt),
        water: settings.water && OpenWorld.water(map, address),
        things:
          if(level <= settings.things_within, do: OpenWorld.things(map, address), else: %{}),
        cover:
          if(level <= settings.cover_within, do: covers(settings.cover, map, address), else: [])
      }
    end

    @doc "Uploads a built cell to `target` and answers the changes that show it at the place `map` gives it."
    @spec put(t(), Target.t(), World.t(), built()) :: {[Stream.change()], t()}
    def put(%__MODULE__{settings: settings} = shown, target, %World{} = map, built) do
      {slot, shown} = slot(shown, built.address)
      transform = OpenWorld.origin(map, built.address)
      before = Map.get(shown.cells, built.address, %{handles: [], ids: []})

      placed =
        [
          ground(settings, target, built, transform, slot),
          water(settings, target, built, transform, slot)
        ] ++
          things(settings, target, built, transform, slot) ++
          cover(settings, target, built, transform, slot)

      placed = Enum.reject(placed, &is_nil/1)
      ids = Enum.map(placed, fn {id, _instance, _handles} -> id end)
      gone = for id <- before.ids, id not in ids, do: {:remove_instance, id}
      Enum.each(before.handles, &Target.release(target, &1))

      cell = %{
        slot: slot,
        level: built.level,
        handles: Enum.flat_map(placed, &elem(&1, 2)),
        ids: ids
      }

      changes =
        gone ++ Enum.map(placed, fn {id, instance, _handles} -> {:instance, id, instance} end)

      {changes, %{shown | cells: Map.put(shown.cells, built.address, cell)}}
    end

    @doc "Removes the cells at `addresses` from `target`."
    @spec drop(t(), Target.t(), [Cell.address()]) :: {[Stream.change()], t()}
    def drop(%__MODULE__{} = shown, target, addresses) do
      Enum.reduce(addresses, {[], shown}, fn address, {changes, shown} ->
        case Map.pop(shown.cells, address) do
          {nil, _cells} ->
            {changes, shown}

          {cell, cells} ->
            Enum.each(cell.handles, &Target.release(target, &1))
            removed = Enum.map(cell.ids, &{:remove_instance, &1})
            {changes ++ removed, %{shown | cells: cells, free: [cell.slot | shown.free]}}
        end
      end)
    end

    @doc "One step for viewers at `eyes`: drops what is out of reach and builds up to `budget` cells."
    @spec frame(t(), Target.t(), World.t(), [World.point()], pos_integer()) ::
            {[Stream.change()], t()}
    def frame(%__MODULE__{} = shown, target, %World{} = map, eyes, budget \\ 1) do
      due = due(shown, map, eyes)
      {dropped, shown} = drop(shown, target, due.drop)

      due.build
      |> Enum.take(budget)
      |> Enum.reduce({dropped, shown}, fn {address, level}, {changes, shown} ->
        {added, shown} = put(shown, target, map, built(shown, map, address, level))
        {changes ++ added, shown}
      end)
    end

    defp covers(looks, map, address) do
      for {look, index} <- Enum.with_index(looks) do
        opts = [
          kind: look.kind,
          per: look.per,
          size: Map.get(look, :size, {1.0, 1.0}),
          seed: Map.get(look, :seed, index)
        ]

        {index, OpenWorld.cover(map, address, opts)}
      end
    end

    defp ground(settings, target, built, transform, slot) do
      mesh = Target.mesh(target, built.ground)

      {id(settings, slot, 0),
       %Instance{mesh: mesh, materials: [settings.ground], transform: transform}, [mesh]}
    end

    defp water(_settings, _target, %{water: nil}, _transform, _slot), do: nil

    defp water(settings, target, built, transform, slot) do
      mesh = Target.mesh(target, built.water)

      instance = %Instance{
        mesh: mesh,
        materials: [settings.water],
        transform: transform,
        shadows: false
      }

      {id(settings, slot, 1), instance, [mesh]}
    end

    defp things(settings, target, built, transform, slot) do
      settings.kinds
      |> Map.keys()
      |> Enum.sort()
      |> Enum.with_index(2)
      |> Enum.map(fn {kind, offset} ->
        scattered(
          target,
          Map.get(built.things, kind),
          Map.fetch!(settings.kinds, kind),
          transform,
          id(settings, slot, offset)
        )
      end)
    end

    defp cover(settings, target, built, transform, slot) do
      first = 2 + map_size(settings.kinds)

      for {index, scatter} <- built.cover do
        scattered(
          target,
          scatter,
          Enum.at(settings.cover, index),
          transform,
          id(settings, slot, first + index)
        )
      end
    end

    defp scattered(_target, nil, _look, _transform, _id), do: nil
    defp scattered(_target, %{count: 0}, _look, _transform, _id), do: nil

    defp scattered(target, scatter, look, transform, id) do
      handle = Target.scatter(target, scatter)

      instance = %Instance{
        mesh: look.mesh,
        materials: look.materials,
        transform: transform,
        scatter: handle,
        sway: Map.get(look, :sway),
        fade: Map.get(look, :fade),
        shadows: Map.get(look, :shadows, true)
      }

      {id, instance, [handle]}
    end

    defp slot(%__MODULE__{cells: cells} = shown, address) when is_map_key(cells, address),
      do: {cells[address].slot, shown}

    defp slot(%__MODULE__{free: [slot | free]} = shown, _address),
      do: {slot, %{shown | free: free}}

    defp slot(%__MODULE__{slots: slots} = shown, _address),
      do: {slots, %{shown | slots: slots + 1}}

    defp id(settings, slot, offset),
      do:
        settings.first_id + slot * (2 + map_size(settings.kinds) + length(settings.cover)) +
          offset

    defp nearest(map, address, eyes),
      do: eyes |> Enum.map(&Window.distance(map, address, &1)) |> Enum.min(fn -> 0.0 end)
  end
end
