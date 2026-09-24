defmodule Cauldron2D.Projection.Volume do
  @moduledoc """
  A coloured region of space that tints whatever is seen through it, and the arithmetic
  a projection draws one with.

      volume = Cauldron2D.Projection.Volume.new(
        at: {8.5, 6.5},
        shape: {:sphere, 1.5, 0.0},
        colour: {120, 232, 96},
        strength: 0.6
      )

  `:at` is where the volume stands on the ground and `:shape` what it fills from there,
  as `Cauldron2D.Projection.Volume.Shapes` lists the shapes the engine knows, or
  `{YourModule, data}` for a shape of your own implementing
  `Cauldron2D.Projection.Volume.Shape`. Distances are in tiles. Nothing below the ground
  is drawn, whatever the shape says.

  `:strength` is how much of the colour a viewer sees through the thickest part of the
  shape, `0.0` to `1.0`. `:falloff` decides what a thinner crossing looks like:

    * `:depth` — the colour builds up along the ray, so the volume reads as something
      you look *through*: thin at the edges, full in the middle. The default
    * `:flat` — anything the ray touches at all is tinted by the full strength, which is
      how an area marked out in whole squares reads
    * `:shell` — strongest where the ray only grazes the shape, so the surface glows and
      the middle stays clear

  A volume is never fully opaque.

  A volume either stands where it was made or follows something that moves. `:follows`
  names what it keeps up with — a term of the caller's choosing, a character, a thrown
  light, itself — and `anchored/2` moves every such volume to where its subject is now,
  turning a cone or a beam to face the way the subject faces and dropping a volume whose
  subject is gone. A volume with no `:follows` is left where it stands. Which effects
  follow what, and what may be followed at all, is the game's business; all this knows
  is that a subject has a place and may have a heading.

  `through/4` measures a ray against a volume and `mix/3` blends that much colour into a
  pixel; the two together tint one pixel:

      Volume.mix(pixel, volume, Volume.through(volume, eye, ray, distance_to_surface))

  A ray is a point and a direction of three numbers, `z` running up from the ground, and
  how far along it the projection can see, or `:infinity` where nothing stops it. That
  limit counts steps of the direction as it is given, so a projection may measure it
  however suits it; the length `through/4` answers is always in the units the volume
  itself is measured in, whatever size the direction is.

  `eyeline/3` gives the direction the rays of an axonometric projection all run in,
  `box/2` the rectangle of a picture a volume can reach and `reach/1` how far from `at`
  it spreads across the ground.

  `paint/4` tints a `Cauldron2D.Projection.Canvas` over a rectangle. It takes a plan
  rather than a ray per pixel, because a projection's rays change by the same step from
  one pixel to the next: `ground_plan/2` describes a projection whose rays start on the
  ground and run parallel, `eye_plan/3` one whose rays start at the eye and fan out.

  Painting is done by `Cauldron2D.Projection.Volume.Native` where it built, and in
  Elixir where it did not or where the shape is a module of the caller's own. A plan
  carrying `native: false` paints in Elixir wherever it is, which is how the two are
  checked against each other; they agree to within one level of one channel, where
  `:math.exp/1` and C's `exp` round differently.
  """

  alias Cauldron2D.Projection.Canvas
  alias Cauldron2D.Projection.Volume.{Native, Shapes}

  @type point :: {number(), number(), number()}
  @type plan :: %{
          required(:origin) => point(),
          required(:origin_x) => point(),
          required(:origin_y) => point(),
          required(:direction) => point(),
          required(:direction_x) => point(),
          required(:direction_y) => point(),
          required(:limits) => binary() | nil,
          optional(:native) => boolean()
        }
  @type shape :: tuple()
  @type falloff :: :depth | :flat | :shell
  @type t :: %{
          at: {number(), number()},
          shape: {module(), term()},
          colour: {byte(), byte(), byte()},
          strength: float(),
          falloff: falloff(),
          thickness: float(),
          density: float()
        }

  @default_colour {255, 255, 255}
  @default_shape {:sphere, 1.0, 0.0}
  @default_strength 0.5
  @clearest 0.99
  @still {0.0, 0.0, 0.0}

  @doc """
  A volume from its fields, a map or a keyword list, with `:at` required.

  `:shape` defaults to a dome of one tile, `:colour` to white, `:strength` to
  `#{@default_strength}` and `:falloff` to `:depth`. Passing a volume back in leaves it
  as it is, so a projection may normalise whatever it is handed.
  """
  @spec new(keyword() | map()) :: t()
  def new(fields) do
    fields = Map.new(fields)
    {module, data} = shape = shaped(Map.get(fields, :shape, @default_shape))
    strength = fields |> Map.get(:strength, @default_strength) |> min(@clearest) |> max(0.0)
    thickness = data |> module.thickness() |> max(1.0e-6)

    %{
      at: Map.fetch!(fields, :at),
      shape: shape,
      colour: Map.get(fields, :colour, @default_colour),
      strength: strength / 1,
      falloff: Map.get(fields, :falloff, :depth),
      thickness: thickness,
      density: -:math.log(1 - strength) / thickness
    }
    |> keeping(fields, :follows)
  end

  defp keeping(volume, fields, key) do
    case Map.fetch(fields, key) do
      {:ok, value} -> Map.put(volume, key, value)
      :error -> volume
    end
  end

  @built_in Shapes.kinds()

  defp shaped(shape) when is_tuple(shape) and elem(shape, 0) in @built_in, do: {Shapes, shape}
  defp shaped({module, data}) when is_atom(module), do: {module, data}

  @doc """
  Every volume moved to where the thing it follows is now.

  `subjects` maps what a volume's `:follows` names to where that subject is: a point, or
  `{point, heading}` where the subject faces somewhere and the volume's shape should turn
  with it. A volume with no `:follows` is returned untouched; one whose subject is absent
  from `subjects` is dropped, so an effect outlives nothing it was tied to.
  """
  @spec anchored([map()], %{term() => {number(), number()} | {{number(), number()}, number()}}) ::
          [map()]
  def anchored(volumes, subjects) do
    Enum.flat_map(volumes, &following(&1, subjects))
  end

  defp following(volume, subjects) do
    volume = Map.new(volume)

    case Map.fetch(volume, :follows) do
      :error -> [volume]
      {:ok, subject} -> moved(volume, Map.get(subjects, subject))
    end
  end

  defp moved(_volume, nil), do: []

  defp moved(volume, {{_x, _y} = at, heading}),
    do: [volume |> Map.put(:at, at) |> Map.update!(:shape, &turned(&1, heading))]

  defp moved(volume, {_x, _y} = at), do: [Map.put(volume, :at, at)]

  defp turned({:cone, length, spread, _was, height}, heading),
    do: {:cone, length, spread, heading, height}

  defp turned({:beam, length, width, _was, height}, heading),
    do: {:beam, length, width, heading, height}

  defp turned(shape, _heading), do: shape

  @doc "Every volume of a list, as `new/1` builds one."
  @spec list([keyword() | map()]) :: [t()]
  def list(volumes), do: Enum.map(volumes, &new/1)

  @doc """
  How far a ray travels inside `volume` before `limit`, in the units the volume is
  measured in.

  The ray starts at `origin` and runs along `direction`, and `limit` is how many steps
  of that direction it may take, so a projection whose step is a unit of depth rather
  than a unit of distance passes its own depth. Only what lies above the ground, ahead
  of the origin and nearer than `limit` counts; `:infinity` lets the ray run until it
  leaves the shape.
  """
  @spec through(t(), point(), point(), number() | :infinity) :: float()
  def through(%{at: {cx, cy}, shape: {module, data}}, {ox, oy, oz}, direction, limit) do
    {dx, dy, dz} = direction
    local = {ox - cx, oy - cy, oz}

    steps =
      data
      |> module.span(local, direction)
      |> Enum.reduce(0.0, fn interval, total -> total + inside(interval, {oz, dz}, limit) end)

    steps * :math.sqrt(dx * dx + dy * dy + dz * dz)
  end

  defp inside(interval, ground, limit) do
    case above_ground(interval, ground) do
      nil -> 0.0
      {from, to} -> max(capped(to, limit) - max(from, 0.0), 0.0)
    end
  end

  defp capped(to, :infinity), do: to
  defp capped(to, limit), do: min(to, limit)

  defp above_ground({from, to}, {oz, dz}) when dz > 0, do: {max(from, -oz / dz), to}
  defp above_ground({from, to}, {oz, dz}) when dz < 0, do: {from, min(to, -oz / dz)}
  defp above_ground(interval, {oz, _dz}) when oz >= 0, do: interval
  defp above_ground(_interval, _ground), do: nil

  @doc """
  `pixel` with as much of the volume's colour blended in as `length` inside it calls for,
  by its falloff.

  A length of nothing leaves the pixel untouched. The pixel's own opacity byte is kept.
  """
  @spec mix(binary(), t(), number()) :: binary()
  def mix(pixel, _volume, length) when length <= 0, do: pixel

  def mix(<<red, green, blue, alpha>>, %{colour: {cr, cg, cb}} = volume, length) do
    weight = weight(volume, length)

    <<blend(red, cr, weight), blend(green, cg, weight), blend(blue, cb, weight), alpha>>
  end

  defp weight(%{falloff: :flat, strength: strength}, _length), do: strength

  defp weight(%{falloff: :shell, strength: strength, thickness: thickness}, length),
    do: strength * max(0.0, 1 - length / thickness)

  defp weight(%{density: density}, length), do: 1 - :math.exp(-density * length)

  defp blend(from, to, weight), do: (from + (to - from) * weight) |> round() |> min(255) |> max(0)

  @doc """
  The direction, towards the viewer, that every ray of an axonometric projection runs
  in.

  `across` and `down` are the picture vectors a step of one along the world's `x` and
  `y` moves by, and `lift` how many pixels up the picture a step of one in `z` moves.
  The three must not be flat against one another.
  """
  @spec eyeline({number(), number()}, {number(), number()}, number()) :: point()
  def eyeline({ax, ay}, {bx, by}, lift), do: towards({bx, -ax, (bx * ay - ax * by) / lift})

  defp towards({dx, dy, dz}) when dz < 0, do: {-dx, -dy, -dz}
  defp towards(direction), do: direction

  @doc "The world points of the box the volume fits in, above the ground."
  @spec corners(t()) :: [point()]
  def corners(%{at: {cx, cy}, shape: {module, data}}) do
    {{low_x, low_y, low_z}, {high_x, high_y, high_z}} = module.bounds(data)

    for x <- [cx + low_x, cx + high_x],
        y <- [cy + low_y, cy + high_y],
        z <- [max(low_z, 0.0), max(high_z, 0.0)],
        do: {x, y, z}
  end

  @doc "How far from `at` the volume can spread across the ground."
  @spec reach(t()) :: float()
  def reach(%{shape: {module, data}}) do
    {{low_x, low_y, _low_z}, {high_x, high_y, _high_z}} = module.bounds(data)

    :math.sqrt(max(low_x * low_x, high_x * high_x) + max(low_y * low_y, high_y * high_y))
  end

  @doc """
  The whole-pixel rectangle `{left, top, right, bottom}` of a picture the volume can
  reach, or `nil` when none of it is in view.

  `project` maps a world point to its place in the picture, or to `nil` for a point the
  projection cannot show.
  """
  @spec box(t(), (point() -> {number(), number()} | nil)) ::
          {integer(), integer(), integer(), integer()} | nil
  def box(volume, project) do
    volume
    |> corners()
    |> Enum.map(project)
    |> Enum.reject(&is_nil/1)
    |> rectangle()
  end

  defp rectangle([]), do: nil

  defp rectangle(corners) do
    xs = Enum.map(corners, &elem(&1, 0))
    ys = Enum.map(corners, &elem(&1, 1))

    {floor(Enum.min(xs)), floor(Enum.min(ys)), ceil(Enum.max(xs)), ceil(Enum.max(ys))}
  end

  @doc """
  A plan for a projection whose rays start on the ground and all run the same way.

  `at` answers the world point on the ground under a picture pixel, as a projection's
  own `unproject` does, and `direction` is the way the rays run, as `eyeline/3` gives
  it.
  """
  @spec ground_plan(({number(), number()} -> {number(), number()}), point()) :: plan()
  def ground_plan(at, direction) do
    {x, y} = at.({0.5, 0.5})
    {across_x, across_y} = at.({1.5, 0.5})
    {down_x, down_y} = at.({0.5, 1.5})

    %{
      origin: {x, y, 0.0},
      origin_x: {across_x - x, across_y - y, 0.0},
      origin_y: {down_x - x, down_y - y, 0.0},
      direction: direction,
      direction_x: @still,
      direction_y: @still,
      limits: nil
    }
  end

  @doc """
  A plan for a projection whose rays all start at the eye and fan out.

  `along` answers the direction a picture pixel looks in, scaled so that one step along
  it is one unit of depth, which is what `limits` counts. `limits` is one native float per picture pixel, how far that
  pixel sees before something opaque stops it, or `nil` for nothing in the way.
  """
  @spec eye_plan(point(), ({number(), number()} -> point()), binary() | nil) :: plan()
  def eye_plan(from, along, limits \\ nil) do
    straight = along.({0.5, 0.5})

    %{
      origin: from,
      origin_x: @still,
      origin_y: @still,
      direction: straight,
      direction_x: difference(along.({1.5, 0.5}), straight),
      direction_y: difference(along.({0.5, 1.5}), straight),
      limits: limits
    }
  end

  defp difference({ax, ay, az}, {bx, by, bz}), do: {ax - bx, ay - by, az - bz}

  @doc """
  Tint `canvas` with `volume` over `box`, clipped to the canvas, looking along `plan`.
  """
  @spec paint(
          Canvas.t(),
          t(),
          {integer(), integer(), integer(), integer()} | nil,
          plan()
        ) :: Canvas.t()
  def paint(canvas, _volume, nil, _plan), do: canvas

  def paint(canvas, volume, {left, top, right, bottom}, plan) do
    left = max(left, 0)
    top = max(top, 0)
    right = min(right, canvas.width - 1)
    bottom = min(bottom, canvas.height - 1)

    if right < left or bottom < top do
      canvas
    else
      tinted(canvas, volume, {left, top, right - left + 1, bottom - top + 1}, plan)
    end
  end

  defp tinted(canvas, volume, region, plan) do
    with true <- Map.get(plan, :native, true),
         true <- Native.available?(),
         encoded when encoded != nil <- encoded(volume) do
      in_c(canvas, encoded, region, plan)
    else
      _elsewhere -> in_elixir(canvas, volume, region, plan)
    end
  end

  defp in_c(canvas, encoded, {left, top, width, height} = region, plan) do
    canvas
    |> pixels(region)
    |> Native.tint(width, height, rebased(plan, left, top), limits(plan, canvas, region), encoded)
    |> spliced(canvas, region)
  end

  defp pixels(canvas, {left, top, width, height}) do
    for y <- top..(top + height - 1)//1,
        into: <<>>,
        do: binary_part(Map.fetch!(canvas.rows, y), left * 4, width * 4)
  end

  defp limits(%{limits: nil}, _canvas, _region), do: <<>>

  defp limits(%{limits: held}, canvas, {left, top, width, height}) do
    for y <- top..(top + height - 1)//1,
        into: <<>>,
        do: binary_part(held, (y * canvas.width + left) * 4, width * 4)
  end

  defp rebased(plan, left, top) do
    {
      at(plan.origin, plan.origin_x, plan.origin_y, left, top),
      plan.origin_x,
      plan.origin_y,
      at(plan.direction, plan.direction_x, plan.direction_y, left, top),
      plan.direction_x,
      plan.direction_y
    }
  end

  defp at({x, y, z}, {ax, ay, az}, {bx, by, bz}, across, down),
    do: {x + ax * across + bx * down, y + ay * across + by * down, z + az * across + bz * down}

  defp spliced(tinted, canvas, {left, top, width, height}) do
    rows =
      Enum.reduce(0..(height - 1)//1, canvas.rows, fn index, acc ->
        segment = binary_part(tinted, index * width * 4, width * 4)
        Map.update!(acc, top + index, &splice(&1, left, segment, canvas.width))
      end)

    %{canvas | rows: rows}
  end

  defp splice(row, left, segment, width) do
    after_segment = (left + div(byte_size(segment), 4)) * 4

    <<binary_part(row, 0, left * 4)::binary, segment::binary,
      binary_part(row, after_segment, width * 4 - after_segment)::binary>>
  end

  defp in_elixir(canvas, volume, {left, top, width, height}, plan) do
    rows =
      Enum.reduce(0..(height - 1)//1, canvas.rows, fn index, acc ->
        row = top + index
        Map.update!(acc, row, &drawn(&1, volume, plan, {left, width, row, canvas.width}))
      end)

    %{canvas | rows: rows}
  end

  defp drawn(row, volume, plan, {left, width, down, stride}) do
    middle =
      for across <- left..(left + width - 1)//1, into: <<>> do
        origin = at(plan.origin, plan.origin_x, plan.origin_y, across, down)
        direction = at(plan.direction, plan.direction_x, plan.direction_y, across, down)
        length = through(volume, origin, direction, reach(plan, down * stride + across))

        mix(binary_part(row, across * 4, 4), volume, length)
      end

    splice(row, left, middle, stride)
  end

  defp reach(%{limits: nil}, _index), do: :infinity

  defp reach(%{limits: held}, index) do
    <<limit::float-native-32>> = binary_part(held, index * 4, 4)
    limit
  end

  @kinds %{sphere: 0, cylinder: 1, cone: 2, beam: 3, cells: 4}
  @falloffs %{depth: 0, flat: 1, shell: 2}

  defp encoded(%{shape: {Shapes, data}} = volume) do
    case numbers(data) do
      nil ->
        nil

      {kind, params, cells} ->
        {Map.fetch!(@kinds, kind), Map.fetch!(@falloffs, volume.falloff), volume.at,
         volume.colour, {volume.strength, volume.density, volume.thickness}, params, cells}
    end
  end

  defp encoded(_volume), do: nil

  defp numbers({:sphere, radius, height}), do: {:sphere, doubles([radius, height]), nil}
  defp numbers({:cylinder, radius, height}), do: {:cylinder, doubles([radius, height]), nil}

  defp numbers({:cone, length, spread, heading, height}),
    do: {:cone, doubles([length, spread, heading, height]), nil}

  defp numbers({:beam, length, width, heading, height}),
    do: {:beam, doubles([length, width, heading, height]), nil}

  defp numbers({:cells, tiles, height}), do: {:cells, doubles([height]), bitmap(tiles)}
  defp numbers(_other), do: nil

  defp doubles(values), do: for(value <- values, into: <<>>, do: <<value / 1::float-native-64>>)

  defp bitmap(tiles) do
    case Enum.to_list(tiles) do
      [] -> {0, 0, 1, 1, <<0>>}
      list -> packed(tiles, list)
    end
  end

  defp packed(tiles, list) do
    xs = Enum.map(list, &elem(&1, 0))
    ys = Enum.map(list, &elem(&1, 1))
    left = Enum.min(xs)
    top = Enum.min(ys)
    width = Enum.max(xs) - left + 1
    height = Enum.max(ys) - top + 1

    bits =
      for y <- top..(top + height - 1)//1,
          x <- left..(left + width - 1)//1,
          into: <<>>,
          do: bit(tiles, {x, y})

    {left, top, width, height, bits}
  end

  defp bit(tiles, tile), do: if(MapSet.member?(tiles, tile), do: <<1>>, else: <<0>>)
end
