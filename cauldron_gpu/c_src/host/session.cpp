#include "session.h"

#include <cerrno>
#include <cstring>

#if !defined(_WIN32)
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

#include "../core/shared_memory.h"

namespace cg::host {

namespace {

enum RequestOp : uint8_t {
  RequestOpen = 1,
  RequestSubmit = 2,
  RequestSubmitShared = 3,
  RequestCapture = 4,
  RequestResize = 5,
  RequestRelativeMouse = 6,
  RequestFrames = 7,
  RequestClose = 8
};

struct Mapping {
  const uint8_t *data = nullptr;
  size_t size = 0;
};

#if defined(_WIN32)

bool map_shared_memory(const std::string &name, size_t, Mapping &, std::string &error) {
  error = "shared memory " + name + " is not available on this system";
  return false;
}

void unmap(const Mapping &) {}

#else

void unmap(const Mapping &mapping) { munmap(const_cast<uint8_t *>(mapping.data), mapping.size); }

bool map_shared_memory(const std::string &name, size_t size, Mapping &mapping, std::string &error) {
  int descriptor = shm_open(name.c_str(), O_RDONLY, 0);
  shm_unlink(name.c_str());
  if (descriptor < 0) {
    error = "shm_open " + name + ": " + std::strerror(errno);
    return false;
  }
  struct stat status {};
  if (fstat(descriptor, &status) != 0 || size == 0 || static_cast<size_t>(status.st_size) < size) {
    close(descriptor);
    error = "shared memory " + name + " is smaller than the batch";
    return false;
  }
  void *mapped = mmap(nullptr, size, PROT_READ, MAP_SHARED, descriptor, 0);
  close(descriptor);
  if (mapped == MAP_FAILED) {
    error = std::string("mmap: ") + std::strerror(errno);
    return false;
  }
  mapping = {static_cast<const uint8_t *>(mapped), size};
  return true;
}

#endif

void event_term(Term &term, const SDL_Event &event) {
  switch (event.type) {
    case SDL_EVENT_KEY_DOWN:
    case SDL_EVENT_KEY_UP: {
      term.tuple(4).atom("key").atom(event.type == SDL_EVENT_KEY_DOWN ? "down" : "up");
      std::string name = key_name(event.key.scancode);
      if (name.empty())
        term.integer(event.key.scancode);
      else
        term.atom(name);
      term.boolean(event.key.repeat);
      return;
    }
    case SDL_EVENT_MOUSE_MOTION:
      term.tuple(5).atom("mouse_motion").number(event.motion.x).number(event.motion.y).number(event.motion.xrel).number(event.motion.yrel);
      return;
    case SDL_EVENT_MOUSE_BUTTON_DOWN:
    case SDL_EVENT_MOUSE_BUTTON_UP:
      term.tuple(5)
          .atom("mouse_button")
          .atom(event.type == SDL_EVENT_MOUSE_BUTTON_DOWN ? "down" : "up")
          .integer(event.button.button)
          .number(event.button.x)
          .number(event.button.y);
      return;
    case SDL_EVENT_MOUSE_WHEEL:
      term.tuple(3).atom("mouse_wheel").number(event.wheel.x).number(event.wheel.y);
      return;
    case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
      term.tuple(3).atom("resized").integer(event.window.data1).integer(event.window.data2);
      return;
    case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
      term.atom("close_requested");
      return;
    default:
      term.tuple(2).atom("focus").boolean(event.type == SDL_EVENT_WINDOW_FOCUS_GAINED);
      return;
  }
}

void info_term(Term &term, const cg_device_info &info) {
  term.map(7);
  term.atom("backend").atom(info.backend);
  term.atom("device").binary(info.name, strnlen(info.name, sizeof(info.name)));
  term.atom("ray_tracing").boolean(info.ray_tracing);
  term.atom("mesh_shaders").boolean(info.mesh_shaders);
  term.atom("unified_memory").boolean(info.unified_memory);
  term.atom("upscaling").boolean(info.upscaling);
  term.atom("frame_generation").boolean(info.frame_generation);
}

void capture_term(Term &term, const Capture *capture, const std::string &shared_memory) {
  if (!capture || !capture->pixels) {
    term.tuple(2).atom("capture").atom("error");
    return;
  }
  size_t size = size_t(capture->width) * capture->height * 4;
  if (shared_memory.empty()) {
    term.tuple(4).atom("capture").integer(capture->width).integer(capture->height).binary(capture->pixels, size);
    return;
  }
  std::string error;
  if (!write_shared_memory(shared_memory, capture->pixels, size, error)) {
    term.tuple(2).atom("capture").tuple(2).atom("error").binary(error);
    return;
  }
  term.tuple(4).atom("capture").integer(capture->width).integer(capture->height).tuple(2).atom("shared_memory").binary(shared_memory);
}

Term reply_header(uint32_t tag) {
  Term term;
  term.tuple(3).atom("reply").integer(tag);
  return term;
}

}

std::string Request::text(size_t size) {
  if (failed_ || size > bytes_.size() - at_) {
    failed_ = true;
    return {};
  }
  std::string result(reinterpret_cast<const char *>(bytes_.data() + at_), size);
  at_ += size;
  return result;
}

uint64_t Request::big_endian(size_t width) {
  if (failed_ || width > bytes_.size() - at_) {
    failed_ = true;
    return 0;
  }
  uint64_t value = 0;
  for (size_t index = 0; index < width; ++index) value = (value << 8) | bytes_[at_ + index];
  at_ += width;
  return value;
}

bool Session::handle(std::vector<uint8_t> packet) {
  Request request(packet);
  switch (request.u8()) {
    case RequestOpen:
      open(request);
      return true;
    case RequestSubmit:
      submit_inline(std::move(packet));
      return true;
    case RequestSubmitShared:
      submit_shared(request);
      return true;
    case RequestCapture:
      capture(request);
      return true;
    case RequestResize:
      resize(request);
      return true;
    case RequestRelativeMouse:
      relative_mouse(request);
      return true;
    case RequestFrames:
      frames(request);
      return true;
    case RequestClose:
      return false;
    default:
      send_error("unknown host request");
      return true;
  }
}

void Session::close() {
  if (window_) window_->close();
}

void Session::open(Request &request) {
  bool windowed = request.u8() != 0;
  int width = static_cast<int>(request.u32());
  int height = static_cast<int>(request.u32());
  std::string backend_name = request.text(request.u8());
  std::string title = request.text(request.u32());
  std::string shader_directory = request.text(request.u32());
  Term reply;
  const cg_backend *backend = backend_named(backend_name);
  std::string error;
  if (request.failed() || width <= 0 || height <= 0)
    error = "malformed open request";
  else if (window_)
    error = "already open";
  else if (!backend)
    error = "backend not built: " + backend_name;
  if (error.empty()) {
    window_ = std::make_unique<RenderWindow>();
    OpenRequest open_request{backend, shader_directory, title, width, height, windowed};
    if (!window_->open(open_request, [this](const SDL_Event &event) { send_event(event); },
                       [this](const std::string &message) { send_error(message); }, error))
      window_.reset();
  }
  if (!window_) {
    reply.tuple(2).atom("open_failed").binary(error);
  } else {
    reply.tuple(3).atom("opened").integer(window_->id());
    info_term(reply, window_->info());
  }
  channel_.send(reply);
}

void Session::submit_inline(std::vector<uint8_t> packet) {
  if (!window_) return;
  auto *owned = new std::vector<uint8_t>(std::move(packet));
  window_->submit({owned->data() + 1, owned->size() - 1, now_seconds(), [owned] { delete owned; }});
}

void Session::submit_shared(Request &request) {
  uint64_t size = request.u64();
  std::string name = request.rest();
  Mapping mapping;
  std::string error;
  bool mapped = !request.failed() && map_shared_memory(name, size, mapping, error);
  Term released;
  released.tuple(2).atom("released").binary(name);
  channel_.send(released);
  if (!mapped) {
    send_error(error.empty() ? "malformed shared submit" : error);
    return;
  }
  if (!window_) {
    unmap(mapping);
    return;
  }
  window_->submit({mapping.data, mapping.size, now_seconds(), [mapping] { unmap(mapping); }});
}

void Session::capture(Request &request) {
  uint32_t tag = request.u32();
  bool generated = request.u8() != 0;
  std::string shared_memory = request.rest();
  Channel &channel = channel_;
  auto reply = [&channel, tag, shared_memory](const Capture *picture) {
    Term term = reply_header(tag);
    capture_term(term, picture, shared_memory);
    channel.send(term);
  };
  if (!window_ || !window_->capture(generated, reply)) reply_closed(tag);
}

void Session::resize(Request &request) {
  uint32_t tag = request.u32();
  uint32_t width = request.u32();
  uint32_t height = request.u32();
  std::string error = "closed";
  if (width == 0 || height == 0) error = "the size must be positive";
  if (!window_ || width == 0 || height == 0 || !window_->resize(width, height, error)) {
    Term term = reply_header(tag);
    term.tuple(2).atom("error").binary(error);
    channel_.send(term);
    return;
  }
  channel_.send(reply_header(tag).atom("ok"));
}

void Session::relative_mouse(Request &request) {
  uint32_t tag = request.u32();
  bool enabled = request.u8() != 0;
  if (!window_ || !window_->relative_mouse(enabled)) return reply_closed(tag);
  channel_.send(reply_header(tag).atom("ok"));
}

void Session::frames(Request &request) {
  uint32_t tag = request.u32();
  Term term = reply_header(tag);
  term.integer(static_cast<int64_t>(window_ ? window_->frames() : 0));
  channel_.send(term);
}

void Session::send_event(const SDL_Event &event) {
  Term term;
  term.tuple(2).atom("event");
  event_term(term, event);
  channel_.send(term);
}

void Session::send_error(const std::string &message) {
  Term term;
  term.tuple(2).atom("event").tuple(2).atom("error").binary(message);
  channel_.send(term);
}

void Session::reply_closed(uint32_t tag) {
  Term term = reply_header(tag);
  term.tuple(2).atom("error").binary("closed");
  channel_.send(term);
}

}
