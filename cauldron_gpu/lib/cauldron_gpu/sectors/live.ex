if Code.ensure_loaded?(Cauldron2D.Sectors.Map) do
  defmodule CauldronGPU.Sectors.Live do
    @moduledoc """
    A `Cauldron2D.Sectors.Map` drawn while its sectors move: doors and lifts change
    heights, lights flicker, switches and animated pictures change what sides and flats
    show. Each sector is one mesh and one instance — its floors, ceilings and the walls
    facing into it — and `update/5` rebuilds only the sectors that changed and their
    neighbours. Each sector's light level is held in a lightmap with a row per sector
    (`CauldronGPU.Sectors.Live.Lightmap`), put again whenever a light changes, and turned
    into light falling with distance by a light table
    (`CauldronGPU.Sectors.Live.LightTable`) the caller puts in its environment with
    `light_space: :display`:

        {table, reach} = CauldronGPU.Sectors.Live.light_table(live)
        %CauldronGPU.Environment{light_space: :display, light_table: {table, reach}, tone_map: :clamp}

    Sky ceilings and floors, and the upper walls left out between two sky ceilings, are
    `sky` surfaces showing the environment's sky, so they hide what lies beyond them as
    Doom's sky does; `sky_box/4` gives the sky picture as a box laid out as Doom draws its
    sky (`CauldronGPU.Sectors.Live.SkyBox`), for the environment's `sky_picture`:

        {faces, live} = CauldronGPU.Sectors.Live.sky_box(live, target, 1.2, nil)
        %CauldronGPU.Environment{sky_picture: {:box, faces}}

        live = CauldronGPU.Sectors.Live.new(map, pictures, palette, sky: sky, sky_flats: [f_sky1], first_id: 1)
        {changes, live} = CauldronGPU.Sectors.Live.update(live, target, sectors, sides, shown: %{}, stretch: 1.2)
        CauldronGPU.Target.submit(target, changes)
        CauldronGPU.Target.submit(target, CauldronGPU.Sectors.Live.close(live, target))

    `map` carries a BSP; `pictures` is the `Cauldron2D.Sectors.Pictures` set its picture
    ids index, made with `native: false`; `palette` is 768 bytes. `sectors` and `sides` are
    the map's as they are now, with the shapes `Cauldron2D.Sectors.Map` gives them.

    Instances take the ids from `:first_id` up, one a sector in sector order (`ids/1`).

    Options of `new/4`:
      * `:sky` — picture id of the sky, default none
      * `:sky_flats` — picture ids that mark a sky ceiling, default `[]`
      * `:first_id` — the first instance id, default `1`
      * `:scale` — metres per map unit, default `1 / 32`
      * `:light` — the options of `Cauldron2D.Sectors.Light` the light table follows,
        default `[]`

    Options of `update/5`, as `Cauldron2D.Sectors.View` takes them:
      * `:shown` — `%{picture => picture}`, the picture drawn in place of another this
        tick, for animated pictures; default `%{}`
      * `:extra_light` — light added to every level, default `0`
      * `:fixed` — a light table every picture is drawn through at full light, default
        `nil`
      * `:stretch` — how many times taller than wide a map unit is drawn, default `1.0`

    Pictures are uploaded the first time they are drawn.
    """

    alias Cauldron2D.Sectors.Map, as: SectorMap
    alias Cauldron2D.Sectors.Pictures, as: Set
    alias CauldronGPU.{Handle, Instance, Material, Quat, Target, Transform}
    alias CauldronGPU.Sectors.Live.{Geometry, Lightmap, LightTable, Mesh, Pictures, SkyBox}

    @sky_face 512

    @type t :: %__MODULE__{
            geometry: Geometry.t(),
            pictures: Pictures.t(),
            count: pos_integer(),
            first_id: pos_integer(),
            scale: number(),
            sky: non_neg_integer() | nil,
            sky_flats: MapSet.t(),
            light_options: keyword(),
            light_table: {Handle.t(), float()} | nil,
            reach: float(),
            sky_material: Handle.t() | nil,
            sky_boxes: %{{number(), non_neg_integer() | nil} => %{atom() => Handle.t()}},
            sectors: tuple() | nil,
            sides: tuple() | nil,
            meshes: %{non_neg_integer() => %{mesh: Handle.t(), keys: [term()]}},
            placed: %{non_neg_integer() => term()},
            lightmap: Handle.t() | nil,
            light: term()
          }

    @enforce_keys [:geometry, :pictures, :count, :first_id, :scale, :reach]
    defstruct [
      :geometry,
      :pictures,
      :count,
      :first_id,
      :scale,
      :sky,
      :reach,
      :sky_material,
      :lightmap,
      :light,
      :light_table,
      :sectors,
      :sides,
      sky_flats: MapSet.new(),
      sky_boxes: %{},
      light_options: [],
      meshes: %{},
      placed: %{}
    ]

    @doc "A live map ready for its first `update/5`; nothing is uploaded yet."
    @spec new(SectorMap.t(), Set.t(), binary(), keyword()) :: t()
    def new(%SectorMap{} = map, %Set{} = pictures, palette, opts \\ []) do
      map = if map.subsectors, do: map, else: SectorMap.with_bsp(map)

      %__MODULE__{
        geometry: Geometry.new(map),
        pictures: Pictures.new(pictures, palette),
        count: tuple_size(map.sectors),
        first_id: Keyword.get(opts, :first_id, 1),
        scale: Keyword.get(opts, :scale, 1 / 32),
        sky: Keyword.get(opts, :sky),
        sky_flats: MapSet.new(Keyword.get(opts, :sky_flats, [])),
        light_options: Keyword.get(opts, :light, []),
        reach: extent(map)
      }
    end

    @doc """
    The changes that draw the map with `sectors` and `sides` as they are now, and the
    live map to update next time. Meshes, textures and materials it needs are uploaded
    through `target`.
    """
    @spec update(t(), Target.t(), tuple(), tuple(), keyword()) ::
            {[CauldronGPU.Stream.change()], t()}
    def update(%__MODULE__{} = live, target, sectors, sides, opts \\ []) do
      look = %{
        shown: Keyword.get(opts, :shown, %{}),
        extra: Keyword.get(opts, :extra_light, 0),
        fixed: Keyword.get(opts, :fixed),
        stretch: Keyword.get(opts, :stretch, 1.0)
      }

      dirty = live |> dirty(sectors, sides) |> MapSet.to_list()

      {[], live}
      |> light(target, sectors, look)
      |> rebuild(target, dirty, sectors, sides)
      |> place(target, look)
      |> then(fn {changes, live} ->
        {Enum.reverse(changes), %{live | sectors: sectors, sides: sides}}
      end)
    end

    @doc "Removes every instance placed and releases every handle uploaded; gives the removing changes."
    @spec close(t(), Target.t()) :: [CauldronGPU.Stream.change()]
    def close(%__MODULE__{} = live, target) do
      handles =
        Enum.map(Map.values(live.meshes), & &1.mesh) ++
          Pictures.handles(live.pictures) ++
          Enum.reject(
            [live.lightmap, live.sky_material, table_handle(live.light_table)],
            &is_nil/1
          ) ++
          Enum.flat_map(Map.values(live.sky_boxes), &Map.values/1)

      Enum.each(handles, &Target.release(target, &1))
      for sector <- Map.keys(live.placed), do: {:remove_instance, instance_id(live, sector)}
    end

    @doc """
    The light table and its reach in metres, for the environment's `light_table`; `nil`
    before the first `update/5`.
    """
    @spec light_table(t()) :: {Handle.t(), float()} | nil
    def light_table(%__MODULE__{light_table: light_table}), do: light_table

    @doc "The instance ids the live map uses."
    @spec ids(t()) :: Range.t()
    def ids(%__MODULE__{first_id: first, count: count}), do: first..(first + count - 1)

    @doc "The texture of `picture` through light table `table` (`nil` for none), uploaded the first time."
    @spec texture(t(), Target.t(), non_neg_integer(), non_neg_integer() | nil) ::
            {Pictures.texture(), t()}
    def texture(%__MODULE__{} = live, target, picture, table) do
      {texture, pictures} = Pictures.texture(live.pictures, target, picture, table)
      {texture, %{live | pictures: pictures}}
    end

    @doc """
    A material kept as `key` (a tuple whose second and third elements are a picture and a
    light table), made the first time by `make` from that picture's texture.
    """
    @spec material(t(), Target.t(), tuple(), (Pictures.texture() -> Material.t())) ::
            {Handle.t(), t()}
    def material(%__MODULE__{} = live, target, key, make) do
      {handle, pictures} = Pictures.material(live.pictures, target, key, make)
      {handle, %{live | pictures: pictures}}
    end

    @doc "The transform that places map coordinates in the renderer's frame, heights times `stretch`."
    @spec transform(t(), number()) :: Transform.t()
    def transform(%__MODULE__{scale: scale}, stretch) do
      Transform.new(
        rotation: Quat.axis_angle({1, 0, 0}, -:math.pi() / 2),
        scale: {scale, scale, scale * stretch}
      )
    end

    @doc "A map point `{x, y, height}` in the renderer's frame, heights times `stretch`."
    @spec point(t(), {number(), number(), number()}, number()) :: {float(), float(), float()}
    def point(%__MODULE__{scale: scale}, {x, y, z}, stretch),
      do: {x * scale, z * scale * stretch, -y * scale}

    @doc "A camera far distance, in the renderer's units, that keeps the level and its sky in view."
    @spec far(t(), number()) :: float()
    def far(%__MODULE__{reach: reach, scale: scale}, stretch),
      do: 2 * reach * scale * max(stretch, 1.0)

    @doc """
    The sky picture as the six faces of an environment's `{:box, faces}` sky, for heights
    drawn `stretch` times taller than wide and pictures through light table `table`
    (`nil` for none); made the first time for each, `nil` for a map with no sky picture.
    """
    @spec sky_box(t(), Target.t(), number(), non_neg_integer() | nil) ::
            {%{atom() => Handle.t()} | nil, t()}
    def sky_box(%__MODULE__{sky: nil} = live, _target, _stretch, _table), do: {nil, live}

    def sky_box(%__MODULE__{} = live, target, stretch, table) do
      case Map.fetch(live.sky_boxes, {stretch, table}) do
        {:ok, faces} ->
          {faces, live}

        :error ->
          {colours, pictures} = Pictures.colours(live.pictures, table)
          picture = elem(pictures.set.pictures, live.sky)

          faces =
            picture
            |> SkyBox.faces(colours, stretch, @sky_face)
            |> Map.new(fn {face, texture} -> {face, Target.texture(target, texture)} end)

          {faces,
           %{
             live
             | pictures: pictures,
               sky_boxes: Map.put(live.sky_boxes, {stretch, table}, faces)
           }}
      end
    end

    defp dirty(%__MODULE__{sectors: nil, count: count}, _sectors, _sides),
      do: MapSet.new(0..(count - 1))

    defp dirty(live, sectors, sides) do
      moved = changed_sectors(live.sectors, sectors)

      moved
      |> Enum.reduce(moved, &MapSet.union(&2, Geometry.neighbours(live.geometry, &1)))
      |> MapSet.union(changed_sides(live.sides, sides))
    end

    defp changed_sectors(same, same), do: MapSet.new()

    defp changed_sectors(old, new) do
      for index <- 0..(tuple_size(new) - 1),
          shape(elem(old, index)) != shape(elem(new, index)),
          into: MapSet.new(),
          do: index
    end

    defp shape(sector),
      do: {sector.floor, sector.ceiling, sector.floor_picture, sector.ceiling_picture}

    defp changed_sides(same, same), do: MapSet.new()

    defp changed_sides(old, new) do
      for index <- 0..(tuple_size(new) - 1),
          elem(old, index) != elem(new, index),
          into: MapSet.new(),
          do: elem(new, index).sector
    end

    defp light({changes, live}, target, sectors, look) do
      levels = for sector <- Tuple.to_list(sectors), do: sector.light
      key = {levels, look.extra, look.fixed}

      cond do
        key == live.light ->
          {changes, live}

        live.lightmap == nil ->
          handle = Target.texture(target, lightmap(key))
          {texture, reach} = LightTable.texture(live.scale, live.light_options)
          table = {Target.texture(target, texture), reach}
          {changes, %{live | lightmap: handle, light: key, light_table: table}}

        true ->
          {[{:texture, live.lightmap.id, lightmap(key)} | changes], %{live | light: key}}
      end
    end

    defp lightmap({levels, extra, fixed}), do: Lightmap.texture(levels, extra, fixed)

    defp rebuild({changes, live}, _target, [], _sectors, _sides), do: {changes, live}

    defp rebuild({changes, live}, target, dirty, sectors, sides) do
      live.geometry
      |> Geometry.surfaces(
        dirty,
        sectors,
        sides,
        live.pictures.set,
        live.sky_flats
      )
      |> Enum.reduce({changes, live}, fn {sector, surfaces}, acc ->
        put_sector(acc, target, sector, surfaces)
      end)
    end

    defp put_sector({changes, live}, target, sector, []) do
      case Map.pop(live.meshes, sector) do
        {nil, _meshes} ->
          {changes, live}

        {%{mesh: mesh}, meshes} ->
          Target.release(target, mesh)

          {[{:remove_instance, instance_id(live, sector)} | changes],
           %{live | meshes: meshes, placed: Map.delete(live.placed, sector)}}
      end
    end

    defp put_sector({changes, live}, target, sector, surfaces) do
      {mesh, keys} = Mesh.build(surfaces, live.count)

      {changes, handle} =
        case Map.get(live.meshes, sector) do
          nil -> {changes, Target.mesh(target, mesh)}
          %{mesh: handle} -> {[{:mesh, handle.id, mesh} | changes], handle}
        end

      {changes,
       %{
         live
         | meshes: Map.put(live.meshes, sector, %{mesh: handle, keys: keys}),
           placed: Map.put(live.placed, sector, :rebuilt)
       }}
    end

    defp place({changes, live}, target, look) do
      Enum.reduce(live.meshes, {changes, live}, fn {sector, %{mesh: mesh, keys: keys}},
                                                   {changes, live} ->
        {materials, live} = surface_materials(live, target, keys, look)
        placing = {Enum.map(materials, & &1.id), look.stretch}

        if Map.get(live.placed, sector) == placing do
          {changes, live}
        else
          instance = %Instance{
            mesh: mesh,
            materials: materials,
            shadows: false,
            transform: transform(live, look.stretch)
          }

          {[{:instance, instance_id(live, sector), instance} | changes],
           %{live | placed: Map.put(live.placed, sector, placing)}}
        end
      end)
    end

    defp surface_materials(live, target, keys, look) do
      Enum.map_reduce(keys, live, fn
        :sky, live ->
          sky_material(live, target)

        {:picture, picture}, live ->
          surface_material(live, target, Map.get(look.shown, picture, picture), look)
      end)
    end

    defp sky_material(%__MODULE__{sky_material: nil} = live, target) do
      handle = Target.material(target, %Material{sky: true, double_sided: true})
      {handle, %{live | sky_material: handle}}
    end

    defp sky_material(live, _target), do: {live.sky_material, live}

    defp surface_material(live, target, shown, look) do
      material(live, target, {:surface, shown, look.fixed}, fn texture ->
        %Material{
          base_texture: texture.handle,
          lightmap: live.lightmap,
          lightmap_scale: 1.0,
          alpha_cutoff: if(texture.masked, do: 0.5, else: 0.0),
          roughness: 1.0
        }
      end)
    end

    defp table_handle(nil), do: nil
    defp table_handle({handle, _reach}), do: handle

    defp instance_id(live, sector), do: live.first_id + sector

    defp extent(%SectorMap{vertices: vertices}) do
      {xs, ys} = vertices |> Tuple.to_list() |> Enum.unzip()
      {left, right} = Enum.min_max(xs)
      {bottom, top} = Enum.min_max(ys)
      :math.sqrt((right - left) * (right - left) + (top - bottom) * (top - bottom))
    end
  end
end
