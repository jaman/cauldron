defmodule Cauldron2D.BoxBody do
  @moduledoc """
  A box that walks and falls through a grid of tiles, for platform games: `%{x, y, vx,
  vy, w, h, grounded?}`, `{x, y}` the middle of its feet in tiles, `y` growing downward,
  `vx` and `vy` in tiles a second.

  The grid is a function from a tile to `:solid`, `:platform` or `:open`. `move/3` moves
  the body across, stopping at solid tiles, then up or down: falling, it lands on the top
  of a solid tile or of a platform; rising, it stops under a solid tile and passes up
  through platforms. It moves in steps of at most a fifth of a tile, so a fast body does
  not pass through a thin wall. It is grounded when it stands on a solid tile or a
  platform and is not rising.

      grid = fn {x, y} -> if y >= 10, do: :solid, else: :open end
      body = Cauldron2D.BoxBody.new({5.0, 8.0}, {0.8, 1.8})
      Cauldron2D.BoxBody.move(%{body | vy: 30.0}, 0.1, grid).grounded?
      #=> true
  """

  alias Cauldron2D.Box

  @step 0.2

  @type t :: %{
          x: float(),
          y: float(),
          vx: float(),
          vy: float(),
          w: float(),
          h: float(),
          grounded?: boolean()
        }
  @type grid :: ({integer(), integer()} -> :solid | :platform | :open)

  @doc "A body of size `{w, h}` with its feet at `{x, y}`."
  @spec new({number(), number()}, {number(), number()}) :: t()
  def new({x, y}, {w, h}),
    do: %{x: x / 1, y: y / 1, vx: 0.0, vy: 0.0, w: w / 1, h: h / 1, grounded?: false}

  @doc "The body moved `dt` seconds by its velocity through `grid`."
  @spec move(t(), number(), grid()) :: t()
  def move(body, dt, grid) do
    body |> across(body.vx * dt, grid) |> along(body.vy * dt, grid)
  end

  @doc "The box the body takes up (`Cauldron2D.Box`)."
  @spec box(t()) :: Box.t()
  def box(body), do: {body.x - body.w / 2, body.y - body.h, body.x + body.w / 2, body.y}

  @doc "Whether the body's box overlaps tile `{tx, ty}`."
  @spec covers?(t(), {integer(), integer()}) :: boolean()
  def covers?(body, tile), do: Box.overlap?(box(body), Box.tile(tile))

  @doc "The tiles the body's box overlaps."
  @spec tiles(t()) :: [{integer(), integer()}]
  def tiles(body), do: Box.tiles(box(body))

  defp across(body, distance, _grid) when distance == 0, do: body

  defp across(body, distance, grid) do
    steps = max(1, ceil(abs(distance) / @step))

    Enum.reduce_while(1..steps, body, fn _step, acc ->
      moved = %{acc | x: acc.x + distance / steps}
      if solid?(moved, grid), do: {:halt, %{acc | vx: 0.0}}, else: {:cont, moved}
    end)
  end

  defp along(body, distance, grid) do
    steps = max(1, ceil(abs(distance) / @step))

    Enum.reduce_while(1..steps, %{body | grounded?: false}, fn _step, acc ->
      moved = %{acc | y: acc.y + distance / steps}

      cond do
        solid?(moved, grid) and distance > 0 ->
          {:halt, land(%{acc | y: max(acc.y, Float.floor(moved.y))})}

        solid?(moved, grid) ->
          {:halt, %{acc | vy: 0.0}}

        distance > 0 and platform_under?(acc, moved, grid) ->
          {:halt, land(%{moved | y: Float.floor(moved.y)})}

        true ->
          {:cont, moved}
      end
    end)
    |> grounding(grid)
  end

  defp land(body), do: %{body | vy: 0.0, grounded?: true}

  defp grounding(%{grounded?: true} = body, _grid), do: body

  defp grounding(body, grid) do
    under = for tx <- columns(body), do: grid.({tx, floor(body.y + 0.01)})

    touching? =
      abs(body.y - Float.round(body.y)) < 0.02 and Enum.any?(under, &(&1 in [:solid, :platform]))

    %{body | grounded?: touching? and body.vy >= 0}
  end

  defp solid?(body, grid), do: Enum.any?(tiles(body), &(grid.(&1) == :solid))

  defp platform_under?(before, after_move, grid) do
    row = floor(after_move.y)

    before.y <= row + 0.001 and after_move.y >= row and
      Enum.any?(columns(after_move), &(grid.({&1, row}) == :platform))
  end

  defp columns(body), do: floor(body.x - body.w / 2)..floor(body.x + body.w / 2 - 0.001)//1
end
