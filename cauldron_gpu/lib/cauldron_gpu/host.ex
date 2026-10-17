defmodule CauldronGPU.Host do
  @moduledoc """
  The renderer in its own OS process (`priv/native/<system architecture>/cauldron_gpu_host`),
  so a crash in it leaves the VM running. The functions take the same arguments and
  return the same values as `CauldronGPU`'s; a caller switches by module.

      {:ok, gpu} = CauldronGPU.Host.open(window: false, width: 640, height: 360)
      cube = CauldronGPU.Host.mesh(gpu, CauldronGPU.Mesh.cube(1.0))
      CauldronGPU.Host.submit(gpu, [{:instance, 1, %CauldronGPU.Instance{mesh: cube}}])

  A server process owns the renderer process and keeps the scene sent to it. When the
  renderer process exits, the `:events` process receives
  `{:cauldron_gpu, window_id, :renderer_exited}`; `restart/1` starts a new one and sends
  it the kept scene (meshes, textures, materials, instances, poses, lights, camera,
  environment, effects). Changes submitted while the renderer is down are kept and
  answered with `{:error, "renderer exited"}`. `window_id` stays the same across
  restarts. Other events are those of `CauldronGPU`.

  Handles are not freed by garbage collection. `release/2` releases one; every handle a
  process made is released when that process exits. A released object is freed once no
  scene entry uses it. The server stops when the process that called `open/1` exits.

  Change batches of `:shared_memory_threshold` bytes or more (default 262144) reach the
  renderer through a POSIX shared-memory object rather than the pipe.
  """

  use GenServer

  alias CauldronGPU.{Canvas, Handle, Material, Mesh, Native, Stream, Texture}
  alias CauldronGPU.Host.Record

  @type t :: %__MODULE__{server: pid(), id: non_neg_integer(), info: CauldronGPU.info()}

  @enforce_keys [:server, :id, :info]
  defstruct [:server, :id, :info]

  @open_timeout 30_000
  @default_threshold 262_144

  @doc """
  Starts a renderer process and opens a window or offscreen device in it. Options are
  those of `CauldronGPU.open/1`, plus `:shared_memory_threshold`.
  """
  @spec open(keyword()) :: {:ok, t()} | {:error, String.t()}
  def open(opts \\ []) do
    with {:ok, backend} <- backend(Keyword.get(opts, :backend)),
         {:ok, server} <- start_server(Keyword.put(opts, :backend, backend)) do
      {id, info} = GenServer.call(server, :describe)
      {:ok, %__MODULE__{server: server, id: id, info: info}}
    end
  end

  @doc "The backends the renderer was built with, preferred first."
  @spec backends() :: [:metal | :vulkan]
  defdelegate backends, to: CauldronGPU

  @doc "Closes the window and stops the renderer process and its server."
  @spec close(t()) :: :ok
  def close(%__MODULE__{server: server}) do
    GenServer.stop(server)
  catch
    :exit, _reason -> :ok
  end

  @doc "Sends one tick of changes (see `CauldronGPU.Stream`); a `:tick` is put before them."
  @spec submit(t(), [Stream.change()]) :: :ok | {:error, String.t()}
  def submit(%__MODULE__{server: server}, changes) do
    changes = [:tick | changes]
    call(server, {:submit, changes, IO.iodata_to_binary(Stream.encode(changes))})
  end

  @doc "Uploads a mesh and returns its handle."
  @spec mesh(t(), Mesh.t()) :: Handle.t()
  def mesh(host, %Mesh{} = mesh), do: put(host, :mesh, &{:mesh, &1, mesh}, [])

  @doc "Uploads a texture and returns its handle."
  @spec texture(t(), Texture.t()) :: Handle.t()
  def texture(host, %Texture{} = texture), do: put(host, :texture, &{:texture, &1, texture}, [])

  @doc "Makes a canvas and returns its handle, a texture's."
  @spec canvas(t(), Canvas.t()) :: Handle.t()
  def canvas(host, %Canvas{} = canvas), do: put(host, :texture, &{:canvas, &1, canvas}, [])

  @doc "Defines a material and returns its handle."
  @spec material(t(), Material.t()) :: Handle.t()
  def material(host, %Material{} = material),
    do: put(host, :material, &{:material, &1, material}, Material.textures(material))

  @doc "Releases a handle: the renderer frees its object once no scene entry uses it."
  @spec release(t(), Handle.t()) :: :ok
  def release(%__MODULE__{server: server}, %Handle{kind: kind, id: id}) do
    GenServer.call(server, {:release, kind, id})
  end

  @doc "Hides the pointer and reports only relative motion while `enabled`."
  @spec relative_mouse(t(), boolean()) :: :ok | {:error, String.t()}
  def relative_mouse(%__MODULE__{server: server}, enabled),
    do: call(server, {:request, :relative_mouse, enabled})

  @doc "The next drawn frame; see `CauldronGPU.capture/3`."
  @spec capture(t(), timeout(), keyword()) ::
          {:ok, %{width: pos_integer(), height: pos_integer(), shared_memory: String.t()}}
          | {:ok, %{width: pos_integer(), height: pos_integer(), pixels: binary()}}
          | {:error, term()}
  def capture(%__MODULE__{server: server}, timeout \\ 5000, opts \\ []) do
    request = {Keyword.get(opts, :generated, false), Keyword.get(opts, :shared_memory, "")}

    with {:ok, tag} <- call(server, {:capture, request}) do
      receive do
        {__MODULE__, ^tag, result} -> capture_result(result)
      after
        timeout -> {:error, :timeout}
      end
    end
  end

  @doc "The size of the terminal the VM runs in; see `CauldronGPU.terminal_size/0`."
  @spec terminal_size() :: {:ok, map()} | {:error, String.t()}
  defdelegate terminal_size, to: CauldronGPU

  @doc "Changes an offscreen device's picture size (`window: false`)."
  @spec resize(t(), pos_integer(), pos_integer()) :: :ok | {:error, String.t()}
  def resize(%__MODULE__{server: server}, width, height),
    do: call(server, {:request, :resize, {width, height}})

  @doc "Removes the POSIX shared-memory object `name`, if there is one."
  @spec remove_shared_memory(String.t()) :: :ok
  defdelegate remove_shared_memory(name), to: CauldronGPU

  @doc "How many frames the renderer process has drawn since it started."
  @spec frames(t()) :: non_neg_integer()
  def frames(%__MODULE__{server: server}) do
    case call(server, {:request, :frames, nil}) do
      count when is_integer(count) -> count
      {:error, _reason} -> 0
    end
  end

  @doc """
  Starts a new renderer process after the previous one exited and sends it the kept
  scene. `{:error, "running"}` while the renderer is alive.
  """
  @spec restart(t()) :: :ok | {:error, String.t()}
  def restart(%__MODULE__{server: server}),
    do: GenServer.call(server, :restart, @open_timeout + 5000)

  @doc "The renderer's OS process id, or `nil` while it is down."
  @spec os_pid(t()) :: non_neg_integer() | nil
  def os_pid(%__MODULE__{server: server}), do: GenServer.call(server, :os_pid)

  @impl GenServer
  def init({opts, opener}) do
    state = %{
      opts: opts,
      opener: Process.monitor(opener),
      events: Keyword.get(opts, :events, opener),
      threshold: Keyword.get(opts, :shared_memory_threshold, @default_threshold),
      port: nil,
      id: nil,
      info: nil,
      record: Record.new(),
      next_id: 0,
      next_tag: 0,
      waiting: %{},
      shared: MapSet.new(),
      next_shared: 0,
      owners: %{}
    }

    case start_renderer(state) do
      {:ok, state} -> {:ok, state}
      {:error, message} -> {:stop, {:shutdown, message}}
    end
  end

  @impl GenServer
  def handle_call(:describe, _from, state), do: {:reply, {state.id, state.info}, state}

  def handle_call(:os_pid, _from, %{port: nil} = state), do: {:reply, nil, state}

  def handle_call(:os_pid, _from, state),
    do: {:reply, state.port |> Port.info(:os_pid) |> elem(1), state}

  def handle_call({:submit, changes, binary}, _from, state) do
    state = %{state | record: Record.apply_changes(state.record, changes)}
    {reply, state} = send_stream(state, binary)
    {:reply, reply, state}
  end

  def handle_call({:put, kind, change_for}, {caller, _tag}, state) do
    id = state.next_id + 1
    change = change_for.(id)
    state = %{state | next_id: id, record: Record.apply_changes(state.record, [change])}
    {_reply, state} = send_stream(state, IO.iodata_to_binary(Stream.encode([change])))
    {:reply, id, own(state, caller, {kind, id})}
  end

  def handle_call({:release, kind, id}, _from, state) do
    {:reply, :ok, release_object(state, {kind, id})}
  end

  def handle_call({:capture, _request}, _from, %{port: nil} = state),
    do: {:reply, {:error, "renderer exited"}, state}

  def handle_call({:capture, {generated, shared_memory}}, {caller, _tag}, state) do
    {tag, state} = next_tag(state)
    command(state, <<4, tag::32, flag(generated), shared_memory::binary>>)
    {:reply, {:ok, tag}, %{state | waiting: Map.put(state.waiting, tag, {:capture, caller})}}
  end

  def handle_call({:request, _kind, _argument}, _from, %{port: nil} = state),
    do: {:reply, {:error, "renderer exited"}, state}

  def handle_call({:request, kind, argument}, from, state) do
    {tag, state} = next_tag(state)
    command(state, request(kind, tag, argument))
    {:noreply, %{state | waiting: Map.put(state.waiting, tag, {:call, from})}}
  end

  def handle_call(:restart, _from, %{port: nil} = state) do
    case start_renderer(state) do
      {:ok, state} ->
        replay = [:tick | Record.replay(state.record)]
        {_reply, state} = send_stream(state, IO.iodata_to_binary(Stream.encode(replay)))
        {:reply, :ok, state}

      {:error, message} ->
        {:reply, {:error, message}, state}
    end
  end

  def handle_call(:restart, _from, state), do: {:reply, {:error, "running"}, state}

  @impl GenServer
  def handle_info({port, {:data, data}}, %{port: port} = state),
    do: {:noreply, host_message(:erlang.binary_to_term(data), state)}

  def handle_info({port, {:exit_status, _status}}, %{port: port} = state),
    do: {:noreply, renderer_exited(state)}

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{opener: ref} = state),
    do: {:stop, :normal, state}

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {{_monitor, keys}, owners} = Map.pop(state.owners, pid, {nil, MapSet.new()})
    {:noreply, Enum.reduce(keys, %{state | owners: owners}, &release_object(&2, &1))}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    if state.port, do: command(state, <<8>>)
    Enum.each(state.shared, &CauldronGPU.remove_shared_memory/1)
  end

  defp start_server(opts) do
    case GenServer.start(__MODULE__, {opts, self()}) do
      {:ok, server} -> {:ok, server}
      {:error, {:shutdown, message}} -> {:error, message}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp put(%__MODULE__{server: server}, kind, change_for, keeps) do
    id = GenServer.call(server, {:put, kind, change_for})
    %Handle{kind: kind, id: id, ref: make_ref(), keeps: keeps}
  end

  defp call(server, message) do
    GenServer.call(server, message)
  catch
    :exit, _reason -> {:error, "closed"}
  end

  defp start_renderer(state) do
    port =
      Port.open({:spawn_executable, executable()}, [
        :binary,
        {:packet, 4},
        :exit_status,
        :use_stdio
      ])

    Port.command(port, open_request(state.opts))
    await_open(%{state | port: port}, [])
  end

  defp await_open(%{port: port} = state, held) do
    receive do
      {^port, {:data, data}} ->
        case :erlang.binary_to_term(data) do
          {:opened, id, info} -> {:ok, opened(state, id, info, held)}
          {:open_failed, message} -> stop_port(state, message)
          other -> await_open(state, [other | held])
        end

      {^port, {:exit_status, status}} ->
        {:error, "renderer process exited with status #{status}"}
    after
      @open_timeout -> stop_port(state, "renderer process did not open")
    end
  end

  defp opened(state, id, info, held) do
    state = %{state | id: state.id || id, info: info}
    held |> Enum.reverse() |> Enum.reduce(state, &host_message/2)
  end

  defp stop_port(%{port: port}, message) do
    Port.close(port)
    {:error, message}
  end

  defp open_request(opts) do
    backend = Atom.to_string(Keyword.fetch!(opts, :backend))
    title = Keyword.get(opts, :title, "cauldron_gpu")
    shaders = Path.join(:code.priv_dir(:cauldron_gpu), "shaders")

    <<1, flag(Keyword.get(opts, :window, true)), Keyword.get(opts, :width, 1280)::32,
      Keyword.get(opts, :height, 720)::32, byte_size(backend), backend::binary,
      byte_size(title)::32, title::binary, byte_size(shaders)::32, shaders::binary>>
  end

  defp request(:relative_mouse, tag, enabled), do: <<6, tag::32, flag(enabled)>>
  defp request(:resize, tag, {width, height}), do: <<5, tag::32, width::32, height::32>>
  defp request(:frames, tag, nil), do: <<7, tag::32>>

  defp host_message({:event, event}, state) do
    send(state.events, {:cauldron_gpu, state.id, event})
    state
  end

  defp host_message({:released, name}, state),
    do: %{state | shared: MapSet.delete(state.shared, name)}

  defp host_message({:reply, tag, result}, state) do
    {waiter, waiting} = Map.pop(state.waiting, tag)
    answer(waiter, tag, result)
    %{state | waiting: waiting}
  end

  defp answer({:call, from}, _tag, result), do: GenServer.reply(from, result)
  defp answer({:capture, caller}, tag, result), do: send(caller, {__MODULE__, tag, result})
  defp answer(nil, _tag, _result), do: :ok

  defp renderer_exited(state) do
    Enum.each(state.waiting, fn {tag, waiter} ->
      answer(waiter, tag, {:error, "renderer exited"})
    end)

    Enum.each(state.shared, &CauldronGPU.remove_shared_memory/1)
    send(state.events, {:cauldron_gpu, state.id, :renderer_exited})
    %{state | port: nil, waiting: %{}, shared: MapSet.new()}
  end

  defp send_stream(%{port: nil} = state, _binary), do: {{:error, "renderer exited"}, state}

  defp send_stream(state, binary) when byte_size(binary) >= state.threshold do
    name = "/cgh#{System.pid()}_#{Integer.to_string(state.next_shared, 36)}"
    state = %{state | next_shared: state.next_shared + 1}

    case write_shared(name, binary) do
      :ok ->
        command(state, <<3, byte_size(binary)::64, name::binary>>)
        {:ok, %{state | shared: MapSet.put(state.shared, name)}}

      {:error, _reason} ->
        command(state, [2, binary])
        {:ok, state}
    end
  end

  defp send_stream(state, binary) do
    command(state, [2, binary])
    {:ok, state}
  end

  defp write_shared(name, binary) do
    if Native.load_error(),
      do: {:error, :not_loaded},
      else: Native.write_shared_memory(name, binary)
  end

  defp command(%{port: port}, data), do: Port.command(port, data)

  defp own(state, pid, key) do
    {monitor, keys} =
      Map.get_lazy(state.owners, pid, fn -> {Process.monitor(pid), MapSet.new()} end)

    %{state | owners: Map.put(state.owners, pid, {monitor, MapSet.put(keys, key)})}
  end

  defp release_object(state, {kind, id} = key) do
    owners =
      Map.new(state.owners, fn {pid, {monitor, keys}} ->
        {pid, {monitor, MapSet.delete(keys, key)}}
      end)

    state = %{state | owners: owners, record: Record.release(state.record, kind, id)}

    if state.port,
      do: command(state, [2, IO.iodata_to_binary(Stream.encode([{drop(kind), id}]))])

    state
  end

  defp next_tag(state), do: {state.next_tag + 1, %{state | next_tag: state.next_tag + 1}}

  defp capture_result({:capture, width, height, {:shared_memory, name}}),
    do: {:ok, %{width: width, height: height, shared_memory: name}}

  defp capture_result({:capture, width, height, pixels}),
    do: {:ok, %{width: width, height: height, pixels: pixels}}

  defp capture_result({:capture, {:error, reason}}), do: {:error, reason}
  defp capture_result({:capture, :error}), do: {:error, :capture_failed}
  defp capture_result({:error, reason}), do: {:error, reason}

  defp backend(nil) do
    case CauldronGPU.backends() do
      [first | _] -> {:ok, first}
      [] -> {:error, "no backend built"}
    end
  end

  defp backend(name) when name in [:metal, :vulkan], do: {:ok, name}

  defp executable do
    architecture = to_string(:erlang.system_info(:system_architecture))

    Path.join([
      :code.priv_dir(:cauldron_gpu),
      "native",
      architecture,
      "cauldron_gpu_host" <> executable_suffix(:os.type())
    ])
  end

  defp executable_suffix({:win32, _}), do: ".exe"
  defp executable_suffix(_), do: ""

  defp drop(:mesh), do: :drop_mesh
  defp drop(:texture), do: :drop_texture
  defp drop(:material), do: :drop_material
  defp flag(true), do: 1
  defp flag(false), do: 0
end
