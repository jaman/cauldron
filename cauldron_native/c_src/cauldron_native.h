#ifndef CAULDRON_NATIVE_H
#define CAULDRON_NATIVE_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
    int64_t id;
    int phase;
    float x;
    float y;
} cn_touch;

enum { CN_TOUCH_BEGAN = 0, CN_TOUCH_MOVED = 1, CN_TOUCH_ENDED = 2, CN_TOUCH_CANCELLED = 3 };

enum { CN_LIFECYCLE_ACTIVE = 0, CN_LIFECYCLE_INACTIVE = 1, CN_LIFECYCLE_BACKGROUND = 2 };

enum { CN_FOLD_UNKNOWN = 0, CN_FOLD_CLOSED = 1, CN_FOLD_HALF_OPEN = 2, CN_FOLD_OPEN = 3 };

void cn_screen(int width, int height, float scale, float top, float right, float bottom, float left);
void cn_touches(const cn_touch *touches, int count);
void cn_lifecycle(int state);
void cn_posture(int fold, int has_angle, float angle, int has_hinge, int x, int y, int width, int height,
                int vertical, int separating);
void cn_back(void);
void cn_pad_connected(int device, const char *name);
void cn_pad_disconnected(int device);
void cn_pad_button(int device, const char *button, int pressed);
void cn_pad_axis(int device, const char *axis, float value);
void cn_ui_event(const uint8_t *json, size_t size);
void cn_result(const uint8_t *json, size_t size);
void cn_url(const uint8_t *url, size_t size);
void cn_background(void);
void cn_network(const uint8_t *json, size_t size);

void cn_platform_present(const uint8_t *rgba, int width, int height);
void cn_platform_overlay(const uint8_t *packed, size_t size);
void cn_platform_quit(void);
void *cn_platform_gpu_surface(void);
void cn_platform_hide_gpu_surface(void);
void cn_platform_ui(const uint8_t *json, size_t size);
void cn_platform_request(const uint8_t *json, size_t size);

#endif
