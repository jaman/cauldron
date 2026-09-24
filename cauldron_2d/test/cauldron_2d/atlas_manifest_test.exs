defmodule Cauldron2D.Atlas.ManifestTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Atlas.Manifest

  test "lines are name, glyph, colour and rate, any of the last three empty" do
    manifest = Manifest.parse("wall\t# \t#5a7cf0\t\nflame\tf \t\t12\nbare\n\n")

    assert manifest == %{
             wall: %{glyph: "# ", color: {90, 124, 240}},
             flame: %{glyph: "f ", fps: 12},
             bare: %{}
           }

    assert Manifest.render(manifest) == "bare\t\t\t\nflame\tf \t\t12\nwall\t# \t#5a7cf0\t\n"
    assert Manifest.parse(Manifest.render(manifest)) == manifest
  end

  test "call options lay over the file's" do
    assert Manifest.arts(%{wall: %{glyph: "# ", fps: 4}},
             wall: [glyph: "@ "],
             gem: [color: {1, 2, 3}]
           )
           |> Enum.map(fn {name, options} -> {name, Enum.sort(options)} end)
           |> Enum.sort() ==
             [gem: [color: {1, 2, 3}], wall: [fps: 4, glyph: "@ "]]
  end
end

defmodule Cauldron2D.Atlas.ManifestDeriveTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Atlas.Manifest

  test "a fifth field is a derivation, kept as written and rendered back" do
    text = "knight\tK \t#2040c0\t\nknight_red\tK \t#c02020\t\tfrom knight; colour C #c02020\n"
    manifest = Manifest.parse(text)

    assert manifest.knight_red == %{
             glyph: "K ",
             color: {192, 32, 32},
             derive: "from knight; colour C #c02020"
           }

    refute Map.has_key?(manifest.knight, :derive)
    assert Manifest.render(manifest) == text
    assert Manifest.derived(manifest) == [knight_red: "from knight; colour C #c02020"]
  end
end

defmodule Cauldron2D.Atlas.ManifestSolidsTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Atlas.Manifest

  test "the sixth, seventh and eighth fields are the height, the faces and the poses, rendered back" do
    line = "house\t# \t#a08060\t\t\t2\ttop=roof side=wall south=door\tfront=hero_f back=hero_b\n"
    manifest = Manifest.parse(line)

    assert manifest == %{
             house: %{
               glyph: "# ",
               color: {160, 128, 96},
               height: 2,
               faces: %{top: :roof, side: :wall, south: :door},
               poses: %{front: :hero_f, back: :hero_b}
             }
           }

    assert Manifest.render(manifest) == line
  end

  test "a bad height or an unknown face or pose name is left out" do
    assert Manifest.parse("x\t\t\t\t\tlots\tup=roof\tdance=a\n") == %{x: %{}}
  end
end
