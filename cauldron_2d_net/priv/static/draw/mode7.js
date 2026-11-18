/**
 * `Cauldron2D.Projection.Mode7` in the browser: the world as a textured ground plane seen
 * in perspective from above it, movers standing on it as billboards, everything fading
 * towards the atlas's void colour with distance. The same bytes
 * `Cauldron2D.Projection.Mode7.render/2` gives with its ground sampled by the plane NIF.
 *
 *     var picture = CauldronDraw.mode7.render(atlas, {
 *       position: [12.5, 8.5], heading: 0, cell: view.cell, size: [360, 204],
 *       movers: [{art: "hero", x: 14.5, y: 8.5, heading: 0}], at: 0
 *     });
 *
 * `opts` takes `position`, `heading` (radians), `cell(x, y)` (`null` or
 * `{base, overlays, tint}`), `size`, and optionally `eye` (default `1.6`), `pitch`,
 * `aspect`, `fov`, `range`, `sky` (`[[r, g, b], [r, g, b]]`), `movers`, `volumes` in wire
 * form and `at`.
 */
(function (global) {
  var D = global.CauldronDraw = global.CauldronDraw || {};
  var fogLevels = 6, near = 0.2, defaultSky = [[24, 30, 58], [96, 120, 170]];
  var shades = new WeakMap();

  function option(opts, name, fallback) {
    return opts[name] === undefined || opts[name] === null ? fallback : opts[name];
  }

  function skyRows(height, horizon, colours) {
    var top = colours[0], bottom = colours[1], rows = [];
    for (var y = 0; y < height; y++) {
      var mix = Math.min(1.0, y / Math.max(horizon, 1));
      rows.push([D.round(top[0] + (bottom[0] - top[0]) * mix), D.round(top[1] + (bottom[1] - top[1]) * mix),
                 D.round(top[2] + (bottom[2] - top[2]) * mix), 255]);
    }
    return rows;
  }

  function context(atlas, opts) {
    var width = opts.size[0], height = opts.size[1], heading = opts.heading;
    var pitch = Math.max(Math.min(option(opts, "pitch", 0.0), 0.8), -0.8);
    var fov = option(opts, "fov", 70) * Math.PI / 180;
    var projection = width / 2 / Math.tan(fov / 2);
    var horizon = height / 2 + pitch * height / 2;
    return {
      atlas: atlas, cell: opts.cell, at: option(opts, "at", 0), width: width, height: height,
      horizon: horizon, projection: projection, vertical: projection / option(opts, "aspect", 1.0),
      position: opts.position, direction: [Math.cos(heading), Math.sin(heading)], right: [-Math.sin(heading), Math.cos(heading)],
      eye: option(opts, "eye", 1.6), range: option(opts, "range", 24),
      sky: skyRows(height, horizon, option(opts, "sky", defaultSky))
    };
  }

  function cameraSpace(ctx, x, y) {
    var cx = ctx.position[0], cy = ctx.position[1];
    return [(x - cx) * ctx.direction[0] + (y - cy) * ctx.direction[1], (x - cx) * ctx.right[0] + (y - cy) * ctx.right[1]];
  }

  function topSprite(ctx, art) {
    var entry = ctx.atlas.art(art);
    return entry.faces.top ? ctx.atlas.slice(entry.faces.top) : ctx.atlas.frame(art, ctx.at);
  }

  function planeTexture(ctx, textures, art) {
    if (textures[art] !== undefined) return textures[art];
    var slot = ctx.atlas.tile * ctx.atlas.tile * 4, data = topSprite(ctx, art).data, texture = new Uint8ClampedArray(slot);
    texture.set(data.length >= slot ? data.subarray(0, slot) : data);
    textures[art] = texture;
    return texture;
  }

  function channel(value, fog, mix) {
    return Math.max(0, Math.min(255, D.round(value + (fog - value) * mix)));
  }

  function ground(ctx, canvas) {
    var width = ctx.width, height = ctx.height, tile = ctx.atlas.tile, out = canvas.data, empty = ctx.atlas.void;
    var fx = ctx.position[0], fy = ctx.position[1], dx = ctx.direction[0], dy = ctx.direction[1], rx = ctx.right[0], ry = ctx.right[1];
    var reach = Math.ceil(ctx.range) + 2, left = Math.floor(fx) - reach, top = Math.floor(fy) - reach, span = 2 * reach;
    var textures = {};
    for (var y = 0; y < height; y++) {
      var rowAt = y * width * 4, x, i;
      if (y <= ctx.horizon) {
        var sky = ctx.sky[y];
        for (x = 0; x < width; x++) { i = rowAt + x * 4; out[i] = sky[0]; out[i + 1] = sky[1]; out[i + 2] = sky[2]; out[i + 3] = sky[3]; }
        continue;
      }
      var depth = ctx.eye * ctx.vertical / (y - ctx.horizon);
      var fog = Math.min(fogLevels, Math.trunc((depth < 0 ? 0 : depth) / ctx.range * fogLevels));
      var mix = fog / fogLevels, far = depth > ctx.range, step = depth / ctx.projection;
      var wx = fx + dx * depth - rx * width / 2.0 * step, wy = fy + dy * depth - ry * width / 2.0 * step;
      for (x = 0; x < width; x++, wx += rx * step, wy += ry * step) {
        i = rowAt + x * 4;
        var floorX = Math.floor(wx), floorY = Math.floor(wy), column = floorX - left, row = floorY - top;
        var cell = far || column < 0 || row < 0 || column > span || row > span ? null : ctx.cell(floorX, floorY);
        if (!cell) { out[i] = empty[0]; out[i + 1] = empty[1]; out[i + 2] = empty[2]; out[i + 3] = 255; continue; }
        var texture = planeTexture(ctx, textures, cell.base);
        var tx = Math.max(0, Math.min(tile - 1, Math.trunc((wx - floorX) * tile)));
        var ty = Math.max(0, Math.min(tile - 1, Math.trunc((wy - floorY) * tile)));
        var t = (ty * tile + tx) * 4;
        if (texture[t + 3] < 128) { out[i] = texture[t]; out[i + 1] = texture[t + 1]; out[i + 2] = texture[t + 2]; out[i + 3] = texture[t + 3]; continue; }
        out[i] = channel(texture[t], empty[0], mix);
        out[i + 1] = channel(texture[t + 1], empty[1], mix);
        out[i + 2] = channel(texture[t + 2], empty[2], mix);
        out[i + 3] = 255;
      }
    }
    return canvas;
  }

  function shaded(ctx, sprite, flip, level) {
    var held = shades.get(sprite);
    if (!held) { held = {}; shades.set(sprite, held); }
    var key = (flip ? "f" : "n") + level + ctx.atlas.void.join(",");
    if (held[key]) return held[key];
    var src = sprite.data, w = sprite.width, h = sprite.height, data = new Uint8ClampedArray(src.length), fog = ctx.atlas.void, mix = level / fogLevels;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var s = (y * w + x) * 4, d = (y * w + (flip ? w - 1 - x : x)) * 4;
        if (src[s + 3] < 128) { data[d] = src[s]; data[d + 1] = src[s + 1]; data[d + 2] = src[s + 2]; data[d + 3] = src[s + 3]; continue; }
        data[d] = channel(src[s] * 1.0, fog[0], mix);
        data[d + 1] = channel(src[s + 1] * 1.0, fog[1], mix);
        data[d + 2] = channel(src[s + 2] * 1.0, fog[2], mix);
        data[d + 3] = 255;
      }
    }
    held[key] = { width: w, height: h, data: data };
    return held[key];
  }

  function pose(heading, ctx) {
    if (heading === null || heading === undefined) return ["front", false];
    var hx = Math.cos(heading), hy = Math.sin(heading), dx = ctx.direction[0], dy = ctx.direction[1];
    var dot = hx * dx + hy * dy, cross = hx * dy - hy * dx;
    if (dot < -0.5) return ["front", false];
    if (dot > 0.5) return ["back", false];
    return ["side", cross > 0];
  }

  function billboard(mover, ctx) {
    var space = cameraSpace(ctx, mover.x, mover.y), depth = space[0], lateral = space[1];
    if (!(depth > 0.2 && depth < ctx.range)) return null;
    var posed = pose(mover.heading, ctx), sprite = ctx.atlas.pose(mover.art, posed[0], ctx.at);
    var stand = ctx.atlas.art(mover.art).stand;
    if (stand === null || stand === undefined) stand = sprite.height / ctx.atlas.tile;
    var image = shaded(ctx, sprite, posed[1], Math.min(fogLevels, Math.trunc(Math.max(depth, 0) / ctx.range * fogLevels)));
    var vertical = ctx.vertical / depth, tall = vertical * stand, wide = tall * sprite.width / sprite.height;
    var groundAt = ctx.horizon + ctx.eye * vertical;
    return { depth: depth, left: ctx.width / 2 + lateral * ctx.projection / depth - wide / 2, top: groundAt - tall, wide: wide, tall: tall, image: image };
  }

  function paintBillboard(canvas, board) {
    var left = D.round(board.left), top = D.round(board.top);
    var wide = Math.max(1, D.round(board.wide)), tall = Math.max(1, D.round(board.tall));
    var x0 = Math.max(0, -left), y0 = Math.max(0, -top), x1 = Math.min(wide, canvas.width - left), y1 = Math.min(tall, canvas.height - top);
    if (!(x1 > x0 && y1 > y0)) return canvas;
    var image = board.image, src = image.data, out = canvas.data, columns = [];
    for (var x = x0; x < x1; x++) columns.push(Math.min(image.width - 1, Math.trunc(x * image.width / wide)));
    for (var y = y0; y < y1; y++) {
      var row = Math.min(image.height - 1, Math.trunc(y * image.height / tall)) * image.width;
      for (var c = 0; c < columns.length; c++) {
        var s = (row + columns[c]) * 4;
        if (src[s + 3] < 128) continue;
        var d = ((top + y) * canvas.width + left + x0 + c) * 4;
        out[d] = src[s]; out[d + 1] = src[s + 1]; out[d + 2] = src[s + 2]; out[d + 3] = 255;
      }
    }
    return canvas;
  }

  function looking(point, ctx) {
    var side = (point[0] - ctx.width / 2) / ctx.projection;
    return [ctx.direction[0] + ctx.right[0] * side, ctx.direction[1] + ctx.right[1] * side, (ctx.horizon - point[1]) / ctx.vertical];
  }

  function screenPoint(point, ctx) {
    var space = cameraSpace(ctx, point[0], point[1]), depth = space[0], lateral = space[1];
    if (!(depth > near)) return null;
    return [ctx.width / 2 + lateral * ctx.projection / depth, ctx.horizon + (ctx.eye - point[2]) * ctx.vertical / depth];
  }

  function volumeBox(volume, ctx) {
    var depth = cameraSpace(ctx, volume.at[0], volume.at[1])[0];
    if (depth - D.volume.reach(volume) < near) return [0, 0, ctx.width - 1, ctx.height - 1];
    return D.volume.box(volume, function (point) { return screenPoint(point, ctx); });
  }

  function volumeItems(opts, ctx) {
    var wire = option(opts, "volumes", []);
    if (!wire.length) return [];
    return D.volume.list(wire).map(function (volume) {
      return {
        depth: cameraSpace(ctx, volume.at[0], volume.at[1])[0],
        paint: function (canvas) {
          var plan = D.volume.eyePlan([ctx.position[0], ctx.position[1], ctx.eye], function (point) { return looking(point, ctx); });
          return D.volume.paint(canvas, volume, volumeBox(volume, ctx), plan);
        }
      };
    });
  }

  /** The picture `Cauldron2D.Projection.Mode7.render/2` draws for `opts`, as the module describes. */
  function render(atlas, opts) {
    var ctx = context(atlas, opts), canvas = ground(ctx, D.raster(ctx.width, ctx.height));
    var items = option(opts, "movers", []).map(function (mover) { return billboard(mover, ctx); })
      .filter(function (board) { return board !== null; })
      .concat(volumeItems(opts, ctx));
    items.sort(function (a, b) { return a.depth > b.depth ? -1 : a.depth < b.depth ? 1 : 0; });
    items.forEach(function (item) { canvas = item.paint ? item.paint(canvas) : paintBillboard(canvas, item); });
    return canvas;
  }

  D.mode7 = { render: render };
})(typeof window !== "undefined" ? window : globalThis);
