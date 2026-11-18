# Testing `cauldron_gpu` on Windows

This folder builds `cauldron_gpu`'s Vulkan renderer on a Windows machine and draws one
frame with it — no window, no display, nothing to install on the Elixir side beyond the
two SDKs below. It is a test kit, not a package: nothing here is published.

## What you need

| Thing | Why | Where |
| --- | --- | --- |
| Erlang/OTP 29 and Elixir 1.18+ | build and run the project | `winget install Erlang.Erlang`, `winget install Elixir.Elixir` |
| Visual Studio 2022 Build Tools, "Desktop development with C++" | `cl.exe` and `nmake.exe` build the renderer | <https://visualstudio.microsoft.com/visual-cpp-build-tools/> |
| LunarG Vulkan SDK | headers, loader and `vulkan-1.lib`; sets `VULKAN_SDK` | <https://vulkan.lunarg.com/> |
| SDL3 development libraries for MSVC | windowing and input for the host | `SDL3-devel-*-VC.zip` from <https://github.com/libsdl-org/SDL/releases> |

Unzip SDL3 somewhere and set `SDL3_DIR` to the extracted folder (the one holding
`include\SDL3\SDL.h`). The Vulkan SDK installer sets `VULKAN_SDK` itself.

`run.ps1` accepts the SDKs from the environment, and otherwise looks in `C:\VulkanSDK`
and `C:\SDL3*` for them.

## Layout

The kit expects the packages beside it:

```
cauldron/
├── windows/            this folder
├── cauldron_gpu/       the renderer
└── cauldron_3d_scene/  the scene it draws
```

`windows/kit/` is a two-line Mix project that depends on `cauldron_gpu` by path. It
deliberately has no other dependencies, so the build does not drag in the 2D engine or
the mobile hosts; `run.ps1` builds it with `MIX_ENV=prod` for the same reason. Only
`elixir_make` comes from Hex, so the machine needs network access once.

## Run it

Open **x64 Native Tools Command Prompt for VS 2022** (Start menu → Visual Studio 2022),
`cd` to the `cauldron` folder, and run:

```powershell
powershell -ExecutionPolicy Bypass -File windows\run.ps1
```

The script checks the tools, fetches `elixir_make`, builds the renderer and draws the
frame. On success it prints the device and leaves the picture in
`windows\kit\gpu-smoke.png`:

```
backends: vulkan
device:   NVIDIA GeForce RTX 4070
backend:  vulkan
frame:    320x200, 256000 bytes, sha256 1f0c...
picture:  C:\work\cauldron\windows\kit\gpu-smoke.png
```

The picture is a red cube over a horizon: the same scene the macOS and Linux runs draw.

## When it does not work

| Exit | Means | Fix |
| --- | --- | --- |
| 0 | the card drew a frame | — |
| 1 | the renderer opened, the frame did not arrive | run `vulkaninfo --summary`, check the renderer's message |
| 2 | no renderer was built — `cauldron_gpu` fell back to software | `VULKAN_SDK`/`SDL3_DIR` were not set when `mix` compiled; set them, then `cd windows\kit; mix clean; mix run smoke.exs` |

`nmake` prints `SKIP_REASON` when it decides not to build the renderer; the reason is one
of "Vulkan's headers or SDL3 were not found", "VULKAN_INCLUDE or SDL3_DIR does not hold
the headers", or "setup chose software drawing". `mix cauldron_gpu.setup --check`, run
inside `cauldron_gpu/` after `mix deps.get`, reports the same findings and where it looked.

## A window instead of a headless frame

The headless test is the quick check. To watch it draw, open a window and pump events:

```elixir
{:ok, gpu} = CauldronGPU.open(title: "cauldron", width: 800, height: 500)
# ... the same mesh, material, instance, light and camera as smoke.exs ...

receive do
  {:cauldron_gpu, _id, :close_requested} -> CauldronGPU.close(gpu)
  {:cauldron_gpu, _id, {:error, message}} -> IO.puts(message)
end
```

Window events arrive at the process that called `open/1` unless `:events` names another.
