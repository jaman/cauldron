#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#include "erl_nif.h"
#include "cauldron_native.h"

typedef struct {
    int known;
    int width;
    int height;
    float scale;
    float top;
    float right;
    float bottom;
    float left;
} cn_screen_state;

typedef struct {
    int known;
    int fold;
    int has_angle;
    float angle;
    int has_hinge;
    int x;
    int y;
    int width;
    int height;
    int vertical;
    int separating;
} cn_posture_state;

static pthread_mutex_t subscriber_lock = PTHREAD_MUTEX_INITIALIZER;
static ErlNifPid subscriber;
static int subscribed = 0;
static cn_screen_state screen = {0};
static cn_posture_state posture = {0};
static pthread_mutex_t system_lock = PTHREAD_MUTEX_INITIALIZER;
static ErlNifPid system_watcher;
static int system_watched = 0;
static uint8_t *last_network = NULL;

#define CN_WAITING_LIMIT 64

typedef struct {
    const char *kind;
    uint8_t *json;
    size_t size;
} cn_waiting;

static cn_waiting waiting[CN_WAITING_LIMIT];
static int waiting_count = 0;
static size_t last_network_size = 0;

static ERL_NIF_TERM atom(ErlNifEnv *env, const char *name) {
    ERL_NIF_TERM term;
    if (enif_make_existing_atom(env, name, &term, ERL_NIF_UTF8)) return term;
    return enif_make_atom(env, name);
}

static int current_subscriber(ErlNifPid *to) {
    int has_subscriber;

    pthread_mutex_lock(&subscriber_lock);
    has_subscriber = subscribed;
    *to = subscriber;
    pthread_mutex_unlock(&subscriber_lock);

    return has_subscriber;
}

static void deliver(ErlNifEnv *env, ErlNifPid *to, ERL_NIF_TERM kind, ERL_NIF_TERM payload) {
    ERL_NIF_TERM message = enif_make_tuple3(env, atom(env, "cauldron_native"), kind, payload);
    enif_send(NULL, to, env, message);
}

static ERL_NIF_TERM screen_term(ErlNifEnv *env, cn_screen_state state) {
    ERL_NIF_TERM keys[4] = {atom(env, "width"), atom(env, "height"), atom(env, "scale"), atom(env, "insets")};
    ERL_NIF_TERM insets = enif_make_tuple4(env,
        enif_make_double(env, state.top), enif_make_double(env, state.right),
        enif_make_double(env, state.bottom), enif_make_double(env, state.left));
    ERL_NIF_TERM values[4] = {enif_make_int(env, state.width), enif_make_int(env, state.height),
                              enif_make_double(env, state.scale), insets};
    ERL_NIF_TERM map;
    enif_make_map_from_arrays(env, keys, values, 4, &map);
    return map;
}

void cn_screen(int width, int height, float scale, float top, float right, float bottom, float left) {
    cn_screen_state state = {1, width, height, scale, top, right, bottom, left};
    ErlNifPid to;

    pthread_mutex_lock(&subscriber_lock);
    screen = state;
    pthread_mutex_unlock(&subscriber_lock);

    if (!current_subscriber(&to)) return;
    ErlNifEnv *env = enif_alloc_env();
    deliver(env, &to, atom(env, "screen"), screen_term(env, state));
    enif_free_env(env);
}

static const char *fold_name(int fold) {
    switch (fold) {
        case CN_FOLD_CLOSED: return "closed";
        case CN_FOLD_HALF_OPEN: return "half_open";
        case CN_FOLD_OPEN: return "open";
        default: return "unknown";
    }
}

static ERL_NIF_TERM hinge_term(ErlNifEnv *env, cn_posture_state state) {
    if (!state.has_hinge) return atom(env, "nil");
    ERL_NIF_TERM keys[6] = {atom(env, "x"), atom(env, "y"), atom(env, "width"), atom(env, "height"),
                            atom(env, "vertical"), atom(env, "separating")};
    ERL_NIF_TERM values[6] = {enif_make_int(env, state.x), enif_make_int(env, state.y),
                              enif_make_int(env, state.width), enif_make_int(env, state.height),
                              atom(env, state.vertical ? "true" : "false"),
                              atom(env, state.separating ? "true" : "false")};
    ERL_NIF_TERM map;
    enif_make_map_from_arrays(env, keys, values, 6, &map);
    return map;
}

static ERL_NIF_TERM posture_term(ErlNifEnv *env, cn_posture_state state) {
    ERL_NIF_TERM keys[3] = {atom(env, "fold"), atom(env, "angle"), atom(env, "hinge")};
    ERL_NIF_TERM values[3] = {atom(env, fold_name(state.fold)),
                              state.has_angle ? enif_make_double(env, state.angle) : atom(env, "nil"),
                              hinge_term(env, state)};
    ERL_NIF_TERM map;
    enif_make_map_from_arrays(env, keys, values, 3, &map);
    return map;
}

