defmodule Cauldron.Menu.Item do
  @moduledoc """
  One row of a `Cauldron.Menu` page, and what choosing or changing it does.

  Build items with the functions here and list them on a page:

      [
        Item.action("PLAY", [{:request, :play}, :close]),
        Item.page("OPTIONS", :options),
        Item.slider("MUSIC", [:music], 0.0..1.0, step: 0.1),
        Item.toggle("FLASHING", [:options, :flashing]),
        Item.choice("SKILL", [:options, :skill], [{1, "EASY"}, {2, "HARD"}]),
        Item.binding("JUMP", :jump),
        Item.text("NAME", [:options, :name], max: 3),
        Item.gap(),
        Item.action("QUIT", {:confirm, "LEAVE THE TOWN?", :leave})
      ]

  A `path` is a list of keys into the player's settings, the map a client hands
  `menu_event/3`: `[:music]` is the music level, `[:options, :flashing]` one of the
  game's own options. A missing key reads as the item's `:default`.

  A result is what an action does when chosen, one of these or a list of them done in
  order:

    * `:close` — close the menu
    * `:leave` — close the menu and leave the world
    * `:back` — go back a page, closing the menu from the first
    * `:stay` — nothing
    * `{:page, name}` — open page `name`, coming back to this one on `:back`
    * `{:request, term}` — send `term` to the world with the next input
    * `{:confirm, prompt, result}` — ask `prompt`; choosing yes does `result`
  """

  @type path :: [term()]
  @type result ::
          :close
          | :leave
          | :back
          | :stay
          | {:page, atom()}
          | {:request, term()}
          | {:confirm, String.t(), result()}
          | [result()]
  @type kind :: :action | :toggle | :choice | :slider | :binding | :text | :gap | :note
  @type t :: %__MODULE__{
          kind: kind(),
          label: String.t(),
          path: path() | nil,
          action: atom() | nil,
          result: result() | nil,
          choices: [{term(), String.t()}],
          low: number(),
          high: number(),
          step: number(),
          max: pos_integer(),
          default: term()
        }

  @enforce_keys [:kind, :label]
  defstruct [
    :kind,
    :label,
    :path,
    :action,
    :result,
    :default,
    choices: [],
    low: 0,
    high: 1,
    step: 1,
    max: 16
  ]

  @doc "A row that does `result` when chosen."
  @spec action(String.t(), result()) :: t()
  def action(label, result), do: %__MODULE__{kind: :action, label: label, result: result}

  @doc "A row that opens page `name`."
  @spec page(String.t(), atom()) :: t()
  def page(label, name), do: action(label, {:page, name})

  @doc "A row that turns the boolean at `path` on and off. Option `:default` (`false`)."
  @spec toggle(String.t(), path(), keyword()) :: t()
  def toggle(label, path, opts \\ []),
    do: %__MODULE__{
      kind: :toggle,
      label: label,
      path: path,
      default: Keyword.get(opts, :default, false)
    }

  @doc """
  A row that steps the value at `path` through `choices`, `{value, text}` pairs, wrapping
  at either end. Option `:default` (the first choice's value).
  """
  @spec choice(String.t(), path(), [{term(), String.t()}], keyword()) :: t()
  def choice(label, path, [{first, _text} | _] = choices, opts \\ []),
    do: %__MODULE__{
      kind: :choice,
      label: label,
      path: path,
      choices: choices,
      default: Keyword.get(opts, :default, first)
    }

  @doc """
  A row that moves the number at `path` within `low..high` by `:step` (default a tenth
  of the range). Option `:default` (`low`).
  """
  @spec slider(String.t(), path(), Range.t() | {number(), number()}, keyword()) :: t()
  def slider(label, path, range, opts \\ [])

  def slider(label, path, first..last//_, opts), do: slider(label, path, {first, last}, opts)

  def slider(label, path, {low, high}, opts) when high > low,
    do: %__MODULE__{
      kind: :slider,
      label: label,
      path: path,
      low: low,
      high: high,
      step: Keyword.get(opts, :step, (high - low) / 10),
      default: Keyword.get(opts, :default, low)
    }

  @doc "A row showing the keys bound to game action `action`; choosing it waits for a new key."
  @spec binding(String.t(), atom()) :: t()
  def binding(label, action), do: %__MODULE__{kind: :binding, label: label, action: action}

  @doc """
  A row holding the text at `path`; choosing it takes typed characters until `Enter`.
  Options `:max` (characters, default 16) and `:default` (`""`).
  """
  @spec text(String.t(), path(), keyword()) :: t()
  def text(label, path, opts \\ []),
    do: %__MODULE__{
      kind: :text,
      label: label,
      path: path,
      max: Keyword.get(opts, :max, 16),
      default: Keyword.get(opts, :default, "")
    }

  @doc "An empty row the cursor passes over."
  @spec gap() :: t()
  def gap, do: %__MODULE__{kind: :gap, label: ""}

  @doc "A row of text the cursor passes over."
  @spec note(String.t()) :: t()
  def note(label), do: %__MODULE__{kind: :note, label: label}

  @doc "Whether the cursor can rest on `item`."
  @spec focusable?(t()) :: boolean()
  def focusable?(%__MODULE__{kind: kind}), do: kind not in [:gap, :note]

  @doc "The item's value in `settings`: a setting, or a binding's keys."
  @spec value(t(), map()) :: term()
  def value(%__MODULE__{kind: :binding, action: action}, settings),
    do: settings |> Map.get(:bindings, %{}) |> Map.get(action, [])

  def value(%__MODULE__{path: nil}, _settings), do: nil

  def value(%__MODULE__{path: path, default: default}, settings),
    do: read(settings, path, default)

  @doc """
  The item's value as words: `"ON"`/`"OFF"`, a choice's text, a slider's percent, a
  binding's keys joined by `" "`, the text itself; `nil` for an action, a gap or a note.
  """
  @spec display(t(), map()) :: String.t() | nil
  def display(%__MODULE__{kind: :toggle} = item, settings),
    do: if(value(item, settings), do: "ON", else: "OFF")

  def display(%__MODULE__{kind: :choice} = item, settings) do
    current = value(item, settings)
    Enum.find_value(item.choices, inspect(current), fn {v, text} -> v == current && text end)
  end

  def display(%__MODULE__{kind: :slider} = item, settings),
    do: "#{round(fraction(item, settings) * 100)}%"

  def display(%__MODULE__{kind: :binding} = item, settings),
    do: item |> value(settings) |> Enum.map_join(" ", &key_name/1)

  def display(%__MODULE__{kind: :text} = item, settings), do: value(item, settings)
  def display(%__MODULE__{}, _settings), do: nil

  @doc "How far along its range a slider stands, `0.0..1.0`; `nil` for any other item."
  @spec fraction(t(), map()) :: float() | nil
  def fraction(%__MODULE__{kind: :slider} = item, settings),
    do: (value(item, settings) - item.low) / (item.high - item.low)

  def fraction(%__MODULE__{}, _settings), do: nil

  @doc """
  `settings` after moving `item` by `direction`, `-1` or `1`: a toggle flips, a choice
  steps and wraps, a slider steps and stops at its ends. Other items leave them as they are.
  """
  @spec change(t(), map(), -1 | 1) :: map()
  def change(%__MODULE__{kind: :toggle} = item, settings, _direction),
    do: write(settings, item.path, not value(item, settings))

  def change(%__MODULE__{kind: :choice} = item, settings, direction) do
    values = Enum.map(item.choices, &elem(&1, 0))
    at = Enum.find_index(values, &(&1 == value(item, settings))) || 0
    write(settings, item.path, Enum.at(values, Integer.mod(at + direction, length(values))))
  end

  def change(%__MODULE__{kind: :slider} = item, settings, direction) do
    stepped = value(item, settings) + direction * item.step
    write(settings, item.path, stepped |> snap(item) |> max(item.low) |> min(item.high))
  end

  def change(%__MODULE__{}, settings, _direction), do: settings

  @doc "`settings` with `keys` bound to the binding item's action, replacing what it had."
  @spec bind(t(), map(), [term()]) :: map()
  def bind(%__MODULE__{kind: :binding, action: action}, settings, keys),
    do: Map.update(settings, :bindings, %{action => keys}, &Map.put(&1, action, keys))

  @doc "`settings` with `text` at the text item's path."
  @spec put_text(t(), map(), String.t()) :: map()
  def put_text(%__MODULE__{kind: :text, path: path}, settings, text),
    do: write(settings, path, text)

  @doc "A key spec, as `Cauldron.Input.spec_of/1` gives it, as a word."
  @spec key_name(term()) :: String.t()
  def key_name(:" "), do: "SPACE"
  def key_name({:mouse, :wheel_up}), do: "WHEEL UP"
  def key_name({:mouse, :wheel_down}), do: "WHEEL DOWN"
  def key_name({:mouse, button}), do: "MOUSE #{key_name(button)}"
  def key_name({key, mods}), do: Enum.map_join(mods ++ [key], "+", &key_name/1)
  def key_name(key) when is_atom(key), do: key |> Atom.to_string() |> String.upcase()

  defp snap(number, %{low: low, step: step}) when is_float(number) or is_float(step),
    do: Float.round(low + Float.round((number - low) / step) * step, 6)

  defp snap(number, _item), do: number

  defp read(settings, [key], default), do: Map.get(settings, key, default)

  defp read(settings, [key | rest], default),
    do: settings |> Map.get(key, %{}) |> read(rest, default)

  defp write(settings, [key], value), do: Map.put(settings, key, value)

  defp write(settings, [key | rest], value),
    do: Map.put(settings, key, settings |> Map.get(key, %{}) |> write(rest, value))
end
