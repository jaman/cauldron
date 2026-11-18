defmodule Cauldron2D.Assets.Lock do
  @moduledoc """
  `assets.lock.exs` beside a game's `assets.exs`: for each asset, the digest of the spec
  it was made from, the candidates the Studio made (their library ids and files), and
  the one chosen. Kept in the repository, so the same art is rebuilt from the Studio's
  library without asking the model again.

      %{jar: %{digest: 1234, candidates: [%{id: "...", path: "...", url: "..."}], pick: 2}}
  """

  @type candidate :: %{
          id: String.t(),
          path: String.t() | nil,
          url: String.t() | nil,
          seed: integer() | nil
        }
  @type entry :: %{
          digest: non_neg_integer(),
          candidates: [candidate()],
          pick: non_neg_integer() | nil
        }
  @type t :: %{atom() => entry()}

  @doc "The lock in `path`, empty when there is none."
  @spec read(Path.t()) :: t()
  def read(path) do
    case File.read(path) do
      {:ok, text} -> text |> Code.string_to_quoted!(file: path) |> literal!(path)
      {:error, :enoent} -> %{}
    end
  end

  # `write/2` writes a literal term, so read one back as data. A lock holding anything
  # else — a call, an alias, a function — is refused instead of evaluated.
  defp literal!(ast, path) do
    if literal?(ast) do
      {value, _binding} = Code.eval_quoted(ast, [], file: path)
      value
    else
      raise ArgumentError, "#{path} is not an asset lock: it holds code, not data"
    end
  end

  defp literal?(ast) when is_list(ast), do: Enum.all?(ast, &literal?/1)

  defp literal?({:%{}, _meta, pairs}),
    do: Enum.all?(pairs, fn {key, value} -> literal?(key) and literal?(value) end)

  defp literal?({:{}, _meta, items}), do: Enum.all?(items, &literal?/1)
  defp literal?({:__block__, _meta, [item]}), do: literal?(item)
  defp literal?({:-, _meta, [number]}) when is_number(number), do: true

  defp literal?(value) when is_atom(value) or is_binary(value) or is_number(value), do: true
  defp literal?(_other), do: false

  @doc "Write `lock` to `path`."
  @spec write(Path.t(), t()) :: :ok
  def write(path, lock) do
    File.write!(
      path,
      inspect(lock, pretty: true, limit: :infinity, printable_limit: :infinity) <> "\n"
    )
  end

  @doc "`lock` with candidate `index` of asset `name` chosen."
  @spec pick(t(), atom(), non_neg_integer()) :: {:ok, t()} | {:error, term()}
  def pick(lock, name, index) do
    case Map.fetch(lock, name) do
      {:ok, %{candidates: candidates} = entry} when index < length(candidates) ->
        {:ok, Map.put(lock, name, %{entry | pick: index})}

      {:ok, _entry} ->
        {:error, {:no_candidate, name, index}}

      :error ->
        {:error, {:no_asset, name}}
    end
  end
end
