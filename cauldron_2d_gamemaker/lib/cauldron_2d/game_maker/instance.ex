defmodule Cauldron2D.GameMaker.Instance do
  @moduledoc """
  One instance of an object in the running game, with GameMaker's built-in instance
  variables under their GameMaker names, and the game's own variables in `vars`.

  Motion is kept in both forms GameMaker exposes: `hspeed` and `vspeed`, and `speed`
  and `direction` (degrees, counter-clockwise from `+x`, with `y` growing downwards).
  `put_motion/2` writes either form and recomputes the other, so they always agree.

  `alarms` is a tuple of twelve counts, `-1` for an alarm that is off. `image_blend` is
  `{r, g, b}`; `image_alpha` is `0.0`–`1.0`. `sprite_index` and `mask_index` are sprite
  indices, `-1` for none. `room_layer` is whether a GameMaker Studio 2 room placed the
  instance on one of its instance layers, rather than code making it.
  """

  alias Cauldron2D.Turn

  @enforce_keys [:id, :object, :x, :y]
  defstruct [
    :id,
    :object,
    :x,
    :y,
    :xstart,
    :ystart,
    :xprevious,
    :yprevious,
    hspeed: 0.0,
    vspeed: 0.0,
    speed: 0.0,
    direction: 0.0,
    friction: 0.0,
    gravity: 0.0,
    gravity_direction: 270.0,
    sprite_index: -1,
    mask_index: -1,
    image_index: 0.0,
    image_speed: 1.0,
    image_xscale: 1.0,
    image_yscale: 1.0,
    image_angle: 0.0,
    image_blend: {255, 255, 255},
    image_alpha: 1.0,
    depth: 0,
    visible: true,
    solid: false,
    persistent: false,
    alarms: {-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    room_layer: false,
    vars: %{}
  ]

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          object: non_neg_integer(),
          x: number(),
          y: number(),
          xstart: number(),
          ystart: number(),
          xprevious: number(),
          yprevious: number(),
          hspeed: number(),
          vspeed: number(),
          speed: number(),
          direction: number(),
          friction: number(),
          gravity: number(),
          gravity_direction: number(),
          sprite_index: integer(),
          mask_index: integer(),
          image_index: number(),
          image_speed: number(),
          image_xscale: number(),
          image_yscale: number(),
          image_angle: number(),
          image_blend: {byte(), byte(), byte()},
          room_layer: boolean(),
          image_alpha: number(),
          depth: number(),
          visible: boolean(),
          solid: boolean(),
          persistent: boolean(),
          alarms: tuple(),
          vars: map()
        }

  @doc """
  The instance with its motion set by `motion`: `%{hspeed: h, vspeed: v}` (either key
  alone keeps the other), `%{speed: s}`, `%{direction: d}`, or both of the last two.
  """
  @spec put_motion(t(), map()) :: t()
  def put_motion(%__MODULE__{} = instance, motion)
      when is_map_key(motion, :speed) or is_map_key(motion, :direction) do
    speed = Map.get(motion, :speed, instance.speed)
    direction = Map.get(motion, :direction, instance.direction)
    {cos, sin} = Turn.cos_sin(direction)
    %{instance | speed: speed, direction: direction, hspeed: speed * cos, vspeed: -speed * sin}
  end

  def put_motion(%__MODULE__{} = instance, motion) do
    hspeed = Map.get(motion, :hspeed, instance.hspeed)
    vspeed = Map.get(motion, :vspeed, instance.vspeed)
    speed = :math.sqrt(hspeed * hspeed + vspeed * vspeed)

    direction =
      if speed == 0,
        do: instance.direction,
        else: Float.round(:math.atan2(-vspeed, hspeed) * 180 / :math.pi(), 10) |> wrap()

    %{instance | hspeed: hspeed, vspeed: vspeed, speed: speed, direction: direction}
  end

  @doc "The value of alarm `number`, `-1` when it is off."
  @spec alarm(t(), 0..11) :: integer()
  def alarm(%__MODULE__{alarms: alarms}, number), do: elem(alarms, number)

  @doc "The instance with alarm `number` set to `steps`; `-1` turns it off."
  @spec put_alarm(t(), 0..11, integer()) :: t()
  def put_alarm(%__MODULE__{alarms: alarms} = instance, number, steps),
    do: %{instance | alarms: put_elem(alarms, number, steps)}

  @doc "The game's own variable `name`, `default` when it is unset."
  @spec var(t(), term(), term()) :: term()
  def var(%__MODULE__{vars: vars}, name, default \\ nil), do: Map.get(vars, name, default)

  @doc "The instance with its own variable `name` set to `value`."
  @spec put_var(t(), term(), term()) :: t()
  def put_var(%__MODULE__{vars: vars} = instance, name, value),
    do: %{instance | vars: Map.put(vars, name, value)}

  defp wrap(degrees) when degrees < 0, do: degrees + 360
  defp wrap(degrees), do: degrees
end
