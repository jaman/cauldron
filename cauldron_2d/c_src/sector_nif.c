#include <erl_nif.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  int width, height;
  unsigned char *pixels;
} frame_t;

typedef struct {
  int width, height;
  unsigned char *pixels;
  unsigned char *mask;
} picture_t;

typedef struct {
  int count, maps;
  picture_t *pictures;
  unsigned char *tables;
} set_t;

static ErlNifResourceType *frame_type;
static ErlNifResourceType *set_type;

static int shimmer(int x, int y) {
  uint32_t hash = (uint32_t)(x * 7 + y) * 2654435761u;
  return ((hash >> 16) & 1) ? 1 : -1;
}

static void frame_free(ErlNifEnv *env, void *object) {
  frame_t *frame = (frame_t *)object;
  (void)env;
  free(frame->pixels);
}

static void set_free(ErlNifEnv *env, void *object) {
  set_t *set = (set_t *)object;
  int index;
  (void)env;

  for (index = 0; index < set->count; index++) {
    free(set->pictures[index].pixels);
    free(set->pictures[index].mask);
  }

  free(set->pictures);
  free(set->tables);
}

static int load(ErlNifEnv *env, void **priv, ERL_NIF_TERM info) {
  ErlNifResourceFlags flags = ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER;
  (void)priv;
  (void)info;
  frame_type = enif_open_resource_type(env, NULL, "cauldron_sector_frame", frame_free, flags, NULL);
  set_type = enif_open_resource_type(env, NULL, "cauldron_sector_set", set_free, flags, NULL);
  return frame_type == NULL || set_type == NULL;
}

static int upgrade(ErlNifEnv *env, void **priv, void **old, ERL_NIF_TERM info) {
  (void)old;
  return load(env, priv, info);
}

static int wrap(int value, int size) {
  int result = value % size;
  return result < 0 ? result + size : result;
}

static int clamp(int value, int low, int high) {
  if (value < low) return low;
  if (value > high) return high;
  return value;
}

static int16_t read_i16(const unsigned char *at) { return (int16_t)(at[0] | (at[1] << 8)); }

static uint16_t read_u16(const unsigned char *at) { return (uint16_t)(at[0] | (at[1] << 8)); }

static int32_t read_i32(const unsigned char *at) {
  return (int32_t)((uint32_t)at[0] | ((uint32_t)at[1] << 8) | ((uint32_t)at[2] << 16) |
                   ((uint32_t)at[3] << 24));
}

static double read_f64(const unsigned char *at) {
  double value;
  memcpy(&value, at, sizeof(double));
  return value;
}

static ERL_NIF_TERM frame_new(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  int width, height;
  frame_t *frame;
  ERL_NIF_TERM term;
  (void)argc;

  if (!enif_get_int(env, argv[0], &width) || !enif_get_int(env, argv[1], &height) || width < 1 ||
      height < 1)
    return enif_make_badarg(env);

  frame = enif_alloc_resource(frame_type, sizeof(frame_t));
  frame->width = width;
  frame->height = height;
  frame->pixels = calloc((size_t)width * (size_t)height, 1);
  term = enif_make_resource(env, frame);
  enif_release_resource(frame);
  return term;
}

static int read_picture(ErlNifEnv *env, ERL_NIF_TERM term, picture_t *out) {
  const ERL_NIF_TERM *field;
  int arity;
  ErlNifBinary pixels, mask;
  size_t size;

  if (!enif_get_tuple(env, term, &arity, &field) || arity != 4) return 0;
  if (!enif_get_int(env, field[0], &out->width) || !enif_get_int(env, field[1], &out->height))
    return 0;
  if (out->width < 1 || out->height < 1) return 0;
  size = (size_t)out->width * (size_t)out->height;
  if (!enif_inspect_binary(env, field[2], &pixels) || pixels.size != size) return 0;

  out->pixels = malloc(size);
  memcpy(out->pixels, pixels.data, size);
  out->mask = NULL;

  if (enif_inspect_binary(env, field[3], &mask) && mask.size == size) {
    out->mask = malloc(size);
    memcpy(out->mask, mask.data, size);
  }

  return 1;
}

