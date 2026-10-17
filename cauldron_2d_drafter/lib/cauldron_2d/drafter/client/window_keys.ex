defmodule Cauldron2D.Drafter.Client.WindowKeys do
  @moduledoc """
  Turns a `CauldronGPU` window's key events into the events a drafter app gets from a
  terminal speaking the kitty keyboard protocol with key releases
  (`Drafter.Terminal.KittyKeyboard`): a press is the legacy `{:key, ...}` event followed
  by `{:key_down, key, modifiers}`, a repeat the legacy event alone, a release
  `{:key_up, key, modifiers}`. Shifted glyphs are those of a US keyboard.

      iex> alias Cauldron2D.Drafter.Client.WindowKeys
      iex> WindowKeys.events({:key, :down, :a, false}, [:shift])
      [{:key, :A}, {:key_down, :a, [:shift]}]
      iex> WindowKeys.events({:key, :up, :return, false}, [])
      [{:key_up, :enter, []}]
  """

  @type modifier :: :ctrl | :alt | :shift
  @type window_event :: {:key, :down | :up, atom(), boolean()}

  @renamed %{
    return: :enter,
    keypad_enter: :kp_enter,
    space: :" ",
    pageup: :page_up,
    pagedown: :page_down,
    left_ctrl: :left_control,
    right_ctrl: :right_control,
    left_gui: :left_super,
    right_gui: :right_super,
    capslock: :caps_lock,
    numlockclear: :num_lock,
    scrolllock: :scroll_lock,
    printscreen: :print_screen,
    keypad_0: :kp_0,
    keypad_1: :kp_1,
    keypad_2: :kp_2,
    keypad_3: :kp_3,
    keypad_4: :kp_4,
    keypad_5: :kp_5,
    keypad_6: :kp_6,
    keypad_7: :kp_7,
    keypad_8: :kp_8,
    keypad_9: :kp_9,
    keypad_period: :kp_decimal,
    "keypad_/": :kp_divide,
    "keypad_*": :kp_multiply,
    "keypad_-": :kp_subtract,
    "keypad_+": :kp_add,
    "keypad_=": :kp_equal
  }

  @modifiers %{
    left_shift: :shift,
    right_shift: :shift,
    left_ctrl: :ctrl,
    right_ctrl: :ctrl,
    left_alt: :alt,
    right_alt: :alt
  }

  @shifted Map.new(
             Enum.zip(
               String.graphemes("1234567890-=[]\\;'`,./"),
               String.graphemes("!@\#$%^&*()_+{}|:\"~<>?")
             )
           )

  @named ~w(escape enter tab backspace up down left right home end insert delete page_up page_down)a ++
           for(n <- 1..24, do: :"f#{n}")

  @doc "The drafter events for one window key event with `modifiers` held."
  @spec events(window_event(), [modifier()]) :: [tuple()]
  def events({:key, :up, name, _repeat?}, modifiers), do: [{:key_up, key(name), modifiers}]

  def events({:key, :down, name, true}, modifiers), do: legacy(key(name), modifiers)

  def events({:key, :down, name, false}, modifiers) do
    key = key(name)
    legacy(key, modifiers) ++ [{:key_down, key, modifiers}]
  end

  @doc "The modifiers held after `event`, from those held before it, in the order `[:ctrl, :alt, :shift]`."
  @spec modifiers(window_event(), [modifier()]) :: [modifier()]
  def modifiers({:key, direction, name, _repeat?}, held) do
    case Map.get(@modifiers, name) do
      nil -> held
      modifier -> ordered(change(held, modifier, direction))
    end
  end

  defp change(held, modifier, :down), do: [modifier | held]
  defp change(held, modifier, :up), do: List.delete(held, modifier)

  defp ordered(held), do: for(modifier <- [:ctrl, :alt, :shift], modifier in held, do: modifier)

  defp key(name), do: Map.get(@renamed, name, name)

  defp legacy(key, modifiers) when key in @named, do: [named(key, modifiers)]

  defp legacy(key, modifiers) do
    case Atom.to_string(key) do
      <<glyph::utf8>> -> [glyph_event(<<glyph::utf8>>, modifiers)]
      _no_glyph -> []
    end
  end

  defp named(key, []), do: {:key, key}
  defp named(key, modifiers), do: {:key, key, modifiers}

  defp glyph_event(glyph, modifiers) do
    cond do
      :ctrl in modifiers or :alt in modifiers -> {:key, String.to_atom(glyph), modifiers}
      :shift in modifiers -> {:key, String.to_atom(shifted(glyph))}
      true -> {:key, String.to_atom(glyph)}
    end
  end

  defp shifted(<<letter>>) when letter in ?a..?z, do: <<letter - 32>>
  defp shifted(glyph), do: Map.get(@shifted, glyph, glyph)
end
