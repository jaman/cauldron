%{
  project: "cauldron-games",
  model: "flux2_klein_4b",
  style:
    "16-bit pixel art game sprite in the style of the Bitmap Brothers, biomechanical chrome and chitin, glossy metallic highlights, clean dark outline, seen from directly above",
  background: {255, 0, 255},
  outline: {8, 6, 18},
  palette: 16,
  assets: [
    ship: [prompt: "a sleek chrome and teal starfighter pointing straight up, twin engines, small cockpit", fit: {24, 24}, count: 4],
    drone: [prompt: "a small bulbous insect drone with glowing red eyes and wings", fit: {16, 16}, count: 4],
    dart: [prompt: "a narrow arrowhead-shaped bone-white insect pointing straight down", fit: {14, 16}, count: 4],
    spore: [prompt: "a round green spore pod covered in bumps, glowing yellow centre", fit: {20, 20}, count: 4],
    sporelet: [prompt: "a tiny round green spore seed, glowing", fit: {10, 10}, count: 4],
    orb: [prompt: "a floating purple eyeball creature wrapped in a chrome ring", fit: {20, 20}, count: 4],
    shell: [prompt: "a heavily armoured beetle shell with brass plates and a gun barrel, facing down", fit: {28, 28}, count: 4],
    turret: [prompt: "a fleshy wall-mounted gun turret with a chrome barrel", fit: {16, 16}, count: 4],
    guardian: [prompt: "a biomechanical guardian creature, armoured carapace, glowing core, facing down", fit: {48, 40}, size: {768, 640}, count: 4],
    hive_mother: [prompt: "a huge grotesque hive mother insect queen boss, swollen abdomen, many legs, chrome mandibles, facing down", fit: {80, 56}, size: {1024, 704}, count: 4],
    hive_sac: [prompt: "a pulsing yellow egg sac with veins", fit: {28, 28}, count: 4],
    leviathan: [prompt: "a giant biomechanical sea serpent skull boss with an open jaw full of chrome teeth, facing down", fit: {88, 56}, size: {1024, 640}, count: 4],
    leviathan_eye: [prompt: "a single glowing red reptile eye set in chrome", fit: {20, 20}, count: 4],
    spore_engine: [prompt: "a huge organic spore factory boss machine with pipes and green glowing vents, facing down", fit: {88, 56}, size: {1024, 640}, count: 4],
    spore_vent: [prompt: "a round fleshy vent nozzle glowing green", fit: {24, 24}, count: 4],
    iron_warden: [prompt: "a massive iron fortress beetle boss with riveted plates and four gun ports, facing down", fit: {88, 56}, size: {1024, 640}, count: 4],
    warden_gun: [prompt: "a small riveted iron cannon turret seen from above", fit: {20, 20}, count: 4],
    queen: [prompt: "the alien insect queen final boss, elegant and terrifying, chrome crown, translucent wings, facing down", fit: {96, 64}, size: {1024, 704}, count: 4],
    queen_claw: [prompt: "a huge chrome and chitin pincer claw", fit: {32, 32}, count: 4],
    trader: [
      prompt: "a friendly bug-eyed alien shopkeeper bust portrait with a monocle and a merchant's cap, 16-bit pixel art",
      style: "16-bit pixel art character portrait in the style of the Bitmap Brothers, glossy shading, clean dark outline",
      fit: {64, 64},
      count: 4
    ],
    deep_1: [prompt: "a seamless top-down view of an alien hive interior, dark teal chitin ribs and glowing amber pods, organic", background: nil, size: {512, 1024}, count: 2, finish: [size: {160, 320}, palette: 24, dither: :bayer4, trim: false, outline: nil]],
    deep_2: [prompt: "a seamless top-down texture that fills the whole frame edge to edge, no border and no background: dark red fleshy biomechanical flue walls with dripping veins and bone pipes", background: nil, size: {512, 1024}, count: 2, finish: [size: {160, 320}, palette: 24, dither: :bayer4, trim: false, outline: nil]],
    deep_3: [prompt: "a seamless top-down view of an alien spore garden, dark green mossy ground with glowing yellow fungi", background: nil, size: {512, 1024}, count: 2, finish: [size: {160, 320}, palette: 24, dither: :bayer4, trim: false, outline: nil]],
    deep_4: [prompt: "a seamless top-down view of dark iron machinery veins with riveted plates and orange molten channels", background: nil, size: {512, 1024}, count: 2, finish: [size: {160, 320}, palette: 24, dither: :bayer4, trim: false, outline: nil]],
    deep_5: [prompt: "a seamless top-down texture that fills the whole frame edge to edge, no border and no background: purple alien hive membrane covering the entire picture, pulsing violet veins and chrome ribs running across it, no objects", background: nil, size: {512, 1024}, count: 2, finish: [size: {160, 320}, palette: 24, dither: :bayer4, trim: false, outline: nil]],
    rock_1: [prompt: "a seamless texture of dark teal biomechanical chitin rock wall, ridged", background: nil, size: {512, 512}, count: 1, finish: [size: {64, 64}, palette: 12, trim: false, outline: nil]],
    rock_2: [prompt: "a seamless texture of dark red fleshy rock wall with veins", background: nil, size: {512, 512}, count: 1, finish: [size: {64, 64}, palette: 12, trim: false, outline: nil]],
    rock_3: [prompt: "a seamless texture of mossy green alien rock wall with fungus", background: nil, size: {512, 512}, count: 1, finish: [size: {64, 64}, palette: 12, trim: false, outline: nil]],
    rock_4: [prompt: "a seamless texture of riveted rusty iron plate wall", background: nil, size: {512, 512}, count: 1, finish: [size: {64, 64}, palette: 12, trim: false, outline: nil]],
    rock_5: [prompt: "a seamless texture of purple chitin and chrome rib wall", background: nil, size: {512, 512}, count: 1, finish: [size: {64, 64}, palette: 12, trim: false, outline: nil]],
    title_art: [
      prompt: "a 16-bit Bitmap Brothers style title illustration: a chrome starfighter blasting up a glowing alien biomechanical tunnel toward a huge insect queen, dramatic, no text, no letters, no logo, no title",
      background: nil,
      size: {1024, 768},
      count: 2,
      finish: [size: {256, 192}, palette: 40, dither: :bayer4, trim: false, outline: nil]
    ]
  ]
}
