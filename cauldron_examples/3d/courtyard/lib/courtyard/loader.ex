defmodule Courtyard.Loader do
  @moduledoc """
  Uploads scenes, and the character (`:character`, `Courtyard.Character`), away from the
  drawing. `request/3` starts a scene's `upload/2` the first time it is asked for on a
  target and answers its status from then on: `:loading`, `{:ready, placed}`,
  `{:missing, command}` or `{:failed, reason}`.

  Each scene is uploaded by a process of its own, which stays alive until `forget/2`
  ends it. A target that releases a process's objects when it exits
  (`CauldronGPU.Host`) keeps the scene's objects for that long. `forget/2` drops the
  scene, so asking again uploads it again. `note/0` is the status bar's line about the
  scene asked for last, or `nil` once it is ready.

      Courtyard.Loader.request(target, :atrium, side: 2048)
  """

  use GenServer

  alias Courtyard.Scenes

  @type status ::
          :loading
          | {:ready, Courtyard.Scene.placed()}
          | {:missing, String.t()}
          | {:failed, term()}

  @doc "Starts the loader, registered under its module's name."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "The status of `scene` on `target`, starting its upload when it has none."
  @spec request(Cauldron3D.Scene.Target.t(), Scenes.scene() | :character, keyword()) :: status()
  def request(target, scene, opts \\ []),
    do: GenServer.call(__MODULE__, {:request, target, scene, opts})

  @doc "Forgets `scene` on `target`, ending the process that holds it."
  @spec forget(Cauldron3D.Scene.Target.t(), Scenes.scene() | :character) :: :ok
  def forget(target, scene), do: GenServer.cast(__MODULE__, {:forget, target, scene})

  @doc "The status bar's line about the scene asked for last, or `nil`."
  @spec note() :: String.t() | nil
  def note, do: GenServer.call(__MODULE__, :note)

  @impl true
  def init(:ok), do: {:ok, %{loads: %{}, holders: %{}, last: nil}}

  @impl true
  def handle_call({:request, target, scene, opts}, _from, state) do
    key = {target, scene}
    state = if scene == :character, do: state, else: %{state | last: key}

    case Map.fetch(state.loads, key) do
      {:ok, status} -> {:reply, status, state}
      :error -> {:reply, :loading, start_holder(state, key, opts)}
    end
  end

  def handle_call(:note, _from, %{last: nil} = state), do: {:reply, nil, state}

  def handle_call(:note, _from, %{last: {_target, scene} = key} = state),
    do: {:reply, note(scene, Map.get(state.loads, key)), state}

  @impl true
  def handle_cast({:forget, target, scene}, state) do
    key = {target, scene}
    {holder, holders} = Map.pop(state.holders, key)
    if holder, do: end_holder(holder)
    {:noreply, %{state | holders: holders, loads: Map.delete(state.loads, key)}}
  end

  @impl true
  def handle_info({:uploaded, pid, key, result}, state) do
    case Map.fetch(state.holders, key) do
      {:ok, {^pid, _monitor}} -> {:noreply, uploaded(state, key, status(result))}
      _other -> {:noreply, state}
    end
  end

  def handle_info({:DOWN, monitor, :process, _pid, reason}, state) do
    case Enum.find(state.holders, fn {_key, {_pid, held}} -> held == monitor end) do
      {key, _holder} ->
        loads = Map.update(state.loads, key, {:failed, reason}, &failed(&1, reason))
        {:noreply, %{state | holders: Map.delete(state.holders, key), loads: loads}}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp start_holder(state, {target, scene} = key, opts) do
    loader = self()

    {:ok, pid} =
      Task.Supervisor.start_child(Courtyard.Tasks, fn ->
        hold(loader, key, fn -> uploader(scene).upload(target, opts) end)
      end)

    %{
      state
      | loads: Map.put(state.loads, key, :loading),
        holders: Map.put(state.holders, key, {pid, Process.monitor(pid)})
    }
  end

  defp uploader(:character), do: Courtyard.Character
  defp uploader(scene), do: Scenes.module(scene)

  defp hold(loader, key, upload) do
    loader_down = Process.monitor(loader)
    send(loader, {:uploaded, self(), key, upload.()})

    receive do
      :release -> :ok
      {:DOWN, ^loader_down, :process, _pid, _reason} -> :ok
    end
  end

  defp uploaded(state, key, {:ready, _placed} = status),
    do: %{state | loads: Map.put(state.loads, key, status)}

  defp uploaded(state, key, status) do
    {holder, holders} = Map.pop(state.holders, key)
    end_holder(holder)
    %{state | holders: holders, loads: Map.put(state.loads, key, status)}
  end

  defp end_holder({pid, monitor}) do
    Process.demonitor(monitor, [:flush])
    send(pid, :release)
  end

  defp failed(:loading, reason), do: {:failed, reason}
  defp failed(status, _reason), do: status

  defp status({:ok, placed}), do: {:ready, placed}
  defp status({:error, {:missing, command}}), do: {:missing, command}
  defp status({:error, reason}), do: {:failed, reason}

  defp note(scene, :loading), do: "loading #{Scenes.module(scene).name()}…"

  defp note(scene, {:missing, command}),
    do: "#{Scenes.module(scene).name()} isn't downloaded: run #{command}"

  defp note(scene, {:failed, reason}),
    do: "#{Scenes.module(scene).name()} could not load: #{inspect(reason)}"

  defp note(_scene, _status), do: nil
end
