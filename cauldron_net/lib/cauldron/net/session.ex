defmodule Cauldron.Net.Session do
  @moduledoc """
  A browser player's life in a world, as functions over a struct, for a channel process
  to drive: the process calling `join/4` becomes the world's player and gets its frames
  and its audio's PCM as messages.

      {:ok, session, pushes} = Session.join(MyGame.Client, world, "alice", %{settings: %{sfx: 0.8, music: 0.3}})
      {session, pushes} = Session.frame(session, frame_message)
      session = Session.input(session, ["left", "act"], [10.5, 4.0], %{"act" => 0.5})

  Every function that has something for the browser returns pushes, `{event, payload}`
  pairs in the order to send them; a payload that is a binary is a `"pcm"` chunk.

  What a session's sound costs the server is `Cauldron.Net.Audio`'s policy: its own
  stage for effects and music, a stage for effects with the world's shared music
  (`Cauldron.Net.Audio.Shared`) mixed under them, or none. The chunks reach the
  calling process as `{:pcm, chunk}` from its own stage and `{:cauldron_shared_pcm,
  chunk}` from the shared one; `pcm/2` and `shared_pcm/2` turn them into pushes, and
  `rerate/2` answers `{:cauldron_audio_rate, rate}` from the policy.
  """

  alias Cauldron.{Audio, Chat, Player, World}
  alias Cauldron.Audio.Music
  alias Cauldron.Client.{Controls, Game, Hud, Party, Stage, View}
  alias Cauldron.Net.Audio.Shared
  alias Cauldron.Net.{Drawer, Frame}
  alias TuningFork.Mixer

  @type push :: {String.t(), map() | binary()}
  @type t :: %__MODULE__{
          game: module(),
          world: GenServer.server(),
          local_world: pid() | nil,
          name: String.t(),
          audio: pid() | nil,
          actions: %{String.t() => atom()},
          stage: Stage.t(),
          drawer: module(),
          drawn: Drawer.state(),
          pane: {pos_integer(), pos_integer()} | nil,
          gpu?: boolean(),
          ended?: boolean(),
          chat_room: term(),
          party: Party.t(),
          sent: map() | nil,
          paused_by_menu?: boolean(),
          cue: term(),
          shared: pid() | nil,
          format: Cauldron.Net.Audio.format(),
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
    :last_status,
    :actions,
    :stage,
    :drawer,
    :drawn,
    pane: nil,
    gpu?: false,
    ended?: false,
    chat_room: nil,
    party: nil,
    sent: nil,
    paused_by_menu?: false,
    cue: nil,
    shared: nil,
    format: :off,
    music: :off,
    levels: %{sfx: 0.0, music: 0.0},
    music_on?: true,
    queued: :queue.new()
  ]

  @queued_most 4
  @said_most 500
  @auto_rate 30

  @doc """
  Join `world` as `name` from the calling process; `game` implements
  `Cauldron.Client.Game`. A `world` of `{module, opts}` is this player's alone,
  started here and stopped by `leave/1`.

  `props` carries `:settings` (`:sfx` and `:music` levels, default
  `Cauldron.Audio.default_levels/0`) and
  anything the game's `join_props/1` adds. Options: `:drawer`, the
  `Cauldron.Net.Drawer` the scenes go to the client through (required), which is given
  the other options as well; `:sink`, a `Cauldron.Audio.Sink` for the audio instead of
  `Cauldron.Audio.Sink.process/2` to this process; `:audio`, the PCM format asked for as
  `%{rate: hertz, channels: 1 | 2}` (default 44 100 Hz stereo — 22 050 Hz mono is a
  quarter of the bytes) or `:off` for no sound; `:policy`, a sound policy instead of
  `Cauldron.Net.Audio.policy/0`; `:local`, `true` for a client in the same node, which
  takes the drawer's payloads as terms; `:gpu`, `true` for a
  client in the same node that draws a scene's `:gpu` itself: such a scene is pushed as
  `"gpu"`, `%{gpu: function, size: gpu_size}` (its `:gpu` and `:gpu_size`, see
  `Cauldron.Client.Game`), instead of a picture; `:chat_room`, the
  room of `Cauldron.Chat` the world's players talk in, which the session joins in a
  game with a chat, pushing `"chat_history"` (`messages`) with the others and
  `"chat"` for each message `chat/2` is given; the talk key pushes `"talk"`. The pushes are the
  drawer's first pushes, then `"audio"` with the format the PCM comes in, or `%{off: true}`
  when none will. A message for the drawer, such as a change to what it draws from, is
  answered by `changed/2`.
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

    join_props =
      Map.merge(%{username: name}, Map.merge(extra, Map.drop(props, [:settings, :params])))

    with :ok <- joined(world, local, name, join_props) do
      {drawer, drawer_opts} = Drawer.fetch!(opts)
      {drawn, drawn_pushes} = drawer.open(game, Keyword.merge(opts, drawer_opts))
      policy = Keyword.get(opts, :policy, Cauldron.Net.Audio.policy())

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
          actions: Map.new(game.actions(), &{Atom.to_string(&1), &1}),
          stage: Stage.new(game, Map.merge(settings, levels)),
          party:
            game |> Party.new(settings, %{username: name}) |> Party.seat(world, name, join_props),
          drawer: drawer,
          drawn: drawn,
          gpu?: Keyword.get(opts, :gpu, false),
          levels: levels
        }
        |> sounded(
          policy,
          asked,
          Keyword.get(opts, :sink, {TuningFork.Sink.Process, owner: self()})
        )

      session = session |> chatting(Keyword.get(opts, :chat_room)) |> paced()

      {:ok, session,
       drawn_pushes ++ [{"audio", audio_push(session.format)} | chat_history(session)]}
    end
  end

  defp audio_push(:off), do: %{off: true}
  defp audio_push(format), do: format

  defp sounded(session, policy, asked, sink) do
    format = Cauldron.Net.Audio.format(asked)
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

  def pcm(%__MODULE__{} = session, chunk) do
    if silent?(chunk), do: {session, []}, else: {session, [{"pcm", chunk}]}
  end

  defp silent?(<<>>), do: true

  defp silent?(chunk) when is_binary(chunk) do
    chunk
    |> :binary.bin_to_list()
    |> Enum.all?(&(&1 == 0))
  end

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
        (session.music not in [:own, :static] or Cauldron.Net.Audio.policy().sfx == :personal)

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

  @doc "A message the session's process received that is for its drawer (`c:Cauldron.Net.Drawer.changed/3`): the drawer's pushes, and the scene drawn again; `:unknown` for any other."
  @spec changed(t(), term()) :: {t(), [push()]} | :unknown
  def changed(%__MODULE__{} = session, message) do
    case session.drawer.changed(session.drawn, session.game, message) do
      {:ok, drawn, pushes} ->
        {session, more} = drawn(%{session | drawn: drawn})
        {session, pushes ++ more}

      :unknown ->
        :unknown
    end
  end

  @doc """
  A `{:cauldron_frame, message}` from the world: events and cues reach the audio, what
  the world asks of the client is acted on, and the pushes are the frame's `"status"`
  (hud rows, outcome, subject, focus), what the drawer sends to show its scene, and
  once, when the round is first over for this player, `"ended"` with the full
  `outcome` and the last `view`, for a summary the client runs itself.
  """
  @spec frame(t(), %{view: term(), events: list()}) :: {t(), [push()]}
  def frame(%__MODULE__{} = session, %{view: view, events: events}) do
    session = session |> sound(view, events) |> cued(view) |> expired()
    {stage, effects} = session.stage |> Stage.view(view) |> Stage.asked()
    {session, effected} = effect(%{session | stage: stage}, effects)
    {session, drawn} = drawn(session)
    {session, ended} = ended(session, view)
    {session, notice} = status(session, view)
    {session, notice ++ effected ++ drawn ++ ended}
  end

  defp expired(session), do: sent(%{session | party: Party.expire(session.party, now())})

  defp now, do: System.monotonic_time(:millisecond)

  defp ended(%{ended?: true} = session, _view), do: {session, []}

  defp ended(session, view) do
    case Game.outcome(session.game, view) do
      nil -> {session, []}
      outcome -> {%{session | ended?: true}, [{"ended", %{outcome: outcome, view: view}}]}
    end
  end

  defp status(%{last_status: last, drawer: drawer} = session, view) do
    status =
      {"status",
       Frame.status(
         Stage.scene(session.stage),
         Hud.rows(session.game.hud(view)),
         Game.outcome(session.game, view),
         &drawer.colour/1
       )}

    if last == status do
      {session, []}
    else
      {%{session | last_status: status}, [status]}
    end
  end

  @doc """
  The client's pane: `{columns, rows}`, how much of the world it shows across and
  down at zoom 1. A server-drawn picture is drawn over it; nothing is drawn before the
  client gives one.
  """
  @spec pane(t(), {pos_integer(), pos_integer()}) :: {t(), [push()]}
  def pane(%__MODULE__{} = session, {columns, rows} = pane) when columns > 0 and rows > 0,
    do: drawn(%{session | pane: pane, drawn: session.drawer.pane(session.drawn, pane)})

  @doc """
  A key pressed in the world, as `Cauldron.Input` names keys: to the game's open menu,
  or the client's own action bound to it (`Cauldron.Client.Stage.key/3`).
  """
  @spec key(t(), atom(), [atom()]) :: {t(), [push()]}
  def key(session, key, mods \\ [], down? \\ true)

  def key(%__MODULE__{} = session, key, mods, false),
    do: {sent(%{session | party: Party.key(session.party, key, mods, false, now())}), []}

  def key(%__MODULE__{} = session, key, mods, true) do
    if Stage.takes_key?(session.stage, key) do
      {stage, effects} = Stage.key(session.stage, key, mods)
      effect(%{session | stage: stage}, effects)
    else
      {sent(%{session | party: Party.key(session.party, key, mods, true, now())}), []}
    end
  end

  @doc """
  The view moved by `{fx, fy}`, fractions of the pane's width and height, for a player
  watching the world (`Cauldron.Client.Stage.pan_by/2`); nothing before the pane is known.
  """
  @spec pan(t(), {number(), number()}) :: {t(), [push()]}
  def pan(%__MODULE__{pane: nil} = session, _fraction), do: {session, []}

  def pan(%__MODULE__{pane: {columns, rows}} = session, {fx, fy}) do
    zoom = session.stage.zoom

    drawn(%{
      session
      | stage: Stage.pan_by(session.stage, {fx * columns / zoom, fy * rows / zoom})
    })
  end

  @doc "Say `text` in the world's chat room as this player; nothing in a game without a chat."
  @spec say(t(), String.t()) :: t()
  def say(%__MODULE__{chat_room: nil} = session, _text), do: session

  def say(%__MODULE__{} = session, text) do
    case text |> String.trim() |> String.slice(0, @said_most) do
      "" -> session
      said -> Chat.say(session.chat_room, Game.player_label(session.game, session.name), said)
    end

    session
  end

  @doc "A `{:chat, room, message}` from the world's room: the push that shows it."
  @spec chat(t(), map()) :: {t(), [push()]}
  def chat(%__MODULE__{} = session, message), do: {session, [{"chat", message}]}

  defp chatting(session, nil), do: session

  defp chatting(session, room) do
    if Stage.chat?(session.game) do
      Chat.join(room)
      %{session | chat_room: room}
    else
      session
    end
  end

  defp chat_history(%{chat_room: nil}), do: []
  defp chat_history(session), do: [{"chat_history", %{messages: Chat.history(session.chat_room)}}]

  @doc "The view back on the scene's focus (`Cauldron.Client.Stage.recentre/1`)."
  @spec recentre(t()) :: {t(), [push()]}
  def recentre(%__MODULE__{} = session),
    do: drawn(%{session | stage: Stage.recentre(session.stage)})

  @doc "A controller button pressed in the world (`Cauldron.Client.Stage.pad/2`)."
  @spec pad(t(), atom()) :: {t(), [push()]}
  def pad(%__MODULE__{} = session, button) do
    {stage, effects} = Stage.pad(session.stage, button)
    effect(%{session | stage: stage}, effects)
  end

  @doc """
  A mouse event in the world: `%{type: :mouse_down | :mouse_up, button}`, `%{type:
  :scroll, direction}` or `%{type: :move}`, each with `at`, the pointer as fractions of
  the picture's width and height. A press or a notch goes to the game's open menu; else
  presses hold what the game binds to the buttons, moves and notches make its pointer
  gestures, a notch the game does not bind zooms, and the pointer aims where the player
  lets it (the settings' `:pointer`, default on).
  """
  @spec mouse(t(), map()) :: {t(), [push()]}
  def mouse(%__MODULE__{} = session, %{type: type} = mouse) when type in [:mouse_down, :scroll] do
    if Stage.menu_open?(session.stage) do
      {stage, effects} = Stage.mouse(session.stage, mouse)
      effect(%{session | stage: stage}, effects)
    else
      {session, pushes} = moused(session, mouse)

      {stage, effects} =
        if type == :scroll and not wheel_bound?(session),
          do: Stage.mouse(session.stage, mouse),
          else: {session.stage, []}

      {session, more} = effect(%{session | stage: stage}, effects)
      {session, pushes ++ more}
    end
  end

  def mouse(%__MODULE__{} = session, mouse), do: moused(session, mouse)

  defp moused(session, mouse) do
    {stage, effects} = Stage.pointer(session.stage, mouse)
    session = %{session | stage: stage}
    {fx, fy} = Map.get(mouse, :at, {0.5, 0.5})
    {columns, rows} = session.pane || {1, 1}
    event = Map.merge(Map.delete(mouse, :at), %{x: fx * columns, y: fy * rows})
    controls = Controls.mouse(session.party.controls, event, now())
    aim = if pointing?(session), do: aim_at(session, {fx, fy})

    session
    |> Map.put(:party, Party.controls(session.party, fn _ -> Controls.aim(controls, aim) end))
    |> sent()
    |> effect(effects)
  end

  defp pointing?(session), do: Map.get(session.stage.settings, :pointer, true)

  defp wheel_bound?(session),
    do: Controls.binds?(session.party.controls, :wheel, []) or wheel_in_keymap?(session)

  defp wheel_in_keymap?(session) do
    session.party.controls.input
    |> Cauldron.Input.keymap()
    |> Enum.any?(fn {_action, keys} ->
      Enum.any?(keys, &(&1 in [{:mouse, :wheel_up}, {:mouse, :wheel_down}]))
    end)
  end

  @doc "The game's open menu a frame on, drawn again; nothing while no menu is open."
  @spec menu_tick(t()) :: {t(), [push()]}
  def menu_tick(%__MODULE__{} = session) do
    if Stage.menu_open?(session.stage),
      do: drawn(%{session | stage: Stage.menu_tick(session.stage)}),
      else: {session, []}
  end

  @doc "Whether the game's menu is open, so the host ticks it every `Cauldron.Client.Menus.frame_ms/0`."
  @spec menu_open?(t()) :: boolean()
  def menu_open?(%__MODULE__{} = session), do: Stage.menu_open?(session.stage)

  @doc "The player's settings: the levels, the preset, the game's options."
  @spec settings(t()) :: map()
  def settings(%__MODULE__{} = session), do: session.stage.settings

  defp effect(session, effects) do
    Enum.reduce(effects, {session, []}, fn effect, {session, pushes} ->
      {session, more} = apply_effect(session, effect)
      {session, pushes ++ more}
    end)
  end

  defp apply_effect(session, {:sounds, []}), do: {session, []}

  defp apply_effect(%{audio: nil} = session, {:sounds, _events}), do: {session, []}

  defp apply_effect(session, {:sounds, events}) do
    Audio.play(session.audio, events)
    {session, []}
  end

  defp apply_effect(session, {:settings, settings}) do
    session = levels(session, settings.sfx, settings.music)
    {sent(%{session | party: Party.settings(session.party, settings)}), [{"settings", settings}]}
  end

  defp apply_effect(session, :pause) when not is_nil(session.local_world) do
    paused(sent(%{session | party: Party.let_go(session.party)}))
  end

  defp apply_effect(session, :pause),
    do: {sent(%{session | party: Party.let_go(session.party)}), []}

  defp apply_effect(%{paused_by_menu?: true, local_world: world} = session, :resume) do
    if Process.alive?(world), do: World.resume(world)
    {%{session | paused_by_menu?: false}, []}
  end

  defp apply_effect(session, :resume), do: {session, []}
  defp apply_effect(session, :toggle_pause), do: {toggle_pause(session), []}
  defp apply_effect(session, :leave), do: {session, [{"go", %{to: "lobby"}}]}

  defp apply_effect(session, {:go, screen}),
    do: {session, [{"go", %{to: Atom.to_string(screen)}}]}

  defp apply_effect(session, :quit), do: {session, [{"go", %{to: "title"}}]}
  defp apply_effect(session, {:clipboard, text}), do: {session, [{"clipboard", %{text: text}}]}
  defp apply_effect(session, :redraw), do: drawn(session)
  defp apply_effect(session, {:travel, move}), do: {session, [{"travel", move}]}
  defp apply_effect(%{chat_room: nil} = session, :talk), do: {session, []}
  defp apply_effect(session, :talk), do: {session, [{"talk", %{}}]}

  defp paused(%{local_world: world} = session) do
    if World.paused?(world) do
      {session, []}
    else
      World.pause(world)
      {%{session | paused_by_menu?: true}, []}
    end
  end

  defp drawn(session) do
    case Stage.scene(session.stage) do
      nil ->
        {session, []}

      %{gpu: gpu} = scene when session.gpu? ->
        {session, [{"gpu", %{gpu: gpu, size: Map.get(scene, :gpu_size)}}]}

      scene ->
        props = Stage.draw_props(session.stage, scene)
        {drawn, pushes} = session.drawer.draw(session.drawn, props)
        {%{session | drawn: drawn}, pushes}
    end
  end

  @doc """
  The world point under the client's pointer, `{fx, fy}` fractions of the width and
  height of the picture it was last sent (`c:Cauldron.Net.Drawer.world_at/3`), or `nil`.
  """
  @spec aim_at(t(), {number(), number()}) :: {float(), float()} | nil
  def aim_at(%__MODULE__{} = session, fraction) do
    case Stage.scene(session.stage) do
      nil ->
        nil

      scene ->
        session.drawer.world_at(session.drawn, Stage.draw_props(session.stage, scene), fraction)
    end
  end

  @doc """
  An action held (`strength` `nil` for in full) or let go by name, as a touch screen's
  button holds it; a name the game does not know is passed over.
  """
  @spec hold(t(), String.t(), boolean(), number() | nil) :: t()
  def hold(%__MODULE__{} = session, name, down?, strength \\ nil) do
    case Map.get(session.actions, name) do
      nil ->
        session

      action ->
        sent(%{
          session
          | party: Party.controls(session.party, &Controls.hold(&1, action, down?, strength))
        })
    end
  end

  defp stick_aimed(state, session) do
    case Controls.stick_aim(session.party.controls, session.stage.look, fn -> focus(session) end) do
      nil -> state
      aim -> %{state | aim: aim}
    end
  end

  defp focus(session) do
    case Stage.scene(session.stage) do
      %{focus: focus} -> focus
      _none -> nil
    end
  end

  @doc """
  The player's settings changed outside the game's menu — a settings screen beside the
  world: `:preset` or `:bindings` (the keys the game is played with from now on, what was
  held let go), `:pointer` (whether the pointer aims) and `:fps` (`frame_rate/1`).
  """
  @spec configure(t(), map()) :: t()
  def configure(%__MODULE__{} = session, changes) do
    settings =
      Map.merge(session.stage.settings, Map.take(changes, [:preset, :bindings, :pointer, :fps]))

    session = paced(%{session | stage: %{session.stage | settings: settings}})
    keymap = Controls.bindings(session.game, settings)

    if keymap == Cauldron.Input.keymap(session.party.controls.input),
      do: session,
      else: sent(%{session | party: Party.settings(session.party, settings)})
  end

  @doc """
  The frames a second the player's settings ask for: their `:fps`, one of the game's
  `c:Cauldron.Client.Game.frame_rates/0`, with `:auto` (and no setting) 30. The world
  sends the session every so many ticks to make that rate, and the client gets a picture
  or a scene for each.
  """
  @spec frame_rate(map()) :: pos_integer()
  def frame_rate(%{fps: fps}) when is_integer(fps) and fps > 0, do: fps
  def frame_rate(_settings), do: @auto_rate

  defp paced(session) do
    rate = frame_rate(session.stage.settings)
    Player.frames(session.world, session.name, rate)
    session
  end

  @doc "The aim set at a world point, or `nil`, for a client that places it itself (a program, a remote world's terminal)."
  @spec aim(t(), {number(), number()} | nil) :: t()
  def aim(%__MODULE__{} = session, point),
    do: sent(%{session | party: Party.controls(session.party, &Controls.aim(&1, point))})

  @doc "A `Gamepad.Wire` event from one of the player's controllers: its buttons and sticks hold the game's actions, and a press works the menu or the client's own buttons."
  @spec pad_event(t(), map()) :: {t(), [push()]}
  def pad_event(%__MODULE__{} = session, event) do
    {party, routed} = Party.pad(session.party, event)
    session = %{session | party: party} |> nudged(event, routed) |> sent()

    case {event, routed, Stage.menu_open?(session.stage)} do
      {%{type: :button, button: button, pressed: true}, :own, _menu?} -> pad(session, button)
      {%{type: :button, button: button, pressed: true}, _seat, true} -> pad(session, button)
      _other -> {session, []}
    end
  end

  defp nudged(session, event, :own) do
    if Stage.menu_open?(session.stage) do
      session
    else
      nudge = &Controls.nudge(&1, event, session.stage.look, fn -> focus(session) end)
      %{session | party: Party.controls(session.party, nudge)}
    end
  end

  defp nudged(session, _event, _routed), do: session

  defp sent(session) do
    look = session.stage.look

    state =
      View.of(session.game).steered(Party.state(session.party), look) |> stick_aimed(session)

    message = Map.merge(Stage.input_extras(session.stage), state)
    session = %{session | party: Party.send_seats(session.party, session.world, look)}

    if message == session.sent do
      session
    else
      Player.input(session.world, session.name, message)
      %{session | sent: message}
    end
  end

  @doc "Set the effects and music levels, 0.0 to 1.0; shared music is scaled by the session's music level as it is mixed."
  @spec levels(t(), number(), number()) :: t()
  def levels(%__MODULE__{} = session, sfx, music) do
    stage = %{
      session.stage
      | settings: Map.merge(session.stage.settings, %{sfx: sfx / 1, music: music / 1})
    }

    apply_levels(%{session | levels: %{sfx: sfx / 1, music: music / 1}, stage: stage})
  end

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
    if session.chat_room, do: Chat.leave(session.chat_room)
    session.drawer.close(session.drawn, session.game)
    Party.unseat(session.party, session.world)
    Player.leave(session.world, session.name)
    stop_audio(session.audio)
    if session.shared && Process.alive?(session.shared), do: Shared.unsubscribe(session.shared)

    if session.local_world && Process.alive?(session.local_world),
      do: GenServer.stop(session.local_world)

    :ok
  end

  @doc "The player stepped away from the client (`Cauldron.Client.Stage.rest/1`)."
  @spec rest(t()) :: {t(), [push()]}
  def rest(%__MODULE__{} = session) do
    {stage, effects} = Stage.rest(session.stage)
    effect(%{session | stage: stage}, effects)
  end

  @doc "The player came back after `rest/1` (`Cauldron.Client.Stage.wake/1`)."
  @spec wake(t()) :: {t(), [push()]}
  def wake(%__MODULE__{} = session) do
    {stage, effects} = Stage.wake(session.stage)
    effect(%{session | stage: stage}, effects)
  end

  @doc "Push every scene as a picture from now on, for a client joined with `:gpu` whose graphics card could not open."
  @spec without_gpu(t()) :: t()
  def without_gpu(%__MODULE__{} = session), do: %{session | gpu?: false}

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
        [
          name: nil,
          sink: sink,
          sounds: if(sfx?, do: game.sounds(), else: fn _event -> nil end),
          sfx: if(sfx?, do: levels.sfx, else: 0.0),
          music: if(music?, do: levels.music, else: 0.0),
          static_music: music == :static,
          music_dir: Game.music_dir(game),
          rate: format.rate,
          channels: format.channels
        ] ++ Game.audio_options(game)
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
