# Town

A town to walk around, in any of the terminal client's projections: top-down, isometric
(turned and tilted), or from inside it. Every player is a villager; villagers of the
town's own wander the paved streets.

```
mix town                    # in this terminal
mix town --name alice
mix test
```

It opens in the town, isometric, with the keys the drafter demo had:

| keys | what |
|---|---|
| `W A S D`, arrows | walk, turned with the view; in first person `W`/`S` along the eye, `A`/`D` across it |
| `Tab` | the view: isometric, first person, top-down |
| `Q` `E` | turn the isometric view a quarter, or the eye by 15° |
| `\` `Z` / `/` `C` | tilt the isometric diamond up or down, or pitch the eye |
| `M` | mouse look: the pointer turns and pitches the eye in first person |
| `T`, `B` | pictures against block characters; the glyph set (half, quad, sextant, octant) |
| `+` `-`, wheel | zoom |
| click yourself, point, click | plan a way and walk it; the pointer shows the path and its distance |
| `R`, `L` | the measuring rule (straight-line, D&D, Pathfinder); a range of six tiles |
| `Esc`, `X`, right button | put a plan down |
| `?`, `^Q` | the hints; quit |

On a controller the left stick walks, the right stick nudges the aim a tile at a time (or
looks around in first person), `A` picks, `B` cancels, `Start` changes the view, `X`
toggles cells and the bumpers zoom.

| file | what |
|---|---|
| `priv/town.txt`, `lib/town/legend.ex` | the map, one character a tile, and the cells it becomes; doors face the nearest road |
| `priv/art/*.pic`, `atlas.txt`, `lib/town/art.ex` | the pictures: floors, props, the storeys of each kind of building with their faces, villagers in five tunics posed front, back and side, standing and walking |
| `lib/town/rules.ex` | the three ways of measuring a distance |
| `lib/town/game.ex` | the `Cauldron2D.Game`: walking, wandering, picking a way |
| `lib/town/client.ex` | the `Cauldron2D.Client.Game`: the scene, the hud, the keys |
| `lib/mix/tasks/town.ex` | `mix town` |

The pictures are the ones the drafter demo `drafter/examples/spark/35_isometric_town.exs`
draws with; here the engine draws them, and the game is only the town.
