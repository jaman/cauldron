# Cauldron2D.Native

This package plays a `cauldron_2d` game on a phone or tablet. `cauldron_native` builds the
app; this package is what runs inside it:

* the game's own title and summary screens and its worlds, at a picture size that follows
  the screen's size in points, so a tablet shows more of the world
* an on-screen controller laid out as phone games lay theirs out: a thumbstick that sets
  down where the thumb lands, the buttons fanned in the other bottom corner and labelled
  with the game's actions, faint until held, left- or right-handed, the fan locked in
  place or following the thumb
* game controllers connected to the device, which hide the on-screen controller
* taps on the picture as clicks; the game's menu opened when the app leaves the screen

## Using it

```elixir
{:cauldron_2d_native, "~> 0.1", targets: [:ios, :android]},
{:cauldron_native, "~> 0.1", runtime: Mix.target() in [:ios, :android]}
```

```elixir
# config/config.exs
if config_target() in [:ios, :android] do
  config :cauldron_2d_native, game: MyGame.Client
end
```

```
mix cauldron_native.build ios --team ABCDE12345 --run
mix cauldron_native.build android --run
```

The [Mobile releases guide](https://hexdocs.pm/cauldron_native/building_apps.html)
covers the setup, signing and building in full.

## The game's options

`Cauldron2D.Native.Settings.menu_items/1` gives the rows a game's options page shows for the
controller: which hand it is laid out for, and whether the buttons stay put. Add them on
the phone builds only:

```elixir
items = game_rows ++ Cauldron2D.Native.Settings.menu_items(&String.upcase/1)
```

The phone shows only the game's own screens and its worlds. It has no text screens for a
lobby, settings or the guide, so a game reaches its options through its own menu.

## Options

`config :cauldron_2d_native` takes `Cauldron2D.Native.Client`'s options: `:game`,
`:username`, `:props`, and `:point_size`, the points of the screen one picture pixel takes
(default `0.75`; smaller shows more of the world and costs more drawing).

## Example

`cauldron_examples/games/beast` in the Cauldron repository.
