defmodule Cauldron2D.Projection.GroundTest do
  @moduledoc """
  The ground plane sampler answers the same bytes whether the NIF did the work or Elixir
  did, over a spread of headings, pitches and cameras.
  """

  use ExUnit.Case, async: true

  alias Cauldron2D.Projection.Ground

  @tile 8
  @void {14, 14, 20}
  @levels 6

  defp textures do
    grass = :binary.copy(<<40, 160, 40, 255>>, @tile * @tile)
    dirt = :binary.copy(<<120, 90, 60, 255>>, @tile * @tile)
    checks = for i <- 0..(@tile * @tile - 1), into: <<>>, do: <<i, 255 - i, 128, 255>>
    grass <> dirt <> checks
  end

  defp cell({x, y}) do
    case Integer.mod(x * 3 + y * 5, 7) do
      0 -> :void
      1 -> {:grass, [], nil}
      2 -> {:dirt, [], nil}
      3 -> {:checks, [], nil}
      _ -> {:grass, [], nil}
    end
  end

  defp grid do
    arts = %{grass: 1, dirt: 2, checks: 3}
    {cells, bounds} = Ground.build_grid(&cell/1, {-30, -30, 30, 30}, arts)
    %{cells: cells, bounds: bounds, textures: textures()}
  end

  defp sky(height),
    do: List.to_tuple(for(y <- 0..(height - 1)//1, do: <<y, 40, 90, 255>>))

  defp camera(heading, pitch, {width, height}) do
    fov = 70 * :math.pi() / 180
    projection = width / 2 / :math.tan(fov / 2)

    {5.37, 8.61, :math.cos(heading), :math.sin(heading), -:math.sin(heading), :math.cos(heading),
     height / 2 + pitch * height / 2, projection, projection, 1.6, 24.0}
  end

  defp spec(heading, pitch, size) do
    %{
      grid: grid(),
      size: size,
      tile: @tile,
      camera: camera(heading, pitch, size),
      void: @void,
      levels: @levels,
      sky: sky(elem(size, 1))
    }
  end

  test "the NIF is loaded" do
    assert Ground.available?(), "the plane NIF did not build or load"
  end

  test "the NIF and Elixir answer the same bytes where a tile is one colour" do
    size = {96, 64}

    one_colour =
      for shade <- [40, 120, 200],
          into: <<>>,
          do: :binary.copy(<<shade, 160, 40, 255>>, @tile * @tile)

    flat = %{grid: %{grid() | textures: one_colour}}

    for heading <- [0.0, 0.7, 1.5708, 2.9, -1.2, 4.6], pitch <- [-0.6, 0.0, 0.35] do
      spec = Map.merge(spec(heading, pitch, size), flat)

      assert Ground.rows(spec) == Ground.rows(Map.put(spec, :native, false)),
             "heading #{heading}, pitch #{pitch} differ between the NIF and Elixir"
    end
  end

  test "over a detailed tile they differ only at a texel boundary, by one level" do
    {width, height} = size = {96, 64}

    for heading <- [0.0, 0.7, 1.5708, 2.9, -1.2, 4.6], pitch <- [-0.6, 0.0, 0.35] do
      spec = spec(heading, pitch, size)
      native = Ground.rows(spec)
      elixir = Ground.rows(Map.put(spec, :native, false))

      gaps =
        for y <- 0..(height - 1)//1,
            x <- 0..(width - 1)//1,
            a = binary_part(Map.fetch!(native, y), x * 4, 4),
            b = binary_part(Map.fetch!(elixir, y), x * 4, 4),
            a != b,
            do: channel_gap(a, b)

      where = "heading #{heading}, pitch #{pitch}"
      assert Enum.all?(gaps, &(&1 <= 1)), "#{where}: a channel differs by more than one"

      assert length(gaps) <= div(width * height, 500),
             "#{where}: #{length(gaps)} pixels differ, more than a texel boundary explains"
    end
  end

  defp channel_gap(<<ar, ag, ab, _>>, <<br, bg, bb, _>>),
    do: Enum.max([abs(ar - br), abs(ag - bg), abs(ab - bb)])

  test "a grid answers the void beyond its bounds and for a cell it has no art for" do
    {cells, bounds} = Ground.build_grid(&cell/1, {0, 0, 2, 2}, %{grass: 1})
    assert bounds == {3, 3, 0, 0}
    assert byte_size(cells) == 3 * 3 * 2

    indices = for <<index::unsigned-integer-size(16) <- cells>>, do: index
    assert 0 in indices
    assert 1 in indices
    refute 2 in indices
  end
end