static ERL_NIF_TERM set_new(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  unsigned length;
  ERL_NIF_TERM list = argv[0], head;
  ErlNifBinary tables;
  set_t *set;
  ERL_NIF_TERM term;
  int index = 0;
  (void)argc;

  if (!enif_get_list_length(env, list, &length)) return enif_make_badarg(env);
  if (!enif_inspect_binary(env, argv[1], &tables) || tables.size == 0 || tables.size % 256 != 0)
    return enif_make_badarg(env);

  set = enif_alloc_resource(set_type, sizeof(set_t));
  set->count = 0;
  set->maps = (int)(tables.size / 256);
  set->tables = malloc(tables.size);
  memcpy(set->tables, tables.data, tables.size);
  set->pictures = calloc(length > 0 ? length : 1, sizeof(picture_t));

  while (enif_get_list_cell(env, list, &head, &list)) {
    if (!read_picture(env, head, &set->pictures[index])) {
      set->count = index;
      enif_release_resource(set);
      return enif_make_badarg(env);
    }
    index++;
    set->count = index;
  }

  term = enif_make_resource(env, set);
  enif_release_resource(set);
  return term;
}

static int get_frame(ErlNifEnv *env, ERL_NIF_TERM term, frame_t **out) {
  return enif_get_resource(env, term, frame_type, (void **)out);
}

static int get_set(ErlNifEnv *env, ERL_NIF_TERM term, set_t **out) {
  return enif_get_resource(env, term, set_type, (void **)out);
}

static ERL_NIF_TERM fill(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  frame_t *frame;
  int colour;
  (void)argc;

  if (!get_frame(env, argv[0], &frame) || !enif_get_int(env, argv[1], &colour))
    return enif_make_badarg(env);

  memset(frame->pixels, colour & 255, (size_t)frame->width * (size_t)frame->height);
  return argv[0];
}

static void draw_column(frame_t *frame, set_t *set, const unsigned char *record) {
  int x = read_u16(record);
  int y1 = read_i16(record + 2);
  int y2 = read_i16(record + 4);
  int flags = read_u16(record + 6);
  int32_t picture = read_i32(record + 8);
  int column = read_i32(record + 12);
  int light = read_u16(record + 16);
  double v = read_f64(record + 20);
  double step = read_f64(record + 28);
  int masked = flags & 1, shimmering = flags & 2;
  picture_t *pic;
  const unsigned char *source, *mask, *table;
  int y, texel, row, width = frame->width;

  if (x < 0 || x >= frame->width || picture < 0 || picture >= set->count) return;
  pic = &set->pictures[picture];

  if (masked) {
    if (column < 0 || column >= pic->width) return;
  } else {
    column = wrap(column, pic->width);
  }

  if (y1 < 0) {
    v += step * (double)(0 - y1);
    y1 = 0;
  }
  if (y2 > frame->height - 1) y2 = frame->height - 1;
  if (y1 > y2) return;

  source = pic->pixels + (size_t)column * (size_t)pic->height;
  mask = pic->mask ? pic->mask + (size_t)column * (size_t)pic->height : NULL;
  table = set->tables + (size_t)clamp(light, 0, set->maps - 1) * 256;

  for (y = y1; y <= y2; y++, v += step) {
    row = (int)floor(v);

    if (masked) {
      if (row < 0 || row >= pic->height) continue;
      if (mask && !mask[row]) continue;
    } else {
      row = wrap(row, pic->height);
    }

    if (shimmering) {
      int near = clamp(y + shimmer(x, y), 0, frame->height - 1);
      frame->pixels[(size_t)y * width + x] = table[frame->pixels[(size_t)near * width + x]];
    } else {
      texel = source[row];
      frame->pixels[(size_t)y * width + x] = table[texel];
    }
  }
}

static ERL_NIF_TERM columns(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  frame_t *frame;
  set_t *set;
  ErlNifBinary records;
  size_t offset;
  (void)argc;

  if (!get_frame(env, argv[0], &frame) || !get_set(env, argv[1], &set) ||
      !enif_inspect_binary(env, argv[2], &records) || records.size % 36 != 0)
    return enif_make_badarg(env);

  for (offset = 0; offset < records.size; offset += 36) draw_column(frame, set, records.data + offset);

  return argv[0];
}

typedef struct {
  int x1, x2, sky, picture, start, fixed, maps;
  double fade, height, vx, vy, angle, cx, cy, fx, fy, sky_columns, sky_mid, sky_step;
} plane_t;

