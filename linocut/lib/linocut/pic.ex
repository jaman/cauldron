defmodule Linocut.Pic do
  @moduledoc """
  A picture kept in a file: a palette, a blank line, and the picture.

      R #c33
      W white

      ..RR..
      .RWWR.

  Each palette line is one character, a space, and a colour as `Linocut.Palette` reads
  it: `#rgb`, `#rrggbb`, `#rrggbbaa` or a colour name. `.` and space in the picture are
  transparent. `parse/2` takes `Linocut.sprite/3`'s options.
  """

  alias FrenchCurve.Raster
  alias Linocut.Palette

  @separator "---"

  @doc """
  The raster the text describes, or why it could not be read.

  Frames separated by a `---` line come back as one raster with the frames side by
  side, left to right, as a strip; `frames/2` gives them one by one.
  """
  @spec parse(String.t(), keyword()) :: {:ok, Raster.t()} | {:error, term()}
  def parse(text, opts \\ []) do
    with {:ok, frames} <- frames(text, opts), do: {:ok, strip(frames)}
  end

  @doc "The frames the text describes, one raster each, or why it could not be read."
  @spec frames(String.t(), keyword()) :: {:ok, [Raster.t()]} | {:error, term()}
  def frames(text, opts \\ []) do
    case String.split(text, ~r/\r?\n\s*\r?\n/, parts: 2) do
      [header, pictures] ->
        with {:ok, palette} <- palette(header) do
          {:ok,
           pictures
           |> String.split(~r/\r?\n---\r?\n/)
           |> Enum.map(&Linocut.sprite(&1, palette, opts))}
        end

      _no_blank_line ->
        {:error, :no_picture}
    end
  end

  @doc "The line that separates frames in a pic."
  @spec separator() :: String.t()
  def separator, do: @separator

  @type text :: %{palette: [{String.t(), String.t()}], frames: [[String.t()]]}

  @doc """
  The text as data, nothing rendered: the palette as `{key, colour_spec}` pairs in the
  order written, and the frames as their rows of keys. `write/1` turns it back.

  ## Examples

      iex> Linocut.Pic.read("R #c33\\n\\n.R\\nR.\\n---\\nR.\\n.R\\n")
      {:ok, %{palette: [{"R", "#c33"}], frames: [[".R", "R."], ["R.", ".R"]]}}

  """
  @spec read(String.t()) :: {:ok, text()} | {:error, term()}
  def read(text) do
    case String.split(text, ~r/\r?\n\s*\r?\n/, parts: 2) do
      [header, pictures] ->
        with {:ok, palette} <- palette_lines(header) do
          {:ok,
           %{
             palette: palette,
             frames: pictures |> String.split(~r/\r?\n---\r?\n/) |> Enum.map(&rows/1)
           }}
        end

      _no_blank_line ->
        {:error, :no_picture}
    end
  end

  @doc "The text of a picture given as `read/1` gives it."
  @spec write(text()) :: String.t()
  def write(%{palette: palette, frames: frames}) do
    Enum.map_join(palette, "", fn {key, spec} -> key <> " " <> spec <> "\n" end) <>
      "\n" <>
      Enum.map_join(frames, "\n" <> @separator <> "\n", &(Enum.join(&1, "\n") <> "\n"))
  end

  defp rows(picture), do: picture |> String.split(~r/\r?\n/) |> Enum.reject(&(&1 == ""))

  defp palette_lines(header) do
    header
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, acc} ->
      case String.split(String.trim(line), " ", parts: 2, trim: true) do
        [key, spec] when byte_size(key) > 0 -> {:cont, {:ok, acc ++ [{key, String.trim(spec)}]}}
        _other -> {:halt, {:error, {:palette_line, line}}}
      end
    end)
  end

  defp strip([raster]), do: raster

  defp strip(rasters) do
    {width, height} = Raster.dimensions(hd(rasters))
    canvas = Raster.new(width * length(rasters), height)

    for {raster, index} <- Enum.with_index(rasters),
        y <- 0..(height - 1)//1,
        x <- 0..(width - 1)//1,
        reduce: canvas do
      acc -> Raster.put_pixel(acc, index * width + x, y, Raster.get_pixel(raster, x, y))
    end
  end

  defp palette(header) do
    header
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.reduce_while({:ok, %{}}, fn line, {:ok, acc} ->
      case entry(line) do
        {:ok, char, colour} -> {:cont, {:ok, Map.put(acc, char, colour)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp entry(line) do
    case String.split(String.trim(line), " ", parts: 2, trim: true) do
      [char, spec] when byte_size(char) > 0 -> colour(char, String.trim(spec))
      _other -> {:error, {:palette_line, line}}
    end
  end

  defp colour(char, spec) do
    {:ok, char, Palette.color(spec_term(spec))}
  rescue
    ArgumentError -> {:error, {:colour, char, spec}}
  end

  defp spec_term("#" <> _ = hex), do: hex

  defp spec_term(name) do
    case Enum.find(Palette.names(), &(Atom.to_string(&1) == name)) do
      nil -> name
      atom -> atom
    end
  end
end
