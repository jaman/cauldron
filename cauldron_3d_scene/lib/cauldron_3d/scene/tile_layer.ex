defmodule Cauldron3D.Scene.TileLayer do
  @moduledoc """
  Palette-indexed tiles drawn in order into a target, one layer of a `{:layers, [layer]}` change.

    * `target`, `clear`, `port`, `view` — as `Cauldron3D.Scene.SpriteLayer`
    * `atlas` — the handle of a `:linear` texture with `:nearest` filtering and `:clamp`
      wrapping whose red channel holds each pixel's pen number (0 to 255)
    * `palette` — the handle of a `:linear` texture, one row of `:nearest` colours, that
      pens are looked up in
    * `transparent` — the pen drawn as nothing; `nil` (the default) draws every pen
    * `pens` — a bit mask of the pens that are drawn (bit `n` for pen `n`, pens 0 to 15);
      default `0xFFFF`
    * `tiles` — drawn first to last, each `{source_x, source_y, width, height, x, y, flags,
      palette_base}`: the rectangle of the atlas in its pixels, where its top-left corner
      lands in the view, `flags` with bit 0 mirroring across, bit 1 mirroring down and bit 2
      swapping rows and columns first (the tile is then drawn `height` wide and `width` tall), and the palette position of pen 0 (a pixel of pen `n` takes the colour at `palette_base + n`)

  A pixel is drawn when its centre is inside the tile; it takes the atlas pixel at that point,
  by its own pen, with no filtering and no blending: the palette's colour replaces what is
  there, with its alpha.

      %Cauldron3D.Scene.TileLayer{
        view: {0, 0, 384, 224},
        atlas: atlas,
        palette: palette,
        transparent: 15,
        tiles: [{0, 0, 16, 16, 32, 48, 0, 64}]
      }
  """

  alias Cauldron3D.Scene.Handle

  @type tile ::
          {non_neg_integer(), non_neg_integer(), pos_integer(), pos_integer(), integer(),
           integer(), 0..7, non_neg_integer()}
  @type rect :: {number(), number(), number(), number()}
  @type t :: %__MODULE__{
          target: :frame | Handle.t(),
          clear: {number(), number(), number(), number()} | nil,
          port: rect() | nil,
          view: rect() | nil,
          atlas: Handle.t(),
          palette: Handle.t(),
          transparent: 0..255 | nil,
          pens: 0..0xFFFF,
          tiles: [tile()]
        }

  @enforce_keys [:atlas, :palette]
  defstruct [
    :atlas,
    :palette,
    target: :frame,
    clear: nil,
    port: nil,
    view: nil,
    transparent: nil,
    pens: 0xFFFF,
    tiles: []
  ]
end
