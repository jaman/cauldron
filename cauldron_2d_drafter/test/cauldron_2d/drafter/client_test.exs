defmodule Cauldron2D.Drafter.ClientTest do
  @moduledoc """
  The client's screens driven headlessly against a tiny game and a real world.
  """

  use ExUnit.Case, async: false

  alias Cauldron2D.{Atlas, Player, World}
  alias Cauldron2D.Drafter.Client
  alias Cauldron2D.Drafter.Client.{Screens, Settings}
  alias Cauldron2D.TestGames.Dots
  alias Drafter.Test, as: DT
  alias Drafter.Test.HeadlessDriver
  alias Drafter.Widget.Registry
  alias FrenchCurve.Raster

  defmodule DotsClient do
    @moduledoc false
    @behaviour Cauldron2D.Client.Game

    def title, do: %{name: "DOTS", tagline: "little dots"}
    def atlas, do: :dots
    def actions, do: [:left, :right]

    def keymaps,
      do: [
        wasd: %{left: [:a], right: [:d, {:mouse, :right}]},
        arrows: %{left: [:left], right: [:right]}
      ]

    def refusal_text(:already_joined), do: "you are already in it"
    def refusal_text(other), do: inspect(other)
    def player_label({:bot, n}), do: "Bot #{n}"
    def player_label("alice"), do: "red-fox-12"
    def player_label(id), do: to_string(id)

    def pages(%{served_by: %{host: host}}),
      do: [
        %{
          key: :n,
          hint: "No sound?",
          title: "Sound",
          render: fn -> [["run the player, then connect to #{host}"]] end
        }
      ]

    def pages(_props), do: []
    def toggles, do: []

    def worlds(_props) do
      humans = if Process.whereis(:dots_world), do: World.players(:dots_world), else: []

      [
        %{
          id: :main,
          name: "Main",
          world: :dots_world,
          players: length(humans),
          humans: humans,
          map: "flat"
        },
        %{id: :other, name: "Other", world: :dots_world, players: 0, map: "flat"}
      ]
    end

    def scene(view),
      do: %{
        focus: view.me.pos,
        bounds: {view.width, view.height},
        cell: fn _ -> {:floor, [], nil} end,
        movers: view.movers
      }

    def hud(view),
      do: %{
        left: [["SIDE"], ["x=#{elem(view.me.pos, 0) |> Float.round(1)}"]],
        width: 12,
        bottom: [["under the world"]]
      }

    def listener(view), do: view.me.pos
    def sounds, do: fn _ -> nil end
    def music, do: []
    def cue(_view, _screen), do: nil
    def steering, do: [:left, :right]
    def client_keys, do: %{fps: :i, display: :g, glyphs: :b, mouse_look: :m}

    def outcome(%{me: %{pos: {x, _}}}) when x > 6.0,
      do: %{
        title: "Far enough",
        lines: ["you reached x=" <> Float.to_string(Float.round(x, 1))],
        next: :same_world
      }

    def outcome(_view), do: nil

    def guide do
      [
        {"Dots",
         for(
           n <- 1..30,
           do: %{
             art: :dot,
             name: "Dot #{n}",
             text: "the #{n}th dot, which is white like the others"
           }
         )},
        {"Floor", [%{art: :floor, name: "Floor", text: "what the dots lie on"}]}
      ]
    end
  end

  defmodule AimingDotsClient do
    @moduledoc false
    @behaviour Cauldron2D.Client.Game

    defdelegate title, to: DotsClient
    defdelegate atlas, to: DotsClient
    defdelegate actions, to: DotsClient
    defdelegate keymaps, to: DotsClient
    defdelegate toggles, to: DotsClient
    defdelegate worlds(props), to: DotsClient
    defdelegate scene(view), to: DotsClient
    defdelegate hud(view), to: DotsClient
    defdelegate listener(view), to: DotsClient
    defdelegate sounds, to: DotsClient
    defdelegate music, to: DotsClient
    defdelegate cue(view, screen), to: DotsClient
    defdelegate steering, to: DotsClient

    def padmap(_props), do: %{aim: [{:stick, :left}], left: [:dpad_left], right: [:dpad_right]}
  end

  setup_all do
    Atlas.new(:dots, tile: 8)
    |> Atlas.put(:floor, Raster.new(8, 8, background: {20, 20, 30, 255}),
      glyph: "· ",
      color: {60, 60, 80}
    )
    |> Atlas.put(:dot, Raster.new(8, 8, background: {250, 250, 250, 255}),
      glyph: "@ ",
      color: {250, 250, 250}
    )
    |> Atlas.install()

    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Registry.register(Cauldron2D.Drafter.Surface)
    :ok
  end

  setup do
    {:ok, world} = World.start_link(game: Dots, hz: 50, name: :dots_world)

    dir =
      Path.join(
        System.tmp_dir!(),
        "client_test_#{System.os_time(:nanosecond)}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    previous_config = System.get_env("XDG_CONFIG_HOME")
    System.put_env("XDG_CONFIG_HOME", Path.join(dir, "config"))

    {:ok, accounts} =
      Drafter.Accounts.start_link(path: Path.join(dir, "accounts.bin"), iterations: 1_000)

    case Drafter.Accounts.register(accounts, "alice", "correct horse") do
      :ok -> :ok
      other -> raise "register #{inspect(other)} dir=#{dir} ls=#{inspect(File.ls!(dir))}"
    end

    ctx =
      DT.start_headless(
        Client,
        %{
          game: DotsClient,
          username: "alice",
          accounts: accounts,
          sink: TuningFork.Sink.Silent,
          settings: %{display: :glyphs, pointer: false}
        },
        size: {80, 24}
      )

    on_exit(fn ->
      DT.stop(ctx)
      if Process.alive?(world), do: GenServer.stop(world)
      File.rm_rf!(dir)

      if previous_config,
        do: System.put_env("XDG_CONFIG_HOME", previous_config),
        else: System.delete_env("XDG_CONFIG_HOME")
    end)

    {:ok, ctx: ctx, world: world, accounts: accounts, config_dir: Path.join(dir, "config")}
  end

  test "a pan is kept while the scene follows the same subject and dropped when it follows another" do
    panned = %{pan: {3.0, -2.0}, subject: "alice"}
    assert Client.follow(panned, %{focus: {0.0, 0.0}, subject: "alice"}) == panned
    assert Client.follow(panned, %{focus: {0.0, 0.0}}) == panned

    assert Client.follow(panned, %{focus: {0.0, 0.0}, subject: "bob"}) == %{
             pan: {0.0, 0.0},
             subject: "bob"
           }

    assert Client.follow(%{pan: {0.0, 0.0}, subject: nil}, %{focus: {0.0, 0.0}, subject: "bob"}) ==
             %{pan: {0.0, 0.0}, subject: "bob"}
  end

  test "the session is listed under the username from mount until the client stops", %{ctx: ctx} do
    assert [%{id: "alice", kind: :terminal}] =
             Enum.filter(Cauldron2D.Sessions.list(), &(&1.id == "alice"))

    Cauldron2D.Sessions.subscribe()
    DT.stop(ctx)
    assert_receive {:cauldron_sessions, :closed, %{id: "alice"}}
    assert Enum.filter(Cauldron2D.Sessions.list(), &(&1.id == "alice")) == []
  end

  test "the arrow keys move the lobby's selection even though the chat line could take focus", %{
    ctx: ctx
  } do
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "▶ Main" end)

    DT.send_key(ctx, :down)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "▶ Other" end)

    DT.send_key(ctx, :up)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "▶ Main" end)

    DT.send_key(ctx, :j)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "▶ Other" end)
    refute DT.screen_text(ctx) =~ "j\n"
  end

  test "the wheel moves the lobby's selection and a click chooses a row, a second click joins it",
       %{ctx: ctx, world: world} do
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "▶ Main" end)

    DT.send_mouse(ctx, %{type: :scroll, direction: :down, x: 5, y: 5, modifiers: []})
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "▶ Other" end)

    row = ctx |> DT.screen_lines() |> Enum.find_index(&String.contains?(&1, "Main"))
    DT.send_mouse(ctx, %{type: :mouse_down, button: :left, x: 4, y: row, modifiers: []})
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "▶ Main" end)

    DT.send_mouse(ctx, %{type: :mouse_down, button: :left, x: 4, y: row, modifiers: []})
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)
  end

  test "a refused join is said in the lobby rather than swallowed", %{ctx: ctx, world: world} do
    :ok = Player.join(world, "alice", %{username: "alice"})
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "▶ Main" end)
    DT.send_key(ctx, :enter)

    assert :ok ==
             DT.wait_for(ctx, fn c ->
               DT.screen_text(c) =~ "could not join: you are already in it"
             end)
  end

  test "pointer steering is on unless the player turned it off, and presets come in the game's order" do
    alias Cauldron2D.Drafter.Client.Settings
    assert Settings.new(DotsClient).pointer
    refute Settings.new(DotsClient, %{pointer: false}).pointer
    assert Settings.presets(DotsClient) == [:wasd, :arrows]
    assert Settings.new(DotsClient).preset == :wasd
  end

  test "a game's pages show as small buttons on the title, and the lobby's kind column and player labels are the game's" do
    served = %{
      game: DotsClient,
      username: "alice",
      pages: DotsClient.pages(%{served_by: %{host: "arcade"}}),
      keys: Client.default_keys()
    }

    tree = Screens.title(served)
    {:layout, :vertical, children, _} = tree

    assert {:layout, :horizontal, [_spacer, {:button, "No sound?  n", opts}], _} =
             List.last(children)

    assert opts[:compact] == true
    assert opts[:on_click] == {:page, :n}

    refute Enum.any?(
             flatten_tree(Screens.title(%{served | pages: []})),
             &match?({:button, _, _}, &1)
           )

    assert Enum.any?(labels(Screens.page(served, :n)), &(&1 =~ "connect to arcade"))

    plain =
      labels(
        Screens.lobby(%{
          game: DotsClient,
          username: "alice",
          keys: Client.default_keys(),
          chat?: true,
          lobby: %{selected: 0, messages: [], team: nil}
        })
      )

    assert Enum.any?(plain, &(&1 =~ ~r/Worlds\s+Players\s+Map/))
    refute Enum.any?(plain, &(&1 =~ "Kind"))
  end

  test "the lobby's header shows the player their own name and, when the game writes them differently, how others see them" do
    header = fn username ->
      Screens.lobby(%{
        game: DotsClient,
        username: username,
        keys: Client.default_keys(),
        chat?: true,
        lobby: %{selected: 0, messages: [], team: nil}
      })
      |> flatten_tree()
      |> Enum.find_value(fn
        {:header, text, _} -> text
        _ -> nil
      end)
    end

    assert header.("alice") =~ "alice (red-fox-12)"
    assert header.("bob") =~ "bob"
    refute header.("bob") =~ "("
  end

  test "h opens the guide from the title and the lobby, the arrows and page keys scroll it, Esc returns",
       %{ctx: ctx} do
    DT.send_key(ctx, :h)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Dot 1" end)
    text = DT.screen_text(ctx)
    assert text =~ "Dots" and text =~ "the 1th dot"
    refute text =~ "Dot 30"
    refute text =~ "Floor"

    DT.send_key(ctx, :page_down)
    DT.send_key(ctx, :page_down)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Dot 30" end)
    assert DT.screen_text(ctx) =~ "what the dots lie on"
    DT.send_key(ctx, :up)
    DT.send_key(ctx, :home)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Dot 1" end)

    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "little dots" end)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Worlds" end)
    DT.send_key(ctx, :h)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Dot 1" end)
    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Worlds" end)
  end

  test "the lobby follows players coming and going without a key being pressed", %{
    ctx: ctx,
    world: world
  } do
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "nobody yet" end)
    :ok = Player.join(world, "bob", %{})
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "bob" end)
    Player.leave(world, "bob")
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "nobody yet" end)
  end

  test "the lobby knows which world a screen row shows" do
    worlds = __MODULE__.ManyWorlds.worlds(%{})
    assert Screens.world_at(worlds, 0, 3) == 0
    assert Screens.world_at(worlds, 0, 2) == nil
    assert Screens.world_at(worlds, 0, 3 + Screens.lobby_window()) == nil
    assert Screens.world_at(worlds, 20, 3) == nil
    assert Screens.world_at(worlds, 20, 4) == 20 - div(Screens.lobby_window(), 2)
    assert Screens.world_at([], 0, 3) == nil
  end

  test "= and - zoom the world in and out, shown under the world, and 0 puts it back", %{
    ctx: ctx,
    world: world
  } do
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "x=" end, timeout: 2_000)
    refute DT.screen_text(ctx) =~ "zoom"

    DT.send_key(ctx, :=)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "zoom 2×" end)
    assert DT.get_state(ctx).zoom == 2
    DT.send_key(ctx, :=)
    DT.send_key(ctx, :=)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "zoom 4×" end)
    DT.send_key(ctx, :"0")
    assert :ok == DT.wait_for(ctx, fn c -> not (DT.screen_text(c) =~ "zoom") end)
    DT.send_key(ctx, :-)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "zoom 1/2×" end)
    assert DT.get_state(ctx).zoom == 0.5
    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Worlds" end)
    assert DT.get_state(ctx).zoom == 1
  end

  test "watching, the arrows and a drag pan the view and the wheel zooms about the pointer; 0 recentres",
       %{ctx: ctx, world: world} do
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :w)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "x=" end, timeout: 2_000)
    assert DT.get_state(ctx).watching?

    DT.send_key(ctx, :right)
    DT.send_key(ctx, :down)
    DT.sync(ctx)
    assert {dx, dy} = DT.get_state(ctx).pan
    assert dx > 0 and dy > 0

    DT.send_mouse(ctx, %{type: :mouse_down, button: :left, x: 10, y: 5, modifiers: []})
    DT.send_mouse(ctx, %{type: :drag, button: :left, x: 14, y: 7, modifiers: []})
    DT.send_mouse(ctx, %{type: :mouse_up, button: :left, x: 14, y: 7, modifiers: []})
    DT.sync(ctx)
    assert {dragged_x, dragged_y} = DT.get_state(ctx).pan
    assert dragged_x < dx and dragged_y < dy

    DT.send_mouse(ctx, %{type: :scroll, direction: :up, x: 4, y: 2, modifiers: []})
    DT.sync(ctx)
    assert DT.get_state(ctx).zoom == 2
    assert DT.get_state(ctx).pan != {dragged_x, dragged_y}

    DT.send_key(ctx, :"0")
    DT.sync(ctx)
    assert DT.get_state(ctx).pan == {0.0, 0.0}
    assert DT.get_state(ctx).zoom == 1
  end

  test "flying, the arrows steer rather than pan, and the wheel zooms about the ship", %{
    ctx: ctx,
    world: world
  } do
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "x=" end, timeout: 2_000)
    refute DT.get_state(ctx).watching?

    DT.send_key(ctx, :right)
    DT.sync(ctx)
    assert DT.get_state(ctx).pan == {0.0, 0.0}
    DT.send_mouse(ctx, %{type: :scroll, direction: :up, x: 4, y: 2, modifiers: []})
    DT.sync(ctx)
    assert DT.get_state(ctx).zoom == 2
    assert DT.get_state(ctx).pan == {0.0, 0.0}
  end

  test "a burst of wheel events, as a terminal sends for one notch, is one zoom step", %{
    ctx: ctx,
    world: world
  } do
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "x=" end, timeout: 2_000)

    for _ <- 1..3,
        do: DT.send_mouse(ctx, %{type: :scroll, direction: :up, x: 4, y: 2, modifiers: []})

    DT.sync(ctx)
    assert DT.get_state(ctx).zoom == 2

    Process.sleep(200)
    DT.send_mouse(ctx, %{type: :scroll, direction: :up, x: 4, y: 2, modifiers: []})
    DT.sync(ctx)
    assert DT.get_state(ctx).zoom == 4
  end

  test "tapping ? shows the hints until tapped again", %{ctx: ctx, world: world} do
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)

    DT.send_key(ctx, :"?")
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Esc  lobby" end, timeout: 2_000)
    assert DT.screen_text(ctx) =~ "d, mouse right  right"
    assert DT.screen_text(ctx) =~ "x="

    Process.sleep(300)
    DT.send_key(ctx, :"?")

    assert :ok ==
             DT.wait_for(ctx, fn c -> not (DT.screen_text(c) =~ "Esc  lobby") end, timeout: 2_000)

    assert DT.screen_text(ctx) =~ "x="
  end

  test "a hud with a left column stands beside the world, its bottom rows under both", %{
    ctx: ctx,
    world: world
  } do
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)

    assert :ok ==
             DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "under the world" end, timeout: 2_000)

    lines = DT.screen_lines(ctx)
    side = Enum.find_index(lines, &String.contains?(&1, "SIDE"))
    x = Enum.find_index(lines, &String.contains?(&1, "x="))
    under = Enum.find_index(lines, &String.contains?(&1, "under the world"))
    assert side == 0
    assert x == 1
    assert under >= 20, "the world fills the height above the bottom rows, got row #{under}"
    assert lines |> Enum.at(side) |> String.trim_leading() |> String.starts_with?("SIDE")
  end

  defmodule PlainHud do
    @moduledoc false
    def atlas, do: :dots
    def actions, do: []
    def scene(_view), do: %{focus: {0.0, 0.0}, bounds: {1, 1}, cell: fn _ -> nil end, movers: []}
    def hud(_view), do: [["a"]]
  end

  defmodule ColumnHud do
    @moduledoc false
    def atlas, do: :dots
    def actions, do: []
    def scene(_view), do: %{focus: {0.0, 0.0}, bounds: {1, 1}, cell: fn _ -> nil end, movers: []}
    def hud(_view), do: %{left: [["s"]], width: 14, bottom: [[{"b", {1, 2, 3}}]]}
  end

  defmodule ManyWorlds do
    @moduledoc false
    def title, do: %{name: "MANY", tagline: ""}

    def worlds(_props),
      do:
        for(
          n <- 1..40,
          do: %{
            id: n,
            name: "world #{String.pad_leading(Integer.to_string(n), 2, "0")}",
            world: :none,
            players: 0,
            map: "m"
          }
        )
  end

  defp labels(tree),
    do:
      tree
      |> flatten_tree()
      |> Enum.flat_map(fn
        {:label, text, _} when is_binary(text) -> [text]
        {:label, runs, _} when is_list(runs) -> [Enum.map_join(runs, "", &elem(&1, 0))]
        _ -> []
      end)

  defp flatten_tree({:layout, _, children, _}), do: Enum.flat_map(children, &flatten_tree/1)
  defp flatten_tree(other), do: [other]

  defmodule KindsOfWorld do
    @moduledoc false
    def title, do: %{name: "KINDS", tagline: ""}

    def worlds(_props) do
      [
        %{
          id: :flag,
          name: "flag",
          world: :none,
          players: 2,
          map: "Four Flags",
          note: "300×300, 4 bots",
          teams: [1, 2, 3, 4],
          kind: {"capture the flag", {111, 227, 154}}
        },
        %{
          id: :ring,
          name: "ring",
          world: :none,
          players: 0,
          map: "The Ring",
          note: "80×80, 2 bots",
          teams: [],
          kind: {"free for all", {255, 184, 77}}
        },
        %{
          id: :odd,
          name: "odd",
          world: :none,
          players: 0,
          map: "Odd",
          note: nil,
          teams: [],
          kind: "king of the hill"
        }
      ]
    end
  end

  test "the lobby lists worlds in columns — name, kind, who is flying, map — and describes the chosen one beside them" do
    lobby = fn selected ->
      labels(
        Screens.lobby(%{
          game: KindsOfWorld,
          username: "alice",
          keys: Client.default_keys(),
          chat?: true,
          lobby: %{selected: selected, messages: [], team: nil}
        })
      )
    end

    first = lobby.(0)
    assert Enum.any?(first, &(&1 =~ ~r/Worlds\s+Kind\s+Players\s+Map/))
    assert Enum.any?(first, &(&1 =~ ~r/▶ flag\s+capture the flag\s+2 players\s+Four Flags/))
    assert Enum.any?(first, &(&1 =~ ~r/  ring\s+free for all\s+nobody\s+The Ring/))
    assert Enum.any?(first, &(&1 =~ ~r/  odd\s+king of the hill\s+nobody\s+Odd\s*$/))
    assert Enum.any?(first, &(&1 =~ "teams 1, 2, 3, 4"))
    assert Enum.any?(first, &(&1 =~ "capture the flag"))

    second = lobby.(1)
    assert Enum.any?(second, &(&1 =~ "▶ ring"))
    refute Enum.any?(second, &(&1 =~ "teams 1"))
  end

  test "the lobby shows a window of the worlds around the selection, saying how many more lie either side" do
    lobby = fn selected ->
      labels(
        Screens.lobby(%{
          game: ManyWorlds,
          username: "alice",
          keys: Client.default_keys(),
          chat?: true,
          lobby: %{selected: selected, messages: [], team: nil}
        })
      )
    end

    top = lobby.(0)
    assert Enum.any?(top, &(&1 =~ "▶ world 01"))
    refute Enum.any?(top, &(&1 =~ "world 20"))
    assert Enum.any?(top, &(&1 =~ ~r/▼ \d+ more/))
    refute Enum.any?(top, &(&1 =~ "▲"))

    middle = lobby.(20)
    assert Enum.any?(middle, &(&1 =~ "▶ world 21"))
    assert Enum.any?(middle, &(&1 =~ ~r/▲ \d+ more/))
    assert Enum.any?(middle, &(&1 =~ ~r/▼ \d+ more/))

    last = lobby.(39)
    assert Enum.any?(last, &(&1 =~ "▶ world 40"))
    refute Enum.any?(last, &(&1 =~ "▼"))
  end

  test "the world screen lays a plain hud under the world and a column hud beside it" do
    state = fn game ->
      %{
        game: game,
        view: %{},
        settings: Settings.new(DotsClient),
        talk: [],
        talking?: false,
        help?: false,
        local_world: nil
      }
    end

    assert {:layout, :vertical, [{:cauldron_surface, _}, {:label, [{"a", %{}}], _}], _} =
             Screens.play(state.(PlainHud))

    assert {:layout, :vertical,
            [
              {:layout, :horizontal,
               [
                 {:layout, :vertical, [{:label, [{"s", %{}}], _}], column},
                 {:cauldron_surface, _}
               ], _},
              {:label, [{"b", %{fg: {1, 2, 3}}}], _}
            ], _} =
             Screens.play(state.(ColumnHud))

    assert column[:width] == 14
  end

  test "the fps key shows how many frames a second the world sends, and hides it again", %{
    ctx: ctx,
    world: world
  } do
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)
    refute DT.screen_text(ctx) =~ "frames/s"

    DT.send_key(ctx, :i)

    assert :ok ==
             DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ ~r/\d+ frames\/s/ end, timeout: 3_000)

    [count] = Regex.run(~r/(\d+) frames\/s/, DT.screen_text(ctx), capture: :all_but_first)
    assert String.to_integer(count) > 20

    DT.send_key(ctx, :"?")
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "i  frames/s" end, timeout: 2_000)

    DT.send_key(ctx, :i)

    assert :ok ==
             DT.wait_for(ctx, fn c -> not (DT.screen_text(c) =~ ~r/\d+ frames\/s/) end,
               timeout: 2_000
             )
  end

  test "holding ? shows the hints only while held", %{ctx: ctx, world: world} do
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)

    HeadlessDriver.inject_event({:key, :"?"})
    DT.sync(ctx)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Esc  lobby" end, timeout: 2_000)
    Process.sleep(300)
    HeadlessDriver.inject_event({:key_up, :/, [:shift]})
    DT.sync(ctx)

    assert :ok ==
             DT.wait_for(ctx, fn c -> not (DT.screen_text(c) =~ "Esc  lobby") end, timeout: 2_000)
  end

  test "escape walks back to the title and out", %{ctx: ctx, world: world} do
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)

    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Worlds" end)
    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "little dots" end)
    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn c -> not Process.alive?(c.app_pid) end)
  end

  test "q leaves the world for the lobby, and the lobby for the title", %{ctx: ctx, world: world} do
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)

    DT.send_key(ctx, :q)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == [] end)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Worlds" end)

    DT.send_key(ctx, :q)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "little dots" end)
  end

  test "held keys move the player and escape returns to the lobby", %{ctx: ctx, world: world} do
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)

    HeadlessDriver.inject_event({:key_release_support, true})
    HeadlessDriver.inject_event({:key_down, :d, []})
    DT.sync(ctx)
    Process.sleep(200)
    %{players: %{"alice" => %{pos: {x, _}}}} = World.snapshot(world)
    assert x > 5.0

    HeadlessDriver.inject_event({:key_up, :d, []})
    DT.sync(ctx)
    Process.sleep(100)
    %{players: %{"alice" => %{pos: {settled, _}}}} = World.snapshot(world)
    Process.sleep(100)
    %{players: %{"alice" => %{pos: {still, _}}}} = World.snapshot(world)
    assert_in_delta settled, still, 0.001

    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == [] end)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Worlds" end)
  end

  test "the pointer steers only when pointer steering is on", %{ctx: ctx, world: world} do
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "x=" end, timeout: 2_000)

    HeadlessDriver.inject_event({:mouse, %{type: :move, x: 30, y: 3, button: nil, modifiers: []}})

    DT.sync(ctx)
    Process.sleep(100)
    assert %{players: %{"alice" => %{aim: nil}}} = World.snapshot(world)

    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Worlds" end)
    DT.send_key(ctx, :s)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Pointer steering   off" end)
    for _ <- 1..3, do: DT.send_key(ctx, :down)
    DT.send_key(ctx, :right)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Pointer steering   on" end)
    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Worlds" end)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "x=" end, timeout: 2_000)

    HeadlessDriver.inject_event({:mouse, %{type: :move, x: 30, y: 3, button: nil, modifiers: []}})

    DT.sync(ctx)

    assert :ok ==
             DT.wait_for(
               ctx,
               fn _ ->
                 match?(%{players: %{"alice" => %{aim: {_, _}}}}, World.snapshot(world))
               end,
               timeout: 2_000
             )
  end

  test "settings rebind a key with Enter and are saved to the account and to disk", %{
    ctx: ctx,
    accounts: accounts,
    config_dir: config_dir
  } do
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :s)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Controls" end)
    assert DT.screen_text(ctx) =~ "[wasd]"
    assert DT.screen_text(ctx) =~ "left: a"

    DT.send_key(ctx, :enter)
    refute DT.screen_text(ctx) =~ "press a key", "Enter on the preset row rebinds nothing"
    DT.send_key(ctx, :down)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "press a key" end)
    DT.send_key(ctx, :h)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "left: a, h" end)
    DT.send_key(ctx, :backspace)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "left: a\n" end)
    DT.send_key(ctx, :backspace)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ ~r/left: *\n/ end)
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :h)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "left: h\n" end)

    DT.send_key(ctx, :up)
    DT.send_key(ctx, :right)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "[arrows]" end)
    assert DT.screen_text(ctx) =~ "left: left"
    DT.send_key(ctx, :left)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "[wasd]" end)
    DT.send_key(ctx, :down)
    DT.send_key(ctx, :backspace)
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :h)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "left: h\n" end)

    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Worlds" end)

    assert {:ok, %{props: %{settings: %{bindings: %{left: [:h]}}}}} =
             Drafter.Accounts.fetch(accounts, "alice")

    assert File.exists?(Path.join([config_dir, "dots", "alice.settings"]))

    assert %{bindings: %{left: [:h]}} =
             Settings.load(DotsClient, "alice") |> Map.from_struct()

    alias Cauldron2D.Drafter.Client.Settings
    desktop = Settings.load(DotsClient, "alice", %{}, kind: :desktop)
    assert desktop.bindings.left == [:a]

    :ok =
      Settings.save(Settings.nudge(desktop, :sfx, -0.5), DotsClient, "alice", accounts,
        kind: :desktop
      )

    assert File.exists?(Path.join([config_dir, "dots", "alice.desktop.settings"]))

    assert {:ok, %{props: %{settings_desktop: %{sfx: sfx}, settings: %{bindings: %{left: [:h]}}}}} =
             Drafter.Accounts.fetch(accounts, "alice")

    assert sfx < 0.5
    assert Settings.load(DotsClient, "alice", %{}, kind: :desktop).sfx == sfx
    assert Settings.load(DotsClient, "alice").sfx > 0.5
  end

  test "under the kitty protocol Enter starts a rebind without binding itself, and Escape cancels",
       %{ctx: ctx} do
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :s)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "left: a" end)
    DT.send_key(ctx, :down)

    HeadlessDriver.inject_event({:key_release_support, true})

    for event <- [{:key, :enter}, {:key_down, :enter, []}, {:key_up, :enter, []}],
        do: HeadlessDriver.inject_event(event)

    DT.sync(ctx)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "press a key" end)

    for event <- [{:key, :escape}, {:key_down, :escape, []}, {:key_up, :escape, []}],
        do: HeadlessDriver.inject_event(event)

    DT.sync(ctx)

    assert :ok ==
             DT.wait_for(ctx, fn c ->
               DT.screen_text(c) =~ "left: a" and not (DT.screen_text(c) =~ "press a key")
             end)

    for event <- [
          {:key, :enter},
          {:key_down, :enter, []},
          {:key_up, :enter, []},
          {:key, :h},
          {:key_down, :h, []},
          {:key_up, :h, []}
        ],
        do: HeadlessDriver.inject_event(event)

    DT.sync(ctx)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "left: a, h" end)
  end

  test "settings open from the title and return to it", %{ctx: ctx} do
    assert DT.screen_text(ctx) =~ "s  settings"
    DT.send_key(ctx, :s)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Controls" end)
    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "little dots" end)
  end

  test "settings open over the world with Tab, keep the player in the world, and return", %{
    ctx: ctx,
    world: world
  } do
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)

    DT.send_key(ctx, :tab)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Controls" end)
    assert World.players(world) == ["alice"]
    DT.send_key(ctx, :right)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "[arrows]" end)

    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "x=" end, timeout: 2_000)
    assert World.players(world) == ["alice"]

    HeadlessDriver.inject_event({:key_release_support, true})
    HeadlessDriver.inject_event({:key_down, :right, []})
    DT.sync(ctx)
    Process.sleep(200)
    %{players: %{"alice" => %{pos: {x, _}}}} = World.snapshot(world)
    assert x > 5.0, "the new preset's keys steer after returning from settings"
  end

  test "chat reaches the lobby", %{ctx: ctx} do
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :c)
    for key <- [:h, :i], do: DT.send_key(ctx, key)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "red-fox-12: hi" end)
  end

  test "every settings item is reachable with the cursor and changed with the arrows", %{ctx: ctx} do
    DT.send_key(ctx, :s)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Controls" end)
    assert DT.screen_text(ctx) =~ "↑ ↓  choose"

    DT.send_key(ctx, :right)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "[arrows]" end)
    for _ <- 1..3, do: DT.send_key(ctx, :down)
    DT.send_key(ctx, :right)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Pointer steering   on" end)
    DT.send_key(ctx, :down)
    DT.send_key(ctx, :left)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "75%" end)
    DT.send_key(ctx, :down)
    DT.send_key(ctx, :right)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "45%" end)
    DT.send_key(ctx, :down)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "▶ Display   glyphs" end)
    DT.send_key(ctx, :right)

    assert :ok ==
             DT.wait_for(ctx, fn c ->
               DT.screen_text(c) =~ "Display   pixels where the terminal has them"
             end)

    DT.send_key(ctx, :right)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Display   braille" end)
    DT.send_key(ctx, :down)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "▶ Frame rate   auto" end)
    DT.send_key(ctx, :right)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Frame rate   15 fps" end)
    assert Drafter.AppRegistry.get_frame_interval() == 67
    DT.send_key(ctx, :left)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Frame rate   auto" end)
    assert Drafter.AppRegistry.get_frame_interval() == 33
    DT.send_key(ctx, :down)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "▶ Controls" end)
  end

  test "braille is a display choice the world draws with", %{ctx: ctx, world: world} do
    DT.send_key(ctx, :s)
    for _ <- 1..6, do: DT.send_key(ctx, :down)
    DT.send_key(ctx, :right)
    DT.send_key(ctx, :right)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Display   braille" end)
    DT.send_key(ctx, :escape)
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)

    assert :ok ==
             DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ ~r/[\x{2801}-\x{28FF}]/u end,
               timeout: 2_000
             )
  end

  test "a bound mouse button holds its action from press to release", %{ctx: ctx, world: world} do
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "x=" end, timeout: 2_000)

    HeadlessDriver.inject_event(
      {:mouse, %{type: :mouse_down, button: :right, x: 10, y: 3, modifiers: []}}
    )

    DT.sync(ctx)
    Process.sleep(200)
    %{players: %{"alice" => %{pos: {x, _}}}} = World.snapshot(world)
    assert x > 5.0

    HeadlessDriver.inject_event(
      {:mouse, %{type: :mouse_up, button: :right, x: 10, y: 3, modifiers: []}}
    )

    DT.sync(ctx)
    Process.sleep(100)
    %{players: %{"alice" => %{pos: {settled, _}}}} = World.snapshot(world)
    Process.sleep(100)
    %{players: %{"alice" => %{pos: {still, _}}}} = World.snapshot(world)
    assert_in_delta settled, still, 0.001
  end

  test "a binding can be rebound to a mouse button", %{ctx: ctx} do
    DT.send_key(ctx, :s)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "left: a" end)
    DT.send_key(ctx, :down)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "press a key" end)

    HeadlessDriver.inject_event(
      {:mouse, %{type: :mouse_down, button: :left, x: 1, y: 1, modifiers: []}}
    )

    DT.sync(ctx)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "left: a, mouse left" end)
  end

  test "when the game says it is over, the summary shows and Enter returns to the lobby", %{
    ctx: ctx,
    world: world
  } do
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)

    HeadlessDriver.inject_event({:key_release_support, true})
    HeadlessDriver.inject_event({:key_down, :d, []})
    DT.sync(ctx)

    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Far enough" end, timeout: 3_000)
    assert DT.screen_text(ctx) =~ "you reached"
    assert DT.screen_text(ctx) =~ "Enter  Main again"
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == [] end)

    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "x=" end, timeout: 2_000)

    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Worlds" end)
  end

  test "a steering key takes the aim away from the pointer until it moves again", %{
    ctx: ctx,
    world: world
  } do
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :s)
    for _ <- 1..3, do: DT.send_key(ctx, :down)
    DT.send_key(ctx, :right)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Pointer steering   on" end)
    DT.send_key(ctx, :escape)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "x=" end, timeout: 2_000)

    HeadlessDriver.inject_event({:mouse, %{type: :move, x: 30, y: 3, modifiers: []}})
    DT.sync(ctx)

    assert :ok ==
             DT.wait_for(
               ctx,
               fn _ ->
                 match?(%{players: %{"alice" => %{aim: {_, _}}}}, World.snapshot(world))
               end,
               timeout: 2_000
             )

    DT.send_key(ctx, :a)

    assert :ok ==
             DT.wait_for(
               ctx,
               fn _ -> match?(%{players: %{"alice" => %{aim: nil}}}, World.snapshot(world)) end,
               timeout: 2_000
             )

    HeadlessDriver.inject_event({:mouse, %{type: :move, x: 31, y: 3, modifiers: []}})
    DT.sync(ctx)

    assert :ok ==
             DT.wait_for(
               ctx,
               fn _ ->
                 match?(%{players: %{"alice" => %{aim: {_, _}}}}, World.snapshot(world))
               end,
               timeout: 2_000
             )
  end

  test "t opens a talk line in the world; what is said reaches everyone in it and keys do not steer meanwhile",
       %{ctx: ctx, world: world} do
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "x=" end, timeout: 2_000)

    DT.send_key(ctx, :t)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "say:" end)
    for key <- [:d, :d, :d], do: DT.send_key(ctx, key)
    Process.sleep(150)
    %{players: %{"alice" => %{pos: {x, _}}}} = World.snapshot(world)
    assert_in_delta x, 5.0, 0.001
    DT.send_key(ctx, :enter)

    assert :ok ==
             DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "red-fox-12: ddd" end, timeout: 2_000)

    refute DT.screen_text(ctx) =~ "say:"
  end
