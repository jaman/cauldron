#include "internal.hpp"

namespace cgvk {
namespace {

constexpr vk::DescriptorBindingFlags heap_binding_flags = vk::DescriptorBindingFlagBits::ePartiallyBound |
                                                          vk::DescriptorBindingFlagBits::eUpdateAfterBind |
                                                          vk::DescriptorBindingFlagBits::eUpdateUnusedWhilePending;

vk::DescriptorSetLayout create_set_layout(vk::Device device) {
  std::array<vk::DescriptorSetLayoutBinding, 2> bindings{{
      {.binding = sampler_binding, .descriptorType = vk::DescriptorType::eSampler, .descriptorCount = sampler_capacity, .stageFlags = vk::ShaderStageFlagBits::eAll},
      {.binding = sampled_image_binding, .descriptorType = vk::DescriptorType::eSampledImage, .descriptorCount = sampled_image_capacity, .stageFlags = vk::ShaderStageFlagBits::eAll},
  }};
  std::array<vk::DescriptorBindingFlags, 2> flags{heap_binding_flags, heap_binding_flags};
  vk::DescriptorSetLayoutBindingFlagsCreateInfo flags_info{.bindingCount = static_cast<uint32_t>(flags.size()), .pBindingFlags = flags.data()};
  return device.createDescriptorSetLayout({
      .pNext = &flags_info,
      .flags = vk::DescriptorSetLayoutCreateFlagBits::eUpdateAfterBindPool,
      .bindingCount = static_cast<uint32_t>(bindings.size()),
      .pBindings = bindings.data(),
  });
}

vk::DescriptorPool create_pool(vk::Device device) {
  std::array<vk::DescriptorPoolSize, 2> sizes{{
      {.type = vk::DescriptorType::eSampler, .descriptorCount = sampler_capacity},
      {.type = vk::DescriptorType::eSampledImage, .descriptorCount = sampled_image_capacity},
  }};
  return device.createDescriptorPool({
      .flags = vk::DescriptorPoolCreateFlagBits::eUpdateAfterBind,
      .maxSets = 1,
      .poolSizeCount = static_cast<uint32_t>(sizes.size()),
      .pPoolSizes = sizes.data(),
  });
}

vk::DescriptorSetLayout create_accel_layout(vk::Device device, bool ray_tracing) {
  vk::DescriptorSetLayoutBinding binding{
      .binding = 0,
      .descriptorType = vk::DescriptorType::eAccelerationStructureKHR,
      .descriptorCount = 1,
      .stageFlags = vk::ShaderStageFlagBits::eAll,
  };
  return device.createDescriptorSetLayout({.bindingCount = ray_tracing ? 1u : 0u, .pBindings = ray_tracing ? &binding : nullptr});
}

vk::DescriptorPool create_accel_pool(vk::Device device) {
  vk::DescriptorPoolSize size{.type = vk::DescriptorType::eAccelerationStructureKHR, .descriptorCount = accel_set_capacity};
  return device.createDescriptorPool({
      .flags = vk::DescriptorPoolCreateFlagBits::eFreeDescriptorSet,
      .maxSets = accel_set_capacity,
      .poolSizeCount = 1,
      .pPoolSizes = &size,
  });
}

vk::PipelineLayout create_pipeline_layout(vk::Device device, const std::array<vk::DescriptorSetLayout, 2> &set_layouts) {
  vk::PushConstantRange push_range{.stageFlags = vk::ShaderStageFlagBits::eAll, .offset = 0, .size = CG_MAX_PUSH};
  return device.createPipelineLayout({
      .setLayoutCount = static_cast<uint32_t>(set_layouts.size()),
      .pSetLayouts = set_layouts.data(),
      .pushConstantRangeCount = 1,
      .pPushConstantRanges = &push_range,
  });
}

}

uint32_t SlotPool::acquire() {
  if (!released.empty()) {
    uint32_t slot = released.back();
    released.pop_back();
    return slot;
  }
  return next < capacity ? next++ : 0;
}

void SlotPool::release(uint32_t slot) {
  released.push_back(slot);
}

void create_bindless(cg_device &device) {
  Bindless &bindless = device.bindless;
  bindless.set_layout = create_set_layout(device.device);
  bindless.pool = create_pool(device.device);
  bindless.set = device.device.allocateDescriptorSets({
      .descriptorPool = bindless.pool,
      .descriptorSetCount = 1,
      .pSetLayouts = &bindless.set_layout,
  })[0];
  bindless.accel_layout = create_accel_layout(device.device, device.capabilities.ray_tracing);
  if (device.capabilities.ray_tracing) bindless.accel_pool = create_accel_pool(device.device);
  bindless.pipeline_layout = create_pipeline_layout(device.device, {bindless.set_layout, bindless.accel_layout});
}

void destroy_bindless(cg_device &device) {
  Bindless &bindless = device.bindless;
  device.device.destroyPipelineLayout(bindless.pipeline_layout);
  device.device.destroyDescriptorPool(bindless.accel_pool);
  device.device.destroyDescriptorSetLayout(bindless.accel_layout);
  device.device.destroyDescriptorPool(bindless.pool);
  device.device.destroyDescriptorSetLayout(bindless.set_layout);
}

void write_sampled_image(cg_device &device, uint32_t index, vk::ImageView view) {
  vk::DescriptorImageInfo image{.imageView = view, .imageLayout = vk::ImageLayout::eShaderReadOnlyOptimal};
  device.device.updateDescriptorSets(vk::WriteDescriptorSet{
                                         .dstSet = device.bindless.set,
                                         .dstBinding = sampled_image_binding,
                                         .dstArrayElement = index,
                                         .descriptorCount = 1,
                                         .descriptorType = vk::DescriptorType::eSampledImage,
                                         .pImageInfo = &image,
                                     },
                                     {});
}

void write_sampler(cg_device &device, uint32_t index, vk::Sampler sampler) {
  vk::DescriptorImageInfo image{.sampler = sampler};
  device.device.updateDescriptorSets(vk::WriteDescriptorSet{
                                         .dstSet = device.bindless.set,
                                         .dstBinding = sampler_binding,
                                         .dstArrayElement = index,
                                         .descriptorCount = 1,
                                         .descriptorType = vk::DescriptorType::eSampler,
                                         .pImageInfo = &image,
                                     },
                                     {});
}

vk::DescriptorSet create_accel_set(cg_device &device, vk::AccelerationStructureKHR scene) {
  vk::DescriptorSet set = device.device.allocateDescriptorSets({
      .descriptorPool = device.bindless.accel_pool,
      .descriptorSetCount = 1,
      .pSetLayouts = &device.bindless.accel_layout,
  })[0];
  vk::WriteDescriptorSetAccelerationStructureKHR accel{.accelerationStructureCount = 1, .pAccelerationStructures = &scene};
  device.device.updateDescriptorSets(vk::WriteDescriptorSet{
                                         .pNext = &accel,
                                         .dstSet = set,
                                         .dstBinding = 0,
                                         .dstArrayElement = 0,
                                         .descriptorCount = 1,
                                         .descriptorType = vk::DescriptorType::eAccelerationStructureKHR,
                                     },
                                     {});
  return set;
}

}
