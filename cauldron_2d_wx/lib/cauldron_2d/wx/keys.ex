defmodule Cauldron2D.Wx.Keys do
  @moduledoc """
  Keys between wx and `Cauldron.Input`: a key spec as the wx key code that presses it
  (`code/1`, for a game's own page keys), and a wx key code as the key `Cauldron.Input`
  names (`input_key/1`, what the window sends a world).

      Cauldron2D.Wx.Keys.code(:left)
      #=> 314
      Cauldron2D.Wx.Keys.input_key(?A)
      #=> :a
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
    left_control: 308,
    right_control: 308,
    left_alt: 307,
    right_alt: 307
  }

  @f1 340

  @doc "The wx key code for a key spec, `{:mouse, button}` for a button, or `nil` when it has none."
  @spec code(Cauldron.Input.key_spec()) :: integer() | {:mouse, atom()} | nil
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

  @input_names Map.new(@names, fn {atom, code} -> {code, atom} end)
               |> Map.merge(%{306 => :left_shift, 307 => :left_alt, 308 => :left_control})
  @printable for char <- ?!..?~,
                 char not in ?A..?Z,
                 into: %{},
                 do: {char, String.to_atom(<<char>>)}
  @functions for n <- 1..24, into: %{}, do: {@f1 + n - 1, String.to_atom("f#{n}")}
  @letters for char <- ?A..?Z, into: %{}, do: {char, String.to_atom(String.downcase(<<char>>))}

  @doc """
  A wx key code as `Cauldron.Input` names the key, or `nil`: the named keys, `F1` to
  `F24`, letters (wx gives them upper case) as lower-case letters, and other printable
  ASCII as itself.
  """
  @spec input_key(integer()) :: atom() | nil
  def input_key(code),
    do:
      Map.get(@input_names, code) || Map.get(@letters, code) || Map.get(@printable, code) ||
        Map.get(@functions, code)
end