end

defmodule Cauldron2D.Drafter.ClientControllerTest do
  @moduledoc """
  A game controller's events steer the world through the client's pad.
  """

  use ExUnit.Case, async: false

  alias Cauldron2D.{Atlas, World}
  alias Cauldron2D.Drafter.Client
  alias Cauldron2D.Drafter.ClientTest.DotsClient
  alias Cauldron2D.TestGames.Dots
  alias Drafter.Test, as: DT
  alias Drafter.Test.HeadlessDriver
  alias Drafter.Widget.Registry
  alias FrenchCurve.Raster

  setup_all do
    Atlas.new(:dots, tile: 8)
    |> Atlas.put(:floor, Raster.new(8, 8, background: {20, 20, 30, 255}),
      glyph: "· ",
      color: {60, 60, 80}
    )
    |> Atlas.put(:dot, Raster.new(8, 8, background: {250, 250, 250, 255}),
      glyph: "@ ",
      color: {250, 250, 250}
    )
    |> Atlas.install()

    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Registry.register(Cauldron2D.Drafter.Surface)
    :ok
  end

  setup do
    {:ok, world} = World.start_link(game: Dots, hz: 50, name: :dots_world)

    dir = Path.join(System.tmp_dir!(), "client_pad_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    previous_config = System.get_env("XDG_CONFIG_HOME")
    System.put_env("XDG_CONFIG_HOME", Path.join(dir, "config"))

    ctx =
      DT.start_headless(
        Client,
        %{
          game: DotsClient,
          username: "alice",
          sink: TuningFork.Sink.Silent,
          settings: %{display: :glyphs, pointer: false}
        },
        size: {80, 24}
      )

    on_exit(fn ->
      DT.stop(ctx)
      if Process.alive?(world), do: GenServer.stop(world)
      File.rm_rf!(dir)

      if previous_config,
        do: System.put_env("XDG_CONFIG_HOME", previous_config),
        else: System.delete_env("XDG_CONFIG_HOME")
    end)

    {:ok, ctx: ctx, world: world}
  end

  defp pad(ctx, event) do
    HeadlessDriver.inject_event({:controller, event})
    DT.sync(ctx)
  end

  test "the left stick and the d-pad hold the game's steering actions, at the stick's strength",
       %{ctx: ctx, world: world} do
    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "x=" end, timeout: 2_000)

    pad(ctx, %{type: :connected, device: 0, name: "Pad"})
    pad(ctx, %{type: :axis, device: 0, axis: :left_x, value: 0.75})

    assert %{held: held, strength: %{right: 0.75}} = DT.get_state(ctx).last_input
    assert MapSet.to_list(held) == [:right]

    pad(ctx, %{type: :axis, device: 0, axis: :left_x, value: 0.0})
    pad(ctx, %{type: :button, device: 0, button: :dpad_left, pressed: true})

    assert %{held: held} = DT.get_state(ctx).last_input
    assert MapSet.to_list(held) == [:left]
    refute Map.has_key?(DT.get_state(ctx).last_input, :strength)

    pad(ctx, %{type: :disconnected, device: 0})
    assert MapSet.size(DT.get_state(ctx).last_input.held) == 0
  end

  test "a stick bound to aim aims a fixed way ahead of the focus in the direction it is pushed, and lets go when centred",
       %{ctx: plain, world: world} do
    DT.stop(plain)

    ctx =
      DT.start_headless(
        Client,
        %{
          game: Cauldron2D.Drafter.ClientTest.AimingDotsClient,
          username: "bob",
          sink: TuningFork.Sink.Silent,
          settings: %{display: :glyphs, pointer: true}
        },
        size: {80, 24}
      )

    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> "bob" in World.players(world) end)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "x=" end, timeout: 2_000)

    pad(ctx, %{type: :connected, device: 0, name: "Pad"})
    pad(ctx, %{type: :axis, device: 0, axis: :left_x, value: 0.0})
    pad(ctx, %{type: :axis, device: 0, axis: :left_y, value: -1.0})

    state = DT.get_state(ctx)
    {fx, fy} = Client.focus(state, Client.scene(state))
    assert %{held: held, aim: {ax, ay}} = state.last_input
    assert MapSet.size(held) == 0
    assert_in_delta ax, fx, 0.01
    assert_in_delta ay, fy - 8.0, 0.01

    pad(ctx, %{type: :axis, device: 0, axis: :left_y, value: 0.0})
    assert DT.get_state(ctx).last_input.aim == nil

    pad(ctx, %{type: :button, device: 0, button: :dpad_left, pressed: true})
    assert MapSet.to_list(DT.get_state(ctx).last_input.held) == [:left]
    DT.stop(ctx)
  end

  test "in the lobby the d-pad moves the selection and A joins", %{ctx: ctx, world: world} do
    DT.send_key(ctx, :enter)
    assert DT.get_state(ctx).screen == :lobby

    pad(ctx, %{type: :button, device: 0, button: :dpad_down, pressed: true})
    pad(ctx, %{type: :button, device: 0, button: :dpad_down, pressed: false})
    assert DT.get_state(ctx).lobby.selected == 1

    pad(ctx, %{type: :button, device: 0, button: :dpad_up, pressed: true})
    pad(ctx, %{type: :button, device: 0, button: :dpad_up, pressed: false})
    assert DT.get_state(ctx).lobby.selected == 0

    pad(ctx, %{type: :button, device: 0, button: :a, pressed: true})
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)
  end
