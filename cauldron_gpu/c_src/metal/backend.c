#include <SDL3/SDL.h>

#include "../gpu.h"

cg_device *cg_metal_device_create(void);
void cg_metal_device_destroy(cg_device *device);
void cg_metal_device_info(cg_device *device, cg_device_info *info);
void cg_metal_surface_set(cg_device *device, void *layer, void *view);
void *cg_metal_surface_view(cg_device *device);
void cg_metal_surface_resize(cg_device *device, uint32_t width, uint32_t height);
cg_format cg_metal_surface_format(cg_device *device);
cg_buffer *cg_metal_buffer_create(cg_device *device, uint64_t size, cg_memory memory, const char *label);
void cg_metal_buffer_destroy(cg_device *device, cg_buffer *buffer);
void *cg_metal_buffer_contents(cg_buffer *buffer);
uint64_t cg_metal_buffer_address(cg_buffer *buffer);
cg_texture *cg_metal_texture_create(cg_device *device, const cg_texture_desc *desc);
void cg_metal_texture_destroy(cg_device *device, cg_texture *texture);
uint64_t cg_metal_texture_handle(cg_texture *texture);
cg_sampler *cg_metal_sampler_create(cg_device *device, const cg_sampler_desc *desc);
void cg_metal_sampler_destroy(cg_device *device, cg_sampler *sampler);
uint64_t cg_metal_sampler_handle(cg_sampler *sampler);
cg_pipeline *cg_metal_pipeline_create(cg_device *device, const cg_pipeline_desc *desc);
void cg_metal_pipeline_destroy(cg_device *device, cg_pipeline *pipeline);
cg_cmd *cg_metal_frame_begin(cg_device *device);
cg_texture *cg_metal_frame_target(cg_device *device);
void cg_metal_frame_end(cg_device *device, cg_cmd *cmd);
void cg_metal_cmd_copy_buffer(cg_cmd *cmd, cg_buffer *src, uint64_t src_offset, cg_buffer *dst, uint64_t dst_offset, uint64_t size);
void cg_metal_cmd_copy_to_texture(cg_cmd *cmd, cg_buffer *src, uint64_t src_offset, uint32_t bytes_per_row, cg_texture *dst, uint32_t mip, uint32_t layer, uint32_t width, uint32_t height);
void cg_metal_cmd_generate_mips(cg_cmd *cmd, cg_texture *texture);
void cg_metal_cmd_copy_texture_to_buffer(cg_cmd *cmd, cg_texture *src, cg_buffer *dst, uint64_t dst_offset, uint32_t bytes_per_row);
void cg_metal_cmd_begin_pass(cg_cmd *cmd, const cg_pass_desc *desc);
void cg_metal_cmd_end_pass(cg_cmd *cmd);
void cg_metal_cmd_set_pipeline(cg_cmd *cmd, cg_pipeline *pipeline);
void cg_metal_cmd_push(cg_cmd *cmd, const void *data, uint32_t size);
void cg_metal_cmd_draw(cg_cmd *cmd, uint32_t vertex_count, uint32_t instance_count, uint32_t first_vertex);
void cg_metal_cmd_draw_indexed(cg_cmd *cmd, cg_buffer *indices, uint32_t index_count, uint32_t instance_count, uint32_t first_index);

cg_pipeline *cg_metal_compute_pipeline_create(cg_device *device, const cg_compute_desc *desc);
cg_accel *cg_metal_accel_create_geometry(cg_device *device, cg_cmd *cmd, cg_buffer *vertices, uint32_t vertex_count, uint32_t vertex_stride, cg_buffer *indices, uint32_t index_count);
cg_accel *cg_metal_accel_create_scene(cg_device *device, cg_cmd *cmd, const cg_accel_instance *instances, uint32_t count);
void cg_metal_accel_destroy(cg_device *device, cg_accel *accel);
void cg_metal_cmd_begin_compute(cg_cmd *cmd, const char *label);
void cg_metal_cmd_end_compute(cg_cmd *cmd);
void cg_metal_cmd_set_compute_pipeline(cg_cmd *cmd, cg_pipeline *pipeline);
void cg_metal_cmd_set_accel(cg_cmd *cmd, cg_accel *scene);
void cg_metal_cmd_dispatch(cg_cmd *cmd, uint32_t groups_x, uint32_t groups_y, uint32_t groups_z);
cg_upscaler *cg_metal_upscaler_create(cg_device *device, const cg_upscaler_desc *desc);
void cg_metal_upscaler_destroy(cg_device *device, cg_upscaler *upscaler);
void cg_metal_cmd_upscale(cg_cmd *cmd, cg_upscaler *upscaler, const cg_upscale *frame);
cg_interpolator *cg_metal_interpolator_create(cg_device *device, const cg_upscaler_desc *desc);
void cg_metal_interpolator_destroy(cg_device *device, cg_interpolator *interpolator);
void cg_metal_cmd_interpolate(cg_cmd *cmd, cg_interpolator *interpolator, const cg_interpolate *frame);
float cg_metal_frame_gpu_seconds(cg_device *device);
void cg_metal_frame_end_pair(cg_device *device, cg_cmd *cmd, cg_texture *first, cg_texture *second, float spacing);

