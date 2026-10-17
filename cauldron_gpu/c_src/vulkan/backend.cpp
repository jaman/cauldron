#include "internal.hpp"

#include <SDL3/SDL_video.h>

namespace {

constexpr cg_backend vulkan_backend{
    .name = "vulkan",
    .shader_extension = "spv",
    .window_flags = SDL_WINDOW_VULKAN,
    .device_create = cgvk::device_create,
    .device_destroy = cgvk::device_destroy,
    .device_info = cgvk::device_info,
    .surface_attach = cgvk::surface_attach,
    .surface_detach = cgvk::surface_detach,
    .surface_resize = cgvk::surface_resize,
    .surface_format = cgvk::surface_format,
    .buffer_create = cgvk::buffer_create,
    .buffer_destroy = cgvk::buffer_destroy,
    .buffer_contents = cgvk::buffer_contents,
    .buffer_address = cgvk::buffer_address,
    .texture_create = cgvk::texture_create,
    .texture_destroy = cgvk::texture_destroy,
    .texture_handle = cgvk::texture_handle,
    .sampler_create = cgvk::sampler_create,
    .sampler_destroy = cgvk::sampler_destroy,
    .sampler_handle = cgvk::sampler_handle,
    .pipeline_create = cgvk::pipeline_create,
    .compute_pipeline_create = cgvk::compute_pipeline_create,
    .pipeline_destroy = cgvk::pipeline_destroy,
    .accel_create_geometry = cgvk::accel_create_geometry,
    .accel_create_scene = cgvk::accel_create_scene,
    .accel_destroy = cgvk::accel_destroy,
    .upscaler_create = cgvk::upscaler_create,
    .upscaler_destroy = cgvk::upscaler_destroy,
    .interpolator_create = cgvk::interpolator_create,
    .interpolator_destroy = cgvk::interpolator_destroy,
    .frame_begin = cgvk::frame_begin,
    .frame_target = cgvk::frame_target,
    .frame_end = cgvk::frame_end,
    .frame_end_pair = cgvk::frame_end_pair,
    .frame_gpu_seconds = cgvk::frame_gpu_seconds,
    .cmd_copy_buffer = cgvk::cmd_copy_buffer,
    .cmd_copy_to_texture = cgvk::cmd_copy_to_texture,
    .cmd_generate_mips = cgvk::cmd_generate_mips,
    .cmd_copy_texture_to_buffer = cgvk::cmd_copy_texture_to_buffer,
    .cmd_begin_pass = cgvk::cmd_begin_pass,
    .cmd_end_pass = cgvk::cmd_end_pass,
    .cmd_set_pipeline = cgvk::cmd_set_pipeline,
    .cmd_push = cgvk::cmd_push,
    .cmd_draw = cgvk::cmd_draw,
    .cmd_draw_indexed = cgvk::cmd_draw_indexed,
    .cmd_begin_compute = cgvk::cmd_begin_compute,
    .cmd_end_compute = cgvk::cmd_end_compute,
    .cmd_set_compute_pipeline = cgvk::cmd_set_compute_pipeline,
    .cmd_set_accel = cgvk::cmd_set_accel,
    .cmd_dispatch = cgvk::cmd_dispatch,
    .cmd_upscale = cgvk::cmd_upscale,
    .cmd_interpolate = cgvk::cmd_interpolate,
};

}

extern "C" const cg_backend *cg_vulkan_backend(void) {
  return &vulkan_backend;
}
