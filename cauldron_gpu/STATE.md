# State

`cauldron_gpu` draws 3D scenes and 2D layers on the machine's graphics card: Metal on Macs, Vulkan on
NVIDIA and AMD under Linux and Windows. Elixir describes the scene; native code draws it.

This file is the record of the work. Read it at the start of a session and update it as
work lands. It holds three things:

- **Decisions** — what was settled, why, and what it rules out. A decision here is not
  reopened unless something it depended on turns out to be false; if that happens,
  record what was found and the new decision next to the old one, never silently edit it.
- **Open questions and checks** — things that must be answered or verified before the
  work that depends on them starts.
- **Work** — the build order as checklists. Each finished item says what was built and
  where, briefly, so the next session can pick up without re-reading the code.

Reasons for code go here, not in code comments.

## Decisions

**D1. Our own graphics layer with two backends, Metal and Vulkan.** (2026-10-16)
Rejected: wgpu, and Vulkan on Macs through MoltenVK. Reason: the goal is the newest GPU
features, and those two choices close off hardware ray tracing on Macs, MetalFX upscaling
and frame interpolation, DLSS and DLSS frame generation, FSR frame generation. Cost
accepted: two backends behind one set of render passes.
Rules out: a WebGPU or browser target from this package, and DX12-only features on Windows
(Vulkan reaches the same hardware there).

**D2. Elixir describes the scene; native code owns the frame.** (2026-10-16)
Elixir keeps the world (entities, transforms, materials, lights, camera) and sends changes.
A native render thread draws at display rate from its own copy of the scene, applying the
newest changes at the start of each frame. Elixir never issues draw calls. A slow BEAM tick
never causes a missed frame: the renderer redraws or interpolates from the last state.
GPU objects (meshes, textures, materials) are NIF resources; when Elixir drops the last
reference the GPU memory is freed.

**D3. One renderer, two hostings.** (2026-10-16)
Games load it as a NIF inside the VM (changes passed as binaries without copying). Editors
(an Elixir "Blender") run the same renderer as a separate OS process: changes over a socket,
bulk data (meshes, textures) through shared memory; a crash restarts the process and the
scene is sent again. The change stream is the only interface between Elixir and the
renderer, so both hostings share every line of renderer code. Games come first; the
out-of-process host is built after the renderer works in the VM.
Accepted: a crash in the NIF takes the VM down, the same as a crash in a native game.

**D4. Nx is not the renderer.** (2026-10-16)
Nx reaches tensor math on the GPU, not the rasterizer, ray-tracing hardware, swapchains
or frame pacing. It may sit beside the renderer for physics, animation or denoising.

**D5. Location: `tui/cauldron/cauldron_gpu`, a cauldron package.** (2026-10-16)

**D6. Metal backend in Swift.** (2026-10-16)
Apple's new APIs (Metal 4, MetalFX frame interpolation) and sample code arrive in Swift
first; metal-cpp trails. `erl_nif.h` is a C header, so the NIF entry point is a small C
file calling Swift functions exported with `@_cdecl`.

