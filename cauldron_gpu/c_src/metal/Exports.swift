import Foundation
import Metal
import QuartzCore

@_cdecl("cg_metal_device_create")
public func deviceCreate() -> OpaquePointer? {
  guard let mtl = MTLCreateSystemDefaultDevice(), let device = Device(device: mtl) else { return nil }
  return retained(device)
}

@_cdecl("cg_metal_device_destroy")
public func deviceDestroy(_ pointer: OpaquePointer) {
  let device: Device = released(pointer)
  device.queue.makeCommandBuffer().map { buffer in
    buffer.commit()
    buffer.waitUntilCompleted()
  }
  device.lock.lock()
  device.completed = device.submitted
  device.lock.unlock()
  device.collectReleased()
}

@_cdecl("cg_metal_device_info")
public func deviceInfo(_ pointer: OpaquePointer, _ info: UnsafeMutablePointer<cg_device_info>) {
  let device: Device = borrowed(pointer)
  let details = device.info()
  info.pointee.ray_tracing = details.rayTracing
  info.pointee.mesh_shaders = details.meshShaders
  info.pointee.unified_memory = details.unifiedMemory
  info.pointee.upscaling = upscalingSupported(device.device)
  info.pointee.frame_generation = frameGenerationSupported(device.device)
  copyString(details.name, into: &info.pointee.name)
  copyString("metal", into: &info.pointee.backend)
}

@_cdecl("cg_metal_surface_set")
public func surfaceSet(_ pointer: OpaquePointer, _ layerPointer: UnsafeMutableRawPointer?, _ view: UnsafeMutableRawPointer?) {
  let device: Device = borrowed(pointer)
  device.view = view
  guard let layerPointer else {
    device.layer = nil
    return
  }
  let layer = Unmanaged<CAMetalLayer>.fromOpaque(layerPointer).takeUnretainedValue()
  layer.device = device.device
  layer.pixelFormat = .bgra8Unorm_srgb
  layer.framebufferOnly = false
  layer.maximumDrawableCount = 3
  layer.displaySyncEnabled = true
  device.layer = layer
}

@_cdecl("cg_metal_surface_view")
public func surfaceView(_ pointer: OpaquePointer) -> UnsafeMutableRawPointer? {
  let device: Device = borrowed(pointer)
  return device.view
}

@_cdecl("cg_metal_surface_resize")
public func surfaceResize(_ pointer: OpaquePointer, _ width: UInt32, _ height: UInt32) {
  let device: Device = borrowed(pointer)
  device.layer?.drawableSize = CGSize(width: Int(width), height: Int(height))
}

@_cdecl("cg_metal_surface_format")
public func surfaceFormat(_ pointer: OpaquePointer) -> cg_format {
  CG_FORMAT_BGRA8_SRGB
}

@_cdecl("cg_metal_buffer_create")
public func bufferCreate(_ pointer: OpaquePointer, _ size: UInt64, _ memory: cg_memory, _ label: UnsafePointer<CChar>?) -> OpaquePointer? {
  let device: Device = borrowed(pointer)
  let options: MTLResourceOptions = memory == CG_MEMORY_GPU ? .storageModePrivate : .storageModeShared
  guard let buffer = device.device.makeBuffer(length: max(Int(size), 16), options: options) else { return nil }
  if let label { buffer.label = String(cString: label) }
  device.keepResident(buffer)
  return retained(Buffer(buffer: buffer))
}

@_cdecl("cg_metal_buffer_destroy")
public func bufferDestroy(_ pointer: OpaquePointer, _ bufferPointer: OpaquePointer) {
  let device: Device = borrowed(pointer)
  let buffer: Buffer = released(bufferPointer)
  device.release(buffer)
}

@_cdecl("cg_metal_buffer_contents")
public func bufferContents(_ pointer: OpaquePointer) -> UnsafeMutableRawPointer? {
  let buffer: Buffer = borrowed(pointer)
  return buffer.buffer.storageMode == .shared ? buffer.buffer.contents() : nil
}

@_cdecl("cg_metal_buffer_address")
public func bufferAddress(_ pointer: OpaquePointer) -> UInt64 {
  let buffer: Buffer = borrowed(pointer)
  return buffer.buffer.gpuAddress
}

@_cdecl("cg_metal_texture_create")
public func textureCreate(_ pointer: OpaquePointer, _ desc: UnsafePointer<cg_texture_desc>) -> OpaquePointer? {
  let device: Device = borrowed(pointer)
  let spec = desc.pointee
  let descriptor = MTLTextureDescriptor()
  descriptor.textureType = spec.kind == CG_TEXTURE_CUBE ? .typeCube : .type2D
  descriptor.pixelFormat = pixelFormat(spec.format)
  descriptor.width = Int(spec.width)
  descriptor.height = Int(spec.height)
  descriptor.mipmapLevelCount = Int(max(spec.mip_levels, 1))
  descriptor.storageMode = .private
  descriptor.usage = textureUsage(spec.usage)
  guard let texture = device.device.makeTexture(descriptor: descriptor) else { return nil }
  if let label = spec.label { texture.label = String(cString: label) }
  device.keepResident(texture)
  return retained(Texture(texture: texture))
}