static int read_plane(ErlNifBinary *params, plane_t *out) {
  const unsigned char *at = params->data;

  if (params->size != 124) return 0;
  out->x1 = read_u16(at);
  out->x2 = read_u16(at + 2);
  out->sky = read_u16(at + 4) & 1;
  out->picture = read_i32(at + 8);
  out->start = read_i32(at + 12);
  out->fixed = read_i32(at + 16);
  out->maps = read_i32(at + 20);
  out->fade = read_f64(at + 28);
  out->height = read_f64(at + 36);
  out->vx = read_f64(at + 44);
  out->vy = read_f64(at + 52);
  out->angle = read_f64(at + 60);
  out->cx = read_f64(at + 68);
  out->cy = read_f64(at + 76);
  out->fx = read_f64(at + 84);
  out->fy = read_f64(at + 92);
  out->sky_columns = read_f64(at + 100);
  out->sky_mid = read_f64(at + 108);
  out->sky_step = read_f64(at + 116);
  return 1;
}

static void sky_column(frame_t *frame, set_t *set, plane_t *plane, picture_t *pic, int x, int top,
                       int bottom) {
  double angle = plane->angle + atan2(plane->cx - ((double)x + 0.5), plane->fx);
  int column = wrap((int)floor(angle * plane->sky_columns), pic->width);
  const unsigned char *source = pic->pixels + (size_t)column * (size_t)pic->height;
  const unsigned char *table =
      set->tables + (size_t)clamp(plane->fixed >= 0 ? plane->fixed : 0, 0, set->maps - 1) * 256;
  int y, row;

  for (y = top; y <= bottom; y++) {
    row = wrap((int)floor(plane->sky_mid + ((double)y + 0.5 - plane->cy) * plane->sky_step),
               pic->height);
    frame->pixels[(size_t)y * frame->width + x] = table[source[row]];
  }
}

static int plane_light(plane_t *plane, double distance, int maps) {
  if (plane->fixed >= 0) return plane->fixed;
  if (distance < 1.0) distance = 1.0;
  return clamp(plane->start - (int)floor(plane->fade / distance), 0, maps - 1);
}

static void flat_column(frame_t *frame, set_t *set, plane_t *plane, picture_t *pic, int x, int top,
                        int bottom) {
  double forward_x = cos(plane->angle), forward_y = sin(plane->angle);
  double right_x = sin(plane->angle), right_y = -cos(plane->angle);
  double across = ((double)x + 0.5 - plane->cx) / plane->fx;
  int y, u, v, light;
  double dy, distance, world_x, world_y;

  for (y = top; y <= bottom; y++) {
    dy = (double)y + 0.5 - plane->cy;
    if (fabs(dy) < 1e-9) continue;
    distance = -plane->height * plane->fy / dy;
    if (distance <= 0.0) continue;
    world_x = plane->vx + forward_x * distance + right_x * distance * across;
    world_y = plane->vy + forward_y * distance + right_y * distance * across;
    u = wrap((int)floor(world_x), pic->width);
    v = wrap((int)floor(-world_y), pic->height);
    light = plane_light(plane, distance, set->maps);
    frame->pixels[(size_t)y * frame->width + x] =
        set->tables[(size_t)clamp(light, 0, set->maps - 1) * 256 +
                    pic->pixels[(size_t)u * pic->height + v]];
  }
}

static ERL_NIF_TERM plane(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  frame_t *frame;
  set_t *set;
  ErlNifBinary params, tops, bottoms;
  plane_t spec;
  picture_t *pic;
  int x, top, bottom, count;
  (void)argc;

  if (!get_frame(env, argv[0], &frame) || !get_set(env, argv[1], &set) ||
      !enif_inspect_binary(env, argv[2], &params) || !enif_inspect_binary(env, argv[3], &tops) ||
      !enif_inspect_binary(env, argv[4], &bottoms) || !read_plane(&params, &spec))
    return enif_make_badarg(env);

  count = spec.x2 - spec.x1 + 1;
  if (count < 1 || tops.size != (size_t)count * 2 || bottoms.size != (size_t)count * 2)
    return enif_make_badarg(env);
  if (spec.picture < 0 || spec.picture >= set->count) return argv[0];
  pic = &set->pictures[spec.picture];

  for (x = spec.x1; x <= spec.x2; x++) {
    if (x < 0 || x >= frame->width) continue;
    top = read_i16(tops.data + (x - spec.x1) * 2);
    bottom = read_i16(bottoms.data + (x - spec.x1) * 2);
    if (top < 0) top = 0;
    if (bottom > frame->height - 1) bottom = frame->height - 1;
    if (top > bottom) continue;

    if (spec.sky)
      sky_column(frame, set, &spec, pic, x, top, bottom);
    else
      flat_column(frame, set, &spec, pic, x, top, bottom);
  }

  return argv[0];
}

