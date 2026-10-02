#include <erl_nif.h>
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

static ErlNifFunc funcs[] = {{"available?", 0, available, 0},
                             {"over", 2, over, ERL_NIF_DIRTY_JOB_CPU_BOUND}};

ERL_NIF_INIT(Elixir.Cauldron2D.Blend, funcs, NULL, NULL, NULL, NULL)
