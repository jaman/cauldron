defmodule Cauldron.Scores do
  @moduledoc """
  A local high-score table: the best scores, best first, each a map with at least a
  `:score` and whatever else the game keeps with it (initials, the level reached). It is
  kept in the game's data directory as `scores.terms` (`Cauldron.Paths.data/2`, the
  game's home named as `Cauldron.Client.Game.home/1` gives it).

      table = Cauldron.Scores.read(:my_game)

      if Cauldron.Scores.qualifies?(table, 4200) do
        table = Cauldron.Scores.add(table, %{initials: "ABC", score: 4200})
        Cauldron.Scores.write(:my_game, table)
      end

  A table kept as `scores.exs` (an Elixir list of maps written out as text) is read when
  there is no `scores.terms`, as data only; nothing in it is run.
  """

  alias Cauldron.Paths

  @keep 8

  @type entry :: %{required(:score) => number(), optional(atom()) => term()}

  @doc "The table kept for `home`, best first; empty when none is kept."
  @spec read(Paths.game()) :: [entry()]
  def read(home) do
    case File.read(Paths.data(home, "scores.terms")) do
      {:ok, binary} -> :erlang.binary_to_term(binary, [:safe])
      {:error, _none} -> read_text(Paths.data(home, "scores.exs"))
    end
  end

  @doc "Keep `table` for `home`."
  @spec write(Paths.game(), [entry()]) :: :ok
  def write(home, table) do
    file = Paths.data(home, "scores.terms")
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, :erlang.term_to_binary(table))
  end

  @doc "Whether `score` earns a place on `table` of the best `keep` (default 8); a score of nought never does."
  @spec qualifies?([entry()], number(), pos_integer()) :: boolean()
  def qualifies?(table, score, keep \\ @keep)
  def qualifies?(_table, score, _keep) when score <= 0, do: false
  def qualifies?(table, _score, keep) when length(table) < keep, do: true
  def qualifies?(table, score, _keep), do: score > table |> List.last() |> Map.fetch!(:score)

  @doc "`table` with `entry` in its place, keeping the best `keep` (default 8)."
  @spec add([entry()], entry(), pos_integer()) :: [entry()]
  def add(table, entry, keep \\ @keep),
    do: [entry | table] |> Enum.sort_by(& &1.score, :desc) |> Enum.take(keep)

  defp read_text(file) do
    with {:ok, text} <- File.read(file),
         {:ok, quoted} <- Code.string_to_quoted(text),
         {:ok, table} <- literal(quoted) do
      table
    else
      _unreadable -> []
    end
  end

  defp literal(list) when is_list(list), do: all(list, [])

  defp literal({:%{}, _meta, pairs}),
    do: with({:ok, pairs} <- all(pairs, []), do: {:ok, Map.new(pairs)})

  defp literal({key, value}), do: with({:ok, [k, v]} <- all([key, value], []), do: {:ok, {k, v}})

  defp literal(value) when is_binary(value) or is_number(value) or is_atom(value),
    do: {:ok, value}

  defp literal(_other), do: :error

  defp all([], done), do: {:ok, Enum.reverse(done)}

  defp all([item | rest], done) do
    case literal(item) do
      {:ok, value} -> all(rest, [value | done])
      :error -> :error
    end
  end
end
