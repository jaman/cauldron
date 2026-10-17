if Code.ensure_loaded?(Cauldron2D.Sectors.Map) do
  defmodule CauldronGPU.Sectors.Sky do
    @moduledoc """
    A sky picture wrapped round the inside of a cylinder, as
    `CauldronGPU.Sectors.Surfaces` surfaces keyed `:sky`, laid out as Doom draws its sky:
    1024 picture columns to a full turn, one picture row per 1/160 radian of elevation,
    row 100 at the horizon. Above and below the picture the cylinder continues in its top
    and bottom rows and is closed by caps.

        CauldronGPU.Sectors.Sky.surfaces({x, y, z}, radius, {256, 128})
    """

    alias CauldronGPU.Sectors.Surfaces

    @segments 64

    @doc "The sky cylinder around map point `centre` with `radius`, for a picture of `size`."
    @spec surfaces(Surfaces.vec3(), number(), {pos_integer(), pos_integer()}) ::
            [Surfaces.surface()]
    def surfaces(centre, radius, {width, height}) do
      top_row = 0.5 / height
      bottom_row = (height - 0.5) / height
      top = elevation(0.5, radius)
      bottom = elevation(height - 0.5, radius)
      cap = 2.0 * radius
      repeats = 1024 / width

      Enum.flat_map(0..(@segments - 1), fn segment ->
        turn = {segment / @segments, (segment + 1) / @segments}

        [
          band(centre, radius, turn, repeats, {top, top_row}, {cap, top_row}),
          band(centre, radius, turn, repeats, {bottom, bottom_row}, {top, top_row}),
          band(centre, radius, turn, repeats, {-cap, bottom_row}, {bottom, bottom_row}),
          cap(centre, radius, turn, repeats, cap, top_row),
          cap(centre, radius, turn, repeats, -cap, bottom_row)
        ]
      end)
    end

    defp elevation(row, radius), do: (100 - row) * radius / 160

    defp band(centre, radius, {from, to}, repeats, {low, low_v}, {high, high_v}) do
      corners = [
        corner(centre, radius, to, low, repeats, low_v),
        corner(centre, radius, from, low, repeats, low_v),
        corner(centre, radius, from, high, repeats, high_v),
        corner(centre, radius, to, high, repeats, high_v)
      ]

      {:sky, corners}
    end

    defp cap({cx, cy, cz} = centre, radius, {from, to}, repeats, height, v) do
      middle = {{cx, cy, cz + height}, {0.0, 0.0, 0.0}, {(from + to) / 2 * repeats, v}, 255}

      {:sky,
       [
         corner(centre, radius, from, height, repeats, v),
         corner(centre, radius, to, height, repeats, v),
         middle
       ]}
    end

    defp corner({cx, cy, cz}, radius, turn, height, repeats, v) do
      angle = turn * 2 * :math.pi()
      {dx, dy} = {:math.cos(angle), :math.sin(angle)}

      {{cx + dx * radius, cy + dy * radius, cz + height}, {-dx, -dy, 0.0}, {turn * repeats, v},
       255}
    end
  end
end
