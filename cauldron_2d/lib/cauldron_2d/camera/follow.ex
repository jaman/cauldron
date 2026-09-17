defmodule Cauldron2D.Camera.Follow do
  @moduledoc """
  A camera that trails its target and can be shaken, as a value the game steps.

      follow = Cauldron2D.Camera.Follow.new(ship.pos)
      follow = follow |> Cauldron2D.Camera.Follow.follow(ship.pos, dt, 0.3) |> Cauldron2D.Camera.Follow.step(dt)
      Cauldron2D.Camera.view(focus: Cauldron2D.Camera.Follow.focus(follow), ...)

  `follow/4` closes on the target so that the distance halves every `lag` seconds; a
  `lag` of `0` snaps to it. `shake/3` starts a shake of an amplitude in tiles that
  fades to nothing over its time; `step/2` advances it. The shake is a fixed pattern
  of the time elapsed, so a replay shakes the same way.
  """

  @type point :: {float(), float()}
  @type t :: %__MODULE__{
          pos: point(),
          shake: nil | %{amplitude: float(), duration: float(), elapsed: float()}
        }

  defstruct pos: {0.0, 0.0}, shake: nil

  @doc "A camera at `pos`."
  @spec new({number(), number()}) :: t()
  def new({x, y}), do: %__MODULE__{pos: {x / 1, y / 1}}

  @doc "Move toward `target` for `dt` seconds, the distance halving every `lag` seconds."
  @spec follow(t(), {number(), number()}, number(), number()) :: t()
  def follow(%__MODULE__{} = follow, {tx, ty}, _dt, lag) when lag <= 0,
    do: %{follow | pos: {tx / 1, ty / 1}}

  def follow(%__MODULE__{pos: {x, y}} = follow, {tx, ty}, dt, lag) do
    share = 1 - :math.pow(0.5, dt / lag)
    %{follow | pos: {x + (tx - x) * share, y + (ty - y) * share}}
  end

  @doc "Start a shake of `amplitude` tiles fading over `duration` seconds; a shake already going is replaced."
  @spec shake(t(), number(), number()) :: t()
  def shake(%__MODULE__{} = follow, amplitude, duration) when duration > 0 do
    %{follow | shake: %{amplitude: amplitude / 1, duration: duration / 1, elapsed: 0.0}}
  end

  @doc "Advance the shake by `dt` seconds; it ends when its time is up."
  @spec step(t(), number()) :: t()
  def step(%__MODULE__{shake: nil} = follow, _dt), do: follow

  def step(%__MODULE__{shake: shake} = follow, dt) do
    elapsed = shake.elapsed + dt

    if elapsed >= shake.duration,
      do: %{follow | shake: nil},
      else: %{follow | shake: %{shake | elapsed: elapsed}}
  end

  @doc "The shake's offset now, `{0.0, 0.0}` when there is none."
  @spec offset(t()) :: point()
  def offset(%__MODULE__{shake: nil}), do: {0.0, 0.0}

  def offset(%__MODULE__{shake: %{amplitude: amplitude, duration: duration, elapsed: elapsed}}) do
    strength = amplitude * (1 - elapsed / duration)
    {strength * :math.sin(elapsed * 73.0), strength * :math.cos(elapsed * 61.0)}
  end

  @doc "Where the camera looks: its position plus the shake."
  @spec focus(t()) :: point()
  def focus(%__MODULE__{pos: {x, y}} = follow) do
    {dx, dy} = offset(follow)
    {x + dx, y + dy}
  end
end
