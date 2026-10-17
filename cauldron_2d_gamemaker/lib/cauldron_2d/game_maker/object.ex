defmodule Cauldron2D.GameMaker.Object do
  @moduledoc """
  An object (an `OBJT` entry): the definition rooms place instances of.

    * `sprite` and `mask` are sprite indices, `-1` for none; with no mask the sprite's
      own masks collide
    * `parent` is the object it inherits events from, `nil` for none
    * `depth` orders drawing: greater depth is drawn first, further back
    * `managed` is the managed flag of files written by GameMaker 2022.5 up to 2026.1,
      `nil` for other files
    * `physics` holds the Box2D settings, `nil` when the object does not use physics
    * `events` lists `{type, subtype, code}`: `type` is a name from
      `Cauldron2D.GameMaker.Event.types/0`, `subtype` the alarm, key, object, step or
      other number the type takes, and `code` the index of the event's code entry,
      `nil` for none. A game compiled to native code carries no code entries in its
      data file; its event's code is the executable's function named by
      `Cauldron2D.GameMaker.Event.handler_name/3`
  """

  alias Cauldron2D.GameMaker.Bytes
  alias Cauldron2D.GameMaker.Event
  alias Cauldron2D.GameMaker.General

  @enforce_keys [:name, :sprite, :depth, :events]
  defstruct [
    :name,
    :sprite,
    :mask,
    :parent,
    :depth,
    :visible,
    :managed,
    :solid,
    :persistent,
    :physics,
    events: []
  ]

  @type event :: {Event.type(), non_neg_integer(), non_neg_integer() | nil}
  @type t :: %__MODULE__{
          name: String.t(),
          sprite: integer(),
          mask: integer(),
          parent: non_neg_integer() | nil,
          depth: integer(),
          visible: boolean(),
          managed: boolean() | nil,
          solid: boolean(),
          persistent: boolean(),
          physics: map() | nil,
          events: [event()]
        }

  @doc "The object at `at`; `general` says whether its entry carries the managed flag."
  @spec read(binary(), non_neg_integer(), General.t()) :: t()
  def read(data, at, %General{} = general) do
    flag = managed_flag_size(general)

    <<_name::little-32, sprite::little-signed-32, visible::little-32, managed::binary-size(flag),
      solid::little-32, depth::little-signed-32, persistent::little-32, parent::little-signed-32,
      mask::little-signed-32, physics::little-32, sensor::little-32, shape::little-32,
      density::binary-4, restitution::binary-4, group::little-32, linear::binary-4,
      angular::binary-4, vertices::little-32, friction::binary-4, awake::little-32,
      kinematic::little-32>> = binary_part(data, at, 80 + flag)

    shape_at = at + 80 + flag
    events_at = shape_at + vertices * 8

    %__MODULE__{
      name: Bytes.string_at(data, at),
      sprite: sprite,
      mask: mask,
      parent: if(parent >= 0, do: parent),
      depth: depth,
      visible: visible != 0,
      managed: managed(managed),
      solid: solid != 0,
      persistent: persistent != 0,
      physics:
        if(physics != 0,
          do: %{
            sensor: sensor != 0,
            shape: shape,
            density: Bytes.float(density),
            restitution: Bytes.float(restitution),
            group: group,
            linear_damping: Bytes.float(linear),
            angular_damping: Bytes.float(angular),
            friction: Bytes.float(friction),
            awake: awake != 0,
            kinematic: kinematic != 0,
            points: points(data, shape_at, vertices)
          }
        ),
      events: events(data, events_at)
    }
  end

  defp managed(<<>>), do: nil
  defp managed(<<flag::little-32>>), do: flag != 0

  defp managed_flag_size(general) do
    if General.at_least?(general, 2022, 5) and not General.at_least?(general, 2026, 1),
      do: 4,
      else: 0
  end

  defp points(data, at, count) do
    for <<x::binary-4, y::binary-4 <- binary_part(data, at, count * 8)>>,
      do: {Bytes.float(x), Bytes.float(y)}
  end

  defp events(data, at) do
    data
    |> Bytes.pointers(at)
    |> Enum.with_index()
    |> Enum.flat_map(fn {list, type} ->
      for event <- Bytes.pointers(data, list) do
        {Event.type(type), Bytes.u32(data, event), code(data, event + 4)}
      end
    end)
  end

  defp code(data, actions_at) do
    case Bytes.pointers(data, actions_at) do
      [action | _] -> action_code(Bytes.i32(data, action + 32))
      [] -> nil
    end
  end

  defp action_code(code) when code >= 0, do: code
  defp action_code(_code), do: nil
end
