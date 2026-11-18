defmodule Cauldron.World.Pending do
  @moduledoc """
  The input each player has sent since a world's last step, waiting for the next one.

  A step applies each player's latest input, with every action held in any of the
  inputs they sent since the last step added to its `:held`, so a press that begins and
  ends between two steps still counts for one step. When that added an action, the
  latest input as it was sent stays waiting and is applied at the following step, so the
  release arrives too. Input that is not a map with a `:held` set is applied as sent.

      pending = Pending.new() |> Pending.put(:alice, %{held: MapSet.new([:jump]), aim: nil})
      pending = Pending.put(pending, :alice, %{held: MapSet.new(), aim: nil})
      Pending.inputs(pending)
      #=> [{:alice, %{held: MapSet.new([:jump]), aim: nil}}]
      Pending.stepped(pending) |> Pending.inputs()
      #=> [{:alice, %{held: MapSet.new(), aim: nil}}]
  """

  @type entry :: %{latest: term(), held: MapSet.t() | nil}
  @type t :: %{term() => entry()}

  @doc "Nothing waiting."
  @spec new() :: t()
  def new, do: %{}

  @doc "Add `input`, the latest from player `id`."
  @spec put(t(), term(), term()) :: t()
  def put(pending, id, %{held: %MapSet{} = held} = input) do
    Map.update(pending, id, %{latest: input, held: held}, fn
      %{held: %MapSet{} = before} -> %{latest: input, held: MapSet.union(before, held)}
      _sent_as_is -> %{latest: input, held: held}
    end)
  end

  def put(pending, id, input), do: Map.put(pending, id, %{latest: input, held: nil})

  @doc "Forget what player `id` sent."
  @spec delete(t(), term()) :: t()
  def delete(pending, id), do: Map.delete(pending, id)

  @doc "The input to apply at this step, per player."
  @spec inputs(t()) :: [{term(), term()}]
  def inputs(pending), do: Enum.map(pending, fn {id, entry} -> {id, applied(entry)} end)

  @doc "What stays waiting once a step has applied `inputs/1`: each latest input that differed from what was applied."
  @spec stepped(t()) :: t()
  def stepped(pending) do
    for {id, %{latest: latest} = entry} <- pending, applied(entry) != latest, into: %{} do
      {id, %{latest: latest, held: latest.held}}
    end
  end

  defp applied(%{latest: latest, held: nil}), do: latest
  defp applied(%{latest: latest, held: held}), do: %{latest | held: held}
end
