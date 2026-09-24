defmodule Cauldron2D.Net.Session do
  @moduledoc """
  A browser player's life in a world, as functions over a struct, for a channel process
  to drive: the process calling `join/4` becomes the world's player and gets its frames
  and its audio's PCM as messages.

      {:ok, session, pushes} = Session.join(MyGame.Client, world, "alice", %{settings: %{sfx: 0.8, music: 0.3}})
      {session, pushes} = Session.frame(session, frame_message)
      session = Session.input(session, ["left", "act"], [10.5, 4.0], %{"act" => 0.5})

  Every function that has something for the browser returns pushes, `{event, payload}`
  pairs in the order to send them; a payload that is a binary is a `"pcm"` chunk.

  What a session's sound costs the server is `Cauldron2D.Net.Audio`'s policy: its own
  stage for effects and music, a stage for effects with the world's shared music
  (`Cauldron2D.Net.Audio.Shared`) mixed under them, or none. The chunks reach the
  calling process as `{:pcm, chunk}` from its own stage and `{:cauldron_shared_pcm,
  chunk}` from the shared one; `pcm/2` and `shared_pcm/2` turn them into pushes, and
  `rerate/2` answers `{:cauldron_audio_rate, rate}` from the policy.
  """

  alias Cauldron2D.{Atlas, Audio, Player, World}
  alias Cauldron2D.Audio.Music
  alias Cauldron2D.Client.{Game, Hud}
  alias Cauldron2D.Net.Audio.Shared
  alias Cauldron2D.Net.{Frame, Sheet}
  alias TuningFork.Mixer

  @type push :: {String.t(), map() | binary()}
  @type t :: %__MODULE__{
          game: module(),
          world: GenServer.server(),
          local_world: pid() | nil,
          name: String.t(),
          audio: pid() | nil,
          sheet: Sheet.t(),
          sheet_url: String.t() | {module(), atom()},
          actions: %{String.t() => atom()},
          map_sent?: boolean(),
          cue: term(),
          shared: pid() | nil,
          format: Cauldron2D.Net.Audio.format(),
          music: :own | :static | :shared | :off,
          levels: %{sfx: float(), music: float()},
          music_on?: boolean(),
          queued: :queue.queue(binary())
        }

  defstruct [
    :game,
    :world,
    :local_world,
    :name,
    :audio,
    :sheet,
    :sheet_url,
    :actions,
    map_sent?: false,
    cue: nil,
    shared: nil,
    format: :off,
    music: :off,
    levels: %{sfx: 0.0, music: 0.0},
    music_on?: true,
    queued: :queue.new()
  ]

  @queued_most 4

  @doc """
  Join `world` as `name` from the calling process; `game` implements
  `Cauldron2D.Client.Game`. A `world` of `{module, opts}` is this player's alone,
  started here and stopped by `leave/1`.

  `props` carries `:settings` (`:sfx` and `:music` levels, default
  `Cauldron2D.Audio.default_levels/0`) and
  anything the game's `join_props/1` adds. Options: `:sheet_url`, where the game serves
  the sheet PNG — a path, or `{module, function}` of no arguments called each time a
  sheet is sent, for a path that changes with the sheet (default `"/atlas.png"`);
  `:sink`, a sink for the audio instead of
  `TuningFork.Sink.Process` to this process; `:audio`, the PCM format asked for as
  `%{rate: hertz, channels: 1 | 2}` (default 44 100 Hz stereo — 22 050 Hz mono is a
  quarter of the bytes) or `:off` for no sound; `:policy`, a sound policy instead of
  `Cauldron2D.Net.Audio.policy/0`. The pushes are the sheet, then `"audio"` with the
  format the PCM comes in, or `%{off: true}` when none will. The process is subscribed
  to the game's atlas; `atlas_changed/1` answers the message.
  """
  @spec join(module(), GenServer.server(), String.t(), map(), keyword()) ::
          {:ok, t(), [push()]} | {:error, term()}
  def join(game, world, name, props, opts \\ []) do
    settings = Map.get(props, :settings, %{})
    params = Map.get(props, :params, %{})

    extra =
      Game.optional(
        game,
        :join_props,
        [%{username: name, settings: settings, params: params}],
        %{}
      )

    {world, local} = local_world(world)

    with :ok <-
           joined(
             world,
             local,
             name,
             Map.merge(%{username: name}, Map.merge(extra, Map.drop(props, [:settings, :params])))
           ) do
      Atlas.subscribe(game.atlas())
      sheet = Sheet.cached(game.atlas())
      sheet_url = Keyword.get(opts, :sheet_url, "/atlas.png")
      policy = Keyword.get(opts, :policy, Cauldron2D.Net.Audio.policy())

      asked =
        if Map.get(params, "audio") == false,
          do: :off,
          else: Keyword.get(opts, :audio, %{rate: 44_100, channels: 2})

      levels = Map.merge(Audio.default_levels(), Map.take(settings, [:sfx, :music]))

      session =
        %__MODULE__{
          game: game,
          world: world,
          local_world: local,
          name: name,
          sheet: sheet,
          sheet_url: sheet_url,
          actions: Map.new(game.actions(), &{Atom.to_string(&1), &1}),
          levels: levels
        }
        |> sounded(
          policy,
          asked,
          Keyword.get(opts, :sink, {TuningFork.Sink.Process, owner: self()})
        )

      {:ok, session,
       [
         {"sheet", Sheet.index(sheet, sheet_url(sheet_url))},
         {"audio", audio_push(session.format)}
       ]}
    end
  end

  defp audio_push(:off), do: %{off: true}
  defp audio_push(format), do: format

  defp sounded(session, policy, asked, sink) do
    format = Cauldron2D.Net.Audio.format(asked)
    music = music_of(policy, format)
    sfx? = format != :off and policy.sfx == :personal

    if music == :off and not sfx? do
      %{session | format: :off, music: :off, audio: nil, shared: nil}
    else
      audio =
        if sfx? or music in [:own, :static],
          do: start_audio(session.game, session.levels, sink, format, sfx?, music)

      shared = if music == :shared, do: shared(session, format)
      %{session | format: format, music: music, audio: audio, shared: shared}
    end
  end

  defp music_of(_policy, :off), do: :off
  defp music_of(%{music: :off}, _format), do: :off
  defp music_of(%{music: :world}, _format), do: :shared
  defp music_of(%{music: :static}, _format), do: :static
  defp music_of(_personal_or_dynamic, _format), do: :own

  defp shared(%{world: world, game: game}, format) do
    case GenServer.whereis(world) do
      pid when is_pid(pid) ->
        shared = Shared.fetch(pid, game, format)
        :ok = Shared.subscribe(shared)
        shared

      _gone ->
        nil
    end
  end

  @doc "A chunk from the session's own stage, `{:pcm, chunk}`: the push, with the world's shared music under it when the music is shared."
  @spec pcm(t(), binary()) :: {t(), [push()]}
  def pcm(%__MODULE__{music: :shared} = session, chunk) do
    case :queue.out(session.queued) do
      {{:value, music}, rest} ->
        {%{session | queued: rest},
         [{"pcm", Mixer.mix([chunk, Mixer.scale(music, music_level(session))])}]}

      {:empty, _} ->
        {session, [{"pcm", chunk}]}
    end
  end

  def pcm(%__MODULE__{} = session, chunk), do: {session, [{"pcm", chunk}]}

  @doc "A chunk of the world's shared music, `{:cauldron_shared_pcm, chunk}`: pushed as it is when the session has no stage of its own, else kept for the next chunk of its own to go under."
  @spec shared_pcm(t(), binary()) :: {t(), [push()]}
  def shared_pcm(%__MODULE__{audio: nil, music: :shared} = session, chunk),
    do: {session, [{"pcm", Mixer.scale(chunk, music_level(session))}]}

  def shared_pcm(%__MODULE__{music: :shared} = session, chunk) do
    queued =
      if :queue.len(session.queued) >= @queued_most,
        do: :queue.drop(session.queued),
        else: session.queued

    {%{session | queued: :queue.in(chunk, queued)}, []}
  end

  def shared_pcm(%__MODULE__{} = session, _chunk), do: {session, []}

  @doc "The policy's rate changed, `{:cauldron_audio_rate, rate}`: the session's audio starts again at the new rate, and the browser is told the format."
  @spec rerate(t(), pos_integer()) :: {t(), [push()]}
  def rerate(%__MODULE__{format: :off} = session, _rate), do: {session, []}
  def rerate(%__MODULE__{format: %{rate: rate}} = session, rate), do: {session, []}

  def rerate(%__MODULE__{} = session, rate) do
    stop_audio(session.audio)
    format = %{session.format | rate: rate}

    sfx? =
      session.audio != nil and
        (session.music not in [:own, :static] or Cauldron2D.Net.Audio.policy().sfx == :personal)

    audio =
      if session.audio,
        do:
          start_audio(
            session.game,
            session.levels,
            {TuningFork.Sink.Process, owner: self()},
            format,
            sfx?,
            session.music
          )

    {%{session | format: format, audio: audio, cue: nil, queued: :queue.new()},
     [{"audio", format}]}
  end

  defp local_world({module, opts}) do
    {:ok, world} = World.start_link([game: module] ++ Keyword.drop(opts, [:name]))
    {world, world}
  end

  defp local_world(world), do: {world, nil}

  defp joined(world, local, name, props) do
    case Player.join(world, name, props) do
      :ok ->
        :ok

      {:error, reason} ->
        if local, do: GenServer.stop(local)
        {:error, reason}
    end
  end

  @doc "A `{:cauldron_atlas, name, :changed}` for the game's atlas: the new sheet, and the map goes again with the next frame."
  @spec atlas_changed(t()) :: {t(), [push()]}
  def atlas_changed(%__MODULE__{} = session) do
    sheet = Sheet.cached(session.game.atlas())

    {%{session | sheet: sheet, map_sent?: false},
     [{"sheet", Sheet.index(sheet, sheet_url(session.sheet_url))}]}
  end

  defp sheet_url({mod, fun}), do: apply(mod, fun, [])
  defp sheet_url(path) when is_binary(path), do: path

  @doc "A `{:cauldron_frame, message}` from the world: the map first if not yet sent, then the frame; events and cues reach the audio."
  @spec frame(t(), %{view: term(), events: list()}) :: {t(), [push()]}
  def frame(%__MODULE__{} = session, %{view: view, events: events}) do
    session = session |> sound(view, events) |> cued(view)
    scene = session.game.scene(view)

    frame =
      {"frame",
       Frame.frame(
         scene,
         Hud.rows(session.game.hud(view)),
         Game.outcome(session.game, view),
         session.sheet
       )}

    if session.map_sent? do
      {session, [frame]}
    else
      {%{session | map_sent?: true},
       [{"map", Frame.map(Game.static_map(session.game, view), session.sheet)}, frame]}
    end
  end

  @doc """
  What the browser holds and aims at, and how hard it holds what an analog control
  holds (`strength`, action name to 0.0–1.0); actions the game does not know, and
  strengths for actions not held or out of range, are dropped.
  """
  @spec input(t(), [String.t()], [number()] | nil, %{String.t() => number()}) :: t()
  def input(%__MODULE__{} = session, held, aim, strength \\ %{}) do
    actions =
      for name <- held,
          action = Map.get(session.actions, name),
          action != nil,
          into: MapSet.new(),
          do: action

    strengths =
      for {name, value} <- strength,
          is_number(value) and value >= 0 and value <= 1,
          action = Map.get(session.actions, name),
          action != nil,
          MapSet.member?(actions, action),
          into: %{},
          do: {action, value / 1}

    input = %{held: actions, aim: aim && List.to_tuple(aim)}

    Player.input(
      session.world,
      session.name,
      if(strengths == %{}, do: input, else: Map.put(input, :strength, strengths))
    )

    session
  end

  @doc "Set the effects and music levels, 0.0 to 1.0; shared music is scaled by the session's music level as it is mixed."
  @spec levels(t(), number(), number()) :: t()
  def levels(%__MODULE__{} = session, sfx, music),
    do: apply_levels(%{session | levels: %{sfx: sfx / 1, music: music / 1}})

  @doc "Switch the music off, or back on at the session's music level, leaving the effects alone; the switch outlives a change of levels."
  @spec music(t(), boolean()) :: t()
  def music(%__MODULE__{} = session, on?) when is_boolean(on?),
    do: apply_levels(%{session | music_on?: on?})

  defp apply_levels(%__MODULE__{audio: audio} = session) do
    if audio,
      do:
        Audio.levels(
          audio,
          session.levels.sfx,
          if(session.music in [:own, :static], do: music_level(session), else: 0.0)
        )

    session
  end

  defp music_level(%__MODULE__{music_on?: true, levels: %{music: music}}), do: music
  defp music_level(%__MODULE__{}), do: 0.0

  @doc "Leave the world and stop the audio."
  @spec leave(t()) :: :ok
  def leave(%__MODULE__{} = session) do
    Atlas.unsubscribe(session.game.atlas())
    Player.leave(session.world, session.name)
    stop_audio(session.audio)
    if session.shared && Process.alive?(session.shared), do: Shared.unsubscribe(session.shared)

    if session.local_world && Process.alive?(session.local_world),
      do: GenServer.stop(session.local_world)

    :ok
  end

  @doc "Pause or resume the player's own world; nothing for a shared one."
  @spec toggle_pause(t()) :: t()
  def toggle_pause(%__MODULE__{local_world: nil} = session), do: session

  def toggle_pause(%__MODULE__{local_world: world} = session) do
    if World.paused?(world), do: World.resume(world), else: World.pause(world)
    session
  end

  defp wanted_cue(%{music: :static, game: game}, view),
    do: game.cue(view, {:static, :play}) || game.cue(view, :play)

  defp wanted_cue(%{game: game}, view), do: game.cue(view, :play)

  defp start_audio(game, levels, sink, format, sfx?, music) do
    music? = music in [:own, :static]

    {:ok, audio} =
      Audio.start_link(
        name: nil,
        sink: sink,
        sounds: if(sfx?, do: game.sounds(), else: fn _event -> nil end),
        sfx: if(sfx?, do: levels.sfx, else: 0.0),
        music: if(music?, do: levels.music, else: 0.0),
        static_music: music == :static,
        music_dir: Game.music_dir(game),
        rate: format.rate,
        channels: format.channels
      )

    if music?, do: for({name, spec} <- game.music(), do: Music.piece(audio, name, spec))
    audio
  end

  defp stop_audio(nil), do: :ok
  defp stop_audio(audio), do: if(Process.alive?(audio), do: GenServer.stop(audio), else: :ok)

  defp sound(%{audio: nil} = session, _view, _events), do: session

  defp sound(session, view, events) do
    Audio.listener(session.audio, session.game.listener(view))
    if events != [], do: Audio.play(session.audio, events)
    session
  end

  defp cued(%{music: music} = session, _view) when music not in [:own, :static], do: session

  defp cued(%{cue: current} = session, view) do
    case wanted_cue(session, view) do
      ^current ->
        session

      nil ->
        Music.stop(session.audio)
        %{session | cue: nil}

      cue ->
        Music.cue(session.audio, cue)
        %{session | cue: cue}
    end
  end
end
