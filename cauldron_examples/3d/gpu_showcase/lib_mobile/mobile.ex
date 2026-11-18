defmodule GpuShowcase.Mobile do
  @moduledoc """
  The showcase courtyard on a phone or tablet, drawn by `cauldron_gpu` into the app's
  graphics surface (`CauldronNative.gpu_surface/0`: Metal on iOS, Vulkan on Android).

  A thumb on the left half of the screen sets a stick down where it lands and moves the
  camera along the way it looks; a finger dragged on the right half turns it. A game
  controller's left stick moves and its right stick turns. The ring of crates turns
  while the app is on screen; the renderer follows the screen when it turns or resizes,
  closes when the app leaves the screen, and opens again when it comes back.
  """

  use GenServer

  alias Cauldron3D.Scene.{Camera, Quat}
  alias GpuShowcase.Courtyard

  @tick_ms 33
  @speed 0.18
  @look 0.004
  @stick_points 56
  @deadzone 0.2

  @doc "Start the showcase."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl GenServer
  def init(_opts) do
    :ok = CauldronNative.subscribe(self())
    Process.send_after(self(), :tick, @tick_ms)

    {:ok,
     %{
       gpu: nil,
       assets: nil,
       screen: nil,
       tick: 0,
       position: {0.0, 2.2, 9.0},
       yaw: 0.0,
       pitch: -0.15,
       stick: nil,
       looks: %{},
       pad_move: {0.0, 0.0},
       pad_look: {0.0, 0.0},
       active?: true
     }}
  end

  @impl GenServer
  def handle_info({:cauldron_native, :screen, screen}, %{gpu: nil} = state),
    do: {:noreply, %{state | screen: screen} |> opened() |> overlaid()}

  def handle_info({:cauldron_native, :screen, screen}, state) do
    CauldronGPU.resize(state.gpu, screen.width, screen.height)
    {:noreply, overlaid(%{state | screen: screen, stick: nil, looks: %{}})}
  end

  def handle_info({:cauldron_native, :touches, touches}, %{screen: screen} = state)
      when screen != nil,
      do: {:noreply, touches |> Enum.reduce(state, &touched/2) |> overlaid()}

  def handle_info({:cauldron_native, :pad, %{type: :axis, axis: axis, value: value}}, state),
    do: {:noreply, padded(state, axis, value)}

  def handle_info({:cauldron_native, :lifecycle, :active}, state),
    do: {:noreply, %{state | active?: true}}

  def handle_info({:cauldron_native, :lifecycle, _away}, state),
    do: {:noreply, %{closed(state) | active?: false}}

  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @tick_ms)
    {:noreply, ticked(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp ticked(%{active?: false} = state), do: state
  defp ticked(%{screen: nil} = state), do: state
  defp ticked(%{gpu: nil} = state), do: opened(state)
  defp ticked(state), do: drawn(state)

  defp opened(%{screen: screen} = state) do
    with {:ok, surface} <- CauldronNative.gpu_surface(),
         {:ok, gpu} <- CauldronGPU.open(surface: surface, width: screen.width, height: screen.height) do
      assets = Courtyard.upload(gpu)
      CauldronGPU.submit(gpu, Courtyard.scene(assets))
      %{state | gpu: gpu, assets: assets}
    else
      _unavailable -> state
    end
  end

  defp closed(%{gpu: nil} = state), do: state

  defp closed(state) do
    CauldronGPU.close(state.gpu)
    CauldronNative.hide_gpu_surface()
    %{state | gpu: nil, assets: nil}
  end

  defp drawn(state) do
    state = moved(state)
    camera = %Camera{position: state.position, rotation: Quat.yaw_pitch(state.yaw, state.pitch), fov_y: 1.1}
    CauldronGPU.submit(state.gpu, Courtyard.ring(state.assets, state.tick) ++ [camera])
    %{state | tick: state.tick + 1}
  end

  defp moved(state) do
    {right, back} = add2(stick_vector(state), state.pad_move)
    {turn, tilt} = state.pad_look
    state = turned(state, turn * 0.05, tilt * 0.05)
    rotation = Quat.yaw_pitch(state.yaw, state.pitch)
    step = Quat.rotate(rotation, {right, 0.0, back})
    %{state | position: add(state.position, scale(step, @speed))}
  end

  defp stick_vector(%{stick: nil}), do: {0.0, 0.0}

  defp stick_vector(%{stick: %{origin: {ox, oy}, at: {x, y}}, screen: screen}) do
    radius = @stick_points * screen.scale
    {dx, dy} = {(x - ox) / radius, (y - oy) / radius}
    length = :math.sqrt(dx * dx + dy * dy)

    cond do
      length < @deadzone -> {0.0, 0.0}
      length > 1.0 -> {dx / length, dy / length}
      true -> {dx, dy}
    end
  end

  defp touched(%{id: id, phase: :began, x: x, y: y}, state) do
    if x < state.screen.width / 2 and state.stick == nil,
      do: %{state | stick: %{id: id, origin: {x, y}, at: {x, y}}},
      else: %{state | looks: Map.put(state.looks, id, {x, y})}
  end

  defp touched(%{id: id, phase: :moved, x: x, y: y}, %{stick: %{id: id} = stick} = state),
    do: %{state | stick: %{stick | at: {x, y}}}

  defp touched(%{id: id, phase: :moved, x: x, y: y}, state) do
    case Map.fetch(state.looks, id) do
      {:ok, {lx, ly}} ->
        %{turned(state, (x - lx) * @look, (y - ly) * @look) | looks: Map.put(state.looks, id, {x, y})}

      :error ->
        state
    end
  end

  defp touched(%{id: id}, %{stick: %{id: id}} = state), do: %{state | stick: nil}
  defp touched(%{id: id}, state), do: %{state | looks: Map.delete(state.looks, id)}

  defp turned(state, across, down),
    do: %{state | yaw: state.yaw - across, pitch: (state.pitch - down) |> max(-1.5) |> min(1.5)}

  defp padded(state, axis, value) do
    value = if abs(value) < @deadzone, do: 0.0, else: value
    {mx, my} = state.pad_move
    {lx, ly} = state.pad_look

    case axis do
      :left_x -> %{state | pad_move: {value, my}}
      :left_y -> %{state | pad_move: {mx, value}}
      :right_x -> %{state | pad_look: {value, ly}}
      :right_y -> %{state | pad_look: {lx, value}}
      _other -> state
    end
  end

  defp overlaid(%{screen: nil} = state), do: state

  defp overlaid(%{screen: screen} = state) do
    radius = @stick_points * screen.scale
    CauldronNative.overlay(stick_shapes(state.stick, radius, screen))
    state
  end

  defp stick_shapes(nil, radius, screen) do
    {_top, _right, bottom, left} = screen.insets
    x = left / 2 + radius * 1.4
    y = screen.height - bottom / 2 - radius * 1.3
    [%{x: x, y: y, radius: radius, alpha: 0.3}, %{x: x, y: y, radius: radius * 0.4, alpha: 0.3}]
  end

  defp stick_shapes(%{origin: {ox, oy}, at: {x, y}}, radius, _screen) do
    {dx, dy} = {x - ox, y - oy}
    length = max(radius, :math.sqrt(dx * dx + dy * dy))
    knob = {ox + dx / length * min(length, radius), oy + dy / length * min(length, radius)}

    [
      %{x: ox, y: oy, radius: radius, alpha: 0.6},
      %{x: elem(knob, 0), y: elem(knob, 1), radius: radius * 0.4, held?: true, alpha: 0.9}
    ]
  end

  defp add({ax, ay, az}, {bx, by, bz}), do: {ax + bx, ay + by, az + bz}
  defp add2({ax, ay}, {bx, by}), do: {ax + bx, ay + by}
  defp scale({x, y, z}, factor), do: {x * factor, y * factor, z * factor}
end
