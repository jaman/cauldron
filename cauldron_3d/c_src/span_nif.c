#include <erl_nif.h>
#include <math.h>
#include <stdint.h>
#include <string.h>

typedef struct {
  double w0, wx, u0, ux, v0, vx;
} planes_t;

enum light_kind { LIGHT_NONE, LIGHT_SCALAR, LIGHT_RGB, LIGHT_PLANE };

typedef struct {
  enum light_kind kind;
  double scale, red, green, blue, origin, per_x;
} light_t;

static ERL_NIF_TERM atom_nil;
static ERL_NIF_TERM atom_plane;

static int load(ErlNifEnv *env, void **priv, ERL_NIF_TERM info) {
  (void)priv;
  (void)info;
  atom_nil = enif_make_atom(env, "nil");
  atom_plane = enif_make_atom(env, "plane");
  return 0;
}

static int get_number(ErlNifEnv *env, ERL_NIF_TERM term, double *out) {
  long integer;

  if (enif_get_double(env, term, out)) {
    return 1;
  }

  if (enif_get_long(env, term, &integer)) {
    *out = (double)integer;
    return 1;
  }

  return 0;
}

static int get_numbers(ErlNifEnv *env, ERL_NIF_TERM term, int count, double *out) {
  const ERL_NIF_TERM *fields;
  int arity;

  if (!enif_get_tuple(env, term, &arity, &fields) || arity != count) {
    return 0;
  }

  for (int i = 0; i < count; i++) {
    if (!get_number(env, fields[i], &out[i])) {
      return 0;
    }
  }

  return 1;
}

static int get_planes(ErlNifEnv *env, ERL_NIF_TERM term, planes_t *planes) {
  double values[6];

  if (!get_numbers(env, term, 6, values)) {
    return 0;
  }

  planes->w0 = values[0];
  planes->wx = values[1];
  planes->u0 = values[2];
  planes->ux = values[3];
  planes->v0 = values[4];
  planes->vx = values[5];
  return 1;
}

static int get_light(ErlNifEnv *env, ERL_NIF_TERM term, light_t *light) {
  const ERL_NIF_TERM *fields;
  int arity;

  if (enif_is_identical(term, atom_nil)) {
    light->kind = LIGHT_NONE;
    return 1;
  }

  if (get_number(env, term, &light->scale)) {
    light->kind = LIGHT_SCALAR;
    return 1;
  }

  if (!enif_get_tuple(env, term, &arity, &fields)) {
    return 0;
  }

  if (arity == 3 && enif_is_identical(fields[0], atom_plane)) {
    light->kind = LIGHT_PLANE;
    return get_number(env, fields[1], &light->origin) &&
           get_number(env, fields[2], &light->per_x);
  }

  if (arity == 3) {
    light->kind = LIGHT_RGB;
    return get_number(env, fields[0], &light->red) &&
           get_number(env, fields[1], &light->green) &&
           get_number(env, fields[2], &light->blue);
  }

  return 0;
}

static unsigned char channel(double value) {
  if (value >= 255.0) {
    return 255;
  }

  if (value <= 0.0) {
    return 0;
  }

  return (unsigned char)(int)value;
}

static long wrap(long value, long size) {
  long result = value % size;
  return result < 0 ? result + size : result;
}

static void texel_uv(const planes_t *planes, long x, long *u, long *v) {
  double xc = (double)x + 0.5;
  double w = planes->w0 + planes->wx * xc;
  *u = (long)floor((planes->u0 + planes->ux * xc) / w);
  *v = (long)floor((planes->v0 + planes->vx * xc) / w);
}

static void light_texel(unsigned char *out, const unsigned char *colour, const light_t *light,
                        long x) {
  double scale;

  switch (light->kind) {
  case LIGHT_NONE:
    memcpy(out, colour, 4);
    return;
  case LIGHT_SCALAR:
    out[0] = channel(colour[0] * light->scale);
    out[1] = channel(colour[1] * light->scale);
    out[2] = channel(colour[2] * light->scale);
    out[3] = colour[3];
    return;
  case LIGHT_RGB:
    out[0] = channel(colour[0] * light->red);
    out[1] = channel(colour[1] * light->green);
    out[2] = channel(colour[2] * light->blue);
    out[3] = colour[3];
    return;
  case LIGHT_PLANE:
    scale = (light->origin + light->per_x * ((double)x + 0.5)) / 128;
    out[0] = channel(colour[0] * scale);
    out[1] = channel(colour[1] * scale);
    out[2] = channel(colour[2] * scale);
    out[3] = colour[3];
    return;
  }
}

static int get_run(ErlNifEnv *env, ERL_NIF_TERM term, long *first, long *stop) {
  const ERL_NIF_TERM *fields;
  int arity;

  return enif_get_tuple(env, term, &arity, &fields) && arity == 2 &&
         enif_get_long(env, fields[0], first) && enif_get_long(env, fields[1], stop);
}

