# Megablast

A vertical shooter in the line of the Bitmap Brothers' Xenon 2 Megablast: five stages up
a living lane, a guardian half way up each and a boss at its end, credits to gather and
the trader's shop between stages.

```
mix megablast
mix test
```

The arrows (or WASD) steer and move up and down the view, Space fires, B (or E) lets a
bomb go, Escape pauses. In the shop, Up and Down choose and Space buys.

* **Five stages** — the Chitin Lane, the Weeping Flue, the Spore Gardens, the Iron Veins
  and the Queen's Heart, each a timeline of waves by how far up the lane they come
  (`lib/megablast/stages.ex`).
* **Creatures** — drones sweep, darts dive at where you were, spores burst into
  sporelets, orbs hold ahead and fire at you, shells creep and fire fans, turrets grow
  out of the rock.
* **Bosses** — a guardian half way, and at the end of each stage a boss whose core is
  armoured until its parts are broken, firing harder as it weakens: the Hive Mother, the
  Leviathan, the Spore Engine, the Iron Warden and the Queen.
* **Chains** — kills in quick succession chain; every five add to the multiplier, up to
  eight.
* **Credits and the shop** — creatures drop green credits; between stages the trader
  sells the mega cannon's levels, a laser, homing missiles, side and rear shots, drones,
  engines, smart bombs, shields and ships. A lost ship costs a level of every weapon.
* **Feel** — the world stops a moment when a boss part breaks or a ship is lost, the view
  shakes, struck things flash white.

## How it is made

| file | what it is |
|---|---|
| `lib/megablast/game.ex`, `spawn.ex`, `combat.ex`, `progress.ex` | the world, what comes in, every strike, the phases |
| `ship.ex`, `weapons.ex`, `shop.ex` | the ship, its kit, the trader |
| `foe.ex`, `pattern.ex`, `boss.ex`, `stages.ex` | the creatures, bullet patterns, bosses, and the five stages as data |
| `lane.ex` | the rock walls and turrets, drawn from each stage's rock |
| `scene.ex`, `hud.ex`, `title.ex`, `summary.ex`, `menus.ex`, `scores.ex` | the lane, hud, title, end screen, menus and best pilots, in the game's own art and font |
| `sound.ex` | synthesised effects, and the music |
| `assets.exs`, `assets.lock.exs` | the art the image model drew (`mix cauldron.assets`) |
| `priv/art` | that art finished as pixel art, and the hand-drawn bullets, shots, blasts and bars |
| `priv/audio` | two loops made with ACE-Step, cut to bars |
