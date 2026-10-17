#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <string>

#include <SDL3/SDL.h>

#include "renderer.h"

namespace cg {

struct OpenRequest {
  const cg_backend *backend;
  std::string shader_directory;
  std::string title;
  int width;
  int height;
  bool windowed;
};

class RenderWindow {
 public:
  using EventSink = std::function<void(const SDL_Event &)>;

  RenderWindow() = default;
  RenderWindow(const RenderWindow &) = delete;
  RenderWindow &operator=(const RenderWindow &) = delete;
  ~RenderWindow();

  bool open(const OpenRequest &request, EventSink events, Renderer::ErrorReporter errors, std::string &error);
  void close();
  bool submit(Batch batch);
  bool capture(bool generated, CaptureReply reply);
  bool relative_mouse(bool enabled);
  bool resize(uint32_t width, uint32_t height, std::string &error);
  uint64_t frames();
  FrameStats stats();
  SDL_WindowID id() const { return id_; }
  cg_device_info info();

 private:
  bool open_sdl_window(const std::string &title, int width, int height, std::string &error);
  void deliver(const SDL_Event &event);
  void close_locked();

  std::mutex mutex_;
  std::unique_ptr<Renderer> renderer_;
  SDL_Window *sdl_window_ = nullptr;
  SDL_WindowID id_ = 0;
  EventSink events_;
  bool open_ = false;
};

const cg_backend *backend_named(const std::string &name);
std::string key_name(SDL_Scancode scancode);
bool forwarded_event(const SDL_Event &event);

}
