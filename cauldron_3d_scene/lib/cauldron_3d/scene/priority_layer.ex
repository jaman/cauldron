defmodule Cauldron3D.Scene.PriorityLayer do
  @moduledoc """
  Palette-indexed sprite tiles that show only where a coverage canvas lets them, one layer of a `{:layers, [layer]}` change.

    * `target`, `clear`, `port`, `view`, `atlas`, `palette`, `transparent`, `pens` and `tiles` — as `Cauldron3D.Scene.TileLayer`, except
      that bits 3 to 5 of a tile's `flags` hold its priority (0 to 7)
    * `coverage` — the handle of a `Cauldron3D.Scene.Canvas` the same size as the target whose red channel holds, for each pixel, 0
      where nothing covers it and otherwise the priority of the front-most layer that covered it plus one
    * `shadows` — how many shadow colours the palette texture holds (0 for none); it is then `shadows` or more colours wide and three rows
      tall: row 0 is the palette, row 1 the colours that can be under a shadow and row 2 the colour each becomes

  A tile whose `flags` have bit 6 set is a shadow: where it shows it draws no colour of its own, and the pixel shows the row 2 colour for the
  row 1 colour the target held there when the layer began (the pixel is left as it was when the table does not list that colour).

  Tiles are drawn first to last, and the last tile that draws a pen at a pixel decides what the pixel shows. A pixel of
  a tile shows its palette colour when the tile's priority is above 0 and the coverage there is 0 or at most the tile's priority; in every
  other case it shows the colour the target held there when the layer began. A layer reads the target as it was before the layer started,
  so tiles of one layer that overlap do not see each other's colours.

  The native renderer draws it, and only into a canvas.
  """

  alias Cauldron3D.Scene.{Handle, TileLayer}

  @type t :: %__MODULE__{
          target: :frame | Handle.t(),
          clear: {number(), number(), number(), number()} | nil,
          port: TileLayer.rect() | nil,
          view: TileLayer.rect() | nil,
          atlas: Handle.t(),
          palette: Handle.t(),
          coverage: Handle.t(),
          shadows: non_neg_integer(),
          transparent: 0..255 | nil,
          pens: 0..0xFFFF,
          tiles: [TileLayer.tile()]
        }

  @enforce_keys [:atlas, :palette, :coverage]
  defstruct [:atlas, :palette, :coverage, shadows: 0, target: :frame, clear: nil, port: nil, view: nil, transparent: nil, pens: 0xFFFF, tiles: []]
end
