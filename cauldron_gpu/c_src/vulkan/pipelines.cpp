#include "internal.hpp"

#include <cstring>
#include <memory>
#include <stdexcept>

namespace cgvk {
namespace {

struct ShaderModules {
  vk::Device device;
  std::vector<vk::ShaderModule> modules;

  ~ShaderModules() {
    for (vk::ShaderModule module : modules) device.destroyShaderModule(module);
  }
};

vk::ShaderModule create_shader_module(vk::Device device, const cg_shader &shader) {
  if (shader.code == nullptr || shader.size == 0 || shader.size % sizeof(uint32_t) != 0) {
    throw std::invalid_argument("shader code is not a SPIR-V module");
  }
  std::vector<uint32_t> words(shader.size / sizeof(uint32_t));
  std::memcpy(words.data(), shader.code, shader.size);
  return device.createShaderModule({.codeSize = shader.size, .pCode = words.data()});
}

void add_stage(ShaderModules &modules, std::vector<vk::PipelineShaderStageCreateInfo> &stages, vk::ShaderStageFlagBits stage, const cg_shader &shader) {
  if (shader.entry == nullptr) throw std::invalid_argument("shader entry point is missing");
  modules.modules.push_back(create_shader_module(modules.device, shader));
  stages.push_back({.stage = stage, .module = modules.modules.back(), .pName = shader.entry});
}

bool depth_biased(const cg_pipeline_desc &desc) {
  return desc.depth_bias != 0.0f || desc.depth_slope_bias != 0.0f;
}

vk::PipelineRasterizationStateCreateInfo rasterization_state(const cg_pipeline_desc &desc) {
  return {
      .polygonMode = vk::PolygonMode::eFill,
      .cullMode = to_cull_mode(desc.cull),
      .frontFace = vk::FrontFace::eCounterClockwise,
      .depthBiasEnable = depth_biased(desc) ? vk::True : vk::False,
      .depthBiasConstantFactor = desc.depth_bias,
      .depthBiasSlopeFactor = desc.depth_slope_bias,
      .lineWidth = 1.0f,
  };
}

vk::PipelineDepthStencilStateCreateInfo depth_state(const cg_pipeline_desc &desc) {
  bool has_depth = desc.depth_format != CG_FORMAT_UNDEFINED;
  return {
      .depthTestEnable = has_depth ? vk::True : vk::False,
      .depthWriteEnable = has_depth && desc.depth_write ? vk::True : vk::False,
      .depthCompareOp = to_compare_op(desc.depth_compare),
  };
}

struct GraphicsPipelineInputs {
  std::vector<vk::PipelineShaderStageCreateInfo> stages;
  std::vector<vk::Format> color_formats;
  std::vector<vk::PipelineColorBlendAttachmentState> blends;
};

vk::Pipeline build_pipeline(cg_device &device, const cg_pipeline_desc &desc, GraphicsPipelineInputs &inputs) {
  vk::PipelineVertexInputStateCreateInfo vertex_input{};
  vk::PipelineInputAssemblyStateCreateInfo input_assembly{.topology = vk::PrimitiveTopology::eTriangleList};
  vk::PipelineViewportStateCreateInfo viewport{.viewportCount = 1, .scissorCount = 1};
  vk::PipelineRasterizationStateCreateInfo rasterization = rasterization_state(desc);
  vk::PipelineMultisampleStateCreateInfo multisample{.rasterizationSamples = vk::SampleCountFlagBits::e1};
  vk::PipelineDepthStencilStateCreateInfo depth = depth_state(desc);
  vk::PipelineColorBlendStateCreateInfo blend{.attachmentCount = static_cast<uint32_t>(inputs.blends.size()), .pAttachments = inputs.blends.data()};
  std::array<vk::DynamicState, 2> dynamic_states{vk::DynamicState::eViewport, vk::DynamicState::eScissor};
  vk::PipelineDynamicStateCreateInfo dynamic{.dynamicStateCount = static_cast<uint32_t>(dynamic_states.size()), .pDynamicStates = dynamic_states.data()};
  vk::PipelineRenderingCreateInfo rendering{
      .colorAttachmentCount = static_cast<uint32_t>(inputs.color_formats.size()),
      .pColorAttachmentFormats = inputs.color_formats.data(),
      .depthAttachmentFormat = to_vk_format(desc.depth_format),
  };
  vk::GraphicsPipelineCreateInfo info{
      .pNext = &rendering,
      .stageCount = static_cast<uint32_t>(inputs.stages.size()),
      .pStages = inputs.stages.data(),
      .pVertexInputState = &vertex_input,
      .pInputAssemblyState = &input_assembly,
      .pViewportState = &viewport,
      .pRasterizationState = &rasterization,
      .pMultisampleState = &multisample,
      .pDepthStencilState = &depth,
      .pColorBlendState = &blend,
      .pDynamicState = &dynamic,
      .layout = device.bindless.pipeline_layout,
  };
  auto [result, pipeline] = device.device.createGraphicsPipeline({}, info);
  if (result != vk::Result::eSuccess) throw std::runtime_error(vk::to_string(result));
  return pipeline;
}

cg_pipeline *make_pipeline(cg_device &device, const cg_pipeline_desc &desc) {
  if (desc.color_count > CG_MAX_COLOR) throw std::invalid_argument("too many color targets");
  ShaderModules modules{.device = device.device, .modules = {}};
  GraphicsPipelineInputs inputs;
  add_stage(modules, inputs.stages, vk::ShaderStageFlagBits::eVertex, desc.vertex);
  if (desc.fragment.code != nullptr) add_stage(modules, inputs.stages, vk::ShaderStageFlagBits::eFragment, desc.fragment);
  for (uint32_t index = 0; index < desc.color_count; ++index) {
    inputs.color_formats.push_back(to_vk_format(desc.color_formats[index]));
    inputs.blends.push_back(to_blend_state(desc.blend[index]));
  }
  auto pipeline = std::make_unique<cg_pipeline>();
  pipeline->pipeline = build_pipeline(device, desc, inputs);
  name_handle(device, pipeline->pipeline, desc.label);
  return pipeline.release();
}

cg_pipeline *make_compute_pipeline(cg_device &device, const cg_compute_desc &desc) {
  ShaderModules modules{.device = device.device, .modules = {}};
  std::vector<vk::PipelineShaderStageCreateInfo> stages;
  add_stage(modules, stages, vk::ShaderStageFlagBits::eCompute, desc.compute);
  vk::ComputePipelineCreateInfo info{.stage = stages.front(), .layout = device.bindless.pipeline_layout};
  auto [result, handle] = device.device.createComputePipeline({}, info);
  if (result != vk::Result::eSuccess) throw std::runtime_error(vk::to_string(result));
  auto pipeline = std::make_unique<cg_pipeline>();
  pipeline->pipeline = handle;
  name_handle(device, pipeline->pipeline, desc.label);
  return pipeline.release();
}

}

cg_pipeline *compute_pipeline_create(cg_device *device, const cg_compute_desc *desc) noexcept {
  try {
    return make_compute_pipeline(*device, *desc);
  } catch (const std::exception &error) {
    report_failure("compute_pipeline_create", error.what());
    return nullptr;
  }
}

cg_pipeline *pipeline_create(cg_device *device, const cg_pipeline_desc *desc) noexcept {
  try {
    return make_pipeline(*device, *desc);
  } catch (const std::exception &error) {
    report_failure("pipeline_create", error.what());
    return nullptr;
  }
}

void pipeline_destroy(cg_device *device, cg_pipeline *pipeline) noexcept {
  if (pipeline == nullptr) return;
  vk::Pipeline handle = pipeline->pipeline;
  delete pipeline;
  retire(*device, [device, handle] { device->device.destroyPipeline(handle); });
}

}
