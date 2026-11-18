defmodule Cauldron3D.Scene.ShadowLayer do
  @moduledoc """
  Tiles whose pixels darken (or otherwise remap) what is already in the target, one layer of a
  `{:layers, [layer]}` change.

    * `target`, `clear`, `port`, `view`, `atlas`, `transparent`, `pens` and `tiles` — as
      `Cauldron3D.Scene.TileLayer`
    * `table` — the handle of a `:linear` texture with `:nearest` filtering and `:clamp`
      wrapping, `count` colours wide and two rows tall: row 0 holds the colours that can be
      under a shadow and row 1 the colour each becomes
    * `count` — how many colours the table holds (at most 255)

  Every drawn pixel of a tile (a pen that is not `transparent` and is set in `pens`) is replaced
  by the table's row 1 colour for the colour the target held there when the layer began; a
  colour the table does not list stays as it is. The atlas pen only decides which pixels are
  shadow.

  A layer reads the target as it was before the layer started, so tiles of one layer that
  overlap do not see each other. Only the browser renderer draws it, and only into a canvas.
  """

  alias Cauldron3D.Scene.{Handle, TileLayer}

  @type t :: %__MODULE__{
          target: :frame | Handle.t(),
          clear: {number(), number(), number(), number()} | nil,
          port: TileLayer.rect() | nil,
          view: TileLayer.rect() | nil,
          atlas: Handle.t(),
          table: Handle.t(),
          count: 1..255,
          transparent: 0..255 | nil,
          pens: 0..0xFFFF,
          tiles: [TileLayer.tile()]
        }

  @enforce_keys [:atlas, :table, :count]
  defstruct [:atlas, :table, :count, target: :frame, clear: nil, port: nil, view: nil, transparent: nil, pens: 0xFFFF, tiles: []]
end
