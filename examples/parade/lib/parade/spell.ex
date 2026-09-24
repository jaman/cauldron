defmodule Parade.Spell do
  @moduledoc """
  The four effects the courtyard can raise, and the ones burning now.

      spells = Parade.Spell.cast([], :bless, {x, y}, heading, elapsed)
      Parade.Spell.volumes(spells, elapsed, :measured)

  Each is a `Cauldron2D.Projection.Volume` the client hands to its scene: an emanation
  around the caster, a cone from them, or a burst thrown ahead. A tile is five feet, so
  a fifteen-foot emanation reaches three tiles from the edge of the caster's own square.

  `volumes/3` answers either way of marking an area out. `:measured` gives the shape
  itself, which is what a computer can do and a table cannot; `:squares` gives the whole
  tiles whose middles the shape passes over, which is how a table plays it, tinted
  evenly because a square is either in the area or out of it.

  A spell rises over a fifth of a second and fades over the last, then drops off the
  list.

  `aimed/4` gives the same area, fainter, for a caster still holding the key: the cone
  and the burst both follow where the caster faces, so they can turn until it points
  where they want it and let go.

  An emanation rises from a creature's own space and goes where that creature goes, so
  bless carries a `:follows` of whoever cast it and bane one of whoever it was cast at;
  `Cauldron2D.Projection.Volume.anchored/2` is what moves them. A cone and a burst are
  thrown and stay where they land. `tracks/1` says which of the three a spell is, and
  the game decides who a valid subject is.
  """

  alias Cauldron2D.Projection.Volume

  @feet_per_tile 5
  @rise 0.2
  @fall 0.8
  @quarter_turn :math.pi() / 2
  @aiming 0.5

  @spells [
    gale: %{
      tracks: nil,
      name: "gale blast",
      form: :cone,
      feet: 30,
      colour: {236, 244, 255},
      strength: 0.5,
      seconds: 3.0,
      tall: 2.0,
      thrown: 0
    },
    bless: %{
      tracks: :self,
      name: "bless",
      form: :emanation,
      feet: 15,
      colour: {255, 205, 96},
      strength: 0.45,
      seconds: 8.0,
      tall: 2.0,
      thrown: 0
    },
    bane: %{
      tracks: :other,
      name: "bane",
      form: :emanation,
      feet: 15,
      colour: {156, 84, 198},
      strength: 0.45,
      seconds: 8.0,
      tall: 2.0,
      thrown: 0
    },
    acid: %{
      tracks: nil,
      name: "acidic burst",
      form: :burst,
      feet: 10,
      colour: {124, 236, 96},
      strength: 0.6,
      seconds: 4.0,
      tall: 2.0,
      thrown: 15
    }
  ]

  @type kind :: atom()
  @type t :: %{
          kind: kind(),
          at: {float(), float()},
          heading: float(),
          cast_at: float(),
          follows: term()
        }

  @doc "The spells that can be cast, in the order the keys `1` to `4` raise them."
  @spec kinds() :: [kind()]
  def kinds, do: Keyword.keys(@spells)

  @doc "What a spell is called."
  @spec name(kind()) :: String.t()
  def name(kind), do: @spells |> Keyword.fetch!(kind) |> Map.fetch!(:name)

  @doc "The colour a spell tints the courtyard."
  @spec colour(kind()) :: {byte(), byte(), byte()}
  def colour(kind), do: @spells |> Keyword.fetch!(kind) |> Map.fetch!(:colour)

  @doc """
  What a spell keeps up with once it is cast: `:self` for an emanation from the
  caster's own space, `:other` for one laid on somebody else, `nil` for a cone or a
  burst, which stay where they land.
  """
  @spec tracks(kind()) :: :self | :other | nil
  def tracks(kind), do: @spells |> Keyword.fetch!(kind) |> Map.fetch!(:tracks)

  @doc "How far a spell reaches, in feet."
  @spec feet(kind()) :: pos_integer()
  def feet(kind), do: @spells |> Keyword.fetch!(kind) |> Map.fetch!(:feet)

  @doc """
  `spells` with `kind` added, raised by a caster standing at `at` and facing `heading`.

  A burst lands where the caster is looking, as far ahead as the spell can be thrown.
  """
  @spec cast([t()], kind(), {number(), number()}, number(), number(), term()) :: [t()]
  def cast(spells, kind, at, heading, elapsed, follows \\ nil) do
    spell = Keyword.fetch!(@spells, kind)

    spells ++
      [
        %{
          kind: kind,
          at: thrown(at, heading, spell),
          heading: heading,
          cast_at: elapsed,
          follows: follows
        }
      ]
  end

  defp thrown({x, y}, _heading, %{thrown: 0}), do: {x / 1, y / 1}

  defp thrown({x, y}, heading, %{thrown: feet}) do
    away = tiles(feet)
    {x + :math.cos(heading) * away, y + :math.sin(heading) * away}
  end

  @doc "The spells still burning at `elapsed` seconds into the game."
  @spec burning([t()], number()) :: [t()]
  def burning(spells, elapsed), do: Enum.filter(spells, &(age(&1, elapsed) < seconds(&1)))

  @doc """
  The spells as volumes for a scene, marked out `:measured` or in whole `:squares`.
  """
  @spec volumes([t()], number(), :measured | :squares) :: [map()]
  def volumes(spells, elapsed, marking) do
    for spell <- burning(spells, elapsed) do
      settings = Keyword.fetch!(@spells, spell.kind)

      spell
      |> measured(settings, elapsed)
      |> marked(settings, marking)
      |> tied_to(spell.follows)
    end
  end

  @doc """
  The area `kind` would cover, drawn faintly, for a caster at `at` looking along
  `heading` who has not let go yet.
  """
  @spec aimed(kind(), {number(), number()}, number(), :measured | :squares) :: map()
  def aimed(kind, at, heading, marking) do
    settings = Keyword.fetch!(@spells, kind)

    %{
      at: thrown(at, heading, settings),
      shape: shape(settings.form, settings, heading),
      colour: settings.colour,
      strength: settings.strength * @aiming
    }
    |> marked(settings, marking)
  end

  defp tied_to(volume, nil), do: volume
  defp tied_to(volume, subject), do: Map.put(volume, :follows, subject)

  defp measured(spell, settings, elapsed) do
    %{
      at: spell.at,
      shape: shape(settings.form, settings, spell.heading),
      colour: settings.colour,
      strength: settings.strength * envelope(settings, age(spell, elapsed))
    }
  end

  defp shape(:emanation, settings, _heading), do: {:sphere, tiles(settings.feet) + 0.5, 0.0}

  defp shape(:cone, settings, heading),
    do: {:cone, tiles(settings.feet), @quarter_turn, heading, settings.tall}

  defp shape(:burst, settings, _heading) do
    radius = tiles(settings.feet)
    {:sphere, radius, radius * 0.6}
  end

  defp marked(volume, _settings, :measured), do: volume

  defp marked(volume, settings, :squares) do
    measured = Volume.new(volume)
    {x, y} = measured.at
    {corner_x, corner_y} = {floor(x), floor(y)}
    reach = ceil(Volume.reach(measured)) + 1

    tiles =
      for tile_x <- (corner_x - reach)..(corner_x + reach)//1,
          tile_y <- (corner_y - reach)..(corner_y + reach)//1,
          covers?(measured, {tile_x, tile_y}),
          into: MapSet.new(),
          do: {tile_x - corner_x, tile_y - corner_y}

    %{
      volume
      | at: {corner_x / 1, corner_y / 1},
        shape: {:cells, tiles, settings.tall}
    }
    |> Map.put(:falloff, :flat)
  end

  defp covers?(volume, {tile_x, tile_y}) do
    Volume.through(volume, {tile_x + 0.5, tile_y + 0.5, 0.0}, {0.0, 0.0, 1.0}, :infinity) > 0.0
  end

  defp envelope(settings, age) do
    rising = min(1.0, age / @rise)
    falling = min(1.0, (settings.seconds - age) / @fall)
    rising |> min(falling) |> max(0.0)
  end

  defp age(spell, elapsed), do: elapsed - spell.cast_at

  defp seconds(spell), do: @spells |> Keyword.fetch!(spell.kind) |> Map.fetch!(:seconds)

  defp tiles(feet), do: feet / @feet_per_tile
end
