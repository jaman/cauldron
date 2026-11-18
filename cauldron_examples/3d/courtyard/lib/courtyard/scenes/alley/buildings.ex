defmodule Courtyard.Scenes.Alley.Buildings do
  @moduledoc """
  The alley's building fronts as parts of Poly Haven's modular facade kits, for
  `Courtyard.Kit.assemble/2`, in the alley's coordinates.

      {:ok, fronts} = Courtyard.Kit.assemble(apartments_kit, Courtyard.Scenes.Alley.Buildings.apartments())

  A front is a row of 3-metre bays along its +X, facing its +Z. Each storey is a dado
  band under a 3-metre wall with the bay's door or window; piers stand at both ends, and
  a cornice and crown run along the top. Each bay is `{ground, upper}`: what its ground
  storey and its upper storeys hold. A ground part wider than a bay is given at the
  bay it ends in, the bays it covers before that as `:spanned`.
  """

  @bay 3.0
  @wall 3.0

  @apartment_bays [
    {:plain, :large},
    {:door, :double},
    {:plain, :large},
    {:plain, :small},
    {:small_door, :fire_door},
    {:plain, :large},
    {:plain, :double},
    {:door, :large},
    {:plain, :small},
    {:offset_door, :large},
    {:plain, :double},
    {:plain, :large},
    {:door, :small},
    {:plain, :large},
    {:plain, :double},
    {:small_door, :large},
    {:plain, :small},
    {:plain, :large}
  ]

  @factory_bays [
    {:plain, :tall_large},
    {:door, :tall_small},
    {:plain, :tall_large},
    {:spanned, :tall_small},
    {:spanned, :tall_large},
    {:garage_double, :tall_small},
    {:plain, :tall_large},
    {:recessed, :tall_small},
    {:plain, :tall_large},
    {:spanned, :tall_small},
    {:garage, :tall_large},
    {:plain, :tall_small},
    {:door, :tall_large},
    {:plain, :tall_small},
    {:spanned, :tall_large},
    {:garage, :tall_small},
    {:plain, :tall_large},
    {:plain, :tall_small}
  ]

  @end_bays [{:plain, :small}, {:plain, :blank}, {:plain, :small}]

  @doc """
  The apartment block along the alley's north side, `z = -4`, with the end walls closing
  the alley at `x = ±27`; all from the `modular_urban_apartments_facade` kit.
  """
  @spec apartments() :: [Courtyard.Kit.part()]
  def apartments do
    front(apartment_kit(), @apartment_bays, 4, {-27.0, 0.0, -4.0}, 0.0) ++
      front(apartment_kit(), @end_bays, 4, {27.0, 0.0, -4.5}, -:math.pi() / 2) ++
      front(apartment_kit(), @end_bays, 4, {-27.0, 0.0, 4.5}, :math.pi() / 2)
  end

  @doc "The factory along the alley's south side, `z = 4`, from the `modular_factory_facade` kit."
  @spec factory() :: [Courtyard.Kit.part()]
  def factory, do: front(factory_kit(), @factory_bays, 3, {27.0, 0.0, 4.0}, :math.pi())

  @doc "The height of the floor of `storey` (0 for the ground) in the apartment block."
  @spec apartment_floor(non_neg_integer()) :: float()
  def apartment_floor(storey), do: storey * pitch(apartment_kit()) + apartment_kit().band

  defp apartment_kit do
    %{
      band: 0.5,
      ground: &apartment_ground/1,
      upper: &apartment_upper/2,
      piers: {"dado_pier_pedestal_01", "wall_pier_standard_01"},
      top: [{"cornice_standard_standard_01", 0.0}, {"crown_standard_standard_01", 0.2}],
      top_piers: [{"cornice_pier_standard_01", 0.0}, {"crown_pier_pedestal_01", 0.2}]
    }
  end

  defp factory_kit do
    %{
      band: 0.55,
      ground: &factory_ground/1,
      upper: &factory_upper/2,
      piers: {"dado_pier_pedestal_01", "wall_pier_standard_01"},
      top: [{"cornice01_standard_standard_01", 0.0}, {"crown_standard_standard_01", 0.15}],
      top_piers: [{"cornice01_pier_standard_01", 0.0}, {"crown_pier_pedestal_01", 0.15}]
    }
  end

  defp apartment_ground(:plain), do: {"dado_standard_standard_01", ["wall_standard_standard_01"]}

  defp apartment_ground(:door),
    do: {"dado_door_centered_large_01", ["wall_door_centered_large_01", "door_centered_large_01"]}

  defp apartment_ground(:small_door),
    do: {"dado_door_centered_small_01", ["wall_door_centered_small_01", "door_centered_small_01"]}

  defp apartment_ground(:offset_door),
    do: {"dado_door_offset_small_01", ["wall_door_offset_small_01", "door_offset_small_01"]}

  defp apartment_upper(:blank, _storey),
    do: {"dado_standard_standard_01", ["wall_standard_standard_01"]}

  defp apartment_upper(:fire_door, storey) do
    row = "0#{4 * storey - 3}"
    {"dado_door_window_small_01", ["wall_door_window_small_#{row}", "door_window_small_#{row}"]}
  end

  defp apartment_upper(window, storey) do
    kind = "centered_#{window}_0#{storey}"
    {"dado_standard_standard_01", ["wall_window_#{kind}", "window_#{kind}"]}
  end

  defp factory_ground(:plain), do: {"dado_standard_standard_01", ["wall_standard_standard_01"]}
  defp factory_ground(:spanned), do: {nil, []}

  defp factory_ground(:door),
    do: {"dado_door_centered_large_01", ["wall_door_centered_large_01", "door_centered_large_01"]}

  defp factory_ground(:recessed),
    do: {"dado_door_recessed_small_01", ["wall_door_recessed_small_01", "door_recessed_small_01"]}

  defp factory_ground(:garage),
    do: {"dado_garage_door_01", ["wall_door_garage_door_01", "door_garage_door_01"]}

  defp factory_ground(:garage_double),
    do: {"dado_garage_double_01", ["wall_door_garage_double_01", "door_garage_double_01"]}

  defp factory_upper(window, storey) do
    kind = "#{window}_0#{storey}"
    {"dado_standard_standard_01", ["wall_window_#{kind}", "window_#{kind}"]}
  end

  defp front(kit, bays, storeys, origin, yaw) do
    width = length(bays) * @bay

    bays
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {{ground, upper}, index} ->
      bay(kit, ground, upper, storeys, index * @bay)
    end)
    |> Kernel.++(piers(kit, storeys, [0.0, width]))
    |> Kernel.++(top(kit, length(bays), storeys, width))
    |> Enum.map(&placed(&1, origin, yaw))
  end

  defp bay(kit, ground, upper, storeys, x) do
    storey(kit, kit.ground.(ground), 0, x) ++
      Enum.flat_map(1..(storeys - 1)//1, &storey(kit, kit.upper.(upper, &1), &1, x))
  end

  defp storey(_kit, {nil, []}, _storey, _x), do: []

  defp storey(kit, {dado, panels}, storey, x) do
    floor = storey * pitch(kit)
    [{dado, {x, floor, 0.0}} | Enum.map(panels, &{&1, {x, floor + kit.band, 0.0}})]
  end

  defp piers(kit, storeys, positions) do
    {dado, wall} = kit.piers

    for x <- positions,
        storey <- 0..(storeys - 1),
        {name, rise} <- [{dado, 0.0}, {wall, kit.band}],
        do: {name, {x, storey * pitch(kit) + rise, 0.0}}
  end

  defp top(kit, bays, storeys, width) do
    height = storeys * pitch(kit)

    for(index <- 1..bays, {name, rise} <- kit.top, do: {name, {index * @bay, height + rise, 0.0}}) ++
      for x <- [0.0, width], {name, rise} <- kit.top_piers, do: {name, {x, height + rise, 0.0}}
  end

  defp pitch(kit), do: kit.band + @wall

  defp placed({name, {x, y, z}}, {ox, oy, oz}, yaw) do
    {cos, sin} = {:math.cos(yaw), :math.sin(yaw)}
    {name, {ox + x * cos + z * sin, oy + y, oz - x * sin + z * cos}, yaw}
  end
end
