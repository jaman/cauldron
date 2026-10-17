UNAME_S := $(shell uname -s)
PRIV_DIR ?= priv
BUILD_DIR ?= _build/native/$(notdir $(PRIV_DIR))
SLANG_VERSION := 2026.19
SLANGC := tools/slang/bin/slangc

ERTS_INCLUDE_DIR ?= $(shell erl -noshell -eval 'io:format("~s/include", [code:root_dir() ++ "/erts-" ++ erlang:system_info(version)])' -s init stop)
SDL_CFLAGS := $(patsubst -I%,-isystem %,$(shell pkg-config --cflags sdl3))
SDL_LIBS := $(shell pkg-config --libs sdl3)

CORE_SOURCES := $(wildcard c_src/core/*.cpp)
HOST_SOURCES := $(wildcard c_src/host/*.cpp)
VULKAN_SOURCES := $(wildcard c_src/vulkan/*.cpp)
METAL_SWIFT := $(wildcard c_src/metal/*.swift)
SHADERS := $(wildcard shaders/*.slang)
SHADER_ENTRIES := $(filter-out shaders/common.slang shaders/shading.slang,$(SHADERS))

CXXFLAGS_BASE := -std=c++20 -fPIC -O2 -Wall -Wextra -I$(ERTS_INCLUDE_DIR) $(SDL_CFLAGS)
CFLAGS_BASE := -std=c11 -fPIC -O2 -Wall -Wextra $(SDL_CFLAGS)

ifeq ($(UNAME_S),Darwin)
SDKROOT := $(shell xcrun --sdk macosx --show-sdk-path)
CC := xcrun clang
CXX := xcrun clang++
SWIFTC := xcrun swiftc
WITH_METAL := 1
WITH_VULKAN ?= $(if $(CAULDRON_GPU_VULKAN),$(CAULDRON_GPU_VULKAN),$(shell pkg-config --exists vulkan && echo 1))
else
WITH_METAL :=
WITH_VULKAN := 1
endif

DEFINES :=
OBJECTS := $(patsubst c_src/core/%.cpp,$(BUILD_DIR)/core/%.o,$(CORE_SOURCES))
LIBS := $(SDL_LIBS)

ifeq ($(WITH_METAL),1)
DEFINES += -DCG_HAVE_METAL
OBJECTS += $(BUILD_DIR)/metal/swift.o $(BUILD_DIR)/metal/backend.o
LIBS += -framework Metal -framework MetalFX -framework QuartzCore -framework Foundation
endif

ifeq ($(WITH_VULKAN),1)
DEFINES += -DCG_HAVE_VULKAN
VULKAN_CFLAGS := $(patsubst -I%,-isystem %,$(shell pkg-config --cflags vulkan)) -isystem c_src/vulkan/vma
OBJECTS += $(patsubst c_src/vulkan/%.cpp,$(BUILD_DIR)/vulkan/%.o,$(VULKAN_SOURCES))
LIBS += $(shell pkg-config --libs vulkan)
endif

LIBRARY := $(PRIV_DIR)/cauldron_gpu.so
HOST := $(PRIV_DIR)/cauldron_gpu_host
HOST_OBJECTS := $(filter-out $(BUILD_DIR)/core/nif.o,$(OBJECTS)) $(patsubst c_src/host/%.cpp,$(BUILD_DIR)/host/%.o,$(HOST_SOURCES))

NATIVE_READY := $(shell pkg-config --exists sdl3 $(if $(filter 1,$(WITH_VULKAN)),vulkan,) && echo yes)

ifeq ($(NATIVE_READY),yes)
all: $(LIBRARY) $(HOST)
else
all:
	@echo "cauldron_gpu: SDL3$(if $(filter 1,$(WITH_VULKAN)), or Vulkan,) not found by pkg-config; the renderer was not built and CauldronGPU.open/1 reports it"
endif

ifeq ($(UNAME_S),Darwin)
$(LIBRARY): $(OBJECTS) | $(PRIV_DIR)
	$(CXX) -dynamiclib -undefined dynamic_lookup -o $@ $(OBJECTS) $(LIBS) -L$(SDKROOT)/usr/lib/swift -L/usr/lib/swift -Wl,-rpath,/usr/lib/swift

$(HOST): $(HOST_OBJECTS) | $(PRIV_DIR)
	$(CXX) -o $@ $(HOST_OBJECTS) $(LIBS) -L$(SDKROOT)/usr/lib/swift -L/usr/lib/swift -Wl,-rpath,/usr/lib/swift
else
$(LIBRARY): $(OBJECTS) | $(PRIV_DIR)
	$(CXX) -shared -o $@ $(OBJECTS) $(LIBS)

$(HOST): $(HOST_OBJECTS) | $(PRIV_DIR)
	$(CXX) -pthread -o $@ $(HOST_OBJECTS) $(LIBS)
endif

$(BUILD_DIR)/core/%.o: c_src/core/%.cpp c_src/core/*.h c_src/gpu.h
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS_BASE) $(DEFINES) -c $< -o $@

$(BUILD_DIR)/host/%.o: c_src/host/%.cpp c_src/host/*.h c_src/core/*.h c_src/gpu.h
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS_BASE) $(DEFINES) -c $< -o $@

$(BUILD_DIR)/vulkan/vma.o: c_src/vulkan/vma.cpp
	@mkdir -p $(dir $@)
	$(CXX) -std=c++20 -fPIC -O2 -w $(VULKAN_CFLAGS) -c $< -o $@

$(BUILD_DIR)/vulkan/%.o: c_src/vulkan/%.cpp c_src/vulkan/*.hpp c_src/gpu.h
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS_BASE) $(VULKAN_CFLAGS) -c $< -o $@

$(BUILD_DIR)/metal/swift.o: $(METAL_SWIFT) c_src/gpu.h
	@mkdir -p $(dir $@)
	SDKROOT=$(SDKROOT) $(SWIFTC) -swift-version 5 -O -parse-as-library -wmo -module-name CauldronGPUMetal \
		-import-objc-header c_src/gpu.h -emit-object $(METAL_SWIFT) -o $@

$(BUILD_DIR)/metal/backend.o: c_src/metal/backend.c c_src/gpu.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS_BASE) -c $< -o $@

$(PRIV_DIR):
	mkdir -p $(PRIV_DIR)

slang:
	mkdir -p tools
	curl -sL -o tools/slang.tar.gz https://github.com/shader-slang/slang/releases/download/v$(SLANG_VERSION)/slang-$(SLANG_VERSION)-$(shell uname -s | tr A-Z a-z | sed 's/darwin/macos/')-$(shell uname -m | sed 's/arm64/aarch64/').tar.gz
	rm -rf tools/slang && mkdir -p tools/slang && tar -xzf tools/slang.tar.gz -C tools/slang && rm tools/slang.tar.gz

shaders: $(patsubst shaders/%.slang,priv/shaders/%.spv,$(SHADER_ENTRIES)) $(patsubst shaders/%.slang,priv/shaders/%.metallib,$(SHADER_ENTRIES))

priv/shaders/%.spv: shaders/%.slang shaders/common.slang shaders/shading.slang
	@mkdir -p priv/shaders
	$(SLANGC) $< -I shaders -target spirv -fvk-invert-y -fvk-use-entrypoint-name -o $@

priv/shaders/%.metallib: shaders/%.slang shaders/common.slang shaders/shading.slang
	@mkdir -p priv/shaders _build/shaders
	$(SLANGC) $< -I shaders -target metal -o _build/shaders/$*.metal
	if grep -q 'thread RayDesc ' _build/shaders/$*.metal && ! grep -q 'struct RayDesc ' _build/shaders/$*.metal; then \
		awk '/^using namespace metal;/ && !done {print; print "struct RayDesc { float3 Origin; float TMin; float3 Direction; float TMax; };"; done=1; next} 1' \
			_build/shaders/$*.metal > _build/shaders/$*.ray.metal && mv _build/shaders/$*.ray.metal _build/shaders/$*.metal; \
	fi
	xcrun -sdk macosx metal -std=metal3.1 -o $@ _build/shaders/$*.metal

clean:
	rm -rf $(BUILD_DIR) $(LIBRARY) $(HOST)

.PHONY: all clean slang shaders