@_cdecl("cg_metal_texture_destroy")
public func textureDestroy(_ pointer: OpaquePointer, _ texturePointer: OpaquePointer) {
  let device: Device = borrowed(pointer)
  let texture: Texture = released(texturePointer)
  device.release(texture)
}

@_cdecl("cg_metal_texture_handle")
public func textureHandle(_ pointer: OpaquePointer) -> UInt64 {
  let texture: Texture = borrowed(pointer)
  return texture.texture?.gpuResourceID._impl ?? 0
}

@_cdecl("cg_metal_sampler_create")
public func samplerCreate(_ pointer: OpaquePointer, _ desc: UnsafePointer<cg_sampler_desc>) -> OpaquePointer? {
  let device: Device = borrowed(pointer)
  let spec = desc.pointee
  let descriptor = MTLSamplerDescriptor()
  let filter: MTLSamplerMinMagFilter = spec.filter == CG_FILTER_LINEAR ? .linear : .nearest
  let address: MTLSamplerAddressMode = spec.address == CG_ADDRESS_REPEAT ? .repeat : .clampToEdge
  descriptor.minFilter = filter
  descriptor.magFilter = filter
  descriptor.mipFilter = spec.mip_filter == CG_FILTER_LINEAR ? .linear : .nearest
  descriptor.sAddressMode = address
  descriptor.tAddressMode = address
  descriptor.rAddressMode = address
  descriptor.maxAnisotropy = Int(max(spec.max_anisotropy, 1))
  descriptor.supportArgumentBuffers = true
  guard let sampler = device.device.makeSamplerState(descriptor: descriptor) else { return nil }
  return retained(Sampler(sampler: sampler))
}

@_cdecl("cg_metal_sampler_destroy")
public func samplerDestroy(_ pointer: OpaquePointer, _ samplerPointer: OpaquePointer) {
  let device: Device = borrowed(pointer)
  let sampler: Sampler = released(samplerPointer)
  device.release(sampler)
}

@_cdecl("cg_metal_sampler_handle")
public func samplerHandle(_ pointer: OpaquePointer) -> UInt64 {
  let sampler: Sampler = borrowed(pointer)
  return sampler.sampler.gpuResourceID._impl
}

@_cdecl("cg_metal_pipeline_create")
public func pipelineCreate(_ pointer: OpaquePointer, _ desc: UnsafePointer<cg_pipeline_desc>) -> OpaquePointer? {
  let device: Device = borrowed(pointer)
  let spec = desc.pointee
  let descriptor = MTLRenderPipelineDescriptor()
  if let label = spec.label { descriptor.label = String(cString: label) }
  guard let vertex = shaderFunction(device.device, spec.vertex) else { return nil }
  descriptor.vertexFunction = vertex
  descriptor.fragmentFunction = shaderFunction(device.device, spec.fragment)
  let count = Int(spec.color_count)
  let blendModes = blends(spec.blend, count: count)
  for (index, format) in formats(spec.color_formats, count: count).enumerated() {
    descriptor.colorAttachments[index].pixelFormat = pixelFormat(format)
    applyBlend(blendModes[index], to: descriptor.colorAttachments[index])
  }
  descriptor.depthAttachmentPixelFormat = pixelFormat(spec.depth_format)
  let depthDescriptor = MTLDepthStencilDescriptor()
  depthDescriptor.depthCompareFunction = spec.depth_format == CG_FORMAT_UNDEFINED ? .always : compareFunction(spec.depth_compare)
  depthDescriptor.isDepthWriteEnabled = spec.depth_format != CG_FORMAT_UNDEFINED && spec.depth_write
  do {
    let state = try device.device.makeRenderPipelineState(descriptor: descriptor)
    guard let depth = device.device.makeDepthStencilState(descriptor: depthDescriptor) else { return nil }
    let pipeline = Pipeline(
      state: state, depth: depth, cull: cullMode(spec.cull),
      depthBias: spec.depth_bias, depthSlopeBias: spec.depth_slope_bias)
    return retained(pipeline)
  } catch {
    FileHandle.standardError.write("cauldron_gpu: pipeline \(descriptor.label ?? ""): \(error)\n".data(using: .utf8)!)
    return nil
  }
}

@_cdecl("cg_metal_pipeline_destroy")
public func pipelineDestroy(_ pointer: OpaquePointer, _ pipelinePointer: OpaquePointer) {
  let device: Device = borrowed(pointer)
  let pipeline: Pipeline = released(pipelinePointer)
  device.release(pipeline)
}

