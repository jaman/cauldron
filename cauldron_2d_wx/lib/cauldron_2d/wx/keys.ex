defmodule Cauldron2D.Wx.Keys do
  @moduledoc """
  A game's keymap as a wx window reads it: `Cauldron2D.Input` key specs become wx key
  codes, and mouse buttons stay `{:mouse, button}` as `Cauldron2D.Wx.Input` takes them.

      Cauldron2D.Wx.Keys.wx_keymap(%{left: [:a, :left], fire: [:" ", {:mouse, :left}]})
      #=> %{?A => :left, 314 => :left, 32 => :fire, {:mouse, :left} => :fire}

  A key with no wx code is left out.
  """

  @names %{
    " ": 32,
    enter: 13,
    escape: 27,
    tab: 9,
    backspace: 8,
    delete: 127,
    left: 314,
    up: 315,
    right: 316,
    down: 317,
    home: 313,
    end: 312,
    page_up: 366,
    page_down: 367,
    insert: 322,
    left_shift: 306,
    right_shift: 306,
    left_ctrl: 308,
    right_ctrl: 308,
    left_alt: 307,
    right_alt: 307
  }

  @f1 340

  @doc "The wx key code for a key spec, `{:mouse, button}` for a button, or `nil` when it has none."
  @spec code(Cauldron2D.Input.key_spec()) :: integer() | {:mouse, atom()} | nil
  def code({:mouse, button}), do: {:mouse, button}
  def code({key, _mods}), do: code(key)

  def code(key) when is_atom(key) do
    case Map.fetch(@names, key) do
      {:ok, code} -> code
      :error -> named(Atom.to_string(key))
    end
  end

  defp named(<<char>>) when char in ?a..?z, do: char - 32

  defp named(<<char>>)
       when char in ?A..?Z or char in ?0..?9 or char in ?!..?/ or char in ?:..?@ or char in ?[..?` or
              char in ?{..?~,
       do: char

  defp named("f" <> number) do
    case Integer.parse(number) do
      {n, ""} when n in 1..24 -> @f1 + n - 1
      _other -> nil
    end
  end

  defp named(_other), do: nil

  @doc "A keymap as `Cauldron2D.Wx.Input.new/2` takes it."
  @spec wx_keymap(Cauldron2D.Input.keymap()) :: map()
  def wx_keymap(keymap) do
    for {action, keys} <- keymap,
        key <- keys,
        code = code(key),
        code != nil,
        into: %{},
        do: {code, action}
  end
end
