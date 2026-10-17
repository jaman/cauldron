#include "internal.hpp"

#include <algorithm>
#include <memory>
#include <stdexcept>

namespace cgvk {
namespace {

using BufferUsage = vk::BufferUsageFlagBits;

constexpr vk::BufferUsageFlags storage_usage = BufferUsage::eAccelerationStructureStorageKHR | BufferUsage::eShaderDeviceAddress;
constexpr vk::BufferUsageFlags scratch_usage = BufferUsage::eStorageBuffer | BufferUsage::eShaderDeviceAddress;
constexpr vk::BufferUsageFlags instance_usage = BufferUsage::eAccelerationStructureBuildInputReadOnlyKHR | BufferUsage::eShaderDeviceAddress;
constexpr uint64_t storage_alignment = 256;
constexpr uint64_t instance_alignment = 16;

struct BuildRequest {
  vk::AccelerationStructureTypeKHR type;
  vk::BuildAccelerationStructureFlagsKHR flags;
  vk::AccelerationStructureGeometryKHR geometry;
  uint32_t primitive_count;
};

void destroy_accel_now(cg_device &device, const cg_accel &accel) {
  device.device.destroyAccelerationStructureKHR(accel.handle);
  if (accel.set) device.device.freeDescriptorSets(device.bindless.accel_pool, accel.set);
  vmaDestroyBuffer(device.allocator, accel.storage.buffer, accel.storage.allocation);
}

std::unique_ptr<cg_accel> allocate_accel(cg_device &device, vk::AccelerationStructureTypeKHR type, vk::DeviceSize size) {
  auto accel = std::make_unique<cg_accel>();
  accel->storage = create_raw_buffer(device, size, storage_usage, CG_MEMORY_GPU, storage_alignment);
  try {
    accel->handle = device.device.createAccelerationStructureKHR({.buffer = accel->storage.buffer, .size = size, .type = type});
  } catch (...) {
    destroy_accel_now(device, *accel);
    throw;
  }
  accel->address = device.device.getAccelerationStructureAddressKHR({.accelerationStructure = accel->handle});
  return accel;
}

void record_build(cg_cmd &cmd, const vk::AccelerationStructureBuildGeometryInfoKHR &build, uint32_t primitive_count) {
  vk::AccelerationStructureBuildRangeInfoKHR range{.primitiveCount = primitive_count};
  const vk::AccelerationStructureBuildRangeInfoKHR *ranges = &range;
  record_memory_barrier(cmd.commands, full_memory_barrier());
  cmd.commands.buildAccelerationStructuresKHR(build, ranges);
  record_memory_barrier(cmd.commands, accel_build_barrier());
}

std::unique_ptr<cg_accel> build_accel(cg_device &device, cg_cmd &cmd, const BuildRequest &request) {
  vk::AccelerationStructureBuildGeometryInfoKHR build{
      .type = request.type,
      .flags = request.flags,
      .mode = vk::BuildAccelerationStructureModeKHR::eBuild,
      .geometryCount = 1,
      .pGeometries = &request.geometry,
  };
  auto sizes = device.device.getAccelerationStructureBuildSizesKHR(vk::AccelerationStructureBuildTypeKHR::eDevice, build, request.primitive_count);
  cg_buffer scratch = create_raw_buffer(device, std::max<vk::DeviceSize>(sizes.buildScratchSize, 1), scratch_usage, CG_MEMORY_GPU,
                                        device.capabilities.scratch_alignment);
  retire_raw_buffer(device, scratch);
  auto accel = allocate_accel(device, request.type, sizes.accelerationStructureSize);
  build.dstAccelerationStructure = accel->handle;
  build.scratchData.deviceAddress = scratch.address;
  record_build(cmd, build, request.primitive_count);
  return accel;
}

vk::AccelerationStructureGeometryKHR triangle_geometry(const cg_buffer &vertices, uint32_t vertex_count, uint32_t vertex_stride, const cg_buffer &indices) {
  return {
      .geometryType = vk::GeometryTypeKHR::eTriangles,
      .geometry = {.triangles = {
                       .vertexFormat = vk::Format::eR32G32B32Sfloat,
                       .vertexData = {.deviceAddress = vertices.address},
                       .vertexStride = vertex_stride,
                       .maxVertex = vertex_count == 0 ? 0 : vertex_count - 1,
                       .indexType = vk::IndexType::eUint32,
                       .indexData = {.deviceAddress = indices.address},
                   }},
      .flags = vk::GeometryFlagBitsKHR::eOpaque,
  };
}

vk::AccelerationStructureGeometryKHR instance_geometry(const cg_buffer &instances) {
  return {
      .geometryType = vk::GeometryTypeKHR::eInstances,
      .geometry = {.instances = {.arrayOfPointers = vk::False, .data = {.deviceAddress = instances.address}}},
  };
}

vk::AccelerationStructureInstanceKHR to_vk_instance(const cg_accel_instance &instance, uint32_t index) {
  vk::AccelerationStructureInstanceKHR result{};
  for (size_t row = 0; row < 3; ++row) {
    for (size_t column = 0; column < 4; ++column) result.transform.matrix[row][column] = instance.transform[row * 4 + column];
  }
  result.instanceCustomIndex = index;
  result.mask = instance.mask & 0xffu;
  result.instanceShaderBindingTableRecordOffset = 0;
  result.flags = static_cast<VkGeometryInstanceFlagsKHR>(vk::GeometryInstanceFlagBitsKHR::eTriangleFacingCullDisable);
  result.accelerationStructureReference = instance.geometry->address;
  return result;
}

cg_buffer upload_instances(cg_device &device, const cg_accel_instance *instances, uint32_t count) {
  uint64_t size = sizeof(vk::AccelerationStructureInstanceKHR) * std::max(count, 1u);
  cg_buffer buffer = create_raw_buffer(device, size, instance_usage, CG_MEMORY_UPLOAD, instance_alignment);
  auto *destination = static_cast<vk::AccelerationStructureInstanceKHR *>(buffer.mapped);
  for (uint32_t index = 0; index < count; ++index) destination[index] = to_vk_instance(instances[index], index);
  return buffer;
}

cg_accel *make_geometry(cg_device &device, cg_cmd &cmd, const cg_buffer &vertices, uint32_t vertex_count, uint32_t vertex_stride,
                        const cg_buffer &indices, uint32_t index_count) {
  BuildRequest request{
      .type = vk::AccelerationStructureTypeKHR::eBottomLevel,
      .flags = vk::BuildAccelerationStructureFlagBitsKHR::ePreferFastTrace,
      .geometry = triangle_geometry(vertices, vertex_count, vertex_stride, indices),
      .primitive_count = index_count / 3,
  };
  return build_accel(device, cmd, request).release();
}

cg_accel *make_scene(cg_device &device, cg_cmd &cmd, const cg_accel_instance *instances, uint32_t count) {
  cg_buffer instance_buffer = upload_instances(device, instances, count);
  retire_raw_buffer(device, instance_buffer);
  BuildRequest request{
      .type = vk::AccelerationStructureTypeKHR::eTopLevel,
      .flags = vk::BuildAccelerationStructureFlagBitsKHR::ePreferFastBuild,
      .geometry = instance_geometry(instance_buffer),
      .primitive_count = count,
  };
  std::unique_ptr<cg_accel> scene = build_accel(device, cmd, request);
  try {
    scene->set = create_accel_set(device, scene->handle);
  } catch (...) {
    cg_accel retired = *scene;
    retire(device, [&device, retired] { destroy_accel_now(device, retired); });
    throw;
  }
  return scene.release();
}

}

cg_accel *accel_create_geometry(cg_device *device, cg_cmd *cmd, cg_buffer *vertices, uint32_t vertex_count, uint32_t vertex_stride,
                                cg_buffer *indices, uint32_t index_count) noexcept {
  if (!device->capabilities.ray_tracing) return nullptr;
  try {
    return make_geometry(*device, *cmd, *vertices, vertex_count, vertex_stride, *indices, index_count);
  } catch (const std::exception &error) {
    report_failure("accel_create_geometry", error.what());
    return nullptr;
  }
}

cg_accel *accel_create_scene(cg_device *device, cg_cmd *cmd, const cg_accel_instance *instances, uint32_t count) noexcept {
  if (!device->capabilities.ray_tracing) return nullptr;
  try {
    return make_scene(*device, *cmd, instances, count);
  } catch (const std::exception &error) {
    report_failure("accel_create_scene", error.what());
    return nullptr;
  }
}

void accel_destroy(cg_device *device, cg_accel *accel) noexcept {
  if (accel == nullptr) return;
  cg_accel retired = *accel;
  delete accel;
  retire(*device, [device, retired] { destroy_accel_now(*device, retired); });
}

}
