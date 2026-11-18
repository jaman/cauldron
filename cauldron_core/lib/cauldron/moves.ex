defmodule Cauldron.Moves do
  @moduledoc """
  The timing of a strike — a punch, a swing, a bite — as frame data: a wind-up before it
  can hit, an active window in which it hits, and a recovery after, in seconds. A move
  is any map with `:windup`, `:active` and `:recover`; the game keeps its own table of
  moves with whatever else it needs (damage, reach, the next move of a combo).

      jab = %{windup: 0.06, active: 0.08, recover: 0.16, damage: 1}
      Cauldron.Moves.part(jab, 0.1)
      #=> :active

  `frame/3` picks the picture of a move's animation that keeps time with its parts, so
  the frame showing the full swing is on screen while the move can hit.
  """

  @type move :: %{
          required(:windup) => number(),
          required(:active) => number(),
          required(:recover) => number(),
          optional(atom()) => term()
        }
  @type part :: :windup | :active | :recover | :done

  @doc "Which part of `move` it is in, `t` seconds after it began."
  @spec part(move(), number()) :: part()
  def part(%{windup: windup, active: active, recover: recover}, t) do
    cond do
      t < windup -> :windup
      t < windup + active -> :active
      t < windup + active + recover -> :recover
      true -> :done
    end
  end

  @doc "The seconds `move` takes from beginning to end."
  @spec duration(move()) :: number()
  def duration(move), do: move.windup + move.active + move.recover

  @doc """
  The frame of `move`'s animation to show `t` seconds in, from `0`, for an animation of
  `{windup, active, recover}` frames: the wind-up's frames spread over the wind-up, the
  active frames over the active window, the recovery's over the recovery. After the end,
  the last frame.

      Cauldron.Moves.frame(jab, 0.1, {2, 1, 2})
      #=> 2
  """
  @spec frame(move(), number(), {pos_integer(), pos_integer(), pos_integer()}) ::
          non_neg_integer()
  def frame(move, t, {windup_frames, active_frames, recover_frames}) do
    case part(move, t) do
      :windup ->
        spread(t / move.windup, windup_frames)

      :active ->
        windup_frames + spread((t - move.windup) / move.active, active_frames)

      :recover ->
        windup_frames + active_frames +
          spread((t - move.windup - move.active) / move.recover, recover_frames)

      :done ->
        windup_frames + active_frames + recover_frames - 1
    end
  end

  defp spread(share, frames), do: min(frames - 1, trunc(share * frames))
end
