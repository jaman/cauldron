defmodule Cauldron2D.Drafter.Client.Seats do
  @moduledoc """
  The further players a client plays on the same machine, from the game's
  `local_seats/1`: each a player of the world with its own keys and its own controller.

  A seat is `%{id, input, pad, last_input}`. Seats join the world with `frames: false`,
  so the client receives frames only as its own player; each key event reaches every
  seat's input and counts where that seat's keymap binds it; a controller event reaches
  the one seat it is routed to. `send_input/3` sends a seat's input only when it changed.
  """

  alias Cauldron2D.{Input, Player}
  alias Cauldron2D.Input.Pad

  @type seat :: %{
          id: String.t(),
          input: Input.t(),
          pad: Pad.t(),
          last_input: map() | nil
        }

  @doc """
  The seats `keymaps` describe, joined to `world` as `"<username> 2"` and on. A seat
  the world refuses is left out. `props` are the player's own join props, given to each
  seat with its own `:username` and with `:seat_of`, the player's own username, so the
  world can tell whose seat it is; `input_options` are those of the player's own input.
  """
  @spec join(GenServer.server(), String.t(), map(), [Input.keymap()], Pad.padmap(), keyword()) ::
          [seat()]
  def join(world, username, props, keymaps, padmap, input_options) do
    keymaps
    |> Enum.with_index(2)
    |> Enum.flat_map(fn {keymap, number} ->
      id = "#{username} #{number}"

      case Player.join(world, id, Map.merge(props, %{username: id, seat_of: username}),
             frames: false
           ) do
        :ok ->
          [
            %{
              id: id,
              input: Input.new(keymap, input_options),
              pad: Pad.new(padmap),
              last_input: nil
            }
          ]

        {:error, _reason} ->
          []
      end
    end)
  end

  @doc "Every seat out of `world`."
  @spec leave([seat()], GenServer.server()) :: :ok
  def leave(seats, world) do
    Enum.each(seats, &Player.leave(world, &1.id))
  end

  @doc "Every seat's input after a key or pointer event at `now`."
  @spec key([seat()], term(), integer()) :: [seat()]
  def key(seats, event, now),
    do: Enum.map(seats, &%{&1 | input: Input.handle(&1.input, event, now)})

  @doc "Every seat's input with its timed holds expired at `now`."
  @spec expire([seat()], integer()) :: [seat()]
  def expire(seats, now), do: Enum.map(seats, &%{&1 | input: Input.expire(&1.input, now)})

  @doc "Every seat holding nothing, its keys read by the keymap it had."
  @spec release([seat()], [Input.keymap()], keyword()) :: [seat()]
  def release(seats, keymaps, input_options) do
    seats
    |> Enum.zip(keymaps)
    |> Enum.map(fn {seat, keymap} -> %{seat | input: Input.new(keymap, input_options)} end)
  end

  @doc "Seat `index` (counting from `0`) after a controller event."
  @spec controller([seat()], non_neg_integer(), map()) :: [seat()]
  def controller(seats, index, event) do
    List.update_at(seats, index, fn seat ->
      pad = Pad.handle(seat.pad, event)
      %{seat | pad: pad, input: Input.merge(seat.input, Pad.held(pad), Pad.strength(pad))}
    end)
  end

  @doc """
  Every seat whose input changed sent to `world`, its read input passed through `steer`
  first, as the client steers its own player's.
  """
  @spec send_input([seat()], GenServer.server(), (map() -> map())) :: [seat()]
  def send_input(seats, world, steer) do
    Enum.map(seats, fn seat ->
      sent = seat.input |> Input.state() |> steer.() |> Map.put(:aim, nil)

      if sent != seat.last_input do
        Player.input(world, seat.id, sent)
        %{seat | last_input: sent}
      else
        seat
      end
    end)
  end
end
