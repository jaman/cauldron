defmodule Cauldron2D.GameMaker.Views do
  @moduledoc """
  GameMaker's built-in view following, run once a step after the end step events.

  An enabled view that follows an object moves so that the first instance of that
  object (or of an object descending from it) stays at least `border` `{x, y}` pixels
  inside the view's edges. It moves at most `speed` `{x, y}` pixels a step on each axis,
  `-1` for no limit, and never past the room's edges. A view that follows nothing, or
  whose object has no instance, stays where it is.
  """

  alias Cauldron2D.GameMaker.Room.View
  alias Cauldron2D.GameMaker.World

  @doc "The world with every following view moved."
  @spec follow(World.t()) :: World.t()
  def follow(%World{views: views} = world) do
    room_size = Enum.at(world.data.rooms, world.room).size
    %{world | views: Enum.map(views, &follow(world, &1, room_size))}
  end

  defp follow(world, %View{enabled: true, follow: object} = view, room_size)
       when is_integer(object) do
    case World.instances_of(world, object) do
      [id | _] ->
        instance = World.fetch(world, id)
        {x, y, width, height} = view.view
        {border_x, border_y} = view.border
        {speed_x, speed_y} = view.speed
        {room_width, room_height} = room_size

        new_x = axis(x, width, instance.x, border_x, speed_x, room_width)
        new_y = axis(y, height, instance.y, border_y, speed_y, room_height)
        %{view | view: {new_x, new_y, width, height}}

      [] ->
        view
    end
  end

  defp follow(_world, %View{} = view, _room_size), do: view

  defp axis(start, size, target, border, speed, room) do
    wanted =
      cond do
        target - start < border -> target - border
        start + size - target < border -> target + border - size
        true -> start
      end

    wanted
    |> limit(start, speed)
    |> clamp(0, max(room - size, 0))
  end

  defp limit(wanted, _start, speed) when speed < 0, do: wanted
  defp limit(wanted, start, speed), do: start + max(-speed, min(speed, wanted - start))

  defp clamp(value, low, high), do: value |> max(low) |> min(high)
end
