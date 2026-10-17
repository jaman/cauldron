#include "internal.hpp"

namespace cgvk {
namespace {

struct UseState {
  vk::ImageLayout layout;
  vk::PipelineStageFlags2 stages;
  vk::AccessFlags2 access;
};

using Stage = vk::PipelineStageFlagBits2;
using Access = vk::AccessFlagBits2;

constexpr vk::PipelineStageFlags2 shader_stages = Stage::eVertexShader | Stage::eFragmentShader | Stage::eComputeShader;

constexpr std::array<UseState, 8> use_states{{
    {vk::ImageLayout::eUndefined, Stage::eNone, Access::eNone},
    {vk::ImageLayout::eUndefined, Stage::eColorAttachmentOutput, Access::eNone},
    {vk::ImageLayout::eTransferDstOptimal, Stage::eAllTransfer, Access::eTransferWrite},
    {vk::ImageLayout::eTransferSrcOptimal, Stage::eAllTransfer, Access::eTransferRead},
    {vk::ImageLayout::eShaderReadOnlyOptimal, shader_stages, Access::eShaderRead},
    {vk::ImageLayout::eColorAttachmentOptimal, Stage::eColorAttachmentOutput, Access::eColorAttachmentRead | Access::eColorAttachmentWrite},
    {vk::ImageLayout::eDepthStencilAttachmentOptimal, Stage::eEarlyFragmentTests | Stage::eLateFragmentTests,
     Access::eDepthStencilAttachmentRead | Access::eDepthStencilAttachmentWrite},
    {vk::ImageLayout::ePresentSrcKHR, Stage::eNone, Access::eNone},
}};

const UseState &state_of(ImageUse use) {
  return use_states[static_cast<size_t>(use)];
}

vk::ImageMemoryBarrier2 barrier_between(const cg_texture &texture, const UseState &from, const UseState &to,
                                        vk::ImageLayout old_layout, vk::ImageSubresourceRange range) {
  return {
      .srcStageMask = from.stages,
      .srcAccessMask = from.access,
      .dstStageMask = to.stages,
      .dstAccessMask = to.access,
      .oldLayout = old_layout,
      .newLayout = to.layout,
      .srcQueueFamilyIndex = vk::QueueFamilyIgnored,
      .dstQueueFamilyIndex = vk::QueueFamilyIgnored,
      .image = texture.image,
      .subresourceRange = range,
  };
}

}

vk::ImageSubresourceRange whole_range(const cg_texture &texture) {
  return {.aspectMask = texture.aspect, .baseMipLevel = 0, .levelCount = texture.mip_levels, .baseArrayLayer = 0, .layerCount = texture.layers};
}

vk::ImageSubresourceRange mip_range(const cg_texture &texture, uint32_t mip) {
  return {.aspectMask = texture.aspect, .baseMipLevel = mip, .levelCount = 1, .baseArrayLayer = 0, .layerCount = texture.layers};
}

vk::ImageMemoryBarrier2 transition_barrier(cg_texture &texture, ImageUse target, bool discard) {
  const UseState &from = state_of(texture.use);
  vk::ImageLayout old_layout = discard ? vk::ImageLayout::eUndefined : from.layout;
  texture.use = target;
  return barrier_between(texture, from, state_of(target), old_layout, whole_range(texture));
}

vk::ImageMemoryBarrier2 mip_barrier(const cg_texture &texture, uint32_t mip, ImageUse from, ImageUse to) {
  const UseState &source = state_of(from);
  return barrier_between(texture, source, state_of(to), source.layout, mip_range(texture, mip));
}

void record_barriers(vk::CommandBuffer commands, std::span<const vk::MemoryBarrier2> memory, std::span<const vk::ImageMemoryBarrier2> images) {
  commands.pipelineBarrier2({
      .memoryBarrierCount = static_cast<uint32_t>(memory.size()),
      .pMemoryBarriers = memory.data(),
      .imageMemoryBarrierCount = static_cast<uint32_t>(images.size()),
      .pImageMemoryBarriers = images.data(),
  });
}

void transition(vk::CommandBuffer commands, cg_texture &texture, ImageUse target, bool discard) {
  vk::ImageMemoryBarrier2 barrier = transition_barrier(texture, target, discard);
  record_barriers(commands, {}, {&barrier, 1});
}

vk::MemoryBarrier2 full_memory_barrier() {
  return {
      .srcStageMask = Stage::eAllCommands,
      .srcAccessMask = Access::eMemoryWrite,
      .dstStageMask = Stage::eAllCommands,
      .dstAccessMask = Access::eMemoryRead | Access::eMemoryWrite,
  };
}

vk::MemoryBarrier2 host_read_barrier() {
  return {
      .srcStageMask = Stage::eAllCommands,
      .srcAccessMask = Access::eMemoryWrite,
      .dstStageMask = Stage::eHost,
      .dstAccessMask = Access::eHostRead,
  };
}

vk::MemoryBarrier2 accel_build_barrier() {
  return {
      .srcStageMask = Stage::eAccelerationStructureBuildKHR,
      .srcAccessMask = Access::eAccelerationStructureWriteKHR,
      .dstStageMask = Stage::eAllCommands,
      .dstAccessMask = Access::eAccelerationStructureReadKHR | Access::eShaderRead,
  };
}

void record_memory_barrier(vk::CommandBuffer commands, const vk::MemoryBarrier2 &barrier) {
  record_barriers(commands, {&barrier, 1}, {});
}

}
