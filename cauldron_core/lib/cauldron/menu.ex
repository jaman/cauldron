defmodule Cauldron.Menu do
  @moduledoc """
  How a game's menu behaves, with nothing about how it looks: pages of
  `Cauldron.Menu.Item` rows, the cursor on each, going into a page and back, changing
  settings, waiting for a key to bind, taking typed text, and asking yes or no.

  It answers `Cauldron.Client.Game`'s `open_menu/1` and `menu_event/3` as they are:

      def open_menu(settings), do: Cauldron.Menu.open(MyGame.Menus.pages(), settings)
      def menu_event(menu, event, settings), do: Cauldron.Menu.event(menu, event, settings)

  and the game draws it in `scene/2`, where the look carries the menu as `:menu`, from
  `title/1`, `rows/1`, `window/2` and `prompt/1`.

  ## Pages

  `pages` maps a page's name to `%{title: text, items: items}`, `items` a list of items
  or a function of the settings returning one, read every time the page is shown (a
  controls page listing the game's actions, a page of saved games). A page may give
  `back: result` (see `Cauldron.Menu.Item`), what going back from it does; by default
  the page it was opened from, and closing the menu from the first.

  ## Moves

  An event becomes a move — `:up`, `:down`, `:left`, `:right`, `:choose` or `:back` — by
  the key it carries, as `Cauldron.Input.spec_of/1` reads it, against `:keys`, and
  then by the game action the player's bindings give that key, against `:actions`.
  `:up` and `:down` move the cursor over the rows it can rest on, wrapping; `:left`
  and `:right` change a toggle, choice or slider; `:choose` does an action, flips a
  toggle, steps a choice, and starts a rebind or typing; `:back` goes back.

  While a binding waits, the next key, mouse button or wheel notch becomes the action's
  only key, and `Esc` gives up. While typing, a printable key adds its character,
  `Backspace` takes one off, `Enter` keeps the text and `Esc` gives up. While a prompt
  asks, `:choose` (or `y`) is yes and `:back` (or `n`) is no.

  ## What `event/3` returns

  `%{menu: menu_or_nil, settings: settings}`, with `:sounds` when the menu makes any,
  `:request` when an action sends the world something, and `leave: true` when one
  leaves the world: what `menu_event/3` returns.

  ## Options

    * `:open` — the page shown first. Default `:main`
    * `:keys` — `%{move => [key]}` over the defaults: `up: [:up, {:mouse, :wheel_up}]`,
      `down: [:down, {:mouse, :wheel_down}]`, `left: [:left]`, `right: [:right]`,
      `choose: [:enter, :" "]`, `back: [:escape, :backspace]`
    * `:actions` — `%{game_action => move}`, so the game's own buttons work the menu as
      well: `%{jump: :choose, pause: :back}`. Default `%{}`
    * `:sounds` — `%{event => sound}`, the sound events to play, as the game's
      `sounds/0` table knows them, for `:move`, `:change`, `:choose`, `:back`, `:open`
      (a page) and `:refuse` (a move that does nothing). Default none
  """

  alias Cauldron.Input
  alias Cauldron.Menu.Item

  @default_keys %{
    up: [:up, {:mouse, :wheel_up}],
    down: [:down, {:mouse, :wheel_down}],
    left: [:left],
    right: [:right],
    choose: [:enter, :" "],
    back: [:escape, :backspace]
  }

  @type page :: %{
          required(:title) => String.t(),
          required(:items) => [Item.t()] | (map() -> [Item.t()]),
          optional(:back) => Item.result()
        }
  @type mode ::
          :browse
          | {:binding, Item.t()}
          | {:typing, Item.t(), String.t()}
          | {:confirm, String.t(), Item.result()}
  @type row :: %{
          index: non_neg_integer(),
          item: Item.t(),
          kind: Item.kind(),
          label: String.t(),
          value: String.t() | nil,
          fraction: float() | nil,
          focused?: boolean(),
          waiting?: boolean()
        }
  @type t :: %__MODULE__{
          pages: %{atom() => page()},
          page: atom(),
          trail: [atom()],
          cursors: %{atom() => non_neg_integer()},
          mode: mode(),
          settings: map(),
          keys: %{atom() => [term()]},
          actions: %{atom() => atom()},
          sounds: %{atom() => term()},
          pad?: boolean()
        }

  @enforce_keys [:pages, :page, :settings]
  defstruct [
    :pages,
    :page,
    :settings,
    trail: [],
    cursors: %{},
    mode: :browse,
    keys: @default_keys,
    actions: %{},
    sounds: %{},
    pad?: false
  ]

  @doc "The menu on its first page, showing `settings`."
  @spec open(%{atom() => page()}, map(), keyword()) :: t()
  def open(pages, settings, opts \\ []) do
    %__MODULE__{
      pages: pages,
      page: Keyword.get(opts, :open, :main),
      settings: settings,
      keys: Map.merge(@default_keys, Keyword.get(opts, :keys, %{})),
      actions: Keyword.get(opts, :actions, %{}),
      sounds: Keyword.get(opts, :sounds, %{})
    }
    |> settle()
  end

  @doc "The menu after `event`, as the module documentation describes."
  @spec event(t(), term(), map()) :: map()
  def event(%__MODULE__{} = menu, event, settings) do
    menu = %{menu | settings: settings, pad?: from_pad?(event, menu.pad?)}
    handle(menu, menu.mode, event)
  end

  @doc "Whether the last key the menu took came from a controller."
  @spec pad?(t()) :: boolean()
  def pad?(%__MODULE__{pad?: pad?}), do: pad?

  @doc "The title of the page showing."
  @spec title(t()) :: String.t()
  def title(%__MODULE__{} = menu), do: Map.get(page(menu), :title, "")

  @doc "The name of the page showing."
  @spec page_name(t()) :: atom()
  def page_name(%__MODULE__{page: page}), do: page

  @doc "Every row of the page showing, ready to draw."
  @spec rows(t()) :: [row()]
  def rows(%__MODULE__{} = menu) do
    focused = cursor(menu)

    menu
    |> items()
    |> Enum.with_index()
    |> Enum.map(fn {item, index} -> row(menu, item, index, index == focused) end)
  end

  @doc """
  The rows to show when only `count` fit, keeping the cursor in view: `{first, rows}`,
  `first` the index of the first row shown.
  """
  @spec window(t(), pos_integer()) :: {non_neg_integer(), [row()]}
  def window(%__MODULE__{} = menu, count) do
    all = rows(menu)
    first = (cursor(menu) - div(count, 2)) |> min(length(all) - count) |> max(0)
    {first, Enum.slice(all, first, count)}
  end

  @doc """
  What the menu is waiting for, if anything: `nil`, `%{kind: :confirm, text: prompt,
  pad?: boolean}` (`pad?` when the last key came from a controller, which answers with
  `A` and `B`),
  `%{kind: :binding, text: label}` or `%{kind: :typing, text: label, typed: text}`.
  """
  @spec prompt(t()) :: map() | nil
  def prompt(%__MODULE__{mode: :browse}), do: nil

  def prompt(%__MODULE__{mode: {:confirm, text, _result}} = menu),
    do: %{kind: :confirm, text: text, pad?: menu.pad?}

  def prompt(%__MODULE__{mode: {:binding, item}}), do: %{kind: :binding, text: item.label}

  def prompt(%__MODULE__{mode: {:typing, item, typed}}),
    do: %{kind: :typing, text: item.label, typed: typed}

  @doc "The item under the cursor, or `nil` on a page with nothing to rest on."
  @spec focused(t()) :: Item.t() | nil
  def focused(%__MODULE__{} = menu), do: Enum.at(items(menu), cursor(menu))

  defp handle(menu, :browse, event) do
    case move(menu, event) do
      nil -> reply(menu)
      move -> browse(menu, move, focused(menu))
    end
  end

  defp handle(menu, {:binding, item}, event) do
    case Input.spec_of(event) do
      nil -> reply(menu)
      :escape -> reply(%{menu | mode: :browse}, :back)
      key -> menu |> rebound(item, key) |> reply(:change)
    end
  end

  defp handle(menu, {:typing, item, typed}, event), do: typing(menu, item, typed, key_of(event))

  defp handle(menu, {:confirm, _text, result}, event) do
    case answer(menu, event) do
      :yes -> run(%{menu | mode: :browse}, result, [:choose])
      :no -> reply(%{menu | mode: :browse}, :back)
      nil -> reply(menu)
    end
  end

  defp browse(menu, :up, _item), do: menu |> step(-1) |> reply(:move)
  defp browse(menu, :down, _item), do: menu |> step(1) |> reply(:move)
  defp browse(menu, :back, _item), do: run(menu, back_result(menu), [:back])
  defp browse(menu, _move, nil), do: reply(menu, :refuse)

  defp browse(menu, move, %Item{kind: kind} = item)
       when move in [:left, :right] and kind in [:toggle, :choice, :slider] do
    menu |> changed(item, if(move == :left, do: -1, else: 1)) |> reply(:change)
  end

  defp browse(menu, :choose, %Item{kind: :action, result: result}),
    do: run(menu, result, [:choose])

  defp browse(menu, :choose, %Item{kind: kind} = item) when kind in [:toggle, :choice],
    do: menu |> changed(item, 1) |> reply(:change)

  defp browse(menu, :choose, %Item{kind: :binding} = item),
    do: reply(%{menu | mode: {:binding, item}}, :choose)

  defp browse(menu, :choose, %Item{kind: :text} = item),
    do: reply(%{menu | mode: {:typing, item, Item.value(item, menu.settings)}}, :choose)

  defp browse(menu, _move, _item), do: reply(menu, :refuse)

  defp typing(menu, _item, _typed, :escape), do: reply(%{menu | mode: :browse}, :back)

  defp typing(menu, item, typed, :enter) do
    settings = Item.put_text(item, menu.settings, typed)
    reply(%{menu | mode: :browse, settings: settings}, :choose)
  end

  defp typing(menu, item, typed, :backspace),
    do: reply(%{menu | mode: {:typing, item, String.slice(typed, 0..-2//1)}}, :change)

  defp typing(menu, item, typed, key) when is_atom(key) and key != nil do
    character = Atom.to_string(key)

    if String.length(character) == 1 and String.printable?(character) and
         String.length(typed) < item.max,
       do: reply(%{menu | mode: {:typing, item, typed <> character}}, :change),
       else: reply(menu, :refuse)
  end

  defp typing(menu, _item, _typed, _key), do: reply(menu)

  defp from_pad?({:key, _key, mods}, _was), do: :pad in mods
  defp from_pad?({:key, _key}, _was), do: false
  defp from_pad?(_event, was), do: was

  defp answer(menu, event) do
    case {key_of(event), move(menu, event)} do
      {:y, _move} -> :yes
      {:n, _move} -> :no
      {_key, :choose} -> :yes
      {_key, :back} -> :no
      _other -> nil
    end
  end

  defp run(menu, results, sounds) when is_list(results) do
    Enum.reduce(results, %{menu: menu, effects: %{}, sounds: sounds}, &perform/2)
    |> finish(menu)
  end

  defp run(menu, result, sounds), do: run(menu, [result], sounds)

  defp perform(_result, %{menu: nil} = acc), do: acc
  defp perform(:stay, acc), do: acc
  defp perform(:close, acc), do: %{acc | menu: nil}
  defp perform(:leave, acc), do: %{acc | menu: nil, effects: Map.put(acc.effects, :leave, true)}
  defp perform({:request, term}, acc), do: %{acc | effects: Map.put(acc.effects, :request, term)}

  defp perform({:confirm, text, result}, acc),
    do: %{acc | menu: %{acc.menu | mode: {:confirm, text, result}}}

  defp perform({:page, name}, %{menu: menu} = acc) do
    opened = settle(%{menu | page: name, trail: [menu.page | menu.trail]})
    %{acc | menu: opened, sounds: acc.sounds ++ [:open]}
  end

  defp perform(:back, %{menu: %{trail: []}} = acc), do: %{acc | menu: nil}

  defp perform(:back, %{menu: %{trail: [previous | rest]} = menu} = acc),
    do: %{acc | menu: %{menu | page: previous, trail: rest}}

  defp finish(%{menu: menu, effects: effects, sounds: sounds}, before) do
    %{menu: menu, settings: before.settings}
    |> Map.merge(effects)
    |> put_sounds(before, sounds)
  end

  defp reply(menu, sound \\ nil),
    do: put_sounds(%{menu: menu, settings: menu.settings}, menu, [sound])

  defp put_sounds(reply, menu, sounds) do
    case for(sound <- sounds, played = Map.get(menu.sounds, sound), do: played) do
      [] -> reply
      played -> Map.put(reply, :sounds, played)
    end
  end

  defp move(menu, event) do
    case Input.spec_of(event) do
      nil -> nil
      key -> by_key(menu.keys, key) || by_action(menu, key)
    end
  end

  defp by_key(keys, key), do: Enum.find_value(keys, fn {move, bound} -> key in bound && move end)

  defp by_action(menu, key) do
    bindings = Map.get(menu.settings, :bindings, %{})

    Enum.find_value(menu.actions, fn {action, move} ->
      key in Map.get(bindings, action, []) && move
    end)
  end

  defp key_of({:key, key}) when is_atom(key), do: key
  defp key_of({:key, key, mods}) when is_atom(key), do: shifted(key, mods)
  defp key_of(_event), do: nil

  defp shifted(key, mods) do
    if :shift in mods,
      do: key |> Atom.to_string() |> String.upcase() |> String.to_atom(),
      else: key
  end

  defp back_result(menu), do: Map.get(page(menu), :back, :back)

  defp changed(menu, item, direction),
    do: %{menu | settings: Item.change(item, menu.settings, direction)}

  defp rebound(menu, item, key),
    do: %{menu | mode: :browse, settings: Item.bind(item, menu.settings, [key])}

  defp page(menu), do: Map.fetch!(menu.pages, menu.page)

  defp items(menu) do
    case page(menu).items do
      items when is_list(items) -> items
      fun when is_function(fun, 1) -> fun.(menu.settings)
    end
  end

  defp cursor(menu), do: Map.get(menu.cursors, menu.page, 0)

  defp settle(menu) do
    items = items(menu)
    at = cursor(menu)

    case Enum.at(items, at) do
      %Item{} = item -> if Item.focusable?(item), do: menu, else: step(menu, 1)
      nil -> put_cursor(menu, 0) |> settle_first(items)
    end
  end

  defp settle_first(menu, items) do
    case Enum.find_index(items, &Item.focusable?/1) do
      nil -> menu
      index -> put_cursor(menu, index)
    end
  end

  defp step(menu, direction) do
    items = items(menu)
    count = length(items)
    from = cursor(menu)

    1..max(count, 1)//1
    |> Enum.map(&Integer.mod(from + direction * &1, max(count, 1)))
    |> Enum.find(from, &(&1 < count and Item.focusable?(Enum.at(items, &1))))
    |> then(&put_cursor(menu, &1))
  end

  defp put_cursor(menu, index), do: %{menu | cursors: Map.put(menu.cursors, menu.page, index)}

  defp row(menu, item, index, focused?) do
    %{
      index: index,
      item: item,
      kind: item.kind,
      label: item.label,
      value: value_text(menu, item, focused?),
      fraction: Item.fraction(item, menu.settings),
      focused?: focused?,
      waiting?: focused? and menu.mode != :browse
    }
  end

  defp value_text(%{mode: {:typing, item, typed}}, item, true), do: typed
  defp value_text(menu, item, _focused?), do: Item.display(item, menu.settings)
end
