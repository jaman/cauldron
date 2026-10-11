#include <erl_nif.h>
#include <math.h>
#include <stdint.h>
#include <string.h>

static ERL_NIF_TERM available(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;
  (void)argv;
  return enif_make_atom(env, "true");
}

static ERL_NIF_TERM over(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ErlNifBinary base, top;

  if (argc != 2) {
    return enif_make_badarg(env);
  }

  if (!enif_inspect_binary(env, argv[0], &base) ||
      !enif_inspect_binary(env, argv[1], &top)) {
    return enif_make_badarg(env);
  }

  if (base.size != top.size || base.size % 4 != 0) {
    return enif_make_badarg(env);
  }

  ERL_NIF_TERM result;
  unsigned char *out = enif_make_new_binary(env, base.size, &result);

  for (size_t i = 0; i < base.size; i += 4) {
    unsigned int top_a = top.data[i + 3];

    if (top_a == 0) {
      memcpy(out + i, base.data + i, 4);
      continue;
    }

    if (top_a == 255) {
      memcpy(out + i, top.data + i, 4);
      continue;
    }

    double top_alpha = top_a / 255.0;
    double base_alpha = base.data[i + 3] / 255.0 * (1.0 - top_alpha);
    double alpha = top_alpha + base_alpha;

    for (int channel = 0; channel < 3; channel++) {
      double mixed = (top.data[i + channel] * top_alpha +
                      base.data[i + channel] * base_alpha) / alpha;
      out[i + channel] = (unsigned char)(mixed + 0.5);
    }

    out[i + 3] = (unsigned char)(alpha * 255.0 + 0.5);
  }

  return result;
}

typedef struct {
  double x, y, origin_x, origin_y, scale_x, scale_y, cos, sin, red, green, blue, alpha;
  int width, height, mode;
} stamp_t;

static void corner(const stamp_t *s, double u, double v, double *cx, double *cy) {
  double dx = (u - s->origin_x) * s->scale_x;
  double dy = (v - s->origin_y) * s->scale_y;
  *cx = s->x + dx * s->cos + dy * s->sin;
  *cy = s->y - dx * s->sin + dy * s->cos;
}

static int clamp_index(double value, int low, int high) {
  if (!(value > low)) {
    return low;
  }

  if (value >= high) {
    return high;
  }

  return (int)value;
}

static int placed(const stamp_t *s) {
  return isfinite(s->x) && isfinite(s->y) && isfinite(s->origin_x) && isfinite(s->origin_y) &&
         isfinite(s->scale_x) && isfinite(s->scale_y) && isfinite(s->cos) && isfinite(s->sin);
}

static int covered(const stamp_t *s, int canvas_width, int first, int last, int *left, int *top,
                   int *right, int *bottom) {
  if (!placed(s) || s->scale_x == 0.0 || s->scale_y == 0.0 || s->alpha <= 0.0) {
    return 0;
  }

  double us[4] = {0.0, (double)s->width, 0.0, (double)s->width};
  double vs[4] = {0.0, 0.0, (double)s->height, (double)s->height};
  double min_x = 0, max_x = 0, min_y = 0, max_y = 0;

  for (int i = 0; i < 4; i++) {
    double cx, cy;
    corner(s, us[i], vs[i], &cx, &cy);
    if (i == 0 || cx < min_x) min_x = cx;
    if (i == 0 || cx > max_x) max_x = cx;
    if (i == 0 || cy < min_y) min_y = cy;
    if (i == 0 || cy > max_y) max_y = cy;
  }

  double l = floor(min_x), r = ceil(max_x), t = floor(min_y), b = ceil(max_y);

  if (isnan(l) || isnan(r) || isnan(t) || isnan(b)) {
    return 0;
  }

  *left = clamp_index(l, 0, canvas_width);
  *right = clamp_index(r, 0, canvas_width);
  *top = clamp_index(t, first, last);
  *bottom = clamp_index(b, first, last);

  return *left < *right && *top < *bottom;
}

static unsigned char byte_of(double value) {
  double rounded = value + 0.5;
  return (unsigned char)(rounded < 0.0 ? 0.0 : (rounded > 255.0 ? 255.0 : rounded));
}

