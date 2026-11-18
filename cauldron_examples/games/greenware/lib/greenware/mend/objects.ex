defmodule Greenware.Mend.Objects do
  @moduledoc """
  The clay bodies of Greenware. Each object is a 96 by 72 cross-section: the cells that
  are clay, the cells that are missing, and the zones a puzzle asks about. They are
  generated in code now; the final art replaces the rendering, not the geometry.
  """

  alias Greenware.Mend.Shape

  @doc "The geometry for an object."
  def build(:cup) do
    bowl = Shape.ring(48, 40, 21, 16, 4)
    base = Shape.ellipse(48, 54, 14, 4)
    handle = Shape.ring(70, 38, 8, 10, 3) |> Shape.intersect(Shape.rect(64, 28, 20, 24))
    mask = Shape.union(Shape.union(bowl, base), handle)
    crack = Shape.intersect(bowl, Shape.rect(62, 30, 8, 10))
    rim = Shape.intersect(bowl, Shape.rect(28, 24, 40, 5))

    %{
      id: :cup,
      mask: mask,
      holes: crack,
      zones: %{crack: crack, rim: rim, body: bowl},
      colour: :terracotta,
      clay: 80,
      wet: 64,
      hint: "Press clay into the crack, smooth the rim, then fire it."
    }
  end

  def build(:key) do
    shaft = Shape.rect(22, 34, 54, 8)
    bow = Shape.ring(24, 38, 9, 9, 4)
    teeth = Shape.union(Shape.rect(62, 42, 4, 9), Shape.rect(70, 42, 4, 11))
    missing = Shape.rect(53, 42, 5, 8)
    mask = Shape.union(Shape.union(shaft, bow), Shape.union(teeth, missing))
    profile = Shape.union(Shape.rect(50, 34, 28, 18), missing)

    %{
      id: :key,
      mask: mask,
      holes: missing,
      zones: %{crack: missing, teeth: teeth, profile: profile, shaft: shaft},
      colour: :ochre,
      clay: 60,
      wet: 58,
      hint: "A key is a shape before it is a thing. Fill the missing tooth, then fire it hard."
    }
  end

  def build(:wing) do
    wing = Shape.ellipse(48, 38, 27, 12)
    tip = Shape.ellipse(70, 34, 10, 7)
    mask = Shape.union(wing, tip)
    tear = Shape.intersect(Shape.ellipse(37, 39, 9, 6), mask)

    feathers =
      Shape.intersect(
        mask,
        Shape.union(Shape.line({30, 36}, {60, 32}, 1), Shape.line({30, 42}, {58, 42}, 1))
      )

    %{
      id: :wing,
      mask: mask,
      holes: tear,
      zones: %{crack: tear, feathers: feathers, body: wing},
      colour: :sage,
      clay: 55,
      wet: 70,
      hint: "A wing is thin; it needs wire more than it needs weight."
    }
  end

  def build(:bucket) do
    body = Shape.union(Shape.rect(32, 28, 32, 26), Shape.ellipse(48, 28, 17, 5))
    rim = Shape.ring(48, 28, 17, 5, 2)
    handle = Shape.intersect(Shape.ring(48, 24, 20, 17, 2), Shape.rect(28, 6, 40, 20))
    mask = Shape.union(Shape.union(body, rim), handle)
    hole = Shape.intersect(Shape.ellipse(44, 50, 8, 5), body)

    %{
      id: :bucket,
      mask: mask,
      holes: hole,
      zones: %{crack: hole, rim: rim, body: body},
      colour: :terracotta,
      clay: 90,
      wet: 66,
      hint: "The bottom takes the weight. Seal it, then fire it before the water finds it."
    }
  end

  def build(:arm) do
    limb = Shape.line({28, 44}, {66, 34}, 7)
    hand = Shape.ellipse(70, 32, 8, 7)
    mask = Shape.union(limb, hand)
    hole = Shape.intersect(Shape.disc(47, 39, 5), mask)

    %{
      id: :arm,
      mask: mask,
      holes: hole,
      zones: %{crack: hole, joint: Shape.disc(47, 39, 8), body: limb},
      colour: :leather,
      clay: 70,
      wet: 62,
      hint: "A joint is a hinge. Mend it with wire, or it will break at the same place."
    }
  end

  def build(:dam) do
    wall = Shape.rect(18, 24, 60, 32)
    buttress = Shape.union(Shape.rect(18, 46, 10, 18), Shape.rect(68, 46, 10, 18))
    mask = Shape.union(wall, buttress)
    hole = Shape.intersect(Shape.ellipse(48, 40, 10, 8), wall)
    crack = Shape.union(hole, Shape.intersect(Shape.line({48, 40}, {40, 56}, 1), wall))

    %{
      id: :dam,
      mask: mask,
      holes: crack,
      zones: %{crack: crack, face: wall, base: buttress},
      colour: :slate,
      clay: 120,
      wet: 58,
      hint: "Water is patient. Give it a seam and it will take the whole wall."
    }
  end

  def build(:lamp) do
    body = Shape.ellipse(44, 42, 14, 12)
    base = Shape.rect(34, 50, 20, 5)
    spout = Shape.line({56, 38}, {68, 30}, 3)
    handle = Shape.intersect(Shape.ring(30, 40, 8, 8, 3), Shape.rect(22, 32, 12, 18))
    mask = Shape.union(Shape.union(body, base), Shape.union(spout, handle))
    hole = Shape.intersect(Shape.ellipse(50, 40, 5, 5), body)

    %{
      id: :lamp,
      mask: mask,
      holes: hole,
      zones: %{crack: hole, bowl: body, spout: spout},
      colour: :ochre,
      clay: 75,
      wet: 68,
      hint: "Oil finds every crack. Seal the bowl; the spout only has to pour."
    }
  end

  def build(:plate) do
    plate = Shape.ring(48, 38, 26, 18, 4)
    inner = Shape.ellipse(48, 38, 22, 14)
    mask = Shape.union(plate, inner)
    c1 = Shape.intersect(Shape.line({34, 32}, {44, 40}, 1), inner)
    c2 = Shape.intersect(Shape.line({56, 30}, {52, 42}, 1), inner)
    c3 = Shape.intersect(Shape.line({40, 44}, {58, 46}, 1), inner)
    crack = Shape.union(Shape.union(c1, c2), c3)

    %{
      id: :plate,
      mask: mask,
      holes: crack,
      zones: %{crack: crack, note_a: c1, note_b: c2, note_c: c3, rim: plate},
      colour: :bone,
      clay: 50,
      wet: 72,
      hint: "Three cracks, three notes. Fill each one until the plate rings."
    }
  end

  def build(:doll) do
    head = Shape.ellipse(48, 18, 8, 8)
    body = Shape.rect(42, 25, 12, 20)
    arms = Shape.union(Shape.line({42, 30}, {34, 42}, 2), Shape.line({54, 30}, {62, 42}, 2))
    leg = Shape.rect(44, 45, 5, 14)
    missing = Shape.rect(43, 45, 8, 14)
    stand = Shape.rect(30, 58, 36, 4)

    mask =
      Shape.union(
        Shape.union(head, body),
        Shape.union(Shape.union(arms, leg), Shape.union(missing, stand))
      )

    %{
      id: :doll,
      mask: mask,
      holes: missing,
      zones: %{crack: missing, body: body, stand: stand},
      colour: :rose,
      clay: 70,
      wet: 50,
      hint:
        "This one was fired once. It will not bend; give it a leg that holds, not a leg that moves."
    }
  end

  def build(:hub) do
    wheel = Shape.ring(48, 36, 24, 20, 4)
    center = Shape.ellipse(48, 36, 6, 6)

    spokes =
      Enum.reduce([0, 1, 3, 4, 5], MapSet.new(), fn index, acc ->
        angle = index * :math.pi() / 3

        MapSet.union(
          acc,
          Shape.line(
            {48, 36},
            {48 + round(20 * :math.cos(angle)), 36 + round(16 * :math.sin(angle))},
            2
          )
        )
      end)

    missing = Shape.line({48, 36}, {28, 36}, 2)
    mask = Shape.union(Shape.union(wheel, center), Shape.union(spokes, missing))

    %{
      id: :hub,
      mask: mask,
      holes: missing,
      zones: %{crack: missing, wheel: wheel, spokes: spokes},
      colour: :ochre,
      clay: 85,
      wet: 60,
      hint: "A wheel is a promise that the spokes will share the weight. Give it the missing one."
    }
  end

  def build(:face) do
    head = Shape.ellipse(48, 36, 22, 26)
    eye_l = Shape.ellipse(39, 30, 4, 4)
    eye_r = Shape.ellipse(57, 30, 4, 4)
    mouth = Shape.ellipse(48, 47, 7, 3)
    mask = Shape.union(head, Shape.union(eye_l, Shape.union(eye_r, mouth)))
    holes = Shape.union(eye_l, Shape.union(eye_r, mouth))

    %{
      id: :face,
      mask: mask,
      holes: holes,
      zones: %{crack: holes, eyes: Shape.union(eye_l, eye_r), mouth: mouth, body: head},
      colour: :bone,
      clay: 60,
      wet: 70,
      hint: "A face is three holes and the space between them. Make the space kind."
    }
  end

  def build(:music_box) do
    box = Shape.rect(28, 40, 40, 20)
    lid = Shape.rect(28, 36, 40, 5)
    cylinder = Shape.ring(48, 32, 12, 7, 3)

    teeth =
      Shape.union(
        Shape.rect(34, 32, 3, 7),
        Shape.union(
          Shape.rect(40, 32, 3, 7),
          Shape.union(Shape.rect(54, 32, 3, 7), Shape.rect(60, 32, 3, 7))
        )
      )

    missing = Shape.union(Shape.rect(46, 32, 3, 7), Shape.rect(50, 32, 3, 7))
    mask = Shape.union(Shape.union(box, lid), Shape.union(cylinder, Shape.union(teeth, missing)))

    %{
      id: :music_box,
      mask: mask,
      holes: missing,
      zones: %{crack: missing, teeth: teeth, box: box, cylinder: cylinder},
      colour: :leather,
      clay: 65,
      wet: 58,
      hint: "Two teeth are missing from the comb. The tune is only as good as its gaps."
    }
  end

  def build(:bridge) do
    left = Shape.rect(20, 18, 12, 38)
    right = Shape.rect(64, 18, 12, 38)
    span = Shape.rect(32, 26, 32, 6)
    missing = Shape.rect(38, 26, 20, 6)
    mask = Shape.union(Shape.union(left, right), Shape.union(span, missing))

    %{
      id: :bridge,
      mask: mask,
      holes: missing,
      zones: %{crack: missing, span: span, towers: Shape.union(left, right)},
      colour: :slate,
      clay: 100,
      wet: 55,
      hint: "Ash will not hold a bridge. Clay and wire will."
    }
  end

  def build(:heart) do
    left = Shape.ellipse(42, 34, 12, 12)
    right = Shape.ellipse(54, 34, 12, 12)
    point = Shape.polygon([{28, 34}, {68, 34}, {48, 60}])
    mask = Shape.union(Shape.union(left, right), point)
    crack = Shape.intersect(Shape.line({48, 24}, {44, 38}, 1), mask)
    crack = Shape.union(crack, Shape.intersect(Shape.line({44, 38}, {52, 50}, 1), mask))

    %{
      id: :heart,
      mask: mask,
      holes: crack,
      zones: %{crack: crack, body: mask},
      colour: :terracotta,
      clay: 80,
      wet: 62,
      hint: "The Mender's heart cracked along an old seam. Wire it, or it will open again."
    }
  end

  def build(:sky) do
    arc = Shape.ring(48, 92, 58, 54, 5)
    mask = Shape.intersect(arc, Shape.rect(0, 0, 96, 56))
    hole = Shape.intersect(Shape.ellipse(48, 40, 10, 8), mask)

    %{
      id: :sky,
      mask: mask,
      holes: hole,
      zones: %{crack: hole, arc: mask},
      colour: :bone,
      clay: 140,
      wet: 75,
      hint: "A sky is a roof with no walls. It only holds if the whole arc shares the weight."
    }
  end
end
