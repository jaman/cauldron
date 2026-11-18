/**
 * `Cauldron2D.Projection.Iso` in the browser, and the `Cauldron2D.Projection.Canvas`
 * framebuffer the axonometric projections paint on.
 *
 * A canvas is a picture `{width, height, data}`. A stamp is a picture reduced to its
 * opaque pixels, `{width, height, data, runs}`, `runs` a flat list of `y, x, length`
 * triples; painting it copies those runs at full opacity and clips to the canvas.
 *
 *     var picture = CauldronDraw.iso.compose(atlas, opts);
 *
 * `opts` is what `CauldronDraw.projectionOptions` builds for an isometric view: `focus`,
 * `cell(x, y)`, `size`, `facing`, `facings`, `tilt`, `shrink`, `movers` of
 * `{art, x, y, heading}`, `labels` and `volumes` in wire form, and `at`.
 */
(function (global) {
  var D = global.CauldronDraw = global.CauldronDraw || {};
  var C = D.canvas = {};
  var ids = new WeakMap(), nextId = 1;
  var caches = new WeakMap();

  /** A canvas `width` by `height` filled with the opaque colour `[r, g, b]`. */
  C.fill = function (width, height, rgb) { return D.raster(width, height, [rgb[0], rgb[1], rgb[2], 255]); };

  /** A fully transparent canvas `width` by `height`. */
  C.blank = function (width, height) { return D.raster(width, height); };

  /** A number naming `picture` for as long as it lives, for cache keys. */
  C.id = function (picture) {
    var id = ids.get(picture);
    if (!id) { id = nextId++; ids.set(picture, id); }
    return id;
  };

  /** `Cauldron2D.Projection.Canvas.memo/3`: the value under `key` for `atlas`, built by `build` when absent. */
  C.memo = function (atlas, key, build) {
    var cache = caches.get(atlas);
    if (!cache) { cache = {}; caches.set(atlas, cache); }
    if (!(key in cache)) cache[key] = build();
    return cache[key];
  };

  /** `Canvas.stamp/1`: `image` reduced to its pixels of alpha 128 and above, made opaque. */
  C.stamp = function (image) {
    var w = image.width, h = image.height, src = image.data, data = new Uint8ClampedArray(src.length), runs = [];
    for (var y = 0; y < h; y++) {
      var start = -1;
      for (var x = 0; x <= w; x++) {
        var i = (y * w + x) * 4, solid = x < w && src[i + 3] >= 128;
        if (solid) {
          data[i] = src[i]; data[i + 1] = src[i + 1]; data[i + 2] = src[i + 2]; data[i + 3] = 255;
          if (start < 0) start = x;
        } else if (start >= 0) {
          runs.push(y, start, x - start);
          start = -1;
        }
      }
    }
    return { width: w, height: h, data: data, runs: runs };
  };

  /** `Canvas.paint/3`: `stamp` with its top-left corner at `x0, y0`, clipped to `canvas`. */
  C.paint = function (canvas, stamp, x0, y0) {
    var runs = stamp.runs, width = canvas.width, height = canvas.height, out = canvas.data, src = stamp.data;
    for (var k = 0; k < runs.length; k += 3) {
      var y = y0 + runs[k];
      if (y < 0 || y >= height) continue;
      var x = x0 + runs[k + 1], length = runs[k + 2], from = Math.max(0, -x), to = Math.min(length, width - x);
      if (to <= from) continue;
      var s = (runs[k] * stamp.width + runs[k + 1] + from) * 4;
      out.set(src.subarray(s, s + (to - from) * 4), (y * width + x + from) * 4);
    }
    return canvas;
  };

  /** `Canvas.shrink/2`: `image` at `1 / factor` of its size, every `factor`th pixel. */
  C.shrink = function (image, factor) {
    if (factor === 1) return image;
    var w = Math.max(1, D.div(image.width, factor)), h = Math.max(1, D.div(image.height, factor)), out = new Uint8ClampedArray(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var s = (y * factor * image.width + x * factor) * 4, d = (y * w + x) * 4;
        out[d] = image.data[s]; out[d + 1] = image.data[s + 1]; out[d + 2] = image.data[s + 2]; out[d + 3] = image.data[s + 3];
      }
    }
    return { width: w, height: h, data: out };
  };

  /** `Canvas.flip/1`: `image` mirrored left to right. */
  C.flip = function (image) {
    var w = image.width, h = image.height, out = new Uint8ClampedArray(image.data.length);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var s = (y * w + w - 1 - x) * 4, d = (y * w + x) * 4;
        out[d] = image.data[s]; out[d + 1] = image.data[s + 1]; out[d + 2] = image.data[s + 2]; out[d + 3] = image.data[s + 3];
      }
    }
    return { width: w, height: h, data: out };
  };

  /** `Canvas.texel/4`: the pixel `[r, g, b, a]` of a `size` square texture at `u, v`, read with rows `size` pixels wide. */
  C.texel = function (texture, size, u, v) {
    var column = Math.max(0, Math.min(size - 1, Math.trunc(u * size)));
    var row = Math.max(0, Math.min(size - 1, Math.trunc(v * size)));
    var i = (row * size + column) * 4, d = texture.data;
    return [d[i], d[i + 1], d[i + 2], d[i + 3]];
  };

  function channel(value, fog, mix) { return Math.max(0, Math.min(255, D.round(value + (fog - value) * mix))); }

  /** `Canvas.shade/4`: `pixel` multiplied by `factor` and mixed towards `fog` by `mix`; a transparent pixel is left alone. */
  C.shade = function (pixel, factor, fog, mix) {
    if (pixel[3] < 128) return pixel;
    return [channel(pixel[0] * factor, fog[0], mix), channel(pixel[1] * factor, fog[1], mix), channel(pixel[2] * factor, fog[2], mix), 255];
  };

  /**
   * `Canvas.quad/5`: the parallelogram `origin + u * across + v * down` painted from
   * `texel(u, v)`, which answers `[r, g, b, a]` or `null`; pixels of alpha below 128 are
   * left alone.
   */
  C.quad = function (canvas, origin, across, down, texel) {
    var ox = origin[0], oy = origin[1], ax = across[0], ay = across[1], dx = down[0], dy = down[1];
    var determinant = ax * dy - ay * dx;
    if (Math.abs(determinant) < 1.0e-9) return canvas;
    var xs = [ox, ox + ax, ox + dx, ox + ax + dx], ys = [oy, oy + ay, oy + dy, oy + ay + dy];
    var left = Math.max(0, Math.floor(Math.min.apply(null, xs))), right = Math.min(canvas.width - 1, Math.ceil(Math.max.apply(null, xs)));
    var top = Math.max(0, Math.floor(Math.min.apply(null, ys))), bottom = Math.min(canvas.height - 1, Math.ceil(Math.max.apply(null, ys)));
    var out = canvas.data;
    for (var y = top; y <= bottom; y++) {
      for (var x = left; x <= right; x++) {
        var px = x + 0.5 - ox, py = y + 0.5 - oy;
        var u = (px * dy - py * dx) / determinant, v = (ax * py - ay * px) / determinant;
        if (!(u >= 0 && u < 1 && v >= 0 && v < 1)) continue;
        var pixel = texel(u, v);
        if (!pixel || pixel[3] < 128) continue;
        var i = (y * canvas.width + x) * 4;
        out[i] = pixel[0]; out[i + 1] = pixel[1]; out[i + 2] = pixel[2]; out[i + 3] = pixel[3];
      }
    }
    return canvas;
  };

  var box = ["###", "#.#", "#.#", "#.#", "###"];

  /** `Linocut.Font.render/3` with `font` as `atlas.labelFont`: `text` in `[r, g, b]`, `scale` times its size. */
  C.text = function (font, text, colour, scale) {
    var chars = Array.from(text), width = Math.max(1, Math.max(0, chars.length * 4 - 1)), height = 5;
    var image = D.raster(width * scale, height * scale);
    chars.forEach(function (char, index) {
      var glyph = font.glyphs[char] || box;
      glyph.forEach(function (row, y) {
        Array.from(row).forEach(function (pixel, x) {
          if (pixel !== "#") return;
          for (var sy = 0; sy < scale; sy++) {
            for (var sx = 0; sx < scale; sx++) {
              var i = (((y * scale + sy) * width * scale) + (index * 4 + x) * scale + sx) * 4;
              image.data[i] = colour[0]; image.data[i + 1] = colour[1]; image.data[i + 2] = colour[2]; image.data[i + 3] = 255;
            }
          }
        });
      });
    });
    return image;
  };

  /** A wire label `[text, x, y, colour, scale, background]` painted centred on `place([x, y])`. */
  C.label = function (canvas, atlas, label, place) {
    var rendered = C.text(atlas.labelFont, label[0], label[3], label[4] || 1), at = place([label[1], label[2]]);
    return C.paint(canvas, C.stamp(rendered), D.round(at[0] - rendered.width / 2), D.round(at[1] - rendered.height / 2));
  };

  /**
   * The picture of `art`'s `face` as `face_at/4` of the projections picks it: the face,
   * else its `side`, else its frame at `at`; through `tint` when one is given and its
   * tinted pictures have arrived.
   */
  C.faceAt = function (atlas, art, face, at, tint) {
    var source = C.source(atlas, art, tint), entry = source.art(art);
    return entry.faces[face] || entry.faces.side ? source.face(art, face) : source.frame(art, at);
  };

  /** The atlas view `art` is drawn from through `tint`: its tinted pictures, or the atlas itself with no tint or none arrived. */
  C.source = function (atlas, art, tint) {
    if (tint === null || tint === undefined) return atlas;
    return atlas.tinted(art, tint) || atlas;
  };

  var LEFT_SHADE = 0.62, RIGHT_SHADE = 0.82, STAMPED_FACINGS = 32, SEAM = 1.0, SPREAD = 1.0, STOREYS = 4;
  var FACES = [["east", [1, 0], [1, 0], [1, 1]], ["west", [-1, 0], [0, 1], [0, 0]], ["south", [0, 1], [1, 1], [0, 1]], ["north", [0, -1], [0, 0], [1, 0]]];

  function turn(opts) {
    var facings = opts.facings === undefined || opts.facings === null ? 4 : opts.facings;
    if (facings === "free") facings = 360;
    facings = Math.max(facings, 4);
    var facing = snapped(opts.facing === undefined || opts.facing === null ? 0 : opts.facing, facings);
    return [facing, facings, facing * 2 * Math.PI / facings];
  }

  function snapped(facing, facings) {
    if (facings > STAMPED_FACINGS) return facing;
    return D.mod(D.round(facing), facings);
  }

  function edge(dx, dy, angle, halfW, halfH) {
    var c = Math.cos(angle), s = Math.sin(angle);
    var rx = dx * c + dy * s, ry = dy * c - dx * s;
    return [(rx - ry) * halfW, (rx + ry) * halfH];
  }

  function geometry(atlas, opts) {
    var tile = atlas.tile, shrink = opts.shrink || 1;
    var tilt = Math.max(Math.min(opts.tilt === undefined || opts.tilt === null ? 1.0 : opts.tilt, 1.5), 0.5);
    var tileH = Math.max(2, 2 * D.round(tile * tilt / 2));
    var width = opts.size[0], height = opts.size[1], turned = turn(opts), angle = turned[2];
    return {
      tile: tile, shrink: shrink, tilt: tilt, halfW: tile / shrink, halfH: tileH / 2 / shrink, blockH: tile / shrink,
      stampTileH: tileH, facing: turned[0], facings: turned[1], angle: angle, cos: Math.cos(angle), sin: Math.sin(angle),
      stepped: turned[1] === 4, stamps: turned[1] <= STAMPED_FACINGS,
      across: edge(1, 0, angle, tile / shrink, tileH / 2 / shrink), down: edge(0, 1, angle, tile / shrink, tileH / 2 / shrink),
      focus: opts.focus, size: [width, height], centre: [width / 2, height / 2]
    };
  }

  function quarter(dx, dy, turns) {
    if (turns === 0) return [dx, dy];
    if (turns === 1) return [dy, -dx];
    if (turns === 2) return [-dx, -dy];
    return [-dy, dx];
  }

  function rotate(dx, dy, g) {
    if (g.stepped) return quarter(dx, dy, g.facing);
    return [dx * g.cos + dy * g.sin, dy * g.cos - dx * g.sin];
  }

  function unrotate(dx, dy, g) {
    if (g.stepped) return quarter(dx, dy, D.rem(4 - g.facing, 4));
    return [dx * g.cos - dy * g.sin, dy * g.cos + dx * g.sin];
  }

  function place(x, y, g) {
    var r = rotate(x - g.focus[0], y - g.focus[1], g);
    return [g.centre[0] + (r[0] - r[1]) * g.halfW, g.centre[1] + (r[0] + r[1]) * g.halfH];
  }

  function unprojected(px, py, g) {
    var u = (px - g.centre[0]) / g.halfW, v = (py - g.centre[1]) / g.halfH;
    var d = unrotate((u + v) / 2, (v - u) / 2, g);
    return [g.focus[0] + d[0], g.focus[1] + d[1]];
  }

  function raised(point, lift) { return [point[0], point[1] - lift]; }

  function depthOf(x, y, g) {
    var r = rotate(x - g.focus[0], y - g.focus[1], g);
    return r[0] + r[1];
  }

  function screenNormal(normal, g) {
    var r = rotate(normal[0], normal[1], g);
    return [(r[0] - r[1]) * g.halfW, (r[0] + r[1]) * g.halfH];
  }

  function faceShade(normal, g) {
    var nx = screenNormal(normal, g)[0], reach = g.halfW * 1.5, mix = (nx / reach + 1) / 2;
    return LEFT_SHADE + (RIGHT_SHADE - LEFT_SHADE) * Math.min(1.0, Math.max(0.0, mix));
  }

  function worldBounds(g) {
    var width = g.size[0], height = g.size[1], rise = STOREYS * g.blockH, xs = [], ys = [];
    [0, width].forEach(function (px) {
      [-rise, height + rise].forEach(function (py) {
        var point = unprojected(px, py, g);
        xs.push(point[0]); ys.push(point[1]);
      });
    });
    return [Math.floor(Math.min.apply(null, xs)) - 1, Math.floor(Math.min.apply(null, ys)) - 1,
            Math.ceil(Math.max.apply(null, xs)) + 1, Math.ceil(Math.max.apply(null, ys)) + 1];
  }

  function onScreen(x, y, g) {
    var p = place(x, y, g), ax = g.across[0], ay = g.across[1], bx = g.down[0], by = g.down[1];
    var xs = [0, ax, bx, ax + bx], ys = [0, ay, by, ay + by];
    return p[0] + Math.max.apply(null, xs) > -SEAM && p[0] + Math.min.apply(null, xs) < g.size[0] + SEAM &&
      p[1] + Math.max.apply(null, ys) > -SEAM && p[1] + Math.min.apply(null, ys) - STOREYS * g.blockH < g.size[1] + SEAM;
  }

  function visibleCells(cell, g) {
    var bounds = worldBounds(g), cells = [];
    for (var x = bounds[0]; x <= bounds[2]; x++) {
      for (var y = bounds[1]; y <= bounds[3]; y++) {
        if (!onScreen(x, y, g)) continue;
        var tile = cell(x, y);
        if (tile) cells.push({ x: x, y: y, tile: tile });
      }
    }
    return cells;
  }

  function grown(a, b) {
    var ax = a[0], ay = a[1], bx = b[0], by = b[1];
    var span = Math.abs(ax * by - ay * bx), lengthA = Math.sqrt(ax * ax + ay * ay), lengthB = Math.sqrt(bx * bx + by * by);
    var outA = Math.min(SEAM * lengthB / Math.max(span, 1.0e-9), SPREAD), outB = Math.min(SEAM * lengthA / Math.max(span, 1.0e-9), SPREAD);
    return [[ax * (1 + 2 * outA), ay * (1 + 2 * outA)], [bx * (1 + 2 * outB), by * (1 + 2 * outB)],
            [-ax * outA - bx * outB, -ay * outA - by * outB]];
  }

  function drawn(quads) {
    var xs = [], ys = [];
    quads.forEach(function (q) {
      var o = q[0], a = q[1], b = q[2];
      xs.push(o[0], o[0] + a[0], o[0] + b[0], o[0] + a[0] + b[0]);
      ys.push(o[1], o[1] + a[1], o[1] + b[1], o[1] + a[1] + b[1]);
    });
    var left = Math.floor(Math.min.apply(null, xs)), above = Math.floor(Math.min.apply(null, ys));
    var canvas = C.blank(Math.ceil(Math.max.apply(null, xs)) - left + 1, Math.ceil(Math.max.apply(null, ys)) - above + 1);
    quads.forEach(function (q) { C.quad(canvas, [q[0][0] - left, q[0][1] - above], q[1], q[2], q[3]); });
    return { offset: [left, above], image: canvas };
  }

  function texture(tex, tile) { return function (u, v) { return C.texel(tex, tile, u, v); }; }

  function shaded(tex, tile, shade) { return function (u, v) { return C.shade(C.texel(tex, tile, u, v), shade, [0, 0, 0], 0); }; }

  function tileImage(top, g) {
    var grow = grown(g.across, g.down);
    return drawn([[grow[2], grow[0], grow[1], texture(top, g.tile)]]);
  }

  function cornerAt(d, g) { return [d[0] * g.across[0] + d[1] * g.down[0], d[0] * g.across[1] + d[1] * g.down[1]]; }

  function sideQuad(tex, shade, from, to, g) {
    var lift = g.blockH, s = cornerAt(from, g), e = cornerAt(to, g);
    if (Math.abs(e[0] - s[0]) < 1) return null;
    var grow = grown([e[0] - s[0], e[1] - s[1]], [0, lift]);
    return [[s[0] + grow[2][0], s[1] - lift + grow[2][1]], grow[0], grow[1], shaded(tex, g.tile, shade)];
  }

  function blockImage(faces, cap, g) {
    var grow = grown(g.across, g.down), quads = [];
    faces.forEach(function (f) {
      var quad = sideQuad(f.sprite, faceShade(f.normal, g), f.from, f.to, g);
      if (quad) quads.push(quad);
    });
    quads.push([raised(grow[2], g.blockH), grow[0], grow[1], texture(cap, g.tile)]);
    return drawn(quads);
  }

  function stampOf(atlas, key, g, build) {
    return C.memo(atlas, "iso|" + key + "|" + g.stampTileH + "|" + g.shrink, function () { return C.stamp(C.shrink(build(), g.shrink)); });
  }

  function turned(atlas, key, g, build) {
    return C.memo(atlas, "iso|" + key + "|" + g.stampTileH + "|" + g.shrink + "|" + g.facing + "|" + g.facings, function () {
      var built = build();
      return { stamp: C.stamp(built.image), offset: built.offset };
    });
  }

  function upright(sprite, flip) { return flip ? C.flip(sprite) : sprite; }

  function uprightStamp(atlas, sprite, flip, g) {
    return stampOf(atlas, "upright|" + C.id(sprite) + "|" + flip, g, function () { return upright(sprite, flip); });
  }

  function standing(stamp, foot, g) {
    return [stamp, D.round(foot[0] - stamp.width / 2), D.round(foot[1] + g.halfH / 4 - stamp.height)];
  }

  function paintFloor(canvas, atlas, c, g, at) {
    var top = C.faceAt(atlas, c.tile.base, "top", at, c.tile.tint);
    var built = turned(atlas, "tile|" + C.id(top), g, function () { return tileImage(top, g); });
    var p = place(c.x, c.y, g);
    return C.paint(canvas, built.stamp, D.round(p[0] + built.offset[0]), D.round(p[1] + built.offset[1]));
  }

  function facingSides(atlas, art, tint, at, g) {
    var sides = [];
    FACES.forEach(function (f) {
      if (screenNormal(f[1], g)[1] > 0) sides.push({ sprite: C.faceAt(atlas, art, f[0], at, tint), normal: f[1], from: f[2], to: f[3] });
    });
    return sides;
  }

  function stack(atlas, art, c, g, at, built) {
    var height = atlas.art(art).height, tint = c.tile.tint;
    if (height === 0) {
      var sprite = C.source(atlas, art, tint).frame(art, at);
      var stamp = uprightStamp(atlas, sprite, false, g);
      built.stamps.push(standing(stamp, place(c.x + 0.5, c.y + 0.5, g), g));
      return;
    }
    var cap = C.faceAt(atlas, art, "top", at, tint), faces = facingSides(atlas, art, tint, at, g);
    var key = "block|" + C.id(cap) + "|" + faces.map(function (f) { return C.id(f.sprite); }).join(",");
    var cube = turned(atlas, key, g, function () { return blockImage(faces, cap, g); });
    var p = place(c.x, c.y, g);
    for (var storey = built.storeys; storey <= built.storeys + height - 1; storey++)
      built.stamps.push([cube.stamp, D.round(p[0] + cube.offset[0]), D.round(p[1] + cube.offset[1] - storey * g.blockH)]);
    built.storeys += height;
  }

  function standingItems(atlas, cells, g, at) {
    var items = [];
    cells.forEach(function (c) {
      var arts = [c.tile.base].concat(c.tile.overlays).filter(function (art) { return atlas.art(art).height > 0 || art !== c.tile.base; });
      if (!arts.length) return;
      var built = { stamps: [], storeys: 0 };
      arts.forEach(function (art) { stack(atlas, art, c, g, at, built); });
      items.push({ depth: depthOf(c.x + 0.5, c.y + 0.5, g), stamps: built.stamps });
    });
    return items;
  }

  function pose(heading, g) {
    if (heading === null || heading === undefined) return ["front", false];
    var h = rotate(Math.cos(heading), Math.sin(heading), g);
    return [h[0] + h[1] >= 0 ? "front" : "back", h[0] - h[1] < 0];
  }

  function moverStamp(atlas, mover, g, at) {
    var posed = pose(mover.heading, g);
    return standing(uprightStamp(atlas, atlas.pose(mover.art, posed[0], at), posed[1], g), place(mover.x, mover.y, g), g);
  }

  function moverItems(atlas, movers, g, at) {
    return movers.map(function (m) { return { depth: depthOf(m.x, m.y, g), stamps: [moverStamp(atlas, m, g, at)] }; });
  }

  function walkingMovers(atlas, movers, g, at) {
    return movers.map(function (m) {
      return { depth: depthOf(m.x, m.y, g), paint: function (canvas) { var s = moverStamp(atlas, m, g, at); return C.paint(canvas, s[0], s[1], s[2]); } };
    });
  }

  function volumeItems(opts, g) {
    return D.volume.list(opts.volumes || []).map(function (volume) {
      return { depth: depthOf(volume.at[0], volume.at[1], g), paint: function (canvas) { return paintVolume(canvas, volume, g); } };
    });
  }

  function paintVolume(canvas, volume, g) {
    var direction = D.volume.eyeline(g.across, g.down, g.blockH);
    var plan = D.volume.groundPlan(function (pixel) { return unprojected(pixel[0], pixel[1], g); }, direction);
    var solid = function (point) { return raised(place(point[0], point[1], g), point[2] * g.blockH); };
    return D.volume.paint(canvas, volume, D.volume.box(volume, solid), plan);
  }

  function painted(canvas, item) {
    if (item.stamps) { item.stamps.forEach(function (s) { C.paint(canvas, s[0], s[1], s[2]); }); return canvas; }
    return item.paint(canvas);
  }

  function sorted(items) { return items.slice().sort(function (a, b) { return a.depth - b.depth; }); }

  function labelled(canvas, atlas, opts, g) {
    (opts.labels || []).forEach(function (label) { C.label(canvas, atlas, label, function (p) { return place(p[0], p[1], g); }); });
    return canvas;
  }

  function stamped(atlas, g, opts) {
    var at = opts.at || 0, cells = visibleCells(opts.cell, g);
    var canvas = C.fill(g.size[0], g.size[1], atlas.void);
    cells.forEach(function (c) { paintFloor(canvas, atlas, c, g, at); });
    var items = standingItems(atlas, cells, g, at).concat(moverItems(atlas, opts.movers || [], g, at), volumeItems(opts, g));
    sorted(items).forEach(function (item) { canvas = painted(canvas, item); });
    return labelled(canvas, atlas, opts, g);
  }

  function ground(g, atlas, cell, at) {
    var width = g.size[0], height = g.size[1], canvas = D.raster(width, height), out = canvas.data, textures = {};
    var voidPixel = [atlas.void[0], atlas.void[1], atlas.void[2], 255];
    for (var py = 0; py < height; py++) {
      var v = (py + 0.5 - g.centre[1]) / g.halfH;
      for (var px = 0; px < width; px++) {
        var u = (px + 0.5 - g.centre[0]) / g.halfW, d = unrotate((u + v) / 2, (v - u) / 2, g);
        var wx = g.focus[0] + d[0], wy = g.focus[1] + d[1], tile = cell(Math.floor(wx), Math.floor(wy)), pixel;
        if (!tile) pixel = voidPixel;
        else {
          var key = tile.base + "\u0000" + tile.tint;
          if (!textures[key]) textures[key] = C.faceAt(atlas, tile.base, "top", at, tile.tint);
          pixel = C.texel(textures[key], atlas.tile, wx - Math.floor(wx), wy - Math.floor(wy));
        }
        var i = (py * width + px) * 4;
        out[i] = pixel[0]; out[i + 1] = pixel[1]; out[i + 2] = pixel[2]; out[i + 3] = pixel[3];
      }
    }
    return canvas;
  }

  function side(canvas, block, face, g) {
    var normal = face[1];
    if (screenNormal(normal, g)[1] <= 0) return canvas;
    var tex = C.faceAt(block.atlas, block.art, face[0], block.at, block.tint), shade = faceShade(normal, g);
    var s = raised(place(block.x + face[2][0], block.y + face[2][1], g), block.top);
    var e = raised(place(block.x + face[3][0], block.y + face[3][1], g), block.top);
    return C.quad(canvas, s, [e[0] - s[0], e[1] - s[1]], [0, block.top - block.base], function (u, v) {
      var value = v * block.height;
      return C.shade(C.texel(tex, block.tile, u, value - Math.floor(value)), shade, [0, 0, 0], 0);
    });
  }

  function cap(canvas, atlas, art, tint, x, y, lift, g, at) {
    var tex = C.faceAt(atlas, art, "top", at, tint);
    var o = raised(place(x, y, g), lift), a = raised(place(x + 1, y, g), lift), d = raised(place(x, y + 1, g), lift);
    return C.quad(canvas, o, [a[0] - o[0], a[1] - o[1]], [d[0] - o[0], d[1] - o[1]], texture(tex, atlas.tile));
  }

  function block(canvas, atlas, art, tint, x, y, storeys, g, at) {
    var height = atlas.art(art).height, base = storeys * g.blockH, top = base + height * g.blockH;
    var spec = { atlas: atlas, art: art, tint: tint, x: x, y: y, base: base, top: top, height: height, tile: atlas.tile, at: at };
    FACES.forEach(function (face) { canvas = side(canvas, spec, face, g); });
    return cap(canvas, atlas, art, tint, x, y, top, g, at);
  }

  function standingBlocks(atlas, cells, g, at) {
    var items = [];
    cells.forEach(function (c) {
      var arts = [c.tile.base].concat(c.tile.overlays).filter(function (art) { return atlas.art(art).height > 0; });
      if (!arts.length) return;
      items.push({
        depth: depthOf(c.x + 0.5, c.y + 0.5, g),
        paint: function (canvas) {
          var storeys = 0;
          arts.forEach(function (art) { canvas = block(canvas, atlas, art, c.tile.tint, c.x, c.y, storeys, g, at); storeys += atlas.art(art).height; });
          return canvas;
        }
      });
    });
    return items;
  }

  function sampled(atlas, g, opts) {
    var at = opts.at || 0, cells = visibleCells(opts.cell, g);
    var items = standingBlocks(atlas, cells, g, at).concat(walkingMovers(atlas, opts.movers || [], g, at), volumeItems(opts, g));
    var canvas = ground(g, atlas, opts.cell, at);
    sorted(items).forEach(function (item) { canvas = painted(canvas, item); });
    return labelled(canvas, atlas, opts, g);
  }

  D.iso = {
    /** `Cauldron2D.Projection.Iso.compose/2`: the isometric picture for `opts`. */
    compose: function (atlas, opts) {
      var g = geometry(atlas, opts);
      return g.stamps ? stamped(atlas, g, opts) : sampled(atlas, g, opts);
    },

    /** `Cauldron2D.Projection.Iso.project/3`: where world point `[x, y]` lands in the picture. */
    project: function (atlas, point, opts) { return place(point[0], point[1], geometry(atlas, opts)); },

    /** `Cauldron2D.Projection.Iso.unproject/3`: the ground point under picture pixel `[px, py]`. */
    unproject: function (atlas, pixel, opts) { return unprojected(pixel[0], pixel[1], geometry(atlas, opts)); }
  };
})(typeof window !== "undefined" ? window : globalThis);
