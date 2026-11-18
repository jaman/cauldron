/**
 * The pieces every part of the browser's scene drawing stands on: Elixir's integer
 * arithmetic, RGBA pictures and the blending `Cauldron2D.Blend` does, the atlas a
 * `Cauldron2D.Net.Atlas` index describes, and the reader that turns
 * `Cauldron2D.Net.Scene` payloads into views.
 *
 * A picture is `{width, height, data}`, `data` a `Uint8ClampedArray` of RGBA bytes, rows
 * top to bottom. Every function here gives the bytes Elixir gives for the same input.
 */
(function (global) {
  var D = global.CauldronDraw = global.CauldronDraw || {};

  /** Elixir's `round/1`: halves away from zero. */
  D.round = function (x) { return x < 0 ? -Math.round(-x) : Math.round(x); };
  /** Elixir's `div/2`: truncated toward zero. */
  D.div = function (a, b) { return Math.trunc(a / b); };
  /** Elixir's `rem/2`: the sign of the dividend. */
  D.rem = function (a, b) { return a % b; };
  /** Elixir's `Integer.floor_div/2`. */
  D.floorDiv = function (a, b) { return Math.floor(a / b); };
  /** Elixir's `Integer.mod/2`: the sign of the divisor. */
  D.mod = function (a, b) { var r = a % b; return r !== 0 && (r < 0) !== (b < 0) ? r + b : r; };

  /** A picture `width` by `height`, every pixel `fill` (`[r, g, b, a]`, default transparent). */
  D.raster = function (width, height, fill) {
    var data = new Uint8ClampedArray(width * height * 4);
    if (fill && (fill[0] || fill[1] || fill[2] || fill[3])) {
      for (var i = 0; i < data.length; i += 4) { data[i] = fill[0]; data[i + 1] = fill[1]; data[i + 2] = fill[2]; data[i + 3] = fill[3]; }
    }
    return { width: width, height: height, data: data };
  };

  /** The `width` by `height` part of `picture` from `{x, y}`, which must lie inside it. */
  D.crop = function (picture, x, y, width, height) {
    var out = new Uint8ClampedArray(width * height * 4);
    for (var row = 0; row < height; row++) {
      var from = ((y + row) * picture.width + x) * 4;
      out.set(picture.data.subarray(from, from + width * 4), row * width * 4);
    }
    return { width: width, height: height, data: out };
  };

  /** `above` laid over `beneath`, two pictures of one size, as `Cauldron2D.Blend.over/2`. */
  D.over = function (beneath, above) {
    var b = beneath.data, t = above.data, out = new Uint8ClampedArray(b.length);
    for (var i = 0; i < b.length; i += 4) {
      var ta = t[i + 3];
      if (ta === 0) { out[i] = b[i]; out[i + 1] = b[i + 1]; out[i + 2] = b[i + 2]; out[i + 3] = b[i + 3]; continue; }
      if (ta === 255) { out[i] = t[i]; out[i + 1] = t[i + 1]; out[i + 2] = t[i + 2]; out[i + 3] = 255; continue; }
      var top = ta / 255, base = b[i + 3] / 255 * (1 - top), alpha = top + base;
      out[i] = D.round((t[i] * top + b[i] * base) / alpha);
      out[i + 1] = D.round((t[i + 1] * top + b[i + 1] * base) / alpha);
      out[i + 2] = D.round((t[i + 2] * top + b[i + 2] * base) / alpha);
      out[i + 3] = D.round(alpha * 255);
    }
    return { width: beneath.width, height: beneath.height, data: out };
  };

  /** `Cauldron2D.Surface.stack/2`: `above` over `beneath`. */
  D.stack = function (beneath, above) { return D.over(beneath, above); };

  /** `Cauldron2D.Surface.magnify/2`: every pixel `times` wide and tall. */
  D.magnify = function (picture, times) {
    if (times === 1) return picture;
    var w = picture.width * times, h = picture.height * times, out = new Uint8ClampedArray(w * h * 4), src = picture.data;
    for (var y = 0; y < h; y++) {
      var sy = Math.floor(y / times);
      for (var x = 0; x < w; x++) {
        var s = (sy * picture.width + Math.floor(x / times)) * 4, d = (y * w + x) * 4;
        out[d] = src[s]; out[d + 1] = src[s + 1]; out[d + 2] = src[s + 2]; out[d + 3] = src[s + 3];
      }
    }
    return { width: w, height: h, data: out };
  };

  function unit(value) { return value > 1 ? 1 : value > 0 ? value : 0; }
  function byte(value) { return Math.max(0, Math.min(255, Math.trunc(value + 0.5))); }

  /** `Cauldron2D.Turn.cos_sin/1`: the cosine and sine of `degrees`, exact at the quarter turns. */
  D.cosSin = function (degrees) {
    var quarters = degrees / 90;
    if (quarters === Math.round(quarters)) return [[1, 0], [0, 1], [-1, 0], [0, -1]][D.mod(D.round(quarters), 4)];
    var radians = degrees * Math.PI / 180;
    return [Math.cos(radians), Math.sin(radians)];
  };

  /**
   * `picture` drawn into `canvas` in place, as `Cauldron2D.Blend.draw/6` draws it:
   * `placement` has `position` `[x, y]`, and optionally `origin`, `scale`, `angle`
   * (degrees), `blend` `[r, g, b]`, `alpha` and `mode` (`"over"`, `"add"`, `"subtract"`,
   * or `{gamemaker: mode}`).
   */
  D.draw = function (canvas, picture, placement) {
    var origin = placement.origin || [0, 0], scale = placement.scale || [1, 1];
    var cs = D.cosSin(placement.angle || 0), blend = placement.blend || [255, 255, 255];
    var st = {
      x: placement.position[0], y: placement.position[1], ox: origin[0], oy: origin[1], sx: scale[0], sy: scale[1],
      cos: cs[0], sin: cs[1], br: unit(blend[0] / 255), bg: unit(blend[1] / 255), bb: unit(blend[2] / 255),
      alpha: unit(placement.alpha === undefined ? 1 : placement.alpha), mode: modeNumber(placement.mode || "over"),
      w: picture.width, h: picture.height
    };
    if (st.sx === 0 || st.sy === 0 || st.alpha <= 0) return canvas;
    var xs = [], ys = [];
    [[0, 0], [st.w, 0], [0, st.h], [st.w, st.h]].forEach(function (c) {
      var dx = (c[0] - st.ox) * st.sx, dy = (c[1] - st.oy) * st.sy;
      xs.push(st.x + dx * st.cos + dy * st.sin);
      ys.push(st.y - dx * st.sin + dy * st.cos);
    });
    var left = Math.max(0, Math.floor(Math.min.apply(null, xs))), right = Math.min(canvas.width, Math.ceil(Math.max.apply(null, xs)));
    var top = Math.max(0, Math.floor(Math.min.apply(null, ys))), bottom = Math.min(canvas.height, Math.ceil(Math.max.apply(null, ys)));
    var c = canvas.data, p = picture.data;
    for (var row = top; row < bottom; row++) {
      for (var col = left; col < right; col++) {
        var rx = col + 0.5 - st.x, ry = row + 0.5 - st.y;
        var u = (rx * st.cos - ry * st.sin) / st.sx + st.ox, v = (rx * st.sin + ry * st.cos) / st.sy + st.oy;
        if (!(u >= 0 && u < st.w && v >= 0 && v < st.h)) continue;
        laid(c, (row * canvas.width + col) * 4, p, (Math.floor(v) * st.w + Math.floor(u)) * 4, st);
      }
    }
    return canvas;
  };

  function modeNumber(mode) {
    if (mode === "add") return 1;
    if (mode === "subtract") return 2;
    if (mode && mode.gamemaker) return 10 + modeNumber(mode.gamemaker);
    return 0;
  }

  function laid(c, i, p, j, st) {
    var br = c[i], bgc = c[i + 1], bb = c[i + 2], ba = c[i + 3], tr = p[j], tg = p[j + 1], tb = p[j + 2], ta = p[j + 3];
    var top = ta * st.alpha / 255;
    if (st.mode >= 10) {
      var kind = Math.trunc(st.mode - 10), baseA = ba / 255, tints = [st.br, st.bg, st.bb], above = [tr, tg, tb], beneath = [br, bgc, bb];
      for (var k = 0; k < 3; k++) {
        var colour = above[k] / 255 * tints[k], under = beneath[k] / 255, result;
        if (kind === 2) result = under * (1 - colour);
        else if (kind === 1) result = colour * top + under;
        else result = colour * top + under * (1 - top);
        c[i + k] = byte(result * 255);
      }
      var alpha = kind === 2 ? baseA * (1 - top) : kind === 1 ? top * top + baseA : top * top + baseA * (1 - top);
      c[i + 3] = byte(alpha * 255);
      return;
    }
    if (top <= 0) return;
    if (st.mode === 1) {
      c[i] = Math.min(255, Math.trunc(br + tr * st.br * top + 0.5));
      c[i + 1] = Math.min(255, Math.trunc(bgc + tg * st.bg * top + 0.5));
      c[i + 2] = Math.min(255, Math.trunc(bb + tb * st.bb * top + 0.5));
      c[i + 3] = Math.min(255, Math.trunc(ba + top * 255 + 0.5));
      return;
    }
    if (st.mode === 2) {
      c[i] = Math.max(0, Math.trunc(br * (1 - tr * st.br / 255 * top) + 0.5));
      c[i + 1] = Math.max(0, Math.trunc(bgc * (1 - tg * st.bg / 255 * top) + 0.5));
      c[i + 2] = Math.max(0, Math.trunc(bb * (1 - tb * st.bb / 255 * top) + 0.5));
      return;
    }
    var base = ba / 255 * (1 - top), sum = top + base;
    c[i] = Math.trunc((tr * st.br * top + br * base) / sum + 0.5);
    c[i + 1] = Math.trunc((tg * st.bg * top + bgc * base) / sum + 0.5);
    c[i + 2] = Math.trunc((tb * st.bb * top + bb * base) / sum + 0.5);
    c[i + 3] = Math.trunc(sum * 255 + 0.5);
  }

  /**
   * `Cauldron2D.Render.render/3`: a picture `width` by `height` starting as `background`
   * (`[r, g, b, a]`, or a picture of that size), with each operation drawn in order:
   * `{sprite: picture, placement}` as `draw` takes them, or `{raster: picture, at: [x, y]}`.
   */
  D.render = function (width, height, operations, background) {
    var canvas;
    if (background && background.data) canvas = { width: width, height: height, data: new Uint8ClampedArray(background.data) };
    else canvas = D.raster(width, height, background || [0, 0, 0, 0]);
    operations.forEach(function (op) {
      if (op.raster) D.draw(canvas, op.raster, { position: op.at });
      else D.draw(canvas, op.sprite, op.placement);
    });
    return canvas;
  };

  function hex(colour) {
    var n = parseInt(colour.slice(1), 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  }

  /**
   * The atlas a client draws from: `index` as `Cauldron2D.Net.Atlas.index/2` gives it, and
   * its sheet's RGBA bytes. `art(name)` is an art's index entry; `frame`, `pose` and
   * `face` are pictures as `Cauldron2D.Atlas.frame_at/3`, `pose/4` and `face/3` give them;
   * `addTinted` takes the tinted pictures `Cauldron2D.Net.Atlas.tinted/3` sends, and
   * `tinted(name, tint)` answers an atlas-like view of them (`frame`, `pose`, `face`), or
   * `null` while they have not arrived. `addTintedCell` takes the pictures
   * `Cauldron2D.Net.Atlas.tinted_cell/4` sends, and `tintedCell(base, overlays, tint, at)`
   * answers the cell blended and tinted at `at` milliseconds, or `null` while they have
   * not arrived.
   */
  D.atlas = function (index, rgba, width, height) {
    var sheet = { width: width, height: height, data: rgba };
    var cut = {};
    function slice(source, key, rect) {
      var k = key + rect.join(",");
      if (!cut[k]) cut[k] = D.crop(source, rect[0], rect[1], rect[2], rect[3]);
      return cut[k];
    }
    function view(source, key, arts) {
      return {
        art: function (name) { var a = arts[name]; if (!a) throw new Error("no art " + name); return a; },
        frameIndex: function (name, at) {
          var a = arts[name];
          return a.frames.length === 1 ? 0 : D.mod(D.floorDiv(at * a.fps, 1000), a.frames.length);
        },
        frame: function (name, at) { var a = arts[name]; return slice(source, key, a.frames[this.frameIndex(name, at)]); },
        sprite: function (name) { return slice(source, key, arts[name].frames[0]); },
        pose: function (name, pose, at) {
          var a = arts[name], frames = a.poses[pose] || a.frames;
          return slice(source, key, frames[D.mod(D.floorDiv(at * a.fps, 1000), frames.length)]);
        },
        face: function (name, face) {
          var a = arts[name], rect = a.faces[face] || a.faces.side || a.frames[0];
          return slice(source, key, rect);
        }
      };
    }
    var atlas = view(sheet, "sheet:", index.arts);
    var tints = {};
    atlas.index = index;
    atlas.tile = index.tile;
    atlas.void = hex(index.void);
    atlas.tallest = index.tallest;
    atlas.fonts = index.fonts;
    atlas.labelFont = index.label_font;
    atlas.sheet = sheet;
    atlas.slice = function (rect) { return slice(sheet, "sheet:", rect); };
    atlas.addTinted = function (name, tint, tintIndex, data, w, h) {
      var arts = {};
      arts[name] = tintIndex;
      tints[tint + "\u0000" + name] = view({ width: w, height: h, data: data }, "tint:" + tint + ":" + name + ":", arts);
    };
    atlas.tinted = function (name, tint) { return tints[tint + "\u0000" + name] || null; };
    var tintedCells = {};
    function cellKey(base, overlays, tint) { return [tint, base].concat(overlays).join("\u0000"); }
    atlas.addTintedCell = function (base, overlays, tint, cellIndex, data, w, h) {
      tintedCells[cellKey(base, overlays, tint)] = { index: cellIndex, source: { width: w, height: h, data: data }, key: "cell:" + cellKey(base, overlays, tint) + ":" };
    };
    atlas.tintedCell = function (base, overlays, tint, at) {
      var held = tintedCells[cellKey(base, overlays, tint)];
      if (!held) return null;
      var arts = [base].concat(overlays), position = 0;
      for (var i = 0; i < arts.length; i++) position = position * held.index.counts[i] + atlas.frameIndex(arts[i], at);
      return slice(held.source, held.key, held.index.frames[position]);
    };
    return atlas;
  };

  /**
   * A reader of `Cauldron2D.Net.Scene` payloads for `atlas`: `read(payload)` keeps the
   * cells and kinds and answers a view — the payload's fields, `focus` as `[x, y]`,
   * `cell(x, y)` the world's cell (`null` for an empty tile, else `{base, overlays,
   * tint}` by name), and each layer with its own `cell(x, y)`.
   */
  D.reader = function (atlas) {
    var kinds = {}, grids = {};
    function cellOf(name) {
      var grid = grids[name] || {};
      return function (x, y) {
        var k = grid[x + "," + y];
        return k ? kinds[k] : null;
      };
    }
    return {
      read: function (payload) {
        payload.kinds.forEach(function (k) { kinds[k[0]] = { base: k[1], overlays: k[2], tint: k[3] }; });
        Object.keys(payload.cells).forEach(function (name) {
          var grid = grids[name] || (grids[name] = {}), changes = payload.cells[name];
          for (var i = 0; i < changes.length; i += 3) {
            if (changes[i + 2] === 0) delete grid[changes[i] + "," + changes[i + 1]];
            else grid[changes[i] + "," + changes[i + 1]] = changes[i + 2];
          }
        });
        var view = Object.assign({}, payload);
        view.atlas = atlas;
        view.cell = cellOf("world");
        view.layers = payload.layers.map(function (layer) {
          var copy = Object.assign({}, layer);
          copy.cell = cellOf(layer.name);
          return copy;
        });
        return view;
      }
    };
  };
})(typeof window !== "undefined" ? window : globalThis);
