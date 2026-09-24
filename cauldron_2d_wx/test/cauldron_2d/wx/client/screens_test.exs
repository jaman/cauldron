defmodule Cauldron2D.Wx.Client.ScreensTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Wx.Client.Screens

  defmodule Game do
    @moduledoc false
    def title, do: %{name: "DOTS", tagline: "little dots"}
    def keymaps, do: [arrows: %{left: [:left], right: [:right]}, wasd: %{left: [:a], right: [:d]}]

    def guide,
      do: [
        {"Things",
         [%{art: :dot, name: "Dot", text: "a dot"}, %{art: :dot, name: "Other", text: "another"}]}
      ]
  end

  defp texts(items), do: Enum.map(items, &elem(&1, 2))
  defp actions(items), do: items |> Enum.map(&elem(&1, 5)) |> Enum.reject(&is_nil/1)

  defp state(extra) do
    Map.merge(
      %{
        game: Game,
        username: "alice",
        screen: :title,
        worlds: [
          %{
            id: :pit,
            name: "The Pit",
            world: :none,
            players: 2,
            map: "pit",
            kind: {"race", {0, 200, 0}},
            note: "two racers",
            teams: [1, 2]
          },
          %{id: :ring, name: "Ring", world: :none, players: 0}
        ],
        selected: 0,
        team: nil,
        settings: %{preset: :arrows, sfx: 0.85, music: 0.35, pointer: true},
        setting: 0,
        summary: nil,
        guide_offset: 0,
        pages: [
          %{key: :n, hint: "No sound?", title: "Sound", render: fn -> [["run the player"]] end}
        ],
        page: nil,
        status: "",
        lobby?: true
      },
      extra
    )
  end

  test "the title names the game, the player, the keys and the game's pages" do
    items = Screens.draw(state(%{}), {800, 600})
    assert "DOTS" in texts(items)
    assert Enum.any?(texts(items), &(&1 =~ "little dots"))
    assert Enum.any?(texts(items), &(&1 =~ "alice"))
    assert Enum.any?(texts(items), &(&1 =~ "No sound?"))

    assert :play in actions(items) and :settings in actions(items) and :guide in actions(items) and
             {:page, :n} in actions(items)
  end

  test "the lobby lists the worlds with the chosen one marked, its kind, players, note and teams" do
    items = Screens.draw(state(%{screen: :lobby}), {800, 600})
    assert Enum.any?(texts(items), &(&1 =~ "▶ The Pit"))
    assert Enum.any?(texts(items), &(&1 =~ "race"))
    assert Enum.any?(texts(items), &(&1 =~ "2 playing"))
    assert Enum.any?(texts(items), &(&1 =~ "two racers"))
    assert Enum.any?(texts(items), &(&1 =~ "team"))
    assert {:row, 0} in actions(items) and {:row, 1} in actions(items)
    chosen = Screens.draw(state(%{screen: :lobby, selected: 1, team: 2}), {800, 600})
    assert Enum.any?(texts(chosen), &(&1 =~ "▶ Ring"))
  end

  test "settings show the preset with its keys, the levels and the pointer, the chosen one marked" do
    items = Screens.draw(state(%{screen: :settings, setting: 1}), {800, 600})
    assert Enum.any?(texts(items), &(&1 =~ "arrows"))
    assert Enum.any?(texts(items), &(&1 =~ "left"))
    assert Enum.any?(texts(items), &(&1 =~ "▶ effects"))
    assert Enum.any?(texts(items), &(&1 =~ "85%"))
    assert {:setting, 0} in actions(items) and {:step, 1, 1} in actions(items)
  end

  test "the summary shows the outcome and the ways on; the guide shows entries from an offset; a page shows its rows" do
    summary =
      Screens.draw(
        state(%{screen: :summary, summary: %{title: "Far", lines: ["you got there"]}}),
        {800, 600}
      )

    assert "Far" in texts(summary) and "you got there" in texts(summary)
    assert :again in actions(summary)

    guide = Screens.draw(state(%{screen: :guide, guide_offset: 2}), {800, 600})
    assert Enum.any?(texts(guide), &(&1 =~ "Other"))
    refute Enum.any?(texts(guide), &(&1 =~ "a dot"))

    page = Screens.draw(state(%{screen: :page, page: :n}), {800, 600})
    assert "Sound" in texts(page) and "run the player" in texts(page)
  end

  test "a status line is shown on any screen" do
    items = Screens.draw(state(%{screen: :lobby, status: "could not join: full"}), {800, 600})
    assert Enum.any?(texts(items), &(&1 =~ "could not join: full"))
  end
end
