UNAME_S := $(shell uname -s)
PRIV_DIR ?= priv
BUILD_DIR ?= _build/native/$(notdir $(PRIV_DIR))
SLANG_VERSION := 2026.19
SLANGC := tools/slang/bin/slangc

ERTS_INCLUDE_DIR ?= $(shell erl -noshell -eval 'io:format("~s/include", [code:root_dir() ++ "/erts-" ++ erlang:system_info(version)])' -s init stop)
PKG_CONFIG ?= pkg-config
SDL_CFLAGS := $(patsubst -I%,-isystem %,$(shell $(PKG_CONFIG) --cflags sdl3))
SDL_LIBS := $(shell $(PKG_CONFIG) --libs sdl3)
SDL_LIBDIR := $(shell $(PKG_CONFIG) --variable=libdir sdl3)
VULKAN_INCLUDE ?=
VULKAN_FROM_HEADERS := $(if $(VULKAN_INCLUDE),$(if $(wildcard $(VULKAN_INCLUDE)/vulkan/vulkan.hpp),1,),)
VULKAN_FROM_PKG_CONFIG := $(if $(VULKAN_FROM_HEADERS),,$(shell $(PKG_CONFIG) --exists vulkan && echo 1))
VULKAN_AVAILABLE := $(or $(VULKAN_FROM_HEADERS),$(VULKAN_FROM_PKG_CONFIG))

