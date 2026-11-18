defmodule CauldronGPU do
  @moduledoc """
  A window drawn by the graphics card from a scene described in Elixir.

  Elixir keeps the world and sends changes; a native render thread draws at the display's
  rate from its own copy of the scene, interpolating poses between ticks.

      {:ok, gpu} = CauldronGPU.open(title: "Demo", width: 1280, height: 720)
      cube = CauldronGPU.mesh(gpu, Cauldron3D.Scene.Mesh.cube(1.0))
      red = CauldronGPU.material(gpu, %Cauldron3D.Scene.Material{base_color: {0.8, 0.1, 0.1, 1.0}})

      CauldronGPU.submit(gpu, [
        {:instance, 1, %Cauldron3D.Scene.Instance{mesh: cube, materials: [red]}},
        {:light, 1, %Cauldron3D.Scene.Light{kind: :directional, direction: {-0.4, -1.0, -0.3}, shadows: true}},
        %Cauldron3D.Scene.Camera{position: {0.0, 1.0, 4.0}}
      ])

  Window events arrive at the `:events` process as `{:cauldron_gpu, window_id, event}`:
  `{:key, :down | :up, key, repeat?}` (key an atom such as `:w`, `:space`, `:left_shift`),
  `{:mouse_motion, x, y, dx, dy}`, `{:mouse_button, :down | :up, button, x, y}`,
  `{:mouse_wheel, dx, dy}`, `{:resized, width, height}`, `{:focus, boolean}`,
  `:close_requested`, and `{:error, message}` when the renderer rejects a change.

  On macOS the window runs on the process's main thread, which the first `open/1` takes
  for the rest of the VM's life; `wx` cannot open windows in the same VM.
  """

  alias Cauldron3D.Scene.{Canvas, Capabilities, Handle, Material, Mesh, Scatter, Stream, Texture}
  alias CauldronGPU.Native

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

  With `surface: handle` it draws into a surface the host app made instead of a window,
  as `CauldronNative.gpu_surface/0` gives it: on iOS a `CAMetalLayer *` with the Metal
  backend, on Android an `ANativeWindow *` with Vulkan, as an integer. `width` and
  `height` are the surface's size in pixels; `resize/3` follows it when it changes. No
  window events are sent: the host reports input. A phone build of this library has no
  windows, only surfaces and `window: false`.
  """
  @spec open(keyword()) :: {:ok, t()} | {:error, String.t()}
  def open(opts \\ []) do
    with :ok <- loaded(),
         {:ok, backend} <- backend(Keyword.get(opts, :backend)),
         {:ok, window, id, info} <- opened(backend, Keyword.get(opts, :surface), opts) do
      {:ok, %__MODULE__{window: window, id: id, info: info, ids: :atomics.new(1, signed: false)}}
    end
  end

  defp opened(backend, nil, opts) do
    Native.open(
      backend,
      Keyword.get(opts, :title, "cauldron_gpu"),
      Keyword.get(opts, :width, 1280),
      Keyword.get(opts, :height, 720),
      shader_directory(),
      Keyword.get(opts, :events, self()),
      Keyword.get(opts, :window, true)
    )
  end

  defp opened(backend, surface, opts) when is_integer(surface) and surface > 0 do
    Native.open_surface(
      backend,
      surface,
      Keyword.get(opts, :width, 1280),
      Keyword.get(opts, :height, 720),
      shader_directory(),
      Keyword.get(opts, :events, self())
    )
  end

  @doc "The backends this build has, preferred first."
  @spec backends() :: [:metal | :vulkan]
  def backends, do: if(Native.load_error(), do: [], else: Native.backends())

  @doc "Closes the window. Later calls with `gpu` return `{:error, \"closed\"}`."
  @spec close(t()) :: :ok
  def close(%__MODULE__{window: window}), do: Native.close(window)

  @doc "Sends one tick of changes (see `Cauldron3D.Scene.Stream`); a `:tick` is put before them."
  @spec submit(t(), [Stream.change()]) :: :ok | {:error, String.t()}
  def submit(%__MODULE__{window: window}, changes) do
    Native.submit(window, IO.iodata_to_binary(Stream.encode([:tick | decoded(changes)])))
  end

  @doc "Uploads a mesh and returns its handle."
  @spec mesh(t(), Mesh.t()) :: Handle.t()
  def mesh(gpu, %Mesh{} = mesh), do: put(gpu, :mesh, fn id -> {:mesh, id, mesh} end, [])

  @doc "Uploads a texture and returns its handle. An encoded texture is decoded first (`decode/1`)."
  @spec texture(t(), Texture.t()) :: Handle.t()
  def texture(gpu, %Texture{} = texture),
    do: put(gpu, :texture, fn id -> {:texture, id, decode!(texture)} end, [])

  @doc """
  The texture with a PNG or JPEG file (`Cauldron3D.Scene.Texture.encoded/2`) decoded to RGBA
  pixels, on a dirty scheduler; a texture of pixels as it is. `{:error, reason}` for a
  file that cannot be read.
  """
  @spec decode(Texture.t()) :: {:ok, Texture.t()} | {:error, String.t()}
  def decode(%Texture{encoding: :raw} = texture), do: {:ok, texture}

  def decode(%Texture{} = texture) do
    case Native.decode_image(texture.pixels) do
      {:ok, width, height, pixels} ->
        {:ok, %{texture | width: width, height: height, pixels: pixels, encoding: :raw}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "As `decode/1`, raising `ArgumentError` for a file that cannot be read."
  @spec decode!(Texture.t()) :: Texture.t()
  def decode!(texture) do
    case decode(texture) do
      {:ok, decoded} -> decoded
      {:error, reason} -> raise ArgumentError, "cannot decode texture: #{reason}"
    end
  end

  @doc """
  The PNG or JPEG file `file` scaled so its longest side is at most `:max_side` pixels
  (default 2048; a smaller picture keeps its size), written again as JPEG at `:quality`
  (default 90), or as PNG when any pixel is see-through. `:colour` is `:srgb` (default)
  for colour pictures, resized in linear light, or `:linear` for data such as normals
  and roughness. Runs on a dirty scheduler.
  """
  @spec reduce_image(binary(), keyword()) ::
          {:ok,
           %{kind: :png | :jpeg, width: pos_integer(), height: pos_integer(), bytes: binary()}}
          | {:error, String.t()}
  def reduce_image(file, opts \\ []) do
    max_side = Keyword.get(opts, :max_side, 2048)
    colour = Keyword.get(opts, :colour, :srgb)

    case Native.reduce_image(file, max_side, colour, Keyword.get(opts, :quality, 90)) do
      {:ok, kind, width, height, bytes} ->
        {:ok, %{kind: kind, width: width, height: height, bytes: bytes}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "`changes` with every encoded texture in them decoded (`decode!/1`)."
  @spec decoded([Stream.change()]) :: [Stream.change()]
  def decoded(changes) do
    Enum.map(changes, fn
      {:texture, id, %Texture{} = texture} -> {:texture, id, decode!(texture)}
      change -> change
    end)
  end

  @doc "Makes a canvas (`Cauldron3D.Scene.Canvas`) and returns its handle, a texture's."
  @spec canvas(t(), Canvas.t()) :: Handle.t()
  def canvas(gpu, %Canvas{} = canvas),
    do: put(gpu, :texture, fn id -> {:canvas, id, canvas} end, [])

  @doc "Defines a material and returns its handle, which keeps its textures' handles."
  @spec material(t(), Material.t()) :: Handle.t()
  def material(gpu, %Material{} = material) do
    put(gpu, :material, fn id -> {:material, id, material} end, Material.textures(material))
  end

  @doc "Uploads a scatter, the places an instance draws its mesh at, and returns its handle."
  @spec scatter(t(), Scatter.t()) :: Handle.t()
  def scatter(gpu, %Scatter{} = scatter),
    do: put(gpu, :scatter, fn id -> {:scatter, id, scatter} end, [])

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
  Sends the calling process every frame the renderer draws, as
  `{:cauldron_gpu, id, {:frame, width, height, pixels}}`, until `stop_stream/1`.

  At most `:ahead` frames (default `2`) are sent before the receiver calls
  `frame_shown/1`; until then the renderer draws but reads nothing back, so a slow
  receiver gets fewer frames instead of a growing mailbox. An offscreen device
  (`window: false`) draws at `:fps` (default `60`) while streaming, whatever is
  submitted; a window draws at its display's rate.

  `shared_memory: names` writes each frame into the next of the POSIX shared-memory
  objects `names` in turn, as `capture/3` does, and sends
  `{:frame, width, height, {:shared_memory, name}}`. A frame that cannot be read back
  arrives as `{:frame, :error}`; one that cannot be written as `{:frame, {:error, reason}}`.

      {:ok, gpu} = CauldronGPU.open(window: false, width: 640, height: 360)
      :ok = CauldronGPU.stream(gpu, shared_memory: ["/frame_0", "/frame_1", "/frame_2", "/frame_3"])

      receive do
        {:cauldron_gpu, _id, {:frame, width, height, {:shared_memory, name}}} ->
          show(name, width, height)
          CauldronGPU.frame_shown(gpu)
      end
  """
  @spec stream(t(), keyword()) :: :ok | {:error, String.t()}
  def stream(%__MODULE__{window: window}, opts \\ []) do
    Native.stream_frames(
      window,
      Keyword.get(opts, :shared_memory, []),
      Keyword.get(opts, :ahead, 2),
      Keyword.get(opts, :fps, 60)
    )
  end

  @doc "Stops the frames `stream/2` started. Frames already read back still arrive."
  @spec stop_stream(t()) :: :ok | {:error, String.t()}
  def stop_stream(%__MODULE__{window: window}), do: Native.stop_frames(window)

  @doc "Tells the renderer one streamed frame has been used, so it may read back another."
  @spec frame_shown(t()) :: :ok | {:error, String.t()}
  def frame_shown(%__MODULE__{window: window}), do: Native.frame_shown(window)

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

  @shader_sets [
    {"-iossimulator", "ios_simulator"},
    {"-tvossimulator", "tvos_simulator"},
    {"-ios", "ios"},
    {"-tvos", "tvos"}
  ]

  defp shader_directory do
    shaders = Path.join(:code.priv_dir(:cauldron_gpu), "shaders")
    architecture = to_string(:erlang.system_info(:system_architecture))

    case Enum.find(@shader_sets, fn {mark, _set} -> String.contains?(architecture, mark) end) do
      {_mark, set} -> Path.join(shaders, set)
      nil -> shaders
    end
  end

  defimpl Cauldron3D.Scene.Target do
    def submit(gpu, changes), do: @for.submit(gpu, changes)
    def mesh(gpu, mesh), do: @for.mesh(gpu, mesh)
    def texture(gpu, texture), do: @for.texture(gpu, texture)
    def canvas(gpu, canvas), do: @for.canvas(gpu, canvas)
    def material(gpu, material), do: @for.material(gpu, material)
    def scatter(gpu, scatter), do: @for.scatter(gpu, scatter)
    def release(_gpu, _handle), do: :ok
    def capabilities(gpu), do: Capabilities.from_info(gpu.info)
  end
end
