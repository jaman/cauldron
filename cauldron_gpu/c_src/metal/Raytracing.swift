import Foundation
import Metal

final class Accel {
  let structure: MTLAccelerationStructure
  let children: [Accel]
  let instances: MTLBuffer?

  init(structure: MTLAccelerationStructure, children: [Accel], instances: MTLBuffer?) {
    self.structure = structure
    self.children = children
    self.instances = instances
  }
}

@_cdecl("cg_metal_compute_pipeline_create")
public func computePipelineCreate(_ pointer: OpaquePointer, _ desc: UnsafePointer<cg_compute_desc>) -> OpaquePointer? {
  let device: Device = borrowed(pointer)
  let spec = desc.pointee
  guard let function = shaderFunction(device.device, spec.compute) else { return nil }
  do {
    let state = try device.device.makeComputePipelineState(function: function)
    let threads = MTLSize(width: Int(max(spec.threads.0, 1)), height: Int(max(spec.threads.1, 1)), depth: Int(max(spec.threads.2, 1)))
    return retained(ComputePipeline(state: state, threads: threads))
  } catch {
    FileHandle.standardError.write("cauldron_gpu: compute pipeline: \(error)\n".data(using: .utf8)!)
    return nil
  }
}

@_cdecl("cg_metal_accel_create_geometry")
public func accelCreateGeometry(_ pointer: OpaquePointer, _ commandsPointer: OpaquePointer, _ vertices: OpaquePointer, _ vertexCount: UInt32, _ vertexStride: UInt32, _ indices: OpaquePointer, _ indexCount: UInt32) -> OpaquePointer? {
  let device: Device = borrowed(pointer)
  let commands: Commands = borrowed(commandsPointer)
  let vertexBuffer: Buffer = borrowed(vertices)
  let indexBuffer: Buffer = borrowed(indices)
  guard device.device.supportsRaytracing, indexCount >= 3 else { return nil }
  let geometry = MTLAccelerationStructureTriangleGeometryDescriptor()
  geometry.vertexBuffer = vertexBuffer.buffer
  geometry.vertexStride = Int(vertexStride)
  geometry.vertexFormat = .float3
  geometry.indexBuffer = indexBuffer.buffer
  geometry.indexType = .uint32
  geometry.triangleCount = Int(indexCount / 3)
  geometry.opaque = true
  let descriptor = MTLPrimitiveAccelerationStructureDescriptor()
  descriptor.geometryDescriptors = [geometry]
  guard let structure = build(device, commands, descriptor) else { return nil }
  return retained(Accel(structure: structure, children: [], instances: nil))
}

@_cdecl("cg_metal_accel_create_scene")
public func accelCreateScene(_ pointer: OpaquePointer, _ commandsPointer: OpaquePointer, _ instances: UnsafePointer<cg_accel_instance>, _ count: UInt32) -> OpaquePointer? {
  let device: Device = borrowed(pointer)
  let commands: Commands = borrowed(commandsPointer)
  guard device.device.supportsRaytracing, count > 0 else { return nil }
  var children: [Accel] = []
  var indexOf: [ObjectIdentifier: UInt32] = [:]
  let stride = MemoryLayout<MTLAccelerationStructureInstanceDescriptor>.stride
  guard let buffer = device.device.makeBuffer(length: stride * Int(count), options: .storageModeShared) else { return nil }
  let descriptors = buffer.contents().bindMemory(to: MTLAccelerationStructureInstanceDescriptor.self, capacity: Int(count))
  for index in 0..<Int(count) {
    let instance = instances[index]
    guard let geometryPointer = instance.geometry else { return nil }
    let geometry: Accel = borrowed(geometryPointer)
    let key = ObjectIdentifier(geometry)
    let slot = indexOf[key] ?? {
      children.append(geometry)
      indexOf[key] = UInt32(children.count - 1)
      return UInt32(children.count - 1)
    }()
    descriptors[index] = instanceDescriptor(instance, slot: slot)
  }
  let descriptor = MTLInstanceAccelerationStructureDescriptor()
  descriptor.instancedAccelerationStructures = children.map(\.structure)
  descriptor.instanceCount = Int(count)
  descriptor.instanceDescriptorBuffer = buffer
  descriptor.instanceDescriptorType = .default
  guard let structure = build(device, commands, descriptor) else { return nil }
  return retained(Accel(structure: structure, children: children, instances: buffer))
}

