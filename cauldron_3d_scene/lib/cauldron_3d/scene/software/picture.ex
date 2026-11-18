if Code.ensure_loaded?(Cauldron3D.Render) do
  defmodule Cauldron3D.Scene.Software.Picture do
    @moduledoc """
    One frame of a scene drawn by `Cauldron3D.Render` on the CPU, for
    `Cauldron3D.Scene.Software`: the sky's shading behind everything, each shown
    instance's triangles textured with its materials' base textures and tinted by
    `Cauldron3D.Scene.Software.Lighting`, then the screen tint and the overlay over the
    whole frame. Answers the frame's RGBA pixels, rows from the top.

    Drawn: meshes with their parts' materials (base colour and texture, vertex colours,
    `alpha_cutoff`, `:blend` and `:add` alpha modes, `double_sided`, `unlit`, emissive
    colour), poses (blending and bones), `in_front` and `depth_test: false` instances,
    the environment's sky shading, ambient light and exposure, point, spot and directional
    lights, the screen tint and the overlay. Not drawn: shadows, reflections, ray-traced
    effects, lightmaps and light styles, normal and occlusion maps, sky pictures, fog,
    2D layers and canvases' contents.
    """

    alias Cauldron3D.Scene.{Camera, Environment, Instance, Material, Quat, Transform}
    alias Cauldron3D.Scene.Host.Record
    alias Cauldron3D.Scene.Software.{Display, Lighting, Posing, Resources}

    @palette :binary.copy(<<0, 0, 0>>, 256)
    @blank_material %Material{base_color: {0.8, 0.8, 0.8, 1.0}}

    @doc "The RGBA pixels of `record` drawn at `{width, height}`; black before it has a camera."
    @spec draw(Record.t(), Resources.t(), {pos_integer(), pos_integer()}) :: binary()
    def draw(%Record{camera: nil}, _resources, {width, height}),
      do: :binary.copy(<<0, 0, 0, 255>>, width * height)

    def draw(%Record{camera: camera} = record, resources, {width, height}) do
      environment = record.environment || %Environment{}

      camera
      |> view({width, height})
      |> Cauldron3D.Render.draw(polygons(record, resources, {width, height}),
        palette: @palette,
        backdrop: sky(environment, {width, height})
      )
      |> Map.fetch!(:pixels)
    end

    @doc "The `Cauldron3D.Polygon`s `draw/3` draws `record` from at `{width, height}`, back faces left out: the instances, then the screen tint and the overlay."
    @spec polygons(Record.t(), Resources.t(), {pos_integer(), pos_integer()}) :: [
            Cauldron3D.Polygon.t()
          ]
    def polygons(%Record{camera: camera} = record, resources, size) do
      environment = record.environment || %Environment{}
      view = view(camera, size)

      lights = Map.values(record.lights)

      instances =
        record.instances
        |> Enum.flat_map(&job(&1, record, resources))
        |> Enum.flat_map(&job_polygons(&1, lights, {environment, camera.position}))

      instances ++
        tint_polygons(record.screen_tint, view) ++
        overlay_polygons(record.overlay, view, resources)
    end

    @doc "The `Cauldron3D.View` of a scene camera in a picture of `{width, height}` pixels."
    @spec view(Camera.t(), {pos_integer(), pos_integer()}) :: Cauldron3D.View.t()
    def view(%Camera{} = camera, {width, height}) do
      half_height = :math.tan(camera.fov_y / 2)
      aspect = camera.aspect || width / height
      scale_y = height / 2 / half_height

      %Cauldron3D.View{
        camera: %Cauldron3D.Camera{position: camera.position, near: camera.near},
        width: width,
        height: height,
        origin: camera.position,
        forward: Quat.rotate(camera.rotation, {0.0, 0.0, -1.0}),
        right: Quat.rotate(camera.rotation, {1.0, 0.0, 0.0}),
        up: Quat.rotate(camera.rotation, {0.0, 1.0, 0.0}),
        center_x: width / 2,
        center_y: height / 2,
        scale_x: width / 2 / (half_height * aspect),
        scale_y: scale_y,
        near: camera.near,
        perspective?: true
      }
    end

    defp job({_id, %Instance{hidden: true}}, _record, _resources), do: []

    defp job({id, %Instance{mesh: %{id: mesh_id}} = instance}, record, resources) do
      case Map.fetch(resources.meshes, mesh_id) do
        {:ok, mesh} ->
          pose = Map.get(record.poses, id)

          parts =
            mesh.parts
            |> Enum.with_index()
            |> Enum.map(fn {triangles, part} ->
              material = material(instance, part, resources)
              {triangles, material, texture(material.base_texture, resources)}
            end)

          [
            %{
              instance: instance,
              mesh: mesh,
              pose: pose,
              blend: blend_mesh(pose, resources),
              parts: parts
            }
          ]

        :error ->
          []
      end
    end

    defp job(_entry, _record, _resources), do: []

    defp blend_mesh(%{blend_to: %{id: id}}, resources), do: Map.take(resources.meshes, [id])
    defp blend_mesh(_pose, _resources), do: %{}

    defp job_polygons(job, lights, {environment, eye}) do
      world = Posing.world(job.mesh, job.pose, job.instance.transform || %Transform{}, job.blend)
      posed = %{world: world, lit: lit(world, lights, environment), colors: job.mesh.colors}

      Enum.flat_map(job.parts, fn {triangles, material, texture} ->
        part_polygons(triangles, posed, {material, texture}, job.instance, {environment, eye})
      end)
    end

    defp lit(world, lights, environment) do
      world
      |> Tuple.to_list()
      |> Enum.map(fn {position, normal, _uv} ->
        Lighting.light(position, normal, lights, environment)
      end)
      |> List.to_tuple()
    end

    defp tints(triangles, %{lit: lit, colors: colors}, material, environment) do
      for {a, b, c} <- triangles, index <- [a, b, c], uniq: true, into: %{} do
        {index,
         Lighting.tint(material, elem(lit, index), colors && elem(colors, index), environment)}
      end
    end

    defp material(%Instance{materials: materials}, part, resources) do
      case Enum.at(materials, part) || List.last(materials) do
        %{id: id} -> Map.get(resources.materials, id, @blank_material)
        nil -> @blank_material
      end
    end

    defp part_polygons(_triangles, _posed, {%Material{sky: true}, _texture}, _instance, _scene),
      do: []

    defp part_polygons(triangles, posed, {material, texture}, instance, {environment, eye}) do
      paint = if texture, do: {:texture, texture, nil}, else: {:flat, {255, 255, 255}}
      template = struct!(Cauldron3D.Polygon, [paint: paint] ++ style(material, instance))
      tints = tints(triangles, posed, material, environment)
      world = posed.world
      {width, height} = if texture, do: {texture.width, texture.height}, else: {0, 0}

      for {a, b, c} <- triangles,
          {pa, _, {ua, va}} = elem(world, a),
          {pb, _, {ub, vb}} = elem(world, b),
          {pc, _, {uc, vc}} = elem(world, c),
          material.double_sided or facing?(pa, pb, pc, eye) do
        %{
          template
          | points: [pa, pb, pc],
            uvs: [{ua * width, va * height}, {ub * width, vb * height}, {uc * width, vc * height}],
            tints: [Map.fetch!(tints, a), Map.fetch!(tints, b), Map.fetch!(tints, c)]
        }
      end
    end

    defp facing?({ax, ay, az}, {bx, by, bz}, {cx, cy, cz}, {ex, ey, ez}) do
      {ux, uy, uz} = {bx - ax, by - ay, bz - az}
      {vx, vy, vz} = {cx - ax, cy - ay, cz - az}
      {nx, ny, nz} = {uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx}
      nx * (ex - ax) + ny * (ey - ay) + nz * (ez - az) > 0
    end

    defp style(material, instance) do
      [
        cull: if(material.double_sided, do: :none, else: :clockwise),
        blend: blend(material.alpha_mode),
        alpha_test: if(material.alpha_cutoff > 0, do: material.alpha_cutoff),
        depth: depth(instance)
      ]
    end

    defp blend(:blend), do: {:alpha, 1.0}
    defp blend(:add), do: {:add, 1.0}
    defp blend(:multiply), do: {:alpha, 1.0}
    defp blend(_opaque), do: :none

    defp depth(%Instance{depth_test: false}), do: :always
    defp depth(%Instance{in_front: true}), do: :near_third
    defp depth(_instance), do: :test

    defp texture(%{id: id}, resources), do: Map.get(resources.textures, id)
    defp texture(nil, _resources), do: nil

    defp tint_polygons({:screen_tint, {_r, _g, _b, alpha}}, _view) when alpha <= 0, do: []

    defp tint_polygons({:screen_tint, {r, g, b, alpha}}, view) do
      colour = {round(min(r, 1.0) * 255), round(min(g, 1.0) * 255), round(min(b, 1.0) * 255)}
      [screen_polygon(view, paint: {:flat, colour}, uvs: nil, blend: {:alpha, min(alpha, 1.0)})]
    end

    defp tint_polygons(_none, _view), do: []

    defp overlay_polygons({:overlay, %{id: id}}, view, resources),
      do: overlay_polygon(Map.get(resources.textures, id), view, {:alpha, 1.0})

    defp overlay_polygons({:overlay, %{id: id}, :premultiplied}, view, resources),
      do: overlay_polygon(Map.get(resources.textures, id), view, {:premultiplied, 1.0})

    defp overlay_polygons(_none, _view, _resources), do: []

    defp overlay_polygon(nil, _view, _blend), do: []

    defp overlay_polygon(texture, view, blend) do
      corners = [
        {0.0, 0.0},
        {texture.width / 1, 0.0},
        {texture.width / 1, texture.height / 1},
        {0.0, texture.height / 1}
      ]

      [screen_polygon(view, paint: {:texture, texture, nil}, uvs: corners, blend: blend)]
    end

    defp screen_polygon(view, fields) do
      distance = view.near * 2
      corners = [{0, 0}, {view.width, 0}, {view.width, view.height}, {0, view.height}]

      points =
        for {x, y} <- corners do
          across = (x - view.center_x) / view.scale_x * distance
          down = (view.center_y - y) / view.scale_y * distance

          view.origin
          |> madd(view.forward, distance)
          |> madd(view.right, across)
          |> madd(view.up, down)
        end

      struct!(Cauldron3D.Polygon, [points: points, depth: :always, cull: :none] ++ fields)
    end

    defp sky(%Environment{} = environment, {width, height}) do
      half = max(div(height, 2), 1)

      rows =
        for y <- 0..(height - 1)//1 do
          colour =
            if y < half,
              do: mix(environment.sky_top, environment.sky_horizon, y / half),
              else:
                mix(
                  environment.sky_horizon,
                  environment.sky_ground,
                  (y - half) / max(height - half, 1)
                )

          :binary.copy(pixel(Display.shown(colour, environment)), width)
        end

      %Cauldron3D.Frame{
        width: width,
        height: height,
        pixels: IO.iodata_to_binary(rows),
        format: :rgba
      }
    end

    defp mix({ar, ag, ab}, {br, bg, bb}, t),
      do: {ar + (br - ar) * t, ag + (bg - ag) * t, ab + (bb - ab) * t}

    defp pixel({r, g, b}), do: <<round(r * 255), round(g * 255), round(b * 255), 255>>

    defp madd({ax, ay, az}, {bx, by, bz}, scale),
      do: {ax + bx * scale, ay + by * scale, az + bz * scale}
  end
end
