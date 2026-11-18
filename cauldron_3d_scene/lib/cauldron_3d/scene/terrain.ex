defmodule Cauldron3D.Scene.Terrain do
  @moduledoc """
  The mesh of a square of ground from a grid of heights.

      mesh = Cauldron3D.Scene.Terrain.mesh(64, 64.0, fn across, along -> heights[{across, along}] end, step: 2, skirt: 3.0)

  The square is `size` across with `samples` steps a side; `height` gives the ground's
  height at a sample, and is also asked one sample outside the square on every side, for
  the slope at the edges. The mesh lies from `{0, 0}` to `{size, size}` on X and Z with
  heights on Y, and each grid square is two triangles split from its `{x + 1, z}` corner
  to its `{x, z + 1}` corner.

  Options:

    * `:step` — use every `step`th sample (default 1); `samples` must divide by it
    * `:skirt` — hang a wall this far down from the square's edges, to hide the gaps
      between squares drawn at different steps (default 0, none)
    * `:kinds` — a function of a sample giving four amounts `{a, b, c, d}`, 0 to 255,
      stored as the vertices' colours for a material's layers
      (`Cauldron3D.Scene.Material`)
  """

  alias Cauldron3D.Scene.Mesh

  @type sampler :: (integer(), integer() -> number())

  @doc "The mesh of a square `size` across with `samples` steps a side."
  @spec mesh(pos_integer(), number(), sampler(), keyword()) :: Mesh.t()
  def mesh(samples, size, height, opts \\ []) do
    step = Keyword.get(opts, :step, 1)
    skirt = Keyword.get(opts, :skirt, 0)
    kinds = Keyword.get(opts, :kinds)
    side = div(samples, step)
    spacing = size / samples

    top =
      for along <- 0..side,
          across <- 0..side,
          do: corner(across * step, along * step, spacing, height, size)

    hem = if skirt > 0, do: hem(side, step, spacing, height, size, skirt), else: []
    points = top ++ hem

    %Mesh{
      vertices: for(point <- points, into: <<>>, do: vertex(point)),
      indices:
        for(
          index <- squares(side) ++ walls(side, skirt),
          into: <<>>,
          do: <<index::little-unsigned-32>>
        ),
      colors: colours(points, kinds)
    }
  end

  defp corner(across, along, spacing, height, size) do
    here = height.(across, along)
    rise_x = (height.(across + 1, along) - height.(across - 1, along)) / (2 * spacing)
    rise_z = (height.(across, along + 1) - height.(across, along - 1)) / (2 * spacing)
    length = :math.sqrt(rise_x * rise_x + 1.0 + rise_z * rise_z)

    %{
      sample: {across, along},
      position: {across * spacing, here, along * spacing},
      normal: {-rise_x / length, 1.0 / length, -rise_z / length},
      uv: {across * spacing / size, along * spacing / size}
    }
  end

  defp hem(side, step, spacing, height, size, skirt) do
    for {across, along} <- rim(side) do
      point = corner(across * step, along * step, spacing, height, size)
      {x, y, z} = point.position
      %{point | position: {x, y - skirt, z}}
    end
  end

  defp rim(side) do
    Enum.map(0..side, &{&1, 0}) ++
      Enum.map(0..side, &{side, &1}) ++
      Enum.map(side..0//-1, &{&1, side}) ++ Enum.map(side..0//-1, &{0, &1})
  end

  defp squares(side) do
    for along <- 0..(side - 1)//1, across <- 0..(side - 1)//1 do
      low = along * (side + 1) + across
      [low, low + side + 1, low + 1, low + 1, low + side + 1, low + side + 2]
    end
    |> List.flatten()
  end

  defp walls(_side, skirt) when skirt <= 0, do: []

  defp walls(side, _skirt) do
    first_hem = (side + 1) * (side + 1)
    tops = Enum.map(rim(side), fn {across, along} -> along * (side + 1) + across end)

    tops
    |> Enum.with_index(first_hem)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [{top, hem}, {next_top, next_hem}] ->
      [top, next_top, hem, hem, next_top, next_hem]
    end)
  end

  defp vertex(%{position: {x, y, z}, normal: {nx, ny, nz}, uv: {u, v}}) do
    <<x::little-float-32, y::little-float-32, z::little-float-32, u::little-float-32,
      nx::little-float-32, ny::little-float-32, nz::little-float-32, v::little-float-32,
      0.0::little-float-32, 0.0::little-float-32, 65_280.0::little-float-32,
      65_535.0::little-float-32>>
  end

  defp colours(_points, nil), do: nil

  defp colours(points, kinds) do
    for %{sample: {across, along}} <- points, into: <<>> do
      {first, second, third, fourth} = kinds.(across, along)
      <<first, second, third, fourth>>
    end
  end
end
