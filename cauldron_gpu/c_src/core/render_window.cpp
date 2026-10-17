#include "render_window.h"

#include <algorithm>
#include <atomic>
#include <cctype>

#include "window.h"

namespace cg {

namespace {

float refresh_rate_of(SDL_Window *window) {
  const SDL_DisplayMode *mode = SDL_GetCurrentDisplayMode(SDL_GetDisplayForWindow(window));
  return mode && mode->refresh_rate > 0 ? mode->refresh_rate : 60.0f;
}

std::atomic<SDL_WindowID> next_offscreen_id{1u << 30};

}

RenderWindow::~RenderWindow() { close(); }

bool RenderWindow::open(const OpenRequest &request, EventSink events, Renderer::ErrorReporter errors, std::string &error) {
  if (!start_window_thread(error)) {
    error = "window thread: " + error;
    return false;
  }
  std::lock_guard lock(mutex_);
  events_ = std::move(events);
  renderer_ = std::make_unique<Renderer>(request.backend, request.shader_directory, std::move(errors));
  bool created = false;
  run_on_window_thread([&] { created = renderer_->create_device(error); });
  if (!created || (request.windowed && !open_sdl_window(request.title, request.width, request.height, error))) {
    renderer_.reset();
    return false;
  }
  open_ = true;
  if (request.windowed) {
    register_window(id_, {[this](const SDL_Event &event) { deliver(event); }});
  } else {
    id_ = next_offscreen_id++;
    renderer_->set_offscreen(true);
    renderer_->resize(static_cast<uint32_t>(request.width), static_cast<uint32_t>(request.height));
  }
  if (!renderer_->start(error)) {
    close_locked();
    return false;
  }
  return true;
}

void RenderWindow::close() {
  std::lock_guard lock(mutex_);
  close_locked();
}

void RenderWindow::close_locked() {
  if (!open_) return;
  open_ = false;
  renderer_->stop();
  unregister_window(id_);
  Renderer *renderer = renderer_.get();
  SDL_Window *sdl_window = sdl_window_;
  if (sdl_window)
    run_on_window_thread([&] {
      renderer->backend()->surface_detach(renderer->device());
      SDL_DestroyWindow(sdl_window);
    });
  renderer_.reset();
  sdl_window_ = nullptr;
}

bool RenderWindow::submit(Batch batch) {
  std::lock_guard lock(mutex_);
  if (!open_) {
    batch.release();
    return false;
  }
  renderer_->submit(std::move(batch));
  return true;
}

bool RenderWindow::capture(bool generated, CaptureReply reply) {
  std::lock_guard lock(mutex_);
  if (!open_) return false;
  renderer_->request_capture(generated, std::move(reply));
  return true;
}

bool RenderWindow::relative_mouse(bool enabled) {
  std::lock_guard lock(mutex_);
  if (!open_) return false;
  SDL_Window *sdl_window = sdl_window_;
  run_on_window_thread([&] { SDL_SetWindowRelativeMouseMode(sdl_window, enabled); });
  return true;
}

bool RenderWindow::resize(uint32_t width, uint32_t height, std::string &error) {
  std::lock_guard lock(mutex_);
  if (!open_) {
    error = "closed";
    return false;
  }
  if (sdl_window_) {
    error = "a window's size follows the window";
    return false;
  }
  renderer_->resize(width, height);
  return true;
}

FrameStats RenderWindow::stats() {
  std::lock_guard lock(mutex_);
  return open_ ? renderer_->stats() : FrameStats{};
}

uint64_t RenderWindow::frames() {
  std::lock_guard lock(mutex_);
  return open_ ? renderer_->frames_drawn() : 0;
}

cg_device_info RenderWindow::info() {
  std::lock_guard lock(mutex_);
  return renderer_ ? renderer_->info() : cg_device_info{};
}

bool RenderWindow::open_sdl_window(const std::string &title, int width, int height, std::string &error) {
  Renderer *renderer = renderer_.get();
  bool attached = false;
  run_on_window_thread([&] {
    SDL_WindowFlags flags = SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY | renderer->backend()->window_flags;
    sdl_window_ = SDL_CreateWindow(title.c_str(), width, height, flags);
    if (!sdl_window_) {
      error = SDL_GetError();
      return;
    }
    attached = renderer->backend()->surface_attach(renderer->device(), sdl_window_);
    if (!attached) {
      error = "surface creation failed";
      SDL_DestroyWindow(sdl_window_);
      sdl_window_ = nullptr;
      return;
    }
    id_ = SDL_GetWindowID(sdl_window_);
    int pixel_width = 0, pixel_height = 0;
    SDL_GetWindowSizeInPixels(sdl_window_, &pixel_width, &pixel_height);
    renderer->resize(static_cast<uint32_t>(pixel_width), static_cast<uint32_t>(pixel_height));
    renderer->set_refresh_rate(refresh_rate_of(sdl_window_));
    SDL_RaiseWindow(sdl_window_);
  });
  return attached;
}

void RenderWindow::deliver(const SDL_Event &event) {
  if (event.type == SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED && renderer_)
    renderer_->resize(static_cast<uint32_t>(event.window.data1), static_cast<uint32_t>(event.window.data2));
  if (event.type == SDL_EVENT_WINDOW_DISPLAY_CHANGED && renderer_ && sdl_window_) renderer_->set_refresh_rate(refresh_rate_of(sdl_window_));
  if (forwarded_event(event)) events_(event);
}

const cg_backend *backend_named(const std::string &name) {
#if defined(CG_HAVE_METAL)
  if (name == "metal") return cg_metal_backend();
#endif
#if defined(CG_HAVE_VULKAN)
  if (name == "vulkan") return cg_vulkan_backend();
#endif
  return nullptr;
}

std::string key_name(SDL_Scancode scancode) {
  std::string name = SDL_GetScancodeName(scancode);
  std::transform(name.begin(), name.end(), name.begin(), [](unsigned char c) { return c == ' ' ? '_' : std::tolower(c); });
  return name;
}

bool forwarded_event(const SDL_Event &event) {
  switch (event.type) {
    case SDL_EVENT_KEY_DOWN:
    case SDL_EVENT_KEY_UP:
    case SDL_EVENT_MOUSE_MOTION:
    case SDL_EVENT_MOUSE_BUTTON_DOWN:
    case SDL_EVENT_MOUSE_BUTTON_UP:
    case SDL_EVENT_MOUSE_WHEEL:
    case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
    case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
    case SDL_EVENT_WINDOW_FOCUS_GAINED:
    case SDL_EVENT_WINDOW_FOCUS_LOST:
      return true;
    default:
      return false;
  }
}

}
