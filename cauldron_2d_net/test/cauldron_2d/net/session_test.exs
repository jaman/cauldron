defmodule Cauldron2D.Net.SessionTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.{Atlas, Audio, World}
  alias Cauldron2D.Client.Game
  alias Cauldron2D.Net.Audio.Shared
  alias Cauldron2D.Net.{Channel, Session}
  alias FrenchCurve.Raster

  defmodule Dots do
    @moduledoc false
    @behaviour Cauldron2D.Game

    @impl true
    def init(_opts), do: %{players: %{}, events: []}

    @impl true
    def join(state, id, props),
      do: {:ok, put_in(state.players[id], %{pos: {5.0, 5.0}, held: MapSet.new(), props: props})}

    @impl true
    def leave(state, id), do: %{state | players: Map.delete(state.players, id)}

    @impl true
    def handle_input(state, id, %{held: held, aim: aim} = input),
      do:
        update_in(
          state.players[id],
          &Map.merge(&1, %{held: held, aim: aim, strength: Map.get(input, :strength, %{})})
        )

    @impl true
    def step(state, dt) do
      players =
        Map.new(state.players, fn {id, p} ->
          {x, y} = p.pos
          dx = if MapSet.member?(p.held, :right), do: 4.0 * dt, else: 0.0
          {id, %{p | pos: {x + dx, y}}}
        end)

      events =
        if Enum.any?(players, fn {_, p} -> MapSet.member?(p.held, :fire) end),
          do: [:ping | state.events],
          else: state.events

      %{state | players: players, events: events}
    end

    @impl true
    def view(state, id) do
      %{
        me: state.players[id],
        movers: for({_, p} <- state.players, do: {:dot, p.pos}),
        width: 8,
        height: 6
      }
    end

    @impl true
    def drain_events(state), do: {Enum.reverse(state.events), %{state | events: []}}
  end

  defmodule DotsWeb do
    @moduledoc false
    @behaviour Cauldron2D.Client.Game

    def title, do: %{name: "DOTS"}
    def atlas, do: :dots_web
    def actions, do: [:left, :right, :fire]
    def keymaps, do: [arrows: %{left: [:left], right: [:right], fire: [:" "]}]
    def toggles, do: []

    def worlds(_props),
      do: [
        %{id: :main, name: "Main", world: :dots_web_world, players: 0},
        %{id: :own, name: "Own", world: {Cauldron2D.Net.SessionTest.Dots, [hz: 50]}, players: 0}
      ]

    def map(view),
      do: %{
        width: view.width,
        height: view.height,
        cell: fn {x, y} -> if x == 0 or y == 0, do: :wall, else: nil end
      }

    def scene(view),
      do: %{
        focus: view.me.pos,
        bounds: {view.width, view.height},
        cell: fn _ -> :void end,
        movers: view.movers,
        labels: [{"me", view.me.pos, {255, 255, 0}}]
      }

    def hud(view), do: [[{"x=#{elem(view.me.pos, 0)}", {255, 255, 255}}]]
    def listener(view), do: view.me.pos

    def sounds,
      do: fn :ping ->
        TuningFork.Voice.new(
          shape: :sine,
          freq: 440.0,
          envelope: TuningFork.Envelope.hit(0.05),
          gain: 0.5
        )
      end

    def music,
      do: [
        {"hum",
         %{
           bpm: 120,
           beats_per_bar: 4,
           layers: [:pad],
           sections: %{on: %{pad: "note(\"c3 e3\").s(\"sine\").gain(.4)"}}
         }}
      ]

    def cue(_view, :play), do: %{piece: "hum", section: :on, layers: %{}}
    def cue(_view, _screen), do: nil

    def join_props(%{username: name, params: params}),
      do: %{tag: name <> "!", side: Map.get(params, "side")}

    def outcome(%{me: %{pos: {x, _}}}) when x > 7.0, do: %{title: "Far", lines: ["x"]}
    def outcome(_), do: nil
  end

  setup_all do
    Atlas.new(:dots_web, tile: 4)
    |> Atlas.put(:wall, Raster.new(4, 4, background: {0, 0, 200, 255}))
    |> Atlas.put(:dot, Raster.new(4, 4, background: {250, 250, 250, 255}))
    |> Atlas.install()

    :ok
  end

  setup do
    {:ok, world} = World.start_link(game: Dots, hz: 50, name: :dots_web_world)
    on_exit(fn -> if Process.alive?(world), do: GenServer.stop(world) end)
    {:ok, world: world}
  end

  test "joining sends the sheet; the first frame sends the map then the frame; input reaches the world",
       %{world: world} do
    {:ok, session, pushes} =
      Session.join(DotsWeb, world, "alice", %{settings: %{sfx: 1.0, music: 0.0}},
        sink: TuningFork.Sink.Silent
      )

    assert [
             {"sheet", %{url: "/atlas.png", tile: 4, arts: %{"dot" => _, "wall" => _}}},
             {"audio", %{rate: 44_100, channels: 2}}
           ] = pushes

    assert %{players: %{"alice" => %{props: %{username: "alice", tag: "alice!", side: nil}}}} =
             World.snapshot(world)

    assert_receive {:cauldron_frame, message}, 500
    {session, pushes} = Session.frame(session, message)
    assert [{"map", %{width: 8, height: 6, rows: rows}}, {"frame", frame}] = pushes
    assert length(rows) == 6 and hd(rows) |> Enum.all?(&(&1 == session.sheet.arts.wall))
    assert frame.focus == [5.0, 5.0]
    assert [[_dot, 5.0, 5.0]] = frame.movers
    assert frame.hud == [[["x=5.0", "#ffffff"]]]
    assert frame.labels == [["me", 5.0, 5.0, "#ffff00", 1]]
    assert frame.over == nil

    assert_receive {:cauldron_frame, message}, 500
    {session, [{"frame", _}]} = Session.frame(session, message)

    session =
      Session.input(session, ["right", "nonsense"], [6.5, 5.0], %{
        "right" => 0.5,
        "nonsense" => 1.0,
        "left" => 2.0
      })

    Process.sleep(120)

    assert %{
             players: %{
               "alice" => %{held: held, aim: {6.5, 5.0}, pos: {x, _}, strength: %{right: 0.5}}
             }
           } = World.snapshot(world)

    assert MapSet.to_list(held) == [:right]
    assert x > 5.0

    :ok = Session.leave(session)
    assert World.players(world) == []
  end

  test "the round's end rides the frame, and a sound event arrives as PCM at this process", %{
    world: world
  } do
    {:ok, session, pushes} =
      Session.join(DotsWeb, world, "bob", %{settings: %{sfx: 1.0, music: 0.0}},
        audio: %{rate: 22_050, channels: 1}
      )

    assert {"audio", %{rate: 22_050, channels: 1}} in pushes
    assert Audio.rate(session.audio) == {22_050, 1}

    assert Channel.audio(%{"audio" => %{"rate" => 22_050, "channels" => 1}}) == [
             audio: %{rate: 22_050, channels: 1}
           ]

    assert Channel.audio(%{"audio" => %{"rate" => 5, "channels" => 7}}) == []
    assert Channel.audio(%{}) == []
    session = Session.input(session, ["fire"], nil)
    assert_receive {:pcm, chunk} when is_binary(chunk), 2_000

    far = %{view: %{me: %{pos: {9.0, 5.0}}, movers: [], width: 8, height: 6}, events: []}
    {_session, pushes} = Session.frame(%{session | map_sent?: true}, far)
    assert [{"frame", %{over: %{title: "Far", lines: ["x"]}}}] = pushes
    :ok = Session.leave(session)
  end

  describe "the server's sound policy" do
    alias Cauldron2D.Net.Audio, as: Policy

    setup do
      on_exit(fn -> Policy.set([]) end)
      :ok
    end

    test "a session that asks for no sound, or a server whose sound is off, gets no audio at all",
         %{world: world} do
      {:ok, quiet, pushes} =
        Session.join(DotsWeb, world, "ann", %{
          settings: %{sfx: 1.0, music: 1.0},
          params: %{"audio" => false}
        })

      assert quiet.audio == nil
      assert {"audio", %{off: true}} in pushes
      assert Channel.audio(%{"audio" => false}) == [audio: :off]
      :ok = Session.leave(quiet)

      Policy.set(music: :off, sfx: :off)

      {:ok, silent, pushes} =
        Session.join(DotsWeb, world, "ben", %{settings: %{sfx: 1.0, music: 1.0}})

      assert silent.audio == nil
      assert {"audio", %{off: true}} in pushes
      silent = Session.input(silent, ["fire"], nil)
      refute_receive {:pcm, _}, 300
      :ok = Session.leave(silent)
    end

    test "with the music shared by world, sessions in one world share one stage and get its music mixed under their own effects",
         %{world: world} do
      Policy.set(music: :world, sfx: :personal)
      {:ok, one, _} = Session.join(DotsWeb, world, "cat", %{settings: %{sfx: 1.0, music: 1.0}})
      test = self()

      other =
        spawn_link(fn ->
          {:ok, two, _} =
            Session.join(DotsWeb, world, "dan", %{settings: %{sfx: 1.0, music: 1.0}})

          send(test, {:two, two})

          receive do
            :leave -> Session.leave(two)
          end
        end)

      assert_receive {:two, two}, 2_000
      assert one.shared == two.shared and is_pid(one.shared)
      assert Shared.subscribers(one.shared) == 2
      assert_receive {:cauldron_shared_pcm, music}, 3_000
      assert_receive {:pcm, own}, 3_000
      assert byte_size(music) == byte_size(own)

      {one, []} = Session.shared_pcm(one, music)
      {one, [{"pcm", mixed}]} = Session.pcm(one, own)
      assert byte_size(mixed) == byte_size(own)
      {_one, [{"pcm", ^own}]} = Session.pcm(one, own)

      :ok = Session.leave(one)
      send(other, :leave)
      Process.sleep(100)
      assert Shared.subscribers(one.shared) == 0
    end

    test "with the music shared and effects off a session has no stage of its own and passes the shared music straight through",
         %{world: world} do
      Policy.set(music: :world, sfx: :off)

      {:ok, session, pushes} =
        Session.join(DotsWeb, world, "eve", %{settings: %{sfx: 1.0, music: 1.0}})

      assert session.audio == nil and is_pid(session.shared)
      assert {"audio", %{rate: 44_100, channels: 2}} in pushes
      assert_receive {:cauldron_shared_pcm, music}, 3_000
      assert {_session, [{"pcm", ^music}]} = Session.shared_pcm(session, music)

      quiet = Session.music(session, false)
      refute quiet.music_on?
      assert {_session, [{"pcm", silence}]} = Session.shared_pcm(quiet, music)
      assert TuningFork.Mixer.silent?(silence)
      halved = Session.levels(quiet, 1.0, 0.5)
      assert halved.levels == %{sfx: 1.0, music: 0.5} and not halved.music_on?
      assert {_session, [{"pcm", silence}]} = Session.shared_pcm(halved, music)
      assert TuningFork.Mixer.silent?(silence)
      back = Session.music(halved, true)
      assert {_session, [{"pcm", half}]} = Session.shared_pcm(back, music)
      assert half == TuningFork.Mixer.scale(music, 0.5)
      :ok = Session.leave(session)
    end

    test "static music is a session's own stage playing one rendered section under its effects",
         %{world: world} do
      Policy.set(music: :static)

      {:ok, session, _} =
        Session.join(DotsWeb, world, "gus", %{settings: %{sfx: 1.0, music: 1.0}})

      assert session.music == :static and is_pid(session.audio) and session.shared == nil
      view = %{me: %{pos: {5.0, 5.0}}, movers: [], width: 8, height: 6}
      {session, _} = Session.frame(session, %{view: view, events: []})
      assert session.cue == %{piece: "hum", section: :on, layers: %{}}
      :ok = Session.leave(session)
    end

    test "the policy's rate caps what a session gets, and a rate change restarts its audio and tells the browser",
         %{world: world} do
      Policy.set(music: :dynamic, rate: 22_050)

      {:ok, session, pushes} =
        Session.join(DotsWeb, world, "fay", %{settings: %{sfx: 1.0, music: 0.0}})

      assert {"audio", %{rate: 22_050, channels: 2}} in pushes
      assert Audio.rate(session.audio) == {22_050, 2}
      {session, pushes} = Session.rerate(session, 44_100)
      assert pushes == [{"audio", %{rate: 44_100, channels: 2}}]
      assert Audio.rate(session.audio) == {44_100, 2}
      :ok = Session.leave(session)
    end
  end

  test "a world of the player's own starts a world for them, can be paused, and stops when they leave" do
    %{world: own} = Game.world(DotsWeb, %{}, "own")

    {:ok, session, _pushes} =
      Session.join(DotsWeb, own, "dave", %{settings: %{sfx: 0.0, music: 0.0}},
        sink: TuningFork.Sink.Silent
      )

    assert is_pid(session.local_world)
    assert_receive {:cauldron_frame, _}, 500
    session = Session.toggle_pause(session)
    assert World.paused?(session.local_world)
    world = session.local_world
    :ok = Session.leave(session)
    refute Process.alive?(world)
  end

  def versioned_sheet_url,
    do:
      "/atlas.png?v=" <> Integer.to_string(:persistent_term.get({__MODULE__, :sheet_version}, 1))

  test "a changed atlas sends a new sheet and the map again, at the address the game gives for it then",
       %{world: world} do
    :persistent_term.put({__MODULE__, :sheet_version}, 1)

    {:ok, session, [{"sheet", %{url: "/atlas.png?v=1"}}, _audio]} =
      Session.join(DotsWeb, world, "carol", %{settings: %{sfx: 0.0, music: 0.0}},
        sink: TuningFork.Sink.Silent,
        sheet_url: {__MODULE__, :versioned_sheet_url}
      )

    assert_receive {:cauldron_frame, message}, 500
    {session, [{"map", _}, {"frame", _}]} = Session.frame(session, message)

    Atlas.new(:dots_web, tile: 4)
    |> Atlas.put(:wall, Raster.new(4, 4, background: {0, 0, 200, 255}))
    |> Atlas.put(:dot, Raster.new(4, 4, background: {250, 250, 250, 255}))
    |> Atlas.put(:gem, Raster.new(4, 4, background: {0, 250, 0, 255}))
    |> Atlas.install()

    assert_receive {:cauldron_atlas, :dots_web, :changed}
    :persistent_term.put({__MODULE__, :sheet_version}, 2)

    {session, [{"sheet", %{arts: %{"gem" => _}, url: "/atlas.png?v=2"}}]} =
      Session.atlas_changed(session)

    assert_receive {:cauldron_frame, message}, 500
    {_session, [{"map", _}, {"frame", _}]} = Session.frame(session, message)
    :ok = Session.leave(session)
  end
end
