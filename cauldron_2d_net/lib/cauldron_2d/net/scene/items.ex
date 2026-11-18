defmodule Cauldron2D.Net.Scene.Items do
  @moduledoc """
  The parts of a scene that are plain data — movers, labels, volumes, `:screen` items,
  outlines — written as JSON can carry them and read back into the terms
  `Cauldron2D.Draw` takes. Arts are named by name: an atom by
  its name, any other term by `inspect/1`; `read_*` functions take `arts`, the names to
  the atlas's own art terms.

  ## Shapes on the wire

    * mover — `[art, x, y, heading, tint]`, `heading` and `tint` `null` when absent
    * label — `[text, x, y, [r, g, b], scale, [r, g, b] | null]`, the last the background
    * volume — `%{at, shape, colour, strength, falloff}`: `at` `[x, y]` or `[x, y, z]`,
      `shape` `[kind, ...]` (`:cells` as `["cells", [[x, y], ...], height]`), `colour`
      `[r, g, b]`, `falloff` `"depth"`, `"flat"` or `"shell"`
    * screen item — `[kind, ...]` in the order `Cauldron2D.Screen` lists the item's
      parts, points and sizes as pairs, colours as lists, the options last as an object
      whose colours are lists and whose atoms are strings; `:pane` as `"pane"`
    * outline — `[left, top, right, bottom, [r, g, b, a]]`

  Only the shapes `Cauldron2D.Projection.Volume.Shapes` knows go over the wire;
  `portable?/1` says whether a volume's does.
  """

  alias Cauldron2D.Projection.Volume.Shapes

  @option_atoms ~w(anchor pivot align direction falloff)a
  @option_colours ~w(colour shadow outline tint background)a
  @anchors ~w(top_left top top_right left centre right bottom_left bottom bottom_right)a
  @words @anchors ++ ~w(up down left right centre center depth flat shell)a

  @doc "An art's name on the wire."
  @spec art_name(term()) :: String.t()
  def art_name(art) when is_atom(art), do: Atom.to_string(art)
  def art_name(art), do: inspect(art)

  @doc "The names of `atlas`'s arts to the arts, for the `read_*` functions."
  @spec arts(Cauldron2D.Atlas.t()) :: %{String.t() => term()}
  def arts(atlas), do: Map.new(Map.keys(atlas.entries), &{art_name(&1), &1})

  @doc "Whether a volume's shape is one the engine knows, so a client can draw it."
  @spec portable?(map() | keyword()) :: boolean()
  def portable?(volume) do
    case Map.get(Map.new(volume), :shape) do
      nil -> true
      shape when is_tuple(shape) -> elem(shape, 0) in Shapes.kinds()
      _other -> false
    end
  end

  @doc "A mover on the wire."
  @spec mover(tuple()) :: list()
  def mover({art, {x, y}}), do: [art_name(art), x / 1, y / 1, nil, nil]
  def mover({art, {x, y}, heading}), do: [art_name(art), x / 1, y / 1, number(heading), nil]

  def mover({art, {x, y}, heading, opts}),
    do: [art_name(art), x / 1, y / 1, number(heading), tint_name(Map.get(opts, :tint))]

  @doc "A mover read back."
  @spec read_mover(list(), map()) :: tuple()
  def read_mover([art, x, y, nil, nil], arts), do: {Map.fetch!(arts, art), {x, y}}
  def read_mover([art, x, y, heading, nil], arts), do: {Map.fetch!(arts, art), {x, y}, heading}

  def read_mover([art, x, y, heading, tint], arts),
    do: {Map.fetch!(arts, art), {x, y}, heading, %{tint: String.to_existing_atom(tint)}}

  @doc "A label on the wire."
  @spec label(tuple()) :: list()
  def label({text, {x, y}, colour}), do: [text, x / 1, y / 1, rgb(colour), 1, nil]

  def label({text, {x, y}, colour, opts}),
    do: [
      text,
      x / 1,
      y / 1,
      rgb(colour),
      Keyword.get(opts, :scale, 1),
      rgb(Keyword.get(opts, :background))
    ]

  @doc "A label read back."
  @spec read_label(list()) :: tuple()
  def read_label([text, x, y, colour, 1, nil]), do: {text, {x, y}, tuple(colour)}

  def read_label([text, x, y, colour, scale, background]),
    do:
      {text, {x, y}, tuple(colour),
       [scale: scale] ++ if(background, do: [background: tuple(background)], else: [])}

  @doc "A volume on the wire."
  @spec volume(map() | keyword()) :: map()
  def volume(volume) do
    volume = Map.new(volume)

    %{
      at: Tuple.to_list(volume.at),
      shape: shape(Map.get(volume, :shape, {:sphere, 1.0, 0.0})),
      colour: rgb(Map.get(volume, :colour, {255, 255, 255})),
      strength: Map.get(volume, :strength, 0.5),
      falloff: Atom.to_string(Map.get(volume, :falloff, :depth))
    }
  end

  @doc "A volume read back."
  @spec read_volume(map()) :: map()
  def read_volume(volume) do
    %{
      at: List.to_tuple(fetch(volume, :at)),
      shape: read_shape(fetch(volume, :shape)),
      colour: tuple(fetch(volume, :colour)),
      strength: fetch(volume, :strength),
      falloff: word(fetch(volume, :falloff))
    }
  end

  @doc "A `:screen` item on the wire."
  @spec screen_item(tuple()) :: list()
  def screen_item(item) do
    {[kind | rest], opts} = split_options(Tuple.to_list(item))
    [Atom.to_string(kind) | parts(kind, rest)] ++ [options(opts)]
  end

  @doc "A `:screen` item read back."
  @spec read_screen_item(list(), map()) :: tuple()
  def read_screen_item([kind | rest], arts) do
    {parts, [opts]} = Enum.split(rest, -1)
    kind = String.to_existing_atom(kind)
    List.to_tuple([kind | read_parts(kind, parts, arts)] ++ optioned(read_options(opts)))
  end

  defp optioned([]), do: []
  defp optioned(opts), do: [opts]

  @doc "An outline on the wire."
  @spec outline(tuple()) :: list()
  def outline({{left, top, right, bottom}, colour}),
    do: [left / 1, top / 1, right / 1, bottom / 1, Tuple.to_list(colour)]

  @doc "An outline read back."
  @spec read_outline(list()) :: tuple()
  def read_outline([left, top, right, bottom, colour]),
    do: {{left, top, right, bottom}, List.to_tuple(colour)}

  @doc "A tint's name on the wire, `nil` for none."
  @spec tint_name(atom() | nil) :: String.t() | nil
  def tint_name(nil), do: nil
  def tint_name(tint) when is_atom(tint), do: Atom.to_string(tint)

  @doc "A tint read back."
  @spec read_tint(String.t() | nil) :: atom() | nil
  def read_tint(nil), do: nil
  def read_tint(name), do: String.to_existing_atom(name)

  defp split_options(parts) do
    case List.last(parts) do
      opts when is_list(opts) and opts != [] -> {Enum.drop(parts, -1), opts}
      [] -> {Enum.drop(parts, -1), []}
      _other -> {parts, []}
    end
  end

  defp parts(:art, [art, at]), do: [art_name(art), pair(at)]
  defp parts(:text, [font, text, at]), do: [Atom.to_string(font), text, pair(at)]
  defp parts(:panel, [art, at, size]), do: [art_name(art), pair(at), pair(size)]
  defp parts(:bar, [art, at, fraction]), do: [art_name(art), pair(at), fraction]
  defp parts(:fill, [at, :pane, rgba]), do: [pair(at), "pane", Tuple.to_list(rgba)]

  defp parts(kind, [at, size, rgba]) when kind in [:fill, :box],
    do: [pair(at), pair(size), Tuple.to_list(rgba)]

  defp pair({a, b}), do: [a, b]

  defp read_parts(:art, [art, at], arts), do: [Map.fetch!(arts, art), tuple(at)]

  defp read_parts(:text, [font, text, at], _arts),
    do: [String.to_existing_atom(font), text, tuple(at)]

  defp read_parts(:panel, [art, at, size], arts),
    do: [Map.fetch!(arts, art), tuple(at), tuple(size)]

  defp read_parts(:bar, [art, at, fraction], arts),
    do: [Map.fetch!(arts, art), tuple(at), fraction]

  defp read_parts(:fill, [at, "pane", rgba], _arts), do: [tuple(at), :pane, tuple(rgba)]
  defp read_parts(:fill, [at, size, rgba], _arts), do: [tuple(at), tuple(size), tuple(rgba)]
  defp read_parts(:box, [at, size, rgba], _arts), do: [tuple(at), tuple(size), tuple(rgba)]

  defp options(opts) do
    Map.new(opts, fn
      {key, value} when key in @option_colours -> {Atom.to_string(key), rgb_any(value)}
      {key, value} when key in @option_atoms -> {Atom.to_string(key), Atom.to_string(value)}
      {key, value} -> {Atom.to_string(key), value}
    end)
  end

  defp read_options(opts) do
    Enum.map(opts, fn {key, value} ->
      key = String.to_existing_atom(key)

      cond do
        key in @option_colours and is_list(value) -> {key, List.to_tuple(value)}
        key in @option_atoms -> {key, word(value)}
        true -> {key, value}
      end
    end)
  end

  defp shape({:cells, cells, height}),
    do: ["cells", for({x, y} <- cells, do: [x, y]), height]

  defp shape(shape) when is_tuple(shape) do
    [kind | rest] = Tuple.to_list(shape)
    [Atom.to_string(kind) | rest]
  end

  defp read_shape(["cells", cells, height]),
    do: {:cells, MapSet.new(cells, &List.to_tuple/1), height}

  defp read_shape([kind | rest]), do: List.to_tuple([String.to_existing_atom(kind) | rest])

  defp word(text) do
    atom = String.to_existing_atom(text)
    if atom in @words, do: atom, else: raise(ArgumentError, "not a known word: #{text}")
  end

  defp number(nil), do: nil
  defp number(value), do: value / 1

  defp rgb(nil), do: nil
  defp rgb(colour) when is_tuple(colour), do: Tuple.to_list(colour)
  defp rgb_any(colour) when is_tuple(colour), do: Tuple.to_list(colour)
  defp rgb_any(other), do: other

  defp tuple(list) when is_list(list), do: List.to_tuple(list)

  defp fetch(map, key), do: Map.get_lazy(map, key, fn -> Map.fetch!(map, Atom.to_string(key)) end)
end
