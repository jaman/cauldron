import Metal
import QuartzCore

final class Buffer {
  let buffer: MTLBuffer

  init(buffer: MTLBuffer) {
    self.buffer = buffer
  }
}

final class Texture {
  var texture: MTLTexture?

  init(texture: MTLTexture?) {
    self.texture = texture
  }
}

final class Sampler {
  let sampler: MTLSamplerState

  init(sampler: MTLSamplerState) {
    self.sampler = sampler
  }
}

final class Pipeline {
  let state: MTLRenderPipelineState
  let depth: MTLDepthStencilState
  let cull: MTLCullMode
  let depthBias: Float
  let depthSlopeBias: Float

  init(state: MTLRenderPipelineState, depth: MTLDepthStencilState, cull: MTLCullMode, depthBias: Float, depthSlopeBias: Float) {
    self.state = state
    self.depth = depth
    self.cull = cull
    self.depthBias = depthBias
    self.depthSlopeBias = depthSlopeBias
  }
}

func retained<T: AnyObject>(_ object: T) -> OpaquePointer {
  OpaquePointer(Unmanaged.passRetained(object).toOpaque())
}

func borrowed<T: AnyObject>(_ pointer: OpaquePointer) -> T {
  Unmanaged<T>.fromOpaque(UnsafeRawPointer(pointer)).takeUnretainedValue()
}

func released<T: AnyObject>(_ pointer: OpaquePointer) -> T {
  Unmanaged<T>.fromOpaque(UnsafeRawPointer(pointer)).takeRetainedValue()
}

func pixelFormat(_ format: cg_format) -> MTLPixelFormat {
  switch format {
  case CG_FORMAT_RGBA8_UNORM: return .rgba8Unorm
  case CG_FORMAT_RGBA8_SRGB: return .rgba8Unorm_srgb
  case CG_FORMAT_BGRA8_UNORM: return .bgra8Unorm
  case CG_FORMAT_BGRA8_SRGB: return .bgra8Unorm_srgb
  case CG_FORMAT_RGBA16F: return .rgba16Float
  case CG_FORMAT_RG16F: return .rg16Float
  case CG_FORMAT_R32F: return .r32Float
  case CG_FORMAT_D32F: return .depth32Float
  default: return .invalid
  }
}

func compareFunction(_ compare: cg_compare) -> MTLCompareFunction {
  switch compare {
  case CG_COMPARE_LESS: return .less
  case CG_COMPARE_LESS_EQUAL: return .lessEqual
  case CG_COMPARE_GREATER: return .greater
  case CG_COMPARE_GREATER_EQUAL: return .greaterEqual
  default: return .always
  }
}

func cullMode(_ cull: cg_cull) -> MTLCullMode {
  switch cull {
  case CG_CULL_BACK: return .back
  case CG_CULL_FRONT: return .front
  default: return .none
  }
}

func loadAction(_ load: cg_load) -> MTLLoadAction {
  switch load {
  case CG_LOAD_CLEAR: return .clear
  case CG_LOAD_LOAD: return .load
  default: return .dontCare
  }
}

func applyBlend(_ blend: cg_blend, to attachment: MTLRenderPipelineColorAttachmentDescriptor) {
  switch blend {
  case CG_BLEND_ALPHA:
    attachment.isBlendingEnabled = true
    attachment.sourceRGBBlendFactor = .sourceAlpha
    attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
    attachment.sourceAlphaBlendFactor = .one
    attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
  case CG_BLEND_ADD:
    attachment.isBlendingEnabled = true
    attachment.sourceRGBBlendFactor = .one
    attachment.destinationRGBBlendFactor = .one
    attachment.sourceAlphaBlendFactor = .one
    attachment.destinationAlphaBlendFactor = .one
  case CG_BLEND_MULTIPLY:
    attachment.isBlendingEnabled = true
    attachment.sourceRGBBlendFactor = .destinationColor
    attachment.destinationRGBBlendFactor = .zero
    attachment.sourceAlphaBlendFactor = .zero
    attachment.destinationAlphaBlendFactor = .one
  default:
    attachment.isBlendingEnabled = false
  }
}

func formats<T>(_ tuple: T, count: Int) -> [cg_format] {
  withUnsafeBytes(of: tuple) { Array($0.bindMemory(to: cg_format.self).prefix(count)) }
}

func blends<T>(_ tuple: T, count: Int) -> [cg_blend] {
  withUnsafeBytes(of: tuple) { Array($0.bindMemory(to: cg_blend.self).prefix(count)) }
}

func colorAttachments<T>(_ tuple: T, count: Int) -> [cg_color_attachment] {
  withUnsafeBytes(of: tuple) { Array($0.bindMemory(to: cg_color_attachment.self).prefix(count)) }
}

final class ComputePipeline {
  let state: MTLComputePipelineState
  let threads: MTLSize

  init(state: MTLComputePipelineState, threads: MTLSize) {
    self.state = state
    self.threads = threads
  }
}
