defmodule Cauldron2D.Audio do
  @moduledoc """
  Sound effects and music for one listener, over one `TuningFork` stage.

  A game emits the events that happened — `:brick`, `{:explosion, {x, y}}` — and supplies
  a function from an event's name to the voice it makes. Each instance is a process; a
  game with one player uses the default one, a served game starts one per session with a
  sink that reaches that player.

      Cauldron2D.Audio.start(sounds: &MyGame.Sound.voice/1, sfx: 0.85, music: 0.35)
      Cauldron2D.Audio.play([:brick, {:wall, {12.0, 3.0}}])
      Cauldron2D.Audio.bed(Cauldron2D.Audio, "mygame/level-3", fn -> MyGame.Music.render(3) end)

      {:ok, audio} = Cauldron2D.Audio.start_link(name: nil, sink: {TuningFork.Sink.Pulse, server: "tcp:127.0.0.1:<port>"})
      Cauldron2D.Audio.listener(audio, {player_x, player_y})
      Cauldron2D.Audio.play(audio, events)

  Every function takes the instance first. The ones with a fixed number of arguments
  default it to the process registered as `Cauldron2D.Audio`; `play_piece/4` and `bed/4`
  take it explicitly.

  ## Rules

    * `start/1` or `start_link/1` comes first. It records the sound table and opens the
      stage; when this machine has no sound the stage stays silent and every call is a
      no-op returning `:ok`. `on?/1` reports which.
    * An event is any term the table knows, or `{event, {x, y}}` placing it. With a listener set, a placed event is
      scaled by its distance — full within one tile, silent at `:earshot` tiles — and
      panned by its side; an unplaced one plays at full level, centred.
    * Effects and music have separate levels, set by `levels/3`.
    * Beds are keyed by a string. A render runs once, in a task, and is kept in memory and
      on disk via `TuningFork.Cache`; a bed finishing after another key was asked for is
      dropped. A render that raises is logged and never plays.
    * `clear_bed/1` and `resume_bed/1` cover both playback modes.
    * Music with sections and layers is `Cauldron2D.Audio.Music`.
  """

  use GenServer

  require Logger

  alias Cauldron2D.Audio.{Music, Rendered}
  alias TuningFork.{Cache, Mixer, Stage, Voice}

  @bed {__MODULE__, :bed}

  @type instance :: GenServer.server()
  @type event :: term() | {term(), {number(), number()}}
  @type sound :: Voice.t() | [{non_neg_integer(), Voice.t()}] | nil

  @doc """
  Start the default instance, registered as `Cauldron2D.Audio`, replacing one already
  running. Returns whether sound is possible.

  Takes the options of `start_link/1`.
  """
  @spec start(keyword()) :: boolean()
  def start(opts \\ []) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end

    {:ok, pid} = start_link(Keyword.put(opts, :name, __MODULE__))
    on?(pid)
  end

  @doc """
  Start an instance linked to the caller.

  The instance lives as long as the caller: when the caller exits, for any reason, the
  instance stops, and a stage it started stops with it, closing its sink. A stage handed
  in with `:stage` is left running.

  ## Options

    * `:name` — a registered name, or `nil` for none. Default `Cauldron2D.Audio`
    * `:sounds` — a function from an event name to a `t:sound/0`. Default: silent
    * `:sink` — a `TuningFork.Sink` module, or `{module, sink_opts}`. Default:
      `TuningFork.Sink.Speaker` when that package is present, else nothing plays
    * `:stage` — an already running stage to use instead of starting one
    * `:mode` — the default for `play_piece/4`, `:live` or `:rendered`. Default `:live`
    * `:sfx`, `:music` — levels 0.0 to 1.0. Default `default_levels/0`
    * `:earshot` — tiles at which a placed event falls silent. Default `30.0`
    * `:music_dir` — the directory rendered music is kept in; a game's is
      `Cauldron2D.Client.Game.music_dir/1`. Default `TuningFork.Cache.dir/0`
    * `:static_music` — play the first section cued and nothing after, rendered once
      and looped; see `Cauldron2D.Audio.Music`. Default `false`
    * `:parallel` — synthesise the music's voices on every core, for one player on a
      machine of their own (the terminal, the desktop); a server with many players
      leaves it off. Default `false`
    * `:rate`, `:channels`, `:chunk`, `:voices`, `:lead`, `:fx` — the stage's settings.
      Default `44_100`, `2`, `256`, `12`, `2048`, `[]`: the sink is kept 2048 frames
      (46 ms at 44.1 kHz) ahead of playback, in a ring of four times that, so a few
      milliseconds of scheduling jitter never leave it empty
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @sfx 0.85
  @music 0.35

  @doc "The effects and music levels an instance starts with: `%{sfx: 0.85, music: 0.35}`."
  @spec default_levels() :: %{sfx: float(), music: float()}
  def default_levels, do: %{sfx: @sfx, music: @music}

  @doc "Whether a stage with somewhere to play is running."
  @spec on?(instance()) :: boolean()
  def on?(audio \\ __MODULE__), do: alive?(audio) and GenServer.call(audio, :on?)

  @doc "Where the listener is, for placed events."
  @spec listener(instance(), {number(), number()} | nil) :: :ok
  def listener(audio \\ __MODULE__, pos), do: cast(audio, {:listener, pos})

  @doc "Sound `events` in order through the table given at start: a name — any term — or `{name, {x, y}}` placed against the listener; one the table answers `nil` for, or has no clause for, is silent."
  @spec play(instance(), [event()]) :: :ok
  def play(audio \\ __MODULE__, events), do: cast(audio, {:play, events})

  @doc "Sound `voice` directly, scaled by the effects level."
  @spec play_voice(instance(), Voice.t()) :: :ok
  def play_voice(audio \\ __MODULE__, %Voice{} = voice), do: cast(audio, {:play_voice, voice})

  @doc "Set the effects and music levels, each 0.0 to 1.0."
  @spec levels(instance(), number(), number()) :: :ok
  def levels(audio \\ __MODULE__, sfx, music), do: cast(audio, {:levels, sfx / 1, music / 1})

  @doc """
  Play `score` on a loop, live or from a render, under `key`.

  ## Options

    * `:mode` — `:live` or `:rendered`, overriding the instance's default
    * `:render` — a zero-arity function returning the PCM to loop in `:rendered` mode.
      Default: renders `score` at the stage's rate
    * `:fingerprint` — keys the on-disk render together with `key`. Default `"0"`
  """
  @spec play_piece(instance(), String.t(), TuningFork.Score.t(), keyword()) :: :ok
  def play_piece(audio, key, %TuningFork.Score{} = score, opts \\ []) do
    cast(audio, {:play_piece, key, score, opts})
  end

  @doc "Loop the PCM `render` produces under `key`; see the module rules for caching."
  @spec bed(instance(), String.t(), (-> binary()), keyword()) :: :ok
  def bed(audio, key, render, opts \\ []) when is_function(render, 0) do
    cast(audio, {:bed, key, render, opts})
  end

  @doc "Stop the music, live or rendered."
  @spec clear_bed(instance()) :: :ok
  def clear_bed(audio \\ __MODULE__), do: cast(audio, :clear_bed)

  @doc "Start the music last asked for again."
  @spec resume_bed(instance()) :: :ok
  def resume_bed(audio \\ __MODULE__), do: cast(audio, :resume_bed)

  @doc "The key last given to `bed/4` or `play_piece/4`, or `nil`."
  @spec playing(instance()) :: String.t() | nil
  def playing(audio \\ __MODULE__), do: if(alive?(audio), do: GenServer.call(audio, :playing))

  @doc "Silence everything, or restore it."
  @spec mute(instance(), boolean()) :: :ok
  def mute(audio \\ __MODULE__, muted?), do: cast(audio, {:mute, muted?})

  @doc "The stage this instance plays through, or `nil`."
  @spec stage(instance()) :: pid() | nil
  def stage(audio \\ __MODULE__), do: if(alive?(audio), do: GenServer.call(audio, :stage))

  @doc false
  def rate(audio), do: GenServer.call(audio, :rate)

  defp cast(audio, message) do
    if alive?(audio), do: GenServer.cast(audio, message)
    :ok
  end

  defp alive?(pid) when is_pid(pid), do: Process.alive?(pid)
  defp alive?(name) when is_atom(name), do: Process.whereis(name) != nil
  defp alive?({:via, _, _} = via), do: GenServer.whereis(via) != nil

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)
    rate = Keyword.get(opts, :rate, 44_100)
    channels = Keyword.get(opts, :channels, 2)
    {stage, playable?} = open_stage(opts, rate, channels)

    state = %{
      stage: stage,
      own_stage?: not Keyword.has_key?(opts, :stage),
      playable?: playable?,
      rate: rate,
      channels: channels,
      sounds: Keyword.get(opts, :sounds, fn _event -> nil end),
      mode: Keyword.get(opts, :mode, :live),
      sfx: Keyword.get(opts, :sfx, @sfx) / 1,
      music: Keyword.get(opts, :music, @music) / 1,
      earshot: Keyword.get(opts, :earshot, 30.0) / 1,
      parallel: Keyword.get(opts, :parallel, false),
      music_dir: Keyword.get(opts, :music_dir, Cache.dir()),
      listener: nil,
      playing: nil,
      piece: :rendered,
      music_director: Music.new(static: Keyword.get(opts, :static_music, false))
    }

    if stage, do: Stage.bed_gain(stage, state.music)
    {:ok, state}
  end

  defp open_stage(opts, rate, channels) do
    case Keyword.fetch(opts, :stage) do
      {:ok, stage} ->
        {stage, true}

      :error ->
        case sink(opts) do
          nil -> {nil, false}
          {module, sink_opts} -> start_stage(module, sink_opts, opts, rate, channels)
        end
    end
  end

  defp sink(opts) do
    case Keyword.get(opts, :sink) do
      nil -> if Code.ensure_loaded?(TuningFork.Sink.Speaker), do: {TuningFork.Sink.Speaker, []}
      {module, sink_opts} -> {module, sink_opts}
      module when is_atom(module) -> {module, []}
    end
  end

  defp start_stage(module, sink_opts, opts, rate, channels) do
    lead = Keyword.get(opts, :lead, 2048)

    result =
      Stage.start_link(
        name: nil,
        sink: module,
        rate: rate,
        channels: channels,
        chunk: Keyword.get(opts, :chunk, 256),
        voices: Keyword.get(opts, :voices, 12),
        sink_opts: Keyword.merge([lead: lead, buffer: 4 * lead], sink_opts),
        fx: Keyword.get(opts, :fx, [])
      )

    with {:ok, pid} <- result,
         true <- :sys.get_state(pid).sink != TuningFork.Sink.Silent do
      {pid, true}
    else
      false ->
        {:ok, pid} = result
        GenServer.stop(pid)
        {nil, false}

      {:error, _reason} ->
        {nil, false}
    end
  end

  @impl GenServer
  def handle_call(:on?, _from, state), do: {:reply, state.stage != nil and state.playable?, state}
  def handle_call(:playing, _from, state), do: {:reply, state.playing, state}
  def handle_call(:stage, _from, state), do: {:reply, state.stage, state}
  def handle_call(:rate, _from, state), do: {:reply, {state.rate, state.channels}, state}

  def handle_call({:music, request}, _from, state) do
    {reply, director} = Music.handle(request, state.music_director, self(), state)
    {:reply, reply, %{state | music_director: director}}
  end

  @impl GenServer
  def handle_cast(_message, %{stage: nil} = state), do: {:noreply, state}

  def handle_cast({:listener, pos}, state), do: {:noreply, %{state | listener: pos}}

  def handle_cast({:play, events}, state) do
    Enum.each(events, fn event -> sound(state, event) end)
    {:noreply, state}
  end

  def handle_cast({:play_voice, voice}, state) do
    Stage.play_pcm(state.stage, rendered(state, voice, state.sfx, 0.0))
    {:noreply, state}
  end

  def handle_cast({:levels, sfx, music}, state) do
    Stage.bed_gain(state.stage, music)
    state = %{state | sfx: sfx, music: music}
    {:ok, director} = Music.handle({:level, music}, state.music_director, self(), state)
    {:noreply, %{state | music_director: director}}
  end

  def handle_cast({:play_piece, key, score, opts}, state) do
    mode = resolve_mode(Keyword.get(opts, :mode), state.mode)

    render =
      Keyword.get(opts, :render, fn ->
        TuningFork.Score.render(score, state.rate, channels: state.channels)
      end)

    state = %{state | playing: key, piece: if(mode == :live, do: {:live, score}, else: :rendered)}

    case mode do
      :live -> Stage.start_score(state.stage, score, loop: true)
      :rendered -> play_stored_or_build(state, key, render, opts)
    end

    {:noreply, state}
  end

  def handle_cast({:bed, key, render, opts}, state) do
    state = %{state | playing: key, piece: :rendered}
    play_stored_or_build(state, key, render, opts)
    {:noreply, state}
  end

  def handle_cast(:clear_bed, state) do
    Stage.clear_bed(state.stage)
    Stage.stop_score(state.stage)
    {:noreply, state}
  end

  def handle_cast(:resume_bed, state) do
    resume(state)
    {:noreply, state}
  end

  def handle_cast({:mute, muted?}, state) do
    Stage.mute(state.stage, muted?)

    case state.piece do
      {:live, _score} -> :ok
      :rendered -> if muted?, do: Stage.clear_bed(state.stage), else: resume(state)
    end

    {:noreply, state}
  end

  def handle_cast({:music, request}, state) do
    {_reply, director} = Music.handle(request, state.music_director, self(), state)
    {:noreply, %{state | music_director: director}}
  end

  @impl GenServer
  def handle_info({:rendered, key, pcm}, state) do
    :persistent_term.put({@bed, key}, pcm)
    if state.playing == key, do: Stage.bed(state.stage, pcm)
    {:noreply, state}
  end

  def handle_info({:music, message}, state) do
    director = Music.handle_info(message, state.music_director, self(), state)
    {:noreply, %{state | music_director: director}}
  end

  def handle_info({:EXIT, stage, _reason}, %{stage: stage} = state),
    do: {:stop, :normal, %{state | stage: nil}}

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}
  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, %{own_stage?: true, stage: stage}) when is_pid(stage) do
    if Process.alive?(stage), do: GenServer.stop(stage)
    :ok
  catch
    :exit, _already_going_down -> :ok
  end

  def terminate(_reason, _state), do: :ok

  defp resolve_mode(override, default) do
    case System.get_env("CAULDRON_AUDIO") do
      "rendered" -> :rendered
      "live" -> :live
      _unset -> override || default
    end
  end

  defp play_stored_or_build(state, key, render, opts) do
    case :persistent_term.get({@bed, key}, nil) do
      nil -> build(key, render, Keyword.get(opts, :fingerprint, "0"), self(), state.music_dir)
      pcm -> Stage.bed(state.stage, pcm)
    end
  end

  defp build(key, render, fingerprint, owner, dir) do
    Task.start(fn ->
      try do
        send(owner, {:rendered, key, Cache.fetch(key, fingerprint, render, dir: dir)})
      rescue
        error ->
          Logger.error("""
          rendering #{inspect(key)} failed, so it will never play: #{Exception.message(error)}
          #{Exception.format_stacktrace(__STACKTRACE__)}\
          """)
      end
    end)
  end

  defp resume(%{piece: {:live, score}} = state),
    do: Stage.start_score(state.stage, score, loop: true)

  defp resume(%{piece: :rendered, playing: key} = state) when is_binary(key) do
    case :persistent_term.get({@bed, key}, nil) do
      nil -> :ok
      pcm -> Stage.bed(state.stage, pcm)
    end
  end

  defp resume(_state), do: :ok

  defp sound(state, {name, {x, y}}) when is_number(x) and is_number(y) do
    case placement(state, {x, y}) do
      :silent -> :ok
      {gain, pan} -> emit(state, lookup(state, name), state.sfx * gain, pan)
    end
  end

  defp sound(state, name), do: emit(state, lookup(state, name), state.sfx, 0.0)

  defp lookup(state, name) do
    state.sounds.(name)
  rescue
    FunctionClauseError -> nil
  end

  defp placement(%{listener: nil}, _pos), do: {1.0, 0.0}

  defp placement(%{listener: {lx, ly}, earshot: earshot}, {x, y}) do
    dx = x - lx
    dy = y - ly
    distance = :math.sqrt(dx * dx + dy * dy)

    cond do
      distance >= earshot -> :silent
      distance <= 1.0 -> {1.0, 0.0}
      true -> {1.0 - (distance - 1.0) / (earshot - 1.0), max(-1.0, min(1.0, dx / earshot))}
    end
  end

  defp emit(_state, nil, _gain, _pan), do: :ok

  defp emit(state, %Voice{} = voice, gain, pan),
    do: Stage.play_pcm(state.stage, rendered(state, voice, gain, pan))

  defp emit(state, run, gain, pan) when is_list(run) do
    stage = state.stage

    Enum.each(run, fn {delay, voice} ->
      after_delay(stage, rendered(state, voice, gain, pan), delay)
    end)
  end

  defp rendered(state, voice, gain, pan) do
    voice
    |> Rendered.fetch(state.rate)
    |> Mixer.scale(voice.gain * gain)
    |> Mixer.pan(max(-1.0, min(1.0, voice.pan + pan)), state.channels)
  end

  defp after_delay(stage, pcm, delay) do
    spawn(fn ->
      reference = Process.monitor(stage)

      receive do
        {:DOWN, ^reference, :process, _pid, _reason} -> :ok
      after
        delay -> Stage.play_pcm(stage, pcm)
      end
    end)
  end
end
