#include <android/log.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <jni.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include "cauldron_native.h"

void erl_start(int argc, char **argv);

static JavaVM *java_vm;
static jclass activity_class;
static jmethodID overlay_method;
static jmethodID quit_method;
static jmethodID show_gpu_method;
static jmethodID ui_method;
static jmethodID request_method;

static pthread_mutex_t window_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t gpu_released = PTHREAD_COND_INITIALIZER;
static ANativeWindow *window;
static ANativeWindow *gpu_window;
static int gpu_wanted;
static int gpu_handed;
static int window_width;
static int window_height;
static uint8_t *last_frame;
static int last_width;
static int last_height;

static char **start_arguments;
static int start_count;

JNIEXPORT jint JNI_OnLoad(JavaVM *vm, void *reserved) {
    JNIEnv *env;
    java_vm = vm;
    if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;
    jclass found = (*env)->FindClass(env, "cauldron/app/CauldronActivity");
    activity_class = (*env)->NewGlobalRef(env, found);
    overlay_method = (*env)->GetStaticMethodID(env, activity_class, "overlay", "([B)V");
    quit_method = (*env)->GetStaticMethodID(env, activity_class, "quit", "()V");
    show_gpu_method = (*env)->GetStaticMethodID(env, activity_class, "showGpu", "(Z)V");
    ui_method = (*env)->GetStaticMethodID(env, activity_class, "ui", "([B)V");
    request_method = (*env)->GetStaticMethodID(env, activity_class, "request", "([B)V");
    return JNI_VERSION_1_6;
}

static void make_folder(const char *path) {
    mkdir(path, 0700);
}

static void set_folder(const char *name, const char *data, const char *folder) {
    char path[4096];
    snprintf(path, sizeof(path), "%s/%s", data, folder);
    make_folder(path);
    setenv(name, path, 1);
}

static void expand(char *text, size_t size, const char *marker, const char *value) {
    char *found = strstr(text, marker);
    if (!found) return;
    char rest[8192];
    snprintf(rest, sizeof(rest), "%s", found + strlen(marker));
    snprintf(found, size - (size_t)(found - text), "%s%s", value, rest);
}

static void release_environment(const char *root, const char *data) {
    char path[4096];
    snprintf(path, sizeof(path), "%s/releases/env", root);
    FILE *file = fopen(path, "r");
    if (!file) return;

    char line[8192];
    while (fgets(line, sizeof(line), file)) {
        line[strcspn(line, "\n")] = 0;
        char *equals = strchr(line, '=');
        if (!equals) continue;
        *equals = 0;
        char value[8192];
        snprintf(value, sizeof(value), "%s", equals + 1);
        expand(value, sizeof(value), "$ROOT", root);
        expand(value, sizeof(value), "$HOME", data);
        setenv(line, value, 1);
    }
    fclose(file);
}

static void *forward_output(void *pipe_end) {
    FILE *output = fdopen((int)(intptr_t)pipe_end, "r");
    char line[4096];
    while (fgets(line, sizeof(line), output)) {
        line[strcspn(line, "\n")] = 0;
        __android_log_write(ANDROID_LOG_INFO, "cauldron", line);
    }
    return NULL;
}

static void send_output_to_logcat(void) {
    int ends[2];
    if (pipe(ends) != 0) return;
    dup2(ends[1], STDOUT_FILENO);
    dup2(ends[1], STDERR_FILENO);
    close(ends[1]);
    setvbuf(stdout, NULL, _IOLBF, 0);
    pthread_t thread;
    pthread_create(&thread, NULL, forward_output, (void *)(intptr_t)ends[0]);
    pthread_detach(thread);
}

static void read_arguments(const char *root, const char *data) {
    char path[4096];
    snprintf(path, sizeof(path), "%s/releases/start_args", root);
    FILE *file = fopen(path, "r");
    if (!file) abort();

    start_arguments = calloc(256, sizeof(char *));
    start_arguments[start_count++] = strdup("beam");

    char line[8192];
    while (fgets(line, sizeof(line), file) && start_count < 255) {
        line[strcspn(line, "\n")] = 0;
        if (!line[0]) continue;
        expand(line, sizeof(line), "$ROOT", root);
        expand(line, sizeof(line), "$HOME", data);
        start_arguments[start_count++] = strdup(line);
    }
    fclose(file);
}

static void *run_beam(void *unused) {
    erl_start(start_count, start_arguments);
    return NULL;
}

