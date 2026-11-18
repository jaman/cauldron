defmodule Cauldron3D.Scene.Scatter do
  @moduledoc """
  Many places for one mesh. An instance given a scatter (`Cauldron3D.Scene.Instance`)
  draws its mesh once at every place, in a single draw: a wood, a field of grass, a
  scree of rocks.

  `placements` holds 32 bytes a place, little-endian 32-bit floats: the position
  `x y z`, a scale, and a rotation quaternion `x y z w`, in the instance's own space.
  `centre` and `radius` are a sphere holding every position, which the renderer culls
  by.

      scatter = Cauldron3D.Scene.Scatter.upright([{{4.0, 0.0, 2.0}, 1.2, 0.7}, {{9.5, 0.3, 6.0}, 0.9, 2.1}])
      handle = CauldronGPU.scatter(gpu, scatter)
      {:instance, 7, %Cauldron3D.Scene.Instance{mesh: pine, materials: [bark, needles], scatter: handle}}
  """

  @type vec :: {number(), number(), number()}
  @type quat :: {number(), number(), number(), number()}
  @type t :: %__MODULE__{
          placements: binary(),
          count: non_neg_integer(),
          centre: vec(),
          radius: float()
        }

  @enforce_keys [:placements, :count, :centre, :radius]
  defstruct [:placements, :count, :centre, :radius]

  @doc "A scatter of `places`, each `{position, scale, rotation}` with `rotation` a quaternion."
  @spec new([{vec(), number(), quat()}]) :: t()
  def new(places) do
    {centre, radius} = bounds(Enum.map(places, &elem(&1, 0)))

    %__MODULE__{
      placements: for(place <- places, into: <<>>, do: packed(place)),
      count: length(places),
      centre: centre,
      radius: radius
    }
  end

  @doc "A scatter of `places`, each `{position, scale, turn}` with `turn` radians about the upright axis."
  @spec upright([{vec(), number(), number()}]) :: t()
  def upright(places) do
    places
    |> Enum.map(fn {position, scale, turn} ->
      {position, scale, {0.0, :math.sin(turn / 2), 0.0, :math.cos(turn / 2)}}
    end)
    |> new()
  end

  defp packed({{x, y, z}, scale, {qx, qy, qz, qw}}) do
    for value <- [x, y, z, scale, qx, qy, qz, qw], into: <<>>, do: <<value::little-float-32>>
  end

  defp bounds([]), do: {{0.0, 0.0, 0.0}, 0.0}

  defp bounds(positions) do
    {low, high} =
      Enum.reduce(positions, {hd(positions), hd(positions)}, fn {x, y, z},
                                                                {{lx, ly, lz}, {hx, hy, hz}} ->
        {{min(lx, x), min(ly, y), min(lz, z)}, {max(hx, x), max(hy, y), max(hz, z)}}
      end)

    {lx, ly, lz} = low
    {hx, hy, hz} = high
    centre = {(lx + hx) / 2, (ly + hy) / 2, (lz + hz) / 2}
    {cx, cy, cz} = centre
    {centre, :math.sqrt((hx - cx) * (hx - cx) + (hy - cy) * (hy - cy) + (hz - cz) * (hz - cz))}
  end
end