static int get_texture(ErlNifEnv *env, ERL_NIF_TERM term, ErlNifBinary *pixels, long *width,
                       long *height, ErlNifBinary *colours, int *indexed) {
  const ERL_NIF_TERM *source;
  int arity;

  if (!enif_get_tuple(env, term, &arity, &source) || arity != 4 ||
      !enif_inspect_binary(env, source[0], pixels) || !enif_get_long(env, source[1], width) ||
      !enif_get_long(env, source[2], height) || *width <= 0 || *height <= 0) {
    return 0;
  }

  if (enif_is_identical(source[3], atom_nil)) {
    *indexed = 0;
    return pixels->size == (size_t)(*width * *height * 4);
  }

  *indexed = 1;
  return enif_inspect_binary(env, source[3], colours) && colours->size == 1024 &&
         pixels->size == (size_t)(*width * *height);
}

static ERL_NIF_TERM texture(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ErlNifBinary pixels, colours;
  long width, height, first, stop, clear = -1;
  int indexed;
  planes_t planes;
  light_t light;

  if (argc != 5 || !get_texture(env, argv[0], &pixels, &width, &height, &colours, &indexed) ||
      !(enif_is_identical(argv[1], atom_nil) || enif_get_long(env, argv[1], &clear)) ||
      !get_light(env, argv[2], &light) || !get_planes(env, argv[3], &planes) ||
      !get_run(env, argv[4], &first, &stop)) {
    return enif_make_badarg(env);
  }

  long count = stop > first ? stop - first : 0;
  ERL_NIF_TERM result;
  unsigned char *out = enif_make_new_binary(env, (size_t)count * 4, &result);

  for (long x = first; x < stop; x++, out += 4) {
    long u, v;
    texel_uv(&planes, x, &u, &v);
    long at = wrap(v, height) * width + wrap(u, width);

    if (!indexed) {
      light_texel(out, pixels.data + at * 4, &light, x);
      continue;
    }

    unsigned char index = pixels.data[at];

    if (index == clear) {
      memset(out, 0, 4);
    } else {
      light_texel(out, colours.data + index * 4, &light, x);
    }
  }

  return result;
}

static ERL_NIF_TERM surface(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ErlNifBinary pixels, colours;
  long width, height, first, stop;
  int indexed;
  planes_t planes;

  if (argc != 3 || !get_texture(env, argv[0], &pixels, &width, &height, &colours, &indexed) ||
      !get_planes(env, argv[1], &planes) || !get_run(env, argv[2], &first, &stop)) {
    return enif_make_badarg(env);
  }

  long count = stop > first ? stop - first : 0;
  ERL_NIF_TERM result;
  unsigned char *out = enif_make_new_binary(env, (size_t)count * 4, &result);

  for (long x = first; x < stop; x++, out += 4) {
    long u, v;
    texel_uv(&planes, x, &u, &v);
    long column = u < 0 ? 0 : (u > width - 1 ? width - 1 : u);
    long row = v < 0 ? 0 : (v > height - 1 ? height - 1 : v);
    long at = row * width + column;

    if (indexed) {
      memcpy(out, colours.data + pixels.data[at] * 4, 4);
    } else {
      memcpy(out, pixels.data + at * 4, 4);
    }
  }

  return result;
}

static ERL_NIF_TERM tint(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ErlNifBinary base;
  long first;
  double p[10], threshold;

  if (argc != 4 || !enif_inspect_binary(env, argv[0], &base) || base.size % 4 != 0 ||
      !enif_get_long(env, argv[1], &first) || !get_numbers(env, argv[2], 10, p) ||
      !get_number(env, argv[3], &threshold)) {
    return enif_make_badarg(env);
  }

  ERL_NIF_TERM result;
  unsigned char *out = enif_make_new_binary(env, base.size, &result);
  long count = (long)(base.size / 4);

  for (long i = 0; i < count; i++) {
    const unsigned char *pixel = base.data + i * 4;
    unsigned char *to = out + i * 4;
    double xc = (double)(first + i) + 0.5;
    double w = p[0] + p[1] * xc;

    if (pixel[3] < threshold) {
      memset(to, 0, 4);
      continue;
    }

    to[0] = channel(pixel[0] * (p[2] + p[3] * xc) / w);
    to[1] = channel(pixel[1] * (p[4] + p[5] * xc) / w);
    to[2] = channel(pixel[2] * (p[6] + p[7] * xc) / w);
    to[3] = channel(pixel[3] * (p[8] + p[9] * xc) / w);
  }

  return result;
}

static ERL_NIF_TERM available(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;
  (void)argv;
  return enif_make_atom(env, "true");
}

static ErlNifFunc funcs[] = {{"available?", 0, available, 0},
                             {"texture", 5, texture, 0},
                             {"surface", 3, surface, 0},
                             {"tint", 4, tint, 0}};

ERL_NIF_INIT(Elixir.Cauldron3D.Paint.Spans, funcs, load, NULL, NULL, NULL)