JNIEXPORT void JNICALL Java_cauldron_app_CauldronActivity_start(JNIEnv *env, jclass type, jstring root_text, jstring data_text) {
    const char *root = (*env)->GetStringUTFChars(env, root_text, NULL);
    const char *data = (*env)->GetStringUTFChars(env, data_text, NULL);
    char path[4096];

    setenv("HOME", data, 1);
    setenv("CAULDRON_NATIVE_DATA", data, 1);
    set_folder("XDG_CONFIG_HOME", data, "config");
    set_folder("XDG_DATA_HOME", data, "data");
    set_folder("XDG_STATE_HOME", data, "state");
    set_folder("XDG_CACHE_HOME", data, "cache");
    set_folder("TMPDIR", data, "tmp");
    snprintf(path, sizeof(path), "%s/bin", root);
    setenv("BINDIR", path, 1);
    setenv("ROOTDIR", root, 1);
    setenv("EMU", "beam", 1);
    setenv("PROGNAME", "erl", 1);
    setenv("LANG", "en_US.UTF-8", 1);
    setenv("ERL_CRASH_DUMP_SECONDS", "0", 1);
    snprintf(path, sizeof(path), "%s/inetrc", data);
    setenv("ERL_INETRC", path, 1);

    release_environment(root, data);
    if (getenv("CAULDRON_NATIVE_LOG")) send_output_to_logcat();
    read_arguments(root, data);
    (*env)->ReleaseStringUTFChars(env, root_text, root);
    (*env)->ReleaseStringUTFChars(env, data_text, data);

    pthread_attr_t attributes;
    pthread_t thread;
    pthread_attr_init(&attributes);
    pthread_attr_setstacksize(&attributes, 16 * 1024 * 1024);
    pthread_create(&thread, &attributes, run_beam, NULL);
    pthread_detach(thread);
}

static void blit(ANativeWindow *target, const uint8_t *rgba, int width, int height) {
    ANativeWindow_Buffer buffer;
    if (ANativeWindow_lock(target, &buffer, NULL) != 0) return;

    uint32_t *pixels = buffer.bits;
    for (int y = 0; y < buffer.height; y++) memset(pixels + (size_t)y * buffer.stride, 0, (size_t)buffer.width * 4);

    float fit = (float)buffer.width / width < (float)buffer.height / height
        ? (float)buffer.width / width : (float)buffer.height / height;
    float factor = fit >= 1.0f ? (float)(int)fit : fit;
    int shown_width = (int)(width * factor);
    int shown_height = (int)(height * factor);
    int left = (buffer.width - shown_width) / 2;
    int top = (buffer.height - shown_height) / 2;
    const uint32_t *source = (const uint32_t *)rgba;

    for (int y = 0; y < shown_height; y++) {
        int source_y = (int)(y / factor);
        if (source_y >= height) source_y = height - 1;
        uint32_t *row = pixels + (size_t)(top + y) * buffer.stride + left;
        const uint32_t *source_row = source + (size_t)source_y * width;
        for (int x = 0; x < shown_width; x++) {
            int source_x = (int)(x / factor);
            if (source_x >= width) source_x = width - 1;
            row[x] = source_row[source_x] | 0xff000000u;
        }
    }

    ANativeWindow_unlockAndPost(target);
}

void cn_platform_present(const uint8_t *rgba, int width, int height) {
    pthread_mutex_lock(&window_lock);
    size_t size = (size_t)width * height * 4;
    if (width != last_width || height != last_height) {
        free(last_frame);
        last_frame = malloc(size);
        last_width = width;
        last_height = height;
    }
    memcpy(last_frame, rgba, size);
    if (window && !gpu_wanted) blit(window, rgba, width, height);
    pthread_mutex_unlock(&window_lock);
}

static void show_pictures(void) {
    if (!window) return;
    ANativeWindow_setBuffersGeometry(window, window_width, window_height, AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM);
    if (last_frame) blit(window, last_frame, last_width, last_height);
}

JNIEXPORT void JNICALL Java_cauldron_app_CauldronActivity_surface(JNIEnv *env, jclass type, jobject surface, jint width, jint height) {
    pthread_mutex_lock(&window_lock);
    if (window) ANativeWindow_release(window);
    window = ANativeWindow_fromSurface(env, surface);
    window_width = width;
    window_height = height;
    if (!gpu_wanted) show_pictures();
    pthread_mutex_unlock(&window_lock);
}

JNIEXPORT void JNICALL Java_cauldron_app_CauldronActivity_surfaceGone(JNIEnv *env, jclass type) {
    pthread_mutex_lock(&window_lock);
    if (window) ANativeWindow_release(window);
    window = NULL;
    pthread_mutex_unlock(&window_lock);
}

JNIEXPORT void JNICALL Java_cauldron_app_CauldronActivity_gpuSurface(JNIEnv *env, jclass type, jobject surface) {
    pthread_mutex_lock(&window_lock);
    if (gpu_window) ANativeWindow_release(gpu_window);
    gpu_window = ANativeWindow_fromSurface(env, surface);
    pthread_mutex_unlock(&window_lock);
}

