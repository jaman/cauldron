defmodule Cauldron2D.Client.Hud do
  @moduledoc """
  The shapes a game's hud comes in, and one form every front end reads.

  A hud is rows of runs — `[row]` drawn under the world — or `%{left: [row], width:
  columns, bottom: [row]}`, a column of rows beside the world and rows under both. A
  row is `[run]` or `{tag, [run]}`, the tag naming the row for a front end that styles
  or hides rows by name. A run is text, `{text, colour}` or `{text, style}`, `colour`
  an `{r, g, b}` or `nil` and `style` a map with `:fg` (an `{r, g, b}` or a colour
  name `Linocut.Palette` knows) and `:bold`.
  """

  @type rgb :: {byte(), byte(), byte()}
  @type style :: %{optional(:fg) => rgb() | atom(), optional(:bold) => boolean()}
  @type run :: String.t() | {String.t(), rgb() | nil} | {String.t(), style()}
  @type row :: [run()] | {atom(), [run()]}
  @type t ::
          [row()]
          | %{
              required(:left) => [row()],
              required(:width) => pos_integer(),
              optional(:bottom) => [row()]
            }

  @doc "The runs of a row as `{text, style}` pairs."
  @spec runs(row()) :: [{String.t(), style()}]
  def runs({tag, runs}) when is_atom(tag), do: runs(runs)
  def runs(runs) when is_list(runs), do: Enum.map(runs, &run/1)

  defp run(text) when is_binary(text), do: {text, %{}}
  defp run({text, nil}), do: {text, %{}}
  defp run({text, {r, g, b}}), do: {text, %{fg: {r, g, b}}}
  defp run({text, style}) when is_map(style), do: {text, style}

  @doc "A row's tag, or `nil`."
  @spec tag(row()) :: atom() | nil
  def tag({tag, _runs}) when is_atom(tag), do: tag
  def tag(_runs), do: nil

  @doc "The hud as a column of rows, its width in cells, and the rows under the world."
  @spec layout(t()) :: %{left: [row()], width: non_neg_integer(), bottom: [row()]}
  def layout(rows) when is_list(rows), do: %{left: [], width: 0, bottom: rows}

  def layout(%{left: left, width: width} = hud),
    do: %{left: left, width: width, bottom: Map.get(hud, :bottom, [])}

  @doc "Every row in reading order: the column, then the rows under."
  @spec rows(t()) :: [row()]
  def rows(hud) do
    %{left: left, bottom: bottom} = layout(hud)
    left ++ bottom
  end

  @doc "A row's text with no styling."
  @spec text(row()) :: String.t()
  def text(row), do: row |> runs() |> Enum.map_join(&elem(&1, 0))

  @doc "A run's foreground as `{r, g, b}`, or `nil`."
  @spec colour({String.t(), style()}) :: rgb() | nil
  def colour({_text, style}) do
    case Map.get(style, :fg) do
      nil ->
        nil

      {r, g, b} ->
        {r, g, b}

      name when is_atom(name) ->
        name |> Linocut.Palette.color() |> then(fn {r, g, b, _a} -> {r, g, b} end)
    end
  end
end
