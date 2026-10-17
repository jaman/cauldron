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
    * `kind` is `:bitmap`, `:swf`, `:spine` or `:vector`; only a bitmap sprite has frames
    * `nine_slice` is `nil`, or `%{left, top, right, bottom, modes}` when the sprite is
      drawn stretched by its nine parts: the borders in pixels from each edge, kept as
      they are, and the tile mode of the left, top, right, bottom and centre parts
      (`0` stretch, `1` repeat, `2` mirror, `3` blank, `4` hide)
  """

  alias Cauldron2D.GameMaker.Bytes
  alias Cauldron2D.GameMaker.General
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
    kind: :bitmap,
    nine_slice: nil
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
          kind: :bitmap | :swf | :spine | :vector,
          nine_slice:
            %{
              left: integer(),
              top: integer(),
              right: integer(),
              bottom: integer(),
              modes: [non_neg_integer()]
            }
            | nil
        }

  @kinds %{0 => :bitmap, 1 => :swf, 2 => :spine, 3 => :vector}

  @doc """
  The sprite at `at`, its frames looked up in `regions` by offset. Files written by
  GameMaker 2024.6 or later store each mask as the collision box only; the masks come
  back widened to the whole picture.
  """
  @spec read(binary(), non_neg_integer(), %{non_neg_integer() => Region.t()}, General.t()) ::
          t()
  def read(data, at, regions, %General{} = general) do
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

    mask_box = if General.at_least?(general, 2024, 6), do: :box, else: :picture

    if marker == -1,
      do: special(data, at + 60, sprite, regions, mask_box),
      else: bitmap(data, at + 56, sprite, regions, mask_box)
  end

  @doc "The mask frame `frame` collides with, `nil` for a sprite with no masks."
  @spec mask(t(), integer()) :: Mask.t() | nil
  def mask(%__MODULE__{masks: []}, _frame), do: nil
  def mask(%__MODULE__{masks: [only]}, _frame), do: only

  def mask(%__MODULE__{masks: masks}, frame),
    do: Enum.at(masks, Integer.mod(frame, length(masks)))

  defp special(data, at, sprite, regions, mask_box) do
    [version, kind] = Bytes.u32s(data, at, 2)
    rate = Bytes.f32(data, at + 8)
    per = if Bytes.u32(data, at + 12) == 0, do: :per_second, else: :per_frame
    frames_at = at + 16 + 4 * min(max(version - 1, 0), 2)

    sprite = %{
      sprite
      | speed: {rate, per},
        kind: Map.get(@kinds, kind, :bitmap),
        nine_slice: nine_slice(data, version, at)
    }

    if sprite.kind == :bitmap,
      do: bitmap(data, frames_at, sprite, regions, mask_box),
      else: sprite
  end

  defp nine_slice(data, version, at) when version >= 3 do
    case Bytes.u32(data, at + 20) do
      0 ->
        nil

      slice_at ->
        <<left::little-signed-32, top::little-signed-32, right::little-signed-32,
          bottom::little-signed-32, enabled::little-32, modes::binary-20>> =
          binary_part(data, slice_at, 40)

        if enabled != 0,
          do: %{
            left: left,
            top: top,
            right: right,
            bottom: bottom,
            modes: for(<<mode::little-32 <- modes>>, do: mode)
          }
    end
  end

  defp nine_slice(_data, _version, _at), do: nil

  defp bitmap(data, at, sprite, regions, mask_box) do
    pointers = Bytes.pointers(data, at)
    masks_at = at + 4 + 4 * length(pointers)

    %{
      sprite
      | frames: Enum.map(pointers, &Map.fetch!(regions, &1)),
        masks: masks(data, masks_at, sprite, mask_box)
    }
  end

  defp masks(data, at, %__MODULE__{size: size, box: {left, top, right, bottom}}, :box) do
    case {right - left + 1, bottom - top + 1} do
      ^size -> picture_masks(data, at, size)
      {box_width, box_height} when box_width < 1 or box_height < 1 -> []
      box_size -> box_masks(data, at, box_size, {left, top}, size)
    end
  end

  defp masks(data, at, %__MODULE__{size: size}, :picture), do: picture_masks(data, at, size)

  defp picture_masks(data, at, {width, height}) do
    size = div(width + 7, 8) * height
    count = Bytes.u32(data, at)

    for index <- 0..(count - 1)//1,
        do: Mask.new(width, height, binary_part(data, at + 4 + index * size, size))
  end

  defp box_masks(data, at, {box_width, box_height}, corner, {width, height}) do
    size = div(box_width + 7, 8) * box_height
    count = Bytes.u32(data, at)

    for index <- 0..(count - 1)//1 do
      bits = binary_part(data, at + 4 + index * size, size)
      widened = widen(bits, {box_width, box_height}, corner, {width, height})
      Mask.new(width, height, widened)
    end
  end

  defp widen(bits, {box_width, box_height}, {left, top}, {width, height}) do
    stride = div(box_width + 7, 8)
    rows = for <<row::binary-size(stride) <- bits>>, do: row
    rows = List.to_tuple(rows)
    padding = div(width + 7, 8) * 8 - width

    for y <- 0..(height - 1), into: <<>> do
      source = y - top

      if source >= 0 and source < box_height,
        do: place(elem(rows, source), box_width, left, width, padding),
        else: <<0::size(width + padding)>>
    end
  end

  defp place(row, box_width, left, width, padding) when left >= 0 and left + box_width <= width do
    <<picked::bitstring-size(box_width), _::bitstring>> = row
    <<0::size(left), picked::bitstring, 0::size(width - left - box_width + padding)>>
  end

  defp place(row, box_width, left, width, padding) do
    bits = for x <- 0..(width - 1), into: <<>>, do: <<pixel(row, x - left, box_width)::1>>
    <<bits::bitstring, 0::size(padding)>>
  end

  defp pixel(row, x, box_width) when x >= 0 and x < box_width do
    <<_::bitstring-size(x), bit::1, _::bitstring>> = row
    bit
  end

  defp pixel(_row, _x, _box_width), do: 0
end
