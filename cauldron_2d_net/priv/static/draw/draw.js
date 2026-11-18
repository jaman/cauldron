/**
 * `Cauldron2D.Draw` in the browser: a view a `CauldronDraw.reader` read, drawn over a
 * pane `[columns, rows]` tiles at zoom 1 into a picture, the same bytes
 * `Cauldron2D.Draw.picture/3` gives.
 *
 *     var picture = CauldronDraw.picturePane(view, [40, 22], at);
 *
 * It calls on the other parts by these names, each given the atlas and plain objects:
 *
 *   - `CauldronDraw.surface.compose(atlas, rows, movers, opts)` — `Cauldron2D.Surface.compose/4`:
 *     `rows` of cells (`null` or `{base, overlays, tint}`), `movers` of
 *     `{art, x, y, tint, pose, flip}` in pixels, `opts` `{scale, at, labels, volumes, void}`,
 *     labels `{text, x, y, colour, scale, background}` in pixels
 *   - `CauldronDraw.parallax.compose(atlas, layers, opts)` — `Cauldron2D.Parallax.compose/3`,
 *     each layer as the reader gives it (its `focus` the point it is seen from),
 *     `opts` `{focus, size, pixels, at, scale, front}`; `null` for no layers that side
 *   - `CauldronDraw.screen.compose(atlas, items, width, height, at)` — `Cauldron2D.Screen.compose/4`,
 *     items as the payload writes them
 *   - `CauldronDraw.iso.compose`, `CauldronDraw.oblique.compose`, `CauldronDraw.mode7.render`,
 *     `CauldronDraw.firstPerson.render` — `(atlas, opts)`, the projections, `opts` as
 *     `projectionOptions` builds them
 */
