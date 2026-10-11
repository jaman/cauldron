defmodule Cauldron3D.Setup do
  @moduledoc """
  A polygon made ready for drawing: clipped to the near plane, projected, and reduced to
  the rows it covers, its edges, and a plane `{at_origin, per_x, per_y}` for each
  attribute across the picture.

      Cauldron3D.Setup.new(view, polygon)
      #=> %Cauldron3D.Setup{} | nil

  `nil` is a polygon that cannot be seen: wholly behind the near plane, facing away
  under its `cull`, edge-on, or outside the picture.

  The attributes are `:near` (grows toward the camera), `:w` (see `Cauldron3D.View`),
  `:uw` and `:vw` (the paint position times `w`), `:light` (carried straight across
  the picture, or `nil`) and `:tint` (four planes, each of red, green, blue and alpha
  times `w`, or `nil`). Rows are sampled at their centres.

  A polygon drawn with `depth: :near_third` has its `:near` plane moved into the nearest
  third of the depth range: `0.333 * near + 0.6665 / view.near`.
  """

  alias Cauldron3D.{Polygon, Vec, View}

  @type plane :: {float(), float(), float()}
  @type edge :: {float(), float(), float(), float()}
  @type t :: %__MODULE__{
          top: non_neg_integer(),
          bottom: non_neg_integer(),
          edges: [edge()],
          near: plane(),
          w: plane(),
          uw: plane(),
          vw: plane(),
          light: plane() | nil,
          tint: {plane(), plane(), plane(), plane()} | nil,
          paint: term(),
          nearest: float(),
          clear: byte() | nil,
          alpha_test: float() | nil,
          depth: :test | :always,
          blend: Cauldron3D.Polygon.blend()
        }

  defstruct [
    :top,
    :bottom,
    :edges,
    :near,
    :w,
    :uw,
    :vw,
    :light,
    :tint,
    :paint,
    :nearest,
    :clear,
    :alpha_test,
    :depth,
    blend: :none
  ]

  @doc "Whether the setup is drawn over the solid polygons rather than among them."
  @spec overlay?(t()) :: boolean()
  def overlay?(%__MODULE__{clear: nil, alpha_test: nil, depth: :test, blend: :none}), do: false
  def overlay?(%__MODULE__{}), do: true

  @doc "Whether an overlay setup hides what is behind it where it is drawn."
  @spec opaque?(t()) :: boolean()
  def opaque?(%__MODULE__{blend: :none}), do: true
  def opaque?(%__MODULE__{}), do: false

  @doc "The polygon ready to draw in `view`, or `nil` when it cannot be seen."
  @spec new(View.t(), Polygon.t()) :: t() | nil
  def new(%View{} = view, %Polygon{} = polygon) do
    count = length(polygon.points)
    uvs = polygon.uvs || List.duplicate({0.0, 0.0}, count)
    lights = polygon.lights || List.duplicate(nil, count)
    tints = polygon.tints || List.duplicate(nil, count)

    vertices =
      Enum.zip_with([polygon.points, uvs, lights, tints], fn [point, {u, v}, light, tint] ->
        {View.to_camera(view, point), u / 1, v / 1, light, tint}
      end)

    with [_, _, _ | _] = clipped <- clip(vertices, view.near),
         projected = Enum.map(clipped, &project(view, &1)),
         true <- facing?(projected, polygon.cull),
         {:ok, rows} <- rows(projected, view.height),
         {:ok, planes} <- planes(projected, polygon.lights != nil, polygon.tints != nil) do
      {top, bottom} = rows
      nearest = projected |> Enum.map(&elem(&1, 2)) |> Enum.max()

      {planes, nearest, depth} = depth_range(polygon.depth, planes, nearest, view)

      struct!(
        __MODULE__,
        Map.merge(planes, %{
          top: top,
          bottom: bottom,
          edges: edges(projected),
          paint: polygon.paint,
          clear: polygon.clear,
          alpha_test: polygon.alpha_test,
          depth: depth,
          blend: polygon.blend,
          nearest: nearest
        })
      )
    else
      _ -> nil
    end
  end

  @doc "The value of an attribute plane at the centre of pixel `{x, y}`."
  @spec at(plane(), number(), number()) :: float()
  def at({origin, per_x, per_y}, x, y), do: origin + per_x * (x + 0.5) + per_y * (y + 0.5)

  @doc """
  The pixels row `y` covers, as `{first, last}` columns inside a picture `width` wide,
  or `nil` when it covers none.
  """
  @spec span(t(), integer(), pos_integer()) :: {integer(), integer()} | nil
  def span(%__MODULE__{edges: edges}, y, width) do
    yc = y + 0.5

    xs =
      for {top, bottom, x_top, slope} <- edges, yc >= top and yc < bottom do
        x_top + (yc - top) * slope
      end

    case xs do
      [] ->
        nil

      xs ->
        first = max(ceil(Enum.min(xs) - 0.5), 0)
        last = min(ceil(Enum.max(xs) - 0.5) - 1, width - 1)
        if first <= last, do: {first, last}
    end
  end

  defp depth_range(:near_third, %{near: {a0, ax, ay}} = planes, nearest, view) do
    offset = 0.6665 / view.near

    {%{planes | near: {0.333 * a0 + offset, 0.333 * ax, 0.333 * ay}}, 0.333 * nearest + offset,
     :test}
  end

  defp depth_range(depth, planes, nearest, _view), do: {planes, nearest, depth}

  defp clip(vertices, near) do
    vertices
    |> Enum.zip(tl(vertices) ++ [hd(vertices)])
    |> Enum.flat_map(fn {from, to} -> clip_edge(from, to, near) end)
  end

  defp clip_edge(
         {{_, _, from_depth}, _, _, _, _} = from,
         {{_, _, to_depth}, _, _, _, _} = to,
         near
       ) do
    case {from_depth >= near, to_depth >= near} do
      {true, true} -> [from]
      {true, false} -> [from, crossing(from, to, near)]
      {false, true} -> [crossing(from, to, near)]
      {false, false} -> []
    end
  end

  defp crossing({from_point, fu, fv, fl, ft}, {to_point, tu, tv, tl, tt}, near) do
    {_, _, from_depth} = from_point
    {_, _, to_depth} = to_point
    t = (near - from_depth) / (to_depth - from_depth)
    light = if fl == nil, do: nil, else: fl + (tl - fl) * t

    {Vec.lerp(from_point, to_point, t), fu + (tu - fu) * t, fv + (tv - fv) * t, light,
     lerp_tint(ft, tt, t)}
  end

  defp lerp_tint(nil, _to, _t), do: nil

  defp lerp_tint({r0, g0, b0, a0}, {r1, g1, b1, a1}, t),
    do: {r0 + (r1 - r0) * t, g0 + (g1 - g0) * t, b0 + (b1 - b0) * t, a0 + (a1 - a0) * t}

  defp project(view, {point, u, v, light, tint}) do
    {x, y, near, w} = View.project(view, point)

    case tint do
      nil -> {x, y, near, w, u * w, v * w, light, 0.0, 0.0, 0.0, 0.0}
      {r, g, b, a} -> {x, y, near, w, u * w, v * w, light, r * w, g * w, b * w, a * w}
    end
  end

  defp facing?(_projected, :none), do: true

  defp facing?(projected, cull) do
    area = signed_area(projected)

    case cull do
      :clockwise -> area < 0
      :counter_clockwise -> area > 0
    end
  end

  defp signed_area(projected) do
    projected
    |> Enum.zip(tl(projected) ++ [hd(projected)])
    |> Enum.reduce(0.0, fn {from, to}, acc ->
      acc + (elem(from, 0) * elem(to, 1) - elem(to, 0) * elem(from, 1))
    end)
  end

  defp rows(projected, height) do
    ys = Enum.map(projected, &elem(&1, 1))
    top = max(ceil(Enum.min(ys) - 0.5), 0)
    bottom = min(ceil(Enum.max(ys) - 0.5) - 1, height - 1)
    if top <= bottom, do: {:ok, {top, bottom}}, else: :error
  end

  defp edges(projected) do
    for {from, to} <- Enum.zip(projected, tl(projected) ++ [hd(projected)]),
        {x0, y0, x1, y1} = {elem(from, 0), elem(from, 1), elem(to, 0), elem(to, 1)},
        y0 != y1 do
      if y0 < y1,
        do: {y0, y1, x0, (x1 - x0) / (y1 - y0)},
        else: {y1, y0, x1, (x0 - x1) / (y0 - y1)}
    end
  end

  defp planes([first | rest], lit?, tinted?) do
    case widest(first, rest) do
      nil ->
        :error

      {second, third, det} ->
        plane = &plane(first, second, third, det, &1)

        {:ok,
         %{
           near: plane.(2),
           w: plane.(3),
           uw: plane.(4),
           vw: plane.(5),
           light: if(lit?, do: plane.(6)),
           tint: if(tinted?, do: {plane.(7), plane.(8), plane.(9), plane.(10)})
         }}
    end
  end

  defp widest(first, rest) do
    pairs =
      for {a, i} <- Enum.with_index(rest), {b, j} <- Enum.with_index(rest), j > i, do: {a, b}

    case Enum.max_by(pairs, fn {a, b} -> abs(det(first, a, b)) end, fn -> nil end) do
      nil ->
        nil

      {a, b} ->
        det = det(first, a, b)
        if abs(det) < 1.0e-6, do: nil, else: {a, b, det}
    end
  end

  defp det(first, second, third) do
    {x0, y0} = {elem(first, 0), elem(first, 1)}

    (elem(second, 0) - x0) * (elem(third, 1) - y0) -
      (elem(third, 0) - x0) * (elem(second, 1) - y0)
  end

  defp plane(first, second, third, det, index) do
    {x0, y0} = {elem(first, 0), elem(first, 1)}
    {dx1, dy1} = {elem(second, 0) - x0, elem(second, 1) - y0}
    {dx2, dy2} = {elem(third, 0) - x0, elem(third, 1) - y0}
    a0 = elem(first, index)
    da1 = elem(second, index) - a0
    da2 = elem(third, index) - a0
    per_x = (da1 * dy2 - da2 * dy1) / det
    per_y = (dx1 * da2 - dx2 * da1) / det
    {a0 - per_x * x0 - per_y * y0, per_x, per_y}
  end
end
