# Cistern

The game *Your first game* builds, step by step, in the Cauldron documentation
(`cauldron_2d/guides/tutorial.md`): a storm cloud with a face drifts over a town in
drought, and you carry three jars — one on your head, one at each end of a yoke — to
catch its rain. A drop that reaches the ground breaks a jar and sets the storm back;
storms grow faster; the last jar broken, you are out.

```
mix cistern                 # in this terminal
mix cistern.serve           # http://localhost:4300/play
mix cistern.desktop         # in a window
mix test
```

| file | step |
|---|---|
| `lib/cistern/game.ex`, `field.ex`, `squall.ex`, `storm.ex`, `tuning.ex` | the game as a value |
| `test/cistern/game_test.exs` | testing it without a world |
| `priv/art/*.pic`, `atlas.txt`, `lib/cistern/art.ex` | the art |
| `lib/cistern/client.ex`, `lib/mix/tasks/cistern.ex` | on screen |
| `lib/cistern/sound.ex` | sound and music |
| `lib/cistern/worlds.ex`, `brain.ex` | more players and a robot |
| `lib/cistern/web.ex`, `lib/mix/tasks/cistern.serve.ex` | a browser |
| `lib/mix/tasks/cistern.desktop.ex` | a window |
