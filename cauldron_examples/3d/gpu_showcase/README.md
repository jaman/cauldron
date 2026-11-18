# GPU showcase

`cauldron_gpu` drawing in a window of its own, with Metal on macOS and Vulkan elsewhere.

```
mix deps.get
mix showcase                                  # a lit courtyard; fly with W A S D, Space, Left Shift and the mouse
EFFECTS=rt,gi,upscale mix showcase            # ray-traced shadows, reflections, light, and upscaling
mix spheres                                   # two thousand spheres; = and - add or take away 500
```

Both tasks take `[seconds] [metal|vulkan]` to stop by themselves and to pick the backend. `CAPTURE=frame.png` saves the last frame before closing.

## As a program of its own

```
MIX_ENV=prod mix release
_build/prod/rel/gpu_showcase/bin/gpu_showcase start
SHOWCASE_ARGS="30" _build/prod/rel/gpu_showcase/bin/gpu_showcase start
```

The release carries the Erlang runtime, so the machine it runs on needs nothing
installed. It opens the showcase when it starts and stops when the window closes.
`SHOWCASE_ARGS` takes `mix showcase`'s arguments. The release is also written as
`_build/prod/gpu_showcase-0.1.0.tar.gz`, to unpack and run elsewhere on the same kind of
machine.

| Module | What it is |
| --- | --- |
| `GpuShowcase.Courtyard` | The courtyard scene, built in code |
| `GpuShowcase.Showcase` | The courtyard to fly through |
| `GpuShowcase.Spheres` | The load test |
