#include "internal.hpp"

#include <SDL3/SDL_vulkan.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <optional>
#include <stdexcept>

namespace cgvk {
namespace {

constexpr const char *validation_layer_name = "VK_LAYER_KHRONOS_validation";

bool validation_requested() {
  const char *setting = std::getenv("CAULDRON_GPU_VALIDATION");
  return setting != nullptr && std::strcmp(setting, "1") == 0;
}

bool layer_available(const char *name) {
  for (const auto &layer : vk::enumerateInstanceLayerProperties()) {
    if (std::strcmp(layer.layerName, name) == 0) return true;
  }
  return false;
}

bool instance_extension_available(const char *name) {
  for (const auto &extension : vk::enumerateInstanceExtensionProperties()) {
    if (std::strcmp(extension.extensionName, name) == 0) return true;
  }
  return false;
}

VKAPI_ATTR vk::Bool32 VKAPI_CALL print_validation_message(vk::DebugUtilsMessageSeverityFlagBitsEXT severity,
                                                         vk::DebugUtilsMessageTypeFlagsEXT,
                                                         const vk::DebugUtilsMessengerCallbackDataEXT *data, void *) {
  std::fprintf(stderr, "cauldron_gpu vulkan %s: %s\n", vk::to_string(severity).c_str(), data->pMessage);
  return vk::False;
}

vk::DebugUtilsMessengerCreateInfoEXT messenger_info() {
  return {
      .messageSeverity = vk::DebugUtilsMessageSeverityFlagBitsEXT::eWarning | vk::DebugUtilsMessageSeverityFlagBitsEXT::eError,
      .messageType = vk::DebugUtilsMessageTypeFlagBitsEXT::eGeneral | vk::DebugUtilsMessageTypeFlagBitsEXT::eValidation,
      .pfnUserCallback = print_validation_message,
  };
}

std::vector<const char *> sdl_instance_extensions() {
  Uint32 count = 0;
  const char *const *names = SDL_Vulkan_GetInstanceExtensions(&count);
  if (names == nullptr) throw std::runtime_error(SDL_GetError());
  return {names, names + count};
}

bool has_device_extension(vk::PhysicalDevice physical, const char *name) {
  for (const auto &extension : physical.enumerateDeviceExtensionProperties()) {
    if (std::strcmp(extension.extensionName, name) == 0) return true;
  }
  return false;
}

bool supports_required_features(vk::PhysicalDevice physical) {
  auto chain = physical.getFeatures2<vk::PhysicalDeviceFeatures2, vk::PhysicalDeviceVulkan11Features,
                                     vk::PhysicalDeviceVulkan12Features, vk::PhysicalDeviceVulkan13Features>();
  const auto &v11 = chain.get<vk::PhysicalDeviceVulkan11Features>();
  const auto &v12 = chain.get<vk::PhysicalDeviceVulkan12Features>();
  const auto &v13 = chain.get<vk::PhysicalDeviceVulkan13Features>();
  return v11.shaderDrawParameters && v12.bufferDeviceAddress && v12.descriptorIndexing && v12.runtimeDescriptorArray &&
         v12.descriptorBindingPartiallyBound && v12.descriptorBindingSampledImageUpdateAfterBind &&
         v12.descriptorBindingUpdateUnusedWhilePending &&
         v12.shaderSampledImageArrayNonUniformIndexing && v12.scalarBlockLayout && v13.dynamicRendering &&
         v13.synchronization2;
}

std::optional<uint32_t> presentable_graphics_family(vk::Instance instance, vk::PhysicalDevice physical) {
  auto families = physical.getQueueFamilyProperties();
  for (uint32_t index = 0; index < families.size(); ++index) {
    bool graphics = static_cast<bool>(families[index].queueFlags & vk::QueueFlagBits::eGraphics);
    if (graphics && SDL_Vulkan_GetPresentationSupport(instance, physical, index)) return index;
  }
  return std::nullopt;
}

int device_type_rank(vk::PhysicalDeviceType type) {
  if (type == vk::PhysicalDeviceType::eDiscreteGpu) return 2;
  if (type == vk::PhysicalDeviceType::eIntegratedGpu) return 1;
  return 0;
}

bool usable_device(vk::PhysicalDevice physical) {
  return physical.getProperties().apiVersion >= vk::ApiVersion13 &&
         has_device_extension(physical, vk::KHRSwapchainExtensionName) && supports_required_features(physical);
}

}

void report_failure(const char *operation, const char *reason) {
  std::fprintf(stderr, "cauldron_gpu vulkan: %s failed: %s\n", operation, reason);
}

InstanceSetup create_instance() {
  bool validation = validation_requested() && layer_available(validation_layer_name);
  bool portability = instance_extension_available(vk::KHRPortabilityEnumerationExtensionName);
  std::vector<const char *> extensions = sdl_instance_extensions();
  std::vector<const char *> layers;
  if (portability) extensions.push_back(vk::KHRPortabilityEnumerationExtensionName);
  if (validation) {
    extensions.push_back(vk::EXTDebugUtilsExtensionName);
    layers.push_back(validation_layer_name);
  }
  vk::ApplicationInfo application{.pApplicationName = "cauldron_gpu", .pEngineName = "cauldron_gpu", .apiVersion = vk::ApiVersion13};
  vk::InstanceCreateInfo info{
      .flags = portability ? vk::InstanceCreateFlagBits::eEnumeratePortabilityKHR : vk::InstanceCreateFlags{},
      .pApplicationInfo = &application,
      .enabledLayerCount = static_cast<uint32_t>(layers.size()),
      .ppEnabledLayerNames = layers.data(),
      .enabledExtensionCount = static_cast<uint32_t>(extensions.size()),
      .ppEnabledExtensionNames = extensions.data(),
  };
  vk::Instance instance = vk::createInstance(info);
  VULKAN_HPP_DEFAULT_DISPATCHER.init(instance);
  vk::DebugUtilsMessengerEXT messenger = validation ? instance.createDebugUtilsMessengerEXT(messenger_info()) : vk::DebugUtilsMessengerEXT{};
  return {.instance = instance, .messenger = messenger, .debug_utils = validation};
}

PhysicalChoice pick_physical_device(vk::Instance instance) {
  std::optional<PhysicalChoice> best;
  int best_rank = -1;
  for (vk::PhysicalDevice physical : instance.enumeratePhysicalDevices()) {
    if (!usable_device(physical)) continue;
    auto family = presentable_graphics_family(instance, physical);
    int rank = device_type_rank(physical.getProperties().deviceType);
    if (family && rank > best_rank) {
      best = PhysicalChoice{.physical = physical, .queue_family = *family};
      best_rank = rank;
    }
  }
  if (!best) throw std::runtime_error("no Vulkan 1.3 device with dynamic rendering, synchronization2, buffer device address and descriptor indexing");
  return *best;
}

bool device_extension_available(vk::PhysicalDevice physical, const char *name) {
  return has_device_extension(physical, name);
}

}
