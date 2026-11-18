defmodule Cauldron2D.PaletteDriftTest do
  use ExUnit.Case, async: true

  # Two tables name the same colours: the core's, because a hud resolves a name
  # without linocut, and linocut's, because a picture is drawn with it. A colour
  # added to one and not the other is a picture and a hud disagreeing about yellow.
  # Linocut names one colour a hud cannot use — `:transparent` has no RGB — so the
  # core's names must be a subset, and the shared ones must agree.
  test "every colour a hud can name is a colour linocut draws" do
    assert MapSet.subset?(
             MapSet.new(Cauldron.Palette.names()),
             MapSet.new(Linocut.Palette.names())
           )
  end

  test "every named colour is the same RGB in both" do
    for name <- Cauldron.Palette.names() do
      {r, g, b, _alpha} = Linocut.Palette.color(name)

      assert Cauldron.Palette.rgb(name) == {r, g, b},
             "#{name} is #{inspect(Cauldron.Palette.rgb(name))} in Cauldron and " <>
               "#{inspect({r, g, b})} in Linocut"
    end
  end
end
