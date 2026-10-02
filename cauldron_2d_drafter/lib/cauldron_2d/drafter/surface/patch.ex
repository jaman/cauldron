defmodule Cauldron2D.Drafter.Surface.Patch do
  @moduledoc """
  Which parts of a projected picture have to be drawn again this frame.

      Patch.plan([{10, 20, 4, 4}], {960, 400}, {8, 16}, 0.4)
      #=> {:patches, [{8, 16, 8, 16}]}

  `spots` are the pixel rectangles the moving parts of a scene cover, each
  `{x, y, width, height}`; `picture` is its size in pixels; `cell` the pixels one
  terminal cell covers, as `{across, down}`; `room` the share of the picture still worth
  patching.

  Answers `{:patches, rects}`, every rectangle clipped to the picture, grown out to cell
  edges, and merged with any it touches, so no two of them meet and each starts on a
  whole cell. Answers `:whole` when the rectangles would cover more than `room` of the
  picture.
  """

  @type rect :: {integer(), integer(), pos_integer(), pos_integer()}

  @doc "The rectangles to redraw, as the module documentation describes."
  @spec plan([rect()], {pos_integer(), pos_integer()}, {number(), number()}, number()) ::
          {:patches, [rect()]} | :whole
  def plan([], _picture, _cell, _room), do: {:patches, []}

  def plan(spots, {width, height} = picture, cell, room) do
    rects =
      spots
      |> Enum.flat_map(&aligned(&1, picture, cell))
      |> merged()

    if area(rects) > room * width * height, do: :whole, else: {:patches, rects}
  end

  defp aligned({x, y, w, h}, {width, height}, {across, down}) do
    left = clamped(floor(x / across) * across, width)
    right = clamped(ceil((x + w) / across) * across, width)
    top = clamped(floor(y / down) * down, height)
    bottom = clamped(ceil((y + h) / down) * down, height)

    if right > left and bottom > top,
      do: [{round(left), round(top), round(right - left), round(bottom - top)}],
      else: []
  end

  defp clamped(value, high), do: value |> max(0) |> min(high)

  defp merged(rects) do
    settled = Enum.reduce(rects, [], &absorb/2)
    if length(settled) == length(rects), do: settled, else: merged(settled)
  end

  defp absorb(rect, kept) do
    {touching, apart} = Enum.split_with(kept, &touches?(&1, rect))
    [Enum.reduce(touching, rect, &union/2) | apart]
  end

  defp touches?({ax, ay, aw, ah}, {bx, by, bw, bh}),
    do: ax <= bx + bw and bx <= ax + aw and ay <= by + bh and by <= ay + ah

  defp union({ax, ay, aw, ah}, {bx, by, bw, bh}) do
    left = min(ax, bx)
    top = min(ay, by)
    {left, top, max(ax + aw, bx + bw) - left, max(ay + ah, by + bh) - top}
  end

  defp area(rects), do: Enum.reduce(rects, 0, fn {_x, _y, w, h}, total -> total + w * h end)
end
