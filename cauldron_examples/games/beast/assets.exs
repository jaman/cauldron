style_sprite =
  "16-bit Amiga pixel art game sprite in the style of Shadow of the Beast and Another World, side view, rich painterly shading, clean dark outline, limited palette"

layer = fn prompt, colours ->
  [prompt: prompt, background: {255, 0, 255}, size: {1024, 512}, count: 2, finish: [size: {256, 128}, palette: colours, dither: :bayer4, trim: false, outline: nil]]
end

sky = fn prompt ->
  [prompt: prompt, background: nil, size: {1024, 576}, count: 2, finish: [size: {256, 144}, palette: 32, dither: :bayer4, trim: false, outline: nil]]
end

rock = fn prompt ->
  [prompt: prompt, background: nil, size: {512, 512}, count: 1, finish: [size: {64, 64}, palette: 12, trim: false, outline: nil]]
end

hero_rig = "1792537326933-000000021373-tc74ksi"

rigged = fn motion, fit ->
  {seed, motion} = Keyword.pop(motion, :seed)
  {count, motion} = Keyword.pop(motion, :count, 1)
  [rig: hero_rig, seed: seed, count: count, motion: Keyword.put(motion, :yaw, 60), fit: fit]
end

%{
  project: "cauldron-games",
  model: "flux2_klein_4b",
  style: style_sprite,
  background: {255, 0, 255},
  outline: {12, 8, 10},
  palette: 16,
  assets: [
    hero: [prompt: "a muscular beast-man warrior with a long dark mane and horned brow, grey-green skin, leather loincloth and arm bands, standing facing right, full body", size: {512, 768}, fit: {32, 48}, count: 4],
    hero_run: rigged.([prompt: "a man runs forward at a steady, constant pace the whole time, pumping his arms", seconds: 6, seed: 11, loop: 1, keep: 8, arm_swing: [forward: 40, back: 10, elbow: 50]], {40, 48}),
    hero_punch: rigged.([prompt: "a boxer in his stance throws a quick straight jab at shoulder height, fully extending his arm straight ahead, then pulls it back to his guard, his feet planted and his chest facing forward the whole time", seconds: 2.0, seed: 81, count: 3, keep: 5, from: 0.25, to: 0.5], {48, 48}),
    hero_kick: rigged.([prompt: "a man standing facing forward kicks a door open in front of him: he lifts his right knee and thrusts the sole of his right foot straight ahead at waist height, then puts the foot back down, his chest facing forward the whole time", seconds: 2.0, seed: 71, count: 3, keep: 5, from: 0.26, to: 0.52], {48, 48}),
    hero_sweep: rigged.([prompt: "a man in a deep crouch facing forward kicks low at the ankles of an enemy in front of him: staying crouched, he slides his right foot far forward along the floor in front of him, then draws it back under him", seconds: 2.0, seed: 91, count: 3, keep: 5, from: 0.75, to: 1.0], {48, 32}),
    hero_jump: rigged.([prompt: "a man bends his knees and jumps high straight up, tucking his knees with his arms raised, then lands back on his feet", seconds: 2.5, seed: 21, keep: 1, from: 0.45, to: 0.45], {36, 48}),
    hero_duck: rigged.([prompt: "a man crouches down low, ready to spring, holds the crouch, then stands back up", seconds: 2.5, seed: 21, keep: 1, from: 0.5, to: 0.5], {36, 32}),
    hero_roll: rigged.([prompt: "a man tucks his head and does a forward somersault roll straight ahead along the ground, staying facing forward, and comes back up onto his feet facing the same way", seconds: 3.0, seed: 31, keep: 1, from: 0.45, to: 0.45], {32, 32}),
    hero_charge: rigged.([prompt: "a man facing forward slowly draws his right fist far back behind his shoulder, leaning back and gathering power, holds that wound-up pose still for a long moment, then throws a powerful punch straight forward", seconds: 3.0, seed: 43, keep: 1, from: 0.22, to: 0.22], {40, 48}),
    hero_hurt: rigged.([prompt: "a man facing forward the whole time is hit hard in the chest and staggers straight backwards, doubling over in pain, then straightens up", seconds: 2.5, seed: 31, keep: 1, from: 0.4, to: 0.4], {36, 48}),
    crawler: [prompt: "a low armoured scorpion-crab beast with a curled tail, facing left", fit: {24, 16}, count: 4],
    bat: [prompt: "a leathery red-eyed giant bat with spread wings", fit: {20, 16}, count: 4],
    goblin: [prompt: "a hunched green goblin with a spiked club, facing left, full body", size: {512, 768}, fit: {24, 36}, count: 4],
    goblin_raise: [from: :goblin, prompt: "the same goblin raising its spiked club high over its head; keep its look, pixel style and the flat magenta background", fit: {28, 40}],
    archer: [prompt: "a gaunt hooded skeleton archer with a longbow, facing left, full body", size: {512, 768}, fit: {22, 38}, count: 4],
    archer_draw: [from: :archer, prompt: "the same archer drawing its bow fully with an arrow nocked; keep its look, pixel style and the flat magenta background", fit: {26, 38}],
    wyrm: [prompt: "the head and neck of a giant sand wyrm bursting upward, gaping jaws full of teeth, red sand scales, facing left", size: {768, 768}, fit: {48, 64}, count: 4],
    troll: [prompt: "a huge hulking cave troll with grey warty skin and long arms, facing left, full body", size: {768, 768}, fit: {56, 64}, count: 4],
    troll_raise: [from: :troll, prompt: "the same troll raising both huge fists over its head to slam the ground; keep its look, pixel style and the flat magenta background", fit: {60, 70}],
    spirit: [prompt: "an ancient angry face carved in the bark of a giant tree trunk, glowing green eyes, gnarled roots", size: {768, 768}, fit: {56, 72}, count: 4],
    spirit_open: [from: :spirit, prompt: "the same tree face with its mouth gaping wide open and eyes blazing; keep its look, pixel style and the flat magenta background", fit: {56, 72}],
    mage: [prompt: "an evil sorcerer in a tall purple hat and flowing robes with a gnarled staff, facing left, full body", size: {512, 768}, fit: {28, 44}, count: 4],
    mage_cast: [from: :mage, prompt: "the same sorcerer raising his staff high, crackling with purple magic; keep his look, pixel style and the flat magenta background", fit: {32, 48}],
    plain_sky: sky.("a 16-bit Amiga game background in the style of Roger Dean: a vast red and violet alien sky over a blood-red plain, two moons, floating rock islands, painterly"),
    plain_far: layer.("a distant silhouette of jagged violet mountains and floating rocks along the bottom of the picture, painterly 16-bit Amiga game parallax layer", 16),
    plain_near: layer.("tall dark red grasses, bones and twisted dead shrubs along the bottom of the picture, painterly 16-bit Amiga game parallax foreground", 16),
    caverns_sky: sky.("a 16-bit Amiga game background: the depths of a vast underground cavern, glowing blue crystals, dripping stalactites, distant waterfalls, painterly, no text, no signature"),
    caverns_far: layer.("rows of dark stalagmites and rock pillars along the bottom of the picture, faintly lit blue, painterly 16-bit Amiga game parallax layer", 16),
    tree_sky: sky.("a 16-bit Amiga game background: inside the green canopy of an impossibly huge ancient tree, shafts of golden light, hanging vines, painterly"),
    tree_far: layer.("giant twisted branches and hanging moss along the bottom of the picture, painterly 16-bit Amiga game parallax layer", 16),
    castle_sky: sky.("a 16-bit Amiga game background: the vaulted hall of a sorcerer's castle, purple stained glass, chains and torches, painterly"),
    castle_far: layer.("stone columns, arches and banners along the bottom of the picture, painterly 16-bit Amiga game parallax layer", 16),
    rock_plain: rock.("a seamless texture of cracked blood-red desert rock"),
    rock_caverns: rock.("a seamless texture of dark blue-grey cave rock with crystal flecks"),
    rock_tree: rock.("a seamless tileable close-up texture of rough gnarled tree bark with moss in its cracks, the bark fills the entire square edge to edge, no background, no sky, not a whole tree") |> Keyword.merge(count: 2, style: "16-bit Amiga pixel art game tile texture, rich painterly shading, limited palette"),
    rock_castle: rock.("a seamless texture of dark purple castle stone bricks"),
    title_art: [
      prompt: "a 16-bit Amiga game title illustration in the style of Roger Dean and Shadow of the Beast: a lone beast-man on a cliff facing a dark sorcerer's castle under a red sky with two moons",
      background: nil,
      size: {1024, 768},
      count: 2,
      finish: [size: {256, 192}, palette: 40, dither: :bayer4, trim: false, outline: nil]
    ]
  ]
}