**D7. Vulkan backend in C++.** (2026-10-16)
Vulkan-Hpp (Khronos's official C++ bindings), VMA (the GPU memory allocator) and NVIDIA
Streamline (DLSS) are C++; FidelityFX (FSR) has a C API C++ calls directly. Plain C would
still need C++ files for Streamline and VMA.

**D8. No Zig in the code.** (2026-10-16)
Zig is before 1.0 and each release breaks the standard library and build API. Builds use
`Makefile` / `Makefile.win` as `cauldron_3d` does. `zig cc` for cross-compiling is
reconsidered only if those makefiles cannot produce a build we need.

**D9. The change stream works for any renderer.** (2026-10-16)
The stream carries scene-level facts only: meshes, materials, lights, camera, requested
effects. Nothing Metal- or Vulkan-specific (no pipeline states, no shader names).
Materials use glTF's PBR metallic-roughness model. Effects are requests; each renderer
reports what it can do and falls back (ray-traced shadows requested → shadow maps where
there is no ray-tracing hardware). This lets a browser client draw the same stream; D1's
"no browser target" applies to this package, not to cauldron.

**D10. Browser client on three.js, outside this package.** (2026-10-16)
three.js is a renderer, which is all a stream-driven client needs; its WebGPU renderer
falls back to WebGL 2. Rejected: Babylon.js, a full engine whose scene graph, physics and
input would duplicate what cauldron already owns. Meshes go to the browser as glTF,
converted once on the server from what `cauldron_3d_formats` reads. The browser client
lives with the web packages (beside `cauldron.js` in `cauldron_2d_net`, or a 3D
counterpart of it), not in `cauldron_gpu`. It gets raster rendering only: WebGPU has no
ray-tracing hardware access, DLSS or frame generation.

**D11. Renderer core in C++; the graphics layer is a C function table.** (2026-10-16)
`c_src/gpu.h` declares `cg_backend`, a struct of function pointers. The Vulkan backend
(C++) and the Metal backend (Swift functions exported with `@_cdecl`, gathered into the
table by `c_src/metal/backend.c`) each fill one. The core (scene, passes, frame loop,
stream decoding) and the NIF entry are C++ and call only the table. Swift's C++ interop
was not used: Swift cannot implement a C++ interface, and a C table needs nothing from it.

**D12. Bindless everything: buffers by GPU address, textures by handle.** (2026-10-16)
Shaders get one push-constant struct (≤ 128 bytes) holding GPU addresses of every buffer
they read, and read textures and samplers through `DescriptorHandle<T>` values stored in
buffers. There are no vertex layouts (vertices are read from a buffer by index), no
per-draw descriptor sets and no bind groups. Metal: `gpuAddress`, `gpuResourceID`, all
allocations in one `MTLResidencySet`. Vulkan: buffer device address, and one global
descriptor set holding every sampled texture (binding 2) and sampler (binding 0) as
Slang's resource heap expects. Measured with slangc 2026.19: pointers and handles to
`Texture2D`, `TextureCube`, `RWTexture2D` and `SamplerState` compile to both targets.
Unbounded texture arrays (`Texture2D t[]`) do not compile for Metal; do not use them.
Storage images through handles alias binding 2 with a different descriptor type on
Vulkan, which needs `VK_EXT_mutable_descriptor_type`; compute writes go to buffers until
that is settled.

**D13. Shaders are Slang, compiled ahead of time and committed.** (2026-10-16)
`shaders/*.slang` → `priv/shaders/*.spv` (with `-fvk-invert-y`, so one projection serves
both backends) and `priv/shaders/*.metallib`, by `make shaders` using the slangc that
`make slang` downloads into `tools/slang` (ignored by git, pinned version). Someone
building the package needs neither slangc nor Apple's Metal toolchain.
Ray tracing on Metal through Slang: inline ray queries (`RayQuery`) compile, measured in a
compute shader with the acceleration structure bound directly; through a
`DescriptorHandle` in a fragment shader they do not. Ray-tracing pipelines (`TraceRay`,
hit and miss shaders) have no Metal output in Slang (open issue shader-slang/slang#11296).
So ray tracing is written as inline ray queries in compute passes on both backends.
Mesh shaders compile for Metal.

**D14. SDL3 for windows and input.** (2026-10-16)
SDL3 (3.4) creates the window, the Metal layer or Vulkan surface, and delivers keyboard,
mouse and window events on all three systems. Linked through pkg-config.
Gamepads stay with the `gamepad` package; SDL3's gamepad support is not used, so input
from a pad reaches a game the same way whatever draws it.

**D15. The window thread is the process's main thread on macOS.** (2026-10-16)
Measured: a NIF calling `erl_drv_steal_main_thread` gets a thread where
`pthread_main_np()` is 1, and SDL3 initialises video, opens a window and returns a
`CAMetalLayer` there, under both `erl -noshell` and `elixir`. On Linux and Windows the
window thread is an ordinary thread. One window thread serves every window. Only one
library per VM can take the main thread, so `cauldron_gpu` and `wx` cannot both open
windows in one VM on macOS.

**D16. The render thread is separate from the window thread.** (2026-10-16)
The window thread creates windows and surfaces and pumps events. Each window has a render
thread that acquires drawables, applies changes and draws. Metal and Vulkan both allow
presenting from a thread other than the one that made the window.

**D17. Depth is reversed (1 near, 0 far) in 32-bit float.** (2026-10-16)
Precision across large Quake-size maps; MetalFX frame interpolation takes a reversed-depth
flag.

**D18. Vendor upscaling and frame generation, per system.** (2026-10-16)
Researched, not yet built:
- macOS: MetalFX frame interpolation (`MTLFXFrameInterpolator`) and the temporal
  denoised scaler need macOS 26. Apple publishes no chip list; support is checked at run
  time (`supportsDevice`). Inputs: color, previous color, motion, reversed depth, optional
  UI texture, camera matrices, jitter, delta time.
- NVIDIA on Windows: Streamline (Windows only).
- NVIDIA on Linux: the DLSS SDK (NGX) directly; upscaling and ray reconstruction ship
  `.so` files, frame generation ships one too but NVIDIA states Windows as its
  requirement. We present and pace generated frames ourselves.
- AMD: the FidelityFX SDK 2.x (FSR 4) is DX12 only; Vulkan upscaling and frame generation
  are in SDK 1.1.4 (FSR 3.1), Windows only, and frame generation replaces the swapchain
  (`ffxReplaceSwapchainForFrameinterpolationVK`). FSR 4 needs an RX 9000.

**D19. The Elixir API.** (2026-10-16)
`CauldronGPU.open/1` opens a window and returns a struct holding the window resource, its
SDL window id, device info and an `:atomics` id counter. Meshes, textures and materials
are uploaded with `mesh/2`, `texture/2`, `material/2`, which return `CauldronGPU.Handle`s;
the renderer frees each when its handle is garbage collected (NIF resource destructor
sends the drop operation). Scene entries — instances, lights, camera, environment,
effects — are keyed by the caller's integer ids and changed by `submit/2`, one game tick
per call. Events go to the `:events` pid as `{:cauldron_gpu, window_id, event}`.
`capture/2` returns the next frame's RGBA bytes; `CauldronGPU.PNG` saves them.
Coordinates follow glTF: right-handed, +Y up, the camera looking down -Z.

**D20. Change stream format.** (2026-10-16)
Operation codes and field order are in `CauldronGPU.Stream` (encoder) and
`c_src/core/stream.cpp` (decoder); both must change together. Vertices are 48 bytes:
`position.xyz, u, normal.xyz, v, lightmap.uv, 0, 0`. Indices are `u32`. Transforms are
position (3 floats), rotation quaternion (x, y, z, w), scale (3 floats). A `:tick`
operation starts a game tick: every pose's previous value becomes its current one, and the
render thread draws poses interpolated between the last two ticks by arrival time, so the
picture runs one tick behind the game.

**D21. Deferred renderer layout.** (2026-10-16)
G-buffer: albedo `RGBA8_SRGB`; normal + roughness `RGBA16F`; emissive + metallic
`RGBA16F`; baked light (lightmap) + has-lightmap flag `RGBA16F`; depth `D32F` reversed.
Passes: shadow map (2048², one directional light, texel-snapped square of
`shadow_distance` around the camera, 3×3 PCF) → geometry → lighting (full-screen: sun
with shadow, point and spot lights from a buffer, sky reflections weighted by a roughness
Fresnel, exponential fog, sky where depth is 0) → ACES tone map into the surface.
Per-frame data (frame constants, instance matrices, materials, lights) is written each
frame into one of three upload arenas. One draw per mesh part.

**D22. Games describe, cauldron draws; GPU frames also go to the terminal.** (2026-10-16)
A game returns a scene each tick (world, models with frame and pose, sprites,
particles, dynamic lights, camera) plus a 2D overlay and screen effects; cauldron owns
the renderers behind one behaviour: the `cauldron_3d` software renderer, `cauldron_gpu`
in a native window (`--native`), `cauldron_gpu` read back into the terminal's picture
path, and the browser client. Game-specific choices (which textures are sky or liquid,
the palette, the HUD) are passed as data. GPU-only effects (ray tracing, upscaling) are
opt-in, since they change the games' look. Order: the technical proof of concept in
`cauldron_gpu` first (ray tracing, upscaling, frame generation, terminal output), then
moving the games' drawing into cauldron; editing the game projects needs the user's yes.

**D23. Metal shaders go through MSL; `RayDesc` is supplied when Slang drops it.** (2026-10-16)
Measured with slangc 2026.19: a shader that uses any `DescriptorHandle` and a
`RayQuery` gets Metal source that uses `RayDesc` without defining it. `make shaders`
therefore compiles Slang to MSL in `_build/shaders`, adds
`struct RayDesc { float3 Origin; float TMin; float3 Direction; float TMax; };` after
`using namespace metal;` when the type is used but missing, and builds the metallib with
`xcrun metal -std=metal3.1`. Remove the step once Slang emits the struct itself.

**D24. Ray-traced shadows and ambient occlusion.** (2026-10-16)
Each mesh gets a geometry acceleration structure at upload when the device has ray
tracing; each frame the visible instances form a scene acceleration structure (mask 0
for `shadows: false` instances), destroyed after the frame. One compute pass
(`shaders/raytrace.slang`, 8×8 groups) reads depth and normals and writes per pixel
`{sun visibility, ambient visibility}` (`float2`) to a GPU buffer: one ray to the
shadow-casting directional light, eight cosine-weighted hemisphere rays of
`ao_radius`. The lighting pass uses the sun value in place of the shadow map and
multiplies indirect light and sky reflections by the ambient value, averaged over 5×5
neighbours weighted by depth. Requested through `{:effects, [:ray_traced_shadows,
:ray_traced_ambient_occlusion]}`; ignored where there is no ray tracing.

**D25. Ray-traced reflections shade their hits.** (2026-10-16)
Pixels with roughness up to 0.5 trace one mirror ray (closest hit) in the same compute
pass. Each frame writes a table of traced instances (vertex and index addresses, the
instance's matrices index, its parts with material slots); a hit reads the triangle's
vertices by `CommittedInstanceIndex` and `CommittedPrimitiveIndex`, interpolates
texture and lightmap coordinates and the normal, and is lit by its lightmap or ambient,
emissive, and the sun with a shadow ray. Misses show the sky. The lighting pass blends
the result over the sky reflection by `1 - roughness / 0.5`. Rougher surfaces keep the
sky reflection; glossy (jittered) reflections need denoising first.

**D26. Offscreen rendering for the terminal.** (2026-10-16)
`CauldronGPU.open(window: false, width:, height:)` makes a device with no window or
surface. Backends then return a command list from `frame_begin` without a drawable and
`frame_end` submits without presenting. The render thread draws only when there is work
(a submitted batch, a capture request, or a capture still waiting for its frame), so an
idle offscreen renderer costs nothing. A frame takes the waiting capture requests before
it takes the batches, so a capture always shows every change submitted before it.
`examples/terminal.exs` sends each captured frame to the terminal as a zlib-compressed
RGBA kitty graphics image: 117 frames a second at 960×540 on the M3 Max, measured
writing to a file (GPU, readback, zlib, base64; the terminal's own drawing rate not
included).

**D27. Temporal upscaling.** (2026-10-16)
With `:upscaling` requested and `device_info.upscaling` true, frames are drawn at
`render_scale` (default 0.5) of the output size with a Halton(2,3) sub-pixel jitter
(32-frame cycle) added to the projection, and the backend's temporal upscaler (MetalFX
`MTLFXTemporalScaler` on Metal; none yet on Vulkan, where DLSS/FSR will go) turns the
lit HDR image into an output-size HDR image before tone mapping. Motion vectors (RG16F,
previous minus current position in texture coordinates, scaled to input pixels) come
from the geometry pass, using each instance's previous model matrix and the previous
unjittered view-projection; the lighting pass writes the sky's motion from the camera
alone. History is reset on the first frame and whenever the render size changes. The
G-buffer limit `CG_MAX_COLOR` is 8.

**D28. Frame generation.** (2026-10-16)
With `:frame_generation` requested, a window (not offscreen) and
`device_info.frame_generation` (MetalFX `MTLFXFrameInterpolator`, macOS 26+), the tone
map writes into the renderer's own `final` texture in the surface format; the
interpolator makes a frame between the previous `final` and this one from the depth and
motion of the input size and the camera; `frame_end_pair` copies the generated frame and
then the real one into two surface images and presents them half the last frame interval
apart. The layer is no longer framebuffer-only so it can be copied into. The first frame
after a reset presents the real frame twice. `capture(gpu, timeout, generated: true)`
returns the next generated frame (BGRA swizzled to RGBA). Vulkan has `frame_end_pair`
and no interpolator yet. Measured on the M3 Max at 1280×720 with upscaling: 24 real
frames a second, each presented with a generated one; pacing two images per display
refresh needs work before frame generation helps on a 60 Hz display.

**D29. Released objects live while scene entries use them.** (2026-10-16)
A garbage-collected handle's drop operation only marks the mesh, texture or material
released; each frame the renderer frees released meshes and materials that no instance
names, and released textures that no material names. Found when `mix run` scripts lost
handles to garbage collection before their last use and the scene went blank.

**D30. Frames reach the terminal through shared memory.** (2026-10-16)
Measured in Ghostty by the user: zlib+base64 pixels in the escape sequence ran at
12.8 fps at 960×540 and 41.8 at 480×270, so the cost is bytes through the terminal.
`capture(gpu, timeout, shared_memory: name)` makes the renderer copy the frame straight
into a POSIX shared-memory object (no Elixir binary), and the kitty sequence carries only
the name (`t=s`); the terminal reads and removes it. macOS cannot resize an existing
shared-memory object, so the renderer removes any object of that name before creating
it. A caller reuses a small pool of names (the example: four), so a terminal that never
reads them holds at most four frames; `remove_shared_memory/1` clears them on exit.
`t=t` (temporary file) is the fallback. iTerm2 does not gain from this: it has no kitty
placements, and its own image protocol only takes data inline. Writing frames to a file
instead of a terminal: 844 frames a second through shared memory, 663 through temporary
files, 15 inline.

**D31. The out-of-process host speaks packets over a pipe; big batches go through shared memory.** (2026-10-16)
`priv/native/<arch>/cauldron_gpu_host` is one renderer per OS process, built from
`c_src/host/` and every core object except `nif.cpp`. Window and renderer lifetime
(open, close, submit, capture, resize, relative mouse, frames) is `cg::RenderWindow`
(`c_src/core/render_window.*`), used by both the NIF and the host, so the two hostings
share it as well as the renderer. `cg::launch_window_thread` is defined per hosting: the
NIF steals the BEAM's main thread (D15) or starts a thread; the host's `main` hands its
own main thread to the window loop.
The host's stdin/stdout carry `{:packet, 4}` frames; its own stdout is moved to stderr at
start so library output cannot corrupt them. Requests (Elixir → host) are a one-byte
code and big-endian fields: `1` open (`windowed::8, width::32, height::32,
backend_size::8, backend, title_size::32, title, shaders_size::32, shaders`), `2` submit
(the change stream inline), `3` shared submit (`size::64, name`), `4` capture
(`tag::32, generated::8, shared_memory_name`), `5` resize (`tag::32, w::32, h::32`),
`6` relative mouse (`tag::32, enabled::8`), `7` frames (`tag::32`), `8` close. Messages
back are external term format: `{:opened, id, info}`, `{:open_failed, message}`,
`{:event, event}` with the NIF's event shapes, `{:reply, tag, result}`, and
`{:released, name}`. A shared submit names a POSIX shared-memory object the BEAM wrote
(through `CauldronGPU.Native.write_shared_memory/2`); the host maps it, removes the name
at once and answers `{:released, name}`, and unmaps it when the batch is applied. The
server removes the names never answered when the host exits. Batches below
`:shared_memory_threshold` (default 256 KiB), or where shared memory cannot be written,
go inline. Ending stdin, or request `8`, closes the renderer and ends the process.
Handle drops are submits of the drop operations.

**D32. Host handles are released explicitly or with their owner.** (2026-10-16)
There is no NIF resource for a host handle, so garbage collection frees nothing.
`CauldronGPU.Host` (a GenServer owning the Port) releases a handle on `release/2`, and
every handle a process made when that process exits (it monitors each process that made
one). D29 still holds: a release only marks the object. The server keeps the scene it
has relayed (`CauldronGPU.Host.Record`: resources, instances with their latest transform
and pose, lights, camera, environment, effects); released objects stay in the record
while a kept instance, pose or material names them. When the host process exits the
server sends `{:cauldron_gpu, id, :renderer_exited}` to the events pid, answers waiting
calls with `{:error, "renderer exited"}`, and keeps recording submits; `restart/1` starts
a new process and sends `[:tick | Record.replay(record)]`, then the released objects'
drops. The window id given to callers stays the first one. Restart is the caller's
choice; the server does not restart by itself. The server stops when the process that
called `open/1` exits.

**D33. Vertex animation and skinning run on the GPU before everything else.** (2026-10-16)
`{:pose, id, %CauldronGPU.Pose{blend_to:, blend:, bones:}}` bends an instance: a compute
pass (`shaders/deform.slang`, `c_src/core/deformer.*`) blends towards a second mesh with
the same vertex count (Quake keyframes) and then skins with up to four bones per vertex
(`%Mesh{skin: <<4 indices, 4 weights>> per vertex}`, stream op 16), writing a per-instance
vertex buffer. Drawing, shadows, the ray-traced scene (a geometry acceleration structure
rebuilt each frame for each posed instance) and the hit tables all read those vertices.
Each posed instance keeps last frame's deformed vertices too, so motion vectors include the
deformation. Poses apply at the tick that carries them; they are not interpolated between
ticks.

**D34. Cascaded shadows, transparency and bloom.** (2026-10-16)
Four 2048² cascades split at 1/16, 1/4, 9/16 and 1 of `shadow_distance`, each an
orthographic square around the bounding sphere of its slice of the view, texel-snapped;
the lighting pass picks the cascade by distance from the camera. Materials with
`alpha_mode: :blend` are drawn after lighting in a forward pass (shared shading code in
`shaders/shading.slang`), sorted far to near by instance position, with no depth writes
and no shadows (left out of the shadow maps and, when every part is see-through, of the
ray-traced scene). Bloom: five half-size levels, a 13-tap downsample with a soft threshold
on the first, tent upsamples added back up, the result added before tone mapping at
`bloom_strength` (default 0.05) above `bloom_threshold` (1.0).

**D35. Frame generation turns itself on only when it shows more frames.** (2026-10-16)
The renderer measures the interval between real frames with generation on and with it
off, predicts the rate shown each way (real rate, or twice it), and generates only when
that shows at least 10% more; it holds each choice for two seconds. Measured on the M3
Max at 60 Hz with 2,000 ray-traced spheres at 1920×1080: off, 53 frames a second; on, 21
real (42 shown) — so it tries generation, measures, and returns to 53. Before measuring
generation it assumes a 40% cost. `CauldronGPU.stats/1` reports frames, GPU and CPU
milliseconds per frame, the display's refresh rate and whether it is generating. The
window reports its display's refresh rate when it opens and when it moves display.

**D36. The terminal example fills the terminal.** (2026-10-16)
`CauldronGPU.terminal_size/0` reads `TIOCGWINSZ` (cells and pixels); offscreen devices
resize with `CauldronGPU.resize/3`. `examples/terminal.exs` draws at the terminal's pixel
size (8×16-pixel cells assumed when the terminal reports none), places the picture over
the whole terminal but the last row with `c=`, `r=` and `C=1`, and checks the size once a
second.

**D37. Light styles, normal and occlusion maps, tone map choice, part culling, denoising.** (2026-10-16)
- Light styles: a BSP atlas page holds up to four slots side by side, slot `k` holding
  each face's lightmap for its `k`-th style; vertices carry their four style numbers in
  the lightmap coordinates' spare pair (`s0 + 256·s1`, `s2 + 256·s3`, 255 none); the
  material's `lightmap_styles` is the slot count; `{:light_styles, [scale]}` sets a 64-entry
  table in the frame. `CauldronGPU.Bsp.light_style/2` reads `a`–`z` patterns (`m` = 1).
- Normal maps use tangents derived from screen-space derivatives of position and texture
  coordinates, so vertices carry no tangents. Occlusion maps ride in the albedo's alpha.
- `Environment.tone_map`: `:aces` (default), `:neutral`, `:clamp`.
- Each mesh part's bounding sphere is computed at upload; parts outside the camera frustum
  are not drawn in the geometry and forward passes but still cast shadows. Posed instances
  are not culled.
- Ray-traced indirect light: 2 ambient-occlusion rays, 1 glossy reflection ray (GGX, up to
  roughness 0.7), 1 bounce ray per pixel per frame, accumulated by a temporal pass
  (`shaders/denoise.slang`) reprojected by motion vectors and rejected where the distance
  to the camera disagrees (16 frames for bounce light and occlusion, 8 for reflections),
  then a 5×5 depth- and normal-aware average in the lighting pass. Bounce light replaces
  flat ambient on surfaces without a lightmap.

**D38. The browser client is `cauldron_3d_net` and reads the change stream itself.** (2026-10-16)
Location chosen by the user: `tui/cauldron/cauldron_3d_net` (named like
`cauldron_2d_net`, which is not renamed). Amends D10: meshes, textures and materials reach
the browser in the change stream's own format, decoded by `priv/static/cauldron3d.js` —
no glTF conversion, since the stream already carries everything three.js needs (vertex
arrays become `BufferGeometry` with groups per part, materials `MeshStandardMaterial`
with the lightmap on the second UV set). `Cauldron3D.Net.Scene` keeps the scene with
`CauldronGPU.Host.Record` (which now also keeps light styles) and broadcasts batches
through `Phoenix.PubSub`; `Cauldron3D.Net.Channel` sends a joining browser the whole scene
(subscribing first, so nothing is missed) and then each batch as a binary push; browser
input comes back as `CauldronGPU` event shapes, key names from a fixed list.
In the browser: light styles by patching three.js's lightmap shader chunk, poses blended
and skinned on the CPU, interpolation between ticks, bloom (`UnrealBloomPass`), tone map
choice; ray-traced effects, upscaling and frame generation are ignored. three.js 0.170.0
from jsDelivr. `cauldron_gpu`'s native build is skipped (with a message) when SDL3 or
Vulkan is missing, so a web server can depend on it without them.
Verified 2026-10-16: `mix run examples/showcase.exs` in cauldron_3d_net, the page loaded
in a headless Chromium, the courtyard drawn with shadows and lights, and held arrow keys
turning and moving the camera on the server.

**D39. One protocol for every place a scene goes.** (2026-10-16)
`CauldronGPU.Target` (`submit/2`, `mesh/2`, `texture/2`, `material/2`) is implemented by
`CauldronGPU` (in the VM), `CauldronGPU.Host` (own process) and `Cauldron3D.Net.Scene`
(browsers, now a struct opened with `open/1`; `start_link/1` and `lookup/1` for
supervisors and channels). The converters upload through it, so the same
`CauldronGPU.Bsp.upload/4`, model and Doom code fills a native window, a host or a browser.
Verified: `cauldron_3d_net/examples/quake_map.exs` puts E1M1 in a browser with its
textures, lightmaps and light styles. A project depending on `cauldron_gpu` gets the
converters only if it also depends on `cauldron_3d` (optional dependency); a dependency
compiled before that was added needs `mix deps.compile cauldron_gpu --force`.
`release/2` joined the protocol (a `CauldronGPU` answers `:ok`; its handles free when
unreferenced).

**D40. Games draw on the card only when asked, and fall back to their own picture.** (2026-10-16)
A `Cauldron2D.Client.Game` scene may carry `:gpu`, a function `(target, cache, size,
aspect) -> {changes, cache}` describing the same picture as its `:picture`. The terminal
client (`cauldron_2d_drafter`) uses it only when its picture options include `gpu` (drawn
offscreen at the pane's pixels and shown through the usual image path, so every terminal
protocol and the block-glyph fallback still work) or `window` (a window of its own, whose
keys are fed to the client as kitty-protocol key events). `Client.Stage` owns a
`CauldronGPU.Host` (a renderer crash leaves the game running; it is restarted with the
scene), and `Client.Gpu` keeps the client's side. With no `:gpu`, no card, a renderer that
fails to open or a closed window, the game's software picture is drawn, with a note for a
few seconds. `cauldron_gpu` is an optional dependency of `cauldron_2d_drafter`; each game
depends on it directly and gains `--gpu` and `--window`.

**D41. Skies and liquids.** (2026-10-16)
Materials gained `sky` (the surface shows the environment's sky along the view; no shadow;
rays reaching it see the sky) and `warp` (texels moved by `8 sin(texel / 8 + t)` across
axes, Quake's turbulence). `Environment.sky_picture` is `nil` (the gradient),
`{:layers, back, front}` (Quake's two scrolling layers on a flattened dome, made by
`Bsp.sky_layers/3`) or `{:box, faces}` (six pictures in cube-map layout, for Half-Life).
The G-buffer marks sky pixels (baked alpha 2) and the lighting pass fills them; RT
visibility uses closest hits so sky faces do not block light. The clock is seconds since
the renderer started (`GpuFrame.sky_picture.w`; the frame is 1200 bytes). The browser
client draws the same sky in a camera-centred box and on sky faces, and warps liquids.
Verified on E1M1: sky and moving water on Metal and Vulkan (MoltenVK), with RT effects on,
and the sky in the browser.

**D42. What palette games need from the renderer.** (2026-10-16)
Added for Quake and Doom, each general enough for other games:
`Camera.viewport` (the view projected into a rectangle of the frame, the rest black under the
overlay) and `Camera.aspect` (non-square pixels); `Instance.in_front` (depth squeezed into the
nearest tenth, no shadow, not traced: held weapons); `Instance.shading` (fixed
ambient + directional light as baked light: Quake's model lighting); `Environment.light_space:
:display` (baked light multiplies display colour, emissive texels show as is) and `gamma`;
`Environment.light_table` (baked light and distance look up the light shown: Doom's
diminishing light); `Material.smear` (the lit frame behind, copied by a full-screen pass,
shifted by rows: Doom's fuzz). Screen tint and overlay now blend display colours. GpuFrame is
1264 bytes, GpuInstance 240. The browser client does the same with shader patches, a
camera-centred projection matrix, a final pass for viewport and gamma, and a second render of
the scene without smeared objects. Verified by captures on Metal and Vulkan and in a browser
with a test scene; the games' own comparisons are with their agents.

**D43. Doom's last gaps.** (2026-10-16)
`light_table` rows are depth along the view (Doom's distance), not straight-line distance.
`smear` picks per square block. `Camera.resolution` shows the view as a grid of blocks
(low detail). Sprites sinking into floors: see D45 (`Instance.standing`). Alias-model skins
are uploaded without mipmaps (smaller levels let skin fill colour into edges).

**D44. What Half-Life needed.** (2026-10-16)
Under `light_space: :display`, point, spot and directional lights add to baked light by the
palette rule (`max(n·l,0)·max(1−d²/r²,0)`, spots `·max(1−x²−y²,0)` across the cone).
`Material.uv_scroll`, `uv_from: :reflection` (environment-mapped coordinates),
`alpha_mode: :add | :multiply` (new `CG_BLEND_MULTIPLY`, Metal and Vulkan; forward pipelines
are a blend × sides × depth-test table), `Mesh.colors` (RGBA bytes a vertex; `Billboards`
boards take `:color`; a `colors` address in `DrawPush`), `Instance.depth_test: false`,
`Instance.swell` (bulging shells), `Environment.contrast`/`brightness` beside `gamma`,
coloured light styles (three floats a style in the stream and the frame), and
`{:overlay, texture, :premultiplied}` (additive HUD pixels). GpuFrame 2096 bytes,
GpuMaterial 144, DrawPush 112.

**D45. Things standing in a room.** (2026-10-16)
`Instance.standing: {floor, ceiling}` replaces D43's wall-only hiding, which let sprites show
through raised floors in front of them. Floors and ceilings at or below `floor` or at or above
`ceiling` do not hide the instance; everything else nearer does, as Doom clips sprites by its
seg silhouettes. The geometry pass keeps the nearest depth per pixel in an R32F target; the
forward pass reads it with the G-buffer normal and the surface's height. `CG_BLEND_MAX` is
gone. The browser renders a nearest depth/normal/height target with an override material.
Verified at E1M1's blue armour (software and GPU agree) and in a test scene natively and in
a browser. GpuInstance is 272 bytes. The browser's bloom is ten times the native strength
(`bloomStrength * 10`), so bright scenes glow more there; it predates these rounds.

**D46. The card by default, and a setup page.** (2026-10-16)
This replaces D40's "only when asked". `Cauldron2D.Drafter.Settings` has a `drawing` field:
`:auto` (the default: the card in the pane when there is one), `:software`, `:pane` and
`:window`. The settings screen shows it as a Drawing row when `CauldronGPU.Host` is loaded,
and the Quake and Doom options menus show it too. The picture options `software`, `gpu` and
`window` override it for one run. `Client.Gpu.tick/2` starts the renderer on the first scene
that has `:gpu`, so a game without one never starts it. `Gpu.configure/1` runs at mount and
on every settings change. A note shows only when the card was named and cannot be used. In
window mode the window is redrawn on the menu timer and after each menu event, so menus work
while the world is paused. Pad presses reach menus as `{:key, key, [:pad]}`.
`Cauldron2D.Drafter.Launcher` is a setup page shown before a game starts: path fields with
a check and a discover function, choices, text, and the Drawing field. It saves to
`$XDG_CONFIG_HOME/<game>/launcher.config` and opens on the first run, when a saved path
fails its check, or with `--launcher`. Quake, Doom and Half-Life use it and find Steam
installs (CrossOver too). The Makefile builds Vulkan on macOS whenever `pkg-config` finds it;
`CAULDRON_GPU_VULKAN` is no longer needed.

**D47. 2D layers on the card.** (2026-10-17)
2D games draw on the card through two new stream ops. Op 21, `{:canvas, id, %Canvas{}}`,
makes an RGBA8 UNORM texture that is also a render target. It lives in the texture id space,
so sprites, column layers, the overlay and materials can all use it, and it is dropped
like a texture. Op 22, `{:layers, [layer]}`, replaces the layer list, and the list is drawn
every frame until the next one. A layer is a `SpriteLayer` (sprites into a target, an
optional clear, a port in target pixels, a view in sprite units) or a `ColumnLayer` (a
source texture redrawn through a per-column `{u, v_scale, shade}` table, sampled
bilinearly, black outside the source).

- **Display values, not light.** Cauldron2D blends sRGB bytes directly, so the 2D path
  does too. Pictures are uploaded `:linear` (UNORM), canvases are UNORM, and the blend
  factors do the rest. `:over` uses `CG_BLEND_ALPHA`. `:add` uses ADD with the shader
  writing `rgb·a, a`. `:subtract` uses MULTIPLY with the shader writing `1 − rgb·a, 1`,
  which keeps the alpha.
- **The frame's layers** draw into a "layers" RGBA8 UNORM target at output size. The first
  of them clears it to transparent unless it clears to a colour. The tonemap lays it over
  the display colours after the overlay: `shown·(1 − a) + rgb`. A renderer that has never
  been sent a `Camera` (`Scene::camera_set`) builds only the layers and presents them with
  `present2d.slang`, skipping the 3D passes. A camera sent once keeps 3D on.
- **Coverage and texels as `Cauldron2D.Blend`.** The vertex shader widens each quad by one
  pixel. The fragment shader inverts the placement at the pixel centre, discards outside
  `[0, w) × [0, h)`, and floors to the texel, as `blend_nif.c` does. A first version
  interpolated texel coordinates instead and missed ties at texel edges when drawing
  smaller. Measured against `Cauldron2D.DrawList` (four sprites with turns, mirror, tint,
  add and subtract; a canvas at half size doubled): 0 pixels differ on Metal and on Vulkan
  (MoltenVK). On NidhOX frames: exact at 640×400 (zoom 2). At 700×380 (zoom 1.9), about 300
  of 266 000 pixels pick the neighbouring texel at exact ties, decided by 64-bit rounding in
  software and 32-bit on the card; the stream's floats are 32-bit too.
- **Slang's `SV_VertexID` on SPIR-V leaves out the draw's first vertex**, while Metal's
  includes it. Runs of sprites with one blend mode are separate draws, so the run's first
  sprite goes in `LayerPush.first` and every draw starts at vertex 0.
- **No scissor in `cg_backend`.** Ports clip in the fragment shader (`outside_port`).
- `GpuFrame` is 2128 bytes (a `layers` float4 and the `flat` handle pair). `GpuSprite` is 96
  bytes, `GpuLayer` 80, `LayerPush` 32.
- **Targets.** `CauldronGPU.Target` gained `canvas/2`. `Host.Record` keeps canvases and the
  last layer list and counts their handles as used. The browser (`cauldron3d.js`,
  `Layers2D`) draws the same layers with three.js render targets. Its canvases store the
  top row first, so they sample like uploaded textures. Its column layer blends four texels
  itself, so it works whatever the source's filter. Checked against native captures by eye.
- **First user: NidhOX** (`Nidhox.Gpu`, through `Cauldron2D.Drafter.Client.Sprites`). The
  room goes into a canvas, the stairs' spiral warp is a column layer, then the GUI, then
  the letterbox. Measured at 126 items through `CauldronGPU.Host` with readback: 1 ms a
  frame against 4 ms in software at 640×400, and 6 ms against 36 ms at 1920×1200.

**D48. An autorelease pool around every Metal frame.** (2026-10-18)
The render thread is a C++ thread with no autorelease pool, so every Metal frame's
autoreleased objects (the command buffer above all) were never freed, along with every
resource they retained. Captures, replaced textures and upload buffers leaked one frame's
worth at a time: NidhOX in the pane grew `cauldron_gpu_host` past 12 GB in minutes. The
Metal backend table (`c_src/metal/backend.c`) now pushes a pool in `frame_begin` and pops
it in `frame_end` and `frame_end_pair`. Measured with 600 frames, each uploading a 2 MB
texture, releasing the last one and capturing 640×400: before, 1,255 → 3,135 MB, with
1,800 MB of `IOAccelerator` still held after idling. After, flat at 1,343 MB and 149 MB
after idling. A minute of NidhOX attract mode at 1280×800 with a capture each frame holds
at about 1.5 GB. The remaining 1.3 GB while busy is freed GPU memory the driver keeps for
reuse (`Owned physical footprint (unmapped)`), and it is returned when the renderer idles.
Vulkan has no autorelease, so this does not apply to it.

## Open questions and checks

Each must be settled before the work item named in brackets starts. Record the answer
as a decision.

- [ ] **FSR on Linux** [Work 8]. No official Linux support found for FidelityFX on
      Vulkan; decide whether Linux AMD gets FSR 3.1 built from source, or upscaling only.

## Work

### 1. Package and build

- [x] Mix project, `Makefile` (macOS, Linux), `make slang`, `make shaders`, NIF entry
- [x] `Makefile.win` (nmake, MSVC; needs `VULKAN_SDK` and `SDL3_DIR`) — written, never run
- [x] Host executable target (`cauldron_gpu_host`)

### 2. Graphics layer

- [x] Interface `c_src/gpu.h`: buffers by address, textures by handle, passes, graphics
      and compute pipelines, acceleration structures, upscaler, frame interpolator, paired
      presents, readback, GPU frame time
- [x] Metal backend (Swift), every entry
- [x] Vulkan backend (C++): every entry; raster, compute, offscreen, paired presents and
      timing tested on MoltenVK; acceleration structures never run (no RT in MoltenVK);
      upscaler and interpolator return NULL

### 3. Change stream and native scene

- [x] API (D19), stream (D20), interpolation between ticks, released objects kept while
      used (D29), poses (D33), light styles (D37)

### 4. Window, input, presenting

- [x] macOS window on the main thread; events; relative mouse; display refresh rate
- [ ] Linux and Windows windows (code paths exist; never run)
- [ ] Fullscreen, vsync choice, HDR output

### 5. Rasterized renderer

- [x] Deferred PBR, point/spot/directional lights, cascaded shadows (D34), sky, fog,
      transparency, bloom, tone map choice, normal and occlusion maps, per-part culling (D37)
- [ ] Alpha-tested shadows (cut-out textures cast solid shadows in the shadow maps)
- [ ] GPU-driven culling and indirect drawing (CPU culling covers the current scenes)

### 6. Assets

- [x] BSP worlds with every light style (`CauldronGPU.Bsp`)
- [x] Quake alias models (`CauldronGPU.AliasModel`), Half-Life studio models
      (`CauldronGPU.StudioModel`), placement helpers (`CauldronGPU.Placement`)
- [x] Doom sector maps (`CauldronGPU.Sectors`) with an example-local WAD reader
- [ ] Doom things/sprites, moving sectors, animated flats and walls
- [ ] Half-Life chrome and additive textures; items dropped to the floor

### 7. Ray tracing

- [x] Shadows, ambient occlusion, mirror and glossy reflections, one-bounce global
      illumination, temporal + spatial denoising (D24, D25, D37)
- [ ] A stronger denoiser (variance-guided, à-trous) and history clamping for moving objects
- [ ] Ray-traced shadows for alpha-tested surfaces (any-hit)

### 8. Upscaling and frame generation

- [x] MetalFX temporal upscaling (D27) and frame interpolation (D28) with adaptive use (D35)
- [x] GPU frame timing (`CauldronGPU.stats/1`)
- [ ] DLSS / DLSS frame generation (Streamline on Windows, NGX on Linux) — needs an
      NVIDIA machine to build and run
- [ ] FSR 3.1 upscaling and frame generation on Vulkan — needs a Windows machine (the SDK
      builds only there)

### 9. Games

- [x] Readback, offscreen device, terminal output through shared memory, terminal-sized
      pictures (D26, D30, D36)
- [x] Client side of D22's second step: scene `:gpu`, `Client.Stage`, `gpu`/`window`
      picture options, fallback (D40); skies and liquids (D41)
- [x] Each game's `:gpu` scene: `elixir_quake`, `elixir_doom`, `elixir_half_life` (D42–D45)
- [x] The card by default, the Drawing setting, the setup page (D46)

### 10. Out-of-process host

- [x] Host executable, `CauldronGPU.Host`, restart with the scene re-sent (D31, D32)
- [ ] Windows: no POSIX shared memory, every batch goes inline; `{:light_styles, …}` is not
      kept for restart (games send it every tick)

### 11. Browser client (D10, D38)

- [x] `cauldron_3d_net`: scene server, channel, socket, page, three.js client, input
- [ ] Capability report from the browser to the server (the client ignores what it cannot
      draw; the server is not told)
- [x] Converters upload to browser scenes through `CauldronGPU.Target` (D39); E1M1 verified
- [x] 2D layers and canvases in the browser (D47)

### 12. 2D layers (D47)

- [x] Stream ops 21 (canvas) and 22 (layers); `Canvas`, `Sprite`, `SpriteLayer`,
      `ColumnLayer`; `canvas/2` on `CauldronGPU`, `Host`, `Target` and the browser scene
- [x] `sprite.slang`, `columns.slang`, `present2d.slang`; a layers target over the 3D
      frame; layers alone with no camera
- [x] `Cauldron2D.Drafter.Client.Sprites` (draw lists to sprites, pictures uploaded once)
- [x] NidhOX draws on the card (`Nidhox.Gpu`)
- [ ] A drafter window backend: cells as quads from a glyph atlas, pictures as textures
      (planned in `dev_docs/VELLUM_DESIGN.md` D20)
- [ ] First run on Linux and Windows Vulkan

## Next session

State at the end of 2026-10-16, second round. Everything above marked done was verified
on the M3 Max by captured frames unless it says otherwise.

- A plain `mix compile` builds Metal and Vulkan on this Mac (D46). `make shaders` after
  changing `shaders/`.
- Examples: `showcase.exs` (`EFFECTS=rt,gi,upscale`), `spheres.exs` (load test, `COUNT=`, `=`/`-`), `quake_map.exs` (`MONSTERS=1`,
  light styles, `VIEW=`, `CAPTURE_AT=`), `doom_map.exs`, `studio_model.exs`,
  `terminal.exs` (fills the terminal; not yet watched by the user after the sizing work).
- 2026-10-17: 2D layers (D47) landed and NidhOX uses them. `make shaders` built
  `sprite`, `columns` and `present2d`.
- Open items, in rough order of value: D22's second
  step (needs the user's yes for the game projects), a stronger denoiser, alpha-tested
  shadows, Doom things and moving sectors, first runs on Linux/Windows (Vulkan RT, window,
  `Makefile.win`), DLSS/FSR on the machines that have them.
