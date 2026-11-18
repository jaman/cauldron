# Cauldron examples

Every Cauldron example is here: the games, the 3D showcases, and the browser demos. Each
one is its own Mix project and depends on the Cauldron packages by path, so an edit to a
package shows up in the examples at once.

```
cd cauldron_examples/games/beast
mix deps.get
mix beast
```

## Games

| Example | Run | What it shows |
| --- | --- | --- |
| [`games/cistern`](games/cistern) | `mix cistern`, `mix cistern.serve`, `mix cistern.desktop` | The tutorial's game: catch a storm cloud's rain in three jars. It uses every 2D package, runs in the terminal, a browser and a window, and has tests. The [tutorial](../cauldron_2d/guides/tutorial.md) builds it step by step |
| [`games/cistern_complete`](games/cistern_complete) | `mix cistern_complete` | Cistern finished: pouring, the Squall's moods, hail, lightning, versus, its own title, menus and hud, art made with image models |
| [`games/beast`](games/beast) | `mix beast`, `mix beast.serve`, `mix beast.desktop`, `mix cauldron_native.build ios\|android` | An action platformer across four hand-built lands: combos, rolls, creatures that show their blows, four bosses, music, art made with image models and animated from video. It is also the phone and tablet example: the same game as an iOS and an Android app |
| [`games/megablast`](games/megablast) | `mix megablast` | A vertical shooter: five stages, guardians and multi-part bosses, chains, credits and a shop |
| [`games/town`](games/town) | `mix town` | A town you walk top-down, isometric or in first person: the engine's projections, standing art with doors, villagers, a game controller |
| [`games/parade`](games/parade) | `mix parade` | A courtyard of knights: spells aimed and cast as areas, paths found with `Cauldron2D.Route`, detailed figures cut from a sprite sheet |

## 3D

| Example | Run | What it shows |
| --- | --- | --- |
| [`3d/gpu_showcase`](3d/gpu_showcase) | `mix showcase`, `mix spheres` | `cauldron_gpu` in a window: a lit courtyard with metal and plastic spheres, shadows, ray tracing and upscaling (`EFFECTS=rt,gi,upscale`); a load test of two thousand spheres. `MIX_ENV=prod mix release` builds the showcase as a program of its own |
| [`3d/courtyard`](3d/courtyard) | `mix courtyard`, `mix courtyard --window`, `mix cauldron_native.build ios` | A Cauldron game drawn in 3D by the graphics card, in the terminal, a window or on an iPhone or iPad, with a character walked by keys, mouse, controller or touch under a camera that follows her, and three scenes (`mix courtyard.fetch` downloads the alley, the atrium and the character) |
| [`3d/vale`](3d/vale) | `mix vale.figure`, `mix vale`, `mix vale --window` | An open land on `Cauldron.OpenWorld`: a lake, meadows, woods and a crag to climb, walked, swum and climbed by a small figure with clips made in imachine, toon-lit with outlines, grass and trees drawn as scatters, and painted ranges on panels where the simulation ends |
| [`3d/web_3d`](3d/web_3d) | `mix showcase` | `cauldron_3d_net`: the same courtyard served to a browser and drawn there with three.js |

## Apps

| Example | Run | What it shows |
| --- | --- | --- |
| [`apps/notes`](apps/notes) | `mix cauldron_native.build ios --team TEAM --run`, `mix cauldron_native.build android --run` | An app with the platform's own controls, SwiftUI on iOS and Jetpack Compose on Android, written in Elixir (`CauldronNative.App`): a list of notes, a pushed screen, a form, settings, and a star rating that is a view of its own in Swift and in Kotlin |
| [`apps/catalog`](apps/catalog) | `mix cauldron_native.build ios --team TEAM --run`, `mix cauldron_native.build android --run` | Every native control on one app, as the platforms' component catalogs show theirs: text and icons, buttons, chips and menus, fields, pickers, dates, progress, lists, grids and cards, tabs, toolbars, search, sheets, alerts and action sheets, images, and a meter drawn in Swift and in Kotlin |
| [`apps/food_truck`](apps/food_truck) | `mix cauldron_native.build macos --run`, `mix cauldron_native.build ios --simulator --device "iPad Pro 13-inch (M5)" --run`, `mix cauldron_native.build android --run` | Apple's Food Truck sample (github.com/apple/sample-food-truck) with its own art, drawn by each platform: the animated truck header, New Orders as stacked donuts, the hourly forecast with its nights, the donut lattice and trending tags; orders as a table or by status; the social feed with Social Feed+ (StoreKit, Google Play Billing; run it from Xcode to buy from its StoreKit configuration); the account; sales history by city with a year of history to unlock; the donut gallery and editor with flavour profiles; the Top 5 chart; cities on a turning map with their weather (WeatherKit, or Open-Meteo); the Orders, Daily Donut and Parking Spot widgets; an order's Live Activity counting down its preparation (a Live Update on Android); and the Mac's menu bar item. The truck's data is a GenServer, its menu saved to DETS |
| [`apps/now_in_android`](apps/now_in_android) | `mix cauldron_native.build android --run`, `mix cauldron_native.build ios --simulator --run`, `mix cauldron_native.build macos --run` | Google's Now in Android sample as Google designs it: For You with its topic picker and feed of cards, Saved, Interests, a topic's screen, Search, and settings for the theme, Dynamic colour and dark mode; the user's choices are a GenServer saved to DETS |

## By technique

| Technique | Where to look |
| --- | --- |
| A first game, step by step | `games/cistern` with the tutorial |
| A game's own title, summary and menus (`Cauldron.Front`, `Cauldron.Menu`) | `games/beast`, `games/cistern_complete`, `games/megablast` |
| Platform physics, combos, telegraphed attacks, bosses | `games/beast` |
| Projections: top-down, isometric, first person | `games/town` |
| Path finding and aimed area spells | `games/parade` |
| Music and synthesised effects (`Cauldron.Audio`) | `games/beast`, `games/cistern_complete` |
| Art from image models and video (`mix cauldron.assets`) | `games/beast`, `games/cistern_complete`, `games/megablast` |
| Playing in a browser (`Cauldron2D.Net`) | `mix cistern.serve`, `mix beast.serve` |
| A desktop window (`Cauldron2D.Wx`) | `mix cistern.desktop`, `mix beast.desktop` |
| An iOS or Android app (`cauldron_native`) | `games/beast`, `3d/courtyard` (3D on iOS), `3d/gpu_showcase` (iOS) |
| 3D on the graphics card (`cauldron_gpu`) | `3d/gpu_showcase`, `3d/courtyard` |
| 3D in a terminal | `3d/courtyard` |
| 3D in a browser (`cauldron_3d_net`) | `3d/web_3d` |
| Releasing a desktop program | `3d/gpu_showcase` |

## License

[AGPL-3.0-only](LICENSE). You may use, study, change and share it under the AGPL at
no cost.

A game or service whose source you do not publish needs a
[commercial license](COMMERCIAL.md).
