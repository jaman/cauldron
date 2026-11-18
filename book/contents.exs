# The book's contents and order.
#
# Each chapter is `{title, path}` with the path relative to the repository root.
# Part one is for people using Cauldron; part two is for people working on it.
# A chapter added here is assembled by `elixir book/build.exs`; a guide that is not
# listed here still ships with its package, but is not part of the book.

[
  {"Part one — Using Cauldron",
   [
     {"Introduction", "cauldron_core/guides/introduction.md"},
     {"Installation", "cauldron_core/guides/installation.md"},
     {"Worlds and players", "cauldron_core/guides/worlds-and-players.md"},
     {"Input and menus", "cauldron_core/guides/input-and-menus.md"},
     {"Sound and music", "cauldron_core/guides/sound-and-music.md"},
     {"Saving and scores", "cauldron_core/guides/saving-and-scores.md"},
     {"Testing a game", "cauldron_core/guides/testing.md"},
     {"Your first 2D game", "cauldron_2d/guides/tutorial.md"},
     {"Atlases and art", "cauldron_2d/guides/atlas-and-art.md"},
     {"Projections", "cauldron_2d/guides/projections.md"},
     {"Maps and grids", "cauldron_2d/guides/maps-and-grids.md"},
     {"Physics", "cauldron_2d/guides/physics.md"},
     {"From tiles to an open world", "book/from-tiles-to-open-world.md"},
     {"A terminal", "cauldron_2d_drafter/guides/terminal.md"},
     {"Serving over SSH and telnet", "cauldron_2d_drafter/guides/serving.md"},
     {"A browser", "cauldron_2d_net/guides/browser.md"},
     {"A desktop window", "cauldron_2d_wx/guides/window.md"},
     {"Software 3D", "cauldron_3d/guides/software-3d.md"},
     {"3D scenes", "cauldron_3d_scene/guides/scenes.md"},
     {"3D file formats", "cauldron_3d_formats/guides/files.md"},
     {"The graphics card", "cauldron_gpu/guides/gpu.md"},
     {"3D in a browser", "cauldron_3d_net/guides/browser-3d.md"},
     {"3D in Livebook", "cauldron_3d_kino/guides/livebook.md"},
     {"On a phone or tablet", "cauldron_native/guides/overview.md"},
     {"Building a mobile app", "cauldron_native/guides/building_apps.md"},
     {"Publishing a mobile app", "cauldron_native/guides/publishing.md"},
     {"Worlds across the network", "cauldron_net/guides/networking.md"},
     {"Editing sound effects", "cauldron_sfx/guides/editor.md"},
     {"Troubleshooting", "cauldron_core/guides/troubleshooting.md"},
     {"Glossary", "cauldron_core/guides/glossary.md"}
   ]},
  {"Part two — Working on Cauldron",
   [
     {"Architecture", "book/architecture.md"},
     {"Extending the engine", "book/extending.md"},
     {"Contributing", "book/contributing.md"}
   ]}
]
