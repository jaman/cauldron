defmodule CisternComplete.Storm do
  @moduledoc """
  The pace of storm `level`, from `1`, and what it holds: how fast the Squall drifts and
  turns, how often it drops, how fast rain falls, how many drops the storm holds, and
  whether it brings hail and lightning.
  """

  alias Cauldron.Tuning

  @floor_every 0.2

  @type t :: %{
          squall_speed: float(),
          swerve: float(),
          drop_every: float(),
          fall: float(),
          drops: pos_integer(),
          hail: float(),
          lightning?: boolean()
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
      drops: get(tuning, :storm_drops) + steps * get(tuning, :storm_drops_step),
      hail: if(level >= get(tuning, :hail_from), do: get(tuning, :hail_chance), else: 0.0),
      lightning?: level >= get(tuning, :lightning_from)
    }
  end

  defp get(tuning, key), do: Tuning.get(tuning, key)
end