static bool metal_surface_attach(cg_device *device, void *sdl_window) {
  SDL_MetalView view = SDL_Metal_CreateView((SDL_Window *)sdl_window);
  if (view == NULL) return false;
  cg_metal_surface_set(device, SDL_Metal_GetLayer(view), view);
  return true;
}

void *objc_autoreleasePoolPush(void);
void objc_autoreleasePoolPop(void *pool);

static _Thread_local void *frame_pool = NULL;

static void drain_frame_pool(void) {
  if (frame_pool == NULL) return;
  objc_autoreleasePoolPop(frame_pool);
  frame_pool = NULL;
}

static cg_cmd *metal_frame_begin(cg_device *device) {
  drain_frame_pool();
  frame_pool = objc_autoreleasePoolPush();
  cg_cmd *cmd = cg_metal_frame_begin(device);
  if (cmd == NULL) drain_frame_pool();
  return cmd;
}

static void metal_frame_end(cg_device *device, cg_cmd *cmd) {
  cg_metal_frame_end(device, cmd);
  drain_frame_pool();
}

static void metal_frame_end_pair(cg_device *device, cg_cmd *cmd, cg_texture *first, cg_texture *second, float spacing) {
  cg_metal_frame_end_pair(device, cmd, first, second, spacing);
  drain_frame_pool();
}

static void metal_surface_detach(cg_device *device) {
  SDL_MetalView view = cg_metal_surface_view(device);
  cg_metal_surface_set(device, NULL, NULL);
  if (view != NULL) SDL_Metal_DestroyView(view);
}

static const cg_backend metal_backend = {
  .name = "metal",
  .shader_extension = "metallib",
  .window_flags = SDL_WINDOW_METAL,
  .device_create = cg_metal_device_create,
  .device_destroy = cg_metal_device_destroy,
  .device_info = cg_metal_device_info,
  .surface_attach = metal_surface_attach,
  .surface_detach = metal_surface_detach,
  .surface_resize = cg_metal_surface_resize,
  .surface_format = cg_metal_surface_format,
  .buffer_create = cg_metal_buffer_create,
  .buffer_destroy = cg_metal_buffer_destroy,
  .buffer_contents = cg_metal_buffer_contents,
  .buffer_address = cg_metal_buffer_address,
  .texture_create = cg_metal_texture_create,
  .texture_destroy = cg_metal_texture_destroy,
  .texture_handle = cg_metal_texture_handle,
  .sampler_create = cg_metal_sampler_create,
  .sampler_destroy = cg_metal_sampler_destroy,
  .sampler_handle = cg_metal_sampler_handle,
  .pipeline_create = cg_metal_pipeline_create,
  .pipeline_destroy = cg_metal_pipeline_destroy,
  .frame_begin = metal_frame_begin,
  .frame_target = cg_metal_frame_target,
  .frame_end = metal_frame_end,
  .cmd_copy_buffer = cg_metal_cmd_copy_buffer,
  .cmd_copy_to_texture = cg_metal_cmd_copy_to_texture,
  .cmd_generate_mips = cg_metal_cmd_generate_mips,
  .cmd_copy_texture_to_buffer = cg_metal_cmd_copy_texture_to_buffer,
  .cmd_begin_pass = cg_metal_cmd_begin_pass,
  .cmd_end_pass = cg_metal_cmd_end_pass,
  .cmd_set_pipeline = cg_metal_cmd_set_pipeline,
  .cmd_push = cg_metal_cmd_push,
  .cmd_draw = cg_metal_cmd_draw,
  .cmd_draw_indexed = cg_metal_cmd_draw_indexed,
  .compute_pipeline_create = cg_metal_compute_pipeline_create,
  .accel_create_geometry = cg_metal_accel_create_geometry,
  .accel_create_scene = cg_metal_accel_create_scene,
  .accel_destroy = cg_metal_accel_destroy,
  .cmd_begin_compute = cg_metal_cmd_begin_compute,
  .cmd_end_compute = cg_metal_cmd_end_compute,
  .cmd_set_compute_pipeline = cg_metal_cmd_set_compute_pipeline,
  .cmd_set_accel = cg_metal_cmd_set_accel,
  .cmd_dispatch = cg_metal_cmd_dispatch,
  .upscaler_create = cg_metal_upscaler_create,
  .upscaler_destroy = cg_metal_upscaler_destroy,
  .cmd_upscale = cg_metal_cmd_upscale,
  .interpolator_create = cg_metal_interpolator_create,
  .interpolator_destroy = cg_metal_interpolator_destroy,
  .cmd_interpolate = cg_metal_cmd_interpolate,
  .frame_end_pair = metal_frame_end_pair,
  .frame_gpu_seconds = cg_metal_frame_gpu_seconds,
};

const cg_backend *cg_metal_backend(void) {
  return &metal_backend;
}
