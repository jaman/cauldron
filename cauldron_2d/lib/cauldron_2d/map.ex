defmodule Cauldron2D.Map do
  @moduledoc """
  A tile map written as text: a grid of characters, one per tile, with optional
  `name: value` options ahead of it.

  Two layouts are read:

    * a bare picture — every line is a row:

          ####
          #..#
          ####

    * the header format of XPilot's map files — options, then the grid between the
      multiline markers:

          mapwidth: 6
          mapheight: 3
          edgewrap: yes
          mapData: \\multiline: EndOfMapdata
          xxxxxx
          x _  x
          xxxxxx
          EndOfMapdata

  The engine attaches no meaning to any character, and to no option but the two that
  size the grid (`mapwidth`, `mapheight`) and the one `parse/2` is told wraps it. A game
  supplies a legend to `cells/2` and reads the options it honours with `option/4`. Option
  names are matched without regard to case.

  A map wraps when the option named by `:wrap` is true: `at/2` outside the grid then
  reads the tile on the opposite side, and otherwise reads a space.
  """

  @type point :: {integer(), integer()}
  @type t :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          rows: tuple(),
          options: %{String.t() => String.t()},
          wrap?: boolean()
        }

  defstruct [:width, :height, :rows, options: %{}, wrap?: false]

  @multiline ~r/\A\s*mapdata\s*:\s*\\multiline\s*:\s*(\S+)\s*\z/i
  @option ~r/\A\s*([A-Za-z][A-Za-z0-9_]*)\s*:\s*(.*?)\s*\z/

  @doc """
  Parse map text.

  Returns `{:ok, map}`, or `{:error, :empty}` for no rows at all. A multiline block with
  no closing marker runs to the end of the text; a row wider than `mapwidth` is cut to it
  and a shorter one padded with spaces; rows beyond `mapheight` are dropped and missing
  ones are blank.

  ## Options

    * `:wrap` — the name of the header option that, when true, makes the map wrap
      (`"edgewrap"` in XPilot's files). Default: none, the map never wraps
  """
  @spec parse(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def parse(text, opts \\ []) when is_binary(text) do
    lines = text |> String.replace("\r\n", "\n") |> String.split("\n")

    result =
      case Enum.find_index(lines, &Regex.match?(@multiline, &1)) do
        nil -> picture(lines)
        index -> classic(Enum.take(lines, index), Enum.drop(lines, index))
      end

    with {:ok, map} <- result, do: {:ok, %{map | wrap?: wraps?(map, Keyword.get(opts, :wrap))}}
  end

  defp wraps?(_map, nil), do: false
  defp wraps?(map, option), do: truthy?(Map.get(map.options, String.downcase(option)))

  @doc "Read and parse a file, with `parse/2`'s options; a `.gz` file is decompressed first."
  @spec parse_file(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def parse_file(path, opts \\ []) do
    with {:ok, bytes} <- File.read(path) do
      bytes |> maybe_gunzip(path) |> parse(opts)
    end
  end

  defp maybe_gunzip(bytes, path) do
    if String.ends_with?(path, ".gz"), do: :zlib.gunzip(bytes), else: bytes
  end

  defp picture(lines) do
    rows =
      lines
      |> Enum.drop_while(&blank?/1)
      |> Enum.reverse()
      |> Enum.drop_while(&blank?/1)
      |> Enum.reverse()

    case rows do
      [] -> {:error, :empty}
      rows -> build(rows, %{}, rows |> Enum.map(&String.length/1) |> Enum.max(), length(rows))
    end
  end

  defp blank?(line), do: String.trim(line) == ""

  defp trim_trailing_blank(rows) do
    rows |> Enum.reverse() |> Enum.drop_while(&blank?/1) |> Enum.reverse()
  end

  defp classic(header, [marker | body]) do
    [_, terminator] = Regex.run(@multiline, marker)
    options = options(header)

    rows = body |> Enum.take_while(&(String.trim(&1) != terminator)) |> trim_trailing_blank()

    width =
      int_option(options, "mapwidth") ||
        rows |> Enum.map(&String.length/1) |> Enum.max(fn -> 0 end)

    height = int_option(options, "mapheight") || length(rows)
    build(rows, options, width, height)
  end

  defp options(header) do
    for line <- header, [_, key, value] <- [Regex.run(@option, line)], into: %{} do
      {String.downcase(key), value}
    end
  end

  defp int_option(options, key) do
    case Map.fetch(options, key) do
      {:ok, value} -> parse_int(value)
      :error -> nil
    end
  end

  defp parse_int(value) do
    case Integer.parse(String.trim(value)) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp build(_rows, _options, width, height) when width <= 0 or height <= 0, do: {:error, :empty}

  defp build(rows, options, width, height) do
    {:ok,
     %__MODULE__{
       width: width,
       height: height,
       rows: fit(rows, width, height),
       options: options,
       wrap?: false
     }}
  end

  defp fit(rows, width, height) do
    blank = List.duplicate(" ", width)

    rows
    |> Enum.take(height)
    |> Enum.map(&fit_row(&1, width))
    |> Kernel.++(List.duplicate(blank, max(0, height - length(rows))))
    |> Enum.map(&List.to_tuple/1)
    |> List.to_tuple()
  end

  defp fit_row(row, width) do
    graphemes = String.graphemes(row)
    Enum.take(graphemes ++ List.duplicate(" ", max(0, width - length(graphemes))), width)
  end

  @doc "The character at `{x, y}`; a space outside the grid, or the wrapped tile when the map wraps."
  @spec at(t(), point()) :: String.t()
  def at(%__MODULE__{wrap?: true} = map, {x, y}) do
    elem(elem(map.rows, Integer.mod(y, map.height)), Integer.mod(x, map.width))
  end

  def at(%__MODULE__{} = map, {x, y})
      when x >= 0 and y >= 0 and x < map.width and y < map.height do
    elem(elem(map.rows, y), x)
  end

  def at(%__MODULE__{}, _point), do: " "

  @doc """
  An option converted to `type`, or `default` when absent or not of that type.

  `type` is `:string`, `:integer`, `:float` or `:boolean`. Booleans read `yes`, `true`,
  `on` and `1` as true and `no`, `false`, `off` and `0` as false.
  """
  @spec option(t(), String.t(), :string | :integer | :float | :boolean, term()) :: term()
  def option(%__MODULE__{options: options}, name, type, default) do
    case Map.fetch(options, String.downcase(name)) do
      {:ok, value} -> convert(type, String.trim(value), default)
      :error -> default
    end
  end

  defp convert(:string, value, _default), do: value

  defp convert(:integer, value, default) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> default
    end
  end

  defp convert(:float, value, default) do
    case Float.parse(value) do
      {float, ""} -> float
      _ -> default
    end
  end

  defp convert(:boolean, value, default) do
    case String.downcase(value) do
      yes when yes in ["yes", "true", "on", "1"] -> true
      no when no in ["no", "false", "off", "0"] -> false
      _ -> default
    end
  end

  defp truthy?(nil), do: false
  defp truthy?(value), do: convert(:boolean, String.trim(value), false)

  @doc """
  Every tile the legend gives a value for, as `%{{x, y} => value}`.

  `legend` is called with each character; a `nil` return leaves that tile out.
  """
  @spec cells(t(), (String.t() -> term())) :: %{point() => term()}
  def cells(%__MODULE__{} = map, legend) when is_function(legend, 1) do
    for y <- 0..(map.height - 1),
        x <- 0..(map.width - 1),
        value = legend.(at(map, {x, y})),
        value != nil,
        into: %{},
        do: {{x, y}, value}
  end

  @doc "Where `char` occurs, row by row then left to right."
  @spec positions(t(), String.t()) :: [point()]
  def positions(%__MODULE__{} = map, char) do
    for y <- 0..(map.height - 1), x <- 0..(map.width - 1), at(map, {x, y}) == char, do: {x, y}
  end
end
