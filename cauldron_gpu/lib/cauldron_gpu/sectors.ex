if Code.ensure_loaded?(Cauldron2D.Sectors.Map) do
  defmodule CauldronGPU.Sectors do
    @moduledoc """
    A `Cauldron2D.Sectors.Map` uploaded for drawing: one mesh holding every floor,
    ceiling and wall, a material per picture, and a sky cylinder.

        world = CauldronGPU.Sectors.upload(gpu, map, pictures, palette, sky: sky, sky_flats: [f_sky1])
        CauldronGPU.submit(gpu, CauldronGPU.Sectors.instances(world, first_id: 1))

    `pictures` is the `Cauldron2D.Sectors.Pictures` set the map's picture ids index, made
    with `native: false`; `palette` is 768 bytes. A map without a BSP gets one from
    `Cauldron2D.Sectors.Map.with_bsp/2`.

    Floors and ceilings come from `CauldronGPU.Sectors.Flats`, walls with Doom's pegging
    from `CauldronGPU.Sectors.Walls`. Each sector's light level is baked into the
    vertices' lightmap coordinates and read from one lightmap texture
    (`CauldronGPU.Sectors.Light`), so surfaces are lit with the environment's ambient
    light at `0`. Pictures with a mask are cut out where it is `0`. Ceilings whose picture
    is one of `:sky_flats` are left open, and upper walls between two such sectors left
    out; the `:sky` picture is drawn unlit on a cylinder far outside the map.

    Vertices stay in map units with heights on +Z; `transform/1` turns them into the
    renderer's frame (+Y up) at `:scale` metres a unit, and `point/2` does the same for one
    point such as a player start.

    Options:
      * `:sky` — picture id of the sky, default none (the environment's sky shows)
      * `:sky_flats` — picture ids that mark a sky ceiling, default `[]`
      * `:scale` — metres per map unit, default `1 / 32`
      * `:light_scale` — lightmap multiplier, default `2.0`
      * `:light_distance` — viewing distance in map units the light levels are taken at,
        default `128`
      * `:filter` — texture filtering, `:nearest` (default) or `:linear`
      * `:sky_distance` — the sky cylinder's radius in half widths of the map, default `64`
    """

    alias Cauldron2D.Sectors.Map, as: SectorMap
    alias Cauldron2D.Sectors.Pictures
    alias CauldronGPU.{Handle, Instance, Material, Quat, Transform}
    alias CauldronGPU.Sectors.{Flats, Light, Sky, Surfaces, Textures, Walls}

    @type model :: %{mesh: Handle.t(), materials: [Handle.t()], shadows: boolean()}
    @type t :: %__MODULE__{
            models: [model()],
            handles: [Handle.t()],
            scale: number(),
            far: float()
          }

    @enforce_keys [:models, :handles, :scale, :far]
    defstruct [:models, :handles, :scale, :far]

    @doc "Uploads `map`'s floors, ceilings, walls and pictures, and the sky."
    @spec upload(CauldronGPU.Target.t(), SectorMap.t(), Pictures.t(), binary(), keyword()) :: t()
    def upload(gpu, %SectorMap{} = map, %Pictures{} = pictures, palette, opts \\ []) do
      map = if map.subsectors, do: map, else: SectorMap.with_bsp(map)
      sky_flats = MapSet.new(Keyword.get(opts, :sky_flats, []))
      sky = Keyword.get(opts, :sky)
      scale = Keyword.get(opts, :scale, 1 / 32)

      surfaces =
        Flats.surfaces(map, pictures, sky_flats) ++ Walls.surfaces(map, pictures, sky_flats)

      {mesh, keys} = Surfaces.mesh(surfaces)

      ids =
        keys |> Enum.map(fn {:picture, id} -> id end) |> then(&Enum.uniq(&1 ++ List.wrap(sky)))

      textures =
        Textures.upload(gpu, pictures, palette, ids, Keyword.get(opts, :filter, :nearest))

      lightmap =
        CauldronGPU.Target.texture(gpu, Light.texture(Keyword.get(opts, :light_distance, 128)))

      light_scale = Keyword.get(opts, :light_scale, 2.0)

      level = %{
        mesh: CauldronGPU.Target.mesh(gpu, mesh),
        materials: Enum.map(keys, &picture_material(gpu, textures, &1, lightmap, light_scale)),
        shadows: true
      }

      {centre, radius} = extent(map, Keyword.get(opts, :sky_distance, 64))

      %__MODULE__{
        models: [level | sky_model(gpu, sky, textures, pictures, centre, radius)],
        handles: [lightmap | Enum.map(Map.values(textures), & &1.handle)],
        scale: scale,
        far: 2.5 * radius * scale
      }
    end

    @doc "The transform that places map coordinates in the renderer's frame."
    @spec transform(t() | number()) :: Transform.t()
    def transform(%__MODULE__{scale: scale}), do: transform(scale)

    def transform(scale),
      do: Transform.new(rotation: Quat.axis_angle({1, 0, 0}, -:math.pi() / 2), scale: scale)

    @doc "A map point `{x, y, height}` in the renderer's frame."
    @spec point(t(), {number(), number(), number()}) :: {float(), float(), float()}
    def point(%__MODULE__{scale: scale}, {x, y, z}), do: {x * scale, z * scale, -y * scale}

    @doc "The camera rotation facing a map angle of `degrees` (0 along +X, counter-clockwise from above)."
    @spec facing(number(), number()) :: Quat.t()
    def facing(degrees, pitch \\ 0.0),
      do: Quat.yaw_pitch((degrees - 90) * :math.pi() / 180, pitch)

    @doc "A camera far distance, in the renderer's units, that keeps the level and its sky in view."
    @spec far(t()) :: float()
    def far(%__MODULE__{far: far}), do: far

    @doc "Instance changes placing the level and its sky, ids counting up from `:first_id` (default 1)."
    @spec instances(t(), keyword()) :: [CauldronGPU.Stream.change()]
    def instances(%__MODULE__{} = world, opts \\ []) do
      world.models
      |> Enum.with_index(Keyword.get(opts, :first_id, 1))
      |> Enum.map(fn {model, id} ->
        {:instance, id,
         %Instance{
           mesh: model.mesh,
           materials: model.materials,
           shadows: model.shadows,
           transform: transform(world)
         }}
      end)
    end

    defp picture_material(gpu, textures, {:picture, id}, lightmap, light_scale) do
      %{handle: handle, masked: masked} = Map.fetch!(textures, id)

      CauldronGPU.Target.material(gpu, %Material{
        base_texture: handle,
        lightmap: lightmap,
        lightmap_scale: light_scale,
        alpha_cutoff: if(masked, do: 0.5, else: 0.0),
        roughness: 1.0
      })
    end

    defp sky_model(_gpu, nil, _textures, _pictures, _centre, _radius), do: []

    defp sky_model(gpu, sky, textures, pictures, centre, radius) do
      {mesh, [:sky]} = Surfaces.mesh(Sky.surfaces(centre, radius, Pictures.size(pictures, sky)))

      material =
        CauldronGPU.Target.material(gpu, %Material{
          base_texture: Map.fetch!(textures, sky).handle,
          unlit: true,
          double_sided: true
        })

      [%{mesh: CauldronGPU.Target.mesh(gpu, mesh), materials: [material], shadows: false}]
    end

    defp extent(%SectorMap{vertices: vertices, sectors: sectors}, sky_distance) do
      {xs, ys} = vertices |> Tuple.to_list() |> Enum.unzip()
      {left, right} = Enum.min_max(xs)
      {bottom, top} = Enum.min_max(ys)
      {low, _} = sectors |> Tuple.to_list() |> Enum.map(& &1.floor) |> Enum.min_max()
      {_, high} = sectors |> Tuple.to_list() |> Enum.map(& &1.ceiling) |> Enum.min_max()
      half = :math.sqrt((right - left) * (right - left) + (top - bottom) * (top - bottom)) / 2
      {{(left + right) / 2, (bottom + top) / 2, (low + high) / 2}, sky_distance * half}
    end
  end
end
