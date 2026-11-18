defmodule Greenware.Mend.Puzzles do
  @moduledoc """
  The fifteen mends of the campaign: what each object is called, what the player is
  asked to do, and the tests the world runs on the clay.
  """

  alias Greenware.Mend.Objects

  @doc "Every puzzle by id."
  def all do
    Map.new(ids(), &{&1, puzzle(&1)})
  end

  def ids do
    [
      :cup,
      :key,
      :wing,
      :bucket,
      :arm,
      :dam,
      :lamp,
      :plate,
      :doll,
      :hub,
      :face,
      :music_box,
      :bridge,
      :heart,
      :sky
    ]
  end

  @doc "One puzzle, its geometry and its checks."
  def puzzle(id) do
    object = Objects.build(object_id(id))

    Map.merge(object, %{
      id: id,
      title: title(id),
      goal: goal(id),
      checks: checks(id),
      hint: hint(id)
    })
  end

  defp object_id(:music_box), do: :music_box
  defp object_id(id), do: id

  defp title(:cup), do: "A CUP FOR THE DRIP"
  defp title(:key), do: "THE LATCH"
  defp title(:wing), do: "THE BIRD'S WING"
  defp title(:bucket), do: "THE DRY WELL"
  defp title(:arm), do: "THE GREEN MAN'S ARM"
  defp title(:dam), do: "THE DAM"
  defp title(:lamp), do: "A LAMP FOR THE CELLAR"
  defp title(:plate), do: "THE CRACKED CHOIR"
  defp title(:doll), do: "THE FIRST FIRED THING"
  defp title(:hub), do: "THE FERRIS WHEEL"
  defp title(:face), do: "THE HALL OF MIRRORS"
  defp title(:music_box), do: "THE RINGMASTER'S BOX"
  defp title(:bridge), do: "THE ASH BRIDGE"
  defp title(:heart), do: "THE MENDER'S HEART"
  defp title(:sky), do: "THE SKY"

  defp goal(:cup), do: "Seal the crack, then fire the cup so it holds water."
  defp goal(:key), do: "Fill the missing tooth and fire the key hard enough to turn."
  defp goal(:wing), do: "Mend the tear and wire the wing so it can beat."
  defp goal(:bucket), do: "Seal the bottom of the bucket and fire it."
  defp goal(:arm), do: "Join the arm at the elbow and wire the joint."
  defp goal(:dam), do: "Close the crack and fire the wall before the water returns."
  defp goal(:lamp), do: "Seal the bowl, wire the handle, and fire the lamp."
  defp goal(:plate), do: "Fill the three cracks until the plate rings, then fire it."
  defp goal(:doll), do: "Give the fired doll a leg that stands, and fire it twice."
  defp goal(:hub), do: "Replace the missing spoke, wire the hub, and fire it."
  defp goal(:face), do: "Give the face eyes and a mouth, then fire it."
  defp goal(:music_box), do: "Fill the missing teeth, wire the comb, and fire the box."
  defp goal(:bridge), do: "Span the ash with clay and wire, then fire the bridge."
  defp goal(:heart), do: "Wire the Mender's heart and fire it shut."
  defp goal(:sky), do: "Mend the whole arc, wire it, and fire the sky."

  defp checks(:cup),
    do: [{:fill, :crack, 0.9, "the crack is sealed"}, {:fired, 30, "the clay is fired"}]

  defp checks(:key),
    do: [{:fill, :crack, 0.9, "the missing tooth is whole"}, {:fired, 50, "the key is hard"}]

  defp checks(:wing),
    do: [
      {:fill, :crack, 0.85, "the tear is closed"},
      {:wire, 8, "the wing is wired"},
      {:fired, 20, "the clay is set"}
    ]

  defp checks(:bucket),
    do: [{:fill, :crack, 0.95, "the bottom is sealed"}, {:fired, 40, "the bucket is fired"}]

  defp checks(:arm),
    do: [
      {:fill, :crack, 0.9, "the elbow is joined"},
      {:wire, 10, "the joint is wired"},
      {:fired, 30, "the clay is set"}
    ]

  defp checks(:dam),
    do: [
      {:fill, :crack, 0.95, "the crack is closed"},
      {:wire, 6, "the wall is bound"},
      {:fired, 60, "the wall is fired"}
    ]

  defp checks(:lamp),
    do: [
      {:fill, :crack, 0.95, "the bowl is sealed"},
      {:wire, 4, "the handle is wired"},
      {:fired, 50, "the lamp is fired"}
    ]

  defp checks(:plate),
    do: [
      {:tune, [:note_a, :note_b, :note_c], 120, 55, "the three notes ring"},
      {:fired, 60, "the plate is fired"}
    ]

  defp checks(:doll),
    do: [
      {:fill, :crack, 0.9, "the leg holds"},
      {:wire, 6, "the leg is wired"},
      {:fired, 80, "the doll is fired"}
    ]

  defp checks(:hub),
    do: [
      {:fill, :crack, 0.9, "the spoke is whole"},
      {:wire, 10, "the hub is wired"},
      {:fired, 40, "the hub is fired"}
    ]

  defp checks(:face),
    do: [
      {:fill, :eyes, 0.9, "the eyes are open"},
      {:fill, :mouth, 0.9, "the mouth is whole"},
      {:fired, 40, "the face is fired"}
    ]

  defp checks(:music_box),
    do: [
      {:fill, :crack, 0.9, "the missing teeth are cut"},
      {:wire, 6, "the comb is wired"},
      {:fired, 50, "the box is fired"}
    ]

  defp checks(:bridge),
    do: [
      {:fill, :crack, 0.95, "the span holds"},
      {:wire, 12, "the span is wired"},
      {:fired, 40, "the bridge is fired"}
    ]

  defp checks(:heart),
    do: [
      {:fill, :crack, 0.95, "the seam is closed"},
      {:wire, 10, "the heart is wired"},
      {:fired, 60, "the heart is fired"}
    ]

  defp checks(:sky),
    do: [
      {:fill, :crack, 0.95, "the hole is closed"},
      {:wire, 20, "the arc is bound"},
      {:fired, 80, "the sky is fired"}
    ]

  defp hint(:cup), do: "The Cat watches the drip. Clay first, fire after."
  defp hint(:key), do: "The latch is a shape, not a strength. The tooth is the whole key."
  defp hint(:wing), do: "Thin things need a wire inside them. The bird will not wait."
  defp hint(:bucket), do: "The well is dry because the bucket leaks. Start at the bottom."
  defp hint(:arm), do: "The Green Man says a joint should bend, not break."
  defp hint(:dam), do: "The water is already coming. Fire the wall or it will soften."
  defp hint(:lamp), do: "A lamp needs a whole bowl and a handle that does not let go."
  defp hint(:plate), do: "The Choir tunes by filling. Each crack has its own note."
  defp hint(:doll), do: "The doll was fired long ago. The leg is the new thing."
  defp hint(:hub), do: "A wheel shares its weight. Give it all six spokes."
  defp hint(:face), do: "The Boy is waiting to see what you choose."
  defp hint(:music_box), do: "Two teeth make the gap. The tune lives in the gap."
  defp hint(:bridge), do: "Ash is a poor foundation. The wire is the bridge."
  defp hint(:heart), do: "This is the Mender's own crack. It has been open a long time."
  defp hint(:sky), do: "You cannot fire the sky in pieces. Bind it first."
end
