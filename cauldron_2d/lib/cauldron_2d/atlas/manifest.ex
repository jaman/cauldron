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
  Four more fields make an art stand or pose: its height in storeys, its faces as
  `top=ART side=ART south=ART` (`top`, `side`, `north`, `east`, `south`, `west`), its
  poses as `front=ART back=ART side=ART`, each naming other arts of the same directory,
  and how tall it stands in tiles when drawn as a billboard — the projections draw a
  standing art of no height at its picture's size against the tile unless this says
  otherwise.

      house	# 	#a08060			2	top=roof side=wall south=door
      hero	@ 						front=hero_front back=hero_back side=hero_side	0.75
  `Cauldron2D.Atlas.load/3` reads it as the defaults under its `:arts`, and builds the
  derived arts after the pictures.
  """

  @file_name "atlas.txt"

  @type entry :: %{
          optional(:glyph) => String.t(),
          optional(:color) => {byte(), byte(), byte()},
          optional(:fps) => pos_integer(),
          optional(:derive) => String.t(),
          optional(:height) => non_neg_integer(),
          optional(:faces) => %{atom() => atom()},
          optional(:poses) => %{atom() => atom()},
          optional(:stand) => number()
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

  @faces ~w(top side north east south west)a
  @poses ~w(front back side)a

  defp entry(fields) do
    [glyph, colour, fps, derive, height, faces, poses, stand] =
      Enum.take(fields ++ List.duplicate("", 8), 8)

    %{}
    |> put_if(:glyph, if(glyph != "", do: glyph))
    |> put_if(:color, colour(colour))
    |> put_if(:fps, fps(fps))
    |> put_if(:derive, if(String.trim(derive) != "", do: String.trim(derive)))
    |> put_if(:height, height(height))
    |> put_if(:faces, names(faces, @faces))
    |> put_if(:poses, names(poses, @poses))
    |> put_if(:stand, stand(stand))
  end

  defp stand(text) do
    case Float.parse(String.trim(text)) do
      {tiles, ""} when tiles > 0 -> tiles
      _other -> nil
    end
  end

  defp height(text) do
    case Integer.parse(String.trim(text)) do
      {n, ""} when n >= 0 -> n
      _other -> nil
    end
  end

  defp names(text, allowed) do
    pairs =
      for token <- String.split(text),
          [key, art] <- [String.split(token, "=", parts: 2)],
          key = String.to_atom(key),
          key in allowed,
          art != "",
          into: %{},
          do: {key, String.to_atom(art)}

    if pairs == %{}, do: nil, else: pairs
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
        ] ++ tail_fields(entry),
        "\t"
      ) <> "\n"
    end)
  end

  defp tail_fields(entry) do
    [
      Map.get(entry, :derive, ""),
      height_text(Map.get(entry, :height)),
      names_text(Map.get(entry, :faces), @faces),
      names_text(Map.get(entry, :poses), @poses),
      stand_text(Map.get(entry, :stand))
    ]
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
  end

  defp stand_text(nil), do: ""
  defp stand_text(tiles), do: to_string(tiles)

  defp height_text(nil), do: ""
  defp height_text(height), do: Integer.to_string(height)

  defp names_text(nil, _order), do: ""

  defp names_text(names, order) do
    Enum.map_join(for(key <- order, art = Map.get(names, key), do: "#{key}=#{art}"), " ", & &1)
  end

  defp hex(nil), do: ""
  defp hex({r, g, b}), do: "#" <> Base.encode16(<<r, g, b>>, case: :lower)

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
