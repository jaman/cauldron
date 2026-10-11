defmodule Cauldron2D.Grid.Coarse.Search do
  @moduledoc """
  A* over a graph given as functions, as `Cauldron2D.Grid.Coarse` searches its regions
  and its tiles.

      Search.run(start, &(&1 == goal), fn node -> [{next, cost}] end, fn node -> estimate end)

  `arrived?` says a node ends the search, `steps` gives each node's neighbours with the
  cost of stepping to them (positive), and `estimate` the least cost still to go from a
  node, never more than the true cost. The result is the cheapest way as its nodes, the
  start first and the node arrived at last, or `:none` when no node reachable arrives.
  """

  @type step :: {term(), number()}

  @doc "The cheapest way from `start` to a node `arrived?` accepts; see the module documentation."
  @spec run(term(), (term() -> boolean()), (term() -> [step()]), (term() -> number())) ::
          {:ok, [term()]} | :none
  def run(start, arrived?, steps, estimate) do
    search(
      :gb_sets.singleton({estimate.(start), 0, start}),
      %{start => {0, nil}},
      %{arrived?: arrived?, steps: steps, estimate: estimate}
    )
  end

  defp search(open, seen, graph) do
    if :gb_sets.is_empty(open),
      do: :none,
      else: visit(:gb_sets.take_smallest(open), seen, graph)
  end

  defp visit({{_estimate, cost, node}, open}, seen, graph) do
    {known, _previous} = Map.fetch!(seen, node)

    cond do
      cost > known -> search(open, seen, graph)
      graph.arrived?.(node) -> {:ok, walk_back(seen, node, [])}
      true -> expand(open, seen, graph, node, cost)
    end
  end

  defp expand(open, seen, graph, node, cost) do
    {open, seen} =
      node
      |> graph.steps.()
      |> Enum.reduce({open, seen}, &relax(&1, &2, node, cost, graph))

    search(open, seen, graph)
  end

  defp relax({next, step}, {open, seen} = acc, node, cost, graph) do
    total = cost + step

    case Map.get(seen, next) do
      {known, _previous} when known <= total ->
        acc

      _unseen_or_dearer ->
        {:gb_sets.add({total + graph.estimate.(next), total, next}, open),
         Map.put(seen, next, {total, node})}
    end
  end

  defp walk_back(seen, node, path) do
    case Map.fetch!(seen, node) do
      {_cost, nil} -> [node | path]
      {_cost, previous} -> walk_back(seen, previous, [node | path])
    end
  end
end
