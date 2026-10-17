#ifndef CAULDRON_GPU_H
#define CAULDRON_GPU_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * The graphics layer every backend implements, as a table of functions.
 *
 * Buffers are read by shaders through GPU addresses passed in push constants; textures
 * and samplers through 64-bit handles stored in buffers. A destroyed object stays alive
 * until the GPU has finished every frame submitted before the call. A texture is
 * readable by shaders outside the pass or copy that writes it. Copies are recorded
 * outside passes. Push constants are at most CG_MAX_PUSH bytes and stay set for the
 * following draws in the pass, or dispatches in the compute section.
 *
 * Every pass, compute section and copy sees all memory written by the ones recorded
 * before it in the same frame. Compute shaders read the scene acceleration structure
 * bound with cmd_set_accel through Slang's `RaytracingAccelerationStructure` declared
 * at `[[vk::binding(0, 1)]]` (Metal buffer index 1). Geometry acceleration structures
 * read float3 positions at the start of each vertex; instance transforms are 3x4
 * row-major; an instance with mask 0 is never hit. Acceleration structures are only
 * created when device_info reports ray_tracing.
 *
 * A temporal upscaler turns a jittered `color` frame of the input size into `output`
 * (created with CG_TEXTURE_STORAGE) of the output size, using `depth` and `motion`.
 * Motion holds, per input pixel, the offset to where that pixel was in the previous
 * frame in texture coordinates; motion_scale converts it to input pixels. Jitter is the
 * sub-pixel offset applied to the projection, in input pixels. `reset` discards history.
 * upscaler_create returns NULL when device_info does not report upscaling.
 *
 * A frame interpolator makes `output` (output size, CG_TEXTURE_STORAGE), a frame halfway
 * between `previous_color` and `color` (both output size, the surface format, final
 * pictures after tone mapping), from `depth` and `motion` of the input size and the
 * camera described by near/far planes, vertical field of view and aspect. frame_end_pair
 * copies `first` and then `second` (both the surface format and size) into two surface
 * images and presents them `spacing` seconds apart, instead of frame_end; the frame's own
 * surface texture is then not drawn into. interpolator_create returns NULL when
 * device_info does not report frame_generation.
 *
 * frame_gpu_seconds is how long the GPU spent on the most recently completed frame, 0
 * before any has completed.
 */

#define CG_MAX_COLOR 8
#define CG_MAX_PUSH 128

typedef struct cg_device cg_device;
typedef struct cg_buffer cg_buffer;
typedef struct cg_texture cg_texture;
typedef struct cg_sampler cg_sampler;
typedef struct cg_pipeline cg_pipeline;
typedef struct cg_cmd cg_cmd;

typedef enum cg_format {
  CG_FORMAT_UNDEFINED = 0,
  CG_FORMAT_RGBA8_UNORM,
  CG_FORMAT_RGBA8_SRGB,
  CG_FORMAT_BGRA8_UNORM,
  CG_FORMAT_BGRA8_SRGB,
  CG_FORMAT_RGBA16F,
  CG_FORMAT_RG16F,
  CG_FORMAT_R32F,
  CG_FORMAT_D32F
} cg_format;

typedef enum cg_memory {
  CG_MEMORY_GPU,
  CG_MEMORY_UPLOAD,
  CG_MEMORY_READBACK
} cg_memory;

enum {
  CG_TEXTURE_SAMPLED = 1,
  CG_TEXTURE_RENDER_TARGET = 2,
  CG_TEXTURE_DEPTH = 4,
  CG_TEXTURE_READBACK = 8,
  CG_TEXTURE_STORAGE = 16
};

typedef enum cg_texture_kind {
  CG_TEXTURE_2D,
  CG_TEXTURE_CUBE
} cg_texture_kind;

typedef struct cg_texture_desc {
  cg_texture_kind kind;
  cg_format format;
  uint32_t width;
  uint32_t height;
  uint32_t mip_levels;
  uint32_t usage;
  const char *label;
} cg_texture_desc;

typedef enum cg_filter {
  CG_FILTER_NEAREST,
  CG_FILTER_LINEAR
} cg_filter;

typedef enum cg_address {
  CG_ADDRESS_REPEAT,
  CG_ADDRESS_CLAMP
} cg_address;

typedef struct cg_sampler_desc {
  cg_filter filter;
  cg_filter mip_filter;
  cg_address address;
  float max_anisotropy;
} cg_sampler_desc;

typedef enum cg_load {
  CG_LOAD_CLEAR,
  CG_LOAD_LOAD,
  CG_LOAD_DONT_CARE
} cg_load;

