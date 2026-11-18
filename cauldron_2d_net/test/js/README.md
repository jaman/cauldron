# Browser renderer checks

`priv/static/draw/*.js` draws a scene from the data `Cauldron2D.Net.Scene` writes. These
checks hold it to the picture `Cauldron2D.Draw` draws from the same data, byte for byte.

Make fixtures from a game, in that game's directory:

    mix run ../../cauldron_2d_net/test/js/fixtures.exs Beast.Client journey ../../cauldron_2d_net/test/js/fixtures/beast

Each fixture directory holds the atlas (`atlas.json`, `atlas.rgba`) and one directory per
scene (`scene.json`, `expected.rgba`, and the tinted arts and tinted cells the scene uses). Then:

    node test/js/run.mjs

prints, per scene, the pixels that differ from the expected picture.
