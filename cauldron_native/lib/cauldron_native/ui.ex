defmodule CauldronNative.UI do
  @moduledoc """
  The controls an app's screen is made of, drawn by the platform's own toolkit: SwiftUI on
  iOS, Jetpack Compose on Android. Each function returns a `CauldronNative.UI.Node`; an
  app's `c:CauldronNative.App.render/1` returns one node, the root, holding the others.

      navigation([
        screen("Notes", [
          list(for note <- notes, do: text(note.text, id: note.id)),
          text_field("New note", value: draft, on_change: :draft, on_submit: :add),
          button("Add", on_tap: :add, disabled: draft == "")
        ])
      ])

  ## Children

  A list of children may hold nested lists and `nil`s, which are flattened and dropped, so
  a child shown only sometimes is `if shown?, do: text("…")`.

  ## Options every control takes

    * `:id` — the node's identity among its siblings. Give one to each row of a list whose
      rows move, are added or are removed, so the platform keeps each row's state and
      animates the change. Default: its position
    * `:modifiers` — the platform's own adjustments, applied in order:
      `padding: 8`, `padding: [horizontal: 16]`, `font: :headline`, `foreground: :accent`,
      `background: :secondary_background`, `frame: [max_width: :infinity, height: 44]`
      (also `width`, `min_width`, `min_height` and `max_height`), `corner_radius: 12`,
      `opacity: 0.5`, `bold: true`, `gradient: [{:asset, "AccentColorDimmed"}, :accent]`
      (a background shading from the first colour at the top leading corner to the last
      at the bottom trailing one); and under `ios:` (SwiftUI, on iOS, tvOS and macOS) or
      `android:` ones only that platform has. A renderer passes over a modifier it does
      not know.
      Fonts are text styles (`:large_title`, `:title`, `:title2`, `:title3`, `:headline`,
      `:body`, `:callout`, `:subheadline`, `:footnote`, `:caption`), sized by the
      device's text size setting. Colours are roles (`:primary`, `:secondary`,
      `:accent`, `:background`, `:secondary_background`, `:destructive`), `"#rrggbb"`,
      or `{:asset, name}`, a colour of the app's `:assets` catalog, with its dark
      appearance
    * `:label` — what VoiceOver and TalkBack say for the control; `:hint` — what the
      control does, as an action ("open the settings"): VoiceOver reads it after the
      label, and TalkBack reads it as "double tap to open the settings" on a control the
      user taps or switches
    * `:disabled` — `true` greys the control out and stops its events
    * `:on_tap` — makes any control, a stack or a card say, one the user taps: the event
      is sent on a tap, and VoiceOver and TalkBack announce it as a button

  ## Events

  An option named `on_…` names the event the app's `c:CauldronNative.App.handle_event/3`
  gets, any term: `on_tap: :save`, `on_tap: {:open, note.id}`. The value given with it is
  the control's: the text of a field, `true` or `false` of a toggle, the number of a
  slider, the number of screens left after a back gesture.
  """

  alias CauldronNative.UI.{Node, Value}

  @type child :: Node.t() | [child()] | nil
  @type opts :: keyword()

  @doc "Text, in the platform's body font unless a `font:` modifier says otherwise."
  @spec text(String.t(), opts()) :: Node.t()
  def text(content, opts \\ []), do: node(:text, [content: content] ++ opts)

  @doc """
  A button with `label` as its title. Options: `on_tap`, `role` (`:destructive`,
  `:cancel`), `style` (`:plain`, `:bordered`, `:prominent`, or `:icon`, its icon alone with
  `label` as what VoiceOver and TalkBack say), `icon` (a name as `icon/2` takes it, shown
  before the title, or alone in a toolbar).
  """
  @spec button(String.t(), opts()) :: Node.t()
  def button(label, opts \\ []), do: node(:button, [title: label] ++ named_icon(opts))

  @doc """
  A one-line text field showing `placeholder` while empty. Options: `value`, the text
  (the field keeps the cursor and selection itself); `on_change`, given the text after
  each edit; `on_submit`, given the text when the return key is pressed; `keyboard`
  (`:default`, `:email`, `:number`, `:decimal`, `:phone`, `:url`); `capitalize`
  (`:sentences`, `:words`, `:characters`, `:none`); `autocorrect` (boolean).
  """
  @spec text_field(String.t(), opts()) :: Node.t()
  def text_field(placeholder, opts \\ []),
    do: node(:text_field, [placeholder: placeholder] ++ opts)

  @doc "A text field whose text is hidden, for passwords; options as `text_field/2`."
  @spec secure_field(String.t(), opts()) :: Node.t()
  def secure_field(placeholder, opts \\ []),
    do: node(:secure_field, [placeholder: placeholder] ++ opts)

  @doc "A switch with `label` beside it. Options: `value` (boolean), `on_change`, given the new value."
  @spec toggle(String.t(), opts()) :: Node.t()
  def toggle(label, opts \\ []), do: node(:toggle, [title: label] ++ opts)

  @doc "A slider. Options: `value`, `min` (default 0.0), `max` (default 1.0), `step`, `on_change`, given the new value."
  @spec slider(opts()) :: Node.t()
  def slider(opts \\ []), do: node(:slider, opts)

  @doc "Children one above another. Options: `spacing` (points), `alignment` (`:leading`, `:center`, `:trailing`)."
  @spec vstack([child()], opts()) :: Node.t()
  def vstack(children, opts \\ []), do: node(:vstack, opts, children)

  @doc "Children side by side. Options: `spacing` (points), `alignment` (`:top`, `:center`, `:bottom`)."
  @spec hstack([child()], opts()) :: Node.t()
  def hstack(children, opts \\ []), do: node(:hstack, opts, children)

  @doc """
  Children on top of one another, the last in front. Option: `alignment` (`:center`,
  `:top`, `:bottom`, `:leading`, `:trailing`, `:top_leading`, `:top_trailing`,
  `:bottom_leading`, `:bottom_trailing`).
  """
  @spec zstack([child()], opts()) :: Node.t()
  def zstack(children, opts \\ []), do: node(:zstack, opts, children)

  @doc "Space that grows to fill a stack."
  @spec spacer(opts()) :: Node.t()
  def spacer(opts \\ []), do: node(:spacer, opts)

  @doc """
  A value within a range, as a gauge: `value` between `min` (default 0) and `max`
  (default 1). Options: `style`, `:linear` (default), `:circular` (a ring, as the Lock
  Screen's widgets show) or `:segmented` (one segment per whole unit of the range);
  `title`, text above a linear or segmented gauge; `current`, text shown as the value
  (in a circular gauge's middle); `image`, a picture of the app's catalog shown as the
  value instead (`{:asset, name}`), or a list of them drawn one over another.
  """
  @spec gauge(number(), opts()) :: Node.t()
  def gauge(value, opts \\ []),
    do: node(:gauge, [value: value] ++ Keyword.update(opts, :image, nil, &asset_name/1))

  defp asset_name({:asset, name}), do: [name]
  defp asset_name(nil), do: nil
  defp asset_name(pictures) when is_list(pictures), do: Enum.flat_map(pictures, &asset_name/1)

  @doc "A thin line between the controls of a stack."
  @spec divider(opts()) :: Node.t()
  def divider(opts \\ []), do: node(:divider, opts)

  @doc "Children that scroll when they do not fit. Option: `axis` (`:vertical`, default, or `:horizontal`)."
  @spec scroll([child()], opts()) :: Node.t()
  def scroll(children, opts \\ []), do: node(:scroll, opts, children)

  @doc "Rows in the platform's list style, scrolling; its children are rows or `section/3`s."
  @spec list([child()], opts()) :: Node.t()
  def list(children, opts \\ []), do: node(:list, opts, children)

  @doc "A titled group of rows in a `list/2` or `form/2`. Option: `footer`, text under it."
  @spec section(String.t() | nil, [child()], opts()) :: Node.t()
  def section(title, children, opts \\ []), do: node(:section, [title: title] ++ opts, children)

  @doc "Fields and settings in the platform's form style: grouped rows, scrolling."
  @spec form([child()], opts()) :: Node.t()
  def form(children, opts \\ []), do: node(:form, opts, children)

  @doc """
  A stack of `screen/3`s, the first at the bottom: the platform shows the last with a back
  control and the system back gesture, and pushes and pops them with its own animation.
  Option: `on_back`, given the number of screens to keep when the player goes back; the
  app then drops the screens above it.
  """
  @spec navigation([child()], opts()) :: Node.t()
  def navigation(screens, opts \\ []), do: node(:navigation, opts, screens)

  @doc """
  One screen of a `navigation/2`, with `title` in its bar; a `toolbar/2` among its children
  goes in the bar. Options: `large_title` (boolean, iOS); `search`, the text of a search
  field the platform places with the bar, with `on_search` given the text after each edit
  and `search_prompt` its placeholder.
  """
  @spec screen(String.t(), [child()], opts()) :: Node.t()
  def screen(title, children, opts \\ []), do: node(:screen, [title: title] ++ opts, children)

  @doc """
  A view of the app's own, written in Swift (`native/ios`) or Kotlin (`native/android`)
  and registered under `name`. The options other than the common ones go to it as its
  properties; `on_…` options are events it may send.
  """
  @spec native(atom() | String.t(), opts()) :: Node.t()
  def native(name, opts \\ []), do: node(:native, [name: to_string(name)] ++ opts)

  @doc """
  An icon by name, drawn as the platform draws its own: an SF Symbol on iOS, a Material
  icon on Android. Names both platforms share: `:add`, `:add_circle`, `:back`, `:forward`,
  `:phone`, `:check`, `:check_circle`, `:close`, `:calendar`, `:delete`, `:edit`, `:mail`,
  `:favorite`, `:favorite_border`, `:home`, `:info`, `:location`, `:lock`, `:menu`,
  `:more`, `:notifications`, `:person`, `:account`, `:play`, `:refresh`, `:search`,
  `:send`, `:settings`, `:share`, `:cart`, `:star`, `:thumb_up`, `:warning`, `:list`,
  `:face`, `:build`. Options `ios:` and `android:` name a platform's own icon instead (an
  SF Symbol name; a Material icon name such as `"ShoppingCart"`), and `asset:` a symbol
  or image of the app's `:assets` catalog in place of both. `label/2` takes the same
  options.
  """
  @spec icon(atom() | String.t(), opts()) :: Node.t()
  def icon(name, opts \\ []), do: node(:icon, [name: to_string(name)] ++ opts)

  @doc """
  A picture: `{:asset, name}`, an image set of the app's `:assets` catalog by its name
  there (`"dough/blue-full"`); a file in the app (a path, such as one under
  `Application.app_dir/2`); or one from the web (an `http` or `https` URL), shown while
  it loads as the platform's placeholder. Option: `fit` (`:fit`, default, or `:fill`).
  """
  @spec image({:asset, String.t()} | String.t(), opts()) :: Node.t()
  def image(source, opts \\ [])
  def image({:asset, name}, opts), do: node(:image, [asset: name] ++ opts)
  def image(source, opts), do: node(:image, [source: source] ++ opts)

  @doc "Text with an icon before it (`icon:`, a name as `icon/2` takes it)."
  @spec label(String.t(), opts()) :: Node.t()
  def label(title, opts \\ []), do: node(:label, [title: title] ++ named_icon(opts))

  @doc "Text that opens `url` in the browser."
  @spec link(String.t(), String.t(), opts()) :: Node.t()
  def link(title, url, opts \\ []), do: node(:link, [title: title, url: url] ++ opts)

  @doc "A button that opens a menu of `buttons`. Option: `icon`, shown in place of `title`."
  @spec menu(String.t(), [child()], opts()) :: Node.t()
  def menu(title, buttons, opts \\ []),
    do: node(:menu, [title: title] ++ named_icon(opts), buttons)

  @doc "A compact choice the player turns on and off. Options: `selected` (boolean), `on_tap`."
  @spec chip(String.t(), opts()) :: Node.t()
  def chip(title, opts \\ []), do: node(:chip, [title: title] ++ opts)

  @doc """
  One choice among `options`, each a term or `{term, label}`. Options: `value`, the chosen
  term; `on_change`, given the chosen term; `style`: `:menu` (default), `:segmented`
  (a row of segments), `:wheel` (iOS; a menu on Android) or `:inline` (the options as
  rows, in a list or form).
  """
  @spec picker(String.t(), [term() | {term(), String.t()}], opts()) :: Node.t()
  def picker(title, options, opts \\ []) do
    {values, labels} = options |> Enum.map(&option/1) |> Enum.unzip()
    {value, opts} = Keyword.pop(opts, :value)
    index = Enum.find_index(values, &(&1 == value)) || -1
    node(:picker, [title: title, options: labels, value: index] ++ opts, [], {:index, values})
  end

  @doc """
  A date, a time, or both, chosen with the platform's picker. `value` is a `Date`, a
  `Time` or a `NaiveDateTime`, which also says which is chosen; `on_change` is given the
  same kind back. Option: `style`: `:compact` (default), `:graphical` (a calendar) or
  `:wheel`.
  """
  @spec date_picker(String.t(), Date.t() | Time.t() | NaiveDateTime.t(), opts()) :: Node.t()
  def date_picker(title, value, opts \\ []) do
    {text, kind} = Value.encode_date(value)
    node(:date_picker, [title: title, value: text, mode: kind] ++ opts, [], {:date, kind})
  end

  @doc "A number stepped up and down. Options: `value`, `min`, `max`, `step` (default 1), `on_change`, given the new number."
  @spec stepper(String.t(), opts()) :: Node.t()
  def stepper(title, opts \\ []), do: node(:stepper, [title: title] ++ opts)

  @doc """
  Progress: `value` from 0.0 to 1.0, or `nil` for progress of unknown length. Options:
  `style` (`:linear`, default, or `:circular`), `title`.
  """
  @spec progress(opts()) :: Node.t()
  def progress(opts \\ []), do: node(:progress, opts)

  @doc "Text of many lines, taking `text_field/2`'s options."
  @spec text_editor(String.t(), opts()) :: Node.t()
  def text_editor(placeholder, opts \\ []),
    do: node(:text_editor, [placeholder: placeholder] ++ opts)

  @doc "Children on a raised card (Android) or a grouped background (iOS)."
  @spec card([child()], opts()) :: Node.t()
  def card(children, opts \\ []), do: node(:card, opts, children)

  @doc "Children in a grid. Option: `columns` (default 2), or `min_width`, the points a column needs, for as many columns as fit."
  @spec grid([child()], opts()) :: Node.t()
  def grid(children, opts \\ []), do: node(:grid, opts, children)

  @doc "A titled section that opens and closes. Options: `expanded` (boolean), `on_toggle`, given the new state."
  @spec disclosure(String.t(), [child()], opts()) :: Node.t()
  def disclosure(title, children, opts \\ []),
    do: node(:disclosure, [title: title] ++ opts, children)

  @doc """
  Screens behind a tab bar, each a `tab/3`. Options: `selected`, the selected tab's `:id`
  (or position); `on_select`, given the tab's `:id` (or position) when the player picks it.
  """
  @spec tabs([child()], opts()) :: Node.t()
  def tabs(tabs, opts \\ []) do
    tabs = flatten(tabs)
    keys = tabs |> Enum.with_index() |> Enum.map(fn {tab, index} -> tab.key || index end)
    {selected, opts} = Keyword.pop(opts, :selected)
    index = Enum.find_index(keys, &(&1 == selected)) || 0
    node(:tabs, [selected: index] ++ opts, tabs, {:index, keys})
  end

  @doc "One tab of `tabs/2`, its title and `icon:` in the tab bar; its child is usually a `navigation/2` or a `screen/3`."
  @spec tab(String.t(), [child()], opts()) :: Node.t()
  def tab(title, children, opts \\ []),
    do: node(:tab, [title: title] ++ named_icon(opts), children)

  @doc """
  A sidebar of rows beside a detail pane, as the platform lays them out: SwiftUI's split
  view (sidebar and detail side by side on an iPad and a Mac, a stack on an iPhone) and
  Material's list and detail panes on Android (side by side on a wide screen, one at a
  time on a phone).

  `sidebar` is rows (`label/2`s) or `section/3`s of them, each row with an `:id`; `detail`
  is what the selected row shows, usually a `navigation/2` or `screen/3`. Options:
  `title`, the sidebar's; `selected`, the selected row's `:id`, or `nil` for none, which on
  a phone shows the sidebar; `on_select`, given the row's `:id` when the user picks one
  and `nil` when they go back to the sidebar on a phone.
  """
  @spec split([child()], [child()], opts()) :: Node.t()
  def split(sidebar, detail, opts \\ []) do
    sidebar = flatten(sidebar)
    keys = Enum.map(sidebar_rows(sidebar), & &1.key)
    {selected, opts} = Keyword.pop(opts, :selected)
    index = if selected == nil, do: -1, else: Enum.find_index(keys, &(&1 == selected)) || -1

    node(
      :split,
      [selected: index] ++ opts,
      [node(:sidebar, [], sidebar), node(:detail, [], detail)],
      {:index, keys}
    )
  end

  @doc """
  Rows of data in columns: SwiftUI's table on an iPad and a Mac, a list of rows on an
  iPhone, and rows of columns on a wide Android screen or list rows on a phone. Where there
  is room for one column only, a row shows its first column and the rest under it.

  `columns` are `{key, title}`, or `{key, title, width}` for a column of a fixed width in
  points; `rows` are maps holding each column's key, and an `:id`. A cell is text, or a
  control (an `hstack/2` of a picture and a label, a `menu/3`), drawn in its column as it
  is and passed over where a row shows its columns as text. Option: `on_select`, given
  the row's `:id` when the user taps it.

      table([number: "Order", donuts: "Donuts", status: "Status"], orders,
        on_select: :open_order
      )
  """
  @spec table([{atom(), String.t()} | {atom(), String.t(), number()}], [map()], opts()) ::
          Node.t()
  def table(columns, rows, opts \\ []) do
    keys = Enum.map(rows, &Map.fetch!(&1, :id))
    titles = Enum.map(columns, &elem(&1, 1))
    widths = Enum.map(columns, &column_width/1)

    {cells, controls} =
      Enum.map_reduce(rows, [], fn row, controls ->
        Enum.map_reduce(columns, controls, fn column, controls ->
          table_cell(Map.get(row, elem(column, 0), ""), controls)
        end)
      end)

    node(
      :table,
      [columns: titles, widths: widths, rows: cells] ++ opts,
      Enum.reverse(controls),
      {:index, keys}
    )
  end

  defp column_width({_key, _title, width}), do: width
  defp column_width({_key, _title}), do: nil

  defp table_cell(%Node{} = control, controls),
    do: {%{child: length(controls)}, [control | controls]}

  defp table_cell(value, controls), do: {to_string(value), controls}

  @doc """
  The app's look for `children`: options `scheme`, `:system` (default), `:light` or
  `:dark`; `accent`, a colour (`"#rrggbb"`) for the controls; `dynamic_color`, Android's
  colours taken from the wallpaper (default `true` where the system has them); with it
  `false`, Android derives Material's whole set of colours from `accent`. iOS, tvOS and
  macOS take `scheme` and `accent`.
  """
  @spec theme([child()], opts()) :: Node.t()
  def theme(children, opts \\ []), do: node(:theme, opts, children)

  @doc """
  An item of the Mac's menu bar, its `icon:` (a name as `icon/2` takes it, or `ios:`, an
  SF Symbol) in the bar and `title` as its tooltip; clicking it opens a window under it
  of `children`. Other systems have no menu bar, and leave it out. A child of a
  `screen/3`, `theme/2` or `split/3` the app keeps shown.
  """
  @spec menu_bar_extra(String.t(), [child()], opts()) :: Node.t()
  def menu_bar_extra(title, children, opts \\ []),
    do: node(:menu_bar_extra, [title: title] ++ named_icon(opts), children)

  @doc "Buttons and menus in the bar of the `screen/3` it is a child of."
  @spec toolbar([child()], opts()) :: Node.t()
  def toolbar(items, opts \\ []), do: node(:toolbar, opts, items)

  @doc """
  Children in a sheet over the screen while `shown` is true. Options: `shown`, `title`,
  `on_dismiss`, sent when the player swipes or taps it away.
  """
  @spec sheet([child()], opts()) :: Node.t()
  def sheet(children, opts \\ []), do: node(:sheet, opts, children)

  @doc """
  An alert with `title` while `shown` is true, its `buttons` as its actions (a button's
  `role: :cancel` or `:destructive` is placed and coloured as the platform does). Options:
  `shown`, `message`, `on_dismiss`.
  """
  @spec alert(String.t(), [child()], opts()) :: Node.t()
  def alert(title, buttons, opts \\ []), do: node(:alert, [title: title] ++ opts, buttons)

  @doc """
  A dialog of `content`, controls the user changes, with `title` and its `buttons` as
  the platform places them: Material's dialog on Android, with the buttons at its foot;
  a sheet on iOS and macOS whose bar holds the title, a `role: :cancel` button on its
  leading side and the others on its trailing side. Options: `shown`, `on_dismiss`, sent
  when the user dismisses it without a button.
  """
  @spec dialog(String.t(), [child()], [child()], opts()) :: Node.t()
  def dialog(title, content, buttons, opts \\ []),
    do:
      node(:dialog, [title: title] ++ opts, [
        node(:dialog_content, [], content),
        node(:dialog_actions, [], buttons)
      ])

  @doc "A choice of actions that rises from the bottom (an action sheet), with `alert/3`'s options."
  @spec confirm(String.t(), [child()], opts()) :: Node.t()
  def confirm(title, buttons, opts \\ []), do: node(:confirm, [title: title] ++ opts, buttons)

  @doc """
  A video from `source` (a path or an `http(s)` URL) in the platform's player, with its
  controls, full screen and picture in picture. Options: `autoplay`, `loop`, `muted`
  (booleans, default `false`), `controls` (default `true`), `on_end`, sent when it ends.
  """
  @spec video(String.t(), opts()) :: Node.t()
  def video(source, opts \\ []), do: node(:video, [source: source] ++ opts)

  @doc """
  What the camera sees, live. Option `facing`: `:back` (default) or `:front`. Needs the
  `:camera` permission (`CauldronNative.Device.permission/2`); without it the preview
  shows the platform's placeholder.
  """
  @spec camera_preview(opts()) :: Node.t()
  def camera_preview(opts \\ []), do: node(:camera_preview, opts)

  @typedoc "One series of a chart, made by `series/3`."
  @type series :: %{name: String.t(), mark: atom(), colour: String.t() | nil, points: list()}

  @doc """
  A chart of `series` (each made by `series/3`) drawn by the platform: Swift Charts on
  iOS and Vico, a Material chart library, on Android. Every series shares one x-axis, whose
  values are all numbers, all text (categories) or all `Date`s or `DateTime`s.

  Options: `x_label` and `y_label`, the axes' titles; `y_range`, `{min, max}` fixed
  rather than fitted to the data; `legend` (default `true` when there is more than one
  series); `donut` (`true` for a ring rather than a pie, with `:sector` marks). Its height
  is 240 points unless a `frame:` modifier gives one.

      chart([
        series("Coffee", [{"Mon", 3}, {"Tue", 5}, {"Wed", 2}]),
        series("Tea", [{"Mon", 1}, {"Tue", 2}, {"Wed", 4}])
      ], y_label: "Cups")
  """
  @spec chart([series()], opts()) :: Node.t()
  def chart(series, opts \\ []) do
    {x_type, encoded} = chart_points(series)

    node(
      :chart,
      [series: encoded, x_type: x_type, legend: length(series) > 1] ++ opts
    )
  end

  @doc """
  One series of `chart/2`: `points` as `{x, y}`, `y` a number. Options: `mark` —
  `:bar` (default), `:line`, `:area`, `:point` or `:sector` (a pie's slices, `x` naming
  each; the only series in its chart); `colour` (`"#rrggbb"`), else the platform's own.
  """
  @spec series(String.t(), [{term(), number()}], keyword()) :: series()
  def series(name, points, opts \\ []),
    do: %{
      name: name,
      mark: Keyword.get(opts, :mark, :bar),
      colour: Keyword.get(opts, :colour),
      points: points
    }

  @doc """
  A map from the platform: MapKit on iOS, Google Maps on Android (which needs the app's
  `:maps` key, `CauldronNative.Build.App`). Options: `center`, `{latitude, longitude}`;
  `distance`, the metres across the view (default `1000`); `markers`, each made by
  `marker/3`; `style`: `:standard` (default), `:satellite` or `:hybrid`; `user_location`
  (`true` shows the phone's position, which needs the `:location` permission);
  `on_select`, given the id of the marker tapped; `on_move`, given
  `%{latitude: _, longitude: _, distance: _}` when the user has moved the view. Its height
  is 300 points unless a `frame:` modifier gives one.
  """
  @spec map(opts()) :: Node.t()
  def map(opts \\ []) do
    {markers, opts} = Keyword.pop(opts, :markers, [])
    ids = Enum.map(markers, & &1.id)
    shown = Enum.map(markers, &Map.delete(&1, :id))
    node(:map, [markers: shown] ++ opts, [], {:map, ids})
  end

  @doc """
  A marker on `map/1` at `{latitude, longitude}`, with `title` and the `id` the map's
  `on_select` is given. Option: `colour` (`"#rrggbb"`).
  """
  @spec marker(term(), String.t(), {number(), number()}, keyword()) :: map()
  def marker(id, title, {latitude, longitude}, opts \\ []),
    do: %{
      id: id,
      title: title,
      latitude: latitude,
      longitude: longitude,
      colour: Keyword.get(opts, :colour)
    }

  defp chart_points(series) do
    x_type = series |> Enum.flat_map(& &1.points) |> List.first() |> x_type()

    encoded =
      Enum.map(series, fn one ->
        %{one | points: Enum.map(one.points, fn {x, y} -> [x_value(x), y] end)}
      end)

    {x_type, encoded}
  end

  defp x_type(nil), do: :number
  defp x_type({x, _y}) when is_number(x), do: :number
  defp x_type({%Date{}, _y}), do: :date
  defp x_type({%DateTime{}, _y}), do: :date
  defp x_type({%NaiveDateTime{}, _y}), do: :date
  defp x_type({_x, _y}), do: :category

  defp x_value(%Date{} = date), do: date |> DateTime.new!(~T[00:00:00]) |> x_value()

  defp x_value(%NaiveDateTime{} = moment),
    do: moment |> DateTime.from_naive!("Etc/UTC") |> x_value()

  defp x_value(%DateTime{} = moment), do: DateTime.to_unix(moment, :millisecond)
  defp x_value(x) when is_number(x) or is_binary(x), do: x
  defp x_value(x), do: to_string(x)

  defp sidebar_rows(sidebar),
    do:
      Enum.flat_map(sidebar, fn row -> if row.type == :section, do: row.children, else: [row] end)

  defp named_icon(opts), do: Keyword.update(opts, :icon, nil, &to_string/1)

  defp option({value, label}), do: {value, to_string(label)}
  defp option(value), do: {value, to_string(value)}

  defp node(type, opts, children \\ [], decode \\ nil) do
    {key, props} = Keyword.pop(opts, :id)

    %Node{
      type: type,
      key: key,
      props: Map.new(props),
      children: flatten(children),
      decode: decode
    }
  end

  defp flatten(children) do
    children
    |> List.wrap()
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end
end
