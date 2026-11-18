defmodule Cauldron.Net.Keys do
  @moduledoc """
  Keys between a browser and `Cauldron.Input`: a browser's `KeyboardEvent.key` and
  `KeyboardEvent.code` read as the key `Cauldron.Input` names, and the other way, for a
  program that sends keys as a browser does.

      Cauldron.Net.Keys.input_key("ArrowLeft")
      #=> :left
      Cauldron.Net.Keys.input_key("Shift", "ShiftLeft")
      #=> :left_shift
      Cauldron.Net.Keys.browser_key(:" ")
      #=> " "

  Named keys, `F1` to `F24`, printable ASCII and the modifier keys by side are known;
  anything else is `nil`. A modifier key is named by its side, as a terminal names it:
  `:left_shift`, `:right_control`, `:left_alt`, `:left_super` (the Windows or Command
  key) and so on.
  """

  @input_names %{
    "Escape" => :escape,
    "Enter" => :enter,
    "Tab" => :tab,
    "Backspace" => :backspace,
    "Delete" => :delete,
    "Insert" => :insert,
    "Home" => :home,
    "End" => :end,
    "PageUp" => :page_up,
    "PageDown" => :page_down,
    "ArrowLeft" => :left,
    "ArrowRight" => :right,
    "ArrowUp" => :up,
    "ArrowDown" => :down,
    " " => :" "
  }
  @printable for char <- ?!..?~, into: %{}, do: {<<char>>, String.to_atom(<<char>>)}
  @functions for n <- 1..24, into: %{}, do: {"F#{n}", String.to_atom("f#{n}")}
  @side_keys %{
    "ShiftLeft" => :left_shift,
    "ShiftRight" => :right_shift,
    "ControlLeft" => :left_control,
    "ControlRight" => :right_control,
    "AltLeft" => :left_alt,
    "AltRight" => :right_alt,
    "MetaLeft" => :left_super,
    "MetaRight" => :right_super
  }
  @side_names %{
    "ShiftLeft" => "Shift",
    "ShiftRight" => "Shift",
    "ControlLeft" => "Control",
    "ControlRight" => "Control",
    "AltLeft" => "Alt",
    "AltRight" => "Alt",
    "MetaLeft" => "Meta",
    "MetaRight" => "Meta"
  }
  @side_codes Map.new(@side_keys, fn {code, atom} -> {atom, code} end)
  @mods %{"ctrl" => :ctrl, "shift" => :shift, "alt" => :alt, "meta" => :meta}
  @browser_names Map.new(@input_names, fn {name, atom} -> {atom, name} end)
                 |> Map.merge(Map.new(@printable, fn {name, atom} -> {atom, name} end))
                 |> Map.merge(Map.new(@functions, fn {name, atom} -> {atom, name} end))

  @doc """
  A browser's `KeyboardEvent.key`, with its `KeyboardEvent.code` when the browser gave
  one, as `Cauldron.Input` names the key, or `nil`. The code names a modifier key's
  side; every other key is read from `key`.
  """
  @spec input_key(String.t(), String.t() | nil) :: atom() | nil
  def input_key(key, code \\ nil),
    do:
      Map.get(@side_keys, code) || Map.get(@input_names, key) || Map.get(@printable, key) ||
        Map.get(@functions, key)

  @doc "The `KeyboardEvent.key` a browser gives for a key `Cauldron.Input` names, or `nil`: `input_key/2` the other way."
  @spec browser_key(atom()) :: String.t() | nil
  def browser_key(key) do
    case Map.fetch(@side_codes, key) do
      {:ok, code} -> Map.fetch!(@side_names, code)
      :error -> Map.get(@browser_names, key)
    end
  end

  @doc "The `KeyboardEvent.code` a browser gives for a modifier key `Cauldron.Input` names by its side, or `nil` for any other key."
  @spec browser_code(atom()) :: String.t() | nil
  def browser_code(key), do: Map.get(@side_codes, key)

  @doc "Modifier names from a browser (`ctrl`, `shift`, `alt`, `meta`) as atoms; others are dropped."
  @spec input_mods(term()) :: [atom()]
  def input_mods(mods) when is_list(mods),
    do: for(mod <- mods, atom = Map.get(@mods, mod), atom != nil, do: atom)

  def input_mods(_mods), do: []
end
