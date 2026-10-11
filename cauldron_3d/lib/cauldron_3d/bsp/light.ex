defmodule Cauldron3D.Bsp.Light do
  @moduledoc """
  How brightly a world is lit at a point: the lightmap of the nearest upward-facing
  solid face directly below it, within `:reach` units, each light style at its scale.
  Models standing at the point are lit by it.

      Cauldron3D.Bsp.Light.at(bsp, origin, styles)
      #=> {r, g, b}

  `styles` is a tuple or map from style number to scale, 256 normal. The result is per
  channel, 0 and up (a world with grey lightmaps gives three equal values); `nil` when
  no face is below.

  `point/4` finds the light the way the world's own tree finds it: down from the point
  through the nodes to the first node whose plane the line crosses with a lit face under
  the crossing.
  """

  alias Cauldron3D.{Bsp, Vec}
  alias Cauldron3D.Bsp.Face

  @doc "The light at `point`. Options: `:reach`, how far below to look, default 2048."
  @spec at(Bsp.t(), Vec.t(), tuple() | map(), keyword()) :: {number(), number(), number()} | nil
  def at(%Bsp{} = bsp, {x, y, z} = point, styles, opts \\ []) do
    reach = Keyword.get(opts, :reach, 2048.0)

    bsp
    |> Bsp.leaves_touching({x - 0.5, y - 0.5, z - reach}, {x + 0.5, y + 0.5, z})
    |> Enum.flat_map(&elem(bsp.leaves, &1).faces)
    |> Enum.uniq()
    |> Enum.flat_map(&below(bsp, &1, point, reach))
    |> Enum.max_by(fn {height, _face} -> height end, fn -> nil end)
    |> case do
      nil -> nil
      {height, face} -> on_face(bsp, face, {x, y, height}, styles)
    end
  end

  @doc """
  The light at `point` and the direction it comes from, `{{r, g, b}, direction}`, found
  along the line from `point` straight down `:distance` units (default 8192): walking
  the world's nodes front side first, the first node whose plane the line crosses whose
  faces include one, not sky or liquid, whose texture area holds the crossing point.
  Its lightmap sample there, each style's sample times the style's scale over 255 and
  its colour, is the light, from `{1, 0, 1}` (of length one); a face with no lightmap
  gives black from `{0, 1, -1}`, and no face at all black from `{0, 1, 1}`.

  `styles` maps a style number to its scale (256 normal) or to `{scale, {r, g, b}}`; a
  style not in it is 256 and white.
  """
  @spec point(Bsp.t(), Vec.t(), map(), keyword()) :: {Vec.t(), Vec.t()}
  def point(%Bsp{} = bsp, {x, y, z} = start, styles, opts \\ []) do
    stop = {x, y, z - Keyword.get(opts, :distance, 8192.0)}
    %{heads: [head | _]} = elem(bsp.models, 0)

    case recurse(bsp, head, start, stop, styles) do
      nil -> {{0.0, 0.0, 0.0}, Vec.normalize({0.0, 1.0, 1.0})}
      :unlit -> {{0.0, 0.0, 0.0}, Vec.normalize({0.0, 1.0, -1.0})}
      colour -> {colour, Vec.normalize({1.0, 0.0, 1.0})}
    end
  end

  @doc "The light of `face`'s lightmap at `point` on it, each style at its scale; black for an unlit face."
  @spec on_face(Bsp.t(), Face.t(), Vec.t(), tuple() | map()) :: {number(), number(), number()}
  def on_face(_bsp, %Face{lightmap: nil}, _point, _styles), do: {0, 0, 0}

  def on_face(bsp, %Face{} = face, point, styles) do
    {s, t} = Face.st(face, point)
    {s_min, t_min} = face.mins
    {across, down} = Face.lightmap_size(face)
    column = trunc(s - s_min) |> div(face.luxel) |> max(0) |> min(across - 1)
    row = trunc(t - t_min) |> div(face.luxel) |> max(0) |> min(down - 1)
    channels = bsp.light_channels

    face.styles
    |> Enum.with_index()
    |> Enum.reduce({0, 0, 0}, fn {style, i}, {r, g, b} ->
      at = face.lightmap + (i * across * down + row * across + column) * channels
      scale = scale(styles, style)
      {lr, lg, lb} = texel(bsp.lightmaps, at, channels)
      {r + lr * scale / 256, g + lg * scale / 256, b + lb * scale / 256}
    end)
  end

  defp recurse(_bsp, node, _start, _stop, _styles) when node < 0, do: nil

  defp recurse(bsp, node, start, stop, styles) do
    %{plane: plane, front: front_child, back: back_child} = info = elem(bsp.nodes, node)
    {normal, distance} = Bsp.plane(bsp, plane)
    front = Vec.dot(start, normal) - distance
    back = Vec.dot(stop, normal) - distance
    side = front < 0

    {near_child, far_child} =
      if side, do: {back_child, front_child}, else: {front_child, back_child}

    if back < 0 == side do
      recurse(bsp, near_child, start, stop, styles)
    else
      mid = Vec.lerp(start, stop, front / (front - back))

      recurse(bsp, near_child, start, mid, styles) ||
        node_light(bsp, info, mid, styles) ||
        recurse(bsp, far_child, mid, stop, styles)
    end
  end

  defp node_light(bsp, %{first_face: first, face_count: count}, mid, styles) when count > 0 do
    Enum.find_value(first..(first + count - 1), fn index ->
      face_light(bsp, elem(bsp.faces, index), mid, styles)
    end)
  end

  defp node_light(_bsp, _info, _mid, _styles), do: nil

  defp face_light(bsp, %Face{} = face, mid, styles) do
    {s, t} = Face.st(face, mid)
    {s, t} = {trunc(s), trunc(t)}
    {s_min, t_min} = face.mins
    {s_extent, t_extent} = face.extents
    kind = elem(bsp.textures, face.texture).kind

    cond do
      kind in [:sky, :liquid] ->
        nil

      s < s_min or t < t_min ->
        nil

      s - s_min > s_extent or t - t_min > t_extent ->
        nil

      face.lightmap == nil ->
        :unlit

      true ->
        sample_light(bsp, face, div(s - s_min, face.luxel), div(t - t_min, face.luxel), styles)
    end
  end

  defp sample_light(bsp, face, ds, dt, styles) do
    {across, down} = Face.lightmap_size(face)
    channels = bsp.light_channels

    face.styles
    |> Enum.with_index()
    |> Enum.reduce({0.0, 0.0, 0.0}, fn {style, i}, {r, g, b} ->
      at = face.lightmap + (i * across * down + dt * across + ds) * channels
      {scale, {cr, cg, cb}} = style_of(styles, style)
      {lr, lg, lb} = texel(bsp.lightmaps, at, channels)
      k = scale / 255
      {r + lr * k * cr, g + lg * k * cg, b + lb * k * cb}
    end)
  end

  defp style_of(styles, style) do
    case Map.get(styles, style, 256) do
      {scale, rgb} -> {scale, rgb}
      scale -> {scale, {1.0, 1.0, 1.0}}
    end
  end

  defp below(bsp, index, {x, y, z}, reach) do
    face = elem(bsp.faces, index)
    {{nx, ny, nz} = normal, distance} = Bsp.plane(bsp, face.plane)
    up = if face.back?, do: -nz, else: nz
    kind = elem(bsp.textures, face.texture).kind

    with true <- kind in [:solid, :masked] and up > 0.01,
         height = (distance - nx * x - ny * y) / nz,
         true <- height <= z + 0.01 and height >= z - reach,
         true <- inside?(face.points, {x, y, height}, normal) do
      [{height, face}]
    else
      _ -> []
    end
  end

  defp inside?([first | _] = points, point, normal) do
    signs =
      points
      |> Enum.zip(tl(points) ++ [first])
      |> Enum.map(fn {a, b} -> Vec.dot(cross(Vec.sub(b, a), Vec.sub(point, a)), normal) end)

    Enum.all?(signs, &(&1 >= -0.01)) or Enum.all?(signs, &(&1 <= 0.01))
  end

  defp cross({ax, ay, az}, {bx, by, bz}),
    do: {ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx}

  defp texel(lightmaps, at, 3) when at + 3 <= byte_size(lightmaps) do
    <<_::binary-size(^at), r, g, b, _::binary>> = lightmaps
    {r, g, b}
  end

  defp texel(lightmaps, at, 1) when at < byte_size(lightmaps) do
    v = :binary.at(lightmaps, at)
    {v, v, v}
  end

  defp texel(_lightmaps, _at, _channels), do: {0, 0, 0}

  defp scale(styles, style) when is_tuple(styles) and style < tuple_size(styles),
    do: elem(styles, style)

  defp scale(styles, style) when is_map(styles), do: Map.get(styles, style, 256)
  defp scale(_styles, _style), do: 256
end
