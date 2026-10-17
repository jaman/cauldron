#include "internal.hpp"

#include <algorithm>
#include <cstdint>

namespace cgvk {
namespace {

void update_completed_serial(cg_device &device) {
  for (FrameSlot &slot : device.frames) {
    bool newer = slot.serial > device.completed_serial;
    if (newer && device.device.getFenceStatus(slot.done) == vk::Result::eSuccess) device.completed_serial = slot.serial;
  }
}

void wait_for_slot(cg_device &device, FrameSlot &slot) {
  static_cast<void>(device.device.waitForFences(slot.done, vk::True, UINT64_MAX));
}

void begin_recording(cg_device &device, FrameSlot &slot) {
  device.device.resetFences(slot.done);
  device.device.resetCommandPool(slot.pool);
  slot.cmd.commands.begin(vk::CommandBufferBeginInfo{.flags = vk::CommandBufferUsageFlagBits::eOneTimeSubmit});
  record_frame_start(device, slot);
  slot.cmd.commands.bindDescriptorSets(vk::PipelineBindPoint::eGraphics, device.bindless.pipeline_layout, 0, device.bindless.set, {});
  slot.cmd.commands.bindDescriptorSets(vk::PipelineBindPoint::eCompute, device.bindless.pipeline_layout, 0, device.bindless.set, {});
  slot.cmd.pass_attachment_count = 0;
  device.recording = true;
}

void mark_submitted(cg_device &device, FrameSlot &slot) {
  device.submitted_serial += 1;
  slot.serial = device.submitted_serial;
  device.recording = false;
}

void submit_commands(cg_device &device, vk::CommandBuffer commands, std::span<const vk::SemaphoreSubmitInfo> waits,
                     std::span<const vk::SemaphoreSubmitInfo> signals, vk::Fence fence) {
  vk::CommandBufferSubmitInfo command{.commandBuffer = commands};
  device.queue.submit2(vk::SubmitInfo2{
                           .waitSemaphoreInfoCount = static_cast<uint32_t>(waits.size()),
                           .pWaitSemaphoreInfos = waits.data(),
                           .commandBufferInfoCount = 1,
                           .pCommandBufferInfos = &command,
                           .signalSemaphoreInfoCount = static_cast<uint32_t>(signals.size()),
                           .pSignalSemaphoreInfos = signals.data(),
                       },
                       fence);
}

void submit_to_current_image(cg_device &device, vk::CommandBuffer commands, vk::Semaphore acquired, vk::Fence fence) {
  Swapchain &swapchain = device.surface.swapchain;
  std::array<vk::SemaphoreSubmitInfo, 1> waits{{{.semaphore = acquired, .stageMask = vk::PipelineStageFlagBits2::eAllCommands}}};
  std::array<vk::SemaphoreSubmitInfo, 1> signals{{{.semaphore = swapchain.rendered[swapchain.current], .stageMask = vk::PipelineStageFlagBits2::eAllCommands}}};
  submit_commands(device, commands, waits, signals, fence);
  present_current_image(device);
}

void finish_presented_frame(cg_device &device, FrameSlot &slot) {
  Swapchain &swapchain = device.surface.swapchain;
  std::array<vk::MemoryBarrier2, 1> host_visible{host_read_barrier()};
  std::array<vk::ImageMemoryBarrier2, 1> to_present{transition_barrier(swapchain.images[swapchain.current], ImageUse::present, false)};
  record_barriers(slot.cmd.commands, host_visible, to_present);
  record_frame_finish(device, slot, slot.cmd.commands);
  slot.cmd.commands.end();
  submit_to_current_image(device, slot.cmd.commands, slot.acquired, slot.done);
  mark_submitted(device, slot);
}

void finish_offscreen_frame(cg_device &device, FrameSlot &slot) {
  record_memory_barrier(slot.cmd.commands, host_read_barrier());
  record_frame_finish(device, slot, slot.cmd.commands);
  slot.cmd.commands.end();
  submit_commands(device, slot.cmd.commands, {}, {}, slot.done);
  mark_submitted(device, slot);
}

void record_copy_to_current_image(cg_device &device, vk::CommandBuffer commands, cg_texture &source) {
  Swapchain &swapchain = device.surface.swapchain;
  cg_texture &image = swapchain.images[swapchain.current];
  std::array<vk::MemoryBarrier2, 1> ordering{full_memory_barrier()};
  std::array<vk::ImageMemoryBarrier2, 2> to_copy{transition_barrier(source, ImageUse::transfer_src, false),
                                                 transition_barrier(image, ImageUse::transfer_dst, true)};
  record_barriers(commands, ordering, to_copy);
  vk::ImageSubresourceLayers layer{.aspectMask = vk::ImageAspectFlagBits::eColor, .mipLevel = 0, .baseArrayLayer = 0, .layerCount = 1};
  vk::ImageCopy region{
      .srcSubresource = layer,
      .srcOffset = {},
      .dstSubresource = layer,
      .dstOffset = {},
      .extent = {.width = std::min(source.extent.width, image.extent.width), .height = std::min(source.extent.height, image.extent.height), .depth = 1},
  };
  commands.copyImage(source.image, vk::ImageLayout::eTransferSrcOptimal, image.image, vk::ImageLayout::eTransferDstOptimal, region);
  std::vector<vk::ImageMemoryBarrier2> after{transition_barrier(image, ImageUse::present, false)};
  if (source.usage & CG_TEXTURE_SAMPLED) after.push_back(transition_barrier(source, ImageUse::sampled, false));
  record_barriers(commands, {}, after);
}

void finish_first_of_pair(cg_device &device, FrameSlot &slot, cg_texture &first) {
  record_memory_barrier(slot.cmd.commands, host_read_barrier());
  record_copy_to_current_image(device, slot.cmd.commands, first);
  slot.cmd.commands.end();
  submit_to_current_image(device, slot.cmd.commands, slot.acquired, {});
}

void finish_second_of_pair(cg_device &device, FrameSlot &slot, cg_texture &second) {
  vk::CommandBuffer commands = slot.pair_commands;
  commands.begin(vk::CommandBufferBeginInfo{.flags = vk::CommandBufferUsageFlagBits::eOneTimeSubmit});
  bool acquired = acquire_next_image(device, slot.second_acquired);
  if (acquired) record_copy_to_current_image(device, commands, second);
  record_frame_finish(device, slot, commands);
  commands.end();
  if (acquired) {
    submit_to_current_image(device, commands, slot.second_acquired, slot.done);
  } else {
    submit_commands(device, commands, {}, {}, slot.done);
  }
  mark_submitted(device, slot);
}

void finish_pair(cg_device &device, FrameSlot &slot, cg_texture &first, cg_texture &second) {
  finish_first_of_pair(device, slot, first);
  finish_second_of_pair(device, slot, second);
}

void advance_frame(cg_device &device) {
  device.presenting = false;
  device.frame_index = (device.frame_index + 1) % frames_in_flight;
  device.surface.frame_lock.unlock();
}

bool begin_presented_frame(cg_device &device, FrameSlot &slot) {
  return prepare_swapchain(device) && acquire_next_image(device, slot.acquired);
}

FrameSlot create_frame_slot(cg_device &device) {
  FrameSlot slot;
  slot.pool = device.device.createCommandPool({.queueFamilyIndex = device.queue_family});
  slot.done = device.device.createFence({.flags = vk::FenceCreateFlagBits::eSignaled});
  slot.acquired = device.device.createSemaphore({});
  slot.second_acquired = device.device.createSemaphore({});
  slot.cmd.device = &device;
  std::vector<vk::CommandBuffer> commands = device.device.allocateCommandBuffers({
      .commandPool = slot.pool,
      .level = vk::CommandBufferLevel::ePrimary,
      .commandBufferCount = 2,
  });
  slot.cmd.commands = commands[0];
  slot.pair_commands = commands[1];
  create_frame_timer(device, slot);
  return slot;
}

}

void create_frames(cg_device &device) {
  for (FrameSlot &slot : device.frames) slot = create_frame_slot(device);
}

void destroy_frames(cg_device &device) {
  for (FrameSlot &slot : device.frames) {
    device.device.destroySemaphore(slot.acquired);
    device.device.destroySemaphore(slot.second_acquired);
    destroy_frame_timer(device, slot);
    device.device.destroyFence(slot.done);
    device.device.destroyCommandPool(slot.pool);
  }
}

void retire(cg_device &device, std::function<void()> release) {
  uint64_t serial = device.submitted_serial + (device.recording ? 1 : 0);
  device.retirements.push_back({.serial = serial, .release = std::move(release)});
}

void collect_retirements(cg_device &device) {
  update_completed_serial(device);
  std::vector<Retirement> pending;
  std::vector<Retirement> due;
  for (Retirement &retirement : device.retirements) {
    (retirement.serial <= device.completed_serial ? due : pending).push_back(std::move(retirement));
  }
  device.retirements = std::move(pending);
  for (Retirement &retirement : due) retirement.release();
}

void release_all_retirements(cg_device &device) {
  for (Retirement &retirement : device.retirements) retirement.release();
  device.retirements.clear();
}

void submit_immediately(cg_device &device, const std::function<void(vk::CommandBuffer)> &record) {
  vk::CommandPool pool = device.device.createCommandPool({
      .flags = vk::CommandPoolCreateFlagBits::eTransient,
      .queueFamilyIndex = device.queue_family,
  });
  vk::CommandBuffer commands = device.device.allocateCommandBuffers({
      .commandPool = pool,
      .level = vk::CommandBufferLevel::ePrimary,
      .commandBufferCount = 1,
  })[0];
  commands.begin(vk::CommandBufferBeginInfo{.flags = vk::CommandBufferUsageFlagBits::eOneTimeSubmit});
  record(commands);
  commands.end();
  vk::Fence done = device.device.createFence({});
  vk::CommandBufferSubmitInfo command{.commandBuffer = commands};
  device.queue.submit2(vk::SubmitInfo2{.commandBufferInfoCount = 1, .pCommandBufferInfos = &command}, done);
  static_cast<void>(device.device.waitForFences(done, vk::True, UINT64_MAX));
  device.device.destroyFence(done);
  device.device.destroyCommandPool(pool);
}

cg_cmd *frame_begin(cg_device *device) noexcept {
  std::unique_lock lock(device->surface.mutex);
  FrameSlot &slot = device->frames[device->frame_index];
  wait_for_slot(*device, slot);
  read_frame_time(*device, slot);
  collect_retirements(*device);
  bool presenting = static_cast<bool>(device->surface.handle);
  if (presenting && !begin_presented_frame(*device, slot)) return nullptr;
  begin_recording(*device, slot);
  device->presenting = presenting;
  device->surface.frame_lock = std::move(lock);
  return &slot.cmd;
}

cg_texture *frame_target(cg_device *device) noexcept {
  Swapchain &swapchain = device->surface.swapchain;
  if (!device->recording || !device->presenting) return nullptr;
  return &swapchain.images[swapchain.current];
}

void frame_end(cg_device *device, cg_cmd *) noexcept {
  FrameSlot &slot = device->frames[device->frame_index];
  if (device->presenting) {
    finish_presented_frame(*device, slot);
  } else {
    finish_offscreen_frame(*device, slot);
  }
  advance_frame(*device);
}

void frame_end_pair(cg_device *device, cg_cmd *cmd, cg_texture *first, cg_texture *second, float) noexcept {
  if (!device->presenting || !device->surface.swapchain.copyable) {
    frame_end(device, cmd);
    return;
  }
  finish_pair(*device, device->frames[device->frame_index], *first, *second);
  advance_frame(*device);
}

}
