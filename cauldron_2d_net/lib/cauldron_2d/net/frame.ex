defmodule Cauldron2D.Net.Frame do
  @moduledoc """
  What goes over the wire to a browser: the static map once, and a frame per tick, with
  arts as sheet indices.

      Cauldron2D.Net.Frame.map(%{width: w, height: h, cell: fun}, sheet)
      Cauldron2D.Net.Frame.frame(%{focus: {x, y}, movers: [{art, {x, y}}], labels: [{"alice", {x, y}, {255, 255, 0}}]}, hud_rows, outcome, sheet)

  `sheet` is what `Cauldron2D.Net.Sheet.build/1` returned, or any map with `:arts` and
  `:tile`. A mover whose art the sheet lacks is left out. Hud rows are as
  `Cauldron2D.Client.Hud` describes them and go out as `[text, "#rrggbb" | nil]` runs;
  a row's tag goes in `tags` at the same position (`nil` for a row without one) —
  `tags` is there only when some row has a tag. Labels go out as
  `[text, x, y, "#rrggbb", scale]`.
  """

  alias Cauldron2D.Client.Hud

  @type sheet :: %{
          required(:arts) => %{atom() => pos_integer()},
          required(:tile) => pos_integer()
        }

  @doc "The static layer: `width` by `height` rows of art indices, 0 where `cell` returns `nil`, and whether the world wraps at its edges (`:wrap?`, default false)."
  @spec map(
          %{
            required(:width) => pos_integer(),
            required(:height) => pos_integer(),
            required(:cell) => ({integer(), integer()} -> atom() | nil),
            optional(:wrap?) => boolean()
          },
          sheet()
        ) :: map()
  def map(%{width: width, height: height, cell: cell} = layer, sheet) do
    rows =
      for y <- 0..(height - 1),
          do: for(x <- 0..(width - 1), do: Map.get(sheet.arts, cell.({x, y}), 0))

    %{
      width: width,
      height: height,
      tile: sheet.tile,
      wrap: Map.get(layer, :wrap?, false),
      rows: rows
    }
  end

  @type row :: Hud.row()

  @doc "One tick: the focus, the movers, the labels, the hud rows (with their tags when any row has one) and the outcome when the round is over for this player."
  @spec frame(
          %{
            required(:focus) => {number(), number()},
            required(:movers) => [{atom(), {number(), number()}}],
            optional(:labels) => list()
          },
          [row()],
          map() | nil,
          sheet()
        ) :: map()
  def frame(%{focus: {fx, fy}, movers: movers} = scene, hud, outcome, sheet) do
    tags = Enum.map(hud, &Hud.tag/1)

    frame = %{
      focus: [fx / 1, fy / 1],
      movers:
        for(
          {art, {x, y}} <- movers,
          index = Map.get(sheet.arts, art),
          index != nil,
          do: [index, x / 1, y / 1]
        ),
      labels: for(label <- Map.get(scene, :labels, []), do: label_wire(label)),
      hud:
        for(row <- hud, do: for(run <- Hud.runs(row), do: [elem(run, 0), hex(Hud.colour(run))])),
      over: outcome && Map.take(outcome, [:title, :lines])
    }

    if Enum.any?(tags),
      do: Map.put(frame, :tags, Enum.map(tags, &(&1 && Atom.to_string(&1)))),
      else: frame
  end

  defp label_wire({text, {x, y}, colour}), do: [text, x / 1, y / 1, hex(colour), 1]

  defp label_wire({text, {x, y}, colour, opts}),
    do: [text, x / 1, y / 1, hex(colour), Keyword.get(opts, :scale, 1)]

  defp hex(nil), do: nil
  defp hex({r, g, b}), do: "#" <> Base.encode16(<<r, g, b>>, case: :lower)
end
