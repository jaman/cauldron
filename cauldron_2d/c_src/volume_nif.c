#include <erl_nif.h>
#include <math.h>
#include <string.h>

#define KIND_SPHERE 0
#define KIND_CYLINDER 1
#define KIND_CONE 2
#define KIND_BEAM 3
#define KIND_CELLS 4

#define FALLOFF_DEPTH 0
#define FALLOFF_FLAT 1
#define FALLOFF_SHELL 2

#define NEARLY_FLAT 1.0e-12
#define VERY_FAR 1.0e18
#define NUDGE 1.0e-9
#define MAX_SPANS 96

typedef struct {
  int kind, falloff;
  double at_x, at_y;
  unsigned char colour[3];
  double strength, density, thickness;
  double params[4];
  const unsigned char *bits;
  int bits_x, bits_y, bits_w, bits_h;
  double low[3], high[3];
  double axis[2], edge_high[2], edge_low[2];
} volume;

typedef struct {
  double origin[3], origin_x[3], origin_y[3];
  double direction[3], direction_x[3], direction_y[3];
} plan;

static int get_double(ErlNifEnv *env, ERL_NIF_TERM term, double *out) {
  long value;

  if (enif_get_double(env, term, out)) return 1;

  if (enif_get_long(env, term, &value)) {
    *out = (double)value;
    return 1;
  }

  return 0;
}

static int get_triple(ErlNifEnv *env, ERL_NIF_TERM term, double *out) {
  const ERL_NIF_TERM *field;
  int arity, index;

  if (!enif_get_tuple(env, term, &arity, &field) || arity != 3) return 0;

  for (index = 0; index < 3; index++) {
    if (!get_double(env, field[index], &out[index])) return 0;
  }

  return 1;
}

static int get_plan(ErlNifEnv *env, ERL_NIF_TERM term, plan *out) {
  const ERL_NIF_TERM *field;
  double *slot[6];
  int arity, index;

  if (!enif_get_tuple(env, term, &arity, &field) || arity != 6) return 0;

  slot[0] = out->origin;
  slot[1] = out->origin_x;
  slot[2] = out->origin_y;
  slot[3] = out->direction;
  slot[4] = out->direction_x;
  slot[5] = out->direction_y;

  for (index = 0; index < 6; index++) {
    if (!get_triple(env, field[index], slot[index])) return 0;
  }

  return 1;
}

static void edge_normal(double angle, double turn, double *out) {
  out[0] = sin(angle) * turn;
  out[1] = -cos(angle) * turn;
}

static void prepare(volume *out) {
  double radius, height, length, width, half;

  out->axis[0] = 1.0;
  out->axis[1] = 0.0;

  if (out->kind == KIND_CONE) {
    half = fabs(out->params[1]) / 2;
    if (half > M_PI / 2 - NEARLY_FLAT) half = M_PI / 2 - NEARLY_FLAT;
    edge_normal(out->params[2] + half, 1.0, out->edge_high);
    edge_normal(out->params[2] - half, -1.0, out->edge_low);
  } else if (out->kind == KIND_BEAM) {
    out->axis[0] = cos(out->params[2]);
    out->axis[1] = sin(out->params[2]);
  }

  switch (out->kind) {
    case KIND_SPHERE:
      radius = out->params[0];
      height = out->params[1];
      out->low[0] = out->low[1] = -radius;
      out->high[0] = out->high[1] = radius;
      out->low[2] = height - radius;
      out->high[2] = height + radius;
      break;

    case KIND_CYLINDER:
      radius = out->params[0];
      out->low[0] = out->low[1] = -radius;
      out->high[0] = out->high[1] = radius;
      out->low[2] = 0.0;
      out->high[2] = out->params[1];
      break;

    case KIND_CONE:
      length = out->params[0];
      out->low[0] = out->low[1] = -length;
      out->high[0] = out->high[1] = length;
      out->low[2] = 0.0;
      out->high[2] = out->params[3];
      break;

    case KIND_BEAM:
      length = out->params[0];
      width = out->params[1];
      out->low[0] = out->low[1] = -(length + width);
      out->high[0] = out->high[1] = length + width;
      out->low[2] = 0.0;
      out->high[2] = out->params[3];
      break;

    default:
      out->low[0] = out->bits_x;
      out->low[1] = out->bits_y;
      out->high[0] = out->bits_x + out->bits_w;
      out->high[1] = out->bits_y + out->bits_h;
      out->low[2] = 0.0;
      out->high[2] = out->params[0];
      break;
  }

  if (out->low[2] < 0.0) out->low[2] = 0.0;
  if (out->high[2] < 0.0) out->high[2] = 0.0;
}

