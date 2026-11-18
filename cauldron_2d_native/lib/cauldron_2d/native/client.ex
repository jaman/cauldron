defmodule Cauldron2D.Native.Client do
  @moduledoc """
  A `Cauldron.Client.Game` on a phone or tablet: the game's own title and summary
  (`Cauldron.Net.FrontSession`) and its worlds (`Cauldron.Net.Link.Local`), drawn
  to the screen with `CauldronNative.present/3` (a scene with a `:gpu` drawn by
  `cauldron_gpu` into the app's graphics surface, `Cauldron2D.Native.Gpu`, where the app can),
  played with the on-screen controller
  (`Cauldron2D.Native.Pad`) and taps, heard through the speaker.

      Cauldron2D.Native.Client.start_link(game: MyGame.Client)

  `Cauldron2D.Native.Application` starts one when the app is a mobile app and
  `config :cauldron_2d_native, game: MyGame.Client` names the game.

  The flow is the game's `start/0`: a `{:play, id, opts}` start opens its title front
  (when the game has one and `title: true`) or the world; a lobby start joins the first
  world, since the phone draws no lobby. The title's and summary's moves are followed
  as the browser follows them; `"quit"` closes the app where the platform allows it
  (`CauldronNative.quit/0`), and `"lobby"`, `"settings"` and `"guide"` come back to the
  title. A game without a title front opens its world directly.

  A game controller connected to the device plays as the on-screen one does and hides
  it, numbered from `1` after the on-screen controller's `0`; the on-screen controller
  comes back when the last one goes. A tap on the picture is a left click at that point
  of it. When the app leaves the screen the world rests
  (`Cauldron.Net.Link.Local.rest/1`) and a `:gpu` renderer closes; the world wakes when
  the app comes back, and the renderer opens again on its next scene. Android's back
  gesture is `Escape`.

  ## Options

    * `:game` — the module. Required
    * `:username` — the player's name. Default `"player"`
    * `:props` — the props `worlds/1` and `fronts/1` are given. Default `%{}`
    * `:point_size` — the points a picture pixel takes on the screen
      (`Cauldron2D.Native.Screen`). Default `0.75`
  """

  use GenServer

  alias Cauldron.Client.{Game, Keys, Start}
  alias Cauldron.Net.FrontSession
  alias Cauldron.Net.Link.Local
  alias Cauldron2D.Atlas
  alias Cauldron2D.Client.Look
  alias Cauldron2D.Native.{Gpu, Pad, Screen, Settings}
  alias Cauldron2D.Raster

  @doc "Start the client for `:game`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl GenServer
  def init(opts) do
    game = Keyword.fetch!(opts, :game)
    username = Keyword.get(opts, :username, "player")
    props = Map.merge(%{username: username}, Keyword.get(opts, :props, %{}))
    :ok = CauldronNative.subscribe(self())

    state = %{
      game: game,
      username: username,
      props: props,
      settings: Settings.load(game, username),
      flow: Start.flow(game, props),
      point_size: Keyword.get(opts, :point_size),
      tile: Atlas.fetch(game.atlas()).tile,
      screen: nil,
      pad: nil,
      picture: nil,
      mode: :starting,
      world: nil,
      resting?: false,
      controllers: %{},
      next_controller: 1,
      gpu: Gpu.new()
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_info({:cauldron_native, :screen, screen}, state),
    do: {:noreply, state |> laid_out(screen) |> started()}

  def handle_info({:cauldron_native, :pad, event}, state),
    do: {:noreply, controller(state, event)}

  def handle_info({:cauldron_native, :touches, touches}, %{controllers: controllers} = state)
      when controllers != %{},
      do: {:noreply, tapped(state, touches)}

  def handle_info({:cauldron_native, :touches, touches}, %{pad: pad} = state) when pad != nil do
    {pad, events, pointers} = Pad.touch(pad, touches)
    state = %{state | pad: pad} |> pressed(events) |> pointed(pointers) |> fan_kept()
    CauldronNative.overlay(Pad.shapes(pad))
    {:noreply, state}
  end

  def handle_info({:cauldron_native, :lifecycle, :active}, state), do: {:noreply, woken(state)}
  def handle_info({:cauldron_native, :lifecycle, _away}, state), do: {:noreply, rested(state)}
  def handle_info({:cauldron_native, :back, _pressed}, state), do: {:noreply, escaped(state)}

  def handle_info(:front_frame, %{mode: {:front, front}} = state) do
    Process.send_after(self(), :front_frame, FrontSession.frame_ms())
    {front, pushes} = FrontSession.tick(front)
    {:noreply, front_pushes(%{state | mode: {:front, front}}, pushes)}
  end

  def handle_info(:front_frame, state), do: {:noreply, state}

  def handle_info({:cauldron_link, :picture, raster}, state),
    do: {:noreply, presented(state, raster)}

  def handle_info({:cauldron_link, :gpu, scene}, %{mode: {:world, link}, resting?: false} = state) do
    gpu = Gpu.draw(state.gpu, newest_gpu(scene), state.screen)
    if Gpu.failed?(gpu) and not Gpu.failed?(state.gpu), do: Local.without_gpu(link)
    {:noreply, %{state | gpu: gpu}}
  end

  def handle_info({:cauldron_link, :drawing, _drawing}, %{mode: {:world, link}} = state) do
    Local.pane(link, pane(state))
    {:noreply, state}
  end

  def handle_info({:cauldron_link, :sheet, _sheet, _png}, %{mode: {:world, link}} = state) do
    Local.pane(link, pane(state))
    {:noreply, state}
  end

  def handle_info({:cauldron_link, :status, %{over: over}}, %{mode: {:world, _link}} = state)
      when over != nil,
      do: {:noreply, to_summary(state, over)}

  def handle_info({:cauldron_link, :settings, settings}, state),
    do: {:noreply, saved(state, settings)}

  def handle_info({:cauldron_link, :go, _to}, state), do: {:noreply, to_title(state)}
  def handle_info({:cauldron_link, :closed, _reason}, state), do: {:noreply, to_title(state)}
  def handle_info({:cauldron_link, :refused, _reason}, state), do: {:noreply, to_title(state)}
  def handle_info(_message, state), do: {:noreply, state}

  defp laid_out(state, screen) do
    labels = Pad.labels(padmap(state), Keys.pad(state.game, Look.of(state.game)))
    {pad, events} = if state.pad, do: Pad.release(state.pad), else: {nil, []}
    state = if pad, do: pressed(%{state | pad: pad}, events), else: state

    pad =
      Pad.new(screen, labels,
        hand: Settings.hand(state.settings),
        buttons: Settings.buttons(state.settings),
        offset: Settings.fan_offset(state.settings)
      )

    state = %{state | screen: screen, pad: pad} |> shown_pad()
    repaned(state)
  end

  defp padmap(state) do
    taken = state.game |> Keys.pad(Look.of(state.game)) |> Map.values() |> Enum.reject(&is_nil/1)
    Game.padmap(state.game, state.props, taken)
  end

  defp pane(state),
    do: Screen.pane(state.screen, state.tile, Screen.scale(state.screen, state.point_size))

  defp repaned(%{mode: {:world, link}} = state) do
    Local.pane(link, pane(state))
    state
  end

  defp repaned(%{mode: {:front, front}} = state) do
    {front, pushes} = FrontSession.pane(front, pane(state))
    front_pushes(%{state | mode: {:front, front}}, pushes)
  end

  defp repaned(state), do: state

  defp started(%{mode: :starting} = state), do: begin(state)
  defp started(state), do: state

  defp begin(%{flow: {:play, id, opts}} = state) do
    if Keyword.get(opts, :title, false), do: to_title(state), else: enter(state, id)
  end

  defp begin(state), do: enter(state, :first)

  defp to_title(state), do: open_front(state, :title, %{}) || enter(state, first_play(state))

  defp to_summary(state, %{outcome: outcome, view: view}) do
    props = %{outcome: outcome, view: view, world: state.world && to_string(state.world.id)}
    open_front(state, :summary, props) || to_title(state)
  end

  defp to_summary(state, _over), do: to_title(state)

  defp open_front(state, screen, props) do
    state = left(state)

    case FrontSession.open(
           state.game,
           screen,
           state.username,
           Map.merge(state.props, Map.put(props, :settings, state.settings)),
           drawer: Cauldron2D.Net.Drawer,
           local: true,
           audio: audio_format(state.game),
           sink: TuningFork.Sink.Speaker
         ) do
      {:ok, front, _pushes} ->
        Process.send_after(self(), :front_frame, FrontSession.frame_ms())
        {front, pushes} = FrontSession.pane(front, pane(state))
        CauldronNative.overlay([])
        front_pushes(%{state | mode: {:front, front}}, pushes)

      {:error, :no_front} ->
        nil
    end
  end

  defp first_play(%{flow: {:play, id, _opts}}), do: id
  defp first_play(_state), do: :first

  defp enter(state, id) do
    state = left(state)
    worlds = state.game.worlds(state.props)

    world =
      if id == :first,
        do: List.first(worlds),
        else: Enum.find(worlds, &(to_string(&1.id) == to_string(id)))

    case world do
      nil -> %{state | mode: :idle}
      world -> joined(state, world)
    end
  end

  defp joined(state, world) do
    {:ok, link} =
      Local.start_link(
        owner: self(),
        game: state.game,
        drawer: Cauldron2D.Net.Drawer,
        world: world.world,
        name: state.username,
        props:
          state.props
          |> Map.drop([:username])
          |> Map.merge(
            Game.optional(
              state.game,
              :join_props,
              [%{username: state.username, settings: state.settings}],
              %{}
            )
          )
          |> Map.put(:settings, state.settings),
        client_props: state.props,
        sink: Game.optional(state.game, :sink, [state.props], TuningFork.Sink.Speaker),
        gpu: Gpu.usable?(state.gpu)
      )

    Local.levels(link, state.settings.sfx, state.settings.music)
    Local.configure(link, Map.take(state.settings, [:preset, :pointer]))
    Local.pane(link, pane(state))
    shown_pad(%{state | mode: {:world, link}, world: world, picture: nil, resting?: false})
  end

  defp left(%{mode: {:world, link}} = state) do
    if Process.alive?(link), do: Local.leave(link)
    %{state | mode: :idle, gpu: Gpu.close(state.gpu)}
  end

  defp left(%{mode: {:front, front}} = state) do
    FrontSession.close(front)
    %{state | mode: :idle}
  end

  defp left(state), do: state

  defp newest_gpu(scene) do
    receive do
      {:cauldron_link, :gpu, newer} -> newest_gpu(newer)
    after
      0 -> scene
    end
  end

  defp front_pushes(state, pushes), do: Enum.reduce(pushes, state, &front_push/2)

  defp front_push({"picture", raster}, state), do: presented(state, raster)
  defp front_push({"settings", settings}, state), do: saved(state, settings)
  defp front_push({"go", %{to: "world", id: id}}, state), do: enter(state, id)

  defp front_push({"go", %{to: "quit"}}, state) do
    CauldronNative.quit()
    state
  end

  defp front_push({"go", %{to: to}}, %{mode: {:front, %{screen: :summary}}} = state)
       when to in ["lobby", "title"],
       do: to_title(state)

  defp front_push({"go", _elsewhere}, state), do: state
  defp front_push(_push, state), do: state

  defp presented(state, %FrenchCurve.Raster{width: width, height: height} = raster) do
    CauldronNative.present(width, height, Raster.to_rgba_binary(raster))
    %{state | picture: {width, height}}
  end

  defp saved(state, settings) do
    settings = Map.merge(state.settings, settings)
    Settings.save(state.game, state.username, settings)
    relaid(%{state | settings: settings}, layout(state.settings))
  end

  defp layout(settings), do: {Settings.hand(settings), Settings.buttons(settings)}

  defp relaid(%{screen: screen} = state, before) when screen != nil do
    if layout(state.settings) == before, do: state, else: laid_out(state, screen)
  end

  defp relaid(state, _before), do: state

  defp fan_kept(%{pad: pad, settings: settings} = state) do
    offset = Pad.offset(pad)

    if offset == Settings.fan_offset(settings),
      do: state,
      else: saved(state, %{fan_offset: offset})
  end

  defp pressed(state, events), do: Enum.reduce(events, state, &press/2)

  defp press(event, %{mode: {:world, link}} = state) do
    Local.pad_event(link, event)
    state
  end

  defp press(%{button: button, pressed: true}, %{mode: {:front, front}} = state) do
    {front, pushes} = FrontSession.pad(front, button)
    front_pushes(%{state | mode: {:front, front}}, pushes)
  end

  defp press(_event, state), do: state

  defp pointed(state, pointers), do: Enum.reduce(pointers, state, &point/2)

  defp point(_pointer, %{picture: nil} = state), do: state

  defp point({phase, at}, state) do
    case Screen.fraction(state.screen, state.picture, at) do
      nil -> state
      fraction -> clicked(state, phase, fraction)
    end
  end

  defp clicked(%{mode: {:world, link}} = state, phase, fraction) do
    Local.mouse(link, mouse(phase, fraction))
    state
  end

  defp clicked(%{mode: {:front, front}} = state, :down, fraction) do
    {front, pushes} = FrontSession.mouse(front, mouse(:down, fraction))
    front_pushes(%{state | mode: {:front, front}}, pushes)
  end

  defp clicked(state, _phase, _fraction), do: state

  defp mouse(:down, at), do: %{type: :mouse_down, button: :left, at: at}
  defp mouse(:up, at), do: %{type: :mouse_up, button: :left, at: at}
  defp mouse(:move, at), do: %{type: :move, at: at}

  defp rested(%{mode: {:world, link}, resting?: false} = state) do
    {pad, events} = Pad.release(state.pad)
    state = pressed(%{state | pad: pad}, events)
    Local.rest(link)
    %{state | resting?: true, gpu: Gpu.close(state.gpu)}
  end

  defp rested(state), do: state

  defp woken(%{mode: {:world, link}, resting?: true} = state) do
    Local.wake(link)
    %{state | resting?: false}
  end

  defp woken(state), do: state

  defp escaped(%{mode: {:world, link}} = state) do
    Local.key(link, :escape, [], true)
    Local.key(link, :escape, [], false)
    state
  end

  defp escaped(%{mode: {:front, front}} = state) do
    {front, pushes} = FrontSession.key(front, :escape, [])
    front_pushes(%{state | mode: {:front, front}}, pushes)
  end

  defp escaped(state), do: state

  defp controller(state, %{type: :disconnected, device: native} = event) do
    case Map.pop(state.controllers, native) do
      {nil, _controllers} ->
        state

      {device, controllers} ->
        %{state | controllers: controllers}
        |> then(&press(%{event | device: device}, &1))
        |> shown_pad()
    end
  end

  defp controller(state, %{device: native} = event) do
    state = known(state, native)
    press(%{event | device: Map.fetch!(state.controllers, native)}, state)
  end

  defp known(%{controllers: controllers} = state, native) when is_map_key(controllers, native),
    do: state

  defp known(state, native) do
    state = hidden_pad(state)

    %{
      state
      | controllers: Map.put(state.controllers, native, state.next_controller),
        next_controller: state.next_controller + 1
    }
  end

  defp hidden_pad(%{pad: nil} = state), do: state

  defp hidden_pad(state) do
    {pad, events} = Pad.release(state.pad)
    CauldronNative.overlay([])
    pressed(%{state | pad: pad}, events)
  end

  defp shown_pad(%{controllers: controllers, pad: pad, mode: {:world, _}} = state)
       when controllers == %{} and pad != nil do
    CauldronNative.overlay(Pad.shapes(pad))
    state
  end

  defp shown_pad(state), do: state

  defp tapped(state, touches) do
    pointers =
      for %{phase: phase, x: x, y: y} <- touches,
          do:
            {Map.fetch!(%{began: :down, moved: :move, ended: :up, cancelled: :up}, phase),
             {x / 1, y / 1}}

    pointed(state, pointers)
  end

  defp audio_format(game) do
    rate = game |> Game.audio_options() |> Keyword.get(:rate, 44_100)
    %{rate: rate, channels: 2}
  end

  @impl GenServer
  def terminate(_reason, state) do
    _ = left(state)
    :ok
  end
end
