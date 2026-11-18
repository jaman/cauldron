# Cauldron3D.Scene

A 3D scene as plain Elixir with no native code, drawn by any renderer that implements
`Cauldron3D.Scene.Target`. It holds:

* the structs a scene is made of: `Cauldron3D.Scene.Mesh`, `Texture`, `Material`, `Instance`,
  `Light`, `Camera`, `Environment`, `Transform`, `Quat`, `Pose`, `Canvas`, `Sprite`,
  `SpriteLayer`, `ColumnLayer` and `Handle`
* `Cauldron3D.Scene.Stream`, the change list and its binary encoding
* `Cauldron3D.Scene.Target`, the protocol every renderer implements
* `Cauldron3D.Scene.Host.Record`, a scene rebuilt from the changes sent to it
* `Cauldron3D.Scene.PNG`
* the converters for game data: `Cauldron3D.Scene.Bsp` (Quake), `Cauldron3D.Scene.Sectors` (Doom),
  `Cauldron3D.Scene.AliasModel`, `Cauldron3D.Scene.StudioModel` (Half-Life) and
  `Cauldron3D.Scene.Billboards`

Renderers implement `Cauldron3D.Scene.Target`: `cauldron_gpu` (the native renderer, which
depends on this package), `cauldron_3d_net` (browsers) and `cauldron_3d_kino` (Livebook).
Depend on this package alone when your code only describes scenes.

## Installation

```elixir
def deps do
  [{:cauldron_3d_scene, "~> 0.4"}]
end
```

The converters read game data through `cauldron_3d_formats`, `cauldron_3d` and
`cauldron_2d`. Those are optional, so add the ones you use to your own dependencies.

## License

[AGPL-3.0-only](LICENSE). You may use, study, change and share it under the AGPL at
no cost.

A game or service whose source you do not publish needs a
[commercial license](COMMERCIAL.md).
