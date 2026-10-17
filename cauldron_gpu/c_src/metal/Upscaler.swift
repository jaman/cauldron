import Foundation
import Metal
import MetalFX

final class Upscaler {
  let scaler: MTLFXTemporalScaler

  init(scaler: MTLFXTemporalScaler) {
    self.scaler = scaler
  }
}

func upscalingSupported(_ device: MTLDevice) -> Bool {
  MTLFXTemporalScalerDescriptor.supportsDevice(device)
}

@_cdecl("cg_metal_upscaler_create")
public func upscalerCreate(_ pointer: OpaquePointer, _ desc: UnsafePointer<cg_upscaler_desc>) -> OpaquePointer? {
  let device: Device = borrowed(pointer)
  let spec = desc.pointee
  guard upscalingSupported(device.device) else { return nil }
  let descriptor = MTLFXTemporalScalerDescriptor()
  descriptor.inputWidth = Int(spec.input_width)
  descriptor.inputHeight = Int(spec.input_height)
  descriptor.outputWidth = Int(spec.output_width)
  descriptor.outputHeight = Int(spec.output_height)
  descriptor.colorTextureFormat = pixelFormat(spec.color_format)
  descriptor.depthTextureFormat = pixelFormat(spec.depth_format)
  descriptor.motionTextureFormat = pixelFormat(spec.motion_format)
  descriptor.outputTextureFormat = pixelFormat(spec.output_format)
  guard let scaler = descriptor.makeTemporalScaler(device: device.device) else { return nil }
  scaler.fence = device.fence
  return retained(Upscaler(scaler: scaler))
}

@_cdecl("cg_metal_upscaler_destroy")
public func upscalerDestroy(_ pointer: OpaquePointer, _ upscalerPointer: OpaquePointer) {
  let device: Device = borrowed(pointer)
  let upscaler: Upscaler = released(upscalerPointer)
  device.release(upscaler)
}

@_cdecl("cg_metal_cmd_upscale")
public func cmdUpscale(_ pointer: OpaquePointer, _ upscalerPointer: OpaquePointer, _ frame: UnsafePointer<cg_upscale>) {
  let commands: Commands = borrowed(pointer)
  let upscaler: Upscaler = borrowed(upscalerPointer)
  let spec = frame.pointee
  guard let color = texture(spec.color), let depth = texture(spec.depth), let motion = texture(spec.motion),
        let output = texture(spec.output) else { return }
  commands.finish()
  let scaler = upscaler.scaler
  scaler.colorTexture = color
  scaler.depthTexture = depth
  scaler.motionTexture = motion
  scaler.outputTexture = output
  scaler.jitterOffsetX = spec.jitter_x
  scaler.jitterOffsetY = spec.jitter_y
  scaler.motionVectorScaleX = spec.motion_scale_x
  scaler.motionVectorScaleY = spec.motion_scale_y
  scaler.reset = spec.reset
  scaler.isDepthReversed = spec.reversed_depth
  scaler.encode(commandBuffer: commands.buffer)
}

private func texture(_ pointer: OpaquePointer?) -> MTLTexture? {
  guard let pointer else { return nil }
  let wrapped: Texture = borrowed(pointer)
  return wrapped.texture
}

final class Interpolator {
  let interpolator: MTLFXFrameInterpolator

  init(interpolator: MTLFXFrameInterpolator) {
    self.interpolator = interpolator
  }
}

func frameGenerationSupported(_ device: MTLDevice) -> Bool {
  MTLFXFrameInterpolatorDescriptor.supportsDevice(device)
}

@_cdecl("cg_metal_interpolator_create")
public func interpolatorCreate(_ pointer: OpaquePointer, _ desc: UnsafePointer<cg_upscaler_desc>) -> OpaquePointer? {
  let device: Device = borrowed(pointer)
  let spec = desc.pointee
  guard frameGenerationSupported(device.device) else { return nil }
  let descriptor = MTLFXFrameInterpolatorDescriptor()
  descriptor.inputWidth = Int(spec.input_width)
  descriptor.inputHeight = Int(spec.input_height)
  descriptor.outputWidth = Int(spec.output_width)
  descriptor.outputHeight = Int(spec.output_height)
  descriptor.colorTextureFormat = pixelFormat(spec.color_format)
  descriptor.outputTextureFormat = pixelFormat(spec.output_format)
  descriptor.depthTextureFormat = pixelFormat(spec.depth_format)
  descriptor.motionTextureFormat = pixelFormat(spec.motion_format)
  descriptor.uiTextureFormat = pixelFormat(spec.color_format)
  if #available(macOS 27.0, *) { descriptor.requiresPrevColorTexture = true }
  guard let interpolator = descriptor.makeFrameInterpolator(device: device.device) else { return nil }
  interpolator.fence = device.fence
  return retained(Interpolator(interpolator: interpolator))
}

@_cdecl("cg_metal_interpolator_destroy")
public func interpolatorDestroy(_ pointer: OpaquePointer, _ interpolatorPointer: OpaquePointer) {
  let device: Device = borrowed(pointer)
  let interpolator: Interpolator = released(interpolatorPointer)
  device.release(interpolator)
}

@_cdecl("cg_metal_cmd_interpolate")
public func cmdInterpolate(_ pointer: OpaquePointer, _ interpolatorPointer: OpaquePointer, _ frame: UnsafePointer<cg_interpolate>) {
  let commands: Commands = borrowed(pointer)
  let wrapped: Interpolator = borrowed(interpolatorPointer)
  let spec = frame.pointee
  guard let color = texture(spec.color), let previous = texture(spec.previous_color), let depth = texture(spec.depth),
        let motion = texture(spec.motion), let output = texture(spec.output) else { return }
  commands.finish()
  let interpolator = wrapped.interpolator
  interpolator.colorTexture = color
  interpolator.prevColorTexture = previous
  interpolator.depthTexture = depth
  interpolator.motionTexture = motion
  interpolator.outputTexture = output
  interpolator.motionVectorScaleX = spec.motion_scale_x
  interpolator.motionVectorScaleY = spec.motion_scale_y
  interpolator.jitterOffsetX = spec.jitter_x
  interpolator.jitterOffsetY = spec.jitter_y
  interpolator.deltaTime = spec.delta_time
  interpolator.nearPlane = spec.near_plane
  interpolator.farPlane = spec.far_plane
  interpolator.fieldOfView = spec.fov_y * 180 / Float.pi
  interpolator.aspectRatio = spec.aspect
  interpolator.shouldResetHistory = spec.reset
  interpolator.isDepthReversed = spec.reversed_depth
  interpolator.encode(commandBuffer: commands.buffer)
}
