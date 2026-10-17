#include "internal.hpp"

namespace cgvk {
namespace {

vk::Offset3D mip_corner(const cg_texture &texture, uint32_t mip) {
  return {
      .x = static_cast<int32_t>(std::max(texture.extent.width >> mip, 1u)),
      .y = static_cast<int32_t>(std::max(texture.extent.height >> mip, 1u)),
      .z = 1,
  };
}

vk::ImageSubresourceLayers mip_layers(const cg_texture &texture, uint32_t mip) {
  return {.aspectMask = texture.aspect, .mipLevel = mip, .baseArrayLayer = 0, .layerCount = texture.layers};
}

void blit_mip(vk::CommandBuffer commands, const cg_texture &texture, uint32_t mip) {
  vk::ImageBlit2 region{
      .srcSubresource = mip_layers(texture, mip - 1),
      .srcOffsets = std::array<vk::Offset3D, 2>{vk::Offset3D{}, mip_corner(texture, mip - 1)},
      .dstSubresource = mip_layers(texture, mip),
      .dstOffsets = std::array<vk::Offset3D, 2>{vk::Offset3D{}, mip_corner(texture, mip)},
  };
  commands.blitImage2({
      .srcImage = texture.image,
      .srcImageLayout = vk::ImageLayout::eTransferSrcOptimal,
      .dstImage = texture.image,
      .dstImageLayout = vk::ImageLayout::eTransferDstOptimal,
      .regionCount = 1,
      .pRegions = &region,
      .filter = vk::Filter::eLinear,
  });
}

void begin_label(cg_cmd &cmd, const char *label) {
  cmd.pass_labelled = cmd.device->capabilities.debug_utils && label != nullptr;
  if (cmd.pass_labelled) cmd.commands.beginDebugUtilsLabelEXT({.pLabelName = label});
}

void end_label(cg_cmd &cmd) {
  if (cmd.pass_labelled) cmd.commands.endDebugUtilsLabelEXT();
  cmd.pass_labelled = false;
}

vk::ClearValue color_clear(const cg_color_attachment &attachment) {
  return {.color = {.float32 = std::array<float, 4>{attachment.clear[0], attachment.clear[1], attachment.clear[2], attachment.clear[3]}}};
}

vk::RenderingAttachmentInfo color_attachment_info(const cg_color_attachment &attachment) {
  return {
      .imageView = attachment.texture->attachment_view,
      .imageLayout = vk::ImageLayout::eColorAttachmentOptimal,
      .loadOp = to_load_op(attachment.load),
      .storeOp = attachment.store ? vk::AttachmentStoreOp::eStore : vk::AttachmentStoreOp::eDontCare,
      .clearValue = color_clear(attachment),
  };
}

vk::RenderingAttachmentInfo depth_attachment_info(const cg_depth_attachment &attachment) {
  return {
      .imageView = attachment.texture->attachment_view,
      .imageLayout = vk::ImageLayout::eDepthStencilAttachmentOptimal,
      .loadOp = to_load_op(attachment.load),
      .storeOp = attachment.store ? vk::AttachmentStoreOp::eStore : vk::AttachmentStoreOp::eDontCare,
      .clearValue = {.depthStencil = {.depth = attachment.clear, .stencil = 0}},
  };
}

vk::Extent2D pass_extent(const cg_pass_desc &desc) {
  return desc.color_count > 0 ? desc.colors[0].texture->extent : desc.depth.texture->extent;
}

void prepare_attachments(cg_cmd &cmd, const cg_pass_desc &desc) {
  std::vector<vk::ImageMemoryBarrier2> barriers;
  cmd.pass_attachment_count = 0;
  for (uint32_t index = 0; index < desc.color_count; ++index) {
    cg_texture *texture = desc.colors[index].texture;
    barriers.push_back(transition_barrier(*texture, ImageUse::color_attachment, desc.colors[index].load != CG_LOAD_LOAD));
    cmd.pass_attachments[cmd.pass_attachment_count++] = texture;
  }
  if (desc.depth.texture != nullptr) {
    barriers.push_back(transition_barrier(*desc.depth.texture, ImageUse::depth_attachment, desc.depth.load != CG_LOAD_LOAD));
    cmd.pass_attachments[cmd.pass_attachment_count++] = desc.depth.texture;
  }
  std::array<vk::MemoryBarrier2, 1> ordering{full_memory_barrier()};
  record_barriers(cmd.commands, ordering, barriers);
}

void set_full_viewport(vk::CommandBuffer commands, vk::Extent2D extent) {
  vk::Viewport viewport{
      .x = 0.0f,
      .y = 0.0f,
      .width = static_cast<float>(extent.width),
      .height = static_cast<float>(extent.height),
      .minDepth = 0.0f,
      .maxDepth = 1.0f,
  };
  commands.setViewport(0, viewport);
  commands.setScissor(0, vk::Rect2D{.offset = {}, .extent = extent});
}

}

void cmd_copy_buffer(cg_cmd *cmd, cg_buffer *src, uint64_t src_offset, cg_buffer *dst, uint64_t dst_offset, uint64_t size) noexcept {
  record_memory_barrier(cmd->commands, full_memory_barrier());
  cmd->commands.copyBuffer(src->buffer, dst->buffer, vk::BufferCopy{.srcOffset = src_offset, .dstOffset = dst_offset, .size = size});
}

void cmd_copy_to_texture(cg_cmd *cmd, cg_buffer *src, uint64_t src_offset, uint32_t bytes_per_row, cg_texture *dst,
                         uint32_t mip, uint32_t layer, uint32_t width, uint32_t height) noexcept {
  std::array<vk::MemoryBarrier2, 1> before{full_memory_barrier()};
  std::array<vk::ImageMemoryBarrier2, 1> to_transfer{transition_barrier(*dst, ImageUse::transfer_dst, false)};
  record_barriers(cmd->commands, before, to_transfer);
  vk::BufferImageCopy region{
      .bufferOffset = src_offset,
      .bufferRowLength = bytes_per_row / vk::blockSize(dst->format),
      .bufferImageHeight = 0,
      .imageSubresource = {.aspectMask = dst->aspect, .mipLevel = mip, .baseArrayLayer = layer, .layerCount = 1},
      .imageOffset = {},
      .imageExtent = {.width = width, .height = height, .depth = 1},
  };
  cmd->commands.copyBufferToImage(src->buffer, dst->image, vk::ImageLayout::eTransferDstOptimal, region);
  transition(cmd->commands, *dst, ImageUse::sampled, false);
}

void cmd_generate_mips(cg_cmd *cmd, cg_texture *texture) noexcept {
  if (texture->mip_levels < 2) return;
  std::array<vk::MemoryBarrier2, 1> before{full_memory_barrier()};
  std::array<vk::ImageMemoryBarrier2, 1> to_transfer{transition_barrier(*texture, ImageUse::transfer_dst, false)};
  record_barriers(cmd->commands, before, to_transfer);
  for (uint32_t mip = 1; mip < texture->mip_levels; ++mip) {
    std::array<vk::ImageMemoryBarrier2, 1> to_source{mip_barrier(*texture, mip - 1, ImageUse::transfer_dst, ImageUse::transfer_src)};
    record_barriers(cmd->commands, {}, to_source);
    blit_mip(cmd->commands, *texture, mip);
    std::array<vk::ImageMemoryBarrier2, 1> to_sampled{mip_barrier(*texture, mip - 1, ImageUse::transfer_src, ImageUse::sampled)};
    record_barriers(cmd->commands, {}, to_sampled);
  }
  std::array<vk::ImageMemoryBarrier2, 1> last_to_sampled{mip_barrier(*texture, texture->mip_levels - 1, ImageUse::transfer_dst, ImageUse::sampled)};
  record_barriers(cmd->commands, {}, last_to_sampled);
  texture->use = ImageUse::sampled;
}

void cmd_copy_texture_to_buffer(cg_cmd *cmd, cg_texture *src, cg_buffer *dst, uint64_t dst_offset, uint32_t bytes_per_row) noexcept {
  std::array<vk::MemoryBarrier2, 1> before{full_memory_barrier()};
  std::array<vk::ImageMemoryBarrier2, 1> to_source{transition_barrier(*src, ImageUse::transfer_src, false)};
  record_barriers(cmd->commands, before, to_source);
  vk::BufferImageCopy region{
      .bufferOffset = dst_offset,
      .bufferRowLength = bytes_per_row / vk::blockSize(src->format),
      .bufferImageHeight = 0,
      .imageSubresource = {.aspectMask = src->aspect, .mipLevel = 0, .baseArrayLayer = 0, .layerCount = 1},
      .imageOffset = {},
      .imageExtent = {.width = src->extent.width, .height = src->extent.height, .depth = 1},
  };
  cmd->commands.copyImageToBuffer(src->image, vk::ImageLayout::eTransferSrcOptimal, dst->buffer, region);
  if (src->usage & CG_TEXTURE_SAMPLED) transition(cmd->commands, *src, ImageUse::sampled, false);
}

void cmd_begin_pass(cg_cmd *cmd, const cg_pass_desc *desc) noexcept {
  begin_label(*cmd, desc->label);
  prepare_attachments(*cmd, *desc);
  std::array<vk::RenderingAttachmentInfo, CG_MAX_COLOR> colors{};
  for (uint32_t index = 0; index < desc->color_count; ++index) colors[index] = color_attachment_info(desc->colors[index]);
  bool has_depth = desc->depth.texture != nullptr;
  vk::RenderingAttachmentInfo depth = has_depth ? depth_attachment_info(desc->depth) : vk::RenderingAttachmentInfo{};
  vk::Extent2D extent = pass_extent(*desc);
  cmd->commands.beginRendering({
      .renderArea = {.offset = {}, .extent = extent},
      .layerCount = 1,
      .colorAttachmentCount = desc->color_count,
      .pColorAttachments = colors.data(),
      .pDepthAttachment = has_depth ? &depth : nullptr,
  });
  set_full_viewport(cmd->commands, extent);
}

void cmd_end_pass(cg_cmd *cmd) noexcept {
  cmd->commands.endRendering();
  std::vector<vk::ImageMemoryBarrier2> barriers;
  for (uint32_t index = 0; index < cmd->pass_attachment_count; ++index) {
    cg_texture *texture = cmd->pass_attachments[index];
    if (texture->usage & CG_TEXTURE_SAMPLED) barriers.push_back(transition_barrier(*texture, ImageUse::sampled, false));
  }
  if (!barriers.empty()) record_barriers(cmd->commands, {}, barriers);
  cmd->pass_attachment_count = 0;
  end_label(*cmd);
}

void cmd_set_pipeline(cg_cmd *cmd, cg_pipeline *pipeline) noexcept {
  cmd->commands.bindPipeline(vk::PipelineBindPoint::eGraphics, pipeline->pipeline);
}

void cmd_push(cg_cmd *cmd, const void *data, uint32_t size) noexcept {
  cmd->commands.pushConstants(cmd->device->bindless.pipeline_layout, vk::ShaderStageFlagBits::eAll, 0, std::min(size, static_cast<uint32_t>(CG_MAX_PUSH)), data);
}

void cmd_draw(cg_cmd *cmd, uint32_t vertex_count, uint32_t instance_count, uint32_t first_vertex) noexcept {
  cmd->commands.draw(vertex_count, instance_count, first_vertex, 0);
}

void cmd_draw_indexed(cg_cmd *cmd, cg_buffer *indices, uint32_t index_count, uint32_t instance_count, uint32_t first_index) noexcept {
  cmd->commands.bindIndexBuffer(indices->buffer, 0, vk::IndexType::eUint32);
  cmd->commands.drawIndexed(index_count, instance_count, first_index, 0, 0);
}

void cmd_begin_compute(cg_cmd *cmd, const char *label) noexcept {
  begin_label(*cmd, label);
  record_memory_barrier(cmd->commands, full_memory_barrier());
}

void cmd_end_compute(cg_cmd *cmd) noexcept {
  end_label(*cmd);
}

void cmd_set_compute_pipeline(cg_cmd *cmd, cg_pipeline *pipeline) noexcept {
  cmd->commands.bindPipeline(vk::PipelineBindPoint::eCompute, pipeline->pipeline);
}

void cmd_set_accel(cg_cmd *cmd, cg_accel *scene) noexcept {
  cmd->commands.bindDescriptorSets(vk::PipelineBindPoint::eCompute, cmd->device->bindless.pipeline_layout, accel_set_index, scene->set, {});
}

void cmd_dispatch(cg_cmd *cmd, uint32_t groups_x, uint32_t groups_y, uint32_t groups_z) noexcept {
  cmd->commands.dispatch(groups_x, groups_y, groups_z);
}

}