typedef struct cg_color_attachment {
  cg_texture *texture;
  cg_load load;
  bool store;
  float clear[4];
} cg_color_attachment;

typedef struct cg_depth_attachment {
  cg_texture *texture;
  cg_load load;
  bool store;
  float clear;
} cg_depth_attachment;

typedef struct cg_pass_desc {
  uint32_t color_count;
  cg_color_attachment colors[CG_MAX_COLOR];
  cg_depth_attachment depth;
  const char *label;
} cg_pass_desc;

typedef enum cg_cull {
  CG_CULL_NONE,
  CG_CULL_BACK,
  CG_CULL_FRONT
} cg_cull;

typedef enum cg_compare {
  CG_COMPARE_ALWAYS,
  CG_COMPARE_LESS,
  CG_COMPARE_LESS_EQUAL,
  CG_COMPARE_GREATER,
  CG_COMPARE_GREATER_EQUAL
} cg_compare;

typedef enum cg_blend {
  CG_BLEND_NONE,
  CG_BLEND_ALPHA,
  CG_BLEND_ADD,
  CG_BLEND_MULTIPLY
} cg_blend;

typedef struct cg_shader {
  const void *code;
  size_t size;
  const char *entry;
} cg_shader;

typedef struct cg_pipeline_desc {
  cg_shader vertex;
  cg_shader fragment;
  uint32_t color_count;
  cg_format color_formats[CG_MAX_COLOR];
  cg_blend blend[CG_MAX_COLOR];
  cg_format depth_format;
  cg_compare depth_compare;
  bool depth_write;
  cg_cull cull;
  float depth_bias;
  float depth_slope_bias;
  const char *label;
} cg_pipeline_desc;

typedef struct cg_compute_desc {
  cg_shader compute;
  uint32_t threads[3];
  const char *label;
} cg_compute_desc;

typedef struct cg_accel cg_accel;

typedef struct cg_accel_instance {
  float transform[12];
  uint32_t mask;
  cg_accel *geometry;
} cg_accel_instance;

typedef struct cg_upscaler cg_upscaler;

typedef struct cg_upscaler_desc {
  uint32_t input_width;
  uint32_t input_height;
  uint32_t output_width;
  uint32_t output_height;
  cg_format color_format;
  cg_format depth_format;
  cg_format motion_format;
  cg_format output_format;
} cg_upscaler_desc;

typedef struct cg_upscale {
  cg_texture *color;
  cg_texture *depth;
  cg_texture *motion;
  cg_texture *output;
  float jitter_x;
  float jitter_y;
  float motion_scale_x;
  float motion_scale_y;
  bool reset;
  bool reversed_depth;
} cg_upscale;

typedef struct cg_interpolator cg_interpolator;

typedef struct cg_interpolate {
  cg_texture *color;
  cg_texture *previous_color;
  cg_texture *depth;
  cg_texture *motion;
  cg_texture *output;
  float motion_scale_x;
  float motion_scale_y;
  float jitter_x;
  float jitter_y;
  float delta_time;
  float near_plane;
  float far_plane;
  float fov_y;
  float aspect;
  bool reset;
  bool reversed_depth;
} cg_interpolate;

typedef struct cg_device_info {
  char name[256];
  char backend[16];
  bool ray_tracing;
  bool mesh_shaders;
  bool unified_memory;
  bool upscaling;
  bool frame_generation;
} cg_device_info;

/**
 * One backend. `shader_extension` names the compiled shader files it loads
 * ("metallib" or "spv"); `window_flags` are the SDL window flags its surface needs.
 * `surface_attach` and `surface_detach` run on the window thread with an `SDL_Window *`;
 * every other function runs on the render thread. Front faces are counter-clockwise.
 * `frame_begin` waits for a free frame and returns its command list. With a surface it
 * returns NULL while the surface is zero-sized; without one (offscreen rendering) it
 * always returns a command list, `frame_target` returns NULL and `frame_end` submits
 * without presenting. `frame_target` is the surface texture of the frame begun last.
 */
