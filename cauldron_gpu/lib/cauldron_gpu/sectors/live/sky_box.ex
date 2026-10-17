if Code.ensure_loaded?(Cauldron2D.Sectors.Map) do
  defmodule CauldronGPU.Sectors.Live.SkyBox do
    @moduledoc """
    A sky picture laid out as Doom draws its sky (`CauldronGPU.Sectors.Sky`: 1024 picture
    columns to a full turn, one picture row per 1/160 of elevation's tangent, row 100 at
    the horizon, the top and bottom rows carried on above and below), as the six faces of
    an `CauldronGPU.Environment` `{:box, faces}` sky.

        faces = CauldronGPU.Sectors.Live.SkyBox.faces(picture, colours, 1.2, 256)

    `picture` is a column-by-column `Cauldron2D.Sectors.Pictures` picture, `colours` a
    tuple of 256 RGBA binaries, `stretch` how many times taller than wide a map unit is
    drawn (heights in the renderer's frame are map heights times it), `size` each face's
    width and height in texels. Faces are filtered `:nearest`.
    """

    alias CauldronGPU.Texture

    @columns 1024
    @rows_per_tangent 160
    @horizon_row 100

    @faces [:pos_x, :neg_x, :pos_y, :neg_y, :pos_z, :neg_z]

    @doc "The six face textures, keyed as `CauldronGPU.Environment`'s box takes them."
    @spec faces(map(), tuple(), number(), pos_integer()) :: %{atom() => Texture.t()}
    def faces(picture, colours, stretch, size) do
      Map.new(@faces, fn face -> {face, face(face, picture, colours, stretch, size)} end)
    end

    defp face(face, picture, colours, stretch, size) when face in [:pos_y, :neg_y] do
      pixels =
        for j <- 0..(size - 1), i <- 0..(size - 1), into: <<>> do
          u = (i + 0.5) / size
          v = (j + 0.5) / size
          elem(colours, texel(picture, direction(face, u, v), stretch))
        end

      texture(pixels, size)
    end

    defp face(face, picture, colours, stretch, size) do
      around =
        for i <- 0..(size - 1) do
          {x, _y, z} = direction(face, (i + 0.5) / size, 0.5)
          {column(picture, x, z), :math.sqrt(x * x + z * z) * stretch}
        end

      pixels =
        for j <- 0..(size - 1), {column, across} <- around, into: <<>> do
          y = 1 - 2 * (j + 0.5) / size
          elem(colours, at(picture, column, row(picture, y / across)))
        end

      texture(pixels, size)
    end

    defp texture(pixels, size) do
      %Texture{
        width: size,
        height: size,
        pixels: pixels,
        filter: :nearest,
        wrap: :clamp,
        mipmaps: false
      }
    end

    defp direction(:pos_x, u, v), do: {1.0, 1 - 2 * v, 1 - 2 * u}
    defp direction(:neg_x, u, v), do: {-1.0, 1 - 2 * v, 2 * u - 1}
    defp direction(:pos_z, u, v), do: {2 * u - 1, 1 - 2 * v, 1.0}
    defp direction(:neg_z, u, v), do: {1 - 2 * u, 1 - 2 * v, -1.0}
    defp direction(:pos_y, u, v), do: {2 * u - 1, 1.0, 2 * v - 1}
    defp direction(:neg_y, u, v), do: {2 * u - 1, -1.0, 1 - 2 * v}

    defp texel(picture, {x, y, z}, stretch) do
      across = max(:math.sqrt(x * x + z * z), 1.0e-9)
      at(picture, column(picture, x, z), row(picture, y / (across * stretch)))
    end

    defp column(%{width: width}, x, z) do
      turn = :math.atan2(-z, x) / (2 * :math.pi())
      Integer.mod(floor((turn - Float.floor(turn)) * @columns), width)
    end

    defp row(%{height: height}, tangent),
      do: (@horizon_row - tangent * @rows_per_tangent) |> floor() |> max(0) |> min(height - 1)

    defp at(%{height: height, pixels: pixels}, column, row),
      do: :binary.at(pixels, column * height + row)
  end
end
