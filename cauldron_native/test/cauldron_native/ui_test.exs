defmodule CauldronNative.UITest do
  use ExUnit.Case, async: true

  import CauldronNative.UI

  alias CauldronNative.App.Runtime
  alias CauldronNative.UI.Tree

  defmodule Counter do
    use CauldronNative.App

    @impl true
    def mount(params), do: %{count: Map.get(params, :start, 0), name: "", locked: false}

    @impl true
    def render(state) do
      vstack([
        text("Count #{state.count}"),
        button("Add", on_tap: {:add, 1}, disabled: state.locked),
        text_field("Name", value: state.name, on_change: :name)
      ])
    end

    @impl true
    def handle_event({:add, amount}, _value, state), do: %{state | count: state.count + amount}
    def handle_event(:name, text, state), do: %{state | name: text}
  end

  test "the first patch holds every node; a change sends only the nodes that changed, and removed ids" do
    first = Tree.build(vstack([text("a"), text("b"), button("Go", on_tap: :go)]))
    patch = Tree.diff(Tree.empty(), first)
    assert Enum.map(patch.nodes, & &1["id"]) == ["r", "r/0", "r/1", "r/2"]

    assert %{"type" => "button", "events" => ["tap"], "props" => %{"title" => "Go"}} =
             Enum.at(patch.nodes, 3)

    second = Tree.build(vstack([text("a"), text("c"), button("Go", on_tap: :go)]))

    assert %{nodes: [%{"id" => "r/1", "props" => %{"content" => "c"}}], removed: []} =
             Tree.diff(first, second)

    third = Tree.build(vstack([text("a")]))

    assert %{nodes: [%{"id" => "r", "children" => ["r/0"]}], removed: ["r/1", "r/2"]} =
             Tree.diff(first, third)

    assert Tree.unchanged?(Tree.diff(third, third))
  end

  test "rows with ids keep them when they move, so only the parent's order changes" do
    rows = fn order -> Tree.build(list(for n <- order, do: text("row #{n}", id: n))) end
    patch = Tree.diff(rows.([1, 2, 3]), rows.([3, 1, 2]))
    assert %{nodes: [%{"id" => "r", "children" => ["r/k3", "r/k1", "r/k2"]}], removed: []} = patch
  end

  test "an event reaches the app with its value, and only what changed goes back; a disabled control's events are passed over" do
    test = self()

    {:ok, runtime} =
      Runtime.start_link(
        app: Counter,
        params: %{start: 5},
        send: &send(test, {:patch, JSON.decode!(&1)})
      )

    assert_receive {:patch, %{"nodes" => first}}
    assert length(first) == 4

    send(runtime, {:cauldron_native, :ui, ~s({"id":"r/1","kind":"tap"})})

    assert_receive {:patch,
                    %{
                      "nodes" => [%{"id" => "r/0", "props" => %{"content" => "Count 6"}}],
                      "removed" => []
                    }}

    send(runtime, {:cauldron_native, :ui, ~s({"id":"r/2","kind":"change","value":"Ann"})})
    assert_receive {:patch, %{"nodes" => [%{"id" => "r/2", "props" => %{"value" => "Ann"}}]}}

    send(runtime, {:cauldron_native, :ui, ~s({"id":"r/0","kind":"tap"})})
    :sys.replace_state(runtime, &put_in(&1.state.locked, true))
    send(runtime, {:cauldron_native, :ui, ~s({"id":"r/2","kind":"change","value":"Bo"})})
    assert_receive {:patch, _}
    send(runtime, {:cauldron_native, :ui, ~s({"id":"r/1","kind":"tap"})})
    assert Runtime.state(runtime).count == 6
  end

  defmodule Choices do
    use CauldronNative.App

    @impl true
    def mount(_params), do: %{size: :m, day: ~D[2026-10-23], tab: :home}

    @impl true
    def render(state) do
      vstack([
        picker("Size", [{:s, "Small"}, {:m, "Medium"}, {:l, "Large"}],
          value: state.size,
          on_change: :size
        ),
        date_picker("Day", state.day, on_change: :day),
        tabs([tab("Home", [], id: :home), tab("Me", [], id: :me)],
          selected: state.tab,
          on_select: :tab
        )
      ])
    end

    @impl true
    def handle_event(key, value, state), do: Map.put(state, key, value)
  end

  test "a picker, a date picker and tabs send the platform positions and ISO text, and give the app back its own terms" do
    test = self()

    {:ok, runtime} =
      Runtime.start_link(app: Choices, send: &send(test, {:patch, JSON.decode!(&1)}))

    assert_receive {:patch, %{"nodes" => nodes}}
    props = Map.new(nodes, &{&1["id"], &1["props"]})
    assert %{"options" => ["Small", "Medium", "Large"], "value" => 1} = props["r/0"]
    assert %{"value" => "2026-10-23", "mode" => "date"} = props["r/1"]
    assert %{"selected" => 0} = props["r/2"]

    send(runtime, {:cauldron_native, :ui, ~s({"id":"r/0","kind":"change","value":2})})
    send(runtime, {:cauldron_native, :ui, ~s({"id":"r/1","kind":"change","value":"2027-01-05"})})
    send(runtime, {:cauldron_native, :ui, ~s({"id":"r/2","kind":"select","value":1})})
    assert_receive {:patch, %{"nodes" => [%{"id" => "r/2", "props" => %{"selected" => 1}}]}}
    assert %{size: :l, day: ~D[2027-01-05], tab: :me} = Runtime.state(runtime)
  end
end
