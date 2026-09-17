defmodule Cauldron2D.Wx.Sheet do
  @moduledoc """
  A sprite sheet PNG as wx bitmaps: the sheet scaled up once with nearest-neighbour
  sampling, and a bitmap per index cut from it on first use.

      sheet = Cauldron2D.Wx.Sheet.load(index, png, 2)
      bitmap = Cauldron2D.Wx.Sheet.bitmap(sheet, 7)

  `index` is what `Cauldron2D.Net.Wire.sheet/1` gives; `png` the bytes; the scale the
  pixels a sheet pixel becomes. Needs a running wx. The cut bitmaps are kept in a
  public ETS table, so any process with the wx environment can draw from the sheet.
  """

  alias Cauldron2D.Wx.Const

  @type t :: %__MODULE__{
          tile: pos_integer(),
          scale: number(),
          frames: [{integer(), integer()}],
          anim: map(),
          image: term(),
          bitmaps: :ets.table(),
          void: {byte(), byte(), byte()}
        }

  defstruct [:tile, :scale, :frames, :image, :bitmaps, anim: %{}, void: {0, 0, 0}]

  @doc "Load the sheet, scaled `scale` times — a whole number, or a fraction such as 0.25 that leaves a tile a whole number of pixels."
  @spec load(%{tile: pos_integer(), frames: [{integer(), integer()}]}, binary(), number()) :: t()
  def load(%{tile: tile, frames: frames} = index, png, scale) do
    path =
      Path.join(System.tmp_dir!(), "cauldron_web_sheet_#{System.unique_integer([:positive])}.png")

    File.write!(path, png)
    image = :wxImage.new(path)
    File.rm(path)
    {width, height} = {:wxImage.getWidth(image), :wxImage.getHeight(image)}

    scaled =
      :wxImage.scale(image, max(1, round(width * scale)), max(1, round(height * scale)),
        quality: Const.image_quality_nearest()
      )

    :wxImage.destroy(image)

    %__MODULE__{
      tile: tile,
      scale: scale,
      frames: frames,
      anim: Map.get(index, :anim, %{}),
      image: :wxBitmap.new(scaled),
      bitmaps: :ets.new(__MODULE__, [:set, :public]),
      void: Map.get(index, :void, {0, 0, 0})
    }
  end

  @doc "The indices the sheet animates: the first index of every animated art."
  @spec animated(t()) :: MapSet.t()
  def animated(%__MODULE__{anim: anim}), do: anim |> Map.keys() |> MapSet.new()

  @doc "The bitmap for `index` as it shows at `at_ms`, following the sheet's animations."
  @spec bitmap_at(t(), non_neg_integer(), integer()) :: term() | nil
  def bitmap_at(%__MODULE__{} = sheet, index, at_ms),
    do: bitmap(sheet, Cauldron2D.Sheet.index_at(sheet, index, at_ms))

  @doc "Let the sheet's cut bitmaps go."
  @spec unload(t()) :: :ok
  def unload(%__MODULE__{bitmaps: bitmaps}) do
    :ets.delete(bitmaps)
    :ok
  end

  @doc "The bitmap for `index`, cut on first use; `nil` for an index the sheet has not got."
  @spec bitmap(t(), non_neg_integer()) :: term() | nil
  def bitmap(%__MODULE__{bitmaps: bitmaps} = sheet, index) do
    case :ets.lookup(bitmaps, index) do
      [{^index, bitmap}] ->
        bitmap

      [] ->
        case Enum.at(sheet.frames, index) do
          nil ->
            nil

          {x, y} ->
            size = pixels(sheet)

            bitmap =
              :wxBitmap.getSubBitmap(
                sheet.image,
                {round(x * sheet.scale), round(y * sheet.scale), size, size}
              )

            :ets.insert(bitmaps, {index, bitmap})
            bitmap
        end
    end
  end

  @doc "The pixel size of a tile on this sheet."
  @spec pixels(t()) :: pos_integer()
  def pixels(%__MODULE__{tile: tile, scale: scale}), do: max(1, round(tile * scale))
end
