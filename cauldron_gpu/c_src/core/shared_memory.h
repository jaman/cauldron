#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

namespace cg {

bool write_shared_memory(const std::string &name, const uint8_t *data, size_t size, std::string &error);
void remove_shared_memory(const std::string &name);

}