@_cdecl("cg_metal_accel_destroy")
public func accelDestroy(_ pointer: OpaquePointer, _ accelPointer: OpaquePointer) {
  let device: Device = borrowed(pointer)
  let accel: Accel = released(accelPointer)
  device.release(accel)
}

@_cdecl("cg_metal_cmd_begin_compute")
public func cmdBeginCompute(_ pointer: OpaquePointer, _ label: UnsafePointer<CChar>?) {
  let commands: Commands = borrowed(pointer)
  commands.beginCompute(label: label.map { String(cString: $0) })
}

@_cdecl("cg_metal_cmd_end_compute")
public func cmdEndCompute(_ pointer: OpaquePointer) {
  let commands: Commands = borrowed(pointer)
  commands.endCompute()
}

@_cdecl("cg_metal_cmd_set_compute_pipeline")
public func cmdSetComputePipeline(_ pointer: OpaquePointer, _ pipelinePointer: OpaquePointer) {
  let commands: Commands = borrowed(pointer)
  let pipeline: ComputePipeline = borrowed(pipelinePointer)
  commands.setComputePipeline(pipeline)
}

@_cdecl("cg_metal_cmd_set_accel")
public func cmdSetAccel(_ pointer: OpaquePointer, _ accelPointer: OpaquePointer) {
  let commands: Commands = borrowed(pointer)
  let accel: Accel = borrowed(accelPointer)
  commands.compute?.setAccelerationStructure(accel.structure, bufferIndex: 1)
  commands.compute?.useResource(accel.structure, usage: .read)
  for child in accel.children { commands.compute?.useResource(child.structure, usage: .read) }
}

@_cdecl("cg_metal_cmd_dispatch")
public func cmdDispatch(_ pointer: OpaquePointer, _ x: UInt32, _ y: UInt32, _ z: UInt32) {
  let commands: Commands = borrowed(pointer)
  commands.dispatch(MTLSize(width: Int(x), height: Int(y), depth: Int(z)))
}

private func build(_ device: Device, _ commands: Commands, _ descriptor: MTLAccelerationStructureDescriptor) -> MTLAccelerationStructure? {
  let sizes = device.device.accelerationStructureSizes(descriptor: descriptor)
  guard let structure = device.device.makeAccelerationStructure(size: sizes.accelerationStructureSize),
        let scratch = device.device.makeBuffer(length: max(sizes.buildScratchBufferSize, 16), options: .storageModePrivate),
        let encoder = commands.accelerationEncoder() else { return nil }
  encoder.build(accelerationStructure: structure, descriptor: descriptor, scratchBuffer: scratch, scratchBufferOffset: 0)
  commands.endAcceleration(encoder)
  return structure
}

private func instanceDescriptor(_ instance: cg_accel_instance, slot: UInt32) -> MTLAccelerationStructureInstanceDescriptor {
  var descriptor = MTLAccelerationStructureInstanceDescriptor()
  let rows = withUnsafeBytes(of: instance.transform) { Array($0.bindMemory(to: Float.self)) }
  var matrix = MTLPackedFloat4x3()
  withUnsafeMutableBytes(of: &matrix) { bytes in
    let columns = bytes.bindMemory(to: Float.self)
    for column in 0..<4 {
      for row in 0..<3 { columns[column * 3 + row] = rows[row * 4 + column] }
    }
  }
  descriptor.transformationMatrix = matrix
  descriptor.options = [.opaque, .disableTriangleCulling]
  descriptor.mask = instance.mask
  descriptor.intersectionFunctionTableOffset = 0
  descriptor.accelerationStructureIndex = slot
  return descriptor
}
