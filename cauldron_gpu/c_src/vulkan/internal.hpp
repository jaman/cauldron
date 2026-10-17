#pragma once

#define VK_ENABLE_BETA_EXTENSIONS
#define VULKAN_HPP_DISPATCH_LOADER_DYNAMIC 1
#define VULKAN_HPP_NO_CONSTRUCTORS
#include <vulkan/vulkan.hpp>
#include <vulkan/vulkan_format_traits.hpp>
#include <vk_mem_alloc.h>

#include <array>
#include <atomic>
#include <cstdint>
#include <functional>
#include <mutex>
#include <span>
#include <vector>

#include "../gpu.h"

namespace cgvk {

inline constexpr uint32_t frames_in_flight = 2;
inline constexpr uint32_t sampler_binding = 0;
inline constexpr uint32_t sampled_image_binding = 2;
inline constexpr uint32_t sampler_capacity = 2048;
inline constexpr uint32_t sampled_image_capacity = 16384;
inline constexpr uint32_t accel_set_index = 1;
inline constexpr uint32_t accel_set_capacity = 256;

enum class ImageUse : uint8_t {
  undefined,
  acquired,
  transfer_dst,
  transfer_src,
  sampled,
  color_attachment,
  depth_attachment,
  present
};

struct SlotPool {
  uint32_t capacity;
  uint32_t next = 1;
  std::vector<uint32_t> released{};

  uint32_t acquire();
  void release(uint32_t slot);
};

struct Bindless {
  vk::DescriptorSetLayout set_layout;
  vk::DescriptorPool pool;
  vk::DescriptorSet set;
  vk::DescriptorSetLayout accel_layout;
  vk::DescriptorPool accel_pool;
  vk::PipelineLayout pipeline_layout;
  SlotPool images{sampled_image_capacity};
  SlotPool samplers{sampler_capacity};
};

struct Retirement {
  uint64_t serial;
  std::function<void()> release;
};

struct Capabilities {
  bool debug_utils = false;
  bool anisotropy = false;
  float max_anisotropy = 1.0f;
  bool ray_tracing = false;
  bool mesh_shaders = false;
  uint32_t scratch_alignment = 0;
  uint64_t timestamp_mask = 0;
  float timestamp_period = 0.0f;
};

}

struct cg_buffer {
  vk::Buffer buffer;
  VmaAllocation allocation = nullptr;
  void *mapped = nullptr;
  uint64_t address = 0;
};

struct cg_texture {
  vk::Image image;
  VmaAllocation allocation = nullptr;
  vk::ImageView sampled_view;
  vk::ImageView attachment_view;
  vk::Format format = vk::Format::eUndefined;
  vk::ImageAspectFlags aspect;
  vk::Extent2D extent;
  uint32_t mip_levels = 1;
  uint32_t layers = 1;
  uint32_t usage = 0;
  uint32_t descriptor_index = 0;
  cgvk::ImageUse use = cgvk::ImageUse::undefined;
};

struct cg_sampler {
  vk::Sampler sampler;
  uint32_t descriptor_index = 0;
};

struct cg_pipeline {
  vk::Pipeline pipeline;
};

struct cg_accel {
  cg_buffer storage;
  vk::AccelerationStructureKHR handle;
  uint64_t address = 0;
  vk::DescriptorSet set;
};

struct cg_cmd {
  cg_device *device = nullptr;
  vk::CommandBuffer commands;
  std::array<cg_texture *, CG_MAX_COLOR + 1> pass_attachments{};
  uint32_t pass_attachment_count = 0;
  bool pass_labelled = false;
};

namespace cgvk {

struct FrameSlot {
  vk::CommandPool pool;
  vk::Fence done;
  vk::Semaphore acquired;
  vk::Semaphore second_acquired;
  vk::CommandBuffer pair_commands;
  vk::QueryPool timestamps;
  bool timed = false;
  uint64_t serial = 0;
  cg_cmd cmd;
};

struct Swapchain {
  vk::SwapchainKHR handle;
  std::vector<cg_texture> images;
  std::vector<vk::Semaphore> rendered;
  uint32_t current = 0;
  bool copyable = false;
};

struct Surface {
  std::mutex mutex;
  std::unique_lock<std::mutex> frame_lock;
  vk::SurfaceKHR handle;
  vk::SurfaceFormatKHR format;
  std::atomic<cg_format> reported_format{CG_FORMAT_UNDEFINED};
  std::atomic<uint32_t> width{0};
  std::atomic<uint32_t> height{0};
  std::atomic<bool> stale{true};
  Swapchain swapchain;
};

}

