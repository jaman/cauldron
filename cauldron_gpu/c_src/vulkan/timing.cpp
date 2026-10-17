#include "internal.hpp"

namespace cgvk {
namespace {

constexpr uint32_t timestamps_per_frame = 2;
constexpr double nanoseconds_per_second = 1e9;

bool timed(const cg_device &device) {
  return device.capabilities.timestamp_mask != 0;
}

uint64_t mask_for_bits(uint32_t valid_bits) {
  return valid_bits >= 64 ? ~uint64_t{0} : (uint64_t{1} << valid_bits) - 1;
}

}

void probe_timestamps(cg_device &device) {
  uint32_t valid_bits = device.physical.getQueueFamilyProperties()[device.queue_family].timestampValidBits;
  float period = device.properties.limits.timestampPeriod;
  bool usable = valid_bits != 0 && period > 0.0f;
  device.capabilities.timestamp_mask = usable ? mask_for_bits(valid_bits) : 0;
  device.capabilities.timestamp_period = period;
}

void create_frame_timer(cg_device &device, FrameSlot &slot) {
  if (!timed(device)) return;
  slot.timestamps = device.device.createQueryPool({.queryType = vk::QueryType::eTimestamp, .queryCount = timestamps_per_frame});
}

void destroy_frame_timer(cg_device &device, FrameSlot &slot) {
  device.device.destroyQueryPool(slot.timestamps);
}

void record_frame_start(cg_device &device, FrameSlot &slot) {
  if (!timed(device)) return;
  slot.cmd.commands.resetQueryPool(slot.timestamps, 0, timestamps_per_frame);
  slot.cmd.commands.writeTimestamp2(vk::PipelineStageFlagBits2::eTopOfPipe, slot.timestamps, 0);
}

void record_frame_finish(cg_device &device, FrameSlot &slot, vk::CommandBuffer commands) {
  if (!timed(device)) return;
  commands.writeTimestamp2(vk::PipelineStageFlagBits2::eBottomOfPipe, slot.timestamps, 1);
  slot.timed = true;
}

void read_frame_time(cg_device &device, FrameSlot &slot) {
  if (!slot.timed) return;
  slot.timed = false;
  std::array<uint64_t, timestamps_per_frame> ticks{};
  vk::Result result = device.device.getQueryPoolResults(slot.timestamps, 0, timestamps_per_frame, sizeof(ticks), ticks.data(),
                                                         sizeof(uint64_t), vk::QueryResultFlagBits::e64);
  if (result != vk::Result::eSuccess) return;
  uint64_t elapsed = (ticks[1] - ticks[0]) & device.capabilities.timestamp_mask;
  device.last_gpu_seconds = static_cast<float>(static_cast<double>(elapsed) * device.capabilities.timestamp_period / nanoseconds_per_second);
}

float frame_gpu_seconds(cg_device *device) noexcept {
  return device->last_gpu_seconds;
}

}