static int get_volume(ErlNifEnv *env, ERL_NIF_TERM term, volume *out) {
  const ERL_NIF_TERM *field, *colour, *shading, *cells;
  ErlNifBinary params, bits;
  int arity, index, channel;
  unsigned int count;
  double at[2];

  if (!enif_get_tuple(env, term, &arity, &field) || arity != 7) return 0;
  if (!enif_get_int(env, field[0], &out->kind)) return 0;
  if (!enif_get_int(env, field[1], &out->falloff)) return 0;

  if (!enif_get_tuple(env, field[2], &arity, &colour) || arity != 2) return 0;
  if (!get_double(env, colour[0], &at[0])) return 0;
  if (!get_double(env, colour[1], &at[1])) return 0;
  out->at_x = at[0];
  out->at_y = at[1];

  if (!enif_get_tuple(env, field[3], &arity, &colour) || arity != 3) return 0;

  for (index = 0; index < 3; index++) {
    if (!enif_get_int(env, colour[index], &channel)) return 0;
    if (channel < 0) channel = 0;
    if (channel > 255) channel = 255;
    out->colour[index] = (unsigned char)channel;
  }

  if (!enif_get_tuple(env, field[4], &arity, &shading) || arity != 3) return 0;
  if (!get_double(env, shading[0], &out->strength)) return 0;
  if (!get_double(env, shading[1], &out->density)) return 0;
  if (!get_double(env, shading[2], &out->thickness)) return 0;

  if (!enif_inspect_binary(env, field[5], &params)) return 0;
  if (params.size > sizeof(out->params)) return 0;
  memset(out->params, 0, sizeof(out->params));
  memcpy(out->params, params.data, params.size);

  out->bits = NULL;
  out->bits_x = out->bits_y = out->bits_w = out->bits_h = 0;

  if (enif_get_tuple(env, field[6], &arity, &cells) && arity == 5) {
    if (!enif_get_int(env, cells[0], &out->bits_x)) return 0;
    if (!enif_get_int(env, cells[1], &out->bits_y)) return 0;
    if (!enif_get_int(env, cells[2], &out->bits_w)) return 0;
    if (!enif_get_int(env, cells[3], &out->bits_h)) return 0;
    if (!enif_inspect_binary(env, cells[4], &bits)) return 0;
    if (out->bits_w < 0 || out->bits_h < 0) return 0;
    count = (unsigned int)out->bits_w * (unsigned int)out->bits_h;
    if (bits.size < count) return 0;
    out->bits = bits.data;
  } else if (out->kind == KIND_CELLS) {
    return 0;
  }

  prepare(out);
  return 1;
}

static int slab(double origin, double direction, double low, double high, double *from,
                double *to) {
  double one, other;

  if (fabs(direction) < NEARLY_FLAT) {
    if (origin < low || origin > high) return 0;
    *from = -VERY_FAR;
    *to = VERY_FAR;
    return 1;
  }

  one = (low - origin) / direction;
  other = (high - origin) / direction;
  *from = one < other ? one : other;
  *to = one < other ? other : one;
  return 1;
}

static int meet(double *from, double *to, double low, double high) {
  if (low > *from) *from = low;
  if (high < *to) *to = high;
  return *to > *from;
}

static int roots(double a, double b, double c, double *from, double *to) {
  double discriminant, root;

  if (a < NEARLY_FLAT) return 0;

  discriminant = b * b - 4 * a * c;
  if (discriminant <= 0) return 0;

  root = sqrt(discriminant);
  *from = (-b - root) / (2 * a);
  *to = (-b + root) / (2 * a);
  return 1;
}

static int column(double radius, double height, const double o[3], const double d[3],
                  double *from, double *to) {
  double a, b, c, low, high;

  a = d[0] * d[0] + d[1] * d[1];
  b = 2 * (d[0] * o[0] + d[1] * o[1]);
  c = o[0] * o[0] + o[1] * o[1] - radius * radius;

  if (a < NEARLY_FLAT) {
    if (c > 0) return 0;
    *from = -VERY_FAR;
    *to = VERY_FAR;
  } else if (!roots(a, b, c, from, to)) {
    return 0;
  }

  if (!slab(o[2], d[2], 0.0, height, &low, &high)) return 0;
  return meet(from, to, low, high);
}

static int half_plane(const double normal[2], const double o[3], const double d[3], double *from,
                      double *to) {
  double nx = normal[0];
  double ny = normal[1];
  double at = nx * o[0] + ny * o[1];
  double along = nx * d[0] + ny * d[1];

  if (fabs(along) < NEARLY_FLAT) return at >= 0;
  if (along > 0) return meet(from, to, -at / along, VERY_FAR);
  return meet(from, to, -VERY_FAR, -at / along);
}

