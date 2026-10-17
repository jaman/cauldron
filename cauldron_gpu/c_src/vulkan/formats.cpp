#include "internal.hpp"

namespace cgvk {
namespace {

struct FormatPair {
  cg_format portable;
  vk::Format native;
};

constexpr std::array<FormatPair, 8> format_pairs{{
    {CG_FORMAT_RGBA8_UNORM, vk::Format::eR8G8B8A8Unorm},
    {CG_FORMAT_RGBA8_SRGB, vk::Format::eR8G8B8A8Srgb},
    {CG_FORMAT_BGRA8_UNORM, vk::Format::eB8G8R8A8Unorm},
    {CG_FORMAT_BGRA8_SRGB, vk::Format::eB8G8R8A8Srgb},
    {CG_FORMAT_RGBA16F, vk::Format::eR16G16B16A16Sfloat},
    {CG_FORMAT_RG16F, vk::Format::eR16G16Sfloat},
    {CG_FORMAT_R32F, vk::Format::eR32Sfloat},
    {CG_FORMAT_D32F, vk::Format::eD32Sfloat},
}};

}

vk::Format to_vk_format(cg_format format) {
  for (const auto &pair : format_pairs) {
    if (pair.portable == format) return pair.native;
  }
  return vk::Format::eUndefined;
}

cg_format from_vk_format(vk::Format format) {
  for (const auto &pair : format_pairs) {
    if (pair.native == format) return pair.portable;
  }
  return CG_FORMAT_UNDEFINED;
}

vk::ImageAspectFlags aspect_of(vk::Format format) {
  return format == vk::Format::eD32Sfloat ? vk::ImageAspectFlagBits::eDepth : vk::ImageAspectFlagBits::eColor;
}

vk::CompareOp to_compare_op(cg_compare compare) {
  switch (compare) {
    case CG_COMPARE_LESS: return vk::CompareOp::eLess;
    case CG_COMPARE_LESS_EQUAL: return vk::CompareOp::eLessOrEqual;
    case CG_COMPARE_GREATER: return vk::CompareOp::eGreater;
    case CG_COMPARE_GREATER_EQUAL: return vk::CompareOp::eGreaterOrEqual;
    case CG_COMPARE_ALWAYS: break;
  }
  return vk::CompareOp::eAlways;
}

vk::CullModeFlags to_cull_mode(cg_cull cull) {
  switch (cull) {
    case CG_CULL_BACK: return vk::CullModeFlagBits::eBack;
    case CG_CULL_FRONT: return vk::CullModeFlagBits::eFront;
    case CG_CULL_NONE: break;
  }
  return vk::CullModeFlagBits::eNone;
}

vk::PipelineColorBlendAttachmentState to_blend_state(cg_blend blend) {
  constexpr vk::ColorComponentFlags all_channels = vk::ColorComponentFlagBits::eR | vk::ColorComponentFlagBits::eG |
                                                   vk::ColorComponentFlagBits::eB | vk::ColorComponentFlagBits::eA;
  switch (blend) {
    case CG_BLEND_ALPHA:
      return {
          .blendEnable = vk::True,
          .srcColorBlendFactor = vk::BlendFactor::eSrcAlpha,
          .dstColorBlendFactor = vk::BlendFactor::eOneMinusSrcAlpha,
          .colorBlendOp = vk::BlendOp::eAdd,
          .srcAlphaBlendFactor = vk::BlendFactor::eOne,
          .dstAlphaBlendFactor = vk::BlendFactor::eOneMinusSrcAlpha,
          .alphaBlendOp = vk::BlendOp::eAdd,
          .colorWriteMask = all_channels,
      };
    case CG_BLEND_ADD:
      return {
          .blendEnable = vk::True,
          .srcColorBlendFactor = vk::BlendFactor::eOne,
          .dstColorBlendFactor = vk::BlendFactor::eOne,
          .colorBlendOp = vk::BlendOp::eAdd,
          .srcAlphaBlendFactor = vk::BlendFactor::eOne,
          .dstAlphaBlendFactor = vk::BlendFactor::eOne,
          .alphaBlendOp = vk::BlendOp::eAdd,
          .colorWriteMask = all_channels,
      };
    case CG_BLEND_MULTIPLY:
      return {
          .blendEnable = vk::True,
          .srcColorBlendFactor = vk::BlendFactor::eDstColor,
          .dstColorBlendFactor = vk::BlendFactor::eZero,
          .colorBlendOp = vk::BlendOp::eAdd,
          .srcAlphaBlendFactor = vk::BlendFactor::eZero,
          .dstAlphaBlendFactor = vk::BlendFactor::eOne,
          .alphaBlendOp = vk::BlendOp::eAdd,
          .colorWriteMask = all_channels,
      };
    case CG_BLEND_NONE: break;
  }
  return {.blendEnable = vk::False, .colorWriteMask = all_channels};
}

vk::AttachmentLoadOp to_load_op(cg_load load) {
  switch (load) {
    case CG_LOAD_CLEAR: return vk::AttachmentLoadOp::eClear;
    case CG_LOAD_LOAD: return vk::AttachmentLoadOp::eLoad;
    case CG_LOAD_DONT_CARE: break;
  }
  return vk::AttachmentLoadOp::eDontCare;
}

vk::Filter to_filter(cg_filter filter) {
  return filter == CG_FILTER_LINEAR ? vk::Filter::eLinear : vk::Filter::eNearest;
}

vk::SamplerMipmapMode to_mipmap_mode(cg_filter filter) {
  return filter == CG_FILTER_LINEAR ? vk::SamplerMipmapMode::eLinear : vk::SamplerMipmapMode::eNearest;
}

vk::SamplerAddressMode to_address_mode(cg_address address) {
  return address == CG_ADDRESS_CLAMP ? vk::SamplerAddressMode::eClampToEdge : vk::SamplerAddressMode::eRepeat;
}

}
