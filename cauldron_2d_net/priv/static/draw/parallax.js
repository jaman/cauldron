/**
 * `Cauldron2D.Parallax` in the browser: the layers of one side of the world composed
 * into one picture, the same bytes `Cauldron2D.Parallax.compose/3` gives.
 *
 *     var behind = CauldronDraw.parallax.compose(atlas, view.layers, {
 *       focus: view.focus, size: [30, 17], pixels: [480, 272], at: at, scale: 1, front: false
 *     });
 *
 * Each layer is as `CauldronDraw.reader` gives it: its `focus` the point it is seen from,
 * `cell(x, y)` its cells, `movers` `[art, x, y, heading, tint]` in its own tiles,
 * `volumes` in wire form, `picture` a panorama `{art, size, wrap, at, cover}` or `null`,
 * `bands` `[[first, last, factor], ...]` or `null`, and `void`.
 */
(function (global) {
  var D = global.CauldronDraw = global.CauldronDraw || {};

  function wraps(wrap, axis) { return wrap === "both" || wrap === axis; }

  /** `Cauldron2D.Parallax.Panorama.places/5`: where copies `period` tiles apart sit to cover `extent` from `origin`. */
  function places(wrapping, origin, extent, period, at) {
    if (!wrapping) return [at];
    var out = [], first = at + (D.floorDiv(origin - at - period, period) + 1) * period;
    for (var place = first; place < origin + extent; place += period) out.push(place);
    return out;
  }

  function enlarged(sprite, times) {
    if (times === 1) return sprite;
    return D.magnify(sprite, times);
  }

  function tops(picture, oy, height, artHeight, tile) {
    if (picture.cover) return [height - artHeight];
    return places(wraps(picture.wrap, "y"), oy, Math.ceil(height / tile), picture.size[1], picture.at[1])
      .map(function (place) { return (place - oy) * tile; });
  }

  function segments(columns, artWidth, width) {
    var out = [];
    columns.forEach(function (left) {
      var from = Math.max(left, 0), to = Math.min(left + artWidth, width);
      if (to > from) out.push([from, from - left, to - from]);
    });
    return out.sort(function (a, b) { return a[0] - b[0] || a[1] - b[1] || a[2] - b[2]; });
  }

  function fill(out, at, count, blank) {
    for (var i = 0; i < count; i++) {
      out[at + i * 4] = blank[0]; out[at + i * 4 + 1] = blank[1]; out[at + i * 4 + 2] = blank[2]; out[at + i * 4 + 3] = blank[3];
    }
    return at + count * 4;
  }

  function line(out, at, art, sourceRow, spans, width, blank) {
    var cursor = 0, written = at;
    spans.forEach(function (span) {
      written = fill(out, written, Math.max(0, span[0] - cursor), blank);
      var from = (sourceRow * art.width + span[1]) * 4;
      out.set(art.data.subarray(from, from + span[2] * 4), written);
      written += span[2] * 4;
      cursor = Math.max(cursor, span[0] + span[2]);
    });
    written = fill(out, written, Math.max(0, width - cursor), blank);
    if (written - at !== width * 4) throw new Error("panorama copies overlap");
  }

  /**
   * `Cauldron2D.Parallax.Panorama.render/8`: `picture` laid across a pane `width` by
   * `height` pixels whose top-left tile is `origin`, `tile` pixels a tile at `scale`.
   */
  function panorama(atlas, picture, origin, width, height, tile, scale, at, voidMode) {
    var sprite = D.surfaceSprite(atlas, picture.art, null, null, false, scale, at);
    var times = picture.cover ? Math.max(1, Math.ceil(height / sprite.height)) : 1;
    var art = enlarged(sprite, times);
    var blank = voidMode === "opaque" ? [atlas.void[0], atlas.void[1], atlas.void[2], 255] : [0, 0, 0, 0];
    var columns = places(wraps(picture.wrap, "x") || picture.cover, origin[0], Math.ceil(width / tile), picture.size[0] * times, picture.at[0])
      .map(function (place) { return (place - origin[0]) * tile; });
    var rows = tops(picture, origin[1], height, art.height, tile), spans = segments(columns, art.width, width);
    var out = D.raster(width, height);
    for (var y = 0; y < height; y++) {
      var top = null;
      for (var r = 0; r < rows.length; r++) if (y >= rows[r] && y < rows[r] + art.height) { top = rows[r]; break; }
      if (top === null) fill(out.data, y * width * 4, width, blank);
      else line(out.data, y * width * 4, art, y - top, spans, width, blank);
    }
    return out;
  }

  function factor(bands, row) {
    for (var i = 0; i < bands.length; i++) {
      var first = bands[i][0], last = bands[i][1];
      if (first <= last ? row >= first && row <= last : row <= first && row >= last) return bands[i][2];
    }
    return 0.0;
  }

  /** `Cauldron2D.Parallax.Bands.roll/4`: each band's pixel rows rolled sideways by its share of `focus`. */
  function roll(picture, bands, focus, tile) {
    if (!bands || !bands.length) return picture;
    var width = picture.width, height = picture.height, src = picture.data, out = new Uint8ClampedArray(src.length);
    var shifts = [];
    for (var row = 0; row <= D.div(height - 1, tile); row++) shifts.push(D.mod(D.round(-focus[0] * factor(bands, row) * tile), width));
    for (var y = 0; y < height; y++) {
      var cut = shifts[D.div(y, tile)], start = y * width * 4;
      out.set(src.subarray(start + cut * 4, start + width * 4), start);
      out.set(src.subarray(start, start + cut * 4), start + (width - cut) * 4);
    }
    return { width: width, height: height, data: out };
  }

  function placed(layer, origin, tile) {
    return layer.movers.map(function (m) {
      return { art: m[0], x: (m[1] - origin[0]) * tile, y: (m[2] - origin[1]) * tile, tint: m[4], pose: null, flip: false };
    });
  }

  function shifted(volumes, origin) {
    return volumes.map(function (v) {
      var copy = Object.assign({}, v), at = v.at.slice();
      at[0] = at[0] - origin[0]; at[1] = at[1] - origin[1];
      copy.at = at;
      return copy;
    });
  }

  function build(atlas, layer, origin, size, at, scale, tile) {
    if (layer.picture)
      return panorama(atlas, layer.picture, origin, (Math.ceil(size[0]) + 1) * tile, (Math.ceil(size[1]) + 1) * tile, tile, scale, at, layer.void);
    var camera = D.camera(layer.focus, size, layer.cell);
    return D.surface.compose(atlas, camera.cells, placed(layer, origin, atlas.tile), {
      scale: scale, at: at, void: layer.void, volumes: shifted(layer.volumes, camera.origin)
    });
  }

  function layerPicture(atlas, layer, size, at, scale, tile, target) {
    var ex = layer.focus[0] - size[0] / 2, ey = layer.focus[1] - size[1] / 2;
    var origin = [Math.floor(ex), Math.floor(ey)];
    var scroll = [Math.floor((ex - Math.floor(ex)) * tile), Math.floor((ey - Math.floor(ey)) * tile)];
    var whole = build(atlas, layer, origin, size, at, scale, tile);
    return roll(D.crop(whole, scroll[0], scroll[1], target[0], target[1]), layer.bands, layer.focus, tile);
  }

  /**
   * `Cauldron2D.Parallax.compose/3`: the layers whose `front` is `opts.front` drawn back
   * to front into one picture `opts.pixels` in size (default `opts.size` times the
   * tile), or `null` when that side has none. `opts` has `focus`, `size` (`[columns,
   * rows]` of tiles), `pixels`, `at`, `scale` and `front`.
   */
  D.parallax = {
    compose: function (atlas, layers, opts) {
      var front = !!opts.front, chosen = layers.filter(function (layer) { return !!layer.front === front; });
      if (!chosen.length) return null;
      var at = opts.at || 0, scale = opts.scale || 1, tile = Math.max(1, D.div(atlas.tile, scale)), size = opts.size;
      var target = opts.pixels || [D.round(size[0] * tile), D.round(size[1] * tile)];
      var pictures = chosen.map(function (layer) { return layerPicture(atlas, layer, size, at, scale, tile, target); });
      if (pictures.length === 1) return pictures[0];
      return D.render(target[0], target[1], pictures.slice(1).map(function (p) { return { raster: p, at: [0, 0] }; }), pictures[0]);
    },
    places: places,
    roll: roll
  };
})(typeof window !== "undefined" ? window : globalThis);