void cn_posture(int fold, int has_angle, float angle, int has_hinge, int x, int y, int width, int height,
                int vertical, int separating) {
    cn_posture_state state = {1, fold, has_angle, angle, has_hinge, x, y, width, height, vertical, separating};
    ErlNifPid to;

    pthread_mutex_lock(&subscriber_lock);
    posture = state;
    pthread_mutex_unlock(&subscriber_lock);

    if (!current_subscriber(&to)) return;
    ErlNifEnv *env = enif_alloc_env();
    deliver(env, &to, atom(env, "posture"), posture_term(env, state));
    enif_free_env(env);
}

static const char *phase_name(int phase) {
    switch (phase) {
        case CN_TOUCH_BEGAN: return "began";
        case CN_TOUCH_MOVED: return "moved";
        case CN_TOUCH_ENDED: return "ended";
        default: return "cancelled";
    }
}

void cn_touches(const cn_touch *touches, int count) {
    ErlNifPid to;
    if (!current_subscriber(&to)) return;

    ErlNifEnv *env = enif_alloc_env();
    ERL_NIF_TERM list = enif_make_list(env, 0);

    for (int i = count - 1; i >= 0; i--) {
        ERL_NIF_TERM keys[4] = {atom(env, "id"), atom(env, "phase"), atom(env, "x"), atom(env, "y")};
        ERL_NIF_TERM values[4] = {enif_make_int64(env, touches[i].id), atom(env, phase_name(touches[i].phase)),
                                  enif_make_double(env, touches[i].x), enif_make_double(env, touches[i].y)};
        ERL_NIF_TERM touch;
        enif_make_map_from_arrays(env, keys, values, 4, &touch);
        list = enif_make_list_cell(env, touch, list);
    }

    deliver(env, &to, atom(env, "touches"), list);
    enif_free_env(env);
}

void cn_lifecycle(int state) {
    ErlNifPid to;
    if (!current_subscriber(&to)) return;

    ErlNifEnv *env = enif_alloc_env();
    const char *name = state == CN_LIFECYCLE_ACTIVE ? "active"
                     : state == CN_LIFECYCLE_INACTIVE ? "inactive" : "background";
    deliver(env, &to, atom(env, "lifecycle"), atom(env, name));
    enif_free_env(env);
}

void cn_back(void) {
    ErlNifPid to;
    if (!current_subscriber(&to)) return;

    ErlNifEnv *env = enif_alloc_env();
    deliver(env, &to, atom(env, "back"), atom(env, "pressed"));
    enif_free_env(env);
}

static void deliver_pad(ErlNifPid *to, ErlNifEnv *env, int count, ERL_NIF_TERM keys[], ERL_NIF_TERM values[]) {
    ERL_NIF_TERM event;
    enif_make_map_from_arrays(env, keys, values, count, &event);
    deliver(env, to, atom(env, "pad"), event);
}

void cn_pad_connected(int device, const char *name) {
    ErlNifPid to;
    if (!current_subscriber(&to)) return;

    ErlNifEnv *env = enif_alloc_env();
    ErlNifBinary text;
    enif_alloc_binary(strlen(name), &text);
    memcpy(text.data, name, text.size);

    ERL_NIF_TERM keys[3] = {atom(env, "type"), atom(env, "device"), atom(env, "name")};
    ERL_NIF_TERM values[3] = {atom(env, "connected"), enif_make_int(env, device), enif_make_binary(env, &text)};
    deliver_pad(&to, env, 3, keys, values);
    enif_free_env(env);
}

void cn_pad_disconnected(int device) {
    ErlNifPid to;
    if (!current_subscriber(&to)) return;

    ErlNifEnv *env = enif_alloc_env();
    ERL_NIF_TERM keys[2] = {atom(env, "type"), atom(env, "device")};
    ERL_NIF_TERM values[2] = {atom(env, "disconnected"), enif_make_int(env, device)};
    deliver_pad(&to, env, 2, keys, values);
    enif_free_env(env);
}

void cn_pad_button(int device, const char *button, int pressed) {
    ErlNifPid to;
    if (!current_subscriber(&to)) return;

    ErlNifEnv *env = enif_alloc_env();
    ERL_NIF_TERM keys[4] = {atom(env, "type"), atom(env, "device"), atom(env, "button"), atom(env, "pressed")};
    ERL_NIF_TERM values[4] = {atom(env, "button"), enif_make_int(env, device), atom(env, button),
                              atom(env, pressed ? "true" : "false")};
    deliver_pad(&to, env, 4, keys, values);
    enif_free_env(env);
}

