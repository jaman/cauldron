defmodule Cauldron2D.Net.Audio.Shared do
  @moduledoc """
  One world's music, synthesised once for every session in it: a `Cauldron2D.Audio`
  cued from the world's own state, its PCM sent to every subscriber as
  `{:cauldron_shared_pcm, chunk}`.

      shared = Cauldron2D.Net.Audio.Shared.fetch(world, MyGame.Client, %{rate: 44_100, channels: 2})
      :ok = Cauldron2D.Net.Audio.Shared.subscribe(shared)

  `fetch/3` finds the world's stage or starts it. The cue is the game's `cue/2` of the
  view its `c:Cauldron2D.Game.view/2` gives for the id `:audio`, read from a snapshot
  every two seconds; a game whose `view/2` cannot answer for an id that is not a
  player gets no music from a shared stage. A subscriber is watched; the stage stops a
  few seconds after its last subscriber is gone, and with the world. A rate change
  from `Cauldron2D.Net.Audio` restarts the stage at the new rate.
  """

  use GenServer, restart: :temporary

  alias Cauldron2D.{Audio, World}
  alias Cauldron2D.Audio.Music
  alias Cauldron2D.Client.Game

  @cue_ms 2_000
  @linger_ms 5_000

  @doc "The shared stage of `world` for `game` in `format`, started if it is not running."
  @spec fetch(pid(), module(), %{rate: pos_integer(), channels: 1 | 2}) :: pid()
  def fetch(world, game, format) when is_pid(world) do
    case Registry.lookup(Cauldron2D.Net.Audio.registry(), {:shared, world}) do
      [{pid, _} | _] ->
        pid

      [] ->
        case DynamicSupervisor.start_child(
               Cauldron2D.Net.Audio.supervisor(),
               {__MODULE__, world: world, game: game, format: format}
             ) do
          {:ok, pid} -> pid
          {:error, {:already_started, pid}} -> pid
        end
    end
  end

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "Have the calling process sent the music; it is watched, and its going counts."
  @spec subscribe(pid()) :: :ok
  def subscribe(shared), do: GenServer.call(shared, {:subscribe, self()})

  @doc "Stop being sent the music."
  @spec unsubscribe(pid()) :: :ok
  def unsubscribe(shared), do: GenServer.call(shared, {:unsubscribe, self()})

  @doc "How many processes are sent the music."
  @spec subscribers(pid()) :: non_neg_integer()
  def subscribers(shared), do: GenServer.call(shared, :subscribers)

  @impl GenServer
  def init(opts) do
    world = Keyword.fetch!(opts, :world)
    game = Keyword.fetch!(opts, :game)
    format = Keyword.fetch!(opts, :format)

    case Registry.register(Cauldron2D.Net.Audio.registry(), {:shared, world}, nil) do
      {:ok, _} -> :ok
      {:error, {:already_registered, _}} -> :ok
    end

    Process.flag(:trap_exit, true)
    Process.monitor(world)
    Cauldron2D.Net.Audio.subscribe()
    Process.send_after(self(), :cue, 0)
    Process.send_after(self(), :linger, @linger_ms)

    {:ok,
     %{
       world: world,
       game: game,
       played: World.game(world),
       format: format,
       audio: start_audio(game, format),
       subscribers: %{},
       cue: nil
     }}
  end

  @impl GenServer
  def handle_call({:subscribe, pid}, _from, state) do
    ref = Map.get(state.subscribers, pid) || Process.monitor(pid)
    {:reply, :ok, %{state | subscribers: Map.put(state.subscribers, pid, ref)}}
  end

  def handle_call({:unsubscribe, pid}, _from, state), do: {:reply, :ok, forget(state, pid)}
  def handle_call(:subscribers, _from, state), do: {:reply, map_size(state.subscribers), state}

  @impl GenServer
  def handle_info({:pcm, chunk}, state) do
    for {pid, _ref} <- state.subscribers, do: send(pid, {:cauldron_shared_pcm, chunk})
    {:noreply, state}
  end

  def handle_info(:cue, state) do
    Process.send_after(self(), :cue, @cue_ms)
    {:noreply, cued(state)}
  end

  def handle_info(:linger, %{subscribers: subscribers} = state) when map_size(subscribers) == 0,
    do: {:stop, :normal, state}

  def handle_info(:linger, state), do: {:noreply, state}

  def handle_info({:DOWN, _ref, :process, world, _reason}, %{world: world} = state),
    do: {:stop, :normal, state}

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    state = forget(state, pid)
    if map_size(state.subscribers) == 0, do: Process.send_after(self(), :linger, @linger_ms)
    {:noreply, state}
  end

  def handle_info({:cauldron_audio_rate, rate}, %{format: %{rate: rate}} = state),
    do: {:noreply, state}

  def handle_info({:cauldron_audio_rate, rate}, state) do
    stop_audio(state.audio)
    format = %{state.format | rate: rate}
    {:noreply, %{state | format: format, audio: start_audio(state.game, format), cue: nil}}
  end

  def handle_info({:EXIT, audio, _reason}, %{audio: audio} = state),
    do: {:stop, :normal, %{state | audio: nil}}

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    stop_audio(state.audio)
    :ok
  end

  defp forget(state, pid) do
    case Map.pop(state.subscribers, pid) do
      {nil, _} -> state
      {ref, rest} -> Process.demonitor(ref, [:flush]) && %{state | subscribers: rest}
    end
  end

  defp start_audio(game, format) do
    {:ok, audio} =
      Audio.start_link(
        name: nil,
        sink: {TuningFork.Sink.Process, owner: self()},
        sounds: fn _event -> nil end,
        sfx: 0.0,
        music: Audio.default_levels().music,
        music_dir: Game.music_dir(game),
        rate: format.rate,
        channels: format.channels
      )

    for {name, spec} <- game.music(), do: Music.piece(audio, name, spec)
    audio
  end

  defp stop_audio(nil), do: :ok
  defp stop_audio(audio), do: if(Process.alive?(audio), do: GenServer.stop(audio), else: :ok)

  defp cued(%{audio: nil} = state), do: state

  defp cued(state) do
    cue = world_cue(state)

    cond do
      cue == state.cue -> state
      cue == nil -> Music.stop(state.audio) && %{state | cue: nil}
      true -> Music.cue(state.audio, cue) && %{state | cue: cue}
    end
  end

  defp world_cue(%{world: world, game: game, played: played}) do
    game.cue(played.view(World.snapshot(world), :audio), :arena)
  rescue
    _cannot_view -> nil
  catch
    :exit, _gone -> nil
  end
end
