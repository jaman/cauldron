#include "internal.hpp"

#include <SDL3/SDL_video.h>
#include <SDL3/SDL_vulkan.h>

#include <algorithm>
#include <stdexcept>

namespace cgvk {
namespace {

vk::SurfaceFormatKHR choose_surface_format(vk::PhysicalDevice physical, vk::SurfaceKHR surface) {
  std::vector<vk::SurfaceFormatKHR> formats = physical.getSurfaceFormatsKHR(surface);
  for (const auto &candidate : formats) {
    if (candidate.format == vk::Format::eB8G8R8A8Srgb && candidate.colorSpace == vk::ColorSpaceKHR::eSrgbNonlinear) return candidate;
  }
  for (const auto &candidate : formats) {
    if (from_vk_format(candidate.format) != CG_FORMAT_UNDEFINED) return candidate;
  }
  throw std::runtime_error("surface offers no format cauldron_gpu can describe");
}

vk::Extent2D choose_extent(const vk::SurfaceCapabilitiesKHR &capabilities, uint32_t width, uint32_t height) {
  if (capabilities.currentExtent.width != UINT32_MAX) return capabilities.currentExtent;
  return {
      .width = std::clamp(width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
      .height = std::clamp(height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
  };
}

uint32_t choose_image_count(const vk::SurfaceCapabilitiesKHR &capabilities) {
  uint32_t count = capabilities.minImageCount + 1;
  bool bounded = capabilities.maxImageCount != 0;
  return bounded ? std::min(count, capabilities.maxImageCount) : count;
}

vk::CompositeAlphaFlagBitsKHR choose_composite_alpha(const vk::SurfaceCapabilitiesKHR &capabilities) {
  constexpr std::array<vk::CompositeAlphaFlagBitsKHR, 4> preference{
      vk::CompositeAlphaFlagBitsKHR::eOpaque,
      vk::CompositeAlphaFlagBitsKHR::eInherit,
      vk::CompositeAlphaFlagBitsKHR::ePreMultiplied,
      vk::CompositeAlphaFlagBitsKHR::ePostMultiplied,
  };
  for (auto mode : preference) {
    if (capabilities.supportedCompositeAlpha & mode) return mode;
  }
  return vk::CompositeAlphaFlagBitsKHR::eOpaque;
}

cg_texture wrap_swapchain_image(cg_device &device, vk::Image image, vk::Format format, vk::Extent2D extent) {
  cg_texture texture;
  texture.image = image;
  texture.format = format;
  texture.aspect = vk::ImageAspectFlagBits::eColor;
  texture.extent = extent;
  texture.usage = CG_TEXTURE_RENDER_TARGET;
  texture.attachment_view = device.device.createImageView({
      .image = image,
      .viewType = vk::ImageViewType::e2D,
      .format = format,
      .subresourceRange = whole_range(texture),
  });
  return texture;
}

Swapchain build_swapchain(cg_device &device, const vk::SurfaceCapabilitiesKHR &capabilities, vk::Extent2D extent, vk::SwapchainKHR previous) {
  Surface &surface = device.surface;
  Swapchain swapchain;
  swapchain.copyable = static_cast<bool>(capabilities.supportedUsageFlags & vk::ImageUsageFlagBits::eTransferDst);
  vk::ImageUsageFlags usage = vk::ImageUsageFlagBits::eColorAttachment;
  if (swapchain.copyable) usage |= vk::ImageUsageFlagBits::eTransferDst;
  swapchain.handle = device.device.createSwapchainKHR({
      .surface = surface.handle,
      .minImageCount = choose_image_count(capabilities),
      .imageFormat = surface.format.format,
      .imageColorSpace = surface.format.colorSpace,
      .imageExtent = extent,
      .imageArrayLayers = 1,
      .imageUsage = usage,
      .imageSharingMode = vk::SharingMode::eExclusive,
      .preTransform = capabilities.currentTransform,
      .compositeAlpha = choose_composite_alpha(capabilities),
      .presentMode = vk::PresentModeKHR::eFifo,
      .clipped = vk::True,
      .oldSwapchain = previous,
  });
  for (vk::Image image : device.device.getSwapchainImagesKHR(swapchain.handle)) {
    swapchain.images.push_back(wrap_swapchain_image(device, image, surface.format.format, extent));
    swapchain.rendered.push_back(device.device.createSemaphore({}));
  }
  return swapchain;
}

void destroy_swapchain(cg_device &device, Swapchain &swapchain) {
  for (vk::Semaphore semaphore : swapchain.rendered) device.device.destroySemaphore(semaphore);
  for (const cg_texture &image : swapchain.images) device.device.destroyImageView(image.attachment_view);
  device.device.destroySwapchainKHR(swapchain.handle);
  swapchain = {};
}

bool recreate_swapchain(cg_device &device) {
  Surface &surface = device.surface;
  vk::SurfaceCapabilitiesKHR capabilities = device.physical.getSurfaceCapabilitiesKHR(surface.handle);
  vk::Extent2D extent = choose_extent(capabilities, surface.width, surface.height);
  if (extent.width == 0 || extent.height == 0) return false;
  device.queue.waitIdle();
  Swapchain previous = std::move(surface.swapchain);
  surface.swapchain = build_swapchain(device, capabilities, extent, previous.handle);
  destroy_swapchain(device, previous);
  surface.stale = false;
  return true;
}

vk::Result acquire(cg_device &device, vk::Semaphore acquired) {
  Swapchain &swapchain = device.surface.swapchain;
  return device.device.acquireNextImageKHR(swapchain.handle, UINT64_MAX, acquired, {}, &swapchain.current);
}

void destroy_surface(cg_device &device) {
  Surface &surface = device.surface;
  if (!surface.handle) return;
  device.queue.waitIdle();
  destroy_swapchain(device, surface.swapchain);
  SDL_Vulkan_DestroySurface(device.instance, surface.handle, nullptr);
  surface.handle = vk::SurfaceKHR{};
  surface.reported_format = CG_FORMAT_UNDEFINED;
}

bool attach_surface(cg_device &device, SDL_Window *window) {
  Surface &surface = device.surface;
  VkSurfaceKHR created = VK_NULL_HANDLE;
  if (!SDL_Vulkan_CreateSurface(window, device.instance, nullptr, &created)) throw std::runtime_error(SDL_GetError());
  surface.handle = created;
  if (!device.physical.getSurfaceSupportKHR(device.queue_family, surface.handle)) {
    destroy_surface(device);
    throw std::runtime_error("the chosen queue cannot present to this window");
  }
  int width = 0;
  int height = 0;
  SDL_GetWindowSizeInPixels(window, &width, &height);
  surface.format = choose_surface_format(device.physical, surface.handle);
  surface.reported_format = from_vk_format(surface.format.format);
  surface.width = static_cast<uint32_t>(std::max(width, 0));
  surface.height = static_cast<uint32_t>(std::max(height, 0));
  surface.stale = true;
  return true;
}

}

bool prepare_swapchain(cg_device &device) {
  Surface &surface = device.surface;
  if (!surface.handle || surface.width == 0 || surface.height == 0) return false;
  if (!surface.stale && surface.swapchain.handle) return true;
  return recreate_swapchain(device);
}

bool acquire_next_image(cg_device &device, vk::Semaphore acquired) {
  vk::Result result = acquire(device, acquired);
  if (result == vk::Result::eErrorOutOfDateKHR && recreate_swapchain(device)) result = acquire(device, acquired);
  if (result == vk::Result::eSuboptimalKHR) device.surface.stale = true;
  bool acquired_image = result == vk::Result::eSuccess || result == vk::Result::eSuboptimalKHR;
  if (acquired_image) {
    Swapchain &swapchain = device.surface.swapchain;
    swapchain.images[swapchain.current].use = ImageUse::acquired;
  }
  return acquired_image;
}

void present_current_image(cg_device &device) {
  Swapchain &swapchain = device.surface.swapchain;
  vk::PresentInfoKHR info{
      .waitSemaphoreCount = 1,
      .pWaitSemaphores = &swapchain.rendered[swapchain.current],
      .swapchainCount = 1,
      .pSwapchains = &swapchain.handle,
      .pImageIndices = &swapchain.current,
  };
  if (device.queue.presentKHR(&info) != vk::Result::eSuccess) device.surface.stale = true;
}

void release_surface(cg_device &device) {
  std::lock_guard lock(device.surface.mutex);
  destroy_surface(device);
}

bool surface_attach(cg_device *device, void *sdl_window) noexcept {
  std::lock_guard lock(device->surface.mutex);
  if (device->surface.handle) return true;
  try {
    return attach_surface(*device, static_cast<SDL_Window *>(sdl_window));
  } catch (const std::exception &error) {
    report_failure("surface_attach", error.what());
    return false;
  }
}

void surface_detach(cg_device *device) noexcept {
  release_surface(*device);
}

void surface_resize(cg_device *device, uint32_t width, uint32_t height) noexcept {
  device->surface.width = width;
  device->surface.height = height;
  device->surface.stale = true;
}

cg_format surface_format(cg_device *device) noexcept {
  return device->surface.reported_format;
}

}
