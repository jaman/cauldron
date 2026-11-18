defmodule Cistern.Storm do
  @moduledoc """
  The pace of storm `level`, from `1`: how fast the Squall drifts and turns, how often it
  drops, how fast a drop falls and how many drops the storm holds, each the tuning's
  first-storm value moved by its step once for every storm after the first.
  """

  alias Cauldron.Tuning

  @floor_every 0.2

  @type t :: %{
          squall_speed: float(),
          swerve: float(),
          drop_every: float(),
          fall: float(),
          drops: pos_integer()
        }

  @doc "The pace of storm `level` under `tuning`."
  @spec pace(Tuning.t(), pos_integer()) :: t()
  def pace(tuning, level) when level >= 1 do
    steps = level - 1

    %{
      squall_speed: get(tuning, :squall_speed) + steps * get(tuning, :squall_speed_step),
      swerve: get(tuning, :swerve) * level,
      drop_every:
        max(@floor_every, get(tuning, :drop_every) - steps * get(tuning, :drop_every_step)),
      fall: get(tuning, :fall) + steps * get(tuning, :fall_step),
      drops: get(tuning, :storm_drops) + steps * get(tuning, :storm_drops_step)
    }
  end

  defp get(tuning, key), do: Tuning.get(tuning, key)
end
