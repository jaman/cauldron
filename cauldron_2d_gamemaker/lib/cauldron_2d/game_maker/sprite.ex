defmodule Cauldron2D.GameMaker.Sprite do
  @moduledoc """
  A sprite (a `SPRT` entry): frames of a picture, the point it is drawn from, and the
  masks it collides with.

    * `size` is `{width, height}`; every frame is a `Cauldron2D.GameMaker.Region` whose
      `bounds` are that size
    * `origin` is `{x, y}`, the pixel placed at an instance's position
    * `box` is the collision box `{left, top, right, bottom}`, inclusive, in the
      picture's pixels; `box_mode` says how it was chosen (`0` automatic, `1` the whole
      picture, `2` set by hand)
    * `masks` holds one `Cauldron2D.Mask` per frame when `separate_masks` is set,
      otherwise one for every frame; `mask/2` gives a frame's
    * `speed` is `{rate, :per_second | :per_frame}`, the animation's playback; GameMaker
      Studio 1 files carry none and are `{1.0, :per_frame}`
    * `kind` is `:bitmap`, `:vector` or `:spine`; only a bitmap sprite has frames
  """

  alias Cauldron2D.GameMaker.Bytes
  alias Cauldron2D.GameMaker.Region
  alias Cauldron2D.Mask

  @enforce_keys [:name, :size, :origin, :frames]
  defstruct [
    :name,
    :size,
    :origin,
    :box,
    :box_mode,
    :separate_masks,
    :smooth,
    frames: [],
    masks: [],
    speed: {1.0, :per_frame},
    kind: :bitmap
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          size: {non_neg_integer(), non_neg_integer()},
          origin: {integer(), integer()},
          box: {integer(), integer(), integer(), integer()},
          box_mode: non_neg_integer(),
          separate_masks: boolean(),
          smooth: boolean(),
          frames: [Region.t()],
          masks: [Mask.t()],
          speed: {float(), :per_second | :per_frame},
          kind: :bitmap | :vector | :spine
        }

  @kinds %{0 => :bitmap, 1 => :vector, 2 => :spine}

  @doc "The sprite at `at`, its frames looked up in `regions` by offset."
  @spec read(binary(), non_neg_integer(), %{non_neg_integer() => Region.t()}) :: t()
  def read(data, at, regions) do
    <<_name::little-32, width::little-32, height::little-32, left::little-signed-32,
      right::little-signed-32, bottom::little-signed-32, top::little-signed-32,
      _transparent::little-32, smooth::little-32, _preload::little-32, box_mode::little-32,
      separate::little-32, origin_x::little-signed-32, origin_y::little-signed-32,
      marker::little-signed-32>> = binary_part(data, at, 60)

    sprite = %__MODULE__{
      name: Bytes.string_at(data, at),
      size: {width, height},
      origin: {origin_x, origin_y},
      box: {left, top, right, bottom},
      box_mode: box_mode,
      separate_masks: separate != 0,
      smooth: smooth != 0,
      frames: []
    }

    if marker == -1,
      do: special(data, at + 60, sprite, regions),
      else: bitmap(data, at + 56, sprite, regions)
  end

  @doc "The mask frame `frame` collides with, `nil` for a sprite with no masks."
  @spec mask(t(), integer()) :: Mask.t() | nil
  def mask(%__MODULE__{masks: []}, _frame), do: nil
  def mask(%__MODULE__{masks: [only]}, _frame), do: only

  def mask(%__MODULE__{masks: masks}, frame),
    do: Enum.at(masks, Integer.mod(frame, length(masks)))

  defp special(data, at, sprite, regions) do
    [version, kind] = Bytes.u32s(data, at, 2)
    rate = Bytes.f32(data, at + 8)
    per = if Bytes.u32(data, at + 12) == 0, do: :per_second, else: :per_frame
    frames_at = at + 16 + 4 * min(max(version - 1, 0), 2)
    sprite = %{sprite | speed: {rate, per}, kind: Map.get(@kinds, kind, :bitmap)}

    if sprite.kind == :bitmap, do: bitmap(data, frames_at, sprite, regions), else: sprite
  end

  defp bitmap(data, at, sprite, regions) do
    pointers = Bytes.pointers(data, at)
    masks_at = at + 4 + 4 * length(pointers)

    %{
      sprite
      | frames: Enum.map(pointers, &Map.fetch!(regions, &1)),
        masks: masks(data, masks_at, sprite.size)
    }
  end

  defp masks(data, at, {width, height}) do
    size = div(width + 7, 8) * height
    count = Bytes.u32(data, at)

    for index <- 0..(count - 1)//1,
        do: Mask.new(width, height, binary_part(data, at + 4 + index * size, size))
  end
end
