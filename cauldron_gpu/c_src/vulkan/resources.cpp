#include "internal.hpp"

#include <algorithm>
#include <memory>
#include <stdexcept>

namespace cgvk {
namespace {

constexpr vk::BufferUsageFlags base_buffer_usage = vk::BufferUsageFlagBits::eStorageBuffer | vk::BufferUsageFlagBits::eIndexBuffer |
                                                   vk::BufferUsageFlagBits::eTransferSrc | vk::BufferUsageFlagBits::eTransferDst |
                                                   vk::BufferUsageFlagBits::eShaderDeviceAddress;

VmaAllocationCreateInfo host_allocation_info(VmaAllocationCreateFlags access) {
  VmaAllocationCreateInfo info{};
  info.usage = VMA_MEMORY_USAGE_AUTO;
  info.flags = access | VMA_ALLOCATION_CREATE_MAPPED_BIT;
  info.requiredFlags = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
  return info;
}

VmaAllocationCreateInfo buffer_allocation_info(cg_memory memory) {
  if (memory == CG_MEMORY_UPLOAD) return host_allocation_info(VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT);
  if (memory == CG_MEMORY_READBACK) {
    VmaAllocationCreateInfo info = host_allocation_info(VMA_ALLOCATION_CREATE_HOST_ACCESS_RANDOM_BIT);
    info.preferredFlags = VK_MEMORY_PROPERTY_HOST_CACHED_BIT;
    return info;
  }
  VmaAllocationCreateInfo info{};
  info.usage = VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE;
  return info;
}

cg_buffer *make_buffer(cg_device &device, uint64_t size, cg_memory memory, const char *label) {
  if (size == 0) throw std::invalid_argument("buffer size is zero");
  auto buffer = std::make_unique<cg_buffer>(create_raw_buffer(device, size, general_buffer_usage(device), memory, 0));
  name_handle(device, buffer->buffer, label);
  return buffer.release();
}

vk::ImageUsageFlags image_usage(uint32_t usage) {
  vk::ImageUsageFlags flags;
  if (usage & CG_TEXTURE_SAMPLED) flags |= vk::ImageUsageFlagBits::eSampled | vk::ImageUsageFlagBits::eTransferDst | vk::ImageUsageFlagBits::eTransferSrc;
  if (usage & CG_TEXTURE_RENDER_TARGET) flags |= vk::ImageUsageFlagBits::eColorAttachment | vk::ImageUsageFlagBits::eTransferSrc;
  if (usage & CG_TEXTURE_DEPTH) flags |= vk::ImageUsageFlagBits::eDepthStencilAttachment;
  if (usage & CG_TEXTURE_READBACK) flags |= vk::ImageUsageFlagBits::eTransferSrc;
  if (usage & CG_TEXTURE_STORAGE) flags |= vk::ImageUsageFlagBits::eStorage | vk::ImageUsageFlagBits::eTransferSrc;
  return flags;
}

void validate_texture_desc(const cg_texture_desc &desc) {
  if (to_vk_format(desc.format) == vk::Format::eUndefined) throw std::invalid_argument("unknown texture format");
  if (desc.width == 0 || desc.height == 0) throw std::invalid_argument("texture has zero size");
  if (desc.usage == 0) throw std::invalid_argument("texture has no usage");
  if (desc.kind == CG_TEXTURE_CUBE && desc.width != desc.height) throw std::invalid_argument("cube texture faces must be square");
}

void allocate_image(cg_device &device, cg_texture &texture, const cg_texture_desc &desc) {
  bool cube = desc.kind == CG_TEXTURE_CUBE;
  VkImageCreateInfo image_info = vk::ImageCreateInfo{
      .flags = cube ? vk::ImageCreateFlagBits::eCubeCompatible : vk::ImageCreateFlags{},
      .imageType = vk::ImageType::e2D,
      .format = texture.format,
      .extent = {.width = desc.width, .height = desc.height, .depth = 1},
      .mipLevels = texture.mip_levels,
      .arrayLayers = texture.layers,
      .samples = vk::SampleCountFlagBits::e1,
      .tiling = vk::ImageTiling::eOptimal,
      .usage = image_usage(desc.usage),
      .sharingMode = vk::SharingMode::eExclusive,
      .initialLayout = vk::ImageLayout::eUndefined,
  };
  VmaAllocationCreateInfo allocation_info{};
  allocation_info.usage = VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE;
  VkImage created = VK_NULL_HANDLE;
  if (vmaCreateImage(device.allocator, &image_info, &allocation_info, &created, &texture.allocation, nullptr) != VK_SUCCESS) {
    throw std::runtime_error("vmaCreateImage");
  }
  texture.image = created;
}

vk::ImageView create_view(cg_device &device, const cg_texture &texture, vk::ImageViewType type, vk::ImageSubresourceRange range) {
  return device.device.createImageView({.image = texture.image, .viewType = type, .format = texture.format, .subresourceRange = range});
}

void create_views(cg_device &device, cg_texture &texture, cg_texture_kind kind) {
  if (texture.usage & CG_TEXTURE_SAMPLED) {
    vk::ImageViewType type = kind == CG_TEXTURE_CUBE ? vk::ImageViewType::eCube : vk::ImageViewType::e2D;
    texture.sampled_view = create_view(device, texture, type, whole_range(texture));
  }
  if (texture.usage & (CG_TEXTURE_RENDER_TARGET | CG_TEXTURE_DEPTH)) {
    vk::ImageSubresourceRange first_layer{.aspectMask = texture.aspect, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1};
    texture.attachment_view = create_view(device, texture, vk::ImageViewType::e2D, first_layer);
  }
}

void publish_texture(cg_device &device, cg_texture &texture) {
  if (!(texture.usage & CG_TEXTURE_SAMPLED)) return;
  texture.descriptor_index = device.bindless.images.acquire();
  if (texture.descriptor_index == 0) throw std::runtime_error("bindless texture table is full");
  write_sampled_image(device, texture.descriptor_index, texture.sampled_view);
}

vk::Sampler create_vk_sampler(cg_device &device, const cg_sampler_desc &desc) {
  bool anisotropic = device.capabilities.anisotropy && desc.max_anisotropy > 1.0f;
  return device.device.createSampler({
      .magFilter = to_filter(desc.filter),
      .minFilter = to_filter(desc.filter),
      .mipmapMode = to_mipmap_mode(desc.mip_filter),
      .addressModeU = to_address_mode(desc.address),
      .addressModeV = to_address_mode(desc.address),
      .addressModeW = to_address_mode(desc.address),
      .anisotropyEnable = anisotropic ? vk::True : vk::False,
      .maxAnisotropy = anisotropic ? std::min(desc.max_anisotropy, device.capabilities.max_anisotropy) : 1.0f,
      .minLod = 0.0f,
      .maxLod = vk::LodClampNone,
  });
}

void fill_fallback_texture(cg_device &device, cg_texture &texture) {
  submit_immediately(device, [&texture](vk::CommandBuffer commands) {
    transition(commands, texture, ImageUse::transfer_dst, true);
    vk::ClearColorValue white{.float32 = std::array<float, 4>{1.0f, 1.0f, 1.0f, 1.0f}};
    vk::ImageSubresourceRange range = whole_range(texture);
    commands.clearColorImage(texture.image, vk::ImageLayout::eTransferDstOptimal, white, range);
    transition(commands, texture, ImageUse::sampled, false);
  });
}

}

vk::BufferUsageFlags general_buffer_usage(const cg_device &device) {
  if (!device.capabilities.ray_tracing) return base_buffer_usage;
  return base_buffer_usage | vk::BufferUsageFlagBits::eAccelerationStructureBuildInputReadOnlyKHR;
}

cg_buffer create_raw_buffer(cg_device &device, uint64_t size, vk::BufferUsageFlags usage, cg_memory memory, uint64_t alignment) {
  VkBufferCreateInfo buffer_info = vk::BufferCreateInfo{.size = size, .usage = usage, .sharingMode = vk::SharingMode::eExclusive};
  VmaAllocationCreateInfo allocation_info = buffer_allocation_info(memory);
  VkBuffer created = VK_NULL_HANDLE;
  VmaAllocationInfo allocated{};
  cg_buffer buffer;
  if (vmaCreateBufferWithAlignment(device.allocator, &buffer_info, &allocation_info, alignment, &created, &buffer.allocation, &allocated) != VK_SUCCESS) {
    throw std::runtime_error("vmaCreateBuffer");
  }
  buffer.buffer = created;
  buffer.mapped = allocated.pMappedData;
  buffer.address = device.device.getBufferAddress({.buffer = buffer.buffer});
  return buffer;
}

void retire_raw_buffer(cg_device &device, const cg_buffer &buffer) {
  VmaAllocator allocator = device.allocator;
  VkBuffer handle = buffer.buffer;
  VmaAllocation allocation = buffer.allocation;
  retire(device, [allocator, handle, allocation] { vmaDestroyBuffer(allocator, handle, allocation); });
}

cg_texture *make_texture(cg_device &device, const cg_texture_desc &desc) {
  validate_texture_desc(desc);
  auto texture = std::make_unique<cg_texture>();
  texture->format = to_vk_format(desc.format);
  texture->aspect = aspect_of(texture->format);
  texture->extent = vk::Extent2D{desc.width, desc.height};
  texture->mip_levels = std::max(desc.mip_levels, 1u);
  texture->layers = desc.kind == CG_TEXTURE_CUBE ? 6 : 1;
  texture->usage = desc.usage;
  try {
    allocate_image(device, *texture, desc);
    create_views(device, *texture, desc.kind);
  } catch (...) {
    free_texture(device, *texture);
    throw;
  }
  name_handle(device, texture->image, desc.label);
  return texture.release();
}

void free_texture(cg_device &device, const cg_texture &texture) {
  device.device.destroyImageView(texture.sampled_view);
  device.device.destroyImageView(texture.attachment_view);
  vmaDestroyImage(device.allocator, texture.image, texture.allocation);
  if (texture.descriptor_index != 0) device.bindless.images.release(texture.descriptor_index);
}

cg_sampler *make_sampler(cg_device &device, const cg_sampler_desc &desc) {
  auto sampler = std::make_unique<cg_sampler>();
  sampler->sampler = create_vk_sampler(device, desc);
  return sampler.release();
}

void create_fallbacks(cg_device &device) {
  cg_texture_desc texture_desc{
      .kind = CG_TEXTURE_2D,
      .format = CG_FORMAT_RGBA8_UNORM,
      .width = 1,
      .height = 1,
      .mip_levels = 1,
      .usage = CG_TEXTURE_SAMPLED,
      .label = "cauldron_gpu fallback texture",
  };
  device.fallback_texture = make_texture(device, texture_desc);
  write_sampled_image(device, 0, device.fallback_texture->sampled_view);
  fill_fallback_texture(device, *device.fallback_texture);
  cg_sampler_desc sampler_desc{.filter = CG_FILTER_LINEAR, .mip_filter = CG_FILTER_LINEAR, .address = CG_ADDRESS_REPEAT, .max_anisotropy = 1.0f};
  device.fallback_sampler = make_sampler(device, sampler_desc);
  write_sampler(device, 0, device.fallback_sampler->sampler);
}

void destroy_fallbacks(cg_device &device) {
  if (device.fallback_texture != nullptr) free_texture(device, *device.fallback_texture);
  if (device.fallback_sampler != nullptr) device.device.destroySampler(device.fallback_sampler->sampler);
  delete device.fallback_texture;
  delete device.fallback_sampler;
  device.fallback_texture = nullptr;
  device.fallback_sampler = nullptr;
}

cg_buffer *buffer_create(cg_device *device, uint64_t size, cg_memory memory, const char *label) noexcept {
  try {
    return make_buffer(*device, size, memory, label);
  } catch (const std::exception &error) {
    report_failure("buffer_create", error.what());
    return nullptr;
  }
}

void buffer_destroy(cg_device *device, cg_buffer *buffer) noexcept {
  if (buffer == nullptr) return;
  retire_raw_buffer(*device, *buffer);
  delete buffer;
}

void *buffer_contents(cg_buffer *buffer) noexcept {
  return buffer->mapped;
}

uint64_t buffer_address(cg_buffer *buffer) noexcept {
  return buffer->address;
}

cg_texture *texture_create(cg_device *device, const cg_texture_desc *desc) noexcept {
  try {
    std::unique_ptr<cg_texture> texture{make_texture(*device, *desc)};
    try {
      publish_texture(*device, *texture);
    } catch (...) {
      free_texture(*device, *texture);
      throw;
    }
    return texture.release();
  } catch (const std::exception &error) {
    report_failure("texture_create", error.what());
    return nullptr;
  }
}

void texture_destroy(cg_device *device, cg_texture *texture) noexcept {
  if (texture == nullptr) return;
  cg_texture retired = *texture;
  delete texture;
  retire(*device, [device, retired] { free_texture(*device, retired); });
}

uint64_t texture_handle(cg_texture *texture) noexcept {
  return texture->descriptor_index;
}

cg_sampler *sampler_create(cg_device *device, const cg_sampler_desc *desc) noexcept {
  try {
    std::unique_ptr<cg_sampler> sampler{make_sampler(*device, *desc)};
    sampler->descriptor_index = device->bindless.samplers.acquire();
    if (sampler->descriptor_index == 0) {
      device->device.destroySampler(sampler->sampler);
      throw std::runtime_error("bindless sampler table is full");
    }
    write_sampler(*device, sampler->descriptor_index, sampler->sampler);
    return sampler.release();
  } catch (const std::exception &error) {
    report_failure("sampler_create", error.what());
    return nullptr;
  }
}

void sampler_destroy(cg_device *device, cg_sampler *sampler) noexcept {
  if (sampler == nullptr) return;
  vk::Sampler handle = sampler->sampler;
  uint32_t index = sampler->descriptor_index;
  delete sampler;
  retire(*device, [device, handle, index] {
    device->device.destroySampler(handle);
    device->bindless.samplers.release(index);
  });
}

uint64_t sampler_handle(cg_sampler *sampler) noexcept {
  return sampler->descriptor_index;
}

}
