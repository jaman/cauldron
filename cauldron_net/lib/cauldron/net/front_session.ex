defmodule Cauldron.Net.FrontSession do
  @moduledoc """
  A browser player on one of the game's own screens outside a world — its title, its
  summary (`Cauldron.Front`, named by `c:Cauldron.Client.Game.fronts/1`) — as
  functions over a struct for a channel process to drive, drawn as a world's scene is
  (through a `Cauldron.Net.Drawer`) and heard through its own audio stage.

      {:ok, front, pushes} = FrontSession.open(MyGame.Client, :title, "alice", %{settings: settings}, drawer: Cauldron2D.Net.Drawer)
      {front, pushes} = FrontSession.key(front, :enter, [])

  Every function that has something for the browser returns pushes, `{event, payload}`
  pairs in the order to send them. Where the front sends the player is pushed as
  `"go"`: `%{to: "world", id: id}`, `%{to: "lobby"}`, `%{to: "title"}`, `%{to:
  "settings"}`, `%{to: "guide"}` or `%{to: "quit"}`; settings the front changed as
  `"settings"`, as a world's session pushes them.

  The props are the player's `:settings`, and on the summary `:outcome`, `:view` and
  `:world` (the id of the world the round was played in, for the summary's "again").
  """

  alias Cauldron.Audio
  alias Cauldron.Audio.Music
  alias Cauldron.Client.{Fronts, Game, Menus, Stage, Start, View}
  alias Cauldron.Net.Drawer

  @type push :: {String.t(), map() | binary()}
  @type t :: %__MODULE__{}

  defstruct [
    :game,
    :screen,
    :fronts,
    :front,
    :settings,
    :drawer,
    :drawn,
    :audio,
    :flow,
    :props,
    cue: nil
  ]

  @doc """
  Open `screen` (`:title` or `:summary`) for `name`; `{:error, :no_front}` when the
  game draws no such screen. Options: `:drawer` (as `Cauldron.Net.Session.join/5` takes
  it, given the other options as well), `:audio` (the PCM format, or `:off`), `:sink`.
  The pushes are the drawer's first pushes and the audio format.
  """
  @spec open(module(), Cauldron.Front.screen(), String.t(), map(), keyword()) ::
          {:ok, t(), [push()]} | {:error, :no_front}
  def open(game, screen, name, props, opts \\ []) do
    fronts = Fronts.of(game, props)

    if Map.has_key?(fronts, screen) do
      settings =
        Stage.with_options(
          game,
          Map.merge(Audio.default_levels(), Map.get(props, :settings, %{}))
        )

      {drawer, drawer_opts} = Drawer.fetch!(opts)
      {drawn, drawn_pushes} = drawer.open(game, Keyword.merge(opts, drawer_opts))
      format = Keyword.get(opts, :audio, %{rate: 44_100, channels: 2})

      front =
        %__MODULE__{
          game: game,
          screen: screen,
          fronts: fronts,
          front: nil,
          settings: settings,
          drawer: drawer,
          drawn: drawn,
          flow: Start.flow(game, props),
          props: props,
          audio: start_audio(game, settings, format, Keyword.get(opts, :sink))
        }

      context = %{
        settings: settings,
        username: name,
        worlds: game.worlds(%{username: name}),
        outcome: Map.get(props, :outcome),
        view: Map.get(props, :view)
      }

      {front, _start?} = Fronts.open(front, context, now())

      {:ok, cued(front),
       drawn_pushes ++ [{"audio", if(format == :off, do: %{off: true}, else: format)}]}
    else
      {:error, :no_front}
    end
  end

  @doc "How often the front is ticked and drawn again, in milliseconds."
  @spec frame_ms() :: pos_integer()
  def frame_ms, do: Fronts.frame_ms()

  @doc "The front moved on to the present and drawn."
  @spec tick(t()) :: {t(), [push()]}
  def tick(front), do: front |> Fronts.tick(now()) |> cued() |> drawn()

  @doc "The client's pane: the tiles across and down it shows at zoom 1."
  @spec pane(t(), {pos_integer(), pos_integer()}) :: {t(), [push()]}
  def pane(front, size), do: drawn(%{front | drawn: front.drawer.pane(front.drawn, size)})

  @doc "A message for the front's drawer (`Cauldron.Net.Session.changed/2`): its pushes and the front drawn again, or `:unknown`."
  @spec changed(t(), term()) :: {t(), [push()]} | :unknown
  def changed(front, message) do
    case front.drawer.changed(front.drawn, front.game, message) do
      {:ok, drawn, pushes} ->
        {front, more} = drawn(%{front | drawn: drawn})
        {front, pushes ++ more}

      :unknown ->
        :unknown
    end
  end

  @doc "A key pressed, as `Cauldron.Input` names keys."
  @spec key(t(), atom(), [atom()]) :: {t(), [push()]}
  def key(front, key, mods), do: event(front, {:key, key, mods})

  @doc "A controller button pressed: the d-pad, `A`, `B` and `Start` work the front as keys."
  @spec pad(t(), atom()) :: {t(), [push()]}
  def pad(front, button) do
    case Menus.pad_key(button) do
      nil -> {front, []}
      key -> event(front, {:key, key, [:pad]})
    end
  end

  @doc "A mouse press or wheel notch."
  @spec mouse(t(), map()) :: {t(), [push()]}
  def mouse(front, mouse), do: event(front, {:mouse, mouse})

  @doc "The effects and music levels."
  @spec levels(t(), number(), number()) :: t()
  def levels(front, sfx, music) do
    if front.audio, do: Audio.levels(front.audio, sfx, music)
    %{front | settings: Map.merge(front.settings, %{sfx: sfx / 1, music: music / 1})}
  end

  @doc "Close the front, its drawer and its audio."
  @spec close(t()) :: :ok
  def close(front) do
    front.drawer.close(front.drawn, front.game)
    stop_audio(front.audio)
  end

  defp stop_audio(nil), do: :ok

  defp stop_audio(audio) do
    if Process.alive?(audio), do: GenServer.stop(audio)
    :ok
  end

  defp event(front, event) do
    {front, reply} = Fronts.event(front, event, front.settings)
    if front.audio, do: Audio.play(front.audio, Map.get(reply, :sounds, []))
    {front, settings_pushes} = settled(front, reply.settings)
    {front, drawn} = drawn(front)
    {front, settings_pushes ++ drawn ++ went(front, Map.get(reply, :go))}
  end

  defp settled(%{settings: settings} = front, settings), do: {front, []}

  defp settled(front, settings) do
    if front.audio, do: Audio.levels(front.audio, settings.sfx, settings.music)
    {%{front | settings: settings}, [{"settings", settings}]}
  end

  defp went(_front, nil), do: []
  defp went(front, :play), do: [go(played(front.flow))]
  defp went(_front, {:play, id}), do: [go(%{to: "world", id: to_string(id)})]
  defp went(front, :again), do: [go(again(front))]

  defp went(_front, to) when to in [:lobby, :title, :settings, :guide],
    do: [go(%{to: Atom.to_string(to)})]

  defp went(_front, :quit), do: [go(%{to: "quit"})]
  defp went(%{screen: :title}, :back), do: [go(%{to: "quit"})]
  defp went(_front, :back), do: [go(%{to: "lobby"})]

  defp go(where), do: {"go", where}

  defp played({:play, id, _opts}), do: %{to: "world", id: to_string(id)}
  defp played(_flow), do: %{to: "lobby"}

  defp again(%{props: %{outcome: %{next: :same_world}, world: id}}) when id != nil,
    do: %{to: "world", id: to_string(id)}

  defp again(%{props: %{outcome: %{next: :next_world}, world: id}} = front) when id != nil do
    worlds = front.game.worlds(%{})

    case Enum.find_index(worlds, &(to_string(&1.id) == to_string(id))) do
      nil -> %{to: "lobby"}
      index -> %{to: "world", id: to_string(Enum.at(worlds, rem(index + 1, length(worlds))).id)}
    end
  end

  defp again(_front), do: %{to: "lobby"}

  defp drawn(front) do
    view = View.of(front.game)
    look = View.given(view.look(front.game), nil, 0, front.settings.options)
    props = view.props(front.game, Fronts.scene(front), look, view.zoom(front.game))
    {drawn, pushes} = front.drawer.draw(front.drawn, props)
    {%{front | drawn: drawn}, pushes}
  end

  defp cued(%{audio: nil} = front), do: front

  defp cued(front) do
    case Fronts.cue(front) do
      cue when cue == front.cue ->
        front

      nil ->
        Music.stop(front.audio)
        %{front | cue: nil}

      cue ->
        Music.cue(front.audio, cue)
        %{front | cue: cue}
    end
  end

  defp start_audio(_game, _settings, :off, _sink), do: nil

  defp start_audio(game, settings, format, sink) do
    {:ok, audio} =
      Audio.start_link(
        [
          name: nil,
          sink: sink || {TuningFork.Sink.Process, owner: self()},
          sounds: game.sounds(),
          sfx: settings.sfx,
          music: settings.music,
          music_dir: Game.music_dir(game),
          rate: format.rate,
          channels: format.channels
        ] ++ Game.audio_options(game)
      )

    for {name, spec} <- game.music(), do: Music.piece(audio, name, spec)
    audio
  end

  defp now, do: System.monotonic_time(:millisecond)
end