end

defmodule Cauldron2D.Drafter.Client.SettingsDisplayTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Drafter.Client.Settings

  test "the display choices run auto, braille, the glyph sets, glyphs, and wrap" do
    settings = Settings.new(Cauldron2D.Drafter.ClientTest.DotsClient, %{})

    displays =
      Enum.scan(1..7, settings, fn _, acc -> Settings.step_display(acc, 1) end)
      |> Enum.map(& &1.display)

    assert displays == [:braille, :half, :quad, :sextant, :octant, :glyphs, :auto]
  end

  test "a glyph set is the surface mode of its name" do
    settings = Settings.new(Cauldron2D.Drafter.ClientTest.DotsClient, %{display: :octant})

    assert Settings.surface_mode(settings) == :octant
    assert Settings.surface_mode(%{settings | display: :glyphs}) == :text
  end
end

defmodule Cauldron2D.Drafter.ClientProjectionTest do
  @moduledoc """
  The world's projection, turned and tilted from the keys and the pad.
  """

  use ExUnit.Case, async: false

  alias Cauldron2D.{Atlas, World}
  alias Cauldron2D.Drafter.Client
  alias Cauldron2D.Drafter.ClientTest.DotsClient
  alias Cauldron2D.TestGames.Dots
  alias Drafter.Test, as: DT
  alias Drafter.Test.HeadlessDriver
  alias Drafter.Widget.Registry
  alias FrenchCurve.Raster

  setup_all do
    Atlas.new(:dots, tile: 8)
    |> Atlas.put(:floor, Raster.new(8, 8, background: {20, 20, 30, 255}),
      glyph: "· ",
      color: {60, 60, 80}
    )
    |> Atlas.put(:dot, Raster.new(8, 8, background: {250, 250, 250, 255}),
      glyph: "@ ",
      color: {250, 250, 250}
    )
    |> Atlas.install()

    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Registry.register(Cauldron2D.Drafter.Surface)
    :ok
  end

  setup do
    {:ok, world} = World.start_link(game: Dots, hz: 50, name: :dots_world)
    dir = Path.join(System.tmp_dir!(), "client_look_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    previous_config = System.get_env("XDG_CONFIG_HOME")
    System.put_env("XDG_CONFIG_HOME", Path.join(dir, "config"))

    ctx =
      DT.start_headless(
        Client,
        %{
          game: DotsClient,
          username: "alice",
          sink: TuningFork.Sink.Silent,
          settings: %{display: :octant, pointer: false}
        },
        size: {80, 24}
      )

    on_exit(fn ->
      DT.stop(ctx)
      if Process.alive?(world), do: GenServer.stop(world)
      File.rm_rf!(dir)

      if previous_config,
        do: System.put_env("XDG_CONFIG_HOME", previous_config),
        else: System.delete_env("XDG_CONFIG_HOME")
    end)

    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "x=" end, timeout: 2_000)

    {:ok, ctx: ctx, world: world}
  end

  defp pad(ctx, event) do
    HeadlessDriver.inject_event({:controller, event})
    DT.sync(ctx)
  end

  test "v cycles the projection through top, isometric and first person, shown under the world",
       %{ctx: ctx} do
    assert DT.get_state(ctx).look.projection == :top

    DT.send_key(ctx, :v)
    DT.sync(ctx)
    assert DT.get_state(ctx).look.projection == :iso
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "isometric" end, timeout: 2_000)

    DT.send_key(ctx, :v)
    DT.sync(ctx)
    assert DT.get_state(ctx).look.projection == :first_person

    assert :ok ==
             DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "first person" end, timeout: 2_000)

    DT.send_key(ctx, :v)
    DT.sync(ctx)
    assert DT.get_state(ctx).look.projection == :top
  end

  test "the brackets turn the isometric view and the quotes tilt it", %{ctx: ctx} do
    DT.send_key(ctx, :v)
    DT.send_key(ctx, :"]")
    DT.sync(ctx)
    assert DT.get_state(ctx).look.facing == 1

    DT.send_key(ctx, :"[")
    DT.send_key(ctx, :"[")
    DT.sync(ctx)
    assert DT.get_state(ctx).look.facing == 3

    DT.send_key(ctx, :"'")
    DT.sync(ctx)
    assert DT.get_state(ctx).look.tilt > 1.0
  end

  test "in first person the brackets turn the eye and the quotes pitch it, and the right stick does both",
       %{ctx: ctx} do
    DT.send_key(ctx, :v)
    DT.send_key(ctx, :v)
    DT.send_key(ctx, :"]")
    DT.sync(ctx)
    assert DT.get_state(ctx).look.heading > 0.0

    DT.send_key(ctx, :";")
    DT.sync(ctx)
    assert DT.get_state(ctx).look.pitch < 0.0

    before = DT.get_state(ctx).look
    pad(ctx, %{type: :axis, device: 0, axis: :right_x, value: -1.0})
    pad(ctx, %{type: :axis, device: 0, axis: :right_y, value: -1.0})

    assert :ok ==
             DT.wait_for(
               ctx,
               fn c ->
                 look = DT.get_state(c).look
                 look.heading < before.heading and look.pitch > before.pitch
               end,
               timeout: 2_000
             )
  end

  test "in first person a drag turns and pitches the eye, and the pointer alone does not",
       %{ctx: ctx} do
    DT.send_key(ctx, :v)
    DT.send_key(ctx, :v)
    DT.sync(ctx)
    assert DT.get_state(ctx).look.projection == :first_person

    DT.send_mouse(ctx, %{type: :move, x: 20, y: 10, modifiers: []})
    DT.sync(ctx)
    before = DT.get_state(ctx).look

    DT.send_mouse(ctx, %{type: :move, x: 30, y: 14, modifiers: []})
    DT.sync(ctx)
    assert DT.get_state(ctx).look.heading == before.heading, "a bare move must not steer"

    DT.send_mouse(ctx, %{type: :mouse_down, button: :left, x: 30, y: 14, modifiers: []})
    DT.send_mouse(ctx, %{type: :drag, button: :left, x: 40, y: 18, modifiers: []})
    DT.sync(ctx)
    dragged = DT.get_state(ctx).look

    assert dragged.heading > before.heading
    assert dragged.pitch < before.pitch

    DT.send_mouse(ctx, %{type: :drag, button: :left, x: 20, y: 10, modifiers: []})
    DT.sync(ctx)
    back = DT.get_state(ctx).look

    assert back.heading < dragged.heading
    assert back.pitch > dragged.pitch
  end

  test "start cycles the projection and the bumpers turn, as the game's client_pad may rebind",
       %{ctx: ctx} do
    pad(ctx, %{type: :button, device: 0, button: :start, pressed: true})
    assert DT.get_state(ctx).look.projection == :iso

    pad(ctx, %{type: :button, device: 0, button: :right_bumper, pressed: true})
    assert DT.get_state(ctx).look.facing == 1
  end

  test "in the isometric view the right stick nudges the aim a tile at a time, turned with the facing",
       %{ctx: ctx} do
    DT.send_key(ctx, :v)
    DT.send_key(ctx, :"]")
    DT.sync(ctx)

    pad(ctx, %{type: :axis, device: 0, axis: :right_x, value: 1.0})
    {fx, fy} = DT.get_state(ctx).view.me.pos
    assert %{aim: {ax, ay}} = DT.get_state(ctx).last_input
    assert_in_delta ax, fx, 0.001
    assert_in_delta ay, fy + 1, 0.001

    DT.send_mouse(ctx, %{type: :move, x: 10, y: 5, modifiers: []})
    DT.sync(ctx)
    assert DT.get_state(ctx).pad_aim == nil
  end

  test "mouse look turns the eye with the pointer in first person once switched on",
       %{ctx: ctx} do
    DT.send_key(ctx, :v)
    DT.send_key(ctx, :v)
    DT.sync(ctx)
    before = DT.get_state(ctx).look.heading

    DT.send_mouse(ctx, %{type: :move, x: 10, y: 5, modifiers: []})
    DT.send_mouse(ctx, %{type: :move, x: 20, y: 5, modifiers: []})
    DT.sync(ctx)
    assert DT.get_state(ctx).look.heading == before

    DT.send_key(ctx, :m)
    DT.send_mouse(ctx, %{type: :move, x: 30, y: 8, modifiers: []})
    DT.sync(ctx)
    assert DT.get_state(ctx).look.heading > before
    assert DT.get_state(ctx).look.pitch < 0.0
  end

  test "the display keys toggle pictures against glyph sets and cycle the sets", %{ctx: ctx} do
    assert DT.get_state(ctx).settings.display == :octant

    DT.send_key(ctx, :b)
    DT.sync(ctx)
    assert DT.get_state(ctx).settings.display == :half

    DT.send_key(ctx, :g)
    DT.sync(ctx)
    assert DT.get_state(ctx).settings.display == :auto

    DT.send_key(ctx, :g)
    DT.sync(ctx)
    assert DT.get_state(ctx).settings.display == :half
  end
