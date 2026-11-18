defmodule Greenware.Campaign do
  @moduledoc """
  The Bake, act by act: its hubs, its scenes, the mends they hold and the lines around
  them. The world reads this data; nothing here draws.
  """

  @acts [
    %{
      id: 1,
      name: "THE WORKSHOP",
      subtitle: "where you woke",
      bg: :workshop,
      hub: :workshop_hub,
      exit: :garden_hub
    },
    %{
      id: 2,
      name: "THE GARDEN",
      subtitle: "everything is growing too fast",
      bg: :garden,
      hub: :garden_hub,
      exit: :cellar_hub
    },
    %{
      id: 3,
      name: "THE CELLAR",
      subtitle: "things put away",
      bg: :cellar,
      hub: :cellar_hub,
      exit: :fair_hub
    },
    %{
      id: 4,
      name: "THE FAIR",
      subtitle: "a carnival of broken toys",
      bg: :fair,
      hub: :fair_hub,
      exit: :kiln_hub
    },
    %{
      id: 5,
      name: "THE KILN ROAD",
      subtitle: "ash, heat, the Potter's house",
      bg: :kiln,
      hub: :kiln_hub,
      exit: nil
    }
  ]

  @order [
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

  @uses %{
    cup: %{label: "FILL THE CUP", effect: :water},
    key: %{label: "TURN THE LATCH", effect: :open},
    wing: %{label: "RELEASE THE BIRD", effect: :bird},
    bucket: %{label: "DRAW THE WATER", effect: :water},
    arm: %{label: "LIFT THE ARM", effect: :arm},
    dam: %{label: "HOLD THE STREAM", effect: :water},
    lamp: %{label: "LIGHT THE LAMP", effect: :light},
    plate: %{label: "HEAR THE CHOIR", effect: :ring},
    doll: %{label: "STAND THE DOLL", effect: :stand},
    hub: %{label: "TURN THE WHEEL", effect: :spin},
    face: %{label: "LOOK IN THE MIRROR", effect: :reflect},
    music_box: %{label: "PLAY THE BOX", effect: :music},
    bridge: %{label: "CROSS THE BRIDGE", effect: :cross},
    heart: %{label: "LISTEN", effect: :beat},
    sky: %{label: "FIRE THE SKY", effect: :dawn}
  }

  @hub_labels %{
    cup: "THE CUP",
    key: "THE LATCH",
    wing: "THE BIRD",
    bucket: "THE WELL",
    arm: "THE ARM",
    dam: "THE DAM",
    lamp: "THE LAMP",
    plate: "THE CHOIR",
    doll: "THE DOLL",
    hub: "THE WHEEL",
    face: "THE MIRROR",
    music_box: "THE BOX",
    bridge: "THE BRIDGE",
    heart: "THE HEART",
    sky: "THE SKY"
  }

  def hub_label(id), do: Map.get(@hub_labels, id, "A MEND")

  def acts, do: @acts

  def act(id), do: Enum.find(@acts, &(&1.id == id))

  def act_count, do: length(@acts)

  @doc "The hub of act `id`."
  def hub(id) do
    case id do
      1 ->
        %{
          id: :workshop_hub,
          act: 1,
          title: "THE WORKSHOP",
          subtitle: "THE DRIP IS BACK",
          bg: :workshop,
          intro: [
            {:narrator, "You wake on the workbench with a brass key in your chest and no face."},
            {:cat,
             "You are late. The roof is leaking, the door is stuck, and the Mender is gone."},
            {:cat, "Start with the cup. It is the smallest thing that is wrong."},
            {:cat, "Mend it, then use it. A mended thing is only a promise until it is used."}
          ],
          exit: %{label: "THE GARDEN DOOR", to: :garden_hub, requires: [:cup, :key]}
        }

      2 ->
        %{
          id: :garden_hub,
          act: 2,
          title: "THE GARDEN",
          subtitle: "THE WELL IS DRY",
          bg: :garden,
          intro: [
            {:narrator,
             "The garden has grown over the path in a single night. Everything is thirsty."},
            {:green_man,
             "The well has been dry since the Kiln went cold. The bucket leaks. The bed is cracked."},
            {:cat, "He will not ask you to fix his arm. You should offer."}
          ],
          exit: %{label: "THE CELLAR STAIR", to: :cellar_hub, requires: [:bucket, :arm, :dam]}
        }

      3 ->
        %{
          id: :cellar_hub,
          act: 3,
          title: "THE CELLAR",
          subtitle: "THE DARK IS NOT EMPTY",
          bg: :cellar,
          intro: [
            {:narrator, "The stairs go down farther than the house is tall."},
            {:choir, "Ah. A new hand. A new hand. A new hand."},
            {:cat, "The lamp first. Do not go into the dark holding a broken lamp."}
          ],
          exit: %{label: "THE CELLAR DOOR", to: :fair_hub, requires: [:lamp, :plate, :doll]}
        }

      4 ->
        %{
          id: :fair_hub,
          act: 4,
          title: "THE FAIR",
          subtitle: "EVERYTHING HERE WAS LOVED ONCE",
          bg: :fair,
          intro: [
            {:narrator, "The Fair is still turning, though nobody has bought a ticket in years."},
            {:boy, "Are you the Mender? You are smaller than the last one."},
            {:cat, "He is a drawing. Be careful what you give him."}
          ],
          exit: %{label: "THE KILN ROAD", to: :kiln_hub, requires: [:hub, :face, :music_box]}
        }

      5 ->
        %{
          id: :kiln_hub,
          act: 5,
          title: "THE KILN ROAD",
          subtitle: "THE POTTER'S HOUSE",
          bg: :kiln,
          intro: [
            {:narrator, "Ash falls like warm snow. Ahead, the Kiln stands open and cold."},
            {:potter, "You came. I made you to fix what I could not."},
            {:cat, "Do not believe everything a voice in a kiln says."}
          ],
          exit: nil
        }
    end
  end

  @scenes %{
    cup: %{
      id: :cup,
      act: 1,
      title: "A CUP FOR THE DRIP",
      subtitle: "THE WORKSHOP",
      bg: :workshop,
      objective: "Seal the cup and fire it so it holds water.",
      puzzle: :cup,
      requires: [],
      optional?: false,
      figures: [{:greenware, 170, 250}, {:cat, 470, 272}],
      prop: {:cup, 300, 240},
      hotspot: %{id: :cup, rect: {270, 210, 110, 90}, label: "THE CRACKED CUP", kind: :mend},
      intro: [
        {:narrator, "A drip falls from the roof into a cup that will not hold it."},
        {:cat, "That cup is older than you. It is also the only one left."},
        {:cat,
         "Press clay into the crack. Smooth it. Then fire it, or the water will take it apart."}
      ],
      success: [
        {:narrator, "The cup fills. The drip stops being a loss."},
        {:cat, "There. The door next."}
      ]
    },
    key: %{
      id: :key,
      act: 1,
      title: "THE LATCH",
      subtitle: "THE WORKSHOP DOOR",
      bg: :workshop,
      objective: "Fill the missing tooth and fire the key.",
      puzzle: :key,
      requires: [:cup],
      optional?: false,
      figures: [{:greenware, 200, 250}, {:cat, 480, 272}],
      prop: {:key, 320, 300},
      hotspot: %{id: :key, rect: {240, 220, 160, 80}, label: "THE BROKEN LATCH", kind: :mend},
      intro: [
        {:narrator, "The door is shut. The latch is a clay key with one tooth missing."},
        {:cat, "A key is not a hammer. It has to fit before it has to be strong."},
        {:cat, "The tooth is the whole key."}
      ],
      success: [
        {:narrator, "The key turns. The door opens onto a garden."},
        {:cat, "The Mender left a letter behind the coat. I cannot read it. You can."}
      ]
    },
    wing: %{
      id: :wing,
      act: 1,
      title: "THE BIRD'S WING",
      subtitle: "THE WINDOW",
      bg: :workshop,
      objective: "Mend the tear and wire the wing.",
      puzzle: :wing,
      requires: [:cup],
      optional?: true,
      figures: [{:greenware, 180, 250}, {:cat, 480, 272}],
      prop: {:bird, 360, 180},
      hotspot: %{id: :wing, rect: {320, 150, 120, 80}, label: "THE BIRD ON THE SILL", kind: :mend},
      intro: [
        {:narrator, "A bird is caught between the window and the storm. One wing is torn."},
        {:cat, "It will not thank you. Mend it anyway."},
        {:cat, "A wing is thin. Wire it, or it will tear again."}
      ],
      success: [
        {:narrator, "The bird tests the wing once, twice, and is gone."},
        {:cat, "It left a feather. You can keep it, or you can give it to someone who needs it."}
      ]
    },
    bucket: %{
      id: :bucket,
      act: 2,
      title: "THE DRY WELL",
      subtitle: "THE GARDEN",
      bg: :garden,
      objective: "Seal the bucket and fire it.",
      puzzle: :bucket,
      requires: [:cup, :key],
      optional?: false,
      figures: [{:green_man, 160, 240}, {:greenware, 250, 255}, {:cat, 520, 275}],
      prop: {:bucket, 365, 230},
      hotspot: %{id: :bucket, rect: {310, 215, 110, 80}, label: "THE LEAKING BUCKET", kind: :mend},
      intro: [
        {:narrator, "The garden is dry. The well is deep. The bucket has a hole in its bottom."},
        {:green_man, "I have carried water in my hands for three days. It is not working."},
        {:cat, "Start at the bottom. Water always does."}
      ],
      success: [
        {:narrator, "The bucket comes up full. The garden drinks."},
        {:green_man, "You have a good hand. My arm, though. My arm is not good."}
      ]
    },
    arm: %{
      id: :arm,
      act: 2,
      title: "THE GREEN MAN'S ARM",
      subtitle: "THE GARDEN",
      bg: :garden,
      objective: "Join the elbow and wire the joint.",
      puzzle: :arm,
      requires: [:bucket],
      optional?: false,
      figures: [{:green_man, 160, 240}, {:greenware, 300, 255}, {:cat, 500, 275}],
      prop: {:arm, 400, 240},
      hotspot: %{id: :arm, rect: {330, 210, 150, 90}, label: "THE GREEN MAN'S ARM", kind: :mend},
      intro: [
        {:narrator, "The Green Man's arm hangs at an angle a joint should not make."},
        {:green_man, "I can still hold a seed. I cannot hold a spade."},
        {:cat, "A joint is a hinge. Wire it, or it will break in the same place."}
      ],
      success: [
        {:narrator, "The arm bends. The Green Man lifts a spade, and then, carefully, a seed."},
        {:green_man, "The dam is cracking. You should go before the water does."}
      ]
    },
    dam: %{
      id: :dam,
      act: 2,
      title: "THE DAM",
      subtitle: "THE GARDEN'S EDGE",
      bg: :garden,
      objective: "Close the crack and fire the wall.",
      puzzle: :dam,
      requires: [:bucket, :arm],
      optional?: false,
      figures: [{:greenware, 220, 255}, {:cat, 470, 275}],
      prop: {:dam, 360, 230},
      hotspot: %{id: :dam, rect: {280, 200, 180, 110}, label: "THE CRACKING DAM", kind: :mend},
      intro: [
        {:narrator,
         "The dam holds back the stream by habit. A crack runs from the top to the base."},
        {:cat, "The water is already coming. Shape it, then fire it. Do not wait."}
      ],
      success: [
        {:narrator, "The wall holds. The stream turns aside and the garden keeps its feet."},
        {:cat,
         "The cellar stair is open. Bring a light. There is something down there that sings."}
      ]
    },
    lamp: %{
      id: :lamp,
      act: 3,
      title: "A LAMP FOR THE CELLAR",
      subtitle: "THE CELLAR",
      bg: :cellar,
      objective: "Seal the bowl, wire the handle, and fire the lamp.",
      puzzle: :lamp,
      requires: [:dam],
      optional?: false,
      figures: [{:greenware, 220, 255}],
      prop: {:lamp, 340, 230},
      hotspot: %{id: :lamp, rect: {280, 200, 130, 100}, label: "THE LAMP", kind: :mend},
      intro: [
        {:narrator, "The cellar is a throat. The lamp is the only warm thing in it."},
        {:choir, "Light. Light. Light. We have not seen the walls in years."},
        {:cat, "Seal the bowl. A lamp that leaks oil is a fire, not a light."}
      ],
      success: [
        {:narrator, "The wick catches. The cellar becomes a room again."},
        {:choir, "Oh. Oh, we are cracked. Would you look at us? We are all cracked."}
      ]
    },
    plate: %{
      id: :plate,
      act: 3,
      title: "THE CRACKED CHOIR",
      subtitle: "THE CELLAR",
      bg: :cellar,
      objective: "Fill the three cracks until the plate rings, then fire it.",
      puzzle: :plate,
      requires: [:lamp],
      optional?: false,
      figures: [{:greenware, 220, 255}, {:choir, 400, 215}],
      prop: {:plate, 360, 230},
      hotspot: %{id: :plate, rect: {290, 190, 150, 110}, label: "THE CRACKED PLATE", kind: :mend},
      intro: [
        {:narrator, "A stack of plates hums. Each crack has a note, and each note is wrong."},
        {:choir, "We used to sing at the Fair. Now we only rattle."},
        {:cat, "Fill each crack to its note. The plate will tell you when it is right."}
      ],
      success: [
        {:narrator,
         "The plate rings. The other plates answer, one by one, until the cellar is a chord."},
        {:choir, "The door. The door with the names. It opens for a whole note."}
      ]
    },
    doll: %{
      id: :doll,
      act: 3,
      title: "THE FIRST FIRED THING",
      subtitle: "THE CELLAR",
      bg: :cellar,
      objective: "Give the fired doll a leg that stands, and fire it.",
      puzzle: :doll,
      requires: [:lamp, :plate],
      optional?: false,
      figures: [{:greenware, 210, 255}, {:choir, 420, 215}],
      prop: {:doll, 340, 215},
      hotspot: %{id: :doll, rect: {300, 180, 90, 120}, label: "THE FIRED DOLL", kind: :mend},
      intro: [
        {:narrator, "The doll is the first thing the Potter ever fired. Its leg is gone."},
        {:choir, "It cannot be changed. It can only be added to."},
        {:cat, "This one is already hard. Do not try to bend it. Give it a leg that holds."}
      ],
      success: [
        {:narrator,
         "The doll stands. It does not thank you; it was never given a mouth for that."},
        {:cat, "The Fair is through the door. The Boy is waiting."}
      ]
    },
    hub: %{
      id: :hub,
      act: 4,
      title: "THE FERRIS WHEEL",
      subtitle: "THE FAIR",
      bg: :fair,
      objective: "Replace the missing spoke, wire the hub, and fire it.",
      puzzle: :hub,
      requires: [:doll],
      optional?: false,
      figures: [{:greenware, 190, 255}, {:boy, 470, 245}, {:cat, 540, 275}],
      prop: {:ferris, 330, 300},
      hotspot: %{id: :hub, rect: {250, 140, 180, 140}, label: "THE FERRIS HUB", kind: :mend},
      intro: [
        {:narrator,
         "The Ferris wheel leans on one missing spoke. The Fair waits for it to fall."},
        {:boy, "If it turns again, I can see the whole Bake from the top."},
        {:cat, "A wheel shares its weight. Give it all six."}
      ],
      success: [
        {:narrator, "The wheel turns. The Boy rides it to the top and does not look down."},
        {:boy, "You can see the Kiln from here. It is not far."}
      ]
    },
    face: %{
      id: :face,
      act: 4,
      title: "THE HALL OF MIRRORS",
      subtitle: "THE FAIR",
      bg: :fair,
      objective: "Give yourself eyes and a mouth, then fire the face.",
      puzzle: :face,
      requires: [:hub],
      optional?: false,
      figures: [{:greenware, 250, 260}, {:boy, 470, 245}, {:cat, 540, 275}],
      prop: {:mirror, 380, 300},
      hotspot: %{id: :face, rect: {320, 160, 120, 120}, label: "THE MIRROR", kind: :mend},
      intro: [
        {:narrator, "The mirror shows a face you have not made yet."},
        {:boy, "You do not have to look like the Mender. You can look like you."},
        {:cat, "Three holes and the space between them. Make the space kind."}
      ],
      success: [
        {:narrator, "The face in the mirror is yours. It is not the Mender's. The Boy grins."},
        {:boy, "Now you can make the face you want when you meet the Potter."}
      ]
    },
    music_box: %{
      id: :music_box,
      act: 4,
      title: "THE RINGMASTER'S BOX",
      subtitle: "THE FAIR",
      bg: :fair,
      objective: "Fill the missing teeth, wire the comb, and fire the box.",
      puzzle: :music_box,
      requires: [:hub, :face],
      optional?: false,
      figures: [{:greenware, 200, 255}, {:boy, 480, 245}, {:cat, 540, 275}],
      prop: {:box, 360, 235},
      hotspot: %{id: :music_box, rect: {300, 200, 140, 100}, label: "THE MUSIC BOX", kind: :mend},
      intro: [
        {:narrator, "The music box is the Fair's heart. Two teeth are missing from its comb."},
        {:boy, "It used to play the song the Potter whistled. I only remember the gaps."},
        {:cat, "The tune lives in the gap. Give it back."}
      ],
      success: [
        {:narrator, "The box plays. The Fair stops, all at once, to listen."},
        {:narrator, "When the song ends, the Kiln Road is open."}
      ]
    },
    bridge: %{
      id: :bridge,
      act: 5,
      title: "THE ASH BRIDGE",
      subtitle: "THE KILN ROAD",
      bg: :kiln,
      objective: "Span the ash with clay and wire, then fire the bridge.",
      puzzle: :bridge,
      requires: [:music_box],
      optional?: false,
      figures: [{:greenware, 170, 255}, {:cat, 500, 275}],
      prop: {:chasm, 350, 250},
      hotspot: %{id: :bridge, rect: {270, 210, 170, 90}, label: "THE BROKEN SPAN", kind: :mend},
      intro: [
        {:narrator, "The road ends at a chasm of warm ash. Something below is still burning."},
        {:cat, "Ash is a poor foundation. The wire is the bridge."}
      ],
      success: [
        {:narrator, "The bridge holds. The Cat crosses first, then pretends it did not."}
      ]
    },
    heart: %{
      id: :heart,
      act: 5,
      title: "THE MENDER'S HEART",
      subtitle: "THE POTTER'S HOUSE",
      bg: :kiln,
      objective: "Wire the Mender's heart and fire it shut.",
      puzzle: :heart,
      requires: [:bridge],
      optional?: false,
      figures: [{:potter, 420, 235}, {:greenware, 220, 255}, {:cat, 520, 275}],
      prop: {:heart, 320, 225},
      hotspot: %{id: :heart, rect: {270, 180, 100, 110}, label: "THE CRACKED HEART", kind: :mend},
      intro: [
        {:narrator,
         "The Potter's house is empty except for a heart on the table. It is cracked."},
        {:potter, "That is the Mender's. I made it too. I made it too small."},
        {:cat, "You do not have to fix it. You could leave it. But you came all this way."}
      ],
      success: [
        {:narrator, "The heart closes. For a moment the house smells of rain on warm clay."},
        {:potter, "The Kiln is yours. Do what I could not."}
      ]
    },
    sky: %{
      id: :sky,
      act: 5,
      title: "THE SKY",
      subtitle: "THE KILN",
      bg: :kiln,
      objective: "Mend the whole arc, wire it, and fire the sky.",
      puzzle: :sky,
      requires: [:heart],
      optional?: false,
      figures: [{:potter, 420, 235}, {:greenware, 240, 255}, {:cat, 520, 275}],
      prop: {:kiln, 480, 300},
      hotspot: %{id: :sky, rect: {180, 130, 260, 170}, label: "THE CRACK IN THE SKY", kind: :mend},
      intro: [
        {:narrator,
         "Above the Kiln, the sky is a clay dome with a hole in it. Through the hole: nothing."},
        {:potter, "Fire it and it will be perfect. Leave it and it will keep changing."},
        {:cat, "Whatever you choose, choose it with your own face."}
      ],
      success: [
        {:narrator, "The sky holds. The Kiln waits."},
        {:narrator, "There is still the choice."}
      ]
    }
  }

  @doc "One scene."
  def scene(id) do
    @scenes
    |> Map.fetch!(id)
    |> Map.put(:use, Map.fetch!(@uses, id))
  end

  def use(id), do: Map.fetch!(@uses, id)

  @doc "Every scene, by id."
  def scenes, do: @scenes

  @doc "Scenes of an act, in the order they are shown."
  def act_scenes(act) do
    @order
    |> Enum.map(&scene/1)
    |> Enum.filter(&(&1.act == act))
  end

  @doc "Whether a scene is open, given the completed ones."
  def available?(%{requires: requires}, completed), do: Enum.all?(requires, &(&1 in completed))

  @doc "The required scenes of an act."
  def required_scenes(act) do
    act |> act_scenes() |> Enum.reject(& &1.optional?)
  end

  @doc "Whether an act's required scenes are all done."
  def act_complete?(act, completed) do
    Enum.all?(required_scenes(act), &(&1.id in completed))
  end

  @doc "The hub after `act`, or `nil`."
  def next_hub(act) do
    case act(act) do
      %{exit: nil} -> nil
      %{exit: hub} -> hub
    end
  end

  @doc "The three endings, as pages of lines."
  def endings do
    %{
      fire: %{
        title: "FIRED",
        lines: [
          {:narrator,
           "You fire the sky. The crack closes. The world goes still and bright and perfect."},
          {:narrator, "Nothing dries. Nothing cracks. Nothing changes."},
          {:cat, "It is beautiful. It is also finished. There is no morning after this one."},
          {:narrator, "The Bake is a bowl on a shelf. It will never need mending again."}
        ]
      },
      green: %{
        title: "GREENWARE",
        lines: [
          {:narrator, "You leave the sky green. The crack stays. The world keeps breathing."},
          {:narrator, "Things will dry. Things will break. You will be there with your hands."},
          {:cat, "Good. A world that cannot break cannot be mended."},
          {:narrator,
           "The Kiln goes cold. The garden keeps growing. You make a cup for the drip."}
        ]
      },
      mend: %{
        title: "THE NEW KILN",
        lines: [
          {:narrator, "You climb into the Kiln and give it your key. The fire takes."},
          {:narrator,
           "You become the warm thing at the edge of the Bake, the place where broken clay goes."},
          {:cat, "I will keep the door open. Someone has to tell them how."},
          {:narrator,
           "In the morning, a small figure wakes on a workbench with no face and a key in its chest."}
        ]
      }
    }
  end
end
