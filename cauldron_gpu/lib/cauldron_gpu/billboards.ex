defmodule CauldronGPU.Billboards do
  @moduledoc """
  Flat pictures turned to face the camera — sprites, particles, beams seen side on — as
  one mesh, rebuilt each tick and put under the same mesh id.

      {mesh, keys} = CauldronGPU.Billboards.mesh(boards, camera)
      materials = Enum.map(keys, &Map.fetch!(materials_by_key, &1))
      [{:mesh, handle.id, mesh}, {:instance, 7, %CauldronGPU.Instance{mesh: handle, materials: materials, shadows: false}}]

  A board is a map:

    * `:at` — `{x, y, z}` in the renderer's frame (+Y up), the board's anchor point
    * `:size` — `{width, height}` in the same units
    * `:key` — what the board is drawn with; boards sharing a key share a mesh part, and
      `mesh/2` answers the keys in part order so the caller can give one material each
    * `:uv` — `{u0, v0, u1, v1}`, the part of the texture shown, `u0` on the left and `v0`
      at the top. Default `{0.0, 0.0, 1.0, 1.0}`; `u0 > u1` mirrors the picture
    * `:anchor` — `:centre` (default), the board centred on `:at`; or `:bottom`, its
      bottom edge centred on `:at`
    * `:upright` — `true` keeps the board's up along +Y, turning it only about the vertical
      (a standing sprite); `false` (default) faces the camera fully
    * `:color` — `{r, g, b, a}` bytes the board's material colour is multiplied by
      (`CauldronGPU.Mesh`'s `colors`); when no board has one the mesh has no colours
    * `:offset` — `{right, up}`, where the anchor sits on the board from its centre or
      bottom, in the board's own units. Default `{0.0, 0.0}`

  The mesh is `nil` when there are no boards.
  """

  alias CauldronGPU.{Camera, Mesh, Quat}

  @type board :: %{
          required(:at) => {number(), number(), number()},
          required(:size) => {number(), number()},
          required(:key) => term(),
          optional(:uv) => {number(), number(), number(), number()},
          optional(:anchor) => :centre | :bottom,
          optional(:upright) => boolean(),
          optional(:offset) => {number(), number()},
          optional(:color) => {byte(), byte(), byte(), byte()}
        }

  @doc "The boards as one mesh facing `camera`, with one part per key, and the keys in part order."
  @spec mesh([board()], Camera.t()) :: {Mesh.t() | nil, [term()]}
  def mesh([], _camera), do: {nil, []}

  def mesh(boards, %Camera{rotation: rotation}) do
    right = Quat.rotate(rotation, {1.0, 0.0, 0.0})
    up = Quat.rotate(rotation, {0.0, 1.0, 0.0})
    toward = Quat.rotate(rotation, {0.0, 0.0, 1.0})
    groups = boards |> Enum.group_by(& &1.key) |> Enum.to_list()

    {vertices, indices, parts, _count} =
      Enum.reduce(groups, {[], [], [], 0}, fn {_key, group}, {vertices, indices, parts, count} ->
        first = div(IO.iodata_length(indices), 4)
        quad_vertices = Enum.map(group, &quad(&1, {right, up, toward}))
        quad_indices = for n <- 0..(length(group) - 1), do: corners(count + 4 * n)
        added = length(group) * 6

        {[vertices | quad_vertices], [indices | quad_indices], [{first, added} | parts],
         count + 4 * length(group)}
      end)

    mesh = %Mesh{
      vertices: IO.iodata_to_binary(vertices),
      indices: IO.iodata_to_binary(indices),
      parts: Enum.reverse(parts),
      colors: colors(groups)
    }

    {mesh, Enum.map(groups, &elem(&1, 0))}
  end

  defp colors(groups) do
    boards = Enum.flat_map(groups, &elem(&1, 1))

    if Enum.any?(boards, &Map.has_key?(&1, :color)),
      do:
        for(
          board <- boards,
          {r, g, b, a} = Map.get(board, :color, {255, 255, 255, 255}),
          _corner <- 1..4,
          into: <<>>,
          do: <<r, g, b, a>>
        )
  end

  defp quad(board, {camera_right, camera_up, toward}) do
    {width, height} = board.size
    {u0, v0, u1, v1} = Map.get(board, :uv, {0.0, 0.0, 1.0, 1.0})
    {offset_right, offset_up} = Map.get(board, :offset, {0.0, 0.0})
    {right, up, normal} = axes(Map.get(board, :upright, false), camera_right, camera_up, toward)
    lift = if Map.get(board, :anchor, :centre) == :bottom, do: height / 2, else: 0.0

    centre =
      board.at
      |> add(scale(right, -offset_right))
      |> add(scale(up, lift - offset_up))

    half_right = scale(right, width / 2)
    half_up = scale(up, height / 2)

    corners = [
      {sub(sub(centre, half_right), half_up), {u0, v1}},
      {sub(add(centre, half_right), half_up), {u1, v1}},
      {add(add(centre, half_right), half_up), {u1, v0}},
      {add(sub(centre, half_right), half_up), {u0, v0}}
    ]

    Enum.map(corners, fn {position, uv} -> vertex(position, normal, uv) end)
  end

  defp axes(false, right, up, toward), do: {right, up, toward}

  defp axes(true, {rx, _ry, rz}, _up, _toward) do
    length = :math.sqrt(rx * rx + rz * rz)

    right = if length < 1.0e-6, do: {1.0, 0.0, 0.0}, else: {rx / length, 0.0, rz / length}
    {x, _y, z} = right
    {right, {0.0, 1.0, 0.0}, {-z, 0.0, x}}
  end

  defp corners(base),
    do: for(index <- [0, 1, 2, 0, 2, 3], into: <<>>, do: <<base + index::little-unsigned-32>>)

  defp vertex({x, y, z}, {nx, ny, nz}, {u, v}) do
    <<x::little-float-32, y::little-float-32, z::little-float-32, u::little-float-32,
      nx::little-float-32, ny::little-float-32, nz::little-float-32, v::little-float-32,
      0.0::little-float-32, 0.0::little-float-32, 65_535.0::little-float-32,
      65_535.0::little-float-32>>
  end

  defp add({ax, ay, az}, {bx, by, bz}), do: {ax + bx, ay + by, az + bz}
  defp sub({ax, ay, az}, {bx, by, bz}), do: {ax - bx, ay - by, az - bz}
  defp scale({x, y, z}, factor), do: {x * factor, y * factor, z * factor}
end
