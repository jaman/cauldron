#include <erl_nif.h>

#include <cstring>
#include <memory>
#include <string>

#include "render_window.h"
#include "shared_memory.h"
#include "terminal.h"
#include "window.h"

#if defined(__APPLE__)
extern "C" int erl_drv_steal_main_thread(char *name, void **tid, void *(*func)(void *), void *arg, void *opts);
#else
#include <thread>
#endif

namespace cg {

bool launch_window_thread(void *(*loop)(void *)) {
#if defined(__APPLE__)
  void *tid = nullptr;
  char name[] = "cauldron_gpu window";
  return erl_drv_steal_main_thread(name, &tid, loop, nullptr, nullptr) == 0;
#else
  std::thread(loop, nullptr).detach();
  return true;
#endif
}

}

namespace {

ErlNifResourceType *window_type = nullptr;
ErlNifResourceType *handle_type = nullptr;

struct Window {
  cg::RenderWindow view;
  ErlNifPid owner;
};

struct WindowRef {
  Window *window;
};

struct Handle {
  WindowRef *window_ref;
  uint8_t drop_op;
  uint32_t id;
};

ERL_NIF_TERM atom(ErlNifEnv *env, const char *name) {
  ERL_NIF_TERM result;
  return enif_make_existing_atom(env, name, &result, ERL_NIF_UTF8) ? result : enif_make_atom(env, name);
}

ERL_NIF_TERM error_tuple(ErlNifEnv *env, const std::string &reason) {
  ERL_NIF_TERM message;
  unsigned char *bytes = enif_make_new_binary(env, reason.size(), &message);
  std::memcpy(bytes, reason.data(), reason.size());
  return enif_make_tuple2(env, atom(env, "error"), message);
}

std::string binary_string(ErlNifEnv *env, ERL_NIF_TERM term) {
  ErlNifBinary binary;
  if (!enif_inspect_binary(env, term, &binary)) return {};
  return std::string(reinterpret_cast<const char *>(binary.data), binary.size);
}

void send_to_owner(Window *window, const std::function<ERL_NIF_TERM(ErlNifEnv *)> &build) {
  ErlNifEnv *env = enif_alloc_env();
  ERL_NIF_TERM message = enif_make_tuple3(env, atom(env, "cauldron_gpu"), enif_make_uint(env, window->view.id()), build(env));
  enif_send(nullptr, &window->owner, env, message);
  enif_free_env(env);
}

ERL_NIF_TERM key_name(ErlNifEnv *env, SDL_Scancode scancode) {
  std::string name = cg::key_name(scancode);
  if (name.empty()) return enif_make_int(env, scancode);
  return enif_make_atom(env, name.c_str());
}

ERL_NIF_TERM event_term(ErlNifEnv *env, const SDL_Event &event) {
  switch (event.type) {
    case SDL_EVENT_KEY_DOWN:
    case SDL_EVENT_KEY_UP:
      return enif_make_tuple4(env, atom(env, "key"), atom(env, event.type == SDL_EVENT_KEY_DOWN ? "down" : "up"),
                              key_name(env, event.key.scancode), atom(env, event.key.repeat ? "true" : "false"));
    case SDL_EVENT_MOUSE_MOTION:
      return enif_make_tuple5(env, atom(env, "mouse_motion"), enif_make_double(env, event.motion.x),
                              enif_make_double(env, event.motion.y), enif_make_double(env, event.motion.xrel),
                              enif_make_double(env, event.motion.yrel));
    case SDL_EVENT_MOUSE_BUTTON_DOWN:
    case SDL_EVENT_MOUSE_BUTTON_UP:
      return enif_make_tuple5(env, atom(env, "mouse_button"),
                              atom(env, event.type == SDL_EVENT_MOUSE_BUTTON_DOWN ? "down" : "up"),
                              enif_make_uint(env, event.button.button), enif_make_double(env, event.button.x),
                              enif_make_double(env, event.button.y));
    case SDL_EVENT_MOUSE_WHEEL:
      return enif_make_tuple3(env, atom(env, "mouse_wheel"), enif_make_double(env, event.wheel.x),
                              enif_make_double(env, event.wheel.y));
    case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
      return enif_make_tuple3(env, atom(env, "resized"), enif_make_int(env, event.window.data1),
                              enif_make_int(env, event.window.data2));
    case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
      return atom(env, "close_requested");
    case SDL_EVENT_WINDOW_FOCUS_GAINED:
    case SDL_EVENT_WINDOW_FOCUS_LOST:
      return enif_make_tuple2(env, atom(env, "focus"), atom(env, event.type == SDL_EVENT_WINDOW_FOCUS_GAINED ? "true" : "false"));
    default:
      return 0;
  }
}

ERL_NIF_TERM info_map(ErlNifEnv *env, const cg_device_info &info) {
  ERL_NIF_TERM keys[] = {atom(env, "backend"), atom(env, "device"), atom(env, "ray_tracing"), atom(env, "mesh_shaders"),
                         atom(env, "unified_memory"), atom(env, "upscaling"), atom(env, "frame_generation")};
  ERL_NIF_TERM name;
  size_t length = strnlen(info.name, sizeof(info.name));
  std::memcpy(enif_make_new_binary(env, length, &name), info.name, length);
  ERL_NIF_TERM values[] = {atom(env, info.backend), name, atom(env, info.ray_tracing ? "true" : "false"),
                           atom(env, info.mesh_shaders ? "true" : "false"), atom(env, info.unified_memory ? "true" : "false"),
                           atom(env, info.upscaling ? "true" : "false"), atom(env, info.frame_generation ? "true" : "false")};
  ERL_NIF_TERM map;
  enif_make_map_from_arrays(env, keys, values, 7, &map);
  return map;
}

ERL_NIF_TERM nif_open(ErlNifEnv *env, int, const ERL_NIF_TERM argv[]) {
  char backend_name[32];
  int width, height;
  ErlNifPid owner;
  bool windowed = enif_is_identical(argv[6], atom(env, "true"));
  if (!enif_get_atom(env, argv[0], backend_name, sizeof(backend_name), ERL_NIF_UTF8) ||
      !enif_get_int(env, argv[2], &width) || !enif_get_int(env, argv[3], &height) ||
      !enif_get_local_pid(env, argv[5], &owner) || width <= 0 || height <= 0)
    return enif_make_badarg(env);
  const cg_backend *backend = cg::backend_named(backend_name);
  if (!backend) return error_tuple(env, std::string("backend not built: ") + backend_name);

  auto *ref = static_cast<WindowRef *>(enif_alloc_resource(window_type, sizeof(WindowRef)));
  ref->window = new Window();
  Window *window = ref->window;
  window->owner = owner;
  ERL_NIF_TERM term = enif_make_resource(env, ref);
  enif_release_resource(ref);

  cg::OpenRequest request{backend, binary_string(env, argv[4]), binary_string(env, argv[1]), width, height, windowed};
  auto events = [window](const SDL_Event &event) { send_to_owner(window, [&](ErlNifEnv *message_env) { return event_term(message_env, event); }); };
  auto errors = [window](const std::string &message) {
    send_to_owner(window, [&](ErlNifEnv *message_env) {
      ERL_NIF_TERM text;
      std::memcpy(enif_make_new_binary(message_env, message.size(), &text), message.data(), message.size());
      return enif_make_tuple2(message_env, atom(message_env, "error"), text);
    });
  };
  std::string error;
  if (!window->view.open(request, events, errors, error)) return error_tuple(env, error);
  return enif_make_tuple4(env, atom(env, "ok"), term, enif_make_uint(env, window->view.id()), info_map(env, window->view.info()));
}

WindowRef *window_ref(ErlNifEnv *env, ERL_NIF_TERM term) {
  void *resource = nullptr;
  return enif_get_resource(env, term, window_type, &resource) ? static_cast<WindowRef *>(resource) : nullptr;
}

ERL_NIF_TERM nif_submit(ErlNifEnv *env, int, const ERL_NIF_TERM argv[]) {
  WindowRef *ref = window_ref(env, argv[0]);
  if (!ref || !enif_is_binary(env, argv[1])) return enif_make_badarg(env);
  ErlNifEnv *held = enif_alloc_env();
  ErlNifBinary binary;
  enif_inspect_binary(held, enif_make_copy(held, argv[1]), &binary);
  if (!ref->window->view.submit({binary.data, binary.size, cg::now_seconds(), [held] { enif_free_env(held); }}))
    return error_tuple(env, "closed");
  return atom(env, "ok");
}

ERL_NIF_TERM nif_handle(ErlNifEnv *env, int, const ERL_NIF_TERM argv[]) {
  WindowRef *ref = window_ref(env, argv[0]);
  unsigned int drop_op, id;
  if (!ref || !enif_get_uint(env, argv[1], &drop_op) || !enif_get_uint(env, argv[2], &id) || drop_op > 255)
    return enif_make_badarg(env);
  auto *handle = static_cast<Handle *>(enif_alloc_resource(handle_type, sizeof(Handle)));
  enif_keep_resource(ref);
  *handle = {ref, static_cast<uint8_t>(drop_op), id};
  ERL_NIF_TERM term = enif_make_resource(env, handle);
  enif_release_resource(handle);
  return term;
}

ERL_NIF_TERM nif_close(ErlNifEnv *env, int, const ERL_NIF_TERM argv[]) {
  WindowRef *ref = window_ref(env, argv[0]);
  if (!ref) return enif_make_badarg(env);
  ref->window->view.close();
  return atom(env, "ok");
}

ERL_NIF_TERM nif_relative_mouse(ErlNifEnv *env, int, const ERL_NIF_TERM argv[]) {
  WindowRef *ref = window_ref(env, argv[0]);
  if (!ref) return enif_make_badarg(env);
  bool enabled = enif_is_identical(argv[1], atom(env, "true"));
  return ref->window->view.relative_mouse(enabled) ? atom(env, "ok") : error_tuple(env, "closed");
}

ERL_NIF_TERM nif_frames(ErlNifEnv *env, int, const ERL_NIF_TERM argv[]) {
  WindowRef *ref = window_ref(env, argv[0]);
  if (!ref) return enif_make_badarg(env);
  return enif_make_uint64(env, ref->window->view.frames());
}

ERL_NIF_TERM nif_stats(ErlNifEnv *env, int, const ERL_NIF_TERM argv[]) {
  WindowRef *ref = window_ref(env, argv[0]);
  if (!ref) return enif_make_badarg(env);
  cg::FrameStats stats = ref->window->view.stats();
  ERL_NIF_TERM keys[] = {atom(env, "frames"), atom(env, "gpu_ms"), atom(env, "cpu_ms"), atom(env, "refresh_rate"), atom(env, "generating")};
  ERL_NIF_TERM values[] = {enif_make_uint64(env, stats.frames), enif_make_double(env, stats.gpu_seconds * 1000.0),
                           enif_make_double(env, stats.cpu_seconds * 1000.0), enif_make_double(env, stats.refresh_rate),
                           atom(env, stats.generating ? "true" : "false")};
  ERL_NIF_TERM map;
  enif_make_map_from_arrays(env, keys, values, 5, &map);
  return map;
}

ERL_NIF_TERM binary_term(ErlNifEnv *env, const std::string &text) {
  ERL_NIF_TERM term;
  std::memcpy(enif_make_new_binary(env, text.size(), &term), text.data(), text.size());
  return term;
}

ERL_NIF_TERM capture_term(ErlNifEnv *env, const cg::Capture *capture, const std::string &shared_memory) {
  if (!capture || !capture->pixels) return enif_make_tuple2(env, atom(env, "capture"), atom(env, "error"));
  size_t size = size_t(capture->width) * capture->height * 4;
  ERL_NIF_TERM width = enif_make_uint(env, capture->width), height = enif_make_uint(env, capture->height);
  if (shared_memory.empty()) {
    ERL_NIF_TERM pixels;
    std::memcpy(enif_make_new_binary(env, size, &pixels), capture->pixels, size);
    return enif_make_tuple4(env, atom(env, "capture"), width, height, pixels);
  }
  std::string error;
  if (!cg::write_shared_memory(shared_memory, capture->pixels, size, error))
    return enif_make_tuple2(env, atom(env, "capture"), enif_make_tuple2(env, atom(env, "error"), binary_term(env, error)));
  return enif_make_tuple4(env, atom(env, "capture"), width, height,
                          enif_make_tuple2(env, atom(env, "shared_memory"), binary_term(env, shared_memory)));
}

ERL_NIF_TERM nif_capture(ErlNifEnv *env, int, const ERL_NIF_TERM argv[]) {
  WindowRef *ref = window_ref(env, argv[0]);
  ErlNifPid caller;
  if (!ref || !enif_self(env, &caller)) return enif_make_badarg(env);
  SDL_WindowID id = ref->window->view.id();
  bool generated = enif_is_identical(argv[1], atom(env, "true"));
  std::string shared_memory = binary_string(env, argv[2]);
  bool requested = ref->window->view.capture(generated, [caller, id, shared_memory](const cg::Capture *capture) {
    ErlNifEnv *message_env = enif_alloc_env();
    ERL_NIF_TERM message = enif_make_tuple3(message_env, atom(message_env, "cauldron_gpu"), enif_make_uint(message_env, id),
                                            capture_term(message_env, capture, shared_memory));
    enif_send(nullptr, &caller, message_env, message);
    enif_free_env(message_env);
  });
  return requested ? atom(env, "ok") : error_tuple(env, "closed");
}

ERL_NIF_TERM nif_remove_shared_memory(ErlNifEnv *env, int, const ERL_NIF_TERM argv[]) {
  if (!enif_is_binary(env, argv[0])) return enif_make_badarg(env);
  cg::remove_shared_memory(binary_string(env, argv[0]));
  return atom(env, "ok");
}

ERL_NIF_TERM nif_write_shared_memory(ErlNifEnv *env, int, const ERL_NIF_TERM argv[]) {
  ErlNifBinary data;
  if (!enif_is_binary(env, argv[0]) || !enif_inspect_iolist_as_binary(env, argv[1], &data)) return enif_make_badarg(env);
  std::string error;
  if (!cg::write_shared_memory(binary_string(env, argv[0]), data.data, data.size, error)) return error_tuple(env, error);
  return atom(env, "ok");
}

ERL_NIF_TERM nif_terminal_size(ErlNifEnv *env, int, const ERL_NIF_TERM[]) {
  cg::TerminalSize size{};
  if (!cg::terminal_size(size)) return error_tuple(env, "not a terminal");
  ERL_NIF_TERM keys[] = {atom(env, "columns"), atom(env, "rows"), atom(env, "width"), atom(env, "height")};
  ERL_NIF_TERM values[] = {enif_make_uint(env, size.columns), enif_make_uint(env, size.rows), enif_make_uint(env, size.width),
                           enif_make_uint(env, size.height)};
  ERL_NIF_TERM map;
  enif_make_map_from_arrays(env, keys, values, 4, &map);
  return enif_make_tuple2(env, atom(env, "ok"), map);
}

ERL_NIF_TERM nif_resize(ErlNifEnv *env, int, const ERL_NIF_TERM argv[]) {
  WindowRef *ref = window_ref(env, argv[0]);
  unsigned int width, height;
  if (!ref || !enif_get_uint(env, argv[1], &width) || !enif_get_uint(env, argv[2], &height) || width == 0 || height == 0)
    return enif_make_badarg(env);
  std::string error;
  return ref->window->view.resize(width, height, error) ? atom(env, "ok") : error_tuple(env, error);
}

ERL_NIF_TERM nif_backends(ErlNifEnv *env, int, const ERL_NIF_TERM[]) {
  ERL_NIF_TERM list = enif_make_list(env, 0);
#if defined(CG_HAVE_VULKAN)
  list = enif_make_list_cell(env, atom(env, "vulkan"), list);
#endif
#if defined(CG_HAVE_METAL)
  list = enif_make_list_cell(env, atom(env, "metal"), list);
#endif
  return list;
}

void window_destructor(ErlNifEnv *, void *object) {
  auto *ref = static_cast<WindowRef *>(object);
  delete ref->window;
}

void handle_destructor(ErlNifEnv *, void *object) {
  auto *handle = static_cast<Handle *>(object);
  Window *window = handle->window_ref->window;
  auto *bytes = new uint8_t[5];
  bytes[0] = handle->drop_op;
  std::memcpy(bytes + 1, &handle->id, 4);
  window->view.submit({bytes, 5, cg::now_seconds(), [bytes] { delete[] bytes; }});
  enif_release_resource(handle->window_ref);
}

int load(ErlNifEnv *env, void **, ERL_NIF_TERM) {
  auto flags = static_cast<ErlNifResourceFlags>(ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER);
  window_type = enif_open_resource_type(env, nullptr, "cauldron_gpu_window", window_destructor, flags, nullptr);
  handle_type = enif_open_resource_type(env, nullptr, "cauldron_gpu_handle", handle_destructor, flags, nullptr);
  return window_type && handle_type ? 0 : 1;
}

ErlNifFunc functions[] = {
    {"open", 7, nif_open, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"submit", 2, nif_submit, 0},
    {"handle", 3, nif_handle, 0},
    {"close", 1, nif_close, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"relative_mouse", 2, nif_relative_mouse, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"frames", 1, nif_frames, 0},
    {"stats", 1, nif_stats, 0},
    {"capture", 3, nif_capture, 0},
    {"remove_shared_memory", 1, nif_remove_shared_memory, 0},
    {"write_shared_memory", 2, nif_write_shared_memory, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"terminal_size", 0, nif_terminal_size, 0},
    {"resize", 3, nif_resize, 0},
    {"backends", 0, nif_backends, 0},
};

}

ERL_NIF_INIT(Elixir.CauldronGPU.Native, functions, load, nullptr, nullptr, nullptr)