static int occupied(const volume *v, int tile_x, int tile_y) {
  int column_index = tile_x - v->bits_x;
  int row_index = tile_y - v->bits_y;

  if (column_index < 0 || row_index < 0) return 0;
  if (column_index >= v->bits_w || row_index >= v->bits_h) return 0;

  return v->bits[(size_t)row_index * v->bits_w + column_index] != 0;
}

static double leaves(double origin, double direction, int tile) {
  if (fabs(direction) < NEARLY_FLAT) return VERY_FAR;
  if (direction > 0) return ((double)tile + 1.0 - origin) / direction;
  return ((double)tile - origin) / direction;
}

static int march(const volume *v, const double o[3], const double d[3], double from, double to,
                 double out[][2]) {
  double at = from, next, across, down;
  int count = 0, tile_x, tile_y;

  while (at < to && count < MAX_SPANS) {
    tile_x = (int)floor(o[0] + (at + NUDGE) * d[0]);
    tile_y = (int)floor(o[1] + (at + NUDGE) * d[1]);
    across = leaves(o[0], d[0], tile_x);
    down = leaves(o[1], d[1], tile_y);
    next = across < down ? across : down;
    if (next > to) next = to;
    if (next < at + NUDGE) next = at + NUDGE;

    if (occupied(v, tile_x, tile_y)) {
      double stop = next < to ? next : to;

      if (count > 0 && at - out[count - 1][1] < NUDGE * 2) {
        out[count - 1][1] = stop;
      } else {
        out[count][0] = at;
        out[count][1] = stop;
        count++;
      }
    }

    at = next;
  }

  return count;
}

static int spans_of(const volume *v, const double o[3], const double d[3], double out[][2]) {
  double from, to, low, high, a, b, c, along_x, along_y;

  switch (v->kind) {
    case KIND_SPHERE: {
      double ez = o[2] - v->params[1];
      a = d[0] * d[0] + d[1] * d[1] + d[2] * d[2];
      b = 2 * (d[0] * o[0] + d[1] * o[1] + d[2] * ez);
      c = o[0] * o[0] + o[1] * o[1] + ez * ez - v->params[0] * v->params[0];
      if (!roots(a, b, c, &from, &to)) return 0;
      out[0][0] = from;
      out[0][1] = to;
      return 1;
    }

    case KIND_CYLINDER:
      if (!column(v->params[0], v->params[1], o, d, &from, &to)) return 0;
      out[0][0] = from;
      out[0][1] = to;
      return 1;

    case KIND_CONE:
      if (!column(v->params[0], v->params[3], o, d, &from, &to)) return 0;
      if (!half_plane(v->edge_high, o, d, &from, &to)) return 0;
      if (!half_plane(v->edge_low, o, d, &from, &to)) return 0;
      if (to <= from) return 0;
      out[0][0] = from;
      out[0][1] = to;
      return 1;

    case KIND_BEAM: {
      double ax = v->axis[0];
      double ay = v->axis[1];
      along_x = o[0] * ax + o[1] * ay;
      along_y = o[1] * ax - o[0] * ay;

      if (!slab(along_x, d[0] * ax + d[1] * ay, 0.0, v->params[0], &from, &to)) return 0;
      if (!slab(along_y, d[1] * ax - d[0] * ay, -v->params[1] / 2, v->params[1] / 2, &low, &high))
        return 0;
      if (!meet(&from, &to, low, high)) return 0;
      if (!slab(o[2], d[2], 0.0, v->params[3], &low, &high)) return 0;
      if (!meet(&from, &to, low, high)) return 0;
      out[0][0] = from;
      out[0][1] = to;
      return 1;
    }

    default:
      if (fabs(d[0]) < NEARLY_FLAT && fabs(d[1]) < NEARLY_FLAT) {
        if (!occupied(v, (int)floor(o[0]), (int)floor(o[1]))) return 0;
        if (!slab(o[2], d[2], 0.0, v->params[0], &from, &to)) return 0;
        out[0][0] = from;
        out[0][1] = to;
        return 1;
      }

      if (!slab(o[2], d[2], 0.0, v->params[0], &from, &to)) return 0;
      if (!slab(o[0], d[0], v->low[0], v->high[0], &low, &high)) return 0;
      if (!meet(&from, &to, low, high)) return 0;
      if (!slab(o[1], d[1], v->low[1], v->high[1], &low, &high)) return 0;
      if (!meet(&from, &to, low, high)) return 0;
      return march(v, o, d, from, to, out);
  }
}

