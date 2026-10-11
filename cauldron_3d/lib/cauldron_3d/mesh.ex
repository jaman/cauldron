defmodule Cauldron3D.Mesh do
  @moduledoc """
  A model made of textured triangles, posed by keyframes.

    * `frames` — a tuple of `%{vertices: tuple of Vec, normals: tuple of Vec}`, every
      frame with the same vertices in the same order
    * `triangles` — a list of `{{i0, i1, i2}, {uv0, uv1, uv2}}`: three vertex indices and
      where each corner lies on the skin, in its pixels
    * `skins` — a list of `Cauldron3D.Texture`

  The model's own axes are `x` forward, `y` left and `z` up; placed in the world it is
  turned by `yaw`, `pitch` and `roll` as `Cauldron3D.Camera` turns.

      Cauldron3D.Mesh.polygons(mesh, frame: 3, origin: {64.0, 0.0, 24.0}, yaw: 1.2)
  """

  alias Cauldron3D.{Camera, Polygon, Texture, Vec}

  @type frame :: %{vertices: tuple(), normals: tuple()}
  @type t :: %__MODULE__{
          frames: tuple(),
          triangles: [{{non_neg_integer(), non_neg_integer(), non_neg_integer()}, tuple()}],
          skins: [Texture.t()]
        }

  defstruct frames: {}, triangles: [], skins: []

  @doc """
  The mesh's triangles as polygons in the world.

  ## Options

    * `:frame` — the frame index, or `{from, to, t}` to blend `t` of the way between two
      frames; default 0
    * `:origin`, `:yaw`, `:pitch`, `:roll` — where it stands and how it is turned
    * `:scale` — a number, default 1.0
    * `:skin` — the skin index, default 0
    * `:light` — a number (0 to 255) for even light, or `{ambient, directional, toward}`:
      each vertex lit `ambient` plus `directional` times how squarely its normal faces
      the direction `toward`; default 128
    * `:cull`, `:clear`, `:depth` — as `Cauldron3D.Polygon`'s, default `:none`, `nil`
      and `:test`
  """
  @spec polygons(t(), keyword()) :: [Polygon.t()]
  def polygons(%__MODULE__{} = mesh, opts \\ []) do
    {vertices, normals} = pose(mesh, Keyword.get(opts, :frame, 0))
    place = placer(opts)
    turn = turner(opts)
    world = vertices |> Tuple.to_list() |> Enum.map(place) |> List.to_tuple()
    lights = lights(normals, turn, Keyword.get(opts, :light, 128))
    skin = Enum.at(mesh.skins, Keyword.get(opts, :skin, 0)) || hd(mesh.skins)
    cull = Keyword.get(opts, :cull, :none)
    clear = Keyword.get(opts, :clear)
    depth = Keyword.get(opts, :depth, :test)

    for {{i0, i1, i2}, {uv0, uv1, uv2}} <- mesh.triangles do
      %Polygon{
        points: [elem(world, i0), elem(world, i1), elem(world, i2)],
        uvs: [uv0, uv1, uv2],
        lights: [elem(lights, i0), elem(lights, i1), elem(lights, i2)],
        paint: {:shaded, skin},
        cull: cull,
        clear: clear,
        depth: depth
      }
    end
  end

  defp pose(mesh, {from, to, t}) do
    a = elem(mesh.frames, from)
    b = elem(mesh.frames, to)
    {blend(a.vertices, b.vertices, t), blend(a.normals, b.normals, t)}
  end

  defp pose(mesh, index) do
    frame = elem(mesh.frames, index)
    {frame.vertices, frame.normals}
  end

  defp blend(a, b, t) do
    Enum.zip_with(Tuple.to_list(a), Tuple.to_list(b), &Vec.lerp(&1, &2, t)) |> List.to_tuple()
  end

  defp placer(opts) do
    origin = Vec.float(Keyword.get(opts, :origin, {0.0, 0.0, 0.0}))
    scale = Keyword.get(opts, :scale, 1.0)
    turn = turner(opts)
    fn point -> point |> Vec.scale(scale) |> turn.() |> Vec.add(origin) end
  end

  defp turner(opts) do
    {forward, right, up} =
      Camera.basis(%Camera{
        yaw: Keyword.get(opts, :yaw, 0.0) / 1,
        pitch: Keyword.get(opts, :pitch, 0.0) / 1,
        roll: Keyword.get(opts, :roll, 0.0) / 1
      })

    left = Vec.scale(right, -1.0)
    fn {x, y, z} -> forward |> Vec.scale(x) |> Vec.madd(left, y) |> Vec.madd(up, z) end
  end

  defp lights(normals, _turn, light) when is_number(light),
    do: List.to_tuple(List.duplicate(light / 1, tuple_size(normals)))

  defp lights(normals, turn, {ambient, directional, toward}) do
    toward = Vec.normalize(toward)

    normals
    |> Tuple.to_list()
    |> Enum.map(fn normal -> ambient + directional * max(Vec.dot(turn.(normal), toward), 0.0) end)
    |> List.to_tuple()
  end
end