struct cg_device {
  bool sdl_library_loaded = false;
  vk::Instance instance;
  vk::DebugUtilsMessengerEXT messenger;
  vk::PhysicalDevice physical;
  vk::PhysicalDeviceProperties properties;
  uint32_t queue_family = 0;
  vk::Device device;
  vk::Queue queue;
  VmaAllocator allocator = nullptr;
  cgvk::Capabilities capabilities;
  cgvk::Bindless bindless;
  cg_texture *fallback_texture = nullptr;
  cg_sampler *fallback_sampler = nullptr;
  std::array<cgvk::FrameSlot, cgvk::frames_in_flight> frames;
  uint32_t frame_index = 0;
  uint64_t submitted_serial = 0;
  uint64_t completed_serial = 0;
  bool recording = false;
  bool presenting = false;
  float last_gpu_seconds = 0.0f;
  std::vector<cgvk::Retirement> retirements;
  cgvk::Surface surface;

  ~cg_device();
};

namespace cgvk {

struct InstanceSetup {
  vk::Instance instance;
  vk::DebugUtilsMessengerEXT messenger;
  bool debug_utils;
};

struct PhysicalChoice {
  vk::PhysicalDevice physical;
  uint32_t queue_family;
};

void report_failure(const char *operation, const char *reason);

InstanceSetup create_instance();
PhysicalChoice pick_physical_device(vk::Instance instance);
bool device_extension_available(vk::PhysicalDevice physical, const char *name);
void create_logical_device(cg_device &device);
void create_allocator(cg_device &device);

void create_bindless(cg_device &device);
void destroy_bindless(cg_device &device);
void write_sampled_image(cg_device &device, uint32_t index, vk::ImageView view);
void write_sampler(cg_device &device, uint32_t index, vk::Sampler sampler);
vk::DescriptorSet create_accel_set(cg_device &device, vk::AccelerationStructureKHR scene);

void create_frames(cg_device &device);
void probe_timestamps(cg_device &device);
void create_frame_timer(cg_device &device, FrameSlot &slot);
void destroy_frame_timer(cg_device &device, FrameSlot &slot);
void record_frame_start(cg_device &device, FrameSlot &slot);
void record_frame_finish(cg_device &device, FrameSlot &slot, vk::CommandBuffer commands);
void read_frame_time(cg_device &device, FrameSlot &slot);
void destroy_frames(cg_device &device);
void retire(cg_device &device, std::function<void()> release);
void collect_retirements(cg_device &device);
void release_all_retirements(cg_device &device);
void submit_immediately(cg_device &device, const std::function<void(vk::CommandBuffer)> &record);

bool prepare_swapchain(cg_device &device);
bool acquire_next_image(cg_device &device, vk::Semaphore acquired);
void present_current_image(cg_device &device);
void release_surface(cg_device &device);

vk::BufferUsageFlags general_buffer_usage(const cg_device &device);
cg_buffer create_raw_buffer(cg_device &device, uint64_t size, vk::BufferUsageFlags usage, cg_memory memory, uint64_t alignment);
void retire_raw_buffer(cg_device &device, const cg_buffer &buffer);
cg_texture *make_texture(cg_device &device, const cg_texture_desc &desc);
void free_texture(cg_device &device, const cg_texture &texture);
cg_sampler *make_sampler(cg_device &device, const cg_sampler_desc &desc);
void create_fallbacks(cg_device &device);
void destroy_fallbacks(cg_device &device);

void name_object(cg_device &device, vk::ObjectType type, uint64_t handle, const char *label);

template <typename Handle>
void name_handle(cg_device &device, Handle handle, const char *label) {
  using Native = typename Handle::CType;
  name_object(device, Handle::objectType, reinterpret_cast<uint64_t>(static_cast<Native>(handle)), label);
}

vk::Format to_vk_format(cg_format format);
cg_format from_vk_format(vk::Format format);
vk::ImageAspectFlags aspect_of(vk::Format format);
vk::CompareOp to_compare_op(cg_compare compare);
vk::CullModeFlags to_cull_mode(cg_cull cull);
vk::PipelineColorBlendAttachmentState to_blend_state(cg_blend blend);
vk::AttachmentLoadOp to_load_op(cg_load load);
vk::Filter to_filter(cg_filter filter);
vk::SamplerMipmapMode to_mipmap_mode(cg_filter filter);
vk::SamplerAddressMode to_address_mode(cg_address address);

vk::ImageSubresourceRange whole_range(const cg_texture &texture);
vk::ImageSubresourceRange mip_range(const cg_texture &texture, uint32_t mip);
vk::ImageMemoryBarrier2 transition_barrier(cg_texture &texture, ImageUse target, bool discard);
vk::ImageMemoryBarrier2 mip_barrier(const cg_texture &texture, uint32_t mip, ImageUse from, ImageUse to);
void transition(vk::CommandBuffer commands, cg_texture &texture, ImageUse target, bool discard);
void record_barriers(vk::CommandBuffer commands, std::span<const vk::MemoryBarrier2> memory, std::span<const vk::ImageMemoryBarrier2> images);
vk::MemoryBarrier2 full_memory_barrier();
vk::MemoryBarrier2 host_read_barrier();
vk::MemoryBarrier2 accel_build_barrier();
void record_memory_barrier(vk::CommandBuffer commands, const vk::MemoryBarrier2 &barrier);

cg_device *device_create() noexcept;
void device_destroy(cg_device *device) noexcept;
void device_info(cg_device *device, cg_device_info *info) noexcept;

bool surface_attach(cg_device *device, void *sdl_window) noexcept;
void surface_detach(cg_device *device) noexcept;
void surface_resize(cg_device *device, uint32_t width, uint32_t height) noexcept;
cg_format surface_format(cg_device *device) noexcept;

cg_buffer *buffer_create(cg_device *device, uint64_t size, cg_memory memory, const char *label) noexcept;
void buffer_destroy(cg_device *device, cg_buffer *buffer) noexcept;
void *buffer_contents(cg_buffer *buffer) noexcept;
uint64_t buffer_address(cg_buffer *buffer) noexcept;

cg_texture *texture_create(cg_device *device, const cg_texture_desc *desc) noexcept;
void texture_destroy(cg_device *device, cg_texture *texture) noexcept;
uint64_t texture_handle(cg_texture *texture) noexcept;

cg_sampler *sampler_create(cg_device *device, const cg_sampler_desc *desc) noexcept;
void sampler_destroy(cg_device *device, cg_sampler *sampler) noexcept;
uint64_t sampler_handle(cg_sampler *sampler) noexcept;

cg_pipeline *pipeline_create(cg_device *device, const cg_pipeline_desc *desc) noexcept;
cg_pipeline *compute_pipeline_create(cg_device *device, const cg_compute_desc *desc) noexcept;
void pipeline_destroy(cg_device *device, cg_pipeline *pipeline) noexcept;

cg_accel *accel_create_geometry(cg_device *device, cg_cmd *cmd, cg_buffer *vertices, uint32_t vertex_count, uint32_t vertex_stride, cg_buffer *indices, uint32_t index_count) noexcept;
cg_accel *accel_create_scene(cg_device *device, cg_cmd *cmd, const cg_accel_instance *instances, uint32_t count) noexcept;
void accel_destroy(cg_device *device, cg_accel *accel) noexcept;

cg_upscaler *upscaler_create(cg_device *device, const cg_upscaler_desc *desc) noexcept;
void upscaler_destroy(cg_device *device, cg_upscaler *upscaler) noexcept;
void cmd_upscale(cg_cmd *cmd, cg_upscaler *upscaler, const cg_upscale *frame) noexcept;
cg_interpolator *interpolator_create(cg_device *device, const cg_upscaler_desc *desc) noexcept;
void interpolator_destroy(cg_device *device, cg_interpolator *interpolator) noexcept;
void cmd_interpolate(cg_cmd *cmd, cg_interpolator *interpolator, const cg_interpolate *frame) noexcept;

cg_cmd *frame_begin(cg_device *device) noexcept;
cg_texture *frame_target(cg_device *device) noexcept;
void frame_end(cg_device *device, cg_cmd *cmd) noexcept;
void frame_end_pair(cg_device *device, cg_cmd *cmd, cg_texture *first, cg_texture *second, float spacing) noexcept;
float frame_gpu_seconds(cg_device *device) noexcept;

void cmd_copy_buffer(cg_cmd *cmd, cg_buffer *src, uint64_t src_offset, cg_buffer *dst, uint64_t dst_offset, uint64_t size) noexcept;
void cmd_copy_to_texture(cg_cmd *cmd, cg_buffer *src, uint64_t src_offset, uint32_t bytes_per_row, cg_texture *dst, uint32_t mip, uint32_t layer, uint32_t width, uint32_t height) noexcept;
void cmd_generate_mips(cg_cmd *cmd, cg_texture *texture) noexcept;
void cmd_copy_texture_to_buffer(cg_cmd *cmd, cg_texture *src, cg_buffer *dst, uint64_t dst_offset, uint32_t bytes_per_row) noexcept;
void cmd_begin_pass(cg_cmd *cmd, const cg_pass_desc *desc) noexcept;
void cmd_end_pass(cg_cmd *cmd) noexcept;
void cmd_set_pipeline(cg_cmd *cmd, cg_pipeline *pipeline) noexcept;
void cmd_push(cg_cmd *cmd, const void *data, uint32_t size) noexcept;
void cmd_draw(cg_cmd *cmd, uint32_t vertex_count, uint32_t instance_count, uint32_t first_vertex) noexcept;
void cmd_draw_indexed(cg_cmd *cmd, cg_buffer *indices, uint32_t index_count, uint32_t instance_count, uint32_t first_index) noexcept;
void cmd_begin_compute(cg_cmd *cmd, const char *label) noexcept;
void cmd_end_compute(cg_cmd *cmd) noexcept;
void cmd_set_compute_pipeline(cg_cmd *cmd, cg_pipeline *pipeline) noexcept;
void cmd_set_accel(cg_cmd *cmd, cg_accel *scene) noexcept;
void cmd_dispatch(cg_cmd *cmd, uint32_t groups_x, uint32_t groups_y, uint32_t groups_z) noexcept;

}
