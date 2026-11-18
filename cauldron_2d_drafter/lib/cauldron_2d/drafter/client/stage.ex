defmodule Cauldron2D.Drafter.Client.Stage do
  @moduledoc """
  A graphics card drawing a client's scenes: a `CauldronGPU.Host` renderer, offscreen for
  pictures shown in the pane or in a window of its own, and the cache a scene's `:gpu`
  function keeps between ticks.

      {:ok, stage} = Stage.start(:pane, title: "Quake", fps: 30)
      # once {Stage, ^stage, :ready} has arrived:
      {:ok, raster} = Stage.picture(stage, scene.gpu, {960, 600}, 1.0, false)

  In the pane the renderer draws at the stage's frame rate (`:fps`, `rate/2`) and streams
  every frame back (`CauldronGPU.Host.stream/2`); `picture/5` sends the scene and answers
  the newest frame not yet answered, waiting for the next when there is none. A frame
  replaced before it is asked for is handed back to the renderer unused. Asked with
  `shared?` true, frames come as POSIX shared-memory objects
  (`%{shared_memory: name, width: w, height: h}`, as `Cauldron2D.Drafter.Surface` takes
  them) instead of pixels.

  The process that starts a stage is its owner and receives `{Stage, stage, message}`:

    * `:ready` — the renderer has opened; `picture/5` and `draw/2` may be used
    * `{:failed, reason}` — it did not open, or stopped and could not be started again;
      the stage has stopped
    * `{:input, event}` — a key pressed or released in the window, or the mouse moved,
      pressed or scrolled there, as a terminal's drafter event
      (`Cauldron2D.Drafter.Client.WindowKeys`, `Cauldron2D.Drafter.Client.WindowMouse`).
      While `pointer/2` has said the pointer steers, the first click in the window
      captures it (the window's relative mouse mode) and is not passed on; the window
      losing focus, or `pointer/2` saying it no longer steers, lets it go
    * `:closed` — the window was closed; the stage has stopped
    * `{:drawn, count}` — once a second while the renderer is open: the pictures handed
      to the pane in the second before, or in a window the frames the renderer drew

  A renderer process that exits is started again with the scene it had, so the cache
  stays good. The stage stops when its owner exits.
  """

  use GenServer

  require Logger

  @compile {:no_warn_undefined, [CauldronGPU.Host]}

  alias Cauldron2D.Drafter.Client.{WindowKeys, WindowMouse}
  alias Cauldron2D.Raster

  @type t :: pid()
  @type mode :: :pane | :window
  @type gpu :: (term(), term(), {pos_integer(), pos_integer()}, number() -> {list(), term()})

  @pane_size {640, 360}
  @window_size {1280, 720}
  @picture_timeout 5_000
  @frame_wait_ms 250
  @count_ms 1_000
  @shared_slots 4
  @ahead 2

  @doc "Whether this build has `CauldronGPU` and a renderer to open."
  @spec available?() :: boolean()
  def available?,
    do: Code.ensure_loaded?(CauldronGPU.Host) and CauldronGPU.Host.backends() != []

  @doc """
  Starts a stage owned by the caller, opening its renderer in the background. Options:
  `:title` (the window's title), `:fps` (how often the pane's renderer draws; default
  30).
  """
  @spec start(mode(), keyword()) :: {:ok, t()} | {:error, term()}
  def start(mode, opts \\ []) when mode in [:pane, :window] do
    if available?(),
      do: GenServer.start(__MODULE__, {mode, self(), opts}),
      else: {:error, "no graphics card renderer in this build"}
  end

  @doc """
  Sends the scene `gpu` describes, drawn at `size` pixels, and answers the newest frame:
  a raster, or with `shared?` a frame in POSIX shared memory when the stream has one.
  When no frame arrives within a moment the scene is captured once instead.
  `{:error, reason}` when the renderer is not ready, the function raises, or nothing
  comes back in time.
  """
  @spec picture(t(), gpu(), {pos_integer(), pos_integer()}, number(), boolean()) ::
          {:ok,
           Raster.t() | %{shared_memory: String.t(), width: pos_integer(), height: pos_integer()}}
          | {:error, term()}
  def picture(stage, gpu, size, aspect, shared?) do
    GenServer.call(stage, {:picture, gpu, size, aspect, shared?}, @picture_timeout + 1_000)
  catch
    :exit, reason -> {:error, reason}
  end

  @doc "Sets how many frames a second the pane's renderer draws."
  @spec rate(t(), pos_integer()) :: :ok
  def rate(stage, fps), do: GenServer.cast(stage, {:rate, fps})

  @doc "Sends the scene `gpu` describes to the window. Ticks sent faster than they are drawn are dropped for the newest."
  @spec draw(t(), gpu()) :: :ok
  def draw(stage, gpu), do: GenServer.cast(stage, {:draw, gpu})

  @doc "Whether the pointer steers the game, so that a click in the window captures it."
  @spec pointer(t(), boolean()) :: :ok
  def pointer(stage, steers?), do: GenServer.cast(stage, {:pointer, steers?})

  @doc "Stops the stage, closing its renderer."
  @spec stop(t()) :: :ok
  def stop(stage) do
    GenServer.stop(stage)
  catch
    :exit, _reason -> :ok
  end

  @impl true
  def init({mode, owner, opts}) do
    Process.monitor(owner)

    {:ok,
     %{
       mode: mode,
       owner: owner,
       title: Keyword.get(opts, :title, "cauldron"),
       host: nil,
       size: if(mode == :window, do: @window_size, else: @pane_size),
       cache: nil,
       modifiers: [],
       mouse: WindowMouse.new(),
       pointer?: false,
       drawn: 0,
       frames: 0,
       fps: Keyword.get(opts, :fps, 30),
       stream: nil,
       frame: nil,
       waiting: nil,
       names: shared_names()
     }, {:continue, :open}}
  end

  @impl true
  def handle_continue(:open, state) do
    {width, height} = state.size

    case CauldronGPU.Host.open(
           window: state.mode == :window,
           title: state.title,
           width: width,
           height: height,
           events: self()
         ) do
      {:ok, host} ->
        tell(state, :ready)
        Process.send_after(self(), :count, @count_ms)
        {:noreply, %{state | host: host}}

      {:error, reason} ->
        tell(state, {:failed, reason})
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_call({:picture, _gpu, _size, _aspect, _shared?}, _from, %{host: nil} = state),
    do: {:reply, {:error, :not_ready}, state}

  def handle_call({:picture, gpu, size, aspect, shared?}, from, state) do
    state = state |> sized(size) |> streaming(if(shared?, do: :shared, else: :pixels))

    case described(state, gpu, aspect) do
      {:ok, %{frame: nil} = state} ->
        timer = Process.send_after(self(), :frame_wait, @frame_wait_ms)
        {:noreply, %{state | waiting: {from, timer}}}

      {:ok, state} ->
        {:reply, {:ok, handed(state, state.frame)}, taken(state)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:pointer, steers?}, state), do: {:noreply, pointed(state, steers?)}

  def handle_cast({:rate, fps}, %{fps: fps} = state), do: {:noreply, state}

  def handle_cast({:rate, fps}, state),
    do: {:noreply, %{state | fps: fps} |> restream()}

  def handle_cast({:draw, _gpu}, %{host: nil} = state), do: {:noreply, state}

  def handle_cast({:draw, gpu}, state) do
    case described(state, newest(gpu), 1.0) do
      {:ok, state} -> {:noreply, state}
      {:error, _reason} -> {:noreply, state}
    end
  end

  @impl true
  def handle_info({:cauldron_gpu, _id, {:key, _direction, _name, _repeat?} = event}, state) do
    Enum.each(WindowKeys.events(event, state.modifiers), &tell(state, {:input, &1}))
    {:noreply, %{state | modifiers: WindowKeys.modifiers(event, state.modifiers)}}
  end

  def handle_info({:cauldron_gpu, _id, {:resized, width, height}}, state)
      when width > 0 and height > 0,
      do: {:noreply, %{state | size: {width, height}}}

  def handle_info(
        {:cauldron_gpu, _id, {:mouse_button, :down, 1, _x, _y}},
        %{mode: :window, pointer?: true, mouse: %{captured?: false}} = state
      ) do
    CauldronGPU.Host.relative_mouse(state.host, true)
    {:noreply, %{state | mouse: WindowMouse.capture(state.mouse)}}
  end

  def handle_info({:cauldron_gpu, _id, {kind, _, _, _, _} = event}, state)
      when kind in [:mouse_motion, :mouse_button],
      do: {:noreply, moused(state, event)}

  def handle_info({:cauldron_gpu, _id, {:mouse_wheel, _dx, _dy} = event}, state),
    do: {:noreply, moused(state, event)}

  def handle_info({:cauldron_gpu, _id, {:focus, false}}, state) do
    Enum.each(state.modifiers, &release_modifier(state, &1))
    {:noreply, %{released(state) | modifiers: []}}
  end

  def handle_info({:cauldron_gpu, _id, :close_requested}, state) do
    tell(state, :closed)
    {:stop, :normal, state}
  end

  def handle_info({:cauldron_gpu, _id, :renderer_exited}, state) do
    case CauldronGPU.Host.restart(state.host) do
      :ok ->
        {:noreply, state}

      {:error, reason} ->
        tell(state, {:failed, reason})
        {:stop, :normal, state}
    end
  end

  def handle_info({:cauldron_gpu, _id, {:error, message}}, state) do
    Logger.error("#{inspect(__MODULE__)} renderer rejected a change: #{message}")
    {:noreply, state}
  end

  def handle_info({:cauldron_gpu, _id, {:frame, _width, _height, _pixels} = frame}, state),
    do: {:noreply, arrived(state, frame)}

  def handle_info({:cauldron_gpu, _id, {:frame, _failure}}, state) do
    CauldronGPU.Host.frame_shown(state.host)
    {:noreply, state}
  end

  def handle_info(:frame_wait, %{waiting: {from, _timer}} = state) do
    GenServer.reply(from, captured(state))
    {:noreply, %{state | waiting: nil}}
  end

  def handle_info(:frame_wait, state), do: {:noreply, state}

  def handle_info(:count, state) do
    Process.send_after(self(), :count, @count_ms)
    {:noreply, counted(state)}
  end

  def handle_info({:DOWN, _ref, :process, owner, _reason}, %{owner: owner} = state),
    do: {:stop, :normal, state}

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{host: nil}), do: :ok

  def terminate(_reason, %{host: host} = state) do
    CauldronGPU.Host.close(host)
    Enum.each(state.names, &CauldronGPU.Host.remove_shared_memory/1)
  end

  defp sized(%{size: size} = state, size), do: state

  defp sized(state, {width, height} = size) do
    case CauldronGPU.Host.resize(state.host, width, height) do
      :ok -> %{state | size: size}
      {:error, _reason} -> state
    end
  end

  defp described(state, gpu, aspect) do
    {changes, cache} = gpu.(state.host, state.cache, state.size, aspect)

    case CauldronGPU.Host.submit(state.host, changes) do
      :ok -> {:ok, %{state | cache: cache}}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error ->
      report(error, __STACKTRACE__)
      {:error, error}
  end

  defp newest(gpu) do
    receive do
      {:"$gen_cast", {:draw, newer}} -> newest(newer)
    after
      0 -> gpu
    end
  end

  defp streaming(%{stream: mode} = state, mode), do: state
  defp streaming(state, mode), do: restream(%{state | stream: mode})

  defp restream(%{stream: nil} = state), do: state

  defp restream(state) do
    CauldronGPU.Host.stop_stream(state.host)
    names = if state.stream == :shared, do: state.names, else: []
    CauldronGPU.Host.stream(state.host, shared_memory: names, ahead: @ahead, fps: state.fps)
    %{state | frame: nil}
  end

  defp arrived(%{waiting: {from, timer}} = state, frame) do
    Process.cancel_timer(timer)
    GenServer.reply(from, {:ok, handed(state, frame)})
    %{taken(state) | waiting: nil}
  end

  defp arrived(%{frame: nil} = state, frame), do: %{state | frame: frame}

  defp arrived(state, frame) do
    CauldronGPU.Host.frame_shown(state.host)
    %{state | frame: frame}
  end

  defp handed(_state, {:frame, width, height, {:shared_memory, name}}),
    do: %{shared_memory: name, width: width, height: height}

  defp handed(_state, {:frame, width, height, pixels}),
    do: Raster.from_rgba(width, height, pixels)

  defp taken(state) do
    CauldronGPU.Host.frame_shown(state.host)
    %{state | frame: nil, drawn: state.drawn + 1}
  end

  defp captured(state) do
    case CauldronGPU.Host.capture(state.host, @picture_timeout) do
      {:ok, frame} -> {:ok, Raster.from_rgba(frame.width, frame.height, frame.pixels)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp shared_names do
    stage = :erlang.unique_integer([:positive])
    for slot <- 1..@shared_slots, do: "/cgs#{System.pid()}_#{stage}_#{slot}"
  end

  defp counted(%{mode: :window} = state) do
    frames = CauldronGPU.Host.frames(state.host)
    tell(state, {:drawn, max(frames - state.frames, 0)})
    %{state | frames: frames}
  end

  defp counted(state) do
    tell(state, {:drawn, state.drawn})
    %{state | drawn: 0}
  end

  defp pointed(state, true), do: %{state | pointer?: true}
  defp pointed(state, false), do: %{released(state) | pointer?: false}

  defp released(%{mouse: %{captured?: true}, host: host} = state) when host != nil do
    CauldronGPU.Host.relative_mouse(host, false)
    %{state | mouse: WindowMouse.release(state.mouse)}
  end

  defp released(state), do: %{state | mouse: WindowMouse.release(state.mouse)}

  defp moused(state, event) do
    {events, mouse} = WindowMouse.events(state.mouse, event, state.modifiers)
    Enum.each(events, &tell(state, {:input, &1}))
    %{state | mouse: mouse}
  end

  defp release_modifier(state, modifier),
    do: tell(state, {:input, {:key_up, modifier_key(modifier), []}})

  defp modifier_key(:shift), do: :left_shift
  defp modifier_key(:ctrl), do: :left_control
  defp modifier_key(:alt), do: :left_alt

  defp tell(state, message), do: send(state.owner, {__MODULE__, self(), message})

  defp report(error, stacktrace) do
    message = Exception.message(error)
    seen = Process.get(__MODULE__, MapSet.new())

    unless MapSet.member?(seen, message) do
      Process.put(__MODULE__, MapSet.put(seen, message))

      Logger.error("""
      #{inspect(__MODULE__)} could not describe the scene for the graphics card, so the \
      game's own picture is drawn instead: #{message}
      #{Exception.format_stacktrace(stacktrace)}\
      """)
    end
  end
end
