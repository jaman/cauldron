#include <condition_variable>
#include <cstdlib>
#include <mutex>
#include <thread>

#include "../core/window.h"
#include "channel.h"
#include "session.h"

namespace {

std::mutex loop_mutex;
std::condition_variable loop_requested;
void *(*window_loop)(void *) = nullptr;

void serve(cg::host::Channel &channel) {
  cg::host::Session session(channel);
  std::vector<uint8_t> packet;
  while (channel.receive(packet) && session.handle(std::move(packet))) packet = {};
  session.close();
}

}

namespace cg {

bool launch_window_thread(void *(*loop)(void *)) {
  {
    std::lock_guard lock(loop_mutex);
    window_loop = loop;
  }
  loop_requested.notify_all();
  return true;
}

}

int main() {
  static cg::host::Channel channel;
  std::thread([] {
    serve(channel);
    std::_Exit(0);
  }).detach();
  std::unique_lock lock(loop_mutex);
  loop_requested.wait(lock, [] { return window_loop != nullptr; });
  void *(*loop)(void *) = window_loop;
  lock.unlock();
  loop(nullptr);
  return 0;
}
