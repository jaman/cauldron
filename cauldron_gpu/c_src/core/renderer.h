#pragma once

#include <atomic>
#include <condition_variable>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

#include "../gpu.h"
#include "deformer.h"
#include "frame_arena.h"
#include "passes.h"
#include "resources.h"
#include "scene.h"

namespace cg {

struct Capture {
  uint32_t width;
  uint32_t height;
  const uint8_t *pixels;
};

using CaptureReply = std::function<void(const Capture *)>;

struct FrameStats {
  uint64_t frames;
  float gpu_seconds;
  float cpu_seconds;
  float refresh_rate;
  bool generating;
};

struct CaptureRequest {
  bool generated;
  CaptureReply reply;
};

struct PendingCapture {
  cg_buffer *readback;
  uint32_t width;
  uint32_t height;
  uint64_t frame;
  bool swap_red_blue;
  std::vector<CaptureReply> replies;
};

struct Batch {
  const uint8_t *data;
  size_t size;
  double arrival;
  std::function<void()> release;
};

class Renderer {
 public:
  using ErrorReporter = std::function<void(const std::string &)>;

  Renderer(const cg_backend *backend, std::string shader_directory, ErrorReporter report_error);
  ~Renderer();

  bool create_device(std::string &error);
  const cg_backend *backend() const { return backend_; }
  cg_device *device() const { return device_; }
  cg_device_info info() const;

  bool start(std::string &error);
  void stop();
  void submit(Batch batch);
  void resize(uint32_t width, uint32_t height);
  void request_capture(bool generated, CaptureReply reply);
  void set_offscreen(bool offscreen) { offscreen_ = offscreen; }
  void set_refresh_rate(float hertz) { refresh_rate_ = hertz; }
  FrameStats stats() const;
  uint64_t frames_drawn() const { return frames_drawn_.load(); }

 private:
  void run();
  bool has_work();
  bool draw_frame();
  void take_batches();
  std::vector<CaptureRequest> take_capture_requests();
  void start_capture(cg_cmd *cmd, const FrameInputs &inputs, std::vector<CaptureRequest> requests);
  void start_generated_capture(cg_cmd *cmd, std::vector<CaptureReply> replies);
  void end_frame(cg_cmd *cmd, const FrameInputs &inputs);
  void finish_captures(bool everything);
  void build_frame(cg_cmd *cmd, FrameArena &arena, FrameInputs &inputs, double now);
  void build_flat_frame(FrameArena &arena, FrameInputs &inputs);
  bool build_layers(FrameArena &arena, FrameInputs &inputs);
  void build_sprites(FrameArena &arena, const Layer &layer, LayerDraw &draw);
  void build_columns(FrameArena &arena, const Layer &layer, LayerDraw &draw, GpuLayer &gpu);
  size_t layer_bytes() const;
  void write_materials(FrameArena &arena, FrameInputs &inputs, std::unordered_map<uint32_t, uint32_t> &slots);
  void write_sky(GpuFrame &frame, const Environment &environment, double now);
  void write_lights(FrameArena &arena, FrameInputs &inputs, std::vector<GpuLight> &lights, bool &sun_shadows, Vec3 &sun_direction);

  const cg_backend *backend_;
  std::string shader_directory_;
  ErrorReporter report_error_;
  cg_device *device_ = nullptr;
  std::unique_ptr<Resources> resources_;
  std::unique_ptr<Passes> passes_;
  std::unique_ptr<Deformer> deformer_;
  FrameArena arenas_[3];
  uint64_t frame_index_ = 0;
  Scene scene_;
  Changes changes_;

  std::mutex mutex_;
  std::condition_variable wake_;
  std::deque<Batch> batches_;
  std::vector<CaptureRequest> capture_requests_;
  std::vector<PendingCapture> captures_;
  std::thread thread_;
  std::atomic<bool> running_{false};
  std::atomic<uint32_t> pending_width_{0};
  std::atomic<uint32_t> pending_height_{0};
  std::atomic<bool> resized_{false};
  bool offscreen_ = false;
  bool upscaling_ = false;
  bool frame_generation_ = false;
  std::atomic<bool> generating_{false};
  std::atomic<float> refresh_rate_{60.0f};
  std::atomic<float> gpu_seconds_{0.0f};
  std::atomic<float> cpu_seconds_{0.0f};
  bool should_generate(bool requested);
  void record_interval(double started);
  float interval_without_ = 0;
  float interval_with_ = 0;
  double switched_at_ = 0;
  double last_frame_started_ = 0;
  bool has_opaque_part(const Instance &instance, const GpuMesh &mesh) const;
  bool has_previous_ = false;
  bool has_previous_eye_ = false;
  Vec3 previous_eye_;
  double last_frame_time_ = 0;
  double clock_origin_ = 0;
  Mat4 previous_view_proj_;
  std::pair<uint32_t, uint32_t> previous_size_;
  std::unordered_map<uint32_t, Mat4> previous_models_;
  std::atomic<uint64_t> frames_drawn_{0};
};

double now_seconds();

}
