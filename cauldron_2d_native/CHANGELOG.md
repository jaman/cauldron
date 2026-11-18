# Changelog

## [Unreleased]

- The package is `cauldron_2d_native` (was `cauldron_2d_mobile`), its modules `Cauldron2D.Native.*`, following `cauldron_native`.
- A `:gpu` scene on a device whose graphics card will not open is drawn on the CPU by `Cauldron3D.Scene.Software` (with `cauldron_3d` in the app) and shown as the app's picture; `Cauldron2D.Native.Gpu.usable?/1` replaces `available?/0`.

### Changed

- Depends on `cauldron_core` 0.4 and `cauldron_2d` 0.4: the engine modules that moved from `cauldron_2d` are named `Cauldron.*`, and test and example games write `use Cauldron2D.Client.Game`.
- Depends on `cauldron_net`: the client opens fronts and joins worlds with `drawer: Cauldron2D.Net.Drawer` and `local: true`.

- First release: `Cauldron2D.Native.Client`, a game on a phone or tablet, with the on-screen controller `Cauldron2D.Native.Pad`.
- A connected game controller plays the game and hides the on-screen one; on-screen buttons carry their letters (`A JUMP`); the title's quit closes the app where the platform allows.
- The on-screen controller is laid out as phone games lay theirs out: a thumbstick that sets down where the left thumb lands and follows it, the buttons fanned around the bottom right corner, a small `II` menu button, sizes in points, drawn faintly until held.
- `:point_size` (points a picture pixel takes, default 0.75) replaces `:picture_height`, so a tablet shows more of the world rather than a larger picture.
- Left- or right-handed controls (`:hand` in the settings, `Cauldron2D.Native.Settings.menu_items/1` for a game's options page); the button fan follows the thumb that rests on its side; the corners keep clear of half the cutout insets only; the menu button sits in the middle of the top edge.
- The button fan is locked in place by default (`:buttons`, `:locked` or `:move`), a tap just off a button presses the nearest one, and where the fan was moved to is kept in the settings (`:fan_offset`).
- A game whose scenes have a `:gpu` (such as courtyard) is drawn by `cauldron_gpu` into the app's graphics surface, Metal on iOS and Vulkan on Android (`Cauldron2D.Native.Gpu`); the renderer closes while the app is off the screen. When the renderer will not open on the device, the app hides its surface and draws the game's pictures instead. `cauldron_gpu` is an optional dependency.
