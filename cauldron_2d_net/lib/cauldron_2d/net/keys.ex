defmodule Cauldron2D.Net.Keys do
  @moduledoc """
  A game's keymap as a browser reads it: `Cauldron2D.Input` key specs become
  `KeyboardEvent.code` names, and mouse buttons the button numbers `cauldron.js` takes.

      Cauldron2D.Net.Keys.browser_keymap(%{left: [:a, :left], fire: [:" ", {:mouse, :left}]})
      #=> %{"KeyA" => "left", "ArrowLeft" => "left", "Space" => "fire", "mouse" => %{"0" => "fire"}}

  A key with no browser code is left out.

  `browser_padmap/1` does the same for a `Cauldron2D.Input.Pad` padmap: buttons by
  their wire names to the actions they hold, and each direction of an axis to its.

      Cauldron2D.Net.Keys.browser_padmap(%{left: [:dpad_left, {:axis, :left_x, :neg}]})
      #=> %{"buttons" => %{"dpad_left" => ["left"]}, "axes" => %{"left_x" => %{"neg" => ["left"]}}}
  """

  alias Cauldron2D.Input.Pad

  @names %{
    left: "ArrowLeft",
    right: "ArrowRight",
    up: "ArrowUp",
    down: "ArrowDown",
    " ": "Space",
    enter: "Enter",
    escape: "Escape",
    tab: "Tab",
    backspace: "Backspace",
    delete: "Delete",
    home: "Home",
    end: "End",
    page_up: "PageUp",
    page_down: "PageDown",
    insert: "Insert",
    left_shift: "ShiftLeft",
    right_shift: "ShiftRight",
    left_ctrl: "ControlLeft",
    right_ctrl: "ControlRight",
    left_alt: "AltLeft",
    right_alt: "AltRight",
    "[": "BracketLeft",
    "]": "BracketRight",
    ";": "Semicolon",
    "'": "Quote",
    ",": "Comma",
    .: "Period",
    /: "Slash",
    \\: "Backslash",
    -: "Minus",
    =: "Equal",
    "`": "Backquote"
  }

  @buttons %{left: "0", middle: "1", right: "2"}

  @doc "The browser's name for a key spec, or `nil` when it has none."
  @spec code(Cauldron2D.Input.key_spec()) :: String.t() | {:mouse, String.t()} | nil
  def code({:mouse, button}), do: {:mouse, Map.fetch!(@buttons, button)}
  def code({key, _mods}), do: code(key)

  def code(key) when is_atom(key) do
    case Map.fetch(@names, key) do
      {:ok, name} -> name
      :error -> named(Atom.to_string(key))
    end
  end

  defp named(<<char>>) when char in ?a..?z, do: "Key" <> String.upcase(<<char>>)
  defp named(<<char>>) when char in ?A..?Z, do: "Key" <> <<char>>
  defp named(<<char>>) when char in ?0..?9, do: "Digit" <> <<char>>

  defp named("f" <> number) do
    case Integer.parse(number) do
      {n, ""} when n in 1..24 -> "F#{n}"
      _other -> nil
    end
  end

  defp named(_other), do: nil

  @doc "A keymap as `cauldron.js` takes it."
  @spec browser_keymap(Cauldron2D.Input.keymap()) :: map()
  def browser_keymap(keymap) do
    for {action, keys} <- keymap, key <- keys, code = code(key), code != nil, reduce: %{} do
      acc -> bind(acc, code, Atom.to_string(action))
    end
  end

  @doc "A padmap as `cauldron.js` takes it: `buttons` and `axes` to actions, `aim` naming the stick that aims when one does, and `push` what that stick holds when pushed far, as `Cauldron2D.Input.Pad.push/1` gives it."
  @spec browser_padmap(Cauldron2D.Input.Pad.padmap()) :: map()
  def browser_padmap(padmap) do
    for {action, controls} <- padmap,
        control <- controls,
        reduce: %{"buttons" => %{}, "axes" => %{}} do
      acc -> bind_control(acc, control, Atom.to_string(action))
    end
  end

  defp bind_control(acc, {:stick, side}, "aim"), do: Map.put(acc, "aim", Atom.to_string(side))

  defp bind_control(acc, {:stick, side, options}, "aim") do
    case Pad.push(Pad.new(%{aim: [{:stick, side, options}]})) do
      nil ->
        Map.put(acc, "aim", Atom.to_string(side))

      push ->
        acc
        |> Map.put("aim", Atom.to_string(side))
        |> Map.put(
          "push",
          %{push | action: Atom.to_string(push.action)}
          |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
        )
    end
  end

  defp bind_control(acc, {:stick, _side}, _action), do: acc
  defp bind_control(acc, {:stick, _side, _options}, _action), do: acc

  defp bind_control(acc, {:axis, axis, direction}, action) do
    update_in(
      acc,
      ["axes", Access.key(Atom.to_string(axis), %{}), Access.key(Atom.to_string(direction), [])],
      &(&1 ++ [action])
    )
  end

  defp bind_control(acc, button, action) when is_atom(button) do
    update_in(acc, ["buttons", Access.key(Atom.to_string(button), [])], &(&1 ++ [action]))
  end

  defp bind(acc, {:mouse, button}, action),
    do: Map.update(acc, "mouse", %{button => action}, &Map.put(&1, button, action))

  defp bind(acc, name, action), do: Map.put(acc, name, action)
end
