#include <erl_nif.h>
#include <math.h>
#include <string.h>

typedef struct {
  double fx, fy, dx, dy, rx, ry;
  double horizon, projection, vertical, eye, range;
} camera;

typedef struct {
  const unsigned char *cells;
  int width, height, x0, y0;
} grid;

static int get_double(ErlNifEnv *env, ERL_NIF_TERM term, double *out) {
  long value;

  if (enif_get_double(env, term, out)) return 1;

  if (enif_get_long(env, term, &value)) {
    *out = (double)value;
    return 1;
  }

  return 0;
}

static int get_camera(ErlNifEnv *env, ERL_NIF_TERM term, camera *out) {
  const ERL_NIF_TERM *field;
  double *slot[11];
  int arity, index;

  if (!enif_get_tuple(env, term, &arity, &field) || arity != 11) return 0;

  slot[0] = &out->fx;
  slot[1] = &out->fy;
  slot[2] = &out->dx;
  slot[3] = &out->dy;
  slot[4] = &out->rx;
  slot[5] = &out->ry;
  slot[6] = &out->horizon;
  slot[7] = &out->projection;
  slot[8] = &out->vertical;
  slot[9] = &out->eye;
  slot[10] = &out->range;

  for (index = 0; index < 11; index++) {
    if (!get_double(env, field[index], slot[index])) return 0;
  }

  return 1;
}

static int get_colour(ErlNifEnv *env, ERL_NIF_TERM term, unsigned char *out) {
  const ERL_NIF_TERM *field;
  int arity, index, value;

  if (!enif_get_tuple(env, term, &arity, &field) || arity != 3) return 0;

  for (index = 0; index < 3; index++) {
    if (!enif_get_int(env, field[index], &value) || value < 0 || value > 255) return 0;
    out[index] = (unsigned char)value;
  }

  out[3] = 255;
  return 1;
}

static inline int clamp_int(int value, int high) {
  if (value < 0) return 0;
  if (value > high) return high;
  return value;
}

static inline unsigned char channel(unsigned char value, unsigned char fog, double mix) {
  long rounded = lround((double)value + ((double)fog - (double)value) * mix);

  if (rounded < 0) return 0;
  if (rounded > 255) return 255;
  return (unsigned char)rounded;
}

static inline int cell_at(const grid *map, int wx, int wy) {
  int column = wx - map->x0;
  int row = wy - map->y0;
  const unsigned char *entry;

  if (column < 0 || row < 0 || column >= map->width || row >= map->height) return 0;

  entry = map->cells + ((size_t)row * map->width + column) * 2;
  return (entry[0] << 8) | entry[1];
}

static ERL_NIF_TERM plane(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ErlNifBinary cells, texels;
  camera view;
  grid map;
  ERL_NIF_TERM result;
  const ERL_NIF_TERM *field;
  unsigned char *out, empty[4];
  const unsigned char *pixels;
  int arity, width, height, levels, tile, arts, x, y;

  if (argc != 8) return enif_make_badarg(env);

  if (!enif_inspect_binary(env, argv[0], &cells)) return enif_make_badarg(env);
  if (!enif_get_tuple(env, argv[1], &arity, &field) || arity != 4) return enif_make_badarg(env);
  if (!enif_get_int(env, field[0], &map.width)) return enif_make_badarg(env);
  if (!enif_get_int(env, field[1], &map.height)) return enif_make_badarg(env);
  if (!enif_get_int(env, field[2], &map.x0)) return enif_make_badarg(env);
  if (!enif_get_int(env, field[3], &map.y0)) return enif_make_badarg(env);
  if (map.width <= 0 || map.height <= 0) return enif_make_badarg(env);
  if (cells.size != (size_t)map.width * map.height * 2) return enif_make_badarg(env);
  map.cells = cells.data;

  if (!enif_inspect_binary(env, argv[2], &texels)) return enif_make_badarg(env);
  if (!enif_get_int(env, argv[3], &tile) || tile <= 0) return enif_make_badarg(env);
  if (texels.size % ((size_t)tile * tile * 4) != 0) return enif_make_badarg(env);
  arts = (int)(texels.size / ((size_t)tile * tile * 4));
  pixels = texels.data;

  if (!enif_get_tuple(env, argv[4], &arity, &field) || arity != 2) return enif_make_badarg(env);
  if (!enif_get_int(env, field[0], &width)) return enif_make_badarg(env);
  if (!enif_get_int(env, field[1], &height)) return enif_make_badarg(env);
  if (width <= 0 || height <= 0) return enif_make_badarg(env);

  if (!get_camera(env, argv[5], &view)) return enif_make_badarg(env);
  if (view.projection == 0.0 || view.range <= 0.0) return enif_make_badarg(env);

  if (!get_colour(env, argv[6], empty)) return enif_make_badarg(env);
  if (!enif_get_int(env, argv[7], &levels) || levels <= 0) return enif_make_badarg(env);

  out = enif_make_new_binary(env, (size_t)width * height * 4, &result);
  if (out == NULL) return enif_make_badarg(env);

  for (y = 0; y < height; y++) {
    unsigned char *row = out + (size_t)y * width * 4;
    double depth, step, wx, wy, mix;
    int fog, far;

    if ((double)y <= view.horizon) {
      memset(row, 0, (size_t)width * 4);
      continue;
    }

    depth = view.eye * view.vertical / ((double)y - view.horizon);
    fog = (int)((depth < 0.0 ? 0.0 : depth) / view.range * (double)levels);
    if (fog > levels) fog = levels;
    mix = (double)fog / (double)levels;
    far = depth > view.range;
    step = depth / view.projection;
    wx = view.fx + view.dx * depth - view.rx * (double)width / 2.0 * step;
    wy = view.fy + view.dy * depth - view.ry * (double)width / 2.0 * step;

    for (x = 0; x < width; x++, wx += view.rx * step, wy += view.ry * step) {
      unsigned char *pixel = row + (size_t)x * 4;
      const unsigned char *texel;
      double floor_x, floor_y;
      int index, column, texel_row;

      if (far) {
        memcpy(pixel, empty, 4);
        continue;
      }

      floor_x = floor(wx);
      floor_y = floor(wy);
      index = cell_at(&map, (int)floor_x, (int)floor_y);

      if (index <= 0 || index > arts) {
        memcpy(pixel, empty, 4);
        continue;
      }

      column = clamp_int((int)((wx - floor_x) * (double)tile), tile - 1);
      texel_row = clamp_int((int)((wy - floor_y) * (double)tile), tile - 1);
      texel = pixels + ((size_t)(index - 1) * tile * tile + (size_t)texel_row * tile + column) * 4;

      if (texel[3] < 128) {
        memcpy(pixel, texel, 4);
        continue;
      }

      pixel[0] = channel(texel[0], empty[0], mix);
      pixel[1] = channel(texel[1], empty[1], mix);
      pixel[2] = channel(texel[2], empty[2], mix);
      pixel[3] = 255;
    }
  }

  return result;
}

static ERL_NIF_TERM available(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;
  (void)argv;
  return enif_make_atom(env, "true");
}

static ErlNifFunc funcs[] = {
    {"available?", 0, available, 0},
    {"plane", 8, plane, ERL_NIF_DIRTY_JOB_CPU_BOUND}};

ERL_NIF_INIT(Elixir.Cauldron2D.Projection.Ground, funcs, NULL, NULL, NULL, NULL)
