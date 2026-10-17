#pragma once

#include <cstdint>
#include <functional>
#include <string>

#include <SDL3/SDL.h>

namespace cg {

struct WindowEvents {
  std::function<void(const SDL_Event &)> deliver;
};

bool launch_window_thread(void *(*loop)(void *));
bool start_window_thread(std::string &error);
void run_on_window_thread(const std::function<void()> &work);
void register_window(SDL_WindowID id, WindowEvents events);
void unregister_window(SDL_WindowID id);

}
