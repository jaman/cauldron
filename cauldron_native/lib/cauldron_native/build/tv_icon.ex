defmodule CauldronNative.Build.TvIcon do
  @moduledoc """
  Apple TV's icons, made from the app's one square icon: the asset catalog's brand
  assets, `App Icon & Top Shelf Image`, holding the layered app icons tvOS shows on the
  Home Screen and the App Store, and the top shelf images.

  Each layered icon has two layers: the back one the app's `:icon_background` colour,
  the front one the icon at four fifths of the height, centred on the same colour. The
  top shelf images are the icon centred on the same colour. Images are scaled with
  macOS's `sips`.
  """

  alias CauldronNative.Build.{App, Png, Shell}

  @name "App Icon & Top Shelf Image"

  @stacks [
    {"App Icon - App Store", "primary-app-icon", {1280, 768}, [1]},
    {"App Icon", "primary-app-icon", {400, 240}, [1, 2]}
  ]

  @shelves [
    {"Top Shelf Image Wide", "top-shelf-image-wide", {2320, 720}},
    {"Top Shelf Image", "top-shelf-image", {1920, 720}}
  ]

  @doc "The name the build setting `ASSETCATALOG_COMPILER_APPICON_NAME` takes."
  @spec name() :: String.t()
  def name, do: @name

  @doc "Write the brand assets for `app`'s icon into the asset catalog `catalog`."
  @spec write!(App.t(), String.t()) :: :ok
  def write!(app, catalog) do
    folder = Path.join(catalog, @name <> ".brandassets")
    File.mkdir_p!(folder)

    entries =
      Enum.map(@stacks, &stack!(&1, folder, app.icon, app.icon_background)) ++
        Enum.map(@shelves, &shelf!(&1, folder, app.icon, app.icon_background))

    contents!(folder, %{assets: entries})
  end

  defp stack!({title, role, {width, height} = size, scales}, folder, icon, background) do
    colour = rgb(background)
    stack = Path.join(folder, title <> ".imagestack")

    layer!(stack, "Back", scales, fn path, scale ->
      Png.solid!(path, width * scale, height * scale, colour)
    end)

    layer!(stack, "Front", scales, fn path, scale ->
      centred!(icon, path, size, scale, background)
    end)

    contents!(stack, %{
      layers: [%{filename: "Front.imagestacklayer"}, %{filename: "Back.imagestacklayer"}]
    })

    %{filename: title <> ".imagestack", idiom: "tv", role: role, size: "#{width}x#{height}"}
  end

  defp layer!(stack, name, scales, draw) do
    layer = Path.join(stack, name <> ".imagestacklayer")
    images = Path.join(layer, "Content.imageset")
    File.mkdir_p!(images)
    contents!(layer, %{})
    contents!(images, %{images: Enum.map(scales, &image!(images, &1, draw))})
  end

  defp shelf!({title, role, {width, height} = size}, folder, icon, background) do
    images = Path.join(folder, title <> ".imageset")
    File.mkdir_p!(images)
    draw = fn path, scale -> centred!(icon, path, size, scale, background) end
    contents!(images, %{images: Enum.map([1, 2], &image!(images, &1, draw))})
    %{filename: title <> ".imageset", idiom: "tv", role: role, size: "#{width}x#{height}"}
  end

  defp image!(folder, scale, draw) do
    file = "image@#{scale}x.png"
    draw.(Path.join(folder, file), scale)
    %{filename: file, idiom: "tv", scale: "#{scale}x"}
  end

  defp centred!(icon, path, {width, height}, scale, background) do
    side = div(height * scale * 4, 5)
    _ = Shell.output!("sips", ["-z", "#{side}", "#{side}", icon, "--out", path])

    _ =
      Shell.output!(
        "sips",
        ["--padToHeightWidth", "#{height * scale}", "#{width * scale}"] ++
          ["--padColor", String.trim_leading(background, "#"), path]
      )

    :ok
  end

  defp contents!(folder, contents),
    do:
      File.write!(
        Path.join(folder, "Contents.json"),
        JSON.encode!(Map.put(contents, :info, %{author: "xcode", version: 1}))
      )

  defp rgb("#" <> hex) do
    <<red::binary-size(2), green::binary-size(2), blue::binary-size(2)>> = hex
    {String.to_integer(red, 16), String.to_integer(green, 16), String.to_integer(blue, 16)}
  end
end
