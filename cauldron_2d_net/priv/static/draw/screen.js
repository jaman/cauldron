/**
 * `Cauldron2D.Screen` in the browser: a scene's screen items — arts, text in the atlas's
 * bitmap fonts, nine-slice panels, bars, fills and boxes, placed against the pane's
 * edges — drawn onto a transparent picture the pane's size, the same bytes
 * `Cauldron2D.Screen.compose/4` gives.
 *
 *     var picture = CauldronDraw.screen.compose(atlas, items, 480, 272, at);
 *
 * Items are in the wire form `Cauldron2D.Net.Scene.Items.screen_item/1` writes:
 * `[kind, ...parts, options]`, arts and fonts by name, points and sizes as pairs,
 * colours as lists, atoms as strings and `"pane"` for `:pane`.
 */
(function (global) {
  var D = global.CauldronDraw = global.CauldronDraw || {};
  var has = Object.prototype.hasOwnProperty;
  var anchors = {
    top_left: [0, 0], top: [0.5, 0], top_right: [1, 0], left: [0, 0.5], centre: [0.5, 0.5],
    right: [1, 0.5], bottom_left: [0, 1], bottom: [0.5, 1], bottom_right: [1, 1]
  };
  var segmenter = typeof Intl !== "undefined" && Intl.Segmenter ? new Intl.Segmenter() : null;

  /**
   * `items` drawn onto a transparent picture `width` by `height` pixels, with animated
   * arts at the frame showing at `at` milliseconds.
   */
  function compose(atlas, items, width, height, at) {
    var pane = [width, height], operations = [];
    items.forEach(function (item) {
      var normal = normalised(item), extent = scaled(measure(atlas, normal, pane), normal.opts);
      normal.extent = extent;
      pieces(atlas, normal, placed(normal, extent, pane), at).forEach(function (op) { operations.push(op); });
    });
    return D.render(Math.max(width, 1), Math.max(height, 1), operations, [0, 0, 0, 0]);
  }

  /**
   * Where each glyph of `text` goes in `font` (an atlas font), as `[char, x, y]` from the
   * text's top-left corner, as `Linocut.BitmapFont.layout/3` with `opts` `{align, wrap}`.
   */
  function layout(font, text, opts) {
    var lines = [];
    text.split("\n").forEach(function (line) { wrapped(font, line, opts.wrap).forEach(function (l) { lines.push(l); }); });
    var widest = 0;
    lines.forEach(function (line) { widest = Math.max(widest, lineWidth(font, line)); });
    var align = opts.align || "left", out = [];
    lines.forEach(function (line, row) {
      var x = indent(align, widest, lineWidth(font, line)), top = row * font.line;
      graphemes(line).forEach(function (char) {
        var key = glyphKey(font, char);
        if (key === null) return;
        out.push([key, x, top]);
        x = x + font.glyphs[key][4] + font.spacing;
      });
    });
    return out;
  }

  /** `Linocut.Slices.nine/3`: `picture` at `width` by `height`, its corners `border` pixels square. */
  function nine(picture, border, width, height) {
    var sw = picture.width, sh = picture.height;
    if (!(border > 0 && 2 * border < sw && 2 * border < sh)) throw new Error("no nine slices of border " + border);
    width = Math.max(width, 2 * border);
    height = Math.max(height, 2 * border);
    var out = new Uint8ClampedArray(width * height * 4), src = picture.data;
    for (var oy = 0; oy < height; oy++) {
      var sy = sliced(oy, border, sh, height);
      for (var ox = 0; ox < width; ox++) {
        var s = (sy * sw + sliced(ox, border, sw, width)) * 4, d = (oy * width + ox) * 4;
        out[d] = src[s]; out[d + 1] = src[s + 1]; out[d + 2] = src[s + 2]; out[d + 3] = src[s + 3];
      }
    }
    return { width: width, height: height, data: out };
  }

  function sliced(at, border, source, size) {
    if (at < border) return at;
    if (at < size - border) return border + (at - border) % (source - 2 * border);
    return source - (size - at);
  }

  function normalised(item) {
    var last = item[item.length - 1], withOpts = last !== null && typeof last === "object" && !Array.isArray(last);
    var opts = withOpts ? last : {}, parts = withOpts ? item.slice(1, -1) : item.slice(1);
    switch (item[0]) {
      case "art": return { kind: "art", art: parts[0], at: parts[1], opts: opts };
      case "text": return { kind: "text", font: parts[0], text: parts[1], at: parts[2], opts: opts };
      case "panel": return { kind: "panel", art: parts[0], at: parts[1], size: parts[2], opts: opts };
      case "bar": return { kind: "bar", art: parts[0], at: parts[1], fraction: Math.min(Math.max(parts[2], 0), 1), opts: opts };
      case "fill": return { kind: "fill", at: parts[0], size: parts[1], colour: parts[2], opts: {} };
      case "box": return { kind: "box", at: parts[0], size: [D.round(parts[1][0]), D.round(parts[1][1])], colour: parts[2], opts: opts };
    }
    throw new Error("no screen item " + item[0]);
  }

  function measure(atlas, item, pane) {
    switch (item.kind) {
      case "art": return atlas.art(item.art).size;
      case "panel": return item.size;
      case "fill": return item.size === "pane" ? pane : item.size;
      case "box": return item.size;
      case "bar": return barSize(atlas, item);
      case "text": return textSize(atlas, item);
    }
  }

  function barSize(atlas, item) {
    var size = atlas.art(item.art).size;
    if (item.opts.direction === "up") return [size[0], D.round(size[1] * item.fraction)];
    return [D.round(size[0] * item.fraction), size[1]];
  }

  function textSize(atlas, item) {
    var font = atlas.fonts[item.font], opts = item.opts;
    var grow = present(opts.outline) ? 2 : present(opts.shadow) ? 1 : 0, width = 0, height = font.height + grow;
    layout(font, item.text, opts).forEach(function (p) {
      var glyph = font.glyphs[p[0]];
      width = Math.max(width, p[1] + glyph[2] + grow);
      height = Math.max(height, p[2] + glyph[3] + grow);
    });
    return [width, height];
  }

  function scaleOf(opts) { return present(opts.scale) ? opts.scale : 1; }
  function alphaOf(opts) { return present(opts.alpha) ? opts.alpha : 1.0; }
  function present(value) { return value !== undefined && value !== null && value !== false; }

  function scaled(size, opts) {
    var scale = scaleOf(opts);
    return [size[0] * scale, size[1] * scale];
  }

  function placed(item, extent, pane) {
    var anchor = item.opts.anchor || "top_left", fraction = anchors[anchor], pivot = anchors[item.opts.pivot || anchor];
    return [pane[0] * fraction[0] + item.at[0] - extent[0] * pivot[0], pane[1] * fraction[1] + item.at[1] - extent[1] * pivot[1]];
  }

  function pieces(atlas, item, origin, at) {
    switch (item.kind) {
      case "art": return [picture(atlas.frame(item.art, at), origin, item.opts)];
      case "bar": return barPieces(atlas, item, origin, at);
      case "panel": return panelPieces(atlas, item, origin, at);
      case "fill": return [{ sprite: dot(item.colour), placement: { position: origin, scale: item.extent } }];
      case "box": return boxPieces(item, origin);
      case "text": return textPieces(atlas, item, origin);
    }
  }

  function barPieces(atlas, item, origin, at) {
    var frame = atlas.frame(item.art, at), shown = barSize(atlas, item);
    if (shown[0] === 0 || shown[1] === 0) return [];
    var top = item.opts.direction === "up" ? frame.height - shown[1] : 0;
    return [picture(D.crop(frame, 0, top, shown[0], shown[1]), origin, item.opts)];
  }

  function panelPieces(atlas, item, origin, at) {
    var frame = atlas.frame(item.art, at), scale = scaleOf(item.opts);
    var border = present(item.opts.border) ? item.opts.border : D.div(Math.min(frame.width, frame.height), 3);
    return [picture(nine(frame, border, D.div(item.size[0], scale), D.div(item.size[1], scale)), origin, item.opts)];
  }

  function boxPieces(item, origin) {
    var width = item.extent[0], height = item.extent[1], x = origin[0], y = origin[1];
    var thickness = present(item.opts.thickness) ? item.opts.thickness : 1;
    var edge = Math.min(thickness, Math.max(1, D.div(Math.min(width, height), 2))), picture = dot(item.colour);
    return [
      [[x, y], [width, edge]],
      [[x, y + height - edge], [width, edge]],
      [[x, y + edge], [edge, height - 2 * edge]],
      [[x + width - edge, y + edge], [edge, height - 2 * edge]]
    ].filter(function (side) { return side[1][0] > 0 && side[1][1] > 0; }).map(function (side) {
      return { sprite: picture, placement: { position: side[0], scale: side[1] } };
    });
  }

  function textPieces(atlas, item, origin) {
    var font = atlas.fonts[item.font], opts = item.opts, placements = layout(font, item.text, opts);
    var look = { alpha: alphaOf(opts), scale: scaleOf(opts) };
    var inset = present(opts.outline) ? look.scale : 0, x = origin[0] + inset, y = origin[1] + inset, out = [];
    if (present(opts.outline)) {
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          if (dx !== 0 || dy !== 0) glyphPieces(atlas, font.white, placements, opts.outline, [x + dx * look.scale, y + dy * look.scale], look, out);
        }
      }
    }
    if (present(opts.shadow)) glyphPieces(atlas, font.white, placements, opts.shadow, [x + look.scale, y + look.scale], look, out);
    if (present(opts.colour)) glyphPieces(atlas, font.white, placements, opts.colour, [x, y], look, out);
    else glyphPieces(atlas, font.glyphs, placements, null, [x, y], look, out);
    return out;
  }

  function glyphPieces(atlas, cut, placements, colour, origin, look, out) {
    placements.forEach(function (p) {
      var rect = cut[p[0]], placement = {
        position: [origin[0] + p[1] * look.scale, origin[1] + p[2] * look.scale], scale: [look.scale, look.scale], alpha: look.alpha
      };
      if (colour) placement.blend = [colour[0], colour[1], colour[2]];
      out.push({ sprite: atlas.slice(rect.slice(0, 4)), placement: placement });
    });
  }

  function picture(raster, position, opts) {
    var scale = scaleOf(opts), placement = { position: position, scale: [scale, scale], alpha: alphaOf(opts) };
    if (present(opts.tint)) placement.blend = [opts.tint[0], opts.tint[1], opts.tint[2]];
    return { sprite: raster, placement: placement };
  }

  function dot(colour) {
    var data = new Uint8ClampedArray([colour[0], colour[1], colour[2], colour[3]]);
    return { width: 1, height: 1, data: data };
  }

  function graphemes(text) {
    if (segmenter) return Array.from(segmenter.segment(text), function (s) { return s.segment; });
    return Array.from(text);
  }

  function glyphKey(font, char) {
    if (has.call(font.glyphs, char)) return char;
    if (font.upcase) {
      var upper = char.toUpperCase();
      if (has.call(font.glyphs, upper)) return upper;
    }
    if (font.fallback !== null && font.fallback !== undefined && has.call(font.glyphs, font.fallback)) return font.fallback;
    return null;
  }

  function lineWidth(font, line) {
    var sum = 0, count = 0;
    graphemes(line).forEach(function (char) {
      var key = glyphKey(font, char);
      if (key === null) return;
      sum += font.glyphs[key][4];
      count++;
    });
    return count === 0 ? 0 : sum + font.spacing * (count - 1);
  }

  function wrapped(font, line, width) {
    if (width === undefined || width === null) return [line];
    var lines = [];
    line.split(" ").forEach(function (word) {
      if (!lines.length) { lines.push(word); return; }
      var joined = lines[lines.length - 1] + " " + word;
      if (lineWidth(font, joined) <= width) lines[lines.length - 1] = joined;
      else lines.push(word);
    });
    return lines;
  }

  function indent(align, widest, width) {
    if (align === "centre") return D.div(widest - width, 2);
    if (align === "right") return widest - width;
    return 0;
  }

  D.screen = { compose: compose, layout: layout, nine: nine };
})(typeof window !== "undefined" ? window : globalThis);
