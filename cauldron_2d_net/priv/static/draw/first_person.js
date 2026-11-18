/**
 * `Cauldron2D.Projection.FirstPerson` in the browser: the world seen from a point inside
 * it along a heading, standing arts as textured walls of their height, floors textured to
 * the horizon, movers and the standing arts of no height as billboards, everything fading
 * towards the atlas's void colour with distance. The same bytes
 * `Cauldron2D.Projection.FirstPerson.render/2` gives.
 *
 *     var picture = CauldronDraw.firstPerson.render(atlas, {
 *       position: [12.5, 8.5], heading: 0, cell: view.cell, size: [360, 204],
 *       movers: [{art: "guard", x: 14.5, y: 8.5, heading: 0}], at: 0
 *     });
 *
 * `opts` takes `position`, `heading` (radians), `cell(x, y)` (`null` or
 * `{base, overlays, tint}`), `size`, and optionally `eye` (default `0.6`), `pitch`,
 * `aspect`, `fov`, `range`, `sky` (`[[r, g, b], [r, g, b]]`), `movers`, `volumes` in wire
 * form and `at`.
 */
(function (global) {
  var D = global.CauldronDraw = global.CauldronDraw || {};
  var defaultEye = 0.6, fogLevels = 6, near = 0.15, maxSteps = 96, defaultSky = [[24, 30, 58], [96, 120, 170]];
  var shades = new WeakMap();

  function option(opts, name, fallback) {
    return opts[name] === undefined || opts[name] === null ? fallback : opts[name];
  }

  function channel(value, fog, mix) {
    return Math.max(0, Math.min(255, D.round(value + (fog - value) * mix)));
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

  function voidPixels(atlas) {
    var fog = atlas.void, out = [];
    for (var level = 0; level <= fogLevels; level++) {
      var mix = level / fogLevels;
      out.push([channel(fog[0] * 1.0, fog[0], mix), channel(fog[1] * 1.0, fog[1], mix), channel(fog[2] * 1.0, fog[2], mix), 255]);
    }
    return out;
  }

  function fogLevel(ctx, distance) {
    return Math.min(fogLevels, Math.trunc(distance / ctx.range * fogLevels));
  }

  function shaded(ctx, sprite, level, factor) {
    var held = shades.get(sprite);
    if (!held) { held = {}; shades.set(sprite, held); }
    var key = level + ":" + factor + ":" + ctx.atlas.void.join(",");
    if (held[key]) return held[key];
    var src = sprite.data, data = new Uint8ClampedArray(src.length), fog = ctx.atlas.void, mix = level / fogLevels;
    for (var i = 0; i < src.length; i += 4) {
      if (src[i + 3] < 128) { data[i] = src[i]; data[i + 1] = src[i + 1]; data[i + 2] = src[i + 2]; data[i + 3] = src[i + 3]; continue; }
      data[i] = channel(src[i] * factor, fog[0], mix);
      data[i + 1] = channel(src[i + 1] * factor, fog[1], mix);
      data[i + 2] = channel(src[i + 2] * factor, fog[2], mix);
      data[i + 3] = 255;
    }
    held[key] = data;
    return data;
  }

  function billboardImage(ctx, sprite, flip, level) {
    var held = shades.get(sprite), key = "board:" + flip + ":" + level + ":" + ctx.atlas.void.join(",");
    if (held && held[key]) return held[key];
    var rgba = shaded(ctx, sprite, level, 1.0), w = sprite.width, h = sprite.height, data = rgba;
    if (flip) {
      data = new Uint8ClampedArray(rgba.length);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          var s = (y * w + x) * 4, d = (y * w + w - 1 - x) * 4;
          data[d] = rgba[s]; data[d + 1] = rgba[s + 1]; data[d + 2] = rgba[s + 2]; data[d + 3] = rgba[s + 3];
        }
      }
    }
    shades.get(sprite)[key] = { width: w, height: h, data: data };
    return shades.get(sprite)[key];
  }

  function face(ctx, art, name) {
    var entry = ctx.atlas.art(art), rect = entry.faces[name] || entry.faces.side;
    return rect ? ctx.atlas.slice(rect) : ctx.atlas.frame(art, ctx.at);
  }

  function ray(direction, perpendicular, tanHalf, cameraX) {
    return [direction[0] + perpendicular[0] * tanHalf * cameraX, direction[1] + perpendicular[1] * tanHalf * cameraX];
  }

  function block(ctx, x, y) {
    var cell = ctx.cell(x, y);
    if (!cell) return null;
    var stack = [];
    [cell.base].concat(cell.overlays).forEach(function (art) {
      var height = ctx.atlas.art(art).height;
      if (height > 0) stack.push([art, height]);
    });
    return stack;
  }

  function faceHit(side, rayX, rayY) {
    if (side === 0) return rayX > 0 ? "west" : "east";
    return rayY > 0 ? "north" : "south";
  }

  function wallSpan(ctx, rayDir, art, from, storeys, side, distance) {
    var rayX = rayDir[0], rayY = rayDir[1], px = ctx.position[0], py = ctx.position[1];
    var scale = ctx.vertical / Math.max(distance, 1.0e-6);
    var hit = side === 0 ? py + distance * rayY : px + distance * rayX;
    var fraction = hit - Math.floor(hit);
    if ((side === 0 && rayX > 0) || (side === 1 && rayY < 0)) fraction = 1 - fraction;
    var tile = ctx.atlas.tile;
    var texture = shaded(ctx, face(ctx, art, faceHit(side, rayX, rayY)), fogLevel(ctx, distance), side === 0 ? 0.72 : 1.0);
    return {
      wall: true, distance: distance, top: ctx.horizon - (from + storeys - ctx.eye) * scale, bottom: ctx.horizon - (from - ctx.eye) * scale,
      texture: texture, u: Math.min(tile - 1, Math.trunc(fraction * tile)), factor: distance / ctx.vertical
    };
  }

  function cast(ctx, rayDir) {
    var rayX = rayDir[0], rayY = rayDir[1], px = ctx.position[0], py = ctx.position[1];
    var mapX = Math.floor(px), mapY = Math.floor(py);
    var deltaX = rayX === 0 ? 1.0e30 : Math.abs(1 / rayX), deltaY = rayY === 0 ? 1.0e30 : Math.abs(1 / rayY);
    var stepX = rayX < 0 ? -1 : 1, sideX = rayX < 0 ? (px - mapX) * deltaX : (mapX + 1 - px) * deltaX;
    var stepY = rayY < 0 ? -1 : 1, sideY = rayY < 0 ? (py - mapY) * deltaY : (mapY + 1 - py) * deltaY;
    var top = ctx.horizon + 1, spans = [];
    for (var steps = 0; steps < maxSteps; steps++) {
      var side, distance;
      if (sideX < sideY) { distance = sideX; sideX = sideX + deltaX; mapX = mapX + stepX; side = 0; }
      else { distance = sideY; sideY = sideY + deltaY; mapY = mapY + stepY; side = 1; }
      if (distance > ctx.range || top <= 0) break;
      var stack = block(ctx, mapX, mapY);
      if (stack === null) break;
      var from = 0;
      for (var k = 0; k < stack.length; k++) {
        var span = wallSpan(ctx, rayDir, stack[k][0], from, stack[k][1], side, distance);
        if (span.top < top) { top = span.top; spans.push(span); }
        from = from + stack[k][1];
      }
    }
    return spans;
  }

  function standingProps(ctx) {
    var reach = Math.ceil(ctx.range), px = Math.floor(ctx.position[0]), py = Math.floor(ctx.position[1]), props = [];
    for (var x = px - reach; x <= px + reach; x++) {
      for (var y = py - reach; y <= py + reach; y++) {
        var cell = ctx.cell(x, y);
        if (!cell) continue;
        cell.overlays.forEach(function (art) {
          if (ctx.atlas.art(art).height === 0) props.push({ art: art, x: x + 0.5, y: y + 0.5, heading: null });
        });
      }
    }
    return props;
  }

  function pose(heading, relX, relY) {
    if (heading === null || heading === undefined) return ["front", false];
    var hx = Math.cos(heading), hy = Math.sin(heading);
    var length = Math.max(Math.sqrt(relX * relX + relY * relY), 1.0e-6);
    var tx = -relX / length, ty = -relY / length;
    var dot = hx * tx + hy * ty, cross = hx * ty - hy * tx;
    if (dot > 0.5) return ["front", false];
    if (dot < -0.5) return ["back", false];
    return ["side", cross < 0];
  }

  function placeBillboard(columns, image, tallTiles, ctx, depth, lateral, width) {
    var scale = ctx.projection / depth * tallTiles * image.width / image.height;
    var vertical = ctx.vertical / depth, tall = vertical * tallTiles;
    var left = width / 2 + lateral * ctx.projection / depth - scale / 2;
    var bottom = ctx.horizon + ctx.eye * vertical, top = bottom - tall;
    var from = Math.max(0, Math.floor(left)), to = Math.min(width - 1, Math.ceil(left + scale) - 1);
    for (var x = from; x <= to; x++) {
      var u = Math.max(0, Math.min(image.width - 1, Math.trunc((x + 0.5 - left) / scale * image.width)));
      columns[x].spans.push({ wall: false, distance: depth, top: top, bottom: bottom, image: image, u: u, tall: tall });
    }
  }

  function billboard(mover, columns, ctx, direction, perpendicular, tanHalf, width) {
    var relX = mover.x - ctx.position[0], relY = mover.y - ctx.position[1];
    var depth = relX * direction[0] + relY * direction[1], lateral = relX * perpendicular[0] + relY * perpendicular[1];
    if (!(depth > 0.15 && Math.abs(lateral) <= depth * tanHalf + 1)) return;
    var posed = pose(mover.heading, relX, relY), sprite = ctx.atlas.pose(mover.art, posed[0], ctx.at);
    var image = billboardImage(ctx, sprite, posed[1], fogLevel(ctx, depth));
    var stand = ctx.atlas.art(mover.art).stand;
    var tall = stand === null || stand === undefined ? image.height / ctx.atlas.tile : stand;
    placeBillboard(columns, image, tall, ctx, depth, lateral, width);
  }

  function spanPixel(span, yc, ctx) {
    if (span.wall) {
      var tile = ctx.atlas.tile, z = ctx.eye + (ctx.horizon - yc) * span.factor, storey = Math.trunc(z);
      var row = tile - 1 - Math.min(tile - 1, Math.trunc((z - storey) * tile));
      return [span.texture, (row * tile + span.u) * 4];
    }
    var image = span.image, v = Math.max(0, Math.min(image.height - 1, Math.trunc((yc - span.top) / span.tall * image.height)));
    return [image.data, (v * image.width + span.u) * 4];
  }

  function fromSpans(spans, yc, ctx) {
    for (var k = 0; k < spans.length; k++) {
      var span = spans[k];
      if (!(yc >= span.top && yc <= span.bottom)) continue;
      var found = spanPixel(span, yc, ctx);
      if (found[0][found[1] + 3] >= 128) return [found[0], found[1], span.distance];
    }
    return null;
  }

  function floorSeen(column, yc, ctx) {
    var px = ctx.position[0], py = ctx.position[1];
    var distance = ctx.eye * ctx.vertical / (yc - ctx.horizon);
    var wx = px + column.ray[0] * distance, wy = py + column.ray[1] * distance;
    var cx = Math.floor(wx), cy = Math.floor(wy);
    var level = fogLevel(ctx, Math.min(distance, ctx.range)), tile = ctx.atlas.tile;
    var cell = ctx.cell(Math.trunc(cx), Math.trunc(cy));
    if (!cell) return [ctx.voids[level], 0, distance];
    var texture = shaded(ctx, face(ctx, cell.base, "top"), level, 1.0);
    var u = Math.trunc((wx - cx) * tile), v = Math.trunc((wy - cy) * tile);
    return [texture, (v * tile + u) * 4, distance];
  }

  function surface(column, y, ctx) {
    var yc = y + 0.5, found = fromSpans(column.spans, yc, ctx);
    if (found) return found;
    if (yc <= ctx.horizon) return [ctx.sky[y], 0, Infinity];
    return floorSeen(column, yc, ctx);
  }

  function looking(point, ctx, width) {
    var side = (point[0] - width / 2) / ctx.projection;
    return [ctx.direction[0] + ctx.perpendicular[0] * side, ctx.direction[1] + ctx.perpendicular[1] * side, (ctx.horizon - point[1]) / ctx.vertical];
  }

  function screenPoint(point, ctx, width) {
    var px = ctx.position[0], py = ctx.position[1];
    var depth = (point[0] - px) * ctx.direction[0] + (point[1] - py) * ctx.direction[1];
    var lateral = (point[0] - px) * ctx.perpendicular[0] + (point[1] - py) * ctx.perpendicular[1];
    if (!(depth > near)) return null;
    return [width / 2 + lateral * ctx.projection / depth, ctx.horizon + (ctx.eye - point[2]) * ctx.vertical / depth];
  }

  function volumeBox(volume, ctx, width, height) {
    var px = ctx.position[0], py = ctx.position[1];
    if ((volume.at[0] - px) * ctx.direction[0] + (volume.at[1] - py) * ctx.direction[1] - D.volume.reach(volume) < near)
      return [0, 0, width - 1, height - 1];
    return D.volume.box(volume, function (point) { return screenPoint(point, ctx, width); });
  }

  function seenThrough(canvas, limits, volumes, ctx) {
    var width = canvas.width, height = canvas.height;
    var plan = D.volume.eyePlan([ctx.position[0], ctx.position[1], ctx.eye], function (point) { return looking(point, ctx, width); }, limits);
    return volumes.reduce(function (acc, volume) {
      return D.volume.paint(acc, volume, volumeBox(volume, ctx, width, height), plan);
    }, canvas);
  }

  function columnsOf(ctx, opts, direction, perpendicular, tanHalf, width) {
    var columns = [];
    for (var x = 0; x < width; x++) {
      var rayDir = ray(direction, perpendicular, tanHalf, 2 * (x + 0.5) / width - 1);
      columns.push({ spans: cast(ctx, rayDir), ray: rayDir });
    }
    standingProps(ctx).concat(option(opts, "movers", [])).forEach(function (mover) {
      billboard(mover, columns, ctx, direction, perpendicular, tanHalf, width);
    });
    columns.forEach(function (column) {
      column.spans.reverse();
      column.spans.sort(function (a, b) { return a.distance < b.distance ? -1 : a.distance > b.distance ? 1 : 0; });
    });
    return columns;
  }

  /** The picture `Cauldron2D.Projection.FirstPerson.render/2` draws for `opts`, as the module describes. */
  function render(atlas, opts) {
    var width = opts.size[0], height = opts.size[1], heading = opts.heading;
    var pitch = Math.max(Math.min(option(opts, "pitch", 0.0), 1.0), -1.0);
    var horizon = height / 2 + pitch * height / 2;
    var fov = option(opts, "fov", 70) * Math.PI / 180, tanHalf = Math.tan(fov / 2), projection = width / 2 / tanHalf;
    var direction = [Math.cos(heading), Math.sin(heading)], perpendicular = [-Math.sin(heading), Math.cos(heading)];
    var ctx = {
      atlas: atlas, cell: opts.cell, at: option(opts, "at", 0), eye: option(opts, "eye", defaultEye), horizon: horizon,
      projection: projection, vertical: projection / option(opts, "aspect", 1.0), position: opts.position,
      range: option(opts, "range", 24), sky: skyRows(height, horizon, option(opts, "sky", defaultSky)), voids: voidPixels(atlas),
      direction: direction, perpendicular: perpendicular
    };
    var columns = columnsOf(ctx, opts, direction, perpendicular, tanHalf, width);
    var volumes = option(opts, "volumes", []), canvas = D.raster(width, height), out = canvas.data;
    var limits = volumes.length ? new Float32Array(width * height) : null;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var seen = surface(columns[x], y, ctx), from = seen[0], at = seen[1], i = (y * width + x) * 4;
        out[i] = from[at]; out[i + 1] = from[at + 1]; out[i + 2] = from[at + 2]; out[i + 3] = from[at + 3];
        if (limits) limits[y * width + x] = seen[2] === Infinity ? 1.0e18 : seen[2];
      }
    }
    return limits ? seenThrough(canvas, limits, D.volume.list(volumes), ctx) : canvas;
  }

  D.firstPerson = { render: render };
})(typeof window !== "undefined" ? window : globalThis);
