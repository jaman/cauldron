defmodule CauldronNative.Build.Assets do
  @moduledoc """
  The app's own images, colours and symbols, from an Xcode asset catalog (the app's
  `:assets`, a `.xcassets` folder).

  Apple's systems take the catalog as it is: its entries join the catalog the build
  writes for the icon and launch screen (`merge!/2`), so the app's Swift reads them with
  `Image("dough/blue-full")` and `Color("header/Sky Start")`, the widget extension
  too. Android takes it converted into resources (`android!/2`):

    * an image set's `1x`, `2x` and `3x` PNG or JPEG files become `drawable-mdpi`,
      `drawable-xhdpi` and `drawable-xxhdpi` drawables, a file without a scale a
      `drawable-nodpi` one, and a dark appearance's files the `night` qualified ones
    * a colour set becomes a colour in `values` and, for its dark appearance,
      `values-night`; a colour that refers to one of the system's (`systemIndigoColor`)
      takes that colour's light and dark values
    * a symbol set's regular, medium glyph becomes a vector drawable

  A colour set named `AccentColor` is the Apple app's accent colour, as in an Xcode
  project's own catalog.

  An entry's name is its path in the catalog through the folders that provide a
  namespace, as Xcode names it; on Android it is `resource_name/1` of that name, which
  the app's Kotlin turns into a resource with `cauldronAsset(name)` and
  `cauldronAssetColour(name)`. `CauldronNative.UI.image/2` shows an image set by name
  with `{:asset, name}`.
  """

  @densities %{"1x" => "mdpi", "2x" => "xhdpi", "3x" => "xxhdpi"}
  @raster ~w(.png .jpg .jpeg)

  @system %{
    "systemRedColor" => {"#FFFF3B30", "#FFFF453A"},
    "systemOrangeColor" => {"#FFFF9500", "#FFFF9F0A"},
    "systemYellowColor" => {"#FFFFCC00", "#FFFFD60A"},
    "systemGreenColor" => {"#FF34C759", "#FF30D158"},
    "systemMintColor" => {"#FF00C7BE", "#FF63E6E2"},
    "systemTealColor" => {"#FF30B0C7", "#FF40C8E0"},
    "systemCyanColor" => {"#FF32ADE6", "#FF64D2FF"},
    "systemBlueColor" => {"#FF007AFF", "#FF0A84FF"},
    "systemIndigoColor" => {"#FF5856D6", "#FF5E5CE6"},
    "systemPurpleColor" => {"#FFAF52DE", "#FFBF5AF2"},
    "systemPinkColor" => {"#FFFF2D55", "#FFFF375F"},
    "systemBrownColor" => {"#FFA2845E", "#FFAC8E68"},
    "systemGrayColor" => {"#FF8E8E93", "#FF8E8E93"},
    "whiteColor" => {"#FFFFFFFF", "#FFFFFFFF"},
    "blackColor" => {"#FF000000", "#FF000000"}
  }

  @type entry :: {:image | :colour | :symbol | :other, String.t(), String.t()}

  @doc """
  The entries of `catalog`, each `{kind, name, folder}`: `:image`, `:colour`, `:symbol`
  or `:other` (a set of a kind Android has no counterpart for), its namespaced name and
  its folder.
  """
  @spec entries(String.t()) :: [entry()]
  def entries(catalog), do: walk(catalog, [])

  @doc "The Android resource name of the asset `name`: `asset_` and its lowercased words."
  @spec resource_name(String.t()) :: String.t()
  def resource_name(name) do
    words =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")

    "asset_" <> words
  end

  @doc """
  Copy the entries of `catalog` into the asset catalog at `into`; raises when an entry
  has the name of one already there.
  """
  @spec merge!(String.t(), String.t()) :: :ok
  def merge!(catalog, into) do
    for child <- File.ls!(catalog), child != "Contents.json" do
      target = Path.join(into, child)

      if File.exists?(target),
        do: Mix.raise("#{Path.join(catalog, child)}: the app's catalog already has #{child}")

      File.cp_r!(Path.join(catalog, child), target)
    end

    :ok
  end

  @doc """
  Write the entries of `catalog` into the Android resource folder `res`; raises naming
  an entry Android cannot take, or two whose resource names are the same.
  """
  @spec android!(String.t(), String.t()) :: :ok
  def android!(catalog, res) do
    entries = entries(catalog)
    distinct!(entries)
    colours = for {:colour, name, folder} <- entries, do: colour(name, folder)

    for {:image, name, folder} <- entries, do: drawables!(name, folder, res)
    for {:symbol, name, folder} <- entries, do: vector!(name, folder, res)
    for {:other, name, folder} <- entries, do: unsupported!(name, folder)

    colours!(res, "values", for({name, light, _dark} <- colours, do: {name, light}))

    colours!(
      res,
      "values-night",
      for({name, _light, dark} <- colours, dark != nil, do: {name, dark})
    )
  end

  defp walk(folder, namespace) do
    for child <- File.ls!(folder) |> Enum.sort(),
        path = Path.join(folder, child),
        File.dir?(path),
        entry <- entry(path, child, namespace),
        do: entry
  end

  defp entry(path, child, namespace) do
    case Path.extname(child) do
      "" -> walk(path, namespace ++ named(path, child))
      extension -> [{kind(extension), name(namespace, Path.rootname(child)), path}]
    end
  end

  defp named(path, child) do
    contents = Path.join(path, "Contents.json")

    provides? =
      File.exists?(contents) and
        get_in(JSON.decode!(File.read!(contents)), ["properties", "provides-namespace"]) == true

    if provides?, do: [child], else: []
  end

  defp kind(".imageset"), do: :image
  defp kind(".colorset"), do: :colour
  defp kind(".symbolset"), do: :symbol
  defp kind(_other), do: :other

  defp name(namespace, child), do: Enum.join(namespace ++ [child], "/")

  defp distinct!(entries) do
    entries
    |> Enum.group_by(fn {_kind, name, _folder} -> resource_name(name) end)
    |> Enum.each(fn
      {_resource, [_one]} ->
        :ok

      {resource, many} ->
        names = Enum.map_join(many, ", ", &elem(&1, 1))
        Mix.raise("The assets #{names} would all be the Android resource #{resource}")
    end)
  end

  defp contents(folder),
    do: folder |> Path.join("Contents.json") |> File.read!() |> JSON.decode!()

  defp drawables!(name, folder, res) do
    for image <- Map.get(contents(folder), "images", []),
        image["filename"] != nil,
        image["idiom"] in [nil, "universal", "iphone"] do
      file = Path.join(folder, image["filename"])
      extension = file |> Path.extname() |> String.downcase()

      if extension not in @raster,
        do: Mix.raise("#{file}: Android takes the app's images as PNG or JPEG")

      target = Path.join(res, drawable_folder(image))
      File.mkdir_p!(target)
      File.cp!(file, Path.join(target, resource_name(name) <> extension))
    end

    :ok
  end

  defp drawable_folder(image) do
    density = Map.get(@densities, image["scale"], "nodpi")
    Enum.join(["drawable"] ++ night(image) ++ [density], "-")
  end

  defp night(%{"appearances" => appearances}) do
    if Enum.any?(appearances, &(&1["value"] == "dark")), do: ["night"], else: []
  end

  defp night(_image), do: []

  defp colour(name, folder) do
    colours = Map.get(contents(folder), "colors", [])
    {light, dark} = Enum.split_with(colours, &(night(&1) == []))
    light = List.first(light)

    dark =
      case dark do
        [colour | _] -> argb!(name, colour, :dark)
        [] -> system_dark(light)
      end

    {resource_name(name), argb!(name, light, :light), dark}
  end

  defp system_dark(%{"color" => %{"reference" => reference}}),
    do: @system |> Map.get(reference, {nil, nil}) |> elem(1)

  defp system_dark(_colour), do: nil

  defp argb!(name, %{"color" => %{"reference" => reference}}, appearance) do
    case Map.fetch(@system, reference) do
      {:ok, {light, dark}} ->
        if appearance == :dark, do: dark, else: light

      :error ->
        Mix.raise("The colour #{name} refers to #{reference}, which Android has no value for")
    end
  end

  defp argb!(_name, %{"color" => %{"components" => components}}, _appearance) do
    [alpha, red, green, blue] =
      for key <- ~w(alpha red green blue), do: channel(Map.fetch!(components, key))

    "#" <> Base.encode16(<<alpha, red, green, blue>>)
  end

  defp argb!(name, _colour, _appearance),
    do: Mix.raise("The colour #{name} names no sRGB components, which Android needs")

  defp channel("0x" <> hex), do: String.to_integer(hex, 16)

  defp channel(value) do
    if String.contains?(value, "."),
      do: round(String.to_float(value) * 255),
      else: String.to_integer(value)
  end

  defp colours!(_res, _folder, []), do: :ok

  defp colours!(res, folder, colours) do
    File.mkdir_p!(Path.join(res, folder))

    items =
      Enum.map_join(colours, "\n", fn {name, argb} ->
        ~s(    <color name="#{name}">#{argb}</color>)
      end)

    File.write!(Path.join([res, folder, "cauldron_assets.xml"]), """
    <?xml version="1.0" encoding="utf-8"?>
    <resources>
    #{items}
    </resources>
    """)
  end

  defp vector!(name, folder, res) do
    [svg] =
      for symbol <- Map.get(contents(folder), "symbols", []),
          do: File.read!(Path.join(folder, symbol["filename"]))

    paths = glyph!(name, svg)
    {left, top, right, bottom} = bounds(paths)
    width = right - left
    height = bottom - top
    target = Path.join(res, "drawable")
    File.mkdir_p!(target)

    data =
      Enum.map_join(paths, "\n", fn path ->
        ~s(        <path android:fillColor="#FF000000" android:pathData="#{path}" />)
      end)

    File.write!(Path.join(target, resource_name(name) <> ".xml"), """
    <?xml version="1.0" encoding="utf-8"?>
    <vector xmlns:android="http://schemas.android.com/apk/res/android"
        android:width="#{Float.round(24 * width / height, 2)}dp"
        android:height="24dp"
        android:viewportWidth="#{Float.round(width, 3)}"
        android:viewportHeight="#{Float.round(height, 3)}">
        <group android:translateX="#{Float.round(-left, 3)}" android:translateY="#{Float.round(-top, 3)}">
    #{data}
        </group>
    </vector>
    """)
  end

  defp glyph!(name, svg) do
    case Regex.run(~r/<g id="Regular-M"[^>]*>(.*?)<\/g>/s, svg, capture: :all_but_first) do
      [group] ->
        Regex.scan(~r/<path[^>]*\sd="([^"]+)"/, group, capture: :all_but_first) |> List.flatten()

      nil ->
        Mix.raise("The symbol #{name} has no Regular-M glyph")
    end
  end

  defp bounds(paths) do
    points =
      for path <- paths,
          [x, y] <- path |> numbers() |> Enum.chunk_every(2, 2, :discard),
          do: {x, y}

    {xs, ys} = Enum.unzip(points)
    {Enum.min(xs), Enum.min(ys), Enum.max(xs), Enum.max(ys)}
  end

  defp numbers(path) do
    ~r/-?\d*\.?\d+(?:e-?\d+)?/
    |> Regex.scan(path)
    |> Enum.map(fn [number] -> parse(number) end)
  end

  defp parse("." <> fraction), do: parse("0." <> fraction)
  defp parse("-." <> fraction), do: parse("-0." <> fraction)

  defp parse(number) do
    {value, ""} = Float.parse(number)
    value
  end

  defp unsupported!(name, folder),
    do: Mix.raise("#{folder}: Android has no counterpart for the asset #{name}")
end
