defmodule Cauldron2D.AtlasTest do
  @moduledoc """
  Installing an atlas, and what happens to already-composited tiles when it changes.

  Each test installs under its own name, so nothing here depends on the order tests run in or
  on the atlas `Cauldron2D.SurfaceTest` shares.
  """

  use ExUnit.Case, async: false

  alias Cauldron2D.{Atlas, Surface}
  alias FrenchCurve.Raster

  @tile 4

  defp name(suffix), do: :"atlas_test_#{suffix}"

  defp atlas(suffix, opts \\ []) do
    color = Keyword.get(opts, :color, {10, 20, 30, 255})
    divisor = Keyword.get(opts, :divisor, 2)

    name(suffix)
    |> Atlas.new(tile: @tile, void: Keyword.get(opts, :void, {0, 0, 0}))
    |> Atlas.put(:floor, Raster.new(@tile, @tile, background: color), glyph: "· ")
    |> Atlas.tint(:shade, fn {r, g, b, a} ->
      {div(r, divisor), div(g, divisor), div(b, divisor), a}
    end)
  end

  defp first_pixel(suffix, cell), do: binary_part(Surface.tile_binary(name(suffix), cell), 0, 4)

  describe "installing" do
    test "publishes the atlas and creates its cache table" do
      refute Atlas.installed?(name(:fresh))

      assert Atlas.install(atlas(:fresh)) == name(:fresh)
      assert Atlas.installed?(name(:fresh))
      assert :ets.whereis(Atlas.cache(name(:fresh))) != :undefined
    end

    test "an atlas nobody installed is refused by name rather than returning nil" do
      assert_raise ArgumentError, ~r/no atlas installed under :atlas_test_absent/, fn ->
        Atlas.fetch(name(:absent))
      end
    end

    test "installing the very same atlas again keeps what has been composited" do
      Atlas.install(atlas(:same))
      first_pixel(:same, {:floor, [], nil})
      cached = :ets.tab2list(Atlas.cache(name(:same)))

      Atlas.install(atlas(:same))

      assert :ets.tab2list(Atlas.cache(name(:same))) == cached
      refute cached == []
    end

    test "a tint redefined under a name it already had takes effect" do
      Atlas.install(atlas(:tint, color: {200, 200, 200, 255}, divisor: 2))
      assert first_pixel(:tint, {:floor, [], :shade}) == <<100, 100, 100, 255>>

      Atlas.install(atlas(:tint, color: {200, 200, 200, 255}, divisor: 4))
      assert first_pixel(:tint, {:floor, [], :shade}) == <<50, 50, 50, 255>>
    end

    test "art redefined under a name it already had takes effect" do
      Atlas.install(atlas(:art, color: {1, 2, 3, 255}))
      assert first_pixel(:art, {:floor, [], nil}) == <<1, 2, 3, 255>>

      Atlas.install(atlas(:art, color: {4, 5, 6, 255}))
      assert first_pixel(:art, {:floor, [], nil}) == <<4, 5, 6, 255>>
    end

    test "a changed void colour takes effect too" do
      Atlas.install(atlas(:void, void: {9, 9, 9}))
      assert first_pixel(:void, :void) == <<9, 9, 9, 255>>

      Atlas.install(atlas(:void, void: {7, 7, 7}))
      assert first_pixel(:void, :void) == <<7, 7, 7, 255>>
    end

    test "the cache table survives a re-install, so a held reference stays good" do
      Atlas.install(atlas(:table))
      held = :ets.whereis(Atlas.cache(name(:table)))

      Atlas.install(atlas(:table, color: {99, 99, 99, 255}))

      assert :ets.whereis(Atlas.cache(name(:table))) == held
    end
  end

  describe "looking things up" do
    setup do
      Atlas.install(atlas(:lookup))
      {:ok, atlas: Atlas.fetch(name(:lookup))}
    end

    test "fetch takes a name or a struct and gives the struct either way", %{atlas: atlas} do
      assert Atlas.fetch(name(:lookup)) == atlas
      assert Atlas.fetch(atlas) == atlas
    end

    test "arts lists what was put in", %{atlas: atlas} do
      assert Atlas.arts(atlas) == [:floor]
    end

    test "art the atlas does not have is refused by name", %{atlas: atlas} do
      assert_raise ArgumentError, ~r/has no art :nothing/, fn -> Atlas.entry(atlas, :nothing) end
    end
  end

  describe "the version" do
    test "is the project's, whether or not the application has been loaded" do
      assert Cauldron2D.version() =~ ~r/^\d+\.\d+\.\d+/

      Application.unload(:cauldron_2d)
      assert Cauldron2D.version() =~ ~r/^\d+\.\d+\.\d+/
      Application.load(:cauldron_2d)
    end
  end
end