@_cdecl("cg_metal_frame_begin")
public func frameBegin(_ pointer: OpaquePointer) -> OpaquePointer? {
  let device: Device = borrowed(pointer)
  device.collectReleased()
  if let layer = device.layer, layer.drawableSize.width == 0 || layer.drawableSize.height == 0 { return nil }
  device.framesInFlight.wait()
  let drawable = device.layer?.nextDrawable()
  guard device.layer == nil || drawable != nil, let buffer = device.queue.makeCommandBuffer() else {
    device.framesInFlight.signal()
    return nil
  }
  device.drawable = drawable
  device.target.texture = drawable?.texture
  let commands = Commands(buffer: buffer, fence: device.fence)
  device.commands = commands
  return OpaquePointer(Unmanaged.passUnretained(commands).toOpaque())
}

@_cdecl("cg_metal_frame_target")
public func frameTarget(_ pointer: OpaquePointer) -> OpaquePointer? {
  let device: Device = borrowed(pointer)
  guard device.target.texture != nil else { return nil }
  return OpaquePointer(Unmanaged.passUnretained(device.target).toOpaque())
}

@_cdecl("cg_metal_frame_end")
public func frameEnd(_ pointer: OpaquePointer, _ commandsPointer: OpaquePointer) {
  let device: Device = borrowed(pointer)
  let commands: Commands = borrowed(commandsPointer)
  commands.finish()
  if let drawable = device.drawable { commands.buffer.present(drawable) }
  device.lock.lock()
  device.submitted += 1
  let frame = device.submitted
  device.lock.unlock()
  commands.buffer.addCompletedHandler { [weak device] buffer in
    device?.frameCompleted(frame, gpuSeconds: Float(buffer.gpuEndTime - buffer.gpuStartTime))
  }
  commands.buffer.commit()
  device.drawable = nil
  device.target.texture = nil
  device.commands = nil
}

@_cdecl("cg_metal_frame_end_pair")
public func frameEndPair(_ pointer: OpaquePointer, _ commandsPointer: OpaquePointer, _ first: OpaquePointer, _ second: OpaquePointer, _ spacing: Float) {
  let device: Device = borrowed(pointer)
  let commands: Commands = borrowed(commandsPointer)
  let firstTexture: Texture = borrowed(first)
  let secondTexture: Texture = borrowed(second)
  if let drawable = device.drawable, let source = firstTexture.texture, let blit = commands.blitEncoder() {
    blit.copy(from: source, to: drawable.texture)
    commands.endBlit()
    commands.buffer.present(drawable)
    if let next = device.layer?.nextDrawable(), let source = secondTexture.texture, let blit = commands.blitEncoder() {
      blit.copy(from: source, to: next.texture)
      commands.endBlit()
      commands.buffer.present(next, afterMinimumDuration: CFTimeInterval(spacing))
    }
  }
  device.drawable = nil
  frameEnd(pointer, commandsPointer)
}

@_cdecl("cg_metal_frame_gpu_seconds")
public func frameGpuSeconds(_ pointer: OpaquePointer) -> Float {
  let device: Device = borrowed(pointer)
  device.lock.lock()
  defer { device.lock.unlock() }
  return device.gpuSeconds
}

@_cdecl("cg_metal_cmd_copy_buffer")
public func cmdCopyBuffer(_ pointer: OpaquePointer, _ src: OpaquePointer, _ srcOffset: UInt64, _ dst: OpaquePointer, _ dstOffset: UInt64, _ size: UInt64) {
  let commands: Commands = borrowed(pointer)
  let source: Buffer = borrowed(src)
  let destination: Buffer = borrowed(dst)
  commands.blitEncoder()?.copy(
    from: source.buffer, sourceOffset: Int(srcOffset),
    to: destination.buffer, destinationOffset: Int(dstOffset), size: Int(size))
}

