defmodule Cauldron2D.Atlas.Manifest do
  @moduledoc """
  The `atlas.txt` beside an art directory's pictures: what a text renderer draws for
  each art, and how fast its frames go.

      wall	# 	#5a7cf0	
      flame	f 	#ff7000	12
      flame_blue	f 	#3070ff	12	from flame; colour F #3070ff

  One art a line, tab-separated: the name, the glyph (two columns), the colour as
  `#rrggbb`, the frames a second, and, for an art made from another, its derivation
  as `Linocut.Derive` reads it; an empty field leaves that setting to the picture.
  `Cauldron2D.Atlas.load/3` reads it as the defaults under its `:arts`, and builds the
  derived arts after the pictures.
  """

  @file_name "atlas.txt"

  @type entry :: %{
          optional(:glyph) => String.t(),
          optional(:color) => {byte(), byte(), byte()},
          optional(:fps) => pos_integer(),
          optional(:derive) => String.t()
        }
  @type t :: %{atom() => entry()}

  @doc "The manifest's file name."
  @spec file_name() :: String.t()
  def file_name, do: @file_name

  @doc "The manifest in `dir`, empty when there is none."
  @spec read(Path.t()) :: t()
  def read(dir) do
    case File.read(Path.join(dir, @file_name)) do
      {:ok, text} -> parse(text)
      {:error, _} -> %{}
    end
  end

  @doc "The entries the text holds."
  @spec parse(String.t()) :: t()
  def parse(text) do
    for line <- String.split(text, "\n"),
        String.trim(line) != "",
        [name | fields] = String.split(line, "\t"),
        into: %{} do
      {String.to_atom(name), entry(fields)}
    end
  end

  defp entry(fields) do
    [glyph, colour, fps, derive] = Enum.take(fields ++ ["", "", "", ""], 4)

    %{}
    |> put_if(:glyph, if(glyph != "", do: glyph))
    |> put_if(:color, colour(colour))
    |> put_if(:fps, fps(fps))
    |> put_if(:derive, if(String.trim(derive) != "", do: String.trim(derive)))
  end

  @doc "The derived arts, name and derivation, in name order."
  @spec derived(t()) :: [{atom(), String.t()}]
  def derived(manifest) do
    for {name, %{derive: derive}} <-
          Enum.sort_by(manifest, fn {name, _} -> Atom.to_string(name) end),
        do: {name, derive}
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp colour("#" <> hex) when byte_size(hex) == 6,
    do: hex |> Base.decode16!(case: :mixed) |> then(fn <<r, g, b>> -> {r, g, b} end)

  defp colour(_other), do: nil

  defp fps(text) do
    case Integer.parse(String.trim(text)) do
      {n, ""} when n > 0 -> n
      _other -> nil
    end
  end

  @doc "Write the manifest to `dir`, one art a line in name order."
  @spec write(Path.t(), t()) :: :ok | {:error, term()}
  def write(dir, manifest), do: File.write(Path.join(dir, @file_name), render(manifest))

  @doc "The manifest as text."
  @spec render(t()) :: String.t()
  def render(manifest) do
    manifest
    |> Enum.sort_by(fn {name, _} -> Atom.to_string(name) end)
    |> Enum.map_join("", fn {name, entry} ->
      Enum.join(
        [
          Atom.to_string(name),
          Map.get(entry, :glyph, ""),
          hex(Map.get(entry, :color)),
          fps_text(Map.get(entry, :fps))
        ] ++ derive_field(entry),
        "\t"
      ) <> "\n"
    end)
  end

  defp hex(nil), do: ""
  defp hex({r, g, b}), do: "#" <> Base.encode16(<<r, g, b>>, case: :lower)

  defp derive_field(%{derive: derive}), do: [derive]
  defp derive_field(_entry), do: []

  defp fps_text(nil), do: ""
  defp fps_text(fps), do: Integer.to_string(fps)

  @doc "The manifest's entries as `Cauldron2D.Atlas.load/3`'s `:arts`, with `arts` laid over them."
  @spec arts(t(), keyword()) :: keyword()
  def arts(manifest, arts) do
    given = Map.new(arts, fn {name, options} -> {name, Map.new(options)} end)

    manifest
    |> Map.merge(given, fn _name, from_file, from_call -> Map.merge(from_file, from_call) end)
    |> Enum.map(fn {name, options} -> {name, Map.to_list(options)} end)
  end
end