static int reaches(const volume *v, const double o[3], const double d[3]) {
  double from = -VERY_FAR, to = VERY_FAR, low, high;
  int axis;

  for (axis = 0; axis < 3; axis++) {
    if (!slab(o[axis], d[axis], v->low[axis], v->high[axis], &low, &high)) return 0;
    if (!meet(&from, &to, low, high)) return 0;
  }

  return to > 0;
}

static double through(const volume *v, const double origin[3], const double direction[3],
                      double limit) {
  double local[3], spans[MAX_SPANS][2], total = 0.0, from, to, ground;
  int count, index;

  local[0] = origin[0] - v->at_x;
  local[1] = origin[1] - v->at_y;
  local[2] = origin[2];

  if (!reaches(v, local, direction)) return 0.0;

  count = spans_of(v, local, direction, spans);

  for (index = 0; index < count; index++) {
    from = spans[index][0];
    to = spans[index][1];

    if (direction[2] > NEARLY_FLAT) {
      ground = -local[2] / direction[2];
      if (from < ground) from = ground;
    } else if (direction[2] < -NEARLY_FLAT) {
      ground = -local[2] / direction[2];
      if (to > ground) to = ground;
    } else if (local[2] < 0.0) {
      continue;
    }

    if (from < 0.0) from = 0.0;
    if (to > limit) to = limit;
    if (to > from) total += to - from;
  }

  return total * sqrt(direction[0] * direction[0] + direction[1] * direction[1] +
                      direction[2] * direction[2]);
}

static double weight_of(const volume *v, double length) {
  double weight;

  if (length <= 0.0) return 0.0;

  switch (v->falloff) {
    case FALLOFF_FLAT:
      return v->strength;

    case FALLOFF_SHELL:
      weight = v->strength * (1.0 - length / v->thickness);
      return weight > 0.0 ? weight : 0.0;

    default:
      return 1.0 - exp(-v->density * length);
  }
}

static unsigned char blend(unsigned char from, unsigned char to, double weight) {
  double value = (double)from + ((double)to - (double)from) * weight;
  long rounded = lround(value);

  if (rounded < 0) return 0;
  if (rounded > 255) return 255;
  return (unsigned char)rounded;
}

static ERL_NIF_TERM tint(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ErlNifBinary pixels, limits;
  ERL_NIF_TERM result;
  unsigned char *out, *pixel;
  plan rays;
  volume painted;
  double origin[3], direction[3], limit, length, weight;
  int width, height, column_index, row_index, axis, channel;
  size_t offset;

  (void)argc;

  if (!enif_inspect_binary(env, argv[0], &pixels)) return enif_make_badarg(env);
  if (!enif_get_int(env, argv[1], &width)) return enif_make_badarg(env);
  if (!enif_get_int(env, argv[2], &height)) return enif_make_badarg(env);
  if (!get_plan(env, argv[3], &rays)) return enif_make_badarg(env);
  if (!enif_inspect_binary(env, argv[4], &limits)) return enif_make_badarg(env);
  if (!get_volume(env, argv[5], &painted)) return enif_make_badarg(env);

  if (width <= 0 || height <= 0) return enif_make_badarg(env);
  if (pixels.size != (size_t)width * (size_t)height * 4) return enif_make_badarg(env);
  if (limits.size != 0 && limits.size != (size_t)width * (size_t)height * sizeof(float))
    return enif_make_badarg(env);

  out = enif_make_new_binary(env, pixels.size, &result);
  memcpy(out, pixels.data, pixels.size);

  for (row_index = 0; row_index < height; row_index++) {
    for (column_index = 0; column_index < width; column_index++) {
      for (axis = 0; axis < 3; axis++) {
        origin[axis] = rays.origin[axis] + column_index * rays.origin_x[axis] +
                       row_index * rays.origin_y[axis];
        direction[axis] = rays.direction[axis] + column_index * rays.direction_x[axis] +
                          row_index * rays.direction_y[axis];
      }

      offset = ((size_t)row_index * width + column_index);
      limit = limits.size == 0 ? VERY_FAR : (double)((const float *)limits.data)[offset];
      length = through(&painted, origin, direction, limit);
      weight = weight_of(&painted, length);

      if (weight <= 0.0) continue;

      pixel = out + offset * 4;

      for (channel = 0; channel < 3; channel++) {
        pixel[channel] = blend(pixel[channel], painted.colour[channel], weight);
      }
    }
  }

  return result;
}

static ERL_NIF_TERM available(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;
  (void)argv;
  return enif_make_atom(env, "true");
}

static ErlNifFunc funcs[] = {{"available?", 0, available, 0},
                             {"tint", 6, tint, ERL_NIF_DIRTY_JOB_CPU_BOUND}};

ERL_NIF_INIT(Elixir.Cauldron2D.Projection.Volume.Native, funcs, NULL, NULL, NULL, NULL)
