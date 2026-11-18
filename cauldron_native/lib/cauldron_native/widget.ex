defmodule CauldronNative.Widget do
  @moduledoc """
  The app's widgets on the Home Screen: WidgetKit widgets on iOS and macOS, Glance widgets
  on Android. The app's config names each kind and its sizes (`widgets:`,
  `CauldronNative.Build.App`); the app gives a kind its content with `update/2`, or
  content for the hours ahead with `timeline/2`, and the system shows it, also while the
  app is not running.

  The content is made of `CauldronNative.UI` controls, of the kinds a widget can show:
  `text/2`, `label/2`, `icon/2`, `image/2` (of the app's catalog), `gauge/2`, `vstack/2`,
  `hstack/2`, `zstack/2`, `spacer/1`, `divider/1` and `progress/1`, with the `font`,
  `foreground`, `bold`, `padding`, `frame`, `gradient` (the widget's background, on its
  outermost control) and `tint` (a gauge's colour) modifiers. Icons take their
  `ios:` and `android:` names as `CauldronNative.UI.icon/2` does; Android draws the
  Material icon tinted with the widget's theme.

      CauldronNative.Widget.update(:orders,
        vstack([
          text("Orders", modifiers: [font: :headline]),
          text("5 waiting", modifiers: [font: :title, bold: true])
        ])
      )

  The content is one control for every size, or a map of size to control, a size one of
  `:small`, `:medium`, `:large`, `:extra_large`, and the Lock Screen's `:circular`,
  `:rectangular` and `:inline`, with `:default` for the sizes it leaves out:

      CauldronNative.Widget.update(:orders, %{
        small: vstack([...]),
        circular: gauge(7, max: 25, style: :circular, current: "7"),
        default: text("7 orders")
      })

  Android has no Lock Screen widgets and shows the Home Screen sizes. A tap on a widget
  opens the app.
  """

  alias CauldronNative.Device.Request
  alias CauldronNative.UI.Node

  @type content :: Node.t() | %{atom() => Node.t()}

  @doc "Show `content` in the widgets of `kind` from now on."
  @spec update(atom(), content()) :: :ok
  def update(kind, content), do: timeline(kind, [{DateTime.utc_now(), content}])

  @doc """
  Show each `content` in the widgets of `kind` from its time: `entries` are `{DateTime,
  content}`, earliest first, the last shown until the next update.
  """
  @spec timeline(atom(), [{DateTime.t(), content()}]) :: :ok
  def timeline(kind, entries) do
    Request.send(nil, "widget_update", %{
      kind: Atom.to_string(kind),
      content: %{entries: Enum.map(entries, &entry/1)}
    })
  end

  defp entry({%DateTime{} = at, content}),
    do: %{at: DateTime.to_unix(at), sizes: sizes(content)}

  defp sizes(%Node{} = node), do: %{default: encode(node)}

  defp sizes(content) when is_map(content),
    do: Map.new(content, fn {size, node} -> {size, encode(node)} end)

  @doc "The JSON shape the widgets read: `%{type, props, children}`, nested."
  @spec encode(Node.t()) :: map()
  def encode(%Node{} = node) do
    %{
      type: Atom.to_string(node.type),
      props: Map.new(node.props, fn {key, value} -> {Atom.to_string(key), value(value)} end),
      children: Enum.map(node.children, &encode/1)
    }
  end

  defp value(list) when is_list(list) do
    if list != [] and Keyword.keyword?(list) and not Enum.all?(list, &match?({:asset, _}, &1)),
      do: Map.new(list, fn {key, value} -> {Atom.to_string(key), value(value)} end),
      else: Enum.map(list, &value/1)
  end

  defp value(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> value()

  defp value(atom) when is_atom(atom) and not is_boolean(atom) and not is_nil(atom),
    do: Atom.to_string(atom)

  defp value(other), do: other
end
