defmodule Cauldron2D.Net.Sheet do
  @moduledoc """
  A `Cauldron2D.Atlas` as one PNG sprite sheet and an index a browser draws from,
  packed by `Cauldron2D.Sheet`.

      sheet = Cauldron2D.Net.Sheet.build(atlas)
      Cauldron2D.Net.Sheet.index(sheet, "/atlas.png")

  `cached/1` keeps the sheet of an installed atlas and rebuilds it when a different
  atlas is installed under the name.
  """

  alias Cauldron2D.Atlas
  alias FrenchCurve.{Png, Raster}

  @type t :: %{
          tile: pos_integer(),
          arts: %{term() => pos_integer()},
          frames: [[non_neg_integer()]],
          anim: %{pos_integer() => %{indices: [pos_integer()], fps: pos_integer()}},
          png: binary(),
          columns: pos_integer(),
          rows: pos_integer(),
          void: String.t()
        }

  @doc "Lay every art of `atlas` out on one sheet."
  @spec build(Atlas.t() | Atlas.name()) :: t()
  def build(atlas) do
    packed = Cauldron2D.Sheet.pack(atlas)
    {width, height} = Cauldron2D.Sheet.dimensions(packed)
    {r, g, b} = packed.void

    packed
    |> Map.delete(:raster)
    |> Map.put(:png, Png.encode(width, height, Raster.to_rgba_binary(packed.raster)))
    |> Map.put(:void, "#" <> Base.encode16(<<r, g, b>>, case: :lower))
  end

  @doc "The sheet for the installed atlas `name`, built on first use and again when the atlas changes."
  @spec cached(Atlas.name()) :: t()
  def cached(name) when is_atom(name) do
    atlas = Atlas.fetch(name)

    case :persistent_term.get({__MODULE__, name}, nil) do
      {^atlas, sheet} ->
        sheet

      _stale ->
        sheet = build(atlas)
        :persistent_term.put({__MODULE__, name}, {atlas, sheet})
        sheet
    end
  end

  @doc "The sheet's pixel size."
  @spec dimensions(t()) :: {pos_integer(), pos_integer()}
  def dimensions(sheet), do: Cauldron2D.Sheet.dimensions(sheet)

  @doc "What a client needs to draw from the sheet at `url`, as `Cauldron2D.Sheet.index/2` gives it."
  @spec index(t(), String.t()) :: map()
  def index(sheet, url) do
    void = sheet.void
    packed = %{sheet | void: rgb(void)}
    Cauldron2D.Sheet.index(packed, url)
  end

  defp rgb("#" <> hex),
    do: hex |> Base.decode16!(case: :lower) |> then(fn <<r, g, b>> -> {r, g, b} end)
end
