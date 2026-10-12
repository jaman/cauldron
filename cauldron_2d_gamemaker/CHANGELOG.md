# Changelog

## Unreleased

### Added

- `Surfaces.take_ops/1`: every change made to the surfaces (create, free, clear, copy,
  draw) since they were last taken, as operations. `Surfaces.replay/2` applies them to a
  `Surfaces.Mirror`, a copy of a world's surfaces held apart from the world, and
  `Surfaces.snapshot/1` is the operation that sets a mirror to the surfaces as they are.
  A client on another machine keeps its surfaces this way instead of being sent their
  pixels.

### Changed

- The `Surfaces` functions that read or change surfaces take a `Surfaces.Mirror` as well
  as a `World`. A world's `surfaces` holds `ops`, the operations not yet taken.

## [0.2.0]

### Added

- `Data.read/1` and `Data.parse/1` for GameMaker data files from GameMaker: Studio 1 and
  GameMaker Studio 2 up to 2.3: the header, options, sprites with masks, texture pages
  and their regions, backgrounds and tilesets, objects with events and physics, rooms
  with views, instances, backdrops, tiles and layers, sounds and stored audio, fonts,
  paths and scripts. `Data.index/3` reads a table of names made when the file is read.
- `Pictures` cuts regions, sprite frames, backgrounds and tiles from the decoded pages;
  `Pictures.table/2` cuts every glyph of a font as `{:glyph, font, character}`.
- `Wave.read/1`: stored WAVE sounds, the extensible format included, as 16-bit PCM.
- `Event.handler_name/3` names the compiled function of an object's event.
- `mix gamemaker.info`.
- A runtime for a game's code written in Elixir: `World`, `Step`, `Rooms`, `Collide`,
  `Draw`, `Instance` and the `Code` behaviour, with `Pictures.table/2` and
  `Pictures.sprite_part/3` for drawing its frames through `Cauldron2D.DrawList`.
- `World.new/3` takes `:seed` for the world's random numbers, `:pictures` for drawing
  onto surfaces, and `:object_depths`, the depths by object name at which
  `World.create/4` makes instances (`object_get_depth`, for a GameMaker Studio 2 game
  converted from GameMaker: Studio 1).
- `World` keeps the ids of instances that were outside the room last step in its
  `outside` set, and its surfaces as `%{rasters: %{id => raster}, next: id}`;
  `Surfaces.rasters/1` gives the rasters by id. `World.instances_of/2` reads an index of
  each object's instances and descendants, kept as instances are made and removed.
- Draw order as the runtime has it: instances of equal depth draw newest first, the
  earliest made in front; at equal depth, instances a GameMaker Studio 2 room places on
  its own instance layer (`Instance.room_layer`) draw in front of instances code made.
  Instances made by code are numbered after the highest id any room places.
- Sprite masks are `Cauldron2D.Mask`s; `Sprite.mask/2` picks a frame's.
- `TileLayers`: a room's tile layer drawn as one picture, `{:tile_layer, room, layer,
  blend}`, which `Draw.run/1` gives; `raster/3` draws it and `Surfaces.lookup/2` gives it.
- `Text.items/5` lays a string out in a game's fonts as GameMaker's `draw_text` and
  `draw_text_ext` do (`#` line breaks, alignment, colour, wrapping, line separation),
  with `:angle`, the whole text turned about its position, and `:mode`, the blend mode
  of its glyphs; `Text.width/4` and `Text.height/4` measure it, and `Draw.text/5` draws
  it from draw code.
- `Shapes`: GameMaker's ellipse (`draw_ellipse`) as a picture,
  `{:ellipse, {width, height}, :filled | :outline}`, which `Surfaces.lookup/2` gives.
- `Surfaces`: surfaces made, drawn onto, cleared, freed and drawn as pictures
  (`{:surface, id}`). Drawing onto one blends as GameMaker does, its blend factors
  applied to the alpha channel too. `Surfaces.draw/4` takes `:write`, the colour
  channels drawing changes (`draw_set_colour_write_enable`); `Surfaces.part_item/5`
  draws part of a surface (`draw_surface_part_ext`); `Surfaces.copy/4` copies one
  surface's pixels exactly into another at a place (`surface_copy`).
- `World.put_layer/3` and `World.layers/1`: code changes a room's layers — shown or
  hidden, offset, speed, depth, a background layer's sprite, colour, `:xscale` and
  `:yscale`, and an asset layer's `:tile_blend` (`layer_tile_blend`) — until the room
  is left. Room layers scroll by their speed every step (`World`'s `scroll`).
- `World.add_tile/5`: tiles added by code (`tile_add`), drawn as
  `{:part, {:sprite, sprite, 0}, rectangle}` until the room is left; `Surfaces.lookup/2`
  cuts `{:part, key, rectangle}` pictures.
- `World.hide_tiles/3`: a room's tiles at a depth hidden or shown again
  (`tile_layer_hide`, `tile_layer_show`) until the room is left.
- `Path.position/2`: a path's place at a fraction of its length (`path_get_x`,
  `path_get_y`), curved paths broken into points as GameMaker breaks them.
- `Collide.bounce/4`: `move_bounce_solid` and `move_bounce_all`, simple and advanced.
- `Random`: GameMaker's random numbers — the runtime's WELL512a generator and its
  seeding, `random`, `random_range`, `irandom`, `irandom_range` and `choose` as the
  runtime computes them.
- `Particles`: particles set loose by code, moving, animating and fading by themselves,
  drawn with the room and cleared on entering a room; `Particles.take/2` takes particles
  out of the world, picked by a function of each, and a particle may carry any
  `:picture` in place of a `:sprite`.
- `PartSystems`: GameMaker's particle systems, types and emitters as its runtime runs
  them — ranges, increments, wiggles, gravity, three alphas, HSV colours, death and
  step particles, region shapes and spreads, automatic or manual update and draw.
- `Colour`: `hsv/3` (`make_color_hsv`) and `merge/3` (`merge_color`).
- `Draw.item/2`: draw code adds any picture of the game's own.
