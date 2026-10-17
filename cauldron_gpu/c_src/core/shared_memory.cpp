#include "shared_memory.h"

#if defined(_WIN32)

namespace cg {

bool write_shared_memory(const std::string &, const uint8_t *, size_t, std::string &error) {
  error = "shared memory is not available on this system";
  return false;
}

void remove_shared_memory(const std::string &) {}

}

#else

#include <cerrno>
#include <cstring>

#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

namespace cg {

bool write_shared_memory(const std::string &name, const uint8_t *data, size_t size, std::string &error) {
  shm_unlink(name.c_str());
  int descriptor = shm_open(name.c_str(), O_CREAT | O_EXCL | O_RDWR, 0600);
  if (descriptor < 0) {
    error = std::string("shm_open: ") + std::strerror(errno);
    return false;
  }
  if (ftruncate(descriptor, static_cast<off_t>(size)) != 0) {
    error = std::string("ftruncate: ") + std::strerror(errno);
    close(descriptor);
    shm_unlink(name.c_str());
    return false;
  }
  void *mapped = mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0);
  close(descriptor);
  if (mapped == MAP_FAILED) {
    error = std::string("mmap: ") + std::strerror(errno);
    shm_unlink(name.c_str());
    return false;
  }
  std::memcpy(mapped, data, size);
  munmap(mapped, size);
  return true;
}

void remove_shared_memory(const std::string &name) { shm_unlink(name.c_str()); }

}

#endif
