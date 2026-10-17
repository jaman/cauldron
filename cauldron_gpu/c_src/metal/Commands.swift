import Metal
import QuartzCore

final class Commands {
  let buffer: MTLCommandBuffer
  let fence: MTLFence
  var render: MTLRenderCommandEncoder?
  var blit: MTLBlitCommandEncoder?
  var compute: MTLComputeCommandEncoder?
  var computeThreads = MTLSize(width: 8, height: 8, depth: 1)

  init(buffer: MTLCommandBuffer, fence: MTLFence) {
    self.buffer = buffer
    self.fence = fence
  }

  func blitEncoder() -> MTLBlitCommandEncoder? {
    if blit == nil {
      endCompute()
      blit = buffer.makeBlitCommandEncoder()
      blit?.waitForFence(fence)
    }
    return blit
  }

  func endBlit() {
    guard let blit else { return }
    blit.updateFence(fence)
    blit.endEncoding()
    self.blit = nil
  }

  func accelerationEncoder() -> MTLAccelerationStructureCommandEncoder? {
    endBlit()
    endCompute()
    let encoder = buffer.makeAccelerationStructureCommandEncoder()
    encoder?.waitForFence(fence)
    return encoder
  }

  func endAcceleration(_ encoder: MTLAccelerationStructureCommandEncoder) {
    encoder.updateFence(fence)
    encoder.endEncoding()
  }

  func beginCompute(label: String?) {
    endBlit()
    endCompute()
    compute = buffer.makeComputeCommandEncoder()
    if let label { compute?.label = label }
    compute?.waitForFence(fence)
  }

  func endCompute() {
    guard let compute else { return }
    compute.updateFence(fence)
    compute.endEncoding()
    self.compute = nil
  }

  func beginPass(_ desc: cg_pass_desc) {
    endBlit()
    endCompute()
    let pass = MTLRenderPassDescriptor()
    let colors = colorAttachments(desc.colors, count: Int(desc.color_count))
    for (index, color) in colors.enumerated() {
      guard let pointer = color.texture else { continue }
      let texture: Texture = borrowed(pointer)
      let attachment = pass.colorAttachments[index]!
      attachment.texture = texture.texture
      attachment.loadAction = loadAction(color.load)
      attachment.storeAction = color.store ? .store : .dontCare
      attachment.clearColor = MTLClearColor(
        red: Double(color.clear.0), green: Double(color.clear.1),
        blue: Double(color.clear.2), alpha: Double(color.clear.3))
    }
    if let pointer = desc.depth.texture {
      let texture: Texture = borrowed(pointer)
      pass.depthAttachment.texture = texture.texture
      pass.depthAttachment.loadAction = loadAction(desc.depth.load)
      pass.depthAttachment.storeAction = desc.depth.store ? .store : .dontCare
      pass.depthAttachment.clearDepth = Double(desc.depth.clear)
    }
    render = buffer.makeRenderCommandEncoder(descriptor: pass)
    if let label = desc.label { render?.label = String(cString: label) }
    render?.waitForFence(fence, before: .vertex)
    render?.setFrontFacing(.counterClockwise)
  }

  func endPass() {
    guard let render else { return }
    render.updateFence(fence, after: .fragment)
    render.endEncoding()
    self.render = nil
  }

  func setPipeline(_ pipeline: Pipeline) {
    guard let render else { return }
    render.setRenderPipelineState(pipeline.state)
    render.setDepthStencilState(pipeline.depth)
    render.setCullMode(pipeline.cull)
    render.setDepthBias(pipeline.depthBias, slopeScale: pipeline.depthSlopeBias, clamp: 0)
  }

  func setComputePipeline(_ pipeline: ComputePipeline) {
    compute?.setComputePipelineState(pipeline.state)
    computeThreads = pipeline.threads
  }

  func push(_ data: UnsafeRawPointer, size: Int) {
    if let render {
      render.setVertexBytes(data, length: size, index: 0)
      render.setFragmentBytes(data, length: size, index: 0)
    }
    compute?.setBytes(data, length: size, index: 0)
  }

  func dispatch(_ groups: MTLSize) {
    compute?.dispatchThreadgroups(groups, threadsPerThreadgroup: computeThreads)
  }

  func finish() {
    endPass()
    endBlit()
    endCompute()
  }
}
