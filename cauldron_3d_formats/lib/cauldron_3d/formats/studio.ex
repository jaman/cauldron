defmodule Cauldron3D.Formats.Studio do
  @moduledoc """
  A studio model, `.mdl` version 10: bones, bone controllers, hitboxes, sequences with
  their events, attachments, textures with their own palettes, skin families, and body
  parts of skinned triangle meshes, with the compressed animation decoded on demand.

      {:ok, studio} = Cauldron3D.Formats.Studio.parse(bytes)
      studio = Cauldron3D.Formats.Studio.add_textures(studio, File.read!("scientistt.mdl"))
      studio = Cauldron3D.Formats.Studio.add_group(studio, 1, File.read!("scientist01.mdl"))
      locals = Cauldron3D.Formats.Studio.locals(studio, 3, 12.5)
      transforms = Cauldron3D.Skeleton.pose(studio.parents, locals)

  `locals/4` gives each bone's position and rotation relative to its parent for a frame
  of a sequence; `Cauldron3D.Skeleton.pose/3` turns them into transforms, and
  `vertices/3` moves a body part's vertices by them.

  A model whose textures are in a separate `…t.mdl` holds none until `add_textures/2`;
  a sequence in group `n` above 0 has its animation in a `…0n.mdl` file that
  `add_group/3` supplies.
  """

  import Bitwise, only: [band: 2]

  alias Cauldron3D.{Quat, Texture, Vec}

  @enforce_keys [:name, :mins, :maxs, :bones, :parents, :sequences]
  defstruct [
    :name,
    :eye,
    :mins,
    :maxs,
    :box_mins,
    :box_maxs,
    :flags,
    :bones,
    :parents,
    :sequences,
    controllers: [],
    hitboxes: [],
    groups: {},
    textures: {},
    texture_flags: {},
    skins: {},
    body_parts: [],
    attachments: [],
    animation: %{}
  ]

  @type t :: %__MODULE__{}

  @doc "The model in `data`."
  @spec parse(binary()) :: {:ok, t()} | {:error, :not_a_studio_model}
  def parse(<<"IDST", 10::little-32, name::binary-64, _length::little-32, rest::binary>> = data) do
    <<eye::binary-12, mins::binary-12, maxs::binary-12, box_mins::binary-12, box_maxs::binary-12,
      flags::little-32, bone_count::little-32, bone_at::little-32, controller_count::little-32,
      controller_at::little-32, hitbox_count::little-32, hitbox_at::little-32,
      sequence_count::little-32, sequence_at::little-32, group_count::little-32,
      group_at::little-32, texture_count::little-32, texture_at::little-32,
      _texture_data::little-32, skin_refs::little-32, skin_families::little-32,
      skin_at::little-32, part_count::little-32, part_at::little-32, attachment_count::little-32,
      attachment_at::little-32, _::binary>> = rest

    bones = records(data, bone_at, bone_count, 112, &bone/1)

    {textures, texture_flags} = textures(data, texture_at, texture_count)

    {:ok,
     %__MODULE__{
       name: clean(name),
       eye: vector(eye),
       mins: vector(mins),
       maxs: vector(maxs),
       box_mins: vector(box_mins),
       box_maxs: vector(box_maxs),
       flags: flags,
       bones: List.to_tuple(bones),
       parents: bones |> Enum.map(& &1.parent) |> List.to_tuple(),
       controllers: records(data, controller_at, controller_count, 24, &controller/1),
       hitboxes: records(data, hitbox_at, hitbox_count, 32, &hitbox/1),
       sequences:
         data
         |> records(sequence_at, sequence_count, 176, &sequence_record(data, &1))
         |> List.to_tuple(),
       groups: data |> records(group_at, group_count, 104, &group/1) |> List.to_tuple(),
       textures: textures,
       texture_flags: texture_flags,
       skins: skins(data, skin_at, skin_refs, skin_families),
       body_parts: records(data, part_at, part_count, 76, &body_part(data, &1)),
       attachments: records(data, attachment_at, attachment_count, 88, &attachment/1),
       animation: %{0 => data}
     }}
  end

  def parse(_data), do: {:error, :not_a_studio_model}

  @doc "The model with the textures and skins of its separate texture file `data` (`…t.mdl`)."
  @spec add_textures(t(), binary()) :: t()
  def add_textures(
        %__MODULE__{} = studio,
        <<"IDST", 10::little-32, _::binary-64, _::little-32, rest::binary>> = data
      ) do
    <<_::binary-60, _flags::little-32, _::binary-40, texture_count::little-32,
      texture_at::little-32, _texture_data::little-32, skin_refs::little-32,
      skin_families::little-32, skin_at::little-32, _::binary>> = rest

    {textures, texture_flags} = textures(data, texture_at, texture_count)

    %{
      studio
      | textures: textures,
        texture_flags: texture_flags,
        skins: skins(data, skin_at, skin_refs, skin_families)
    }
  end

  def add_textures(studio, _data), do: studio

  @doc "The model with the animation of sequence group `group` from its file `data` (`…0n.mdl`)."
  @spec add_group(t(), pos_integer(), binary()) :: t()
  def add_group(%__MODULE__{} = studio, group, <<"IDSQ", _::binary>> = data),
    do: %{studio | animation: Map.put(studio.animation, group, data)}

  def add_group(studio, _group, _data), do: studio

  @doc "The groups above 0 whose animation `add_group/3` has not yet supplied."
  @spec missing_groups(t()) :: [pos_integer()]
  def missing_groups(%__MODULE__{} = studio) do
    studio.sequences
    |> Tuple.to_list()
    |> Enum.map(& &1.group)
    |> Enum.uniq()
    |> Enum.reject(&Map.has_key?(studio.animation, &1))
  end

  @doc "The index of the sequence named `name` (without regard to case), or `nil`."
  @spec sequence(t(), String.t()) :: non_neg_integer() | nil
  def sequence(%__MODULE__{sequences: sequences}, name) do
    name = String.downcase(name)
    sequences |> Tuple.to_list() |> Enum.find_index(&(String.downcase(&1.name) == name))
  end

  @doc """
  Each bone's position and rotation relative to its parent for sequence `index` at
  `frame`, a float counting frames from the sequence's start (seconds times its frame
  rate). A looping sequence wraps every `frames` frames; one that does not loop holds
  its last frame. Between two frames the rotations are slerped and the positions
  mixed. A sequence index outside the model is sequence 0.

  ## Options

    * `:bonecontrols` — the five bone controller values in the controllers' own units
      (degrees for a turning controller), the fifth the mouth; each is held inside its
      controller's range unless the controller wraps (type bit `0x8000`), and a turning
      controller's value (types `0x08` to `0x20`) is taken as degrees
    * `:controllers` — up to four settings 0 to 255 instead, each standing for
      `start + n / 255 * (end - start)`, and `:mouth` the fifth likewise
    * `:subblend` — `{first, second}`, each -1.0 to 1.0, choosing among a sequence's
      blends along its first and second blend axes, default `{0.0, 0.0}`
    * `:blend` — 0 to 255 instead of `:subblend`'s first value, standing for
      `n / 255 * 2 - 1`
    * `:base` — `{sequence, frame, last}`: bones before bone `last` take sequence
      `sequence` at `frame` instead
  """
  @spec locals(t(), integer(), number(), keyword()) :: [{Cauldron3D.Vec.t(), Quat.t()}]
  def locals(%__MODULE__{} = studio, index, frame, opts \\ []) do
    adjust = adjustments(studio, opts)
    subblend = subblend(opts)
    count = tuple_size(studio.bones)

    case Keyword.get(opts, :base) do
      {base, base_frame, last} when last > 0 ->
        split = min(last, count)
        below = bone_range(studio, base, base_frame, 0, split, subblend, adjust)
        below ++ bone_range(studio, index, frame, split, count, subblend, adjust)

      _ ->
        bone_range(studio, index, frame, 0, count, subblend, adjust)
    end
  end

  @doc "The vertices of model `model` of body part `part`, each moved by its bone's transform."
  @spec vertices(t(), {non_neg_integer(), non_neg_integer()}, tuple()) :: tuple()
  def vertices(%__MODULE__{} = studio, {part, model}, transforms) do
    %{vertices: vertices, vertex_bones: bones} =
      studio |> Map.get(:body_parts) |> Enum.at(part) |> Map.get(:models) |> Enum.at(model)

    vertices
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Enum.map(fn {point, i} ->
      Cauldron3D.Skeleton.apply(elem(transforms, :binary.at(bones, i)), point)
    end)
    |> List.to_tuple()
  end

  @doc """
  The model's triangles as `Cauldron3D.Polygon`s, posed by `transforms` (one per bone,
  from `Cauldron3D.Skeleton.pose/3`, the entity's place and turn included).

  Each body part draws the model its geomset value names, counting from 1, or its first
  model when the value is 0 or missing. A mesh draws the texture its skin reference
  names in skin family `:skin`, or in family 0 when the model has no such family; a mesh
  whose reference is beyond the model's references is not drawn.

  Each corner is lit by its normal, turned by its vertex's bone: `ambient + diffuse *
  (normal · direction / 2 + 1 / 2)` a channel, or `ambient + diffuse * (normal ·
  direction)` without half-Lambert; with `:ldr` each channel is then held at 1.5 or
  below, cut down to steps of 1/32 (red and blue) or 1/64 (green) and multiplied by
  0.75. The light times `:colour`'s red, green and blue, and `:colour`'s alpha, are the
  corner's tint.

  A texture flagged masked (`0x40`) is see-through at colour 255, and one flagged masked
  or alpha-solid (`0x800`) and not fullbright (`0x04`) is cut out where its alpha is
  below half. A texture flagged chrome (`0x02`) takes its place on the texture from the
  normal and the eye: for each vertex, with `toward` the direction from `:eye` to the
  vertex's bone, `up` the normalised `toward × :view_right` and `right` the normalised
  `up × toward`, both turned back into the bone's own space, the place is
  `((normal · right + 1) / 2, (normal · up + 1) / 2)` of the texture's size.

  ## Options

    * `:geomsets` — a map from body part to its geomset value, default `%{}`
    * `:skin` — the skin family, default 0
    * `:light` — `%{ambient: {r, g, b}, diffuse: {r, g, b}, direction: vec}` (1.0 a
      texture's own colours, `direction` in the world, of length one), or one number
      for an even light (1.0 the texture's own colours); default 1.0
    * `:halflambert` — default true
    * `:ldr` — default false
    * `:colour` — `{r, g, b, a}`, default `{1.0, 1.0, 1.0, 1.0}`
    * `:fatness` — moves each corner this far along its turned normal, default 0.0
    * `:scale` — the entity's scale the transforms carry, default 1.0
    * `:eye`, `:view_right` — where the view is and its right, for chrome textures
    * `:shell` — paints every mesh with another texture instead, unlit:
      `%{texture:, colour: {r, g, b, a}, axes: {forward, left, up}, time:, bulge:,
      scroll:}`; each corner is moved along its turned normal by `sin(s * width + time
      * speed) * height` (`bulge` `{width, height, speed}`, `s` its texture place over
      the texture's width), takes its place on the shell texture from the eye's
      reflection in it (`s = 1/2 + r_left / 2`, `t = 1/2 - r_up / 2`, `r` the
      reflection of the direction to `:eye` in the normal, along the entity's `axes`)
      moved by `scroll` `{ds, dt}` times `time`, and is tinted by the colour
    * `:blend`, `:depth`, `:cull` — as `Cauldron3D.Polygon`'s, for every triangle
  """
  @spec polygons(t(), tuple(), keyword()) :: [Cauldron3D.Polygon.t()]
  def polygons(%__MODULE__{} = studio, transforms, opts \\ []) do
    geomsets = Keyword.get(opts, :geomsets, %{})
    family = Keyword.get(opts, :skin, 0)

    studio.body_parts
    |> Enum.with_index()
    |> Enum.flat_map(fn {part, index} ->
      case Enum.at(part.models, geomset_model(part, Map.get(geomsets, index, 0))) do
        nil -> []
        model -> model_polygons(studio, model, transforms, family, opts)
      end
    end)
  end

  @doc "The model index within body part `part` that body value `body` selects."
  @spec body_model(t(), non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def body_model(%__MODULE__{} = studio, part, body) do
    %{base: base, models: models} = Enum.at(studio.body_parts, part)
    rem(div(body, max(base, 1)), max(length(models), 1))
  end

  defp geomset_model(%{models: models}, value) when value >= 1,
    do: rem(trunc(value) - 1, max(length(models), 1))

  defp geomset_model(_part, _value), do: 0

  defp model_polygons(studio, model, transforms, family, opts) do
    points = vertices_of(model, transforms)
    context = corner_context(model, transforms, points, opts)

    Enum.flat_map(model.meshes, fn mesh ->
      case texture_of(studio, family, mesh.skin) do
        nil -> []
        {texture, flags} -> mesh_polygons(texture, flags, mesh, context, opts)
      end
    end)
  end

  defp mesh_polygons(texture, _flags, mesh, %{shell: %{} = shell} = context, opts) do
    for {c0, c1, c2} <- mesh.triangles do
      corners = [
        shell_corner(context, shell, c0, texture),
        shell_corner(context, shell, c1, texture),
        shell_corner(context, shell, c2, texture)
      ]

      %Cauldron3D.Polygon{
        points: Enum.map(corners, &elem(&1, 0)),
        uvs: Enum.map(corners, &elem(&1, 1)),
        tints: List.duplicate(shell.colour, 3),
        paint: {:texture, shell.texture, nil},
        blend: Keyword.get(opts, :blend, :none),
        cull: Keyword.get(opts, :cull, :none),
        depth: Keyword.get(opts, :depth, :test)
      }
    end
  end

  defp mesh_polygons(texture, flags, mesh, context, opts) do
    chrome? = band(flags, 0x02) != 0
    clear = if band(flags, 0x40) != 0 and not chrome?, do: 255
    cutout? = band(flags, 0x04) == 0 and band(flags, 0x840) != 0
    blend = Keyword.get(opts, :blend, :none)

    for {c0, c1, c2} <- mesh.triangles do
      corners = [
        corner(context, c0, chrome?, texture),
        corner(context, c1, chrome?, texture),
        corner(context, c2, chrome?, texture)
      ]

      %Cauldron3D.Polygon{
        points: Enum.map(corners, &elem(&1, 0)),
        uvs: Enum.map(corners, &elem(&1, 1)),
        tints: Enum.map(corners, &elem(&1, 2)),
        paint: {:texture, texture, nil},
        clear: clear,
        alpha_test: if(cutout? and blend == :none, do: 0.5),
        blend: blend,
        cull: Keyword.get(opts, :cull, :none),
        depth: Keyword.get(opts, :depth, :test)
      }
    end
  end

  defp corner_context(model, transforms, points, opts) do
    %{
      model: model,
      transforms: transforms,
      points: points,
      light: Keyword.get(opts, :light, 1.0),
      halflambert?: Keyword.get(opts, :halflambert, true),
      ldr?: Keyword.get(opts, :ldr, false),
      colour: Keyword.get(opts, :colour, {1.0, 1.0, 1.0, 1.0}),
      fatness: Keyword.get(opts, :fatness, 0.0),
      scale: Keyword.get(opts, :scale, 1.0),
      eye: Keyword.get(opts, :eye, {0.0, 0.0, 0.0}),
      view_right: Keyword.get(opts, :view_right, {0.0, -1.0, 0.0}),
      shell: Keyword.get(opts, :shell)
    }
  end

  defp shell_corner(context, shell, {v, n, s, _t}, texture) do
    transform = bone(context.transforms, context.model.vertex_bones, v)
    turned = Cauldron3D.Skeleton.rotate(transform, normal_at(context.model.normals, n))
    point = elem(context.points, v)

    point =
      if context.fatness == 0, do: point, else: Vec.madd(point, turned, context.fatness)

    point =
      case shell.bulge do
        {width, height, speed} ->
          Vec.madd(
            point,
            turned,
            :math.sin(s / texture.width * width + shell.time * speed) * height
          )

        nil ->
          point
      end

    {point, shell_uv(context, shell, point, turned)}
  end

  defp shell_uv(context, shell, point, turned) do
    normal = Vec.normalize(turned)
    viewer = Vec.normalize(Vec.sub(context.eye, point))
    d = Vec.dot(normal, viewer)
    reflected = Vec.sub(Vec.scale(normal, 2 * d), viewer)
    {_forward, left, up} = shell.axes
    {ds, dt} = shell.scroll
    s = 0.5 + Vec.dot(reflected, left) * 0.5 + ds * shell.time
    t = 0.5 - Vec.dot(reflected, up) * 0.5 + dt * shell.time
    {s * shell.texture.width, t * shell.texture.height}
  end

  defp corner(context, {v, n, s, t}, chrome?, texture) do
    transform = bone(context.transforms, context.model.vertex_bones, v)
    normal = normal_at(context.model.normals, n)
    turned = Cauldron3D.Skeleton.rotate(transform, normal)
    point = elem(context.points, v)

    point =
      if context.fatness == 0, do: point, else: Vec.madd(point, turned, context.fatness)

    uv =
      if chrome?,
        do: chrome_uv(context, transform, normal, texture),
        else: {s / 1, t / 1}

    {point, uv, tint(context, turned)}
  end

  defp normal_at(normals, n) when n < tuple_size(normals), do: elem(normals, n)
  defp normal_at(_normals, _n), do: {0.0, 0.0, 1.0}

  defp tint(%{light: level, colour: {r, g, b, a}}, _turned) when is_number(level),
    do: {level * r, level * g, level * b, a}

  defp tint(context, turned) do
    %{ambient: {ar, ag, ab}, diffuse: {dr, dg, db}, direction: direction} = context.light
    facing = Vec.dot(Vec.normalize(turned), direction)
    facing = if context.halflambert?, do: facing * 0.5 + 0.5, else: facing
    {lr, lg, lb} = {ar + dr * facing, ag + dg * facing, ab + db * facing}
    {lr, lg, lb} = if context.ldr?, do: ldr({lr, lg, lb}), else: {lr, lg, lb}
    {r, g, b, a} = context.colour
    {lr * r, lg * g, lb * b, a}
  end

  defp ldr({r, g, b}) do
    {r, g, b} = {min(r, 1.5), min(g, 1.5), min(b, 1.5)}

    {Float.floor(r * 32) / 32 * 0.75, Float.floor(g * 64) / 64 * 0.75,
     Float.floor(b * 32) / 32 * 0.75}
  end

  defp chrome_uv(context, transform, normal, texture) do
    toward = Vec.normalize(Vec.sub(Cauldron3D.Skeleton.origin(transform), context.eye))
    up = Vec.normalize(cross(toward, context.view_right))
    right = Vec.normalize(cross(up, toward))
    local_right = Vec.scale(unrotate(transform, right), 1 / context.scale)
    local_up = Vec.scale(unrotate(transform, up), 1 / context.scale)
    s = (Vec.dot(normal, local_right) + 1.0) * 0.5
    t = (Vec.dot(normal, local_up) + 1.0) * 0.5
    {s * texture.width, t * texture.height}
  end

  defp unrotate({{a, b, c, _}, {d, e, f, _}, {g, h, i, _}}, {x, y, z}),
    do: {a * x + d * y + g * z, b * x + e * y + h * z, c * x + f * y + i * z}

  defp cross({ax, ay, az}, {bx, by, bz}),
    do: {ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx}

  defp vertices_of(%{vertices: vertices, vertex_bones: bones}, transforms) do
    vertices
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Enum.map(fn {point, i} -> Cauldron3D.Skeleton.apply(bone(transforms, bones, i), point) end)
    |> List.to_tuple()
  end

  defp bone(transforms, bones, i) do
    index = if i < byte_size(bones), do: :binary.at(bones, i), else: 0

    if index < tuple_size(transforms),
      do: elem(transforms, index),
      else: Cauldron3D.Skeleton.identity()
  end

  defp texture_of(studio, family, skin_ref) do
    families = tuple_size(studio.skins)

    with true <- families > 0,
         refs = studio.skins |> elem(0) |> tuple_size(),
         true <- skin_ref < refs,
         family = if(family >= 0 and family < families, do: family, else: 0),
         index = studio.skins |> elem(family) |> elem(skin_ref),
         true <- index >= 0 and index < tuple_size(studio.textures),
         %Texture{} = texture <- elem(studio.textures, index) do
      {texture, elem(studio.texture_flags, index)}
    else
      _ -> nil
    end
  end

  defp bone_range(_studio, _index, _frame, first, stop, _subblend, _adjust) when first >= stop,
    do: []

  defp bone_range(studio, index, frame, first, stop, subblend, adjust) do
    index = if index >= 0 and index < tuple_size(studio.sequences), do: index, else: 0
    sequence = elem(studio.sequences, index)

    case frames(sequence, frame) do
      nil ->
        for bone <- first..(stop - 1), do: rest(elem(studio.bones, bone))

      {frame1, frame2, frac} ->
        data = Map.get(studio.animation, sequence.group)
        weights = weights(sequence, subblend, frame1, frame2, frac)
        for bone <- first..(stop - 1), do: blended(studio, sequence, data, bone, weights, adjust)
    end
  end

  defp rest(info) do
    {position, angles} = info.value |> Tuple.to_list() |> Enum.split(3)
    {List.to_tuple(position), Quat.from_euler(List.to_tuple(angles))}
  end

  defp frames(%{frames: 0}, _frame), do: nil

  defp frames(sequence, frame) do
    time = max(frame / 1, 0.0)
    frame1 = trunc(time)
    frac = time - frame1
    looping? = band(sequence.flags, 1) != 0
    frame1 = wrap(frame1, sequence.frames, looping?)
    frame2 = wrap(trunc(time) + 1, sequence.frames, looping?)

    if frame2 < frame1, do: {frame2, frame1, 1 - frac}, else: {frame1, frame2, frac}
  end

  defp wrap(frame, frames, _looping?) when frame < frames, do: frame
  defp wrap(frame, frames, true), do: rem(frame, frames)
  defp wrap(_frame, frames, false), do: frames - 1

  defp weights(%{blends: blends}, {sub1, sub2}, frame1, frame2, frac) when blends > 1 do
    {bf0, bf1} = blend_factors(blends)
    sub1 = (sub1 + 1) / 2
    sub2 = (sub2 + 1) / 2
    across = blend_weights(bf0, bf1, sub1, sub2)

    if frame1 != frame2,
      do:
        Enum.map(across, fn {blend, weight} -> {frame1, blend, weight * (1 - frac)} end) ++
          Enum.map(across, fn {blend, weight} -> {frame2, blend, weight * frac} end),
      else: Enum.map(across, fn {blend, weight} -> {frame1, blend, weight} end)
  end

  defp weights(_sequence, _subblend, frame1, frame2, frac), do: {:single, frame1, frame2, frac}

  defp blend_factors(4), do: {2, 2}
  defp blend_factors(9), do: {3, 3}
  defp blend_factors(blends), do: {blends, 1}

  defp blend_weights(bf0, bf1, sub1, sub2) when bf0 > 1 do
    {f1, f2, frac} = blend_step(bf0, sub1)

    if bf1 > 1 do
      {a1, a2, frac2} = blend_step(bf1, sub2)

      upper =
        if frac2 != 0,
          do: nonzero([{f2 + a2 * bf0, frac * frac2}, {f1 + a2 * bf0, (1 - frac) * frac2}]),
          else: []

      lower =
        if 1 - frac2 != 0,
          do:
            nonzero([
              {f2 + a1 * bf0, frac * (1 - frac2)},
              {f1 + a1 * bf0, (1 - frac) * (1 - frac2)}
            ]),
          else: []

      upper ++ lower
    else
      nonzero([{f1, frac}, {f2, 1 - frac}])
    end
  end

  defp blend_weights(_bf0, _bf1, _sub1, _sub2), do: [{0, 1.0}]

  defp nonzero(pairs), do: Enum.reject(pairs, fn {_blend, weight} -> weight == 0 end)

  defp blend_step(factor, sub) do
    frac = (factor - 1) * clamp(sub, 0.0, 1.0)
    first = frac |> trunc() |> clamp(0, factor - 1)
    second = clamp(first + 1, 0, factor - 1)
    {first, second, clamp(frac - first, 0.0, 1.0)}
  end

  defp clamp(value, low, high), do: value |> max(low) |> min(high)

  defp blended(studio, sequence, data, bone, {:single, frame1, frame2, frac}, adjust) do
    info = elem(studio.bones, bone)
    at = sequence.animation + bone * 12
    {p1, a1} = calculate(data, at, frame1, info, adjust)
    q1 = Quat.from_euler(a1)

    if frame1 != frame2 do
      {p2, a2} = calculate(data, at, frame2, info, adjust)
      {lerp(p1, p2, frac), slerp(q1, Quat.from_euler(a2), frac)}
    else
      {p1, q1}
    end
  end

  defp blended(studio, sequence, data, bone, [{frame, blend, weight} | rest], adjust) do
    info = elem(studio.bones, bone)
    count = tuple_size(studio.bones)
    at = fn blend -> sequence.animation + (blend * count + bone) * 12 end
    {position, angles} = calculate(data, at.(blend), frame, info, adjust)
    {x, y, z, w} = Quat.from_euler(angles)
    first = {scale3(position, weight), {x * weight, y * weight, z * weight, w * weight}}

    {position, quat} =
      Enum.reduce(rest, first, fn {frame, blend, weight}, {sum_p, sum_q} ->
        {p, a} = calculate(data, at.(blend), frame, info, adjust)
        q = Quat.from_euler(a)
        signed = if dot4(q, sum_q) < 0, do: -weight, else: weight
        {add3(sum_p, scale3(p, weight)), madd4(sum_q, q, signed)}
      end)

    {position, normalize4(quat)}
  end

  defp blended(studio, _sequence, _data, bone, [], _adjust), do: rest(elem(studio.bones, bone))

  defp calculate(data, at, frame, info, adjust) do
    values =
      for j <- 0..5 do
        base = channel(data, at, j, frame, info)

        case elem(info.controllers, j) do
          -1 -> base
          controller -> base + elem(adjust, controller)
        end
      end

    [x, y, z, ax, ay, az] = values
    {{x, y, z}, {ax, ay, az}}
  end

  defp slerp({px, py, pz, pw} = p, {qx, qy, qz, qw}, t) do
    a = (px - qx) ** 2 + (py - qy) ** 2 + (pz - qz) ** 2 + (pw - qw) ** 2
    b = (px + qx) ** 2 + (py + qy) ** 2 + (pz + qz) ** 2 + (pw + qw) ** 2
    {qx, qy, qz, qw} = q = if a > b, do: {-qx, -qy, -qz, -qw}, else: {qx, qy, qz, qw}
    cosom = dot4(p, q)

    if 1.0 + cosom > 0.00000001 do
      {sclp, sclq} =
        if 1.0 - cosom > 0.00000001 do
          omega = :math.acos(cosom)
          sinom = :math.sin(omega)
          {:math.sin((1.0 - t) * omega) / sinom, :math.sin(t * omega) / sinom}
        else
          {1.0 - t, t}
        end

      {sclp * px + sclq * qx, sclp * py + sclq * qy, sclp * pz + sclq * qz, sclp * pw + sclq * qw}
    else
      {rx, ry, rz, rw} = {-py, px, -pw, pz}
      sclp = :math.sin((1.0 - t) * 0.5 * :math.pi())
      sclq = :math.sin(t * 0.5 * :math.pi())
      {sclp * px + sclq * rx, sclp * py + sclq * ry, sclp * pz + sclq * rz, sclp * pw + sclq * rw}
    end
  end

  defp dot4({ax, ay, az, aw}, {bx, by, bz, bw}), do: ax * bx + ay * by + az * bz + aw * bw

  defp madd4({ax, ay, az, aw}, {bx, by, bz, bw}, k),
    do: {ax + bx * k, ay + by * k, az + bz * k, aw + bw * k}

  defp normalize4(q) do
    length = :math.sqrt(dot4(q, q))

    if length != 0 and length != 1 do
      {x, y, z, w} = q
      {x / length, y / length, z / length, w / length}
    else
      q
    end
  end

  defp scale3({x, y, z}, k), do: {x * k, y * k, z * k}
  defp add3({ax, ay, az}, {bx, by, bz}), do: {ax + bx, ay + by, az + bz}

  defp channel(nil, _at, j, _frame, info), do: elem(info.value, j)

  defp channel(data, at, j, frame, info) do
    offset =
      if at + j * 2 + 2 <= byte_size(data),
        do: :binary.decode_unsigned(binary_part(data, at + j * 2, 2), :little),
        else: 0

    raw = if offset == 0, do: 0, else: run_value(data, at + offset, frame)
    elem(info.value, j) + raw * elem(info.scale, j)
  end

  defp run_value(data, at, frame) when at + 2 <= byte_size(data) do
    <<_::binary-size(^at), valid, total, _::binary>> = data

    cond do
      total == 0 -> 0
      total <= frame -> run_value(data, at + (valid + 1) * 2, frame - total)
      valid > frame -> short(data, at + (frame + 1) * 2)
      true -> short(data, at + valid * 2)
    end
  end

  defp run_value(_data, _at, _frame), do: 0

  defp short(data, at) when at + 2 <= byte_size(data) do
    <<_::binary-size(^at), value::little-signed-16, _::binary>> = data
    value
  end

  defp short(_data, _at), do: 0

  defp subblend(opts) do
    case {Keyword.get(opts, :subblend), Keyword.get(opts, :blend)} do
      {{first, second}, _} -> {first / 1, second / 1}
      {nil, blend} when is_number(blend) -> {blend / 255 * 2 - 1, 0.0}
      _ -> {0.0, 0.0}
    end
  end

  defp adjustments(studio, opts) do
    values = controller_values(studio, opts)

    studio.controllers
    |> Enum.map(fn controller ->
      value = Enum.at(values, controller.index, 0.0)

      value =
        if controller.wrap?, do: value, else: clamp(value, controller.start, controller.stop)

      turning? = controller.type >= 0x0008 and controller.type <= 0x0020
      if turning?, do: :math.pi() * value / 180, else: value
    end)
    |> List.to_tuple()
  end

  defp controller_values(studio, opts) do
    case Keyword.get(opts, :bonecontrols) do
      values when is_list(values) ->
        Enum.map(values, &(&1 / 1))

      nil ->
        settings = Keyword.get(opts, :controllers, [])
        mouth = Keyword.get(opts, :mouth, 0)

        for index <- 0..4,
            do: controller_value(studio, index, setting_for(index, settings, mouth))
    end
  end

  defp setting_for(4, _settings, mouth), do: mouth
  defp setting_for(index, settings, _mouth), do: Enum.at(settings, index, 0)

  defp controller_value(studio, index, setting) do
    case Enum.find(studio.controllers, &(&1.index == index)) do
      nil -> 0.0
      %{start: start, stop: stop} -> start + setting / 255 * (stop - start)
    end
  end

  defp lerp({ax, ay, az}, {bx, by, bz}, t),
    do: {ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t}

  defp records(_data, _at, count, _size, _read) when count <= 0, do: []

  defp records(data, at, count, size, read) do
    if at + count * size <= byte_size(data),
      do: for(i <- 0..(count - 1), do: read.(binary_part(data, at + i * size, size))),
      else: []
  end

  defp bone(
         <<name::binary-32, parent::little-signed-32, flags::little-32, controllers::binary-24,
           values::binary-24, scales::binary-24>>
       ) do
    %{
      name: clean(name),
      parent: parent,
      flags: flags,
      controllers: List.to_tuple(for(<<c::little-signed-32 <- controllers>>, do: c)),
      value: floats(values),
      scale: floats(scales)
    }
  end

  defp controller(
         <<bone::little-signed-32, type::little-32, start::little-float-32, stop::little-float-32,
           rest::little-signed-32, index::little-signed-32>>
       ) do
    %{
      bone: bone,
      type: type,
      channel: channel_of(type),
      start: start,
      stop: stop,
      rest: rest,
      index: index,
      wrap?: Bitwise.band(type, 0x8000) != 0
    }
  end

  defp channel_of(type) do
    bits = Bitwise.band(type, 0x3F)
    Enum.find(0..5, 0, &(Bitwise.band(bits, Bitwise.bsl(1, &1)) != 0))
  end

  defp hitbox(
         <<bone::little-signed-32, group::little-signed-32, mins::binary-12, maxs::binary-12>>
       ),
       do: %{bone: bone, group: group, mins: vector(mins), maxs: vector(maxs)}

  defp sequence_record(
         data,
         <<label::binary-32, fps::little-float-32, flags::little-32, activity::little-signed-32,
           weight::little-signed-32, event_count::little-32, event_at::little-32,
           frames::little-32, _pivot_count::little-32, _pivot_at::little-32,
           motion_type::little-32, motion_bone::little-signed-32, movement::binary-12,
           _automove_pos::little-32, _automove_angle::little-32, mins::binary-12, maxs::binary-12,
           blends::little-32, animation::little-32, blend_type0::little-32,
           blend_type1::little-32, blend_start0::little-float-32, blend_start1::little-float-32,
           blend_end0::little-float-32, blend_end1::little-float-32, _blend_parent::little-32,
           group::little-32, entry::little-32, exit::little-32, node_flags::little-32,
           next::little-32>>
       ) do
    %{
      name: clean(label),
      fps: fps,
      flags: flags,
      activity: activity,
      weight: weight,
      events: records(data, event_at, event_count, 76, &event/1),
      frames: frames,
      motion_type: motion_type,
      motion_bone: motion_bone,
      movement: vector(movement),
      mins: vector(mins),
      maxs: vector(maxs),
      blends: blends,
      animation: animation,
      blend_types: {blend_type0, blend_type1},
      blend_starts: {blend_start0, blend_start1},
      blend_ends: {blend_end0, blend_end1},
      group: group,
      entry: entry,
      exit: exit,
      node_flags: node_flags,
      next: next
    }
  end

  defp event(
         <<frame::little-signed-32, event::little-signed-32, type::little-signed-32,
           options::binary-64>>
       ),
       do: %{frame: frame, event: event, type: type, options: clean(options)}

  defp group(<<label::binary-32, name::binary-64, _::binary-8>>),
    do: %{label: clean(label), name: clean(name)}

  defp attachment(
         <<name::binary-32, type::little-32, bone::little-signed-32, origin::binary-12,
           vectors::binary-36>>
       ) do
    <<a::binary-12, b::binary-12, c::binary-12>> = vectors

    %{
      name: clean(name),
      type: type,
      bone: bone,
      origin: vector(origin),
      vectors: {vector(a), vector(b), vector(c)}
    }
  end

  defp textures(data, at, count) do
    entries = records(data, at, count, 80, &texture_entry/1)

    textures =
      for %{width: w, height: h, index: index} <- entries do
        if w > 0 and h > 0 and index + w * h + 768 <= byte_size(data),
          do:
            Texture.new(
              w,
              h,
              binary_part(data, index, w * h),
              binary_part(data, index + w * h, 768)
            ),
          else: nil
      end

    {List.to_tuple(textures), entries |> Enum.map(& &1.flags) |> List.to_tuple()}
  end

  defp texture_entry(
         <<name::binary-64, flags::little-32, width::little-32, height::little-32,
           index::little-32>>
       ),
       do: %{name: clean(name), flags: flags, width: width, height: height, index: index}

  defp skins(_data, _at, refs, families) when refs <= 0 or families <= 0, do: {}

  defp skins(data, at, refs, families) do
    if at + refs * families * 2 <= byte_size(data) do
      0..(families - 1)
      |> Enum.map(&family_skins(data, at + &1 * refs * 2, refs))
      |> List.to_tuple()
    else
      {}
    end
  end

  defp family_skins(data, at, refs) do
    for(<<index::little-signed-16 <- binary_part(data, at, refs * 2)>>, do: index)
    |> List.to_tuple()
  end

  defp body_part(
         data,
         <<name::binary-64, model_count::little-32, base::little-32, model_at::little-32>>
       ),
       do: %{
         name: clean(name),
         base: base,
         models: records(data, model_at, model_count, 112, &model(data, &1))
       }

  defp model(
         data,
         <<name::binary-64, _type::little-32, radius::little-float-32, mesh_count::little-32,
           mesh_at::little-32, vertex_count::little-32, vertex_info::little-32,
           vertex_at::little-32, normal_count::little-32, normal_info::little-32,
           normal_at::little-32, _::binary>>
       ) do
    %{
      name: clean(name),
      radius: radius,
      vertices: points(data, vertex_at, vertex_count),
      vertex_bones: slice(data, vertex_info, vertex_count),
      normals: points(data, normal_at, normal_count),
      normal_bones: slice(data, normal_info, normal_count),
      meshes: records(data, mesh_at, mesh_count, 20, &mesh(data, &1))
    }
  end

  defp mesh(
         data,
         <<_triangle_count::little-32, triangle_at::little-32, skin::little-32, _::binary>>
       ),
       do: %{skin: skin, triangles: commands(data, triangle_at, [])}

  defp commands(data, at, acc) when at + 2 <= byte_size(data) do
    <<_::binary-size(^at), count::little-signed-16, _::binary>> = data
    size = abs(count) * 8

    if count == 0 or at + 2 + size > byte_size(data) do
      acc |> Enum.reverse() |> List.flatten()
    else
      commands(data, at + 2 + size, [
        triangles(command_corners(data, at + 2, size), count < 0) | acc
      ])
    end
  end

  defp commands(_data, _at, acc), do: acc |> Enum.reverse() |> List.flatten()

  defp command_corners(data, at, size) do
    for <<v::little-16, n::little-16, s::little-signed-16,
          t::little-signed-16 <- binary_part(data, at, size)>>,
        do: {v, n, s, t}
  end

  defp triangles(corners, true) do
    [first | rest] = corners
    rest |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [b, c] -> {first, b, c} end)
  end

  defp triangles(corners, false) do
    corners
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.with_index()
    |> Enum.map(fn
      {[a, b, c], i} when rem(i, 2) == 0 -> {a, b, c}
      {[a, b, c], _} -> {b, a, c}
    end)
  end

  defp points(data, at, count) do
    if count > 0 and at + count * 12 <= byte_size(data),
      do:
        for(
          <<x::little-float-32, y::little-float-32,
            z::little-float-32 <- binary_part(data, at, count * 12)>>,
          do: {x, y, z}
        )
        |> List.to_tuple(),
      else: {}
  end

  defp slice(data, at, count) do
    if count > 0 and at + count <= byte_size(data), do: binary_part(data, at, count), else: <<>>
  end

  defp floats(bytes), do: List.to_tuple(for(<<v::little-float-32 <- bytes>>, do: v))
  defp vector(<<x::little-float-32, y::little-float-32, z::little-float-32>>), do: {x, y, z}
  defp clean(name), do: name |> :binary.split(<<0>>) |> hd()
end
