defmodule Cauldron2D.Drafter.Client.Controllers do
  @moduledoc """
  The game controllers a client has seen, and which of its players each one plays.

  A controller is known by its device id (`Gamepad.Wire`'s `device`) and its name, the
  name it reported when it connected; two connected controllers reporting the same name
  are told apart as `"<name>"`, `"<name> #2"` and on, in the order they connected. A
  controller heard from before it said it connected is named `"controller <device>"`.

  The client's players are numbered from 1: the player itself, then each of its seats
  (`Cauldron2D.Drafter.Client.Seats`). `slots/3` gives each connected controller a slot,
  its player's number less one, from `assignments`, a map from controller name to a
  player number or `:none`:

    * a controller assigned a player that exists and no earlier controller took plays it
    * a controller with no assignment plays the lowest-numbered player left free, in
      the order the controllers connected
    * a controller assigned `:none`, or left with no free player, plays no one (`nil`)

      controllers = Controllers.new() |> Controllers.connect(0, "Xbox Wireless Controller")
      Controllers.slots(controllers, %{"Xbox Wireless Controller" => 2}, 2)
      #=> %{0 => 1}
  """

  @enforce_keys [:connected]
  defstruct [:connected]

  @type device :: non_neg_integer()
  @type assignments :: %{String.t() => pos_integer() | :none}
  @type t :: %__MODULE__{connected: [{device(), String.t()}]}

  @doc "No controllers seen."
  @spec new() :: t()
  def new, do: %__MODULE__{connected: []}

  @doc "The controllers with `device` connected under `name`, numbered when the name is taken."
  @spec connect(t(), device(), String.t()) :: t()
  def connect(%__MODULE__{connected: connected} = controllers, device, name) do
    connected = List.keydelete(connected, device, 0)
    %{controllers | connected: connected ++ [{device, unique(connected, name)}]}
  end

  @doc "The name `device` connected under, or `nil` when it is not connected."
  @spec name(t(), device()) :: String.t() | nil
  def name(%__MODULE__{connected: connected}, device) do
    case List.keyfind(connected, device, 0) do
      {^device, name} -> name
      nil -> nil
    end
  end

  @doc "The controllers without `device`."
  @spec disconnect(t(), device()) :: t()
  def disconnect(%__MODULE__{connected: connected} = controllers, device),
    do: %{controllers | connected: List.keydelete(connected, device, 0)}

  @doc "The controllers with `device` known, named `\"controller <device>\"` when it was not already."
  @spec seen(t(), device()) :: t()
  def seen(%__MODULE__{connected: connected} = controllers, device) do
    if List.keymember?(connected, device, 0),
      do: controllers,
      else: connect(controllers, device, "controller #{device}")
  end

  @doc "Whether `device` is known."
  @spec known?(t(), device()) :: boolean()
  def known?(%__MODULE__{connected: connected}, device), do: List.keymember?(connected, device, 0)

  @doc "Each connected controller's slot, or `nil`, for `players` players under `assignments`."
  @spec slots(t(), assignments(), pos_integer()) :: %{device() => non_neg_integer() | nil}
  def slots(%__MODULE__{connected: connected}, assignments, players) do
    {assigned, taken} =
      Enum.reduce(connected, {%{}, MapSet.new()}, fn {device, name}, acc ->
        claim(acc, device, Map.get(assignments, name), players)
      end)

    {assigned, _taken} =
      Enum.reduce(connected, {assigned, taken}, fn {device, name}, {assigned, taken} ->
        cond do
          Map.has_key?(assigned, device) ->
            {assigned, taken}

          Map.get(assignments, name) == :none ->
            {Map.put(assigned, device, nil), taken}

          true ->
            free = Enum.find(0..(players - 1)//1, &(not MapSet.member?(taken, &1)))
            {Map.put(assigned, device, free), if(free, do: MapSet.put(taken, free), else: taken)}
        end
      end)

    assigned
  end

  @doc "The connected controllers, in the order they connected, each `%{name, player}` with `player` its number or `nil`."
  @spec listed(t(), %{device() => non_neg_integer() | nil}) :: [
          %{name: String.t(), player: pos_integer() | nil}
        ]
  def listed(%__MODULE__{connected: connected}, slots) do
    for {device, name} <- connected, do: %{name: name, player: player(Map.get(slots, device))}
  end

  defp claim({assigned, taken}, device, player, players)
       when is_integer(player) and player in 1..players//1 do
    if MapSet.member?(taken, player - 1),
      do: {assigned, taken},
      else: {Map.put(assigned, device, player - 1), MapSet.put(taken, player - 1)}
  end

  defp claim(acc, _device, _player, _players), do: acc

  defp player(nil), do: nil
  defp player(slot), do: slot + 1

  defp unique(connected, name) do
    names = MapSet.new(connected, &elem(&1, 1))

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> name
      count -> "#{name} ##{count}"
    end)
    |> Enum.find(&(not MapSet.member?(names, &1)))
  end
end
