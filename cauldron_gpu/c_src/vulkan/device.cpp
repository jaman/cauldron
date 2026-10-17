#include "internal.hpp"

#include <SDL3/SDL_vulkan.h>

#include <algorithm>
#include <cstring>
#include <memory>
#include <stdexcept>

namespace cgvk {
namespace {

vk::PhysicalDevicePortabilitySubsetFeaturesKHR supported_portability_features(vk::PhysicalDevice physical) {
  auto chain = physical.getFeatures2<vk::PhysicalDeviceFeatures2, vk::PhysicalDevicePortabilitySubsetFeaturesKHR>();
  auto features = chain.get<vk::PhysicalDevicePortabilitySubsetFeaturesKHR>();
  features.pNext = nullptr;
  return features;
}

constexpr std::array<const char *, 3> ray_tracing_extensions{
    vk::KHRAccelerationStructureExtensionName,
    vk::KHRRayQueryExtensionName,
    vk::KHRDeferredHostOperationsExtensionName,
};

bool ray_tracing_extensions_available(vk::PhysicalDevice physical) {
  for (const char *name : ray_tracing_extensions) {
    if (!device_extension_available(physical, name)) return false;
  }
  return true;
}

bool ray_tracing_supported(vk::PhysicalDevice physical) {
  if (!ray_tracing_extensions_available(physical)) return false;
  auto chain = physical.getFeatures2<vk::PhysicalDeviceFeatures2, vk::PhysicalDeviceAccelerationStructureFeaturesKHR,
                                     vk::PhysicalDeviceRayQueryFeaturesKHR>();
  return chain.get<vk::PhysicalDeviceAccelerationStructureFeaturesKHR>().accelerationStructure &&
         chain.get<vk::PhysicalDeviceRayQueryFeaturesKHR>().rayQuery;
}

uint32_t scratch_alignment_of(vk::PhysicalDevice physical) {
  auto chain = physical.getProperties2<vk::PhysicalDeviceProperties2, vk::PhysicalDeviceAccelerationStructurePropertiesKHR>();
  return chain.get<vk::PhysicalDeviceAccelerationStructurePropertiesKHR>().minAccelerationStructureScratchOffsetAlignment;
}

Capabilities probe_capabilities(vk::PhysicalDevice physical, bool debug_utils) {
  vk::PhysicalDeviceFeatures features = physical.getFeatures();
  bool ray_tracing = ray_tracing_supported(physical);
  return {
      .debug_utils = debug_utils,
      .anisotropy = features.samplerAnisotropy == vk::True,
      .max_anisotropy = physical.getProperties().limits.maxSamplerAnisotropy,
      .ray_tracing = ray_tracing,
      .mesh_shaders = device_extension_available(physical, vk::EXTMeshShaderExtensionName),
      .scratch_alignment = ray_tracing ? scratch_alignment_of(physical) : 0,
  };
}

vk::PhysicalDeviceFeatures2 base_features(vk::PhysicalDevice physical) {
  vk::PhysicalDeviceFeatures supported = physical.getFeatures();
  return {.features = {.samplerAnisotropy = supported.samplerAnisotropy, .shaderInt64 = supported.shaderInt64}};
}

void initialize_device(cg_device &device) {
  if (!SDL_Vulkan_LoadLibrary(nullptr)) throw std::runtime_error(SDL_GetError());
  device.sdl_library_loaded = true;
  VULKAN_HPP_DEFAULT_DISPATCHER.init(reinterpret_cast<PFN_vkGetInstanceProcAddr>(SDL_Vulkan_GetVkGetInstanceProcAddr()));
  InstanceSetup setup = create_instance();
  device.instance = setup.instance;
  device.messenger = setup.messenger;
  PhysicalChoice choice = pick_physical_device(device.instance);
  device.physical = choice.physical;
  device.queue_family = choice.queue_family;
  device.properties = device.physical.getProperties();
  device.capabilities = probe_capabilities(device.physical, setup.debug_utils);
  probe_timestamps(device);
  create_logical_device(device);
  create_allocator(device);
  create_bindless(device);
  create_frames(device);
  create_fallbacks(device);
}

void wait_idle_ignoring_errors(vk::Device device) {
  VULKAN_HPP_DEFAULT_DISPATCHER.vkDeviceWaitIdle(device);
}

void copy_string(char *destination, size_t capacity, const char *source) {
  size_t length = std::min(std::strlen(source), capacity - 1);
  std::memcpy(destination, source, length);
  destination[length] = '\0';
}

}

void create_logical_device(cg_device &device) {
  bool portability = device_extension_available(device.physical, vk::KHRPortabilitySubsetExtensionName);
  std::vector<const char *> extensions{vk::KHRSwapchainExtensionName};
  if (portability) extensions.push_back(vk::KHRPortabilitySubsetExtensionName);
  bool ray_tracing = device.capabilities.ray_tracing;
  if (ray_tracing) extensions.insert(extensions.end(), ray_tracing_extensions.begin(), ray_tracing_extensions.end());
  float priority = 1.0f;
  vk::DeviceQueueCreateInfo queue_info{.queueFamilyIndex = device.queue_family, .queueCount = 1, .pQueuePriorities = &priority};
  vk::StructureChain<vk::DeviceCreateInfo, vk::PhysicalDeviceFeatures2, vk::PhysicalDeviceVulkan11Features,
                     vk::PhysicalDeviceVulkan12Features, vk::PhysicalDeviceVulkan13Features,
                     vk::PhysicalDevicePortabilitySubsetFeaturesKHR, vk::PhysicalDeviceAccelerationStructureFeaturesKHR,
                     vk::PhysicalDeviceRayQueryFeaturesKHR>
      chain{
          vk::DeviceCreateInfo{
              .queueCreateInfoCount = 1,
              .pQueueCreateInfos = &queue_info,
              .enabledExtensionCount = static_cast<uint32_t>(extensions.size()),
              .ppEnabledExtensionNames = extensions.data(),
          },
          base_features(device.physical),
          vk::PhysicalDeviceVulkan11Features{.shaderDrawParameters = vk::True},
          vk::PhysicalDeviceVulkan12Features{
              .descriptorIndexing = vk::True,
              .shaderSampledImageArrayNonUniformIndexing = vk::True,
              .descriptorBindingSampledImageUpdateAfterBind = vk::True,
              .descriptorBindingUpdateUnusedWhilePending = vk::True,
              .descriptorBindingPartiallyBound = vk::True,
              .runtimeDescriptorArray = vk::True,
              .scalarBlockLayout = vk::True,
              .bufferDeviceAddress = vk::True,
          },
          vk::PhysicalDeviceVulkan13Features{.synchronization2 = vk::True, .dynamicRendering = vk::True},
          portability ? supported_portability_features(device.physical) : vk::PhysicalDevicePortabilitySubsetFeaturesKHR{},
          vk::PhysicalDeviceAccelerationStructureFeaturesKHR{.accelerationStructure = vk::True},
          vk::PhysicalDeviceRayQueryFeaturesKHR{.rayQuery = vk::True},
      };
  if (!portability) chain.unlink<vk::PhysicalDevicePortabilitySubsetFeaturesKHR>();
  if (!ray_tracing) {
    chain.unlink<vk::PhysicalDeviceAccelerationStructureFeaturesKHR>();
    chain.unlink<vk::PhysicalDeviceRayQueryFeaturesKHR>();
  }
  device.device = device.physical.createDevice(chain.get<vk::DeviceCreateInfo>());
  device.queue = device.device.getQueue(device.queue_family, 0);
}

void create_allocator(cg_device &device) {
  VmaVulkanFunctions functions{};
  functions.vkGetInstanceProcAddr = VULKAN_HPP_DEFAULT_DISPATCHER.vkGetInstanceProcAddr;
  functions.vkGetDeviceProcAddr = VULKAN_HPP_DEFAULT_DISPATCHER.vkGetDeviceProcAddr;
  VmaAllocatorCreateInfo info{};
  info.flags = VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT;
  info.physicalDevice = device.physical;
  info.device = device.device;
  info.pVulkanFunctions = &functions;
  info.instance = device.instance;
  info.vulkanApiVersion = VK_API_VERSION_1_3;
  if (vmaCreateAllocator(&info, &device.allocator) != VK_SUCCESS) throw std::runtime_error("vmaCreateAllocator");
}

void name_object(cg_device &device, vk::ObjectType type, uint64_t handle, const char *label) {
  if (!device.capabilities.debug_utils || label == nullptr) return;
  device.device.setDebugUtilsObjectNameEXT({.objectType = type, .objectHandle = handle, .pObjectName = label});
}

cg_device *device_create() noexcept {
  try {
    auto device = std::make_unique<cg_device>();
    initialize_device(*device);
    return device.release();
  } catch (const std::exception &error) {
    report_failure("device_create", error.what());
    return nullptr;
  }
}

void device_destroy(cg_device *device) noexcept {
  delete device;
}

void device_info(cg_device *device, cg_device_info *info) noexcept {
  *info = {};
  copy_string(info->name, sizeof(info->name), device->properties.deviceName);
  copy_string(info->backend, sizeof(info->backend), "vulkan");
  info->ray_tracing = device->capabilities.ray_tracing;
  info->mesh_shaders = device->capabilities.mesh_shaders;
  info->unified_memory = device->properties.deviceType == vk::PhysicalDeviceType::eIntegratedGpu;
}

}

cg_device::~cg_device() {
  if (device) {
    cgvk::wait_idle_ignoring_errors(device);
    cgvk::release_surface(*this);
    cgvk::release_all_retirements(*this);
    cgvk::destroy_fallbacks(*this);
    cgvk::destroy_frames(*this);
    cgvk::destroy_bindless(*this);
  }
  vmaDestroyAllocator(allocator);
  device.destroy();
  if (messenger) instance.destroyDebugUtilsMessengerEXT(messenger);
  instance.destroy();
  if (sdl_library_loaded) SDL_Vulkan_UnloadLibrary();
}
