/**
 * `Cauldron2D.Projection.Volume` and `Cauldron2D.Projection.Volume.Shapes` in the browser:
 * coloured regions of space that tint whatever is seen through them.
 *
 * A volume as `list` and `new` give it is
 * `{at: [x, y], shape, colour: [r, g, b], strength, falloff, thickness, density, cells}`,
 * `shape` one of `["sphere", radius, height]`, `["cylinder", radius, height]`,
 * `["cone", length, spread, heading, height]`, `["beam", length, width, heading, height]`
 * or `["cells", [[x, y], ...], height]`, `falloff` `"depth"`, `"flat"` or `"shell"`, and
 * `cells` the tiles of a `"cells"` shape prepared for lookup (`null` otherwise).
 *
 * A point or direction is `[x, y, z]`, `z` running up from the ground. A plan is
 * `{origin, originX, originY, direction, directionX, directionY, limits, native}`; `limits`
 * is `null` or a `Float32Array` holding one limit per canvas pixel, row by row. A canvas is
 * a picture `{width, height, data}`.
 *
 * `paint` gives the bytes `Cauldron2D.Projection.Volume.Native` gives; `through` and `mix`
 * give what the Elixir functions of the same names give.
 *
 *     var volumes = CauldronDraw.volume.list(view.volumes);
 *     var length = CauldronDraw.volume.through(volumes[0], [x, y, 0], [0, 0, 1], Infinity);
 *     var pixel = CauldronDraw.volume.mix([r, g, b, 255], volumes[0], length);
 */
