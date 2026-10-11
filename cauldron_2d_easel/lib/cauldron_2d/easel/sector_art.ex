defmodule Cauldron2D.Easel.SectorArt do
  @moduledoc """
  Pictures for previewing a sector map with no game art: a palette of sixteen hues in
  sixteen shades, and wall, floor and ceiling textures drawn from it, as a
  `Cauldron2D.Sectors.Pictures` set with light tables.

      art = Cauldron2D.Easel.SectorArt.get()
      art.names           #=> ["wall", "brick", "metal", ...]
      Cauldron2D.Sectors.Pictures.id(art.pictures, "brick")

  The set is built the first time it is asked for and kept.
  """

  alias Cauldron2D.Sectors.{Light, Pictures}

  @key {__MODULE__, :art}
  @size 64
  @textures [
    {"wall", 1, :panels},
    {"brick", 0, :bricks},
    {"metal", 9, :rivets},
    {"wood", 2, :planks},
    {"stone", 15, :blocks},
    {"floor", 14, :tiles},
    {"ceiling", 15, :grid},
    {"grass", 5, :speckle},
    {"water", 10, :waves},
    {"lava", 0, :waves}
  ]

  @doc "The palette, the picture set and the names in it."
  @spec get() :: %{palette: binary(), pictures: Pictures.t(), names: [String.t()]}
  def get do
    case :persistent_term.get(@key, nil) do
      nil -> tap(build(), &:persistent_term.put(@key, &1))
      art -> art
    end
  end

  defp build do
    palette = palette()
    named = for {name, hue, pattern} <- @textures, do: {name, texture(hue, pattern)}

    %{
      palette: palette,
      pictures: Pictures.new(named, Light.tables(palette)),
      names: Enum.map(@textures, &elem(&1, 0))
    }
  end

  defp palette do
    for hue <- 0..15, shade <- 0..15, into: <<>> do
      {r, g, b} = colour(hue, (shade + 1) / 16)
      <<r, g, b>>
    end
  end

  defp colour(15, level), do: grey(level)

  defp colour(hue, level) do
    {r, g, b} = hue_rgb(hue / 15)
    {round(r * level * 255), round(g * level * 255), round(b * level * 255)}
  end

  defp grey(level), do: {round(level * 230), round(level * 230), round(level * 235)}

  defp hue_rgb(h) do
    sector = h * 6
    x = 1 - abs(:math.fmod(sector, 2) - 1)

    cond do
      sector < 1 -> {1.0, x, 0.0}
      sector < 2 -> {x, 1.0, 0.0}
      sector < 3 -> {0.0, 1.0, x}
      sector < 4 -> {0.0, x, 1.0}
      sector < 5 -> {x, 0.0, 1.0}
      true -> {1.0, 0.0, x}
    end
  end

  defp texture(hue, pattern) do
    rows =
      for y <- 0..(@size - 1), x <- 0..(@size - 1), into: <<>> do
        <<hue * 16 + shade(pattern, x, y)>>
      end

    Pictures.from_rows(@size, @size, rows)
  end

  defp shade(:panels, x, y),
    do:
      if(rem(x, 32) in [0, 31] or rem(y, 32) in [0, 31], do: 5, else: 10 + rem(x * 7 + y * 3, 3))

  defp shade(:bricks, x, y),
    do:
      if(rem(y, 16) == 0 or rem(x + if(rem(div(y, 16), 2) == 0, do: 0, else: 16), 32) == 0,
        do: 4,
        else: 9 + rem(x * 5 + y * 11, 4)
      )

  defp shade(:rivets, x, y),
    do: if(rem(x, 16) in [3, 4] and rem(y, 16) in [3, 4], do: 14, else: 8 + rem(x + y, 2))

  defp shade(:planks, x, y),
    do: if(rem(x, 16) == 0, do: 4, else: 8 + rem(y * 3 + div(x, 16) * 5, 5))

  defp shade(:blocks, x, y),
    do: if(rem(x, 32) == 0 or rem(y, 24) == 0, do: 5, else: 9 + rem(x * 3 + y * 7, 3))

  defp shade(:tiles, x, y),
    do: if(rem(x, 16) == 0 or rem(y, 16) == 0, do: 6, else: 10 + rem(div(x, 16) + div(y, 16), 2))

  defp shade(:grid, x, y), do: if(rem(x, 32) == 0 or rem(y, 32) == 0, do: 4, else: 8)
  defp shade(:speckle, x, y), do: 7 + rem(x * 13 + y * 7 + x * y, 6)
  defp shade(:waves, x, y), do: 8 + round(3 * :math.sin((x + 2 * :math.sin(y / 6) * 3) / 5))
end
