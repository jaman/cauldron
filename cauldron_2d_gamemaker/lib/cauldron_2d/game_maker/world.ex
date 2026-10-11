defmodule Cauldron2D.GameMaker.World do
  @moduledoc """
  A GameMaker game running: its data, its code, the room it is in and the instances in
  that room, as one value.

      world = Cauldron2D.GameMaker.World.new(data, MyGame.Code)
      world = Cauldron2D.GameMaker.Step.run(world, input)
      {world, items} = Cauldron2D.GameMaker.Draw.run(world)

  Instances are kept by id, and `order` lists their ids in creation order, the order
  GameMaker runs every event in. An object without code for an event runs its parent's,
  up the chain.

  Code changes the world through the functions here: `fetch/2`, `update/3`, `create/4`,
  `destroy/2`, `goto/2`, `put_global/3`, `emit/2`, `put_view/3`, `put_layer/3`. Instances
  code creates are numbered from one past the highest id any room places, as GameMaker
  numbers them, so they never take a placed instance's id. `views`
  are the room's views as the game has moved them, `scroll` how far each of the room's
  layers has scrolled by its speed since the room was entered, by layer id, and `layers`
  the changes code has made to the room's layers, by layer name (`layers/1` applies
  them), and `hidden_tiles` the depths of the GameMaker Studio 1 tiles code has hidden
  (`hide_tiles/3`); `added_tiles` the tiles code has added (`add_tile/5`). `particles` are those `Cauldron2D.GameMaker.Particles` has set loose; `surfaces`
  the rasters code draws onto, by id, with the next id to give (`Cauldron2D.GameMaker.Surfaces`
  keeps them; `Surfaces.rasters/1` reads them), drawn with the picture lookup `pictures`. `outbox` collects what the step sends
  out — sounds to play and the like — in the order it was sent; `take_outbox/1` empties
  it. `random` is the game's random number generator (`Cauldron2D.GameMaker.Random`),
  seeded with the `:seed` option. `object_depths` are the depths code creates objects
  at, by object index, where they differ from the objects' own (`:object_depths`).
  """

  alias Cauldron2D.GameMaker.Data
  alias Cauldron2D.GameMaker.Event
  alias Cauldron2D.GameMaker.Instance
  alias Cauldron2D.GameMaker.Object
  alias Cauldron2D.GameMaker.Random
  alias Cauldron2D.GameMaker.Rooms

  @enforce_keys [:data, :code, :objects, :sprites, :owners, :descendants]
  defstruct [
    :data,
    :code,
    :descendants,
    :objects,
    :sprites,
    :owners,
    :room,
    :pending_room,
    instances: %{},
    order: [],
    members: %{},
    created: 0,
    next_id: 100_000,
    globals: %{},
    input: %{held: MapSet.new(), pressed: MapSet.new(), released: MapSet.new()},
    steps: 0,
    hovered: MapSet.new(),
    outside: MapSet.new(),
    views: [],
    scroll: %{},
    layers: %{},
    hidden_tiles: MapSet.new(),
    added_tiles: [],
    particles: [],
    surfaces: %{rasters: %{}, next: 0},
    pictures: nil,
    drawing: [],
    outbox: [],
    random: Random.new(0),
    object_depths: %{},
    part_systems: %{systems: %{}, types: %{}, next_system: 0, next_type: 0}
  ]

  @type input :: %{
          required(:held) => MapSet.t(),
          required(:pressed) => MapSet.t(),
          required(:released) => MapSet.t(),
          optional(:mouse) => map()
        }

  @type t :: %__MODULE__{
          data: Data.t(),
          code: module(),
          objects: tuple(),
          sprites: tuple(),
          owners: tuple(),
          descendants: tuple(),
          room: non_neg_integer() | nil,
          pending_room: non_neg_integer() | nil,
          instances: %{non_neg_integer() => Instance.t()},
          order: [non_neg_integer()],
          members: %{non_neg_integer() => [{non_neg_integer(), non_neg_integer()}]},
          created: non_neg_integer(),
          next_id: non_neg_integer(),
          globals: map(),
          input: input(),
          steps: non_neg_integer(),
          hovered: MapSet.t(),
          outside: MapSet.t(),
          views: [Cauldron2D.GameMaker.Room.View.t()],
          scroll: %{non_neg_integer() => {number(), number()}},
          layers: %{String.t() => map()},
          hidden_tiles: MapSet.t(number()),
          added_tiles: [map()],
          particles: [map()],
          surfaces: %{
            rasters: %{non_neg_integer() => FrenchCurve.Raster.t()},
            next: non_neg_integer()
          },
          pictures: (term() -> FrenchCurve.Raster.t() | nil) | nil,
          drawing: list(),
          outbox: list(),
          random: Random.t(),
          object_depths: %{non_neg_integer() => number()},
          part_systems: map()
        }

  @doc """
  The game in its first room, its instances created and the room started. Options:
  `:room`, a room index to start in instead of the first in the room order;
  `:pictures`, the function from a draw list picture key to its raster that drawing
  onto surfaces uses; `:seed`, the random number generator's seed (default `0`);
  `:object_depths`, a map from object name to the depth `create/4` gives its instances —
  a GameMaker Studio 2 game converted from GameMaker: Studio 1 keeps its objects' old
  depths in such a table and creates instances at them (`object_get_depth`); an object
  it does not name keeps its own depth.
  """
  @spec new(Data.t(), module(), keyword()) :: t()
  def new(%Data{} = data, code, opts \\ []) do
    objects = List.to_tuple(data.objects)

    world = %__MODULE__{
      data: data,
      code: code,
      objects: objects,
      sprites: List.to_tuple(data.sprites),
      owners: owners(data.objects),
      descendants: descendants(data.objects),
      pictures: Keyword.get(opts, :pictures),
      next_id: first_free_id(data),
      random: Random.new(Keyword.get(opts, :seed, 0)),
      object_depths: object_depths(data, Keyword.get(opts, :object_depths, %{}))
    }

    Rooms.enter(world, Keyword.get_lazy(opts, :room, fn -> hd(data.general.room_order) end))
  end

  defp object_depths(%Data{objects: objects}, by_name) do
    for {%{name: name}, index} <- Enum.with_index(objects),
        Map.has_key?(by_name, name),
        into: %{},
        do: {index, Map.fetch!(by_name, name)}
  end

  defp first_free_id(%Data{rooms: rooms}) do
    placed = for %{instances: instances} <- rooms, %{id: id} <- instances, do: id
    max(Enum.max(placed, fn -> 99_999 end) + 1, 100_000)
  end

  @doc "The instance `id`, `nil` once it is gone."
  @spec fetch(t(), non_neg_integer() | nil) :: Instance.t() | nil
  def fetch(%__MODULE__{instances: instances}, id), do: Map.get(instances, id)

  @doc "The world with instance `id` replaced by `fun` of it; unchanged when it is gone."
  @spec update(t(), non_neg_integer(), (Instance.t() -> Instance.t())) :: t()
  def update(%__MODULE__{instances: instances} = world, id, fun) do
    case Map.fetch(instances, id) do
      {:ok, instance} -> %{world | instances: Map.put(instances, id, fun.(instance))}
      :error -> world
    end
  end

  @doc "The object definition at `index`."
  @spec object(t(), non_neg_integer()) :: Object.t()
  def object(%__MODULE__{objects: objects}, index), do: elem(objects, index)

  @doc "The sprite at `index`, `nil` for a negative index."
  @spec sprite(t(), integer()) :: Cauldron2D.GameMaker.Sprite.t() | nil
  def sprite(%__MODULE__{}, index) when index < 0, do: nil
  def sprite(%__MODULE__{sprites: sprites}, index), do: elem(sprites, index)

  @doc "The index of the object called `name`."
  @spec object_index(t(), String.t()) :: non_neg_integer() | nil
  def object_index(%__MODULE__{data: data}, name), do: Data.index(data, :objects, name)

  @doc """
  A new instance of `object` at `{x, y}`, its pre-create and create events run, and its
  id. `fields` are instance variables set before those events run (scale, angle and so
  on, as a room places an instance).
  """
  @spec create(t(), non_neg_integer(), {number(), number()}, map()) :: {t(), non_neg_integer()}
  def create(%__MODULE__{} = world, object, {x, y}, fields \\ %{}) do
    id = Map.get(fields, :id, world.next_id)
    definition = object(world, object)

    instance =
      %Instance{
        id: id,
        object: object,
        x: x,
        y: y,
        xstart: x,
        ystart: y,
        xprevious: x,
        yprevious: y,
        sprite_index: definition.sprite,
        mask_index: definition.mask,
        depth: Map.get(world.object_depths, object, definition.depth),
        visible: definition.visible,
        solid: definition.solid,
        persistent: definition.persistent
      }
      |> struct(Map.delete(fields, :id))

    world =
      %{
        world
        | instances: Map.put(world.instances, id, instance),
          order: world.order ++ [id],
          next_id: max(world.next_id, id + 1)
      }
      |> joined(id, instance.object)

    world =
      world
      |> perform(id, :pre_create, 0)
      |> perform(id, :create, 0)

    {world, id}
  end

  @doc "The world after instance `id`'s destroy and clean-up events, without it."
  @spec destroy(t(), non_neg_integer()) :: t()
  def destroy(%__MODULE__{} = world, id) do
    if fetch(world, id) do
      world
      |> perform(id, :destroy, 0)
      |> perform(id, :clean_up, 0)
      |> remove(id)
    else
      world
    end
  end

  @doc "The world without instance `id`, no events run."
  @spec remove(t(), non_neg_integer()) :: t()
  def remove(%__MODULE__{} = world, id) do
    %{
      world
      | instances: Map.delete(world.instances, id),
        order: List.delete(world.order, id),
        outside: MapSet.delete(world.outside, id)
    }
    |> parted(fetch(world, id))
  end

  @doc """
  The ids, in creation order, of the instances of `object` and of every object that
  descends from it; `:all` for every instance.
  """
  @spec instances_of(t(), non_neg_integer() | :all) :: [non_neg_integer()]
  def instances_of(%__MODULE__{order: order}, :all), do: order

  def instances_of(%__MODULE__{descendants: descendants, members: members}, object) do
    case for(
           kind <- elem(descendants, object),
           found = Map.get(members, kind, []),
           found != [],
           do: found
         ) do
      [] -> []
      [only] -> Enum.map(only, &elem(&1, 1))
      several -> several |> Enum.concat() |> Enum.sort() |> Enum.map(&elem(&1, 1))
    end
  end

  @doc "Whether object `object` is `ancestor` or descends from it."
  @spec descends?(t(), non_neg_integer() | nil, non_neg_integer()) :: boolean()
  def descends?(_world, nil, _ancestor), do: false
  def descends?(_world, ancestor, ancestor), do: true

  def descends?(world, object, ancestor),
    do: descends?(world, object(world, object).parent, ancestor)

  @doc "Whether instance `id`'s object, or an ancestor, has code for the event."
  @spec handles?(t(), non_neg_integer(), Event.type(), term()) :: boolean()
  def handles?(%__MODULE__{} = world, id, type, subtype) do
    case fetch(world, id) do
      nil -> false
      instance -> Map.has_key?(elem(world.owners, instance.object), {type, subtype})
    end
  end

  @doc """
  The world after instance `id` runs its code for the event `type` with `subtype`,
  `other` being the other instance of a collision. Nothing runs when the instance is
  gone or has no code for the event.
  """
  @spec perform(t(), non_neg_integer(), Event.type(), term(), non_neg_integer() | nil) :: t()
  def perform(%__MODULE__{} = world, id, type, subtype, other \\ nil) do
    with %Instance{object: object} <- fetch(world, id),
         {:ok, owner} <- Map.fetch(elem(world.owners, object), {type, subtype}) do
      run(world, owner, id, type, subtype, other)
    else
      _ -> world
    end
  end

  @doc """
  The world after instance `id` runs the code the parent of `object` (an object name)
  has for the event: GameMaker's `event_inherited`, called from `object`'s own code.
  """
  @spec inherited(
          t(),
          non_neg_integer(),
          String.t(),
          Event.type(),
          term(),
          non_neg_integer() | nil
        ) ::
          t()
  def inherited(%__MODULE__{} = world, id, object, type, subtype, other \\ nil) do
    with index when is_integer(index) <- object_index(world, object),
         parent when is_integer(parent) <- object(world, index).parent,
         {:ok, owner} <- Map.fetch(elem(world.owners, parent), {type, subtype}) do
      run(world, owner, id, type, subtype, other)
    else
      _ -> world
    end
  end

  @doc "The world after running the code named `name`, if the game has any."
  @spec run_named(t(), String.t(), non_neg_integer() | nil, non_neg_integer() | nil) :: t()
  def run_named(%__MODULE__{code: code} = world, name, self, other \\ nil) do
    case code.handler(name) do
      nil -> world
      handler -> handler.(world, self, other)
    end
  end

  @doc """
  The world with view `index`'s `view` rectangle `{x, y, width, height}` set: GameMaker's
  `view_xview`, `view_yview`, `view_wview` and `view_hview`.
  """
  @spec put_view(t(), non_neg_integer(), {number(), number(), number(), number()}) :: t()
  def put_view(%__MODULE__{views: views} = world, index, rectangle),
    do: %{world | views: List.update_at(views, index, &%{&1 | view: rectangle})}

  @doc """
  The world with the room's layer `name` changed, as GameMaker's `layer_set_visible`,
  `layer_x`, `layer_y`, `layer_hspeed`, `layer_vspeed`, `layer_depth` and
  `layer_background_*` change it: `changes` has any of `:visible`, `:offset` `{x, y}`,
  `:speed` `{x, y}`, `:depth`, `:background`, a map of the background layer's own
  fields (`:sprite`, `:colour` `{r, g, b, a}`, `:tiled`, `:stretch`, `:xscale`, `:yscale`,
  …), and
  `:tile_blend` `{r, g, b}`, the colour every tile of an asset layer is drawn with, its
  alpha kept (`layer_tile_blend` on each of the layer's tiles). Changes add up until the
  room is left.
  """
  @spec put_layer(t(), String.t(), map()) :: t()
  def put_layer(%__MODULE__{layers: layers} = world, name, changes) do
    merged =
      Map.merge(Map.get(layers, name, %{}), changes, fn
        :background, old, new -> Map.merge(old, new)
        _key, _old, new -> new
      end)

    %{world | layers: Map.put(layers, name, merged)}
  end

  @doc "The room's layers with the changes code has made to them (`put_layer/3`)."
  @spec layers(t()) :: [Cauldron2D.GameMaker.Room.Layer.t()]
  def layers(%__MODULE__{} = world) do
    world.data.rooms
    |> Enum.at(world.room)
    |> Map.fetch!(:layers)
    |> Enum.map(&changed(&1, Map.get(world.layers, &1.name)))
  end

  @doc "The world going to room `room` once the current step ends."
  @spec goto(t(), non_neg_integer()) :: t()
  def goto(%__MODULE__{} = world, room), do: %{world | pending_room: room}

  @doc """
  The world with the room's GameMaker Studio 1 tiles at depth `depth` hidden (`hidden`
  true, `tile_layer_hide`) or shown again (`tile_layer_show`). Entering a room shows
  every tile.
  """
  @spec hide_tiles(t(), number(), boolean()) :: t()
  def hide_tiles(%__MODULE__{hidden_tiles: hidden} = world, depth, true),
    do: %{world | hidden_tiles: MapSet.put(hidden, depth)}

  def hide_tiles(%__MODULE__{hidden_tiles: hidden} = world, depth, false),
    do: %{world | hidden_tiles: MapSet.delete(hidden, depth)}

  @doc """
  The world with a tile added by code (`tile_add`): the part `{left, top, width,
  height}` of frame 0 of sprite `sprite`, its top-left corner at `{x, y}`, at depth
  `depth`. It is drawn until the room is left, hidden with the room's tiles at its depth
  (`hide_tiles/3`).
  """
  @spec add_tile(
          t(),
          non_neg_integer(),
          {number(), number(), number(), number()},
          {number(), number()},
          number()
        ) ::
          t()
  def add_tile(%__MODULE__{added_tiles: tiles} = world, sprite, source, position, depth),
    do: %{
      world
      | added_tiles:
          tiles ++ [%{sprite: sprite, source: source, position: position, depth: depth}]
    }

  @doc "The global variable `name`, `default` when unset."
  @spec global(t(), term(), term()) :: term()
  def global(%__MODULE__{globals: globals}, name, default \\ nil),
    do: Map.get(globals, name, default)

  @doc "The world with global variable `name` set to `value`."
  @spec put_global(t(), term(), term()) :: t()
  def put_global(%__MODULE__{globals: globals} = world, name, value),
    do: %{world | globals: Map.put(globals, name, value)}

  @doc "The world with `message` added to its outbox."
  @spec emit(t(), term()) :: t()
  def emit(%__MODULE__{outbox: outbox} = world, message),
    do: %{world | outbox: [message | outbox]}

  @doc "The outbox's messages in the order sent, and the world with it empty."
  @spec take_outbox(t()) :: {list(), t()}
  def take_outbox(%__MODULE__{outbox: outbox} = world),
    do: {Enum.reverse(outbox), %{world | outbox: []}}

  defp changed(layer, nil), do: layer

  defp changed(layer, changes) do
    {background, plain} = Map.pop(changes, :background)
    {tile_blend, plain} = Map.pop(plain, :tile_blend)

    layer
    |> struct(plain)
    |> changed_background(background)
    |> blended_tiles(tile_blend)
  end

  defp changed_background(%{content: {:background, own}} = layer, %{} = new),
    do: %{layer | content: {:background, Map.merge(own, new)}}

  defp changed_background(layer, _background), do: layer

  defp blended_tiles(%{content: {:assets, assets}} = layer, {red, green, blue}) do
    tiles = Enum.map(assets.tiles, &blended_tile(&1, {red, green, blue}))
    %{layer | content: {:assets, %{assets | tiles: tiles}}}
  end

  defp blended_tiles(layer, _tile_blend), do: layer

  defp blended_tile(%{colour: {_red, _green, _blue, alpha}} = tile, {red, green, blue}) do
    %{tile | colour: {red, green, blue, alpha}}
  end

  defp run(world, owner, id, type, subtype, other) do
    name = object(world, owner).name

    run_named(
      world,
      Event.handler_name(name, type, subtype_name(world, type, subtype)),
      id,
      other
    )
  end

  defp subtype_name(world, :collision, object), do: object(world, object).name
  defp subtype_name(_world, _type, subtype), do: subtype

  defp descendants(objects) do
    indexed = List.to_tuple(objects)
    count = tuple_size(indexed)

    0..(count - 1)//1
    |> Enum.flat_map(&Enum.map(lineage(indexed, &1), fn ancestor -> {ancestor, &1} end))
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> then(fn grouped -> Enum.map(0..(count - 1)//1, &Map.get(grouped, &1, [])) end)
    |> List.to_tuple()
  end

  defp lineage(objects, index) do
    case elem(objects, index) do
      %Object{parent: nil} -> [index]
      %Object{parent: parent} -> [index | lineage(objects, parent)]
    end
  end

  defp joined(world, id, object) do
    member = {world.created, id}

    %{
      world
      | members: Map.update(world.members, object, [member], &(&1 ++ [member])),
        created: world.created + 1
    }
  end

  defp parted(world, nil), do: world

  defp parted(world, %Instance{id: id, object: object}) do
    members = world.members |> Map.get(object, []) |> List.keydelete(id, 1)
    %{world | members: Map.put(world.members, object, members)}
  end

  defp owners(objects) do
    indexed = List.to_tuple(objects)

    0..(tuple_size(indexed) - 1)//1
    |> Enum.map(&owned(indexed, &1))
    |> List.to_tuple()
  end

  defp owned(objects, index) do
    %Object{events: events, parent: parent} = elem(objects, index)
    inherited = if parent, do: owned(objects, parent), else: %{}

    Enum.reduce(events, inherited, fn {type, subtype, _code}, owners ->
      Map.put(owners, {type, subtype}, index)
    end)
  end
end
