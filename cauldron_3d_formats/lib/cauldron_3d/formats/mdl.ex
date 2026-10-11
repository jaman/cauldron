defmodule Cauldron3D.Formats.Mdl do
  @moduledoc """
  A Quake model, `.mdl`, read into a `Cauldron3D.Mesh` and what the game needs besides.

      {:ok, model} = Cauldron3D.Formats.Mdl.parse(bytes)
      model.mesh
      Cauldron3D.Formats.Mdl.pose(model, frame, time)

  `frames` is a tuple with one entry per frame number the game uses: `{:single, pose}`
  or `{:group, [{pose, until}]}`, a group cycling through its poses, each shown until
  `until` seconds into the cycle. `flags` are the model's effect flags (rocket trail,
  grenade smoke, gib blood, rotation and so on), `mins` and `maxs` its box.
  """

  alias Cauldron3D.Formats.Normals
  alias Cauldron3D.{Mesh, Texture}

  @enforce_keys [:mesh, :frames, :flags, :mins, :maxs]
  defstruct [:mesh, :frames, :flags, :mins, :maxs]

  @type t :: %__MODULE__{}

  @doc "The model in `data`."
  @spec parse(binary()) :: {:ok, t()} | {:error, :not_a_model}
  def parse(<<"IDPO", 6::little-32, rest::binary>>) do
    <<sx::little-float-32, sy::little-float-32, sz::little-float-32, ox::little-float-32,
      oy::little-float-32, oz::little-float-32, _radius::little-float-32, _eye::binary-12,
      skin_count::little-32, skin_width::little-32, skin_height::little-32,
      vertex_count::little-32, triangle_count::little-32, frame_count::little-32,
      _sync::little-32, flags::little-32, _size::little-float-32, body::binary>> = rest

    header = %{
      scale: {sx, sy, sz},
      origin: {ox, oy, oz},
      width: skin_width,
      height: skin_height,
      vertices: vertex_count
    }

    {skins, body} = skins(body, skin_count, header)
    {stverts, body} = stverts(body, vertex_count)
    {triangles, body} = triangles(body, triangle_count, stverts, skin_width)
    {frames, poses, _body} = frames(body, frame_count, header)

    {:ok,
     %__MODULE__{
       mesh: %Mesh{frames: List.to_tuple(poses), triangles: triangles, skins: skins},
       frames: List.to_tuple(frames),
       flags: flags,
       mins: {-16.0, -16.0, -16.0},
       maxs: {16.0, 16.0, 16.0}
     }}
  end

  def parse(_data), do: {:error, :not_a_model}

  @doc "The mesh pose for frame number `frame` at `time` seconds; an unknown frame is the first."
  @spec pose(t(), integer(), number()) :: non_neg_integer()
  def pose(%__MODULE__{frames: frames}, frame, time) do
    case frame >= 0 and frame < tuple_size(frames) and elem(frames, frame) do
      {:single, pose} -> pose
      {:group, poses} -> grouped(poses, time)
      _ -> first(elem(frames, 0))
    end
  end

  defp first({:single, pose}), do: pose
  defp first({:group, [{pose, _} | _]}), do: pose

  defp grouped(poses, time) do
    {_, cycle} = List.last(poses)
    at = if cycle > 0, do: :math.fmod(time, cycle), else: 0.0
    Enum.find_value(poses, elem(hd(poses), 0), fn {pose, until} -> if at < until, do: pose end)
  end

  defp skins(body, count, header), do: skins(body, count, header, [])

  defp skins(body, 0, _header, acc), do: {Enum.reverse(acc), body}

  defp skins(<<0::little-32, rest::binary>>, count, header, acc) do
    size = header.width * header.height
    <<pixels::binary-size(^size), rest::binary>> = rest
    skins(rest, count - 1, header, [Texture.new(header.width, header.height, pixels) | acc])
  end

  defp skins(<<1::little-32, group::little-32, rest::binary>>, count, header, acc) do
    size = header.width * header.height

    <<_intervals::binary-size(^group * 4), pixels::binary-size(^size * ^group), rest::binary>> =
      rest

    skins(rest, count - 1, header, [
      Texture.new(header.width, header.height, binary_part(pixels, 0, size)) | acc
    ])
  end

  defp stverts(body, count) do
    <<data::binary-size(^count * 12), rest::binary>> = body

    {for(<<seam::little-32, s::little-32, t::little-32 <- data>>, do: {seam != 0, s, t})
     |> List.to_tuple(), rest}
  end

  defp triangles(body, count, stverts, width) do
    <<data::binary-size(^count * 16), rest::binary>> = body

    triangles =
      for <<front::little-32, a::little-32, b::little-32, c::little-32 <- data>> do
        uvs = Enum.map([a, b, c], &uv(elem(stverts, &1), front != 0, width))
        {{a, b, c}, List.to_tuple(uvs)}
      end

    {triangles, rest}
  end

  defp uv({true, s, t}, false, width), do: {s + div(width, 2) + 0.5, t + 0.5}
  defp uv({_seam, s, t}, _front, _width), do: {s + 0.5, t + 0.5}

  defp frames(body, count, header), do: frames(body, count, header, [], [])

  defp frames(body, 0, _header, frames, poses),
    do: {Enum.reverse(frames), Enum.reverse(poses), body}

  defp frames(<<0::little-32, rest::binary>>, count, header, frames, poses) do
    {pose, rest} = pose(rest, header)
    frames(rest, count - 1, header, [{:single, length(poses)} | frames], [pose | poses])
  end

  defp frames(
         <<1::little-32, group::little-32, _bounds::binary-8, rest::binary>>,
         count,
         header,
         frames,
         poses
       ) do
    <<intervals::binary-size(^group * 4), rest::binary>> = rest
    untils = for <<until::little-float-32 <- intervals>>, do: until

    {group_poses, rest} =
      Enum.map_reduce(1..group, rest, fn _, acc -> pose(acc, header) end)

    first = length(poses)

    entries =
      untils |> Enum.with_index(first) |> Enum.map(fn {until, index} -> {index, until} end)

    frames(
      rest,
      count - 1,
      header,
      [{:group, entries} | frames],
      Enum.reverse(group_poses) ++ poses
    )
  end

  defp pose(<<_bounds::binary-8, _name::binary-16, rest::binary>>, header) do
    size = header.vertices * 4
    <<data::binary-size(^size), rest::binary>> = rest
    {sx, sy, sz} = header.scale
    {ox, oy, oz} = header.origin

    {vertices, normals} =
      for <<x, y, z, n <- data>> do
        {{x * sx + ox, y * sy + oy, z * sz + oz}, Normals.at(n)}
      end
      |> Enum.unzip()

    {%{vertices: List.to_tuple(vertices), normals: List.to_tuple(normals)}, rest}
  end
end
