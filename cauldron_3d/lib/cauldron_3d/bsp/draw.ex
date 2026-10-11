defmodule Cauldron3D.Bsp.Draw do
  @moduledoc """
  The faces of a BSP world a view can see, as polygons for `Cauldron3D.Render`.

      polygons = Cauldron3D.Bsp.Draw.polygons(bsp, view, surfaces: cache, light: light)

  The world's faces come from the leaves the camera's leaf can see, its brush models'
  faces from where each model stands; faces turned away from the camera are left out.
  Solid faces are painted with their lit surfaces (`Cauldron3D.Bsp.Surfaces`) at a mip
  level chosen by distance, liquid faces ripple (`{:warp, ...}`), sky faces show the
  texture's `:layers` (`{:sky, ...}`), and hidden faces are not drawn.

  ## Options

    * `:surfaces` — the surface cache (required where there are solid faces)
    * `:light` — the light map `Cauldron3D.Bsp.Surfaces` takes (required likewise)
    * `:models` — brush models to draw besides the world, each `{model, origin}`,
      `{model, origin, {pitch, yaw, roll}}` (degrees, turned as `Cauldron3D.Camera`
      turns, yaw about `z` first) or a map (see below)
    * `:time` — seconds, for liquid and sky movement, default 0.0
    * `:liquid` — options added to every `{:warp, ...}` paint, or a function of the
      liquid's texture giving them
    * `:sky` — options added to every `{:sky, ...}` paint
    * `:skybox` — six faces for `{:skybox, ...}` (see `Cauldron3D.Paint.Rgba`), drawn on
      sky faces instead of the texture's layers
    * `:mip_bias` — multiplies the distance a mip level is chosen at, default 1.0
    * `:world?` — whether to draw the world's own faces, default true
    * `:rtlights` — lights added over the solid and masked faces of the world and of
      unblended brush models (see `Cauldron3D.Paint.Rgba`'s `{:lit, ...}`), each face
      lit by those whose sphere reaches its plane and its box

  A brush model given as a map has `:model` and `:origin`, and may have:

    * `:axes` — `{forward, left, up}`, where the model's own x, y and z axes point;
      default the world's
    * `:scale` — how many times its own size it is drawn, default 1.0
    * `:tint` — `{r, g, b, a}` its faces' colours and alpha are multiplied by
    * `:blend`, `:depth` — as `Cauldron3D.Polygon`'s, for every face
    * `:alpha_test` — given to its faces of kind `:masked`
    * `:light` — the light map its surfaces are made with instead of `:light`
  """

  alias Cauldron3D.{Bsp, Polygon, Vec, View}
  alias Cauldron3D.Bsp.{Face, Surfaces}

  @doc "The polygons of the world and its brush models that `view` can see."
  @spec polygons(Bsp.t(), View.t(), keyword()) :: [Polygon.t()]
  def polygons(%Bsp{} = bsp, %View{} = view, opts \\ []) do
    world_place = place_of(%{model: 0, origin: Vec.zero()}, opts)

    world =
      if Keyword.get(opts, :world?, true),
        do: bsp |> world_faces(view.origin) |> Enum.map(&{&1, world_place}),
        else: []

    models =
      for placed <- Keyword.get(opts, :models, []),
          place = placement(placed, opts),
          index <- model_faces(bsp, place.model),
          do: {index, place}

    seen =
      Enum.filter(world ++ models, fn {index, place} ->
        facing?(bsp, elem(bsp.faces, index), local(place, view.origin))
      end)

    made = surfaces(bsp, view, seen, opts)

    Enum.flat_map(seen, fn {index, place} ->
      List.wrap(polygon(bsp, view, {index, place}, made, opts))
    end)
  end

  defp placement({model, origin}, opts), do: place_of(%{model: model, origin: origin}, opts)

  defp placement({model, origin, {pitch, yaw, roll}}, opts) do
    {forward, right, up} =
      Cauldron3D.Camera.basis(%Cauldron3D.Camera{
        yaw: yaw * :math.pi() / 180,
        pitch: pitch * :math.pi() / 180,
        roll: roll * :math.pi() / 180
      })

    place_of(%{model: model, origin: origin, axes: {forward, Vec.scale(right, -1.0), up}}, opts)
  end

  defp placement(%{} = placed, opts), do: place_of(placed, opts)

  defp place_of(placed, opts) do
    %{
      model: placed.model,
      origin: Vec.float(placed.origin),
      axes: Map.get(placed, :axes),
      scale: Map.get(placed, :scale, 1.0) / 1,
      tint: Map.get(placed, :tint),
      blend: Map.get(placed, :blend, :none),
      depth: Map.get(placed, :depth, :test),
      alpha_test: Map.get(placed, :alpha_test),
      light: Map.get(placed, :light) || Keyword.get(opts, :light)
    }
  end

  defp local(%{axes: nil, origin: origin, scale: scale}, point),
    do: Vec.scale(Vec.sub(point, origin), 1 / scale)

  defp local(%{axes: {x_axis, y_axis, z_axis}, origin: origin, scale: scale}, point) do
    offset = Vec.sub(point, origin)

    {Vec.dot(offset, x_axis) / scale, Vec.dot(offset, y_axis) / scale,
     Vec.dot(offset, z_axis) / scale}
  end

  defp place(%{axes: nil, origin: origin, scale: scale}, point),
    do: Vec.add(Vec.scale(point, scale), origin)

  defp place(%{axes: {x_axis, y_axis, z_axis}, origin: origin, scale: scale}, {x, y, z}),
    do:
      origin
      |> Vec.madd(x_axis, x * scale)
      |> Vec.madd(y_axis, y * scale)
      |> Vec.madd(z_axis, z * scale)

  defp surfaces(bsp, view, seen, opts) do
    case Keyword.get(opts, :surfaces) do
      nil ->
        %{}

      cache ->
        bias = Keyword.get(opts, :mip_bias, 1.0)

        seen
        |> Enum.filter(fn {index, place} -> place.light != nil and solid?(bsp, index) end)
        |> Enum.map(fn {index, place} ->
          {index, mip(view, elem(bsp.faces, index), place, bias), place.light}
        end)
        |> Enum.uniq_by(fn {index, mip, _light} -> {index, mip} end)
        |> Enum.map(fn {index, mip, light} -> Surfaces.cached(cache, bsp, index, mip, light) end)
        |> Enum.split_with(&match?({:ok, _key, _surface}, &1))
        |> then(fn {found, missing} ->
          Map.new(found, &found/1) |> Map.merge(made(cache, missing))
        end)
    end
  end

  defp solid?(bsp, index),
    do: elem(bsp.textures, elem(bsp.faces, index).texture).kind in [:solid, :masked]

  defp found({:ok, key, surface}), do: {key, surface}

  defp made(cache, missing) do
    missing
    |> Task.async_stream(fn {:missing, job} -> {job.key, Surfaces.make(cache, job)} end,
      timeout: :infinity,
      ordered: false
    )
    |> Map.new(fn {:ok, made} -> made end)
  end

  @doc "The world faces seen from `point`: those of every leaf its leaf can see, each once."
  @spec world_faces(Bsp.t(), Vec.t()) :: [non_neg_integer()]
  def world_faces(%Bsp{} = bsp, point) do
    leaf = Bsp.leaf_at(bsp, point)

    bsp
    |> Bsp.visible_leaves(leaf)
    |> Enum.flat_map(&elem(bsp.leaves, &1).faces)
    |> Enum.uniq()
  end

  @doc "The face indices of brush model `model`."
  @spec model_faces(Bsp.t(), non_neg_integer()) :: [non_neg_integer()]
  def model_faces(%Bsp{} = bsp, model) do
    %{first_face: first, face_count: count} = elem(bsp.models, model)
    if count > 0, do: Enum.to_list(first..(first + count - 1)), else: []
  end

  defp facing?(bsp, %Face{} = face, eye) do
    {normal, distance} = Bsp.plane(bsp, face.plane)
    side = Vec.dot(eye, normal) - distance
    if face.back?, do: side < 0, else: side > 0
  end

  defp polygon(bsp, view, {index, place}, made, opts) do
    face = elem(bsp.faces, index)
    texture = elem(bsp.textures, face.texture)
    points = Enum.map(face.points, &place(place, &1))

    case paint(texture.kind, bsp, view, {index, face, texture, points, place}, made, opts) do
      nil ->
        nil

      polygon ->
        polygon |> dress(texture.kind, place) |> lit(bsp, view, face, texture, place, opts)
    end
  end

  defp lit(
         %Polygon{paint: {:surface, _} = paint} = polygon,
         bsp,
         view,
         face,
         texture,
         %{blend: :none} = place,
         opts
       ) do
    {normal, distance} = Bsp.plane(bsp, face.plane)
    normal = if face.back?, do: Vec.scale(normal, -1.0), else: normal
    distance = if face.back?, do: -distance, else: distance
    normal = turn(place, normal)
    reference = place(place, Vec.scale(normal_local(bsp, face), distance))
    {mins, maxs} = box(polygon.points)

    case Enum.filter(
           Keyword.get(opts, :rtlights, []),
           &reaches?(&1, normal, reference, mins, maxs)
         ) do
      [] ->
        polygon

      lights ->
        mip = mip(view, face, place, Keyword.get(opts, :mip_bias, 1.0))
        {s_min, t_min} = face.mins

        lighting = %{
          lights: lights,
          normal: normal,
          texture: Enum.at(texture.mips, mip),
          offset: {Bitwise.bsr(s_min, mip), Bitwise.bsr(t_min, mip)},
          clear: if(texture.kind == :masked, do: 255)
        }

        %{polygon | paint: {:lit, paint, lighting}}
    end
  end

  defp lit(polygon, _bsp, _view, _face, _texture, _place, _opts), do: polygon

  defp normal_local(bsp, face) do
    {normal, _distance} = Bsp.plane(bsp, face.plane)
    if face.back?, do: Vec.scale(normal, -1.0), else: normal
  end

  defp turn(%{axes: nil}, vector), do: vector

  defp turn(%{axes: {x_axis, y_axis, z_axis}}, {x, y, z}),
    do: Vec.scale(x_axis, x) |> Vec.madd(y_axis, y) |> Vec.madd(z_axis, z)

  defp box([first | rest]) do
    Enum.reduce(rest, {first, first}, fn {x, y, z}, {{ax, ay, az}, {bx, by, bz}} ->
      {{min(ax, x), min(ay, y), min(az, z)}, {max(bx, x), max(by, y), max(bz, z)}}
    end)
  end

  defp reaches?(%{origin: origin, radius: radius}, normal, reference, mins, maxs) do
    {ox, oy, oz} = origin
    {x0, y0, z0} = mins
    {x1, y1, z1} = maxs

    abs(Vec.dot(Vec.sub(origin, reference), normal)) < radius and ox + radius > x0 and
      ox - radius < x1 and oy + radius > y0 and oy - radius < y1 and oz + radius > z0 and
      oz - radius < z1
  end

  defp dress(polygon, kind, place) do
    tints = if place.tint, do: List.duplicate(place.tint, length(polygon.points))

    %{
      polygon
      | tints: tints,
        blend: place.blend,
        depth: place.depth,
        alpha_test: if(kind == :masked, do: place.alpha_test)
    }
  end

  defp paint(:hidden, _bsp, _view, _face, _made, _opts), do: nil

  defp paint(:sky, _bsp, _view, {_index, _face, texture, points, _place}, _made, opts) do
    case Keyword.get(opts, :skybox) do
      nil ->
        sky_opts = [time: Keyword.get(opts, :time, 0.0)] ++ Keyword.get(opts, :sky, [])
        %Polygon{points: points, paint: {:sky, Map.fetch!(texture, :layers), sky_opts}}

      faces ->
        %Polygon{points: points, paint: {:skybox, faces}}
    end
  end

  defp paint(:liquid, _bsp, _view, {_index, face, texture, points, _place}, _made, opts) do
    uvs = Enum.map(face.points, &Face.st(face, &1))
    mip = hd(texture.mips)
    warp = [time: Keyword.get(opts, :time, 0.0)] ++ liquid(Keyword.get(opts, :liquid, []), mip)
    %Polygon{points: points, uvs: uvs, paint: {:warp, mip, warp}}
  end

  defp paint(:masked, bsp, view, face, made, opts), do: paint(:solid, bsp, view, face, made, opts)

  defp paint(:solid, bsp, view, {index, face, _texture, points, place}, made, opts) do
    mip = mip(view, face, place, Keyword.get(opts, :mip_bias, 1.0))

    surface =
      Map.get(made, {index, mip}) ||
        Surfaces.fetch(Keyword.fetch!(opts, :surfaces), bsp, index, mip, place.light)

    {s_min, t_min} = face.mins
    size = Bitwise.bsl(1, mip)

    uvs =
      Enum.map(face.points, fn point ->
        {s, t} = Face.st(face, point)
        {(s - s_min) / size, (t - t_min) / size}
      end)

    %Polygon{points: points, uvs: uvs, paint: {:surface, surface}}
  end

  defp liquid(fun, texture) when is_function(fun, 1), do: fun.(texture)
  defp liquid(opts, _texture), do: opts

  defp mip(%View{perspective?: false} = view, _face, _place, bias),
    do: level(bias / view.scale_x)

  defp mip(view, face, place, bias) do
    distance = Vec.length(Vec.sub(place(place, Face.centre(face)), view.origin))
    level(distance * bias / view.scale_x)
  end

  defp level(texels_per_pixel) when texels_per_pixel <= 1.0, do: 0

  defp level(texels_per_pixel),
    do: texels_per_pixel |> :math.log2() |> floor() |> max(0) |> min(3)
end