(function (global) {
  var D = global.CauldronDraw = global.CauldronDraw || {};
  var V = D.volume = D.volume || {};
  var S = V.shapes = V.shapes || {};

  var FAR = 1.0e18, FLAT = 1.0e-12, NUDGE = 1.0e-9, MAX_SPANS = 96, CLEAREST = 0.99;
  var DEFAULT_SHAPE = ["sphere", 1.0, 0.0], DEFAULT_COLOUR = [255, 255, 255], DEFAULT_STRENGTH = 0.5;
  var KINDS = ["sphere", "cylinder", "cone", "beam", "cells"];

  var SPLITTER = 134217729, LN2 = [0.6931471805599453, 2.3190468138462996e-17], LN2_REST = 5.707708438416212e-34;

  function twoSum(a, b) { var s = a + b, bb = s - a; return [s, (a - (s - bb)) + (b - bb)]; }

  function quickTwoSum(a, b) { var s = a + b; return [s, b - (s - a)]; }

  function split(a) { var c = SPLITTER * a, hi = c - (c - a); return [hi, a - hi]; }

  function twoProd(a, b) {
    var p = a * b, x = split(a), y = split(b);
    return [p, ((x[0] * y[0] - p) + x[0] * y[1] + x[1] * y[0]) + x[1] * y[1]];
  }

  function ddAdd(x, y) {
    var s = twoSum(x[0], y[0]), t = twoSum(x[1], y[1]);
    s = quickTwoSum(s[0], s[1] + t[0]);
    return quickTwoSum(s[0], s[1] + t[1]);
  }

  function ddMul(x, y) { var p = twoProd(x[0], y[0]); return quickTwoSum(p[0], p[1] + (x[0] * y[1] + x[1] * y[0])); }

  function ddMulD(x, d) { var p = twoProd(x[0], d); return quickTwoSum(p[0], p[1] + x[1] * d); }

  function ddDivD(x, d) {
    var q = x[0] / d, p = twoProd(q, d);
    return quickTwoSum(q, ((x[0] - p[0]) - p[1] + x[1]) / d);
  }

  function ddDiv(x, y) {
    var q1 = x[0] / y[0], rest = ddAdd(x, ddMulD(y, -q1));
    var q2 = rest[0] / y[0];
    rest = ddAdd(rest, ddMulD(y, -q2));
    return ddAdd(quickTwoSum(q1, q2), [rest[0] / y[0], 0]);
  }

  function pow2(k) {
    if (k > 1023) return Math.pow(2, k - 600) * Math.pow(2, 600);
    if (k < -1022) return Math.pow(2, k + 600) * Math.pow(2, -600);
    return Math.pow(2, k);
  }

  function expm1Small(r) {
    var term = ddDivD(r, 12);
    for (var n = 11; n >= 1; n--) term = ddDivD(ddMul(r, ddAdd([1, 0], term)), n);
    return term;
  }

  function expScaled(x) {
    var k = Math.round(x / LN2[0]);
    var r = ddAdd(ddAdd([x, 0], ddMulD(LN2, -k)), [-k * LN2_REST, 0]);
    var e = expm1Small([r[0] / 512, r[1] / 512]);
    for (var i = 0; i < 9; i++) e = ddAdd(ddMulD(e, 2), ddMul(e, e));
    return { k: k, m: ddAdd([1, 0], e) };
  }

  function roundedToSubnormal(m, k) {
    var scale = pow2(k + 1074), hi = m[0] * scale, whole = Math.floor(hi), fraction = (hi - whole) + m[1] * scale;
    if (fraction > 0.5 || (fraction === 0.5 && whole % 2 === 1)) whole = whole + 1;
    return whole * pow2(-1074);
  }

  function exactExp(x) {
    if (x !== x) return x;
    if (x > 709.782712893384) return Infinity;
    if (x < -746) return 0;
    if (x === 0) return 1;
    var scaled = expScaled(x);
    if (scaled.k > 1023) return (scaled.m[0] * 2) * pow2(scaled.k - 1);
    if (scaled.k >= -1021) return scaled.m[0] * pow2(scaled.k);
    return roundedToSubnormal(scaled.m, scaled.k);
  }

  function exponentOf(x) {
    var shift = x < 2.2250738585072014e-308 ? 600 : 0, scaled = x * pow2(shift);
    var e = Math.floor(Math.log(scaled) / Math.LN2), m = scaled * pow2(-e);
    while (m >= 2) { m = m / 2; e = e + 1; }
    while (m < 1) { m = m * 2; e = e - 1; }
    if (m > Math.SQRT2) { m = m / 2; e = e + 1; }
    return [m, e - shift];
  }

  function logNear1(m) {
    var f = ddDiv(twoSum(m, -1), twoSum(m, 1)), f2 = ddMul(f, f), sum = ddDivD([1, 0], 45);
    for (var n = 43; n >= 1; n -= 2) sum = ddAdd(ddDivD([1, 0], n), ddMul(f2, sum));
    return ddMulD(ddMul(f, sum), 2);
  }

  function exactLog(x) {
    if (!(x > 0) || x === Infinity) return Math.log(x);
    if (x === 1) return 0;
    var parts = exponentOf(x), e = parts[1], logM = logNear1(parts[0]);
    if (e === 0) return logM[0];
    return ddAdd(ddAdd(ddMulD(LN2, e), [e * LN2_REST, 0]), logM)[0];
  }

  /** `Shapes.kinds/0`: the shape kinds the engine knows. */
  S.kinds = function () { return KINDS.slice(); };

  /** `Shapes.span/3`: the `[from, to]` stretches of `origin + t * direction` inside `shape`, in order. */
  S.span = function (shape, origin, direction, cells) {
    var kind = shape[0];
    if (kind === "sphere") return sphereSpan(shape[1], shape[2], origin, direction);
    if (kind === "cylinder") return wrap(column(shape[1], shape[2], origin, direction));
    if (kind === "cone") return coneSpan(shape, origin, direction);
    if (kind === "beam") return beamSpan(shape, origin, direction);
    return cellsSpan(shape, cells || cellsOf(shape[1]), origin, direction);
  };

  /** `Shapes.bounds/1`: `[[minX, minY, minZ], [maxX, maxY, maxZ]]`, the box `shape` fits in. */
  S.bounds = function (shape) {
    var kind = shape[0];
    if (kind === "sphere") return [[-shape[1], -shape[1], shape[2] - shape[1]], [shape[1], shape[1], shape[2] + shape[1]]];
    if (kind === "cylinder") return [[-shape[1], -shape[1], 0.0], [shape[1], shape[1], shape[2]]];
    if (kind === "cone") return [[-shape[1], -shape[1], 0.0], [shape[1], shape[1], shape[4]]];
    if (kind === "beam") return beamBounds(shape);
    return cellsBounds(shape);
  };

  /** `Shapes.thickness/1`: how far a ray travels through the thickest part of `shape`. */
  S.thickness = function (shape) {
    var kind = shape[0];
    if (kind === "sphere") return 2 * shape[1];
    if (kind === "cylinder") return diagonal(2 * shape[1], 2 * shape[1], shape[2]);
    if (kind === "cone" || kind === "beam") return diagonal(shape[1], 0.0, shape[4]);
    var box = cellsBounds(shape);
    return diagonal(box[1][0] - box[0][0], box[1][1] - box[0][1], box[1][2] - box[0][2]);
  };

  /** `Volume.new/1`: a volume from its fields, wire or already built, with `at` required. */
  V.new = function (fields) {
    var shape = shaped(fields.shape === undefined || fields.shape === null ? DEFAULT_SHAPE : fields.shape);
    var given = fields.strength === undefined || fields.strength === null ? DEFAULT_STRENGTH : fields.strength;
    var strength = Math.max(Math.min(given, CLEAREST), 0.0);
    var thickness = Math.max(S.thickness(shape), 1.0e-6);
    var volume = {
      at: [fields.at[0], fields.at[1]],
      shape: shape,
      colour: fields.colour || DEFAULT_COLOUR,
      strength: strength,
      falloff: fields.falloff || "depth",
      thickness: thickness,
      density: -exactLog(1 - strength) / thickness,
      cells: shape[0] === "cells" ? cellsOf(shape[1]) : null
    };
    if (fields.follows !== undefined) volume.follows = fields.follows;
    return volume;
  };

  /** `Volume.list/1`: every volume of a list, as `new` builds one. */
  V.list = function (volumes) { return (volumes || []).map(V.new); };

  /**
   * `Volume.through/4`: how far the ray from `origin` along `direction` travels inside
   * `volume` above the ground, ahead of the origin and within `limit` steps of `direction`
   * (`Infinity` for no limit), in the units the volume is measured in.
   */
  V.through = function (volume, origin, direction, limit) {
    var dx = direction[0], dy = direction[1], dz = direction[2], oz = origin[2];
    var local = [origin[0] - volume.at[0], origin[1] - volume.at[1], oz];
    var spans = S.span(volume.shape, local, direction, volume.cells), steps = 0.0;
    for (var i = 0; i < spans.length; i++) steps = steps + inside(spans[i], oz, dz, limit);
    return steps * Math.sqrt(dx * dx + dy * dy + dz * dz);
  };

  /** `Volume.mix/3`: `pixel` (`[r, g, b, a]`) with as much of the volume's colour as `length` calls for; a new array. */
  V.mix = function (pixel, volume, length) {
    if (length <= 0) return pixel.slice();
    var weight = weightOf(volume, length), colour = volume.colour;
    return [blend(pixel[0], colour[0], weight), blend(pixel[1], colour[1], weight), blend(pixel[2], colour[2], weight), pixel[3]];
  };

  /** `Volume.eyeline/3`: the direction towards the viewer every ray of an axonometric projection runs in. */
  V.eyeline = function (across, down, lift) {
    var ax = across[0], ay = across[1], bx = down[0], by = down[1];
    var dz = (bx * ay - ax * by) / lift;
    return dz < 0 ? [-bx, ax, -dz] : [bx, -ax, dz];
  };

  /** `Volume.corners/1`: the world points of the box the volume fits in, above the ground. */
  V.corners = function (volume) {
    var box = S.bounds(volume.shape), cx = volume.at[0], cy = volume.at[1], out = [];
    var xs = [cx + box[0][0], cx + box[1][0]], ys = [cy + box[0][1], cy + box[1][1]];
    var zs = [Math.max(box[0][2], 0.0), Math.max(box[1][2], 0.0)];
    xs.forEach(function (x) { ys.forEach(function (y) { zs.forEach(function (z) { out.push([x, y, z]); }); }); });
    return out;
  };

  /** `Volume.reach/1`: how far from `at` the volume can spread across the ground. */
  V.reach = function (volume) {
    var box = S.bounds(volume.shape), lx = box[0][0], ly = box[0][1], hx = box[1][0], hy = box[1][1];
    return Math.sqrt(Math.max(lx * lx, hx * hx) + Math.max(ly * ly, hy * hy));
  };

  /**
   * `Volume.box/2`: the whole-pixel rectangle `[left, top, right, bottom]` the volume can
   * reach, or `null`; `project` maps a world point `[x, y, z]` to `[px, py]` or `null`.
   */
  V.box = function (volume, project) {
    var points = V.corners(volume).map(project).filter(function (p) { return p !== null && p !== undefined; });
    if (!points.length) return null;
    var minX = points[0][0], maxX = minX, minY = points[0][1], maxY = minY;
    for (var i = 1; i < points.length; i++) {
      minX = Math.min(minX, points[i][0]); maxX = Math.max(maxX, points[i][0]);
      minY = Math.min(minY, points[i][1]); maxY = Math.max(maxY, points[i][1]);
    }
    return [Math.floor(minX), Math.floor(minY), Math.ceil(maxX), Math.ceil(maxY)];
  };

  /** `Volume.ground_plan/2`: rays starting on the ground under each pixel (`at([px, py])` gives `[x, y]`), all along `direction`. */
  V.groundPlan = function (at, direction) {
    var centre = at([0.5, 0.5]), across = at([1.5, 0.5]), down = at([0.5, 1.5]);
    var x = centre[0], y = centre[1];
    return {
      origin: [x, y, 0.0], originX: [across[0] - x, across[1] - y, 0.0], originY: [down[0] - x, down[1] - y, 0.0],
      direction: direction, directionX: [0.0, 0.0, 0.0], directionY: [0.0, 0.0, 0.0], limits: null
    };
  };

  /** `Volume.eye_plan/3`: rays from the eye `from`, `along([px, py])` giving each pixel's direction; `limits` a `Float32Array` or `null`. */
  V.eyePlan = function (from, along, limits) {
    var straight = along([0.5, 0.5]);
    return {
      origin: from, originX: [0.0, 0.0, 0.0], originY: [0.0, 0.0, 0.0],
      direction: straight, directionX: difference(along([1.5, 0.5]), straight), directionY: difference(along([0.5, 1.5]), straight),
      limits: limits || null
    };
  };

  /** `Volume.paint/4`: `canvas` tinted with `volume` over `box` (`[left, top, right, bottom]` or `null`), clipped; tints `canvas.data` in place and returns `canvas`. */
  V.paint = function (canvas, volume, box, plan) {
    if (!box) return canvas;
    var left = Math.max(box[0], 0), top = Math.max(box[1], 0);
    var right = Math.min(box[2], canvas.width - 1), bottom = Math.min(box[3], canvas.height - 1);
    if (right < left || bottom < top) return canvas;
    if (plan.native === false) return paintedInElixir(canvas, volume, left, top, right, bottom, plan);
    return paintedNatively(canvas, prepared(volume), left, top, right - left + 1, bottom - top + 1, plan);
  };

  function shaped(shape) {
    var kind = String(shape[0]);
    if (KINDS.indexOf(kind) < 0) throw new Error("not a known volume shape: " + kind);
    return [kind].concat(shape.slice(1));
  }

  function cellsOf(tiles) {
    var members = {}, count = 0, left = 0, top = 0, right = 0, bottom = 0;
    for (var i = 0; i < tiles.length; i++) {
      var x = tiles[i][0], y = tiles[i][1], key = x + "," + y;
      if (members[key]) continue;
      members[key] = true;
      if (count === 0) { left = right = x; top = bottom = y; }
      else { left = Math.min(left, x); right = Math.max(right, x); top = Math.min(top, y); bottom = Math.max(bottom, y); }
      count++;
    }
    return { members: members, count: count, left: left, top: top, right: right, bottom: bottom };
  }

  function member(cells, x, y) { return cells.members[x + "," + y] === true; }

  function diagonal(x, y, z) { return Math.sqrt(x * x + y * y + z * z); }

  function beamBounds(shape) {
    var length = shape[1], half = shape[2] / 2, ax = Math.cos(shape[3]), ay = Math.sin(shape[3]);
    var xs = [], ys = [];
    [0.0, length].forEach(function (along) {
      [-half, half].forEach(function (across) { xs.push(along * ax - across * ay); ys.push(along * ay + across * ax); });
    });
    return [[Math.min.apply(null, xs), Math.min.apply(null, ys), 0.0], [Math.max.apply(null, xs), Math.max.apply(null, ys), shape[4]]];
  }

  function cellsBounds(shape) {
    var cells = cellsOf(shape[1]);
    if (cells.count === 0) return [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]];
    return [[cells.left, cells.top, 0.0], [cells.right + 1, cells.bottom + 1, shape[2]]];
  }

  function wrap(interval) { return interval ? [interval] : []; }

  function roots(a, b, c) {
    var discriminant = b * b - 4 * a * c;
    if (a < FLAT || discriminant <= 0) return null;
    var root = Math.sqrt(discriminant);
    return [(-b - root) / (2 * a), (-b + root) / (2 * a)];
  }

  function slab(origin, direction, low, high) {
    if (Math.abs(direction) < FLAT) return origin >= low && origin <= high ? [-FAR, FAR] : null;
    var one = (low - origin) / direction, other = (high - origin) / direction;
    return [Math.min(one, other), Math.max(one, other)];
  }

  function meet(one, other) {
    if (!one || !other) return null;
    var from = Math.max(one[0], other[0]), to = Math.min(one[1], other[1]);
    return to > from ? [from, to] : null;
  }

  function sphereSpan(radius, height, origin, direction) {
    var ox = origin[0], oy = origin[1], ez = origin[2] - height, dx = direction[0], dy = direction[1], dz = direction[2];
    var a = dx * dx + dy * dy + dz * dz;
    var b = 2 * (dx * ox + dy * oy + dz * ez);
    var c = ox * ox + oy * oy + ez * ez - radius * radius;
    return wrap(roots(a, b, c));
  }

  function column(radius, height, origin, direction) {
    var ox = origin[0], oy = origin[1], dx = direction[0], dy = direction[1];
    var a = dx * dx + dy * dy;
    var b = 2 * (dx * ox + dy * oy);
    var c = ox * ox + oy * oy - radius * radius;
    var disc = a < FLAT ? (c <= 0 ? [-FAR, FAR] : null) : roots(a, b, c);
    return meet(disc, slab(origin[2], direction[2], 0, height));
  }

  function edge(angle, turn) { return [Math.sin(angle) * turn, -Math.cos(angle) * turn]; }

  function clip(interval, normal, origin, direction) {
    if (!interval) return null;
    var at = normal[0] * origin[0] + normal[1] * origin[1];
    var along = normal[0] * direction[0] + normal[1] * direction[1];
    if (Math.abs(along) < FLAT) return at >= 0 ? interval : null;
    if (along > 0) return meet(interval, [-at / along, FAR]);
    return meet(interval, [-FAR, -at / along]);
  }

  function coneSpan(shape, origin, direction) {
    var half = Math.min(Math.abs(shape[2]), Math.PI - FLAT) / 2, heading = shape[3];
    var interval = column(shape[1], shape[4], origin, direction);
    interval = clip(interval, edge(heading + half, 1), origin, direction);
    interval = clip(interval, edge(heading - half, -1), origin, direction);
    return wrap(interval);
  }

  function beamSpan(shape, origin, direction) {
    var ox = origin[0], oy = origin[1], dx = direction[0], dy = direction[1];
    var ax = Math.cos(shape[3]), ay = Math.sin(shape[3]), width = shape[2];
    var interval = slab(ox * ax + oy * ay, dx * ax + dy * ay, 0, shape[1]);
    interval = meet(interval, slab(oy * ax - ox * ay, dy * ax - dx * ay, -width / 2, width / 2));
    interval = meet(interval, slab(origin[2], direction[2], 0, shape[4]));
    return wrap(interval);
  }

  function cellsSpan(shape, cells, origin, direction) {
    var ox = origin[0], oy = origin[1], dx = direction[0], dy = direction[1], height = shape[2];
    if (cells.count === 0) return [];
    if (Math.abs(dx) < FLAT && Math.abs(dy) < FLAT)
      return member(cells, Math.floor(ox), Math.floor(oy)) ? wrap(slab(origin[2], direction[2], 0, height)) : [];
    var interval = slab(origin[2], direction[2], 0, height);
    interval = meet(interval, slab(ox, dx, cells.left, cells.right + 1));
    interval = meet(interval, slab(oy, dy, cells.top, cells.bottom + 1));
    if (!interval) return [];
    return join(march(cells, ox, oy, dx, dy, interval[0], interval[1]));
  }

  function march(cells, ox, oy, dx, dy, at, to) {
    var found = [];
    while (at < to) {
      var tileX = Math.floor(ox + (at + NUDGE) * dx), tileY = Math.floor(oy + (at + NUDGE) * dy);
      var next = Math.max(at + NUDGE, Math.min(to, leaves(ox, dx, tileX, oy, dy, tileY)));
      if (member(cells, tileX, tileY)) found.push([at, Math.min(next, to)]);
      at = next;
    }
    return found;
  }

  function leaves(ox, dx, tileX, oy, dy, tileY) { return Math.min(crosses(ox, dx, tileX), crosses(oy, dy, tileY)); }

  function crosses(origin, direction, tile) {
    if (Math.abs(direction) < FLAT) return FAR;
    if (direction > 0) return (tile + 1 - origin) / direction;
    return (tile - origin) / direction;
  }

  function join(intervals) {
    if (!intervals.length) return [];
    var held = [intervals[0].slice()];
    for (var i = 1; i < intervals.length; i++) {
      var last = held[held.length - 1], interval = intervals[i];
      if (interval[0] - last[1] < NUDGE * 2) last[1] = Math.max(last[1], interval[1]);
      else held.push(interval.slice());
    }
    return held;
  }

  function inside(interval, oz, dz, limit) {
    var ground = aboveGround(interval, oz, dz);
    if (!ground) return 0.0;
    return Math.max(Math.min(ground[1], limit) - Math.max(ground[0], 0.0), 0.0);
  }

  function aboveGround(interval, oz, dz) {
    if (dz > 0) return [Math.max(interval[0], -oz / dz), interval[1]];
    if (dz < 0) return [interval[0], Math.min(interval[1], -oz / dz)];
    return oz >= 0 ? interval : null;
  }

  function weightOf(volume, length) {
    if (volume.falloff === "flat") return volume.strength;
    if (volume.falloff === "shell") return volume.strength * Math.max(0.0, 1 - length / volume.thickness);
    return 1 - exactExp(-volume.density * length);
  }

  function blend(from, to, weight) { return Math.max(Math.min(D.round(from + (to - from) * weight), 255), 0); }

  function difference(a, b) { return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]; }

  function at(point, across, down, column, row) {
    return [point[0] + across[0] * column + down[0] * row, point[1] + across[1] * column + down[1] * row, point[2] + across[2] * column + down[2] * row];
  }

  function paintedInElixir(canvas, volume, left, top, right, bottom, plan) {
    var data = canvas.data, stride = canvas.width;
    for (var row = top; row <= bottom; row++) {
      for (var column = left; column <= right; column++) {
        var origin = at(plan.origin, plan.originX, plan.originY, column, row);
        var direction = at(plan.direction, plan.directionX, plan.directionY, column, row);
        var index = row * stride + column, offset = index * 4;
        var limit = plan.limits ? plan.limits[index] : Infinity;
        var tinted = V.mix([data[offset], data[offset + 1], data[offset + 2], data[offset + 3]], volume, V.through(volume, origin, direction, limit));
        data[offset] = tinted[0]; data[offset + 1] = tinted[1]; data[offset + 2] = tinted[2];
      }
    }
    return canvas;
  }

  function nativeColour(channel) { return Math.max(0, Math.min(255, channel)); }

  function bitmap(cells) {
    if (cells.count === 0) return { x: 0, y: 0, w: 1, h: 1, bits: new Uint8Array(1) };
    var w = cells.right - cells.left + 1, h = cells.bottom - cells.top + 1, bits = new Uint8Array(w * h);
    for (var y = 0; y < h; y++)
      for (var x = 0; x < w; x++) bits[y * w + x] = member(cells, cells.left + x, cells.top + y) ? 1 : 0;
    return { x: cells.left, y: cells.top, w: w, h: h, bits: bits };
  }

  function prepared(volume) {
    var shape = volume.shape, kind = KINDS.indexOf(shape[0]), params = shape[0] === "cells" ? [shape[2]] : shape.slice(1);
    var v = {
      kind: kind, falloff: volume.falloff, atX: volume.at[0], atY: volume.at[1],
      colour: [nativeColour(volume.colour[0]), nativeColour(volume.colour[1]), nativeColour(volume.colour[2])],
      strength: volume.strength, density: volume.density, thickness: volume.thickness,
      params: [params[0] || 0.0, params[1] || 0.0, params[2] || 0.0, params[3] || 0.0],
      bits: kind === 4 ? bitmap(volume.cells) : null,
      axis: [1.0, 0.0], edgeHigh: null, edgeLow: null
    };
    if (kind === 2) {
      var half = Math.abs(v.params[1]) / 2;
      if (half > Math.PI / 2 - FLAT) half = Math.PI / 2 - FLAT;
      v.edgeHigh = edge(v.params[2] + half, 1.0);
      v.edgeLow = edge(v.params[2] - half, -1.0);
    } else if (kind === 3) {
      v.axis = [Math.cos(v.params[2]), Math.sin(v.params[2])];
    }
    nativeBounds(v);
    return v;
  }

  function nativeBounds(v) {
    var p = v.params, reach;
    if (v.kind === 0) { v.low = [-p[0], -p[0], p[1] - p[0]]; v.high = [p[0], p[0], p[1] + p[0]]; }
    else if (v.kind === 1 || v.kind === 2) { v.low = [-p[0], -p[0], 0.0]; v.high = [p[0], p[0], v.kind === 1 ? p[1] : p[3]]; }
    else if (v.kind === 3) { reach = p[0] + p[1]; v.low = [-reach, -reach, 0.0]; v.high = [reach, reach, p[3]]; }
    else { v.low = [v.bits.x, v.bits.y, 0.0]; v.high = [v.bits.x + v.bits.w, v.bits.y + v.bits.h, p[0]]; }
    if (v.low[2] < 0.0) v.low[2] = 0.0;
    if (v.high[2] < 0.0) v.high[2] = 0.0;
  }

  function nativeSlab(origin, direction, low, high) {
    if (Math.abs(direction) < FLAT) return origin < low || origin > high ? null : [-FAR, FAR];
    var one = (low - origin) / direction, other = (high - origin) / direction;
    return one < other ? [one, other] : [other, one];
  }

  function nativeMeet(span, low, high) {
    if (low > span[0]) span[0] = low;
    if (high < span[1]) span[1] = high;
    return span[1] > span[0];
  }

  function nativeColumn(radius, height, o, d) {
    var a = d[0] * d[0] + d[1] * d[1];
    var b = 2 * (d[0] * o[0] + d[1] * o[1]);
    var c = o[0] * o[0] + o[1] * o[1] - radius * radius;
    var span;
    if (a < FLAT) {
      if (c > 0) return null;
      span = [-FAR, FAR];
    } else {
      span = roots(a, b, c);
      if (!span) return null;
    }
    var ground = nativeSlab(o[2], d[2], 0.0, height);
    if (!ground) return null;
    return nativeMeet(span, ground[0], ground[1]) ? span : null;
  }

  function halfPlane(normal, o, d, span) {
    var at = normal[0] * o[0] + normal[1] * o[1], along = normal[0] * d[0] + normal[1] * d[1];
    if (Math.abs(along) < FLAT) return at >= 0;
    if (along > 0) return nativeMeet(span, -at / along, FAR);
    return nativeMeet(span, -FAR, -at / along);
  }

  function occupied(v, tileX, tileY) {
    var b = v.bits, col = tileX - b.x, row = tileY - b.y;
    if (col < 0 || row < 0 || col >= b.w || row >= b.h) return false;
    return b.bits[row * b.w + col] !== 0;
  }

  function nativeLeaves(origin, direction, tile) {
    if (Math.abs(direction) < FLAT) return FAR;
    if (direction > 0) return (tile + 1.0 - origin) / direction;
    return (tile - origin) / direction;
  }

  function nativeMarch(v, o, d, from, to) {
    var at = from, out = [];
    while (at < to && out.length < MAX_SPANS) {
      var tileX = Math.floor(o[0] + (at + NUDGE) * d[0]), tileY = Math.floor(o[1] + (at + NUDGE) * d[1]);
      var across = nativeLeaves(o[0], d[0], tileX), down = nativeLeaves(o[1], d[1], tileY);
      var next = across < down ? across : down;
      if (next > to) next = to;
      if (next < at + NUDGE) next = at + NUDGE;
      if (occupied(v, tileX, tileY)) {
        var stop = next < to ? next : to;
        if (out.length > 0 && at - out[out.length - 1][1] < NUDGE * 2) out[out.length - 1][1] = stop;
        else out.push([at, stop]);
      }
      at = next;
    }
    return out;
  }

  function nativeSpans(v, o, d) {
    var p = v.params, span, low;
    if (v.kind === 0) {
      var ez = o[2] - p[1];
      var a = d[0] * d[0] + d[1] * d[1] + d[2] * d[2];
      var b = 2 * (d[0] * o[0] + d[1] * o[1] + d[2] * ez);
      var c = o[0] * o[0] + o[1] * o[1] + ez * ez - p[0] * p[0];
      return wrap(roots(a, b, c));
    }
    if (v.kind === 1) return wrap(nativeColumn(p[0], p[1], o, d));
    if (v.kind === 2) {
      span = nativeColumn(p[0], p[3], o, d);
      if (!span || !halfPlane(v.edgeHigh, o, d, span) || !halfPlane(v.edgeLow, o, d, span) || span[1] <= span[0]) return [];
      return [span];
    }
    if (v.kind === 3) return nativeBeam(v, o, d);
    if (Math.abs(d[0]) < FLAT && Math.abs(d[1]) < FLAT) {
      if (!occupied(v, Math.floor(o[0]), Math.floor(o[1]))) return [];
      return wrap(nativeSlab(o[2], d[2], 0.0, p[0]));
    }
    span = nativeSlab(o[2], d[2], 0.0, p[0]);
    if (!span) return [];
    for (var axis = 0; axis < 2; axis++) {
      low = nativeSlab(o[axis], d[axis], v.low[axis], v.high[axis]);
      if (!low || !nativeMeet(span, low[0], low[1])) return [];
    }
    return nativeMarch(v, o, d, span[0], span[1]);
  }

  function nativeBeam(v, o, d) {
    var p = v.params, ax = v.axis[0], ay = v.axis[1], other;
    var span = nativeSlab(o[0] * ax + o[1] * ay, d[0] * ax + d[1] * ay, 0.0, p[0]);
    if (!span) return [];
    other = nativeSlab(o[1] * ax - o[0] * ay, d[1] * ax - d[0] * ay, -p[1] / 2, p[1] / 2);
    if (!other || !nativeMeet(span, other[0], other[1])) return [];
    other = nativeSlab(o[2], d[2], 0.0, p[3]);
    if (!other || !nativeMeet(span, other[0], other[1])) return [];
    return [span];
  }

  function reaches(v, o, d) {
    var span = [-FAR, FAR];
    for (var axis = 0; axis < 3; axis++) {
      var bounds = nativeSlab(o[axis], d[axis], v.low[axis], v.high[axis]);
      if (!bounds || !nativeMeet(span, bounds[0], bounds[1])) return false;
    }
    return span[1] > 0;
  }

  function nativeThrough(v, origin, direction, limit) {
    var local = [origin[0] - v.atX, origin[1] - v.atY, origin[2]], total = 0.0;
    if (!reaches(v, local, direction)) return 0.0;
    var spans = nativeSpans(v, local, direction);
    for (var i = 0; i < spans.length; i++) {
      var from = spans[i][0], to = spans[i][1], ground;
      if (direction[2] > FLAT) {
        ground = -local[2] / direction[2];
        if (from < ground) from = ground;
      } else if (direction[2] < -FLAT) {
        ground = -local[2] / direction[2];
        if (to > ground) to = ground;
      } else if (local[2] < 0.0) {
        continue;
      }
      if (from < 0.0) from = 0.0;
      if (to > limit) to = limit;
      if (to > from) total += to - from;
    }
    return total * Math.sqrt(direction[0] * direction[0] + direction[1] * direction[1] + direction[2] * direction[2]);
  }

  function nativeWeight(v, length) {
    if (length <= 0.0) return 0.0;
    if (v.falloff === "flat") return v.strength;
    if (v.falloff === "shell") {
      var weight = v.strength * (1.0 - length / v.thickness);
      return weight > 0.0 ? weight : 0.0;
    }
    return 1.0 - exactExp(-v.density * length);
  }

  function paintedNatively(canvas, v, left, top, width, height, plan) {
    var origin0 = at(plan.origin, plan.originX, plan.originY, left, top);
    var direction0 = at(plan.direction, plan.directionX, plan.directionY, left, top);
    var ox = plan.originX, oy = plan.originY, dx = plan.directionX, dy = plan.directionY;
    var data = canvas.data, limits = plan.limits, origin = [0, 0, 0], direction = [0, 0, 0];
    for (var row = 0; row < height; row++) {
      for (var column = 0; column < width; column++) {
        for (var axis = 0; axis < 3; axis++) {
          origin[axis] = origin0[axis] + column * ox[axis] + row * oy[axis];
          direction[axis] = direction0[axis] + column * dx[axis] + row * dy[axis];
        }
        var index = (top + row) * canvas.width + left + column;
        var limit = limits ? limits[index] : FAR;
        var weight = nativeWeight(v, nativeThrough(v, origin, direction, limit));
        if (weight <= 0.0) continue;
        var offset = index * 4;
        for (var channel = 0; channel < 3; channel++) data[offset + channel] = blend(data[offset + channel], v.colour[channel], weight);
      }
    }
    return canvas;
  }
})(typeof window !== "undefined" ? window : globalThis);
