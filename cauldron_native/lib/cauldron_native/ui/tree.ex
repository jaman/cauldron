defmodule CauldronNative.UI.Tree do
  @moduledoc """
  A screen of `CauldronNative.UI` nodes as the native side keeps it: flat records keyed
  by each node's id, and the changes from one screen to the next.

  A node's id is its parent's id and its key among its siblings (`:id`, else its
  position); the root's is `"r"`. A record holds the node's type, its properties as JSON
  values, the kinds of event it has a handler for (`"tap"` for `on_tap`) and its
  children's ids. The handlers stay here, by id and kind, so only the kind of an event
  crosses to the native side and back.

      tree = Tree.build(root)
      patch = Tree.diff(previous, tree)
      Tree.handler(tree, "r/0", "tap")

  A handler is the app's event and how the control's value becomes the app's
  (`CauldronNative.UI.Value`).
  """

  alias CauldronNative.UI.{Node, Value}

  @root "r"

  @type node_record :: %{String.t() => term()}
  @type t :: %{
          records: %{String.t() => node_record()},
          handlers: %{String.t() => %{String.t() => {term(), Value.decode()}}}
        }
  @type patch :: %{root: String.t(), nodes: [node_record()], removed: [String.t()]}

  @doc "An empty tree, before the first screen."
  @spec empty() :: t()
  def empty, do: %{records: %{}, handlers: %{}}

  @doc "The tree of `root`."
  @spec build(Node.t()) :: t()
  def build(%Node{} = root), do: add(empty(), root, @root)

  @doc "The records added or changed from `old` to `new`, and the ids removed; empty lists when the screen is the same."
  @spec diff(t(), t()) :: patch()
  def diff(old, new) do
    changed = for {id, record} <- new.records, Map.get(old.records, id) != record, do: record
    removed = for id <- Map.keys(old.records), not Map.has_key?(new.records, id), do: id
    %{root: @root, nodes: Enum.sort_by(changed, & &1["id"]), removed: Enum.sort(removed)}
  end

  @doc "Whether a patch changes nothing."
  @spec unchanged?(patch()) :: boolean()
  def unchanged?(%{nodes: [], removed: []}), do: true
  def unchanged?(_patch), do: false

  @doc ~S|The app's event and its value's decoding for a `kind` of event (`"tap"`, `"change"`, …) on the node `id`, or `nil`.|
  @spec handler(t(), String.t(), String.t()) :: {term(), Value.decode()} | nil
  def handler(tree, id, kind), do: tree.handlers |> Map.get(id, %{}) |> Map.get(kind)

  @doc "The JSON a patch is sent as."
  @spec encode(patch()) :: binary()
  def encode(patch), do: JSON.encode!(patch)

  defp add(tree, %Node{} = node, id) do
    {events, props} = split_events(node.props)
    events = Map.new(events, fn {kind, event} -> {kind, {event, node.decode}} end)
    ids = child_ids(node.children, id)

    record = %{
      "id" => id,
      "type" => Atom.to_string(node.type),
      "props" => encode_props(props),
      "events" => events |> Map.keys() |> Enum.sort(),
      "children" => ids
    }

    tree = %{
      records: Map.put(tree.records, id, record),
      handlers: if(events == %{}, do: tree.handlers, else: Map.put(tree.handlers, id, events))
    }

    node.children
    |> Enum.zip(ids)
    |> Enum.reduce(tree, fn {child, child_id}, tree -> add(tree, child, child_id) end)
  end

  defp child_ids(children, parent) do
    children
    |> Enum.with_index()
    |> Enum.map(fn {child, index} -> parent <> "/" <> child_key(child, index) end)
  end

  defp child_key(%Node{key: nil}, index), do: Integer.to_string(index)
  defp child_key(%Node{key: key}, _index), do: "k" <> key_text(key)

  defp key_text(key) when is_binary(key), do: key
  defp key_text(key) when is_atom(key) or is_integer(key), do: to_string(key)
  defp key_text(key), do: key |> :erlang.term_to_binary() |> Base.url_encode64(padding: false)

  defp split_events(props) do
    {events, rest} =
      Enum.split_with(props, fn {key, value} -> event_key?(key) and value != nil end)

    {Map.new(events, fn {key, value} -> {event_kind(key), value} end), Map.new(rest)}
  end

  defp event_key?(key), do: key |> Atom.to_string() |> String.starts_with?("on_")

  defp event_kind(key), do: key |> Atom.to_string() |> String.replace_prefix("on_", "")

  defp encode_props(props) do
    for {key, value} <- props, not event_key?(key), into: %{} do
      {Atom.to_string(key), encode_prop(key, value)}
    end
  end

  defp encode_prop(:modifiers, modifiers), do: encode_modifiers(modifiers)
  defp encode_prop(_key, value), do: encode_value(value)

  defp encode_modifiers(modifiers) do
    for {name, value} <- modifiers do
      case name do
        platform when platform in [:ios, :android] ->
          [Atom.to_string(name), encode_modifiers(value)]

        _ ->
          [Atom.to_string(name), encode_value(value)]
      end
    end
  end

  defp encode_value(value) when is_boolean(value) or is_nil(value), do: value
  defp encode_value(value) when is_atom(value), do: Atom.to_string(value)
  defp encode_value(value) when is_binary(value) or is_number(value), do: value
  defp encode_value(value) when is_tuple(value), do: value |> Tuple.to_list() |> encode_value()

  defp encode_value(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {to_string(key), encode_value(item)} end)

  defp encode_value(value) when is_list(value) do
    if options?(value),
      do: encode_value(Map.new(value)),
      else: Enum.map(value, &encode_value/1)
  end

  defp options?(list),
    do: list != [] and Keyword.keyword?(list) and not Enum.all?(list, &match?({:asset, _}, &1))
end
