defmodule CauldronGPU.ColumnLayer do
  @moduledoc """
  A texture redrawn column by column into a target, one layer of a `{:layers, [layer]}`
  change: a warp given as a table.

    * `target` — `:frame` (the default) or a canvas handle
    * `clear` — `{r, g, b, a}` from 0 to 1 the target is filled with first, or `nil`
    * `port` — `{x, y, width, height}` in the target's pixels, the part redrawn; `nil`
      is the whole target
    * `source` — the handle of the texture or canvas read
    * `columns` — one `{u, v_scale, shade}` per column of the port, left to right

  Each column of the port reads the source at the horizontal position `u` (0 its left
  edge, 1 its right). A pixel `down` of the way from the port's top (0 to 1) reads the
  vertical position `0.5 + (down − 0.5) × v_scale`. The source is sampled between its
  four nearest pixels, edges repeated, and its colour multiplied by `shade`. A position
  outside 0 to 1 draws opaque black. When the port has more pixels across than there are
  columns, the columns are stretched to fill it.
  """

  alias CauldronGPU.Handle

  @type t :: %__MODULE__{
          target: :frame | Handle.t(),
          clear: {number(), number(), number(), number()} | nil,
          port: {number(), number(), number(), number()} | nil,
          source: Handle.t(),
          columns: [{number(), number(), number()}]
        }

  @enforce_keys [:source, :columns]
  defstruct [:source, :columns, target: :frame, clear: nil, port: nil]
end