JNIEXPORT void JNICALL Java_cauldron_app_CauldronActivity_gpuSurfaceGone(JNIEnv *env, jclass type) {
    struct timespec deadline;
    clock_gettime(CLOCK_REALTIME, &deadline);
    deadline.tv_sec += 2;
    pthread_mutex_lock(&window_lock);
    while (gpu_handed)
        if (pthread_cond_timedwait(&gpu_released, &window_lock, &deadline) != 0) break;
    if (gpu_window) ANativeWindow_release(gpu_window);
    gpu_window = NULL;
    pthread_mutex_unlock(&window_lock);
}

static JNIEnv *java_env(int *attached) {
    JNIEnv *env;
    *attached = 0;
    if ((*java_vm)->GetEnv(java_vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) {
        (*java_vm)->AttachCurrentThread(java_vm, &env, NULL);
        *attached = 1;
    }
    return env;
}

static void show_gpu(jboolean shown) {
    int attached;
    JNIEnv *env = java_env(&attached);
    (*env)->CallStaticVoidMethod(env, activity_class, show_gpu_method, shown);
    if (attached) (*java_vm)->DetachCurrentThread(java_vm);
}

void cn_platform_overlay(const uint8_t *packed, size_t size) {
    int attached;
    JNIEnv *env = java_env(&attached);
    jbyteArray bytes = (*env)->NewByteArray(env, (jsize)size);
    (*env)->SetByteArrayRegion(env, bytes, 0, (jsize)size, (const jbyte *)packed);
    (*env)->CallStaticVoidMethod(env, activity_class, overlay_method, bytes);
    (*env)->DeleteLocalRef(env, bytes);
    if (attached) (*java_vm)->DetachCurrentThread(java_vm);
}

void cn_platform_ui(const uint8_t *json, size_t size) {
    int attached;
    JNIEnv *env = java_env(&attached);
    jbyteArray bytes = (*env)->NewByteArray(env, (jsize)size);
    (*env)->SetByteArrayRegion(env, bytes, 0, (jsize)size, (const jbyte *)json);
    (*env)->CallStaticVoidMethod(env, activity_class, ui_method, bytes);
    (*env)->DeleteLocalRef(env, bytes);
    if (attached) (*java_vm)->DetachCurrentThread(java_vm);
}

void cn_platform_request(const uint8_t *json, size_t size) {
    int attached;
    JNIEnv *env = java_env(&attached);
    jbyteArray bytes = (*env)->NewByteArray(env, (jsize)size);
    (*env)->SetByteArrayRegion(env, bytes, 0, (jsize)size, (const jbyte *)json);
    (*env)->CallStaticVoidMethod(env, activity_class, request_method, bytes);
    (*env)->DeleteLocalRef(env, bytes);
    if (attached) (*java_vm)->DetachCurrentThread(java_vm);
}

JNIEXPORT void JNICALL Java_cauldron_app_CauldronActivity_network(JNIEnv *env, jclass type, jbyteArray json) {
    jsize size = (*env)->GetArrayLength(env, json);
    jbyte *bytes = (*env)->GetByteArrayElements(env, json, NULL);
    cn_network((const uint8_t *)bytes, (size_t)size);
    (*env)->ReleaseByteArrayElements(env, json, bytes, JNI_ABORT);
}

JNIEXPORT void JNICALL Java_cauldron_app_CauldronActivity_result(JNIEnv *env, jclass type, jbyteArray json) {
    jsize size = (*env)->GetArrayLength(env, json);
    jbyte *bytes = (*env)->GetByteArrayElements(env, json, NULL);
    cn_result((const uint8_t *)bytes, (size_t)size);
    (*env)->ReleaseByteArrayElements(env, json, bytes, JNI_ABORT);
}

JNIEXPORT void JNICALL Java_cauldron_app_CauldronActivity_uiEvent(JNIEnv *env, jclass type, jbyteArray json) {
    jsize size = (*env)->GetArrayLength(env, json);
    jbyte *bytes = (*env)->GetByteArrayElements(env, json, NULL);
    cn_ui_event((const uint8_t *)bytes, (size_t)size);
    (*env)->ReleaseByteArrayElements(env, json, bytes, JNI_ABORT);
}

JNIEXPORT void JNICALL Java_cauldron_app_CauldronActivity_screen(JNIEnv *env, jclass type, jint width, jint height, jfloat scale,
                                                                    jfloat top, jfloat right, jfloat bottom, jfloat left) {
    cn_screen(width, height, scale, top, right, bottom, left);
}

JNIEXPORT void JNICALL Java_cauldron_app_CauldronActivity_touches(JNIEnv *env, jclass type, jlongArray ids, jintArray phases,
                                                                     jfloatArray xs, jfloatArray ys) {
    jsize count = (*env)->GetArrayLength(env, ids);
    jlong *id_values = (*env)->GetLongArrayElements(env, ids, NULL);
    jint *phase_values = (*env)->GetIntArrayElements(env, phases, NULL);
    jfloat *x_values = (*env)->GetFloatArrayElements(env, xs, NULL);
    jfloat *y_values = (*env)->GetFloatArrayElements(env, ys, NULL);
    cn_touch *touches = malloc(sizeof(cn_touch) * (count ? count : 1));

    for (jsize i = 0; i < count; i++) {
        touches[i].id = id_values[i];
        touches[i].phase = phase_values[i];
        touches[i].x = x_values[i];
        touches[i].y = y_values[i];
    }
    cn_touches(touches, count);

    free(touches);
    (*env)->ReleaseLongArrayElements(env, ids, id_values, JNI_ABORT);
    (*env)->ReleaseIntArrayElements(env, phases, phase_values, JNI_ABORT);
    (*env)->ReleaseFloatArrayElements(env, xs, x_values, JNI_ABORT);
    (*env)->ReleaseFloatArrayElements(env, ys, y_values, JNI_ABORT);
}

JNIEXPORT void JNICALL Java_cauldron_app_CauldronActivity_lifecycle(JNIEnv *env, jclass type, jint state) {
    cn_lifecycle(state);
}

JNIEXPORT void JNICALL Java_cauldron_app_CauldronActivity_back(JNIEnv *env, jclass type) {
    cn_back();
}

void cn_platform_quit(void) {
    int attached;
    JNIEnv *env = java_env(&attached);
    (*env)->CallStaticVoidMethod(env, activity_class, quit_method);
}

JNIEXPORT void JNICALL Java_cauldron_app_CauldronActivity_padConnected(JNIEnv *env, jclass type, jint device, jstring name) {
    const char *text = (*env)->GetStringUTFChars(env, name, NULL);
    cn_pad_connected(device, text);
    (*env)->ReleaseStringUTFChars(env, name, text);
}

JNIEXPORT void JNICALL Java_cauldron_app_CauldronActivity_padDisconnected(JNIEnv *env, jclass type, jint device) {
    cn_pad_disconnected(device);
}

JNIEXPORT void JNICALL Java_cauldron_app_CauldronActivity_padButton(JNIEnv *env, jclass type, jint device, jstring button,
                                                                       jboolean pressed) {
    const char *text = (*env)->GetStringUTFChars(env, button, NULL);
    cn_pad_button(device, text, pressed == JNI_TRUE);
    (*env)->ReleaseStringUTFChars(env, button, text);
}

JNIEXPORT void JNICALL Java_cauldron_app_CauldronActivity_padAxis(JNIEnv *env, jclass type, jint device, jstring axis,
                                                                     jfloat value) {
    const char *text = (*env)->GetStringUTFChars(env, axis, NULL);
    cn_pad_axis(device, text, value);
    (*env)->ReleaseStringUTFChars(env, axis, text);
}

void *cn_platform_gpu_surface(void) {
    pthread_mutex_lock(&window_lock);
    int showing = gpu_wanted;
    gpu_wanted = 1;
    ANativeWindow *surface = gpu_window;
    if (surface) gpu_handed = 1;
    pthread_mutex_unlock(&window_lock);
    if (!showing) show_gpu(JNI_TRUE);
    return surface;
}

void cn_platform_hide_gpu_surface(void) {
    pthread_mutex_lock(&window_lock);
    int showing = gpu_wanted;
    gpu_wanted = 0;
    gpu_handed = 0;
    pthread_cond_broadcast(&gpu_released);
    show_pictures();
    pthread_mutex_unlock(&window_lock);
    if (showing) show_gpu(JNI_FALSE);
}

JNIEXPORT void JNICALL Java_cauldron_app_CauldronActivity_posture(JNIEnv *env, jclass type, jint fold, jboolean has_angle, jfloat angle,
                                                                     jboolean has_hinge, jint x, jint y, jint width, jint height,
                                                                     jboolean vertical, jboolean separating) {
    cn_posture(fold, has_angle, angle, has_hinge, x, y, width, height, vertical, separating);
}

JNIEXPORT void JNICALL Java_cauldron_app_CauldronActivity_url(JNIEnv *env, jclass type, jbyteArray url) {
    jsize size = (*env)->GetArrayLength(env, url);
    jbyte *bytes = (*env)->GetByteArrayElements(env, url, NULL);
    cn_url((const uint8_t *)bytes, (size_t)size);
    (*env)->ReleaseByteArrayElements(env, url, bytes, JNI_ABORT);
}

JNIEXPORT void JNICALL Java_cauldron_app_CauldronActivity_background(JNIEnv *env, jclass type) {
    cn_background();
}