static void lay_gamemaker(unsigned char *base, const unsigned char *top, const stamp_t *s,
                          double top_alpha) {
  double blends[3] = {s->red, s->green, s->blue};
  double base_alpha = base[3] / 255.0;
  int kind = s->mode - 10;

  for (int channel = 0; channel < 3; channel++) {
    double colour = top[channel] / 255.0 * blends[channel];
    double beneath = base[channel] / 255.0;
    double result = kind == 2   ? beneath * (1.0 - colour)
                    : kind == 1 ? colour * top_alpha + beneath
                                : colour * top_alpha + beneath * (1.0 - top_alpha);
    base[channel] = byte_of(result * 255.0);
  }

  double alpha = kind == 2   ? base_alpha * (1.0 - top_alpha)
                 : kind == 1 ? top_alpha * top_alpha + base_alpha
                             : top_alpha * top_alpha + base_alpha * (1.0 - top_alpha);
  base[3] = byte_of(alpha * 255.0);
}

static void lay(unsigned char *base, const unsigned char *top, const stamp_t *s) {
  double top_alpha = top[3] * s->alpha / 255.0;

  if (s->mode >= 10) {
    lay_gamemaker(base, top, s, top_alpha);
    return;
  }

  if (top_alpha <= 0.0) {
    return;
  }

  double blends[3] = {s->red, s->green, s->blue};

  if (s->mode == 2) {
    for (int channel = 0; channel < 3; channel++) {
      double kept = base[channel] * (1.0 - top[channel] / 255.0 * blends[channel] * top_alpha) + 0.5;
      base[channel] = (unsigned char)(kept < 0.0 ? 0.0 : kept);
    }
    return;
  }

  if (s->mode == 1) {
    for (int channel = 0; channel < 3; channel++) {
      double sum = base[channel] + top[channel] * blends[channel] * top_alpha + 0.5;
      base[channel] = (unsigned char)(sum > 255.0 ? 255.0 : sum);
    }

    double coverage = base[3] + top_alpha * 255.0 + 0.5;
    base[3] = (unsigned char)(coverage > 255.0 ? 255.0 : coverage);
    return;
  }

  double base_alpha = base[3] / 255.0 * (1.0 - top_alpha);
  double alpha = top_alpha + base_alpha;

  for (int channel = 0; channel < 3; channel++) {
    double above = top[channel] * blends[channel];
    base[channel] =
        (unsigned char)((above * top_alpha + base[channel] * base_alpha) / alpha + 0.5);
  }

  base[3] = (unsigned char)(alpha * 255.0 + 0.5);
}

static int whole_pixels(const stamp_t *s) {
  return s->cos == 1.0 && s->sin == 0.0 && s->scale_x == 1.0 && s->scale_y == 1.0 &&
         s->x == floor(s->x) && s->y == floor(s->y) && s->origin_x == floor(s->origin_x) &&
         s->origin_y == floor(s->origin_y);
}

static void draw_rows(unsigned char *band, int canvas_width, int first, int last,
                      const unsigned char *picture, const stamp_t *s) {
  int left, top, right, bottom;

  if (!covered(s, canvas_width, first, last, &left, &top, &right, &bottom)) {
    return;
  }

  if (whole_pixels(s)) {
    int shift_x = (int)(s->x - s->origin_x);
    int shift_y = (int)(s->y - s->origin_y);

    for (int row = top; row < bottom; row++) {
      const unsigned char *source = picture + ((size_t)(row - shift_y) * s->width) * 4;
      unsigned char *line = band + (size_t)(row - first) * canvas_width * 4;

      for (int column = left; column < right; column++) {
        lay(line + (size_t)column * 4, source + (size_t)(column - shift_x) * 4, s);
      }
    }

    return;
  }

  for (int row = top; row < bottom; row++) {
    double ry = row + 0.5 - s->y;
    unsigned char *line = band + (size_t)(row - first) * canvas_width * 4;

    for (int column = left; column < right; column++) {
      double rx = column + 0.5 - s->x;
      double u = (rx * s->cos - ry * s->sin) / s->scale_x + s->origin_x;
      double v = (rx * s->sin + ry * s->cos) / s->scale_y + s->origin_y;

      if (u >= 0.0 && u < s->width && v >= 0.0 && v < s->height) {
        size_t source = ((size_t)floor(v) * s->width + (size_t)floor(u)) * 4;
        lay(line + (size_t)column * 4, picture + source, s);
      }
    }
  }
}

static double unit(double value) {
  if (!(value > 0.0)) {
    return 0.0;
  }

  return value > 1.0 ? 1.0 : value;
}

