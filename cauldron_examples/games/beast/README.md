# Beast

An action platformer in the look of Psygnosis' Shadow of the Beast, fought like a modern
one: a journey across four lands to the mage who made you a beast.

```
mix beast
mix beast.serve
mix beast.desktop
mix test
```

`mix beast` plays in the terminal. `mix beast.serve` serves the game to browsers at
`http://localhost:4310/play` (`--port`, and `--drawing server|client|split` for who
draws, as `Cauldron2D.Net.Serve` takes them). `mix beast.desktop` opens a desktop window
(`--name` for the player).

The arrows (or A and D) run, Up (or W) jumps, Down (or S) ducks, Space strikes, X rolls,
Escape rests. `B` shows the hit boxes: blue where things are, red where a blow strikes. On a controller the d-pad or left stick runs, `A` jumps, `X` strikes, `B`
rolls, `Y` (or down on the d-pad) ducks and `Start` rests.

* **Strikes** — Space, Space, Space is a jab, a cross and a kick, each pressed as the
  last ends (a press up to 0.2 s early still counts). Hold the strike after a jab and let go for a heavy blow. In the air it
  is a flying kick. Ducking, it strikes low — a low jab, then a sweep along the ground —
  and stays crouched until the sweep is done.
* **Reading the creatures** — every creature shows its blow before it strikes: a
  crawler shivers before it lunges, a bat hovers over you before it dives, a goblin
  raises its club, an archer draws. Strike one while it winds up and it staggers. Roll
  through what you cannot stop; duck under arrows.
* **Four lands** — the Red Plain, the Well, the Great Tree and the Mage's Castle, each a
  hand-built map (`priv/maps`) with standing stones that keep your place, healing fruit,
  and doors that need the land's key. `Beast.Reach` plays the beast's own jumps over each
  map, and `mix test` fails when a key, fruit, stone, ledge, boss or way on is out of
  reach.
* **Four bosses** — the gates shut behind you, and each boss leaves an opening, rung
  with a chime and named in a line over its health for the first seconds of the fight:
  the Sand Wyrm hunts you from under the ground and lies dazed after each dive, its head
  in reach; the Cave Troll sweeps (jump it), slams (jump the shockwaves) and charges
  (roll through) and is winded after, taking double harm; the Tree Spirit reaches with
  roots and seeds and opens its face only after; and Zelek the mage blinks between his
  perches calling orbs and lightning, and cannot move while the lightning comes. Blows
  break orbs and seeds. Fall in the arena and you are back at the last standing stone,
  the gates open, and the boss wakes whole when you go in again.

## How it is made

| file | what it is |
|---|---|
| `lib/beast/game.ex`, `combat.ex`, `region.ex` | the journey, every blow, the lands |
| `hero.ex`, `moves.ex` | the beast and its blows' frame data |
| `creature.ex`, `boss.ex`, `bosses/*.ex` | the creatures and the four bosses |
| `scene.ex`, `hud.ex`, `title.ex`, `summary.ex`, `menus.ex` | the lands, hud, title, end screen with the best journeys (`Cauldron.Scores`), and menus, in the game's own art and font |
| `sound.ex` | synthesised effects, and the music |
| `priv/maps` | the four lands, as text maps |
| `assets.exs`, `assets.lock.exs` | the art the image model drew; the beast's run, punch and kick are animated from its picture by video (`mix cauldron.assets`) |
| `priv/art` | that art finished as pixel art, and the hand-drawn missiles, ledges, spikes, doors, gates, stones and effects |
