defmodule Cauldron2D.Map.Tiled.Xml do
  @moduledoc """
  A Tiled `.tmx` map turned into the shape its `.tmj` (JSON) form decodes to — maps with
  string keys, as `JSON.decode/1` gives them — so `Cauldron2D.Map.Tiled` reads both the
  same way. Tile data stays as written (`csv`, `base64`, or `<tile gid>` elements, as a
  list of numbers); attributes that are numbers become numbers.
  """

  require Record

  Record.defrecordp(
    :element,
    :xmlElement,
    Record.extract(:xmlElement, from_lib: "xmerl/include/xmerl.hrl")
  )

  Record.defrecordp(
    :attribute,
    :xmlAttribute,
    Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl")
  )

  Record.defrecordp(
    :text,
    :xmlText,
    Record.extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl")
  )

  @numbers ~w(width height tilewidth tileheight firstgid columns tilecount x y id gid
              nextlayerid nextobjectid rotation opacity offsetx offsety spacing margin)

  @doc "The map in `xml`, the text of a `.tmx` file, in the shape of its JSON form."
  @spec decode(binary()) :: {:ok, map()} | {:error, term()}
  def decode(xml) do
    {root, _rest} = :xmerl_scan.string(String.to_charlist(xml), quiet: true)
    {:ok, map(root)}
  catch
    :exit, reason -> {:error, {:tmx, reason}}
  end

  defp map(root) do
    root
    |> attributes()
    |> Map.merge(%{
      "tilesets" => for(child <- children(root, :tileset), do: tileset(child)),
      "layers" => layers(root),
      "properties" => properties(root)
    })
  end

  defp tileset(element) do
    image = List.first(children(element, :image))
    base = attributes(element)
    if image, do: Map.put(base, "image", attributes(image)["source"]), else: base
  end

  defp layers(element) do
    for child <- elements(element), name(child) in [:layer, :objectgroup, :imagelayer, :group] do
      layer(name(child), child)
    end
  end

  defp layer(:layer, element) do
    data = List.first(children(element, :data))

    element
    |> attributes()
    |> Map.merge(%{"type" => "tilelayer", "properties" => properties(element)})
    |> Map.merge(data(data))
  end

  defp layer(:objectgroup, element) do
    element
    |> attributes()
    |> Map.merge(%{
      "type" => "objectgroup",
      "properties" => properties(element),
      "objects" => for(object <- children(element, :object), do: object(object))
    })
  end

  defp layer(:imagelayer, element) do
    image = List.first(children(element, :image))

    element
    |> attributes()
    |> Map.merge(%{"type" => "imagelayer", "image" => image && attributes(image)["source"]})
  end

  defp layer(:group, element) do
    element
    |> attributes()
    |> Map.merge(%{
      "type" => "group",
      "layers" => layers(element),
      "properties" => properties(element)
    })
  end

  defp object(element) do
    element
    |> attributes()
    |> Map.put("properties", properties(element))
    |> then(&if Map.has_key?(&1, "class"), do: Map.put_new(&1, "type", &1["class"]), else: &1)
  end

  defp data(nil), do: %{"data" => []}

  defp data(element) do
    attrs = attributes(element)
    chunks = children(element, :chunk)

    if chunks == [],
      do: Map.put(cells(element, attrs), "encoding", attrs["encoding"] || "list"),
      else: %{
        "encoding" => attrs["encoding"] || "list",
        "compression" => attrs["compression"],
        "chunks" => for(chunk <- chunks, do: Map.merge(attributes(chunk), cells(chunk, attrs)))
      }
  end

  defp cells(element, %{"encoding" => "csv"}) do
    numbers =
      element
      |> content()
      |> String.split(~r/[,\s]+/, trim: true)
      |> Enum.map(&String.to_integer/1)

    %{"data" => numbers}
  end

  defp cells(element, %{"encoding" => "base64"} = attrs),
    do: %{"data" => String.trim(content(element)), "compression" => attrs["compression"]}

  defp cells(element, _attrs),
    do: %{"data" => for(tile <- children(element, :tile), do: attributes(tile)["gid"] || 0)}

  defp properties(element) do
    case children(element, :properties) do
      [properties | _] ->
        for property <- children(properties, :property) do
          attrs = attributes(property)
          value = attrs["value"] || content(property)
          %{"name" => attrs["name"], "type" => attrs["type"] || "string", "value" => value}
        end

      [] ->
        []
    end
  end

  defp children(element, name),
    do: for(child <- elements(element), name(child) == name, do: child)

  defp elements(element(content: content)),
    do: for(child <- content, Record.is_record(child, :xmlElement), do: child)

  defp name(element(name: name)), do: name

  defp content(element(content: content)) do
    content
    |> Enum.flat_map(fn
      text(value: value) -> [List.to_string(value)]
      _other -> []
    end)
    |> Enum.join()
  end

  defp attributes(element(attributes: attributes)) do
    for attribute(name: name, value: value) <- attributes, into: %{} do
      key = Atom.to_string(name)
      {key, number(key, List.to_string(value))}
    end
  end

  defp number(key, value) when key in @numbers do
    case Float.parse(value) do
      {number, ""} ->
        if number == trunc(number) and not String.contains?(value, "."),
          do: trunc(number),
          else: number

      _other ->
        value
    end
  end

  defp number(_key, value), do: value
end
