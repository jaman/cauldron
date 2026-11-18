defmodule Cauldron.MenuTest do
  use ExUnit.Case, async: true

  alias Cauldron.Menu
  alias Cauldron.Menu.Item

  @pages %{
    main: %{
      title: "MAIN",
      items: [
        Item.action("PLAY", [{:request, :play}, :close]),
        Item.gap(),
        Item.page("OPTIONS", :options),
        Item.action("QUIT", {:confirm, "SURE?", :leave})
      ]
    },
    options: %{
      title: "OPTIONS",
      items: [
        Item.slider("MUSIC", [:music], {0.0, 1.0}, step: 0.1),
        Item.toggle("FLASH", [:options, :flash]),
        Item.binding("JUMP", :jump),
        Item.text("NAME", [:options, :name], max: 3)
      ]
    }
  }

  @settings %{music: 0.5, bindings: %{jump: [:" "]}, options: %{}}

  defp press(menu, keys) do
    Enum.reduce(List.wrap(keys), %{menu: menu, settings: menu.settings}, fn key, acc ->
      Menu.event(acc.menu, {:key, key}, acc.settings)
    end)
  end

  test "the cursor skips a gap and wraps around the page" do
    menu = Menu.open(@pages, @settings)
    assert Menu.focused(press(menu, :down).menu).label == "OPTIONS"
    assert Menu.focused(press(menu, :up).menu).label == "QUIT"
  end

  test "choosing an action can send the world a request and close the menu" do
    reply = press(Menu.open(@pages, @settings), :enter)
    assert reply.menu == nil
    assert reply.request == :play
    assert reply.settings == @settings
  end

  test "a controller's A chooses as Enter does" do
    reply = Menu.event(Menu.open(@pages, @settings), {:key, :enter, [:pad]}, @settings)
    assert reply.request == :play
  end

  test "a slider stops at its end and a page goes back to the one it came from" do
    menu = press(Menu.open(@pages, @settings), [:down, :enter]).menu
    assert Menu.page_name(menu) == :options

    reply = press(menu, List.duplicate(:right, 7))
    assert reply.settings.music == 1.0

    back = press(reply.menu, :escape)
    assert Menu.page_name(back.menu) == :main
    assert back.settings.music == 1.0
  end

  test "a binding takes the next key as the action's only key" do
    menu = press(Menu.open(@pages, @settings, open: :options), [:down, :down, :enter]).menu
    assert Menu.prompt(menu).kind == :binding
    reply = press(menu, :w)
    assert reply.settings.bindings.jump == [:w]
    assert Menu.prompt(reply.menu) == nil
  end

  test "typing keeps at most the item's characters and Enter stores them" do
    menu = press(Menu.open(@pages, @settings, open: :options), [:up, :enter]).menu
    reply = press(menu, [:a, :b, :c, :d, :backspace, :e, :enter])
    assert reply.settings.options.name == "abe"
  end

  test "a confirm does its result on yes and nothing on no" do
    menu = press(Menu.open(@pages, @settings), [:up, :enter]).menu
    assert Menu.prompt(menu) == %{kind: :confirm, text: "SURE?", pad?: false}
    assert press(menu, :n).menu.mode == :browse
    assert press(menu, :y) |> Map.take([:menu, :leave]) == %{menu: nil, leave: true}
  end

  test "a confirm opened from a controller is answered with A and B" do
    pad = fn menu, key -> Menu.event(menu, {:key, key, [:pad]}, @settings) end

    menu =
      Menu.open(@pages, @settings)
      |> pad.(:up)
      |> Map.fetch!(:menu)
      |> pad.(:enter)
      |> Map.fetch!(:menu)

    assert Menu.prompt(menu).pad?
    assert pad.(menu, :escape).menu.mode == :browse
    assert pad.(menu, :enter).leave
  end

  test "the game's own action works the menu through the player's bindings" do
    menu = Menu.open(@pages, @settings, actions: %{jump: :choose})
    assert Menu.event(menu, {:key, :" "}, @settings).request == :play
  end
end