CORE_SOURCES := $(wildcard c_src/core/*.cpp)
HOST_SOURCES := $(wildcard c_src/host/*.cpp)
VULKAN_SOURCES := $(wildcard c_src/vulkan/*.cpp)
METAL_SWIFT := $(wildcard c_src/metal/*.swift)
SHADERS := $(wildcard shaders/*.slang)
SHADER_ENTRIES := $(filter-out shaders/common.slang shaders/shading.slang,$(SHADERS))

CXXFLAGS_BASE := -std=c++20 -fPIC -O2 -Wall -Wextra -I$(ERTS_INCLUDE_DIR) -isystem c_src/third_party $(SDL_CFLAGS)
CFLAGS_BASE := -std=c11 -fPIC -O2 -Wall -Wextra $(SDL_CFLAGS)

ifeq ($(UNAME_S),Darwin)
SDKROOT := $(shell xcrun --sdk macosx --show-sdk-path)
CC := xcrun clang
CXX := xcrun clang++
SWIFTC := xcrun swiftc
WITH_METAL := 1
WITH_VULKAN ?= $(if $(CAULDRON_GPU_VULKAN),$(CAULDRON_GPU_VULKAN),$(VULKAN_AVAILABLE))
else
WITH_METAL :=
WITH_VULKAN := 1
endif

DEFINES := -DCG_WINDOWS
OBJECTS := $(patsubst c_src/core/%.cpp,$(BUILD_DIR)/core/%.o,$(CORE_SOURCES))
LIBS := $(SDL_LIBS)

ifeq ($(WITH_METAL),1)
DEFINES += -DCG_HAVE_METAL
OBJECTS += $(BUILD_DIR)/metal/swift.o $(BUILD_DIR)/metal/backend.o
LIBS += -framework Metal -framework MetalFX -framework QuartzCore -framework Foundation
endif

ifeq ($(WITH_VULKAN),1)
DEFINES += -DCG_HAVE_VULKAN
VULKAN_CFLAGS := $(if $(VULKAN_FROM_HEADERS),-isystem $(VULKAN_INCLUDE),$(patsubst -I%,-isystem %,$(shell $(PKG_CONFIG) --cflags vulkan))) -isystem c_src/vulkan/vma
OBJECTS += $(patsubst c_src/vulkan/%.cpp,$(BUILD_DIR)/vulkan/%.o,$(VULKAN_SOURCES))
LIBS += $(if $(VULKAN_FROM_PKG_CONFIG),$(shell $(PKG_CONFIG) --libs vulkan),)
endif

LIBRARY := $(PRIV_DIR)/cauldron_gpu.so
HOST := $(PRIV_DIR)/cauldron_gpu_host
HOST_OBJECTS := $(filter-out $(BUILD_DIR)/core/nif.o,$(OBJECTS)) $(patsubst c_src/host/%.cpp,$(BUILD_DIR)/host/%.o,$(HOST_SOURCES))

NATIVE_READY := $(if $(CAULDRON_GPU_SKIP),,$(if $(filter 1,$(WITH_VULKAN)),$(if $(VULKAN_AVAILABLE),$(shell $(PKG_CONFIG) --exists sdl3 && echo yes),),$(shell $(PKG_CONFIG) --exists sdl3 && echo yes)))

ifeq ($(NATIVE_READY),yes)
all: $(LIBRARY) $(HOST)
else
all:
	$(if $(CAULDRON_GPU_SKIP),@rm -f $(LIBRARY) $(HOST),)
	@echo "cauldron_gpu: $(if $(CAULDRON_GPU_SKIP),setup chose software drawing,SDL3$(if $(filter 1,$(WITH_VULKAN)), or Vulkan's headers,) not found); the renderer was not built, games draw in software, and mix cauldron_gpu.setup sets it up"
endif

ifeq ($(UNAME_S),Darwin)
$(LIBRARY): $(OBJECTS) | $(PRIV_DIR)
	$(CXX) -dynamiclib -undefined dynamic_lookup -o $@ $(OBJECTS) $(LIBS) -L$(SDKROOT)/usr/lib/swift -L/usr/lib/swift -Wl,-rpath,/usr/lib/swift

$(HOST): $(HOST_OBJECTS) | $(PRIV_DIR)
	$(CXX) -o $@ $(HOST_OBJECTS) $(LIBS) -L$(SDKROOT)/usr/lib/swift -L/usr/lib/swift -Wl,-rpath,/usr/lib/swift
else
$(LIBRARY): $(OBJECTS) | $(PRIV_DIR)
	$(CXX) -shared -o $@ $(OBJECTS) $(LIBS) -Wl,-rpath,$(SDL_LIBDIR)

$(HOST): $(HOST_OBJECTS) | $(PRIV_DIR)
	$(CXX) -pthread -o $@ $(HOST_OBJECTS) $(LIBS) -Wl,-rpath,$(SDL_LIBDIR)
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
	$(CXX) $(CXXFLAGS_BASE) $(DEFINES) $(VULKAN_CFLAGS) -c $< -o $@

$(BUILD_DIR)/metal/swift.o: $(METAL_SWIFT) c_src/gpu.h
	@mkdir -p $(dir $@)
	SDKROOT=$(SDKROOT) $(SWIFTC) -swift-version 5 -O -parse-as-library -wmo -module-name CauldronGPUMetal \
		-import-objc-header c_src/gpu.h -emit-object $(METAL_SWIFT) -o $@

$(BUILD_DIR)/metal/backend.o: c_src/metal/backend.c c_src/gpu.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS_BASE) $(DEFINES) -c $< -o $@

$(PRIV_DIR):
	mkdir -p $(PRIV_DIR)

STATIC_DIR ?= priv/static
STATIC_BUILD := $(STATIC_DIR)/objects
IOS_MINIMUM ?= 18.0
APPLE_SDK ?= iphoneos
APPLE_TARGET ?= arm64-apple-ios$(IOS_MINIMUM)
APPLE_FRAMEWORKS = -framework Metal $(if $(wildcard $(shell xcrun -sdk $(APPLE_SDK) --show-sdk-path 2>/dev/null)/System/Library/Frameworks/MetalFX.framework),-framework MetalFX) -framework QuartzCore -framework Foundation
STATIC_CORE_SOURCES := $(filter-out c_src/core/window.cpp,$(CORE_SOURCES))
IOS_SHADERS := $(patsubst shaders/%.slang,priv/shaders/ios/%.metallib,$(SHADER_ENTRIES))
APPLE_SHADER_SETS := ios_simulator tvos tvos_simulator
APPLE_SHADERS := $(foreach set,$(APPLE_SHADER_SETS),$(patsubst shaders/%.slang,priv/shaders/$(set)/%.metallib,$(SHADER_ENTRIES)))

ifneq ($(filter $(CAULDRON_TARGET),ios tvos macos),)
STATIC_OBJECTS := $(patsubst c_src/core/%.cpp,$(STATIC_BUILD)/core/%.o,$(STATIC_CORE_SOURCES)) \
	$(STATIC_BUILD)/metal/swift.o $(STATIC_BUILD)/metal/backend.o

static: $(STATIC_OBJECTS)
	$(AR) rcs $(STATIC_DIR)/cauldron_gpu.a $(STATIC_OBJECTS)
	echo "$(APPLE_FRAMEWORKS) -lc++" > $(STATIC_DIR)/cauldron_gpu.ldflags

$(STATIC_BUILD)/core/%.o: c_src/core/%.cpp c_src/core/*.h c_src/gpu.h
	@mkdir -p $(dir $@)
	$(CC) -x c++ -std=c++20 $(CFLAGS) -DCG_HAVE_METAL -DSTATIC_ERLANG_NIF_LIBNAME=cauldron_gpu -I$(ERTS_INCLUDE_DIR) -isystem c_src/third_party -c $< -o $@

$(STATIC_BUILD)/metal/backend.o: c_src/metal/backend.c c_src/gpu.h
	@mkdir -p $(dir $@)
	$(CC) -std=c11 $(CFLAGS) -c $< -o $@

$(STATIC_BUILD)/metal/swift.o: $(METAL_SWIFT) c_src/gpu.h
	@mkdir -p $(dir $@)
	xcrun -sdk $(APPLE_SDK) swiftc -target $(APPLE_TARGET) -swift-version 5 -O -parse-as-library -wmo \
		-module-name CauldronGPUMetal -import-objc-header c_src/gpu.h -emit-object $(METAL_SWIFT) -o $@
else ifeq ($(CAULDRON_TARGET),android)
ANDROID_VULKAN_CFLAGS := $(if $(VULKAN_FROM_HEADERS),-isystem $(VULKAN_INCLUDE),$(patsubst -I%,-isystem %,$(shell $(PKG_CONFIG) --cflags vulkan))) -isystem c_src/vulkan/vma
ANDROID_CXXFLAGS := -x c++ -std=c++20 $(CFLAGS) -DCG_HAVE_VULKAN -DSTATIC_ERLANG_NIF_LIBNAME=cauldron_gpu \
	-I$(ERTS_INCLUDE_DIR) -isystem c_src/third_party $(ANDROID_VULKAN_CFLAGS)
STATIC_OBJECTS := $(patsubst c_src/core/%.cpp,$(STATIC_BUILD)/core/%.o,$(STATIC_CORE_SOURCES)) \
	$(patsubst c_src/vulkan/%.cpp,$(STATIC_BUILD)/vulkan/%.o,$(VULKAN_SOURCES))

static: $(STATIC_OBJECTS)
	$(AR) rcs $(STATIC_DIR)/cauldron_gpu.a $(STATIC_OBJECTS)
	echo "-ldl -landroid" > $(STATIC_DIR)/cauldron_gpu.ldflags

$(STATIC_BUILD)/core/%.o: c_src/core/%.cpp c_src/core/*.h c_src/gpu.h
	@mkdir -p $(dir $@)
	$(CC) $(ANDROID_CXXFLAGS) -c $< -o $@

$(STATIC_BUILD)/vulkan/vma.o: c_src/vulkan/vma.cpp
	@mkdir -p $(dir $@)
	$(CC) $(ANDROID_CXXFLAGS) -w -c $< -o $@

$(STATIC_BUILD)/vulkan/%.o: c_src/vulkan/%.cpp c_src/vulkan/*.hpp c_src/gpu.h
	@mkdir -p $(dir $@)
	$(CC) $(ANDROID_CXXFLAGS) -c $< -o $@
else
static:
	@echo "cauldron_gpu: no static build for $(CAULDRON_TARGET); the app runs without the renderer"
endif

shaders-ios: $(IOS_SHADERS) $(APPLE_SHADERS)

priv/shaders/ios/%.metallib: priv/shaders/%.metallib
	@mkdir -p priv/shaders/ios
	xcrun -sdk iphoneos metal -std=metal3.1 -mios-version-min=$(IOS_MINIMUM) -o $@ _build/shaders/$*.metal

priv/shaders/ios_simulator/%.metallib: priv/shaders/%.metallib
	@mkdir -p priv/shaders/ios_simulator
	xcrun -sdk iphonesimulator metal -std=metal3.1 -target air64-apple-ios$(IOS_MINIMUM)-simulator -o $@ _build/shaders/$*.metal

priv/shaders/tvos/%.metallib: priv/shaders/%.metallib
	@mkdir -p priv/shaders/tvos
	xcrun -sdk appletvos metal -std=metal3.1 -mtvos-version-min=$(IOS_MINIMUM) -o $@ _build/shaders/$*.metal

priv/shaders/tvos_simulator/%.metallib: priv/shaders/%.metallib
	@mkdir -p priv/shaders/tvos_simulator
	xcrun -sdk appletvsimulator metal -std=metal3.1 -target air64-apple-tvos$(IOS_MINIMUM)-simulator -o $@ _build/shaders/$*.metal

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

.PHONY: all clean slang shaders shaders-ios static
