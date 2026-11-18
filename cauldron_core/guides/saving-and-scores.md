# Saving and scores

Cauldron keeps three kinds of progress for a game, each in its own place: saved games
from `Cauldron.Save`, a local high-score table from `Cauldron.Scores`, and every player's
results and the boards made from them from `Cauldron.Ledger`. None of them is a process
except the ledger.

## Where the files live

All of it goes through `Cauldron.Paths`, one directory per game under the XDG base
directories:

| Call | Directory |
| --- | --- |
| `Cauldron.Paths.config(home, parts)` | `$XDG_CONFIG_HOME/<home>`, or `~/.config/<home>` |
| `Cauldron.Paths.data(home, parts)` | `$XDG_DATA_HOME/<home>`, or `~/.local/share/<home>` |
| `Cauldron.Paths.cache(home, parts)` | `$XDG_CACHE_HOME/<home>`, or `~/.cache/<home>` |

`home` is the game's `home/0` in its client module, or its first name underscored:
`Tag.Client` is `:tag`. Nothing in `Cauldron.Paths` creates a directory; the writer does.

| File | Kept by | Path |
| --- | --- | --- |
| A saved game | `Cauldron.Save` | `data/<home>/saves/<slot>.save` |
| The high-score table | `Cauldron.Scores` | `data/<home>/scores.terms` |
| Results and boards | `Cauldron.Ledger` | the `:path` it was started with, such as `data/<home>/ledger.dets` |
| A player's settings | the front end | `config/<home>/<player>.settings`, or `config/<home>/<player>.<kind>.settings` for another kind of client |
| Rendered music | `Cauldron.Audio` | `cache/<home>/music`, from `Cauldron.Client.Game.music_dir/1` |

The ledger's lock is `<path>.lock`, beside its file.

## Saved games

A save is a game state under a slot name. The natural state to keep is the world's:

```elixir
:ok = Cauldron.Save.write(:tag, "quick", Cauldron.World.snapshot(world))

{:ok, state} = Cauldron.Save.read(:tag, "quick")
{:ok, world} = Cauldron.World.start_link(game: Tag.Game, state: state)
```

`Cauldron.Save.write/3` stores `%{saved_at: DateTime.utc_now(), state: state}` as an
Erlang term and replaces what was there. `read/2` gives `{:ok, state}`, or
`{:error, :enoent}` when there is no slot, `{:error, :corrupt}` when the file is not a
save, and `{:error, :bad_slot}` for a slot name that is not one path segment.

| Function | Does |
| --- | --- |
| `Cauldron.Save.path/2` | The file a slot would be kept in |
| `Cauldron.Save.write/3` | Keep a state under a slot |
| `Cauldron.Save.read/2` | Read it back |
| `Cauldron.Save.list/1` | Every slot, oldest first, with when it was written |
| `Cauldron.Save.delete/2` | Forget a slot |

A slot name is one path segment: anything with a separator or `..` is refused, so a
player's typed name can be used as a slot without escaping the saves directory. The
state is any term the game already knows; it is read with `:erlang.binary_to_term/2`'s
`:safe`, so a file cannot introduce an atom the running node does not have.

A world started from a saved state does not call the game's `init/1`, and it starts with
no players: the game's `join/3` is called for each player as they join again. A game
whose saved state refers to players should therefore treat `join/3` as "take my place in
this state", not "make a new player", when the id is already in it.

## High scores

`Cauldron.Scores` is the local table: the best scores, best first, each a map with at
least a `:score` and whatever the game keeps with it.

```elixir
table = Cauldron.Scores.read(:tag)

if Cauldron.Scores.qualifies?(table, 4200) do
  table = Cauldron.Scores.add(table, %{initials: "ABC", score: 4200})
  Cauldron.Scores.write(:tag, table)
end
```

`qualifies?/3` is true when the table has fewer than `keep` entries (default 8) or the
score beats the last one's; a score of nought never qualifies. `add/3` inserts the entry,
sorts by `:score` highest first and keeps the best `keep`. `read/1` gives `[]` when no
table is kept.

The table is written to `scores.terms`. A table kept as `scores.exs`, an Elixir list of
maps written as text, is read when there is no `scores.terms`; it is read as data only,
so nothing in the file runs. That is how a game can ship a starting table.

## Results and boards

`Cauldron.Ledger` keeps every player's results on disk and makes boards from them. It is
a GenServer over a DETS file:

