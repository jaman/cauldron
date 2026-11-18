# Cistern, finished

Where the chapters of *Your first game* (`cauldron_2d/guides/tutorial.md`, built in
[`cauldron_examples/games/cistern`](../cistern)) lead: the same game, finished.

```
mix cistern_complete        # in this terminal
mix test
```

The town is dry and the Squall will rain anywhere but the cistern. You carry three clay
jars — one on your head, one at each end of a yoke.

* **Catch.** Walk under the rings on the ground; a ring grows as its drop comes down.
* **Fill and pour.** A jar holds five drops, and a drop into a full jar spills — a miss.
  Stand over the grate and press Down (or S, or Space) to pour. A pour scores the
  storm's number a drop, double when all three jars were full.
* **Read the Squall.** It drizzles, gusts (racing and spraying), sulks (stops, swells,
  and bursts), and grins after a miss. From the third storm it throws hail, which
  breaks a jar it lands in. From the fourth, a column flickers before lightning strikes
  it.
* **Misses.** A miss breaks the jar on that side, splashes the rain still falling, and
  sets the storm back a step. Fifteen catches in a row mend a broken side jar. The last
  jar broken, you are out, and a good score is signed into the town's best.
* **Versus.** Beside a robot keeper's square. A pour of three full jars sends a gust to
  your rival's Squall.

Escape pauses.

## How it is made

| file | what it is |
|---|---|
| `lib/cistern_complete/field.ex`, `yoke.ex`, `rain.ex`, `mishap.ex`, `lightning.ex`, `squall.ex`, `storm.ex`, `tuning.ex` | the rules, as values |
| `lib/cistern_complete/game.ex` | the `Cauldron.Game`: squares side by side, gusts between them |
| `lib/cistern_complete/scene.ex`, `hud.ex` | the square and its hud, drawn in the game's own art and font (`Cauldron2D.Screen`) |
| `lib/cistern_complete/title.ex`, `summary.ex`, `menus.ex`, `scores.ex` | its own title, end screen, menus (`Cauldron.Front`, `Cauldron.Menu`) and high scores |
| `lib/cistern_complete/sound.ex` | synthesised effects, and the music |
| `lib/cistern_complete/brain.ex`, `worlds.ex` | the robot keeper and the versus world |
| `assets.exs`, `assets.lock.exs` | the art the image model drew (`mix cauldron.assets`, `cauldron_2d_assets`) |
| `priv/art` | that art finished as pixel art, and the hand-drawn pictures beside it |
| `priv/audio` | two loops made with ACE-Step in NxDiffusion Studio, cut to 24 bars |

The Squall in its four moods, the keeper, the jars, hail, the dusk backdrop and the
title painting were drawn by FLUX.2 [klein] through NxDiffusion Studio and finished by
`Linocut.Pixelate`; the moods are edits of the chosen calm Squall, so it is the same
cloud in each. The font, the rain, rings, splashes, yoke, grate, cobbles, lightning,
frame, cursor and gauges are drawn by hand in `.pic` files.

To make the art again: `mix cauldron.assets` rebuilds it from the lock and the Studio's
library; `mix cauldron.assets --again NAME` asks for new candidates, and
`mix cauldron.assets.pick NAME INDEX` chooses one.