end

defmodule Cauldron2D.Drafter.ClientSteeringTest do
  @moduledoc """
  The four direction actions are steered for the projection in use before they reach
  the world: turned with the isometric view, and along the eye in first person.
  """

  use ExUnit.Case, async: false

  alias Cauldron2D.{Atlas, World}
  alias Cauldron2D.Drafter.Client
  alias Cauldron2D.TestGames.Dots
  alias Drafter.Test, as: DT
  alias Drafter.Widget.Registry
  alias FrenchCurve.Raster

  defmodule FourWays do
    @moduledoc false
    @behaviour Cauldron2D.Client.Game

    def title, do: %{name: "FOUR", tagline: "ways"}
    def atlas, do: :dots
    def actions, do: [:left, :right, :up, :down]

    def keymaps,
      do: [arrows: %{left: [:left], right: [:right], up: [:up], down: [:down]}]

    def toggles, do: []

    def worlds(_props),
      do: [%{id: :main, name: "Main", world: :dots_world, players: 0, humans: [], map: "flat"}]

    def scene(view),
      do: %{
        focus: view.me.pos,
        bounds: {view.width, view.height},
        cell: fn _ -> {:floor, [], nil} end,
        movers: view.movers
      }

    def hud(_view), do: [["x="]]
    def listener(view), do: view.me.pos
    def sounds, do: fn _ -> nil end
    def music, do: []
    def cue(_view, _screen), do: nil
  end

  setup_all do
    Atlas.new(:dots, tile: 8)
    |> Atlas.put(:floor, Raster.new(8, 8, background: {20, 20, 30, 255}), glyph: "· ")
    |> Atlas.put(:dot, Raster.new(8, 8, background: {250, 250, 250, 255}), glyph: "@ ")
    |> Atlas.install()

    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Registry.register(Cauldron2D.Drafter.Surface)
    :ok
  end

  setup do
    {:ok, world} = World.start_link(game: Dots, hz: 50, name: :dots_world)
    dir = Path.join(System.tmp_dir!(), "client_steer_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    previous_config = System.get_env("XDG_CONFIG_HOME")
    System.put_env("XDG_CONFIG_HOME", Path.join(dir, "config"))

    ctx =
      DT.start_headless(
        Client,
        %{
          game: FourWays,
          username: "alice",
          sink: TuningFork.Sink.Silent,
          settings: %{display: :glyphs, pointer: false}
        },
        size: {80, 24}
      )

    on_exit(fn ->
      DT.stop(ctx)
      if Process.alive?(world), do: GenServer.stop(world)
      File.rm_rf!(dir)

      if previous_config,
        do: System.put_env("XDG_CONFIG_HOME", previous_config),
        else: System.delete_env("XDG_CONFIG_HOME")
    end)

    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "x=" end, timeout: 2_000)
    {:ok, ctx: ctx}
  end

  defp held(ctx),
    do: ctx |> DT.get_state() |> Map.fetch!(:last_input) |> Map.fetch!(:held) |> MapSet.to_list()

  test "top down, a direction is sent as pressed", %{ctx: ctx} do
    DT.send_key(ctx, :left)
    DT.sync(ctx)
    assert held(ctx) == [:left]
  end

  test "isometric, a direction is turned with the view", %{ctx: ctx} do
    DT.send_key(ctx, :v)
    DT.send_key(ctx, :"]")
    DT.sync(ctx)
    assert DT.get_state(ctx).look == %{DT.get_state(ctx).look | projection: :iso, facing: 1}

    DT.send_key(ctx, :left)
    DT.sync(ctx)
    assert held(ctx) == [:up]
  end

  test "first person, the directions go as held with the eye's heading beside them", %{ctx: ctx} do
    DT.send_key(ctx, :v)
    DT.send_key(ctx, :v)
    DT.send_key(ctx, :"]")
    DT.sync(ctx)

    DT.send_key(ctx, :up)
    DT.sync(ctx)
    assert held(ctx) == [:up]
    assert_in_delta DT.get_state(ctx).last_input.heading, :math.pi() / 12, 1.0e-9
  end
