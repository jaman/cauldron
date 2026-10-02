defmodule Beast.Art do
  @moduledoc """
  The demo's pictures in the atlas `:beast`: the parallax layers and the figures loaded
  from `priv/art`, and the ground tiles drawn here.

  The runner, the bats and the crawlers were made as sprite sheets and cut into frames by
  `mix linocut.sheet`; `atlas.txt` gives each its glyph, its colour and its rate.

  `install/0` loads the directory, adds the tiles and the far silhouettes, installs the
  atlas and gives back its name.
  """

  alias Cauldron2D.Atlas

  @name :beast
  @tile 16
  @void {18, 10, 24}
  @stride 0.55
  @cycle [0, 1]
  @flap [1.0, 0.74, 0.5, 0.74]

  @earth %{
    "K" => "#2a1a14",
    "D" => "#5a3a28",
    "d" => "#4a2e20",
    "G" => "#6b7a32",
    "S" => "#7a6a58"
  }

  @far %{"K" => "#2a1830"}

  @snag """
  ................
  ................
  .....K....K.....
  ......K..K......
  ...K...KK...K...
  ....K..KK..K....
  .....KKKKKK.....
  .......KK.......
  .......KK.......
  ......KKKK......
  .......KK.......
  .......KK.......
  ......KKKK......
  .......KK.......
  ......KKKK......
  .....KKKKKK.....
  """

  @spire """
  ................
  ................
  ................
  ................
  .......KK.......
  ......KKKK......
  ......KKKK......
  .....KKKKKK.....
  .....KKKKKK.....
  ....KKKKKKKK....
  ....KKKKKKKK....
  ...KKKKKKKKKK...
  ...KKKKKKKKKK...
  ..KKKKKKKKKKKK..
  ..KKKKKKKKKKKK..
  .KKKKKKKKKKKKKK.
  """

  @turf """
  GGGGGGGGGGGGGGGG
  GGKGGGGGGKGGGGGG
  DDDDDDDDDDDDDDDD
  DDdDDDDDDDDdDDDD
  DDDDDDDDDDDDDDDD
  DDDDDdDDDDDDDDDD
  DDDDDDDDDDDDdDDD
  DDDDDDDDDDDDDDDD
  DDdDDDDDDDDDDDDD
  DDDDDDDDdDDDDDDD
  DDDDDDDDDDDDDDDD
  DDDDdDDDDDDDDdDD
  DDDDDDDDDDDDDDDD
  DDDDDDDdDDDDDDDD
  DDDDDDDDDDDDDDDD
  DDDDDDDDDDDDDDDD
  """

  @dirt """
  DDDDDDDDDDDDDDDD
  DDdDDDDDDDDdDDDD
  DdDDDDdDDDDDDDDD
  DDDDDDDDDDDDdDDD
  DDDDdDDDDDDDDDDD
  DDDDDDDDDdDDDDDD
  DdDDDDDDDDDDDDdD
  DDDDDDDdDDDDDDDD
  DDDDdDDDDDDDDDDD
  DDDDDDDDDDDdDDDD
  DdDDDDDDDDDDDDDD
  DDDDDDDDdDDDDDDD
  DDDDdDDDDDDDDDdD
  DDDDDDDDDDDDDDDD
  DDdDDDDDDDDDDDDD
  DDDDDDDDDDDDDDDD
  """

  @stone """
  SSSSSSSSSSSSSSSS
  SKSSSSSKSSSSSSKS
  SSSSSSSSSSSSSSSS
  SSSSKSSSSSSKSSSS
  SSSSSSSSSSSSSSSS
  SSKSSSSSSSSSSSSS
  SSSSSSSSKSSSSSSS
  SSSSSSSSSSSSSSSS
  SSSSSKSSSSSSSKSS
  SSSSSSSSSSSSSSSS
  SKSSSSSSSSSKSSSS
  SSSSSSSSSSSSSSSS
  SSSSSSKSSSSSSSSS
  SSSSSSSSSSSSSSSS
  SSSKSSSSSSSSKSSS
  KKKKKKKKKKKKKKKK
  """

  @doc "The atlas name."
  @spec name() :: Atlas.name()
  def name, do: @name

  @doc "The tile size in pixels."
  @spec tile() :: pos_integer()
  def tile, do: @tile

  @doc "The art directory."
  @spec dir() :: Path.t()
  def dir, do: Path.join(:code.priv_dir(:beast), "art")

  @doc "Load the directory, add the tiles, install the atlas, and give back its name."
  @spec install() :: Atlas.name()
  def install do
    if Atlas.installed?(@name) do
      @name
    else
      {:ok, atlas} = Atlas.load(@name, dir(), tile: @tile, void: @void)

      atlas
      |> strides()
      |> flaps()
      |> ground()
      |> distance()
      |> Atlas.install()
    end
  end

  @doc "How many steps the walk takes before it comes round again."
  @spec steps() :: pos_integer()
  def steps, do: length(@cycle)

  @doc "The runner's art for a distance run, so the legs step with the ground rather than a clock."
  @spec step(number()) :: atom()
  def step(distance) do
    place = Enum.at(@cycle, Integer.mod(floor(distance / @stride), length(@cycle)))

    :"runner_#{place}"
  end

  defp strides(atlas) do
    entry = Atlas.entry(atlas, :runner)
    {walking, [still]} = Enum.split(entry.frames, length(entry.frames) - 1)

    walking
    |> Enum.with_index()
    |> Enum.reduce(atlas, fn {frame, index}, acc ->
      Atlas.put(acc, :"runner_#{index}", frame.raster, glyph: entry.glyph, color: entry.color)
    end)
    |> Atlas.put(:stander, still.raster, glyph: entry.glyph, color: entry.color)
  end

  defp flaps(atlas) do
    entry = Atlas.entry(atlas, :bat)
    wings = entry.frames |> hd() |> Map.fetch!(:raster)
    beat = for share <- @flap, do: Linocut.squash(wings, {1.0, share})

    Atlas.put(atlas, :bat, beat, glyph: entry.glyph, color: entry.color, fps: 12)
  end

  defp ground(atlas) do
    atlas
    |> Atlas.put(:turf, sprite(@turf, @earth), glyph: "\"\"", color: {107, 122, 50})
    |> Atlas.put(:dirt, sprite(@dirt, @earth), glyph: "..", color: {90, 58, 40})
    |> Atlas.put(:stone, sprite(@stone, @earth), glyph: "##", color: {122, 106, 88})
  end

  defp distance(atlas) do
    atlas
    |> Atlas.put(:snag, sprite(@snag, @far), glyph: "Y ", color: {42, 24, 48})
    |> Atlas.put(:spire, sprite(@spire, @far), glyph: "A ", color: {42, 24, 48})
  end

  defp sprite(picture, palette), do: Linocut.sprite(picture, palette)
end
