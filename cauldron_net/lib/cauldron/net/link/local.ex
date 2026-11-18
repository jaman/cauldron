defmodule Cauldron.Net.Link.Local do
  @moduledoc """
  A player's connection to a world reachable as a process — on this node, or
  on a node this one is connected to — through `Cauldron.Net.Session`, so the
  messages arrive in the same shape a `Cauldron.Net.Link.Socket` delivers.

      {:ok, link} = Cauldron.Net.Link.Local.start_link(game: MyGame.Client, drawer: Cauldron2D.Net.Drawer, world: pid, name: "alice", props: %{}, owner: self())

  The owner receives the drawer's messages for each of its pushes
  (`c:Cauldron.Net.Drawer.local/2`: for `Cauldron2D.Net.Drawer`, the sheet, who draws,
  and once it has given its pane with `pane/2`, each picture as a `Cauldron2D.Raster`),
  each tick `{:cauldron_link, :status, status}` (`Cauldron.Net.Wire.status/1`'s shape),
  and `{:cauldron_link, :go, :lobby | :settings | :title}`,
  `{:cauldron_link, :settings, settings}` and `{:cauldron_link, :clipboard, text}` as
  the game's menu and the client's keys have them; `{:cauldron_link, :ended, %{outcome, view}}` once when the round is over for this player; and `{:cauldron_link, :closed,
  reason}` when the world goes. Sound plays through `:sink` (a `Cauldron.Audio.Sink`, default
  `Cauldron.Audio.Sink.speaker/0`), on this machine. The session is joined with `local: true`,
  so the drawer sends terms rather than bytes; with `gpu: true` a scene with a `:gpu` is sent instead
  as `{:cauldron_link, :gpu, %{gpu: function, size: gpu_size}}` for the owner to draw
  with `cauldron_gpu` (`Cauldron.Net.Session.join/5`'s `:gpu`).
  In a game with a chat and a `:chat_room`, the owner
  also receives `{:cauldron_link, :chat_history, messages}`, `{:cauldron_link, :chat,
  message}` and `{:cauldron_link, :talk}`, and `say/2` talks. Options: `:game`,
  `:drawer` (a `Cauldron.Net.Drawer`, a module or `{module, opts}`),
  `:world`, `:name`, `:props`, `:owner`, `:sink`, `:chat_room`, `:gpu`, and `:client_props`, the
  client's props `worlds/1` is given when the world asks to move the player
  (`c:Cauldron.Client.Game.ask/1`): the link then leaves it and joins the next as the
  browser's channel does (`Cauldron.Net.Channel`), sending `{:cauldron_link, :world,
  id}` and the new world's first messages.
  """

  use GenServer

  alias Cauldron.Client.Menus
  alias Cauldron.Net.{Drawer, Session, Wire}

  @doc "Join `:world` as `:name` with `:props` for `:game`, reporting to `:owner`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "A controller event, as `Gamepad.Wire` describes it."
  @spec pad_event(GenServer.server(), map()) :: :ok
  def pad_event(link, event), do: GenServer.cast(link, {:pad_event, event})

  @doc "An action held (`strength` `nil` for in full) or let go by name, as a touch screen's button holds it."
  @spec hold(GenServer.server(), String.t(), boolean(), number() | nil) :: :ok
  def hold(link, action, down?, strength \\ nil),
    do: GenServer.cast(link, {:hold, action, down?, strength})

  @doc "The aim set at a world point, or `nil` to give it back to the pointer, for a client that places it itself."
  @spec aim(GenServer.server(), {number(), number()} | nil) :: :ok
  def aim(link, point), do: GenServer.cast(link, {:aim, point})

  @doc "The tiles across and down the client's pane shows at zoom 1."
  @spec pane(GenServer.server(), {pos_integer(), pos_integer()}) :: :ok
  def pane(link, size), do: GenServer.cast(link, {:pane, size})

  @doc "A key pressed (`down?` true) or released, as `Cauldron.Input` names keys, with its modifiers."
  @spec key(GenServer.server(), atom(), [atom()], boolean()) :: :ok
  def key(link, key, mods \\ [], down? \\ true),
    do: GenServer.cast(link, {:key, key, mods, down?})

  @doc "The view moved by `{fx, fy}`, fractions of the pane, for a player watching the world."
  @spec pan(GenServer.server(), {number(), number()}) :: :ok
  def pan(link, fraction), do: GenServer.cast(link, {:pan, fraction})

  @doc """
  A mouse event: `%{type: :mouse_down | :mouse_up, button}`, `%{type: :scroll,
  direction}` or `%{type: :move}`, each with `at`, the pointer as fractions of the
  picture (`Cauldron.Net.Session.mouse/2`).
  """
  @spec mouse(GenServer.server(), map()) :: :ok
  def mouse(link, mouse), do: GenServer.cast(link, {:mouse, mouse})

  @doc "The player's settings changed beside the world (`Cauldron.Net.Session.configure/2`)."
  @spec configure(GenServer.server(), map()) :: :ok
  def configure(link, changes), do: GenServer.cast(link, {:configure, changes})

  @doc "Say `text` in the world's chat room."
  @spec say(GenServer.server(), String.t()) :: :ok
  def say(link, text), do: GenServer.cast(link, {:say, text})

  @doc "The effects and music levels."
  @spec levels(GenServer.server(), number(), number()) :: :ok
  def levels(link, sfx, music), do: GenServer.cast(link, {:levels, sfx, music})

  @doc "Pause or resume a world of the player's own; nothing for a shared one."
  @spec pause(GenServer.server()) :: :ok
  def pause(link), do: GenServer.cast(link, :pause)

  @doc "The player stepped away, as an app sent to the background: the game's menu opens over the world (`Cauldron.Net.Session.rest/1`)."
  @spec rest(GenServer.server()) :: :ok
  def rest(link), do: GenServer.cast(link, :rest)

  @doc "The player came back after `rest/1` (`Cauldron.Net.Session.wake/1`)."
  @spec wake(GenServer.server()) :: :ok
  def wake(link), do: GenServer.cast(link, :wake)

  @doc "Send every scene as a picture from now on, also after a rejoin, for an owner whose graphics card could not open (`Cauldron.Net.Session.without_gpu/1`)."
  @spec without_gpu(GenServer.server()) :: :ok
  def without_gpu(link), do: GenServer.cast(link, :without_gpu)

  @doc "Leave the world and stop."
  @spec leave(GenServer.server()) :: :ok
  def leave(link), do: GenServer.stop(link, :normal)

  @impl GenServer
  def init(opts) do
    game = Keyword.fetch!(opts, :game)
    owner = Keyword.fetch!(opts, :owner)
    world = Keyword.fetch!(opts, :world)
    sink = Keyword.get(opts, :sink, TuningFork.Sink.Speaker)
    drawer = Drawer.fetch!(opts)
    Process.monitor(owner)

    case Session.join(
           game,
           world,
           Keyword.fetch!(opts, :name),
           Keyword.get(opts, :props, %{}),
           session_opts(
             drawer,
             sink,
             Keyword.get(opts, :chat_room),
             Keyword.get(opts, :gpu, false)
           )
         ) do
      {:ok, session, pushes} ->
        Enum.each(pushes, &deliver(%{owner: owner, game: game, drawer: drawer}, &1))

        {:ok,
         %{
           session: session,
           owner: owner,
           game: game,
           drawer: drawer,
           ticking?: false,
           name: Keyword.fetch!(opts, :name),
           sink: sink,
           gpu?: Keyword.get(opts, :gpu, false),
           join_props: Keyword.get(opts, :props, %{}),
           client_props:
             Keyword.get(opts, :client_props, %{username: Keyword.fetch!(opts, :name)}),
           return_props: nil,
           return_extra: %{},
           watch: watch(session.world)
         }}

      {:error, reason} ->
        send(owner, {:cauldron_link, :refused, reason})
        :ignore
    end
  end

  @impl GenServer
  def handle_cast({:pad_event, event}, state), do: answered(state, &Session.pad_event(&1, event))

  def handle_cast({:hold, action, down?, strength}, state),
    do: {:noreply, %{state | session: Session.hold(state.session, action, down?, strength)}}

  def handle_cast({:pane, size}, state), do: answered(state, &Session.pane(&1, size))

  def handle_cast({:aim, point}, state),
    do: {:noreply, %{state | session: Session.aim(state.session, point)}}

  def handle_cast({:key, key, mods, down?}, state),
    do: answered(state, &Session.key(&1, key, mods, down?))

  def handle_cast({:pan, fraction}, state), do: answered(state, &Session.pan(&1, fraction))
  def handle_cast({:mouse, mouse}, state), do: answered(state, &Session.mouse(&1, mouse))

  def handle_cast({:configure, changes}, state),
    do: {:noreply, %{state | session: Session.configure(state.session, changes)}}

  def handle_cast({:say, text}, state),
    do: {:noreply, %{state | session: Session.say(state.session, text)}}

  def handle_cast({:levels, sfx, music}, state),
    do: {:noreply, %{state | session: Session.levels(state.session, sfx, music)}}

  def handle_cast(:pause, state),
    do: {:noreply, %{state | session: Session.toggle_pause(state.session)}}

  def handle_cast(:rest, state), do: answered(state, &Session.rest/1)
  def handle_cast(:wake, state), do: answered(state, &Session.wake/1)

  def handle_cast(:without_gpu, state),
    do: {:noreply, %{state | gpu?: false, session: Session.without_gpu(state.session)}}

  @impl GenServer
  def handle_info({:cauldron_frame, message}, state),
    do: answered(state, &Session.frame(&1, message))

  def handle_info({:chat, _room, message}, state), do: answered(state, &Session.chat(&1, message))

  def handle_info(:menu_tick, state),
    do: answered(%{state | ticking?: false}, &Session.menu_tick/1)

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{owner: pid} = state),
    do: {:stop, {:shutdown, {:owner_gone, reason}}, state}

  def handle_info(
        {:DOWN, ref, :process, _world, _reason},
        %{watch: ref, return_props: props} = state
      )
      when ref != nil and props != nil do
    {:noreply, ticked(travel(%{state | watch: nil}, {:return, state.return_extra}))}
  end

  def handle_info({:DOWN, _ref, :process, _world, reason}, state) do
    send(state.owner, {:cauldron_link, :closed, reason})
    {:stop, :normal, %{state | session: %{state.session | world: nil}}}
  end

  def handle_info(message, state) do
    case Session.changed(state.session, message) do
      :unknown -> {:noreply, state}
      changed -> answered(state, fn _session -> changed end)
    end
  end

  defp answered(state, step) do
    {session, pushes} = step.(state.session)
    {moves, pushes} = Enum.split_with(pushes, &match?({"travel", _}, &1))
    Enum.each(pushes, &deliver(state, &1))

    state =
      Enum.reduce(moves, %{state | session: session}, fn {"travel", move}, state ->
        travel(state, move)
      end)

    {:noreply, ticked(state)}
  end

  defp session_opts(drawer, sink, chat_room, gpu?),
    do: [drawer: drawer, sink: sink, local: true, chat_room: chat_room, gpu: gpu?]

  defp travel(state, {:on_return, extra}), do: %{state | return_extra: extra}
  defp travel(%{return_props: nil} = state, {:return, _extra}), do: state

  defp travel(state, {:return, extra}) do
    returning = state.return_props

    case entered(left(state), returning, extra) do
      {:ok, state} -> %{state | return_props: nil, return_extra: %{}}
      {:error, state} -> state
    end
  end

  defp travel(state, {:enter, props}) do
    returning = state.return_props || state.client_props

    case entered(left(state), Map.merge(state.client_props, props), %{}) do
      {:ok, state} ->
        %{state | return_props: returning, return_extra: %{}}

      {:error, state} ->
        {_, state} = entered(state, returning, %{refused: true})
        %{state | return_props: nil}
    end
  end

  defp left(state) do
    Session.leave(state.session)
    if state.watch, do: Process.demonitor(state.watch, [:flush])
    %{state | watch: nil}
  end

  defp entered(state, client_props, extra) do
    with [world | _] <- state.game.worlds(client_props),
         id = to_string(world.id),
         {:ok, session, pushes} <-
           Session.join(
             state.game,
             world.world,
             state.name,
             Map.merge(state.join_props, extra),
             session_opts(state.drawer, state.sink, {:world, id}, state.gpu?)
           ) do
      send(state.owner, {:cauldron_link, :world, id})
      Enum.each(pushes, &deliver(state, &1))
      {:ok, %{state | session: session, client_props: client_props, watch: watch(session.world)}}
    else
      _refused -> {:error, state}
    end
  end

  defp watch(world) do
    case GenServer.whereis(world) do
      pid when is_pid(pid) -> Process.monitor(pid)
      _none -> nil
    end
  end

  defp ticked(%{ticking?: false, session: session} = state) do
    if Session.menu_open?(session) do
      Process.send_after(self(), :menu_tick, Menus.frame_ms())
      %{state | ticking?: true}
    else
      state
    end
  end

  defp ticked(state), do: state

  defp deliver(state, {"status", status}),
    do: send(state.owner, {:cauldron_link, :status, Wire.status(status)})

  defp deliver(state, {"gpu", gpu}), do: send(state.owner, {:cauldron_link, :gpu, gpu})

  defp deliver(state, {"go", go}), do: send(state.owner, {:cauldron_link, :go, Wire.go(go)})

  defp deliver(state, {"settings", settings}),
    do: send(state.owner, {:cauldron_link, :settings, settings})

  defp deliver(state, {"clipboard", %{text: text}}),
    do: send(state.owner, {:cauldron_link, :clipboard, text})

  defp deliver(state, {"ended", ended}), do: send(state.owner, {:cauldron_link, :ended, ended})
  defp deliver(state, {"chat", message}), do: send(state.owner, {:cauldron_link, :chat, message})

  defp deliver(state, {"chat_history", %{messages: messages}}),
    do: send(state.owner, {:cauldron_link, :chat_history, messages})

  defp deliver(state, {"talk", _}), do: send(state.owner, {:cauldron_link, :talk})

  defp deliver(%{drawer: {drawer, _opts}} = state, push) do
    for message <- drawer.local(state.game, push),
        do: send(state.owner, Tuple.insert_at(message, 0, :cauldron_link))
  end

  @impl GenServer
  def terminate(_reason, %{session: %{world: nil}}), do: :ok

  def terminate(_reason, %{session: session}) do
    Session.leave(session)
  catch
    :exit, _gone -> :ok
  end
end
