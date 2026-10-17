#include "internal.hpp"

namespace cgvk {

cg_upscaler *upscaler_create(cg_device *, const cg_upscaler_desc *) noexcept {
  return nullptr;
}

void upscaler_destroy(cg_device *, cg_upscaler *) noexcept {}

void cmd_upscale(cg_cmd *, cg_upscaler *, const cg_upscale *) noexcept {}

cg_interpolator *interpolator_create(cg_device *, const cg_upscaler_desc *) noexcept {
  return nullptr;
}

void interpolator_destroy(cg_device *, cg_interpolator *) noexcept {}

void cmd_interpolate(cg_cmd *, cg_interpolator *, const cg_interpolate *) noexcept {}

}
