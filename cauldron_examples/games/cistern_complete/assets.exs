%{
  project: "cauldron-games",
  model: "flux2_klein_4b",
  style:
    "16-bit pixel art game sprite in the style of a 1990s console game, chunky pixels, clean dark outline, warm dusk lighting, limited palette",
  background: {255, 0, 255},
  outline: {28, 16, 22},
  palette: 14,
  assets: [
    jar: [prompt: "a round terracotta clay water jar with a dark rim, seen from the side", fit: {16, 16}, count: 4],
    squall: [
      prompt: "a plump grey-violet storm cloud with a cheeky smiling face, two round eyes, rosy cheeks",
      size: {768, 512},
      fit: {48, 32},
      count: 4
    ],
    squall_grin: [
      from: :squall,
      prompt:
        "the same cloud, now with a wide mischievous toothy grin and narrowed gleeful eyes; keep its shape, colours, pixel style and the flat magenta background",
      fit: {48, 32},
      count: 4
    ],
    squall_sulk: [
      from: :squall,
      prompt:
        "the same cloud, now swollen and darker purple, frowning with puffed-out cheeks as if about to burst; keep its pixel style and the flat magenta background",
      fit: {48, 32},
      count: 4
    ],
    squall_gust: [
      from: :squall,
      prompt:
        "the same cloud, now angry with furrowed brows, blowing hard from pursed lips with white wind streaks; keep its pixel style and the flat magenta background",
      fit: {48, 32},
      count: 4
    ],
    keeper: [
      prompt:
        "a young water carrier in a wide straw hat and a blue tunic with brown trousers, seen from the front, standing, arms raised to the shoulders, full body",
      size: {512, 768},
      fit: {16, 30},
      count: 4
    ],
    hail: [prompt: "a single small round icy hailstone, pale blue and white", fit: {8, 8}, count: 4],
    backdrop: [
      prompt:
        "a 16-bit console game background: a dusk sky of violet and orange over a sleepy desert hill town of flat-roofed adobe houses with warm lit windows along the bottom, the first stars, painterly pixel art, wide view",
      background: nil,
      size: {1024, 704},
      count: 2,
      finish: [size: {256, 176}, palette: 32, dither: :bayer4, trim: false, outline: nil]
    ],
    title_art: [
      prompt:
        "a 16-bit console game title illustration: a small water carrier with three clay jars on a yoke looks up at a big grinning storm cloud with a face over a dusk desert town, violet and orange sky, painterly pixel art",
      background: nil,
      size: {1024, 704},
      count: 2,
      finish: [size: {256, 176}, palette: 40, dither: :bayer4, trim: false, outline: nil]
    ]
  ]
}
