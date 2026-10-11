defmodule Cauldron2D.Sectors.Map do
  @moduledoc """
  A level made of sectors: rooms of any shape, each with its own floor and ceiling height,
  joined and walled by lines, the geometry a sector view and sector movement read.

      map = %Cauldron2D.Sectors.Map{
        vertices: {{0.0, 0.0}, {256.0, 0.0}, ...},
        lines: {%{from: 0, to: 1, front: 0, back: nil, flags: MapSet.new(), special: 0, tag: 0}, ...},
        sides: {%{sector: 0, x_offset: 0.0, y_offset: 0.0, upper: nil, middle: 3, lower: nil}, ...},
        sectors: {%{floor: 0.0, ceiling: 128.0, floor_picture: 5, ceiling_picture: 6, light: 160, special: 0, tag: 0}, ...}
      }
      |> Cauldron2D.Sectors.Map.with_bsp()

  Everything is addressed by position in its tuple. World units are whatever the game
  chooses; `+y` is up the map. A **line** runs `from` vertex `to` vertex; its `front` side
  is on its right looking along it, its `back` side (or `nil` for a wall with nothing
  behind) on its left. A **side** says which sector it faces and which pictures it shows:
  `upper` above a lower ceiling behind it, `lower` below a higher floor behind it,
  `middle` across the opening — on a one-sided line, the whole wall. `x_offset` and
  `y_offset` shift the side's pictures. A **sector** has `floor` and `ceiling` heights,
  their pictures and a `light` of `0..255`; `special` and `tag` are the game's.

  A line's `flags` is a set; the engine reads `:blocks` (nothing passes),
  `:blocks_walkers` (bodies that walk do not pass), `:blocks_sound`, `:upper_unpegged`
  (the upper picture hangs from the ceiling rather than standing on the opening),
  `:lower_unpegged` (the lower picture hangs from the ceiling rather than from the
  opening's floor, and a middle picture stands on the floor), `:secret` (shown as a plain
  wall on the automap), `:hidden` (never on the automap) and `:mapped` (on the automap from
  the start). Others are the game's.

  `segs`, `subsectors` and `nodes` are the BSP that orders the level for drawing and for
  finding a point's sector: built with `with_bsp/2`, or given, as a level file that
  carries its own BSP gives it.
  """

  alias Cauldron2D.Sectors.Bsp

  @enforce_keys [:vertices, :lines, :sides, :sectors]
  defstruct [:vertices, :lines, :sides, :sectors, :segs, :subsectors, :nodes, :blockmap, :reject]

  @type point :: {float(), float()}
  @type line :: %{
          required(:from) => non_neg_integer(),
          required(:to) => non_neg_integer(),
          required(:front) => non_neg_integer(),
          required(:back) => non_neg_integer() | nil,
          required(:flags) => MapSet.t(atom()),
          optional(:special) => term(),
          optional(:tag) => term()
        }
  @type side :: %{
          required(:sector) => non_neg_integer(),
          required(:x_offset) => number(),
          required(:y_offset) => number(),
          required(:upper) => non_neg_integer() | nil,
          required(:middle) => non_neg_integer() | nil,
          required(:lower) => non_neg_integer() | nil
        }
  @type sector :: %{
          required(:floor) => number(),
          required(:ceiling) => number(),
          required(:floor_picture) => non_neg_integer(),
          required(:ceiling_picture) => non_neg_integer(),
          required(:light) => 0..255,
          optional(:special) => term(),
          optional(:tag) => term()
        }
  @type seg :: %{
          from: point(),
          to: point(),
          line: non_neg_integer(),
          side: 0 | 1,
          offset: float()
        }
  @type t :: %__MODULE__{
          vertices: tuple(),
          lines: tuple(),
          sides: tuple(),
          sectors: tuple(),
          segs: tuple() | nil,
          subsectors: tuple() | nil,
          nodes: tuple() | nil,
          blockmap: term(),
          reject: term()
        }

  @doc "The map with a BSP built from its lines by `Cauldron2D.Sectors.Bsp.build/2`."
  @spec with_bsp(t(), keyword()) :: t()
  def with_bsp(%__MODULE__{} = map, opts \\ []) do
    {segs, subsectors, nodes} = Bsp.build(map, opts)
    %{map | segs: segs, subsectors: subsectors, nodes: nodes}
  end

  @doc "The vertex at `index`."
  @spec vertex(t(), non_neg_integer()) :: point()
  def vertex(%__MODULE__{vertices: vertices}, index), do: elem(vertices, index)

  @doc "Line `index`'s end points, `{from, to}`."
  @spec ends(t(), non_neg_integer()) :: {point(), point()}
  def ends(%__MODULE__{} = map, index) do
    line = elem(map.lines, index)
    {vertex(map, line.from), vertex(map, line.to)}
  end

  @doc "The sector side `side` of line `index` faces, or `nil` for a missing back."
  @spec side_sector(t(), non_neg_integer(), 0 | 1, tuple()) :: non_neg_integer() | nil
  def side_sector(%__MODULE__{} = map, index, side, sides \\ nil) do
    sides = sides || map.sides
    line = elem(map.lines, index)

    case if(side == 0, do: line.front, else: line.back) do
      nil -> nil
      side_index -> elem(sides, side_index).sector
    end
  end

  @doc "The subsector containing `point`, found through the BSP."
  @spec subsector_at(t(), point()) :: non_neg_integer()
  def subsector_at(%__MODULE__{} = map, point), do: Bsp.locate(map, point)

  @doc "The sector containing `point`, found through the BSP."
  @spec sector_at(t(), point()) :: non_neg_integer()
  def sector_at(%__MODULE__{} = map, point),
    do: elem(map.subsectors, subsector_at(map, point)).sector

  @doc """
  Which side of the line from `{x, y}` along `{dx, dy}` a point is on: `0` on the right,
  as a line's front is, `1` on the left. A point on a slanted line counts as the left; on
  an upright or level line, as a BSP built for Doom-format levels expects.
  """
  @spec point_side(point(), {number(), number(), number(), number()}) :: 0 | 1
  def point_side({px, _py}, {x, _y, dx, dy}) when dx == 0,
    do: if(px <= x, do: side_of(dy > 0), else: side_of(dy < 0))

  def point_side({_px, py}, {_x, y, dx, dy}) when dy == 0,
    do: if(py <= y, do: side_of(dx < 0), else: side_of(dx > 0))

  def point_side({px, py}, {x, y, dx, dy}), do: side_of((py - y) * dx >= dy * (px - x))

  defp side_of(true), do: 1
  defp side_of(false), do: 0

  @doc "The lines that touch sector `index`."
  @spec sector_lines(t(), non_neg_integer()) :: [non_neg_integer()]
  def sector_lines(%__MODULE__{} = map, index) do
    for line_index <- 0..(tuple_size(map.lines) - 1)//1,
        line = elem(map.lines, line_index),
        Enum.any?([line.front, line.back], &(&1 != nil and elem(map.sides, &1).sector == index)),
        do: line_index
  end
end
