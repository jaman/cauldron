#pragma once

#include <cstdint>
#include <functional>
#include <string>

#if defined(CG_WINDOWS)
#include <SDL3/SDL.h>
#else
typedef union SDL_Event SDL_Event;
typedef struct SDL_Window SDL_Window;
#endif

namespace cg {

using ViewId = uint32_t;

struct WindowEvents {
  std::function<void(const SDL_Event &)> deliver;
};

#if defined(CG_WINDOWS)

bool launch_window_thread(void *(*loop)(void *));
bool start_window_thread(std::string &error);
void run_on_window_thread(const std::function<void()> &work);
void register_window(ViewId id, WindowEvents events);
void unregister_window(ViewId id);

#else

inline bool start_window_thread(std::string &) { return true; }
inline void run_on_window_thread(const std::function<void()> &work) { work(); }
inline void register_window(ViewId, WindowEvents) {}
inline void unregister_window(ViewId) {}

#endif

}
