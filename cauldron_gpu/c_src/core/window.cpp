#include "window.h"

#include <condition_variable>
#include <mutex>
#include <unordered_map>

namespace cg {

namespace {

enum class ThreadState { NotStarted, Starting, Running, Failed };

std::mutex state_mutex;
std::condition_variable state_changed;
ThreadState state = ThreadState::NotStarted;
std::string start_error;

std::mutex windows_mutex;
std::unordered_map<SDL_WindowID, WindowEvents> windows;

void set_state(ThreadState next, const std::string &error) {
  std::lock_guard lock(state_mutex);
  state = next;
  start_error = error;
  state_changed.notify_all();
}

void dispatch(const SDL_Event &event) {
  SDL_Window *window = SDL_GetWindowFromEvent(&event);
  if (!window) return;
  std::function<void(const SDL_Event &)> deliver;
  {
    std::lock_guard lock(windows_mutex);
    auto found = windows.find(SDL_GetWindowID(window));
    if (found == windows.end()) return;
    deliver = found->second.deliver;
  }
  deliver(event);
}

void *window_thread(void *) {
  SDL_SetHint(SDL_HINT_MAC_BACKGROUND_APP, "0");
  if (!SDL_Init(SDL_INIT_VIDEO)) {
    set_state(ThreadState::Failed, SDL_GetError());
    return nullptr;
  }
  set_state(ThreadState::Running, "");
  for (;;) {
    SDL_Event event;
    if (!SDL_WaitEventTimeout(&event, 20)) continue;
    do dispatch(event);
    while (SDL_PollEvent(&event));
  }
  return nullptr;
}

struct Work {
  const std::function<void()> *work;
};

void SDLCALL run_work(void *data) {
  (*static_cast<Work *>(data)->work)();
}

}

bool start_window_thread(std::string &error) {
  std::unique_lock lock(state_mutex);
  if (state == ThreadState::NotStarted) {
    state = ThreadState::Starting;
    lock.unlock();
    if (!launch_window_thread(window_thread)) set_state(ThreadState::Failed, "could not take the main thread");
    lock.lock();
  }
  state_changed.wait(lock, [] { return state == ThreadState::Running || state == ThreadState::Failed; });
  error = start_error;
  return state == ThreadState::Running;
}

void run_on_window_thread(const std::function<void()> &work) {
  Work wrapped{&work};
  SDL_RunOnMainThread(run_work, &wrapped, true);
}

void register_window(SDL_WindowID id, WindowEvents events) {
  std::lock_guard lock(windows_mutex);
  windows[id] = std::move(events);
}

void unregister_window(SDL_WindowID id) {
  std::lock_guard lock(windows_mutex);
  windows.erase(id);
}

}
