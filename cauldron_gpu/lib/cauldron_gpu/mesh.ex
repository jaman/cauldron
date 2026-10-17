defmodule CauldronGPU.Mesh do
  @moduledoc """
  Triangles to upload: vertices, `u32` indices and parts.

  `vertices` is a binary of 48-byte vertices, each twelve little-endian floats:
  `x, y, z, u, nx, ny, nz, v, lu, lv, s01, s23` — position, normal, texture coordinates
  `{u, v}`, lightmap coordinates `{lu, lv}`, and the vertex's four light styles as
  `s0 + 256 * s1` and `s2 + 256 * s3` (255 for none; see `CauldronGPU.Material`). `indices` is a binary of little-endian
  `u32`, three per counter-clockwise triangle. A part is `{first_index, index_count}`;
  an instance gives one material per part. No parts means one part covering every index.

  `skin`, for meshes posed with bones (`CauldronGPU.Pose`), is 8 bytes a vertex: four bone
  indices, then four weights out of 255 that sum to 255; `nil` for a rigid mesh.

  `colors`, 4 bytes a vertex (RGBA, display colour), multiplies each vertex's material base
  colour and alpha, blended across each triangle; `nil` for none.

      CauldronGPU.Mesh.cube(1.0)
      CauldronGPU.Mesh.new(vertices, [0, 1, 2], parts: [{0, 3}])
  """

  @type vertex :: %{
          required(:position) => {number(), number(), number()},
          optional(:normal) => {number(), number(), number()},
          optional(:uv) => {number(), number()},
          optional(:lightmap_uv) => {number(), number()},
          optional(:light_styles) => [0..255]
        }
  @type part :: {non_neg_integer(), non_neg_integer()}
  @type t :: %__MODULE__{
          vertices: binary(),
          indices: binary(),
          parts: [part()],
          skin: binary() | nil,
          colors: binary() | nil
        }

  @enforce_keys [:vertices, :indices]
  defstruct [:vertices, :indices, parts: [], skin: nil, colors: nil]

  @doc "A mesh from vertex maps and a flat list of indices."
  @spec new([vertex()], [non_neg_integer()], keyword()) :: t()
  def new(vertices, indices, opts \\ []) do
    %__MODULE__{
      vertices: for(vertex <- vertices, into: <<>>, do: encode_vertex(vertex)),
      indices: for(index <- indices, into: <<>>, do: <<index::little-unsigned-32>>),
      parts: Keyword.get(opts, :parts, [])
    }
  end

  @doc "The number of vertices in `mesh`."
  @spec vertex_count(t()) :: non_neg_integer()
  def vertex_count(%__MODULE__{vertices: vertices}), do: div(byte_size(vertices), 48)

  @doc "The number of indices in `mesh`."
  @spec index_count(t()) :: non_neg_integer()
  def index_count(%__MODULE__{indices: indices}), do: div(byte_size(indices), 4)

  @doc "A cube `size` across, centred on the origin, each face with its own 0..1 texture square."
  @spec cube(number()) :: t()
  def cube(size) do
    half = size / 2

    faces = [
      {{1, 0, 0}, {0, 0, -1}, {0, 1, 0}},
      {{-1, 0, 0}, {0, 0, 1}, {0, 1, 0}},
      {{0, 1, 0}, {1, 0, 0}, {0, 0, -1}},
      {{0, -1, 0}, {1, 0, 0}, {0, 0, 1}},
      {{0, 0, 1}, {1, 0, 0}, {0, 1, 0}},
      {{0, 0, -1}, {-1, 0, 0}, {0, 1, 0}}
    ]

    {vertices, indices} =
      faces
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {face, index}, {vertices, indices} ->
        {vertices ++ face_vertices(face, half), indices ++ face_indices(index * 4)}
      end)

    new(vertices, indices)
  end

  @doc "A flat square `size` across on the XZ plane facing +Y, its texture repeated `repeat` times."
  @spec plane(number(), number()) :: t()
  def plane(size, repeat \\ 1) do
    half = size / 2

    vertices =
      for {x, z, u, v} <- [
            {-half, half, 0, 0},
            {half, half, repeat, 0},
            {half, -half, repeat, repeat},
            {-half, -half, 0, repeat}
          ] do
        %{position: {x, 0, z}, normal: {0, 1, 0}, uv: {u, v}}
      end

    new(vertices, [0, 1, 2, 0, 2, 3])
  end

  @doc "A UV sphere of `radius` with `rings` bands and twice as many segments."
  @spec sphere(number(), pos_integer()) :: t()
  def sphere(radius, rings \\ 16) do
    segments = rings * 2

    vertices =
      for ring <- 0..rings, segment <- 0..segments do
        theta = ring / rings * :math.pi()
        phi = segment / segments * 2 * :math.pi()

        normal =
          {:math.sin(theta) * :math.cos(phi), :math.cos(theta),
           -:math.sin(theta) * :math.sin(phi)}

        {nx, ny, nz} = normal

        %{
          position: {nx * radius, ny * radius, nz * radius},
          normal: normal,
          uv: {segment / segments, ring / rings}
        }
      end

    indices =
      for ring <- 0..(rings - 1), segment <- 0..(segments - 1) do
        a = ring * (segments + 1) + segment
        b = a + segments + 1
        [a, b, a + 1, a + 1, b, b + 1]
      end

    new(vertices, List.flatten(indices))
  end

  defp face_vertices({normal, right, up}, half) do
    for {s, t, u, v} <- [{-1, -1, 0, 1}, {1, -1, 1, 1}, {1, 1, 1, 0}, {-1, 1, 0, 0}] do
      %{position: corner(normal, right, up, s, t, half), normal: normal, uv: {u, v}}
    end
  end

  defp face_indices(base), do: [base, base + 1, base + 2, base, base + 2, base + 3]

  defp corner({nx, ny, nz}, {rx, ry, rz}, {ux, uy, uz}, s, t, half) do
    {(nx + rx * s + ux * t) * half, (ny + ry * s + uy * t) * half, (nz + rz * s + uz * t) * half}
  end

  defp encode_vertex(vertex) do
    {x, y, z} = vertex.position
    {nx, ny, nz} = Map.get(vertex, :normal, {0, 1, 0})
    {u, v} = Map.get(vertex, :uv, {0, 0})
    {lu, lv} = Map.get(vertex, :lightmap_uv, {0, 0})

    [s0, s1, s2, s3] =
      vertex |> Map.get(:light_styles, [0]) |> Kernel.++([255, 255, 255, 255]) |> Enum.take(4)

    <<x::little-float-32, y::little-float-32, z::little-float-32, u::little-float-32,
      nx::little-float-32, ny::little-float-32, nz::little-float-32, v::little-float-32,
      lu::little-float-32, lv::little-float-32, s0 + 256 * s1::little-float-32,
      s2 + 256 * s3::little-float-32>>
  end
end
