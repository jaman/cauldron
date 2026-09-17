defmodule Cauldron2D.Easel.Drafter.ActualSize do
  @moduledoc """
  The picture being edited as an installed atlas of one art, `:art`, so a
  `Cauldron2D.Drafter.Surface` draws it the way a game does: at its own size through the
  terminal's graphics, its frames in turn at its rate, or as its glyph where the terminal
  has no graphics.

      actual = ActualSize.new()
      actual = ActualSize.sync(actual, easel, Project.entry(project, name))

      {:cauldron_surface, [atlas: actual.name, focus: {0, 0}, cell: ActualSize.cell(false)]}

  The atlas's tile is the longer side of the picture; a picture that is not square is
  padded with transparency to the right and below. `sync/3` installs again only when the
  picture, its palette, its rate or its glyph changed since the last call.
  """

  alias Cauldron2D.{Atlas, Easel, Surface}

  @type t :: %__MODULE__{name: Atlas.name(), fingerprint: term()}

  @enforce_keys [:name]
  defstruct [:name, fingerprint: nil]

  @doc "A holder for an atlas under a name of its own; nothing is installed until `sync/3`."
  @spec new() :: t()
  def new, do: %__MODULE__{name: :"easel_actual_#{System.unique_integer([:positive])}"}

  @doc "Install `easel` as the atlas's `:art`, with `entry`'s `:glyph` and `:color`, unless it already is."
  @spec sync(t(), Easel.t(), map()) :: t()
  def sync(%__MODULE__{} = actual, %Easel{} = easel, entry) do
    fingerprint = :erlang.phash2({easel.frames, easel.palette, easel.fps, entry})

    if fingerprint == actual.fingerprint,
      do: actual,
      else: %{actual | fingerprint: fingerprint, name: install(actual.name, easel, entry)}
  end

  @doc "The `:cell` a surface calls: `:art` at the origin only, or at every tile when `tiled`."
  @spec cell(boolean()) :: (Cauldron2D.Camera.point() -> Surface.cell())
  def cell(true), do: fn _point -> {:art, [], nil} end
  def cell(false), do: fn point -> if point == {0, 0}, do: {:art, [], nil}, else: :void end

  defp install(name, easel, entry) do
    tile = max(easel.width, easel.height)

    frames =
      for raster <- Easel.rasters(easel),
          do: Linocut.transform(raster, {tile, tile}, &Function.identity/1)

    name
    |> Atlas.new(tile: tile)
    |> Atlas.put(:art, frames, Map.to_list(Map.take(entry, [:glyph, :color])) ++ [fps: easel.fps])
    |> Atlas.install()
  end
end
