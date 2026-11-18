/**
 * `Cauldron2D.Surface` in the browser: a grid of cells composed into one picture, with
 * overlays taller or wider than a tile standing on their cells, movers at pixel
 * positions, labels in `Linocut.Font` and volumes seen from above, the same bytes
 * `Cauldron2D.Surface.compose/4` gives.
 *
 *     var picture = CauldronDraw.surface.compose(atlas, rows, movers, {scale: 1, at: 0});
 *
 * A cell is `null` or `{base, overlays, tint}` by art name. A tinted cell with overlays
 * the tile's size is drawn from `atlas.tintedCell`, the server's blended and tinted
 * pictures; any other tinted cell, and a tinted mover, from `atlas.tinted(art, tint)`.
 * Until those pictures arrive the cell is blended from what the atlas holds and not kept.
 */
(function (global) {
  var D = global.CauldronDraw = global.CauldronDraw || {};
  var box = ["###", "#.#", "#.#", "#.#", "###"];

  function cacheOf(atlas) {
    return atlas.surfaceCache || (atlas.surfaceCache = {});
  }

  function tintedView(atlas, art, tint) {
    if (tint === null || tint === undefined) return { view: atlas, ready: true };
    var view = atlas.tinted(art, tint);
    return view ? { view: view, ready: true } : { view: atlas, ready: false };
  }

  function sample(picture, scale) {
    if (scale === 1) return picture;
    var w = D.div(picture.width, scale), h = D.div(picture.height, scale);
    var out = new Uint8ClampedArray(w * h * 4), src = picture.data;
    for (var py = 0; py < h; py++) {
      for (var px = 0; px < w; px++) {
        var s = (py * scale * picture.width + px * scale) * 4, d = (py * w + px) * 4;
        out[d] = src[s]; out[d + 1] = src[s + 1]; out[d + 2] = src[s + 2]; out[d + 3] = src[s + 3];
      }
    }
    return { width: w, height: h, data: out };
  }

  function mirrored(picture) {
    var w = picture.width, out = new Uint8ClampedArray(picture.data.length), src = picture.data;
    for (var y = 0; y < picture.height; y++) {
      for (var x = 0; x < w; x++) {
        var s = (y * w + x) * 4, d = (y * w + (w - 1 - x)) * 4;
        out[d] = src[s]; out[d + 1] = src[s + 1]; out[d + 2] = src[s + 2]; out[d + 3] = src[s + 3];
      }
    }
    return { width: w, height: picture.height, data: out };
  }

  function kept(atlas, key, ready, make) {
    var cache = cacheOf(atlas);
    if (cache[key]) return cache[key];
    var made = make();
    if (ready) cache[key] = made;
    return made;
  }

  function frameKey(atlas, art, at) {
    return art + "#" + atlas.frameIndex(art, at);
  }

  function blendCell(atlas, cell, at) {
    var blended = cell.tint !== null && cell.tint !== undefined && cell.overlays.length ? atlas.tintedCell(cell.base, cell.overlays, cell.tint, at) : null;
    if (blended) return { picture: blended, ready: true };
    var base = tintedView(atlas, cell.base, cell.tint), picture = base.view.frame(cell.base, at), ready = base.ready;
    if (picture.width !== atlas.tile || picture.height !== atlas.tile)
      throw new Error(cell.base + " is " + picture.width + "x" + picture.height + " but a tile's base must be " + atlas.tile + "x" + atlas.tile);
    cell.overlays.forEach(function (art) {
      var overlay = tintedView(atlas, art, cell.tint);
      ready = ready && overlay.ready;
      picture = D.over(picture, overlay.view.frame(art, at));
    });
    return { picture: picture, ready: ready };
  }

  function voidTile(atlas, voidMode) {
    var fill = voidMode === "transparent" ? [0, 0, 0, 0] : [atlas.void[0], atlas.void[1], atlas.void[2], 255];
    return D.raster(atlas.tile, atlas.tile, fill);
  }

  /** `Cauldron2D.Surface.tile_binary/5`: one cell's picture at `1 / scale` of the tile, at `at` milliseconds. */
  D.surfaceTile = function (atlas, cell, scale, at, voidMode) {
    if (cell === null) return kept(atlas, "void:" + voidMode + ":" + scale, true, function () { return sample(voidTile(atlas, voidMode), scale); });
    var key = "cell:" + frameKey(atlas, cell.base, at) + "|" + cell.overlays.map(function (art) { return frameKey(atlas, art, at); }).join(",") +
      "|" + cell.tint + ":" + scale;
    var cache = cacheOf(atlas);
    if (cache[key]) return cache[key];
    var blended = blendCell(atlas, cell, at), picture = sample(blended.picture, scale);
    if (blended.ready) cache[key] = picture;
    return picture;
  };

  function posed(view, art, pose, at) {
    return pose === null || pose === undefined ? view.frame(art, at) : view.pose(art, pose, at);
  }

  /** `Cauldron2D.Surface.sprite_rgba/5` with a pose: the art at `1 / scale`, through `tint`, mirrored when `flip`. */
  D.surfaceSprite = function (atlas, art, tint, pose, flip, scale, at) {
    var chosen = tintedView(atlas, art, tint), frames = atlas.art(art);
    var index = pose === null || pose === undefined ? atlas.frameIndex(art, at) : pose + "#" + D.mod(D.floorDiv(at * frames.fps, 1000), (frames.poses[pose] || frames.frames).length);
    var key = "sprite:" + art + "#" + index + "|" + tint + "|" + !!flip + ":" + scale;
    return kept(atlas, key, chosen.ready, function () {
      var picture = posed(chosen.view, art, pose, at);
      return sample(flip ? mirrored(picture) : picture, scale);
    });
  };

  function fitToGrid(atlas, rows) {
    var tile = atlas.tile, standing = [];
    var fitted = rows.map(function (row, y) {
      return row.map(function (cell, x) {
        if (cell === null) return null;
        var fitting = [];
        cell.overlays.forEach(function (art) {
          var size = atlas.art(art).size;
          if (size[0] === tile && size[1] === tile) fitting.push(art);
          else standing.push({ art: art, x: x * tile + (tile - size[0]) / 2, y: (y + 1) * tile - size[1], tint: cell.tint, pose: null, flip: false });
        });
        return { base: cell.base, overlays: fitting, tint: cell.tint };
      });
    });
    return { fitted: fitted, standing: standing };
  }

  function grid(atlas, rows, tile, scale, at, voidMode, width, height) {
    var canvas = D.raster(width, height), out = canvas.data;
    rows.forEach(function (row, ry) {
      row.forEach(function (cell, cx) {
        var picture = D.surfaceTile(atlas, cell, scale, at, voidMode);
        for (var py = 0; py < tile; py++)
          out.set(picture.data.subarray(py * tile * 4, (py + 1) * tile * 4), ((ry * tile + py) * width + cx * tile) * 4);
      });
    });
    return canvas;
  }

  function moverOperation(atlas, mover, scale, at) {
    var tint = mover.tint === undefined ? null : mover.tint, pose = mover.pose === undefined ? null : mover.pose;
    var picture = D.surfaceSprite(atlas, mover.art, tint, pose, !!mover.flip, scale, at);
    return { raster: picture, at: [D.round(mover.x / scale), D.round(mover.y / scale)] };
  }

  function colour(spec) {
    return [spec[0], spec[1], spec[2], spec.length > 3 ? spec[3] : 255];
  }

  function graphemes(text) {
    if (typeof Intl !== "undefined" && Intl.Segmenter)
      return Array.from(new Intl.Segmenter().segment(text), function (part) { return part.segment; });
    return Array.from(text);
  }

  function glyph(font, char) {
    return font.glyphs[char] || font.glyphs[char.toUpperCase()] || box;
  }

  /** `Linocut.Font.render/3`: `text` in `rgba` (`[r, g, b]` or `[r, g, b, a]`) as a picture, `scale` times the font's size. */
  D.labelText = function (font, text, rgba, scale) {
    var chars = graphemes(text), width = Math.max(1, Math.max(0, chars.length * font.advance - 1));
    var picture = D.raster(width, font.height), lit = colour(rgba), data = picture.data;
    chars.forEach(function (char, index) {
      glyph(font, char).forEach(function (row, y) {
        Array.from(row).forEach(function (pixel, x) {
          var px = index * font.advance + x;
          if (pixel !== "#" || px >= width || y >= font.height) return;
          var i = (y * width + px) * 4;
          data[i] = lit[0]; data[i + 1] = lit[1]; data[i + 2] = lit[2]; data[i + 3] = lit[3];
        });
      });
    });
    return D.magnify(picture, scale || 1);
  };

  function labelPicture(atlas, label) {
    var text = D.labelText(atlas.labelFont, label.text, label.colour, label.scale || 1);
    if (label.background === null || label.background === undefined) return text;
    return D.over(D.raster(text.width, text.height, colour(label.background)), text);
  }

  function labelOperation(atlas, label, scale) {
    return { raster: labelPicture(atlas, label), at: [D.round(label.x / scale), D.round(label.y / scale)] };
  }

  function paintVolumes(picture, volumes, tile) {
    var plan = D.volume.groundPlan(function (p) { return [p[0] / tile, p[1] / tile]; }, [0.0, 0.0, 1.0]);
    return volumes.reduce(function (canvas, volume) {
      var area = D.volume.box(volume, function (p) { return [p[0] * tile, p[1] * tile]; });
      return D.volume.paint(canvas, volume, area, plan);
    }, picture);
  }

  /**
   * `Cauldron2D.Surface.compose/4`: `rows` of cells into a picture `tile / scale` pixels a
   * cell, with `movers` (`{art, x, y, tint, pose, flip}`, top-left corner in full-size
   * pixels) drawn over in order, then `opts.labels` (`{text, x, y, colour, scale,
   * background}`), then `opts.volumes` (wire form, `at` in tiles from the grid's corner).
   * `opts` also takes `scale` (default 1), `at` (default 0) and `void`, `"opaque"` (the
   * default) or `"transparent"`.
   */
  D.surface = {
    compose: function (atlas, rows, movers, opts) {
      opts = opts || {};
      var scale = opts.scale || 1, at = opts.at || 0, tile = D.div(atlas.tile, scale);
      if (!rows.length) return D.raster(tile, tile);
      var width = rows[0].length * tile, height = rows.length * tile;
      var split = fitToGrid(atlas, rows);
      var picture = grid(atlas, split.fitted, tile, scale, at, opts.void || "opaque", width, height);
      var sprites = split.standing.concat(movers || []), labels = opts.labels || [];
      var volumes = opts.volumes && opts.volumes.length ? D.volume.list(opts.volumes) : [];
      if (!sprites.length && !labels.length && !volumes.length) return picture;
      var operations = sprites.map(function (m) { return moverOperation(atlas, m, scale, at); })
        .concat(labels.map(function (l) { return labelOperation(atlas, l, scale); }));
      picture = D.render(width, height, operations, picture);
      return volumes.length ? paintVolumes(picture, volumes, tile) : picture;
    }
  };
})(typeof window !== "undefined" ? window : globalThis);
