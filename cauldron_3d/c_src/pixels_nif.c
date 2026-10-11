#include <erl_nif.h>
#include <stdint.h>
#include <string.h>

static ERL_NIF_TERM lay(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ErlNifBinary under, above;

  if (argc != 2 || !enif_inspect_binary(env, argv[0], &under) ||
      !enif_inspect_binary(env, argv[1], &above) || under.size != above.size ||
      under.size % 4 != 0) {
    return enif_make_badarg(env);
  }

  ERL_NIF_TERM result;
  unsigned char *out = enif_make_new_binary(env, under.size, &result);

  for (size_t i = 0; i < under.size; i += 4) {
    const unsigned char *u = under.data + i;
    const unsigned char *o = above.data + i;
    unsigned int a = o[3];

    if (a == 255) {
      out[i] = o[0];
      out[i + 1] = o[1];
      out[i + 2] = o[2];
      out[i + 3] = 255;
    } else if (a == 0) {
      memcpy(out + i, u, 4);
    } else {
      out[i] = (unsigned char)((o[0] * a + u[0] * (255 - a)) / 255);
      out[i + 1] = (unsigned char)((o[1] * a + u[1] * (255 - a)) / 255);
      out[i + 2] = (unsigned char)((o[2] * a + u[2] * (255 - a)) / 255);
      out[i + 3] = u[3];
    }
  }

  return result;
}

static ERL_NIF_TERM through(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ErlNifBinary pixels, table;

  if (argc != 2 || !enif_inspect_binary(env, argv[0], &pixels) ||
      !enif_inspect_binary(env, argv[1], &table) || pixels.size % 4 != 0 || table.size != 256) {
    return enif_make_badarg(env);
  }

  ERL_NIF_TERM result;
  unsigned char *out = enif_make_new_binary(env, pixels.size, &result);

  for (size_t i = 0; i < pixels.size; i += 4) {
    out[i] = table.data[pixels.data[i]];
    out[i + 1] = table.data[pixels.data[i + 1]];
    out[i + 2] = table.data[pixels.data[i + 2]];
    out[i + 3] = pixels.data[i + 3];
  }

  return result;
}

static ERL_NIF_TERM available(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;
  (void)argv;
  return enif_make_atom(env, "true");
}

static ErlNifFunc funcs[] = {{"available?", 0, available, 0},
                             {"lay", 2, lay, ERL_NIF_DIRTY_JOB_CPU_BOUND},
                             {"through", 2, through, ERL_NIF_DIRTY_JOB_CPU_BOUND}};

ERL_NIF_INIT(Elixir.Cauldron3D.Frame.Pixels, funcs, NULL, NULL, NULL, NULL)