end

defmodule Cauldron2D.Drafter.ClientFlowTest do
  @moduledoc """
  Where the client starts and where back goes, as the game's `start/0` or the mount
  prop says: the lobby flow with or without a title, straight into a world, or a
  function of the game's own.
  """

  use ExUnit.Case, async: false

  alias Cauldron2D.{Atlas, World}
  alias Cauldron2D.Drafter.Client
  alias Cauldron2D.Drafter.ClientTest.DotsClient
  alias Cauldron2D.TestGames.Dots
  alias Drafter.Test, as: DT
  alias Drafter.Widget.Registry
  alias FrenchCurve.Raster

  defmodule Direct do
    @moduledoc false
    @behaviour Cauldron2D.Client.Game

    defdelegate title, to: DotsClient
    defdelegate atlas, to: DotsClient
    defdelegate actions, to: DotsClient
    defdelegate keymaps, to: DotsClient
    defdelegate toggles, to: DotsClient
    defdelegate worlds(props), to: DotsClient
    defdelegate scene(view), to: DotsClient
    defdelegate hud(view), to: DotsClient
    defdelegate listener(view), to: DotsClient
    defdelegate sounds, to: DotsClient
    defdelegate music, to: DotsClient
    defdelegate cue(view, screen), to: DotsClient
    def start, do: {:play, :other}
  end

  defmodule Custom do
    @moduledoc false
    @behaviour Cauldron2D.Client.Game

    defdelegate title, to: DotsClient
    defdelegate atlas, to: DotsClient
    defdelegate actions, to: DotsClient
    defdelegate keymaps, to: DotsClient
    defdelegate toggles, to: DotsClient
    defdelegate worlds(props), to: DotsClient
    defdelegate scene(view), to: DotsClient
    defdelegate hud(view), to: DotsClient
    defdelegate listener(view), to: DotsClient
    defdelegate sounds, to: DotsClient
    defdelegate music, to: DotsClient
    defdelegate cue(view, screen), to: DotsClient
    defdelegate guide, to: DotsClient
    def start, do: &Client.to_guide/1
  end

  setup_all do
    Atlas.new(:dots, tile: 8)
    |> Atlas.put(:floor, Raster.new(8, 8, background: {20, 20, 30, 255}), glyph: "· ")
    |> Atlas.put(:dot, Raster.new(8, 8, background: {250, 250, 250, 255}), glyph: "@ ")
    |> Atlas.install()

    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Registry.register(Cauldron2D.Drafter.Surface)
    :ok
  end

  setup do
    {:ok, world} = World.start_link(game: Dots, hz: 50, name: :dots_world)
    dir = Path.join(System.tmp_dir!(), "client_flow_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    previous_config = System.get_env("XDG_CONFIG_HOME")
    System.put_env("XDG_CONFIG_HOME", Path.join(dir, "config"))

    on_exit(fn ->
      if Process.alive?(world), do: GenServer.stop(world)
      File.rm_rf!(dir)

      if previous_config,
        do: System.put_env("XDG_CONFIG_HOME", previous_config),
        else: System.delete_env("XDG_CONFIG_HOME")
    end)

    {:ok, world: world}
  end

  defp start(game, props \\ %{}) do
    ctx =
      DT.start_headless(
        Client,
        Map.merge(
          %{
            game: game,
            username: "alice",
            sink: TuningFork.Sink.Silent,
            settings: %{display: :glyphs, pointer: false}
          },
          props
        ),
        size: {80, 24}
      )

    on_exit(fn -> DT.stop(ctx) end)
    ctx
  end

  test "the default flow is the title, then the lobby, then the world, and back retraces it",
       %{world: world} do
    ctx = start(DotsClient)
    assert DT.get_state(ctx).screen == :title

    DT.send_key(ctx, :enter)
    assert DT.get_state(ctx).screen == :lobby
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end)
    assert DT.get_state(ctx).screen == :play

    DT.send_key(ctx, :escape)
    assert DT.get_state(ctx).screen == :lobby
    DT.send_key(ctx, :escape)
    assert DT.get_state(ctx).screen == :title
  end

  test "the lobby flow without a title opens on the lobby and stops on back from it" do
    ctx = start(DotsClient, %{start: {:lobby, title: false}})
    assert DT.get_state(ctx).screen == :lobby

    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn c -> not Process.alive?(c.app_pid) end, timeout: 2_000)
  end

  test "a game that starts in a world is in it at once, with no title or lobby, and stops when the player leaves",
       %{world: world} do
    ctx = start(Direct)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end, timeout: 2_000)
    assert DT.get_state(ctx).screen == :play
    assert DT.get_state(ctx).joined.id == :other

    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn c -> not Process.alive?(c.app_pid) end, timeout: 2_000)
  end

  test "a game that starts in a world but keeps the title goes title, world, title", %{
    world: world
  } do
    ctx = start(Direct, %{start: {:play, :main, title: true}})
    assert DT.get_state(ctx).screen == :title

    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn _ -> World.players(world) == ["alice"] end, timeout: 2_000)
    assert DT.get_state(ctx).joined.id == :main

    DT.send_key(ctx, :escape)
    assert DT.get_state(ctx).screen == :title
  end

  test "a function is the game's own entry point, given the client's state" do
    ctx = start(Custom)
    assert DT.get_state(ctx).screen == :guide
  end

  test "the mount prop wins over the game's start" do
    ctx = start(Direct, %{start: :lobby})
    assert DT.get_state(ctx).screen == :title
  end