typedef struct cg_backend {
  const char *name;
  const char *shader_extension;
  uint64_t window_flags;

  cg_device *(*device_create)(void);
  void (*device_destroy)(cg_device *device);
  void (*device_info)(cg_device *device, cg_device_info *info);

  bool (*surface_attach)(cg_device *device, void *sdl_window);
  void (*surface_detach)(cg_device *device);
  void (*surface_resize)(cg_device *device, uint32_t width, uint32_t height);
  cg_format (*surface_format)(cg_device *device);

  cg_buffer *(*buffer_create)(cg_device *device, uint64_t size, cg_memory memory, const char *label);
  void (*buffer_destroy)(cg_device *device, cg_buffer *buffer);
  void *(*buffer_contents)(cg_buffer *buffer);
  uint64_t (*buffer_address)(cg_buffer *buffer);

  cg_texture *(*texture_create)(cg_device *device, const cg_texture_desc *desc);
  void (*texture_destroy)(cg_device *device, cg_texture *texture);
  uint64_t (*texture_handle)(cg_texture *texture);

  cg_sampler *(*sampler_create)(cg_device *device, const cg_sampler_desc *desc);
  void (*sampler_destroy)(cg_device *device, cg_sampler *sampler);
  uint64_t (*sampler_handle)(cg_sampler *sampler);

  cg_pipeline *(*pipeline_create)(cg_device *device, const cg_pipeline_desc *desc);
  cg_pipeline *(*compute_pipeline_create)(cg_device *device, const cg_compute_desc *desc);
  void (*pipeline_destroy)(cg_device *device, cg_pipeline *pipeline);

  cg_accel *(*accel_create_geometry)(cg_device *device, cg_cmd *cmd, cg_buffer *vertices, uint32_t vertex_count, uint32_t vertex_stride, cg_buffer *indices, uint32_t index_count);
  cg_accel *(*accel_create_scene)(cg_device *device, cg_cmd *cmd, const cg_accel_instance *instances, uint32_t count);
  void (*accel_destroy)(cg_device *device, cg_accel *accel);

  cg_upscaler *(*upscaler_create)(cg_device *device, const cg_upscaler_desc *desc);
  void (*upscaler_destroy)(cg_device *device, cg_upscaler *upscaler);
  cg_interpolator *(*interpolator_create)(cg_device *device, const cg_upscaler_desc *desc);
  void (*interpolator_destroy)(cg_device *device, cg_interpolator *interpolator);

  cg_cmd *(*frame_begin)(cg_device *device);
  cg_texture *(*frame_target)(cg_device *device);
  void (*frame_end)(cg_device *device, cg_cmd *cmd);
  void (*frame_end_pair)(cg_device *device, cg_cmd *cmd, cg_texture *first, cg_texture *second, float spacing);
  float (*frame_gpu_seconds)(cg_device *device);

  void (*cmd_copy_buffer)(cg_cmd *cmd, cg_buffer *src, uint64_t src_offset, cg_buffer *dst, uint64_t dst_offset, uint64_t size);
  void (*cmd_copy_to_texture)(cg_cmd *cmd, cg_buffer *src, uint64_t src_offset, uint32_t bytes_per_row, cg_texture *dst, uint32_t mip, uint32_t layer, uint32_t width, uint32_t height);
  void (*cmd_generate_mips)(cg_cmd *cmd, cg_texture *texture);
  void (*cmd_copy_texture_to_buffer)(cg_cmd *cmd, cg_texture *src, cg_buffer *dst, uint64_t dst_offset, uint32_t bytes_per_row);
  void (*cmd_begin_pass)(cg_cmd *cmd, const cg_pass_desc *desc);
  void (*cmd_end_pass)(cg_cmd *cmd);
  void (*cmd_set_pipeline)(cg_cmd *cmd, cg_pipeline *pipeline);
  void (*cmd_push)(cg_cmd *cmd, const void *data, uint32_t size);
  void (*cmd_draw)(cg_cmd *cmd, uint32_t vertex_count, uint32_t instance_count, uint32_t first_vertex);
  void (*cmd_draw_indexed)(cg_cmd *cmd, cg_buffer *indices, uint32_t index_count, uint32_t instance_count, uint32_t first_index);
  void (*cmd_begin_compute)(cg_cmd *cmd, const char *label);
  void (*cmd_end_compute)(cg_cmd *cmd);
  void (*cmd_set_compute_pipeline)(cg_cmd *cmd, cg_pipeline *pipeline);
  void (*cmd_set_accel)(cg_cmd *cmd, cg_accel *scene);
  void (*cmd_dispatch)(cg_cmd *cmd, uint32_t groups_x, uint32_t groups_y, uint32_t groups_z);
  void (*cmd_upscale)(cg_cmd *cmd, cg_upscaler *upscaler, const cg_upscale *frame);
  void (*cmd_interpolate)(cg_cmd *cmd, cg_interpolator *interpolator, const cg_interpolate *frame);
} cg_backend;

const cg_backend *cg_metal_backend(void);
const cg_backend *cg_vulkan_backend(void);

#ifdef __cplusplus
}
#endif

#endif