```elixir
{:ok, ledger} =
  Cauldron.Ledger.start_link(
    path: Cauldron.Paths.data(:tag, "ledger.dets"),
    metrics: [kills: {:sum, :kills}, ratio: {:ratio, :kills, :deaths}, wins: {:count, :won?}]
  )

Cauldron.Ledger.record(ledger, "Park", %{id: "alice", name: "alice", kills: 3, deaths: 1, won?: true})
Cauldron.Ledger.board(ledger, :week, :kills, world: "Park")
```

A result is a map with the player's account as `:id` (their `:name` when there is no id),
the name they played under as `:name`, and whatever fields the metrics read. The world
they played in is the string `record/4` is given. A result whose id is `{:robot, n}` is
not kept, so computer players never reach a board.

Metrics are declared once, as a keyword list:

| Metric | Value |
| --- | --- |
| `{:sum, field}` | The field summed over the rounds |
| `{:max, field}` | The field's largest value |
| `{:count, field}` | How many rounds had the field true |
| `{:ratio, field, by}` | The sum of `field` divided by the sum of `by`, to two places; the sum alone when `by` sums to zero |
| a function | Whatever it returns for the rounds |

`Cauldron.Ledger.board/4` ranks the accounts of a period by one metric: `:day` since
midnight UTC, `:week` the last seven days, `:all` everything. Each entry has every
metric's value, the rounds counted and the name last played under. The board is twenty
accounts by default, `top: n` takes another number and `top: :all` takes every account;
`world:` narrows it to one world's results. Boards are computed from the table and kept
for ten seconds.

| Function | Does |
| --- | --- |
| `Cauldron.Ledger.record/4` | Keep a result from a world |
| `Cauldron.Ledger.board/4` | Rank a period by a metric |
| `Cauldron.Ledger.forget/2` | Drop the results a function is true of |
| `Cauldron.Ledger.count/1` | How many results are kept |
| `Cauldron.Ledger.metrics/1` | The metrics it was started with |
| `Cauldron.Ledger.access/1` | `:read_write`, or `{:held, pid}` |
| `Cauldron.Ledger.holder/1` | The operating system process holding a file |

The file belongs to one operating system process at a time, held through
`Cauldron.Ledger.Lock`. Starting a ledger on a held file fails with
`{:error, {:held, pid}}`; `held: :idle` starts one that keeps nothing instead — its
boards are empty, `record/4` answers `{:error, {:held, pid}}`, and `access/1` says who
holds it. A DETS failure stops the ledger, and a restart reopens the file repaired.

A game that already emits result events needs no recording code: `Cauldron.Ledger.Recorder`
subscribes to a world's events and puts every `{:result, row}` in the ledger under the
world's label. Start it beside the world, which is what a world's `:children` function is
for.

## Keeping a profile

A player's profile is the front end's settings map, not a file the game writes: key
bindings, the preset, the effects and music levels, and the game's own options under
`:options`. It is saved per player, per kind of client, and loaded before the world is
joined. A game's part in it is small and worth getting right:

1. **Name the home.** Write `home/0` in the client module. It names the game in every
   path a front end chooses — the settings, the rendered music — and it is the name to
   give `Cauldron.Save`, `Cauldron.Scores` and `Cauldron.Ledger`. Without it the module's
   first name is used, which works until the module is renamed.
2. **Declare the options.** `options/0` returns the game's own options and their
   defaults, a map. The client keeps a player's choices under `:options`, saves them with
   the rest, puts them on the look given to `scene/2` and sends them with every input, so
   the game sees them as `input.options` and the menu does not need a special case.
3. **Label the player.** `player_label/1` is how a player id is written in a lobby and
   in chat. The ledger records ids as they are; a label is for people to read.
4. **Record once.** Write a score or a result when the round ends — an event drained by
   the world — not every tick. `Cauldron.Scores.add/3` and `Cauldron.Ledger.record/4`
   are cheap, but a file written every tick is not.
5. **Keep saves plain.** Save terms of atoms, numbers, strings, lists, maps and tuples.
   A function, a pid or a reference in a saved state cannot survive a restart.

## Where to go next

| You want to | Read |
| --- | --- |
| Know what a state is made of | [Worlds and players](worlds-and-players.html) |
| Change an option from a menu | [Input and menus](input-and-menus.html) |
| Test a save with no file | [Testing](testing.html) |
| Find a word | [Glossary](glossary.html) |