void cn_pad_axis(int device, const char *axis, float value) {
    ErlNifPid to;
    if (!current_subscriber(&to)) return;

    ErlNifEnv *env = enif_alloc_env();
    ERL_NIF_TERM keys[4] = {atom(env, "type"), atom(env, "device"), atom(env, "axis"), atom(env, "value")};
    ERL_NIF_TERM values[4] = {atom(env, "axis"), enif_make_int(env, device), atom(env, axis),
                              enif_make_double(env, value)};
    deliver_pad(&to, env, 4, keys, values);
    enif_free_env(env);
}

static void deliver_text(const char *kind, const uint8_t *json, size_t size) {
    ErlNifPid to;
    if (!current_subscriber(&to)) return;

    ErlNifEnv *env = enif_alloc_env();
    ERL_NIF_TERM text;
    unsigned char *bytes = enif_make_new_binary(env, size, &text);
    memcpy(bytes, json, size);
    deliver(env, &to, atom(env, kind), text);
    enif_free_env(env);
}

void cn_ui_event(const uint8_t *json, size_t size) { deliver_text("ui", json, size); }

static int keep_waiting(const char *kind, const uint8_t *json, size_t size) {
    int kept = 0;
    pthread_mutex_lock(&subscriber_lock);
    if (!subscribed && waiting_count < CN_WAITING_LIMIT) {
        uint8_t *copy = malloc(size);
        if (copy != NULL) {
            memcpy(copy, json, size);
            waiting[waiting_count].kind = kind;
            waiting[waiting_count].json = copy;
            waiting[waiting_count].size = size;
            waiting_count++;
            kept = 1;
        }
    }
    pthread_mutex_unlock(&subscriber_lock);
    return kept;
}

void cn_result(const uint8_t *json, size_t size) {
    if (keep_waiting("result", json, size)) return;
    deliver_text("result", json, size);
}

void cn_background(void) {
    ErlNifPid to;
    if (keep_waiting("background", (const uint8_t *)"refresh", 7)) return;
    if (!current_subscriber(&to)) return;

    ErlNifEnv *env = enif_alloc_env();
    deliver(env, &to, atom(env, "background"), atom(env, "refresh"));
    enif_free_env(env);
}

void cn_url(const uint8_t *url, size_t size) {
    if (keep_waiting("url", url, size)) return;
    deliver_text("url", url, size);
}

static void hand_over_waiting(ErlNifEnv *caller, ErlNifPid *to, cn_waiting *kept, int count) {
    for (int index = 0; index < count; index++) {
        ErlNifEnv *env = enif_alloc_env();
        ERL_NIF_TERM text;
        unsigned char *bytes = enif_make_new_binary(env, kept[index].size, &text);
        memcpy(bytes, kept[index].json, kept[index].size);
        if (strcmp(kept[index].kind, "background") == 0) text = atom(env, "refresh");
        ERL_NIF_TERM message = enif_make_tuple3(env, atom(env, "cauldron_native"), atom(env, kept[index].kind), text);
        enif_send(caller, to, env, message);
        enif_free_env(env);
        free(kept[index].json);
    }
}

static void send_network(ErlNifEnv *caller, ErlNifPid *to, const uint8_t *json, size_t size) {
    ErlNifEnv *env = enif_alloc_env();
    ERL_NIF_TERM text;
    unsigned char *bytes = enif_make_new_binary(env, size, &text);
    memcpy(bytes, json, size);
    ERL_NIF_TERM message = enif_make_tuple3(env, atom(env, "cauldron_native"), atom(env, "network"), text);
    enif_send(caller, to, env, message);
    enif_free_env(env);
}

void cn_network(const uint8_t *json, size_t size) {
    ErlNifPid to;
    int watched;
    uint8_t *copy = malloc(size);
    if (copy == NULL) return;
    memcpy(copy, json, size);

    pthread_mutex_lock(&system_lock);
    free(last_network);
    last_network = copy;
    last_network_size = size;
    watched = system_watched;
    to = system_watcher;
    pthread_mutex_unlock(&system_lock);

    if (watched) send_network(NULL, &to, json, size);
}

static ERL_NIF_TERM watch_system(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifPid pid;

    if (!enif_get_local_pid(env, argv[0], &pid)) return enif_make_badarg(env);

    pthread_mutex_lock(&system_lock);
    system_watcher = pid;
    system_watched = 1;
    if (last_network != NULL) send_network(env, &pid, last_network, last_network_size);
    pthread_mutex_unlock(&system_lock);

    return atom(env, "ok");
}