end

defmodule Cauldron2D.Drafter.ClientSteeredTest do
  @moduledoc """
  `Cauldron2D.Drafter.Client.steered/2` answers for every projection the client offers,
  and for the isometric view at more facings than four.
  """

  use ExUnit.Case, async: true

  alias Cauldron2D.Drafter.{Client, Surface}

  test "it answers for every projection a game can put the client in" do
    for projection <- Surface.projections() do
      look = %{projection: projection, facing: 0, facings: 4, heading: 0.0}

      steered = Client.steered(read([:up]), look)

      assert MapSet.member?(steered.held, :up) or Map.has_key?(steered, :heading),
             "#{projection} steered an :up into nothing the world can walk"
    end
  end

  defp read(held, strength \\ %{}),
    do: %{
      held: MapSet.new(held),
      strength: strength,
      pressed: MapSet.new(),
      released: MapSet.new()
    }

  test "isometric at finer facings sends the directions as held, with the view's heading" do
    look = %{projection: :iso, facing: 5, facings: 16, heading: 0.0}
    steered = Client.steered(read([:left]), look)
    assert MapSet.to_list(steered.held) == [:left]
    assert_in_delta steered.heading, :math.pi() / 8, 1.0e-9
  end

  test "the oblique view steers as held at its default facing and turns at four" do
    fixed = %{projection: :oblique, facing: 1, facings: 4, heading: 0.0}

    assert MapSet.to_list(Client.steered(read([:up]), fixed).held) == [:up]

    asked = %{projection: :oblique, facing: 1, facings: %{oblique: 4}, heading: 0.0}
    turned = Client.steered(read([:up]), asked)

    assert MapSet.size(turned.held) == 1
    refute MapSet.member?(turned.held, :up)
  end

  test "a facings map picks the count for the projection in view" do
    assert Client.turns_with_pointer?(%{projection: :iso, facings: %{iso: 16}})
    refute Client.turns_with_pointer?(%{projection: :iso, facings: %{iso: 4}})
    refute Client.turns_with_pointer?(%{projection: :oblique, facings: %{oblique: 4}})
    refute Client.turns_with_pointer?(%{projection: :oblique, facings: 16})
  end

  test "a drag turns first person, mode 7 and a free isometric view, but not four facings" do
    assert Client.turns_with_pointer?(%{projection: :first_person})
    assert Client.turns_with_pointer?(%{projection: :mode7})
    assert Client.turns_with_pointer?(%{projection: :iso, facings: 16})
    refute Client.turns_with_pointer?(%{projection: :iso, facings: 4})
    refute Client.turns_with_pointer?(%{projection: :oblique})
    refute Client.turns_with_pointer?(%{projection: :top})
  end

  test "of the directions a stick holds, the isometric view keeps the one pushed hardest" do
    look = %{projection: :iso, facing: 0, facings: 4, heading: 0.0}
    read = read([:left, :up], %{left: 0.9, up: 0.3})
    assert MapSet.to_list(Client.steered(read, look).held) == [:left]
  end
end
