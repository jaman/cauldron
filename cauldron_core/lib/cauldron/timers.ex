defmodule Cauldron.Timers do
  @moduledoc """
  Named countdowns in seconds — untouchable after a wound, a weapon reloading, a roll's
  rest — as a plain map a game keeps with each thing (`%{name => seconds left}`). A
  timer runs until its time is spent, then is gone.

      timers = Cauldron.Timers.start(%{}, :reload, 0.2)
      timers = Cauldron.Timers.step(timers, dt)
      Cauldron.Timers.running?(timers, :reload)
  """

  @type t :: %{atom() => number()}

  @doc "`timers` with `name` running for `seconds`, from now, whatever it had left."
  @spec start(t(), atom(), number()) :: t()
  def start(timers, name, seconds), do: Map.put(timers, name, seconds)

  @doc "`timers` `dt` seconds on: each has `dt` less left, and those spent are gone."
  @spec step(t(), number()) :: t()
  def step(timers, dt) do
    for {name, left} <- timers, left - dt > 0, into: %{}, do: {name, left - dt}
  end

  @doc "Whether `name` is running."
  @spec running?(t(), atom()) :: boolean()
  def running?(timers, name), do: Map.has_key?(timers, name)

  @doc "The seconds `name` has left, `0` when it is not running."
  @spec left(t(), atom()) :: number()
  def left(timers, name), do: Map.get(timers, name, 0)
end
