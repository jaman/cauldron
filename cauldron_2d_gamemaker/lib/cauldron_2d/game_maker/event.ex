defmodule Cauldron2D.GameMaker.Event do
  @moduledoc """
  GameMaker's event types, and the names its compiler gives each event's code.

  The type's number is its place in an object's event list:

  | number | type | subtype |
  | --- | --- | --- |
  | 0 | `:create` | `0` |
  | 1 | `:destroy` | `0` |
  | 2 | `:alarm` | alarm number, 0–11 |
  | 3 | `:step` | `0` step, `1` begin step, `2` end step |
  | 4 | `:collision` | the other object's index |
  | 5 | `:keyboard` | key code, held |
  | 6 | `:mouse` | mouse event number |
  | 7 | `:other` | other event number: `10`–`25` are user events 0–15 |
  | 8 | `:draw` | `0` draw, `64` draw GUI, `72`/`73` draw begin/end, … |
  | 9 | `:key_press` | key code |
  | 10 | `:key_release` | key code |
  | 11 | `:trigger` | trigger number |
  | 12 | `:clean_up` | `0` |
  | 13 | `:gesture` | gesture number |
  | 14 | `:pre_create` | `0` |

  A game compiled to native code keeps each event's code in its executable as a
  function named `gml_Object_<object>_<Type>_<subtype>`, the subtype of a collision
  event being the other object's name: `handler_name/3` builds that name.
  """

  @type type ::
          :create
          | :destroy
          | :alarm
          | :step
          | :collision
          | :keyboard
          | :mouse
          | :other
          | :draw
          | :key_press
          | :key_release
          | :trigger
          | :clean_up
          | :gesture
          | :pre_create
          | {:unknown, non_neg_integer()}

  @types {:create, :destroy, :alarm, :step, :collision, :keyboard, :mouse, :other, :draw,
          :key_press, :key_release, :trigger, :clean_up, :gesture, :pre_create}

  @titles %{
    create: "Create",
    destroy: "Destroy",
    alarm: "Alarm",
    step: "Step",
    collision: "Collision",
    keyboard: "Keyboard",
    mouse: "Mouse",
    other: "Other",
    draw: "Draw",
    key_press: "KeyPress",
    key_release: "KeyRelease",
    trigger: "Trigger",
    clean_up: "CleanUp",
    gesture: "Gesture",
    pre_create: "PreCreate"
  }

  @doc "Every event type, in number order."
  @spec types() :: [type()]
  def types, do: Tuple.to_list(@types)

  @doc "The event type numbered `number`."
  @spec type(non_neg_integer()) :: type()
  def type(number) when number < tuple_size(@types), do: elem(@types, number)
  def type(number), do: {:unknown, number}

  @doc """
  The name of the compiled function for `object`'s event `type` with `subtype`, where a
  collision's subtype is the other object's name.

      iex> Cauldron2D.GameMaker.Event.handler_name("Moon", :step, 2)
      "gml_Object_Moon_Step_2"
      iex> Cauldron2D.GameMaker.Event.handler_name("CatMoveLeft", :collision, "Cat")
      "gml_Object_CatMoveLeft_Collision_Cat"
  """
  @spec handler_name(String.t(), type(), non_neg_integer() | String.t()) :: String.t()
  def handler_name(object, type, subtype) when is_map_key(@titles, type),
    do: "gml_Object_#{object}_#{Map.fetch!(@titles, type)}_#{subtype}"
end