static void plot(frame_t *frame, int x, int y, int colour) {
  if (x < 0 || y < 0 || x >= frame->width || y >= frame->height) return;
  frame->pixels[(size_t)y * frame->width + x] = (unsigned char)colour;
}

static void line(frame_t *frame, int x0, int y0, int x1, int y1, int colour) {
  int dx = abs(x1 - x0), dy = -abs(y1 - y0);
  int sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
  int err = dx + dy, e2, guard = 0;

  for (;;) {
    plot(frame, x0, y0, colour);
    if ((x0 == x1 && y0 == y1) || ++guard > 1 << 16) break;
    e2 = 2 * err;
    if (e2 >= dy) {
      err += dy;
      x0 += sx;
    }
    if (e2 <= dx) {
      err += dx;
      y0 += sy;
    }
  }
}

static ERL_NIF_TERM lines(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  frame_t *frame;
  ErlNifBinary records;
  size_t offset;
  const unsigned char *at;
  (void)argc;

  if (!get_frame(env, argv[0], &frame) || !enif_inspect_binary(env, argv[1], &records) ||
      records.size % 10 != 0)
    return enif_make_badarg(env);

  for (offset = 0; offset < records.size; offset += 10) {
    at = records.data + offset;
    line(frame, read_i16(at), read_i16(at + 2), read_i16(at + 4), read_i16(at + 6), at[8]);
  }

  return argv[0];
}

static ERL_NIF_TERM pixels(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  frame_t *frame;
  ERL_NIF_TERM term;
  size_t size;
  (void)argc;

  if (!get_frame(env, argv[0], &frame)) return enif_make_badarg(env);
  size = (size_t)frame->width * (size_t)frame->height;
  memcpy(enif_make_new_binary(env, size, &term), frame->pixels, size);
  return term;
}

static ERL_NIF_TERM rgba(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  frame_t *frame;
  ErlNifBinary palette;
  ERL_NIF_TERM term;
  unsigned char *out;
  size_t index, size;
  (void)argc;

  if (!get_frame(env, argv[0], &frame) || !enif_inspect_binary(env, argv[1], &palette) ||
      palette.size != 768)
    return enif_make_badarg(env);

  size = (size_t)frame->width * (size_t)frame->height;
  out = enif_make_new_binary(env, size * 4, &term);

  for (index = 0; index < size; index++) {
    memcpy(out + index * 4, palette.data + (size_t)frame->pixels[index] * 3, 3);
    out[index * 4 + 3] = 255;
  }

  return term;
}

static ERL_NIF_TERM size(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  frame_t *frame;
  (void)argc;

  if (!get_frame(env, argv[0], &frame)) return enif_make_badarg(env);
  return enif_make_tuple2(env, enif_make_int(env, frame->width), enif_make_int(env, frame->height));
}

static ERL_NIF_TERM available(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;
  (void)argv;
  return enif_make_atom(env, "true");
}

static ErlNifFunc funcs[] = {{"available?", 0, available, 0},
                             {"native_new", 2, frame_new, 0},
                             {"native_set", 2, set_new, ERL_NIF_DIRTY_JOB_CPU_BOUND},
                             {"native_fill", 2, fill, 0},
                             {"native_columns", 3, columns, ERL_NIF_DIRTY_JOB_CPU_BOUND},
                             {"native_plane", 5, plane, ERL_NIF_DIRTY_JOB_CPU_BOUND},
                             {"native_lines", 2, lines, 0},
                             {"native_pixels", 1, pixels, 0},
                             {"native_rgba", 2, rgba, 0},
                             {"native_size", 1, size, 0}};

ERL_NIF_INIT(Elixir.Cauldron2D.Sectors.Frame, funcs, load, NULL, upgrade, NULL)
