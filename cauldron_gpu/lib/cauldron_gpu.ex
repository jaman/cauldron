defmodule CauldronGPU do
  @moduledoc """
  A window drawn by the graphics card from a scene described in Elixir.

  Elixir keeps the world and sends changes; a native render thread draws at the display's
  rate from its own copy of the scene, interpolating poses between ticks.

      {:ok, gpu} = CauldronGPU.open(title: "Demo", width: 1280, height: 720)
      cube = CauldronGPU.mesh(gpu, CauldronGPU.Mesh.cube(1.0))
      red = CauldronGPU.material(gpu, %CauldronGPU.Material{base_color: {0.8, 0.1, 0.1, 1.0}})

      CauldronGPU.submit(gpu, [
        {:instance, 1, %CauldronGPU.Instance{mesh: cube, materials: [red]}},
        {:light, 1, %CauldronGPU.Light{kind: :directional, direction: {-0.4, -1.0, -0.3}, shadows: true}},
        %CauldronGPU.Camera{position: {0.0, 1.0, 4.0}}
      ])

  Window events arrive at the `:events` process as `{:cauldron_gpu, window_id, event}`:
  `{:key, :down | :up, key, repeat?}` (key an atom such as `:w`, `:space`, `:left_shift`),
  `{:mouse_motion, x, y, dx, dy}`, `{:mouse_button, :down | :up, button, x, y}`,
  `{:mouse_wheel, dx, dy}`, `{:resized, width, height}`, `{:focus, boolean}`,
  `:close_requested`, and `{:error, message}` when the renderer rejects a change.

  On macOS the window runs on the process's main thread, which the first `open/1` takes
  for the rest of the VM's life; `wx` cannot open windows in the same VM.
  """

  alias CauldronGPU.{Canvas, Handle, Material, Mesh, Native, Stream, Texture}

  @type info :: %{
          backend: :metal | :vulkan,
          device: String.t(),
          ray_tracing: boolean(),
          mesh_shaders: boolean(),
          unified_memory: boolean(),
          upscaling: boolean(),
          frame_generation: boolean()
        }
  @type t :: %__MODULE__{
          window: reference(),
          id: non_neg_integer(),
          info: info(),
          ids: :atomics.atomics_ref()
        }

  @enforce_keys [:window, :id, :info, :ids]
  defstruct [:window, :id, :info, :ids]

  @doc """
  Opens a window. Options: `:title`, `:width` and `:height` in points (default 1280×720),
  `:backend` (`:metal` or `:vulkan`, default the first of `backends/0`), `:events`
  (the pid that receives window events, default the caller), `:window` (default `true`).

  With `window: false` nothing appears on screen: `width` and `height` are the picture's
  size in pixels, a frame is drawn for each `submit/2` and `capture/2`, and frames are
  read with `capture/2`.
  """
  @spec open(keyword()) :: {:ok, t()} | {:error, String.t()}
  def open(opts \\ []) do
    with :ok <- loaded(),
         {:ok, backend} <- backend(Keyword.get(opts, :backend)),
         {:ok, window, id, info} <-
           Native.open(
             backend,
             Keyword.get(opts, :title, "cauldron_gpu"),
             Keyword.get(opts, :width, 1280),
             Keyword.get(opts, :height, 720),
             shader_directory(),
             Keyword.get(opts, :events, self()),
             Keyword.get(opts, :window, true)
           ) do
      {:ok, %__MODULE__{window: window, id: id, info: info, ids: :atomics.new(1, signed: false)}}
    end
  end

  @doc "The backends this build has, preferred first."
  @spec backends() :: [:metal | :vulkan]
  def backends, do: if(Native.load_error(), do: [], else: Native.backends())

  @doc "Closes the window. Later calls with `gpu` return `{:error, \"closed\"}`."
  @spec close(t()) :: :ok
  def close(%__MODULE__{window: window}), do: Native.close(window)

  @doc "Sends one tick of changes (see `CauldronGPU.Stream`); a `:tick` is put before them."
  @spec submit(t(), [Stream.change()]) :: :ok | {:error, String.t()}
  def submit(%__MODULE__{window: window}, changes) do
    Native.submit(window, IO.iodata_to_binary(Stream.encode([:tick | changes])))
  end

  @doc "Uploads a mesh and returns its handle."
  @spec mesh(t(), Mesh.t()) :: Handle.t()
  def mesh(gpu, %Mesh{} = mesh), do: put(gpu, :mesh, fn id -> {:mesh, id, mesh} end, [])

  @doc "Uploads a texture and returns its handle."
  @spec texture(t(), Texture.t()) :: Handle.t()
  def texture(gpu, %Texture{} = texture),
    do: put(gpu, :texture, fn id -> {:texture, id, texture} end, [])

  @doc "Makes a canvas (`CauldronGPU.Canvas`) and returns its handle, a texture's."
  @spec canvas(t(), Canvas.t()) :: Handle.t()
  def canvas(gpu, %Canvas{} = canvas),
    do: put(gpu, :texture, fn id -> {:canvas, id, canvas} end, [])

  @doc "Defines a material and returns its handle, which keeps its textures' handles."
  @spec material(t(), Material.t()) :: Handle.t()
  def material(gpu, %Material{} = material) do
    put(gpu, :material, fn id -> {:material, id, material} end, Material.textures(material))
  end

  @doc "Hides the pointer and reports only relative motion while `enabled`."
  @spec relative_mouse(t(), boolean()) :: :ok | {:error, String.t()}
  def relative_mouse(%__MODULE__{window: window}, enabled),
    do: Native.relative_mouse(window, enabled)

  @doc """
  The next drawn frame as `{:ok, %{width: w, height: h, pixels: rgba}}`: tone-mapped,
  sRGB-encoded RGBA bytes, rows from the top. Waits up to `timeout` milliseconds.
  `generated: true` returns the next frame made by frame generation instead.

  `shared_memory: name` writes the pixels into the POSIX shared-memory object `name`
  (at most 31 bytes on macOS, starting with `/`; an existing object of that name is
  removed first) instead of returning them, and answers
  `{:ok, %{width: w, height: h, shared_memory: name}}`. The reader normally removes it;
  `remove_shared_memory/1` removes one that was never read. Not available on Windows.
  """
  @spec capture(t(), timeout(), keyword()) ::
          {:ok, %{width: pos_integer(), height: pos_integer(), shared_memory: String.t()}}
          | {:ok, %{width: pos_integer(), height: pos_integer(), pixels: binary()}}
          | {:error, term()}
  def capture(%__MODULE__{window: window, id: id}, timeout \\ 5000, opts \\ []) do
    generated = Keyword.get(opts, :generated, false)
    shared_memory = Keyword.get(opts, :shared_memory, "")

    with :ok <- Native.capture(window, generated, shared_memory) do
      receive do
        {:cauldron_gpu, ^id, {:capture, width, height, {:shared_memory, name}}} ->
          {:ok, %{width: width, height: height, shared_memory: name}}

        {:cauldron_gpu, ^id, {:capture, width, height, pixels}} ->
          {:ok, %{width: width, height: height, pixels: pixels}}

        {:cauldron_gpu, ^id, {:capture, {:error, reason}}} ->
          {:error, reason}

        {:cauldron_gpu, ^id, {:capture, :error}} ->
          {:error, :capture_failed}
      after
        timeout -> {:error, :timeout}
      end
    end
  end

  @doc """
  The size of the terminal the VM runs in: `{:ok, %{columns:, rows:, width:, height:}}`,
  cells and pixels (pixels are 0 where the terminal does not report them), or
  `{:error, reason}` when there is no terminal.
  """
  @spec terminal_size() :: {:ok, map()} | {:error, String.t()}
  def terminal_size, do: Native.terminal_size()

  @doc "Changes an offscreen device's picture size (`window: false`). Windows follow their window."
  @spec resize(t(), pos_integer(), pos_integer()) :: :ok | {:error, String.t()}
  def resize(%__MODULE__{window: window}, width, height), do: Native.resize(window, width, height)

  @doc "Removes the POSIX shared-memory object `name`, if there is one."
  @spec remove_shared_memory(String.t()) :: :ok
  def remove_shared_memory(name), do: Native.remove_shared_memory(name)

  @doc """
  Timing averaged over recent frames: `frames` drawn, `gpu_ms` and `cpu_ms` per frame, the
  display's `refresh_rate` (60 when offscreen), and whether frame generation is
  `generating` (it runs only when requested and frames take longer than the display's
  refresh).
  """
  @spec stats(t()) :: %{
          frames: non_neg_integer(),
          gpu_ms: float(),
          cpu_ms: float(),
          refresh_rate: float(),
          generating: boolean()
        }
  def stats(%__MODULE__{window: window}), do: Native.stats(window)

  @doc "How many frames the renderer has drawn into the window."
  @spec frames(t()) :: non_neg_integer()
  def frames(%__MODULE__{window: window}), do: Native.frames(window)

  defp put(%__MODULE__{window: window, ids: ids}, kind, change, keeps) do
    id = :atomics.add_get(ids, 1, 1)
    :ok = Native.submit(window, IO.iodata_to_binary(Stream.encode([change.(id)])))

    %Handle{
      kind: kind,
      id: id,
      ref: Native.handle(window, Stream.drop_op(kind), id),
      keeps: keeps
    }
  end

  defp loaded do
    case Native.load_error() do
      nil -> :ok
      text -> {:error, "cauldron_gpu did not load: #{text}"}
    end
  end

  defp backend(nil) do
    case Native.backends() do
      [first | _] -> {:ok, first}
      [] -> {:error, "no backend built"}
    end
  end

  defp backend(name) when name in [:metal, :vulkan], do: {:ok, name}

  defp shader_directory, do: Path.join(:code.priv_dir(:cauldron_gpu), "shaders")
end