@_cdecl("cg_metal_cmd_copy_to_texture")
public func cmdCopyToTexture(_ pointer: OpaquePointer, _ src: OpaquePointer, _ srcOffset: UInt64, _ bytesPerRow: UInt32, _ dst: OpaquePointer, _ mip: UInt32, _ layer: UInt32, _ width: UInt32, _ height: UInt32) {
  let commands: Commands = borrowed(pointer)
  let source: Buffer = borrowed(src)
  let destination: Texture = borrowed(dst)
  guard let texture = destination.texture else { return }
  commands.blitEncoder()?.copy(
    from: source.buffer, sourceOffset: Int(srcOffset),
    sourceBytesPerRow: Int(bytesPerRow), sourceBytesPerImage: Int(bytesPerRow) * Int(height),
    sourceSize: MTLSize(width: Int(width), height: Int(height), depth: 1),
    to: texture, destinationSlice: Int(layer), destinationLevel: Int(mip),
    destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
}

@_cdecl("cg_metal_cmd_generate_mips")
public func cmdGenerateMips(_ pointer: OpaquePointer, _ texturePointer: OpaquePointer) {
  let commands: Commands = borrowed(pointer)
  let texture: Texture = borrowed(texturePointer)
  guard let mtl = texture.texture, mtl.mipmapLevelCount > 1 else { return }
  commands.blitEncoder()?.generateMipmaps(for: mtl)
}

@_cdecl("cg_metal_cmd_copy_texture_to_buffer")
public func cmdCopyTextureToBuffer(_ pointer: OpaquePointer, _ src: OpaquePointer, _ dst: OpaquePointer, _ dstOffset: UInt64, _ bytesPerRow: UInt32) {
  let commands: Commands = borrowed(pointer)
  let source: Texture = borrowed(src)
  let destination: Buffer = borrowed(dst)
  guard let texture = source.texture else { return }
  commands.blitEncoder()?.copy(
    from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
    sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
    to: destination.buffer, destinationOffset: Int(dstOffset),
    destinationBytesPerRow: Int(bytesPerRow), destinationBytesPerImage: Int(bytesPerRow) * texture.height)
}

@_cdecl("cg_metal_cmd_begin_pass")

public func cmdBeginPass(_ pointer: OpaquePointer, _ desc: UnsafePointer<cg_pass_desc>) {
  let commands: Commands = borrowed(pointer)
  commands.beginPass(desc.pointee)
}

@_cdecl("cg_metal_cmd_end_pass")
public func cmdEndPass(_ pointer: OpaquePointer) {
  let commands: Commands = borrowed(pointer)
  commands.endPass()
}

@_cdecl("cg_metal_cmd_set_pipeline")
public func cmdSetPipeline(_ pointer: OpaquePointer, _ pipelinePointer: OpaquePointer) {
  let commands: Commands = borrowed(pointer)
  let pipeline: Pipeline = borrowed(pipelinePointer)
  commands.setPipeline(pipeline)
}

@_cdecl("cg_metal_cmd_push")
public func cmdPush(_ pointer: OpaquePointer, _ data: UnsafeRawPointer, _ size: UInt32) {
  let commands: Commands = borrowed(pointer)
  commands.push(data, size: Int(size))
}

@_cdecl("cg_metal_cmd_draw")
public func cmdDraw(_ pointer: OpaquePointer, _ vertexCount: UInt32, _ instanceCount: UInt32, _ firstVertex: UInt32) {
  let commands: Commands = borrowed(pointer)
  commands.render?.drawPrimitives(
    type: .triangle, vertexStart: Int(firstVertex), vertexCount: Int(vertexCount),
    instanceCount: Int(instanceCount))
}

@_cdecl("cg_metal_cmd_draw_indexed")
public func cmdDrawIndexed(_ pointer: OpaquePointer, _ indices: OpaquePointer, _ indexCount: UInt32, _ instanceCount: UInt32, _ firstIndex: UInt32) {
  let commands: Commands = borrowed(pointer)
  let buffer: Buffer = borrowed(indices)
  commands.render?.drawIndexedPrimitives(
    type: .triangle, indexCount: Int(indexCount), indexType: .uint32,
    indexBuffer: buffer.buffer, indexBufferOffset: Int(firstIndex) * 4,
    instanceCount: Int(instanceCount))
}

private func textureUsage(_ usage: UInt32) -> MTLTextureUsage {
  var result: MTLTextureUsage = []
  if usage & UInt32(CG_TEXTURE_SAMPLED) != 0 { result.insert(.shaderRead) }
  if usage & UInt32(CG_TEXTURE_RENDER_TARGET | CG_TEXTURE_DEPTH) != 0 { result.insert(.renderTarget) }
  if usage & UInt32(CG_TEXTURE_STORAGE) != 0 { result.insert(.shaderWrite) }
  return result
}

func shaderFunction(_ device: MTLDevice, _ shader: cg_shader) -> MTLFunction? {
  guard let code = shader.code, shader.size > 0, let entry = shader.entry else { return nil }
  let data = DispatchData(bytes: UnsafeRawBufferPointer(start: code, count: shader.size))
  do {
    let library = try device.makeLibrary(data: data as __DispatchData)
    return library.makeFunction(name: String(cString: entry))
  } catch {
    FileHandle.standardError.write("cauldron_gpu: shader library: \(error)\n".data(using: .utf8)!)
    return nil
  }
}

private func copyString<T>(_ string: String, into storage: inout T) {
  withUnsafeMutableBytes(of: &storage) { bytes in
    let utf8 = Array(string.utf8.prefix(bytes.count - 1))
    bytes.copyBytes(from: utf8)
    bytes[utf8.count] = 0
  }
}