static int sized(size_t size, int width, int height) {
  if (width <= 0 || height <= 0 || size % 4 != 0) {
    return 0;
  }

  size_t pixels = size / 4;
  return pixels % (size_t)width == 0 && pixels / (size_t)width == (size_t)height;
}

static int read_stamp(ErlNifEnv *env, ERL_NIF_TERM transform_term, int width, int height,
                      stamp_t *s) {
  ErlNifBinary transform;

  if (!enif_inspect_binary(env, transform_term, &transform) ||
      transform.size != 13 * sizeof(double)) {
    return 0;
  }

  double values[13];
  memcpy(values, transform.data, sizeof(values));
  s->x = values[0];
  s->y = values[1];
  s->origin_x = values[2];
  s->origin_y = values[3];
  s->scale_x = values[4];
  s->scale_y = values[5];
  s->cos = values[6];
  s->sin = values[7];
  s->red = unit(values[8]);
  s->green = unit(values[9]);
  s->blue = unit(values[10]);
  s->alpha = unit(values[11]);
  s->mode = (int)values[12];
  s->width = width;
  s->height = height;
  return 1;
}

static ERL_NIF_TERM draw(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ErlNifBinary canvas, picture;
  int canvas_width, canvas_height, width, height;
  stamp_t s;

  if (argc != 7 || !enif_inspect_binary(env, argv[0], &canvas) ||
      !enif_get_int(env, argv[1], &canvas_width) || !enif_get_int(env, argv[2], &canvas_height) ||
      !enif_inspect_binary(env, argv[3], &picture) || !enif_get_int(env, argv[4], &width) ||
      !enif_get_int(env, argv[5], &height) || !read_stamp(env, argv[6], width, height, &s)) {
    return enif_make_badarg(env);
  }

  if (!sized(canvas.size, canvas_width, canvas_height) || !sized(picture.size, width, height)) {
    return enif_make_badarg(env);
  }

  ERL_NIF_TERM result;
  unsigned char *out = enif_make_new_binary(env, canvas.size, &result);
  memcpy(out, canvas.data, canvas.size);
  draw_rows(out, canvas_width, 0, canvas_height, picture.data, &s);
  return result;
}

static ERL_NIF_TERM render_band(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ErlNifBinary background;
  int width, first, last;

  if (argc != 5 || !enif_get_int(env, argv[0], &width) || !enif_get_int(env, argv[1], &first) ||
      !enif_get_int(env, argv[2], &last) || !enif_inspect_binary(env, argv[3], &background) ||
      width <= 0 || first < 0 || last < first || !enif_is_list(env, argv[4]) ||
      (size_t)(last - first) > SIZE_MAX / 4 / (size_t)width) {
    return enif_make_badarg(env);
  }

  size_t size = (size_t)width * (last - first) * 4;

  if (background.size != 4 && background.size != size) {
    return enif_make_badarg(env);
  }

  ERL_NIF_TERM result;
  unsigned char *band = enif_make_new_binary(env, size, &result);

  if (background.size == size) {
    memcpy(band, background.data, size);
  } else {
    for (size_t at = 0; at < size; at += 4) {
      memcpy(band + at, background.data, 4);
    }
  }

  ERL_NIF_TERM items = argv[4], item;

  while (enif_get_list_cell(env, items, &item, &items)) {
    const ERL_NIF_TERM *fields;
    int arity, picture_width, picture_height;
    ErlNifBinary picture;
    stamp_t s;

    if (!enif_get_tuple(env, item, &arity, &fields) || arity != 4 ||
        !enif_inspect_binary(env, fields[0], &picture) ||
        !enif_get_int(env, fields[1], &picture_width) ||
        !enif_get_int(env, fields[2], &picture_height) ||
        !sized(picture.size, picture_width, picture_height) ||
        !read_stamp(env, fields[3], picture_width, picture_height, &s)) {
      return enif_make_badarg(env);
    }

    draw_rows(band, width, first, last, picture.data, &s);
  }

  return result;
}

static ErlNifFunc funcs[] = {{"available?", 0, available, 0},
                             {"over", 2, over, ERL_NIF_DIRTY_JOB_CPU_BOUND},
                             {"draw", 7, draw, ERL_NIF_DIRTY_JOB_CPU_BOUND},
                             {"render_band", 5, render_band, ERL_NIF_DIRTY_JOB_CPU_BOUND}};

ERL_NIF_INIT(Elixir.Cauldron2D.Blend, funcs, NULL, NULL, NULL, NULL)