static ERL_NIF_TERM request(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary json;

    if (!enif_inspect_binary(env, argv[0], &json)) return enif_make_badarg(env);

    cn_platform_request(json.data, json.size);
    return atom(env, "ok");
}

static ERL_NIF_TERM ui(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary patch;

    if (!enif_inspect_binary(env, argv[0], &patch)) return enif_make_badarg(env);

    cn_platform_ui(patch.data, patch.size);
    return atom(env, "ok");
}

static ERL_NIF_TERM quit(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    cn_platform_quit();
    return atom(env, "ok");
}

static ERL_NIF_TERM gpu_surface(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    void *surface = cn_platform_gpu_surface();
    if (surface == NULL) return enif_make_tuple2(env, atom(env, "error"), atom(env, "unavailable"));
    return enif_make_tuple2(env, atom(env, "ok"), enif_make_uint64(env, (ErlNifUInt64)(uintptr_t)surface));
}

static ERL_NIF_TERM hide_gpu_surface(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    cn_platform_hide_gpu_surface();
    return atom(env, "ok");
}

static ERL_NIF_TERM loaded(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    return atom(env, "true");
}

static ERL_NIF_TERM subscribe(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifPid pid;
    cn_screen_state state;
    cn_posture_state posture_now;

    if (!enif_get_local_pid(env, argv[0], &pid)) return enif_make_badarg(env);

    cn_waiting kept[CN_WAITING_LIMIT];
    int kept_count;

    pthread_mutex_lock(&subscriber_lock);
    subscriber = pid;
    subscribed = 1;
    state = screen;
    posture_now = posture;
    kept_count = waiting_count;
    memcpy(kept, waiting, sizeof(cn_waiting) * (size_t)waiting_count);
    waiting_count = 0;
    pthread_mutex_unlock(&subscriber_lock);

    if (state.known) {
        ErlNifEnv *message_env = enif_alloc_env();
        ERL_NIF_TERM message = enif_make_tuple3(message_env, atom(message_env, "cauldron_native"),
                                                atom(message_env, "screen"), screen_term(message_env, state));
        enif_send(env, &pid, message_env, message);
        enif_free_env(message_env);
    }

    if (posture_now.known) {
        ErlNifEnv *message_env = enif_alloc_env();
        ERL_NIF_TERM message = enif_make_tuple3(message_env, atom(message_env, "cauldron_native"),
                                                atom(message_env, "posture"), posture_term(message_env, posture_now));
        enif_send(env, &pid, message_env, message);
        enif_free_env(message_env);
    }

    hand_over_waiting(env, &pid, kept, kept_count);
    return atom(env, "ok");
}

static ERL_NIF_TERM present(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    int width, height;
    ErlNifBinary rgba;

    if (!enif_get_int(env, argv[0], &width) || !enif_get_int(env, argv[1], &height) ||
        !enif_inspect_binary(env, argv[2], &rgba) || width <= 0 || height <= 0 ||
        rgba.size != (size_t)width * (size_t)height * 4)
        return enif_make_badarg(env);

    cn_platform_present(rgba.data, width, height);
    return atom(env, "ok");
}

static ERL_NIF_TERM overlay(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary packed;

    if (!enif_inspect_binary(env, argv[0], &packed)) return enif_make_badarg(env);

    cn_platform_overlay(packed.data, packed.size);
    return atom(env, "ok");
}

static ERL_NIF_TERM current_screen(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    cn_screen_state state;

    pthread_mutex_lock(&subscriber_lock);
    state = screen;
    pthread_mutex_unlock(&subscriber_lock);

    return state.known ? screen_term(env, state) : atom(env, "nil");
}

static ERL_NIF_TERM current_posture(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    cn_posture_state state;

    pthread_mutex_lock(&subscriber_lock);
    state = posture;
    pthread_mutex_unlock(&subscriber_lock);

    return state.known ? posture_term(env, state) : atom(env, "nil");
}

static ErlNifFunc funcs[] = {
    {"loaded", 0, loaded, 0},
    {"subscribe", 1, subscribe, 0},
    {"present", 3, present, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"overlay", 1, overlay, 0},
    {"screen", 0, current_screen, 0},
    {"posture", 0, current_posture, 0},
    {"quit", 0, quit, 0},
    {"gpu_surface", 0, gpu_surface, 0},
    {"hide_gpu_surface", 0, hide_gpu_surface, 0},
    {"ui", 1, ui, 0},
    {"request", 1, request, 0},
    {"watch_system", 1, watch_system, 0}
};

ERL_NIF_INIT(Elixir.CauldronNative.Native, funcs, NULL, NULL, NULL, NULL)
