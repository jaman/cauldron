/**
 * `Cauldron2D.Projection.Oblique` in the browser, painting on the canvas
 * `CauldronDraw.canvas` (from `iso.js`) provides.
 *
 *     var picture = CauldronDraw.oblique.compose(atlas, opts);
 *
 * `opts` is what `CauldronDraw.projectionOptions` builds for an oblique view: `focus`,
 * `cell(x, y)`, `size`, `squash`, `facing`, `facings`, optionally `rise`, `movers` of
 * `{art, x, y, heading}`, `labels` and `volumes` in wire form, and `at`.
 */
(function (global) {
  var D = global.CauldronDraw = global.CauldronDraw || {};
  var C = D.canvas;
  var FACE_SHADE = 0.78;

  function given(value, fallback) { return value === undefined || value === null ? fallback : value; }

  function geometry(atlas, opts) {
    var tile = atlas.tile;
    var squash = Math.max(Math.min(given(opts.squash, 0.5), 1.0), 0.25), rise = Math.max(Math.min(given(opts.rise, 0.75), 2.0), 0.25);
    var width = opts.size[0], height = opts.size[1];
    return {
      tile: tile, rowH: Math.max(2, D.round(tile * squash)), lift: Math.max(1, D.round(tile * rise)),
      turn: given(opts.facings, 1) === 4 ? D.mod(Math.trunc(given(opts.facing, 0)), 4) : 0,
      focus: opts.focus, size: [width, height], centre: [width / 2, height / 2]
    };
  }

  function spun(dx, dy, turn) {
    if (turn === 0) return [dx, dy];
    if (turn === 1) return [dy, -dx];
    if (turn === 2) return [-dx, -dy];
    return [-dy, dx];
  }

  function place(x, y, g) {
    var r = spun(x - g.focus[0], y - g.focus[1], g.turn);
    return [g.centre[0] + r[0] * g.tile, g.centre[1] + r[1] * g.rowH];
  }

  function depth(x, y, g) { return spun(x - g.focus[0], y - g.focus[1], g.turn)[1]; }

  function groundAt(px, py, g) {
    var d = spun((px - g.centre[0]) / g.tile, (py - g.centre[1]) / g.rowH, D.mod(-g.turn, 4));
    return [g.focus[0] + d[0], g.focus[1] + d[1]];
  }

  function rows(g, cell) {
    var across = Math.ceil(g.size[0] / g.tile / 2) + 2;
    var down = Math.ceil(g.size[1] / g.rowH / 2) + Math.ceil(4 * g.lift / g.rowH) + 2;
    var reach = Math.max(across, down), fx = Math.floor(g.focus[0]), fy = Math.floor(g.focus[1]), cells = [];
    for (var y = fy - reach; y <= fy + reach; y++) {
      for (var x = fx - reach; x <= fx + reach; x++) {
        var r = spun(x - g.focus[0], y - g.focus[1], g.turn);
        if (!(Math.abs(r[0]) <= across && Math.abs(r[1]) <= down)) continue;
        var tile = cell(x, y);
        if (tile) cells.push({ x: x, y: y, tile: tile });
      }
    }
    return cells;
  }

  function stampOf(atlas, key, build) { return C.memo(atlas, "oblique|" + key, function () { return C.stamp(build()); }); }

  function squashed(atlas, top, g, factor) {
    var tile = g.tile, rowH = g.rowH, image = D.raster(tile, rowH);
    for (var y = 0; y < rowH; y++) {
      for (var x = 0; x < tile; x++) {
        var pixel = C.shade(C.texel(top, tile, x / tile, y / rowH), factor, atlas.void, 0), i = (y * tile + x) * 4;
        image.data[i] = pixel[0]; image.data[i + 1] = pixel[1]; image.data[i + 2] = pixel[2]; image.data[i + 3] = pixel[3];
      }
    }
    return image;
  }

  function wall(atlas, side, g, storeys) {
    var tile = g.tile, height = storeys * g.lift, image = D.raster(tile, height);
    for (var y = 0; y < height; y++) {
      var v = D.rem(y, g.lift) / g.lift;
      for (var x = 0; x < tile; x++) {
        var pixel = C.shade(C.texel(side, tile, x / tile, v), FACE_SHADE, atlas.void, 0), i = (y * tile + x) * 4;
        image.data[i] = pixel[0]; image.data[i + 1] = pixel[1]; image.data[i + 2] = pixel[2]; image.data[i + 3] = pixel[3];
      }
    }
    return image;
  }

  function ground(canvas, atlas, base, tint, s, g, at) {
    var top = C.faceAt(atlas, base, "top", at, tint);
    var stamp = stampOf(atlas, "ground|" + C.id(top) + "|" + g.rowH, function () { return squashed(atlas, top, g, 1.0); });
    return C.paint(canvas, stamp, D.round(s[0]), D.round(s[1]));
  }

  function block(canvas, atlas, art, tint, s, g, at, storeys) {
    var height = atlas.art(art).height, side = C.faceAt(atlas, art, "south", at, tint), top = C.faceAt(atlas, art, "top", at, tint);
    var face = stampOf(atlas, "face|" + C.id(side) + "|" + g.lift + "|" + height, function () { return wall(atlas, side, g, height); });
    var capped = stampOf(atlas, "cap|" + C.id(top) + "|" + g.rowH, function () { return squashed(atlas, top, g, 1.0); });
    var faceTop = D.round(s[1] + g.rowH - storeys * g.lift - height * g.lift);
    C.paint(canvas, face, D.round(s[0]), faceTop);
    C.paint(canvas, capped, D.round(s[0]), faceTop - g.rowH);
    return storeys + height;
  }

  function upright(canvas, atlas, sprite, flip, s, storeys, g) {
    var stamp = stampOf(atlas, "upright|" + C.id(sprite) + "|" + flip, function () { return flip ? C.flip(sprite) : sprite; });
    var left = D.round(s[0] + g.tile / 2 - stamp.width / 2), bottom = D.round(s[1] + g.rowH - storeys * g.lift);
    return C.paint(canvas, stamp, left, bottom - stamp.height);
  }

  function column(canvas, atlas, c, g, at) {
    var s = place(c.x, c.y, g), tile = c.tile, arts = [tile.base].concat(tile.overlays);
    var standing = arts.filter(function (art) { return atlas.art(art).height > 0; });
    var flat = tile.overlays.filter(function (art) { return atlas.art(art).height === 0; });
    ground(canvas, atlas, tile.base, tile.tint, s, g, at);
    var storeys = 0;
    standing.forEach(function (art) { storeys = block(canvas, atlas, art, tile.tint, s, g, at, storeys); });
    flat.forEach(function (art) { upright(canvas, atlas, atlas.frame(art, at), false, s, storeys, g); });
    return canvas;
  }

  function pose(heading, turn) {
    if (heading === null || heading === undefined) return ["front", false];
    var h = spun(Math.cos(heading), Math.sin(heading), turn);
    if (h[1] > 0.5) return ["front", false];
    if (h[1] < -0.5) return ["back", false];
    return ["side", h[0] < 0];
  }

  function mover(canvas, atlas, m, g, at) {
    var posed = pose(m.heading, g.turn), sprite = atlas.pose(m.art, posed[0], at), s = place(m.x, m.y, g);
    return upright(canvas, atlas, sprite, posed[1], [s[0] - g.tile / 2, s[1] - g.rowH / 2], 0, g);
  }

  function paintVolume(canvas, volume, g) {
    var direction = D.volume.eyeline(spun(g.tile, 0, g.turn), spun(0, g.rowH, g.turn), g.lift);
    var plan = D.volume.groundPlan(function (pixel) { return groundAt(pixel[0], pixel[1], g); }, direction);
    var solid = function (point) { var s = place(point[0], point[1], g); return [s[0], s[1] - point[2] * g.lift]; };
    return D.volume.paint(canvas, volume, D.volume.box(volume, solid), plan);
  }

  function items(atlas, opts, g, at) {
    var cells = rows(g, opts.cell).map(function (c) {
      return { row: depth(c.x, c.y, g), paint: function (canvas) { return column(canvas, atlas, c, g, at); } };
    });
    var movers = (opts.movers || []).map(function (m) {
      return { row: depth(m.x, m.y, g), paint: function (canvas) { return mover(canvas, atlas, m, g, at); } };
    });
    var volumes = D.volume.list(opts.volumes || []).map(function (volume) {
      return { row: depth(volume.at[0], volume.at[1], g), paint: function (canvas) { return paintVolume(canvas, volume, g); } };
    });
    return cells.concat(movers, volumes);
  }

  D.oblique = {
    /** `Cauldron2D.Projection.Oblique.compose/2`: the oblique picture for `opts`. */
    compose: function (atlas, opts) {
      var g = geometry(atlas, opts), at = opts.at || 0, canvas = C.fill(g.size[0], g.size[1], atlas.void);
      items(atlas, opts, g, at).sort(function (a, b) { return a.row - b.row; }).forEach(function (item) { canvas = item.paint(canvas); });
      (opts.labels || []).forEach(function (label) { C.label(canvas, atlas, label, function (p) { return place(p[0], p[1], g); }); });
      return canvas;
    },

    /** `Cauldron2D.Projection.Oblique.project/3`: where world point `[x, y]` lands in the picture. */
    project: function (atlas, point, opts) { return place(point[0], point[1], geometry(atlas, opts)); },

    /** `Cauldron2D.Projection.Oblique.unproject/3`: the ground point under picture pixel `[px, py]`. */
    unproject: function (atlas, pixel, opts) { return groundAt(pixel[0], pixel[1], geometry(atlas, opts)); }
  };
})(typeof window !== "undefined" ? window : globalThis);