(function (global) {
  var D = global.CauldronDraw = global.CauldronDraw || {};
  var zoomIn = [4, 2], zoomOut = [2, 4, 8, 16], sampled = ["first_person", "mode7", "picture"];


  /** `Cauldron2D.Draw.zoom_levels/3` for a picture scaled to its pane. */
  D.zoomLevels = function (atlas, projection) {
    if (projection === "picture") return [1];
    if (projection === "iso") return [2, 1, 0.5, 0.25];
    if (projection === "oblique") return [2, 1, 0.5];
    if (projection === "first_person" || projection === "mode7") return [1];
    var tile = atlas.tile, out = zoomOut.filter(function (d) { return tile % d === 0; }).map(function (d) { return 1 / d; });
    return zoomIn.concat([1]).concat(out);
  };

  /** `Cauldron2D.Draw.nearest/2`. */
  D.nearest = function (zoom, levels) {
    var best = levels[0], bestScore = Infinity;
    levels.forEach(function (level) {
      var score = Math.abs(Math.log(level / zoom));
      if (score < bestScore) { best = level; bestScore = score; }
    });
    return best;
  };

  function tileOf(view) { return view.atlas.tile; }

  /** `Cauldron2D.Camera.view/1` with `scroll: true`: origin, scroll, columns, rows and the cells, a row more and a column more. */
  D.camera = function (focus, size, cell) {
    var width = size[0], height = size[1], columns = Math.ceil(width), rows = Math.ceil(height);
    var ex = focus[0] - width / 2, ey = focus[1] - height / 2, ox = Math.floor(ex), oy = Math.floor(ey);
    var cells = [];
    for (var row = 0; row <= rows; row++) {
      var line = [];
      for (var col = 0; col <= columns; col++) line.push(cell(ox + col, oy + row));
      cells.push(line);
    }
    return { origin: [ox, oy], scroll: [ex - ox, ey - oy], columns: columns, rows: rows, cells: cells };
  };

  /** `Cauldron2D.Draw.picture/3` over `pane` at `at` milliseconds. */
  D.picturePane = function (view, pane, at) {
    if (view.projection === "top") return topDown(view, pane, D.nearest(view.zoom, D.zoomLevels(view.atlas, "top")), at);
    var density = D.density(view);
    var fitted = D.fitted(view);
    return onScreen(drawn(fitted, [pane[0] * density, pane[1] * density], 1.0, at), view, at);
  };

  function zoomed(size, zoom) { return [size[0] / zoom, size[1] / zoom]; }

  function topDown(view, pane, zoom, at) {
    var tile = tileOf(view), camera = D.camera(view.focus, zoomed(pane, zoom), view.cell);
    if (zoom >= 1) return onScreen(world(view, camera, [D.round(pane[0] * tile / zoom), D.round(pane[1] * tile / zoom)], 1, at), view, at);
    return onScreen(world(view, camera, [pane[0] * tile, pane[1] * tile], D.round(1 / zoom), at), view, at);
  }

  function world(view, camera, target, scale, at) {
    var tile = tileOf(view), sx = D.round(camera.scroll[0] * tile), sy = D.round(camera.scroll[1] * tile);
    var behind = parallax(view, target, scale, false, at), front = parallax(view, target, scale, true, at);
    var raster = D.surface.compose(view.atlas, camera.cells, movers(view, camera), {
      scale: scale, at: at, labels: labels(view, camera), volumes: volumes(view, camera), void: behind ? "transparent" : "opaque"
    });
    raster = D.crop(raster, D.div(sx, scale), D.div(sy, scale), target[0], target[1]);
    if (behind) raster = D.stack(behind, raster);
    if (front) raster = D.stack(raster, front);
    return raster;
  }

  function parallax(view, target, scale, front, at) {
    if (!view.layers.length) return null;
    var tile = Math.max(1, D.div(tileOf(view), scale));
    return D.parallax.compose(view.atlas, view.layers, {
      focus: view.focus, size: [target[0] / tile, target[1] / tile], pixels: target, at: at, scale: scale, front: front
    });
  }

  /** `Cauldron2D.Draw.pose/1`: `[pose, flip]` for a heading in radians, `[null, false]` for none. */
  D.pose = function (heading) {
    if (heading === null || heading === undefined) return [null, false];
    var across = Math.cos(heading), down = Math.sin(heading);
    if (down > 0.5) return ["front", false];
    if (down < -0.5) return ["back", false];
    return ["side", across < 0];
  };

  function movers(view, camera) {
    var tile = tileOf(view), ox = camera.origin[0], oy = camera.origin[1];
    return view.movers.map(function (m) {
      var size = view.atlas.art(m[0]).size, pose = D.pose(m[3]);
      return { art: m[0], x: (m[1] - ox) * tile + (tile - size[0]) / 2, y: (m[2] - oy) * tile + tile - size[1], tint: m[4], pose: pose[0], flip: pose[1] };
    });
  }

  function labels(view, camera) {
    var tile = tileOf(view), ox = camera.origin[0], oy = camera.origin[1];
    return view.labels.map(function (l) {
      return { text: l[0], x: (l[1] - ox) * tile, y: (l[2] - oy) * tile, colour: l[3], scale: l[4], background: l[5] };
    });
  }

  function volumes(view, camera) {
    var ox = camera.origin[0], oy = camera.origin[1];
    return view.volumes.map(function (v) {
      var copy = Object.assign({}, v), at = v.at.slice();
      at[0] = at[0] - ox; at[1] = at[1] - oy;
      copy.at = at;
      return copy;
    });
  }

  /** The view's screen items with its outlines as box items placed about the focus. */
  D.screenItems = function (view) {
    if (!view.outlines.length) return view.screen;
    var tile = tileOf(view), fx = view.focus[0], fy = view.focus[1];
    return view.screen.concat(view.outlines.map(function (o) {
      return ["box", [(o[0] - fx) * tile, (o[1] - fy) * tile], [(o[2] - o[0]) * tile, (o[3] - o[1]) * tile], o[4], { anchor: "centre", pivot: "top_left" }];
    }));
  };

  function onScreen(raster, view, at) {
    var items = D.screenItems(view);
    if (!items.length) return raster;
    return D.stack(raster, D.screen.compose(view.atlas, items, raster.width, raster.height, at));
  }

  function drawn(view, size, aspect, at) {
    var opts = D.projectionOptions(view, size, aspect, at);
    if (view.projection === "iso") return D.iso.compose(view.atlas, opts);
    if (view.projection === "oblique") return D.oblique.compose(view.atlas, opts);
    if (view.projection === "mode7") return D.mode7.render(view.atlas, opts);
    return D.firstPerson.render(view.atlas, opts);
  }

  function posedMovers(view) {
    return view.movers.map(function (m) { return { art: m[0], x: m[1], y: m[2], heading: m[3] }; });
  }

  /** `Cauldron2D.Draw.facings/2`. */
  D.facings = function (view, projection) {
    var f = view.facings;
    if (f && typeof f === "object") return f[projection] !== undefined ? f[projection] : (projection === "oblique" ? 1 : 4);
    if (projection === "oblique") return 1;
    return f;
  };

  /** `Cauldron2D.Draw.projection_opts/5`. */
  D.projectionOptions = function (view, size, aspect, at) {
    if (view.projection === "iso")
      return { focus: view.focus, cell: view.cell, size: size, facing: view.facing, facings: D.facings(view, "iso"), tilt: view.tilt * aspect,
               shrink: D.isoShrink(D.projectionZoom(view)), movers: posedMovers(view), labels: view.labels, volumes: view.volumes, at: at };
    if (view.projection === "oblique")
      return { focus: view.focus, cell: view.cell, size: size, squash: 0.5 * aspect, facing: view.facing, facings: D.facings(view, "oblique"),
               movers: posedMovers(view), labels: view.labels, volumes: view.volumes, at: at };
    var opts = { position: view.focus, heading: view.heading, pitch: view.pitch, cell: view.cell, size: size, aspect: aspect,
                 movers: posedMovers(view), volumes: view.volumes, at: at };
    if (view.eye !== null && view.eye !== undefined) opts.eye = view.eye;
    return opts;
  };

  /** `Cauldron2D.Draw.iso_shrink/1`. */
  D.isoShrink = function (zoom) { return zoom >= 1 ? 1 : Math.min(4, Math.max(1, D.round(1 / zoom))); };

  /** `Cauldron2D.Draw.projection_zoom/2` for a picture scaled to its pane. */
  D.projectionZoom = function (view) { return D.nearest(view.zoom, D.zoomLevels(view.atlas, view.projection)); };

  function shrinks(projection) { return projection === "iso"; }

  function nativeDensity(view) {
    var asked = view.density;
    if (asked && typeof asked === "object") asked = asked[view.projection];
    if (asked !== null && asked !== undefined) return asked;
    return sampled.indexOf(view.projection) >= 0 ? 4 : tileOf(view) / 2;
  }

  /** `Cauldron2D.Draw.density/2` for a picture scaled to its pane. */
  D.density = function (view) {
    var zoom = D.projectionZoom(view), asked = shrinks(view.projection) ? Math.max(zoom, 1) : zoom;
    return Math.max(1, D.round(nativeDensity(view) / asked));
  };

  /** `Cauldron2D.Draw.fitted/2` for a picture scaled to its pane. */
  D.fitted = function (view) {
    var zoom = D.projectionZoom(view), copy = Object.assign({}, view);
    copy.zoom = shrinks(view.projection) ? Math.min(zoom, 1) : 1;
    return copy;
  };

})(typeof window !== "undefined" ? window : globalThis);
