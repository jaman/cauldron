import Foundation
import Metal
import QuartzCore

final class Device {
  let device: MTLDevice
  let queue: MTLCommandQueue
  let residency: MTLResidencySet
  let target = Texture(texture: nil)
  let framesInFlight = DispatchSemaphore(value: 3)
  let fence: MTLFence
  let lock = NSLock()
  var layer: CAMetalLayer?
  var view: UnsafeMutableRawPointer?
  var drawable: CAMetalDrawable?
  var commands: Commands?
  var residencyChanged = false
  var submitted: UInt64 = 0
  var completed: UInt64 = 0
  var gpuSeconds: Float = 0
  var released: [(frame: UInt64, object: AnyObject)] = []

  init?(device: MTLDevice) {
    guard let queue = device.makeCommandQueue() else { return nil }
    let descriptor = MTLResidencySetDescriptor()
    descriptor.label = "cauldron_gpu"
    guard let residency = try? device.makeResidencySet(descriptor: descriptor) else { return nil }
    self.device = device
    self.queue = queue
    self.residency = residency
    guard let fence = device.makeFence() else { return nil }
    self.fence = fence
    queue.addResidencySet(residency)
  }

  func keepResident(_ allocation: MTLAllocation) {
    lock.lock()
    residency.addAllocation(allocation)
    residencyChanged = true
    lock.unlock()
  }

  func release(_ object: AnyObject) {
    lock.lock()
    released.append((frame: submitted + 1, object: object))
    lock.unlock()
  }

  func frameCompleted(_ frame: UInt64, gpuSeconds seconds: Float) {
    lock.lock()
    completed = max(completed, frame)
    if seconds > 0 { gpuSeconds = seconds }
    lock.unlock()
    framesInFlight.signal()
  }

  func collectReleased() {
    lock.lock()
    let finished = released.filter { $0.frame <= completed }
    released.removeAll { $0.frame <= completed }
    for entry in finished { forget(entry.object) }
    if residencyChanged {
      residency.commit()
      residencyChanged = false
    }
    lock.unlock()
  }

  private func forget(_ object: AnyObject) {
    switch object {
    case let buffer as Buffer:
      residency.removeAllocation(buffer.buffer)
      residencyChanged = true
    case let texture as Texture:
      if let allocation = texture.texture { residency.removeAllocation(allocation) }
      residencyChanged = true
    default:
      break
    }
  }

  func info() -> (name: String, rayTracing: Bool, meshShaders: Bool, unifiedMemory: Bool) {
    (device.name, device.supportsRaytracing, device.supportsFamily(.metal3), device.hasUnifiedMemory)
  }
}
