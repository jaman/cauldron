defmodule Cauldron2D.Jump do
  @moduledoc """
  Jumping for a body that walks on ground (`Cauldron2D.BoxBody`): coyote time, a jump's
  height set by how long it is held, and a fall-speed cap. A jump value is kept with each
  body in the game's state.

    * **Coyote time** — a body that walks off a ledge can still jump for `:coyote` seconds
      after it leaves the ground (default `0.1`), once
    * **Held height** — rising with the jump let go, gravity pulls `:cut` times as hard
      (default `2.6`), so a tap hops and a held press leaps
    * **Fall cap** — falling never passes `:max_fall` tiles a second (default `30.0`)

  Pair it with `Cauldron.Presses.buffered?/4` so a jump pressed just before landing
  still jumps:

      if Presses.buffered?(presses, held, :jump, 0.1) and Jump.ready?(jump, body),
        do: Jump.launch(jump, body, 26.0)

      body = Jump.fall(body, MapSet.member?(held, :jump), 75.0, dt)
      body = BoxBody.move(body, dt, grid)
      jump = Jump.step(jump, body, dt)
  """

  @coyote 0.1
  @cut 2.6
  @max_fall 30.0

  defstruct air: 0.0, jumped?: false

  @type t :: %__MODULE__{air: number(), jumped?: boolean()}
  @type body :: %{
          required(:vy) => number(),
          required(:grounded?) => boolean(),
          optional(atom()) => term()
        }

  @doc "A jump for a body on the ground."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Whether the body can jump: on the ground, or off it no longer than `:coyote` seconds without having jumped."
  @spec ready?(t(), body(), keyword()) :: boolean()
  def ready?(jump, body, opts \\ []),
    do: body.grounded? or (not jump.jumped? and jump.air <= Keyword.get(opts, :coyote, @coyote))

  @doc "`{jump, body}` with the body leaving the ground upward at `speed` tiles a second."
  @spec launch(t(), body(), number()) :: {t(), body()}
  def launch(jump, body, speed),
    do: {%{jump | jumped?: true}, %{body | vy: -speed, grounded?: false}}

  @doc "The jump after the body has moved `dt` seconds: on the ground it is ready again, in the air it counts the time."
  @spec step(t(), body(), number()) :: t()
  def step(_jump, %{grounded?: true}, _dt), do: new()
  def step(jump, _body, dt), do: %{jump | air: jump.air + dt}

  @doc """
  The body's vertical speed after `dt` seconds of `gravity` (tiles a second squared):
  `:cut` times stronger while it rises with the jump not `held?`, and no faster downward
  than `:max_fall`.
  """
  @spec fall(body(), boolean(), number(), number(), keyword()) :: body()
  def fall(body, held?, gravity, dt, opts \\ []) do
    cut = if body.vy < 0 and not held?, do: Keyword.get(opts, :cut, @cut), else: 1.0
    %{body | vy: min(body.vy + gravity * dt * cut, Keyword.get(opts, :max_fall, @max_fall))}
  end
end
